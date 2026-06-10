// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AuMMMinterRouter} from "src/token/AuMMMinterRouter.sol";
import {IAuMMMinterRouter} from "src/token/IAuMMMinterRouter.sol";
import {AuMM} from "src/token/AuMM.sol";
import {IAuMM} from "src/token/IAuMM.sol";

contract AuMMMinterRouterTest is Test {
    AuMMMinterRouter router;
    AuMM aumm;
    address constant CHANNEL = address(0xC4A9);
    address constant DISTRIBUTOR = address(0xD157);
    address constant RECIPIENT = address(0xBEEF);
    address constant STRANGER = address(0xBAD);
    uint256 constant GENESIS = 20_000_000;

    event MintRouted(address indexed caller, address indexed recipient, uint256 amount);

    function setUp() public {
        aumm = new AuMM(GENESIS, address(this));
        router = new AuMMMinterRouter(IAuMM(address(aumm)), CHANNEL, DISTRIBUTOR);
        aumm.setMinter(address(router));
    }

    function test_constructor_revertsOnZeroAumm() public {
        vm.expectRevert(AuMMMinterRouter.ZeroAddress.selector);
        new AuMMMinterRouter(IAuMM(address(0)), CHANNEL, DISTRIBUTOR);
    }

    function test_constructor_revertsOnZeroBootstrapChannel() public {
        vm.expectRevert(AuMMMinterRouter.ZeroAddress.selector);
        new AuMMMinterRouter(IAuMM(address(aumm)), address(0), DISTRIBUTOR);
    }

    function test_constructor_revertsOnZeroEmissionDistributor() public {
        vm.expectRevert(AuMMMinterRouter.ZeroAddress.selector);
        new AuMMMinterRouter(IAuMM(address(aumm)), CHANNEL, address(0));
    }

    function test_constructor_wiresImmutables() public view {
        assertEq(address(router.AUMM()), address(aumm));
        assertEq(router.BOOTSTRAP_CHANNEL(), CHANNEL);
        assertEq(router.EMISSION_DISTRIBUTOR(), DISTRIBUTOR);
    }

    function test_mintFor_acceptsFromBootstrapChannel() public {
        vm.prank(CHANNEL);
        router.mintFor(RECIPIENT, 1e18);
        assertEq(aumm.balanceOf(RECIPIENT), 1e18);
        assertEq(aumm.totalSupply(), 1e18);
    }

    function test_mintFor_acceptsFromEmissionDistributor() public {
        vm.prank(DISTRIBUTOR);
        router.mintFor(RECIPIENT, 1e18);
        assertEq(aumm.balanceOf(RECIPIENT), 1e18);
        assertEq(aumm.totalSupply(), 1e18);
    }

    function test_mintFor_revertsForStranger() public {
        vm.expectRevert(abi.encodeWithSelector(IAuMMMinterRouter.NotAllowlisted.selector, STRANGER));
        vm.prank(STRANGER);
        router.mintFor(RECIPIENT, 1e18);
    }

    function test_mintFor_emitsMintRouted() public {
        vm.expectEmit(true, true, false, true);
        emit MintRouted(CHANNEL, RECIPIENT, 1e18);
        vm.prank(CHANNEL);
        router.mintFor(RECIPIENT, 1e18);
    }

    function test_mintFor_passthroughUpToCap() public {
        uint256 cap = aumm.MAX_SUPPLY();
        vm.prank(CHANNEL);
        router.mintFor(RECIPIENT, cap);
        assertEq(aumm.totalSupply(), cap);
    }

    function test_mintFor_revertsBeyondCap() public {
        uint256 cap = aumm.MAX_SUPPLY();
        vm.prank(CHANNEL);
        vm.expectRevert(AuMM.SupplyCapExceeded.selector);
        router.mintFor(RECIPIENT, cap + 1);
    }
}
