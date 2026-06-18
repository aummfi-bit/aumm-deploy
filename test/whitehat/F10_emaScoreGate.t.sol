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
import {AureumTime} from "src/lib/AureumTime.sol";
import {MockEMASampler} from "test/unit/VotingWeight.t.sol";
import {MockAuMM, MockGaugeRegistry, MockCCBMultiplier, MockEfficiencyOracle, MockMiliariumRegistry} from "test/unit/EmissionDistributor.t.sol";

/// @notice F-10 fix regression (WM.3) — EmissionDistributor.recordScore now gates the TVL EMA read through
///         _gatedTvlEMA: an unseeded, immature (< EMA_MATURITY_BLOCKS / 60 days), or stale (last refreshed
///         more than EMA_STALENESS_BLOCKS / 14 days ago) EMA contributes ZERO to the F-5 emission score,
///         mirroring the F-04/F-05 VotingWeight consumer gate. Degradation is return-0 (not revert), so a
///         stale pool's stored score self-clears on the next permissionless recordScore. The controllable
///         MockEMASampler (from VotingWeight.t.sol) lets each test pin seed age and refresh freshness.
contract F10_EmaScoreGateTest is Test {
    MockEMASampler internal sampler;
    MockGaugeRegistry internal gauges;
    MockCCBMultiplier internal mult;
    MockEfficiencyOracle internal effOracle;
    MockMiliariumRegistry internal miliReg;
    MockAuMM internal aumm;
    EmissionDistributorHarness internal distributor;

    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant EMA_MATURITY = 60 * AureumTime.BLOCKS_PER_DAY;
    uint256 internal constant EMA_STALENESS = AureumTime.BLOCKS_PER_EPOCH;

    address internal constant POOL = address(0xA1);
    address internal constant GOV = address(0x9011);

    uint256 internal startBlock;

    function setUp() public {
        aumm = new MockAuMM();
        sampler = new MockEMASampler();
        gauges = new MockGaugeRegistry();
        mult = new MockCCBMultiplier();
        effOracle = new MockEfficiencyOracle();
        miliReg = new MockMiliariumRegistry();

        distributor = new EmissionDistributorHarness(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(sampler)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK,
            GOV
        );

        effOracle.setEmissionsRecorder(address(distributor));
        gauges.setApproved(POOL, true);
        mult.setMultiplier(POOL, 1e18);
        sampler.setTvlEMA(POOL, 16_000e18);

        // Continuous regime (alpha = 1e18) so a non-Miliarium pool's effective score equals its F-5 score (= tvlEMA).
        startBlock = AureumTime.year1EndBlock(GENESIS_BLOCK) + 1;
        vm.roll(startBlock);
    }

    /// @dev Pins seed age + refresh freshness, records, returns the resulting poolScore.
    function _setGateAndRecord(uint256 seedBlock, uint256 lastUpdateBlock) private returns (uint256) {
        sampler.setSeedBlock(POOL, seedBlock);
        sampler.setLastUpdateBlock(POOL, lastUpdateBlock);
        distributor.recordScore(POOL);
        return distributor.poolScore(POOL);
    }

    /// @notice Seed gate — an unseeded EMA (emaSeedBlock == 0) contributes zero score.
    function test_F10_unseededEma_confersZeroScore() public {
        assertEq(_setGateAndRecord(0, startBlock), 0);
        assertEq(distributor.totalScore(), 0);
    }

    /// @notice Maturity gate — a seed one block short of EMA_MATURITY_BLOCKS (immature) contributes zero score.
    function test_F10_immatureEma_confersZeroScore() public {
        assertEq(_setGateAndRecord(startBlock - EMA_MATURITY + 1, startBlock), 0);
        assertEq(distributor.totalScore(), 0);
    }

    /// @notice Maturity boundary (strict <): a seed aged exactly EMA_MATURITY_BLOCKS is mature and, when fresh, scores.
    function test_F10_maturityBoundary_atExactMaturity_confersScore() public {
        assertGt(_setGateAndRecord(startBlock - EMA_MATURITY, startBlock), 0);
    }

    /// @notice Freshness gate — a mature seed last refreshed EMA_MATURITY ago (deeply stale) contributes zero score.
    function test_F10_deeplyStaleMatureEma_confersZeroScore() public {
        assertEq(_setGateAndRecord(startBlock - EMA_MATURITY, startBlock - EMA_MATURITY), 0);
        assertEq(distributor.totalScore(), 0);
    }

    /// @notice Happy path — a mature seed refreshed at the current block scores tvlEMA (16_000e18 at mult 1e18, continuous alpha).
    function test_F10_freshMatureEma_confersScore() public {
        assertEq(_setGateAndRecord(startBlock - EMA_MATURITY, startBlock), 16_000e18);
    }

    /// @notice Freshness boundary (strict >): staleness exactly EMA_STALENESS_BLOCKS still scores.
    function test_F10_stalenessBoundaryFresh_atExactEpoch() public {
        assertGt(_setGateAndRecord(startBlock - EMA_MATURITY, startBlock - EMA_STALENESS), 0);
    }

    /// @notice Freshness boundary (strict >): one block past EMA_STALENESS_BLOCKS is stale and zeroes the score.
    function test_F10_stalenessBoundaryStale_oneBlockPast() public {
        assertEq(_setGateAndRecord(startBlock - EMA_MATURITY, startBlock - EMA_STALENESS - 1), 0);
        assertEq(distributor.totalScore(), 0);
    }
}
