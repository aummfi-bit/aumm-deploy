// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AureumFeeRoutingHook } from "../src/fee_router/AureumFeeRoutingHook.sol";

/**
 * @title DeployFeeRoutingHook
 * @notice Fork-only deployment of the `AureumFeeRoutingHook` (the OQ-1 fee-routing hook). A thin
 *         single-`new` script: it deploys the hook from seven resolved constructor arguments and
 *         returns the handle. The hook and the `AureumProtocolFeeController` store each other's
 *         address as immutables, so the prediction interlock that lets the hook land at the
 *         FEE_ROUTING_HOOK address the controller already stored is NOT owned here — it belongs to
 *         the P9.5 `DeployStageP` orchestrator (the D-D21 / D36 pre-compute chain, deterministic
 *         only within one deployer's nonce trajectory). This script performs exactly one CREATE
 *         (the hook), so the orchestrator predicts it as computeCreateAddress(thisScript, 1) and
 *         asserts equality with FEE_ROUTING_HOOK.
 *
 * @dev H13 — the hook constructor is NOT keccak-placeholder-safe: it external-calls
 *      `IERC4626(svZchf_).asset()` to resolve the ZCHF underlying, so svZChf_ must be real
 *      ERC-4626 contract state at deploy time (satisfied on the P10 mainnet fork; a unit test
 *      would need a mock svZCHF exposing asset()). The other six arguments are stored with no
 *      external call.
 *
 * @dev P-D3 / D-D6 — fork-only scope; no production broadcast within Stage P. `run()` is the
 *      broadcast / simulation entry (reads the seven inputs from env); `deploy(...)` is the
 *      testable no-broadcast entry the P9.5 orchestrator calls with args threaded directly,
 *      bypassing the DER_BODENSEE_POOL / BODENSEE_POOL and SV_ZCHF / SVZCHF env-key divergence
 *      the orchestrator normalizes (P-D25).
 *
 * @dev Env vars required by run() (no defaults — a real deploy must never silently fall back to zero):
 *
 *        VAULT               address  — the Aureum Vault (DeployAureumVault output)
 *        DER_BODENSEE_POOL   address  — der Bodensee pool (D-D9)
 *        SV_ZCHF             address  — svZCHF ERC-4626 (real; the ctor reads its asset())
 *        SUSDS               address  — sUSDS ERC-4626 (P-D12 deposit-token generalization)
 *        AUMM                address  — deployed AuMM
 *        FEE_CONTROLLER      address  — AureumProtocolFeeController (DeployAureumVault output; the
 *                                       controller that stored this hook as FEE_ROUTING_HOOK)
 *        GOVERNANCE_MULTISIG address  — the hook's moduleAdmin_ (seeds the three one-shot admin slots)
 */
contract DeployFeeRoutingHook is Script {
    AureumFeeRoutingHook public feeRoutingHook;

    /// @notice `forge script` entry — deploys the hook from env under broadcast.
    function run() external returns (AureumFeeRoutingHook) {
        vm.startBroadcast();
        AureumFeeRoutingHook h = _deploy(
            vm.envAddress("VAULT"),
            vm.envAddress("DER_BODENSEE_POOL"),
            IERC20(vm.envAddress("SV_ZCHF")),
            IERC20(vm.envAddress("SUSDS")),
            IERC20(vm.envAddress("AUMM")),
            vm.envAddress("FEE_CONTROLLER"),
            vm.envAddress("GOVERNANCE_MULTISIG")
        );
        vm.stopBroadcast();
        console2.log("AureumFeeRoutingHook deployed at:", address(h));
        return h;
    }

    /// @notice Testable entry — deploys without broadcast so the P9.5 orchestrator or a fork fixture
    ///         can call it with resolved args and read back the handle. Exactly one CREATE (the hook).
    function deploy(
        address vault_,
        address derBodensee_,
        IERC20 svZchf_,
        IERC20 susds_,
        IERC20 aumm_,
        address feeController_,
        address moduleAdmin_
    ) external returns (AureumFeeRoutingHook) {
        return _deploy(vault_, derBodensee_, svZchf_, susds_, aumm_, feeController_, moduleAdmin_);
    }

    /// @dev Single `new` — no intermediate CREATE, so the hook is this script's nonce-1 deployment.
    function _deploy(
        address vault_,
        address derBodensee_,
        IERC20 svZchf_,
        IERC20 susds_,
        IERC20 aumm_,
        address feeController_,
        address moduleAdmin_
    ) internal returns (AureumFeeRoutingHook) {
        feeRoutingHook = new AureumFeeRoutingHook(
            vault_,
            derBodensee_,
            svZchf_,
            susds_,
            aumm_,
            feeController_,
            moduleAdmin_
        );
        return feeRoutingHook;
    }
}
