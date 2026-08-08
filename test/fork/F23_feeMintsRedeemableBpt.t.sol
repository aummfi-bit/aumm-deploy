// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { StagePIntegrationFixture } from "test/fork/StagePIntegration.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    PoolConfig,
    SwapKind,
    VaultSwapParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

/**
 * @title F23_FeeMintsRedeemableBpt
 * @notice F-23 PoC (PB-D68 rung b). Records CURRENT behaviour of
 *         `AureumFeeRoutingHook._addLiquidityOneSidedToBodenseeViaVault`: a protocol-fee route
 *         deposits into der Bodensee with `AddLiquidityKind.UNBALANCED` and mints redeemable BPT
 *         to the hook, where the value-capture model requires irreversible depth. Expected to
 *         INVERT at the F-23 fix, when the shared helper moves to `AddLiquidityKind.DONATION` and
 *         BPT stops being minted, per PB-D68 (v).
 * @dev Positive control already on tree: `test/fork/StageGIntegration.t.sol` asserts der Bodensee
 *      BPT `totalSupply` UNCHANGED on the donation paths through `SwapAndDepositToBodensee`, so
 *      both mechanisms are already exercised side by side against forked state and only the fee
 *      path is on the wrong one.
 */
contract F23_FeeMintsRedeemableBpt is StagePIntegrationFixture {
    /// @notice Premise. Der Bodensee was created with donation enabled, so DONATION was available
    ///         to the hook from the first block and is not a hypothetical alternative.
    function test_F23_premise_bodenseeAcceptsDonation() public view {
        PoolConfig memory config = vault.getPoolConfig(bodenseePool);
        assertTrue(
            config.liquidityManagement.enableDonation,
            "premise: der Bodensee enableDonation is true"
        );
    }

    /// @notice The defect. A protocol-fee route mints redeemable BPT to the hook — a claim on
    ///         depth the spec requires to be irreversible.
    function test_F23_feeRouteMintsRedeemableBpt() public {
        uint256 supplyBefore = IERC20(bodenseePool).totalSupply();
        uint256 hookBptBefore = IERC20(bodenseePool).balanceOf(address(hook));

        uint256 amountOut = _performSwap(pilotPools[0], IERC20(address(susds)), svZchf, 1e18);
        assertGt(amountOut, 0, "swap produced output");

        assertGt(
            IERC20(bodenseePool).totalSupply(),
            supplyBefore,
            "DEFECT: BPT minted on a protocol-fee route (totalSupply rose); redeemable claim on depth the spec requires to be irreversible"
        );
        assertGt(
            IERC20(bodenseePool).balanceOf(address(hook)),
            hookBptBefore,
            "DEFECT: hook BPT balance rose on a protocol-fee route; redeemable claim on depth the spec requires to be irreversible"
        );
    }

    /// @notice Aggravating condition. After a fee route the hook holds BPT, and
    ///         `AureumFeeRoutingHook` declares no sweep, rescue, withdraw, recover, skim or
    ///         transfer entry, so the claim is inert by omission rather than by construction.
    /// @dev Do not attempt to call a non-existent function; the absence itself is the point.
    function test_F23_mintedBptIsUnreachable() public {
        uint256 amountOut = _performSwap(pilotPools[0], IERC20(address(susds)), svZchf, 1e18);
        assertGt(amountOut, 0, "swap produced output");

        assertGt(
            IERC20(bodenseePool).balanceOf(address(hook)),
            0,
            "hook holds BPT after fee route, with no path to move it"
        );
    }

    /// @dev Mirrored from StagePEndToEndTest / PilotPools — two-arg deal per E10; plain transfer.
    function _performSwap(address pool, IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        deal(address(tokenIn), address(this), amountIn);
        bytes memory result =
            vault.unlock(abi.encodeCall(this._performSwapCallback, (pool, tokenIn, tokenOut, amountIn)));
        amountOut = abi.decode(result, (uint256));
    }

    function _performSwapCallback(address pool, IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn)
        external
        returns (uint256 amountOut)
    {
        require(msg.sender == address(vault), "onlyVault");
        (, uint256 inUsed, uint256 outRcvd) = vault.swap(
            VaultSwapParams({
                kind: SwapKind.EXACT_IN,
                pool: pool,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountGivenRaw: amountIn,
                limitRaw: 0,
                userData: ""
            })
        );
        tokenIn.transfer(address(vault), inUsed);
        vault.settle(tokenIn, inUsed);
        vault.sendTo(tokenOut, address(this), outRcvd);
        amountOut = outRcvd;
    }
}
