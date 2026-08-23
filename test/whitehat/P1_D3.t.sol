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

    /// @dev Defect case — fortnightly sampling keeps a drained pool fresh and fiftyfold overstated.
    function test_P1_D3_fortnightlySamplingKeepsADrainedPoolFreshAndFiftyFoldOverstated() public {
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
        assertLe(
            block.number - sampler.lastEMAUpdateBlock(poolA),
            AureumTime.BLOCKS_PER_EPOCH,
            "sparse pool elapsed since update is within the freshness gate"
        );
        assertLt(sampler.tvlEMA(poolB), PRE_DRAIN_TVL / 50, "daily-sampled pool converged toward truth");
        assertGt(sampler.tvlEMA(poolA), (PRE_DRAIN_TVL * 45) / 100, "sparse pool still above 45% of pre-drain");
        assertGt(sampler.tvlEMA(poolA), sampler.tvlEMA(poolB) * 40, "sparse pool exceeds daily pool by fortyfold");

        vw.poke(holder);
        assertGt(vw.governanceWeight(holder), 0, "drained sparse pool confers live governance weight");
    }

    /// @dev Mechanism case — decay is per call, not per elapsed time, over the same window.
    function test_P1_D3_decayIsPerCallNotPerElapsedTime() public {
        address poolA = address(poolTokenA);
        address poolB = address(poolTokenB);

        oracle.setTvl(poolA, PRE_DRAIN_TVL);
        oracle.setTvl(poolB, PRE_DRAIN_TVL);
        sampler.updateEMA(poolA);
        sampler.updateEMA(poolB);

        oracle.setTvl(poolA, DRAINED_TVL);
        oracle.setTvl(poolB, DRAINED_TVL);

        uint256 blockCounter = sampler.emaSeedBlock(poolA);
        uint256 alphaNum = sampler.EMA_ALPHA_NUMERATOR();
        uint256 alphaDen = sampler.EMA_ALPHA_DENOMINATOR();

        blockCounter += AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(blockCounter);
        sampler.updateEMA(poolB);

        uint256 oneStep = (alphaNum * DRAINED_TVL + (alphaDen - alphaNum) * PRE_DRAIN_TVL) / alphaDen;

        blockCounter += AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(blockCounter);
        sampler.updateEMA(poolA);
        sampler.updateEMA(poolB);

        uint256 twoStep = (alphaNum * DRAINED_TVL + (alphaDen - alphaNum) * oneStep) / alphaDen;

        assertEq(sampler.tvlEMA(poolA), oneStep, "poolA took one post-drain sample");
        assertEq(sampler.tvlEMA(poolB), twoStep, "poolB took two post-drain samples");
        assertLt(sampler.tvlEMA(poolB), sampler.tvlEMA(poolA), "more calls decay further over the same elapsed time");
        assertEq(
            sampler.lastEMAUpdateBlock(poolA),
            sampler.lastEMAUpdateBlock(poolB),
            "identical freshness reading at the same final block"
        );
    }
}
