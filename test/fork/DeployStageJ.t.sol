// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { DeployStageJ } from "../../script/DeployStageJ.s.sol";
import { MiliariumRegistry } from "../../src/registry/MiliariumRegistry.sol";
import { IMiliariumRegistry } from "../../src/ccb/IMiliariumRegistry.sol";
import { IGaugeRegistry } from "../../src/ccb/IGaugeRegistry.sol";
import { IEMASampler } from "../../src/ccb/IEMASampler.sol";
import { CCBMultiplier } from "../../src/ccb/CCBMultiplier.sol";

contract DeployStageJTest is Test {
    function test_DeployStageJ_SeedsRegistryAndSmokesWiring() public {
        address governor = makeAddr("governance");
        address pilot02 = makeAddr("pilot02");
        address pilot03 = makeAddr("pilot03");
        address pilot07 = makeAddr("pilot07");

        vm.setEnv("GOVERNANCE_MULTISIG", vm.toString(governor));
        vm.setEnv("PILOT_POOL_02", vm.toString(pilot02));
        vm.setEnv("PILOT_POOL_03", vm.toString(pilot03));
        vm.setEnv("PILOT_POOL_07", vm.toString(pilot07));

        MiliariumRegistry deployed = new DeployStageJ().deploy(governor);

        assertEq(deployed.miliariumPoolsCount(), 3, "miliariumPoolsCount == 3");
        assertEq(deployed.poolAtSlot(2), pilot02, "slot 2 = pilot02");
        assertEq(deployed.poolAtSlot(3), pilot03, "slot 3 = pilot03");
        assertEq(deployed.poolAtSlot(7), pilot07, "slot 7 = pilot07");
        assertEq(deployed.governanceContract(), governor, "governanceContract = governor");

        // CCBMultiplier wiring smoke — prove the deployed registry satisfies IMiliariumRegistry without a full oracle stack.
        CCBMultiplier smoke = new CCBMultiplier(
            IMiliariumRegistry(address(deployed)),
            IGaugeRegistry(makeAddr("gauge")),
            IEMASampler(makeAddr("sampler"))
        );
        assertEq(
            address(smoke.miliariumRegistry()),
            address(deployed),
            "CCBMultiplier accepts script-deployed registry as IMiliariumRegistry"
        );
    }
}
