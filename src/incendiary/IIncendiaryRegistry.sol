// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

/// @title IIncendiaryRegistry — Stage L forward-dep interface for the per-block Incendiary boost claims registry
/// @notice Read-only surface consumed by the Stage H `EmissionDistributor` for the F-7 Step 1 Incendiary skim
///         subtraction in `_lpTrancheIntegral`'s continuous-leg sub-interval body. Returns the integrated sum
///         of active Incendiary Boost claims over a block interval.
/// @dev Per H-D29 — interval-form `integratedSkim(from, to)` returns the pre-integrated F-7 Step 1 sum over
///      `[from, to]` inclusive. Interval form (rather than per-block `claimsAt(block)`) shifts the
///      O(deltaBlocks) iteration responsibility to the registry — the canonical Stage L implementation ships
///      bucket-cached cumulative sums internally so `integratedSkim` itself stays O(1) regardless of interval
///      size, eliminating an unbounded-gas vector against the distributor's `_lpTrancheIntegral`. Symmetric
///      composition with `_lpTrancheIntegral`'s `(from, to) → uint256` shape per H-D26. Stage H ships this
///      interface stub as a forward-dependency only — no concrete implementation under `src/incendiary/`
///      until Stage L. The distributor defaults `incendiaryRegistry = address(0)` per H-D29 so the F-7
///      continuous-leg sub-interval body returns `rate × n` (zero skim) until governance calls
///      `setIncendiaryRegistry(deployedRegistry)` after Stage L deployment. F-7 canonical spec at
///      `aummfi-bit/aumm-site/11_formulas.md` F-7 — "Incendiary_total = Σ active Incendiary Boost claims this
///      block" — Step 1 per-block discipline; the `BLOCKS_PER_EPOCH` step-sampling per H-D3 applies to F-7
///      Step 2 CCB-weighted POOL share assignment, NOT to Step 1 Incendiary skim per H-D29 scope clarification.
interface IIncendiaryRegistry {
    /// @notice Returns the integrated sum of active Incendiary Boost claims over the block interval
    ///         `[from, to]` inclusive.
    /// @dev Per H-D29 + F-7 Step 1 — `Incendiary_integral(from, to) = Σ_{b=from}^{to} active_claims(b)` in
    ///      AuMM-wei (18-decimal fixed-point). The Stage H distributor reads this in `_phaseAwareBody`'s
    ///      continuous-leg sub-interval body (for `sub_from > year1EndBlock`) and subtracts from `rate × n`
    ///      to derive the LP-tranche contribution per H-D26 conservation invariant `LP_integral +
    ///      Bodensee_apsum + Incendiary_integral = blockEmissionRate × n`. Concrete Stage L implementation
    ///      under `src/incendiary/` is expected to use epoch-bucketed cumulative sums to keep
    ///      `integratedSkim` O(1); a permissionless `crystallize(from, to)` cache-update helper on the
    ///      registry side is the standard pattern. The `view` mutability signals read-only to the
    ///      distributor — cache-update functions live outside this interface and outside the distributor's
    ///      path. Reverting from this function reverts the distributor's entire accrual per H-D29 (no
    ///      `try/catch` wrap; conservative against silent skim-suppression that would over-credit LPs past
    ///      the 21M cap).
    /// @param from The starting block number of the interval (inclusive).
    /// @param to The ending block number of the interval (inclusive).
    /// @return The integrated sum of active Incendiary Boost claims over `[from, to]` in AuMM-wei
    ///         (18-decimal fixed-point).
    function integratedSkim(uint256 from, uint256 to) external view returns (uint256);
}
