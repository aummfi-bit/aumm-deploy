// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { VaultExtension } from "@balancer-labs/v3-vault/contracts/VaultExtension.sol";
import { VaultAdmin } from "@balancer-labs/v3-vault/contracts/VaultAdmin.sol";

/// @notice One-off factory to deploy the Vault at a specific address.
contract AureumVaultFactory is ReentrancyGuardTransient, Ownable2Step {
    bytes32 public immutable vaultCreationCodeHash;
    bytes32 public immutable vaultAdminCreationCodeHash;
    bytes32 public immutable vaultExtensionCreationCodeHash;

    /// @notice The protocol fee controller this factory was deployed with, wired into every Vault produced by `create()`.
    /// @dev The Vault's *current* controller may diverge from this if governance later calls `Vault.setProtocolFeeController`.
    // Rationale: matches Balancer V3 immutable naming (SCREAMING_CASE for
    // protocol-critical addresses). Consistent with foundry.toml [lint]
    // ignore decision on the forked portion of this file.
    // slither-disable-next-line naming-convention
    IProtocolFeeController public immutable INITIAL_FEE_CONTROLLER;

    mapping(address vaultAddress => VaultExtension) public deployedVaultExtensions;
    mapping(address vaultAddress => VaultAdmin) public deployedVaultAdmins;
    mapping(address vaultAddress => bool deployed) public isDeployed;

    IAuthorizer private immutable _authorizer;
    uint32 private immutable _pauseWindowDuration;
    uint32 private immutable _bufferPeriodDuration;
    uint256 private immutable _minTradeAmount;
    uint256 private immutable _minWrapAmount;

    /**
     * @notice Emitted when the Vault is deployed.
     * @param vault The Vault's address
     */
    // Rationale: upstream-verbatim from balancer-v3-monorepo/pkg/vault/
    // contracts/VaultFactory.sol line 42. This finding (unindexed-event-address)
    // cannot be suppressed inline due to a Slither 0.11.4 bug where the
    // detector emits findings with empty `elements`, bypassing the ignore-
    // comment check. Accepted as documented in docs/STAGE_B_NOTES.md (B6).
    event VaultCreated(address vault);

    /// @notice The given salt does not match the generated address when attempting to create the Vault.
    error VaultAddressMismatch();

    /**
     * @notice The bytecode for the given contract does not match the expected bytecode.
     * @param contractName The name of the mismatched contract
     */
    error InvalidBytecode(string contractName);

    /**
     * @notice The Vault has already been deployed at this target address.
     * @param vault Vault address already consumed by a previous deployment
     */
    error VaultAlreadyDeployed(address vault);

    constructor(
        IAuthorizer authorizer,
        uint32 pauseWindowDuration,
        uint32 bufferPeriodDuration,
        uint256 minTradeAmount,
        uint256 minWrapAmount,
        bytes32 vaultCreationCodeHash_,
        bytes32 vaultExtensionCreationCodeHash_,
        bytes32 vaultAdminCreationCodeHash_,
        IProtocolFeeController initialFeeController_
    ) Ownable(msg.sender) {
        vaultCreationCodeHash = vaultCreationCodeHash_;
        vaultAdminCreationCodeHash = vaultAdminCreationCodeHash_;
        vaultExtensionCreationCodeHash = vaultExtensionCreationCodeHash_;

        INITIAL_FEE_CONTROLLER = initialFeeController_;

        _authorizer = authorizer;
        _pauseWindowDuration = pauseWindowDuration;
        _bufferPeriodDuration = bufferPeriodDuration;
        _minTradeAmount = minTradeAmount;
        _minWrapAmount = minWrapAmount;
    }

    /**
     * @notice Deploys the Vault.
     * @dev The Vault can only be deployed once per salt. This function is permissioned.
     *
     * @param salt Salt used to create the Vault. See `getDeploymentAddress`
     * @param targetAddress Expected Vault address. The function will revert if the given salt does not deploy the
     * Vault to the target address
     * @param vaultCreationCode Creation code for the Vault
     * @param vaultExtensionCreationCode Creation code for the VaultExtension
     * @param vaultAdminCreationCode Creation code for the VaultAdmin
     */
    function create(
        bytes32 salt,
        address targetAddress,
        bytes calldata vaultCreationCode,
        bytes calldata vaultExtensionCreationCode,
        bytes calldata vaultAdminCreationCode
    ) external onlyOwner nonReentrant {
        if (isDeployed[targetAddress]) {
            revert VaultAlreadyDeployed(targetAddress);
        }

        if (vaultCreationCodeHash != keccak256(vaultCreationCode)) {
            revert InvalidBytecode("Vault");
        } else if (vaultAdminCreationCodeHash != keccak256(vaultAdminCreationCode)) {
            revert InvalidBytecode("VaultAdmin");
        } else if (vaultExtensionCreationCodeHash != keccak256(vaultExtensionCreationCode)) {
            revert InvalidBytecode("VaultExtension");
        }

        address vaultAddress = getDeploymentAddress(salt);
        if (targetAddress != vaultAddress) {
            revert VaultAddressMismatch();
        }

        // Rationale: dynamic args are upstream creation bytecode (constant)
        // plus abi.encode of constructor args (collision-safe); standard
        // Balancer V3 deployment pattern.
        // slither-disable-next-line encode-packed-collision
        VaultAdmin vaultAdmin = VaultAdmin(
            payable(
                Create2.deploy(
                    0, // ETH value
                    salt,
                    abi.encodePacked(
                        vaultAdminCreationCode,
                        abi.encode(
                            IVault(vaultAddress),
                            _pauseWindowDuration,
                            _bufferPeriodDuration,
                            _minTradeAmount,
                            _minWrapAmount
                        )
                    )
                )
            )
        );
        deployedVaultAdmins[vaultAddress] = vaultAdmin;

        // Rationale: dynamic args are upstream creation bytecode (constant)
        // plus abi.encode of constructor args (collision-safe); standard
        // Balancer V3 deployment pattern.
        // slither-disable-next-line encode-packed-collision
        VaultExtension vaultExtension = VaultExtension(
            payable(
                Create2.deploy(
                    0, // ETH value
                    salt,
                    abi.encodePacked(vaultExtensionCreationCode, abi.encode(vaultAddress, vaultAdmin))
                )
            )
        );
        deployedVaultExtensions[vaultAddress] = vaultExtension;

        // Rationale (encode-packed-collision): dynamic args are upstream creation
        // bytecode (constant) plus abi.encode of constructor args (collision-safe);
        // standard Balancer V3 deployment pattern.
        // Rationale (reentrancy-no-eth): CREATE3.deploy creates a fresh contract
        // at a deterministic address with no prior code; no caller exists to
        // reenter the factory before isDeployed is set later in this function.
        // slither-disable-next-line encode-packed-collision,reentrancy-no-eth
        address deployedAddress = CREATE3.deploy(
            salt,
            abi.encodePacked(vaultCreationCode, abi.encode(vaultExtension, _authorizer, INITIAL_FEE_CONTROLLER)),
            0
        );

        // This should always be the case, but we enforce the end state to match the expected outcome anyway.
        if (deployedAddress != vaultAddress) {
            revert VaultAddressMismatch();
        }

        emit VaultCreated(vaultAddress);

        isDeployed[vaultAddress] = true;
    }

    /// @notice Gets deployment address for a given salt.
    function getDeploymentAddress(bytes32 salt) public view returns (address) {
        return CREATE3.getDeployed(salt);
    }
}
