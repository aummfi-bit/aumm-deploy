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
/// @notice Focused doubles for the AureumGovernance unit cohort (K4.6) — each implements only the
///         surface AureumGovernance calls and is cast to its interface type at construction. Distinct
///         from the CCB / VotingWeight full-interface doubles; not a shared canonical mock.
contract MockVotingWeight is IVotingWeight {
    mapping(address => uint256) public governanceWeights;
    uint256 private _totalSupply;
    function setTotalSupply(uint256 supply_) external {
        _totalSupply = supply_;
    }
    function setGovernanceWeight(address holder, uint256 weight) external {
        governanceWeights[holder] = weight;
    }
    function governanceWeight(address holder) external view returns (uint256) {
        return governanceWeights[holder];
    }
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
    uint256 public pokeCount;
    address public lastPoked;
    function poke(address holder) external {
        pokeCount++;
        lastPoked = holder;
    }
}
contract MockGaugeRegistry {
    mapping(address => IGaugeRegistry.GaugeStatus) public statusOf;
    mapping(address => bool) public approvedOf;
    mapping(address => bool) public revoked;
    mapping(address => bool) public registered;
    function setGaugeStatus(address pool, IGaugeRegistry.GaugeStatus status_) external {
        statusOf[pool] = status_;
    }
    function setGaugeApproved(address pool, bool approved_) external {
        approvedOf[pool] = approved_;
    }
    function gaugeStatus(address pool) external view returns (IGaugeRegistry.GaugeStatus) {
        return statusOf[pool];
    }
    function isGaugeApproved(address pool) external view returns (bool) {
        return approvedOf[pool];
    }
    function revokeGauge(address pool) external {
        revoked[pool] = true;
    }
    function registerGaugeFromComposition(address pool) external {
        registered[pool] = true;
    }
}
contract MockSlotRegistry {
    mapping(address => uint256) public slotOfPool;
    mapping(uint256 => address) public poolAtSlotOf;
    mapping(uint256 => address) public replacedTo;
    function setSlotOf(address pool, uint256 slot) external {
        slotOfPool[pool] = slot;
    }
    function setPoolAtSlot(uint256 slot, address pool) external {
        poolAtSlotOf[slot] = pool;
    }
    function slotOf(address pool) external view returns (uint256) {
        return slotOfPool[pool];
    }
    function poolAtSlot(uint256 slot) external view returns (address) {
        return poolAtSlotOf[slot];
    }
    function replaceSlot(uint256 slot, address newPool) external {
        replacedTo[slot] = newPool;
        poolAtSlotOf[slot] = newPool;
    }
}
contract MockVault {
    mapping(address => uint256) public staticFeeOf;
    uint256 public setFeeCalls;
    function setStaticSwapFeePercentage(address pool, uint256 swapFeePercentage) external {
        staticFeeOf[pool] = swapFeePercentage;
        setFeeCalls++;
    }
}
contract MockBodenseeChannel {
    uint256 public donateCalls;
    address public lastDonateToken;
    uint256 public lastDonateAmount;
    function donate(IERC20 payToken, uint256 amount) external {
        donateCalls++;
        lastDonateToken = address(payToken);
        lastDonateAmount = amount;
    }
}
/// @notice K4.6 unit cohort harness — propose / castVote / state / queue / execute over focused doubles.
contract AureumGovernanceTest is Test {
    AureumGovernance internal gov;
    MockVotingWeight internal votingWeight;
    MockGaugeRegistry internal gaugeReg;
    MockSlotRegistry internal slotReg;
    MockVault internal vault;
    MockBodenseeChannel internal channel;
    MockERC20 internal svZchf;
    MockERC20 internal sUsds;
    address internal proposer = makeAddr("proposer");
    address internal voterA = makeAddr("voterA");
    address internal voterB = makeAddr("voterB");
    address internal bodenseePool = makeAddr("bodenseePool");
    address internal gaugePool = makeAddr("gaugePool");
    address internal feePool = makeAddr("feePool");
    address internal occupantPool = makeAddr("occupantPool");
    address internal candidatePool = makeAddr("candidatePool");
    uint256 internal constant DEPOSIT_SVZCHF = 1_000e18;
    uint256 internal constant DEPOSIT_SUSDS = 1_250e18;
    uint256 internal constant TOTAL_SUPPLY = 1_000_000e18;
    uint256 internal constant VOTING_PERIOD = 100_800;
    uint256 internal constant TIMELOCK = 14_400;
    uint256 internal constant GRACE = 100_800;
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
        votingWeight.setTotalSupply(TOTAL_SUPPLY);
        gaugeReg.setGaugeStatus(gaugePool, IGaugeRegistry.GaugeStatus.Active);
        gaugeReg.setGaugeApproved(feePool, true);
        slotReg.setPoolAtSlot(5, occupantPool);
        gaugeReg.setGaugeStatus(occupantPool, IGaugeRegistry.GaugeStatus.Active);
        svZchf.mint(proposer, 1_000_000e18);
        sUsds.mint(proposer, 1_000_000e18);
        vm.startPrank(proposer);
        svZchf.approve(address(gov), type(uint256).max);
        sUsds.approve(address(gov), type(uint256).max);
        vm.stopPrank();
    }
    function _proposeGauge() internal returns (uint256 id) {
        vm.prank(proposer);
        id = gov.proposeGaugeChallenge(gaugePool, IERC20(address(svZchf)));
    }
    function _proposeComposition() internal returns (uint256 id) {
        vm.prank(proposer);
        id = gov.proposeCompositionChallenge(5, candidatePool, IERC20(address(svZchf)));
    }
    function _proposeFee() internal returns (uint256 id) {
        vm.prank(proposer);
        id = gov.proposeFeeChange(feePool, FEE_OK, IERC20(address(svZchf)));
    }
    function _voteAndClose(uint256 id, bool support) internal {
        votingWeight.setGovernanceWeight(voterA, TOTAL_SUPPLY);
        vm.prank(voterA);
        gov.castVote(id, support);
        vm.roll(block.number + VOTING_PERIOD + 1);
    }
    function _queueAndReachEta(uint256 id) internal {
        gov.queue(id);
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        vm.roll(p.eta);
    }
    function test_setUp_immutablesWired() public {
        assertEq(address(gov.VOTING_WEIGHT()), address(votingWeight));
        assertEq(address(gov.GAUGE_REGISTRY()), address(gaugeReg));
        assertEq(address(gov.SLOT_REGISTRY()), address(slotReg));
        assertEq(address(gov.VAULT()), address(vault));
        assertEq(address(gov.BODENSEE_CHANNEL()), address(channel));
        assertEq(address(gov.SVZCHF()), address(svZchf));
        assertEq(address(gov.SUSDS()), address(sUsds));
        assertEq(gov.BODENSEE_POOL(), bodenseePool);
    }
    function test_constructor_revertZeroAddress_allEightSlots() public {
        IVotingWeight vw = IVotingWeight(address(votingWeight));
        IGaugeRegistry gr = IGaugeRegistry(address(gaugeReg));
        IMiliariumSlotRegistry sr = IMiliariumSlotRegistry(address(slotReg));
        IVault v = IVault(address(vault));
        SwapAndDepositToBodensee ch = SwapAndDepositToBodensee(address(channel));
        IERC20 zc = IERC20(address(svZchf));
        IERC20 su = IERC20(address(sUsds));
        address bp = bodenseePool;
        vm.expectRevert(AureumGovernance.ZeroAddress.selector);
        new AureumGovernance(IVotingWeight(address(0)), gr, sr, v, ch, zc, su, bp);
        vm.expectRevert(AureumGovernance.ZeroAddress.selector);
        new AureumGovernance(vw, IGaugeRegistry(address(0)), sr, v, ch, zc, su, bp);
        vm.expectRevert(AureumGovernance.ZeroAddress.selector);
        new AureumGovernance(vw, gr, IMiliariumSlotRegistry(address(0)), v, ch, zc, su, bp);
        vm.expectRevert(AureumGovernance.ZeroAddress.selector);
        new AureumGovernance(vw, gr, sr, IVault(address(0)), ch, zc, su, bp);
        vm.expectRevert(AureumGovernance.ZeroAddress.selector);
        new AureumGovernance(vw, gr, sr, v, SwapAndDepositToBodensee(address(0)), zc, su, bp);
        vm.expectRevert(AureumGovernance.ZeroAddress.selector);
        new AureumGovernance(vw, gr, sr, v, ch, IERC20(address(0)), su, bp);
        vm.expectRevert(AureumGovernance.ZeroAddress.selector);
        new AureumGovernance(vw, gr, sr, v, ch, zc, IERC20(address(0)), bp);
        vm.expectRevert(AureumGovernance.ZeroAddress.selector);
        new AureumGovernance(vw, gr, sr, v, ch, zc, su, address(0));
    }
    function test_depositAmount_svZchf() public {
        _proposeGauge();
        assertEq(channel.donateCalls(), 1);
        assertEq(channel.lastDonateToken(), address(svZchf));
        assertEq(channel.lastDonateAmount(), DEPOSIT_SVZCHF);
        assertEq(svZchf.balanceOf(address(channel)), DEPOSIT_SVZCHF);
        assertEq(svZchf.balanceOf(proposer), 1_000_000e18 - DEPOSIT_SVZCHF);
    }
    function test_depositAmount_sUsds() public {
        vm.prank(proposer);
        gov.proposeGaugeChallenge(gaugePool, IERC20(address(sUsds)));
        assertEq(channel.lastDonateToken(), address(sUsds));
        assertEq(channel.lastDonateAmount(), DEPOSIT_SUSDS);
        assertEq(sUsds.balanceOf(address(channel)), DEPOSIT_SUSDS);
    }
    function test_depositAmount_revertInvalidPayToken() public {
        MockERC20 other = new MockERC20("Other Token", "OTH", 18);
        vm.expectRevert(AureumGovernance.InvalidPayToken.selector);
        gov.proposeCompositionChallenge(5, candidatePool, IERC20(address(other)));
    }
    function test_proposeGauge_happyPath_depositsAndRecords() public {
        uint256 start = block.number;
        vm.expectEmit(address(gov));
        emit AureumGovernance.ProposalCreated(1, AureumGovernance.ProposalType.GaugeChallenge, proposer, start, start + VOTING_PERIOD, TOTAL_SUPPLY);
        uint256 id = _proposeGauge();
        assertEq(id, 1);
        assertEq(gov.proposalCount(), 1);
        AureumGovernance.Proposal memory p = gov.getProposal(1);
        assertEq(p.proposer, proposer);
        assertEq(uint256(p.proposalType), uint256(AureumGovernance.ProposalType.GaugeChallenge));
        assertEq(p.targetPool, gaugePool);
        assertEq(p.newPool, address(0));
        assertEq(p.slot, 0);
        assertEq(p.newFee, 0);
        assertEq(p.startBlock, start);
        assertEq(p.endBlock, start + VOTING_PERIOD);
        assertEq(p.snapshotTotalSupply, TOTAL_SUPPLY);
        assertEq(p.forVotes, 0);
        assertEq(p.againstVotes, 0);
        assertEq(p.eta, 0);
        assertEq(p.executed, false);
        assertEq(channel.donateCalls(), 1);
        assertEq(channel.lastDonateAmount(), DEPOSIT_SVZCHF);
    }
    function test_proposeGauge_revert_notActive() public {
        address inactivePool = makeAddr("inactivePool");
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.InvalidGaugeTarget.selector, inactivePool));
        gov.proposeGaugeChallenge(inactivePool, IERC20(address(svZchf)));
    }
    function test_proposeGauge_revert_isMiliarium() public {
        slotReg.setSlotOf(gaugePool, 3);
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.InvalidGaugeTarget.selector, gaugePool));
        gov.proposeGaugeChallenge(gaugePool, IERC20(address(svZchf)));
    }
    function test_proposeGauge_revert_invalidPayToken() public {
        MockERC20 other = new MockERC20("Other Token", "OTH", 18);
        vm.expectRevert(AureumGovernance.InvalidPayToken.selector);
        gov.proposeGaugeChallenge(gaugePool, IERC20(address(other)));
    }
    function test_proposeComposition_happyPath_depositsAndRecords() public {
        uint256 start = block.number;
        vm.expectEmit(address(gov));
        emit AureumGovernance.ProposalCreated(1, AureumGovernance.ProposalType.CompositionChallenge, proposer, start, start + VOTING_PERIOD, TOTAL_SUPPLY);
        uint256 id = _proposeComposition();
        assertEq(id, 1);
        assertEq(gov.proposalCount(), 1);
        AureumGovernance.Proposal memory p = gov.getProposal(1);
        assertEq(uint256(p.proposalType), uint256(AureumGovernance.ProposalType.CompositionChallenge));
        assertEq(p.targetPool, address(0));
        assertEq(p.newPool, candidatePool);
        assertEq(p.slot, 5);
        assertEq(p.newFee, 0);
        assertEq(p.snapshotTotalSupply, TOTAL_SUPPLY);
        assertEq(channel.donateCalls(), 1);
        assertEq(channel.lastDonateAmount(), DEPOSIT_SVZCHF);
    }
    function test_proposeComposition_revert_slotOutOfRange() public {
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.InvalidCompositionTarget.selector, uint256(0)));
        gov.proposeCompositionChallenge(0, candidatePool, IERC20(address(svZchf)));
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.InvalidCompositionTarget.selector, uint256(29)));
        gov.proposeCompositionChallenge(29, candidatePool, IERC20(address(svZchf)));
    }
    function test_proposeComposition_revert_slotUnoccupied() public {
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.InvalidCompositionTarget.selector, uint256(7)));
        gov.proposeCompositionChallenge(7, candidatePool, IERC20(address(svZchf)));
    }
    function test_proposeComposition_revert_zeroNewPool() public {
        vm.expectRevert(AureumGovernance.ZeroAddress.selector);
        gov.proposeCompositionChallenge(5, address(0), IERC20(address(svZchf)));
    }
    function test_proposeFee_happyPath_depositsAndRecords() public {
        uint256 start = block.number;
        vm.expectEmit(address(gov));
        emit AureumGovernance.ProposalCreated(1, AureumGovernance.ProposalType.FeeChange, proposer, start, start + VOTING_PERIOD, TOTAL_SUPPLY);
        uint256 id = _proposeFee();
        assertEq(id, 1);
        assertEq(gov.proposalCount(), 1);
        AureumGovernance.Proposal memory p = gov.getProposal(1);
        assertEq(uint256(p.proposalType), uint256(AureumGovernance.ProposalType.FeeChange));
        assertEq(p.targetPool, feePool);
        assertEq(p.newFee, FEE_OK);
        assertEq(p.newPool, address(0));
        assertEq(p.slot, 0);
        assertEq(p.snapshotTotalSupply, TOTAL_SUPPLY);
        assertEq(channel.donateCalls(), 1);
        assertEq(channel.lastDonateAmount(), DEPOSIT_SVZCHF);
    }
    function test_proposeFee_revert_feeOutOfRange() public {
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.InvalidFeeValue.selector, uint256(1e14 - 1)));
        gov.proposeFeeChange(feePool, 1e14 - 1, IERC20(address(svZchf)));
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.InvalidFeeValue.selector, uint256(3e15 + 1)));
        gov.proposeFeeChange(feePool, 3e15 + 1, IERC20(address(svZchf)));
    }
    function test_proposeFee_revert_bodenseePool() public {
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.InvalidFeeTarget.selector, bodenseePool));
        gov.proposeFeeChange(bodenseePool, FEE_OK, IERC20(address(svZchf)));
    }
    function test_proposeFee_revert_notGauged() public {
        address ungauged = makeAddr("ungaugedPool");
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.InvalidFeeTarget.selector, ungauged));
        gov.proposeFeeChange(ungauged, FEE_OK, IERC20(address(svZchf)));
    }
    function test_castVote_accruesForVotes() public {
        uint256 id = _proposeGauge();
        uint256 w = 300_000e18;
        votingWeight.setGovernanceWeight(voterA, w);
        vm.expectEmit(address(gov));
        emit AureumGovernance.VoteCast(id, voterA, true, w);
        vm.prank(voterA);
        gov.castVote(id, true);
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        assertEq(p.forVotes, w);
        assertEq(p.againstVotes, 0);
        assertTrue(gov.hasVoted(id, voterA));
    }
    function test_castVote_accruesAgainstVotes() public {
        uint256 id = _proposeGauge();
        uint256 w = 200_000e18;
        votingWeight.setGovernanceWeight(voterA, w);
        vm.prank(voterA);
        gov.castVote(id, false);
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        assertEq(p.againstVotes, w);
        assertEq(p.forVotes, 0);
    }
    function test_castVote_multipleVotersAccumulate() public {
        uint256 id = _proposeGauge();
        uint256 wA = 300_000e18;
        uint256 wB = 150_000e18;
        votingWeight.setGovernanceWeight(voterA, wA);
        votingWeight.setGovernanceWeight(voterB, wB);
        vm.prank(voterA);
        gov.castVote(id, true);
        vm.prank(voterB);
        gov.castVote(id, false);
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        assertEq(p.forVotes, wA);
        assertEq(p.againstVotes, wB);
    }
    function test_castVote_pokesVoterBeforeAccrual() public {
        uint256 id = _proposeGauge();
        uint256 w = 100_000e18;
        votingWeight.setGovernanceWeight(voterA, w);
        vm.prank(voterA);
        gov.castVote(id, true);
        assertEq(votingWeight.pokeCount(), 1);
        assertEq(votingWeight.lastPoked(), voterA);
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        assertEq(p.forVotes, w);
    }
    function test_castVote_zeroWeightNoOp() public {
        uint256 id = _proposeGauge();
        vm.expectEmit(address(gov));
        emit AureumGovernance.VoteCast(id, voterA, true, 0);
        vm.prank(voterA);
        gov.castVote(id, true);
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        assertEq(p.forVotes, 0);
        assertEq(p.againstVotes, 0);
        assertTrue(gov.hasVoted(id, voterA));
    }
    function test_castVote_revert_doubleVote() public {
        uint256 id = _proposeGauge();
        votingWeight.setGovernanceWeight(voterA, 100_000e18);
        vm.prank(voterA);
        gov.castVote(id, true);
        vm.prank(voterA);
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.AlreadyVoted.selector, voterA, id));
        gov.castVote(id, true);
    }
    function test_castVote_revert_nonexistentProposal() public {
        vm.roll(1_000);
        vm.prank(voterA);
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.ProposalNotActive.selector, uint256(999)));
        gov.castVote(999, true);
    }
    function test_castVote_windowBoundaryStrict() public {
        uint256 id = _proposeGauge();
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        uint256 endBlock = p.endBlock;
        votingWeight.setGovernanceWeight(voterA, 100_000e18);
        votingWeight.setGovernanceWeight(voterB, 50_000e18);
        vm.roll(endBlock);
        vm.prank(voterA);
        gov.castVote(id, true);
        p = gov.getProposal(id);
        assertEq(p.forVotes, 100_000e18);
        vm.roll(endBlock + 1);
        vm.prank(voterB);
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.ProposalNotActive.selector, id));
        gov.castVote(id, false);
    }
    function test_state_active_duringWindowAndAtEndBlock() public {
        uint256 id = _proposeGauge();
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Active));
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        vm.roll(p.endBlock);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Active));
    }
    function test_state_quorumBoundaryStrict() public {
        uint256 id1 = _proposeGauge();
        votingWeight.setGovernanceWeight(voterA, 200_000e18);
        vm.prank(voterA);
        gov.castVote(id1, true);
        uint256 id2 = _proposeGauge();
        votingWeight.setGovernanceWeight(voterB, 200_000e18 - 1);
        vm.prank(voterB);
        gov.castVote(id2, true);
        AureumGovernance.Proposal memory p = gov.getProposal(id1);
        vm.roll(p.endBlock + 1);
        assertEq(uint256(gov.state(id1)), uint256(AureumGovernance.ProposalState.Succeeded));
        assertEq(uint256(gov.state(id2)), uint256(AureumGovernance.ProposalState.Defeated));
    }
    function test_state_gauge_simpleMajorityPass() public {
        uint256 id = _proposeGauge();
        votingWeight.setGovernanceWeight(voterA, 200_000e18);
        votingWeight.setGovernanceWeight(voterB, 100_000e18);
        vm.prank(voterA);
        gov.castVote(id, true);
        vm.prank(voterB);
        gov.castVote(id, false);
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        vm.roll(p.endBlock + 1);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Succeeded));
    }
    function test_state_gauge_tieDefeated() public {
        uint256 id = _proposeGauge();
        votingWeight.setGovernanceWeight(voterA, 150_000e18);
        votingWeight.setGovernanceWeight(voterB, 150_000e18);
        vm.prank(voterA);
        gov.castVote(id, true);
        vm.prank(voterB);
        gov.castVote(id, false);
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        vm.roll(p.endBlock + 1);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Defeated));
    }
    function test_state_fee_simpleMajorityPass() public {
        uint256 id = _proposeFee();
        votingWeight.setGovernanceWeight(voterA, 250_000e18);
        votingWeight.setGovernanceWeight(voterB, 100_000e18);
        vm.prank(voterA);
        gov.castVote(id, true);
        vm.prank(voterB);
        gov.castVote(id, false);
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        vm.roll(p.endBlock + 1);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Succeeded));
    }
    function test_state_composition_supermajorityExactPass() public {
        uint256 id = _proposeComposition();
        votingWeight.setGovernanceWeight(voterA, 200_000e18);
        votingWeight.setGovernanceWeight(voterB, 100_000e18);
        vm.prank(voterA);
        gov.castVote(id, true);
        vm.prank(voterB);
        gov.castVote(id, false);
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        vm.roll(p.endBlock + 1);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Succeeded));
    }
    function test_state_composition_belowSupermajorityDefeated() public {
        uint256 id = _proposeComposition();
        votingWeight.setGovernanceWeight(voterA, 175_000e18);
        votingWeight.setGovernanceWeight(voterB, 125_000e18);
        vm.prank(voterA);
        gov.castVote(id, true);
        vm.prank(voterB);
        gov.castVote(id, false);
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        vm.roll(p.endBlock + 1);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Defeated));
    }
    function test_state_nonexistent_defeated() public {
        vm.roll(1_000);
        assertEq(uint256(gov.state(999)), uint256(AureumGovernance.ProposalState.Defeated));
    }
}
