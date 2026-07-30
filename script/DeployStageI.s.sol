// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";

import { AureumFeeRoutingHook } from "../src/fee_router/AureumFeeRoutingHook.sol";
import { EmissionDistributor } from "../src/emission/EmissionDistributor.sol";

/**
 * @title DeployStageI
 * @notice Wires the Stage I recorder path in a single multisig-authored
 *         broadcast — no contract deployments. The canonical
 *         AureumFeeRoutingHook, the EmissionDistributor, and the three
 *         Stage E pilot pools are all consumed as inputs (env vars); this
 *         script only binds them:
 *
 *           1. hook.setEmissionRecorder(distributor)             — I-D16 one-shot
 *           2. distributor.setAuMTContractForPool(pilot, hook) ×3 — I-D9 one-shot
 *
 * @dev I-D18 — wiring authority is GOVERNANCE_MULTISIG only; there is no
 *      deployer→multisig handoff. By the time this script runs in the
 *      production chain (DeployAuMM → DeployDerBodensee → DeployStageH →
 *      DeployStageI), both gates already admit the multisig: the hook's
 *      `_emissionRecorderAdmin` was seeded `= moduleAdmin_ =
 *      GOVERNANCE_MULTISIG` at the Stage D/G hook constructor, and the
 *      distributor's `governance` was handed to GOVERNANCE_MULTISIG at
 *      DeployStageH Step 7. A single broadcast authored by the multisig
 *      therefore satisfies both `setEmissionRecorder`'s admin gate (I-D16)
 *      and `setAuMTContractForPool`'s `onlyGovernance` gate (I-D9). The
 *      `setEmissionRecorder` call self-zeroes `_emissionRecorderAdmin` as
 *      its second flag, so no separate hook-side handoff is needed either.
 *
 * @dev Production execution — GOVERNANCE_MULTISIG is the Stage A—K
 *      Authorizer Safe, which has no EOA private key. `run()` is therefore a
 *      simulation / calldata reference: `vm.startBroadcast(governor)` sets the
 *      simulated sender to the multisig so the gated calls succeed under
 *      `forge script` simulation; real on-chain submission is the same four
 *      calls executed as a Safe transaction batch. The fork test
 *      (`test/fork/DeployStageI.t.sol`) exercises the `deploy(governor)`
 *      entry, which applies the multisig identity via `vm.startPrank` so the
 *      gated calls succeed without a live broadcast.
 *
 * @dev Fail-fast precondition — `_wire` asserts
 *      `distributor.governance() == governor` before any binding call, so a
 *      run against a pre-handoff distributor (DeployStageH Step 7 skipped)
 *      reverts `GovernanceNotMultisig` with the offending governance address
 *      rather than partial-binding and then reverting mid-wire with the
 *      cryptic `NotGovernance`. Mirrors the DeployStageH Step 8
 *      `MinterNotZero` invariant-guard pattern.
 *
 * @dev Env vars required (no defaults — a real wire must never silently fall
 *      back to zero values):
 *
 *        GOVERNANCE_MULTISIG   address  — wiring authority; hook moduleAdmin_ +
 *                                         distributor governance (post-Stage-H)
 *        FEE_ROUTING_HOOK      address  — canonical AureumFeeRoutingHook (I-D16 recorder slot)
 *        EMISSION_DISTRIBUTOR  address  — Stage H EmissionDistributor (I-D9 per-pool bind)
 *        MILIARIUM_POOL_01     address  — ixHelvetia pilot (Stage E slot 01)
 *        MILIARIUM_POOL_05     address  — ixEdelweiss pilot (Stage E slot 05)
 *        MILIARIUM_POOL_14     address  — ixAurebit pilot (Stage E slot 14)
 */
contract DeployStageI is Script {
    /// @notice Reverts when `distributor.governance() != governor` at the start
    ///         of `_wire` — confirms the I-D18 precondition that DeployStageH
    ///         Step 7 already handed distributor governance to GOVERNANCE_MULTISIG.
    error GovernanceNotMultisig(address actual);

    /// @notice `forge script` entry — broadcasts the four wiring calls as the
    ///         GOVERNANCE_MULTISIG read from env (simulation / Safe-batch reference).
    function run() external {
        address governor = vm.envAddress("GOVERNANCE_MULTISIG");
        vm.startBroadcast(governor);
        _wire(governor);
        vm.stopBroadcast();
    }

    /// @notice Testable entry — applies the GOVERNANCE_MULTISIG identity via
    ///         `vm.startPrank(governor)` so the gated calls succeed from a fork
    ///         test without a live broadcast. `governor` must equal the
    ///         GOVERNANCE_MULTISIG that owns the hook recorder-admin and the
    ///         distributor governance gates.
    function deploy(address governor) external {
        vm.startPrank(governor);
        _wire(governor);
        vm.stopPrank();
    }

    function _wire(address governor) internal {
        AureumFeeRoutingHook hook       = AureumFeeRoutingHook(vm.envAddress("FEE_ROUTING_HOOK"));
        EmissionDistributor distributor = EmissionDistributor(vm.envAddress("EMISSION_DISTRIBUTOR"));

        // I-D18 fail-fast — distributor governance must already be the multisig
        // (DeployStageH Step 7). Otherwise the onlyGovernance binds below would
        // partial-revert mid-wire with the cryptic NotGovernance; surface it up front.
        if (distributor.governance() != governor) {
            revert GovernanceNotMultisig(distributor.governance());
        }

        // 1. Bind the hook's one-shot emissionRecorder slot (I-D16) — self-zeroes
        //    _emissionRecorderAdmin, so no separate hook-side handoff is needed.
        hook.setEmissionRecorder(address(distributor));

        // 2. Bind each pilot pool's recorder gate to the hook (I-D9) — one-shot per
        //    pool. Slots 01/05/14 = ixHelvetia / ixEdelweiss / ixAurebit (Stage E).
        address[3] memory pilots = [
            vm.envAddress("MILIARIUM_POOL_01"),
            vm.envAddress("MILIARIUM_POOL_05"),
            vm.envAddress("MILIARIUM_POOL_14")
        ];
        for (uint256 i = 0; i < pilots.length; i++) {
            distributor.setAuMTContractForPool(pilots[i], address(hook));
        }
    }
}
