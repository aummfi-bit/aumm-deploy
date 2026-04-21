// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

import { Vault } from "@balancer-labs/v3-vault/contracts/Vault.sol";
import { VaultAdmin } from "@balancer-labs/v3-vault/contracts/VaultAdmin.sol";
import { VaultExtension } from "@balancer-labs/v3-vault/contracts/VaultExtension.sol";

import { AureumAuthorizer } from "../src/vault/AureumAuthorizer.sol";
import { AureumProtocolFeeController } from "../src/vault/AureumProtocolFeeController.sol";
import { AureumVaultFactory } from "../src/vault/AureumVaultFactory.sol";

/**
 * @title DeployAureumVault
 * @notice Deploys the Aureum parallel Balancer V3 Vault stack in a single
 *         broadcast: AureumAuthorizer, AureumProtocolFeeController,
 *         AureumVaultFactory, and finally the Vault itself (via
 *         factory.create, which internally deploys VaultAdmin, VaultExtension,
 *         and the Vault via CREATE3).
 *
 * @dev The deploy order is dictated by the three-way address dependency:
 *
 *        FeeController.vault_          needs  Vault address
 *        Vault address                 needs  Factory address + SALT
 *        Factory.initialFeeController  needs  FeeController address
 *
 *      CREATE3 breaks the cycle: the Vault's eventual address depends only on
 *      (factory address, SALT), so once we know the factory's future address
 *      we know the Vault's, and we can deploy the FeeController against that
 *      not-yet-existing Vault address (the FeeController constructor only
 *      *stores* the address as an immutable; it does not call the Vault).
 *
 *      The factory's future address is computed from the deployer's current
 *      nonce via vm.computeCreateAddress. The Vault's future address is
 *      computed via CREATE3.getDeployed(SALT, predictedFactory), which is
 *      `internal pure` and takes the creator as an explicit argument
 *      (see lib/balancer-v3-monorepo/.../CREATE3.sol line 64).
 *
 *      After the factory is deployed we assert that its actual address equals
 *      the predicted address. If any unexpected CREATE happened between the
 *      nonce read and the factory deployment (e.g. a library auto-deploy),
 *      this assertion catches it before any Vault is created.
 *
 * @dev Env vars required (no defaults — a real deploy should never silently
 *      fall back to zero values):
 *
 *        GOVERNANCE_MULTISIG       address  — Aureum authorizer's sole authority
 *        DER_BODENSEE_POOL         address  — fee controller's Bodensee pool identity (D-D9)
 *        FEE_ROUTING_HOOK          address  — fee controller's B10 withdrawal recipient (D-D7)
 *        SALT                      bytes32  — CREATE3 salt for the Vault
 *        PAUSE_WINDOW_DURATION     uint256  — Vault pause window (seconds)
 *        BUFFER_PERIOD_DURATION    uint256  — Vault buffer period (seconds)
 *        MIN_TRADE_AMOUNT          uint256  — Vault min trade amount (wei)
 *        MIN_WRAP_AMOUNT           uint256  — Vault min wrap amount (wei)
 */
contract DeployAureumVault is Script {
    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    /// @notice The deployed factory address did not match the predicted one.
    ///         Almost always means the deployer's nonce shifted between the
    ///         prediction and the deployment — e.g. an unexpected CREATE.
    error FactoryAddressMismatch(address predicted, address actual);

    /// @notice The deployed Vault address did not match the predicted one.
    ///         Almost always means the factory's CREATE3 salt or deployer
    ///         address changed between prediction and `create()`.
    error VaultAddressMismatch(address predicted, address actual);

    // ---------------------------------------------------------------------
    // State — populated during run() so the fork test can read them back
    // ---------------------------------------------------------------------

    AureumAuthorizer public aureumAuthorizer;
    AureumProtocolFeeController public aureumFeeController;
    AureumVaultFactory public aureumFactory;
    IVault public vault;

    // ---------------------------------------------------------------------
    // Entry point
    // ---------------------------------------------------------------------

    /**
     * @notice `forge script` entry point. Reads env vars, broadcasts all
     *         deployments as `msg.sender`, returns the factory.
     */
    function run() external returns (AureumVaultFactory) {
        vm.startBroadcast();
        AureumVaultFactory f = _deploy(msg.sender);
        vm.stopBroadcast();
        return f;
    }

    /**
     * @notice Testable entry point. Performs the same deployment sequence as
     *         `run()` but without `vm.startBroadcast`, so it can be called
     *         directly from a fork test as
     *         `deployer.deploy(address(deployer))`. The `deployer` argument
     *         is the address whose nonce is used to predict the factory's
     *         eventual address — it must be the address that actually
     *         performs the CREATEs, which in a test context is the
     *         `DeployAureumVault` contract itself.
     */
    function deploy(address deployer) external returns (AureumVaultFactory) {
        return _deploy(deployer);
    }

    /**
     * @notice Internal deploy sequence. See contract-level docstring for the
     *         address-dependency-loop explanation. The `deployer` argument
     *         is used for nonce prediction; it must equal the address that
     *         owns the current CREATE context (`msg.sender` under broadcast,
     *         `address(this)` under direct internal call).
     */
    function _deploy(address deployer) internal returns (AureumVaultFactory) {
        // -- 0. Read config from env (no defaults on purpose) -------------

        address governanceMultisig = vm.envAddress("GOVERNANCE_MULTISIG");
        address derBodenseePool = vm.envAddress("DER_BODENSEE_POOL");
        address feeRoutingHook = vm.envAddress("FEE_ROUTING_HOOK");
        bytes32 salt = vm.envBytes32("SALT");
        uint32 pauseWindowDuration = uint32(vm.envUint("PAUSE_WINDOW_DURATION"));
        uint32 bufferPeriodDuration = uint32(vm.envUint("BUFFER_PERIOD_DURATION"));
        uint256 minTradeAmount = vm.envUint("MIN_TRADE_AMOUNT");
        uint256 minWrapAmount = vm.envUint("MIN_WRAP_AMOUNT");

        // -- 1. Hash the three creation codes -----------------------------
        // The factory stores these as immutables and reverts in `create()`
        // if the runtime-supplied creation code does not hash to the stored
        // value. Computing them here once from `type(X).creationCode` means
        // the script and the factory agree by construction. Inlined
        // (rather than via intermediate `bytes memory` locals) to keep the
        // Yul stack-frame size of _deploy within the IR optimiser's limit
        // after the D-D7 addition of a third constructor argument.

        bytes32 vaultCreationCodeHash = keccak256(type(Vault).creationCode);
        bytes32 vaultAdminCreationCodeHash = keccak256(type(VaultAdmin).creationCode);
        bytes32 vaultExtensionCreationCodeHash = keccak256(type(VaultExtension).creationCode);

        // -- 2. Predict the factory's eventual address --------------------
        // The factory will be the N-th CREATE from `deployer`, where N is
        // `deployer`'s current nonce. Foundry's vm.computeCreateAddress
        // implements the standard RLP(sender, nonce) derivation. Any CREATE
        // between this line and the factory deployment will invalidate the
        // prediction — we assert on it below.
        //
        // `deployer` is a function argument rather than `msg.sender` so this
        // function works in both broadcast and direct-call contexts. See the
        // `run()` and `deploy()` entry points above.

        uint64 deployerNonce = vm.getNonce(deployer);

        // The authorizer will be deployed at nonce N (the next CREATE).
        // The fee controller will be deployed at nonce N+1.
        // The factory will be deployed at nonce N+2.
        address predictedFactory = vm.computeCreateAddress(deployer, deployerNonce + 2);

        // -- 3. Predict the Vault's eventual address ----------------------
        // CREATE3.getDeployed is internal pure and depends only on
        // (creator, salt). We pass predictedFactory as the creator because
        // that is who will call CREATE3.deploy() inside factory.create().

        address predictedVault = CREATE3.getDeployed(salt, predictedFactory);

        // -- 4. Deploy everything -----------------------------------------
        // No vm.startBroadcast here — the caller (`run()` or a test)
        // establishes the CREATE context.

        // 4a. AureumAuthorizer (nonce N)
        aureumAuthorizer = new AureumAuthorizer(governanceMultisig);

        // 4b. AureumProtocolFeeController (nonce N+1)
        //     The vault_ argument references an address that does not yet
        //     have code. The FeeController constructor only stores it as an
        //     immutable; it does not call into the Vault.
        aureumFeeController = new AureumProtocolFeeController(
            IVault(predictedVault),
            derBodenseePool,
            feeRoutingHook
        );

        // 4c. AureumVaultFactory (nonce N+2, must equal predictedFactory)
        aureumFactory = new AureumVaultFactory(
            IAuthorizer(address(aureumAuthorizer)),
            pauseWindowDuration,
            bufferPeriodDuration,
            minTradeAmount,
            minWrapAmount,
            vaultCreationCodeHash,
            vaultExtensionCreationCodeHash,
            vaultAdminCreationCodeHash,
            IProtocolFeeController(address(aureumFeeController))
        );

        if (address(aureumFactory) != predictedFactory) {
            revert FactoryAddressMismatch(predictedFactory, address(aureumFactory));
        }

        // 4d. factory.create() — deploys VaultAdmin, VaultExtension, Vault
        aureumFactory.create(
            salt,
            predictedVault,
            type(Vault).creationCode,
            type(VaultExtension).creationCode,
            type(VaultAdmin).creationCode
        );

        // -- 5. Final sanity check ----------------------------------------
        // factory.create() already asserts `deployedAddress == vaultAddress`
        // internally (see AureumVaultFactory.sol line ~158, VaultAddressMismatch).
        // We re-check here against our *own* prediction, which is a stronger
        // statement: it confirms the script's nonce arithmetic matches what
        // the factory actually did.

        address actualVault = aureumFactory.getDeploymentAddress(salt);
        if (actualVault != predictedVault) {
            revert VaultAddressMismatch(predictedVault, actualVault);
        }
        vault = IVault(actualVault);

        return aureumFactory;
    }
}
