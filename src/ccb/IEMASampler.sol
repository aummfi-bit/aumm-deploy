// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title IEMASampler — read-only EMA accessors for CCB multiplier reads
/// @notice `CCBMultiplier` reads per-pool TVL EMA values through this interface — it never calls `updateEMA`; the write-side stays on the concrete `EMASampler` per F-D22.
/// @dev F-D22 (`STAGE_F_NOTES.md` L274-L313) defines this read-only contract.
///      F-D5 / F-D6: per-day EMA refresh is cadence-independent from per-epoch multiplier refresh.
///      `EMASampler.sol` (F1.3) `public tvlEMA` and `public lastEMAUpdateBlock` mappings satisfy this interface via Solidity auto-generated getters with no explicit `is IEMASampler` declaration.
///      Stage H is the natural ordering layer that refreshes EMA before calling `updateMultiplier`.
interface IEMASampler {
    /// @notice Per-pool TVL EMA consumed by `CCBMultiplier`'s F-8 evolution — the `delta_intra_i` per-pool channel and `protocolTVLEMA` sum-of-EMAs per `OQ-23 (iii.b)`.
    /// @param pool The Balancer V3 pool address.
    /// @return The current TVL EMA for `pool`.
    function tvlEMA(address pool) external view returns (uint256);

    /// @notice Block number of the most recent successful `updateEMA` for `pool` — reserved for a future stale-EMA guard at Stage H per F-D22 L289.
    /// @param pool The Balancer V3 pool address.
    /// @return The block number of the last EMA update for `pool`.
    function lastEMAUpdateBlock(address pool) external view returns (uint256);
}
