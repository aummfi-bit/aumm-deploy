// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAureumProtocolFeeControllerHookExtension}
    from "../../src/fee_router/IAureumProtocolFeeControllerHookExtension.sol";

/// @title  MockFeeController
/// @notice Test-only stub for `IAureumProtocolFeeControllerHookExtension`.
///         Records per-pool forward schedules configured by the test and,
///         on `collectSwapAggregateFeesForHook`, transfers the scheduled
///         tokens to `msg.sender` (the hook under test) and emits the
///         corresponding `SwapLegFeeForwarded` events.
/// @dev    Used as the `feeController_` fixture in
///         `test/unit/AureumFeeRoutingHook.t.sol`. The mock is
///         intentionally ungated: tests drive it directly to exercise
///         both the hook-triggered path (via `onAfterSwap`) and the
///         direct-call path. The test is responsible for pre-funding the
///         mock with the token balances it is configured to forward.
///         Each `collectSwapAggregateFeesForHook(pool)` call drains the
///         schedule for `pool`, matching the real controller's "pool
///         aggregate-fee slots are emptied per call" semantics.
contract MockFeeController is IAureumProtocolFeeControllerHookExtension {
    using SafeERC20 for IERC20;

    mapping(address => IERC20[]) private _tokens;
    mapping(address => uint256[]) private _amounts;

    /// @notice Configure the schedule for `pool`. Replaces any previously
    ///         configured schedule. `tokens_` and `amounts_` must be
    ///         equal length.
    function setForward(
        address pool,
        IERC20[] calldata tokens_,
        uint256[] calldata amounts_
    ) external {
        require(tokens_.length == amounts_.length, "MockFeeController: length mismatch");
        delete _tokens[pool];
        delete _amounts[pool];
        for (uint256 i = 0; i < tokens_.length; ++i) {
            _tokens[pool].push(tokens_[i]);
            _amounts[pool].push(amounts_[i]);
        }
    }

    /// @inheritdoc IAureumProtocolFeeControllerHookExtension
    function collectSwapAggregateFeesForHook(
        address pool
    ) external override returns (IERC20[] memory tokens, uint256[] memory forwardedAmounts) {
        tokens = _tokens[pool];
        forwardedAmounts = _amounts[pool];
        delete _tokens[pool];
        delete _amounts[pool];

        uint256 len = tokens.length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 amount = forwardedAmounts[i];
            if (amount == 0) continue;
            tokens[i].safeTransfer(msg.sender, amount);
            emit SwapLegFeeForwarded(pool, address(tokens[i]), amount);
        }
    }
}
