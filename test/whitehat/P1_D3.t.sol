// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {EMASampler} from "src/ccb/EMASampler.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {VotingWeight} from "src/governance/VotingWeight.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {MockTVLOracle} from "test/unit/EMASampler.t.sol";
import {MockGaugeRegistry, MockMiliariumRegistry, MockRecorder} from "test/unit/VotingWeight.t.sol";

/// @title P1 D.3 — freshness gate certifies sampling cadence, not value
/// @notice Reproduction PoC for seam-1 root cause D.3 (Medium). Decay applies once per
///         updateEMA call while the freshness gate at VotingWeight.sol:168 measures
///         elapsed blocks since the last call, so fortnightly sampling at the gate's
///         maximum spacing keeps a drained pool certified fresh with an EMA roughly
///         fifty times its true TVL.
contract P1_D3_FreshnessCertifiesSamplingTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant START_BLOCK = 2_000_000;
    uint256 internal constant PRE_DRAIN_TVL = 1_000_000e18;
    uint256 internal constant DRAINED_TVL = 10_000e18;
    uint256 internal constant DAY_COUNT = 294;
    uint256 internal constant SPARSE_INTERVAL = 14;

    MockERC20 internal poolTokenA;
    MockERC20 internal poolTokenB;
    MockTVLOracle internal oracle;
    EMASampler internal sampler;
    MockGaugeRegistry internal gaugeReg;
    MockMiliariumRegistry internal registry;
    MockRecorder internal recorder;
    VotingWeight internal vw;

    address internal holder;

    function setUp() public {
        vm.roll(START_BLOCK);

        poolTokenA = new MockERC20("Pool A BPT", "BPTA", 18);
        poolTokenB = new MockERC20("Pool B BPT", "BPTB", 18);
        oracle = new MockTVLOracle();
        sampler = new EMASampler(oracle);
        gaugeReg = new MockGaugeRegistry();
        registry = new MockMiliariumRegistry();
        recorder = new MockRecorder();
        holder = makeAddr("p1_d3_holder");

        address poolA = address(poolTokenA);
        address poolB = address(poolTokenB);

        gaugeReg.setApproved(poolA, true);
        registry.setMiliarium(poolA, true);
        address[] memory pools = new address[](1);
        pools[0] = poolA;
        registry.setPoolList(pools);

        recorder.setEffectiveQualBlock(poolA, holder, 1);
        recorder.setEffectiveQualBlock(poolB, holder, 1);
        recorder.setUserLP(poolA, holder, 100e18);
        recorder.setUserLP(poolB, holder, 100e18);
        recorder.setPoolTotalLP(poolA, 100e18);
        recorder.setPoolTotalLP(poolB, 100e18);
        poolTokenA.mint(holder, 100e18);
        poolTokenB.mint(holder, 100e18);

        vw = new VotingWeight(
            IEMASampler(address(sampler)),
            gaugeReg,
            recorder,
            registry,
            GENESIS_BLOCK
        );
    }

    /// @notice The fix (D.3): decay tracks ELAPSED TIME, not call count. A pool sampled once a
    ///         fortnight and a pool sampled daily, over the same 294-day window against the same
    ///         drained spot, converge to the IDENTICAL EMA — the catch-up loop replays the F-4
    ///         steps the sparse pool's own calls skipped, so sparse sampling can no longer hold a
    ///         stale valuation aloft while `lastEMAUpdateBlock` reads fresh. Equality is EXACT, not
    ///         approximate: 294 applications of the same step to the same start with the same
    ///         constant spot give the same result whether batched 14-at-a-time or taken one daily.
    function test_sparseAndDailySamplingConvergeIdentically() public {
        address poolA = address(poolTokenA);
        address poolB = address(poolTokenB);

        oracle.setTvl(poolA, PRE_DRAIN_TVL);
        oracle.setTvl(poolB, PRE_DRAIN_TVL);
        sampler.updateEMA(poolA);
        sampler.updateEMA(poolB);

        oracle.setTvl(poolA, DRAINED_TVL);
        oracle.setTvl(poolB, DRAINED_TVL);

        uint256 blockCounter = sampler.emaSeedBlock(poolA);
        for (uint256 i = 1; i <= DAY_COUNT; ++i) {
            blockCounter += AureumTime.BLOCKS_PER_DAY;
            vm.roll(blockCounter);
            sampler.updateEMA(poolB);
            if (i % SPARSE_INTERVAL == 0) {
                sampler.updateEMA(poolA);
            }
        }

        assertEq(
            sampler.lastEMAUpdateBlock(poolA),
            sampler.lastEMAUpdateBlock(poolB),
            "both pools share the same freshness anchor block"
        );
        assertEq(
            sampler.tvlEMA(poolA),
            sampler.tvlEMA(poolB),
            "D.3 fixed - same elapsed window, same EMA, regardless of sampling cadence"
        );
        assertLt(
            sampler.tvlEMA(poolA),
            (DRAINED_TVL * 101) / 100,
            "D.3 fixed - the sparse pool converged onto the drained truth"
        );
    }

    /// @notice The fix (D.3), the mechanism stated directly: over ONE identical elapsed window,
    ///         one call and two calls produce the SAME EMA. The catch-up loop applies the F-4 step
    ///         once per elapsed day rather than once per call, so `lastEMAUpdateBlock` now certifies
    ///         a value as well as a cadence. Before this, poolB's extra call decayed it strictly
    ///         further than poolA over the very same 28 days.
    function test_emaDecaysWithElapsedTime() public {
        address poolA = address(poolTokenA);
        address poolB = address(poolTokenB);

        oracle.setTvl(poolA, PRE_DRAIN_TVL);
        oracle.setTvl(poolB, PRE_DRAIN_TVL);
        sampler.updateEMA(poolA);
        sampler.updateEMA(poolB);

        oracle.setTvl(poolA, DRAINED_TVL);
        oracle.setTvl(poolB, DRAINED_TVL);

        uint256 blockCounter = sampler.emaSeedBlock(poolA);

        // poolB samples at the midpoint; poolA does not.
        blockCounter += AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(blockCounter);
        sampler.updateEMA(poolB);

        // Both sample at the end of the same 28-day window.
        blockCounter += AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(blockCounter);
        sampler.updateEMA(poolA);
        sampler.updateEMA(poolB);

        assertEq(
            sampler.tvlEMA(poolA),
            sampler.tvlEMA(poolB),
            "D.3 fixed - one call and two calls decay identically over the same elapsed window"
        );
        assertEq(
            sampler.lastEMAUpdateBlock(poolA),
            sampler.lastEMAUpdateBlock(poolB),
            "identical freshness reading at the same final block"
        );
        assertEq(sampler.sampleCount(poolA), 2, "poolA took two calls in total");
        assertEq(sampler.sampleCount(poolB), 3, "poolB took three, and it bought no extra decay");
    }
}
