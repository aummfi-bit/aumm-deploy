// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;
import { Test } from "forge-std/Test.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { AureumGovernanceAuthorizer } from "../../src/governance/AureumGovernanceAuthorizer.sol";
contract AureumGovernanceAuthorizerTest is Test {
    AureumGovernanceAuthorizer internal authorizer;
    address internal governance;
    address internal multisig;
    address internal vault;
    uint256 internal deployBlock;
    function setUp() public {
        governance = makeAddr("governance");
        multisig = makeAddr("emergencyMultisig");
        vault = makeAddr("vault");
        deployBlock = block.number;
        authorizer = new AureumGovernanceAuthorizer(governance, multisig, vault);
    }
    // --- immutables / encoding ---
    function test_immutables_setFromConstructor() public view {
        assertEq(authorizer.GOVERNANCE_CONTRACT(), governance);
        assertEq(authorizer.EMERGENCY_MULTISIG(), multisig);
        assertEq(authorizer.EMERGENCY_WINDOW_BLOCKS(), 2_628_000);
        assertEq(authorizer.EMERGENCY_WINDOW_END_BLOCK(), deployBlock + 2_628_000);
    }
    function test_actionIds_matchAuthenticationEncoding() public view {
        bytes32 disambiguator = bytes32(uint256(uint160(vault)));
        bytes32 expectedPause = keccak256(abi.encodePacked(disambiguator, IVaultAdmin.pauseVault.selector));
        bytes32 expectedRecovery = keccak256(abi.encodePacked(disambiguator, IVaultAdmin.enableRecoveryMode.selector));
        bytes32 expectedUnpause = keccak256(abi.encodePacked(disambiguator, IVaultAdmin.unpauseVault.selector));
        bytes32 expectedDisableRecovery = keccak256(abi.encodePacked(disambiguator, IVaultAdmin.disableRecoveryMode.selector));
        assertEq(authorizer.EMERGENCY_ACTION_PAUSE_VAULT(), expectedPause);
        assertEq(authorizer.EMERGENCY_ACTION_ENABLE_RECOVERY_MODE(), expectedRecovery);
        assertEq(authorizer.EMERGENCY_ACTION_UNPAUSE_VAULT(), expectedUnpause);
        assertEq(authorizer.EMERGENCY_ACTION_DISABLE_RECOVERY_MODE(), expectedDisableRecovery);
    }
    // --- canPerform: governance ---
    function test_canPerform_governanceAlwaysTrue(bytes32 actionId, address target) public {
        // governance authority is unbounded by action type and by the emergency window
        assertTrue(authorizer.canPerform(actionId, governance, target));
        vm.roll(authorizer.EMERGENCY_WINDOW_END_BLOCK() + 1);
        assertTrue(authorizer.canPerform(actionId, governance, target));
    }
    // --- canPerform: emergency multisig, in window ---
    function test_canPerform_emergencyMultisigInWindow_pauseVault() public view {
        assertTrue(authorizer.canPerform(authorizer.EMERGENCY_ACTION_PAUSE_VAULT(), multisig, address(0)));
    }
    function test_canPerform_emergencyMultisigInWindow_enableRecoveryMode() public view {
        assertTrue(authorizer.canPerform(authorizer.EMERGENCY_ACTION_ENABLE_RECOVERY_MODE(), multisig, address(0)));
    }
    function test_canPerform_emergencyMultisigInWindow_unpauseVault() public view {
        assertTrue(authorizer.canPerform(authorizer.EMERGENCY_ACTION_UNPAUSE_VAULT(), multisig, address(0)));
    }
    function test_canPerform_emergencyMultisigInWindow_disableRecoveryMode() public view {
        assertTrue(authorizer.canPerform(authorizer.EMERGENCY_ACTION_DISABLE_RECOVERY_MODE(), multisig, address(0)));
    }
    function test_canPerform_emergencyMultisigNonEmergencyAction_false(bytes32 actionId) public view {
        vm.assume(actionId != authorizer.EMERGENCY_ACTION_PAUSE_VAULT());
        vm.assume(actionId != authorizer.EMERGENCY_ACTION_ENABLE_RECOVERY_MODE());
        vm.assume(actionId != authorizer.EMERGENCY_ACTION_UNPAUSE_VAULT());
        vm.assume(actionId != authorizer.EMERGENCY_ACTION_DISABLE_RECOVERY_MODE());
        assertFalse(authorizer.canPerform(actionId, multisig, address(0)));
    }
    // --- canPerform: emergency window expiry (strict <) ---
    function test_canPerform_emergencyMultisigPostWindow_false() public {
        vm.roll(authorizer.EMERGENCY_WINDOW_END_BLOCK() + 1);
        assertFalse(authorizer.canPerform(authorizer.EMERGENCY_ACTION_PAUSE_VAULT(), multisig, address(0)));
        assertFalse(authorizer.canPerform(authorizer.EMERGENCY_ACTION_ENABLE_RECOVERY_MODE(), multisig, address(0)));
        assertFalse(authorizer.canPerform(authorizer.EMERGENCY_ACTION_UNPAUSE_VAULT(), multisig, address(0)));
        assertFalse(authorizer.canPerform(authorizer.EMERGENCY_ACTION_DISABLE_RECOVERY_MODE(), multisig, address(0)));
    }
    function test_canPerform_windowBoundaryStrict() public {
        uint256 windowEnd = authorizer.EMERGENCY_WINDOW_END_BLOCK();
        bytes32 pauseId = authorizer.EMERGENCY_ACTION_PAUSE_VAULT();
        vm.roll(windowEnd - 1);
        assertTrue(authorizer.canPerform(pauseId, multisig, address(0)));
        vm.roll(windowEnd);
        assertFalse(authorizer.canPerform(pauseId, multisig, address(0)));
    }
    // --- canPerform: random account ---
    function test_canPerform_randomAccount_false(bytes32 actionId, address account, address target) public view {
        vm.assume(account != governance);
        vm.assume(account != multisig);
        assertFalse(authorizer.canPerform(actionId, account, target));
    }
    // --- constructor zero-address reverts ---
    function test_constructor_revertsOnZeroGovernance() public {
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "AureumGovernanceAuthorizer: zero governance"));
        new AureumGovernanceAuthorizer(address(0), multisig, vault);
    }
    function test_constructor_revertsOnZeroMultisig() public {
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "AureumGovernanceAuthorizer: zero multisig"));
        new AureumGovernanceAuthorizer(governance, address(0), vault);
    }
    function test_constructor_revertsOnZeroVault() public {
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "AureumGovernanceAuthorizer: zero vault"));
        new AureumGovernanceAuthorizer(governance, multisig, address(0));
    }
}
