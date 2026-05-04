// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";

/**
 * @title CCBMultiplier — Aureum F-8 anti-cyclical multiplier engine for the 28-Miliarium constellation
 * @notice Per-pool multiplier evolution gated by Miliarium membership (F-D9 / F-D16),
 *         boost activation (F-D17), and cadence guards (F-D6). Reads per-pool TVL EMAs
 *         through `IEMASampler` (F-D22). Permissionless `updateMultiplier` per
 *         `BLOCKS_PER_EPOCH` cadence; gauge-gated `activateBoost` for fixed
 *         90-day 1.2× windows. Aggregate baseline updates atomically with per-pool
 *         F-8 evolution per OQ-23 (iii.b).
 * @dev Stage F scaffold (F3.3a) — storage layout, constants, errors only.
 *      Constructor + setters land at F3.3b; `activateBoost` at F3.3c;
 *      `updateMultiplier` at F3.3d; `getMultiplier` at F3.3e.
 *
 *      Decision references:
 *      F-D6 (`STAGE_F_PLAN.md` L60) — `updateMultiplier` permissionless, callable once per `BLOCKS_PER_EPOCH`.
 *      F-D7 (`STAGE_F_PLAN.md` L61) — F-8 numerical constants from `10_constitution.md` §xxix.
 *      F-D9 / F-D16 (`STAGE_F_PLAN.md` L63 / `STAGE_F_NOTES.md` L54) — Miliarium-only multiplier scope.
 *      F-D17 (`STAGE_F_NOTES.md` L84) — `activateBoost` gauge-gated; double-call reverts; post-expiry re-activation succeeds.
 *      F-D18 (`STAGE_F_NOTES.md` L115) — `lastProtocolAggregateEMA` cold-start seed; first epoch `delta_global = 0`.
 *      F-D19 (`STAGE_F_NOTES.md` L149) — F-8 anti-cyclical polarity (rising aggregate → downward `M_i` step).
 *      F-D20 (`STAGE_F_NOTES.md` L201) — `IMiliariumRegistry` one-shot setter, sealed-after-first-write.
 *      F-D21 (`STAGE_F_NOTES.md` L234) — `updateMultiplier` during boost: full silent no-op.
 *      F-D22 (`STAGE_F_NOTES.md` L274) — `IEMASampler` read-only interface; no `updateEMA` call from `CCBMultiplier`.
 *      F-D23 (`STAGE_F_NOTES.md` L316) — `IGaugeRegistry` one-shot setter, parallel-seal pattern mirroring F-D20.
 */
contract CCBMultiplier {
    // -------------------------------------------------------------------------
    // Constants — F-8 numerical surface (F-D7)
    // -------------------------------------------------------------------------

    /// @notice Per-channel multiplier step — 0.05 in 1e18 fixed-point. `delta_global` and `delta_intra_i` each apply ±`STEP_SIZE` per epoch outside the dead zone (F-D19).
    uint256 public constant STEP_SIZE = 5e16;

    /// @notice Relative dead-zone threshold — 0.1% in 1e18 fixed-point. Applies to both `delta_global` and `delta_intra_i` channels per OQ-23 (ii.c).
    uint256 public constant DEAD_ZONE = 1e15;

    /// @notice Multiplier clamp floor — 0.75 in 1e18 fixed-point. F-8 post-step clamp lower bound.
    uint256 public constant CLAMP_FLOOR = 75e16;

    /// @notice Multiplier clamp ceiling — 1.25 in 1e18 fixed-point. F-8 post-step clamp upper bound.
    uint256 public constant CLAMP_CEILING = 125e16;

    /// @notice Multiplier baseline — 1.0 in 1e18 fixed-point. F-8 per-pool initial value; referenced by `getMultiplier` for unwritten pools and by post-boost-expiry semantics (F-D17 / F-D21).
    uint256 public constant INITIAL_MULTIPLIER = 1e18;

    /// @notice Boost factor — 1.2 in 1e18 fixed-point. `getMultiplier(pool)` returns this during active boost windows per `08_bootstrap.md` §xxi / F-D17.
    uint256 public constant BOOST_FACTOR = 12e17;

    /// @notice Boost window duration — 648,000 blocks (~90 days). `activateBoost(pool)` writes `block.number + GAUGE_BOOST_DURATION_BLOCKS` to `boostExpiryBlock[pool]` per F-D17.
    uint256 public constant GAUGE_BOOST_DURATION_BLOCKS = 648_000;

    /// @notice Fixed Miliarium constellation size — 28 pools per `04_tokenomics.md` §vii. Divisor for `miliariumAvgEMA = currentProtocolAggregateEMA / MILIARIUM_POOL_COUNT` per F-D18.
    uint256 public constant MILIARIUM_POOL_COUNT = 28;

    // -------------------------------------------------------------------------
    // Storage — registries (one-shot setter pattern per F-D20 / F-D23)
    // -------------------------------------------------------------------------

    /// @notice Miliarium registry binding. Stage J handoff replaces the placeholder via `setMiliariumRegistry` per F-D20. Mutable storage; protected by sealed-after-first-write `registrySetter` slot.
    IMiliariumRegistry public miliariumRegistry;

    /// @notice Gauge registry binding. Stage G handoff replaces the placeholder via `setGaugeRegistry` per F-D23. Mutable storage; protected by sealed-after-first-write `gaugeRegistrySetter` slot.
    IGaugeRegistry public gaugeRegistry;

    /// @notice EMA sampler binding. Bound at construction; no setter, never replaced — F-D22 read-only-interface contract. `CCBMultiplier` calls `tvlEMA(pool)` and `lastEMAUpdateBlock(pool)`; never `updateEMA(pool)`.
    IEMASampler public emaSampler;

    /// @notice Authority for `setMiliariumRegistry` per F-D20. Initialized to the deployer at construction; self-zeros on first successful `setMiliariumRegistry` call. Subsequent calls fail at the `OnlyRegistrySetter()` check because `address(0)` cannot transact.
    address public registrySetter;

    /// @notice Authority for `setGaugeRegistry` per F-D23. Independent of `registrySetter` — Stage G and Stage J handoffs seal independently. Same self-zero mechanic as F-D20.
    address public gaugeRegistrySetter;

    // -------------------------------------------------------------------------
    // Storage — F-8 per-pool state
    // -------------------------------------------------------------------------

    /// @notice Per-pool current multiplier (F-8's `M_i[pool]`) in 1e18 fixed-point. Default `0` for unwritten pools — `getMultiplier` returns `INITIAL_MULTIPLIER` until F-8 evolution writes a value (F-D19). Suppressed during active boost per F-D21.
    mapping(address => uint256) public M_i;

    /// @notice Per-pool last `updateMultiplier` block. F-D6 cadence anchor — next eligible call at `lastMultiplierUpdateBlock[pool] + BLOCKS_PER_EPOCH`. Default `0` for never-called pools (cadence guard always passes on first call).
    mapping(address => uint256) public lastMultiplierUpdateBlock;

    /// @notice Per-pool boost expiry block. `activateBoost(pool)` writes `block.number + GAUGE_BOOST_DURATION_BLOCKS` per F-D17. Boost active when `block.number < boostExpiryBlock[pool]` (strict inequality boundary per F-D17 L111 / F-D21).
    mapping(address => uint256) public boostExpiryBlock;

    // -------------------------------------------------------------------------
    // Storage — F-8 protocol-aggregate state
    // -------------------------------------------------------------------------

    /// @notice Last protocol-wide aggregate EMA baseline. F-D18 cold-start seed: `0` sentinel for "never written" — first `updateMultiplier` across the protocol seeds this and applies `delta_global = 0` for that epoch. Subsequent calls compare current aggregate to seeded baseline per OQ-23 (iii.b) / F-D19.
    uint256 public lastProtocolAggregateEMA;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice `activateBoost(pool)` reverts when `block.number < boostExpiryBlock[pool]`. F-D17 no-renewal enforcement per `08_bootstrap.md` §xxi.
    error BoostAlreadyActive(address pool);

    /// @notice `setMiliariumRegistry` reverts when caller is not the deployer-pinned `registrySetter` — covers both pre-seal unauthorized callers and all post-seal callers (per F-D20 self-zero mechanic).
    error OnlyRegistrySetter();

    /// @notice `setGaugeRegistry` reverts when caller is not the deployer-pinned `gaugeRegistrySetter` — covers both pre-seal unauthorized callers and all post-seal callers (per F-D23 self-zero mechanic).
    error OnlyGaugeRegistrySetter();

    /// @notice Setter functions revert when handed `address(0)` — protects against accidental zero-address pin that would brick the registry binding. Shared across F-D20 / F-D23 setter paths.
    error InvalidRegistry();

    /// @notice `updateMultiplier(pool)` and `activateBoost(pool)` revert when `pool` is not a registered Miliarium member. Per F-D9 / F-D16. Pre-Stage-J the placeholder Miliarium registry returns `false` for every pool, so every call reverts here until the Stage J handoff completes.
    error NotMiliariumPool(address pool);

    /// @notice `updateMultiplier(pool)` reverts when called before `lastMultiplierUpdateBlock[pool] + BLOCKS_PER_EPOCH`. Per F-D6 cadence guard. Fires before the boost-skip branch per F-D21 — a too-early call during boost reverts here rather than silently returning.
    error TooEarly(uint256 currentBlock, uint256 nextEligibleBlock);

    /// @notice `activateBoost(pool)` reverts when `IGaugeRegistry.isGaugeApproved(msg.sender)` returns false. Per F-D17 caller gate. Pre-Stage-G the placeholder gauge registry returns `false` for every caller, so every call reverts here until the Stage G handoff completes.
    error OnlyApprovedGauge(address caller);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Wires `CCBMultiplier` to its three external dependencies and pins both setter authorities to the deployer.
     * @dev Per F-D20 / F-D22 / F-D23: zero-address rejection on all three bindings (`InvalidRegistry`) protects
     *      against deployment-side wiring bugs that would brick the contract before Stage G / Stage J handoffs land.
     *      `registrySetter` and `gaugeRegistrySetter` are independent slots — their seals fire on independent
     *      timelines (Stage G ships the gauge registry; Stage J ships the Miliarium registry) per F-D23.
     * @param _miliariumRegistry Stage F placeholder; replaced via `setMiliariumRegistry` at Stage J handoff (F-D20).
     * @param _gaugeRegistry Stage F placeholder; replaced via `setGaugeRegistry` at Stage G handoff (F-D23).
     * @param _emaSampler Concrete `EMASampler` from F1.3; bound at construction and never replaced (F-D22).
     */
    constructor(
        IMiliariumRegistry _miliariumRegistry,
        IGaugeRegistry _gaugeRegistry,
        IEMASampler _emaSampler
    ) {
        if (address(_miliariumRegistry) == address(0)) revert InvalidRegistry();
        if (address(_gaugeRegistry) == address(0)) revert InvalidRegistry();
        if (address(_emaSampler) == address(0)) revert InvalidRegistry();
        miliariumRegistry = _miliariumRegistry;
        gaugeRegistry = _gaugeRegistry;
        emaSampler = _emaSampler;
        registrySetter = msg.sender;
        gaugeRegistrySetter = msg.sender;
    }

    // -------------------------------------------------------------------------
    // Setters — registry binding (F-D20 / F-D23 one-shot self-seal)
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
     * @dev Per F-D23: parallel-seal twin of `setMiliariumRegistry`. Callable exactly once, by the address recorded
     *      as `gaugeRegistrySetter` at construction. Independent of the Miliarium-side seal — Stage G and Stage J
     *      handoffs land on independent timelines. Same authority-then-zero-address check ordering as F-D20.
     * @param newRegistry Concrete `IGaugeRegistry` deployed at Stage G. Must be non-zero (`InvalidRegistry()` otherwise).
     */
    function setGaugeRegistry(IGaugeRegistry newRegistry) external {
        if (msg.sender != gaugeRegistrySetter) revert OnlyGaugeRegistrySetter();
        if (address(newRegistry) == address(0)) revert InvalidRegistry();
        gaugeRegistry = newRegistry;
        gaugeRegistrySetter = address(0);
    }
}
