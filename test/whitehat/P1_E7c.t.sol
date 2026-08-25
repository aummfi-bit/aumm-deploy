// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {EmissionDistributorHarness} from "test/unit/harness/EmissionDistributorHarness.sol";

import {IAuMM} from "src/token/IAuMM.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";

import {MockAuMM, MockEMASampler, MockCCBMultiplier, MockMiliariumRegistry} from "test/unit/EmissionDistributor.t.sol";
import {MockEfficiencyOracle} from "test/fork/mocks/StageGMocks.sol";

/// @notice Minimal gauge-registry double for E.7c: only the two views `recordScore` reads.
contract CappedGaugeRegistry {
    mapping(address => bool) public approved;
    mapping(address => uint256) public capBps;

    function setApproved(address pool, bool flag) external {
        approved[pool] = flag;
    }

    function setCapBps(address pool, uint256 bps) external {
        capBps[pool] = bps;
    }

    function isGaugeApproved(address pool) external view returns (bool) {
        return approved[pool];
    }

    function poolEmissionCapBps(address pool) external view returns (uint256) {
        return capBps[pool];
    }
}

/// @notice Reproduction PoC for seam-1 root cause E.7c (Medium). The clamp at
///         `EmissionDistributor.sol` L495 multiplies by `totalScore` minus the pool's old
///         effective score as read in the caller's block, so the cap is solved against a
///         caller-chosen denominator and then latched. E.7a and E.7b are the other two F-16
///         faces and live on the tournament path rather than here.
contract P1_E7c_CapLatchedAgainstACallerChosenDenominatorTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant SCORE_BLOCK = GENESIS_BLOCK + 2_628_000 + 1;
    uint256 internal constant CAP_BPS = 100; // 1%
    uint256 internal constant CAP_FP = CAP_BPS * 1e14; // 1e16 in 1e18 fixed-point
    uint256 internal constant MOVER_TVL_LARGE = 10_000e18;
    uint256 internal constant MOVER_TVL_SMALL = 100e18;
    uint256 internal constant CAPPED_TVL = 1_000e18;

    address internal constant GOV = address(0x9011);
    address internal constant MOVER = address(0xA001);
    address internal constant CAPPED_A = address(0xA002);
    address internal constant CAPPED_B = address(0xA003);

    MockAuMM internal aumm;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockMiliariumRegistry internal miliReg;
    MockEfficiencyOracle internal effOracle;
    CappedGaugeRegistry internal gauges;
    EmissionDistributorHarness internal distributor;

    function setUp() public {
        aumm = new MockAuMM();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        miliReg = new MockMiliariumRegistry();
        effOracle = new MockEfficiencyOracle();
        gauges = new CappedGaugeRegistry();

        distributor = new EmissionDistributorHarness(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK,
            GOV
        );

        gauges.setApproved(MOVER, true);
        gauges.setApproved(CAPPED_A, true);
        gauges.setApproved(CAPPED_B, true);
        gauges.setCapBps(CAPPED_A, CAP_BPS);
        gauges.setCapBps(CAPPED_B, CAP_BPS);

        mult.setMultiplier(MOVER, 1e18);
        mult.setMultiplier(CAPPED_A, 1e18);
        mult.setMultiplier(CAPPED_B, 1e18);

        vm.roll(SCORE_BLOCK);
    }

    /// @notice The latched poolScore stays put while totalScore falls, so the realised share
    ///         drifts above the cap without any re-score of the capped pool.
    function test_P1_E7c_latchedCapDriftsAboveTheCapWhenTheDenominatorLaterFalls() public {
        ema.setTVLEMA(MOVER, MOVER_TVL_LARGE);
        distributor.recordScore(MOVER);

        ema.setTVLEMA(CAPPED_A, CAPPED_TVL);
        distributor.recordScore(CAPPED_A);

        uint256 latched = distributor.poolScore(CAPPED_A);
        uint256 shareAtLatch = (latched * 1e18) / distributor.totalScore();
        assertApproxEqAbs(
            shareAtLatch,
            CAP_FP,
            10,
            "at latch time the realised share equals the cap within a few wei"
        );

        ema.setTVLEMA(MOVER, MOVER_TVL_SMALL);
        distributor.recordScore(MOVER);

        assertEq(
            distributor.poolScore(CAPPED_A),
            latched,
            "capped poolScore is unchanged; the capped pool was never re-scored"
        );

        uint256 shareAfterFall = (latched * 1e18) / distributor.totalScore();
        assertGt(
            shareAfterFall,
            CAP_FP,
            "realised share exceeds the cap after the denominator moved"
        );
    }

    /// @notice Two identical capped pools latch different scores because recordScore is
    ///         permissionless and the caller chooses the denominator each pool sees.
    function test_P1_E7c_theSameCapYieldsADifferentLatchDependingOnWhenItIsClaimed() public {
        ema.setTVLEMA(MOVER, MOVER_TVL_LARGE);
        distributor.recordScore(MOVER);

        ema.setTVLEMA(CAPPED_A, CAPPED_TVL);
        distributor.recordScore(CAPPED_A);
        uint256 latchFirst = distributor.poolScore(CAPPED_A);

        ema.setTVLEMA(MOVER, MOVER_TVL_SMALL);
        distributor.recordScore(MOVER);

        ema.setTVLEMA(CAPPED_B, CAPPED_TVL);
        distributor.recordScore(CAPPED_B);
        uint256 latchSecond = distributor.poolScore(CAPPED_B);

        assertEq(gauges.poolEmissionCapBps(CAPPED_A), gauges.poolEmissionCapBps(CAPPED_B), "identical cap bps");
        assertEq(ema.tvlEMA(CAPPED_A), ema.tvlEMA(CAPPED_B), "identical TVL EMA inputs");
        assertEq(mult.getMultiplier(CAPPED_A), mult.getMultiplier(CAPPED_B), "identical multiplier inputs");

        assertGt(
            latchFirst,
            latchSecond,
            "recordScore is permissionless so the caller selects the denominator; the cap bounds nothing on its own"
        );
    }
}
