// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";

/**
 * @title AureumGovernanceAuthorizer
 * @notice B-strict authorizer per OQ-10 — `GOVERNANCE_CONTRACT` holds full authorizer-gated authority;
 *         `EMERGENCY_MULTISIG` holds a narrow, time-boxed emergency role limited to {`pauseVault`,
 *         `unpauseVault`, `enableRecoveryMode`, `disableRecoveryMode`} that dies permanently and
 *         irrevocably at `EMERGENCY_WINDOW_END_BLOCK` (strict `<` boundary).
 * @dev F-22 / PB-D63 / PB-D64 (vii) — the emergency set holds each action AND its inverse. Before
 *      that pairing the role could enter `pauseVault` and `enableRecoveryMode` and leave neither,
 *      and both entered states outlive the window: a pause until the Vault's buffer period ends, a
 *      recovery-mode bit forever. The exit grant expires with the entry grant per PB-D64 (x), so
 *      permanent de-escalation lives in `AureumGovernance`'s constrained proposal types rather than
 *      in a standing key, which is what keeps the §xxix dissolution clause intact.
 * @dev Emergency action IDs are computed locally at construction (H13-safe — no external calls).
 *      Disambiguator = `vault_` address per Balancer `Authentication.getActionId` /
 *      `VaultAdmin` encoding (`Authentication.sol:51`, `VaultAdmin.sol:77`).
 */
contract AureumGovernanceAuthorizer is IAuthorizer {
    uint256 public constant EMERGENCY_WINDOW_BLOCKS = 2_628_000;

    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    address public immutable GOVERNANCE_CONTRACT;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    address public immutable EMERGENCY_MULTISIG;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    uint256 public immutable EMERGENCY_WINDOW_END_BLOCK;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    bytes32 public immutable EMERGENCY_ACTION_PAUSE_VAULT;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    bytes32 public immutable EMERGENCY_ACTION_ENABLE_RECOVERY_MODE;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    bytes32 public immutable EMERGENCY_ACTION_UNPAUSE_VAULT;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    bytes32 public immutable EMERGENCY_ACTION_DISABLE_RECOVERY_MODE;

    constructor(address governanceContract_, address emergencyMultisig_, address vault_) {
        require(governanceContract_ != address(0), "AureumGovernanceAuthorizer: zero governance");
        require(emergencyMultisig_ != address(0), "AureumGovernanceAuthorizer: zero multisig");
        require(vault_ != address(0), "AureumGovernanceAuthorizer: zero vault");

        GOVERNANCE_CONTRACT = governanceContract_;
        EMERGENCY_MULTISIG = emergencyMultisig_;
        EMERGENCY_WINDOW_END_BLOCK = block.number + EMERGENCY_WINDOW_BLOCKS;

        bytes32 vaultDisambiguator = bytes32(uint256(uint160(vault_)));
        EMERGENCY_ACTION_PAUSE_VAULT = keccak256(abi.encodePacked(vaultDisambiguator, IVaultAdmin.pauseVault.selector));
        EMERGENCY_ACTION_ENABLE_RECOVERY_MODE = keccak256(abi.encodePacked(vaultDisambiguator, IVaultAdmin.enableRecoveryMode.selector));
        EMERGENCY_ACTION_UNPAUSE_VAULT = keccak256(abi.encodePacked(vaultDisambiguator, IVaultAdmin.unpauseVault.selector));
        EMERGENCY_ACTION_DISABLE_RECOVERY_MODE = keccak256(abi.encodePacked(vaultDisambiguator, IVaultAdmin.disableRecoveryMode.selector));
    }

    function canPerform(bytes32 actionId, address account, address /* where */) external view returns (bool) {
        if (account == GOVERNANCE_CONTRACT) {
            return true;
        }
        if (account == EMERGENCY_MULTISIG && _isEmergencyAction(actionId) && block.number < EMERGENCY_WINDOW_END_BLOCK) {
            return true;
        }
        return false;
    }

    function _isEmergencyAction(bytes32 actionId) internal view returns (bool) {
        return actionId == EMERGENCY_ACTION_PAUSE_VAULT
            || actionId == EMERGENCY_ACTION_ENABLE_RECOVERY_MODE
            || actionId == EMERGENCY_ACTION_UNPAUSE_VAULT
            || actionId == EMERGENCY_ACTION_DISABLE_RECOVERY_MODE;
    }
}
