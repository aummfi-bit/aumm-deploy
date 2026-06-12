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

/// @notice White-hat finding F-01 (S9): proves the propose-time `totalSupply()` snapshot
///         (AureumGovernance L201/L289) diverges from vote-time `governanceWeight` (L257-258), so turnout
///         can exceed 100% of snapshot and the 20% quorum is defeated. Production root cause =
///         VotingWeight `_totalQualifiedWeight` is a lazy poke-accumulator that excludes never-poked holders.
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

    function test_turnoutCanExceedSnapshot() public {
        votingWeight.setTotalSupply(100e18);
        vm.prank(attacker);
        uint256 id = gov.proposeGaugeChallenge(gaugePool, IERC20(address(svZchf)));
        votingWeight.setGovernanceWeight(attacker, 10_000e18);
        vm.prank(attacker);
        gov.castVote(id, true);
        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(gov.getProposal(id).snapshotTotalSupply, 100e18);
        assertEq(gov.getProposal(id).forVotes, 10_000e18);
        assertGt(gov.getProposal(id).forVotes, gov.getProposal(id).snapshotTotalSupply);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Succeeded));
    }

    function test_minorityAttackerRevokesGauge() public {
        votingWeight.setTotalSupply(500e18);
        vm.prank(attacker);
        uint256 id = gov.proposeGaugeChallenge(gaugePool, IERC20(address(svZchf)));
        votingWeight.setGovernanceWeight(attacker, 200e18);
        vm.prank(attacker);
        gov.castVote(id, true);
        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Succeeded));
        _queueAndReachEta(id);
        gov.execute(id);
        assertTrue(gaugeReg.revoked(gaugePool));
        // 200e18 is ~0.4% of the ~50_700e18 true eligible weight (500e18 poked subset + honestWhale 50_000e18 never poked).
    }

    function test_vacuousQuorumWhenAccumulatorEmpty() public {
        votingWeight.setTotalSupply(0);
        vm.prank(attacker);
        uint256 id = gov.proposeGaugeChallenge(gaugePool, IERC20(address(svZchf)));
        votingWeight.setGovernanceWeight(attacker, 1e18);
        vm.prank(attacker);
        gov.castVote(id, true);
        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(gov.getProposal(id).snapshotTotalSupply, 0);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Succeeded));
    }

    function test_singleVoterClearsCompositionSupermajority() public {
        votingWeight.setTotalSupply(300e18);
        vm.prank(attacker);
        uint256 id = gov.proposeCompositionChallenge(5, candidatePool, IERC20(address(svZchf)));
        votingWeight.setGovernanceWeight(attacker, 100e18);
        vm.prank(attacker);
        gov.castVote(id, true);
        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Succeeded));
        _queueAndReachEta(id);
        gov.execute(id);
        assertEq(slotReg.poolAtSlot(5), candidatePool);
        assertTrue(gaugeReg.revoked(occupantPool));
        assertTrue(gaugeReg.registered(candidatePool));
    }

    /// @notice F-01 fix regression — with the tally-time live-supply denominator (AureumGovernance L294), a
    ///         minority attacker can no longer clear quorum against a stale propose-time snapshot. Models the
    ///         lazy `_totalQualifiedWeight` accumulator growing 20x between propose and tally; pre-fix this
    ///         proposal Succeeded, post-fix it is Defeated.
    function test_F01_liveTallySupplyDefeatsStaleQuorumGaming() public {
        // Propose-time: the lazy accumulator is small — few holders have poked in yet.
        votingWeight.setTotalSupply(10_000e18);
        vm.prank(attacker);
        uint256 id = gov.proposeGaugeChallenge(gaugePool, IERC20(address(svZchf)));
        // Attacker votes with weight equal to the entire propose-time snapshot.
        votingWeight.setGovernanceWeight(attacker, 10_000e18);
        vm.prank(attacker);
        gov.castVote(id, true);
        // Between propose and tally, honest holders poke in — the live accumulator grows 20x.
        votingWeight.setTotalSupply(200_000e18);
        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(gov.getProposal(id).snapshotTotalSupply, 10_000e18, "snapshot frozen at propose-time");
        assertEq(votingWeight.totalSupply(), 200_000e18, "live accumulator grew post-propose");
        assertEq(gov.getProposal(id).forVotes, 10_000e18, "attacker weight recorded");
        // Pre-fix (stale snapshot denominator): 10_000e18 turnout is 100% of the 10_000e18 snapshot, clears the 20% bar — Succeeded.
        // Post-fix (live denominator): 10_000e18 is 5% of the 200_000e18 live supply, below the 20% bar — Defeated.
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Defeated), "live-tally quorum defeats stale-snapshot gaming");
    }
}
