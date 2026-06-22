// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";

import { IMiliariumSlotRegistry } from "../src/registry/IMiliariumSlotRegistry.sol";
import { GaugeRegistry } from "../src/gauge/GaugeRegistry.sol";
import { EmissionDistributor } from "../src/emission/EmissionDistributor.sol";

/**
 * @title DeployStageM
 * @notice Bind-only wiring for the five Stage M Major pools — a single
 *         GOVERNANCE_MULTISIG-authored broadcast with no contract deployments.
 *         The Stage-M analog of `DeployStageJ` (registry seed) +
 *         `DeployStageI` (recorder bind) combined, per M-D9. Each Major pool
 *         receives three founding bindings:
 *
 *           1. registry.replaceSlot(slot, pool)              — zero→nonzero SlotPopulated
 *           2. gauge.seedFoundingPool(pool)                   — founding-pool gauge seed (M-D6)
 *           3. distributor.setAuMTContractForPool(pool, hook) — I-D9 shared-hook recorder
 *
 * @dev M-D9 — bind-only. The five Major pools (03 ixCasper / 08 ixBrevis /
 *      09 ixAltrix / 10 ixMediox / 11 ixLongus) are deployed separately by their
 *      M3 `DeployIx*.run()` wrappers (default-sender, mirroring the three Stage-E
 *      pilots) and consumed here as env inputs. `hook.setEmissionRecorder` is
 *      one-shot-bound at Stage I and is NOT re-called.
 *
 * @dev Fail-fast preconditions — `_bind` asserts all three governance gates before
 *      any binding call, mirroring `DeployStageI` / `DeployStageL`: registry,
 *      gauge, and distributor governance must each equal `governor`.
 *
 * @dev Production execution — GOVERNANCE_MULTISIG is the Stage A—K Authorizer Safe,
 *      which has no EOA private key. `run()` is therefore a simulation / calldata
 *      reference: `vm.startBroadcast(governor)` sets the simulated sender to the
 *      multisig so the gated calls succeed under `forge script` simulation; real
 *      on-chain submission is the same fifteen calls (three per pool × five pools)
 *      executed as a Safe transaction batch. The fork test
 *      (`test/fork/DeployStageM.t.sol`, M5) exercises the `deploy(governor)` entry,
 *      which applies the multisig identity via `vm.startPrank` so the gated calls
 *      succeed without a live broadcast.
 *
 * @dev Env vars required (no defaults — a real wire must never silently fall back to
 *      zero values):
 *
 *        GOVERNANCE_MULTISIG   address  — wiring authority; registry + gauge + distributor governance
 *        MILIARIUM_REGISTRY    address  — IMiliariumSlotRegistry (replaceSlot target)
 *        GAUGE_REGISTRY        address  — GaugeRegistry (seedFoundingPool target)
 *        EMISSION_DISTRIBUTOR  address  — EmissionDistributor (setAuMTContractForPool target)
 *        FEE_ROUTING_HOOK      address  — shared-hook recorder (I-D9; per DeployStageI:111)
 *        MAJOR_POOL_03         address  — ixCasper (slot 03)
 *        MAJOR_POOL_08         address  — ixBrevis (slot 08)
 *        MAJOR_POOL_09         address  — ixAltrix (slot 09)
 *        MAJOR_POOL_10         address  — ixMediox (slot 10)
 *        MAJOR_POOL_11         address  — ixLongus (slot 11)
 */
contract DeployStageM is Script {
    /// @notice Reverts when `registry.governanceContract() != governor` at the start of `_bind`.
    error RegistryGovernanceNotMultisig(address actual);

    /// @notice Reverts when `gauge.governanceContract() != governor` at the start of `_bind`.
    error GaugeGovernanceNotMultisig(address actual);

    /// @notice Reverts when `distributor.governance() != governor` at the start of `_bind`.
    error DistributorGovernanceNotMultisig(address actual);

    /// @notice `forge script` entry — broadcasts the bind calls as the GOVERNANCE_MULTISIG
    ///         read from env (simulation / Safe-batch reference).
    function run() external {
        address governor = vm.envAddress("GOVERNANCE_MULTISIG");
        vm.startBroadcast(governor);
        _bind(governor);
        vm.stopBroadcast();
    }

    /// @notice Testable entry — applies the GOVERNANCE_MULTISIG identity via
    ///         `vm.startPrank(governor)` so the gated calls succeed from a fork test
    ///         without a live broadcast.
    function deploy(address governor) external {
        vm.startPrank(governor);
        _bind(governor);
        vm.stopPrank();
    }

    function _bind(address governor) internal {
        IMiliariumSlotRegistry registry = IMiliariumSlotRegistry(vm.envAddress("MILIARIUM_REGISTRY"));
        GaugeRegistry gauge = GaugeRegistry(vm.envAddress("GAUGE_REGISTRY"));
        EmissionDistributor distributor = EmissionDistributor(vm.envAddress("EMISSION_DISTRIBUTOR"));

        if (registry.governanceContract() != governor) {
            revert RegistryGovernanceNotMultisig(registry.governanceContract());
        }
        if (gauge.governanceContract() != governor) {
            revert GaugeGovernanceNotMultisig(gauge.governanceContract());
        }
        if (distributor.governance() != governor) {
            revert DistributorGovernanceNotMultisig(distributor.governance());
        }

        address hook = vm.envAddress("FEE_ROUTING_HOOK");

        uint256[5] memory slots = [uint256(3), 8, 9, 10, 11];
        address[5] memory pools = [
            vm.envAddress("MAJOR_POOL_03"),
            vm.envAddress("MAJOR_POOL_08"),
            vm.envAddress("MAJOR_POOL_09"),
            vm.envAddress("MAJOR_POOL_10"),
            vm.envAddress("MAJOR_POOL_11")
        ];

        for (uint256 i = 0; i < pools.length; i++) {
            registry.replaceSlot(slots[i], pools[i]);
            gauge.seedFoundingPool(pools[i]);
            distributor.setAuMTContractForPool(pools[i], hook);
        }
    }
}
