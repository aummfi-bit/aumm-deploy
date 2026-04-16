// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";

contract AureumAuthorizer is IAuthorizer {
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    address public immutable GOVERNANCE_MULTISIG;

    constructor(address governanceMultisig_) {
        require(governanceMultisig_ != address(0), "AureumAuthorizer: zero multisig");
        GOVERNANCE_MULTISIG = governanceMultisig_;
    }

    function canPerform(bytes32, address account, address) external view returns (bool) {
        return account == GOVERNANCE_MULTISIG;
    }
}
