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
import {MockRegisteredVault} from "../mocks/MockRegisteredVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

/// @title P1 B.3 — share denominator: unrecorded seed and flash inflation
/// @notice Seam-1 root cause B.3 (High). The two seed-omission cases stay as pins of the pre-fix
///         construction, the fix being procedural: the seed recorded through the trusted Router per
///         PP-D58 (iii), witnessed on the fork. The last case is the flash-face regression, the
///         governance denominator clamped to live supply per PP-D58 (iv) and (xv).
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
            address(this),
            address(new MockRegisteredVault())
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

    /// @notice B.3 / PP-D58 (iv) regression: with the seed recorded, a trusted add that is then
    ///         burned through an exit the recorder never sees leaves the tally above live supply, and
    ///         a stranger's forced poke of an honest holder banks the weight it banks at rest, because
    ///         VotingWeight divides by min(poolTotalLP, totalSupply). A burnable pool token stands in
    ///         for the Vault's burn on the untrusted exit, which the fork witness covers separately.
    function test_forcedPokeCannotBankAFlashInflatedDenominator() public {
        MockERC20 flashBpt = new MockERC20("Flash BPT", "FBPT", 18);
        address aumtFlash = makeAddr("aumtFlash");
        address attacker = makeAddr("attacker");
        distributor.setAuMTContractForPool(address(flashBpt), aumtFlash);
        gauges.setApproved(address(flashBpt), true);
        miliReg.setMiliarium(address(flashBpt), true);
        address[] memory pools = new address[](1);
        pools[0] = address(flashBpt);
        miliReg.setPoolList(pools);
        ema.setTvlEMA(address(flashBpt), TVL_EMA);
        ema.setSeedBlock(address(flashBpt), 1);
        ema.setLastUpdateBlock(address(flashBpt), GENESIS_BLOCK);

        // The seed is recorded through the trusted path per PP-D58 (iii), and so is an honest holder.
        flashBpt.mint(seeder, SEED_BPT);
        vm.prank(aumtFlash);
        distributor.recordDeposit(address(flashBpt), seeder, SEED_BPT);
        flashBpt.mint(holder, HOLDER_BPT);
        vm.prank(aumtFlash);
        distributor.recordDeposit(address(flashBpt), holder, HOLDER_BPT);
        assertEq(
            distributor.poolTotalLP(address(flashBpt)),
            flashBpt.totalSupply(),
            "at rest the recorded tally equals live supply"
        );

        vm.roll(MATURED_BLOCK);
        ema.setLastUpdateBlock(address(flashBpt), MATURED_BLOCK);
        vm.prank(stranger);
        vw.poke(holder);
        uint256 atRest = vw.governanceWeight(holder);
        assertGt(atRest, 0, "the honest holder carries weight at rest");

        // The flash: an add the trusted path records, then a burn through an exit it never sees.
        uint256 flash = 1_000_000e18;
        flashBpt.mint(attacker, flash);
        vm.prank(aumtFlash);
        distributor.recordDeposit(address(flashBpt), attacker, flash);
        flashBpt.burn(attacker, flash);
        assertEq(
            distributor.poolTotalLP(address(flashBpt)),
            flashBpt.totalSupply() + flash,
            "the recorded tally now sits above live supply by the flashed amount"
        );

        vm.prank(stranger);
        vw.poke(holder);
        assertEq(
            vw.governanceWeight(holder),
            atRest,
            "a forced poke banks the at-rest weight, not the collapse the inflated tally would give"
        );
    }
}
