// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {CCBMultiplier} from "src/ccb/CCBMultiplier.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

import {MockMiliariumRegistry, MockEMASampler, MockGaugeRegistry} from "test/unit/CCBMultiplier.t.sol";

/// @notice Regression for seam-1 root cause D.8 (Medium), inverted from its PP3.2 reproduction per
///         PP-D57 (iii). The constellation mean divided a sum walked over the live pool count by the
///         literal 28, so a pool at the true mean was stepped down every epoch and reached CLAMP_FLOOR
///         in five; it now divides by the `poolCount` the loop walks, and the literal is deleted. The
///         equal-leg divisor at `EmissionDistributor.sol` L599 is PP-D57 (iv)'s site and is not
///         exercised by this file. C.7 shares this row's redeploy unit.
contract P1_D8_MeanDivisorIsALiteralNotTheLengthWalkedTest is Test {
    uint256 internal constant START_BLOCK = AureumTime.EMA_MATURITY_BLOCKS + 200_000;
    uint256 internal constant EPOCH_1_BLOCK = START_BLOCK;
    uint256 internal constant EPOCH_2_BLOCK = START_BLOCK + AureumTime.BLOCKS_PER_EPOCH;
    uint256 internal constant EPOCH_3_BLOCK = START_BLOCK + 2 * AureumTime.BLOCKS_PER_EPOCH;
    uint256 internal constant EPOCH_4_BLOCK = START_BLOCK + 3 * AureumTime.BLOCKS_PER_EPOCH;
    uint256 internal constant EPOCH_5_BLOCK = START_BLOCK + 4 * AureumTime.BLOCKS_PER_EPOCH;
    uint256 internal constant LIVE_POOL_COUNT = 26;
    uint256 internal constant MAX_POOL_COUNT = 28;
    uint256 internal constant GAUGE_COUNT = MAX_POOL_COUNT + 1;
    // Every pool carries the same EMA, so the pool under test sits at the exact mean of any
    // Miliarium roster it is listed on, and the global aggregate never moves between epochs.
    uint256 internal constant TVL_EMA = 1_000e18;

    CCBMultiplier internal multiplier;
    MockMiliariumRegistry internal miliReg;
    MockEMASampler internal ema;
    MockGaugeRegistry internal gauges;

    address[] internal pools;
    address internal nonMiliariumGauge;

    function setUp() public {
        miliReg = new MockMiliariumRegistry();
        ema = new MockEMASampler();
        gauges = new MockGaugeRegistry();
        multiplier = new CCBMultiplier(miliReg, ema, gauges);

        address[] memory gaugeList = new address[](GAUGE_COUNT);
        for (uint256 i = 0; i < MAX_POOL_COUNT; i++) {
            pools.push(address(uint160(0xA00001 + i)));
            miliReg.setMiliarium(pools[i], true);
            gauges.setApproved(pools[i], true);
            ema.setTVLEMA(pools[i], TVL_EMA);
            gaugeList[i] = pools[i];
        }
        // A non-Miliarium gauge, present only so the gauge count differs from every Miliarium
        // count walked; per PP-D57 (ix) its number carries no protocol meaning.
        nonMiliariumGauge = makeAddr("nonMiliariumGauge");
        gauges.setApproved(nonMiliariumGauge, true);
        ema.setTVLEMA(nonMiliariumGauge, TVL_EMA);
        gaugeList[MAX_POOL_COUNT] = nonMiliariumGauge;
        gauges.setGaugeList(gaugeList);
        _listFirst(LIVE_POOL_COUNT);

        vm.roll(START_BLOCK);
    }

    /// @notice Inverts the reproduction that asserted a step down: a pool sitting exactly at the true
    ///         26-pool mean is now neutral, because the mean divides by the 26 entries walked.
    function test_P1_D8_aPoolAtTheTrueConstellationMeanIsNotStepped() public {
        assertEq(miliReg.miliariumPoolsCount(), LIVE_POOL_COUNT, "premise - the loop walks 26 pools");

        uint256 aggregate;
        for (uint256 i = 0; i < LIVE_POOL_COUNT; i++) {
            aggregate += ema.tvlEMA(pools[i]);
        }
        address subject = pools[0];
        assertEq(ema.tvlEMA(subject), aggregate / LIVE_POOL_COUNT, "premise - the subject sits at the true mean");

        vm.roll(EPOCH_1_BLOCK);
        multiplier.updateMultiplier(subject);

        assertEq(
            multiplier.getMultiplier(subject),
            multiplier.INITIAL_MULTIPLIER(),
            "a pool at the true mean is neutral; the rule reads the mean of the pools it walked"
        );
    }

    /// @notice Inverts the reproduction that drove the average pool to CLAMP_FLOOR in five epochs:
    ///         across the same five permissionless updates it holds INITIAL_MULTIPLIER. The first call
    ///         takes the cold-start global sentinel and every later call reads an unchanged aggregate,
    ///         so the global channel is neutral throughout and the intra channel is the term under test.
    function test_P1_D8_theAveragePoolHoldsItsMultiplierAcrossFiveEpochs() public {
        address subject = pools[0];

        vm.roll(EPOCH_1_BLOCK);
        multiplier.updateMultiplier(subject);
        vm.roll(EPOCH_2_BLOCK);
        multiplier.updateMultiplier(subject);
        vm.roll(EPOCH_3_BLOCK);
        multiplier.updateMultiplier(subject);
        vm.roll(EPOCH_4_BLOCK);
        multiplier.updateMultiplier(subject);
        vm.roll(EPOCH_5_BLOCK);
        multiplier.updateMultiplier(subject);

        assertEq(
            multiplier.getMultiplier(subject),
            multiplier.INITIAL_MULTIPLIER(),
            "the average pool holds INITIAL_MULTIPLIER after the fifth epoch update"
        );
    }

    /// @notice D.8's done-criteria per PP-D57 (iii) and (ix): at every Miliarium roster size from one
    ///         pool to twenty-eight, a pool at the exact mean of the pools walked is neutral. With every
    ///         EMA equal, the mean lands on the common EMA only when the divisor equals the count
    ///         walked; any other integer divisor misses it by at least one part in twenty-nine against a
    ///         0.1% dead zone, stepping the pool down when the divisor is larger and up when it is
    ///         smaller. The gauge roster stays fixed at twenty-nine, so a divisor reading the sibling
    ///         gauge count fails at every size, and a literal divisor fails at every size but its own.
    ///         A fresh multiplier per size keeps every call on the cold-start global sentinel, so only
    ///         the intra channel can move. The closing positive control proves that channel live, so
    ///         the neutrality is earned rather than vacuous.
    function test_meanDivisorEqualsLengthWalked() public {
        address subject = pools[0];
        assertEq(gauges.gaugeCount(), GAUGE_COUNT, "premise - the gauge roster holds 29, a count no Miliarium size equals");

        for (uint256 n = 1; n <= MAX_POOL_COUNT; n++) {
            _listFirst(n);
            CCBMultiplier fresh = new CCBMultiplier(miliReg, ema, gauges);
            fresh.updateMultiplier(subject);
            assertEq(
                fresh.getMultiplier(subject),
                fresh.INITIAL_MULTIPLIER(),
                "a pool at the mean of the pools walked is neutral at every roster size"
            );
        }

        // Doubling the subject's EMA against twenty-five peers puts it at 52/27 of the mean.
        _listFirst(LIVE_POOL_COUNT);
        ema.setTVLEMA(subject, 2 * TVL_EMA);
        CCBMultiplier control = new CCBMultiplier(miliReg, ema, gauges);
        control.updateMultiplier(subject);
        assertEq(
            control.getMultiplier(subject),
            control.INITIAL_MULTIPLIER() - uint256(control.STEP_SIZE()),
            "positive control - a pool far above the mean steps down"
        );
    }

    /// @dev Lists the first `n` provisioned pools on the Miliarium roster only; the gauge roster is
    ///      seated once in `setUp` and never follows it.
    function _listFirst(uint256 n) internal {
        address[] memory listed = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            listed[i] = pools[i];
        }
        miliReg.setPoolList(listed);
    }
}
