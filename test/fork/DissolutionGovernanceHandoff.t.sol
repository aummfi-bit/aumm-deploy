// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { StagePIntegrationFixture } from "./StagePIntegration.t.sol";
import { DissolutionGovernanceHandoff } from "../../script/DissolutionGovernanceHandoff.s.sol";
import { IEmissionDistributor } from "../../src/emission/IEmissionDistributor.sol";
import { TVLOracle } from "../../src/emission/TVLOracle.sol";
import { EfficiencyOracle } from "../../src/emission/EfficiencyOracle.sol";
import { BodenseeBootstrapChannel } from "../../src/emission/BodenseeBootstrapChannel.sol";
import { SwapAndDepositToBodensee } from "../../src/gauge/SwapAndDepositToBodensee.sol";
import { PoolConfig, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { AureumGovernanceAuthorizer } from "../../src/governance/AureumGovernanceAuthorizer.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";

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

    /**
     * @notice Reproduction of seam-1 root cause C.1 — the umbrella lifetime finding. Exactly one
     *         authority in the protocol expires by code, and at the very block it expires the five
     *         retained slots are still live, so the constitution's "the multisig has no authority
     *         thereafter, ever" (`10_constitution.md:203`) is false at the moment it comes due.
     * @dev This case is the HANDOFF-NOT-RUN world, which is the state the code produces on its own:
     *      `script/DissolutionGovernanceHandoff.s.sol` is standalone and nothing in `src/` times,
     *      compels or records it, so five live multisig slots are the default. The sibling case
     *      below covers the handoff-run world.
     * @dev NOT reproduced here, each being another row's PoC rather than C.1's: the donate-rail kill
     *      switch (A.4), the mint oracle (F.1), the trusted-router seat (B.6), the admission
     *      authority (C.6) and the pool-pause brick (A.1). C.1's own content is the LIFETIME rather
     *      than the levers, so the call exercised below is deliberately a benign authoritative write
     *      and not any of those exploits.
     * @dev The exercised slot is `EfficiencyOracle.setFeeRecorder` (gate at `:123`) because it is
     *      authority carrying an observable getter at `:38` and is nobody else's exploit; the other
     *      four retained slots are asserted by read alone.
     * @dev `EMERGENCY_MULTISIG` and the governance multisig are DISTINCT addresses in this fixture
     *      (`StagePIntegration.t.sol:96` against `address(orchestrator)`). The report records that
     *      their distinctness is not determinable from the deployed artifacts, so nothing asserted
     *      here turns on the two being one principal.
     */
    function test_P1_C1_theOneCodeEnforcedExpiryFiresWhileTheRetainedSlotsDoNot() public {
        AureumGovernanceAuthorizer auth = orchestrator.authorizer();
        uint256 endBlock = auth.EMERGENCY_WINDOW_END_BLOCK();

        assertLt(block.number, endBlock, "premise: emergency window still open");
        assertTrue(
            auth.canPerform(auth.EMERGENCY_ACTION_PAUSE_VAULT(), EMERGENCY_MULTISIG, address(vault)),
            "positive control: the emergency grant is live inside the window"
        );

        // The one code-enforced expiry in the protocol. The bound is a strict less-than, so the end
        // block itself already sits outside the window.
        vm.roll(endBlock);
        assertFalse(
            auth.canPerform(auth.EMERGENCY_ACTION_PAUSE_VAULT(), EMERGENCY_MULTISIG, address(vault)),
            "pauseVault grant expired"
        );
        assertFalse(
            auth.canPerform(auth.EMERGENCY_ACTION_UNPAUSE_VAULT(), EMERGENCY_MULTISIG, address(vault)),
            "unpauseVault grant expired"
        );
        assertFalse(
            auth.canPerform(auth.EMERGENCY_ACTION_ENABLE_RECOVERY_MODE(), EMERGENCY_MULTISIG, address(vault)),
            "enableRecoveryMode grant expired"
        );
        assertFalse(
            auth.canPerform(auth.EMERGENCY_ACTION_DISABLE_RECOVERY_MODE(), EMERGENCY_MULTISIG, address(vault)),
            "disableRecoveryMode grant expired"
        );

        // Same block. The five retained slots never heard of that deadline.
        assertEq(orchestrator.emissionDistributor().governance(), address(orchestrator));
        assertEq(orchestrator.bodenseeBootstrapChannel().governance(), address(orchestrator));
        assertEq(orchestrator.tvlOracle().governance(), address(orchestrator));
        assertEq(orchestrator.efficiencyOracle().governance(), address(orchestrator));
        assertEq(orchestrator.swapAndDeposit().donateAuthorizer(), address(orchestrator));

        // Held is not the same as exercisable, so one slot is actually driven.
        EfficiencyOracle eff = orchestrator.efficiencyOracle();
        address recorder = makeAddr("p1_c1_fee_recorder_after_the_window");
        assertNotEq(eff.feeRecorder(), recorder, "premise: not already the candidate");
        vm.prank(address(orchestrator));
        eff.setFeeRecorder(recorder);
        assertEq(eff.feeRecorder(), recorder, "retained authority still executes after the window ends");
    }

    /**
     * @notice Reproduction of seam-1 root cause C.1's `pauseManager` face, and the withdrawal of
     *         PB-D2 (ii)'s inert-non-exclusive-pointer reading. Non-exclusive means the authorizer
     *         principal ALSO qualifies; it does not mean the role holder stops qualifying.
     *         `VaultAdmin._ensureAuthenticatedByRole` at `:787` returns at `:788-790` the moment
     *         `msg.sender == roleAddress` and never reaches the authorizer at all.
     * @dev This is the HANDOFF-RUN world: the dissolution rotates the five emission-layer slots and
     *      cannot touch `PoolRoleAccounts`, for which the Vault exposes no setter. The report's
     *      "in the handoff-run world the gap is five" is what this case pins.
     * @dev What the sibling `test_pauseManager_inertNonExclusivePointer` ASSERTS stays correct: it
     *      reads the stored address and nothing more. It is that test's framing that is withdrawn
     *      here, the word inert and the reading that post-dissolution both directions are
     *      unreachable, which holds for `AureumGovernance` as a principal and not for this seat.
     * @dev NOT claimed: that the seat never lapses. It does. `_MAX_PAUSE_WINDOW_DURATION` is
     *      `365 days * 4` with a 90-day buffer at `VaultStorage.sol:46-47`, so the role dies with
     *      the pool's own pause window, which is why the clock is advanced honestly below rather
     *      than left frozen. The claim is only that the seat outlives BOTH the emergency window and
     *      the dissolution, at which point the constitution says no such authority exists.
     * @dev The one-key-holds-everything collapse is a Sepolia deployment fact and is NOT asserted
     *      here; in this fixture the seat is `address(orchestrator)` from the pool's registration at
     *      `StagePIntegration.t.sol:181-182`.
     */
    function test_P1_C1_thePauseManagerRoleHolderOutlivesTheWindowAndTheDissolution() public {
        _executeDissolutionRotation();

        AureumGovernanceAuthorizer auth = orchestrator.authorizer();
        uint256 endBlock = auth.EMERGENCY_WINDOW_END_BLOCK();

        // Advance the clock coherently. The emergency window is counted in blocks and the pool's
        // pause window in seconds, so rolling alone would leave a state no chain can occupy. 12s
        // per block is the PB-D1 parity figure, making the 2_628_000-block window one year.
        uint256 elapsed = endBlock - block.number;
        vm.warp(block.timestamp + elapsed * 12);
        vm.roll(endBlock);

        // PB20 control. The same derivation reproduces the authorizer's own public constant, so the
        // denial below is earned rather than an unmatched actionId that cannot hit anything.
        assertEq(
            keccak256(abi.encodePacked(bytes32(uint256(uint160(address(vault)))), IVaultAdmin.pauseVault.selector)),
            auth.EMERGENCY_ACTION_PAUSE_VAULT(),
            "control: the actionId derivation matches the authorizer's own"
        );
        bytes32 pausePoolAction =
            keccak256(abi.encodePacked(bytes32(uint256(uint160(address(vault)))), IVaultAdmin.pausePool.selector));
        assertFalse(
            auth.canPerform(pausePoolAction, address(orchestrator), address(vault)),
            "the authorizer denies pausePool to this account"
        );

        // Premise: the pool's own pause window is still open, so a success below is the role seat
        // rather than a frozen clock.
        assertLt(
            block.timestamp,
            uint256(vault.getPoolConfig(bodenseePool).pauseWindowEndTime),
            "premise: the pool pause window is still open"
        );

        // A caller holding no seat is refused on the very same call at the very same block.
        address stranger = makeAddr("p1_c1_stranger_without_the_seat");
        vm.prank(stranger);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.pausePool(bodenseePool);

        // The seat holder is not inert. Its early return never consults the authorizer that has
        // just denied it.
        assertEq(
            vault.getPoolRoleAccounts(bodenseePool).pauseManager,
            address(orchestrator),
            "premise: the seat survived the rotation"
        );
        assertFalse(vault.isPoolPaused(bodenseePool), "premise: not already paused");
        vm.prank(address(orchestrator));
        vault.pausePool(bodenseePool);
        assertTrue(
            vault.isPoolPaused(bodenseePool),
            "the role holder pauses after both the emergency window and the dissolution"
        );
    }
}
