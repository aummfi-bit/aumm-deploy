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

/// @title P1 G.5b — finalizeProposal admits address(0) on a non-existent id
/// @notice Reproduction PoC for seam-1 root cause G.5b (Info). `finalizeProposal`
///         and `vetoProposal` never check `proposalId < nextProposalId`. A read
///         of an unwritten `proposals[id]` returns a zero struct whose
///         `createdBlock == 0`, so the veto-window test
///         (`block.number <= createdBlock + VETO_WINDOW_BLOCKS`) passes for any
///         block past the window, and finalize then admits the struct's
///         `admissionValue` — `address(0)` — as a vault class. G14's heuristic:
///         the zero record AUTHORISES an action here, where at the nine other
///         zero-struct sites it merely permits an opportunity, which is why this
///         is the single instance. Fix intent: `if (proposalId >= nextProposalId)
///         revert UnknownProposal` on both entries.
contract P1_G5b_UnknownIdAdmitsZeroTest is Test {
    VaultClassRegistry internal registry;

    function setUp() public {
        MockERC20 svZCHF = new MockERC20("svZCHF", "svZCHF", 18);
        MockBodenseeHelper helper = new MockBodenseeHelper();
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
    }

    function test_P1_G5b_finalizeUnknownIdAdmitsZeroAddress() public {
        uint256 unknownId = registry.nextProposalId();
        assertEq(unknownId, 0, "premise: no proposals created, nextProposalId is 0");
        assertFalse(registry.admittedClasses(address(0)), "premise: address(0) not admitted");

        // The zero struct's createdBlock is 0, so past the window the finalize
        // guard treats a never-created proposal as vetoable-then-finalizable.
        vm.roll(block.number + registry.VETO_WINDOW_BLOCKS() + 1);
        registry.finalizeProposal(unknownId);

        assertTrue(
            registry.admittedClasses(address(0)),
            "G.5b - address(0) admitted as a vault class via a non-existent proposal id"
        );
    }
}
