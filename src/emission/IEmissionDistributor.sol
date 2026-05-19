// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

/// @title IEmissionDistributor — Stage H pool-scoped emission distributor interface
/// @notice Exposes the externally-observable consumer surface for the pool-scoped emission distributor:
///         claim entry for AuMT holders, record-deposit and record-withdrawal entry for the Stage I AuMT
///         contract, permissionless `recordScore`, governance setters, and views over the H-D22 two-tier
///         storage (global accumulator tier, per-pool tier, per-user tier).
/// @dev Per H-D4 pull / lazy-accrual via MasterChef-style `accRewardPerScoreUnit`. Per H-D5 incremental
///      `totalScore` aggregate with `isGaugeApproved` per-call gate. Per H-D15 two-tier accumulator
///      topology — solitary global `accRewardPerScoreUnit` plus per-pool `poolAccDebt` lazy settle. Per
///      H-D16 per-user maps shipped at H4 plus governance-settable `auMTContract` recorder slot. Per H-D17
///      permissionless `recordScore` with `CCBScore` library delegation and revoked-gauge revert. Per H-D19
///      absolute `newScore` external ABI with F12 signed-delta middleware on `totalScore`. Per H-D20
///      `IAuMM.mint` at claim time only — not at `_settlePool`. Per H-D21 lazy accrual tick on every
///      mutating entry. Per H-D22 two-tier storage layout (global + per-pool + per-user tiers plus
///      immutables). Per H-D23 `recordEmissions` push at `_settlePool` boundary — allocation-side F-10
///      semantics; claim does NOT add a second push. Forward-dep `IEfficiencyOracle.recordEmissions` retrofit
///      lands at sibling sub-step H4.1.x-bis (mirrors H2a.10c `ITVLOracle.quoteSvZCHF` retrofit plus G16
///      inheritor-enumeration discipline). Concrete `EmissionDistributor` lands at H4.2 onward in
///      `src/emission/EmissionDistributor.sol`.
interface IEmissionDistributor {
    /// @notice Emitted when `recordScore` writes a new absolute score for `pool`.
    /// @dev Records the oldScore → newScore transition per H-D17 (f) after the H-D19 signed-delta
    ///      middleware updates `totalScore` and writes `poolScore[pool]`.
    /// @param pool The Balancer V3 pool address whose score was updated.
    /// @param oldScore The prior F-5 score before this `recordScore` invocation.
    /// @param newScore The absolute new score written to `poolScore[pool]`.
    event ScoreUpdated(address indexed pool, uint256 oldScore, uint256 newScore);

    /// @notice Emitted when the AuMT contract records a deposit for `user` in `pool`.
    /// @dev Per H-D16 single-snapshot MasterChef variant and H-D4 pull semantics — deposit triggers
    ///      accrual against the pre-deposit stake.
    /// @param pool The Balancer V3 pool address.
    /// @param user The AuMT holder whose stake increased.
    /// @param amount The AuMT amount deposited (same unit as `userLP`).
    event DepositRecorded(address indexed pool, address indexed user, uint256 amount);

    /// @notice Emitted when the AuMT contract records a withdrawal for `user` in `pool`.
    /// @dev Per H-D16 and H-D4 — withdrawal stops accrual immediately after settle-then-decrement.
    /// @param pool The Balancer V3 pool address.
    /// @param user The AuMT holder whose stake decreased.
    /// @param amount The AuMT amount withdrawn (same unit as `userLP`).
    event WithdrawalRecorded(address indexed pool, address indexed user, uint256 amount);

    /// @notice Emitted when `claim` mints AuMM to `to` on behalf of `claimer`.
    /// @dev Per H-D20 — emitted after `IAuMM.mint(to, amount)` when `amount > 0`. The `claimer` is
    ///      `msg.sender` of the `claim` call; `to` is the mint recipient and supports delegated claims.
    /// @param pool The Balancer V3 pool address from which rewards are claimed.
    /// @param claimer The address that invoked `claim` (`msg.sender`).
    /// @param to The AuMM mint recipient.
    /// @param amount The AuMM amount minted (18-decimal fixed-point).
    event Claimed(address indexed pool, address indexed claimer, address indexed to, uint256 amount);

    /// @notice Emitted when governance rebinds the `governance` slot.
    /// @dev Per H-D14 / H-D10 governance setter precedent — mirrors TVLOracle and EfficiencyOracle
    ///      `setGovernanceContract` pattern.
    /// @param oldGovernance The prior governance address.
    /// @param newGovernance The new governance address (must be non-zero per H-D14).
    event GovernanceTransferred(address indexed oldGovernance, address indexed newGovernance);

    /// @notice Emitted when governance rebinds the `auMTContract` recorder slot.
    /// @dev Per H-D16 recorder-slot pattern — mirrors H-D10 EfficiencyOracle `setEmissionsRecorder` /
    ///      `setFeeRecorder` analogue. Zero address is acceptable as deprecation safety valve.
    /// @param oldAuMTContract The prior AuMT recorder address.
    /// @param newAuMTContract The new AuMT recorder address (zero address permitted).
    event AuMTContractSet(address indexed oldAuMTContract, address indexed newAuMTContract);

    /// @notice Thrown when `recordScore` is called for a pool that is not gauge-approved.
    /// @dev Per H-D17 (a) and H-D5 per-call `isGaugeApproved` gate — prevents `totalScore` corruption
    ///      from stale recordings on revoked gauges.
    /// @param pool The pool address that failed the approval check.
    error NotApproved(address pool);

    /// @notice Thrown when `recordDeposit` or `recordWithdrawal` is invoked by a non-recorder caller.
    /// @dev Per H-D16 recorder-slot gate — pre-Stage-I posture with `auMTContract == address(0)` causes
    ///      all callers to revert because `msg.sender` cannot equal zero in external-call contexts.
    /// @param caller The address that failed the `auMTContract` equality check.
    error NotAuMTContract(address caller);

    /// @notice Thrown when a governance-only entry is invoked by a non-governance caller.
    /// @dev Per H-D14 / H-D10 governance setter precedent.
    /// @param caller The address that failed the `governance` equality check.
    error NotGovernance(address caller);

    /// @notice Thrown when a zero address is supplied where it is forbidden.
    /// @dev Used by `setGovernanceContract` — new governance must be non-zero per H-D14 precedent.
    ///      `setAuMTContract` does NOT revert on zero because zero is the H-D16 deprecation safety valve.
    error ZeroAddress();

    /// @notice Permissionlessly records the current F-5 score for `pool` and updates `totalScore`.
    /// @dev Sequence per H-D17: (a) revert `NotApproved(pool)` if gauge revoked; (b) run `_accrueGlobal`
    ///      then `_settlePool(pool)` per H-D21 lazy tick; (c) compute `newScore` via
    ///      `CCBScore.score(emaSampler.tvlEMA(pool), ccbMultiplier.getMultiplier(pool))`; (d) apply H-D19
    ///      signed-delta middleware to `totalScore`; (e) write `poolScore[pool] = newScore`; (f) emit
    ///      `ScoreUpdated`. Cross-refs H-D5, H-D17, H-D19, F-5, OQ-23.
    /// @param pool The Balancer V3 pool address whose score is being recorded.
    function recordScore(address pool) external;

    /// @notice Records a deposit of `amount` AuMT for `user` in `pool` — AuMT-recorder gated.
    /// @dev Per H-D16 single-snapshot MasterChef variant: revert if `msg.sender != auMTContract`; run
    ///      `_accrueGlobal` then `_settlePool` then settle the user's pending claim against pre-deposit
    ///      `userLP`; increment `userLP[pool][user]` and `poolTotalLP[pool]` by `amount`; update
    ///      `userRewardDebt[pool][user]` to the new pool-effective accumulator; emit `DepositRecorded`.
    ///      Cross-refs H-D4 pull semantics, H-D16, H-D21.
    /// @param pool The Balancer V3 pool address.
    /// @param user The AuMT holder receiving the stake credit.
    /// @param amount The AuMT amount deposited.
    function recordDeposit(address pool, address user, uint256 amount) external;

    /// @notice Records a withdrawal of `amount` AuMT for `user` in `pool` — AuMT-recorder gated.
    /// @dev Symmetric to `recordDeposit` per H-D16: revert if `msg.sender != auMTContract`; settle user
    ///      pending against pre-withdrawal `userLP`; decrement `userLP[pool][user]` and
    ///      `poolTotalLP[pool]` by `amount`; update `userRewardDebt`; emit `WithdrawalRecorded`. Cross-refs
    ///      H-D4, H-D16, H-D21.
    /// @param pool The Balancer V3 pool address.
    /// @param user The AuMT holder whose stake is reduced.
    /// @param amount The AuMT amount withdrawn.
    function recordWithdrawal(address pool, address user, uint256 amount) external;

    /// @notice Claims accrued AuMM rewards for `msg.sender` in `pool`, minting to `to`.
    /// @dev Per H-D20 sequence: run `_accrueGlobal` then `_settlePool` then settle the caller against the
    ///      pool-effective accumulator; compute `amount = pendingClaim(pool, msg.sender)`; zero-amount
    ///      short-circuit (no `IAuMM.mint`, no event); otherwise `IAuMM.mint(to, amount)`, update
    ///      `userRewardDebt[pool][msg.sender]`, emit `Claimed(pool, msg.sender, to, amount)`. Per H-D23,
    ///      `claim` does NOT add a second `recordEmissions` push — push lands at `_settlePool`. Cross-refs
    ///      H-D20, H-D21, H-D23.
    /// @param pool The Balancer V3 pool address from which rewards are claimed.
    /// @param to The AuMM mint recipient — supports delegated claims.
    function claim(address pool, address to) external;

    /// @notice Rebinds the `governance` slot — governance-only.
    /// @dev Reverts `ZeroAddress` if `newGovernance == address(0)` per H-D14 precedent. Swaps old/new,
    ///      emits `GovernanceTransferred`. Cross-refs H-D14, H-D10.
    /// @param newGovernance The new governance contract address (must be non-zero).
    function setGovernanceContract(address newGovernance) external;

    /// @notice Rebinds the `auMTContract` recorder slot — governance-only.
    /// @dev Zero address is acceptable per H-D16 deprecation safety valve — mirrors EfficiencyOracle
    ///      `setEmissionsRecorder`. Swaps old/new, emits `AuMTContractSet`. Cross-refs H-D16, H-D10
    ///      recorder-slot pattern.
    /// @param newAuMTContract The new Stage I AuMT contract address (zero permitted).
    function setAuMTContract(address newAuMTContract) external;

    /// @notice Returns the global `accRewardPerScoreUnit` accumulator.
    /// @dev Global tier per H-D22 — FixedPoint 18-decimal accumulator advancing on every `_accrueGlobal`
    ///      non-zero-`totalScore` interval per H-D15.
    /// @return The current global reward-per-score-unit accumulator (18-decimal fixed-point).
    function accRewardPerScoreUnit() external view returns (uint256);

    /// @notice Returns the aggregate score across all approved gauges.
    /// @dev Global tier per H-D22 — Σ `poolScore` over approved gauges, updated only through the H-D19
    ///      signed-delta middleware.
    /// @return The current `totalScore` (18-decimal fixed-point scale).
    function totalScore() external view returns (uint256);

    /// @notice Returns the block number of the most recent `_accrueGlobal` invocation.
    /// @dev Global tier per H-D22 — most recent accrual block per H-D21 lazy tick.
    /// @return The block number through which global accrual has been recorded.
    function lastAccrualBlock() external view returns (uint256);

    /// @notice Returns the recorded F-5 score for `pool`.
    /// @dev Per-pool tier per H-D22 — absolute `TVL_EMA × CCB_mult` score written by `recordScore` per
    ///      H-D17 (e).
    /// @param pool The Balancer V3 pool address.
    /// @return The current `poolScore[pool]` (18-decimal fixed-point).
    function poolScore(address pool) external view returns (uint256);

    /// @notice Returns the per-pool snapshot of `accRewardPerScoreUnit` at last `_settlePool`.
    /// @dev Per-pool tier per H-D22 — lazy-settle debt snapshot per H-D15.
    /// @param pool The Balancer V3 pool address.
    /// @return The `poolAccDebt[pool]` snapshot value.
    function poolAccDebt(address pool) external view returns (uint256);

    
    /// @notice Returns the per-pool acc-reward-per-LP-unit accumulator for `pool`.
    /// @dev Per-pool tier per H-D22 / H-D24 — FixedPoint 18-decimal AuMM-wei-per-LP-unit accumulator advanced by `_settlePool` after the H-D23 EfficiencyOracle push (skip-on-zero-LP semantic per H-D24). Source for `userRewardDebt` snapshot at user-settle time (H4.6) and `pendingClaim` derivation (H4.7).
    /// @param pool The Balancer V3 pool address.
    /// @return The current `poolAccRewardPerLP[pool]` accumulator (18-decimal fixed-point).
    function poolAccRewardPerLP(address pool) external view returns (uint256);

    /// @notice Returns the total AuMT stake recorded in `pool`.
    /// @dev Per-pool tier per H-D22 — Σ `userLP[pool][*]`, needed for per-user share computation at settle
    ///      time per H-D22.
    /// @param pool The Balancer V3 pool address.
    /// @return The current `poolTotalLP[pool]`.
    function poolTotalLP(address pool) external view returns (uint256);

    /// @notice Returns the AuMT stake of `user` in `pool`.
    /// @dev Per-user tier per H-D22 — the user's AuMT stake in `pool` per H-D16.
    /// @param pool The Balancer V3 pool address.
    /// @param user The AuMT holder address.
    /// @return The current `userLP[pool][user]`.
    function userLP(address pool, address user) external view returns (uint256);

    /// @notice Returns the per-user reward-debt snapshot for `user` in `pool`.
    /// @dev Per-user tier per H-D22 — single-snapshot variant analogous to `poolAccDebt`, computed against
    ///      pool-effective acc-per-LP-unit at settle time per H-D16.
    /// @param pool The Balancer V3 pool address.
    /// @param user The AuMT holder address.
    /// @return The current `userRewardDebt[pool][user]`.
    function userRewardDebt(address pool, address user) external view returns (uint256);

    /// @notice Returns the unclaimed AuMM reward balance for `user` in `pool`.
    /// @dev H1 forward-dep producer view per STAGE_H_NOTES.md L177 — derives
    ///      `(poolAccRewardPerLP[pool] − userRewardDebt[pool][user]).mulDown(userLP[pool][user])` per H-D16 / H-D24 single-snapshot MasterChef variant.
    ///      `poolEffectiveAccPerLPunit` from H-D16 prose binds to `poolAccRewardPerLP[pool]` literally per H-D24; the FixedPoint mulDown form replaces the H-D16 prose's bare multiplication and matches the AuMM-wei output unit.
    ///      Consumed by Stage I AuMT for pre-claim balance display.
    /// @param pool The Balancer V3 pool address.
    /// @param user The AuMT holder address.
    /// @return The pending AuMM claim amount (18-decimal fixed-point).
    function pendingClaim(address pool, address user) external view returns (uint256);

    /// @notice Returns the current governance contract address.
    /// @dev Governance slot per H-D22 — mutable address pivotable via `setGovernanceContract` per H-D14 /
    ///      H-D10 precedent.
    /// @return The governance contract address.
    function governance() external view returns (address);

    /// @notice Returns the current AuMT recorder contract address.
    /// @dev Recorder slot per H-D22 / H-D16 — `address(0)` is the pre-Stage-I and deprecated-recorder
    ///      safety-valve posture per H-D16.
    /// @return The AuMT contract address authorized to call `recordDeposit` / `recordWithdrawal`.
    function auMTContract() external view returns (address);
}
