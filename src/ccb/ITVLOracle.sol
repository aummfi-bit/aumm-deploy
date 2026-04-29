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
}
