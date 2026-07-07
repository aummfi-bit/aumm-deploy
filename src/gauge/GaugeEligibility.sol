// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {IWeightedPool} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import {IBasePoolFactory} from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import {IGaugeEligibility} from "./IGaugeEligibility.sol";
import {IVaultClassRegistry} from "./IVaultClassRegistry.sol";
import {IEfficiencyOracle} from "./IEfficiencyOracle.sol";
import {ITVLOracle} from "../ccb/ITVLOracle.sol";

/**
 * @title GaugeEligibility
 * @notice Auto-gauge eligibility evaluator — 52% Quality Gate per **G-D8**, TVL floor per **OQ-G2**, pool-type whitelist per **G-D6**, F-10 efficiency tournament per **G-D3**, threshold transition events per **G-D5**.
 * @dev G2.3 — constructor body + `_compute52PctNumerator` (G-D8 + G-D10); G2.4 — `_checkEligibilityCriteria` (OQ-G2 + G-D6 + G-D15a); **G2.4-post** — F-D23 one-shot setter for `gaugeRegistry` + `onlyGaugeRegistry` modifier per **G-D22** (caller-restriction lock for `computeEpochSnapshot`; mirrors `VaultClassRegistry.setAuMT` at G1.12 literally). **G2.5-pre-2** — IEfficiencyOracle sibling import + 8-arg constructor + `efficiencyOracle` immutable + event ABI reshape (`tvlSma` → `numeratorSma` + `denominatorSma`) per **G-D23 (iii)** + `firstTournamentEpoch` storage per **G-D23 (v)**. **G2.5** — `computeEpochSnapshot` (carries `onlyGaugeRegistry`; reads `IEfficiencyOracle.efficiencyInputs` pair per **G-D23 (i)** with cold-start grace via `firstTournamentEpoch` per **G-D23 (v)**). **G2.6** — `evaluateEligibility` (per-pool gate via `_checkEligibilityCriteria` + latch write) + view bridges `isEligible` / `cohortOf` / `snapshotEpoch` + `is IGaugeEligibility` inheritance per **G-D5** / **T-I5**.
 */
contract GaugeEligibility is IGaugeEligibility {
    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice G-D15a singleton Balancer pool factory — no setter; set once at deploy.
    address public immutable approvedFactory;

    /// @notice `VaultClassRegistry` binding for 52% numerator admission lookups per G-D8.
    address public immutable vaultClassRegistry;

    /// @notice TVL and fee-revenue oracle per OQ-G1 / OQ-22.
    address public immutable tvlOracle;

    /// @notice F-10 efficiency oracle per **G-D23 (i)** — pre-smoothed numerator/denominator inputs for the canonical OQ-G1 formula `(swap_fee_revenue_i + yield_fee_revenue_i) / emissions_received_i`; oracle owns the 3-epoch SMA, contract reads pre-smoothed pair.
    address public immutable efficiencyOracle;

    /// @notice Balancer V3 vault for pool token and factory reads at G2.3+.
    address public immutable vault;

    /// @notice Canonical AureumFeeRoutingHook — the only hook a gauge-eligible pool may carry per **I-D13** / **OQ-24**; `_checkEligibilityCriteria` rejects any pool whose `IVault(vault).getHooksConfig(pool).hooksContract` differs. Set once at deploy; no setter.
    address public immutable feeRoutingHook;

    /// @notice T-I3 forbidden-token block — AuMM; compared against every pool token in the 52% path.
    address internal immutable _auMM;

    // -------------------------------------------------------------------------
    // Constants (G-D15 G2.0 lock)
    // -------------------------------------------------------------------------

    /// @notice Minimum TVL in svZCHF (18 decimals) for pool-type gate per G-D15c — **Coarse anti-spam gate, not oracle-precise USD**.
    uint256 public constant TVL_FLOOR_SVZCHF = 10_000e18;

    /// @notice Favored cohort size as basis points of the ranked set (1500 = 15%) per G-D3 / OQ-G1.
    uint256 public constant FAVORED_COHORT_BPS = 1500;

    /// @notice Oracle smoothing horizon in epochs for OQ-G1 EMA discipline.
    uint256 public constant SMOOTHING_EPOCHS = 3;

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    mapping(address => bool) public isGaugeEligible;

    mapping(address => bool) public isFavoredCohort;

    mapping(address => uint256) public lastSnapshotEpoch;

    /// @notice First epoch index at which `pool` was ranked in `computeEpochSnapshot` per **G-D23 (v)** — single-purpose cold-start grace predicate; set once on first appearance and gates the 3-epoch warmup window. Never overloaded with `lastSnapshotEpoch` semantics.
    mapping(address => uint256) public firstTournamentEpoch;

    uint256 public currentSnapshotEpoch;

    /// @notice F-10 per-pool emission cap in basis points assigned by the last `computeEpochSnapshot` — 0 (uncapped, top 85%), 100 (bottom 15–10%, 1%), 50 (bottom 10–5%, 0.5%), 10 (bottom 5%, 0.1%) — **P-D13 (3)** / **P-D15 (2)**. Written each epoch for every ranked pool (including 0 that un-caps a pool which climbed back into the top 85% — self-correction per spec L129). Skipped pools (cold-start, warmup, post-warmup zero-denominator) retain their prior value per **P-D15 (4)**. Consumed by the EmissionDistributor via `IGaugeRegistry` delegation (F16e / F16f).
    mapping(address => uint256) public poolEmissionCapBps;

    // -------------------------------------------------------------------------
    // Post-deploy wiring (F-D23 pattern per G-D22)
    // -------------------------------------------------------------------------

    /// @notice GaugeRegistry binding wired post-deploy via `setGaugeRegistry` (G-D22 / G1.12 mirror) — storage, not immutable, because GaugeRegistry's constructor depends on `IGaugeEligibility`.
    address public gaugeRegistry;

    /// @notice one-shot, cleared on first `setGaugeRegistry` call (F-D23 pattern).
    address public gaugeRegistrySetter;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /**
     * @notice Emitted on top-to-bottom cohort crossing when a pool drops out of the favored set (T-T2).
     * @param pool The Balancer pool address.
     * @param epoch Snapshot epoch index for this transition.
     * @param numeratorSma 3-epoch SMA of `swap_fee_revenue_i + yield_fee_revenue_i` per OQ-G1 / **G-D23 (i)**.
     * @param denominatorSma 3-epoch SMA of `emissions_received_i` per OQ-G1 / **G-D23 (i)**; same unit as `numeratorSma` (F-10 is price-agnostic).
     * @param efficiencyRatio F-10 dimensionless ratio `(numeratorSma * 1e18) / denominatorSma` per OQ-G1 / **G-D23 (i)**, 1e18 fixed-point.
     */
    event GaugeEfficiencyDropped(address indexed pool, uint256 indexed epoch, uint256 numeratorSma, uint256 denominatorSma, uint256 efficiencyRatio);

    /**
     * @notice Emitted on bottom-to-top cohort crossing when a pool enters the favored set (T-T1).
     * @param pool The Balancer pool address.
     * @param epoch Snapshot epoch index for this transition.
     * @param numeratorSma 3-epoch SMA of `swap_fee_revenue_i + yield_fee_revenue_i` per OQ-G1 / **G-D23 (i)**.
     * @param denominatorSma 3-epoch SMA of `emissions_received_i` per OQ-G1 / **G-D23 (i)**; same unit as `numeratorSma` (F-10 is price-agnostic).
     * @param efficiencyRatio F-10 dimensionless ratio `(numeratorSma * 1e18) / denominatorSma` per OQ-G1 / **G-D23 (i)**, 1e18 fixed-point.
     */
    event GaugeEfficiencyRising(address indexed pool, uint256 indexed epoch, uint256 numeratorSma, uint256 denominatorSma, uint256 efficiencyRatio);

    // -------------------------------------------------------------------------
    // Custom errors
    // -------------------------------------------------------------------------

    error ZeroAddress();

    error ForbiddenToken(address token);

    error PoolTypeNotWhitelisted(address factory);

    error TVLFloorNotMet(uint256 tvl, uint256 floor);

    error InsufficientQualityGate(uint256 numerator);

    error OnlyGaugeRegistry(address caller);

    error OnlyGaugeRegistrySetter();

    error WrongFeeRoutingHook(address pool, address actualHook);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    /// @notice Gates `computeEpochSnapshot` to the wired `gaugeRegistry` per G-D22 (T-I5 epoch-snapshot determinism).
    modifier onlyGaugeRegistry() {
        if (msg.sender != gaugeRegistry) revert OnlyGaugeRegistry(msg.sender);
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Wires the six deploy-time dependencies for eligibility evaluation and the 52% numerator path.
     * @dev Assigns all immutables after **G-D15a** / G-D8 / OQ-1 address validation — any zero input reverts **ZeroAddress** before storage binds.
     * @param approvedFactory_ Balancer pool factory admitted for G-D15a singleton equality checks.
     * @param vaultClassRegistry_ **G-D8** `VaultClassRegistry` for ERC-4626 class admission look-ups.
     * @param tvlOracle_ Oracle binding for TVL / fee inputs at **G2.4+** / **G2.5**.
     * @param vault_ Balancer V3 vault for pool token reads at **G2.4+**.
     * @param auMM_ T-I3 forbidden token — AuMM.
     * @param gaugeRegistrySetter_ One-shot setter authority for wiring `gaugeRegistry` post-deploy per **G-D22**.
     * @param efficiencyOracle_ **G-D23 (i)** + **G-D23 (ii)** F-10 efficiency oracle binding (sibling to `tvlOracle`) for the OQ-G1 canonical formula at **G2.5**.
     */
    constructor(
        address approvedFactory_,
        address vaultClassRegistry_,
        address tvlOracle_,
        address vault_,
        address auMM_,
        address gaugeRegistrySetter_,
        address efficiencyOracle_,
        address feeRoutingHook_
    ) {
        if (approvedFactory_ == address(0)) revert ZeroAddress();
        if (vaultClassRegistry_ == address(0)) revert ZeroAddress();
        if (tvlOracle_ == address(0)) revert ZeroAddress();
        if (vault_ == address(0)) revert ZeroAddress();
        if (auMM_ == address(0)) revert ZeroAddress();
        if (gaugeRegistrySetter_ == address(0)) revert ZeroAddress();
        if (efficiencyOracle_ == address(0)) revert ZeroAddress();
        if (feeRoutingHook_ == address(0)) revert ZeroAddress();

        approvedFactory = approvedFactory_;
        vaultClassRegistry = vaultClassRegistry_;
        tvlOracle = tvlOracle_;
        vault = vault_;
        _auMM = auMM_;
        gaugeRegistrySetter = gaugeRegistrySetter_;
        efficiencyOracle = efficiencyOracle_;
        feeRoutingHook = feeRoutingHook_;
    }

    // -------------------------------------------------------------------------
    // One-shot setters (F-D23 pattern)
    // -------------------------------------------------------------------------

    /// @notice Wires `gaugeRegistry` from the designated setter and seals the `gaugeRegistrySetter` slot per **G-D22** F-D23 pattern.

    function setGaugeRegistry(address gaugeRegistry_) external {
        if (msg.sender != gaugeRegistrySetter) revert OnlyGaugeRegistrySetter();
        if (gaugeRegistry_ == address(0)) revert ZeroAddress();
        gaugeRegistry = gaugeRegistry_;
        gaugeRegistrySetter = address(0);
    }

    // -------------------------------------------------------------------------
    // External — F-10 efficiency tournament (G-D3 + OQ-G1 + G-D22 + G-D23)
    // -------------------------------------------------------------------------

    /**
     * @notice F-10 efficiency tournament epoch snapshot per **G-D3** + **OQ-G1** + **T-I5** + **G-D5** + **G-D22** + **G-D23** — reads pre-smoothed efficiency inputs, ranks post-grace survivors, assigns cohorts, emits transition events on cohort crossings.
     * @dev Caller-gated by **G-D22** via `onlyGaugeRegistry` (the wired GaugeRegistry binding from G2.4-post's F-D23 one-shot setter). Per-pool zero-handling precedence per **G-D23 (v)**: cold-start grace (first sighting writes `firstTournamentEpoch[pool] = newEpoch`, pool is skipped without revert) → warmup window (`newEpoch - firstTournamentEpoch[pool] < SMOOTHING_EPOCHS`, pool is skipped without revert) → post-warmup `denominatorSma == 0` skips the pool (excluded from ranking, no cap, no revert per **P-D15 (3)**) → ratio compute `(numeratorSma * 1e18) / denominatorSma` (1e18 fixed-point, dimensionless per F-10 price-agnostic). Survivors sorted descending by `efficiencyRatio` via in-memory insertion sort with address-ascending tiebreak per **G-D23 (iv)** / **T-T3** stable-sort determinism — no storage write during sort. Cutoff `favoredCount = (nRanked * 15 + 99) / 100` per **G-D3** ceiling arithmetic (favored top cohort); per-pool emission caps assigned to `poolEmissionCapBps` by floor-percentile tiers per **P-D13 (3)** / **P-D15 (1)** — 10 bps (bottom 5%), 50 bps (bottom 10–5%), 100 bps (bottom 15–10%), 0 (top 85%), via `cap{10,50,100}Count = floor(nRanked × {5,10,15} / 100)`. Transition events fire exactly once per pool per epoch per **G-D5** with reshaped ABI per **G-D23 (iii)**: top-to-bottom → `GaugeEfficiencyDropped` (**T-T2**); bottom-to-top → `GaugeEfficiencyRising` (**T-T1**). Per-pool emission caps ARE assigned here to `poolEmissionCapBps` per **P-D13 (3)** / **P-D15** — the F-16 fix supersedes the **G-D15b** Stage-H deferral; the EmissionDistributor consumes them via `IGaugeRegistry` delegation (F16e / F16f). Caller (GaugeRegistry) responsible for passing a deduped `eligiblePools` set.
     * @param eligiblePools Pre-filtered set of eligible Balancer V3 pools (deduped by caller per G-D22).
     */
    function computeEpochSnapshot(address[] calldata eligiblePools) external onlyGaugeRegistry {
        uint256 newEpoch = currentSnapshotEpoch + 1;
        uint256 totalLen = eligiblePools.length;

        address[] memory rankedPools = new address[](totalLen);
        uint256[] memory rankedNumeratorSma = new uint256[](totalLen);
        uint256[] memory rankedDenominatorSma = new uint256[](totalLen);
        uint256[] memory rankedRatios = new uint256[](totalLen);
        uint256 nRanked = 0;

        // Pass 1 — oracle read + zero-handling precedence per G-D23 (v).
        for (uint256 i = 0; i < totalLen; ++i) {
            address pool = eligiblePools[i];
            (uint256 numeratorSma, uint256 denominatorSma) =
                IEfficiencyOracle(efficiencyOracle).efficiencyInputs(pool);

            if (firstTournamentEpoch[pool] == 0) {
                firstTournamentEpoch[pool] = newEpoch;
                continue;
            }

            if (newEpoch - firstTournamentEpoch[pool] < SMOOTHING_EPOCHS) {
                continue;
            }

            if (denominatorSma == 0) {
                // P-D15 (3) — post-warmup zero-denominator pool skipped (excluded from ranking, no cap, no revert): one dead gauge must not brick the permissionless tournament.
                continue;
            }

            uint256 efficiencyRatio = (numeratorSma * 1e18) / denominatorSma;

            rankedPools[nRanked] = pool;
            rankedNumeratorSma[nRanked] = numeratorSma;
            rankedDenominatorSma[nRanked] = denominatorSma;
            rankedRatios[nRanked] = efficiencyRatio;
            ++nRanked;
        }

        // Pass 2 — insertion sort: descending by ratio, ascending by address on tie (G-D23 (iv) / T-T3).
        for (uint256 i = 1; i < nRanked; ++i) {
            address poolI = rankedPools[i];
            uint256 numI = rankedNumeratorSma[i];
            uint256 denomI = rankedDenominatorSma[i];
            uint256 ratioI = rankedRatios[i];
            uint256 j = i;
            while (
                j > 0 &&
                (rankedRatios[j - 1] < ratioI ||
                    (rankedRatios[j - 1] == ratioI && rankedPools[j - 1] > poolI))
            ) {
                rankedPools[j] = rankedPools[j - 1];
                rankedNumeratorSma[j] = rankedNumeratorSma[j - 1];
                rankedDenominatorSma[j] = rankedDenominatorSma[j - 1];
                rankedRatios[j] = rankedRatios[j - 1];
                --j;
            }
            rankedPools[j] = poolI;
            rankedNumeratorSma[j] = numI;
            rankedDenominatorSma[j] = denomI;
            rankedRatios[j] = ratioI;
        }

        // Pass 3 — ceiling 15% favored cutoff + floor bottom-tier caps + cohort assignment + transition events (G-D3 + G-D5 + P-D15 (1)).
        uint256 favoredCount = (nRanked * 15 + 99) / 100;
        uint256 cap10Count = (nRanked * 5) / 100;
        uint256 cap50Count = (nRanked * 10) / 100;
        uint256 cap100Count = (nRanked * 15) / 100;
        for (uint256 i = 0; i < nRanked; ++i) {
            address pool = rankedPools[i];
            bool wasFavored = isFavoredCohort[pool];
            bool isFavored = i < favoredCount;

            if (wasFavored && !isFavored) {
                emit GaugeEfficiencyDropped(
                    pool, newEpoch, rankedNumeratorSma[i], rankedDenominatorSma[i], rankedRatios[i]
                );
            } else if (!wasFavored && isFavored) {
                emit GaugeEfficiencyRising(
                    pool, newEpoch, rankedNumeratorSma[i], rankedDenominatorSma[i], rankedRatios[i]
                );
            }

            uint256 capBps;
            if (i >= nRanked - cap10Count) capBps = 10;
            else if (i >= nRanked - cap50Count) capBps = 50;
            else if (i >= nRanked - cap100Count) capBps = 100;
            else capBps = 0;
            poolEmissionCapBps[pool] = capBps;

            isFavoredCohort[pool] = isFavored;
            lastSnapshotEpoch[pool] = newEpoch;
        }

        currentSnapshotEpoch = newEpoch;
    }

    // -------------------------------------------------------------------------
    // External — `IGaugeEligibility` surface (G-D5 + T-I5)
    // -------------------------------------------------------------------------

    /// @inheritdoc IGaugeEligibility
    function evaluateEligibility(address pool) external override returns (bool) {
        _checkEligibilityCriteria(pool);
        isGaugeEligible[pool] = true;
        lastSnapshotEpoch[pool] = currentSnapshotEpoch;
        return true;
    }

    /// @inheritdoc IGaugeEligibility
    function isEligible(address pool) external view override returns (bool) {
        return isGaugeEligible[pool];
    }

    /// @inheritdoc IGaugeEligibility
    function cohortOf(address pool) external view override returns (bool favored) {
        favored = isFavoredCohort[pool];
    }

    /// @inheritdoc IGaugeEligibility
    function snapshotEpoch() external view override returns (uint256) {
        return currentSnapshotEpoch;
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Accumulates normalized weights for ERC-4626 pool tokens whose underlying implementation class is admitted — the **G-D8** 52% Quality Gate numerator.
     * @dev **G-D10** — `try IERC4626(token).asset()`/`catch` discriminates ERC-4626Claiming candidates from plain ERC-20s; **T-I3** blocks AuMM before the probe. Non-4626 tokens hit an empty `catch` and add **0**; admitted 4626 tokens add `weights[i]`.
     * @param tokens Pool token set aligned index-wise with `weights`.
     * @param weights Normalized weights from `IBasePool.getNormalizedWeights` — same length as `tokens`.
     * @return numerator Sum of weights for admitted ERC-4626 classes, **1e18**-scale fixed-point compatible with the half-pool bar.
     */
    function _compute52PctNumerator(IERC20[] memory tokens, uint256[] memory weights)
        internal
        view
        returns (uint256 numerator)
    {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ++i) {
            address token = address(tokens[i]);
            if (token == _auMM) revert ForbiddenToken(token);

            try IERC4626(token).asset() returns (address) {
                if (IVaultClassRegistry(vaultClassRegistry).isAdmittedClass(token)) {
                    numerator += weights[i];
                }
            } catch {
                // Plain ERC-20 — no numerator contribution (G-D10 empty catch).
            }
        }
    }

    /**
     * @notice Aggregate binary eligibility gate for `pool` per **OQ-G2** + **G-D6** + **G-D15a** + **G-D8** — reverts on first failed criterion.
     * @dev Body order locked at **G2.4**: numerator path (forbidden tokens + **G-D10** + admitted class weights) then factory provenance, TVL floor, then **0.52e18** quality bar. Caller must pass a weighted pool implementing `IWeightedPool`.
     * @param pool Balancer pool address under evaluation.
     */
    function _checkEligibilityCriteria(address pool) internal view {
        address poolHook = IVault(vault).getHooksConfig(pool).hooksContract;
        if (poolHook != feeRoutingHook) revert WrongFeeRoutingHook(pool, poolHook);
        IERC20[] memory tokens = IVault(vault).getPoolTokens(pool);
        uint256[] memory weights = IWeightedPool(pool).getNormalizedWeights();
        uint256 numerator = _compute52PctNumerator(tokens, weights);
        if (!IBasePoolFactory(approvedFactory).isPoolFromFactory(pool)) revert PoolTypeNotWhitelisted(approvedFactory);
        uint256 tvl = ITVLOracle(tvlOracle).tvl(pool);
        if (tvl < TVL_FLOOR_SVZCHF) revert TVLFloorNotMet(tvl, TVL_FLOOR_SVZCHF);
        if (numerator < 0.52e18) revert InsufficientQualityGate(numerator);
    }

    /**
     * @notice Composition-challenge Quality Gate per **O-D2** / **O-D2a** — ≥52% admitted-ERC-4626 weight, the canonical fee-routing hook, and Aureum-factory provenance, without the TVL floor or anti-spam checks `_checkEligibilityCriteria` runs.
     * @dev Stage O addition (canonical §xxvii registry-level composition check; supersedes K-D6e). Reverts `WrongFeeRoutingHook` if the pool's Vault-registered hook is not the canonical `feeRoutingHook` (**I-D13**); reverts `ForbiddenToken` on AuMM via `_compute52PctNumerator` (**T-I3**, **G-D10**); reverts `PoolTypeNotWhitelisted` if the pool is not from the approved Aureum weighted-pool factory (**F-12** — provenance is what makes the pool's self-reported `getNormalizedWeights` trustworthy, since the canonical hook's `onRegister` does not gate by factory). Returns `false` (does not revert) on a sub-0.52e18 numerator — the **G-D8** quality bar — so the caller (`AureumGovernance` via `IGaugeRegistry`) can branch on a boolean rather than catching a revert.
     * @param pool The candidate replacement pool under evaluation.
     * @return passes `true` when the pool clears the 52% quality gate, carries the canonical hook, and is factory-provenanced.
     */
    function meetsCompositionQualityGate(address pool) external view override returns (bool) {
        address poolHook = IVault(vault).getHooksConfig(pool).hooksContract;
        if (poolHook != feeRoutingHook) revert WrongFeeRoutingHook(pool, poolHook);
        IERC20[] memory tokens = IVault(vault).getPoolTokens(pool);
        uint256[] memory weights = IWeightedPool(pool).getNormalizedWeights();
        uint256 numerator = _compute52PctNumerator(tokens, weights);
        if (!IBasePoolFactory(approvedFactory).isPoolFromFactory(pool)) revert PoolTypeNotWhitelisted(approvedFactory);
        return numerator >= 0.52e18;
    }
}
