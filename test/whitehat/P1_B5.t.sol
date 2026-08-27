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

/// @title P1 B.5 — permissionless syncPosition times a self-desynced clock reset
/// @notice Reproduction PoC for seam-1 root cause B.5 (Medium). A stranger chooses WHEN
///         `_syncDown` zeroes a self-desynced holder's qualification clock, and an unsynced
///         out-of-band exit keeps a matured clock the honest `recordWithdrawal` path resets.
///         Both findings close via the same read-time `if (held < lp) return 0` rule.
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

    /// @dev The stranger times the clock kill; the victim already desynced themselves by transferring BPT.
    function test_P1_B5_strangerChoosesWhenTheSelfDesyncedHolderLosesTheirClock() public {
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

        // Attacker did not manufacture the desync and could not have — the [corrected] B.5 note
        // limits the victim set to holders who desynced themselves; the stranger controls the
        // MOMENT, which is why a block before a governance snapshot is the shape that matters.
        vm.prank(stranger);
        distributor.syncPosition(address(pool), victim);

        assertEq(distributor.effectiveQualBlock(address(pool), victim), 0, "syncDown zeroes the qualification clock");

        vw.poke(victim);
        assertEq(vw.governanceWeight(victim), 0, "eqb zero short-circuits position power");
    }

    /// @dev Honest recordWithdrawal resets the clock; an unsynced out-of-band exit keeps it. F-17 caps LP, not the clock.
    function test_P1_B5_unsyncedOutOfBandExitKeepsAClockTheHonestPathResets() public {
        address exiter = makeAddr("exiter");
        address honest = makeAddr("honest");

        _openMaturedPosition(exiter, STAKE);
        _openMaturedPosition(honest, STAKE);

        uint256 maturedEqb = distributor.effectiveQualBlock(address(pool), exiter);
        assertGt(maturedEqb, 0, "exiter clock is mature before the exit");
        assertGt(distributor.effectiveQualBlock(address(pool), honest), 0, "honest clock is mature before the exit");

        vm.prank(exiter);
        pool.transfer(sink, 90e18);

        vm.prank(honest);
        pool.transfer(sink, 90e18);
        vm.prank(aumtRec);
        distributor.recordWithdrawal(address(pool), honest, 90e18);

        // F-17 read-cap at VotingWeight.sol:180-181 correctly caps the exiter's counted LP at
        // their live balance, so this is not weight inflation — the surviving advantage is the
        // CLOCK, which the honest path surrenders and the out-of-band path keeps.
        assertEq(distributor.effectiveQualBlock(address(pool), honest), 0, "honest path resets eqb at recordWithdrawal");
        assertEq(
            distributor.effectiveQualBlock(address(pool), exiter),
            maturedEqb,
            "unsynced out-of-band exit leaves the matured clock intact"
        );

        assertEq(pool.balanceOf(exiter), 10e18);
        assertEq(pool.balanceOf(honest), 10e18);

        vw.poke(exiter);
        vw.poke(honest);

        assertEq(vw.governanceWeight(honest), 0, "reset clock scores zero");
        assertGt(vw.governanceWeight(exiter), 0, "preserved clock still scores on capped live BPT");
    }
}
