// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {EmissionDistributorHarness} from "test/unit/harness/EmissionDistributorHarness.sol";
import {EMASampler} from "src/ccb/EMASampler.sol";
import {ITVLOracle} from "src/ccb/ITVLOracle.sol";
import {IAuMM} from "src/token/IAuMM.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {AuMMMinterRouter} from "src/token/AuMMMinterRouter.sol";
import {MockEMASampler} from "test/unit/VotingWeight.t.sol";
import {MockAuMM, MockBpt, MockGaugeRegistry, MockCCBMultiplier, MockEfficiencyOracle, MockMiliariumRegistry} from "test/unit/EmissionDistributor.t.sol";
import {MockRegisteredVault} from "../mocks/MockRegisteredVault.sol";

/// @notice Minimal settable TVL oracle for the drain-decay leg. Not declared `is ITVLOracle` —
///         EMASampler only calls tvl(), and the ITVLOracle cast at construction dispatches by
///         selector (the CCBEngineProofs MockTVLOracleProof idiom).
contract MockTVLOracleDrain {
    uint256 private _ret;

    function set(uint256 v) external {
        _ret = v;
    }

    function tvl(address) external view returns (uint256) {
        return _ret;
    }
}

/// @title ZeroTvlDispositionTest
/// @notice PB2.13h — PB-D18 (vi) zero-TVL disposition evidence, distributor side. A pool at zero
///         (or gated-to-zero) TVL EMA must not earn forward emissions, deltas notwithstanding:
///         F-5 is multiplicative (CCBScore.score = tvlEMA.mulDown(multiplier)), so a gated-zero
///         EMA collapses the score regardless of the F-8 multiplier — pinned here at the clamp
///         ceiling (1.25e18), the sharpest "deltas cannot resurrect a dead score" witness.
///         Window (b) stale-score evidence: poolScore persists between recordScore calls (no
///         auto-decay — the exposure), and any stranger's permissionless recordScore self-clears
///         it to zero (the bound). Gate boundaries (unseeded / immature / stale) are already
///         pinned by test/whitehat/F10_emaScoreGate.t.sol; the library-level kill by
///         test/unit/CCBScore.t.sol; window (a) decay mechanics by EMASampler.t.sol plus the
///         drain half-life quantifier below. Window (d) — the Months 0-12 F-1/F-3 equal-split
///         leg paying a zero-TVL Miliarium pool — is spec-mandated §xxviii / H-D6 semantics,
///         note-only per PB-D18 (vi), no pin.
contract ZeroTvlDispositionTest is Test {
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
    uint256 internal constant CLAMP_CEILING = 125e16;
    uint256 internal constant EMA_VALUE = 16_000e18;

    address internal constant POOL = address(0xA1);
    address internal constant GOV = address(0x9011);
    address internal constant STRANGER = address(0xBAD);

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
            GOV,
            address(new MockRegisteredVault())
        );

        effOracle.setEmissionsRecorder(address(distributor));
        gauges.setApproved(POOL, true);
        mult.setMultiplier(POOL, CLAMP_CEILING);
        sampler.setTvlEMA(POOL, EMA_VALUE);

        // Continuous regime (alpha = 1e18): a non-Miliarium pool's effective score equals its
        // F-5 score, so every assert below is a sharp equality on the gated EMA x multiplier.
        startBlock = AureumTime.year1EndBlock(GENESIS_BLOCK) + 1;
        vm.roll(startBlock);
    }

    /// @notice Resurrect-proof (unseeded): a never-seeded EMA scores zero even at the F-8 clamp
    ///         ceiling — the multiplier has nothing to multiply.
    function test_ZeroTvl_unseededAtClampCeiling_scoresZero() public {
        sampler.setSeedBlock(POOL, 0);
        sampler.setLastUpdateBlock(POOL, startBlock);
        distributor.recordScore(POOL);
        assertEq(distributor.poolScore(POOL), 0, "unseeded EMA at 1.25e18 multiplier must score zero");
        assertEq(distributor.totalScore(), 0, "zero pool contributes nothing to totalScore");
    }

    /// @notice Resurrect-proof (stale): a mature-but-abandoned EMA scores zero even at the clamp
    ///         ceiling — F-8 deltas cannot resurrect a gated-dead score.
    function test_ZeroTvl_staleAtClampCeiling_scoresZero() public {
        sampler.setSeedBlock(POOL, startBlock - EMA_MATURITY);
        sampler.setLastUpdateBlock(POOL, startBlock - EMA_STALENESS - 1);
        distributor.recordScore(POOL);
        assertEq(distributor.poolScore(POOL), 0, "stale EMA at 1.25e18 multiplier must score zero");
        assertEq(distributor.totalScore(), 0, "stale pool contributes nothing to totalScore");
    }

    /// @notice Positive control: fresh + mature at the clamp ceiling scores EMA x 1.25 exactly —
    ///         proving the multiplier is live when the EMA is, so the zero results above are the
    ///         gate's kill, not a dead rig.
    function test_ZeroTvl_control_freshMatureAtClampCeiling_scoresWithMultiplier() public {
        sampler.setSeedBlock(POOL, startBlock - EMA_MATURITY);
        sampler.setLastUpdateBlock(POOL, startBlock);
        distributor.recordScore(POOL);
        assertEq(distributor.poolScore(POOL), 20_000e18, "16_000e18 EMA x 1.25e18 multiplier");
    }

    /// @notice Window (b) left edge: a recorded score PERSISTS across epochs with no auto-decay —
    ///         the stale pool keeps its totalScore share until someone re-records. This is the
    ///         exposure the permissionless self-clear bounds.
    function test_ZeroTvl_windowB_staleScorePersistsUntilRerecord() public {
        sampler.setSeedBlock(POOL, startBlock - EMA_MATURITY);
        sampler.setLastUpdateBlock(POOL, startBlock);
        distributor.recordScore(POOL);
        assertEq(distributor.poolScore(POOL), 20_000e18, "scored while fresh");

        vm.roll(startBlock + 5 * EMA_STALENESS);
        assertEq(distributor.poolScore(POOL), 20_000e18, "no auto-decay: score persists while unrecorded");
        assertEq(distributor.totalScore(), 20_000e18, "stale pool still holds its denominator share");
    }

    /// @notice Window (b) right edge: any stranger's permissionless recordScore self-clears the
    ///         stale pool's score — poolScore and totalScore both drop to zero, killing the
    ///         forward share (the EmissionDistributor L454 NatSpec claim, witnessed).
    function test_ZeroTvl_windowB_strangerRecordScoreSelfClears() public {
        sampler.setSeedBlock(POOL, startBlock - EMA_MATURITY);
        sampler.setLastUpdateBlock(POOL, startBlock);
        distributor.recordScore(POOL);
        assertEq(distributor.poolScore(POOL), 20_000e18, "scored while fresh");

        vm.roll(startBlock + EMA_STALENESS + 1);
        vm.prank(STRANGER);
        distributor.recordScore(POOL);
        assertEq(distributor.poolScore(POOL), 0, "stranger re-record self-clears the stale score");
        assertEq(distributor.totalScore(), 0, "forward share dies with the self-clear");
    }
}

/// @title ZeroTvlDrainDecayTest
/// @notice PB2.13h — window (a) quantifier on the REAL EMASampler: a drained-but-still-sampled
///         pool's EMA decays by 59/61 per daily sample (the WK18 anti-pump smoothing running in
///         reverse), halving in ~21 daily samples and reaching under 5% by 90 — bounding how long
///         a drained pool's genuine decay tail can earn before decay, staleness (14d unsampled,
///         F-10), or a re-record zeroes it.
contract ZeroTvlDrainDecayTest is Test {
    EMASampler internal sampler;
    MockTVLOracleDrain internal oracle;

    address internal constant POOL = address(0xD1);
    uint256 internal constant START_BLOCK = 720_000;
    uint256 internal constant SEED_TVL = 16_000e18;

    function setUp() public {
        oracle = new MockTVLOracleDrain();
        sampler = new EMASampler(ITVLOracle(address(oracle)));
        vm.roll(START_BLOCK);
    }

    /// @notice 21 daily zero-spot samples halve the EMA (within 49-51% of seed); 90 leave < 5%.
    ///         Explicit local block counter per the F10 optimizer-hoist lesson.
    function test_ZeroTvl_windowA_drainDecayHalfLife() public {
        oracle.set(SEED_TVL);
        sampler.updateEMA(POOL);
        assertEq(sampler.tvlEMA(POOL), SEED_TVL, "seeded at spot");

        oracle.set(0);
        uint256 blk = START_BLOCK;
        for (uint256 i = 0; i < 21; ++i) {
            blk += AureumTime.BLOCKS_PER_DAY;
            vm.roll(blk);
            sampler.updateEMA(POOL);
        }
        uint256 emaAt21 = sampler.tvlEMA(POOL);
        assertGt(emaAt21, (SEED_TVL * 49) / 100, "half-life lower bound at 21 daily samples");
        assertLt(emaAt21, (SEED_TVL * 51) / 100, "half-life upper bound at 21 daily samples");

        for (uint256 i = 21; i < 90; ++i) {
            blk += AureumTime.BLOCKS_PER_DAY;
            vm.roll(blk);
            sampler.updateEMA(POOL);
        }
        assertLt(sampler.tvlEMA(POOL), SEED_TVL / 20, "under 5% of seed by 90 daily samples");
    }
}

/// @title ZeroTvlDustCaptureTest
/// @notice PB2.13h — window (c) quantifier: a live dust LP unit (1 wei, so H-D24 stranding never
///         fires) captures the pool's ENTIRE tranche allocation while the score lives — wei-exact,
///         since divDown(1)/mulDown(1) round-trips the per-LP accumulator losslessly — and the
///         capture STOPS at the permissionless self-clear. In production the captured magnitude
///         is bounded by windows (a) + (b): what earns here is the drained pool's decaying or
///         stale score tail, not fresh TVL.
contract ZeroTvlDustCaptureTest is Test {
    MockEMASampler internal sampler;
    MockGaugeRegistry internal gauges;
    MockCCBMultiplier internal mult;
    MockEfficiencyOracle internal effOracle;
    MockMiliariumRegistry internal miliReg;
    MockAuMM internal aumm;
    EmissionDistributorHarness internal distributor;
    AuMMMinterRouter internal router;

    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant EMA_MATURITY = 60 * AureumTime.BLOCKS_PER_DAY;
    uint256 internal constant EMA_STALENESS = AureumTime.BLOCKS_PER_EPOCH;
    uint256 internal constant EMA_VALUE = 16_000e18;

    address internal POOL;
    address internal constant GOV = address(0x9011);
    address internal constant AUMT_REC = address(0xAEC);
    address internal constant DUST_USER = address(0xD05);
    address internal constant STRANGER = address(0xBAD);
    address internal constant DUMMY_CHANNEL = address(0xC4A9);

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
            GOV,
            address(new MockRegisteredVault())
        );

        router = new AuMMMinterRouter(IAuMM(address(aumm)), DUMMY_CHANNEL, address(distributor));
        aumm.setMinter(address(router));
        vm.prank(GOV);
        distributor.setMintRouter(address(router));
        effOracle.setEmissionsRecorder(address(distributor));

        // F-17 / P-D18 idiom: a real BPT contract with a large live balance keeps _syncDown a no-op.
        POOL = address(new MockBpt());
        MockBpt(POOL).mint(DUST_USER, 1e30);
        vm.prank(GOV);
        distributor.setAuMTContractForPool(POOL, AUMT_REC);

        gauges.setApproved(POOL, true);
        mult.setMultiplier(POOL, 1e18);
        sampler.setTvlEMA(POOL, EMA_VALUE);

        // Continuous regime, sole scored pool: the dust holder's share of the pool is 100%.
        startBlock = AureumTime.year1EndBlock(GENESIS_BLOCK) + 1;
        vm.roll(startBlock);
    }

    /// @notice The dust unit captures the full LP tranche wei-exactly while the stale score
    ///         lives, keeps capturing until the self-clear settle, and captures nothing after.
    function test_ZeroTvl_windowC_dustCapturesUntilSelfClear() public {
        sampler.setSeedBlock(POOL, startBlock - EMA_MATURITY);
        sampler.setLastUpdateBlock(POOL, startBlock);
        distributor.recordScore(POOL);
        assertEq(distributor.poolScore(POOL), EMA_VALUE, "sole pool scored while fresh");

        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL, DUST_USER, 1);

        // Leg 1 — capture while the (now stale) score persists: one epoch of accrual.
        // TWO claims per PP-D47: the leg spans EMA_STALENESS + 1 blocks because the staleness
        // gate is a strict >, while one accrual releases at most MAX_ACCRUAL_SPAN_BLOCKS, which
        // is that same BLOCKS_PER_EPOCH. The first call drains the epoch and the second the one
        // remaining block; the tranche captured is unchanged and only the call count moved.
        uint256 t1 = startBlock + EMA_STALENESS + 1;
        vm.roll(t1);
        vm.prank(DUST_USER);
        distributor.claim(POOL, DUST_USER);
        vm.prank(DUST_USER);
        distributor.claim(POOL, DUST_USER);
        uint256 leg1 = aumm.balanceOf(DUST_USER);
        // Accrual covers the half-open (startBlock, t1] (lastAccrualBlock sits at startBlock
        // after the deposit); extLpTrancheIntegral is inclusive-inclusive, so anchor at +1.
        uint256 integral1 = distributor.extLpTrancheIntegral(startBlock + 1, t1);
        assertGt(integral1, 0, "rig liveness: nonzero tranche over the interval");
        assertEq(leg1, integral1, "1 wei of dust captures the FULL tranche while the score lives");

        // Leg 2 — the stranger's self-clear settles the pool through t2, then kills the score.
        uint256 t2 = t1 + EMA_STALENESS;
        vm.roll(t2);
        vm.prank(STRANGER);
        distributor.recordScore(POOL);
        assertEq(distributor.poolScore(POOL), 0, "self-cleared");

        // Leg 3 — after the self-clear, a further epoch accrues NOTHING to the pool.
        uint256 t3 = t2 + EMA_STALENESS;
        vm.roll(t3);
        vm.prank(DUST_USER);
        distributor.claim(POOL, DUST_USER);
        assertEq(
            aumm.balanceOf(DUST_USER),
            distributor.extLpTrancheIntegral(startBlock + 1, t2),
            "capture ends at the self-clear: the post-clear epoch pays zero"
        );
    }
}
