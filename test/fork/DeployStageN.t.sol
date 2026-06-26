// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { StageNIntegrationFixture } from "./StageNIntegration.t.sol";
import { DeployStageN } from "../../script/DeployStageN.s.sol";

/**
 * @title DeployStageNForkTest
 * @notice Fail-fast governance-precondition tests for `script/DeployStageN.s.sol`.
 *         Inherits `StageNIntegrationFixture` — the fixture setUp already runs the
 *         happy-path `deploy(address(this))`. `_bind` checks three governance gates in
 *         order — registry → gauge → distributor — reverting at the first mismatch before
 *         any binding; to reach the gauge gate the registry governance is handed to `rando`,
 *         to reach the distributor gate both registry and gauge governance are handed to
 *         `rando`. The fixture rebuilds `realRegistry` and resets gauge governance each
 *         setUp so per-test mutations do not leak. Mirrors the `DeployStageL.t.sol:100`
 *         fail-fast pattern.
 *
 * @dev Run with:
 *
 *        forge test --match-path "test/fork/DeployStageN.t.sol" \
 *          --fork-url $MAINNET_RPC_URL --threads 1 -vv
 *
 *      Per D35 split-form + D36 `--threads 1` belt.
 */
contract DeployStageNForkTest is StageNIntegrationFixture {
    function test_DeployStageN_failFast_registryGovernor_reverts() public {
        address rando = makeAddr("nRandoRegistry");
        DeployStageN freshScript = new DeployStageN();
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployStageN.RegistryGovernanceNotMultisig.selector,
                realRegistry.governanceContract()
            )
        );
        freshScript.deploy(rando);
    }

    function test_DeployStageN_failFast_gaugeGovernor_reverts() public {
        address rando = makeAddr("nRandoGauge");
        realRegistry.setGovernanceContract(rando);
        DeployStageN freshScript = new DeployStageN();
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployStageN.GaugeGovernanceNotMultisig.selector,
                gaugeRegistry.governanceContract()
            )
        );
        freshScript.deploy(rando);
    }

    function test_DeployStageN_failFast_distributorGovernor_reverts() public {
        address rando = makeAddr("nRandoDistributor");
        realRegistry.setGovernanceContract(rando);
        gaugeRegistry.setGovernanceContract(rando);
        DeployStageN freshScript = new DeployStageN();
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployStageN.DistributorGovernanceNotMultisig.selector,
                emissionDistributor.governance()
            )
        );
        freshScript.deploy(rando);
    }
}
