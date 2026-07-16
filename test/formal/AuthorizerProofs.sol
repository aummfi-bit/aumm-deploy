// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IVaultAdmin} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";

import {AureumGovernanceAuthorizer} from "src/governance/AureumGovernanceAuthorizer.sol";
import {AureumAuthorizer} from "src/vault/AureumAuthorizer.sol";

/// @title  AuthorizerProofs
/// @notice hevm symbolic proofs for the authorizer-window surface (PB2.12f /
///         PB-D17). Invoke: hevm test --match prove_ --solver bitwuzla
///         --smt-timeout 300 --max-iterations 10 --root .
/// @dev    Tier-1 of the authorizer-window surface (PB2.12f / PB-D17, the
///         S8-relabeled fourth surface). P-W* namespace. BOTH contracts carry
///         ZERO mutable storage, so every proof is a pure view sweep over
///         immutables + block.number + symbolic args. The Vault.setAuthorizer
///         K7 migration leg is Vault-side audited Balancer substrate
///         (CLAUDE.md section-1 inheritance posture), covered as an
///         interaction note in the f2 .act spec, not provable Aureum
///         bytecode. Solver note: pure address/hash comparison logic,
///         z3-class; canonical run stays bitwuzla per the suite command.
contract AuthorizerProofs is Test {
    AureumGovernanceAuthorizer internal auth;
    AureumAuthorizer internal legacy;

    uint256 internal constant DEPLOY_BLOCK = 1000;
    address internal constant GOV = address(0x60E5);
    address internal constant MSIG = address(0x5AFE);
    address internal constant VAULT_ADDR = address(0xFA17);
    address internal constant LEGACY_MSIG = address(0xAC01);

    function setUp() public {
        // Pins EMERGENCY_WINDOW_END_BLOCK at DEPLOY_BLOCK + 2_628_000
        // deterministically.
        vm.roll(DEPLOY_BLOCK);
        // Constructor is H13-safe: action IDs computed locally; VAULT_ADDR is
        // hashed and never called.
        auth = new AureumGovernanceAuthorizer(GOV, MSIG, VAULT_ADDR);
        legacy = new AureumAuthorizer(LEGACY_MSIG);
    }

    // -------------------------------------------------------------------------
    // P-W* -- AureumGovernanceAuthorizer window + AureumAuthorizer from-state.
    // -------------------------------------------------------------------------

    /// P-W1: governance authority is unconditional and window-independent,
    /// alive arbitrarily far past the emergency boundary.
    function prove_gov_omnipotent(bytes32 actionId, address where, uint256 delta) public {
        vm.assume(delta <= 1e30);

        assert(auth.canPerform(actionId, GOV, where));

        vm.roll(auth.EMERGENCY_WINDOW_END_BLOCK() + delta);
        assert(auth.canPerform(actionId, GOV, where));
    }

    /// P-W2 in-window leg: both emergency actions live at every block
    /// strictly inside the window.
    function prove_emergency_inWindow(uint256 delta, address where) public {
        uint256 window = auth.EMERGENCY_WINDOW_BLOCKS();
        vm.assume(delta < window);

        vm.roll(DEPLOY_BLOCK + delta);
        assert(auth.canPerform(auth.EMERGENCY_ACTION_PAUSE_VAULT(), MSIG, where));
        assert(
            auth.canPerform(auth.EMERGENCY_ACTION_ENABLE_RECOVERY_MODE(), MSIG, where)
        );
    }

    /// P-W2 time-bomb leg: the strict < boundary kills the role at EXACTLY
    /// the end block (delta == 0) and forever after; no revival path exists
    /// (all inputs are immutable).
    function prove_emergency_deadFromBoundary(uint256 delta, address where) public {
        vm.assume(delta <= 1e30);

        vm.roll(auth.EMERGENCY_WINDOW_END_BLOCK() + delta);
        assert(
            auth.canPerform(auth.EMERGENCY_ACTION_PAUSE_VAULT(), MSIG, where) == false
        );
        assert(
            auth.canPerform(auth.EMERGENCY_ACTION_ENABLE_RECOVERY_MODE(), MSIG, where)
                == false
        );
    }

    /// P-W2 scope leg: inside the window the multisig holds exactly two
    /// action IDs, nothing else.
    function prove_emergency_scopeLimited(bytes32 actionId, address where) public {
        bytes32 pause = auth.EMERGENCY_ACTION_PAUSE_VAULT();
        bytes32 recovery = auth.EMERGENCY_ACTION_ENABLE_RECOVERY_MODE();
        vm.assume(actionId != pause);
        vm.assume(actionId != recovery);

        vm.roll(DEPLOY_BLOCK + 1);
        assert(auth.canPerform(actionId, MSIG, where) == false);
    }

    /// P-W3: every non-principal account is denied every action at every
    /// block, in-window and beyond in one symbolic sweep.
    function prove_stranger_nullity(
        address account,
        bytes32 actionId,
        address where,
        uint256 delta
    ) public {
        vm.assume(account != GOV);
        vm.assume(account != MSIG);
        vm.assume(delta <= 1e30);

        vm.roll(DEPLOY_BLOCK + delta);
        assert(auth.canPerform(actionId, account, where) == false);
    }

    /// P-W4: pins the Balancer Authentication.getActionId encoding
    /// (vault-address disambiguator ++ selector) against constructor drift;
    /// hash distinctness witnesses the two-action scope is genuinely two
    /// actions.
    function prove_actionId_binding() public view {
        bytes32 d = bytes32(uint256(uint160(VAULT_ADDR)));
        assert(
            keccak256(abi.encodePacked(d, IVaultAdmin.pauseVault.selector))
                == auth.EMERGENCY_ACTION_PAUSE_VAULT()
        );
        assert(
            keccak256(abi.encodePacked(d, IVaultAdmin.enableRecoveryMode.selector))
                == auth.EMERGENCY_ACTION_ENABLE_RECOVERY_MODE()
        );
        assert(
            auth.EMERGENCY_ACTION_PAUSE_VAULT()
                != auth.EMERGENCY_ACTION_ENABLE_RECOVERY_MODE()
        );
    }

    /// P-W5: the Stage A-K from-state of the K7 setAuthorizer migration is a
    /// single-principal equality gate -- the multisig can perform EVERY
    /// action, everyone else none.
    function prove_legacy_authorizer_gate(
        bytes32 actionId,
        address account,
        address where
    ) public {
        assert(legacy.canPerform(actionId, LEGACY_MSIG, where) == true);

        vm.assume(account != LEGACY_MSIG);
        assert(legacy.canPerform(actionId, account, where) == false);
    }
}
