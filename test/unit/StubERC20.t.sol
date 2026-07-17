// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {StubERC20} from "test-stubs/StubERC20.sol";

contract StubERC20Test is Test {
    StubERC20 internal stub;

    function setUp() public {
        stub = new StubERC20("Stub Token", "STUB", 18);
    }

    function test_ConstructorMetadata() public view {
        assertEq(stub.name(), "Stub Token");
        assertEq(stub.symbol(), "STUB");
        assertEq(stub.decimals(), 18);
    }

    function test_DecimalsRespectsConstructor() public {
        StubERC20 stub6 = new StubERC20("Six", "SIX", 6);
        StubERC20 stub8 = new StubERC20("Eight", "EIGHT", 8);
        StubERC20 stub18 = new StubERC20("Eighteen", "EIGHTEEN", 18);

        assertEq(stub6.decimals(), 6);
        assertEq(stub8.decimals(), 8);
        assertEq(stub18.decimals(), 18);
    }

    function test_MintPermissionlessAnyCaller() public {
        address caller = makeAddr("caller");
        address recipient = makeAddr("recipient");

        vm.prank(caller);
        stub.mint(recipient, 1_000e18);

        assertEq(stub.balanceOf(recipient), 1_000e18);
        assertEq(stub.totalSupply(), 1_000e18);
    }

    function test_MintUncapped() public {
        address recipient = makeAddr("recipient");

        stub.mint(recipient, 1e30);

        assertEq(stub.balanceOf(recipient), 1e30);
    }

    function test_MintAccumulates() public {
        address recipient = makeAddr("recipient");

        stub.mint(recipient, 100e18);
        stub.mint(recipient, 250e18);

        assertEq(stub.balanceOf(recipient), 350e18);
    }
}
