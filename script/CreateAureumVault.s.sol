// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { AureumVaultFactory } from "../src/vault/AureumVaultFactory.sol";

/**
 * @title CreateAureumVault
 * @notice Calls `create()` on an ALREADY-DEPLOYED AureumVaultFactory, and does
 *         nothing else. This is the create-only tail of `DeployAureumVault`,
 *         split out because the PB3.5i9d broadcast landed its first three
 *         transactions and had its fourth rejected by the RPC provider for
 *         exceeding a per-transaction gas ceiling.
 * @dev    Re-running `DeployAureumVault.run()` from that state is destructive:
 *         `_deploy` derives `predictedFactory` from the LIVE deployer nonce, so
 *         a second run would deploy a second authorizer, fee controller and
 *         factory at the next three nonces and strand the sealed immutables of
 *         the first set. This script consumes exactly one nonce and deploys no
 *         contract of its own, so every address projection downstream of the
 *         Vault survives unchanged.
 * @dev    The Vault address is a CREATE3 of (factory, salt) and does not depend
 *         on the deployer nonce, which is why the target is unmoved by the
 *         rejected transaction.
 * @dev Env vars required (no defaults per PB-D22 (ii)):
 *
 *        AUREUM_VAULT_FACTORY  address — the live factory, already deployed
 *        AUREUM_VAULT          address — the projected Vault, asserted below
 *        SALT                  bytes32 — the raw CREATE3 salt
 */
contract CreateAureumVault is Script {
    /// @notice The factory's own CREATE3 derivation disagrees with the projection.
    error VaultAddressMismatch(address predicted, address actual);

    /// @notice The Vault already exists; `create` would revert on its own guard.
    error VaultAlreadyCreated(address vault);

    /// @notice `forge script` entry — one call, one nonce, no deploys of its own.
    function run() external {
        AureumVaultFactory factory = AureumVaultFactory(vm.envAddress("AUREUM_VAULT_FACTORY"));
        address predictedVault = vm.envAddress("AUREUM_VAULT");
        bytes32 salt = vm.envBytes32("SALT");

        address computed = factory.getDeploymentAddress(salt);
        if (computed != predictedVault) {
            revert VaultAddressMismatch(predictedVault, computed);
        }
        if (factory.isDeployed(predictedVault)) {
            revert VaultAlreadyCreated(predictedVault);
        }

        vm.startBroadcast();
        factory.create(
            salt,
            predictedVault,
            vm.getCode("out-vault/Vault.sol/Vault.json"),
            vm.getCode("out-vault/VaultExtension.sol/VaultExtension.json"),
            vm.getCode("out-vault/VaultAdmin.sol/VaultAdmin.json")
        );
        vm.stopBroadcast();

        console2.log("Aureum Vault created at:", predictedVault);
    }
}
