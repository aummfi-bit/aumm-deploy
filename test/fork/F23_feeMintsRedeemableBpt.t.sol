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
 * @notice F-23 regression witness. Was the PoC at PB-D68 rung b, where it recorded the defect:
 *         `AureumFeeRoutingHook._addLiquidityOneSidedToBodenseeViaVault` deposited into der
 *         Bodensee with `AddLiquidityKind.UNBALANCED` and minted redeemable BPT, a claim on
 *         depth the value-capture model requires to be irreversible. Inverted here at the fix
 *         per PB-D68 (v): the shared helper now donates, so BPT supply stays flat, the hook
 *         accumulates nothing, and der Bodensee's reserve is what rises.
 * @dev The reserve assertion is not decoration. Supply-unchanged and hook-balance-unchanged are
 *      both equally true of a route that silently skipped, so without a reserve delta this file
 *      would pass against a hook that had stopped routing altogether. Positive control on tree:
 *      `test/fork/StageGIntegration.t.sol` asserts the same supply-unchanged shape on the
 *      donation paths through `SwapAndDepositToBodensee`, which the fee path now matches.
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

    /// @notice The fix. A protocol-fee route deepens der Bodensee without minting any claim on
    ///         the depth it added.
    function test_F23_feeRouteDonatesWithoutMintingBpt() public {
        uint256 supplyBefore = IERC20(bodenseePool).totalSupply();
        uint256 hookBptBefore = IERC20(bodenseePool).balanceOf(address(hook));
        uint256 reserveBefore = _bodenseeReserve(svZchf);

        uint256 amountOut = _performSwap(pilotPools[0], IERC20(address(susds)), svZchf, 1e18);
        assertGt(amountOut, 0, "swap produced output");

        assertEq(
            IERC20(bodenseePool).totalSupply(),
            supplyBefore,
            "F-23 - BPT supply unchanged by a protocol-fee route"
        );
        assertEq(
            IERC20(bodenseePool).balanceOf(address(hook)),
            hookBptBefore,
            "F-23 - hook BPT balance unchanged by a protocol-fee route"
        );
        assertGt(
            _bodenseeReserve(svZchf),
            reserveBefore,
            "PB-D68 (v) - depth donated, not silently skipped"
        );
    }

    /// @notice The claim is gone by construction rather than by omission. Before the fix the hook
    ///         accrued BPT that only the absence of a sweep entry kept inert; now none is minted,
    ///         so there is nothing for a future token-moving path to reach.
    function test_F23_hookAccumulatesNoBptClaim() public {
        uint256 amountOut = _performSwap(pilotPools[0], IERC20(address(susds)), svZchf, 1e18);
        assertGt(amountOut, 0, "swap produced output");

        assertEq(
            IERC20(bodenseePool).balanceOf(address(hook)),
            0,
            "F-23 - hook holds no BPT claim after a fee route"
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
