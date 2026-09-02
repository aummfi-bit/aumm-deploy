// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { IVotingWeight } from "./IVotingWeight.sol";
import { IEMASampler } from "../ccb/IEMASampler.sol";
import { IGaugeRegistry } from "../ccb/IGaugeRegistry.sol";
import { IMiliariumRegistry } from "../ccb/IMiliariumRegistry.sol";
import { IEmissionDistributor } from "../emission/IEmissionDistributor.sol";
import { AureumTime } from "../lib/AureumTime.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/**
 * @title VotingWeight
 * @notice Value-weighted governance reader per K-D5 — a stateful poke-accumulator delivering an exact
 *         veto fraction (`vetoSupport <= totalSupply` by construction). Implements `IVotingWeight`
 *         (the I9.1 stub per I-D17) consumed by `VaultClassRegistry.vetoProposal`.
 * @dev F-9 pool-aggregate power `tvlEMA(pool)^(1/4 in Era 0, 1/3 in Era 1+) * (userLP / poolTotalLP) * min(time, ON_RAMP)/ON_RAMP` over the
 *      EmissionDistributor recorder clock (OQ-25 anti-flash-loan — hook-recorded shares, never spot BPT; F-04 — the 60-day TVL EMA, never spot tvl; F-05 — that EMA must also be fresh, refreshed within one epoch, never a long-stale seed;
 *      F-02 — the root applies to the pool aggregate and the holder leg is linear, so weight is invariant under splitting a position across wallets). `governanceWeight`
 *      and `totalSupply` are O(1) views over two checkpoints (`_holderWeight` / `_totalQualifiedWeight`);
 *      permissionless `poke(holder)` recomputes the holder aggregate over the gauge-filtered Miliarium
 *      enumeration and applies the signed delta (F12/F13). The exact-fraction invariant holds because
 *      `_totalQualifiedWeight == sum of _holderWeight[*]` and distinct voters hold disjoint positions.
 *
 *      F-06 — every `poke` also pushes block-keyed checkpoints of the holder weight and the running total
 *      (OZ `Checkpoints.Trace208`); `getPastVotes` / `getPastTotalSupply` read frozen weight at a past block
 *      for `AureumGovernance` snapshot voting (numerator ≤ denominator by construction).
 */
contract VotingWeight is IVotingWeight {
    using FixedPoint for uint256;
    using Checkpoints for Checkpoints.Trace208;
    using SafeCast for uint256;
    /// @notice Era 0 governance-power exponent — F-9 1/4 root (18-dec fixed-point).
    uint256 internal constant ERA0_EXPONENT = 0.25e18;
    /// @notice Era 1+ governance-power exponent — F-9 1/3 root (18-dec fixed-point).
    uint256 internal constant ERA1_PLUS_EXPONENT = FixedPoint.ONE / 3;
    /// @notice A pool's TVL EMA must have been seeding for 60 days (matching the EMASampler 60-day window) before the pool confers governance weight — F-04 anti-spot-pump floor.
    uint256 internal constant EMA_MATURITY_BLOCKS = 60 * AureumTime.BLOCKS_PER_DAY;
    /// @notice A pool's TVL EMA must have been refreshed within EMA_STALENESS_BLOCKS (14 days, one epoch) for the pool to confer governance weight — F-05 anti-stale-seed floor: EMA_MATURITY_BLOCKS gates seed age, this gates seed freshness, so a single ancient seed never confers weight on a long-dormant pool.
    uint256 internal constant EMA_STALENESS_BLOCKS = AureumTime.BLOCKS_PER_EPOCH;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    IEMASampler public immutable EMA_SAMPLER;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    IGaugeRegistry public immutable GAUGE_REGISTRY;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    IEmissionDistributor public immutable RECORDER;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    IMiliariumRegistry public immutable REGISTRY;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    uint256 public immutable GENESIS_BLOCK;
    /// @notice Per-holder checkpointed governance weight — sum of `_positionPower` at the holder's last `poke`.
    mapping(address => uint256) internal _holderWeight;
    /// @notice Running sum of every holder's checkpoint — the veto-threshold denominator per I-D17.
    uint256 internal _totalQualifiedWeight;
    /// @notice Per-holder weight history — Governor-style block-keyed checkpoints for snapshot voting (F-06). Pushed on every `poke` delta; read via `getPastVotes`.
    mapping(address => Checkpoints.Trace208) internal _holderWeightHistory;
    /// @notice Total-weight history — the snapshot quorum denominator for `AureumGovernance` (F-06). Pushed on every `poke` delta; read via `getPastTotalSupply`.
    Checkpoints.Trace208 internal _totalQualifiedWeightHistory;
    /// @notice Reverts when a zero address is supplied for an immutable dependency.
    error ZeroAddress();
    /// @notice Reverts when a zero genesis block is supplied — block 0 is not a valid genesis.
    error ZeroGenesisBlock();
    /// @notice Reverts when `getPastVotes` / `getPastTotalSupply` is queried for the current or a future block — the checkpoint is not yet final (Governor `getPast*` semantics).
    error FutureLookup(uint256 blockNumber);
    /// @notice Emitted when `poke` refreshes a holder's checkpoint.
    /// @param holder The holder repoked (indexed).
    /// @param oldWeight The prior checkpoint.
    /// @param newWeight The recomputed checkpoint.
    event WeightPoked(address indexed holder, uint256 oldWeight, uint256 newWeight);
    constructor(
        IEMASampler emaSampler_,
        IGaugeRegistry gaugeRegistry_,
        IEmissionDistributor recorder_,
        IMiliariumRegistry registry_,
        uint256 genesisBlock_
    ) {
        if (address(emaSampler_) == address(0)) revert ZeroAddress();
        if (address(gaugeRegistry_) == address(0)) revert ZeroAddress();
        if (address(recorder_) == address(0)) revert ZeroAddress();
        if (address(registry_) == address(0)) revert ZeroAddress();
        if (genesisBlock_ == 0) revert ZeroGenesisBlock();
        EMA_SAMPLER = emaSampler_;
        GAUGE_REGISTRY = gaugeRegistry_;
        RECORDER = recorder_;
        REGISTRY = registry_;
        GENESIS_BLOCK = genesisBlock_;
    }
    /// @inheritdoc IVotingWeight
    function governanceWeight(address holder) external view override returns (uint256) {
        return _holderWeight[holder];
    }
    /// @inheritdoc IVotingWeight
    function totalSupply() external view override returns (uint256) {
        return _totalQualifiedWeight;
    }
    /// @inheritdoc IVotingWeight
    function getPastVotes(address holder, uint256 blockNumber) external view override returns (uint256) {
        if (blockNumber >= block.number) revert FutureLookup(blockNumber);
        return _holderWeightHistory[holder].upperLookup(blockNumber.toUint48());
    }
    /// @inheritdoc IVotingWeight
    function getPastTotalSupply(uint256 blockNumber) external view override returns (uint256) {
        if (blockNumber >= block.number) revert FutureLookup(blockNumber);
        return _totalQualifiedWeightHistory.upperLookup(blockNumber.toUint48());
    }
    /// @notice Permissionless refresh of `holder`'s checkpoint — recomputes the live aggregate over the
    ///         gauge-filtered Miliarium enumeration and applies the signed delta to both checkpoints.
    /// @dev F12/F13 signed-delta discipline via branch-on-sign with unsigned subtraction in each arm; no
    ///      underflow because `_totalQualifiedWeight >= _holderWeight[holder]` (the holder's checkpoint is
    ///      one summand of the total), so `_totalQualifiedWeight - (oldWeight - newWeight) >= newWeight`.
    ///      No-op short-circuit when the aggregate is unchanged. Anyone may poke any holder — this is how a
    ///      withdrawn holder's stale checkpoint is reset to its live zero (§viii withdrawal-reset) — and, via the F-17 / P-D18 `_positionPower` read-cap, how a holder who moved their BPT out-of-band is reset to their capped-live weight ahead of any recorder `syncPosition`. All
    ///      dependency calls are `view`, so there is no reentrancy surface and writes follow every read.
    /// @param holder The holder whose checkpoint is refreshed.
    function poke(address holder) external {
        uint256 newWeight = 0;
        bool anyStaleZero = false;
        uint256 count = REGISTRY.miliariumPoolsCount();
        for (uint256 i = 0; i < count; i++) {
            (uint256 power, bool staleZero) = _positionPower(REGISTRY.miliariumPoolAt(i), holder);
            newWeight += power;
            if (staleZero) anyStaleZero = true;
        }
        uint256 oldWeight = _holderWeight[holder];
        if (newWeight == oldWeight) return;
        // PP-D52 (ix), shape (A prime) — a reduction CAUSED BY a stale EMA is never banked into
        // checkpoint history: `getPastTotalSupply` reads that history, so a proposal snapshotted
        // inside the outage would stay Defeated even after the EMA recovered. Upward moves and
        // non-staleness reductions still write, so recovery and genuine withdrawal are unaffected
        // and a new qualifier can enter during an outage. INV-8 holds — this returns, never reverts.
        if (newWeight < oldWeight && anyStaleZero) return;
        _holderWeight[holder] = newWeight;
        if (newWeight > oldWeight) {
            _totalQualifiedWeight += newWeight - oldWeight;
        } else {
            _totalQualifiedWeight -= oldWeight - newWeight;
        }
        _holderWeightHistory[holder].push(block.number.toUint48(), newWeight.toUint208());
        _totalQualifiedWeightHistory.push(block.number.toUint48(), _totalQualifiedWeight.toUint208());
        emit WeightPoked(holder, oldWeight, newWeight);
    }
    /// @notice F-9 pool-aggregate governance power for `holder` in `pool` — live, gauge-gated.
    /// @dev (a) gauge gate — unapproved pools confer 0 (read-time per OQ-25); (b) EMA maturity + freshness — a pool whose TVL EMA has been seeding for fewer than EMA_MATURITY_BLOCKS (60 days), has never seeded, or was last refreshed more than EMA_STALENESS_BLOCKS (14 days) ago confers 0 (F-04 anti-spot-pump; F-05 anti-stale-seed); (c) clock from the recorder
    ///      `effectiveQualBlock` — 0 (no/withdrawn position) or sub-cliff time confers 0; (d) poolPower = `tvlEMA(pool)^exponent` with the F-9 era root (F-04 — the 60-day EMA, never spot tvl); (e) share = recorder
    ///      `min(userLP, live BPT balanceOf) / poolTotalLP` — the F-17 / P-D18 read-cap denies a phantom position (recorded userLP over live balance, from an out-of-band BPT move) any power, denominator left uncapped (heals via `syncPosition`), so the cap only under-counts (OQ-25); timeFactor = capped on-ramp fraction `min(timeInPool, ON_RAMP)/ON_RAMP`; (f) power =
    ///      poolPower * share * timeFactor — the holder leg is linear, so the position is split-invariant across wallets (F-02). Every
    ///      degenerate input (immature/never-seeded/stale EMA, zero LP, fully-moved capped LP, zero supply, zero EMA, dust share) short-circuits to 0 before `powDown`.
    /// @param pool The Miliarium pool.
    /// @param holder The holder.
    /// @return power The position's governance power (18-dec).
    /// @return staleZero True ONLY when the pool's TVL EMA is stale (PP-D52 (ix)); every other zero
    ///         this function returns is a legitimate absence and must still ratchet the checkpoint down.
    function _positionPower(address pool, address holder) internal view returns (uint256 power, bool staleZero) {
        if (!GAUGE_REGISTRY.isGaugeApproved(pool)) return (0, false);
        uint256 seedBlock = EMA_SAMPLER.emaSeedBlock(pool);
        if (seedBlock == 0) return (0, false);
        if (block.number - seedBlock < EMA_MATURITY_BLOCKS) return (0, false);
        // PP-D52 (ix) — this is the ONLY branch that sets `staleZero`. Every other zero below is a
        // legitimate absence (no gauge, immature EMA, no position, sub-cliff, capped LP, dust share)
        // and must keep ratcheting the checkpoint down; only a stale oracle is held.
        if (block.number - EMA_SAMPLER.lastEMAUpdateBlock(pool) > EMA_STALENESS_BLOCKS) return (0, true);
        uint256 eqb = RECORDER.effectiveQualBlock(pool, holder);
        if (eqb == 0) return (0, false);
        uint256 timeInPool = block.number - eqb;
        if (timeInPool < AureumTime.QUALIFICATION_PERIOD_BLOCKS) return (0, false);
        uint256 totalLP = RECORDER.poolTotalLP(pool);
        if (totalLP == 0) return (0, false);
        uint256 lp = RECORDER.userLP(pool, holder);
        // F-17 / P-D18 read-cap: cap the numerator at the holder's live BPT balance so a phantom position
        // (recorded userLP over balanceOf, from an out-of-band BPT move that skipped the recorder) confers no
        // governance power. Denominator (poolTotalLP) stays uncapped — it heals via
        // EmissionDistributor.syncPosition — so the cap only ever under-counts.
        uint256 held = IERC20(pool).balanceOf(holder);
        if (held < lp) lp = held;
        if (lp == 0) return (0, false);
        uint256 ema = EMA_SAMPLER.tvlEMA(pool);
        if (ema == 0) return (0, false);
        uint256 share = lp.divDown(totalLP);
        if (share == 0) return (0, false);
        uint256 cappedTime = timeInPool > AureumTime.ON_RAMP_PERIOD_BLOCKS
            ? AureumTime.ON_RAMP_PERIOD_BLOCKS
            : timeInPool;
        uint256 timeFactor = cappedTime.divDown(AureumTime.ON_RAMP_PERIOD_BLOCKS);
        uint256 exponent = block.number < AureumTime.firstHalvingBlock(GENESIS_BLOCK)
            ? ERA0_EXPONENT
            : ERA1_PLUS_EXPONENT;
        return (ema.powDown(exponent).mulDown(share).mulDown(timeFactor), false);
    }
}
