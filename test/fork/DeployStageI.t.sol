// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { StageGIntegrationFixture } from "./StageGIntegration.t.sol";
import { EmissionDistributor } from "../../src/emission/EmissionDistributor.sol";
import { AureumFeeRoutingHook } from "../../src/fee_router/AureumFeeRoutingHook.sol";
import { DeployStageH } from "../../script/DeployStageH.s.sol";
import { DeployStageI } from "../../script/DeployStageI.s.sol";

/**
 * @title DeployStageIForkTest
 * @notice Integration test for `script/DeployStageI.s.sol`. Inherits
 *         `StageGIntegrationFixture` — NOT `StageIIntegrationFixture`, whose
 *         setUp pre-wires all four recorder-path calls; a second
 *         `setEmissionRecorder` bind would revert `NotEmissionRecorderAdmin`
 *         because the admin self-zeroes on the first bind. setUp runs
 *         `DeployStageH.deploy(...)` to reach the post-handoff distributor
 *         (`governance == GOVERNANCE_MULTISIG`). The test runs
 *         `DeployStageI.deploy(GOVERNANCE_MULTISIG)` and asserts
 *         `hook.emissionRecorder == distributor`,
 *         `auMTContractByPool[pilot] == hook` ×3, `governance == multisig`,
 *         and the one-shot lock.
 *
 * @dev Run with:
 *
 *        forge test --match-path "test/fork/DeployStageI.t.sol" \
 *          --fork-url $MAINNET_RPC_URL --threads 1 -vv
 *
 *      Per D35 split-form + D36 `--threads 1` belt.
 *
 * @dev `VAULT_EXPLORER` / `EMA_SAMPLER` / `CCB_MULTIPLIER` / `MILIARIUM_REGISTRY`
 *      retain keccak256 placeholder addresses for the DeployStageH leg: their
 *      receivers have pure-storage constructors with only `ZeroAddress` guards
 *      and no external calls at construction time, mirroring DeployStageHForkTest.
 */
contract DeployStageIForkTest is StageGIntegrationFixture {
    // -------------------------------------------------------------------------
    // Placeholder constants — pure-storage constructor slots
    // GOVERNANCE_MULTISIG is INHERITED from StageGIntegrationFixture L64.
    // -------------------------------------------------------------------------

    address internal constant VAULT_EXPLORER_PLACEHOLDER =
        address(uint160(uint256(keccak256("vaultExplorer"))));
    address internal constant EMA_SAMPLER_PLACEHOLDER =
        address(uint160(uint256(keccak256("emaSampler"))));
    address internal constant CCB_MULTIPLIER_PLACEHOLDER =
        address(uint160(uint256(keccak256("ccbMultiplier"))));
    address internal constant MILIARIUM_REGISTRY_PLACEHOLDER =
        address(uint160(uint256(keccak256("miliariumRegistry"))));

    // -------------------------------------------------------------------------
    // State — populated in setUp / test_DeployStageI
    // -------------------------------------------------------------------------

    DeployStageH internal deployStageHScript;
    DeployStageI internal deployStageIScript;
    EmissionDistributor internal emissionDistributor;

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public override {
        super.setUp();

        // Rationale: vm.setEnv is flagged by forge-lint as an "unsafe
        // cheatcode" because it mutates process environment state. In this
        // test it is the intentional harness mechanism for parameterizing
        // DeployStageH.s.sol — the script reads deployment config via
        // vm.envAddress, so the fork test must populate those env vars before
        // calling deploy(). Scoped to setUp() in a fork test; no production
        // code path touches vm.setEnv. Per Foundry lint best-practice
        // ("Minimize Scope"), each call is suppressed individually with a
        // targeted disable-next-line directive.
        // GOVERNANCE_MULTISIG is already set by super.setUp() — do not re-set.
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("AUMM", vm.toString(address(aumm)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("VAULT", vm.toString(address(vault)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("BODENSEE_POOL", vm.toString(bodenseePool));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("SVZCHF", vm.toString(address(svZchf)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("GAUGE_REGISTRY", vm.toString(address(gaugeRegistry)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("VAULT_EXPLORER", vm.toString(VAULT_EXPLORER_PLACEHOLDER));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("EMA_SAMPLER", vm.toString(EMA_SAMPLER_PLACEHOLDER));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("CCB_MULTIPLIER", vm.toString(CCB_MULTIPLIER_PLACEHOLDER));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_REGISTRY", vm.toString(MILIARIUM_REGISTRY_PLACEHOLDER));

        deployStageHScript = new DeployStageH();
        emissionDistributor = deployStageHScript.deploy(address(deployStageHScript));

        // GOVERNANCE_MULTISIG + FEE_ROUTING_HOOK already set by super.setUp().
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("EMISSION_DISTRIBUTOR", vm.toString(address(emissionDistributor)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("PILOT_POOL_01", vm.toString(pilotPools[0]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("PILOT_POOL_05", vm.toString(pilotPools[1]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("PILOT_POOL_14", vm.toString(pilotPools[2]));
    }

    // -------------------------------------------------------------------------
    // Test
    // -------------------------------------------------------------------------

    function test_DeployStageI() public {
        deployStageIScript = new DeployStageI();
        deployStageIScript.deploy(GOVERNANCE_MULTISIG);

        assertEq(
            hook.emissionRecorder(),
            address(emissionDistributor),
            "hook.emissionRecorder must bind to the EmissionDistributor"
        );
        assertEq(
            emissionDistributor.auMTContractByPool(pilotPools[0]),
            address(hook),
            "pilot 01 recorder gate -> hook"
        );
        assertEq(
            emissionDistributor.auMTContractByPool(pilotPools[1]),
            address(hook),
            "pilot 05 recorder gate -> hook"
        );
        assertEq(
            emissionDistributor.auMTContractByPool(pilotPools[2]),
            address(hook),
            "pilot 14 recorder gate -> hook"
        );
        assertEq(
            emissionDistributor.governance(),
            GOVERNANCE_MULTISIG,
            "distributor.governance == GOVERNANCE_MULTISIG"
        );

        // First bind self-zeroed _emissionRecorderAdmin — admin gate (checked first) now rejects any re-bind.
        vm.expectRevert(AureumFeeRoutingHook.NotEmissionRecorderAdmin.selector);
        hook.setEmissionRecorder(address(emissionDistributor));
    }
}
