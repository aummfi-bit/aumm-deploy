// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {AureumTime} from "src/lib/AureumTime.sol";
import {FixedPoint} from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title CCBMultiplier — Aureum F-8 anti-cyclical multiplier engine for the 28-Miliarium constellation
 * @notice Per-pool multiplier evolution gated by Miliarium membership (F-D9 / F-D16) and cadence
 *         guards (F-D6). Reads per-pool TVL EMAs through `IEMASampler` (F-D22). Permissionless
 *         `updateMultiplier` per `BLOCKS_PER_EPOCH` cadence. The `delta_global` baseline aggregates
 *         over ALL currently-Active gauges via `IGaugeRegistry` enumeration per PB-D18 (ii),
 *         superseding the Miliarium-only OQ-23 (iii.b) universe; the `delta_intra` baseline keeps
 *         its own Miliarium-only sum per PB-D18 (iii) (OQ-23 (iv.a) unchanged). Aggregate baseline
 *         updates atomically with per-pool F-8 evolution.
 * @dev Stage F scaffold (F3.3a) — storage layout, constants, errors only. Constructor + setter land
 *      at F3.3b; `updateMultiplier` at F3.3d; `getMultiplier` at F3.3e. A gauge-gated boost activation
 *      path was removed at P6.6 per P-D22 (O-D4) — dead since the auto-gauge pivot removed its sole
 *      caller; fix-forward on `stage-p`, `stage-f-complete` untouched. The gauge-registry binding
 *      returns at PB2.13d2 per PB-D18 with a live consumer — the all-Active-gauge `delta_global`
 *      aggregate — restoring the P-D22-removed shape (3-arg constructor + one-shot seal): enumeration
 *      this time, no boost machinery.
 *
 *      Decision references:
 *      F-D6 (`STAGE_F_PLAN.md` L60) — `updateMultiplier` permissionless, callable once per `BLOCKS_PER_EPOCH`.
 *      F-D7 (`STAGE_F_PLAN.md` L61) — F-8 numerical constants from `10_constitution.md` §xxix.
 *      F-D9 / F-D16 (`STAGE_F_PLAN.md` L63 / `STAGE_F_NOTES.md` L54) — Miliarium-only multiplier scope.
 *      F-D18 (`STAGE_F_NOTES.md` L115) — `lastProtocolAggregateEMA` cold-start seed; first epoch `delta_global = 0`.
 *      F-D19 (`STAGE_F_NOTES.md` L149) — F-8 anti-cyclical polarity (rising aggregate → downward `M_i` step).
 *      F-D20 (`STAGE_F_NOTES.md` L201) — one-shot setter, sealed-after-first-write (mirrored for both registry slots).
 *      F-D22 (`STAGE_F_NOTES.md` L274) — `IEMASampler` read-only interface; no `updateEMA` call from `CCBMultiplier`.
 *      PB-D18 (`STAGE_P_BIS_NOTES.md`) — OQ-23 reopened: all-Active-gauge `delta_global` aggregate, `delta_intra` decoupled, constants untouched.
 */
contract CCBMultiplier {
    using SafeCast for uint256;
    using SafeCast for int256;

    // -------------------------------------------------------------------------
    // Constants — F-8 numerical surface (F-D7)
    // -------------------------------------------------------------------------

    /// @notice Per-channel multiplier step — 0.05 in 1e18 fixed-point. `delta_global` and `delta_intra_i` each apply ±`STEP_SIZE` per epoch outside the dead zone (F-D19).
    int256 public constant STEP_SIZE = 5e16;

    /// @notice Relative dead-zone threshold — 0.1% in 1e18 fixed-point. Applies to both `delta_global` and `delta_intra_i` channels per OQ-23 (ii.c).
    uint256 public constant DEAD_ZONE = 1e15;

    /// @notice Multiplier clamp floor — 0.75 in 1e18 fixed-point. F-8 post-step clamp lower bound.
    int256 public constant CLAMP_FLOOR = 75e16;

    /// @notice Multiplier clamp ceiling — 1.25 in 1e18 fixed-point. F-8 post-step clamp upper bound.
    int256 public constant CLAMP_CEILING = 125e16;

    /// @notice Multiplier baseline — 1.0 in 1e18 fixed-point. F-8 per-pool initial value; referenced by `getMultiplier` for non-Miliarium and unwritten pools.
    uint256 public constant INITIAL_MULTIPLIER = 1e18;

    /// @notice Fixed Miliarium constellation size — 28 pools per `04_tokenomics.md` §vii. Divisor for the `delta_intra` baseline `miliariumAvg = miliariumAgg / MILIARIUM_POOL_COUNT` per PB-D18 (iii) (OQ-23 (iv.a) simple mean).
    uint256 public constant MILIARIUM_POOL_COUNT = 28;

    // -------------------------------------------------------------------------
    // Storage — registries (one-shot setter pattern per F-D20, mirrored per PB-D18 (v))
    // -------------------------------------------------------------------------

    /// @notice Miliarium registry binding. Stage J handoff replaces the placeholder via `setMiliariumRegistry` per F-D20. Mutable storage; protected by sealed-after-first-write `registrySetter` slot.
    IMiliariumRegistry public miliariumRegistry;

    /// @notice EMA sampler binding. Bound at construction; no setter, never replaced — F-D22 read-only-interface contract. `CCBMultiplier` reads `emaSeedBlock`, `sampleCount`, `MIN_SAMPLES`, `lastEMAUpdateBlock` and `tvlEMA` through the PP-D52 (xii) `_gatedTvlEMA` gate; never `updateEMA(pool)`.
    IEMASampler public immutable emaSampler;

    /// @notice Authority for `setMiliariumRegistry` per F-D20. Initialized to the deployer at construction; self-zeros on first successful `setMiliariumRegistry` call. Subsequent calls fail at the `OnlyRegistrySetter()` check because `address(0)` cannot transact.
    address public registrySetter;

    /// @notice Gauge registry binding — the `delta_global` enumeration universe per PB-D18 (ii). Deploy-time placeholder replaced via `setGaugeRegistry` once the Stage G stack exists (the G stack deploys after the F engine). Mutable storage; protected by the sealed-after-first-write `gaugeRegistrySetter` slot.
    IGaugeRegistry public gaugeRegistry;

    /// @notice Authority for `setGaugeRegistry` per the F-D20 mirror (PB-D18 (v)). Initialized to the deployer at construction; self-zeros on first successful `setGaugeRegistry` call. Subsequent calls fail at the `OnlyGaugeRegistrySetter()` check because `address(0)` cannot transact.
    address public gaugeRegistrySetter;

    // -------------------------------------------------------------------------
    // Storage — F-8 per-pool state
    // -------------------------------------------------------------------------

    /// @notice Per-pool current multiplier (F-8's `M_i[pool]`) in 1e18 fixed-point. Default `0` for unwritten pools — `getMultiplier` returns `INITIAL_MULTIPLIER` until F-8 evolution writes a value (F-D19).
    mapping(address => uint256) public M_i;

    /// @notice Per-pool last `updateMultiplier` block. F-D6 cadence anchor — next eligible call at `lastMultiplierUpdateBlock[pool] + BLOCKS_PER_EPOCH`. Default `0` for never-called pools (cadence guard always passes on first call).
    mapping(address => uint256) public lastMultiplierUpdateBlock;

    // -------------------------------------------------------------------------
    // Storage — F-8 protocol-aggregate state
    // -------------------------------------------------------------------------

    /// @notice Per-pool last protocol-wide aggregate EMA baseline (PP-D52 (xii)) — the sum of `tvlEMA` over ALL currently-Active gauges (PB-D18 (ii)) as observed at THIS pool's own most recent `updateMultiplier` call. Keyed by pool rather than global so each pool's `deltaGlobal` compares the current aggregate to the aggregate at ITS OWN prior cadence window, not to whichever pool last happened to update. F-D18 cold-start seed: `0` sentinel for "never written for this pool" — a pool's own first `updateMultiplier` call applies `delta_global = 0` for that call.
    mapping(address => uint256) public lastProtocolAggregateEMA;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice `setMiliariumRegistry` reverts when caller is not the deployer-pinned `registrySetter` — covers both pre-seal unauthorized callers and all post-seal callers (per F-D20 self-zero mechanic).
    error OnlyRegistrySetter();

    /// @notice `setGaugeRegistry` reverts when caller is not the deployer-pinned `gaugeRegistrySetter` — covers both pre-seal unauthorized callers and all post-seal callers (F-D20 self-zero mechanic, mirrored per PB-D18 (v)).
    error OnlyGaugeRegistrySetter();

    /// @notice Setter functions revert when handed `address(0)` — protects against accidental zero-address pin that would brick a registry binding. Shared across both F-D20 setter paths (`setMiliariumRegistry`, `setGaugeRegistry`) and the constructor bindings.
    error InvalidRegistry();

    /// @notice `updateMultiplier(pool)` reverts when `pool` is not a registered Miliarium member. Per F-D9 / F-D16. Pre-Stage-J the placeholder Miliarium registry returns `false` for every pool, so every call reverts here until the Stage J handoff completes.
    error NotMiliariumPool(address pool);

    /// @notice `updateMultiplier(pool)` reverts when called before `lastMultiplierUpdateBlock[pool] + BLOCKS_PER_EPOCH`. Per F-D6 cadence guard.
    error TooEarly(uint256 currentBlock, uint256 nextEligibleBlock);

    /// @notice `updateMultiplier(pool)` reverts when `pool`'s own TVL EMA is not seeded, not yet matured (< `AureumTime.EMA_MATURITY_BLOCKS` old), below the D.1 sample floor, or stale (last refreshed more than `AureumTime.EMA_STALENESS_BLOCKS` ago). PP-D52 (xii) FOURTH — mirrors `EmissionDistributor._gatedTvlEMA`'s read taxonomy exactly; an ungated zero here would read as a pool far below the constellation mean and step it UP, the opposite of D.4's fix.
    error EmaNotReady(address pool);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Wires `CCBMultiplier` to its three external dependencies and pins both setter authorities to the deployer.
     * @dev Per F-D20 / F-D22 / PB-D18 (v): zero-address rejection on all three bindings (`InvalidRegistry`)
     *      protects against deployment-side wiring bugs that would brick the contract before the respective
     *      handoffs land (Stage J for the Miliarium slot; the post-G-stack orchestrator seal for the gauge slot).
     * @param _miliariumRegistry Stage F placeholder; replaced via `setMiliariumRegistry` at Stage J handoff (F-D20).
     * @param _emaSampler Concrete `EMASampler` from F1.3; bound at construction and never replaced (F-D22).
     * @param _gaugeRegistry Deploy-time placeholder (the Stage G stack deploys after the F engine); replaced via `setGaugeRegistry` at the orchestrator seal (PB-D18 (v)).
     */
    constructor(
        IMiliariumRegistry _miliariumRegistry,
        IEMASampler _emaSampler,
        IGaugeRegistry _gaugeRegistry
    ) {
        if (address(_miliariumRegistry) == address(0)) revert InvalidRegistry();
        if (address(_emaSampler) == address(0)) revert InvalidRegistry();
        if (address(_gaugeRegistry) == address(0)) revert InvalidRegistry();
        miliariumRegistry = _miliariumRegistry;
        emaSampler = _emaSampler;
        gaugeRegistry = _gaugeRegistry;
        registrySetter = msg.sender;
        gaugeRegistrySetter = msg.sender;
    }

    // -------------------------------------------------------------------------
    // Setters — registry bindings (F-D20 one-shot self-seal, mirrored per PB-D18 (v))
    // -------------------------------------------------------------------------

    /**
     * @notice Pin the Miliarium registry to its concrete Stage J deployment and seal the setter authority.
     * @dev Per F-D20: callable exactly once, by the address recorded as `registrySetter` at construction.
     *      Authority check fires before the zero-address guard — caller-side errors are reported as
     *      `OnlyRegistrySetter()` regardless of the supplied `newRegistry`. State write order: registry binding
     *      first, then `registrySetter = address(0)` to seal. Subsequent calls revert `OnlyRegistrySetter()`
     *      because no caller can hold `address(0)`.
     * @param newRegistry Concrete `IMiliariumRegistry` deployed at Stage J. Must be non-zero (`InvalidRegistry()` otherwise).
     */
    function setMiliariumRegistry(IMiliariumRegistry newRegistry) external {
        if (msg.sender != registrySetter) revert OnlyRegistrySetter();
        if (address(newRegistry) == address(0)) revert InvalidRegistry();
        miliariumRegistry = newRegistry;
        registrySetter = address(0);
    }

    /**
     * @notice Pin the gauge registry to its concrete Stage G deployment and seal the setter authority.
     * @dev F-D20 mirror per PB-D18 (v): callable exactly once, by the address recorded as `gaugeRegistrySetter`
     *      at construction. Authority check fires before the zero-address guard — caller-side errors are
     *      reported as `OnlyGaugeRegistrySetter()` regardless of the supplied `newRegistry`. State write order:
     *      registry binding first, then `gaugeRegistrySetter = address(0)` to seal. Subsequent calls revert
     *      `OnlyGaugeRegistrySetter()` because no caller can hold `address(0)`.
     * @param newRegistry Concrete `IGaugeRegistry` (the Stage G `GaugeRegistry`). Must be non-zero (`InvalidRegistry()` otherwise).
     */
    function setGaugeRegistry(IGaugeRegistry newRegistry) external {
        if (msg.sender != gaugeRegistrySetter) revert OnlyGaugeRegistrySetter();
        if (address(newRegistry) == address(0)) revert InvalidRegistry();
        gaugeRegistry = newRegistry;
        gaugeRegistrySetter = address(0);
    }

    // -------------------------------------------------------------------------
    // PP-D52 (xii) EMA readiness gate (mirrors EmissionDistributor._gatedTvlEMA)
    // -------------------------------------------------------------------------

    /// @notice PP-D52 (xii) SECOND — gated TVL EMA read: returns `pool`'s TVL EMA only when its EMA is seeded, matured (at least `AureumTime.EMA_MATURITY_BLOCKS` old), past the D.1 sample floor, and fresh (refreshed within `AureumTime.EMA_STALENESS_BLOCKS`); otherwise `0`. Mirrors `EmissionDistributor._gatedTvlEMA` check for check, and reads the threshold through `MIN_SAMPLES()` per PP-D52 (x) rather than mirroring it as a local constant. D.4: the three raw `tvlEMA` reads this replaces let an unseeded, immature, under-sampled or stale pool move `M_i` over a gauge set anyone grows for 100 svZCHF.
    /// @param pool The Balancer V3 pool address.
    /// @return The pool's TVL EMA when seeded, mature, sampled and fresh, else 0.
    function _gatedTvlEMA(address pool) private view returns (uint256) {
        uint256 seedBlock = emaSampler.emaSeedBlock(pool);
        if (seedBlock == 0) return 0;
        if (block.number - seedBlock < AureumTime.EMA_MATURITY_BLOCKS) return 0;
        if (emaSampler.sampleCount(pool) < emaSampler.MIN_SAMPLES()) return 0;
        if (block.number - emaSampler.lastEMAUpdateBlock(pool) > AureumTime.EMA_STALENESS_BLOCKS) return 0;
        return emaSampler.tvlEMA(pool);
    }

    // -------------------------------------------------------------------------
    // F-8 evolution — updateMultiplier (F-D6 / F-D18 / F-D19 / F-D25 / PB-D18)
    // -------------------------------------------------------------------------

    /**
     * @notice Evolve pool `M_i` by epoch-gated anti-cyclical F-8 steps when outside aggregate and intra dead zones.
     * @dev Per F-D6, F-D16, F-D18, F-D19, F-D25, PB-D18 (ii)/(iii), PP-D52 (xii). Gate-order convention —
     *      (1) Miliarium → (2) cadence → (3) readiness — so non-member, too-early and not-yet-readable calls
     *      revert. The readiness gate is `EmaNotReady`, evaluated once on `pool`'s own EMA immediately after
     *      the cadence check and reused as `poolEMA` at the intra comparison; it writes nothing and consumes
     *      no cadence, exactly as `TooEarly` does, so a keeper may retry once the pool's EMA matures
     *      (PP-D52 (xii) FOURTH — an ungated zero would read as a pool far below the mean and step it UP).
     *      delta_global universe per PB-D18 (ii): the enumerated sum over ALL currently-Active gauges
     *      (`gaugeRegistry.gaugeCount()` / `gaugeAt(i)`, the P-D13 EnumerableSet — Revoked pools leave the set),
     *      now read through `_gatedTvlEMA` rather than raw, superseding the Miliarium-only OQ-23 (iii.b)
     *      universe; a gauge failing the readiness gate contributes zero to the sum rather than reverting the
     *      call, since only `pool`'s own unreadiness is the caller's to fix. Cold-start:
     *      `lastProtocolAggregateEMA[pool] == 0` sentinel yields `delta_global = 0` for that call (F-D18),
     *      now PER POOL per PP-D52 (xii) FIFTH — each pool compares the current aggregate to the aggregate at
     *      ITS OWN prior cadence window, closing D.4's second face, where one global slot re-keyed by whoever
     *      updated last cost every subsequent updater in the same epoch its entire global channel.
     *      delta_intra baseline per PB-D18 (iii): its own Miliarium-only sum — decoupled from the global
     *      aggregate — with simple mean `miliariumAgg / MILIARIUM_POOL_COUNT` against `pool`'s gated TVL EMA
     *      (OQ-23 (iv.a) unchanged); Miliarium pools legitimately appear in both roster walks. Prior-value
     *      sentinel: `M_i[pool] == 0 → INITIAL_MULTIPLIER` ahead of summed steps and clamps (F-D25).
     *      Strict-inequality dead-zone comparisons (`>` / `<`): boundary equality stays neutral across both
     *      channels per F-D19. Anti-cyclical `delta_global` polarity per F-D19.
     * @param pool The Miliarium pool whose `M_i` and cadence anchors to update — must satisfy `isMiliarium(pool)` post-Stage-J.
     */
    function updateMultiplier(address pool) external {
        if (!miliariumRegistry.isMiliarium(pool)) revert NotMiliariumPool(pool);
        uint256 nextEligibleBlock = lastMultiplierUpdateBlock[pool] + AureumTime.BLOCKS_PER_EPOCH;
        if (block.number < nextEligibleBlock) revert TooEarly(block.number, nextEligibleBlock);
        uint256 poolEMA = _gatedTvlEMA(pool);
        if (poolEMA == 0) revert EmaNotReady(pool);

        uint256 currentGlobalAgg;
        IGaugeRegistry gauges = gaugeRegistry;
        uint256 gaugePoolCount = gauges.gaugeCount();
        for (uint256 i = 0; i < gaugePoolCount; ++i) {
            currentGlobalAgg += _gatedTvlEMA(gauges.gaugeAt(i));
        }

        int256 deltaGlobal;
        uint256 lastAgg = lastProtocolAggregateEMA[pool];
        if (lastAgg != 0) {
            uint256 upperBoundGlobal = lastAgg * (FixedPoint.ONE + DEAD_ZONE) / FixedPoint.ONE;
            uint256 lowerBoundGlobal = lastAgg * (FixedPoint.ONE - DEAD_ZONE) / FixedPoint.ONE;
            if (currentGlobalAgg > upperBoundGlobal) deltaGlobal = -STEP_SIZE;
            else if (currentGlobalAgg < lowerBoundGlobal) deltaGlobal = STEP_SIZE;
        }

        uint256 miliariumAgg;
        uint256 poolCount = miliariumRegistry.miliariumPoolsCount();
        for (uint256 i = 0; i < poolCount; ++i) {
            miliariumAgg += _gatedTvlEMA(miliariumRegistry.miliariumPoolAt(i));
        }

        uint256 miliariumAvg = miliariumAgg / MILIARIUM_POOL_COUNT;
        int256 deltaIntra;
        uint256 upperBoundIntra = miliariumAvg * (FixedPoint.ONE + DEAD_ZONE) / FixedPoint.ONE;
        uint256 lowerBoundIntra = miliariumAvg * (FixedPoint.ONE - DEAD_ZONE) / FixedPoint.ONE;
        if (poolEMA > upperBoundIntra) deltaIntra = -STEP_SIZE;
        else if (poolEMA < lowerBoundIntra) deltaIntra = STEP_SIZE;

        uint256 prior = M_i[pool] == 0 ? INITIAL_MULTIPLIER : M_i[pool];
        int256 newM = prior.toInt256() + deltaGlobal + deltaIntra;
        if (newM < CLAMP_FLOOR) newM = CLAMP_FLOOR;
        else if (newM > CLAMP_CEILING) newM = CLAMP_CEILING;

        M_i[pool] = newM.toUint256();
        lastMultiplierUpdateBlock[pool] = block.number;
        lastProtocolAggregateEMA[pool] = currentGlobalAgg;
    }

    // -------------------------------------------------------------------------
    // Multiplier read — getMultiplier (F-D16 / F-D25)
    // -------------------------------------------------------------------------

    /**
     * @notice Hot-path read returning the effective F-8 multiplier per Stage H scoring.
     * @dev Per F-D16, F-D25. Return taxonomy — (1) non-Miliarium → `INITIAL_MULTIPLIER`,
     *      (2) unwritten `M_i[pool]` → `INITIAL_MULTIPLIER`, (3) otherwise → `M_i[pool]`.
     *      `getMultiplier` does NOT revert — uniform read for Stage H per F-D16 L62 ("hot-path read for
     *      Stage H's emission distributor, which scores all gauged pools (Miliarium and non-Miliarium
     *      together) every block per F-D9").
     * @param pool Pool address whose effective multiplier to return.
     * @return Effective F-8 multiplier in 1e18 fixed-point.
     */
    function getMultiplier(address pool) external view returns (uint256) {
        if (!miliariumRegistry.isMiliarium(pool)) return INITIAL_MULTIPLIER;
        uint256 m = M_i[pool];
        return m == 0 ? INITIAL_MULTIPLIER : m;
    }
}
