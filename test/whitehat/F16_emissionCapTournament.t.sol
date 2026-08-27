// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {GaugeRegistry} from "src/gauge/GaugeRegistry.sol";
import {GaugeEligibility} from "src/gauge/GaugeEligibility.sol";
import {EmissionDistributorHarness} from "test/unit/harness/EmissionDistributorHarness.sol";

import {IAuMM} from "src/token/IAuMM.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

import {MockAuMM, MockEMASampler, MockCCBMultiplier, MockMiliariumRegistry} from "test/unit/EmissionDistributor.t.sol";
import {MockEfficiencyOracle} from "test/fork/mocks/StageGMocks.sol";
import {MockRegisteredVault} from "../mocks/MockRegisteredVault.sol";

/// @notice F-16 end-to-end PoC (P-D17) — the emission-cap tournament SEAM: a flash-spiked TVL seed
///         inflates a fee-less pool's F-5 score toward a dominant emission share, but the REAL gauge
///         stack (GaugeRegistry.advanceTournament driving GaugeEligibility.computeEpochSnapshot) ranks it
///         bottom-5% by efficiency and assigns a 10 bps (0.1%) cap, which the REAL
///         EmissionDistributor.recordScore clamp reads through IGaugeRegistry and enforces — holding the
///         attacker's share at or below 0.1% of emissions regardless of the seed magnitude. Standalone
///         real-stack build per P-D17: the gauge stack is real, 20 synthetic gauges are admitted via the
///         onlyGovernance seedFoundingPools eligibility bypass (no mainnet fork), and the spiked seed is
///         represented by the always-fresh MockEMASampler (F04 already proves the real spot-TVL-to-EMA
///         manipulability).
contract F16_EmissionCapTournamentTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    address internal constant GOV = address(0x9011);
    address internal constant PLACEHOLDER = address(0xDEAD);

    MockAuMM internal aumm;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockMiliariumRegistry internal miliReg;
    MockEfficiencyOracle internal effOracle;
    GaugeEligibility internal gaugeElig;
    GaugeRegistry internal gaugeRegistry;
    EmissionDistributorHarness internal distributor;

    address[] internal pools;
    address internal attacker;

    function setUp() public {
        aumm = new MockAuMM();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        miliReg = new MockMiliariumRegistry();
        effOracle = new MockEfficiencyOracle();

        // Real gauge stack (G-D22 deploy order): GaugeEligibility first, GaugeRegistry second, then setGaugeRegistry.
        gaugeElig = new GaugeEligibility(
            PLACEHOLDER,          // approvedFactory_ (unused — tournament path bypasses evaluateEligibility)
            PLACEHOLDER,          // vaultClassRegistry_
            PLACEHOLDER,          // tvlOracle_
            PLACEHOLDER,          // vault_
            PLACEHOLDER,          // auMM_
            address(this),        // gaugeRegistrySetter_ (this test calls setGaugeRegistry)
            address(effOracle),   // efficiencyOracle_ (real ranking input source)
            PLACEHOLDER,          // feeRoutingHook_
            PLACEHOLDER           // admissionAuthority_ (unused in the tournament path)
        );
        gaugeRegistry = new GaugeRegistry(
            GOV,                  // governance (seedFoundingPools caller)
            address(gaugeElig),   // eligibility_
            PLACEHOLDER,          // swapAndDeposit_ (unused — activateGauge path bypassed)
            PLACEHOLDER,          // svZCHF_
            GENESIS_BLOCK         // genesisBlock_ (must equal distributor GENESIS_BLOCK — P-D14 (1) / P-D16 (3))
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

        // 20 synthetic gauges; efficiency DESCENDING with index so pools[0] is most efficient (uncapped,
        // recorded first — avoids the S_other == 0 clamp degenerate), pools[19] the attacker.
        for (uint256 i = 0; i < 20; i++) {
            pools.push(address(uint160(0xA00000 + i)));
        }
        attacker = pools[19];

        for (uint256 i = 0; i < 19; i++) {
            effOracle.setEfficiencyInputs(pools[i], (20 - i) * 1e18, 1e18); // ratio (20-i)*1e18, all above attacker
            mult.setMultiplier(pools[i], 1e18);
            ema.setTVLEMA(pools[i], 100e18);
        }
        // Attacker: fee-less (numeratorSma ~ 0) but emission-receiving (denominatorSma > 0, else post-warmup
        // skip), with a flash-spiked TVL seed. efficiencyRatio == 1, uniquely worst, so bottom-5%.
        effOracle.setEfficiencyInputs(attacker, 1, 1e18);
        mult.setMultiplier(attacker, 1e18);
        ema.setTVLEMA(attacker, 1e30);

        vm.prank(GOV);
        gaugeRegistry.seedFoundingPools(pools);

        vm.roll(GENESIS_BLOCK);
    }

    /// @dev Drives the real tournament past its SMOOTHING_EPOCHS = 3 warmup: advance 1 sets
    ///      firstTournamentEpoch for all 20 (skipped); advances 2-3 are warmup-skips; advance 4
    ///      (newEpoch - first == 3) ranks all 20 and writes poolEmissionCapBps. Each advance lands in a
    ///      distinct epoch past the month-13 activation gate.
    function _runTournamentToCaps() internal {
        uint256 currentBlock = AureumTime.year1EndBlock(GENESIS_BLOCK) + 1;
        vm.roll(currentBlock);
        gaugeRegistry.advanceTournament();
        for (uint256 k = 0; k < 3; k++) {
            currentBlock += AureumTime.BLOCKS_PER_EPOCH;
            vm.roll(currentBlock);
            gaugeRegistry.advanceTournament();
        }
    }

    /// @notice The real tournament assigns the floor-percentile caps (P-D15 (1)) to the least-efficient
    ///         gauges — the fee-less attacker lands bottom-5% (10 bps), the next two worst honest pools draw
    ///         50 / 100 bps, and a top pool stays uncapped — confirming on-chain the tier arithmetic that
    ///         F16g-1 unit-tested against GaugeEligibility directly.
    function test_F16_TournamentAssignsFloorTiersToLeastEfficient() public {
        _runTournamentToCaps();
        assertEq(gaugeElig.poolEmissionCapBps(attacker), 10);   // bottom 5%
        assertEq(gaugeElig.poolEmissionCapBps(pools[18]), 50);  // bottom 10-5%
        assertEq(gaugeElig.poolEmissionCapBps(pools[17]), 100); // bottom 15-10%
        assertEq(gaugeElig.poolEmissionCapBps(pools[0]), 0);    // top 85%
    }

    /// @notice The full F-16 seam — the tournament-assigned 10 bps cap flows through IGaugeRegistry into the
    ///         recordScore clamp, holding the flash-seeded attacker's emission share at or below 0.1% even
    ///         though its raw, unclamped F-5 score dwarfs the entire scored total. Honest pools recorded
    ///         first build S_other; the attacker recorded last is clamped to capT / 1e18 = 0.1% of the total.
    function test_F16_SpikedSeedCappedToBottomFiveTierShare() public {
        _runTournamentToCaps();

        for (uint256 i = 0; i < 19; i++) {
            distributor.recordScore(pools[i]);
        }
        distributor.recordScore(attacker);

        // (a) the cap the distributor reads is the real tournament's bottom-5% assignment, via delegation.
        assertEq(gaugeRegistry.poolEmissionCapBps(attacker), 10);

        // (b) attacker emission share = poolScore / totalScore at or below 0.1% (1e15 in 1e18 fixed-point).
        uint256 attackerScore = distributor.poolScore(attacker);
        uint256 total = distributor.totalScore();
        assertLe(attackerScore * 1e18 / total, 1e15);

        // (c) uncapped counterfactual — the raw F-5 score would have dominated emissions absent the cap.
        assertGt(distributor.f5Score(attacker), total);
    }
}
