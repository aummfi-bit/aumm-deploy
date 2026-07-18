// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { Router } from "@balancer-labs/v3-vault/contracts/Router.sol";

/**
 * @title DeployRouter
 * @notice Deploys the canonical Balancer V3 `Router` (pinned submodule, byte-unmodified) against the
 *         Aureum Vault — the PB-D22 / P-D26 close-out. The Router is the production user-facing
 *         entrypoint for swaps, liquidity, and queries; its `getSender()` is what the F-09
 *         trusted-router allowlist attributes recorder credit to.
 * @dev H13-audited: the full constructor chain is storage-only — `Router` (empty body) →
 *      `RouterCommon` (stores `_weth` + `_permit2`) → `VaultGuard` (stores `_vault`) + `Version`
 *      (stores the version string). No external calls, so this script needs no fork state; address
 *      correctness is the operator's responsibility via the env contract below.
 * @dev Chain position — deployed AFTER the base layer (Vault live at `AUREUM_VAULT`); the hook seat
 *      sequence follows post-orchestration per PB-D22 (iii): the multisig one-shot
 *      `setGovernanceModule(GOVERNANCE_MULTISIG)`, then `setTrustedRouter(router, true)` — honoring
 *      the WH-P6 S10 (b) ordering (orchestrator recorder binds precede the seat). Exercised on a
 *      mainnet fork at the PB3.3d witness; live Sepolia sequence at PB3.5 under per-command §8b.
 * @dev Env vars required (no defaults per PB-D22 (ii) — a real deploy must never silently fall
 *      back to zero):
 *
 *        AUREUM_VAULT      address — the Aureum Vault this Router unlocks
 *        WETH_ADDRESS      address — mainnet WETH on the fork witness; the Sepolia WETH9 address is
 *                                    read and verified §8b at the PB3.5 broadcast, never hardcoded
 *        PERMIT2_ADDRESS   address — the canonical cross-chain Permit2
 *                                    (0x000000000022D473030F116dDEE9F6B43aC78BA3; Sepolia presence
 *                                    verified at PB3.1)
 */
contract DeployRouter is Script {
    /// @notice PB-D22 (iv) — Aureum-branded version string: truthful provenance for an
    ///         Aureum-operated deployment of the canonical bytecode (exposed via `version()`).
    string public constant ROUTER_VERSION = "Aureum V3 Router v1 (Balancer V3 Router, pinned 68057fda)";

    /// @notice `forge script` entry — broadcasts the Router deployment. Returns the address.
    function run() external returns (address router) {
        address vault = vm.envAddress("AUREUM_VAULT");
        address weth = vm.envAddress("WETH_ADDRESS");
        address permit2 = vm.envAddress("PERMIT2_ADDRESS");
        vm.startBroadcast();
        router = address(new Router(IVault(vault), IWETH(weth), IPermit2(permit2), ROUTER_VERSION));
        vm.stopBroadcast();
        console2.log("Aureum Router deployed at:", router);
    }
}
