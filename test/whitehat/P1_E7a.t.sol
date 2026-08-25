// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {GaugeRegistry} from "src/gauge/GaugeRegistry.sol";
import {GaugeEligibility} from "src/gauge/GaugeEligibility.sol";
import {EfficiencyOracle} from "src/emission/EfficiencyOracle.sol";
import {EmissionDistributorHarness} from "test/unit/harness/EmissionDistributorHarness.sol";

import {IAuMM} from "src/token/IAuMM.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";

import {MockAuMM, MockEMASampler, MockCCBMultiplier, MockMiliariumRegistry} from "test/unit/EmissionDistributor.t.sol";
import {MockEfficiencyTVLOracle} from "test/unit/EfficiencyOracle.t.sol";

/// @notice Reproduction PoC for seam-1 root cause E.7a (Medium). No deploy script calls
///         `setFeeRecorder`, so every efficiency numerator stays zero; pass 2 of
///         `computeEpochSnapshot` sorts descending by ratio with an ascending-address
///         tie-break, and the highest-addressed pool takes the harshest emission cap.
///         E.7b and E.7c are the other two F-16 faces.
contract P1_E7a_TournamentRanksByAddressWhenTheFeeFeedIsUnwiredTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant BLOCKS_PER_EPOCH = 100_800;
    uint256 internal constant SCORE_BLOCK = GENESIS_BLOCK + 2_628_000 + 1;
    uint256 internal constant SCORE_SECOND_BLOCK = SCORE_BLOCK + BLOCKS_PER_EPOCH;
    /// @dev EfficiencyOracle.efficiencyInputs sums only the three epochs BEFORE the current one,
    ///      so a denominator accrued in the current epoch is invisible until one further epoch has elapsed.
    uint256 internal constant INSPECT_BLOCK = SCORE_SECOND_BLOCK + BLOCKS_PER_EPOCH;
    uint256 internal constant ADVANCE_1_BLOCK = SCORE_SECOND_BLOCK;
    uint256 internal constant ADVANCE_2_BLOCK = ADVANCE_1_BLOCK + BLOCKS_PER_EPOCH;
    uint256 internal constant ADVANCE_3_BLOCK = ADVANCE_1_BLOCK + 2 * BLOCKS_PER_EPOCH;
    uint256 internal constant ADVANCE_4_BLOCK = ADVANCE_1_BLOCK + 3 * BLOCKS_PER_EPOCH;
    uint256 internal constant POOL_COUNT = 20;

    address internal constant GOV = address(0x9011);
    address internal constant PLACEHOLDER = address(0xDEAD);

    MockAuMM internal aumm;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockMiliariumRegistry internal miliReg;
    MockEfficiencyTVLOracle internal tvlMock;
    EfficiencyOracle internal effOracle;
    GaugeEligibility internal gaugeElig;
    GaugeRegistry internal gaugeRegistry;
    EmissionDistributorHarness internal distributor;

    address[] internal pools;

    function setUp() public {
        aumm = new MockAuMM();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        miliReg = new MockMiliariumRegistry();
        tvlMock = new MockEfficiencyTVLOracle();
        // Real oracle — feeRecorder is deliberately left unset; that omission is the defect
        // under reproduction, not an oversight. Never call setFeeRecorder in this file.
        effOracle = new EfficiencyOracle(tvlMock, address(aumm), GENESIS_BLOCK, GOV);

        gaugeElig = new GaugeEligibility(
            PLACEHOLDER,
            PLACEHOLDER,
            PLACEHOLDER,
            PLACEHOLDER,
            PLACEHOLDER,
            address(this),
            address(effOracle),
            PLACEHOLDER,
            PLACEHOLDER
        );
        gaugeRegistry = new GaugeRegistry(
            GOV,
            address(gaugeElig),
            PLACEHOLDER,
            PLACEHOLDER,
            GENESIS_BLOCK
        );
        gaugeElig.setGaugeRegistry(address(gaugeRegistry));

        distributor = new EmissionDistributorHarness(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gaugeRegistry)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK,
            GOV
        );

        vm.prank(GOV);
        effOracle.setEmissionsRecorder(address(distributor));
        tvlMock.setRate(address(aumm), 1e18);

        for (uint256 i = 0; i < POOL_COUNT; i++) {
            pools.push(address(uint160(0xA00000 + i)));
        }

        // Different TVL EMAs so a real efficiency ranking would not coincide with address order.
        for (uint256 i = 0; i < POOL_COUNT; i++) {
            ema.setTVLEMA(pools[i], (i + 1) * 100e18);
            mult.setMultiplier(pools[i], 1e18);
        }

        vm.prank(GOV);
        gaugeRegistry.seedFoundingPools(pools);

        vm.roll(GENESIS_BLOCK);
    }

    function _scoreAll() internal {
        for (uint256 i = 0; i < POOL_COUNT; i++) {
            distributor.recordScore(pools[i]);
        }
    }

    /// @dev Accrues real emission denominators into the oracle. Two passes across an epoch
    ///      boundary are required so `_ensureCurrentEpoch` finalizes the first window into
    ///      history; `efficiencyInputs` reads only prior epochs, never the live current one.
    function _accrueEmissionDenominators() internal {
        vm.roll(SCORE_BLOCK);
        _scoreAll();
        vm.roll(SCORE_SECOND_BLOCK);
        _scoreAll();
    }

    /// @dev Four `advanceTournament` calls, each in a distinct protocol epoch. Re-scores before
    ///      every advance so the real oracle's SMA window still carries a nonzero denominator
    ///      at the ranking call; without that the finalized accrual epoch ages out of the
    ///      three-epoch lookback and pass 1 skips every pool.
    function _runWarmupToCaps() internal {
        vm.roll(ADVANCE_1_BLOCK);
        _scoreAll();
        gaugeRegistry.advanceTournament();

        vm.roll(ADVANCE_2_BLOCK);
        _scoreAll();
        gaugeRegistry.advanceTournament();

        vm.roll(ADVANCE_3_BLOCK);
        _scoreAll();
        gaugeRegistry.advanceTournament();

        vm.roll(ADVANCE_4_BLOCK);
        _scoreAll();
        gaugeRegistry.advanceTournament();
    }

    /// @notice Premise: fee feed unwired, every numerator zero, every denominator positive.
    function test_P1_E7a_unwiredFeeFeedLeavesEveryEfficiencyNumeratorAtZero() public {
        assertEq(effOracle.feeRecorder(), address(0), "feeRecorder is unset; the fee feed is unwired");

        _accrueEmissionDenominators();

        vm.roll(INSPECT_BLOCK);

        for (uint256 i = 0; i < POOL_COUNT; i++) {
            (uint256 numeratorSma, uint256 denominatorSma) = effOracle.efficiencyInputs(pools[i]);
            assertEq(
                numeratorSma,
                0,
                "numeratorSma is zero; a zero numerator makes every efficiency ratio zero so the sort has no signal to order by"
            );
            assertGt(
                denominatorSma,
                0,
                "denominatorSma is positive after accrual so the pool is not skipped for a zero denominator"
            );
        }
    }

    /// @notice With every ratio zero, the address tie-break decides: highest address gets 10 bps.
    function test_P1_E7a_rankingCollapsesToAddressOrderSoTheHighestAddressedPoolIsClamped() public {
        _accrueEmissionDenominators();
        _runWarmupToCaps();

        address highest = pools[POOL_COUNT - 1];
        address secondHighest = pools[POOL_COUNT - 2];
        address thirdHighest = pools[POOL_COUNT - 3];
        address lowest = pools[0];

        assertEq(gaugeRegistry.poolEmissionCapBps(highest), 10, "highest-addressed pool carries 10 bps");
        assertEq(gaugeRegistry.poolEmissionCapBps(secondHighest), 50, "next-highest carries 50 bps");
        assertEq(gaugeRegistry.poolEmissionCapBps(thirdHighest), 100, "third-highest carries 100 bps");
        assertEq(gaugeRegistry.poolEmissionCapBps(lowest), 0, "lowest-addressed pool carries 0");

        uint256 tenBpsFp = 10 * 1e14;
        uint256 equalSplitFp = 1e18 / POOL_COUNT;
        assertLt(
            tenBpsFp * 10,
            equalSplitFp,
            "10 bps is at least an order of magnitude below an equal split of the twenty ranked pools"
        );
    }
}
