// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
import { MiliariumRegistry } from "../src/registry/MiliariumRegistry.sol";

/**
 * @title DeployStageJ
 * @notice Deploys the Stage J Miliarium slot↔pool registry —
 *         `new MiliariumRegistry(governance_, [1,5,14], [pilot01, pilot05, pilot14])`
 *         per J-D4 constructor-injected genesis seeding and J-D7 stage-close deploy script.
 * @dev H13-safe — `MiliariumRegistry`'s constructor takes only addresses and performs no
 *      external calls, so keccak-derived placeholder env values are valid in fork tests
 *      (contrast with H-D42 / `BodenseeBootstrapChannel`, whose constructor external-calls
 *      into `VAULT` and therefore requires real fork state).
 * @dev I-D18 slot-named env vars — `PILOT_POOL_01`, `PILOT_POOL_05`, `PILOT_POOL_14` name
 *      the three Stage E pilot pool addresses at Miliarium slots 01 / 05 / 14.
 * @dev `GOVERNANCE_MULTISIG` is the initial `governanceContract` at construction (J-D5);
 *      Stage K rebinds via `setGovernanceContract` during the governance handoff.
 * @dev Production chain position — `DeployStageI` → `DeployStageJ` → `DeployStageK`
 *      per STAGES_OVERVIEW deploy order L388.
 * @dev Env vars required (no defaults — a real deploy must never silently fall back to zero values):
 *
 *        GOVERNANCE_MULTISIG   address  — initial governance gate
 *        PILOT_POOL_01         address  — ixHelvetia pilot (Stage E slot 01)
 *        PILOT_POOL_05         address  — ixEdelweiss pilot (Stage E slot 05)
 *        PILOT_POOL_14         address  — ixAurebit pilot (Stage E slot 14)
 */
contract DeployStageJ is Script {
    /// @notice `forge script` entry — broadcasts registry deployment as GOVERNANCE_MULTISIG.
    function run() external {
        address governor = vm.envAddress("GOVERNANCE_MULTISIG");
        vm.startBroadcast(governor);
        _deploy(governor);
        vm.stopBroadcast();
    }

    /// @notice Testable entry — deploys via vm.startPrank(governor) for fork tests without a live broadcast. Returns the deployed registry for assertions.
    function deploy(address governor) external returns (MiliariumRegistry) {
        vm.startPrank(governor);
        MiliariumRegistry registry = _deploy(governor);
        vm.stopPrank();
        return registry;
    }

    /// @dev Builds the genesis seed arrays and deploys `MiliariumRegistry`.
    function _deploy(address governor) internal returns (MiliariumRegistry) {
        uint256[] memory slotNumbers = new uint256[](3);
        slotNumbers[0] = 1;
        slotNumbers[1] = 5;
        slotNumbers[2] = 14;
        address[] memory pools = new address[](3);
        pools[0] = vm.envAddress("PILOT_POOL_01");
        pools[1] = vm.envAddress("PILOT_POOL_05");
        pools[2] = vm.envAddress("PILOT_POOL_14");
        return new MiliariumRegistry(governor, slotNumbers, pools);
    }
}
