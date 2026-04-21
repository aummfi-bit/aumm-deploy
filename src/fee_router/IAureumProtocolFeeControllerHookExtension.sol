// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title  IAureumProtocolFeeControllerHookExtension
/// @notice Extension surface on AureumProtocolFeeController for the
///         swap-leg custody transfer invoked by AureumFeeRoutingHook.
/// @dev    Declares only the β1-new surface — the concrete controller
///         implements this alongside its upstream Balancer V3 base at
///         Stage D4. Rationale, β1 semantics, and the keeper/hook
///         asymmetry are documented in STAGE_D_NOTES.md D17.
interface IAureumProtocolFeeControllerHookExtension {
    // -----------------------------------------------------------------
    //                              Events
    // -----------------------------------------------------------------

    /// @notice Emitted per non-zero token forwarded from the controller
    ///         to AureumFeeRoutingHook by collectSwapAggregateFeesForHook.
    /// @param  pool    Pool whose aggregate swap-fee slot was drained.
    /// @param  token   Token the forwarded amount is denominated in.
    /// @param  amount  Amount forwarded in `token` decimals.
    event SwapLegFeeForwarded(
        address indexed pool,
        address indexed token,
        uint256 amount
    );

    // -----------------------------------------------------------------
    //                              Errors
    // -----------------------------------------------------------------

    /// @notice Thrown when collectSwapAggregateFeesForHook is invoked
    ///         by any address other than the AureumFeeRoutingHook
    ///         pinned at controller-construction.
    error OnlyFeeRoutingHook(address caller);

    // -----------------------------------------------------------------
    //                        External primitives
    // -----------------------------------------------------------------

    /// @notice Drain the aggregate swap-fee slots of `pool` and forward
    ///         them to the AureumFeeRoutingHook; the yield leg drains
    ///         via the unchanged upstream path.
    /// @dev    Gated to AureumFeeRoutingHook — MUST be called inside a
    ///         Vault unlock, which is satisfied when the call originates
    ///         from onAfterSwap. Emits SwapLegFeeForwarded per non-zero
    ///         forwarded token.
    /// @param  pool              Pool to drain.
    /// @return tokens            Pool token list in the Vault's
    ///                           canonical registration order.
    /// @return forwardedAmounts  Amount of each `tokens[i]` now on the
    ///                           AureumFeeRoutingHook balance.
    function collectSwapAggregateFeesForHook(
        address pool
    )
        external
        returns (
            IERC20[] memory tokens,
            uint256[] memory forwardedAmounts
        );
}
