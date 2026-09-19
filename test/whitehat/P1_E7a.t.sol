// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

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

/// @notice Regression suite for seam-1 root cause E.7a (Medium), inverted at PP4.13l from the
///         reproduction this file was authored as. The defect: no deploy script calls
///         `setFeeRecorder`, so every efficiency numerator stays zero, and pass 2 of
///         `computeEpochSnapshot` then sorted descending by ratio with an ascending-address
///         tie-break, handing the harshest emission cap to the highest-addressed pool. PP4.13g
///         added the `numeratorSma == 0` skip ahead of the cold `SSTORE` per PP-D56 (viii), so a
///         zero-numerator pool now leaves the tournament rather than entering it with no signal
///         to be ordered by. Rung 15 seats the feed per PP-D58 (ix) and (xvi): the hook produces the
///         numerator and the spine wires both directions, so the skip now holds only while no feed is
///         seated, and a seated feed ranks a zero numerator at ratio zero in the most severe tier. This
///         unit fixture leaves the feed unset in setUp, so the premise and the skip test below describe
///         an unseated oracle, while the two PP-D58 (xvi) cases at the end seat one inside their own test.
///         E.7b and E.7c are the other two F-16 faces.
contract P1_E7a_ZeroNumeratorPoolsAreSkippedNotRankedByAddressTest is Test {
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
    /// @dev PP-D58 (xvi) — the feed a seated oracle accepts fees from, a fee token priced 1:1, and the
    ///      count of lowest-addressed pools left without revenue.
    address internal constant FEED = address(0xFEED);
    address internal constant FEE_TOKEN = address(0xFEE0);
    uint256 internal constant ZERO_FEE_POOLS = 3;
    /// @dev PP-D58 (xvi)(4) — a settle one epoch boundary after SCORE_BLOCK (epoch 26), inside one accrual
    ///      chunk, and a read in epoch 30, whose window of epochs 27 to 29 excludes epoch 26.
    uint256 internal constant VINTAGE_SETTLE_BLOCK = GENESIS_BLOCK + 27 * BLOCKS_PER_EPOCH + 7_000;
    uint256 internal constant VINTAGE_READ_BLOCK = GENESIS_BLOCK + 30 * BLOCKS_PER_EPOCH + 1;

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
        // Real oracle — feeRecorder is left unset here, as it was on chain before rung 15; only the
        // PP-D58 (xvi) cases at the end of this file seat a feed, each inside its own test.
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
            GOV,
            address(new MockRegisteredVault())
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

    /// @dev Four tournaments, each accumulated and finalized in a distinct protocol epoch. Re-scores before
    ///      every advance so the real oracle's SMA window still carries a nonzero denominator
    ///      at the ranking call; without that the finalized accrual epoch ages out of the
    ///      three-epoch lookback and accumulation skips every pool.
    function _runWarmupToCaps() internal {
        vm.roll(ADVANCE_1_BLOCK);
        _scoreAll();
        _advanceOnce();

        vm.roll(ADVANCE_2_BLOCK);
        _scoreAll();
        _advanceOnce();

        vm.roll(ADVANCE_3_BLOCK);
        _scoreAll();
        _advanceOnce();

        vm.roll(ADVANCE_4_BLOCK);
        _scoreAll();
        _advanceOnce();
    }

    /// @dev One tournament epoch under the **PP-D56 (iv)** split, each phase taking a single page.
    ///      The accumulate page takes its hints from `nextAccumulationPage` per **PP-D56 (xxv)**.
    function _advanceOnce() internal {
        (, address[] memory hints) = gaugeRegistry.nextAccumulationPage(type(uint256).max);
        gaugeRegistry.accumulateTournament(hints);
        gaugeRegistry.finalizeTournament(type(uint256).max);
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

    /// @notice Done-criteria for E.7a, inverted from the reproduction this file was written as.
    ///         The numerator skip is symmetric with the denominator skip in the property that skip
    ///         exists to give: one dead input must not brick the permissionless tournament per
    ///         P-D15 (3). So four advances complete, nothing is ranked, and the address tie-break
    ///         that previously handed 10 / 50 / 100 bps to the three highest-addressed pools never
    ///         runs. Both zero-input skips precede the cold `SSTORE` per PP-D56 (viii), so not one
    ///         of the twenty pools registers a grace epoch it has no data to measure.
    function test_zeroNumeratorSkippedSymmetrically() public {
        _accrueEmissionDenominators();
        _runWarmupToCaps();

        for (uint256 i = 0; i < POOL_COUNT; i++) {
            assertEq(
                gaugeRegistry.poolEmissionCapBps(pools[i]),
                0,
                "no pool carries a cap: every ratio is zero, nothing enters the ranking, and the address tie-break never decides"
            );
            assertEq(
                gaugeElig.firstTournamentEpoch(pools[i]),
                0,
                "the skip precedes the cold SSTORE, so no pool registers a grace epoch across four advances"
            );
        }

        assertEq(
            gaugeElig.currentSnapshotEpoch(),
            4,
            "all four advances completed without reverting, which is the denominator skip's own guarantee extended to the numerator"
        );
    }

    /// @dev Records the same fee for every pool from index ZERO_FEE_POOLS up, as the seated feed, so the
    ///      three lowest-addressed pools carry a zero numerator beside seventeen that earn. A constant fee
    ///      against emissions that rise with TVL gives the earners distinct ratios.
    function _feedFees() internal {
        for (uint256 i = ZERO_FEE_POOLS; i < POOL_COUNT; i++) {
            vm.prank(FEED);
            effOracle.recordFees(pools[i], FEE_TOKEN, 10e18);
        }
    }

    /// @dev `_accrueEmissionDenominators` then `_runWarmupToCaps`, with fees recorded after every scoring
    ///      pass so each tournament's three-epoch window carries a numerator for the earners.
    function _accrueAndWarmUpWithFees() internal {
        vm.roll(SCORE_BLOCK);
        _scoreAll();
        _feedFees();
        vm.roll(ADVANCE_1_BLOCK);
        _scoreAll();
        _feedFees();
        _advanceOnce();
        vm.roll(ADVANCE_2_BLOCK);
        _scoreAll();
        _feedFees();
        _advanceOnce();
        vm.roll(ADVANCE_3_BLOCK);
        _scoreAll();
        _feedFees();
        _advanceOnce();
        vm.roll(ADVANCE_4_BLOCK);
        _scoreAll();
        _feedFees();
        _advanceOnce();
    }

    /// @notice PP-D58 (ix) and (xvi)(1)-(2): once a feed is seated a zero numerator is a signal rather
    ///         than an absence. The three lowest-addressed pools earn nothing, rank at ratio zero at the
    ///         tail of a twenty-pool list, and each takes the 10 bps cap and no favored slot. The address
    ///         tie-break would have handed them 100, 50 and 10 bps in address order, and the rung-13 skip
    ///         would have left them uncapped; the seventeen earners stay uncapped.
    function test_zeroNumeratorRanksAtTheBottomOnceTheFeedIsSeated() public {
        vm.prank(GOV);
        effOracle.setFeeRecorder(FEED);
        tvlMock.setRate(FEE_TOKEN, 1e18);

        _accrueAndWarmUpWithFees();

        assertEq(gaugeElig.currentSnapshotEpoch(), 4, "four tournaments closed");
        for (uint256 i = 0; i < ZERO_FEE_POOLS; i++) {
            (uint256 numeratorSma, uint256 denominatorSma) = effOracle.efficiencyInputs(pools[i]);
            assertEq(numeratorSma, 0, "premise: this pool earned no fees");
            assertGt(denominatorSma, 0, "premise: this pool drew emissions, so it is ranked rather than skipped");
            assertEq(gaugeElig.lastSnapshotEpoch(pools[i]), 4, "the zero-ratio pool was ranked in the fourth tournament");
            assertEq(
                gaugeRegistry.poolEmissionCapBps(pools[i]), 10, "a zero-ratio pool takes the 10 bps cap whatever its address"
            );
            assertFalse(gaugeElig.isFavoredCohort(pools[i]), "a zero-ratio pool is never favored");
        }
        for (uint256 i = ZERO_FEE_POOLS; i < POOL_COUNT; i++) {
            assertEq(
                gaugeRegistry.poolEmissionCapBps(pools[i]), 0, "an earning pool above the bottom bands stays uncapped"
            );
        }
    }

    /// @notice PP-D58 (xvi)(3)-(5): a settle that crosses an epoch boundary credits the F-10 denominator to
    ///         each epoch the emissions accrued in. One pool is scored alone in epoch 26 and settled once in
    ///         epoch 27, inside a single accrual chunk. The oracle receives two pieces, epoch 26's and epoch
    ///         27's, each matching the tranche integral over its own blocks, where before it received the
    ///         whole allocation under epoch 27. The read in epoch 30, whose window is 27 to 29, therefore
    ///         sees only epoch 27's piece.
    function test_settledEmissionsCreditTheEpochTheyAccruedIn() public {
        address pool = pools[0];
        vm.roll(SCORE_BLOCK);
        distributor.recordScore(pool);

        vm.roll(VINTAGE_SETTLE_BLOCK);
        vm.recordLogs();
        distributor.recordScore(pool);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256[2] memory epochs;
        uint256[2] memory amounts;
        uint256 found;
        for (uint256 k = 0; k < logs.length; k++) {
            if (logs[k].emitter != address(effOracle)) continue;
            if (logs[k].topics[0] != EfficiencyOracle.EmissionsRecorded.selector) continue;
            assertLt(found, 2, "no more than two pieces for a settle spanning two epochs");
            epochs[found] = uint256(logs[k].topics[2]);
            (amounts[found],) = abi.decode(logs[k].data, (uint256, uint256));
            found++;
        }
        assertEq(found, 2, "the settle is split into one piece per accrual epoch");
        assertEq(epochs[0], 26, "the first piece is credited to epoch 26, where it accrued");
        assertEq(epochs[1], 27, "the second piece is credited to epoch 27");

        uint256 epoch27Start = GENESIS_BLOCK + 27 * BLOCKS_PER_EPOCH;
        assertApproxEqAbs(
            amounts[0],
            distributor.extLpTrancheIntegral(SCORE_BLOCK + 1, epoch27Start - 1),
            1e3,
            "epoch 26's piece is the tranche over its own blocks"
        );
        assertApproxEqAbs(
            amounts[1],
            distributor.extLpTrancheIntegral(epoch27Start, VINTAGE_SETTLE_BLOCK),
            1e3,
            "epoch 27's piece is the tranche over its own blocks"
        );
        assertEq(distributor.poolDebtEpoch(pool), 27, "the debt epoch follows the accrual cursor");

        vm.roll(VINTAGE_READ_BLOCK);
        (, uint256 denominatorSma) = effOracle.efficiencyInputs(pool);
        assertEq(
            denominatorSma,
            amounts[1] / 3,
            "epoch 26's piece lies outside the epoch-30 window, where the pre-fix lump into epoch 27 would not"
        );
    }
}
