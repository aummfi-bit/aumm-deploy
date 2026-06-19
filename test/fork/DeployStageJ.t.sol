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
        address pilot01 = makeAddr("pilot01");
        address pilot05 = makeAddr("pilot05");
        address pilot14 = makeAddr("pilot14");

        vm.setEnv("GOVERNANCE_MULTISIG", vm.toString(governor));
        vm.setEnv("PILOT_POOL_01", vm.toString(pilot01));
        vm.setEnv("PILOT_POOL_05", vm.toString(pilot05));
        vm.setEnv("PILOT_POOL_14", vm.toString(pilot14));

        MiliariumRegistry deployed = new DeployStageJ().deploy(governor);

        assertEq(deployed.miliariumPoolsCount(), 3, "miliariumPoolsCount == 3");
        assertEq(deployed.poolAtSlot(1), pilot01, "slot 1 = pilot01");
        assertEq(deployed.poolAtSlot(5), pilot05, "slot 5 = pilot05");
        assertEq(deployed.poolAtSlot(14), pilot14, "slot 14 = pilot14");
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
