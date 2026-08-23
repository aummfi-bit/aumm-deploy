// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {CCBMultiplier} from "src/ccb/CCBMultiplier.sol";
import {EMASampler} from "src/ccb/EMASampler.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {VotingWeight} from "src/governance/VotingWeight.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {MockTVLOracle} from "test/unit/EMASampler.t.sol";
import {MockGaugeRegistry, MockMiliariumRegistry, MockRecorder} from "test/unit/VotingWeight.t.sol";

/// @title P1 D.4 — CCBMultiplier consumes tvlEMA without maturity or freshness gates
/// @notice Reproduction PoC for seam-1 root cause D.4 (Medium). CCBMultiplier reads
///         emaSampler.tvlEMA at :213, :228 and :232 with none of the gates
///         EmissionDistributor._gatedTvlEMA applies at :457-463, and a per-pool cadence
///         guards a global baseline so the second updater in a block loses the global
///         channel entirely.
contract P1_D4_UngatedMultiplierTest is Test {
    using SafeCast for int256;

    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant START_BLOCK = 2_000_000;
    uint256 internal constant SEEDED_EMA = 1_000_000e18;

    MockERC20 internal poolTokenA;
    MockTVLOracle internal oracle;
    EMASampler internal sampler;
    CCBMultiplier internal multiplier;
    MockGaugeRegistry internal gaugeReg;
    MockMiliariumRegistry internal registry;
    MockRecorder internal recorder;
    VotingWeight internal vw;

    address internal poolA;
    address internal poolB;
    address internal poolZ;
    address internal gaugeC;
    address internal holder;

    function setUp() public {
        vm.roll(START_BLOCK);

        poolTokenA = new MockERC20("Pool A BPT", "BPTA", 18);
        poolA = address(poolTokenA);
        poolB = makeAddr("poolB");
        poolZ = makeAddr("poolZ");
        gaugeC = makeAddr("gaugeC");
        holder = makeAddr("p1_d4_holder");

        oracle = new MockTVLOracle();
        sampler = new EMASampler(oracle);
        gaugeReg = new MockGaugeRegistry();
        registry = new MockMiliariumRegistry();
        recorder = new MockRecorder();

        multiplier = new CCBMultiplier(registry, IEMASampler(address(sampler)), gaugeReg);

        registry.setMiliarium(poolA, true);
        registry.setMiliarium(poolB, true);
        registry.setMiliarium(poolZ, true);
        address[] memory pools = new address[](3);
        pools[0] = poolA;
        pools[1] = poolB;
        pools[2] = poolZ;
        registry.setPoolList(pools);

        address[] memory gauges = new address[](3);
        gauges[0] = poolA;
        gauges[1] = poolB;
        gauges[2] = poolZ;
        gaugeReg.setGaugeList(gauges);
        gaugeReg.setApproved(poolA, true);

        recorder.setEffectiveQualBlock(poolA, holder, 1);
        recorder.setUserLP(poolA, holder, 100e18);
        recorder.setPoolTotalLP(poolA, 100e18);
        poolTokenA.mint(holder, 100e18);

        vw = new VotingWeight(
            IEMASampler(address(sampler)),
            gaugeReg,
            recorder,
            registry,
            GENESIS_BLOCK
        );
    }

    function _seedPoolEma(address pool, uint256 tvl) private {
        oracle.setTvl(pool, tvl);
        sampler.updateEMA(pool);
    }

    /// @dev Defect case — an immature EMA moves the multiplier while VotingWeight scores it zero.
    function test_P1_D4_immatureEmaMovesTheMultiplierWhileVotingWeightScoresItZero() public {
        _seedPoolEma(poolA, SEEDED_EMA);
        _seedPoolEma(poolB, SEEDED_EMA);
        _seedPoolEma(poolZ, SEEDED_EMA);

        assertLt(
            block.number - sampler.emaSeedBlock(poolA),
            60 * AureumTime.BLOCKS_PER_DAY,
            "EMA is provably immature by the EmissionDistributor gate threshold"
        );

        vw.poke(holder);
        assertEq(vw.governanceWeight(holder), 0, "sibling consumer rejects this immature EMA");

        multiplier.updateMultiplier(poolA);

        uint256 step = multiplier.STEP_SIZE().toUint256();
        assertEq(
            multiplier.getMultiplier(poolA),
            multiplier.INITIAL_MULTIPLIER() - step,
            "multiplier moved a full step on a zero-block-old immature EMA"
        );
    }

    /// @dev Cadence case — per-pool guard on a global baseline drops the second updater's global step.
    function test_P1_D4_perPoolCadenceGuardsAGlobalBaselineSoTheSecondUpdaterLosesTheGlobalStep() public {
        _seedPoolEma(poolA, SEEDED_EMA);
        _seedPoolEma(poolB, SEEDED_EMA);
        _seedPoolEma(poolZ, SEEDED_EMA);

        multiplier.updateMultiplier(poolZ);

        _seedPoolEma(gaugeC, SEEDED_EMA);
        address[] memory gauges = new address[](4);
        gauges[0] = poolA;
        gauges[1] = poolB;
        gauges[2] = poolZ;
        gauges[3] = gaugeC;
        gaugeReg.setGaugeList(gauges);

        multiplier.updateMultiplier(poolA);
        multiplier.updateMultiplier(poolB);

        uint256 step = multiplier.STEP_SIZE().toUint256();
        assertEq(
            multiplier.getMultiplier(poolA),
            multiplier.INITIAL_MULTIPLIER() - 2 * step,
            "first updater took both global and intra steps"
        );
        assertEq(
            multiplier.getMultiplier(poolB),
            multiplier.INITIAL_MULTIPLIER() - step,
            "second updater lost the global step to the overwritten baseline"
        );
        assertEq(
            multiplier.getMultiplier(poolB) - multiplier.getMultiplier(poolA),
            step,
            "gap is exactly one global step lost to per-pool cadence"
        );
    }
}
