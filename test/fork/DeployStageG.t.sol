// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { StageGIntegrationFixture } from "./StageGIntegration.t.sol";

import { SwapAndDepositToBodensee } from "../../src/gauge/SwapAndDepositToBodensee.sol";
import { VaultClassRegistry } from "../../src/gauge/VaultClassRegistry.sol";
import { IVaultClassRegistry } from "../../src/gauge/IVaultClassRegistry.sol";
import { GaugeEligibility } from "../../src/gauge/GaugeEligibility.sol";
import { GaugeRegistry } from "../../src/gauge/GaugeRegistry.sol";
import { GaugeGenesisManifest } from "../../script/config/GaugeGenesisManifest.sol";

import { DeployStageG } from "../../script/DeployStageG.s.sol";

/**
 * @title DeployStageGForkTest
 * @notice Integration test for `script/DeployStageG.s.sol`. Inherits `StageGIntegrationFixture` to
 *         obtain a real Vault + AuMM + Bodensee pool on a mainnet fork (H13: SwapAndDepositToBodensee's
 *         constructor calls `vault.getPoolTokens(bodenseePool)` per G-D12, so keccak256 placeholders for
 *         VAULT / BODENSEE_POOL fail — the fixture provides the real state). Instantiates the script and
 *         calls `deploy(address(deployScript))`: passing the script's own address as `deployer` makes the
 *         internal seal's setter calls (executed by the script contract) satisfy the moduleAdmin /
 *         gaugeRegistrySetter gates (mirrors DeployStageHForkTest L130). Asserts the 4 contracts deploy +
 *         thread their env-sourced immutables, the 4-call internal seal lands, the P-D30 11-token genesis
 *         manifest is admitted, and the Stage-K governance handoffs are correctly deferred (P-D25 / K14).
 *
 *         TVL_ORACLE / EFFICIENCY_ORACLE are the fixture's mocks — GaugeEligibility only stores them (no
 *         constructor call), so mock addresses satisfy its ZeroAddress guards; WEIGHTED_POOL_FACTORY /
 *         FEE_ROUTING_HOOK are the fixture's real awpf / hook.
 *
 * @dev Run with:
 *
 *        forge test --match-path "test/fork/DeployStageG.t.sol" \
 *          --fork-url $MAINNET_RPC_URL --threads 1 -vv
 *
 *      Per D35 split-form + D36 `--threads 1`.
 */
contract DeployStageGForkTest is StageGIntegrationFixture {
    DeployStageG internal deployScript;

    function setUp() public override {
        super.setUp();

        // vm.setEnv parameterizes DeployStageG.s.sol (it reads config via vm.envAddress). Scoped to
        // setUp in a fork test; no production path touches vm.setEnv. Each call suppressed per Foundry
        // lint "Minimize Scope".
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("VAULT", vm.toString(address(vault)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("BODENSEE_POOL", vm.toString(bodenseePool));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("AUMM", vm.toString(address(aumm)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("SV_ZCHF", vm.toString(address(svZchf)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("SUSDS", vm.toString(address(susds)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("WEIGHTED_POOL_FACTORY", vm.toString(address(awpf)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("TVL_ORACLE", vm.toString(address(mockTVLOracle)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("EFFICIENCY_ORACLE", vm.toString(address(mockEfficiencyOracle)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("FEE_ROUTING_HOOK", vm.toString(address(hook)));

        deployScript = new DeployStageG();
    }

    function test_DeployStageG() public {
        // (1) Run the deploy sequence — script's own address as deployer (DeployStageHForkTest L130).
        (
            SwapAndDepositToBodensee sad,
            VaultClassRegistry vcr,
            GaugeEligibility elig,
            GaugeRegistry reg
        ) = deployScript.deploy(address(deployScript));

        // (2) All four contracts deployed.
        assertTrue(address(sad) != address(0), "swapAndDeposit not deployed");
        assertTrue(address(vcr) != address(0), "vaultClassRegistry not deployed");
        assertTrue(address(elig) != address(0), "gaugeEligibility not deployed");
        assertTrue(address(reg) != address(0), "gaugeRegistry not deployed");

        // (3) Constructor immutables/authorities threaded from env + deployer.
        // moduleAdmin self-burns to address(0) once BOTH registries are wired (G-D12 atomic burn);
        // donateAuthorizer persists (multi-shot per G-D21).
        assertEq(sad.moduleAdmin(), address(0), "sad.moduleAdmin burned post-seal (G-D12)");
        assertEq(sad.donateAuthorizer(), address(deployScript), "sad.donateAuthorizer");
        assertEq(elig.approvedFactory(), address(awpf), "elig.approvedFactory");
        assertEq(elig.vault(), address(vault), "elig.vault");
        assertEq(elig.tvlOracle(), address(mockTVLOracle), "elig.tvlOracle");
        assertEq(elig.efficiencyOracle(), address(mockEfficiencyOracle), "elig.efficiencyOracle");
        assertEq(elig.feeRoutingHook(), address(hook), "elig.feeRoutingHook");
        assertEq(elig.vaultClassRegistry(), address(vcr), "elig.vaultClassRegistry");
        assertEq(address(vcr.svZCHF()), address(svZchf), "vcr.svZCHF");
        assertEq(address(vcr.helper()), address(sad), "vcr.helper");
        assertEq(reg.gaugeEligibility(), address(elig), "reg.gaugeEligibility");
        assertEq(reg.swapAndDeposit(), address(sad), "reg.swapAndDeposit");
        assertEq(reg.svZCHF(), address(svZchf), "reg.svZCHF");
        assertEq(reg.governanceContract(), address(deployScript), "reg.governance = deployer");
        assertEq(reg.GENESIS_BLOCK(), aumm.GENESIS_BLOCK(), "reg.GENESIS_BLOCK == aumm.GENESIS_BLOCK");

        // (4) The 4-call internal seal.
        assertEq(sad.vaultClassRegistry(), address(vcr), "seal: sad.vaultClassRegistry");
        assertEq(sad.gaugeRegistry(), address(reg), "seal: sad.gaugeRegistry");
        assertEq(elig.gaugeRegistry(), address(reg), "seal: elig.gaugeRegistry");
        assertEq(elig.gaugeRegistrySetter(), address(0), "seal: elig.gaugeRegistrySetter sealed");
        assertTrue(sad.authorizedDonators(address(vcr)), "seal: vcr authorized donator");

        // (5) The P-D30 11-token genesis manifest is admitted, all ImplementationAddress.
        (
            address[] memory gTokens,
            IVaultClassRegistry.AdmissionType[] memory gTypes
        ) = GaugeGenesisManifest.genesis();
        assertEq(gTokens.length, 11, "expected 11 genesis tokens");
        assertEq(gTypes.length, 11, "expected 11 genesis types");
        for (uint256 i = 0; i < gTokens.length; ++i) {
            assertTrue(vcr.isAdmittedClass(gTokens[i]), "genesis token not admitted");
            assertEq(
                uint256(vcr.admissionType(gTokens[i])),
                uint256(IVaultClassRegistry.AdmissionType.ImplementationAddress),
                "genesis admission type != ImplementationAddress"
            );
        }

        // (6) Stage-K governance/voting handoffs deferred (P-D25 / K14) — not done by DeployStageG.
        assertEq(vcr.votingWeightSetter(), address(deployScript), "votingWeightSetter retained for DeployStageK");
        assertEq(vcr.governanceSetter(), address(deployScript), "governanceSetter retained for DeployStageK");
        assertEq(address(vcr.votingWeight()), address(0), "setVotingWeight deferred");
        assertEq(vcr.governanceContract(), address(0), "setGovernanceContract deferred");
    }
}
