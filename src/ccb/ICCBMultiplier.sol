// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

/// @title ICCBMultiplier — Aureum CCB multiplier interface (RB-005 Stage H retrofit)
/// @notice Per-pool `CCB_mult` accessor used by F-7 Step 3 (CCB-weighted scoring) per `11_formulas.md`;
///         consumed by the Stage H emission distributor in the score formula
///         `Score(pool_i) = TVL_EMA60(pool_i) × CCB_mult(pool_i)`.
/// @dev Stage F shipped `src/ccb/CCBMultiplier.sol` as a concrete contract without an extracted interface;
///      Stage H needs a typed cross-contract handle for the emission-distributor call site (this is an
///      interface-only retrofit, no changes to the Stage F concrete contract or its deployment bytecode).
///      Robustness Backport register entry RB-005 — propagation of the typed-domain hygiene to Stage F itself
///      (adding `is ICCBMultiplier` to the concrete contract) is left to a future review and is NOT done here.
///      Return-value contract per `FINDINGS.md` OQ-23: `1e18` for non-Miliarium pools, `1.2e18` while the
///      (deprecated-at-G-D13) 90-day boost gate would have been active — the gate is retained as a no-op at
///      Stage G close so Stage H consumes the unconditional `M_i[pool]` path in practice — or the latest
///      evolved `M_i[pool]` otherwise; all return values are 18-decimal fixed-point.
interface ICCBMultiplier {
    /// @notice — per-pool CCB multiplier `CCB_mult(pool)` in 18-decimal fixed-point.
    /// @dev — cross-references OQ-23 for the full return-value contract and the F-7 Step 3 consumer formula
    ///      `Score(pool_i) = TVL_EMA60(pool_i) × CCB_mult(pool_i)`.
    /// @param pool — the Balancer V3 pool address.
    /// @return multiplier — `CCB_mult(pool)` as 18-decimal fixed-point (1e18 = 1.0); see OQ-23 for the
    ///                     three return-value regimes.
    function getMultiplier(address pool) external view returns (uint256 multiplier);
}
