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
import {MockBlockAwareVotingWeight} from "test/mocks/MockBlockAwareVotingWeight.sol";
import {MockGaugeRegistry, MockSlotRegistry, MockVault, MockBodenseeChannel} from "test/unit/AureumGovernance.t.sol";

/// @notice F-21 regression suite, split out of F01_quorumSnapshotTiming.t.sol at PP4.10f5.
/// @dev F-21 is the `snapshot == 0` case F-06 left open: the stored mul-form
///      `totalVotes * 10_000 < getPastTotalSupply(snapshotBlock) * QUORUM_BPS` passes vacuously at a
///      zero denominator, since `0 < 0` is false. PB-D62 closed it with a zero-supply guard in
///      `_voteSucceeded`. These cases pinned it inside F01 until PP4.10d added a SECOND, EARLIER
///      guard: `_createProposal` now refuses the bond when LIVE `totalSupply()` is zero.
///      That is why this file exists rather than the cases staying in F01. F01 declares in its own
///      header that it uses the block-agnostic mock "with consistent snapshot inputs", where live
///      and snapshot supply are the same quantity. F-21 now REQUIRES them to diverge: live must be
///      non-zero at propose for the bond to be accepted, while the snapshot denominator must be
///      zero at the vote for the guard under test to fire. A block-agnostic mock cannot express
///      that, so this suite uses the shared `MockBlockAwareVotingWeight`, as F-06 does for its own
///      block-precise property. The divergence is reachable in production because supply can fall
///      between propose and snapshot, which is exactly what the D.5 outage does.
contract F21_ZeroSnapshotQuorumTest is Test {
    AureumGovernance internal gov;
    MockBlockAwareVotingWeight internal votingWeight;
    MockGaugeRegistry internal gaugeReg;
    MockSlotRegistry internal slotReg;
    MockVault internal vault;
    MockBodenseeChannel internal channel;
    MockERC20 internal svZchf;
    MockERC20 internal sUsds;

    address internal attacker = makeAddr("attacker");
    address internal bodenseePool = makeAddr("bodenseePool");
    address internal gaugePool = makeAddr("gaugePool");
    address internal occupantPool = makeAddr("occupantPool");
    address internal candidatePool = makeAddr("candidatePool");

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
        slotReg.setPoolAtSlot(5, occupantPool);
        gaugeReg.setGaugeStatus(occupantPool, IGaugeRegistry.GaugeStatus.Active);
        svZchf.mint(attacker, 1_000_000e18);
        sUsds.mint(attacker, 1_000_000e18);
        vm.startPrank(attacker);
        svZchf.approve(address(gov), type(uint256).max);
        sUsds.approve(address(gov), type(uint256).max);
        vm.stopPrank();
    }

    /// @dev Seats `holder`'s true weight and materializes it into the accumulator, stamping a
    ///      checkpoint at the current block. Seating zero is how a later checkpoint drives the
    ///      snapshot denominator down without touching what live supply was at propose time.
    function _seat(address holder, uint256 weight) internal {
        votingWeight.setTrueWeight(holder, weight);
        votingWeight.poke(holder);
    }

    /// @notice PP4.10d's propose-time guard, the front line added ahead of F-21's vote-time one.
    /// @dev D.5 clause 4 under PP-D52 (v). The two guards read DIFFERENT quantities and neither
    ///      implies the other: this one reads live `totalSupply()` at propose, F-21's reads
    ///      `getPastTotalSupply(snapshotBlock)` at the vote, and the snapshot block is still in the
    ///      future here. Its purpose is narrow and worth stating: it stops a non-refundable bond
    ///      burning during the structural launch window, where no holder has matured yet.
    function test_F21_proposeRefusesTheBondAtZeroLiveSupply() public {
        assertEq(votingWeight.totalSupply(), 0, "premise - the electorate is empty");
        uint256 balanceBefore = svZchf.balanceOf(attacker);

        vm.prank(attacker);
        vm.expectRevert(AureumGovernance.ZeroQualifiedWeight.selector);
        gov.proposeGaugeChallenge(gaugePool, IERC20(address(svZchf)));

        assertEq(svZchf.balanceOf(attacker), balanceBefore, "the bond never moved");
        assertEq(gov.proposalCount(), 0, "no proposal was created");
    }
}
