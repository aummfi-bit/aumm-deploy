// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

/// @title IEfficiencyOracle — Aureum Gauge F-10 efficiency oracle interface
/// @notice Returns pre-smoothed F-10 efficiency inputs for a Balancer V3 pool — the numerator
///         (`swap_fee_revenue_i + yield_fee_revenue_i`) and denominator (`emissions_received_i`) of the
///         canonical OQ-G1 formula, both 3-epoch SMA-smoothed at oracle scope.
/// @dev Per G-D23 (i) the oracle owns the 3-epoch SMA; `GaugeEligibility.computeEpochSnapshot` reads
///      pre-smoothed inputs and computes the dimensionless ratio `(numeratorSma * 1e18) / denominatorSma`.
///      Per G-D23 (ii) this interface is a sibling to `ITVLOracle` — not an extension — so the F-10
///      efficiency path and the OQ-G2 TVL-floor path remain independently swappable.
///      F-10 is price-agnostic per `11_formulas.md` — `numeratorSma` and `denominatorSma` must be expressed in
///      the same unit (the ratio is dimensionless); this interface does NOT lock svZCHF or any other
///      numéraire on either return value.
///      `efficiencyInputs` concrete shipped at H2b in `src/emission/EfficiencyOracle.sol` per H-D10 v2 (intra-epoch accumulation with EpochEntry[3] ring buffer + 3-epoch SMA at oracle scope). The `recordEmissions(address,uint256)` push entry point landed in-place at H4.1.x-bis per H-D23 (allocation-side F-10 semantics — emission-distributor wiring at H4 invokes this at the `_settlePool` boundary after `_accrueGlobal` and before `poolAccDebt` is rebased; mirrors the H2a.10c `quoteSvZCHF` retrofit on `ITVLOracle`).
interface IEfficiencyOracle {
    /// @notice Pre-smoothed F-10 efficiency inputs for `pool` per OQ-G1.
    /// @param pool The Balancer V3 pool address.
    /// @return numeratorSma The 3-epoch SMA of `swap_fee_revenue_i + yield_fee_revenue_i` (1e18 fixed-point).
    /// @return denominatorSma The 3-epoch SMA of `emissions_received_i` (same unit as `numeratorSma`).
    function efficiencyInputs(address pool) external view returns (uint256 numeratorSma, uint256 denominatorSma);

    /// @notice Records a per-pool AuMM emissions allocation per H-D23 — push signature called by `EmissionDistributor._settlePool` after `_accrueGlobal` and before `poolAccDebt` is rebased; allocation-side F-10 semantics.
    /// @dev Per H-D23 this is the accrual-time push entry point invoked at the `_settlePool` boundary inside the emission distributor — `aummAmountScaled18` is what was allocated to the pool at the most recent boundary, not literal mint (F-10 denominator semantics are allocation-side per `11_formulas.md`). The concrete oracle at `src/emission/EfficiencyOracle.sol` converts `aummAmountScaled18` to svZCHF via `tvlOracle.quoteSvZCHF(AuMM, ...)` per H-D10 v2 and accumulates into the intra-epoch denominator; mocks may stub as a no-op since unit tests pin `efficiencyInputs` directly.
    /// @param pool The Balancer V3 pool address whose F-10 denominator is being credited.
    /// @param aummAmountScaled18 The 18-decimal fixed-point AuMM emissions amount allocated to `pool` at the most recent `_settlePool` boundary per Balancer V3 `balancesLiveScaled18` convention.
    function recordEmissions(address pool, uint256 aummAmountScaled18) external;
}
