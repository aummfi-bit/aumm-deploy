// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {AureumGovernance} from "src/governance/AureumGovernance.sol";
import {IVotingWeight} from "src/governance/IVotingWeight.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IMiliariumSlotRegistry} from "src/registry/IMiliariumSlotRegistry.sol";
import {SwapAndDepositToBodensee} from "src/gauge/SwapAndDepositToBodensee.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockVotingWeight, MockGaugeRegistry, MockSlotRegistry, MockVault, MockBodenseeChannel} from "test/unit/AureumGovernance.t.sol";

/// @notice White-hat finding F-01 (S9) regression suite, re-pointed to the F-06 fix. F-06 (Stage-L)
///         replaced F-01's live tally-time `totalSupply()` read with Governor-style snapshot voting:
///         both the numerator (each `getPastVotes(voter, snapshotBlock)` in `castVote`) and the
///         denominator (`getPastTotalSupply(snapshotBlock)` in `_voteSucceeded`) freeze at one pre-vote
///         `snapshotBlock`, so turnout is bounded by the snapshot supply by construction. These tests
///         assert the documented F-01 attacks now Defeat under that denominator, using the block-agnostic
///         mock with consistent snapshot inputs; the block-precise freeze proof (a post-snapshot `poke`
///         cannot move `getPastTotalSupply(snapshotBlock)`) lives in `F06_*.t.sol` with a block-aware mock.
///         `test_F06_vacuousQuorumAtZeroSnapshotStillOpen` records the one case F-06 does NOT close
///         (ledger L140 mul-form, `snapshot == 0`), carried to Stage-P.
contract F01_QuorumSnapshotTimingTest is Test {
    AureumGovernance internal gov;
    MockVotingWeight internal votingWeight;
    MockGaugeRegistry internal gaugeReg;
    MockSlotRegistry internal slotReg;
    MockVault internal vault;
    MockBodenseeChannel internal channel;
    MockERC20 internal svZchf;
    MockERC20 internal sUsds;

    address internal attacker = makeAddr("attacker");
    address internal honestWhale = makeAddr("honestWhale");
    address internal bodenseePool = makeAddr("bodenseePool");
    address internal gaugePool = makeAddr("gaugePool");
    address internal feePool = makeAddr("feePool");
    address internal occupantPool = makeAddr("occupantPool");
    address internal candidatePool = makeAddr("candidatePool");

    uint256 internal constant VOTING_PERIOD = 100_800;
    uint256 internal constant TIMELOCK = 14_400;
    uint256 internal constant FEE_OK = 1e15;

    function setUp() public {
        votingWeight = new MockVotingWeight();
        gaugeReg = new MockGaugeRegistry();
        slotReg = new MockSlotRegistry();
        vault = new MockVault();
        channel = new MockBodenseeChannel();
        svZchf = new MockERC20("Staked Frankencoin", "svZCHF", 18);
        sUsds = new MockERC20("Savings USDS", "sUSDS", 18);
        gov = new AureumGovernance(
            IVotingWeight(address(votingWeight)),
            IGaugeRegistry(address(gaugeReg)),
            IMiliariumSlotRegistry(address(slotReg)),
            IVault(address(vault)),
            SwapAndDepositToBodensee(address(channel)),
            IERC20(address(svZchf)),
            IERC20(address(sUsds)),
            bodenseePool
        );
        gaugeReg.setGaugeStatus(gaugePool, IGaugeRegistry.GaugeStatus.Active);
        gaugeReg.setGaugeApproved(feePool, true);
        slotReg.setPoolAtSlot(5, occupantPool);
        gaugeReg.setGaugeStatus(occupantPool, IGaugeRegistry.GaugeStatus.Active);
        svZchf.mint(attacker, 1_000_000e18);
        sUsds.mint(attacker, 1_000_000e18);
        vm.startPrank(attacker);
        svZchf.approve(address(gov), type(uint256).max);
        sUsds.approve(address(gov), type(uint256).max);
        vm.stopPrank();
    }

    function _queueAndReachEta(uint256 id) internal {
        gov.queue(id);
        vm.roll(gov.getProposal(id).eta);
    }

    /// @notice F-01 regression: the quorum denominator is now `getPastTotalSupply(snapshotBlock)`, read at
    ///         the same block as every `getPastVotes` numerator, so a holder's turnout is bounded by the
    ///         snapshot supply. A minority gauge attacker (10% of supply) can no longer clear the 20% bar.
    function test_F01_turnoutBoundedBySnapshotSupply() public {
        votingWeight.setTotalSupply(100_000e18);
        vm.prank(attacker);
        uint256 id = gov.proposeGaugeChallenge(gaugePool, IERC20(address(svZchf)));
        vm.roll(gov.getProposal(id).snapshotBlock + 1);
        votingWeight.setGovernanceWeight(attacker, 10_000e18); // 10% of snapshot supply, below the 20% quorum
        vm.prank(attacker);
        gov.castVote(id, true);
        vm.roll(gov.getProposal(id).endBlock + 1);
        assertEq(gov.getProposal(id).forVotes, 10_000e18);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Defeated));
    }

    /// @notice F-01 regression: the finding's 200e18 attacker was ~0.4% of true eligible weight but passed
    ///         because the propose-time accumulator excluded the never-poked honestWhale (50_000e18). Under
    ///         snapshot voting the denominator is the checkpointed total at `snapshotBlock`, which subsumes
    ///         every qualified holder, so the dust attacker is defeated and the gauge survives.
    function test_F01_dustAttackerCannotRevokeGauge() public {
        votingWeight.setTotalSupply(50_500e18); // 500e18 poked subset + honestWhale 50_000e18, both in the snapshot
        vm.prank(attacker);
        uint256 id = gov.proposeGaugeChallenge(gaugePool, IERC20(address(svZchf)));
        vm.roll(gov.getProposal(id).snapshotBlock + 1);
        votingWeight.setGovernanceWeight(attacker, 200e18); // ~0.4% of true eligible weight
        vm.prank(attacker);
        gov.castVote(id, true);
        vm.roll(gov.getProposal(id).endBlock + 1);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Defeated));
        assertFalse(gaugeReg.revoked(gaugePool));
    }

    /// @notice F-06 does NOT close the `snapshot == 0` vacuous-quorum case: the stored mul-form
    ///         `totalVotes * 10_000 < getPastTotalSupply(snapshotBlock) * QUORUM_BPS` passes vacuously when the
    ///         denominator is 0 (0 < 0 is false), so a 1e18 vote Succeeds. Orthogonal to the F-01/F-06
    ///         denominator-timing axis (ledger L140, the mul-form's permissive direction); a separate open
    ///         observation carried to Stage-P, asserted here so a future div-form fix flips this test.
    function test_F06_vacuousQuorumAtZeroSnapshotStillOpen() public {
        votingWeight.setTotalSupply(0);
        vm.prank(attacker);
        uint256 id = gov.proposeGaugeChallenge(gaugePool, IERC20(address(svZchf)));
        vm.roll(gov.getProposal(id).snapshotBlock + 1);
        votingWeight.setGovernanceWeight(attacker, 1e18);
        vm.prank(attacker);
        gov.castVote(id, true);
        vm.roll(gov.getProposal(id).endBlock + 1);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Succeeded));
    }

    /// @notice F-21: the `snapshot == 0` vacuous quorum is SHARPER on CompositionChallenge than the
    ///         F-06 carry records. `_voteSucceeded` branches on proposal type and the two branches use
    ///         different comparisons: Gauge and Fee return `forVotes > againstVotes`, which is `0 > 0`
    ///         and false at zero turnout, while Composition returns `forVotes * 3 >= totalVotes * 2`,
    ///         which is `0 >= 0` and TRUE. With the denominator also zero the quorum guard passes
    ///         vacuously, so a CompositionChallenge Succeeds with NO vote cast at all, where
    ///         `test_F06_vacuousQuorumAtZeroSnapshotStillOpen` needed a 1e18 vote. Driven through queue
    ///         and execute here to show the consequence is slot capture rather than a state label.
    ///         Scope: the mock quality gate passes by default, so this proves the vote path only;
    ///         whether an attacker-supplied pool clears the REAL `meetsCompositionQualityGate` is a
    ///         separate question and is the actual cost barrier.
    function test_F21_compositionZeroVoteCapturesSlotAtZeroSnapshot() public {
        votingWeight.setTotalSupply(0);
        vm.prank(attacker);
        uint256 id = gov.proposeCompositionChallenge(5, candidatePool, IERC20(address(svZchf)));

        // Premise asserted before the attack, so a passing capture is the mechanism firing rather
        // than the fixture having started in the captured state.
        assertEq(slotReg.poolAtSlot(5), occupantPool);
        assertFalse(gaugeReg.registered(candidatePool));

        // No castVote anywhere in this test. Turnout is exactly zero.
        vm.roll(gov.getProposal(id).endBlock + 1);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Succeeded));

        gov.queue(id);
        vm.roll(gov.getProposal(id).eta);
        gov.execute(id);

        assertEq(slotReg.poolAtSlot(5), candidatePool);
        assertTrue(gaugeReg.revoked(occupantPool));
        assertTrue(gaugeReg.registered(candidatePool));
    }

    /// @notice F-21 control, and the discriminator that identifies the mechanism. Identical zero supply
    ///         and identical zero turnout, differing only in proposal type: the Gauge branch evaluates
    ///         `0 > 0` and Defeats. A single test showing Composition succeed would be consistent with
    ///         several causes; the pair isolates the comparison operator as the one thing that differs.
    function test_F21_gaugeChallengeZeroVoteDefeatsAtSameSnapshot() public {
        votingWeight.setTotalSupply(0);
        vm.prank(attacker);
        uint256 id = gov.proposeGaugeChallenge(gaugePool, IERC20(address(svZchf)));
        vm.roll(gov.getProposal(id).endBlock + 1);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Defeated));
        assertFalse(gaugeReg.revoked(gaugePool));
    }

    /// @notice F-01 regression: a single 100e18 voter cleared a composition 2/3 supermajority in the finding
    ///         because the propose-time snapshot excluded never-poked holders. Under snapshot voting the
    ///         denominator is the full checkpointed total, so 100e18 fails the 20% quorum outright and the
    ///         slot swap does not execute.
    function test_F01_singleVoterCannotClearComposition() public {
        votingWeight.setTotalSupply(300_000e18);
        vm.prank(attacker);
        uint256 id = gov.proposeCompositionChallenge(5, candidatePool, IERC20(address(svZchf)));
        vm.roll(gov.getProposal(id).snapshotBlock + 1);
        votingWeight.setGovernanceWeight(attacker, 100e18); // far below the 20% quorum of true supply
        vm.prank(attacker);
        gov.castVote(id, true);
        vm.roll(gov.getProposal(id).endBlock + 1);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Defeated));
        assertEq(slotReg.poolAtSlot(5), occupantPool);
        assertFalse(gaugeReg.revoked(occupantPool));
        assertFalse(gaugeReg.registered(candidatePool));
    }

    /// @notice F-01 named regression, re-pointed from the live-read fix to the snapshot fix. Pre-F-06 the
    ///         F-01 fix read the quorum denominator live at tally; F-06 freezes it at `snapshotBlock`. The
    ///         attacker's 10_000e18, which would have been 100% of a thin propose-time snapshot, is 5% of the
    ///         200_000e18 snapshot supply, so the proposal is Defeated. The block-precise proof that a
    ///         post-snapshot `poke` cannot move `getPastTotalSupply(snapshotBlock)` is in `F06_*.t.sol` (v).
    function test_F01_snapshotDenominatorDefeatsStaleQuorumGaming() public {
        votingWeight.setTotalSupply(200_000e18);
        vm.prank(attacker);
        uint256 id = gov.proposeGaugeChallenge(gaugePool, IERC20(address(svZchf)));
        vm.roll(gov.getProposal(id).snapshotBlock + 1);
        votingWeight.setGovernanceWeight(attacker, 10_000e18); // 5% of the snapshot supply
        vm.prank(attacker);
        gov.castVote(id, true);
        vm.roll(gov.getProposal(id).endBlock + 1);
        assertEq(gov.getProposal(id).forVotes, 10_000e18);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Defeated));
    }
}
