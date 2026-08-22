// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {VaultClassRegistry} from "src/gauge/VaultClassRegistry.sol";
import {IVaultClassRegistry} from "src/gauge/IVaultClassRegistry.sol";
import {SwapAndDepositToBodensee} from "src/gauge/SwapAndDepositToBodensee.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Passive SwapAndDepositToBodensee stand-in; the registry only forwards the bond via `donate`.
contract MockBodenseeDonationSink {
    function donate(IERC20, uint256) external {}
}

/// @title P1 G.5a — a stale duplicate proposal is a permanent re-admission ticket
/// @notice Reproduction PoC for seam-1 root cause G.5a (Medium). `finalizeProposal`
///         (`src/gauge/VaultClassRegistry.sol:295`) has no admission re-check and
///         no deadline, and `proposeVaultClass` dedupes against `admittedClasses`
///         only — never against pending proposals. Together these make a
///         pre-positioned duplicate a redeemable re-admission ticket the moment a
///         future `revokeVaultClass` lands. Each fix intent blocks a distinct
///         sub-bug asserted below: re-check admission at finalize; a finalization
///         deadline; one live proposal per `admissionValue`; clear
///         `admissionTypes` on revoke.
/// @dev `revokeVaultClass` is `onlyGovernance` and per C.2 is not reachable today;
///      its reachability is C.2's latent finding and PP-D19 orders this fix before
///      C.2 makes it reachable. The revoke here is pranked AS the governance role —
///      its own designed backstop operation — to exercise the post-revoke state
///      the finding is about, not to claim reachability.
contract P1_G5a_ReadmissionTicketTest is Test {
    MockERC20 internal svZCHF;
    MockBodenseeDonationSink internal helper;
    VaultClassRegistry internal registry;
    address internal governance;
    address internal proposer;

    function setUp() public {
        svZCHF = new MockERC20("svZCHF", "svZCHF", 18);
        helper = new MockBodenseeDonationSink();
        governance = makeAddr("governance");
        proposer = makeAddr("proposer");
        address governanceSetter = makeAddr("governanceSetter");

        address[] memory genesisTokens = new address[](0);
        IVaultClassRegistry.AdmissionType[] memory genesisTypes = new IVaultClassRegistry.AdmissionType[](0);
        registry = new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(helper)),
            makeAddr("votingWeightSetter"),
            governanceSetter,
            genesisTokens,
            genesisTypes
        );
        vm.prank(governanceSetter);
        registry.setGovernanceContract(governance);

        svZCHF.mint(proposer, 100_000e18);
        vm.prank(proposer);
        svZCHF.approve(address(registry), type(uint256).max);
    }

    function _propose(IVaultClassRegistry.AdmissionType t, address v) internal returns (uint256 id) {
        vm.prank(proposer);
        id = registry.proposeVaultClass(t, v, bytes32(0));
    }

    function test_P1_G5a_staleDuplicateProposalReadmitsAfterRevoke() public {
        address v = makeAddr("classValue");

        // Sub-bug 1 — no dedup: three live proposals for one not-yet-admitted
        // value all succeed. proposeVaultClass checks admittedClasses, not
        // pending proposals.
        uint256 p1 = _propose(IVaultClassRegistry.AdmissionType.ImplementationAddress, v);
        uint256 p2 = _propose(IVaultClassRegistry.AdmissionType.FactoryAddress, v);
        uint256 p3 = _propose(IVaultClassRegistry.AdmissionType.ImplementationAddress, v);
        assertTrue(p1 != p2 && p2 != p3, "G.5a - duplicate live proposals for one admissionValue");

        // Sub-bug 2 — no deadline: roll ten veto windows out and finalize is
        // still open.
        vm.roll(block.number + registry.VETO_WINDOW_BLOCKS() * 10);
        registry.finalizeProposal(p1);
        assertTrue(registry.admittedClasses(v), "p1 admits v");
        assertEq(uint256(registry.admissionTypes(v)), uint256(IVaultClassRegistry.AdmissionType.ImplementationAddress));

        // Sub-bug 3 — no re-check at finalize: p2 finalizes despite v already
        // admitted, and overwrites the admission type. A ClassAlreadyAdmitted
        // re-check would revert here.
        registry.finalizeProposal(p2);
        assertTrue(registry.admittedClasses(v), "p2 finalized against an already-admitted value");
        assertEq(
            uint256(registry.admissionTypes(v)),
            uint256(IVaultClassRegistry.AdmissionType.FactoryAddress),
            "G.5a - a duplicate finalize overwrote the admission type"
        );

        // Governance revokes v (its designed backstop; reachability is C.2's).
        vm.prank(governance);
        registry.revokeVaultClass(v);
        assertFalse(registry.admittedClasses(v), "v revoked");
        // Sub-bug 4 — revoke does not clear admissionTypes.
        assertEq(
            uint256(registry.admissionTypes(v)),
            uint256(IVaultClassRegistry.AdmissionType.FactoryAddress),
            "G.5a - admissionTypes survives revoke"
        );

        // The ticket: p3, still un-finalized and long past its window, re-admits
        // v with no veto opportunity.
        registry.finalizeProposal(p3);
        assertTrue(
            registry.admittedClasses(v),
            "G.5a - a stale pre-positioned proposal re-admitted v after revoke, no veto window"
        );
    }
}
