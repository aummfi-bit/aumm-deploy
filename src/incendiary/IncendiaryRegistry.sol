// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IIncendiaryRegistry} from "./IIncendiaryRegistry.sol";
import {SwapAndDepositToBodensee} from "../gauge/SwapAndDepositToBodensee.sol";
import {IGaugeRegistry} from "../ccb/IGaugeRegistry.sol";
import {IAuMM} from "../token/IAuMM.sol";
import {AureumTime} from "../lib/AureumTime.sol";
import {IVaultExplorer} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import {IWeightedPool} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import {PoolData} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {FixedPoint} from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IncendiaryRegistry — Stage L concrete producer for the canonical F-2 Incendiary Boost
/// @notice Sells 14-day directed AuMM emission boosts funded by skimming the existing fixed block
///         emission (F-7 Step 1), never by minting new supply. A buyer deposits svZCHF or sUSDS
///         one-sided into der Bodensee and receives a supplementary per-block emission stream over
///         one or more epochs for a gauged pool of their choice.
/// @dev The concrete implementation behind the H-D29 `IIncendiaryRegistry` forward-dep. L2.1a is the
///      compiling skeleton (L-D16): immutables + constructor + the two `IIncendiaryRegistry` views
///      stubbed `return 0` (concrete + deployable, the H-D21 stub precedent). The price EMA (L3),
///      purchase entry + valuation (L4), placement + cap + crystallize (L5), and the real view bodies
///      (L6) land in subsequent sub-steps. Constants + settled storage land at L2.1b; the crystallize
///      cumulative-cache slots are deferred to L5.3 (L-D17). Until governance calls
///      `setIncendiaryRegistry`, the distributor defaults to `address(0)` (zero skim) per H-D29.
contract IncendiaryRegistry is IIncendiaryRegistry {
    using FixedPoint for uint256;

    /* ---------- Constants ---------- */

    /// @notice EMA smoothing numerator — `EMASampler` constants verbatim (L-D5); α = 2/61 ≈ 60-day half-life.
    uint256 public constant EMA_ALPHA_NUMERATOR = 2;

    /// @notice EMA smoothing denominator — `EMASampler` constants verbatim (L-D5).
    uint256 public constant EMA_ALPHA_DENOMINATOR = 61;

    /// @notice Blocks a rail's EMA must season before it may price a purchase — 60 days at `BLOCKS_PER_DAY` (L-D5).
    uint256 public constant EMA_MATURITY_BLOCKS = 432_000;

    /// @notice Aggregate per-epoch boost cap — 15% of the epoch's emission integral (L-D6).
    uint256 public constant BOOST_CAP_BPS = 1_500;

    /// @notice Anti-gaming valuation haircut — the 5% never skimmed, retained in `Remaining` for other pools (L-D4).
    uint256 public constant HAIRCUT_BPS = 500;

    /* ---------- Immutables ---------- */

    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching the sibling AureumGovernance /
    // EmissionDistributor declarations and the upstream-forked files.
    // slither-disable-next-line naming-convention

    /// @notice der Bodensee deposit channel — receives the svZCHF / sUSDS deposit and routes it via
    ///         `donate` (G-D21, zero-BPT DONATION) per L-D2.
    SwapAndDepositToBodensee public immutable BODENSEE_CHANNEL;

    /// @notice der Bodensee 40/30/30 WeightedPool address — the spot-rate read venue (L-D11).
    address public immutable BODENSEE_POOL;

    /// @notice Read-only Balancer V3 vault explorer — `getPoolData(BODENSEE_POOL).balancesLiveScaled18`
    ///         feeds the L-D11 direct spot rate.
    IVaultExplorer public immutable VAULT_EXPLORER;

    /// @notice AuMM token — `blockEmissionRate` feeds the L-D6 epoch-emission-integral cap basis (L5.1)
    ///         and denominates the entitlement in AuMM-wei.
    IAuMM public immutable AUMM;

    /// @notice svZCHF pay-token rail (L-D2).
    IERC20 public immutable SVZCHF;

    /// @notice sUSDS pay-token rail (L-D2).
    IERC20 public immutable SUSDS;

    /// @notice Gauge registry — the L-D10 purchase-time gauge gate (`isGaugeApproved(pool)`).
    IGaugeRegistry public immutable GAUGE_REGISTRY;

    /// @notice Protocol genesis block — the AureumTime epoch / era basis for placement and cap windows.
    uint256 public immutable GENESIS_BLOCK;

    /* ---------- Storage ---------- */

    /// @notice Per-rail price EMA state — the AuMM price in the pay token (stable-per-AuMM, L-D11); pricing
    ///         divides the deposit by `ema` (the L3.1 divide-direction gate). Mirrors `EMASampler`'s
    ///         three-field-per-key shape (L-D5 / L-D17).
    struct RailEMA {
        uint256 ema;
        uint256 lastSampleBlock;
        uint256 seedBlock;
    }

    /// @notice Price-EMA state keyed by pay-token rail (`SVZCHF` / `SUSDS`); `seedBlock == 0` ⇒ unseeded (L-D17).
    mapping(address => RailEMA) public railEMA;

    /// @notice Aggregate AuMM-wei boost allocated per epoch — the shared 15%-cap bucket (L-D6 / L-D17).
    mapping(uint256 => uint256) public epochSkimAllocated;

    /// @notice Per-(epoch, pool) AuMM-wei boost allocation — additive stacking delivery map (L-D9 / L-D17).
    mapping(uint256 => mapping(address => uint256)) public epochPoolSkim;

    /* ---------- Events ---------- */

    /// @notice Emitted on every successful `updateRailEMA` call (both seed and smoothed paths) (L-D19).
    /// @param payToken    The pay-token rail sampled (svZCHF / sUSDS).
    /// @param spot        The spot rate read from `_spotRate` for this update.
    /// @param newEMA      The post-update EMA (= `spot` on the seed path).
    /// @param blockNumber block.number at the update.
    event RailEMAUpdated(address indexed payToken, uint256 spot, uint256 newEMA, uint256 blockNumber);

    /* ---------- Errors ---------- */

    /// @notice A constructor address argument was the zero address.
    error ZeroAddress();

    /// @notice `_spotRate` could not resolve `token`'s index in der Bodensee's token set (L-D18).
    error TokenNotInPool(address token);

    /// @notice der Bodensee reported a zero scaled balance for `token`; a silent `divDown` zero would poison the EMA seed (L-D18).
    error ZeroSpotBalance(address token);

    /// @notice `updateRailEMA` called with a token that is not a configured pay-token rail (svZCHF / sUSDS) (L-D19).
    error UnknownRail(address rail);

    /// @notice `updateRailEMA` called before the once-per-`BLOCKS_PER_DAY` cadence permits (L-D19, `EMASampler` mirror).
    /// @param currentBlock block.number at the failed call.
    /// @param nextEligibleBlock The first block at which `updateRailEMA(payToken)` is callable.
    error TooEarly(uint256 currentBlock, uint256 nextEligibleBlock);

    /// @notice `_maturePrice` read a rail whose price EMA has not seasoned the 60-day `EMA_MATURITY_BLOCKS`
    ///         window — never seeded (`age == 0`) or still ramping (L-D19, F-04 gate).
    /// @param payToken The rail whose EMA is immature.
    /// @param age Blocks since the rail's EMA seed, 0 if never seeded.
    /// @param required The maturity threshold, `EMA_MATURITY_BLOCKS`.
    error EMANotMature(address payToken, uint256 age, uint256 required);

    /* ---------- Constructor ---------- */

    /// @notice Wires the eight immutables; ZeroAddress-guards the seven address-bearing arguments.
    /// @dev `genesisBlock_` is unguarded — deploy correctness is governance's responsibility, the
    ///      AureumGovernance / EmissionDistributor convention (L-D16).
    constructor(
        SwapAndDepositToBodensee bodenseeChannel_,
        address bodenseePool_,
        IVaultExplorer vaultExplorer_,
        IAuMM aumm_,
        IERC20 svzchf_,
        IERC20 susds_,
        IGaugeRegistry gaugeRegistry_,
        uint256 genesisBlock_
    ) {
        if (address(bodenseeChannel_) == address(0)) revert ZeroAddress();
        if (bodenseePool_ == address(0)) revert ZeroAddress();
        if (address(vaultExplorer_) == address(0)) revert ZeroAddress();
        if (address(aumm_) == address(0)) revert ZeroAddress();
        if (address(svzchf_) == address(0)) revert ZeroAddress();
        if (address(susds_) == address(0)) revert ZeroAddress();
        if (address(gaugeRegistry_) == address(0)) revert ZeroAddress();

        BODENSEE_CHANNEL = bodenseeChannel_;
        BODENSEE_POOL = bodenseePool_;
        VAULT_EXPLORER = vaultExplorer_;
        AUMM = aumm_;
        SVZCHF = svzchf_;
        SUSDS = susds_;
        GAUGE_REGISTRY = gaugeRegistry_;
        GENESIS_BLOCK = genesisBlock_;
    }

    /* ---------- IIncendiaryRegistry views (L2.1a stubs; real bodies at L6) ---------- */

    /// @inheritdoc IIncendiaryRegistry
    /// @dev L2.1a stub returning 0; the O(1) epoch-bucketed body lands at L6.1. `pure` here is the
    ///      zero-warning stub form — widens to `view` at L6.1 when it reads the cumulative buckets.
    function integratedSkim(uint256, uint256) external pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc IIncendiaryRegistry
    /// @dev L2.1a stub returning 0; the O(1) per-pool body lands at L6.2. `pure` here is the
    ///      zero-warning stub form — widens to `view` at L6.2 when it reads the per-pool buckets.
    function boostIntegral(address, uint256, uint256) external pure override returns (uint256) {
        return 0;
    }

    /* ---------- Price EMA sampler (L3.2 / L-D19) ---------- */

    /// @notice Sample der Bodensee's AuMM/`payToken` spot and fold it into the rail's 60-day price EMA.
    /// @dev L-D19, the `EMASampler.updateEMA` mirror (`EMASampler.sol:122-154`). Permissionless — anyone
    ///      may poke once the cadence permits. Order: (1) `UnknownRail` unless `payToken` is a configured
    ///      rail; (2) `TooEarly` unless `block.number >= lastSampleBlock + BLOCKS_PER_DAY`; (3) read
    ///      `_spotRate`; (4) seed (`seedBlock == 0` ⇒ `ema = spot`, write `seedBlock`) or smooth
    ///      `(2·spot + 59·ema) / 61` — plain integer arithmetic, NOT `divDown` (the `/61` is a weighted-mean
    ///      divisor, not a fixed-point scale). Single-step, no catch-up: a multi-day gap applies exactly one
    ///      smoothing step and `lastSampleBlock` advances to the call block (OQ-5a-bis). Maturity is gated
    ///      separately at the read side (`_maturePrice`, L3.2b), not here — sampling builds maturity.
    /// @param payToken The pay-token rail to sample (svZCHF / sUSDS).
    /// @return newEMA The post-update rail EMA (= `spot` on the seed path).
    function updateRailEMA(address payToken) external returns (uint256 newEMA) {
        if (payToken != address(SVZCHF) && payToken != address(SUSDS)) revert UnknownRail(payToken);

        RailEMA storage rail = railEMA[payToken];
        uint256 nextEligible = rail.lastSampleBlock + AureumTime.BLOCKS_PER_DAY;
        if (block.number < nextEligible) revert TooEarly(block.number, nextEligible);

        uint256 spot = _spotRate(payToken);

        if (rail.seedBlock == 0) {
            newEMA = spot;
            rail.seedBlock = block.number;
        } else {
            newEMA =
                (EMA_ALPHA_NUMERATOR * spot + (EMA_ALPHA_DENOMINATOR - EMA_ALPHA_NUMERATOR) * rail.ema) /
                EMA_ALPHA_DENOMINATOR;
        }

        rail.ema = newEMA;
        rail.lastSampleBlock = block.number;

        emit RailEMAUpdated(payToken, spot, newEMA, block.number);
    }

    /// @notice The rail's mature 60-day price EMA, stable-per-AuMM per L-D17 — the price the L4.1
    ///         `buyBoost` valuation divides the deposit by; reverts unless seasoned 60 days.
    /// @dev L-D19. Mirrors the F-04 `VotingWeight._positionPower` gate (`VotingWeight.sol:134-138`) but
    ///      reverts rather than returning 0: unseeded (`seedBlock == 0`, age 0) or still-ramping
    ///      (`block.number - seedBlock < EMA_MATURITY_BLOCKS`) reverts `EMANotMature`, else returns
    ///      `rail.ema`. Internal-only, no public price view (L-D5) — maturity is built by `updateRailEMA`,
    ///      not here.
    /// @param payToken The pay-token rail (svZCHF / sUSDS) the price is denominated in.
    /// @return ema The mature 18-dec rail EMA, stable-per-AuMM.
    function _maturePrice(address payToken) internal view returns (uint256 ema) {
        RailEMA storage rail = railEMA[payToken];
        if (rail.seedBlock == 0) revert EMANotMature(payToken, 0, EMA_MATURITY_BLOCKS);
        uint256 age = block.number - rail.seedBlock;
        if (age < EMA_MATURITY_BLOCKS) revert EMANotMature(payToken, age, EMA_MATURITY_BLOCKS);
        ema = rail.ema;
    }

    /* ---------- Internal: spot-rate read (L3.1 / L-D18) ---------- */

    /// @notice Live der Bodensee spot of AuMM denominated in `payToken` — the per-sample input the
    ///         L-D5 60-day price EMA smooths (L3.2). Internal, no public view: the raw spot is never
    ///         priced (L-D5), so it cannot be mistaken for a callable price oracle.
    /// @dev L-D18. der Bodensee registers its three tokens address-sorted
    ///      (`DeployDerBodensee.s.sol:45-61`), so AuMM's and `payToken`'s positions are
    ///      deploy-address-dependent — resolved by identity-matching `getPoolData(BODENSEE_POOL).tokens[i]`
    ///      against the `AUMM` immutable and `payToken` (the `TVLOracle._venueRatio` pattern), never
    ///      hardcoded. One `getPoolData` supplies `tokens` + `balancesLiveScaled18` (the rate-scaled
    ///      leg — Bodensee stables are `WITH_RATE`); one `getNormalizedWeights()` supplies the
    ///      index-aligned weights. Formula `(bal_X · w_A).divDown(bal_A · w_X)` → 18-dec X-per-AuMM;
    ///      `FixedPoint.divDown(a, b) = a · 1e18 / b` supplies the `· 1e18`, so the receiver is not
    ///      pre-multiplied. Reverts `TokenNotInPool` (index unresolved) / `ZeroSpotBalance` (zero balance).
    /// @param payToken The pay-token rail (svZCHF / sUSDS) the spot is denominated in.
    /// @return spotRate 18-dec fixed-point X-per-AuMM (stable-per-AuMM, L-D17).
    function _spotRate(address payToken) internal view returns (uint256 spotRate) {
        PoolData memory data = VAULT_EXPLORER.getPoolData(BODENSEE_POOL);
        uint256[] memory weights = IWeightedPool(BODENSEE_POOL).getNormalizedWeights();

        uint256 iA = type(uint256).max;
        uint256 iX = type(uint256).max;
        address aumm = address(AUMM);
        for (uint256 i = 0; i < data.tokens.length; i++) {
            address t = address(data.tokens[i]);
            if (t == aumm) {
                iA = i;
            } else if (t == payToken) {
                iX = i;
            }
        }
        if (iA == type(uint256).max) revert TokenNotInPool(aumm);
        if (iX == type(uint256).max) revert TokenNotInPool(payToken);

        uint256 balA = data.balancesLiveScaled18[iA];
        uint256 balX = data.balancesLiveScaled18[iX];
        if (balA == 0) revert ZeroSpotBalance(aumm);
        if (balX == 0) revert ZeroSpotBalance(payToken);

        spotRate = (balX * weights[iA]).divDown(balA * weights[iX]);
    }
}
