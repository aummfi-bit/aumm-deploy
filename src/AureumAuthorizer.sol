// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";

contract AureumAuthorizer is IAuthorizer {
    address public immutable GOVERNANCE_MULTISIG;

    constructor(address governanceMultisig_) {
        require(governanceMultisig_ != address(0), "AureumAuthorizer: zero multisig");
        GOVERNANCE_MULTISIG = governanceMultisig_;
    }

    function canPerform(bytes32, address account, address) external view returns (bool) {
        return account == GOVERNANCE_MULTISIG;
    }
}
