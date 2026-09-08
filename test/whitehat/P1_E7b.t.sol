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
import {MockRegisteredVault} from "../mocks/MockRegisteredVault.sol";

/// @notice Reproduction PoC for seam-1 root cause E.7b (Medium). `advanceTournament` passes
///         the registry's whole active set into `computeEpochSnapshot` with a per-pool external
///         call, a cold SSTORE on first sighting and an insertion sort over the ranked survivors,
///         so cost scales with a set that nothing bounds and a snapshot that can no longer be
///         afforded freezes the caps it last wrote. E.7a and E.7c are the other two F-16 faces.
contract P1_E7b_TournamentEnumeratesAnUnboundedActiveSetTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant BLOCKS_PER_EPOCH = 100_800;
    uint256 internal constant TOURNAMENT_ORIGIN = GENESIS_BLOCK + 2_628_000 + 1;
    /// @dev One run spans THREE scoring epochs and four tournament advances. The first scoring
    ///      epoch exists so the pool's first sighting already carries BOTH legs: at the very first
    ///      `recordScore` the distributor's `totalScore` is still zero, so that epoch accrues no
    ///      emissions, and a pool seen only from it reads a positive numerator against a ZERO
    ///      denominator, which PP-D56 (viii) skips AHEAD of the cold-start stamp. Without it the
    ///      stamp lands at epoch 2, the fourth advance falls inside the warmup window and the run
    ///      measures the skip path. Six epochs of stride keep the next run strictly forward of the
    ///      previous run's fourth advance.
    uint256 internal constant RUN_STRIDE = 6 * BLOCKS_PER_EPOCH;
    uint256 internal constant FREEZE_EXTRA_EPOCHS = 5;

    // LARGE_N is three times SMALL_N so the growth factor is read against three.
    uint256 internal constant SMALL_N = 30;
    uint256 internal constant LARGE_N = 90;
    /// @dev Audit row's own figures: the test derives a marginal per-pool cost from its two
    ///      measurements and checks the row's claim against them rather than against an invented threshold.
    uint256 internal constant AUDIT_POOL_COUNT = 890;
    uint256 internal constant BLOCK_GAS_LIMIT = 30_000_000;

    address internal constant GOV = address(0x9011);
    address internal constant PLACEHOLDER = address(0xDEAD);

    MockAuMM internal aumm;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockMiliariumRegistry internal miliReg;
    MockEfficiencyTVLOracle internal tvlMock;
    EfficiencyOracle internal effOracle;

    GaugeEligibility internal lastElig;
    GaugeRegistry internal lastRegistry;
    EmissionDistributorHarness internal lastDistributor;
    address[] internal lastPools;

    function setUp() public {
        aumm = new MockAuMM();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        miliReg = new MockMiliariumRegistry();
        tvlMock = new MockEfficiencyTVLOracle();
        // Real oracle. PP-D56 (ix) — the fee recorder is WIRED here, reversing the E-family
        // harness default that E.7a's file depends on. After PP4.13g a zero numerator is skipped
        // ahead of the cold-start stamp, so an unset feed would take every pool out of the
        // tournament and this file would measure the SKIP PATH rather than the ranking path:
        // two of the three cost terms E.7b alleges, the cold SSTORE on first sighting and the
        // insertion sort over ranked survivors, exist only for pools that rank. E.7a's own
        // fixture keeps its feed unset; that is E.7a's invariant and does not bind this one.
        effOracle = new EfficiencyOracle(tvlMock, address(aumm), GENESIS_BLOCK, GOV);
        tvlMock.setRate(address(aumm), 1e18);
        vm.prank(GOV);
        effOracle.setFeeRecorder(address(this));

        vm.roll(GENESIS_BLOCK);
    }

    /// @dev Pushes one epoch of numerator and denominator per pool. The fee amount is constant
    ///      while denominators track each pool's distinct TVL EMA, so the ratios are distinct and
    ///      the sort has real work to do; they arrive descending, which is insertion sort's best
    ///      case and keeps these figures a LOWER bound exactly as this test's own NatSpec states.
    function _scoreAll(EmissionDistributorHarness dist, address[] storage poolList) internal {
        for (uint256 i = 0; i < poolList.length; i++) {
            dist.recordScore(poolList[i]);
            effOracle.recordFees(poolList[i], address(aumm), 1e18);
        }
    }

    /// @dev Deploys a fresh gauge + distributor stack for one measurement, accrues both efficiency
    ///      legs, clears the cold-start and smoothing windows with three advances, then returns the
    ///      gas consumed by the fourth `advanceTournament`. `runIndex` selects a forward-only block
    ///      base so a second call in the same test never rolls backward. The advances begin TWO
    ///      epochs after the first scoring block rather than one: the very first `recordScore`
    ///      finds `totalScore` at zero, so that epoch records fees but accrues no emissions, and an
    ///      advance whose three-epoch lookback reaches only that epoch reads a positive numerator
    ///      against a ZERO denominator and is skipped AHEAD of the cold-start stamp per PP-D56
    ///      (viii). Beginning one epoch later puts a fully-populated epoch inside the lookback, so
    ///      the pool stamps at epoch 1, warms through advances 2 and 3, and ranks on the fourth
    ///      exactly as this helper's name says.
    function _measureFourthAdvanceGas(uint256 poolCount, uint256 runIndex) internal returns (uint256 gasUsed) {
        uint256 base = TOURNAMENT_ORIGIN + runIndex * RUN_STRIDE;
        uint256 score1 = base;
        uint256 score2 = base + BLOCKS_PER_EPOCH;
        uint256 adv1 = score2 + BLOCKS_PER_EPOCH;
        uint256 adv2 = score2 + 2 * BLOCKS_PER_EPOCH;
        uint256 adv3 = score2 + 3 * BLOCKS_PER_EPOCH;
        uint256 adv4 = score2 + 4 * BLOCKS_PER_EPOCH;

        lastElig = new GaugeEligibility(
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
        lastRegistry = new GaugeRegistry(
            GOV,
            address(lastElig),
            PLACEHOLDER,
            PLACEHOLDER,
            GENESIS_BLOCK
        );
        lastElig.setGaugeRegistry(address(lastRegistry));

        lastDistributor = new EmissionDistributorHarness(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(lastRegistry)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK,
            GOV,
            address(new MockRegisteredVault())
        );

        vm.prank(GOV);
        effOracle.setEmissionsRecorder(address(lastDistributor));

        delete lastPools;
        for (uint256 i = 0; i < poolCount; i++) {
            lastPools.push(address(uint160(0xA00000 + runIndex * 1_000_000 + i)));
        }

        for (uint256 i = 0; i < poolCount; i++) {
            ema.setTVLEMA(lastPools[i], (i + 1) * 100e18);
            mult.setMultiplier(lastPools[i], 1e18);
        }

        vm.prank(GOV);
        lastRegistry.seedFoundingPools(lastPools);

        vm.roll(score1);
        _scoreAll(lastDistributor, lastPools);
        vm.roll(score2);
        _scoreAll(lastDistributor, lastPools);

        vm.roll(adv1);
        _scoreAll(lastDistributor, lastPools);
        lastRegistry.advanceTournament();

        vm.roll(adv2);
        _scoreAll(lastDistributor, lastPools);
        lastRegistry.advanceTournament();

        vm.roll(adv3);
        _scoreAll(lastDistributor, lastPools);
        lastRegistry.advanceTournament();

        vm.roll(adv4);
        _scoreAll(lastDistributor, lastPools);

        uint256 gasBefore = gasleft();
        lastRegistry.advanceTournament();
        uint256 gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
    }

    /// @dev Pool addresses are built and seeded in ascending order so the registry's active set
    ///      iterates already-sorted, which is insertion sort's best case and makes these figures a
    ///      LOWER bound; production activation order bears no relation to address order, so the
    ///      real sort term is larger and the extrapolation is conservative.
    /// @notice Tournament gas grows at least in proportion to the unbounded active set.
    function test_P1_E7b_tournamentGasScalesWithTheUnboundedActiveSet() public {
        uint256 gasSmall = _measureFourthAdvanceGas(SMALL_N, 0);
        uint256 gasLarge = _measureFourthAdvanceGas(LARGE_N, 1);

        emit log_named_uint("advanceTournament gas SMALL_N=30", gasSmall);
        emit log_named_uint("advanceTournament gas LARGE_N=90", gasLarge);

        // Premise per PP-D56 (ix): these figures measure the RANKING path only if the pools
        // actually rank. This file carried no such check, which is why it went on passing as a
        // skip-path measurement from PP4.13g until the PP4.13s baseline caught the extrapolation
        // falling under the block limit. The state read below belongs to the LARGE_N run.
        (uint256 numeratorSma, uint256 denominatorSma) = effOracle.efficiencyInputs(lastPools[0]);
        emit log_named_uint("numeratorSma[0]", numeratorSma);
        emit log_named_uint("denominatorSma[0]", denominatorSma);
        emit log_named_uint("firstTournamentEpoch[0]", lastElig.firstTournamentEpoch(lastPools[0]));
        emit log_named_uint("currentSnapshotEpoch", lastElig.currentSnapshotEpoch());
        emit log_named_uint("lastSnapshotEpoch[0]", lastElig.lastSnapshotEpoch(lastPools[0]));

        assertGt(numeratorSma, 0, "premise: the fee feed is wired so the numerator is nonzero");
        assertGt(denominatorSma, 0, "premise: emissions accrued so the denominator is nonzero");
        assertGt(
            lastElig.lastSnapshotEpoch(lastPools[0]),
            0,
            "premise: the measured advance RANKED the pool rather than skipping it"
        );

        assertGt(gasSmall, 0, "SMALL_N measurement is nonzero");
        assertGt(gasLarge, 0, "LARGE_N measurement is nonzero");

        uint256 marginalPerPool = (gasLarge - gasSmall) / (LARGE_N - SMALL_N);
        uint256 extrapolatedAtAuditCount = marginalPerPool * AUDIT_POOL_COUNT;
        emit log_named_uint("marginal per-pool gas", marginalPerPool);
        emit log_named_uint("extrapolated gas at AUDIT_POOL_COUNT=890", extrapolatedAtAuditCount);

        assertGt(gasLarge, gasSmall, "cost grows with the active set");
        assertGt(
            extrapolatedAtAuditCount,
            BLOCK_GAS_LIMIT,
            "the audit row's pool count exceeds a block at the measured marginal cost"
        );
    }

    /// @notice Caps written by the last affordable snapshot stay in force when no later
    ///         advanceTournament runs.
    function test_P1_E7b_capsFreezeAtWhateverTheLastAffordableSnapshotWrote() public {
        _measureFourthAdvanceGas(SMALL_N, 0);

        address highest = lastPools[SMALL_N - 1];
        address lowest = lastPools[0];
        uint256 capHighest = lastRegistry.poolEmissionCapBps(highest);
        uint256 capLowest = lastRegistry.poolEmissionCapBps(lowest);

        uint256 freezeBlock = TOURNAMENT_ORIGIN + 4 * BLOCKS_PER_EPOCH + FREEZE_EXTRA_EPOCHS * BLOCKS_PER_EPOCH;
        vm.roll(freezeBlock);

        assertEq(
            lastRegistry.poolEmissionCapBps(highest),
            capHighest,
            "computeEpochSnapshot is the only writer of poolEmissionCapBps; caps freeze without a later snapshot"
        );
        assertEq(
            lastRegistry.poolEmissionCapBps(lowest),
            capLowest,
            "computeEpochSnapshot is the only writer of poolEmissionCapBps; caps freeze without a later snapshot"
        );
    }
}
