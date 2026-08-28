// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

/// @title IIncendiaryRegistry — Stage L forward-dep interface for the per-block Incendiary boost claims registry
/// @notice Read-only surface consumed by the Stage H `EmissionDistributor` for the F-7 Step 1 Incendiary skim
///         subtraction in `_lpTrancheIntegral`'s continuous-leg sub-interval body. Returns the integrated sum
///         of active Incendiary Boost claims over a block interval.
/// @dev Per H-D29 — interval-form `integratedSkim(from, to)` returns the pre-integrated F-7 Step 1 sum over
///      `[from, to]` inclusive. Interval form (rather than per-block `claimsAt(block)`) shifts the
///      O(deltaBlocks) iteration responsibility to the registry — the canonical Stage L implementation walks
///      ONE BUCKET PER EPOCH overlapped (the L-D23 direct epoch walk, which SUPERSEDED the L-D9
///      crystallize-cache model this comment previously described as O(1) and which never shipped), so the
///      unbounded-gas vector against the distributor's `_lpTrancheIntegral` is closed on the DISTRIBUTOR
///      side instead, by PP-D47's `MAX_ACCRUAL_SPAN_BLOCKS` clamp of one epoch per accrual. Symmetric
///      composition with `_lpTrancheIntegral`'s `(from, to) → uint256` shape per H-D26. Stage H ships this
///      interface stub as a forward-dependency only — no concrete implementation under `src/incendiary/`
///      until Stage L. The distributor defaults `incendiaryRegistry = address(0)` per H-D29 so the F-7
///      continuous-leg sub-interval body returns `rate × n` (zero skim) until governance calls
///      `proposeIncendiaryRegistry(deployedRegistry)` and then `acceptIncendiaryRegistry()` after Stage L deployment. F-7 canonical spec at
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
    ///      Bodensee_apsum + Incendiary_integral = blockEmissionRate × n`. The concrete Stage L
    ///      implementation under `src/incendiary/` direct-walks its per-epoch skim buckets per L-D23 —
    ///      the interval is era-bounded by the distributor's `_lpTrancheIntegral` era-split, so no
    ///      cumulative cache is required. The `view` mutability signals read-only to the distributor;
    ///      placement and accounting functions live outside this interface and outside the distributor's
    ///      path. Reverting from this function reverts the distributor's entire accrual per H-D29 (no
    ///      `try/catch` wrap; conservative against silent skim-suppression that would over-credit LPs past
    ///      the 21M cap).
    /// @param from The starting block number of the interval (inclusive).
    /// @param to The ending block number of the interval (inclusive).
    /// @return The integrated sum of active Incendiary Boost claims over `[from, to]` in AuMM-wei
    ///         (18-decimal fixed-point).
    function integratedSkim(uint256 from, uint256 to) external view returns (uint256);

    /// @notice Returns the integrated sum of active Incendiary Boost allocations directed at `pool` over the
    ///         block interval `[from, to]` inclusive.
    /// @dev Per L-D8 / L-D12 — the per-pool delivery counterpart to `integratedSkim`. The Stage L
    ///      `EmissionDistributor` I13 fix-forward (L-D14) reads this in `_settlePool`'s per-pool boost leg and
    ///      adds `boostIntegral(pool, cursor + 1, block.number).divDown(poolTotalLP[pool])` to
    ///      `poolAccRewardPerLP[pool]`, delivering the purchased stream through the pool's existing claim path
    ///      with no new mint channel. Conservation invariant `Σ_pools boostIntegral(p, from, to) =
    ///      integratedSkim(from, to)` ties the per-pool delivery legs back to the global skim per H-D26 — the
    ///      score path emits `rate × n − skim`, the boost legs emit `Σ_pools boostIntegral = skim`, total =
    ///      full LP tranche, no over/under-mint against the 21M cap. Same epoch-bucketed O(1) accounting as
    ///      `integratedSkim` per L-D9. Reverting from this function reverts the distributor's `_settlePool`
    ///      (no `try/catch` wrap), symmetric with the `integratedSkim` posture per H-D29.
    /// @param pool The gauged pool the boost stream is directed at; the L-D10 gauge gate is enforced at
    ///        purchase, not re-checked here.
    /// @param from The starting block number of the interval (inclusive).
    /// @param to The ending block number of the interval (inclusive).
    /// @return The integrated sum of `pool`'s active Incendiary Boost allocations over `[from, to]` in
    ///         AuMM-wei (18-decimal fixed-point).
    function boostIntegral(address pool, uint256 from, uint256 to) external view returns (uint256);
}
