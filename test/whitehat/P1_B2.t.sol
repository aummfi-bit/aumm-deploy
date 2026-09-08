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
        distributor.setAuMTContractForPool(address(bpt), aumt);
        // B.2 / PP-D55 (vii) — the one-shot Stage-K sink seat, wired here so recordWithdrawal and
        // _syncDown reach VotingWeight. Governance is address(this), set at line 72.
        distributor.setVotingWeight(address(vw));

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

    /// @dev B.2 done-criteria case. The honest exit clears the checkpoint and the quorum denominator
    ///      inside the withdrawal transaction: `recordWithdrawal` pushes `onPositionClosed` per
    ///      PP-D55 (vi), so no third party is left with anything to heal. `_syncDown` no-ops on this
    ///      path, because the caller passes the pre-debit live total and `recorded <= referenceBalance`
    ///      holds, which is exactly why the explicit push is required rather than redundant.
    function test_withdrawalClearsVotingWeight() public {
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
        // The fix: both live reads collapse inside the withdrawal transaction, with no poke between.
        assertEq(vw.governanceWeight(holder), 0, "checkpoint not cleared by the withdrawal");
        assertEq(vw.totalSupply(), 0, "quorum denominator not cleared by the withdrawal");

        // History is NOT rewritten: a proposal snapshotted before the exit still reads the weight
        // that was genuinely qualified at that block, which is what F-06 depends on.
        assertEq(
            vw.getPastTotalSupply(pokeBlock),
            weightBefore,
            "the pre-withdrawal snapshot must not be rewritten"
        );

        // Coda: the stranger poke that used to be the only cure now has nothing left to heal.
        vm.prank(stranger);
        vw.poke(holder);
        assertEq(vw.governanceWeight(holder), 0, "poke moved a checkpoint the withdrawal had cleared");
        assertEq(vw.totalSupply(), 0, "poke moved a denominator the withdrawal had cleared");
    }

    /// @dev The same-block face of the fix, and the one a later poke structurally cannot deliver.
    ///      `recordWithdrawal` pushes the close inside the withdrawal transaction, so the zero lands
    ///      at the withdrawal block's own key, and `Checkpoints.Trace208` OVERWRITES on an equal key
    ///      rather than appending. A poke one block later writes a strictly greater key and can never
    ///      reach back, which is why the reproduction this replaces was right about the poke and
    ///      wrong about the harm: the cure was never going to come from the poke side at all.
    function test_withdrawalZeroesTheSameBlockSnapshotWithoutAPoke() public {
        _openMaturedPosition();

        vw.poke(holder);
        uint256 weightBefore = vw.governanceWeight(holder);
        assertGt(weightBefore, 0, "matured position confers governance weight");

        uint256 withdrawalBlock = MATURED_BLOCK;
        vm.prank(holder);
        bpt.transfer(sink, STAKE);
        vm.prank(aumt);
        distributor.recordWithdrawal(address(bpt), holder, STAKE);

        // Asserted BEFORE any poke: the withdrawal alone did this, with no third party involved.
        vm.roll(withdrawalBlock + 1);
        assertEq(
            vw.getPastVotes(holder, withdrawalBlock),
            0,
            "withdrawal-block snapshot still counts the closed position"
        );
        assertEq(
            vw.getPastTotalSupply(withdrawalBlock),
            0,
            "withdrawal-block denominator still counts the closed position"
        );

        // A later poke has nothing to add: it writes a strictly greater key and the snapshot holds.
        vm.prank(stranger);
        vw.poke(holder);
        assertEq(vw.getPastVotes(holder, withdrawalBlock), 0, "the later poke moved the snapshot");
        assertEq(vw.governanceWeight(holder), 0, "live weight is zero after the late poke");
    }
}
