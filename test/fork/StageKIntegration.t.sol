// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { StageIIntegrationFixture } from "./StageIIntegration.t.sol";
import { IEMASampler } from "../../src/ccb/IEMASampler.sol";
import { MiliariumRegistry } from "../../src/registry/MiliariumRegistry.sol";
import { VotingWeight } from "../../src/governance/VotingWeight.sol";
import { AureumGovernance } from "../../src/governance/AureumGovernance.sol";
import { AureumTime } from "../../src/lib/AureumTime.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

/**
 * @title StageKIntegrationFixture
 * @notice Stage K fork-test base — inherits the Stage I recorder-clock stack (real `EmissionDistributor`
 *         bound to the `AureumFeeRoutingHook` one-shot `emissionRecorder`, per-pool recorder gate admitting
 *         `address(hook)`, real `TVLOracle`, real `GaugeRegistry`, AuMM / Bodensee / 3 pilots, and the
 *         `_depositOneSided` / `_withdrawProportional` / `getSender()` IRouterSender-shim helpers).
 * @dev Deploys a fresh real `MiliariumRegistry` serving BOTH `VotingWeight.REGISTRY` and
 *      `AureumGovernance.SLOT_REGISTRY` per J-D2 dual-interface, seeded at manifest slots [1, 5, 14].
 *      Seeds the 3 pilot gauges via `seedFoundingPool` (governance bypass) before the irreversible
 *      governance handoffs. Anchor: K4.7 design (STAGE_K_NOTES.md).
 */
abstract contract StageKIntegrationFixture is StageIIntegrationFixture {
    MiliariumRegistry internal realRegistry;
    VotingWeight internal votingWeight;
    AureumGovernance internal gov;

    function setUp() public virtual override {
        super.setUp();

        gaugeRegistry.seedFoundingPool(pilotPools[0]);
        gaugeRegistry.seedFoundingPool(pilotPools[1]);
        gaugeRegistry.seedFoundingPool(pilotPools[2]);

        uint256[] memory slots = new uint256[](3);
        slots[0] = 1;
        slots[1] = 5;
        slots[2] = 14;
        address[] memory pools = new address[](3);
        pools[0] = pilotPools[0];
        pools[1] = pilotPools[1];
        pools[2] = pilotPools[2];
        realRegistry = new MiliariumRegistry(address(this), slots, pools);

        votingWeight = new VotingWeight(IEMASampler(address(emaSampler)), gaugeRegistry, emissionDistributor, realRegistry, aumm.GENESIS_BLOCK());

        gov = new AureumGovernance(
            votingWeight,
            gaugeRegistry,
            realRegistry,
            vault,
            swapAndDeposit,
            svZchf,
            IERC20(address(susds)),
            bodenseePool
        );

        swapAndDeposit.addAuthorizedDonator(address(gov));

        gaugeRegistry.setGovernanceContract(address(gov));
        realRegistry.setGovernanceContract(address(gov));
    }

    /// @dev K6-deferred EMA shim — VotingWeight reads the 60-day `tvlEMA` behind the F-04
    ///      `EMA_MATURITY_BLOCKS` seed-age gate and the F-05 `EMA_STALENESS_BLOCKS` freshness
    ///      gate; the shim mocks `tvlEMA`, a mature `emaSeedBlock`, and a fresh
    ///      `lastEMAUpdateBlock` (stamped at `block.number`) to keep isolating the poke logic
    ///      under test from oracle pricing and EMA cadence (the R1 empty-roster rationale still
    ///      applies upstream).
    function _mockPoolEma(address pool, uint256 svzchfValue) internal {
        vm.mockCall(address(emaSampler), abi.encodeWithSelector(emaSampler.tvlEMA.selector, pool), abi.encode(svzchfValue));
        vm.mockCall(address(emaSampler), abi.encodeWithSelector(emaSampler.emaSeedBlock.selector, pool), abi.encode(uint256(1)));
        vm.mockCall(address(emaSampler), abi.encodeWithSelector(emaSampler.lastEMAUpdateBlock.selector, pool), abi.encode(block.number));
    }
}

contract StageKWiringTest is StageKIntegrationFixture {
    function test_setUp_stageKWiring() public view {
        assertEq(address(gov.VOTING_WEIGHT()), address(votingWeight));
        assertEq(address(gov.SLOT_REGISTRY()), address(realRegistry));
        assertEq(address(gov.GAUGE_REGISTRY()), address(gaugeRegistry));
        assertEq(address(gov.VAULT()), address(vault));
        assertEq(address(gov.BODENSEE_CHANNEL()), address(swapAndDeposit));
        assertEq(address(gov.SVZCHF()), address(svZchf));
        assertEq(address(gov.SUSDS()), address(susds));
        assertEq(gov.BODENSEE_POOL(), bodenseePool);

        assertEq(address(votingWeight.EMA_SAMPLER()), address(emaSampler));
        assertEq(address(votingWeight.GAUGE_REGISTRY()), address(gaugeRegistry));
        assertEq(address(votingWeight.RECORDER()), address(emissionDistributor));
        assertEq(address(votingWeight.REGISTRY()), address(realRegistry));
        assertEq(votingWeight.GENESIS_BLOCK(), aumm.GENESIS_BLOCK());

        assertTrue(gaugeRegistry.isGaugeApproved(pilotPools[0]));
        assertTrue(gaugeRegistry.isGaugeApproved(pilotPools[1]));
        assertTrue(gaugeRegistry.isGaugeApproved(pilotPools[2]));

        assertEq(realRegistry.poolAtSlot(1), pilotPools[0]);
        assertEq(realRegistry.poolAtSlot(5), pilotPools[1]);
        assertEq(realRegistry.poolAtSlot(14), pilotPools[2]);
        assertEq(realRegistry.miliariumPoolsCount(), 3);

        assertEq(realRegistry.governanceContract(), address(gov));
        assertTrue(swapAndDeposit.authorizedDonators(address(gov)));
    }
}

contract StageKVotingWeightPokeTest is StageKIntegrationFixture {
    function test_poke_postCliff_qualifiesNonZeroWeight() public {
        address lp = makeAddr("lpPostCliff");
        _depositOneSided(pilotPools[0], lp, 100);
        vm.roll(block.number + AureumTime.QUALIFICATION_PERIOD_BLOCKS + 1);
        _mockPoolEma(pilotPools[0], 1_000e18);
        votingWeight.poke(lp);
        assertGt(votingWeight.governanceWeight(lp), 0, "post-cliff poke confers nonzero weight");
        assertEq(votingWeight.totalSupply(), votingWeight.governanceWeight(lp), "single holder: total == holder weight (I-D17 exact fraction)");
    }

    function test_poke_preCliff_confersZeroWeight() public {
        address lp = makeAddr("lpPreCliff");
        _depositOneSided(pilotPools[0], lp, 100);
        vm.roll(block.number + AureumTime.QUALIFICATION_PERIOD_BLOCKS - 1);
        _mockPoolEma(pilotPools[0], 1_000e18);
        votingWeight.poke(lp);
        assertEq(votingWeight.governanceWeight(lp), 0, "sub-cliff poke confers zero weight");
        assertEq(votingWeight.totalSupply(), 0, "sub-cliff: no qualified weight in total");
    }

    function test_poke_afterGaugeRevoke_resetsToZero() public {
        address lp = makeAddr("lpRevoke");
        _depositOneSided(pilotPools[0], lp, 100);
        vm.roll(block.number + AureumTime.QUALIFICATION_PERIOD_BLOCKS + 1);
        _mockPoolEma(pilotPools[0], 1_000e18);
        votingWeight.poke(lp);
        assertGt(votingWeight.governanceWeight(lp), 0, "baseline qualified before revoke");
        vm.prank(address(gov));
        gaugeRegistry.revokeGauge(pilotPools[0]);
        votingWeight.poke(lp);
        assertEq(votingWeight.governanceWeight(lp), 0, "gauge revoke zeroes weight at the gauge gate");
        assertEq(votingWeight.totalSupply(), 0, "revoked-pool weight removed from total");
    }

    function test_poke_afterWithdrawal_resetsToZero() public {
        address lp = makeAddr("lpWithdraw");
        uint256 bptOut = _depositOneSided(pilotPools[0], lp, 100);
        vm.roll(block.number + AureumTime.QUALIFICATION_PERIOD_BLOCKS + 1);
        _mockPoolEma(pilotPools[0], 1_000e18);
        votingWeight.poke(lp);
        assertGt(votingWeight.governanceWeight(lp), 0, "baseline qualified before withdrawal");
        _lpSender = lp;
        _withdrawProportional(pilotPools[0], bptOut);
        votingWeight.poke(lp);
        assertEq(votingWeight.governanceWeight(lp), 0, "withdrawal resets weight at the eqb==0 gate");
        assertEq(votingWeight.totalSupply(), 0, "withdrawn-position weight removed from total");
    }

    /// @notice F-17 / P-D18 faithful end-to-end (S9) — proves the receipt invariant on the REAL stack with a real
    ///         BPT holder, unmasked. Clears the fixture's F-17 balanceOf no-op mock, hands the freshly-minted BPT
    ///         to the recorded LP (so balanceOf(lp) == userLP), and shows (a) an in-sync holder past the cliff
    ///         confers nonzero weight, then (b) moving the BPT out-of-band via a plain ERC-20 transfer — which
    ///         skips the recorder — drops balanceOf(lp) to zero and the VotingWeight._positionPower read-cap
    ///         forfeits the weight. This is the production path the other fork fixtures shortcut past (harness
    ///         holds the BPT); here the attributed LP genuinely holds its receipt.
    function test_F17_realBptHolder_weightTracksLiveBalance() public {
        vm.clearMockedCalls(); // drop the fixture-wide F-17 balanceOf no-op — this test reads the REAL live balance
        address pool = pilotPools[0];
        address lp = makeAddr("faithfulLp");

        uint256 bptOut = _depositOneSided(pool, lp, 100); // recorder credits lp; BPT is minted to the harness
        IERC20(pool).transfer(lp, bptOut);                // hand the receipt to the recorded LP: balanceOf(lp) == userLP
        assertEq(IERC20(pool).balanceOf(lp), emissionDistributor.userLP(pool, lp), "lp holds BPT == recorded userLP (in sync)");

        vm.roll(block.number + AureumTime.QUALIFICATION_PERIOD_BLOCKS + 1);
        _mockPoolEma(pool, 1_000e18);
        votingWeight.poke(lp);
        assertGt(votingWeight.governanceWeight(lp), 0, "real in-sync BPT holder confers nonzero weight");

        // Move the receipt out-of-band (plain ERC-20 transfer skips the recorder) — the read-cap must forfeit weight.
        vm.prank(lp);
        IERC20(pool).transfer(makeAddr("elsewhere"), bptOut);
        assertEq(IERC20(pool).balanceOf(lp), 0, "BPT moved out of lp");
        votingWeight.poke(lp);
        assertEq(votingWeight.governanceWeight(lp), 0, "F-17 read-cap: out-of-band-moved BPT forfeits weight on the real stack");
    }
}

contract StageKCompositionLifecycleTest is StageKIntegrationFixture {
    function test_compositionChallenge_endToEndLifecycle() public {
        // 1. Qualifying voter — real recorded deposit past the 14-day cliff; tvl mocked (K6 deferred, NOTES R1).
        address voter = makeAddr("voterComp");
        _depositOneSided(pilotPools[0], voter, 100);
        vm.roll(block.number + AureumTime.QUALIFICATION_PERIOD_BLOCKS + 1);
        _mockPoolEma(pilotPools[0], 1_000e18);
        votingWeight.poke(voter);
        assertGt(votingWeight.governanceWeight(voter), 0, "voter qualified");

        // 2. Propose a composition challenge — replace slot 5 (ixEdelweiss) with a synthetic candidate.
        uint256 slot = 5;
        address candidate = makeAddr("candidatePool");
        vm.mockCall(address(gaugeRegistry), abi.encodeWithSignature("meetsCompositionQualityGate(address)", candidate), abi.encode(true));
        address oldPool = realRegistry.poolAtSlot(slot);
        assertEq(oldPool, pilotPools[1], "slot 5 holds ixEdelweiss");
        deal(address(svZchf), address(this), 1_000e18); // PROPOSAL_DEPOSIT_SVZCHF
        svZchf.approve(address(gov), 1_000e18);
        uint256 id = gov.proposeCompositionChallenge(slot, candidate, svZchf);

        // 3. Roll into the Active window — past the F-06 voting-delay `snapshotBlock` — then vote FOR (single 100% turnout). The line-above `poke` (at `startBlock <= snapshotBlock`) is the checkpoint `getPastVotes` reads at the snapshot, so no re-poke is needed.
        AureumGovernance.Proposal memory pv = gov.getProposal(id);
        vm.roll(pv.snapshotBlock + 1);
        vm.prank(voter);
        gov.castVote(id, true);

        // 4. Close the voting window — quorum (20%) + 2/3 supermajority both met.
        vm.roll(pv.endBlock + 1);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Succeeded), "succeeded");

        // 5. Queue, roll to the timelock eta, execute.
        gov.queue(id);
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        vm.roll(p.eta);
        gov.execute(id);

        // 6. Composition effects — atomic revoke-old / replaceSlot / register-new.
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Executed), "executed");
        assertEq(realRegistry.poolAtSlot(slot), candidate, "slot 5 now holds candidate");
        assertEq(realRegistry.slotOf(oldPool), 0, "ixEdelweiss deregistered");
        assertEq(realRegistry.slotOf(candidate), slot, "candidate bound to slot 5");
        assertTrue(!gaugeRegistry.isGaugeApproved(oldPool), "ixEdelweiss gauge revoked");
        assertTrue(gaugeRegistry.isGaugeApproved(candidate), "candidate gauge active");
    }

    /// @notice P1 A.1 — pausing der Bodensee bricks every `propose*` entry, including
    ///         `proposeVaultUnpause`, the one proposal type that exists to exit a pause.
    ///         `_createProposal` welds the bond to a live Vault `addLiquidity` on der Bodensee
    ///         (`AureumGovernance.sol:211-214`), so the pool's own pause bit halts proposal
    ///         creation. The exit is inside the door it opens. PP-D29 orders G.1 after this.
    function test_P1_A1_pausedBodenseeBricksProposeVaultUnpause() public {
        address proposer = address(uint160(uint256(keccak256("proposerA1"))));
        deal(address(svZchf), proposer, 1_000e18, true);
        vm.prank(proposer);
        svZchf.approve(address(gov), 1_000e18);
        vm.prank(GOVERNANCE_MULTISIG);
        vault.pausePool(bodenseePool);
        vm.expectPartialRevert(IVaultErrors.PoolPaused.selector);
        vm.prank(proposer);
        gov.proposeVaultUnpause(svZchf);
    }
}
