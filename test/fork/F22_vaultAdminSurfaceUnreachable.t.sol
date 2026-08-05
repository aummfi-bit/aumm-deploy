// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;
import { StagePIntegrationFixture } from "./StagePIntegration.t.sol";
import { AureumGovernanceAuthorizer } from "../../src/governance/AureumGovernanceAuthorizer.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
/**
 * @title F22_VaultAdminSurfaceUnreachable
 * @notice F-22 PoC. After the Stage-K authorizer handoff, every authenticate-gated Vault admin
 *         action other than setStaticSwapFeePercentage is permitted to AureumGovernance and
 *         reachable by no caller at all. setProtocolFeeController is the witness used here.
 * @dev The defect is EXPRESSIBILITY, not permission, and the two are separated deliberately by the
 *      test order below. AureumGovernanceAuthorizer.canPerform (L65-L73) returns true for
 *      GOVERNANCE_CONTRACT on every actionId without exception, so the Vault will accept the call
 *      from that address. What does not exist is any way for AureumGovernance to emit it:
 *      execute() at src/governance/AureumGovernance.sol L343-L374 dispatches over exactly three
 *      proposal types to three fixed targets, GAUGE_REGISTRY.revokeGauge, the SLOT_REGISTRY
 *      replaceSlot composition path, and VAULT.setStaticSwapFeePercentage, and the Proposal struct
 *      carries no target field and no calldata field, so no proposal can name a different function.
 * @dev The EMERGENCY_MULTISIG does not close the gap. _isEmergencyAction (L75-L77) admits exactly
 *      two actionIds, pauseVault and enableRecoveryMode, and only below EMERGENCY_WINDOW_END_BLOCK.
 * @dev Prior art and the boundary of what is new. That AureumGovernance v1 exposes no generic-call
 *      hatch is already recorded, at K-D9 and at PB-D12 (ii), and the sibling witness
 *      DissolutionGovernanceHandoff.t.sol L16 states it. Both concern AUREUM-OWNED setters gated by
 *      each contract's own governanceContract slot. What no document enumerates is the VAULT's own
 *      admin surface, reached instead through the authorizer, which the same fixed dispatch strands
 *      identically. Two live artifacts presuppose the opposite: docs/STAGE_A_PLAN.md row 4 states
 *      the Vault admin surface is governable through the authorizer, true for Stages A-K and silent
 *      thereafter, and src/vault/AureumVaultFactory.sol L28 NatSpec says the controller may diverge
 *      if governance later calls Vault.setProtocolFeeController, which no governance can do.
 * @dev Sepolia is immutable and stays as deployed; the fix is a source change for the Stage-R
 *      mainnet deploy, which is the disposition shape PB-D52 already set for the TVLOracle rebuild.
 */
contract F22_VaultAdminSurfaceUnreachable is StagePIntegrationFixture {
    /// @dev Arbitrary non-zero stand-in. setProtocolFeeController stores the address without
    ///      validating it (VaultAdmin.sol L333-L339), so no real controller is needed to witness
    ///      that the call is accepted.
    address internal constant CANDIDATE_CONTROLLER = address(0xFEE);
    /// @notice Premise. The authorizer grants the governance contract every action, unconditionally.
    /// @dev Asserted FIRST and separately so that the acceptance in the next test reads as the
    ///      permission being real rather than as an artifact of some fixture-specific grant.
    function test_F22_premise_authorizerGrantsGovernanceEveryAction() public view {
        AureumGovernanceAuthorizer auth = orchestrator.authorizer();
        address gov = address(orchestrator.governance());
        assertTrue(auth.canPerform(bytes32(0), gov, address(vault)), "zero actionId permitted");
        assertTrue(
            auth.canPerform(keccak256("setProtocolFeeController"), gov, address(vault)),
            "arbitrary actionId permitted"
        );
    }
    /// @notice The dispositive face. With the governance contract as msg.sender the Vault performs
    ///         the action, so nothing about the permission layer blocks it.
    /// @dev Therefore the only thing standing between governance and this lever is that
    ///      AureumGovernance holds no code path able to produce this call. A proposal cannot name
    ///      it, so the state change witnessed here is one that can never occur on chain.
    function test_F22_governanceAsCallerCanPerform() public {
        address gov = address(orchestrator.governance());
        address before = address(vault.getProtocolFeeController());
        assertNotEq(before, CANDIDATE_CONTROLLER, "premise: controller not already the candidate");
        vm.prank(gov);
        vault.setProtocolFeeController(IProtocolFeeController(CANDIDATE_CONTROLLER));
        assertEq(
            address(vault.getProtocolFeeController()),
            CANDIDATE_CONTROLLER,
            "vault accepts the call from the governance contract"
        );
    }
    /// @notice The multisig held this surface through Stages A-K and lost it at the handoff.
    /// @dev In-fork multisig identity is address(orchestrator) per DeployStageP.s.sol L81. After
    ///      DeployStageK.s.sol L163 seats AureumGovernanceAuthorizer on the Vault, canPerform
    ///      returns false for this account on a non-emergency action, so the Vault rejects it.
    ///      With governance unable to express the call and the multisig unable to make it, no
    ///      caller remains.
    function test_F22_multisigLostTheSurfaceAtHandoff() public {
        vm.prank(address(orchestrator));
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.setProtocolFeeController(IProtocolFeeController(CANDIDATE_CONTROLLER));
    }
}
