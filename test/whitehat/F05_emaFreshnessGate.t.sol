// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {VotingWeight} from "src/governance/VotingWeight.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {MockEMASampler, MockGaugeRegistry, MockRecorder, MockMiliariumRegistry} from "test/unit/VotingWeight.t.sol";

/// @notice F-05 fix regression (WK-R.5) — `VotingWeight._positionPower` now also requires the pool's TVL EMA
///         to be fresh: a mature seed whose `lastEMAUpdateBlock` is older than EMA_STALENESS_BLOCKS (one epoch
///         / 14 days) confers zero governance weight. The 60-day maturity gate guards seed AGE; this guards
///         seed FRESHNESS, so a pumped-then-abandoned EMA cannot vote on a stale stored value.
contract F05_EmaFreshnessGateTest is Test {
    MockEMASampler internal emaSampler;
    MockGaugeRegistry internal gaugeReg;
    MockRecorder internal recorder;
    MockMiliariumRegistry internal registry;
    VotingWeight internal vw;

    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant START_BLOCK = 2_000_000;
    uint256 internal constant EMA_MATURITY = 60 * AureumTime.BLOCKS_PER_DAY;
    uint256 internal constant EMA_STALENESS = AureumTime.BLOCKS_PER_EPOCH;
    address internal constant POOL = address(0xA1);
    address internal constant HOLDER = address(0x2222);

    function setUp() public {
        emaSampler = new MockEMASampler();
        gaugeReg = new MockGaugeRegistry();
        recorder = new MockRecorder();
        registry = new MockMiliariumRegistry();
        vw = new VotingWeight(emaSampler, gaugeReg, recorder, registry, GENESIS_BLOCK);
        vm.roll(START_BLOCK);
        address[] memory pools = new address[](1);
        pools[0] = POOL;
        registry.setPoolList(pools);
        gaugeReg.setApproved(POOL, true);
        recorder.setUserLP(POOL, HOLDER, 1e18);
        recorder.setPoolTotalLP(POOL, 1e18);
        recorder.setEffectiveQualBlock(POOL, HOLDER, START_BLOCK - AureumTime.ON_RAMP_PERIOD_BLOCKS);
        emaSampler.setTvlEMA(POOL, 16_000e18);
        // Mature seed: seeded exactly EMA_MATURITY ago, so the 60-day maturity gate passes; freshness varies per test.
        emaSampler.setSeedBlock(POOL, START_BLOCK - EMA_MATURITY);
    }

    function _setFreshnessAndRead(uint256 lastUpdateBlock) private returns (uint256) {
        emaSampler.setLastUpdateBlock(POOL, lastUpdateBlock);
        vw.poke(HOLDER);
        return vw.governanceWeight(HOLDER);
    }

    /// @notice Core F-05 fix: a mature seed last refreshed at seed time (EMA_MATURITY ago, deeply stale) confers zero weight.
    ///         This is the pumped-then-abandoned EMA the maturity gate alone would have let vote.
    function test_F05_deeplyStaleMatureEma_confersZeroWeight() public {
        assertEq(_setFreshnessAndRead(START_BLOCK - EMA_MATURITY), 0);
        assertEq(vw.totalSupply(), 0);
    }

    /// @notice A mature seed refreshed at the current block confers weight — the freshness gate blocks only stale EMAs.
    function test_F05_freshMatureEma_confersWeight() public {
        assertGt(_setFreshnessAndRead(START_BLOCK), 0);
    }

    /// @notice Boundary (strict >): staleness exactly equal to EMA_STALENESS_BLOCKS still flows.
    function test_F05_stalenessBoundaryFresh_atExactEpoch() public {
        assertGt(_setFreshnessAndRead(START_BLOCK - EMA_STALENESS), 0);
    }

    /// @notice Boundary (strict >): one block past EMA_STALENESS_BLOCKS is stale and zeroes weight.
    function test_F05_stalenessBoundaryStale_oneBlockPast() public {
        assertEq(_setFreshnessAndRead(START_BLOCK - EMA_STALENESS - 1), 0);
    }
}
