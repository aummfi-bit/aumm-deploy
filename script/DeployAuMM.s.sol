// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";

import { AuMM } from "../src/token/AuMM.sol";

/**
 * @title DeployAuMM
 * @notice Deploys the AuMM ERC-20 — the fixed-cap, geometric-halving emission token.
 *         Per H-D42, AuMM is a Stage H / Stage K *input*, not an artifact those stages
 *         deploy: this standalone micro-script deploys it first, and downstream scripts
 *         (`DeployDerBodensee` L39, `DeployStageH`, `DeployStageK`) read the resulting
 *         address from the `AUMM` env var (mirroring the existing env convention).
 * @dev H13-safe — AuMM's constructor is storage-only (zero-check on `minterAdmin_`, then
 *      assigns `GENESIS_BLOCK` + `_minterAdmin`); it makes no external calls, so this
 *      script needs no fork state.
 * @dev Production chain position — DeployAuMM → DeployDerBodensee → DeployStageH →
 *      DeployStageI → DeployStageJ → DeployStageK (the AuMM address threads through as
 *      the `AUMM` env input at each step).
 * @dev `GOVERNANCE_MULTISIG` is the constructor `minterAdmin_` (C-D11 one-shot setter
 *      principal); it calls `aumm.setMinter(router)` during the Stage K handoff per
 *      K-D7 / K-D9, after which setter authority is permanently zeroed.
 * @dev Env vars required (no defaults — a real deploy must never silently fall back to zero):
 *
 *        GENESIS_BLOCK         uint     — Era 0 anchor block for the emission schedule
 *        GOVERNANCE_MULTISIG   address  — one-shot minter admin (setMinter principal)
 */
contract DeployAuMM is Script {
    /// @notice `forge script` entry — broadcasts the AuMM deployment. Returns the address.
    function run() external returns (address aumm) {
        uint256 genesisBlock = vm.envUint("GENESIS_BLOCK");
        address minterAdmin = vm.envAddress("GOVERNANCE_MULTISIG");
        vm.startBroadcast();
        aumm = address(new AuMM(genesisBlock, minterAdmin));
        vm.stopBroadcast();
        console2.log("AuMM deployed at:", aumm);
    }
}
