// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MiliariumRegistry} from "src/registry/MiliariumRegistry.sol";
import {IMiliariumSlotRegistry} from "src/registry/IMiliariumSlotRegistry.sol";

contract MiliariumRegistryTest is Test {
    MiliariumRegistry internal registry;

    address internal constant GOVERNANCE = address(0x1111111111111111111111111111111111111111);
    address internal constant POOL_SLOT2 = address(0x2222222222222222222222222222222222222222);
    address internal constant POOL_SLOT3 = address(0x3333333333333333333333333333333333333333);
    address internal constant POOL_SLOT7 = address(0x7777777777777777777777777777777777777777);
    address internal constant UNREGISTERED = address(0x9999999999999999999999999999999999999999);
    address internal constant NEW_POOL = address(0x4444444444444444444444444444444444444444);
    address internal constant STRANGER = address(0x8888888888888888888888888888888888888888);
    address internal constant NEW_GOV = address(0x5555555555555555555555555555555555555555);

    function setUp() public {
        (uint256[] memory slotNumbers, address[] memory pools) = _seedArrays();
        registry = new MiliariumRegistry(GOVERNANCE, slotNumbers, pools);
        vm.label(address(registry), "MiliariumRegistry");
        vm.label(GOVERNANCE, "GOVERNANCE");
        vm.label(POOL_SLOT2, "POOL_SLOT2");
        vm.label(POOL_SLOT3, "POOL_SLOT3");
        vm.label(POOL_SLOT7, "POOL_SLOT7");
        vm.label(STRANGER, "STRANGER");
        vm.label(NEW_GOV, "NEW_GOV");
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

    function test_replaceSlot_populate_emitsSlotPopulated() public {
        vm.expectEmit(true, true, false, true, address(registry));
        emit IMiliariumSlotRegistry.SlotPopulated(5, NEW_POOL, block.number);
        vm.prank(GOVERNANCE);
        registry.replaceSlot(5, NEW_POOL);
    }

    function test_replaceSlot_populate_registersAndGrowsDenseEnumeration() public {
        vm.prank(GOVERNANCE);
        registry.replaceSlot(5, NEW_POOL);
        assertEq(registry.poolAtSlot(5), NEW_POOL);
        assertEq(registry.slotOf(NEW_POOL), 5);
        assertTrue(registry.isMiliarium(NEW_POOL));
        assertEq(registry.miliariumPoolsCount(), 4);
        assertEq(registry.miliariumPoolAt(3), NEW_POOL);
    }

    function test_replaceSlot_replace_emitsSlotReplaced() public {
        vm.expectEmit(true, true, true, true, address(registry));
        emit IMiliariumSlotRegistry.SlotReplaced(2, POOL_SLOT2, NEW_POOL, block.number);
        vm.prank(GOVERNANCE);
        registry.replaceSlot(2, NEW_POOL);
    }

    function test_replaceSlot_replace_nonLast_swapRemoveCorrectness() public {
        vm.prank(GOVERNANCE);
        registry.replaceSlot(2, NEW_POOL);
        assertEq(registry.poolAtSlot(2), NEW_POOL);
        assertEq(registry.slotOf(NEW_POOL), 2);
        assertTrue(registry.isMiliarium(NEW_POOL));
        assertEq(registry.slotOf(POOL_SLOT2), 0);
        assertFalse(registry.isMiliarium(POOL_SLOT2));
        assertEq(registry.miliariumPoolsCount(), 3);
        assertEq(registry.miliariumPoolAt(0), POOL_SLOT7);
        assertEq(registry.miliariumPoolAt(1), POOL_SLOT3);
        assertEq(registry.miliariumPoolAt(2), NEW_POOL);
        assertEq(registry.slotOf(POOL_SLOT7), 7);
        assertEq(registry.poolAtSlot(7), POOL_SLOT7);
        assertEq(registry.poolAtSlot(3), POOL_SLOT3);
    }

    function test_replaceSlot_replace_lastElement_edgeCase() public {
        vm.prank(GOVERNANCE);
        registry.replaceSlot(7, NEW_POOL);
        assertEq(registry.poolAtSlot(7), NEW_POOL);
        assertEq(registry.slotOf(NEW_POOL), 7);
        assertTrue(registry.isMiliarium(NEW_POOL));
        assertEq(registry.slotOf(POOL_SLOT7), 0);
        assertFalse(registry.isMiliarium(POOL_SLOT7));
        assertEq(registry.miliariumPoolsCount(), 3);
        assertEq(registry.miliariumPoolAt(0), POOL_SLOT2);
        assertEq(registry.miliariumPoolAt(1), POOL_SLOT3);
        assertEq(registry.miliariumPoolAt(2), NEW_POOL);
    }

    function test_replaceSlot_revert_invalidSlot() public {
        vm.prank(GOVERNANCE);
        vm.expectRevert(abi.encodeWithSelector(IMiliariumSlotRegistry.InvalidSlot.selector, uint256(0)));
        registry.replaceSlot(0, NEW_POOL);

        vm.prank(GOVERNANCE);
        vm.expectRevert(abi.encodeWithSelector(IMiliariumSlotRegistry.InvalidSlot.selector, uint256(29)));
        registry.replaceSlot(29, NEW_POOL);
    }

    function test_replaceSlot_revert_zeroNewPool() public {
        vm.prank(GOVERNANCE);
        vm.expectRevert(IMiliariumSlotRegistry.ZeroAddress.selector);
        registry.replaceSlot(5, address(0));
    }

    function test_replaceSlot_revert_notGovernance() public {
        vm.prank(STRANGER);
        vm.expectRevert(abi.encodeWithSelector(IMiliariumSlotRegistry.NotGovernance.selector, STRANGER));
        registry.replaceSlot(5, NEW_POOL);
    }

    function test_replaceSlot_revert_poolAlreadyRegistered() public {
        vm.prank(GOVERNANCE);
        vm.expectRevert(abi.encodeWithSelector(IMiliariumSlotRegistry.PoolAlreadyRegistered.selector, POOL_SLOT2));
        registry.replaceSlot(5, POOL_SLOT2);
    }

    function test_constructor_revert_lengthMismatch() public {
        uint256[] memory slots = new uint256[](2);
        slots[0] = 2;
        slots[1] = 3;
        address[] memory pools = new address[](1);
        pools[0] = POOL_SLOT2;
        vm.expectRevert(IMiliariumSlotRegistry.LengthMismatch.selector);
        new MiliariumRegistry(GOVERNANCE, slots, pools);
    }

    function test_constructor_revert_duplicateSlot() public {
        uint256[] memory slots = new uint256[](2);
        slots[0] = 2;
        slots[1] = 2;
        address[] memory pools = new address[](2);
        pools[0] = POOL_SLOT2;
        pools[1] = POOL_SLOT3;
        vm.expectRevert(abi.encodeWithSelector(IMiliariumSlotRegistry.SlotAlreadyAssigned.selector, uint256(2)));
        new MiliariumRegistry(GOVERNANCE, slots, pools);
    }

    function test_constructor_revert_duplicatePool() public {
        uint256[] memory slots = new uint256[](2);
        slots[0] = 2;
        slots[1] = 3;
        address[] memory pools = new address[](2);
        pools[0] = POOL_SLOT2;
        pools[1] = POOL_SLOT2;
        vm.expectRevert(abi.encodeWithSelector(IMiliariumSlotRegistry.PoolAlreadyRegistered.selector, POOL_SLOT2));
        new MiliariumRegistry(GOVERNANCE, slots, pools);
    }

    function test_constructor_revert_zeroGovernance() public {
        (uint256[] memory slots, address[] memory pools) = _seedArrays();
        vm.expectRevert(IMiliariumSlotRegistry.ZeroAddress.selector);
        new MiliariumRegistry(address(0), slots, pools);
    }

    function test_setGovernanceContract_emitsGovernanceTransferred() public {
        vm.expectEmit(true, true, false, false, address(registry));
        emit IMiliariumSlotRegistry.GovernanceTransferred(GOVERNANCE, NEW_GOV);
        vm.prank(GOVERNANCE);
        registry.setGovernanceContract(NEW_GOV);
    }

    function test_setGovernanceContract_rebindsGate() public {
        vm.prank(GOVERNANCE);
        registry.setGovernanceContract(NEW_GOV);
        assertEq(registry.governanceContract(), NEW_GOV);

        // the new governance can now mutate the registry
        vm.prank(NEW_GOV);
        registry.replaceSlot(5, NEW_POOL);
        assertEq(registry.poolAtSlot(5), NEW_POOL);

        // the old governance is locked out (otherwise-valid args, gate still rejects)
        vm.prank(GOVERNANCE);
        vm.expectRevert(abi.encodeWithSelector(IMiliariumSlotRegistry.NotGovernance.selector, GOVERNANCE));
        registry.replaceSlot(6, UNREGISTERED);
    }

    function test_setGovernanceContract_revert_notGovernance() public {
        vm.prank(STRANGER);
        vm.expectRevert(abi.encodeWithSelector(IMiliariumSlotRegistry.NotGovernance.selector, STRANGER));
        registry.setGovernanceContract(NEW_GOV);
    }

    function test_setGovernanceContract_revert_zeroGovernance() public {
        vm.prank(GOVERNANCE);
        vm.expectRevert(IMiliariumSlotRegistry.ZeroAddress.selector);
        registry.setGovernanceContract(address(0));
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
