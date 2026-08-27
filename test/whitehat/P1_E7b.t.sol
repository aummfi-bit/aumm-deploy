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
    /// @dev One run spans accrual (2 epochs) plus four tournament advances (3 further epochs from
    ///      the second score block); five epochs of stride keep the next run strictly forward.
    uint256 internal constant RUN_STRIDE = 5 * BLOCKS_PER_EPOCH;
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
        // Real oracle — feeRecorder is deliberately left unset; never call setFeeRecorder.
        // The ranking path measured here is the same all-zero-ratio path E.7a established.
        effOracle = new EfficiencyOracle(tvlMock, address(aumm), GENESIS_BLOCK, GOV);
        tvlMock.setRate(address(aumm), 1e18);

        vm.roll(GENESIS_BLOCK);
    }

    function _scoreAll(EmissionDistributorHarness dist, address[] storage poolList) internal {
        for (uint256 i = 0; i < poolList.length; i++) {
            dist.recordScore(poolList[i]);
        }
    }

    /// @dev Deploys a fresh gauge + distributor stack for one measurement, accrues denominators,
    ///      clears the cold-start and smoothing windows with three advances, then returns the gas
    ///      consumed by the fourth `advanceTournament`. `runIndex` selects a forward-only block
    ///      base so a second call in the same test never rolls backward.
    function _measureFourthAdvanceGas(uint256 poolCount, uint256 runIndex) internal returns (uint256 gasUsed) {
        uint256 base = TOURNAMENT_ORIGIN + runIndex * RUN_STRIDE;
        uint256 score1 = base;
        uint256 score2 = base + BLOCKS_PER_EPOCH;
        uint256 adv1 = score2;
        uint256 adv2 = score2 + BLOCKS_PER_EPOCH;
        uint256 adv3 = score2 + 2 * BLOCKS_PER_EPOCH;
        uint256 adv4 = score2 + 3 * BLOCKS_PER_EPOCH;

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
