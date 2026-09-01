// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {VotingWeight} from "src/governance/VotingWeight.sol";
import {IVotingWeight} from "src/governance/IVotingWeight.sol";
import {AureumGovernance} from "src/governance/AureumGovernance.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IMiliariumSlotRegistry} from "src/registry/IMiliariumSlotRegistry.sol";
import {SwapAndDepositToBodensee} from "src/gauge/SwapAndDepositToBodensee.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockEMASampler, MockGaugeRegistry, MockMiliariumRegistry, MockRecorder} from "test/unit/VotingWeight.t.sol";
import {MockSlotRegistry, MockVault, MockBodenseeChannel} from "test/unit/AureumGovernance.t.sol";

/// @title P1 B.1 — quorum denominator counts only ever-poked holders
/// @notice Reproduction PoC for seam-1 root cause B.1 (High). Identical qualifying capital
///         that nobody poked is absent from `getPastTotalSupply`, so a sole poked minority
///         can clear the CompositionChallenge two-thirds bar against an uncounted LP majority.
contract P1_B1_QuorumDenominatorCountsOnlyPokedHoldersTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant START_BLOCK = 2_000_000;
    uint256 internal constant TVL_EMA = 16e18;
    uint256 internal constant LP_IDENTICAL = 100e18;

    VotingWeight internal vw;
    AureumGovernance internal gov;
    MockEMASampler internal emaSampler;
    MockGaugeRegistry internal gaugeReg;
    MockRecorder internal recorder;
    MockMiliariumRegistry internal miliariumReg;
    MockSlotRegistry internal slotReg;
    MockVault internal vault;
    MockBodenseeChannel internal channel;
    MockERC20 internal svZchf;
    MockERC20 internal sUsds;

    address internal pool;
    address internal incumbent;
    address internal candidate;
    address internal bodenseePool;
    address internal holderA;
    address internal holderB;
    address internal holderC;
    address internal proposer;

    function setUp() public {
        emaSampler = new MockEMASampler();
        gaugeReg = new MockGaugeRegistry();
        recorder = new MockRecorder();
        miliariumReg = new MockMiliariumRegistry();
        slotReg = new MockSlotRegistry();
        vault = new MockVault();
        channel = new MockBodenseeChannel();
        svZchf = new MockERC20("Staked Frankencoin", "svZCHF", 18);
        sUsds = new MockERC20("Savings USDS", "sUSDS", 18);

        pool = makeAddr("pool");
        incumbent = makeAddr("incumbent");
        candidate = makeAddr("candidate");
        bodenseePool = makeAddr("bodenseePool");
        holderA = makeAddr("holderA");
        holderB = makeAddr("holderB");
        holderC = makeAddr("holderC");
        proposer = makeAddr("proposer");

        vw = new VotingWeight(emaSampler, gaugeReg, recorder, miliariumReg, GENESIS_BLOCK);
        gov = new AureumGovernance(
            IVotingWeight(address(vw)),
            IGaugeRegistry(address(gaugeReg)),
            IMiliariumSlotRegistry(address(slotReg)),
            IVault(address(vault)),
            SwapAndDepositToBodensee(address(channel)),
            IERC20(address(svZchf)),
            IERC20(address(sUsds)),
            bodenseePool
        );

        address[] memory pools = new address[](1);
        pools[0] = pool;
        miliariumReg.setPoolList(pools);
        miliariumReg.setMiliarium(pool, true);
        gaugeReg.setApproved(pool, true);

        // Seed far enough back to clear EMA maturity; refresh inside the staleness window.
        emaSampler.setTvlEMA(pool, TVL_EMA);
        emaSampler.setSeedBlock(pool, 1);
        emaSampler.setLastUpdateBlock(pool, START_BLOCK);

        vm.mockCall(pool, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(1e30)));

        slotReg.setPoolAtSlot(1, incumbent);
        vm.mockCall(
            address(gaugeReg),
            abi.encodeWithSelector(IGaugeRegistry.meetsCompositionQualityGate.selector, candidate),
            abi.encode(true)
        );
        vm.mockCall(
            address(gaugeReg),
            abi.encodeWithSelector(IGaugeRegistry.feeRailConjunctSatisfied.selector, candidate),
            abi.encode(true)
        );

        svZchf.mint(proposer, 1_000_000e18);
        vm.prank(proposer);
        svZchf.approve(address(gov), type(uint256).max);

        vm.roll(START_BLOCK);
    }

    function _configureHolder(address holder, uint256 userLP, uint256 poolTotalLP) internal {
        uint256 eqb = START_BLOCK - AureumTime.ON_RAMP_PERIOD_BLOCKS;
        recorder.setUserLP(pool, holder, userLP);
        recorder.setPoolTotalLP(pool, poolTotalLP);
        recorder.setEffectiveQualBlock(pool, holder, eqb);
    }

    /// @dev Pins that byte-identical qualifying capital contributes nothing until a discretionary poke.
    function test_P1_B1_unpokedHolderIsAbsentFromTheQuorumDenominator() public {
        _configureHolder(holderA, LP_IDENTICAL, LP_IDENTICAL * 2);
        _configureHolder(holderB, LP_IDENTICAL, LP_IDENTICAL * 2);

        vw.poke(holderA);
        vm.roll(START_BLOCK + 1);

        uint256 weightA = vw.getPastVotes(holderA, START_BLOCK);
        assertGt(weightA, 0, "poked holder has nonzero weight");
        assertEq(vw.getPastVotes(holderB, START_BLOCK), 0, "unpoked twin has zero checkpoint weight");
        assertEq(
            vw.getPastTotalSupply(START_BLOCK),
            weightA,
            "denominator equals the sole poked holder"
        );

        // Counterfactual: a third-party poke of the twin admits the same capital into the denominator.
        vw.poke(holderB);
        vm.roll(START_BLOCK + 2);

        uint256 weightB = vw.getPastVotes(holderB, START_BLOCK + 1);
        assertEq(weightB, weightA, "identical positions yield equal weight once both are poked");
        assertEq(
            vw.getPastTotalSupply(START_BLOCK + 1),
            weightA + weightB,
            "denominator rises by the newly poked twin weight"
        );
    }

    /// @dev Pins that a sole poked minority clears the CompositionChallenge two-thirds bar while unpoked LP stays out.
    function test_P1_B1_solePokedHolderCarriesTheTwoThirdsBarWhileTheRestOfTheLpNeverEnters() public {
        uint256 lpA = 10e18;
        uint256 lpB = 45e18;
        uint256 lpC = 45e18;
        uint256 poolTotal = lpA + lpB + lpC;
        _configureHolder(holderA, lpA, poolTotal);
        _configureHolder(holderB, lpB, poolTotal);
        _configureHolder(holderC, lpC, poolTotal);

        // Only A is poked before the proposal is created.
        vw.poke(holderA);

        vm.prank(proposer);
        uint256 id = gov.proposeCompositionChallenge(1, candidate, IERC20(address(svZchf)));

        AureumGovernance.Proposal memory p = gov.getProposal(id);
        vm.roll(p.snapshotBlock + 1);

        vm.prank(holderA);
        gov.castVote(id, true);

        vm.roll(p.endBlock + 1);

        assertEq(
            uint256(gov.state(id)),
            uint256(AureumGovernance.ProposalState.Succeeded),
            "sole poked minority carries CompositionChallenge"
        );

        uint256 weightA = vw.getPastVotes(holderA, p.snapshotBlock);
        assertEq(
            vw.getPastTotalSupply(p.snapshotBlock),
            weightA,
            "snapshot denominator is A's weight alone"
        );
        assertEq(vw.getPastVotes(holderB, p.snapshotBlock), 0, "unpoked B absent from snapshot");
        assertEq(vw.getPastVotes(holderC, p.snapshotBlock), 0, "unpoked C absent from snapshot");

        uint256 unpokedLP = recorder.userLP(pool, holderB) + recorder.userLP(pool, holderC);
        assertGt(unpokedLP, recorder.userLP(pool, holderA), "unpoked holders hold the LP majority");
        assertGt(unpokedLP * 2, poolTotal, "unpoked LP is strictly more than half the pool");
    }
}
