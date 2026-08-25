// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {CCBMultiplier} from "src/ccb/CCBMultiplier.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

import {MockMiliariumRegistry, MockEMASampler, MockGaugeRegistry} from "test/unit/CCBMultiplier.t.sol";

/// @notice Reproduction PoC for seam-1 root cause D.8 (Medium). The constellation mean
///         divides a sum walked over the live pool count by the literal 28, so a pool at
///         the true mean is stepped down every epoch. The twin literal at
///         `EmissionDistributor.sol` L482 is share-neutral at alpha zero and mis-calibrates
///         the F-3 transition and is NOT reproduced here. C.7 shares this row's redeploy unit.
contract P1_D8_MeanDivisorIsALiteralNotTheLengthWalkedTest is Test {
    uint256 internal constant START_BLOCK = 200_000;
    uint256 internal constant BLOCKS_PER_EPOCH = 100_800;
    uint256 internal constant EPOCH_1_BLOCK = START_BLOCK;
    uint256 internal constant EPOCH_2_BLOCK = START_BLOCK + BLOCKS_PER_EPOCH;
    uint256 internal constant EPOCH_3_BLOCK = START_BLOCK + 2 * BLOCKS_PER_EPOCH;
    uint256 internal constant EPOCH_4_BLOCK = START_BLOCK + 3 * BLOCKS_PER_EPOCH;
    uint256 internal constant EPOCH_5_BLOCK = START_BLOCK + 4 * BLOCKS_PER_EPOCH;
    uint256 internal constant LIVE_POOL_COUNT = 26;
    // Held constant across every updateMultiplier call so the global aggregate does not move
    // between epochs and the global delta contributes nothing; only the intra term is under test.
    uint256 internal constant TVL_EMA = 1_000e18;

    CCBMultiplier internal multiplier;
    MockMiliariumRegistry internal miliReg;
    MockEMASampler internal ema;
    MockGaugeRegistry internal gauges;

    address[] internal pools;

    function setUp() public {
        miliReg = new MockMiliariumRegistry();
        ema = new MockEMASampler();
        gauges = new MockGaugeRegistry();
        multiplier = new CCBMultiplier(miliReg, ema, gauges);

        // Loop at CCBMultiplier.sol L224-L227 walks miliariumPoolsCount (26) while L231 divides
        // by MILIARIUM_POOL_COUNT (28), so the computed mean is understated by 1 - 26/28 = 7.143%,
        // against a DEAD_ZONE of 1e15 (0.1%) — an error 71 times the dead zone.
        for (uint256 i = 0; i < LIVE_POOL_COUNT; i++) {
            pools.push(address(uint160(0xA00001 + i)));
        }
        miliReg.setPoolList(pools);
        gauges.setGaugeList(pools);
        for (uint256 i = 0; i < LIVE_POOL_COUNT; i++) {
            miliReg.setMiliarium(pools[i], true);
            gauges.setApproved(pools[i], true);
            ema.setTVLEMA(pools[i], TVL_EMA);
        }

        vm.roll(START_BLOCK);
    }

    /// @notice A pool sitting exactly at the true 26-pool mean is stepped down because the
    ///         anti-cyclical rule divides by the literal 28.
    function test_P1_D8_aPoolAtTheTrueConstellationMeanIsSteppedDownAnyway() public {
        uint256 literalCount = multiplier.MILIARIUM_POOL_COUNT();
        uint256 deadZone = multiplier.DEAD_ZONE();
        int256 stepSize = multiplier.STEP_SIZE();
        uint256 initial = multiplier.INITIAL_MULTIPLIER();

        assertEq(miliReg.miliariumPoolsCount(), LIVE_POOL_COUNT, "pool count walked is 26");
        assertTrue(LIVE_POOL_COUNT != literalCount, "walked count differs from MILIARIUM_POOL_COUNT");

        uint256 aggregate;
        for (uint256 i = 0; i < LIVE_POOL_COUNT; i++) {
            aggregate += ema.tvlEMA(pools[i]);
        }
        uint256 trueMean = aggregate / LIVE_POOL_COUNT;
        address subject = pools[0];
        uint256 poolEMA = ema.tvlEMA(subject);
        assertEq(poolEMA, trueMean, "pool EMA equals the true constellation mean exactly");

        uint256 upperTrue = (trueMean * (1e18 + deadZone)) / 1e18;
        uint256 lowerTrue = (trueMean * (1e18 - deadZone)) / 1e18;
        assertTrue(
            poolEMA >= lowerTrue && poolEMA <= upperTrue,
            "pool EMA lies inside the dead zone around the TRUE mean a correct divisor would use"
        );

        vm.roll(EPOCH_1_BLOCK);
        multiplier.updateMultiplier(subject);

        assertEq(
            multiplier.getMultiplier(subject),
            initial - uint256(stepSize),
            "stepped down despite being exactly average; the anti-cyclical rule is reading a mean that is 7.143 percent low"
        );
    }

    /// @notice Five permissionless epoch steps drive the average pool from INITIAL to CLAMP_FLOOR.
    function test_P1_D8_theAveragePoolIsDrivenToTheClampFloorInFiveEpochs() public {
        address subject = pools[0];
        int256 floor_ = multiplier.CLAMP_FLOOR();
        int256 ceiling_ = multiplier.CLAMP_CEILING();

        assertEq(
            uint256(ceiling_) * 3,
            uint256(floor_) * 5,
            "CLAMP_CEILING is one and two thirds of CLAMP_FLOOR"
        );

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
            int256(multiplier.getMultiplier(subject)),
            floor_,
            "multiplier lands on CLAMP_FLOOR after the fifth epoch update"
        );
        assertEq(
            5 * AureumTime.BLOCKS_PER_EPOCH,
            5 * BLOCKS_PER_EPOCH,
            "five epochs is five times AureumTime.BLOCKS_PER_EPOCH (roughly seventy days)"
        );
    }
}
