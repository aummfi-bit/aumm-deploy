// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { AureumAuthorizer } from "../../src/vault/AureumAuthorizer.sol";
import { AureumProtocolFeeController } from "../../src/vault/AureumProtocolFeeController.sol";
import { AureumVaultFactory } from "../../src/vault/AureumVaultFactory.sol";

import { DeployAureumVault } from "../../script/DeployAureumVault.s.sol";

/**
 * @title DeployAureumVaultForkTest
 * @notice Integration test for `script/DeployAureumVault.s.sol`. Instantiates
 *         the script contract, calls `deploy(address(deployer))` to run the
 *         full four-contract deploy sequence on a mainnet fork, and asserts
 *         the resulting Vault state is internally consistent.
 *
 * @dev Run with:
 *
 *        source .env
 *        forge test --fork-url $MAINNET_RPC_URL \
 *          --match-path test/fork/DeployAureumVault.t.sol -vv
 *
 *      Follows the Stage A Sanity.t.sol convention of taking the fork URL
 *      from the CLI rather than calling `vm.createSelectFork` in code.
 *
 * @dev The seven env vars that `DeployAureumVault` reads are set in `setUp`
 *      via `vm.setEnv`, so the test does not depend on shell state beyond
 *      the fork URL. Placeholder values mirror the shapes documented in
 *      `.env.example`.
 */
contract DeployAureumVaultForkTest is Test {
    // ---------------------------------------------------------------------
    // Test config — set as env vars in setUp(), read by the script
    // ---------------------------------------------------------------------

    address internal constant GOVERNANCE_MULTISIG = address(uint160(uint256(keccak256("govMultisig"))));
    address internal constant DER_BODENSEE_POOL = address(uint160(uint256(keccak256("derBodenseePool"))));
    bytes32 internal constant SALT = bytes32(uint256(1));

    uint256 internal constant PAUSE_WINDOW_DURATION = 4 * 365 days;
    uint256 internal constant BUFFER_PERIOD_DURATION = 90 days;
    uint256 internal constant MIN_TRADE_AMOUNT = 1_000_000;
    uint256 internal constant MIN_WRAP_AMOUNT = 1_000;

    // ---------------------------------------------------------------------
    // Deploy artifacts — populated in test_DeployAureumVault
    // ---------------------------------------------------------------------

    DeployAureumVault internal deployer;
    AureumVaultFactory internal factory;
    AureumAuthorizer internal authorizer;
    AureumProtocolFeeController internal feeController;
    IVault internal vault;

    // ---------------------------------------------------------------------
    // Setup
    // ---------------------------------------------------------------------

    function setUp() public {
        // Rationale: vm.setEnv is flagged by forge-lint as an "unsafe
        // cheatcode" because it mutates process environment state. In this
        // test it is the intentional harness mechanism for parameterizing
        // DeployAureumVault.s.sol — the script reads deployment config via
        // vm.envString / vm.envUint, so the fork test must populate those
        // env vars before calling deploy(). Scoped to setUp() in a fork
        // test; no production code path touches vm.setEnv. Per Foundry
        // lint best-practice ("Minimize Scope"), each call is suppressed
        // individually with a targeted disable-next-line directive.
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("GOVERNANCE_MULTISIG", vm.toString(GOVERNANCE_MULTISIG));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("DER_BODENSEE_POOL", vm.toString(DER_BODENSEE_POOL));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("SALT", vm.toString(SALT));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("PAUSE_WINDOW_DURATION", vm.toString(PAUSE_WINDOW_DURATION));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("BUFFER_PERIOD_DURATION", vm.toString(BUFFER_PERIOD_DURATION));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MIN_TRADE_AMOUNT", vm.toString(MIN_TRADE_AMOUNT));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MIN_WRAP_AMOUNT", vm.toString(MIN_WRAP_AMOUNT));
    }

    // ---------------------------------------------------------------------
    // The main test
    // ---------------------------------------------------------------------

    function test_DeployAureumVault() public {
        deployer = new DeployAureumVault();
        factory = deployer.deploy(address(deployer));

        authorizer = deployer.aureumAuthorizer();
        feeController = deployer.aureumFeeController();
        vault = deployer.vault();

        // ----- Consistency: the four contracts point at each other -----

        assertEq(
            factory.getDeploymentAddress(SALT),
            address(vault),
            "factory.getDeploymentAddress != vault"
        );

        assertEq(
            address(vault.getAuthorizer()),
            address(authorizer),
            "vault.getAuthorizer != aureumAuthorizer"
        );

        assertEq(
            address(vault.getProtocolFeeController()),
            address(feeController),
            "vault.getProtocolFeeController != aureumFeeController"
        );

        assertEq(
            address(feeController.vault()),
            address(vault),
            "feeController.vault != vault"
        );

        // ----- Vault construction parameters ------

        (, uint32 pauseWindowEndTime, ) = vault.getVaultPausedState();
        assertApproxEqAbs(
            uint256(pauseWindowEndTime),
            block.timestamp + PAUSE_WINDOW_DURATION,
            1,
            "pauseWindowEndTime off by more than 1 second"
        );

        // ----- Authorizer wiring: EOA reverts, multisig succeeds -----

        vm.expectRevert();
        vault.pauseVault();

        (bool vaultPausedBefore, , ) = vault.getVaultPausedState();
        assertFalse(vaultPausedBefore, "vault should not be paused before multisig call");

        vm.prank(GOVERNANCE_MULTISIG);
        vault.pauseVault();

        (bool vaultPausedAfter, , ) = vault.getVaultPausedState();
        assertTrue(vaultPausedAfter, "vault should be paused after multisig call");
    }
}
