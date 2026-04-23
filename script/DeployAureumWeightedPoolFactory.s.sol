// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

/**
 * @title DeployAureumWeightedPoolFactory
 * @notice Fork-only deployment; factory bound to AUREUM_VAULT (not mainnet Balancer vault); bytecode is
 *         Balancer's unchanged submodule bytecode; only the IVault constructor argument and version strings
 *         differ from Balancer mainnet WPF.
 *
 * @dev **D-D6:** fork-only scope; no production broadcast path.
 *
 * @dev **D30:** Factory sourcing resolution — the `WEIGHTED_POOL_FACTORY` env consumed by
 *      `script/DeployDerBodensee.s.sol` is expected to be this script's output, not a mainnet Balancer WPF
 *      address. Lists the 4-step deploy order: (1) `DeployAureumVault.s.sol` → sets `AUREUM_VAULT` env,
 *      (2) this script → sets `WEIGHTED_POOL_FACTORY` env, (3) AuMM / stand-in token deploy → sets `AUMM` env,
 *      (4) `DeployDerBodensee.s.sol`.
 *
 * @dev Seconds-vs-block-number asymmetry: `PAUSE_WINDOW_DURATION` is `uint32` seconds by Balancer bytecode
 *      definition (inherited third-party surface); one of the few time-in-seconds surfaces in the Aureum stack;
 *      elsewhere CLAUDE.md §5's block-number canonical-time rule holds.
 *
 * @dev Identity metadata: `FACTORY_VERSION` / `POOL_VERSION` are JSON strings following Balancer's deploy-task
 *      convention; baked as contract constants (not env-sourced) to prevent silent tampering; bump on substantive changes.
 */
contract DeployAureumWeightedPoolFactory is Script {
    uint32 internal constant PAUSE_WINDOW_DURATION = 4 * 365 days;
    string internal constant FACTORY_VERSION = '{"name":"AureumWeightedPoolFactory","version":1,"deployment":"20260423-fork"}';
    string internal constant POOL_VERSION = '{"name":"AureumWeightedPool","version":1,"deployment":"20260423-fork"}';

    function run() external returns (address factory) {
        address aureumVault = vm.envAddress("AUREUM_VAULT");
        vm.startBroadcast();
        factory = address(new WeightedPoolFactory(IVault(aureumVault), PAUSE_WINDOW_DURATION, FACTORY_VERSION, POOL_VERSION));
        vm.stopBroadcast();
        console2.log("Aureum WeightedPoolFactory (WPF) deployed at:", factory);
        console2.log("Bound vault (AUREUM_VAULT):", aureumVault);
        console2.log("Pause window duration (seconds):", PAUSE_WINDOW_DURATION);
    }
}
