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
///      Concrete implementation deferred to Stage H emission-distributor wiring (mirrors the OQ-22
///      carry-forward for `ITVLOracle` per `CLAUDE.md` §11 deferred items).
interface IEfficiencyOracle {
    /// @notice Pre-smoothed F-10 efficiency inputs for `pool` per OQ-G1.
    /// @param pool The Balancer V3 pool address.
    /// @return numeratorSma The 3-epoch SMA of `swap_fee_revenue_i + yield_fee_revenue_i` (1e18 fixed-point).
    /// @return denominatorSma The 3-epoch SMA of `emissions_received_i` (same unit as `numeratorSma`).
    function efficiencyInputs(address pool) external view returns (uint256 numeratorSma, uint256 denominatorSma);
}
