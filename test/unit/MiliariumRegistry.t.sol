// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiliariumRegistry} from "src/registry/MiliariumRegistry.sol";

contract MiliariumRegistryTest is Test {
    MiliariumRegistry internal registry;

    address internal constant GOVERNANCE = address(0x1111111111111111111111111111111111111111);
    address internal constant POOL_SLOT2 = address(0x2222222222222222222222222222222222222222);
    address internal constant POOL_SLOT3 = address(0x3333333333333333333333333333333333333333);
    address internal constant POOL_SLOT7 = address(0x7777777777777777777777777777777777777777);
    address internal constant UNREGISTERED = address(0x9999999999999999999999999999999999999999);

    function setUp() public {
        (uint256[] memory slotNumbers, address[] memory pools) = _seedArrays();
        registry = new MiliariumRegistry(GOVERNANCE, slotNumbers, pools);
        vm.label(address(registry), "MiliariumRegistry");
        vm.label(GOVERNANCE, "GOVERNANCE");
        vm.label(POOL_SLOT2, "POOL_SLOT2");
        vm.label(POOL_SLOT3, "POOL_SLOT3");
        vm.label(POOL_SLOT7, "POOL_SLOT7");
    }

    function test_genesis_poolAtSlot_seeded() public view {
        assertEq(registry.poolAtSlot(2), POOL_SLOT2);
        assertEq(registry.poolAtSlot(3), POOL_SLOT3);
        assertEq(registry.poolAtSlot(7), POOL_SLOT7);
    }

    function test_genesis_poolAtSlot_emptySlotsAreZero() public view {
        for (uint256 slot = 1; slot <= 28; ++slot) {
            if (slot == 2 || slot == 3 || slot == 7) {
                continue;
            }
            assertEq(registry.poolAtSlot(slot), address(0));
        }
    }

    function test_genesis_slotOf_reverse() public view {
        assertEq(registry.slotOf(POOL_SLOT2), 2);
        assertEq(registry.slotOf(POOL_SLOT3), 3);
        assertEq(registry.slotOf(POOL_SLOT7), 7);
    }

    function test_genesis_slotOf_unregisteredIsZero() public view {
        assertEq(registry.slotOf(UNREGISTERED), 0);
    }

    function test_genesis_isMiliarium_membership() public view {
        assertTrue(registry.isMiliarium(POOL_SLOT2));
        assertTrue(registry.isMiliarium(POOL_SLOT3));
        assertTrue(registry.isMiliarium(POOL_SLOT7));
        assertFalse(registry.isMiliarium(UNREGISTERED));
    }

    function test_genesis_miliariumPoolsCount() public view {
        assertEq(registry.miliariumPoolsCount(), 3);
    }

    function test_genesis_miliariumPoolAt_denseInsertionOrder() public view {
        assertEq(registry.miliariumPoolAt(0), POOL_SLOT2);
        assertEq(registry.miliariumPoolAt(1), POOL_SLOT3);
        assertEq(registry.miliariumPoolAt(2), POOL_SLOT7);
    }

    function _seedArrays() internal pure returns (uint256[] memory slotNumbers, address[] memory pools) {
        slotNumbers = new uint256[](3);
        slotNumbers[0] = 2;
        slotNumbers[1] = 3;
        slotNumbers[2] = 7;

        pools = new address[](3);
        pools[0] = POOL_SLOT2;
        pools[1] = POOL_SLOT3;
        pools[2] = POOL_SLOT7;
    }
}
