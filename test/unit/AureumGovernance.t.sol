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
    function poke(address) external {}
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
}
