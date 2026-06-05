// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title  IRouterSender
/// @notice Minimal view of the Balancer V3 Router's sender accessor.
/// @dev The Aureum fee-routing hook needs only `getSender()` to resolve the
///      liquidity provider inside its `onAfterAddLiquidity` /
///      `onAfterRemoveLiquidity` callbacks. The full Balancer
///      `IRouterCommon` is not importable here: it transitively imports
///      `permit2/src/interfaces/IAllowanceTransfer.sol`, and this project
///      neither vendors nor remaps Permit2 (D32 — Aureum's fork init avoids
///      the Router and Permit2 entirely). This shim declares only the single
///      method the hook calls; its function selector is identical to
///      `IRouterCommon.getSender()`, so the runtime call against the real
///      mainnet Router is byte-identical.
interface IRouterSender {
    /// @notice Get the first sender which initialized the call to Router.
    /// @return sender The address of the sender.
    function getSender() external view returns (address sender);
}
