// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AuMM} from "src/token/AuMM.sol";
import {IAuMM} from "src/token/IAuMM.sol";
import {EmissionDistributor} from "src/emission/EmissionDistributor.sol";
import {IEmissionDistributor} from "src/emission/IEmissionDistributor.sol";
import {VotingWeight} from "src/governance/VotingWeight.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {MockEMASampler, MockGaugeRegistry, MockMiliariumRegistry} from "test/unit/VotingWeight.t.sol";
import {MockBpt, MockCCBMultiplier, MockEfficiencyOracle} from "test/unit/EmissionDistributor.t.sol";

/// @title P1 B.3 — share denominator omits unrecorded seed
/// @notice Reproduction PoC for seam-1 root cause B.3 (High). Covers the seed-omission face only;
///         the flash-inflation face requires the real Vault and lands separately.
contract P1_B3_ShareDenominatorOmitsUnrecordedSeedTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant SEED_BPT = 99e18;
    uint256 internal constant HOLDER_BPT = 1e18;
    uint256 internal constant TOTAL_BPT = 100e18;
    uint256 internal constant TVL_EMA = 16e18;
    /// @dev A block number captured from a live `block.number` read and reused as a call argument
    ///      after an intervening `vm.roll` is unreliable under this profile's optimizer settings —
    ///      the argument was observed to silently resolve to the post-roll block instead of the
    ///      captured one. A compile-time constant removes the hazard entirely, matching
    ///      test/whitehat/P1_B2.t.sol's MATURED_BLOCK precedent.
    uint256 internal constant MATURED_BLOCK = GENESIS_BLOCK + AureumTime.ON_RAMP_PERIOD_BLOCKS;

    AuMM internal aumm;
    MockGaugeRegistry internal gauges;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockEfficiencyOracle internal effOracle;
    MockMiliariumRegistry internal miliReg;
    MockBpt internal seededBpt;
    MockBpt internal controlBpt;
    EmissionDistributor internal distributor;
    VotingWeight internal vw;

    address internal aumtSeeded;
    address internal aumtControl;
    address internal seeder;
    address internal holder;
    address internal controlHolder;
    address internal stranger;

    function setUp() public {
        aumm = new AuMM(GENESIS_BLOCK, address(this));
        gauges = new MockGaugeRegistry();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        effOracle = new MockEfficiencyOracle();
        miliReg = new MockMiliariumRegistry();
        seededBpt = new MockBpt();
        controlBpt = new MockBpt();

        aumtSeeded = makeAddr("aumtSeeded");
        aumtControl = makeAddr("aumtControl");
        seeder = makeAddr("seeder");
        holder = makeAddr("holder");
        controlHolder = makeAddr("controlHolder");
        stranger = makeAddr("stranger");

        distributor = new EmissionDistributor(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK,
            address(this)
        );

        vw = new VotingWeight(
            ema,
            gauges,
            IEmissionDistributor(address(distributor)),
            miliReg,
            GENESIS_BLOCK
        );

        effOracle.setEmissionsRecorder(address(distributor));
        distributor.setAuMTContractForPool(address(seededBpt), aumtSeeded);
        distributor.setAuMTContractForPool(address(controlBpt), aumtControl);

        gauges.setApproved(address(seededBpt), true);
        gauges.setApproved(address(controlBpt), true);
        miliReg.setMiliarium(address(seededBpt), true);
        miliReg.setMiliarium(address(controlBpt), true);
        address[] memory pools = new address[](2);
        pools[0] = address(seededBpt);
        pools[1] = address(controlBpt);
        miliReg.setPoolList(pools);
        mult.setMultiplier(address(seededBpt), 1e18);
        mult.setMultiplier(address(controlBpt), 1e18);

        // Seed ancient enough that maturity still holds after the on-ramp roll.
        ema.setTvlEMA(address(seededBpt), TVL_EMA);
        ema.setSeedBlock(address(seededBpt), 1);
        ema.setLastUpdateBlock(address(seededBpt), GENESIS_BLOCK);
        ema.setTvlEMA(address(controlBpt), TVL_EMA);
        ema.setSeedBlock(address(controlBpt), 1);
        ema.setLastUpdateBlock(address(controlBpt), GENESIS_BLOCK);

        vm.roll(GENESIS_BLOCK);
    }

    /// @dev Models pool initialization minting seed BPT under a hook with no initialize callback,
    ///      then records only the first depositor's stake through the real recorder.
    function _setupSeededPool() internal {
        seededBpt.mint(seeder, SEED_BPT);
        seededBpt.mint(holder, HOLDER_BPT);
        vm.prank(aumtSeeded);
        distributor.recordDeposit(address(seededBpt), holder, HOLDER_BPT);
    }

    /// @dev Control pool with no unrecorded seed: the sole holder is fully recorded.
    function _setupControlPool() internal {
        controlBpt.mint(controlHolder, HOLDER_BPT);
        vm.prank(aumtControl);
        distributor.recordDeposit(address(controlBpt), controlHolder, HOLDER_BPT);
    }

    /// @dev Roll past the on-ramp and restamp EMA freshness on both pools.
    function _matureBothPools() internal {
        vm.roll(MATURED_BLOCK);
        ema.setLastUpdateBlock(address(seededBpt), block.number);
        ema.setLastUpdateBlock(address(controlBpt), block.number);
    }

    /// @dev Pins that a one-percent holder weighs as much as the sole holder of a whole pool.
    function test_P1_B3_unrecordedSeedLetsAOnePercentHolderWeighAsMuchAsASolePool() public {
        _setupSeededPool();
        _setupControlPool();
        _matureBothPools();

        assertEq(seededBpt.totalSupply(), TOTAL_BPT, "seeded pool BPT supply includes unrecorded seed");
        assertEq(
            distributor.poolTotalLP(address(seededBpt)),
            HOLDER_BPT,
            "recorder tally omits the unrecorded seed BPT"
        );
        assertEq(
            seededBpt.balanceOf(holder) * 100,
            seededBpt.totalSupply(),
            "holder is exactly one percent of the pool by BPT balance"
        );

        vw.poke(holder);
        vw.poke(controlHolder);

        uint256 seededWeight = vw.governanceWeight(holder);
        uint256 controlWeight = vw.governanceWeight(controlHolder);
        assertGt(seededWeight, 0, "seeded-pool holder carries governance weight");
        assertGt(controlWeight, 0, "control holder carries governance weight");
        assertEq(
            seededWeight,
            controlWeight,
            "one-percent holder matches sole holder of a whole pool"
        );
    }

    /// @dev Pins that syncPosition cannot admit the omitted seed because _syncDown is downward-only.
    function test_P1_B3_thePermissionlessReconcilerIsDownwardOnlyAndCanNeverAdmitTheSeed() public {
        _setupSeededPool();
        _setupControlPool();
        _matureBothPools();

        uint256 poolTotalBefore = distributor.poolTotalLP(address(seededBpt));
        assertEq(poolTotalBefore, HOLDER_BPT, "baseline recorder tally excludes seed");

        vm.prank(stranger);
        distributor.syncPosition(address(seededBpt), seeder);

        vm.prank(stranger);
        distributor.syncPosition(address(seededBpt), holder);

        assertEq(
            distributor.poolTotalLP(address(seededBpt)),
            poolTotalBefore,
            "downward-only reconciler cannot admit unrecorded seed for seeder"
        );
        assertEq(
            distributor.userLP(address(seededBpt), seeder),
            0,
            "seeder still has zero recorded stake after syncPosition"
        );
        assertEq(
            distributor.userLP(address(seededBpt), holder),
            HOLDER_BPT,
            "holder recorded stake unchanged after syncPosition"
        );
    }
}
