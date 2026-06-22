// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { StageMIntegrationFixture } from "./StageMIntegration.t.sol";
import { DeployStageM } from "../../script/DeployStageM.s.sol";

/**
 * @title DeployStageMForkTest
 * @notice Fail-fast governance-precondition tests for `script/DeployStageM.s.sol`.
 *         Inherits `StageMIntegrationFixture` — the fixture setUp already runs the
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
 *        forge test --match-path "test/fork/DeployStageM.t.sol" \
 *          --fork-url $MAINNET_RPC_URL --threads 1 -vv
 *
 *      Per D35 split-form + D36 `--threads 1` belt.
 */
contract DeployStageMForkTest is StageMIntegrationFixture {
    function test_DeployStageM_failFast_registryGovernor_reverts() public {
        address rando = makeAddr("mRandoRegistry");
        DeployStageM freshScript = new DeployStageM();
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployStageM.RegistryGovernanceNotMultisig.selector,
                realRegistry.governanceContract()
            )
        );
        freshScript.deploy(rando);
    }

    function test_DeployStageM_failFast_gaugeGovernor_reverts() public {
        address rando = makeAddr("mRandoGauge");
        realRegistry.setGovernanceContract(rando);
        DeployStageM freshScript = new DeployStageM();
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployStageM.GaugeGovernanceNotMultisig.selector,
                gaugeRegistry.governanceContract()
            )
        );
        freshScript.deploy(rando);
    }

    function test_DeployStageM_failFast_distributorGovernor_reverts() public {
        address rando = makeAddr("mRandoDistributor");
        realRegistry.setGovernanceContract(rando);
        gaugeRegistry.setGovernanceContract(rando);
        DeployStageM freshScript = new DeployStageM();
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployStageM.DistributorGovernanceNotMultisig.selector,
                emissionDistributor.governance()
            )
        );
        freshScript.deploy(rando);
    }
}
