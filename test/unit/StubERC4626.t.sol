// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {StubERC20} from "test-stubs/StubERC20.sol";
import {StubERC4626} from "test-stubs/StubERC4626.sol";
import {ERC4626RateProvider} from "src/rate_provider/ERC4626RateProvider.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StubERC4626Test is Test {
    StubERC20 internal asset18;
    StubERC4626 internal vault18;

    function setUp() public {
        asset18 = new StubERC20("Stub USDS", "sUSDSu", 18);
        vault18 = new StubERC4626(IERC20(address(asset18)), "Staked USDS", "sUSDS");
    }

    function _depositFor(address user, uint256 amount) internal returns (uint256 shares) {
        asset18.mint(user, amount);
        vm.startPrank(user);
        asset18.approve(address(vault18), amount);
        shares = vault18.deposit(amount, user);
        vm.stopPrank();
    }

    function test_Asset() public view {
        assertEq(vault18.asset(), address(asset18));
    }

    function test_DecimalsInherited18() public view {
        assertEq(vault18.decimals(), 18);
    }

    function testFuzz_ConversionsOneToOne(uint256 amt) public view {
        assertEq(vault18.convertToAssets(amt), amt);
        assertEq(vault18.convertToShares(amt), amt);
        assertEq(vault18.previewDeposit(amt), amt);
        assertEq(vault18.previewWithdraw(amt), amt);
        assertEq(vault18.previewRedeem(amt), amt);
    }

    function test_PreviewRedeemRateOracle() public view {
        assertEq(vault18.previewRedeem(1e18), 1e18);
    }

    function test_DepositPullsAndMints() public {
        address user = makeAddr("user");
        uint256 shares = _depositFor(user, 1_000e18);

        assertEq(shares, 1_000e18);
        assertEq(vault18.balanceOf(user), 1_000e18);
        assertEq(asset18.balanceOf(address(vault18)), 1_000e18);
        assertEq(vault18.totalAssets(), 1_000e18);
        assertEq(asset18.balanceOf(user), 0);
    }

    function test_WithdrawBurnsAndTransfers() public {
        address user = makeAddr("user");
        _depositFor(user, 1_000e18);

        vm.prank(user);
        vault18.withdraw(400e18, user, user);

        assertEq(vault18.balanceOf(user), 600e18);
        assertEq(asset18.balanceOf(user), 400e18);
        assertEq(asset18.balanceOf(address(vault18)), 600e18);
    }

    function test_WithdrawSpendsAllowance() public {
        address user = makeAddr("user");
        _depositFor(user, 1_000e18);

        address spender = makeAddr("spender");
        vm.prank(user);
        vault18.approve(spender, 400e18);

        vm.prank(spender);
        vault18.withdraw(400e18, spender, user);

        assertEq(vault18.balanceOf(user), 600e18);
        assertEq(asset18.balanceOf(spender), 400e18);
        assertEq(vault18.allowance(user, spender), 0);
    }

    function test_WithdrawRevertsWithoutAllowance() public {
        address user = makeAddr("user");
        _depositFor(user, 1_000e18);

        address spender = makeAddr("spender");
        vm.prank(spender);
        vm.expectRevert();
        vault18.withdraw(1, spender, user);
    }

    function test_SeedMintPermissionlessUnbacked() public {
        address seeder = makeAddr("seeder");
        address user = makeAddr("user2");

        vm.prank(seeder);
        vault18.mint(user, 500e18);

        assertEq(vault18.balanceOf(user), 500e18);
        assertEq(vault18.totalSupply(), 500e18);
        assertEq(asset18.balanceOf(address(vault18)), 0);
    }

    function test_F11_RateProviderAcceptsE18Over18() public {
        ERC4626RateProvider rp = new ERC4626RateProvider(IERC4626(address(vault18)));
        assertEq(rp.getRate(), 1e18);
    }

    function test_F11_RateProviderRevertsOn6DecAsset() public {
        StubERC20 asset6 = new StubERC20("Six", "SIX", 6);
        StubERC4626 vault6 = new StubERC4626(IERC20(address(asset6)), "Vault Six", "vSIX");

        vm.expectRevert(abi.encodeWithSelector(ERC4626RateProvider.InvalidAssetDecimals.selector, uint8(6)));
        new ERC4626RateProvider(IERC4626(address(vault6)));
    }
}
