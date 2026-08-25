// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { StagePIntegrationFixture } from "./StagePIntegration.t.sol";
import { DissolutionGovernanceHandoff } from "../../script/DissolutionGovernanceHandoff.s.sol";
import { IEmissionDistributor } from "../../src/emission/IEmissionDistributor.sol";
import { TVLOracle } from "../../src/emission/TVLOracle.sol";
import { EfficiencyOracle } from "../../src/emission/EfficiencyOracle.sol";
import { BodenseeBootstrapChannel } from "../../src/emission/BodenseeBootstrapChannel.sol";
import { SwapAndDepositToBodensee } from "../../src/gauge/SwapAndDepositToBodensee.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

/**
 * @title DissolutionGovernanceHandoffWitness
 * @notice PB2.6 dissolution-time rotation witness per PB-D2 / PB-D11 / PB-D12
 * @dev The in-fork multisig identity is address(orchestrator) (DeployStageP.s.sol L81); the rotation target is orchestrator.governance() (the AureumGovernance instance from DeployStageK)
 * @dev The freeze's "no successor path" — AureumGovernance v1 exposes no generic-call hatch to reach these setters (typed execute dispatch, STAGE_K_NOTES K-D9 / PB-D12 ii) — is the documented structural fact; this witness runtime-asserts only the multisig lockout.
 */
contract DissolutionGovernanceHandoffWitness is StagePIntegrationFixture {
    /// @dev Seeds the DissolutionGovernanceHandoff env from typed orchestrator handles and runs rotate as the in-fork multisig.
    function _executeDissolutionRotation() internal returns (address gov) {
        gov = address(orchestrator.governance());
        DissolutionGovernanceHandoff handoff = new DissolutionGovernanceHandoff();
        vm.setEnv("GOVERNANCE_MULTISIG", vm.toString(address(orchestrator)));
        vm.setEnv("AUREUM_GOVERNANCE", vm.toString(gov));
        vm.setEnv("EMISSION_DISTRIBUTOR", vm.toString(address(orchestrator.emissionDistributor())));
        vm.setEnv("BODENSEE_CHANNEL", vm.toString(address(orchestrator.bodenseeBootstrapChannel())));
        vm.setEnv("TVL_ORACLE", vm.toString(address(orchestrator.tvlOracle())));
        vm.setEnv("EFFICIENCY_ORACLE", vm.toString(address(orchestrator.efficiencyOracle())));
        vm.setEnv("SWAP_AND_DEPOSIT", vm.toString(address(orchestrator.swapAndDeposit())));
        handoff.rotate(address(orchestrator));
    }

    /// @notice Precondition face — the in-fork multisig still holds all five authority slots before dissolution.
    function test_preRotation_multisigHoldsAllFive() public view {
        assertEq(orchestrator.emissionDistributor().governance(), address(orchestrator));
        assertEq(orchestrator.bodenseeBootstrapChannel().governance(), address(orchestrator));
        assertEq(orchestrator.tvlOracle().governance(), address(orchestrator));
        assertEq(orchestrator.efficiencyOracle().governance(), address(orchestrator));
        assertEq(orchestrator.swapAndDeposit().donateAuthorizer(), address(orchestrator));
    }

    /// @notice PB-D12(iv) face 1 — after dissolution rotation, all five slots equal AureumGovernance.
    function test_rotation_landsAllFiveSlots() public {
        address gov = _executeDissolutionRotation();
        assertEq(orchestrator.emissionDistributor().governance(), gov);
        assertEq(orchestrator.bodenseeBootstrapChannel().governance(), gov);
        assertEq(orchestrator.tvlOracle().governance(), gov);
        assertEq(orchestrator.efficiencyOracle().governance(), gov);
        assertEq(orchestrator.swapAndDeposit().donateAuthorizer(), gov);
    }

    /// @notice PB-D12(iv) face 2 — the multisig is locked out of the five rotated setters.
    function test_rotation_multisigLockedOutOfRotatedSetters() public {
        _executeDissolutionRotation();

        IEmissionDistributor ed = orchestrator.emissionDistributor();
        BodenseeBootstrapChannel bod = orchestrator.bodenseeBootstrapChannel();
        TVLOracle tvl = orchestrator.tvlOracle();
        EfficiencyOracle eff = orchestrator.efficiencyOracle();
        SwapAndDepositToBodensee swp = orchestrator.swapAndDeposit();

        vm.prank(address(orchestrator));
        vm.expectRevert(
            abi.encodeWithSelector(IEmissionDistributor.NotGovernance.selector, address(orchestrator))
        );
        ed.setGovernanceContract(address(orchestrator));

        vm.prank(address(orchestrator));
        vm.expectRevert(
            abi.encodeWithSelector(BodenseeBootstrapChannel.NotGovernance.selector, address(orchestrator))
        );
        bod.setGovernanceContract(address(orchestrator));

        vm.prank(address(orchestrator));
        vm.expectRevert(abi.encodeWithSelector(TVLOracle.NotGovernance.selector, address(orchestrator)));
        tvl.setGovernanceContract(address(orchestrator));

        vm.prank(address(orchestrator));
        vm.expectRevert(
            abi.encodeWithSelector(EfficiencyOracle.NotGovernance.selector, address(orchestrator))
        );
        eff.setGovernanceContract(address(orchestrator));

        vm.prank(address(orchestrator));
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.OnlyDonateAuthorizer.selector, address(orchestrator))
        );
        swp.setDonateAuthorizer(address(orchestrator));
    }

    /// @notice PB-D12(ii) freeze — the load-bearing operational-wiring family reverts for the multisig.
    function test_freeze_loadBearingFamilyRevertsForMultisig() public {
        _executeDissolutionRotation();

        IEmissionDistributor ed = orchestrator.emissionDistributor();
        TVLOracle tvl = orchestrator.tvlOracle();
        EfficiencyOracle eff = orchestrator.efficiencyOracle();
        SwapAndDepositToBodensee swp = orchestrator.swapAndDeposit();

        vm.prank(address(orchestrator));
        vm.expectRevert(
            abi.encodeWithSelector(IEmissionDistributor.NotGovernance.selector, address(orchestrator))
        );
        ed.setAuMTContractForPool(pilotPools[0], address(0xBEEF));

        vm.prank(address(orchestrator));
        vm.expectRevert(abi.encodeWithSelector(TVLOracle.NotGovernance.selector, address(orchestrator)));
        tvl.setTokenUnderlying(address(0xA11), address(0xB22));

        vm.prank(address(orchestrator));
        vm.expectRevert(abi.encodeWithSelector(TVLOracle.NotGovernance.selector, address(orchestrator)));
        tvl.addConstellationPool(address(0xC33));

        vm.prank(address(orchestrator));
        vm.expectRevert(abi.encodeWithSelector(TVLOracle.NotGovernance.selector, address(orchestrator)));
        tvl.addHopUnderlying(address(0xD44));

        vm.prank(address(orchestrator));
        vm.expectRevert(
            abi.encodeWithSelector(EfficiencyOracle.NotGovernance.selector, address(orchestrator))
        );
        eff.setFeeRecorder(address(0xE55));

        vm.prank(address(orchestrator));
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.OnlyDonateAuthorizer.selector, address(orchestrator))
        );
        swp.addAuthorizedDonator(address(0xF66));

        vm.prank(address(orchestrator));
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.OnlyDonateAuthorizer.selector, address(orchestrator))
        );
        swp.removeAuthorizedDonator(address(0xF77));
    }

    /**
     * @notice PB-D2(ii) pauseManager inert-pointer attestation — the Miliarium roster pool pauseManager is the write-once GOVERNANCE_MULTISIG (script/pools/deploy-miliarium-pool.s.sol L132), an inert pointer at the to-be-dissolved Safe post-dissolution; NOT rotated (PB-D2), unlike the five re-settable slots.
     * @dev The pause role is NON-exclusive — VaultAdmin `_ensureAuthenticatedByRole` (L787-793) falls through to the authorizer rather than foreclosing on `pauseManager` alone, so the stale pointer was never the sole gate (F-20 / P-D40's EXCLUSIVE-vs-non-exclusive distinction). That fallback grants `GOVERNANCE_CONTRACT` permission unconditionally, but permission is not expressibility (F-22 / PB-D63 (vii)): `AureumGovernance` holds no code path that calls `pausePool`/`unpausePool`, so this attestation is about the role construction, not a live pause capability governance can exercise; the non-exclusivity is the documented structural fact, not re-proven here. PB-D72 WITHDRAWS PB-D2 (ii)'s harmless-by-construction reading: post-dissolution both directions are unreachable, symmetric and so a lost lever rather than F-22's inward door.
     */
    function test_pauseManager_inertNonExclusivePointer() public view {
        assertEq(vault.getPoolRoleAccounts(pilotPools[0]).pauseManager, address(orchestrator));
        assertEq(vault.getPoolRoleAccounts(majorPools[0]).pauseManager, address(orchestrator));
        assertEq(vault.getPoolRoleAccounts(stageNPools[0]).pauseManager, address(orchestrator));
    }

    /**
     * @notice Reproduction of seam-1 root cause C.2's stranding face — after dissolution the
     *         authority is real and exercisable, but its new holder has no code path that can
     *         emit the call, so onboarding a new pool becomes permanently impossible.
     * @dev NOT reproduced here: the seventeen-function breadth of the rotation; GaugeRegistry
     *      and MiliariumRegistry `setGovernanceContract` already welded to v1 at Stage K;
     *      `revokeVaultClass` sealed behind its one-shot; the G23 result that seizing a slot
     *      is destructive rather than extractive because a composition winner binds no
     *      recorder; and the unfillability of slots 04 and 07. This row's done-criteria is a
     *      NOTES clause plus a re-gate of this very file rather than a path-and-case artifact,
     *      so PP-D42's case-name bind does not apply to it.
     */
    function test_P1_C2_theRotatedAuthorityIsRealButItsHolderHasNoCodePathToEmitIt() public {
        address gov = _executeDissolutionRotation();
        IEmissionDistributor ed = orchestrator.emissionDistributor();

        assertEq(
            ed.governance(),
            gov,
            "authority genuinely transferred; this is not a broken slot"
        );

        // AureumGovernance._executeProposal at L425-L445 is six explicit else-if branches over
        // three immutable targets (the Vault, the slot registry and the gauge registry), with
        // NO target member and NO calldata member on the Proposal struct, so no proposal of any
        // type can name an arbitrary callee. The rotated authority is therefore held by a
        // contract with no expressible way to use it — the permitted-but-reachable-by-no-caller
        // class this row is named for. Sibling test_freeze_loadBearingFamilyRevertsForMultisig
        // proves the OTHER half (the multisig lost the same functions), so between the two the
        // functions are stranded rather than transferred. One-shotness of setAuMTContractForPool
        // is C.8's face (test/whitehat/P1_C8.t.sol, AuMTAlreadyBound on a second bind), not re-derived here.

        address unboundPool = makeAddr("p1_c2_unbound_for_authority");
        address aumt = makeAddr("p1_c2_aumt_for_authority");
        assertEq(ed.auMTContractByPool(unboundPool), address(0), "fresh pool starts unbound");

        vm.prank(gov);
        ed.setAuMTContractForPool(unboundPool, aumt);
        assertEq(
            ed.auMTContractByPool(unboundPool),
            aumt,
            "function works for whoever can call it; the defect is that nothing can"
        );
    }

    /// @notice After dissolution, an unbound pool can never record a position because the only bind path has no reachable caller.
    function test_P1_C2_noNewPoolCanEverBeOnboardedAfterDissolution() public {
        address gov = _executeDissolutionRotation();
        IEmissionDistributor ed = orchestrator.emissionDistributor();

        address unboundPool = makeAddr("p1_c2_unbound_for_onboarding");
        address wouldBeAuMT = makeAddr("p1_c2_would_be_aumt");
        address lp = makeAddr("p1_c2_lp");

        vm.prank(wouldBeAuMT);
        vm.expectRevert(
            abi.encodeWithSelector(IEmissionDistributor.NotAuMTContract.selector, unboundPool, wouldBeAuMT)
        );
        ed.recordDeposit(unboundPool, lp, 1e18);

        // setAuMTContractForPool is the only way to bind a recorder for a new pool and is
        // one-shot per pool (C.8 already pins AuMTAlreadyBound on rebind). After dissolution the
        // rotated holder CAN still call it under a prank, but no proposal type can cause that
        // call to be made — so pool onboarding stops permanently.
        address aumt = makeAddr("p1_c2_aumt_for_onboarding");
        vm.prank(gov);
        ed.setAuMTContractForPool(unboundPool, aumt);
        assertEq(
            ed.auMTContractByPool(unboundPool),
            aumt,
            "only bind path works under prank; no proposal type can emit setAuMTContractForPool"
        );
    }
}
