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

/// @title P1 B.2 — closed position keeps a full voting checkpoint
/// @notice Reproduction PoC for seam-1 root cause B.2 (High). `recordWithdrawal` writes only
///         EmissionDistributor storage and never touches VotingWeight, so a poked holder's
///         checkpoint and the past total supply survive a full exit until a discretionary poke.
contract P1_B2_StaleVotingWeightPersistsAfterWithdrawalTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant STAKE = 100e18;
    uint256 internal constant TVL_EMA = 16e18;
    /// @dev A block number captured from a live `block.number` read and reused as a call argument
    ///      after an intervening `vm.roll` is unreliable under this profile's optimizer settings —
    ///      the argument was observed to silently resolve to the post-roll block instead of the
    ///      captured one. A compile-time constant removes the hazard entirely, matching
    ///      test/whitehat/P1_B1.t.sol's START_BLOCK precedent.
    uint256 internal constant MATURED_BLOCK = GENESIS_BLOCK + AureumTime.ON_RAMP_PERIOD_BLOCKS;

    AuMM internal aumm;
    MockGaugeRegistry internal gauges;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockEfficiencyOracle internal effOracle;
    MockMiliariumRegistry internal miliReg;
    MockBpt internal bpt;
    EmissionDistributor internal distributor;
    VotingWeight internal vw;

    address internal aumt;
    address internal holder;
    address internal stranger;
    address internal sink;

    function setUp() public {
        aumm = new AuMM(GENESIS_BLOCK, address(this));
        gauges = new MockGaugeRegistry();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        effOracle = new MockEfficiencyOracle();
        miliReg = new MockMiliariumRegistry();
        bpt = new MockBpt();

        aumt = makeAddr("aumt");
        holder = makeAddr("holder");
        stranger = makeAddr("stranger");
        sink = makeAddr("sink");

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
        distributor.setAuMTContractForPool(address(bpt), aumt);

        gauges.setApproved(address(bpt), true);
        miliReg.setMiliarium(address(bpt), true);
        address[] memory pools = new address[](1);
        pools[0] = address(bpt);
        miliReg.setPoolList(pools);
        mult.setMultiplier(address(bpt), 1e18);

        // Seed ancient enough that maturity still holds after the on-ramp roll.
        ema.setTvlEMA(address(bpt), TVL_EMA);
        ema.setSeedBlock(address(bpt), 1);
        ema.setLastUpdateBlock(address(bpt), GENESIS_BLOCK);

        vm.roll(GENESIS_BLOCK);
    }

    /// @dev Mint BPT, record the deposit, roll past the on-ramp so timeFactor is 1.0, then restamp EMA freshness.
    function _openMaturedPosition() internal {
        bpt.mint(holder, STAKE);
        vm.prank(aumt);
        distributor.recordDeposit(address(bpt), holder, STAKE);

        vm.roll(MATURED_BLOCK);
        // Without this restamp every poke returns zero after the on-ramp roll outruns EMA freshness.
        ema.setLastUpdateBlock(address(bpt), block.number);
    }

    /// @dev Pins that a full exit leaves the VotingWeight checkpoint intact until a stranger pokes.
    function test_P1_B2_fullWithdrawalLeavesAFullWeightCheckpointUntilAStrangerPokes() public {
        _openMaturedPosition();

        vw.poke(holder);
        uint256 weightBefore = vw.governanceWeight(holder);
        assertGt(weightBefore, 0, "matured position confers governance weight");

        uint256 pokeBlock = MATURED_BLOCK;
        vm.roll(pokeBlock + 1);
        assertEq(vw.getPastTotalSupply(pokeBlock), weightBefore, "past total supply tracks the poke");

        vm.prank(holder);
        bpt.transfer(sink, STAKE);
        vm.prank(aumt);
        distributor.recordWithdrawal(address(bpt), holder, STAKE);

        assertEq(distributor.userLP(address(bpt), holder), 0, "distributor stake is cleared");
        assertEq(
            distributor.effectiveQualBlock(address(bpt), holder),
            0,
            "distributor qualification clock is zeroed"
        );
        assertEq(
            vw.governanceWeight(holder),
            weightBefore,
            "VotingWeight checkpoint survives the withdrawal"
        );
        assertEq(
            vw.getPastTotalSupply(pokeBlock),
            weightBefore,
            "past total supply still reports the pre-withdrawal weight"
        );

        // Self-heal requires a discretionary third-party poke; the withdrawal path never triggers it.
        vm.prank(stranger);
        vw.poke(holder);

        assertEq(vw.governanceWeight(holder), 0, "stranger poke collapses the stale checkpoint");
        assertEq(vw.totalSupply(), 0, "live total supply collapses with the checkpoint");
    }

    /// @dev Pins that a poke one block after withdrawal cannot rewrite the withdrawal-block snapshot.
    function test_P1_B2_withdrawalAtTheSnapshotBlockCannotBeCounteredByALaterPoke() public {
        _openMaturedPosition();

        vw.poke(holder);
        uint256 weightBefore = vw.governanceWeight(holder);
        assertGt(weightBefore, 0, "matured position confers governance weight");

        uint256 withdrawalBlock = MATURED_BLOCK;
        vm.prank(holder);
        bpt.transfer(sink, STAKE);
        vm.prank(aumt);
        distributor.recordWithdrawal(address(bpt), holder, STAKE);

        vm.roll(withdrawalBlock + 1);
        vm.prank(stranger);
        vw.poke(holder);

        assertEq(vw.governanceWeight(holder), 0, "live weight is zero after the late poke");
        assertEq(
            vw.getPastVotes(holder, withdrawalBlock),
            weightBefore,
            "withdrawal-block snapshot still counts the closed position"
        );
    }
}
