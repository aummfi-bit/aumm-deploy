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

    function setUp() public {
        (uint256[] memory slotNumbers, address[] memory pools) = _seedArrays();
        registry = new MiliariumRegistry(GOVERNANCE, slotNumbers, pools);
        vm.label(address(registry), "MiliariumRegistry");
        vm.label(GOVERNANCE, "GOVERNANCE");
        vm.label(POOL_SLOT2, "POOL_SLOT2");
        vm.label(POOL_SLOT3, "POOL_SLOT3");
        vm.label(POOL_SLOT7, "POOL_SLOT7");
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
