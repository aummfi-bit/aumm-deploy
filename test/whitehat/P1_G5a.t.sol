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

/// @title P1 G.5a — a stale duplicate proposal is no longer a re-admission ticket
/// @notice Regression for seam-1 root cause G.5a (Medium), inverted at PP4.7 from the
///         PP3.2 reproduction per PP-D49 (ii), (iii) and (iv)/(v). The reproduction
///         drove four sub-bugs against one flow; three are now closed by three
///         separate gates and the fourth was adjudicated CORRECT, so this is a
///         re-derivation from the lock rather than a negation of the old assertions.
/// @dev PP-D49 (iv) SUPERSEDED the queue's "one live proposal per `admissionValue`"
///      fix intent, so concurrent duplicates stay legal and the first case still
///      asserts they are accepted. What closes the finding is that a duplicate cannot
///      be REDEEMED: `ClassAlreadyAdmitted` stops it while the class is admitted and
///      `lastRevokedBlock` stops it after a revocation — which is precisely the
///      propose-admit-revoke sequence a uniqueness map would have left open. Every
///      roll target is absolute off `START_BLOCK` rather than `block.number + k`,
///      because F15 sinks a live block read forward across a `vm.roll`. The revoke is
///      pranked AS the governance role, its own designed backstop, to exercise
///      post-revoke state — reachability is C.2's, and PP-D19 orders this fix first.
contract P1_G5a_ReadmissionTicketClosedTest is Test {
    uint256 internal constant START_BLOCK = 2_000_000;

    MockERC20 internal svZCHF;
    MockBodenseeDonationSink internal helper;
    VaultClassRegistry internal registry;
    address internal governance;
    address internal proposer;

    function setUp() public {
        vm.roll(START_BLOCK);
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

    /// @notice The queue's done-criteria case for G.5a: PP-D49 (ii). Duplicates stay
    ///         legal at creation, so the gate that matters sits at redemption. Two is
    ///         enough to prove the property; the reproduction's third added no gate.
    function test_finalizeRechecksAdmission() public {
        address v = makeAddr("classValue");

        uint256 p1 = _propose(IVaultClassRegistry.AdmissionType.FactoryAddress, v);
        uint256 p2 = _propose(IVaultClassRegistry.AdmissionType.ImplementationAddress, v);
        assertTrue(p1 != p2, "concurrent duplicate proposals for one admissionValue stay legal");

        vm.roll(START_BLOCK + registry.VETO_WINDOW_BLOCKS() + 1);
        registry.finalizeProposal(p1);
        assertTrue(registry.admittedClasses(v), "p1 admits v");
        assertEq(
            uint256(registry.admissionTypes(v)),
            uint256(IVaultClassRegistry.AdmissionType.FactoryAddress),
            "premise: p1 admitted the FactoryAddress type"
        );

        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.ClassAlreadyAdmitted.selector, v));
        registry.finalizeProposal(p2);
        assertEq(
            uint256(registry.admissionTypes(v)),
            uint256(IVaultClassRegistry.AdmissionType.FactoryAddress),
            "G.5a - a duplicate finalize must not overwrite the admission type"
        );
    }

    /// @notice PP-D49 (iv) and (v). The stamp invalidates proposals PREDATING the
    ///         revocation without blacklisting the value, so the tail of this case is
    ///         the positive control: a proposal opened after the revoke still
    ///         finalizes, which is G-D17's non-terminal re-admission path.
    function test_staleProposalCannotReadmitAfterRevokeButAFreshOneCan() public {
        address v = makeAddr("classValue");

        uint256 live = _propose(IVaultClassRegistry.AdmissionType.FactoryAddress, v);
        uint256 stale = _propose(IVaultClassRegistry.AdmissionType.ImplementationAddress, v);

        vm.roll(START_BLOCK + registry.VETO_WINDOW_BLOCKS() + 1);
        registry.finalizeProposal(live);
        assertTrue(registry.admittedClasses(v), "premise: v is admitted before the revoke");

        vm.prank(governance);
        registry.revokeVaultClass(v);
        assertFalse(registry.admittedClasses(v), "v revoked");
        assertEq(
            registry.lastRevokedBlock(v),
            START_BLOCK + registry.VETO_WINDOW_BLOCKS() + 1,
            "PP-D49 (iv) - the revocation is stamped at its own block"
        );
        assertEq(
            uint256(registry.admissionTypes(v)),
            uint256(IVaultClassRegistry.AdmissionType.ImplementationAddress),
            "PP-D49 (v) - revoke clears admissionTypes rather than leaving it stale"
        );

        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.ProposalPredatesRevocation.selector, stale));
        registry.finalizeProposal(stale);
        assertFalse(registry.admittedClasses(v), "G.5a - a stale proposal must not re-admit past governance");

        vm.roll(START_BLOCK + registry.VETO_WINDOW_BLOCKS() + 2);
        uint256 fresh = _propose(IVaultClassRegistry.AdmissionType.ImplementationAddress, v);
        vm.roll(START_BLOCK + 2 * registry.VETO_WINDOW_BLOCKS() + 3);
        registry.finalizeProposal(fresh);
        assertTrue(registry.admittedClasses(v), "re-admission stays open to a proposal opened after the revoke");
    }

    /// @notice PP-D49 (iii). The deadline is one further `VETO_WINDOW_BLOCKS` and the
    ///         comparison is strict, so both sides are pinned: exactly
    ///         `createdBlock + 2 * VETO_WINDOW_BLOCKS` still finalizes and one block
    ///         later does not. No new constant was adjudicated; the window is G-D19's.
    function test_finalizeDeadlineIsOneFurtherWindow() public {
        address onTime = makeAddr("onTimeValue");
        address late = makeAddr("lateValue");

        uint256 onTimeId = _propose(IVaultClassRegistry.AdmissionType.ImplementationAddress, onTime);
        uint256 lateId = _propose(IVaultClassRegistry.AdmissionType.ImplementationAddress, late);

        vm.roll(START_BLOCK + 2 * registry.VETO_WINDOW_BLOCKS());
        registry.finalizeProposal(onTimeId);
        assertTrue(registry.admittedClasses(onTime), "the last legal block still finalizes");

        vm.roll(START_BLOCK + 2 * registry.VETO_WINDOW_BLOCKS() + 1);
        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.FinalizeDeadlineExpired.selector, lateId));
        registry.finalizeProposal(lateId);
        assertFalse(registry.admittedClasses(late), "G.5a - a proposal past its deadline must not admit");
    }
}
