// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { HooksConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";

import { StageKIntegrationFixture } from "./StageKIntegration.t.sol";
import { AureumGovernance } from "../../src/governance/AureumGovernance.sol";
import { AureumTime } from "../../src/lib/AureumTime.sol";
import { IGaugeRegistry } from "../../src/ccb/IGaugeRegistry.sol";

/// @notice O5 non-yield leg double — a code-bearing contract with no `asset()`, so the gate's
///         `try IERC4626(token).asset()` reverts-and-catches to a zero numerator contribution
///         (mirrors the unit-test `MockERC20Plain` pattern; a code-less `makeAddr` is avoided).
contract NonYieldLeg {}

/// @notice Stage O fork-test base — extends the Stage K composition fixture (real AureumGovernance +
///         MiliariumRegistry + GaugeRegistry / GaugeEligibility / VaultClassRegistry, 3 pilots at
///         slots [1, 5, 14]) with synthetic-candidate helpers that mock only a candidate's Vault
///         pool-shape reads, so the REAL composition Quality Gate (O-D2 / O-D2a) evaluates it. Per O-D9.
abstract contract StageOIntegrationFixture is StageKIntegrationFixture {
    /// @dev Mocks `candidate`'s Vault reads so `meetsCompositionQualityGate` returns true: canonical
    ///      fee-routing hook + 100% `susds` (the genesis-admitted ERC-4626 class) → numerator 1e18 >= 0.52e18.
    function _mockConformingCandidate(address candidate) internal {
        HooksConfig memory hc;
        hc.hooksContract = address(hook);
        vm.mockCall(address(vault), abi.encodeWithSignature("getHooksConfig(address)", candidate), abi.encode(hc));
        vm.mockCall(address(awpf), abi.encodeWithSelector(IBasePoolFactory.isPoolFromFactory.selector, candidate), abi.encode(true));
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(susds));
        vm.mockCall(address(vault), abi.encodeWithSignature("getPoolTokens(address)", candidate), abi.encode(tokens));
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;
        vm.mockCall(candidate, abi.encodeWithSignature("getNormalizedWeights()"), abi.encode(weights));
    }

    /// @dev Mocks `candidate`'s Vault reads so `meetsCompositionQualityGate` returns false: canonical
    ///      hook but 51% `susds` + 49% non-yield leg → numerator 0.51e18 < 0.52e18.
    function _mockSubThresholdCandidate(address candidate) internal {
        HooksConfig memory hc;
        hc.hooksContract = address(hook);
        vm.mockCall(address(vault), abi.encodeWithSignature("getHooksConfig(address)", candidate), abi.encode(hc));
        vm.mockCall(address(awpf), abi.encodeWithSelector(IBasePoolFactory.isPoolFromFactory.selector, candidate), abi.encode(true));
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(address(susds));
        tokens[1] = IERC20(address(new NonYieldLeg()));
        vm.mockCall(address(vault), abi.encodeWithSignature("getPoolTokens(address)", candidate), abi.encode(tokens));
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.51e18;
        weights[1] = 0.49e18;
        vm.mockCall(candidate, abi.encodeWithSignature("getNormalizedWeights()"), abi.encode(weights));
    }

    /// @dev Qualifies `voter` for a 100%-turnout composition vote — a recorded deposit on pilot 0
    ///      (slot 1, untouched by a slot-5 composition) past the qualification cliff, EMA-shimmed and poked.
    function _qualifyVoter(address voter) internal {
        _depositOneSided(pilotPools[0], voter, 100);
        vm.roll(block.number + AureumTime.QUALIFICATION_PERIOD_BLOCKS + 1);
        _mockPoolEma(pilotPools[0], 1_000e18);
        votingWeight.poke(voter);
    }
}

/// @notice O5.1 smoke — the Stage O fixture inherits the K wiring and the candidate helpers drive the REAL gate.
contract StageOWiringTest is StageOIntegrationFixture {
    function test_setUp_realGateAcceptsConformingRejectsSubThreshold() public {
        assertEq(address(gov.GAUGE_REGISTRY()), address(gaugeRegistry), "K wiring inherited");
        assertEq(realRegistry.poolAtSlot(5), pilotPools[1], "slot 5 holds the pilot");

        address conforming = makeAddr("conformingCandidate");
        _mockConformingCandidate(conforming);
        assertTrue(gaugeRegistry.meetsCompositionQualityGate(conforming), "real gate accepts 100% admitted-4626");

        address subThreshold = makeAddr("subThresholdCandidate");
        _mockSubThresholdCandidate(subThreshold);
        assertFalse(gaugeRegistry.meetsCompositionQualityGate(subThreshold), "real gate rejects 51% admitted-4626");
    }
}

/// @notice O5.2 — composition lifecycle through the REAL Quality Gate: accept + atomic replace + no-boost,
///         reject at propose (pre-deposit) and at execute (pre-mutation), and deprecated-pool hook permanence.
contract StageOCompositionGateTest is StageOIntegrationFixture {
    uint256 internal constant SLOT = 5;
    uint256 internal constant DEPOSIT = 1_000e18;

    function _proposeAsThis(address candidate) internal returns (uint256 id) {
        deal(address(svZchf), address(this), DEPOSIT);
        svZchf.approve(address(gov), DEPOSIT);
        id = gov.proposeCompositionChallenge(SLOT, candidate, svZchf);
    }

    function _voteQueueReachEta(uint256 id, address voter) internal {
        AureumGovernance.Proposal memory pv = gov.getProposal(id);
        vm.roll(pv.snapshotBlock + 1);
        vm.prank(voter);
        gov.castVote(id, true);
        vm.roll(pv.endBlock + 1);
        gov.queue(id);
        AureumGovernance.Proposal memory pq = gov.getProposal(id);
        vm.roll(pq.eta);
    }

    function test_compositionLifecycle_realGateAccepts_atomicReplace() public {
        address voter = makeAddr("voterAccept");
        _qualifyVoter(voter);
        address candidate = makeAddr("conformingReplacement");
        _mockConformingCandidate(candidate);
        address oldPool = realRegistry.poolAtSlot(SLOT);

        uint256 id = _proposeAsThis(candidate);
        _voteQueueReachEta(id, voter);

        // O-D3 no-boost: the replacement is gauged via the Composition path (no boost on any path, G-D13).
        vm.expectEmit(true, true, false, false, address(gaugeRegistry));
        emit IGaugeRegistry.GaugeActivated(candidate, IGaugeRegistry.GaugeActivationPath.Composition);
        gov.execute(id);

        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Executed), "executed");
        assertEq(realRegistry.poolAtSlot(SLOT), candidate, "slot now holds candidate");
        assertEq(realRegistry.slotOf(oldPool), 0, "old pool deregistered");
        assertFalse(gaugeRegistry.isGaugeApproved(oldPool), "old gauge revoked");
        assertTrue(gaugeRegistry.isGaugeApproved(candidate), "candidate gauge active");
    }

    function test_compositionPropose_realGateRejects_subThreshold_noDeposit() public {
        address candidate = makeAddr("subThresholdReplacement");
        _mockSubThresholdCandidate(candidate);
        deal(address(svZchf), address(this), DEPOSIT);
        svZchf.approve(address(gov), DEPOSIT);
        uint256 balBefore = svZchf.balanceOf(address(this));
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.CompositionQualityGateFailed.selector, candidate));
        gov.proposeCompositionChallenge(SLOT, candidate, svZchf);
        assertEq(svZchf.balanceOf(address(this)), balBefore, "no deposit pulled on reject");
        assertEq(gov.proposalCount(), 0, "no proposal created");
    }

    function test_compositionExecute_realGateRejects_subThresholdMidVote_noMutation() public {
        address voter = makeAddr("voterExecReject");
        _qualifyVoter(voter);
        address candidate = makeAddr("flipReplacement");
        _mockConformingCandidate(candidate);
        address oldPool = realRegistry.poolAtSlot(SLOT);

        uint256 id = _proposeAsThis(candidate);
        _voteQueueReachEta(id, voter);

        // Candidate becomes ineligible after the vote (e.g. a vault-class de-admission) — re-mock sub-threshold.
        _mockSubThresholdCandidate(candidate);
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.CompositionQualityGateFailed.selector, candidate));
        gov.execute(id);

        assertEq(realRegistry.poolAtSlot(SLOT), oldPool, "slot unchanged");
        assertTrue(gaugeRegistry.isGaugeApproved(oldPool), "old gauge intact");
        assertFalse(gaugeRegistry.isGaugeApproved(candidate), "candidate not gauged");
        AureumGovernance.Proposal memory pf = gov.getProposal(id);
        assertFalse(pf.executed, "not executed");
    }

    function test_deprecatedPool_hookSurvivesAndGaugeRevoked() public {
        address voter = makeAddr("voterHook");
        _qualifyVoter(voter);
        address candidate = makeAddr("hookCandidate");
        _mockConformingCandidate(candidate);
        address oldPool = realRegistry.poolAtSlot(SLOT);
        assertEq(vault.getHooksConfig(oldPool).hooksContract, address(hook), "old pool carries the canonical hook pre-deprecation");

        uint256 id = _proposeAsThis(candidate);
        _voteQueueReachEta(id, voter);
        gov.execute(id);

        // Q1.5 / §xxvii — gauge revoked, but the hook stays attached for life (Balancer cannot detach it).
        assertFalse(gaugeRegistry.isGaugeApproved(oldPool), "deprecated pool gauge revoked");
        assertEq(realRegistry.slotOf(oldPool), 0, "deprecated pool deregistered");
        assertEq(vault.getHooksConfig(oldPool).hooksContract, address(hook), "deprecated pool keeps its canonical hook");
    }
}
