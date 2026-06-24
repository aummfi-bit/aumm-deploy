// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";

import { IMiliariumSlotRegistry } from "../src/registry/IMiliariumSlotRegistry.sol";
import { GaugeRegistry } from "../src/gauge/GaugeRegistry.sol";
import { EmissionDistributor } from "../src/emission/EmissionDistributor.sol";

/**
 * @title DeployStageN
 * @notice Bind-only wiring for the eighteen Stage N pools — a single
 *         GOVERNANCE_MULTISIG-authored broadcast with no contract deployments.
 *         The Stage-N analog of `DeployStageJ` (registry seed) +
 *         `DeployStageI` (recorder bind) combined, per M-D9. Each pool
 *         receives three founding bindings:
 *
 *           1. registry.replaceSlot(slot, pool)              — zero→nonzero SlotPopulated
 *           2. gauge.seedFoundingPool(pool)                   — founding-pool gauge seed (M-D6)
 *           3. distributor.setAuMTContractForPool(pool, hook) — I-D9 shared-hook recorder
 *
 * @dev M-D9 — bind-only. The eighteen pools — sixteen Sector-3 clean Standard pools
 *      {12 ixStrata, 13 ixForum, 15 ixRegistrum, 16 ixDebitum, 17 ixEquitix, 18 ixInnovix,
 *      19 ixGigantus, 20 ixMagnix, 21 ixNubix, 22 ixMoneta, 23 ixColossix, 24 ixVitalix,
 *      25 ixMedicix, 26 ixMercatura, 27 ixAurix, 28 ixMetallum} plus the two resolvable
 *      Majors 02 ixAetheron / 06 ixLibertas — are deployed separately by their
 *      `DeployIx*.run()` wrappers (default-sender, mirroring the Stage-E pilots) and
 *      consumed here as env inputs. `hook.setEmissionRecorder` is one-shot-bound at Stage I
 *      and is NOT re-called.
 *
 * @dev Fail-fast preconditions — `_bind` asserts all three governance gates before
 *      any binding call, mirroring `DeployStageI` / `DeployStageL`: registry,
 *      gauge, and distributor governance must each equal `governor`.
 *
 * @dev Production execution — GOVERNANCE_MULTISIG is the Stage A—K Authorizer Safe,
 *      which has no EOA private key. `run()` is therefore a simulation / calldata
 *      reference: `vm.startBroadcast(governor)` sets the simulated sender to the
 *      multisig so the gated calls succeed under `forge script` simulation; real
 *      on-chain submission is the same fifty-four calls (three per pool × eighteen pools)
 *      executed as a Safe transaction batch. The fork test
 *      (`test/fork/DeployStageN.t.sol`, N6) exercises the `deploy(governor)` entry,
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
 *        MILIARIUM_POOL_02     address  — ixAetheron (slot 02)
 *        MILIARIUM_POOL_06     address  — ixLibertas (slot 06)
 *        MILIARIUM_POOL_12     address  — ixStrata (slot 12)
 *        MILIARIUM_POOL_13     address  — ixForum (slot 13)
 *        MILIARIUM_POOL_15     address  — ixRegistrum (slot 15)
 *        MILIARIUM_POOL_16     address  — ixDebitum (slot 16)
 *        MILIARIUM_POOL_17     address  — ixEquitix (slot 17)
 *        MILIARIUM_POOL_18     address  — ixInnovix (slot 18)
 *        MILIARIUM_POOL_19     address  — ixGigantus (slot 19)
 *        MILIARIUM_POOL_20     address  — ixMagnix (slot 20)
 *        MILIARIUM_POOL_21     address  — ixNubix (slot 21)
 *        MILIARIUM_POOL_22     address  — ixMoneta (slot 22)
 *        MILIARIUM_POOL_23     address  — ixColossix (slot 23)
 *        MILIARIUM_POOL_24     address  — ixVitalix (slot 24)
 *        MILIARIUM_POOL_25     address  — ixMedicix (slot 25)
 *        MILIARIUM_POOL_26     address  — ixMercatura (slot 26)
 *        MILIARIUM_POOL_27     address  — ixAurix (slot 27)
 *        MILIARIUM_POOL_28     address  — ixMetallum (slot 28)
 */
contract DeployStageN is Script {
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

        uint256[18] memory slots = [uint256(2), 6, 12, 13, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28];
        address[18] memory pools = [
            vm.envAddress("MILIARIUM_POOL_02"),
            vm.envAddress("MILIARIUM_POOL_06"),
            vm.envAddress("MILIARIUM_POOL_12"),
            vm.envAddress("MILIARIUM_POOL_13"),
            vm.envAddress("MILIARIUM_POOL_15"),
            vm.envAddress("MILIARIUM_POOL_16"),
            vm.envAddress("MILIARIUM_POOL_17"),
            vm.envAddress("MILIARIUM_POOL_18"),
            vm.envAddress("MILIARIUM_POOL_19"),
            vm.envAddress("MILIARIUM_POOL_20"),
            vm.envAddress("MILIARIUM_POOL_21"),
            vm.envAddress("MILIARIUM_POOL_22"),
            vm.envAddress("MILIARIUM_POOL_23"),
            vm.envAddress("MILIARIUM_POOL_24"),
            vm.envAddress("MILIARIUM_POOL_25"),
            vm.envAddress("MILIARIUM_POOL_26"),
            vm.envAddress("MILIARIUM_POOL_27"),
            vm.envAddress("MILIARIUM_POOL_28")
        ];

        for (uint256 i = 0; i < pools.length; i++) {
            registry.replaceSlot(slots[i], pools[i]);
            gauge.seedFoundingPool(pools[i]);
            distributor.setAuMTContractForPool(pools[i], hook);
        }
    }
}
