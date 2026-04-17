// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { AureumAuthorizer } from "../../src/vault/AureumAuthorizer.sol";

contract AureumAuthorizerTest is Test {
    AureumAuthorizer internal authorizer;
    address internal multisig;

    function setUp() public {
        multisig = makeAddr("multisig");
        authorizer = new AureumAuthorizer(multisig);
    }

    function test_canPerform_returnsTrueForMultisig(bytes32 actionId, address target) public view {
        assertTrue(authorizer.canPerform(actionId, multisig, target));
    }

    function test_canPerform_returnsFalseForNonMultisig(
        bytes32 actionId,
        address notMultisig,
        address target
    ) public view {
        vm.assume(notMultisig != multisig);
        assertFalse(authorizer.canPerform(actionId, notMultisig, target));
    }

    function test_constructor_revertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "AureumAuthorizer: zero multisig"));
        new AureumAuthorizer(address(0));
    }

    function test_governanceMultisig_returnsConstructorArgument() public view {
        assertEq(authorizer.GOVERNANCE_MULTISIG(), multisig);
    }
}
