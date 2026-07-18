// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";

import { IncendiaryRegistry } from "../src/incendiary/IncendiaryRegistry.sol";
import { SwapAndDepositToBodensee } from "../src/gauge/SwapAndDepositToBodensee.sol";
import { EmissionDistributor } from "../src/emission/EmissionDistributor.sol";
import { IGaugeRegistry } from "../src/ccb/IGaugeRegistry.sol";
import { IAuMM } from "../src/token/IAuMM.sol";
import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployStageL
 * @notice Deploys the Stage L Incendiary Boost producer and wires both gates in a
 *         single multisig-authored broadcast — `new IncendiaryRegistry(...)` plus
 *         donate-channel authorization and distributor registry binding:
 *
 *           1. channel.addAuthorizedDonator(registry)     — L-D2 deposit tail (G-D21)
 *           2. distributor.setIncendiaryRegistry(registry)  — L-D25 boost-delivery leg
 *
 * @dev L-D28 — wiring authority is GOVERNANCE_MULTISIG only; there is no deployer→multisig
 *      handoff. Post-Stage-K both gates remain multisig-held: `channel.donateAuthorizer()`
 *      stays at the multisig (DeployStageK:158 only `addAuthorizedDonator`s AureumGovernance,
 *      never `setDonateAuthorizer`) and `distributor.governance()` stays at the multisig
 *      (K-D9 hands only gauge + Miliarium governance to AureumGovernance). A single broadcast
 *      authored by the multisig therefore satisfies both `onlyDonateAuthorizer` and
 *      `onlyGovernance`.
 *
 * @dev Production execution — GOVERNANCE_MULTISIG is the Stage A—K Authorizer Safe, which
 *      has no EOA private key. `run()` is therefore a simulation / calldata reference:
 *      `vm.startBroadcast(governor)` sets the simulated sender to the multisig so the gated
 *      calls succeed under `forge script` simulation; real on-chain submission is the same
 *      three calls executed as a Safe transaction batch. The fork test
 *      (`test/fork/DeployStageL.t.sol`, L9.2) exercises the `deploy(governor)` entry, which
 *      applies the multisig identity via `vm.startPrank` so the gated calls succeed without a
 *      live broadcast.
 *
 * @dev Fail-fast preconditions — `_deployAndWire` asserts both gates before any binding call,
 *      so a run against a mis-staged chain reverts with a named diagnostic instead of
 *      partial-binding then reverting mid-wire with the cryptic upstream gate error (I-D18
 *      mirror): `DistributorGovernanceNotMultisig` when `distributor.governance() != governor`;
 *      `DonateAuthorizerNotMultisig` when `channel.donateAuthorizer() != governor`.
 *
 * @dev Ctor arg 1 sources `SWAP_AND_DEPOSIT` (the G-D21 donate channel typed
 *      `SwapAndDepositToBodensee`) — NOT `BODENSEE_CHANNEL`, which names the separate Stage-H
 *      `BodenseeBootstrapChannel`. `genesisBlock_` (ctor arg 8) is read as `aumm.GENESIS_BLOCK()`,
 *      not a separate env var (DeployStageK:117 precedent). `VAULT` is cast `IVaultExplorer`
 *      — L8.6 proved `getPoolData` resolves on the mainnet Vault.
 *
 * @dev Env vars required (no defaults — a real deploy must never silently fall back to zero values):
 *
 *        GOVERNANCE_MULTISIG   address  — wiring authority; donateAuthorizer + distributor governance
 *        SWAP_AND_DEPOSIT      address  — G-D21 donate channel (IncendiaryRegistry ctor arg 1)
 *        BODENSEE_POOL         address  — der Bodensee WeightedPool (ctor arg 2)
 *        VAULT                 address  — cast IVaultExplorer (ctor arg 3)
 *        AUMM                  address  — IAuMM + GENESIS_BLOCK source (ctor args 4 + 8)
 *        SV_ZCHF               address  — svZCHF rail (ctor arg 5)
 *        SUSDS                 address  — sUSDS rail (ctor arg 6)
 *        GAUGE_REGISTRY        address  — IGaugeRegistry (ctor arg 7)
 *        EMISSION_DISTRIBUTOR  address  — setIncendiaryRegistry target
 */
contract DeployStageL is Script {
    /// @notice Reverts when `distributor.governance() != governor` at the start of
    ///         `_deployAndWire` — confirms the L-D28 precondition that distributor governance
    ///         is still GOVERNANCE_MULTISIG post-Stage-K (K-D9 emission-layer slot).
    error DistributorGovernanceNotMultisig(address actual);

    /// @notice Reverts when `channel.donateAuthorizer() != governor` at the start of
    ///         `_deployAndWire` — confirms the L-D28 precondition that the donate channel
    ///         authorizer is still GOVERNANCE_MULTISIG post-Stage-K.
    error DonateAuthorizerNotMultisig(address actual);

    /// @notice The deployed IncendiaryRegistry — public so the composed `DeployStageP.run()` reads it
    ///         after `run()` (PB-D24 (ii)); populated inside `_deployAndWire`, so both entry points set it.
    IncendiaryRegistry public incendiaryRegistry;

    /// @notice `forge script` entry — broadcasts deploy + wire as the GOVERNANCE_MULTISIG
    ///         read from env (simulation / Safe-batch reference).
    function run() external {
        address governor = vm.envAddress("GOVERNANCE_MULTISIG");
        vm.startBroadcast(governor);
        _deployAndWire(governor);
        vm.stopBroadcast();
    }

    /// @notice Testable entry — applies the GOVERNANCE_MULTISIG identity via
    ///         `vm.startPrank(governor)` so the gated calls succeed from a fork test without
    ///         a live broadcast. Returns the deployed registry for assertions.
    function deploy(address governor) external returns (IncendiaryRegistry) {
        vm.startPrank(governor);
        IncendiaryRegistry registry = _deployAndWire(governor);
        vm.stopPrank();
        return registry;
    }

    /// @dev Fail-fast both gates, deploy `IncendiaryRegistry`, wire donate authorization + distributor binding.
    function _deployAndWire(address governor) internal returns (IncendiaryRegistry) {
        SwapAndDepositToBodensee channel = SwapAndDepositToBodensee(vm.envAddress("SWAP_AND_DEPOSIT"));
        EmissionDistributor distributor = EmissionDistributor(vm.envAddress("EMISSION_DISTRIBUTOR"));

        if (distributor.governance() != governor) revert DistributorGovernanceNotMultisig(distributor.governance());
        if (channel.donateAuthorizer() != governor) revert DonateAuthorizerNotMultisig(channel.donateAuthorizer());

        IAuMM aumm = IAuMM(vm.envAddress("AUMM"));
        IncendiaryRegistry registry = new IncendiaryRegistry(
            channel,
            vm.envAddress("BODENSEE_POOL"),
            IVaultExplorer(vm.envAddress("VAULT")),
            aumm,
            IERC20(vm.envAddress("SV_ZCHF")),
            IERC20(vm.envAddress("SUSDS")),
            IGaugeRegistry(vm.envAddress("GAUGE_REGISTRY")),
            aumm.GENESIS_BLOCK()
        );
        channel.addAuthorizedDonator(address(registry));
        distributor.setIncendiaryRegistry(address(registry));
        incendiaryRegistry = registry;
        return registry;
    }
}
