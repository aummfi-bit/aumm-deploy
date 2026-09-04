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

/// @title P1 D.1 — maturity is elapsed-block arithmetic with no sample-count floor
/// @notice Reproduction PoC for seam-1 root cause D.1 (High). A pump-seeded TVL EMA
///         refreshed once after 60 days of elapsed time still clears both the
///         EMASampler maturity gate and VotingWeight._positionPower freshness gate
///         at 96.7% of the attacker-chosen seed — two samples over the window,
///         not sixty.
contract P1_D1_SampleCountFloorTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant START_BLOCK = 2_000_000;
    uint256 internal constant PUMPED_TVL = 1_000_000e18;
    uint256 internal constant TRUE_TVL = 10_000e18;
    uint256 internal constant MATURITY_WINDOW = 60 * AureumTime.BLOCKS_PER_DAY;

    MockERC20 internal poolToken;
    MockTVLOracle internal oracle;
    EMASampler internal sampler;
    MockGaugeRegistry internal gaugeReg;
    MockMiliariumRegistry internal registry;
    MockRecorder internal recorder;
    VotingWeight internal vw;

    address internal holder;

    function setUp() public {
        vm.roll(START_BLOCK);

        poolToken = new MockERC20("Pool BPT", "BPT", 18);
        oracle = new MockTVLOracle();
        sampler = new EMASampler(oracle);
        gaugeReg = new MockGaugeRegistry();
        registry = new MockMiliariumRegistry();
        recorder = new MockRecorder();
        holder = makeAddr("p1_d1_holder");

        address pool = address(poolToken);
        gaugeReg.setApproved(pool, true);
        registry.setMiliarium(pool, true);
        address[] memory pools = new address[](1);
        pools[0] = pool;
        registry.setPoolList(pools);

        recorder.setEffectiveQualBlock(pool, holder, 1);
        recorder.setUserLP(pool, holder, 100e18);
        recorder.setPoolTotalLP(pool, 100e18);
        poolToken.mint(holder, 100e18);

        vw = new VotingWeight(
            IEMASampler(address(sampler)),
            gaugeReg,
            recorder,
            registry,
            GENESIS_BLOCK
        );
    }

    /// @notice The fix (D.1): a pool sampled only twice, sixty days apart, is REJECTED — not
    ///         because its EMA value is wrong (D.3's catch-up loop already converges it correctly
    ///         off the same elapsed window), but because `sampleCount` never cleared `MIN_SAMPLES`.
    ///         Maturity measured in TIME cannot distinguish two samples sixty days apart from sixty
    ///         daily ones; `sampleCount` is the quantity that can, and it is checked independently
    ///         of whatever the EMA arithmetic produces.
    function test_immatureEmaRejectedBelowMinSamples() public {
        address pool = address(poolToken);

        oracle.setTvl(pool, PUMPED_TVL);
        sampler.updateEMA(pool);
        assertEq(sampler.tvlEMA(pool), PUMPED_TVL, "cold-start seed is the raw spot assignment");

        oracle.setTvl(pool, TRUE_TVL);
        vm.roll(block.number + MATURITY_WINDOW);
        sampler.updateEMA(pool);

        // D.3 already converged the value correctly off this same elapsed window — the catch-up
        // loop applies the F-4 step once per elapsed day, so this is not what blocks the pool.
        assertLt(sampler.tvlEMA(pool), PUMPED_TVL / 5, "the EMA value itself is already correct");

        assertEq(sampler.sampleCount(pool), 2, "only two samples were ever taken");
        assertLt(sampler.sampleCount(pool), sampler.MIN_SAMPLES(), "below the D.1 floor");

        vw.poke(holder);
        assertEq(vw.governanceWeight(holder), 0, "fixed: two samples do not clear the floor");
    }

    /// @dev Control case — daily sampling over the same elapsed window converges away from the seed.
    function test_P1_D1_dailySamplingOverTheSameWindowConvergesAwayFromTheSeed() public {
        address pool = address(poolToken);

        oracle.setTvl(pool, PUMPED_TVL);
        sampler.updateEMA(pool);

        oracle.setTvl(pool, TRUE_TVL);
        uint256 seedBlock = sampler.emaSeedBlock(pool);
        uint256 blockCounter = seedBlock;
        for (uint256 i = 0; i < 60; ++i) {
            blockCounter += AureumTime.BLOCKS_PER_DAY;
            vm.roll(blockCounter);
            sampler.updateEMA(pool);
        }

        assertEq(block.number, seedBlock + MATURITY_WINDOW, "identical elapsed window to the defect case");
        assertLt(sampler.tvlEMA(pool), PUMPED_TVL / 5, "daily sampling leaves the EMA far below the seed");
    }
}
