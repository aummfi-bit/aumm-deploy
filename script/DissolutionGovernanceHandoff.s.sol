// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
// Concrete-type imports — these setters are concrete-only (not exposed on the
// contracts' interfaces), so interface handles cannot reach them (DeployStageK L18-23 precedent).
import { EmissionDistributor } from "../src/emission/EmissionDistributor.sol";
import { BodenseeBootstrapChannel } from "../src/emission/BodenseeBootstrapChannel.sol";
import { TVLOracle } from "../src/emission/TVLOracle.sol";
import { EfficiencyOracle } from "../src/emission/EfficiencyOracle.sol";
import { SwapAndDepositToBodensee } from "../src/gauge/SwapAndDepositToBodensee.sol";

/**
 * @title DissolutionGovernanceHandoff
 * @notice PB-D2 / PB-D11 / PB-D12 STANDALONE dissolution-time governance-handoff rotation —
 *         multisig-run as its last act AFTER the OQ-10 window, NOT part of the deploy
 *         orchestration (supersedes the PB-D2 "joins the deploy orchestration" clause).
 * @dev Five order-independent rotations (order-independent unlike DeployStageK's load-bearing
 *      K14 chain — each rotates a distinct contract's authority to the same target):
 *      (1) EmissionDistributor.setGovernanceContract;
 *      (2) BodenseeBootstrapChannel.setGovernanceContract;
 *      (3) TVLOracle.setGovernanceContract;
 *      (4) EfficiencyOracle.setGovernanceContract;
 *      (5) SwapAndDepositToBodensee.setDonateAuthorizer.
 * @dev Precondition: the caller (GOVERNANCE_MULTISIG) must currently hold the `governance`
 *      slot on the four emission contracts and the `donateAuthorizer` slot on
 *      SwapAndDepositToBodensee — the script states it, it cannot enforce it (the DeployStageK
 *      NatSpec precondition posture).
 * @dev VaultClassRegistry is NOT rotated here — it is one-shot-sealed and reroutes to the
 *      PB3.4 production bind per PB-D11.
 * @dev Env vars required (no defaults — a real deploy must never silently fall back to zero values):
 *
 *        GOVERNANCE_MULTISIG    address  — broadcast/prank caller = current authority holder
 *        AUREUM_GOVERNANCE      address  — rotation target — the deployed on-chain governance
 *        EMISSION_DISTRIBUTOR   address  — EmissionDistributor.setGovernanceContract target
 *        BODENSEE_CHANNEL       address  — BodenseeBootstrapChannel.setGovernanceContract target
 *        TVL_ORACLE             address  — TVLOracle.setGovernanceContract target
 *        EFFICIENCY_ORACLE      address  — EfficiencyOracle.setGovernanceContract target
 *        SWAP_AND_DEPOSIT       address  — SwapAndDepositToBodensee.setDonateAuthorizer target
 */
contract DissolutionGovernanceHandoff is Script {
    /// @notice `forge script` entry — broadcasts the five dissolution-time rotations as GOVERNANCE_MULTISIG.
    function run() external {
        address multisig = vm.envAddress("GOVERNANCE_MULTISIG");
        vm.startBroadcast(multisig);
        _rotate();
        vm.stopBroadcast();
    }

    /// @notice Testable entry — runs the five rotations via vm.startPrank(multisig) for fork tests
    ///         without a live broadcast. No return value — a rotation produces no handles.
    function rotate(address multisig) external {
        vm.startPrank(multisig);
        _rotate();
        vm.stopPrank();
    }

    /// @dev Resolves AUREUM_GOVERNANCE and performs the five order-independent authority rotations.
    function _rotate() internal {
        address newGovernance = vm.envAddress("AUREUM_GOVERNANCE");
        EmissionDistributor(vm.envAddress("EMISSION_DISTRIBUTOR")).setGovernanceContract(newGovernance);
        BodenseeBootstrapChannel(vm.envAddress("BODENSEE_CHANNEL")).setGovernanceContract(newGovernance);
        TVLOracle(vm.envAddress("TVL_ORACLE")).setGovernanceContract(newGovernance);
        EfficiencyOracle(vm.envAddress("EFFICIENCY_ORACLE")).setGovernanceContract(newGovernance);
        SwapAndDepositToBodensee(vm.envAddress("SWAP_AND_DEPOSIT")).setDonateAuthorizer(newGovernance);
    }
}
