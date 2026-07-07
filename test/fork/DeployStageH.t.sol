// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { StageGIntegrationFixture } from "./StageGIntegration.t.sol";

import { BodenseeBootstrapChannel } from "../../src/emission/BodenseeBootstrapChannel.sol";
import { EmissionDistributor } from "../../src/emission/EmissionDistributor.sol";

import { DeployStageH } from "../../script/DeployStageH.s.sol";

/**
 * @title DeployStageHForkTest
 * @notice Integration test for `script/DeployStageH.s.sol`. Inherits
 *         `StageGIntegrationFixture` to obtain a real Vault + AuMM +
 *         Bodensee pool + gauge stack on a mainnet fork, then instantiates
 *         the script contract and calls `deploy(address(deployStageHScript))`
 *         to run the Stage H emission-stack deploy sequence. Asserts the
 *         resulting H-D7 Option C invariant (`aumm.minter() == address(0)`
 *         post-deploy), the two Step 4 governance handoffs (BodenseeBootstrapChannel
 *         + EmissionDistributor), the `BODENSEE_POOL` immutable threading into
 *         BodenseeBootstrapChannel, and a positive `setMinter` proof confirming
 *         the slot is consumable after deploy. Per P-D28 the TVLOracle +
 *         EfficiencyOracle handoffs move to the DeployStageF test and the
 *         cross-script `efficiencyOracle.setEmissionsRecorder` assertion to the
 *         P9.6 orchestrator test.
 *
 *         Per H-D42 this test cannot use keccak256 placeholders for VAULT /
 *         AUMM / BODENSEE_POOL — `BodenseeBootstrapChannel`'s constructor calls
 *         `_vault.getPoolTokens(BODENSEE_POOL)` to resolve the AuMM token index
 *         per H-D12, which requires BODENSEE_POOL to already exist in VAULT with
 *         AuMM in its token roster. The fixture provides exactly this state.
 *
 * @dev Inheritance pivot from the H10.2 first-attempt (`test/fork/DeployStageH.t.sol`
 *      at commit `c04ee0d`-adjacent uncommitted state): the first attempt used
 *      keccak256 placeholders for all env vars including VAULT / AUMM /
 *      BODENSEE_POOL and reverted with `call to non-contract address 0x6076…DFFb`
 *      (the keccak256-placeholder VAULT). This rewrite inherits
 *      `StageGIntegrationFixture` to sidestep the H-D12 chicken-and-egg
 *      entirely — the fixture deploys the real Vault + AuMM + Bodensee pool
 *      before the script runs.
 *
 * @dev Run with:
 *
 *        forge test --match-path "test/fork/DeployStageH.t.sol" \
 *          --fork-url $MAINNET_RPC_URL --threads 1 -vv
 *
 *      Per D35 split-form + D36 `--threads 1` belt + H-D40 canonical
 *      fork-test invocation pattern.
 *
 * @dev `EFFICIENCY_ORACLE` / `EMA_SAMPLER` / `CCB_MULTIPLIER` / `MILIARIUM_REGISTRY`
 *      retain keccak256 placeholder addresses: their receiver `EmissionDistributor`
 *      binds them into its `_efficiencyOracle` / `_emaSampler` / `_ccbMultiplier` /
 *      `_miliariumRegistry` immutable slots via a pure-storage constructor with only
 *      `ZeroAddress` guards and no external calls at construction time. The
 *      script's correctness against real fork state is validated by the three env
 *      inputs that DO interact with real fork state: VAULT
 *      (`BodenseeBootstrapChannel` constructor H-D12 `getPoolTokens` call),
 *      AUMM (H-D42 env-read + H-D7 Option C `minter()` invariant), and
 *      BODENSEE_POOL (immutable threading into `BodenseeBootstrapChannel`).
 */
contract DeployStageHForkTest is StageGIntegrationFixture {
    // -------------------------------------------------------------------------
    // Placeholder constants — pure-storage constructor slots
    // GOVERNANCE_MULTISIG is INHERITED from StageGIntegrationFixture L64.
    // -------------------------------------------------------------------------

    address internal constant EFFICIENCY_ORACLE_PLACEHOLDER =
        address(uint160(uint256(keccak256("efficiencyOracle"))));
    address internal constant EMA_SAMPLER_PLACEHOLDER =
        address(uint160(uint256(keccak256("emaSampler"))));
    address internal constant CCB_MULTIPLIER_PLACEHOLDER =
        address(uint160(uint256(keccak256("ccbMultiplier"))));
    address internal constant MILIARIUM_REGISTRY_PLACEHOLDER =
        address(uint160(uint256(keccak256("miliariumRegistry"))));

    // -------------------------------------------------------------------------
    // State — populated in test_DeployStageH
    // -------------------------------------------------------------------------

    DeployStageH internal deployStageHScript;
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
        vm.setEnv("GAUGE_REGISTRY", vm.toString(address(gaugeRegistry)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("EFFICIENCY_ORACLE", vm.toString(EFFICIENCY_ORACLE_PLACEHOLDER));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("EMA_SAMPLER", vm.toString(EMA_SAMPLER_PLACEHOLDER));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("CCB_MULTIPLIER", vm.toString(CCB_MULTIPLIER_PLACEHOLDER));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_REGISTRY", vm.toString(MILIARIUM_REGISTRY_PLACEHOLDER));
    }

    // -------------------------------------------------------------------------
    // Test
    // -------------------------------------------------------------------------

    function test_DeployStageH() public {
        // (1) Instantiate the script contract.
        deployStageHScript = new DeployStageH();

        // (2) Run the deploy sequence. Pass the script's own address as
        //     `deployer` — mirrors DeployAureumVaultForkTest L98 convention
        //     `factory = deployer.deploy(address(deployer))`. The script
        //     contract owns the CREATE context for the Step 4 governance handoff.
        emissionDistributor = deployStageHScript.deploy(address(deployStageHScript));

        // (3a) AUMM env-read landed in the script's aumm state slot.
        assertEq(
            address(deployStageHScript.aumm()),
            address(aumm),
            "deployStageHScript.aumm slot != fixture AUMM"
        );

        // (3b) H-D7 Option C + H-D42 invariant: setMinter not called by script.
        assertEq(
            aumm.minter(),
            address(0),
            "aumm.minter() must be address(0) post-deploy per H-D7 Option C"
        );

        // (3b-bis) H-D7 Option C + I-D9 invariant: setAuMTContractForPool not called by script.
        assertEq(
            emissionDistributor.auMTContractByPool(bodenseePool),
            address(0),
            "emissionDistributor.auMTContractByPool(bodenseePool) must be address(0) post-deploy per H-D7 Option C + I-D9 deferred binding"
        );

        // (3c)-(3d) Step 4 governance handoffs — the two emission-stack contracts DeployStageH
        //           deploys. TVLOracle + EfficiencyOracle handoffs moved to the DeployStageF
        //           test per P-D28.
        assertEq(
            deployStageHScript.bodenseeBootstrapChannel().governance(),
            GOVERNANCE_MULTISIG,
            "bodenseeBootstrapChannel governance handoff"
        );
        assertEq(
            deployStageHScript.emissionDistributor().governance(),
            GOVERNANCE_MULTISIG,
            "emissionDistributor governance handoff"
        );

        // (3e) The efficiencyOracle.setEmissionsRecorder(distributor) wiring is cross-script
        //      (EfficiencyOracle in DeployStageF, the distributor here) and moved to the P9.5
        //      orchestrator per P-D28; it is asserted in the P9.6 orchestrator test, not here.

        // (3f) BODENSEE_POOL immutable threaded into BodenseeBootstrapChannel.
        assertEq(
            deployStageHScript.bodenseeBootstrapChannel().BODENSEE_POOL(),
            bodenseePool,
            "bodenseeBootstrapChannel.BODENSEE_POOL"
        );

        // (4) Positive setMinter proof — Stage K simulation.
        //     StageGIntegrationFixture L152 deploys aumm with
        //     `_minterAdmin = address(this)`, where `address(this)` in setUp
        //     resolves to this test contract (DeployStageHForkTest). The test
        //     contract therefore holds setMinter authority directly — no
        //     vm.prank needed. This diverges from production (where _minterAdmin
        //     would be GOVERNANCE_MULTISIG), but the divergence is irrelevant to
        //     the H10.2 deploy-validation purpose: what the assertion proves is
        //     structural — the script does NOT call setMinter, leaving the slot
        //     consumable from whatever address holds minterAdmin authority.
        //     Stage K's own test will validate the GOVERNANCE_MULTISIG path.
        aumm.setMinter(address(emissionDistributor));
        assertEq(
            aumm.minter(),
            address(emissionDistributor),
            "post-setMinter slot -- Stage K simulation"
        );
    }
}
