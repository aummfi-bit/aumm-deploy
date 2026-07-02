// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title IGaugeRegistry — gauge state machine + three activation paths + revocation surface
/// @notice Public interface to Stage G `GaugeRegistry` (`src/gauge/GaugeRegistry.sol`) — exposes the three activation entrypoints (permissionless `activateGauge` per **OQ-G3**, governance `registerGaugeFromComposition` and `seedFoundingPool` / `seedFoundingPools`), revocation (`revokeGauge`), the Stage K governance handoff (`setGovernanceContract`), and read views (`gaugeStatus`, `isGaugeApproved`).
/// @dev Cross-references: **G-D7** (three activation paths), **G-D13** (no boost across paths), **G-D16a** (extend-in-place; Stage F `isGaugeApproved(address)` selector + ABI preserved verbatim), **G-D16b** (scalar + batch seed), **G-D16c** (try/catch + non-reverting + `GaugeActivationFailed` per **OQ-G3**), **G-D17** (Revoked is terminal at Stage G), **F-D17** (Stage F `CCBMultiplier` consumer of `isGaugeApproved(msg.sender)`).
///      Stage F compat: `CCBMultiplier.activateBoost` (`src/ccb/CCBMultiplier.sol`) calls `isGaugeApproved(msg.sender)` per **F-D17**; the Stage G `GaugeRegistry` implementation returns `_gaugeStatus[caller] == GaugeStatus.Active`. The selector + ABI are unchanged from Stage F per **G-D16a**; additive symbols below do not alter it.
interface IGaugeRegistry {
    /// @notice Gauge state machine — `None` (never gauged), `Active` (currently approved), `Revoked` (terminally revoked per **G-D17**).
    /// @dev Revoked is terminal at Stage G — no entrypoint writes Revoked → Active. Cross-references: **G-D17**.
    enum GaugeStatus {
        None,
        Active,
        Revoked
    }

    /// @notice Activation path tag — distinguishes which entrypoint approved the gauge: `Permissionless` (OQ-G3 fee path), `Composition` (governance composition replacement), `Founding` (governance Miliarium genesis seed).
    /// @dev Cross-references: **G-D7** (three paths), **G-D13** (no boost on any path), **STAGE_G_PRECHECK_AUTO_GAUGE** C-4 (founding bypass).
    enum GaugeActivationPath {
        Permissionless,
        Composition,
        Founding
    }

    /// @notice Emitted when `pool` transitions to `GaugeStatus.Active` via any of the three activation paths.
    /// @dev Path tag identifies which entrypoint activated. Cross-references: **G-D7**, **G-D13**, **G-D16c** step 5.
    /// @param pool The pool now approved as a gauge (indexed for off-chain indexing).
    /// @param path The activation path tag (indexed).
    event GaugeActivated(address indexed pool, GaugeActivationPath indexed path);

    /// @notice Emitted when permissionless `activateGauge` runs to completion but eligibility evaluation fails — fee already routed to Bodensee per **OQ-G3** non-refundable invariant; pool status NOT mutated.
    /// @dev ABI lock per **G-D16c**: `reason` is non-indexed `bytes` carrying the verbatim `evaluateEligibility` revert payload (catch path) or the `GaugeRegistry`-internal `EligibilityReturnedFalse()` selector (explicit-false path). Cross-references: **G-D16c**, **OQ-G3**.
    /// @param pool The pool whose activation failed (indexed).
    /// @param reason The encoded failure reason — verbatim revert bytes from `evaluateEligibility`, or `EligibilityReturnedFalse.selector` for the explicit-false branch.
    event GaugeActivationFailed(address indexed pool, bytes reason);

    /// @notice Emitted when governance flips `pool` from `Active` to terminally `Revoked` per **G-D17**.
    /// @dev No matching reverse-direction event at Stage G; Revoked is terminal. Cross-references: **G-D17**.
    /// @param pool The pool now Revoked (indexed).
    event GaugeRevoked(address indexed pool);

    /// @notice Emitted when `activateGauge` successfully routes the OQ-G3 anti-spam fee through the `SwapAndDepositToBodensee` helper — fired before the eligibility check, so a subsequent `GaugeActivationFailed` may follow on the same call without contradicting this event.
    /// @dev Cross-references: **OQ-G3**, **G-D11** + **G-D12** + **G-D21** (Bodensee donation routing), **G-D16c** step 2.
    /// @param payer The caller who paid the fee (indexed).
    /// @param amount The fee magnitude routed — `100e18` for svZCHF or `125e18` for sUSDS per **G-D12**.
    event AntiSpamFeeRouted(address indexed payer, uint256 amount);

    /// @notice Emitted when `setGovernanceContract` rebinds the governance authority — Stage K on-chain governance handoff path.
    /// @dev Pre-handoff: governance is the Stage A–K Authorizer Safe per **CLAUDE.md** §1; post-handoff: on-chain governance per Stage K. Cross-references: **CLAUDE.md** §2.
    /// @param oldGovernance The previous governance address (indexed).
    /// @param newGovernance The new governance address (indexed).
    event GovernanceTransferred(address indexed oldGovernance, address indexed newGovernance);

    /// @notice Reverts when a governance-only entrypoint is called by a non-governance address.
    /// @dev Caller identity supplied for off-chain debugging. Cross-references: **G-D7**, **G-D17**.
    /// @param caller The unauthorized caller (typically `msg.sender`).
    error NotGovernance(address caller);

    /// @notice Reverts when an activation entrypoint is called against a pool whose status is already `GaugeStatus.Active`.
    /// @dev Pre-locks revert-before-fee-pull on `activateGauge` per **G-D16c** step 1 — callers of already-Active pools are not charged the OQ-G3 anti-spam fee.
    /// @param pool The already-Active pool.
    error AlreadyGauged(address pool);

    /// @notice Reverts when any Stage G entrypoint is called against a pool whose status is `GaugeStatus.Revoked`.
    /// @dev Revoked is terminal at Stage G per **G-D17** — `activateGauge`, `registerGaugeFromComposition`, and `seedFoundingPool` all revert against Revoked status; no Stage G entrypoint writes Revoked → Active.
    /// @param pool The Revoked pool.
    error AlreadyRevoked(address pool);

    /// @notice Reverts when `revokeGauge` is called against a pool whose status is not `GaugeStatus.Active` (i.e., `None` or `Revoked`).
    /// @dev Revocation requires the pool to be currently Active — `None` pools have nothing to revoke; `Revoked` pools are already Revoked.
    /// @param pool The pool that is not currently Active.
    error NotGauged(address pool);

    /// @notice Whether `gauge` is currently registered as an approved gauge authorized to trigger boost activation on Miliarium pools.
    /// @param gauge The address checked for gauge approval (callers typically pass `msg.sender`).
    /// @return True if `gauge` is approved; otherwise false.
    function isGaugeApproved(address gauge) external view returns (bool);

    /// @notice Returns the gauge state machine value for `pool` — `None`, `Active`, or `Revoked`.
    /// @dev Read-only view. Cross-references: **G-D17** (Revoked terminal).
    /// @param pool The pool whose status is queried.
    /// @return status The current `GaugeStatus` for `pool`.
    function gaugeStatus(address pool) external view returns (GaugeStatus status);

    /// @notice Permissionless gauge activation — pulls the OQ-G3 anti-spam fee, routes it to der Bodensee, then runs eligibility; on eligibility failure does NOT revert (fee retained per **OQ-G3**).
    /// @dev Five-step ordering per **G-D16c**: (1) read `_gaugeStatus[pool]` — revert `AlreadyRevoked(pool)` per **G-D17** or `AlreadyGauged(pool)` if Active; (2) pull fee via `SwapAndDepositToBodensee.swapAndDeposit(payToken, amount)` per **G-D21** strict-equality routing — magnitude `100e18` svZCHF or `125e18` sUSDS per **G-D12**; (3) `try IGaugeEligibility.evaluateEligibility(pool) returns (bool eligible) { ... } catch (bytes memory reason) { ... }`; (4) catch OR `eligible == false` → `emit GaugeActivationFailed(pool, reason); return;` (no revert, no state write); (5) success → `_gaugeStatus[pool] = GaugeStatus.Active; emit GaugeActivated(pool, GaugeActivationPath.Permissionless);`. Not `payable` — fee is ERC-20.
    /// @param pool The pool being activated as a gauge.
    function activateGauge(address pool) external;

    /// @notice Governance-only activation for a pool replacing another via composition rebalancing — bypasses eligibility (composition-governance path already vetted the replacement).
    /// @dev No anti-spam fee, no eligibility check, no boost (per **G-D13**). Reverts `NotGovernance(caller)` on non-governance call; `AlreadyGauged(pool)` if Active; `AlreadyRevoked(pool)` if Revoked. Cross-references: **G-D7** path 2.
    /// @param pool The replacement pool to register.
    function registerGaugeFromComposition(address pool) external;

    /// @notice Governance-only seed for a single Miliarium genesis pool — bypasses eligibility per **STAGE_G_PRECHECK_AUTO_GAUGE** C-4.
    /// @dev Scalar primitive per **G-D16b**. No anti-spam fee, no eligibility check, no boost (per **G-D13**). Reverts `NotGovernance(caller)`; `AlreadyGauged(pool)` if Active; `AlreadyRevoked(pool)` if Revoked (re-seeding a Revoked founding pool is out of scope for Stage G per **G-D17**). Cross-references: **G-D7** path 3.
    /// @param pool The Miliarium genesis pool to seed as Active.
    function seedFoundingPool(address pool) external;

    /// @notice Governance-only batch seed for multiple Miliarium genesis pools — atomic per-pool activation; reverts on any individual failure with no partial-state leakage.
    /// @dev Batch convenience per **G-D16b** — internally iterates the `seedFoundingPool` semantic across `pools`; supports a single governance transaction seeding all 28 Miliarium genesis pools (see `aummfi-bit/aumm-site` `miliarium_profiles/`). Inner-bound iteration ceiling deferred to implementation.
    /// @param pools The list of Miliarium genesis pools to seed.
    function seedFoundingPools(address[] calldata pools) external;

    /// @notice Governance-only revocation — flips `pool` from `Active` to terminally `Revoked` per **G-D17**.
    /// @dev Reverts `NotGovernance(caller)` on non-governance call; `NotGauged(pool)` if pool is not currently Active. Grace-period machinery (graduated emission reduction post-revocation) is Stage H's concern; revocation at Stage G is a binary state flip only. Cross-references: **G-D17**.
    /// @param pool The currently-Active pool to revoke.
    function revokeGauge(address pool) external;

    /// @notice Governance-only handoff — rebinds the governance authority to `newGovernance`. Stage K migration path from the Authorizer Safe to on-chain governance.
    /// @dev Reverts `NotGovernance(caller)` on non-governance call; emits `GovernanceTransferred(old, newGovernance)` on success. The Stage A–K Authorizer Safe per **CLAUDE.md** §1 is the initial governance; Stage K migrates to the on-chain governance contract per **CLAUDE.md** §2.
    /// @param newGovernance The new governance contract address.
    function setGovernanceContract(address newGovernance) external;

    /// @notice Composition-challenge Quality Gate for a candidate replacement `pool` — delegates to `IGaugeEligibility.meetsCompositionQualityGate`: ≥52% admitted-ERC-4626 weight plus the canonical fee-routing hook, without the full activation-criteria suite.
    /// @dev Stage O **O-D2** / **O-D2a** — the `GaugeRegistry` implementation forwards to its `gaugeEligibility` immutable (**G-D16d**), so `AureumGovernance` can reach the gate through its existing `GAUGE_REGISTRY` handle and the K-tagged governance constructor stays unchanged. Reverts `WrongFeeRoutingHook` (non-canonical hook) and `ForbiddenToken` (AuMM/AuMT) per the eligibility delegate; returns `false` on a sub-52% numerator. Canonical §xxvii registry-level check; supersedes K-D6e.
    /// @param pool The candidate replacement pool under evaluation.
    /// @return passes True when `pool` clears the 52% quality gate and carries the canonical hook.
    function meetsCompositionQualityGate(address pool) external view returns (bool);

    /// @notice F-10 efficiency-tournament emission cap for `pool` in basis points — delegates to `GaugeEligibility.poolEmissionCapBps`.
    /// @dev The `GaugeRegistry` implementation forwards to its `gaugeEligibility` immutable via a concrete `GaugeEligibility` cast (the mapping is concrete-only on `GaugeEligibility`, absent from `IGaugeEligibility`, per F16d). Tier values: 0 (uncapped, top 85%), 100 (bottom 15–10%, 1%), 50 (bottom 10–5%, 0.5%), 10 (bottom 5%, 0.1%). Consumed by `EmissionDistributor.recordScore` (F16f) to clamp a capped pool's emission share. Assigned each epoch by `computeEpochSnapshot`; a tournament-skipped pool retains its prior value (**P-D15 (4)**). Cross-references: **P-D13 (5)**.
    /// @param pool The pool whose F-10 emission cap is queried.
    /// @return capBps The emission cap in basis points — 0 when uncapped (top 85%), otherwise 100, 50, or 10 per the efficiency tournament tier.
    function poolEmissionCapBps(address pool) external view returns (uint256 capBps);
}
