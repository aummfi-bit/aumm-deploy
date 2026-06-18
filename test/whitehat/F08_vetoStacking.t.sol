// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {VaultClassRegistry} from "src/gauge/VaultClassRegistry.sol";
import {IVaultClassRegistry} from "src/gauge/IVaultClassRegistry.sol";
import {SwapAndDepositToBodensee} from "src/gauge/SwapAndDepositToBodensee.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockVotingWeight, MockSwapAndDepositToBodensee} from "test/unit/VaultClassRegistry.t.sol";

/// @notice F-08 fix regression (WM.1) — VaultClassRegistry.vetoProposal now records one veto per address per
///         proposal: a repeat call from the same holder reverts AlreadyVetoed. Before the fix a single
///         sub-threshold holder could call vetoProposal repeatedly, stacking its own governanceWeight into
///         vetoSupport until it crossed the 10% VETO_THRESHOLD_BPS bar and killed the proposal alone. The fix
///         preserves legitimate multi-voter accumulation and single-veto kills by holders at or above threshold.
contract F08_VetoStackingTest is Test {
    MockERC20 internal svZCHF;
    MockSwapAndDepositToBodensee internal helper;
    MockVotingWeight internal votingWeight;
    VaultClassRegistry internal registry;

    address internal vwSetter;
    address internal govSetter;
    address internal governance;
    address internal proposer;

    uint256 internal constant TOTAL_SUPPLY = 100_000e18;

    function setUp() public {
        svZCHF = new MockERC20("svZCHF", "svZCHF", 18);
        helper = new MockSwapAndDepositToBodensee();
        votingWeight = new MockVotingWeight();
        votingWeight.setTotalSupply(TOTAL_SUPPLY);

        vwSetter = makeAddr("vwSetter");
        govSetter = makeAddr("govSetter");
        governance = makeAddr("governance");
        proposer = makeAddr("proposer");

        registry = new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(helper)),
            vwSetter,
            govSetter,
            new address[](0),
            new IVaultClassRegistry.AdmissionType[](0)
        );

        vm.prank(vwSetter);
        registry.setVotingWeight(address(votingWeight));
        vm.prank(govSetter);
        registry.setGovernanceContract(governance);

        svZCHF.mint(proposer, TOTAL_SUPPLY);
        vm.prank(proposer);
        svZCHF.approve(address(registry), type(uint256).max);
    }

    function _propose(address admissionValue) private returns (uint256) {
        vm.prank(proposer);
        return registry.proposeVaultClass(IVaultClassRegistry.AdmissionType.ImplementationAddress, admissionValue, bytes32(0));
    }

    /// @notice Core F-08 fix: a sub-threshold holder's repeat veto reverts AlreadyVetoed; vetoSupport cannot stack past one contribution, so the proposal survives.
    function test_F08_repeatVeto_revertsAlreadyVetoed() public {
        uint256 id = _propose(makeAddr("admission1"));
        address attacker = makeAddr("attacker");
        votingWeight.setGovernanceWeight(attacker, 5_000e18);

        vm.prank(attacker);
        registry.vetoProposal(id);

        (,,,, uint256 vetoSupp, bool finalized, bool revoked) = registry.proposals(id);
        assertEq(vetoSupp, 5_000e18);
        assertFalse(finalized);
        assertFalse(revoked);

        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.AlreadyVetoed.selector, id));
        vm.prank(attacker);
        registry.vetoProposal(id);

        (,,,, uint256 vetoSuppAfter, bool finalizedAfter, bool revokedAfter) = registry.proposals(id);
        assertEq(vetoSuppAfter, 5_000e18);
        assertFalse(finalizedAfter);
        assertFalse(revokedAfter);
    }

    /// @notice A single sub-threshold veto leaves the proposal alive (sanity baseline for the stacking attack).
    function test_F08_singleSubThresholdVeto_leavesProposalAlive() public {
        uint256 id = _propose(makeAddr("admission2"));
        address voter = makeAddr("voter");
        votingWeight.setGovernanceWeight(voter, 9_999e18);

        vm.prank(voter);
        registry.vetoProposal(id);

        (,,,,, bool finalized, bool revoked) = registry.proposals(id);
        assertFalse(finalized);
        assertFalse(revoked);
    }

    /// @notice Fix preserves legitimate accumulation: two distinct sub-threshold voters still sum past the bar and kill the proposal.
    function test_F08_distinctVotersStillAccumulateToKill() public {
        uint256 id = _propose(makeAddr("admission3"));
        address v1 = makeAddr("v1");
        address v2 = makeAddr("v2");
        votingWeight.setGovernanceWeight(v1, 5_000e18);
        votingWeight.setGovernanceWeight(v2, 5_000e18);

        vm.prank(v1);
        registry.vetoProposal(id);
        (,,,,, bool f1, bool r1) = registry.proposals(id);
        assertFalse(f1);
        assertFalse(r1);

        vm.prank(v2);
        registry.vetoProposal(id);
        (,,,,, bool f2, bool r2) = registry.proposals(id);
        assertTrue(f2);
        assertTrue(r2);
    }

    /// @notice Fix preserves a legitimate single-veto kill: a holder at the 10% threshold revokes in one call.
    function test_F08_sufficientWeightSingleVetoKills() public {
        uint256 id = _propose(makeAddr("admission4"));
        address whale = makeAddr("whale");
        votingWeight.setGovernanceWeight(whale, 10_000e18);

        vm.prank(whale);
        registry.vetoProposal(id);

        (,,,,, bool finalized, bool revoked) = registry.proposals(id);
        assertTrue(finalized);
        assertTrue(revoked);
    }
}
