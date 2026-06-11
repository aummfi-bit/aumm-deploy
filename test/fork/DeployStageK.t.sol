// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;
import { StageIIntegrationFixture } from "./StageIIntegration.t.sol";
import { DeployStageK } from "../../script/DeployStageK.s.sol";
import { MiliariumRegistry } from "../../src/registry/MiliariumRegistry.sol";
import { VaultClassRegistry } from "../../src/gauge/VaultClassRegistry.sol";
import { IVaultClassRegistry } from "../../src/gauge/IVaultClassRegistry.sol";
import { AureumAuthorizer } from "../../src/vault/AureumAuthorizer.sol";
import { VotingWeight } from "../../src/governance/VotingWeight.sol";
import { AureumGovernance } from "../../src/governance/AureumGovernance.sol";
import { AureumGovernanceAuthorizer } from "../../src/governance/AureumGovernanceAuthorizer.sol";
import { AuMMMinterRouter } from "../../src/token/AuMMMinterRouter.sol";
/**
 * @title DeployStageKForkTest
 * @notice Integration test for `script/DeployStageK.s.sol` — the Stage K governance handoff
 *         (4 deploys + 8 wiring calls per K14 / K-D9). Inherits `StageIIntegrationFixture` for a
 *         real Vault + AuMM + Bodensee + gauge + oracle + distributor stack on a mainnet fork,
 *         deploys the two fresh registries the wiring chain consumes, installs a one-shot
 *         authorizer bridge, then runs `DeployStageK.deploy(address(this))` and stores the four
 *         returned handles. K7.3a lands setUp + a trivial sanity assertion; the A/B/C assertion
 *         groups land at K7.3b.
 *
 * @dev Single-governor caller model (K15 / Option 1). The inherited fixture splits the eight
 *      wiring gates across two addresses: `address(this)` holds seven (VCR votingWeightSetter,
 *      swapAndDeposit donateAuthorizer, emission governance on bootstrapChannel + distributor,
 *      AuMM minterAdmin, gauge governance), but wire (8) `vault.setAuthorizer` is gated to the
 *      immutable `GOVERNANCE_MULTISIG` of the Stage B `AureumAuthorizer` the fixture installed
 *      (DeployAureumVault L178/L192). Resolution: deploy a throwaway `AureumAuthorizer(address(this))`
 *      and install it once via `vm.prank(GOVERNANCE_MULTISIG); vault.setAuthorizer(bridge)`, so the
 *      single-governor script then executes all eight wires (including the real wire (8) installing
 *      `AureumGovernanceAuthorizer`) as `address(this)`. This diverges from production — where wire (8)
 *      is signed by the real `GOVERNANCE_MULTISIG` Safe — exactly as `DeployStageH.t.sol` L208—L218
 *      diverges on its `setMinter` simulation; production multisig-path fidelity lives in the deploy
 *      script NatSpec and the K1 `AureumGovernanceAuthorizer` unit suite.
 *
 * @dev Fresh registries — the inherited `miliariumRegistry` is a `MockMiliariumRegistry` (StageI L37)
 *      and the inherited `vaultClassRegistry` is one-shot-sealed at StageG L217 (`setVotingWeight`
 *      zeroes `votingWeightSetter`). K7.3 deploys a fresh real `MiliariumRegistry` (governanceContract
 *      = `address(this)`, no pre-handoff) and a fresh `VaultClassRegistry` (votingWeightSetter =
 *      `address(this)`, unsealed) so wires (7) and (1) succeed.
 *
 * @dev Run with:
 *
 *        forge test --match-path "test/fork/DeployStageK.t.sol" \
 *          --fork-url $MAINNET_RPC_URL --threads 1 -vv
 *
 *      Per D35 split-form + D36 `--threads 1` belt.
 */
contract DeployStageKForkTest is StageIIntegrationFixture {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    /// @notice Emergency authorizer multisig for the deployed `AureumGovernanceAuthorizer`. Distinct
    ///         from the inherited `GOVERNANCE_MULTISIG`; keccak-derived per the StageG constant
    ///         convention. Consumed by the K7.3b assertion-C emergency-routing checks.
    address internal constant EMERGENCY_MULTISIG = address(uint160(uint256(keccak256("emergencyMultisig"))));
    // -------------------------------------------------------------------------
    // State — fresh Stage-K registries + the deploy script + its four handles
    // -------------------------------------------------------------------------
    MiliariumRegistry internal realRegistry;
    VaultClassRegistry internal freshVCR;
    DeployStageK internal deployStageKScript;
    VotingWeight internal votingWeight;
    AureumGovernance internal governance;
    AureumGovernanceAuthorizer internal authorizer;
    AuMMMinterRouter internal router;
    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------
    function setUp() public override {
        super.setUp();
        // (1) Fresh real MiliariumRegistry — dual-interface (IMiliariumRegistry + IMiliariumSlotRegistry,
        //     J-D2), seeded at manifest slots [1, 5, 14] with the three pilots, governanceContract =
        //     address(this) so wire (7) succeeds. NO pre-handoff to gov (the StageKIntegrationFixture L62
        //     handoff is precisely what K7.3 must avoid so the script performs the handoff itself).
        uint256[] memory slots = new uint256[](3);
        slots[0] = 1;
        slots[1] = 5;
        slots[2] = 14;
        address[] memory pools = new address[](3);
        pools[0] = pilotPools[0];
        pools[1] = pilotPools[1];
        pools[2] = pilotPools[2];
        realRegistry = new MiliariumRegistry(address(this), slots, pools);
        // (2) Fresh VaultClassRegistry — votingWeightSetter = address(this) (unsealed) so wire (1)
        //     setVotingWeight succeeds. Mirrors StageG L207—L211 single-token genesis seeding.
        address[] memory genesisTokens = new address[](1);
        genesisTokens[0] = address(susds);
        IVaultClassRegistry.AdmissionType[] memory genesisTypes = new IVaultClassRegistry.AdmissionType[](1);
        genesisTypes[0] = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        freshVCR = new VaultClassRegistry(svZchf, swapAndDeposit, address(this), address(this), genesisTokens, genesisTypes);
        // (3) Authorizer bridge — the fixture's Vault authorizer is AureumAuthorizer(GOVERNANCE_MULTISIG),
        //     so address(this) cannot call setAuthorizer directly. Install a throwaway
        //     AureumAuthorizer(address(this)) under the multisig's authority once; the script's wire (8)
        //     then replaces it with the real AureumGovernanceAuthorizer as address(this) (K15 / Option 1).
        AureumAuthorizer bridge = new AureumAuthorizer(address(this));
        vm.prank(GOVERNANCE_MULTISIG);
        vault.setAuthorizer(bridge);
        // (4) Env vars — the 13 deploy-path vars DeployStageK.deploy() reads (GOVERNANCE_MULTISIG is
        //     run()-only). Rationale: vm.setEnv is flagged by forge-lint as an "unsafe cheatcode" because
        //     it mutates process environment state. Here it is the intentional harness mechanism for
        //     parameterizing DeployStageK.s.sol — the script reads config via vm.envAddress, so the fork
        //     test must populate these before calling deploy(). Scoped to setUp() in a fork test; no
        //     production path touches vm.setEnv. Per Foundry lint best-practice ("Minimize Scope"), each
        //     call is suppressed individually.
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("AUMM", vm.toString(address(aumm)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("TVL_ORACLE", vm.toString(address(tvlOracle)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("GAUGE_REGISTRY", vm.toString(address(gaugeRegistry)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("EMISSION_DISTRIBUTOR", vm.toString(address(emissionDistributor)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_REGISTRY", vm.toString(address(realRegistry)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("VAULT", vm.toString(address(vault)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("SWAP_AND_DEPOSIT", vm.toString(address(swapAndDeposit)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("SV_ZCHF", vm.toString(address(svZchf)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("SUSDS", vm.toString(address(susds)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("BODENSEE_POOL", vm.toString(bodenseePool));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("EMERGENCY_MULTISIG", vm.toString(EMERGENCY_MULTISIG));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("BODENSEE_CHANNEL", vm.toString(address(bootstrapChannel)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("VAULT_CLASS_REGISTRY", vm.toString(address(freshVCR)));
        // (5) Deploy + wire the governance stack as governor = address(this); store the four handles.
        //     Any of the eight wires reverting reverts setUp — green is end-to-end proof the chain ran.
        deployStageKScript = new DeployStageK();
        (votingWeight, governance, authorizer, router) = deployStageKScript.deploy(address(this));
    }
    // -------------------------------------------------------------------------
    // K7.3a sanity — setUp ran the full deploy + 8-wire chain without reverting
    // -------------------------------------------------------------------------
    function test_setUp_deployReturnedFourHandles() public view {
        assertTrue(address(votingWeight) != address(0), "votingWeight unset");
        assertTrue(address(governance) != address(0), "governance unset");
        assertTrue(address(authorizer) != address(0), "authorizer unset");
        assertTrue(address(router) != address(0), "router unset");
    }
}
