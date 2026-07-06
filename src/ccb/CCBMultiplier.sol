// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {AureumTime} from "src/lib/AureumTime.sol";
import {FixedPoint} from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title CCBMultiplier — Aureum F-8 anti-cyclical multiplier engine for the 28-Miliarium constellation
 * @notice Per-pool multiplier evolution gated by Miliarium membership (F-D9 / F-D16) and cadence
 *         guards (F-D6). Reads per-pool TVL EMAs through `IEMASampler` (F-D22). Permissionless
 *         `updateMultiplier` per `BLOCKS_PER_EPOCH` cadence. Aggregate baseline updates atomically
 *         with per-pool F-8 evolution per OQ-23 (iii.b).
 * @dev Stage F scaffold (F3.3a) — storage layout, constants, errors only. Constructor + setter land
 *      at F3.3b; `updateMultiplier` at F3.3d; `getMultiplier` at F3.3e. A gauge-gated boost activation
 *      path was removed at P6.6 per P-D22 (O-D4) — dead since the auto-gauge pivot removed its sole
 *      caller; fix-forward on `stage-p`, `stage-f-complete` untouched.
 *
 *      Decision references:
 *      F-D6 (`STAGE_F_PLAN.md` L60) — `updateMultiplier` permissionless, callable once per `BLOCKS_PER_EPOCH`.
 *      F-D7 (`STAGE_F_PLAN.md` L61) — F-8 numerical constants from `10_constitution.md` §xxix.
 *      F-D9 / F-D16 (`STAGE_F_PLAN.md` L63 / `STAGE_F_NOTES.md` L54) — Miliarium-only multiplier scope.
 *      F-D18 (`STAGE_F_NOTES.md` L115) — `lastProtocolAggregateEMA` cold-start seed; first epoch `delta_global = 0`.
 *      F-D19 (`STAGE_F_NOTES.md` L149) — F-8 anti-cyclical polarity (rising aggregate → downward `M_i` step).
 *      F-D20 (`STAGE_F_NOTES.md` L201) — `IMiliariumRegistry` one-shot setter, sealed-after-first-write.
 *      F-D22 (`STAGE_F_NOTES.md` L274) — `IEMASampler` read-only interface; no `updateEMA` call from `CCBMultiplier`.
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

    /// @notice Fixed Miliarium constellation size — 28 pools per `04_tokenomics.md` §vii. Divisor for `miliariumAvgEMA = currentProtocolAggregateEMA / MILIARIUM_POOL_COUNT` per F-D18.
    uint256 public constant MILIARIUM_POOL_COUNT = 28;

    // -------------------------------------------------------------------------
    // Storage — registry (one-shot setter pattern per F-D20)
    // -------------------------------------------------------------------------

    /// @notice Miliarium registry binding. Stage J handoff replaces the placeholder via `setMiliariumRegistry` per F-D20. Mutable storage; protected by sealed-after-first-write `registrySetter` slot.
    IMiliariumRegistry public miliariumRegistry;

    /// @notice EMA sampler binding. Bound at construction; no setter, never replaced — F-D22 read-only-interface contract. `CCBMultiplier` calls `tvlEMA(pool)` and `lastEMAUpdateBlock(pool)`; never `updateEMA(pool)`.
    IEMASampler public immutable emaSampler;

    /// @notice Authority for `setMiliariumRegistry` per F-D20. Initialized to the deployer at construction; self-zeros on first successful `setMiliariumRegistry` call. Subsequent calls fail at the `OnlyRegistrySetter()` check because `address(0)` cannot transact.
    address public registrySetter;

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

    /// @notice Last protocol-wide aggregate EMA baseline. F-D18 cold-start seed: `0` sentinel for "never written" — first `updateMultiplier` across the protocol seeds this and applies `delta_global = 0` for that epoch. Subsequent calls compare current aggregate to seeded baseline per OQ-23 (iii.b) / F-D19.
    uint256 public lastProtocolAggregateEMA;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice `setMiliariumRegistry` reverts when caller is not the deployer-pinned `registrySetter` — covers both pre-seal unauthorized callers and all post-seal callers (per F-D20 self-zero mechanic).
    error OnlyRegistrySetter();

    /// @notice Setter functions revert when handed `address(0)` — protects against accidental zero-address pin that would brick the registry binding. Shared across the F-D20 setter path and the constructor bindings.
    error InvalidRegistry();

    /// @notice `updateMultiplier(pool)` reverts when `pool` is not a registered Miliarium member. Per F-D9 / F-D16. Pre-Stage-J the placeholder Miliarium registry returns `false` for every pool, so every call reverts here until the Stage J handoff completes.
    error NotMiliariumPool(address pool);

    /// @notice `updateMultiplier(pool)` reverts when called before `lastMultiplierUpdateBlock[pool] + BLOCKS_PER_EPOCH`. Per F-D6 cadence guard.
    error TooEarly(uint256 currentBlock, uint256 nextEligibleBlock);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Wires `CCBMultiplier` to its two external dependencies and pins the setter authority to the deployer.
     * @dev Per F-D20 / F-D22: zero-address rejection on both bindings (`InvalidRegistry`) protects against
     *      deployment-side wiring bugs that would brick the contract before the Stage J handoff lands.
     * @param _miliariumRegistry Stage F placeholder; replaced via `setMiliariumRegistry` at Stage J handoff (F-D20).
     * @param _emaSampler Concrete `EMASampler` from F1.3; bound at construction and never replaced (F-D22).
     */
    constructor(
        IMiliariumRegistry _miliariumRegistry,
        IEMASampler _emaSampler
    ) {
        if (address(_miliariumRegistry) == address(0)) revert InvalidRegistry();
        if (address(_emaSampler) == address(0)) revert InvalidRegistry();
        miliariumRegistry = _miliariumRegistry;
        emaSampler = _emaSampler;
        registrySetter = msg.sender;
    }

    // -------------------------------------------------------------------------
    // Setter — registry binding (F-D20 one-shot self-seal)
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

    // -------------------------------------------------------------------------
    // F-8 evolution — updateMultiplier (F-D6 / F-D18 / F-D19 / F-D25)
    // -------------------------------------------------------------------------

    /**
     * @notice Evolve pool `M_i` by epoch-gated anti-cyclical F-8 steps when outside aggregate and intra dead zones.
     * @dev Per F-D6, F-D16, F-D18, F-D19, F-D25, OQ-23 (iii.b), OQ-23 (iv.a). Gate-order convention —
     *      (1) Miliarium → (2) cadence — so non-member and too-early calls revert. Cold-start: `lastProtocolAggregateEMA`
     *      sentinel `lastProtocolAggregateEMA == 0` yields `delta_global = 0` for that epoch (F-D18). Prior-value sentinel:
     *      `M_i[pool] == 0 → INITIAL_MULTIPLIER` ahead of summed steps and clamps (F-D25). Strict-inequality dead-zone
     *      comparisons (`>` / `<`): boundary equality stays neutral across both channels per F-D19. OQ-23 (iii.b):
     *      protocol aggregate TVL baseline is sum of enumerated EMA samples; anti-cyclical `delta_global` polarity per
     *      F-D19. OQ-23 (iv.a): intra baseline applies simple mean `currentAgg / MILIARIUM_POOL_COUNT` against `pool`'s TVL EMA.
     * @param pool The Miliarium pool whose `M_i` and cadence anchors to update — must satisfy `isMiliarium(pool)` post-Stage-J.
     */
    function updateMultiplier(address pool) external {
        if (!miliariumRegistry.isMiliarium(pool)) revert NotMiliariumPool(pool);
        uint256 nextEligibleBlock = lastMultiplierUpdateBlock[pool] + AureumTime.BLOCKS_PER_EPOCH;
        if (block.number < nextEligibleBlock) revert TooEarly(block.number, nextEligibleBlock);

        uint256 currentAgg;
        uint256 poolCount = miliariumRegistry.miliariumPoolsCount();
        for (uint256 i = 0; i < poolCount; ++i) {
            currentAgg += emaSampler.tvlEMA(miliariumRegistry.miliariumPoolAt(i));
        }

        int256 deltaGlobal;
        uint256 lastAgg = lastProtocolAggregateEMA;
        if (lastAgg != 0) {
            uint256 upperBoundGlobal = lastAgg * (FixedPoint.ONE + DEAD_ZONE) / FixedPoint.ONE;
            uint256 lowerBoundGlobal = lastAgg * (FixedPoint.ONE - DEAD_ZONE) / FixedPoint.ONE;
            if (currentAgg > upperBoundGlobal) deltaGlobal = -STEP_SIZE;
            else if (currentAgg < lowerBoundGlobal) deltaGlobal = STEP_SIZE;
        }

        uint256 miliariumAvg = currentAgg / MILIARIUM_POOL_COUNT;
        uint256 poolEMA = emaSampler.tvlEMA(pool);
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
        lastProtocolAggregateEMA = currentAgg;
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
