// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {VaultClassRegistry} from "src/gauge/VaultClassRegistry.sol";
import {IVaultClassRegistry} from "src/gauge/IVaultClassRegistry.sol";
import {SwapAndDepositToBodensee} from "src/gauge/SwapAndDepositToBodensee.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Passive SwapAndDepositToBodensee stand-in; the registry only forwards the bond via `donate`.
contract MockBodenseeHelper {
    function donate(IERC20, uint256) external {}
}

/// @title P1 G.5b — an unissued proposal id is rejected on both entries
/// @notice Regression for seam-1 root cause G.5b (Info), inverted at PP4.7 from the
///         PP3.2 reproduction per PP-D49 (i). Before the fix neither
///         `finalizeProposal` nor `vetoProposal` bounded `proposalId` against
///         `nextProposalId`: an unwritten `proposals[id]` reads a zero struct whose
///         `AdmissionType` is enum value ZERO — a VALID type — and whose zero
///         `createdBlock` makes the veto-window test pass at every block past
///         `VETO_WINDOW_BLOCKS`, so finalize admitted the struct's `address(0)` as a
///         real vault class.
/// @dev Three cases, and the second and third are not decoration. `vetoProposal`
///      reverted before the fix too, but INCIDENTALLY on `VetoWindowExpired`, so only
///      an assertion on the error itself distinguishes the guard from the accident it
///      hid behind. And the guard is `>=`, never `>`: the boundary case pins that the
///      last ISSUED id still finalizes while `nextProposalId` does not, which an
///      off-by-one would break in exactly the direction that re-opens the finding.
contract P1_G5b_UnknownIdRejectedTest is Test {
    MockERC20 internal svZCHF;
    VaultClassRegistry internal registry;
    address internal proposer;

    function setUp() public {
        svZCHF = new MockERC20("svZCHF", "svZCHF", 18);
        MockBodenseeHelper helper = new MockBodenseeHelper();
        proposer = makeAddr("proposer");
        address[] memory genesisTokens = new address[](0);
        IVaultClassRegistry.AdmissionType[] memory genesisTypes = new IVaultClassRegistry.AdmissionType[](0);
        registry = new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(helper)),
            makeAddr("votingWeightSetter"),
            makeAddr("governanceSetter"),
            genesisTokens,
            genesisTypes
        );
        svZCHF.mint(proposer, 100_000e18);
        vm.prank(proposer);
        svZCHF.approve(address(registry), type(uint256).max);
    }

    /// @notice The queue's done-criteria case for G.5b. The roll is retained from the
    ///         reproduction deliberately: it puts the call at the exact block where the
    ///         zero struct's window check used to wave a phantom id through.
    function test_finalizeRejectsUnknownId() public {
        uint256 unknownId = registry.nextProposalId();
        assertEq(unknownId, 0, "premise: no proposals created, nextProposalId is 0");
        assertFalse(registry.admittedClasses(address(0)), "premise: address(0) not admitted");

        vm.roll(block.number + registry.VETO_WINDOW_BLOCKS() + 1);
        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.UnknownProposal.selector, unknownId));
        registry.finalizeProposal(unknownId);

        assertFalse(
            registry.admittedClasses(address(0)),
            "G.5b - address(0) must never be admitted through a non-existent proposal id"
        );
    }

    /// @notice The second guarded entry. Pre-fix this reverted `VetoWindowExpired`, an
    ///         accident of the zero `createdBlock` rather than an existence check, so the
    ///         assertion is on the error and not merely on the revert.
    function test_vetoRejectsUnknownId() public {
        uint256 unknownId = registry.nextProposalId();
        vm.roll(block.number + registry.VETO_WINDOW_BLOCKS() + 1);
        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.UnknownProposal.selector, unknownId));
        registry.vetoProposal(unknownId);
    }

    /// @notice The `>=` boundary, and the positive control: the guard rejects only ids
    ///         that were never issued, so the last issued id still finalizes.
    function test_finalizeAcceptsLastIssuedIdAndRejectsTheNext() public {
        address value = makeAddr("classValue");
        vm.prank(proposer);
        uint256 issuedId =
            registry.proposeVaultClass(IVaultClassRegistry.AdmissionType.ImplementationAddress, value, bytes32(0));
        assertEq(registry.nextProposalId(), issuedId + 1, "premise: exactly one id issued");

        vm.roll(block.number + registry.VETO_WINDOW_BLOCKS() + 1);
        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.UnknownProposal.selector, issuedId + 1));
        registry.finalizeProposal(issuedId + 1);

        registry.finalizeProposal(issuedId);
        assertTrue(registry.admittedClasses(value), "the last issued id still finalizes");
    }
}
