// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AuMM} from "../../src/token/AuMM.sol";
import {IAuMM} from "../../src/token/IAuMM.sol";
import {EmissionDistributorHarness} from "../unit/harness/EmissionDistributorHarness.sol";
import {IGaugeRegistry} from "../../src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "../../src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "../../src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "../../src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "../../src/gauge/IEfficiencyOracle.sol";
import {AureumTime} from "../../src/lib/AureumTime.sol";
import {
    MockGaugeRegistry,
    MockEMASampler,
    MockCCBMultiplier,
    MockEfficiencyOracle,
    MockMiliariumRegistry
} from "../unit/EmissionDistributor.t.sol";
import {MockRegisteredVault} from "../mocks/MockRegisteredVault.sol";

/// @notice PP3.2 reproduction PoC for root cause E.6 — `_accrueGlobal`'s `totalScore == 0` branch
///         advances `lastAccrualBlock` WITHOUT integrating, so any window in which every pool's
///         score has self-cleared destroys that window's entire LP emission tranche. One
///         permissionless `claim` triggers it; `lastAccrualBlock` is monotonic, so nothing recovers.
/// @dev Unit-scoped deliberately: the defect is pure accounting inside `EmissionDistributor` and
///      touches no Vault path. Real distributor, real AuMM; the five peripheral mocks are the
///      already-neutralized ones from the unit suite. PP-D33 orders the prefix-sum before the
///      cursor fix, so this PoC pins the pre-fix behaviour both rungs are measured against.
contract P1_E6_Test is Test {
    uint256 internal constant GENESIS_BLOCK_ = 1_000_000;
    address internal constant GOV = address(0xC0FE);
    address internal constant POOL = address(0xA1);
    address internal constant MALLORY = address(0xBAD);

    AuMM internal aumm;
    MockGaugeRegistry internal gauges;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockEfficiencyOracle internal effOracle;
    MockMiliariumRegistry internal miliReg;
    EmissionDistributorHarness internal distributor;

    function setUp() public {
        aumm = new AuMM(GENESIS_BLOCK_, address(this));
        gauges = new MockGaugeRegistry();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        effOracle = new MockEfficiencyOracle();
        miliReg = new MockMiliariumRegistry();

        distributor = new EmissionDistributorHarness(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK_,
            GOV,
            address(new MockRegisteredVault())
        );

        effOracle.setEmissionsRecorder(address(distributor));
        gauges.setApproved(POOL, true);
        miliReg.setMiliarium(POOL, true);
        mult.setMultiplier(POOL, 1e18);
        vm.mockCall(POOL, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(0)));
        vm.roll(GENESIS_BLOCK_);
    }

    /// @notice The fix (PP-D47 / E.6): with every score self-cleared AFTER a completed accrual, a
    ///         permissionless `claim` no longer advances the cursor. The window stays PENDING and the next
    ///         accrual carrying live scores integrates it in full, so nothing is forfeited and no caller can
    ///         book the loss at a moment of their choosing. The recovery leg deliberately takes TWO
    ///         `recordScore` calls, which is not incidental: `_accrueGlobal` runs at step 2 and the score
    ///         write at step 10, so the score-restoring call still observes `totalScore == 0` and holds,
    ///         and the drain lands on the call after it. That ordering is why PP-D47 forks on cold start.
    function test_zeroTotalScoreWindowDoesNotForfeit() public {
        ema.setTVLEMA(POOL, 1_000e18);
        distributor.recordScore(POOL);
        assertGt(distributor.totalScore(), 0, "precondition: a scored pool exists");
        vm.roll(block.number + 1_000);
        distributor.recordScore(POOL);
        uint256 accAfterHealthyAccrual = distributor.accRewardPerScoreUnit();
        assertGt(accAfterHealthyAccrual, 0, "control: accrual integrates while totalScore > 0");
        ema.setTVLEMA(POOL, 0);
        distributor.recordScore(POOL);
        assertEq(distributor.totalScore(), 0, "score self-cleared to zero");
        uint256 cursorBefore = distributor.lastAccrualBlock();

        vm.roll(block.number + 10_000);
        vm.prank(MALLORY);
        distributor.claim(POOL, MALLORY);

        assertEq(distributor.lastAccrualBlock(), cursorBefore, "cursor moved across the pending window");
        assertLt(distributor.lastAccrualBlock(), block.number, "cursor was not held behind the current block");
        assertEq(distributor.accRewardPerScoreUnit(), accAfterHealthyAccrual, "accumulator moved with no live score");

        ema.setTVLEMA(POOL, 1_000e18);
        distributor.recordScore(POOL);
        assertEq(distributor.lastAccrualBlock(), cursorBefore, "the score-restoring call drained early");

        distributor.recordScore(POOL);
        assertEq(distributor.lastAccrualBlock(), block.number, "cursor did not catch up once scores returned");
        assertGt(distributor.accRewardPerScoreUnit(), accAfterHealthyAccrual, "the pending window was never integrated");
    }

    /// @notice The fork's OTHER arm (PP-D47): before any accrual has ever completed, the zero-`totalScore`
    ///         branch still advances the cursor and the window IS forfeited. That window is the post-genesis
    ///         maturity gap, in which `_gatedTvlEMA` returns zero for every pool because none has cleared
    ///         `EMA_MATURITY_BLOCKS`, so no pool was eligible and none earned it. Holding it instead would
    ///         hand the whole bootstrap-rate tranche to whichever pool was scored first, against F-1's equal
    ///         1/28 split; `accRewardPerScoreUnit == 0` is the sentinel that separates the two arms.
    function test_coldStartWindowIsForfeitedAsUnearned() public {
        assertEq(distributor.accRewardPerScoreUnit(), 0, "precondition: no accrual has ever completed");
        assertEq(distributor.totalScore(), 0, "precondition: no pool is scored");
        uint256 cursorBefore = distributor.lastAccrualBlock();

        vm.roll(block.number + 50_000);
        vm.prank(MALLORY);
        distributor.claim(POOL, MALLORY);

        assertGt(distributor.lastAccrualBlock(), cursorBefore, "cold-start cursor was held instead of advanced");
        assertEq(distributor.lastAccrualBlock(), block.number, "cold-start cursor did not reach the current block");
        assertEq(distributor.accRewardPerScoreUnit(), 0, "emission accrued with no eligible pool");
    }

    /// @notice The clamp (PP-D47): one call releases at most `MAX_ACCRUAL_SPAN_BLOCKS`, one epoch, so a
    ///         backlog drains across successive touches rather than landing in a single lump on whatever
    ///         scores happen to be live at that instant. The bound is what keeps a long lapse from being
    ///         both a gas-brick and a windfall. Two and a half epochs of gap therefore take exactly three
    ///         calls, and the first two land on exact epoch boundaries measured from the pre-gap cursor.
    function test_backlogDrainsOneEpochPerCall() public {
        ema.setTVLEMA(POOL, 1_000e18);
        distributor.recordScore(POOL);
        vm.roll(block.number + 1);
        distributor.recordScore(POOL);
        uint256 cursor0 = distributor.lastAccrualBlock();
        assertGt(distributor.accRewardPerScoreUnit(), 0, "control: an accrual completed before the gap");
        assertEq(cursor0, block.number, "control: the cursor is current before the gap");

        vm.roll(block.number + (AureumTime.BLOCKS_PER_EPOCH * 5) / 2);

        distributor.recordScore(POOL);
        assertEq(
            distributor.lastAccrualBlock(),
            cursor0 + AureumTime.BLOCKS_PER_EPOCH,
            "first call did not release exactly one epoch"
        );
        assertLt(distributor.lastAccrualBlock(), block.number, "the whole backlog drained in one call");

        distributor.recordScore(POOL);
        assertEq(
            distributor.lastAccrualBlock(),
            cursor0 + 2 * AureumTime.BLOCKS_PER_EPOCH,
            "second call did not release exactly one epoch"
        );

        distributor.recordScore(POOL);
        assertEq(distributor.lastAccrualBlock(), block.number, "third call did not finish the backlog");
    }

    /// @notice The two-sided conservation identity PP-D47's fix intent requires: over a held window plus its
    ///         drain, the accumulator's growth times the live score equals `_lpTrancheIntegral` over exactly
    ///         the drained range — forfeiture would fail it low, double-counting would fail it high. The
    ///         oracle is the contract's OWN integral read through the harness, so the test re-derives no
    ///         schedule arithmetic; only the 18-decimal scaling is restated, as `(x * 1e18) / y`, which is
    ///         `FixedPoint.divDown` verbatim per its source, keeping the expectation independent of the
    ///         library the accumulator uses. The closing re-call is the other side: once drained, the same
    ///         window must credit nothing further.
    function test_heldWindowIsCreditedInFullOnDrain() public {
        ema.setTVLEMA(POOL, 1_000e18);
        distributor.recordScore(POOL);
        vm.roll(block.number + 1_000);
        distributor.recordScore(POOL);
        uint256 accBeforeLapse = distributor.accRewardPerScoreUnit();
        assertGt(accBeforeLapse, 0, "control: an accrual completed before the lapse");

        ema.setTVLEMA(POOL, 0);
        distributor.recordScore(POOL);
        uint256 heldCursor = distributor.lastAccrualBlock();
        assertEq(distributor.totalScore(), 0, "score did not self-clear");

        vm.roll(block.number + 10_000);
        ema.setTVLEMA(POOL, 1_000e18);
        distributor.recordScore(POOL);
        assertEq(distributor.lastAccrualBlock(), heldCursor, "the score-restoring call drained early");
        assertEq(distributor.accRewardPerScoreUnit(), accBeforeLapse, "the score-restoring call moved the accumulator");

        uint256 denominator = distributor.totalScore();
        uint256 windowIntegral = distributor.extLpTrancheIntegral(heldCursor + 1, block.number);
        assertGt(windowIntegral, 0, "the held window integrates to nothing");

        distributor.recordScore(POOL);

        assertEq(distributor.lastAccrualBlock(), block.number, "the drain did not reach the current block");
        assertEq(
            distributor.accRewardPerScoreUnit() - accBeforeLapse,
            (windowIntegral * 1e18) / denominator,
            "the credited amount is not the integral over the held window"
        );

        uint256 accAfterDrain = distributor.accRewardPerScoreUnit();
        distributor.recordScore(POOL);
        assertEq(distributor.accRewardPerScoreUnit(), accAfterDrain, "the drained window was credited twice");
    }
}
