// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title ITVLOracle — Aureum CCB TVL oracle interface
/// @notice Returns svZCHF-denominated TVL for a Balancer V3 pool.
/// @dev Per FINDINGS OQ-22 (TVL / ITVLOracle, FINDINGS L1102): TVL denomination = svZCHF;
///      per-token valuation = RP-aware unwrap + constellation-spot averaging;
///      concrete implementation deferred to the OQ-22 resolution stage (post-Stage F per F-D3).
///      Interface shape pinned at 18-decimal svZCHF return.
interface ITVLOracle {
    /// @notice Spot TVL for `pool`, denominated in svZCHF at 18 decimals.
    /// @param pool The Balancer V3 pool address.
    /// @return Pool TVL in svZCHF (18 decimals).
    function tvl(address pool) external view returns (uint256);

    /// @notice Converts `amountScaled18` of `token` to its svZCHF-denominated equivalent at 18 decimals.
    /// @dev Per H-D9 / H-D10 v2 (H1.9-bis): skip-on-zero semantics — returns 0 if `token` is unmapped in the oracle's per-token underlying registry, or if no constellation venue prices the underlying in svZCHF. Required by Stage H `EfficiencyOracle` per H-D10 to denominate F-10 numerator and denominator in svZCHF for G-D23(i) same-unit compliance. Interface declaration added at H2a.10c retrofit (concrete `quoteSvZCHF` landed at H2a.10a).
    /// @param token The pool token whose svZCHF valuation is queried.
    /// @param amountScaled18 The amount of `token`, in 18-decimal fixed-point per Balancer V3 `balancesLiveScaled18` convention.
    /// @return svZCHFAmountScaled18 The svZCHF-denominated equivalent in 18-decimal fixed-point; 0 when `token` is unmapped or has no constellation venue.
    function quoteSvZCHF(address token, uint256 amountScaled18) external view returns (uint256 svZCHFAmountScaled18);
}
