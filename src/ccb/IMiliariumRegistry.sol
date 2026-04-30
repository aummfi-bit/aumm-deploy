// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title IMiliariumRegistry — Miliarium pool membership and enumeration for CCB
/// @notice Membership gate and index-ordered pool list consumed by `CCBMultiplier` under F-D9 — Miliarium-only multiplier scope and protocol-aggregate-EMA enumeration per OQ-23 (iii.b).
/// @dev F-D9 (`STAGE_F_PLAN.md` L63): multiplier updates apply only to Miliarium pools; non-Miliarium gauged pools score with `CCB_mult = 1.0`.
///      OQ-23 (iii.b): protocol-aggregate TVL EMA is the sum of per-pool EMAs over pools enumerated here.
///      `04_tokenomics.md` §vii: fixed 28-pool Miliarium constellation — the pool-average divisor lives in `CCBMultiplier.sol`, not this interface (per F-D16).
///      Concrete registry: Stage J `MiliariumRegistry.sol`. Pre-Stage-J placeholder: `isMiliarium` returns `false`, `miliariumPoolsCount` returns `0`, and out-of-bounds `miliariumPoolAt` may revert — implementor-defined.
interface IMiliariumRegistry {
    /// @notice Whether `pool` is a registered Miliarium pool for CCB multiplier and aggregate EMA purposes.
    /// @param pool The Balancer V3 pool address.
    /// @return True if `pool` is a Miliarium member; otherwise false.
    function isMiliarium(address pool) external view returns (bool);

    /// @notice Number of Miliarium pools in the canonical enumeration (upper bound for valid `miliariumPoolAt` indices).
    /// @return Count of registered Miliarium pools.
    function miliariumPoolsCount() external view returns (uint256);

    /// @notice Miliarium pool address at `index` in implementation-defined canonical order.
    /// @param index Zero-based index into the Miliarium pool list.
    /// @return The pool address stored at `index` when in range.
    function miliariumPoolAt(uint256 index) external view returns (address);
}
