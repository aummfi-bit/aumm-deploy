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
import {MockGaugeRegistry, MockSlotRegistry, MockVault, MockBodenseeChannel} from "test/unit/AureumGovernance.t.sol";

/// @notice Block-aware voting-weight mock for the F-06 PoC. Unlike the block-agnostic MockVotingWeight
///         in AureumGovernance.t.sol, this honors the block argument of getPastVotes / getPastTotalSupply
///         via ascending per-block checkpoints, mirroring the OZ Checkpoints.Trace208 upperLookup
///         semantics of the real VotingWeight. poke(holder) pulls the holder's true (position-derived)
///         weight into the live accumulator and stamps a checkpoint at the current block - the
///         permissionless lever the F-06 griefer pulls after endBlock. The future-lookup guard is
///         omitted; the PoC reads only strictly-past blocks.
contract MockBlockAwareVotingWeight is IVotingWeight {
    struct Ckpt {
        uint256 blk;
        uint256 val;
    }

    mapping(address => Ckpt[]) private _holderCkpts;
    Ckpt[] private _totalCkpts;
    mapping(address => uint256) private _liveHolder;
    uint256 private _liveTotal;
    mapping(address => uint256) public trueWeight;

    /// @notice Set a holder's true position-derived weight, materialized into the accumulator on the next poke.
    function setTrueWeight(address holder, uint256 weight) external {
        trueWeight[holder] = weight;
    }

    function poke(address holder) external {
        uint256 prev = _liveHolder[holder];
        uint256 target = trueWeight[holder];
        _liveTotal = _liveTotal - prev + target;
        _liveHolder[holder] = target;
        _holderCkpts[holder].push(Ckpt(block.number, target));
        _totalCkpts.push(Ckpt(block.number, _liveTotal));
    }

    function governanceWeight(address holder) external view returns (uint256) {
        return _liveHolder[holder];
    }

    function totalSupply() external view returns (uint256) {
        return _liveTotal;
    }

    function getPastVotes(address holder, uint256 blockNumber) external view returns (uint256) {
        return _upperLookup(_holderCkpts[holder], blockNumber);
    }

    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256) {
        return _upperLookup(_totalCkpts, blockNumber);
    }

    function _upperLookup(Ckpt[] storage ckpts, uint256 blockNumber) private view returns (uint256) {
        uint256 value;
        for (uint256 i; i < ckpts.length; ++i) {
            if (ckpts[i].blk <= blockNumber) value = ckpts[i].val;
            else break;
        }
        return value;
    }
}

/// @notice White-hat finding F-06 (S9) PoC: the post-endBlock quorum-denominator inflation grief and its
///         symmetric deflate-to-pass face are structurally closed by the F-06 snapshot denominator.
///         forVotes/againstVotes freeze at endBlock; _voteSucceeded reads the denominator at
///         getPastTotalSupply(snapshotBlock), a frozen historical value, so a permissionless poke after
///         endBlock grows or shrinks only the LIVE accumulator, never the snapshotBlock checkpoint the
///         tally reads. A passed proposal stays Succeeded through queue/execute; a failed one stays
///         Defeated. The block-aware mock honors the block argument the AureumGovernance.t.sol mock
///         cannot, exercising the freeze directly.
contract F06_PostEndBlockDenominatorFreezeTest is Test {
    AureumGovernance internal gov;
    MockBlockAwareVotingWeight internal votingWeight;
    MockGaugeRegistry internal gaugeReg;
    MockSlotRegistry internal slotReg;
    MockVault internal vault;
    MockBodenseeChannel internal channel;
    MockERC20 internal svZchf;
    MockERC20 internal sUsds;

    address internal proposer = makeAddr("proposer");
    address internal fillerHolder = makeAddr("fillerHolder");
    address internal dormantGriefer = makeAddr("dormantGriefer");
    address internal bodenseePool = makeAddr("bodenseePool");
    address internal gaugePool = makeAddr("gaugePool");

    uint256 internal constant TIMELOCK = 14_400;

    function setUp() public {
        votingWeight = new MockBlockAwareVotingWeight();
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
        svZchf.mint(proposer, 1_000_000e18);
        vm.prank(proposer);
        svZchf.approve(address(gov), type(uint256).max);
    }

    /// @notice Inflation grief defeated: a passed gauge challenge stays Succeeded and executes even after a
    ///         dormant matured-LP holder pokes 600_000e18 into the live accumulator post-endBlock. Under the
    ///         pre-fix live denominator the tally would re-read 1_600_000e18 and the 300_000e18 turnout
    ///         (18.75%) would fall under the 20% bar -> Defeated; under the F-06 snapshot denominator the
    ///         tally reads the frozen 1_000_000e18 (30%) -> Succeeded.
    function test_F06_postEndBlockInflationCannotGriefPassedProposal() public {
        votingWeight.setTrueWeight(proposer, 300_000e18);
        votingWeight.poke(proposer);
        votingWeight.setTrueWeight(fillerHolder, 700_000e18);
        votingWeight.poke(fillerHolder);
        vm.prank(proposer);
        uint256 id = gov.proposeGaugeChallenge(gaugePool, IERC20(address(svZchf)));
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        vm.roll(p.snapshotBlock + 1);
        vm.prank(proposer);
        gov.castVote(id, true);
        vm.roll(p.endBlock + 1);
        votingWeight.setTrueWeight(dormantGriefer, 600_000e18);
        votingWeight.poke(dormantGriefer);
        assertEq(votingWeight.getPastTotalSupply(p.snapshotBlock), 1_000_000e18, "snapshot denominator frozen");
        assertEq(votingWeight.totalSupply(), 1_600_000e18, "live accumulator inflated post-endBlock");
        assertEq(gov.getProposal(id).forVotes, 300_000e18, "turnout frozen at endBlock");
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Succeeded), "passed under snapshot denominator");
        gov.queue(id);
        votingWeight.poke(dormantGriefer);
        AureumGovernance.Proposal memory q = gov.getProposal(id);
        vm.roll(q.eta);
        gov.execute(id);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Executed), "grief failed: proposal executed");
        assertTrue(gaugeReg.revoked(gaugePool), "gauge revoked: effect landed");
    }

    /// @notice Deflation face defeated: a sub-quorum proposal stays Defeated even after the live accumulator
    ///         is shrunk post-endBlock. The 150_000e18 turnout is 15% of the frozen 1_000_000e18 snapshot
    ///         denominator (below the 20% bar). The filler withdraws to 350_000e18 post-endBlock, shrinking
    ///         the LIVE total to 500_000e18 where 150_000e18 would read 30% and pass under a live denominator;
    ///         under the F-06 snapshot denominator it stays 15% -> Defeated and queue reverts.
    function test_F06_postEndBlockDeflationCannotRescueFailedProposal() public {
        votingWeight.setTrueWeight(proposer, 150_000e18);
        votingWeight.poke(proposer);
        votingWeight.setTrueWeight(fillerHolder, 850_000e18);
        votingWeight.poke(fillerHolder);
        vm.prank(proposer);
        uint256 id = gov.proposeGaugeChallenge(gaugePool, IERC20(address(svZchf)));
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        vm.roll(p.snapshotBlock + 1);
        vm.prank(proposer);
        gov.castVote(id, true);
        vm.roll(p.endBlock + 1);
        votingWeight.setTrueWeight(fillerHolder, 350_000e18);
        votingWeight.poke(fillerHolder);
        assertEq(votingWeight.getPastTotalSupply(p.snapshotBlock), 1_000_000e18, "snapshot denominator frozen");
        assertEq(votingWeight.totalSupply(), 500_000e18, "live accumulator deflated post-endBlock");
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Defeated), "sub-quorum under snapshot denominator");
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.ProposalNotSucceeded.selector, id));
        gov.queue(id);
    }
}
