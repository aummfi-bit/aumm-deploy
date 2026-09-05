// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {EmissionDistributor} from "src/emission/EmissionDistributor.sol";
import {VotingWeight} from "src/governance/VotingWeight.sol";
import {IAuMM} from "src/token/IAuMM.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "src/ccb/ICCBMultiplier.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {
    MockAuMM,
    MockBpt,
    MockGaugeRegistry,
    MockEMASampler,
    MockCCBMultiplier,
    MockEfficiencyOracle,
    MockMiliariumRegistry
} from "test/unit/EmissionDistributor.t.sol";
import {MockRegisteredVault} from "../mocks/MockRegisteredVault.sol";

/// @title P1 B.5 — a position whose live BPT fell below its recorded LP confers nothing
/// @notice Regression suite for seam-1 root cause B.5 (Medium, ledger F-31), closed at PP4.11 under
///         PP-D53 (i): one read-time rule, `if (held < lp) return 0`, removes the WEIGHT consequence of
///         both filed faces. What it does not remove is the clock reset itself — `_syncDown` stays
///         unconditional and permissionless because PP-D53 (ii) amended PP-D18's full-drain conjunct away
///         as canon-hostile, and the first case here documents that residual rather than a defect.
contract P1_B5_PermissionlessClockResetTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant STAKE = 100e18;

    MockAuMM internal aumm;
    MockBpt internal pool;
    MockGaugeRegistry internal gauges;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockEfficiencyOracle internal effOracle;
    MockMiliariumRegistry internal miliReg;
    EmissionDistributor internal distributor;
    VotingWeight internal vw;

    address internal gov;
    address internal aumtRec;
    address internal sink;

    function setUp() public {
        uint256 startBlock = GENESIS_BLOCK + AureumTime.ON_RAMP_PERIOD_BLOCKS * 2;
        vm.roll(startBlock);

        gov = makeAddr("gov");
        aumtRec = makeAddr("aumtRec");
        sink = makeAddr("sink");

        aumm = new MockAuMM();
        pool = new MockBpt();
        gauges = new MockGaugeRegistry();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        effOracle = new MockEfficiencyOracle();
        miliReg = new MockMiliariumRegistry();

        distributor = new EmissionDistributor(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK,
            gov,
            address(new MockRegisteredVault())
        );

        vw = new VotingWeight(
            IEMASampler(address(ema)),
            IGaugeRegistry(address(gauges)),
            distributor,
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK
        );

        gauges.setApproved(address(pool), true);
        miliReg.setMiliarium(address(pool), true);
        ema.setTVLEMA(address(pool), 1_000_000e18);

        vm.prank(gov);
        distributor.setAuMTContractForPool(address(pool), aumtRec);
    }

    /// @dev Mint BPT, record the deposit through the bound AuMT, then roll past the on-ramp so timeFactor is 1.0.
    function _openMaturedPosition(address holder, uint256 amount) private {
        pool.mint(holder, amount);
        vm.prank(aumtRec);
        distributor.recordDeposit(address(pool), holder, amount);
        vm.roll(block.number + AureumTime.ON_RAMP_PERIOD_BLOCKS);
    }

    /// @dev PP-D53 (ii) residual: `_syncDown`'s clock reset is still permissionless and still stranger-timed,
    ///      and PP-D53 (ii) deliberately left it that way. What the fix removed is its CONSEQUENCE — the
    ///      holder scores zero from their own desync onward, so the stranger's timing buys nothing.
    function test_strangerTimedClockResetNoLongerChangesTheWeight() public {
        address victim = makeAddr("victim");
        address stranger = makeAddr("stranger");

        _openMaturedPosition(victim, STAKE);

        vw.poke(victim);
        uint256 weightBefore = vw.governanceWeight(victim);
        assertGt(weightBefore, 0, "matured position confers governance weight");

        vm.prank(victim);
        pool.transfer(sink, 1);

        assertGt(distributor.userLP(address(pool), victim), pool.balanceOf(victim), "recorded stake exceeds live BPT");
        assertEq(vw.governanceWeight(victim), weightBefore, "stored checkpoint is unchanged until a poke");

        // The whole of the finding was that a stranger picked the MOMENT of the kill, a block before a
        // governance snapshot. One wei of self-desync now zeroes the weight at the next poke by ANYONE,
        // so there is no moment left to pick.
        vw.poke(victim);
        assertEq(vw.governanceWeight(victim), 0, "one wei below lp zeroes the weight before any stranger acts");
        assertGt(distributor.effectiveQualBlock(address(pool), victim), 0, "and the clock is still intact here");

        vm.prank(stranger);
        distributor.syncPosition(address(pool), victim);

        assertEq(distributor.effectiveQualBlock(address(pool), victim), 0, "syncDown still zeroes the qualification clock");

        vw.poke(victim);
        assertEq(vw.governanceWeight(victim), 0, "and the weight was already zero, so nothing moved");
    }

    /// @dev B.5's done-criteria case: a position whose live BPT has fallen below its recorded LP confers
    ///      NOTHING at read time, whatever its clock says. The honest and out-of-band paths reach zero by
    ///      DIFFERENT routes, and a third untouched holder proves the zeroes are earned, not fixture-wide.
    function test_positionPowerZeroWhenHeldBelowLp() public {
        address exiter = makeAddr("exiter");
        address honest = makeAddr("honest");
        address steady = makeAddr("steady");

        _openMaturedPosition(exiter, STAKE);
        _openMaturedPosition(honest, STAKE);
        _openMaturedPosition(steady, STAKE);

        uint256 maturedEqb = distributor.effectiveQualBlock(address(pool), exiter);
        assertGt(maturedEqb, 0, "exiter clock is mature before the exit");
        assertGt(distributor.effectiveQualBlock(address(pool), honest), 0, "honest clock is mature before the exit");

        vm.prank(exiter);
        pool.transfer(sink, 90e18);

        vm.prank(honest);
        pool.transfer(sink, 90e18);
        vm.prank(aumtRec);
        distributor.recordWithdrawal(address(pool), honest, 90e18);

        // PP-D53 (i) and (ii): the CLOCK asymmetry is unchanged and is not what the fix closed. The honest
        // path still surrenders its clock at recordWithdrawal, the out-of-band path still keeps a matured
        // one, and PP-D53 (ii) deliberately left _syncDown alone. What changed is the READ.
        assertEq(distributor.effectiveQualBlock(address(pool), honest), 0, "honest path resets eqb at recordWithdrawal");
        assertEq(
            distributor.effectiveQualBlock(address(pool), exiter),
            maturedEqb,
            "unsynced out-of-band exit still leaves the matured clock intact"
        );

        assertEq(pool.balanceOf(exiter), 10e18);
        assertEq(pool.balanceOf(honest), 10e18);
        assertGt(distributor.userLP(address(pool), exiter), pool.balanceOf(exiter), "exiter is the held below lp case");
        assertEq(distributor.userLP(address(pool), honest), pool.balanceOf(honest), "honest is the held equals lp case");
        assertEq(distributor.userLP(address(pool), steady), pool.balanceOf(steady), "steady is untouched");

        vw.poke(exiter);
        vw.poke(honest);
        vw.poke(steady);

        assertEq(vw.governanceWeight(exiter), 0, "held below lp confers nothing, matured clock notwithstanding");
        assertEq(vw.governanceWeight(honest), 0, "zeroed clock scores zero");
        assertGt(vw.governanceWeight(steady), 0, "an untouched matured position still scores");
    }
}
