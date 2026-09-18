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

    /// @dev PP-D52 (xii) — sixty daily samples on every pool in `pools`, which clears the D.1 sample
    ///      floor and the F-04 maturity window in one pass and leaves each stamp fresh. Spot values are
    ///      held constant, so the F-4 step returns each seed value unchanged. F10: the height is threaded
    ///      through an explicit counter, since via_ir hoists a block.number read out of a vm.roll loop.
    function _matureAll(address[] memory pools) private {
        uint256 blockCounter = block.number;
        for (uint256 d = 0; d < 60; ++d) {
            blockCounter += AureumTime.BLOCKS_PER_DAY;
            vm.roll(blockCounter);
            for (uint256 i = 0; i < pools.length; ++i) {
                sampler.updateEMA(pools[i]);
            }
        }
    }

    function _allThree() private view returns (address[] memory pools) {
        pools = new address[](3);
        pools[0] = poolA;
        pools[1] = poolB;
        pools[2] = poolZ;
    }

    /// @dev Regression (PP-D52 (xii), D.4): an immature EMA is now REFUSED by the multiplier, which
    ///      is the symmetry the finding was about — VotingWeight already scored this same EMA zero,
    ///      and the two consumers now agree instead of disagreeing. The matured leg is a positive
    ///      control: the gate discriminates on readiness rather than blocking outright, and once the
    ///      sample floor and maturity window are genuinely met the step lands at exactly the value
    ///      the pre-fix defect used to reach on a zero-block-old EMA.
    function test_multiplierGatesOnEmaMaturity() public {
        // poolA sits above the constellation mean so the matured positive control has a real intra
        // step to land; with all three equal the corrected divisor reads it neutral (PP-D57 (iii)).
        _seedPoolEma(poolA, 2 * SEEDED_EMA);
        _seedPoolEma(poolB, SEEDED_EMA);
        _seedPoolEma(poolZ, SEEDED_EMA);

        assertLt(
            block.number - sampler.emaSeedBlock(poolA),
            AureumTime.EMA_MATURITY_BLOCKS,
            "premise - the EMA is provably immature"
        );

        vw.poke(holder);
        assertEq(vw.governanceWeight(holder), 0, "sibling consumer rejects this immature EMA");

        vm.expectRevert(abi.encodeWithSelector(CCBMultiplier.EmaNotReady.selector, poolA));
        multiplier.updateMultiplier(poolA);
        assertEq(
            multiplier.getMultiplier(poolA),
            multiplier.INITIAL_MULTIPLIER(),
            "the refused call moved nothing"
        );

        // Positive control: mature the same three pools and the identical call now lands its step.
        _matureAll(_allThree());
        multiplier.updateMultiplier(poolA);
        uint256 step = multiplier.STEP_SIZE().toUint256();
        assertEq(
            multiplier.getMultiplier(poolA),
            multiplier.INITIAL_MULTIPLIER() - step,
            "matured, the intra channel steps down exactly as before the gate existed"
        );
    }

    /// @notice Regression (PP-D52 (xii) FIFTH, D.4): a per-pool baseline gives EVERY updater its
    ///         own global step, closing the gap the old single global slot opened — whoever updated
    ///         last would re-key the shared baseline to the just-observed aggregate, so the SECOND
    ///         updater in the same epoch compared the aggregate to itself and lost the global channel
    ///         entirely. Round 1 establishes each pool's OWN prior baseline (both cold-start, so both
    ///         read deltaGlobal = 0 regardless of call order). gaugeC then joins the roster and the
    ///         aggregate grows. Round 2 calls poolA then poolB in the SAME block: under the old
    ///         single-slot code, poolA's call would have re-keyed the shared baseline to the new
    ///         aggregate, and poolB's immediately following call would have compared that aggregate
    ///         to itself and read zero growth. Under the fix, poolB reads its OWN round-1 baseline —
    ///         untouched by poolA's write to a DIFFERENT mapping slot — and correctly detects the same
    ///         growth poolA did, taking the identical step.
    function test_perPoolBaselineGivesEveryUpdaterTheGlobalStep() public {
        // poolA and poolB sit above the Miliarium mean, so each takes a real intra step in both
        // rounds alongside the global step under test (PP-D57 (iii)).
        _seedPoolEma(poolA, 2 * SEEDED_EMA);
        _seedPoolEma(poolB, 2 * SEEDED_EMA);
        _seedPoolEma(poolZ, SEEDED_EMA);
        _seedPoolEma(gaugeC, SEEDED_EMA);
        address[] memory allFour = new address[](4);
        allFour[0] = poolA;
        allFour[1] = poolB;
        allFour[2] = poolZ;
        allFour[3] = gaugeC;
        _matureAll(allFour);

        // Round 1: gaugeC not yet in the roster. Both calls are cold-start on the global channel
        // (baseline[pool] == 0), so both take deltaGlobal = 0, isolating the intra step alone.
        multiplier.updateMultiplier(poolA);
        multiplier.updateMultiplier(poolB);

        uint256 step = multiplier.STEP_SIZE().toUint256();
        assertEq(
            multiplier.getMultiplier(poolA),
            multiplier.INITIAL_MULTIPLIER() - step,
            "round 1: cold-start global, intra step only"
        );
        assertEq(
            multiplier.getMultiplier(poolB),
            multiplier.INITIAL_MULTIPLIER() - step,
            "round 1: symmetric with poolA, same cold start"
        );

        // gaugeC joins the roster; the aggregate grows from 5x SEEDED_EMA to 6x. One epoch clears
        // both pools' cadence guards for round 2.
        address[] memory gauges = new address[](4);
        gauges[0] = poolA;
        gauges[1] = poolB;
        gauges[2] = poolZ;
        gauges[3] = gaugeC;
        gaugeReg.setGaugeList(gauges);
        vm.roll(block.number + AureumTime.BLOCKS_PER_EPOCH);

        // Round 2: poolA first, poolB immediately after, same block. Each reads its OWN round-1
        // baseline (5x SEEDED_EMA), not a slot the other's call could have overwritten.
        multiplier.updateMultiplier(poolA);
        multiplier.updateMultiplier(poolB);

        assertEq(
            multiplier.getMultiplier(poolA),
            multiplier.INITIAL_MULTIPLIER() - 3 * step,
            "round 2: poolA takes both the global step and the intra step"
        );
        assertEq(
            multiplier.getMultiplier(poolB),
            multiplier.INITIAL_MULTIPLIER() - 3 * step,
            "round 2: poolB, called second in the same block, takes the SAME global step"
        );
        assertEq(
            multiplier.getMultiplier(poolB) - multiplier.getMultiplier(poolA),
            0,
            "fixed: no gap, where the pre-fix defect read exactly one global step"
        );
    }
}
