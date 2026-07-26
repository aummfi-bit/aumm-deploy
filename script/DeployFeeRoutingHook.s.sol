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
 *         address as immutables, so the hook must land at the FEE_ROUTING_HOOK address the
 *         controller already stored. That prediction is NOT computed here: the base layer is a
 *         fixture/env input per P-D31, so the caller supplies it — the fork fixtures via
 *         computeCreateAddress(thisScript, 1) (a harness formula, structurally wrong under a real
 *         --broadcast per PB-D27 (iv)), and the live broadcast via the runbook's EOA-scoped
 *         projection. What IS owned here, per PB-D27 (iv)(3), is the check: `run()` asserts the
 *         deployed hook equals FEE_ROUTING_HOOK before returning.
 *
 * @dev H13 — the hook constructor is NOT keccak-placeholder-safe: it external-calls
 *      `IERC4626(svZchf_).asset()` to resolve the ZCHF underlying, so svZChf_ must be real
 *      ERC-4626 contract state at deploy time (satisfied on the P10 mainnet fork; a unit test
 *      would need a mock svZCHF exposing asset()). The other six arguments are stored with no
 *      external call.
 *
 * @dev P-D3 / D-D6 — fork-only scope within Stage P; D-D6 (`STAGE_D_PLAN.md` L88) reserves MAINNET for
 *      Stage R and says nothing about testnets, so it does not bar a Sepolia `--broadcast` — this
 *      script is exercised as a live Sepolia broadcast starting at PB3.5
 *      (`docs/STAGE_P_BIS_SEPOLIA_RUNBOOK.md`). `run()` is the broadcast / simulation entry (reads the
 *      seven inputs from env); `deploy(...)` is the testable no-broadcast entry the StagePIntegration
 *      and StagePRunRehearsal fork fixtures call with resolved args threaded directly. DeployStageP
 *      never constructs or calls this script; the base layer is a P-D31 fixture/env input to it.
 *      Because `deploy(...)` takes explicit typed arguments rather than reading env, it sidesteps the
 *      DER_BODENSEE_POOL / BODENSEE_POOL and SV_ZCHF / SVZCHF env-key divergence P-D25 documents --
 *      a divergence DeployStageP separately normalizes for its OWN env reads (`DeployStageP.s.sol`
 *      L152-L153), unrelated to this entry point.
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
 *        FEE_ROUTING_HOOK    address  — this script's own predicted address; run() asserts the
 *                                       deployed hook equals it (PB-D27 (iv)(3)). Not a ctor input.
 */
contract DeployFeeRoutingHook is Script {
    AureumFeeRoutingHook public feeRoutingHook;

    /// @notice The deployed hook diverged from the `FEE_ROUTING_HOOK` prediction the fee controller
    ///         has already stored as an immutable (PB-D27 (iv)(3)); abort immediately.
    error HookAddressMismatch(address predicted, address actual);

    /// @notice `forge script` entry — deploys the hook from env under broadcast.
    function run() external returns (AureumFeeRoutingHook) {
        address predictedHook = vm.envAddress("FEE_ROUTING_HOOK");
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

        // PB-D27 (iv)(3) — the fee controller stored this address as an immutable before this script
        // ran, so a divergence is unrecoverable: the controller would route fees to an address that
        // holds no hook. Assert before the success log, never after.
        if (address(h) != predictedHook) {
            revert HookAddressMismatch(predictedHook, address(h));
        }
        console2.log("AureumFeeRoutingHook deployed at:", address(h));
        return h;
    }

    /// @notice Testable entry — deploys without broadcast so a fork fixture (StagePIntegration,
    ///         StagePRunRehearsal) can call it with resolved args and read back the handle. Exactly
    ///         one CREATE (the hook). DeployStageP never calls this.
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
