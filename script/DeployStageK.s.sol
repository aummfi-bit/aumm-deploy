// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { ITVLOracle } from "../src/ccb/ITVLOracle.sol";
import { IGaugeRegistry } from "../src/ccb/IGaugeRegistry.sol";
import { IMiliariumRegistry } from "../src/ccb/IMiliariumRegistry.sol";
import { IMiliariumSlotRegistry } from "../src/registry/IMiliariumSlotRegistry.sol";
import { IEmissionDistributor } from "../src/emission/IEmissionDistributor.sol";
import { SwapAndDepositToBodensee } from "../src/gauge/SwapAndDepositToBodensee.sol";
import { IAuMM } from "../src/token/IAuMM.sol";
import { VotingWeight } from "../src/governance/VotingWeight.sol";
import { AureumGovernance } from "../src/governance/AureumGovernance.sol";
import { AureumGovernanceAuthorizer } from "../src/governance/AureumGovernanceAuthorizer.sol";
import { AuMMMinterRouter } from "../src/token/AuMMMinterRouter.sol";
// K7.2b wiring-target concrete types — these setters are concrete-only (not exposed on the
// contracts' interfaces), so the deploy-half interface handles cannot reach them.
import { VaultClassRegistry } from "../src/gauge/VaultClassRegistry.sol";
import { BodenseeBootstrapChannel } from "../src/emission/BodenseeBootstrapChannel.sol";
import { EmissionDistributor } from "../src/emission/EmissionDistributor.sol";

/**
 * @title DeployStageK
 * @notice Deploys AND wires the Stage K governance stack — VotingWeight ->
 *         AureumGovernance -> AureumGovernanceAuthorizer -> AuMMMinterRouter (deploy, in
 *         constructor-dependency order) followed by the eight-call wiring chain that
 *         migrates the gauge + Miliarium governance to the on-chain governance contract
 *         and the Vault authorizer to AureumGovernanceAuthorizer — per K-D9 and the K14
 *         wiring inventory. _deploy() (K7.2a) performs the four `new` calls; _wire()
 *         (K7.2b) performs the eight wiring calls; both run() and deploy() deploy then wire.
 * @dev Wiring chain (8 calls, load-bearing order per K14): (1) VaultClassRegistry.setVotingWeight;
 *      (2) SwapAndDepositToBodensee.addAuthorizedDonator(governance); (3) BodenseeBootstrapChannel.setMintRouter
 *      and (4) EmissionDistributor.setMintRouter (BEFORE the handoff, K-D7); (5) AuMM.setMinter(router)
 *      (C-D11 one-shot); (6) GaugeRegistry.setGovernanceContract and (7) MiliariumRegistry.setGovernanceContract
 *      (the handoff); (8) Vault.setAuthorizer(authorizer) (OQ-10 migration, LAST). Handoff scope is gauge +
 *      Miliarium ONLY per K-D9 — emission-layer and VaultClassRegistry governance slots stay at the multisig.
 * @dev Single-governor caller model (K14) — all four deploys and eight wiring calls execute as one `governor`
 *      (= GOVERNANCE_MULTISIG) via vm.startBroadcast / vm.startPrank; deploy and migrate share one run.
 *      Production preconditions (governor holds the setter/governance role on each wiring target and is
 *      authorized for Vault.setAuthorizer by the current Stage B Safe authorizer) are the deployer's
 *      responsibility — the script states them, it cannot enforce them.
 * @dev H13 — the four governance-stack constructors are all zero-check-only (no external calls), so they
 *      tolerate keccak placeholder env values; however _deploy itself external-calls IAuMM(AUMM).GENESIS_BLOCK()
 *      and _wire external-calls every live wiring target, so AUMM and the eight wiring targets must be real
 *      contract state in fork tests (K7.3 inherits the Stage-I/J fork fixture per K-D9).
 * @dev Two distinct Bodensee channels — SWAP_AND_DEPOSIT (SwapAndDepositToBodensee, the proposal-deposit
 *      channel) feeds AureumGovernance and receives addAuthorizedDonator; BODENSEE_CHANNEL
 *      (BodenseeBootstrapChannel, the bootstrap-emission channel) feeds AuMMMinterRouter and receives
 *      setMintRouter. Do not conflate them (K14).
 * @dev One dual-interface registry — MILIARIUM_REGISTRY binds as IMiliariumRegistry (VotingWeight) and as
 *      IMiliariumSlotRegistry (AureumGovernance ctor + setGovernanceContract handoff) per J-D2.
 * @dev Production chain position — DeployStageJ -> DeployStageK per STAGES_OVERVIEW.
 * @dev Env vars required (no defaults — a real deploy must never silently fall back to zero values):
 *
 *        GOVERNANCE_MULTISIG    address  — broadcast/prank deployer + handoff caller
 *        AUMM                   address  — deployed AuMM (genesis source + setMinter target)
 *        TVL_ORACLE             address  — shared TVLOracle (VotingWeight value oracle)
 *        GAUGE_REGISTRY         address  — GaugeRegistry (VotingWeight + AureumGovernance + handoff)
 *        EMISSION_DISTRIBUTOR   address  — EmissionDistributor (VotingWeight recorder + setMintRouter)
 *        MILIARIUM_REGISTRY     address  — MiliariumRegistry (IMiliariumRegistry + IMiliariumSlotRegistry + handoff)
 *        VAULT                  address  — Balancer V3 Vault (AureumGovernance + Authorizer + setAuthorizer)
 *        SWAP_AND_DEPOSIT       address  — SwapAndDepositToBodensee proposal-deposit channel + addAuthorizedDonator
 *        SV_ZCHF                address  — svZCHF deposit token
 *        SUSDS                  address  — sUSDS deposit token
 *        BODENSEE_POOL          address  — der Bodensee pool
 *        EMERGENCY_MULTISIG     address  — emergency authorizer multisig
 *        BODENSEE_CHANNEL       address  — BodenseeBootstrapChannel (AuMMMinterRouter consumer + setMintRouter)
 *        VAULT_CLASS_REGISTRY   address  — VaultClassRegistry (setVotingWeight self-seal)
 */
contract DeployStageK is Script {
    /// @notice `forge script` entry — broadcasts the full governance-stack deploy + wire as GOVERNANCE_MULTISIG.
    function run() external {
        address governor = vm.envAddress("GOVERNANCE_MULTISIG");
        vm.startBroadcast(governor);
        (
            VotingWeight votingWeight,
            AureumGovernance governance,
            AureumGovernanceAuthorizer authorizer,
            AuMMMinterRouter router
        ) = _deploy();
        _wire(votingWeight, governance, authorizer, router);
        vm.stopBroadcast();
    }
    /// @notice Testable entry — deploys and wires via vm.startPrank(governor) for fork tests without a live
    ///         broadcast. Returns the four deployed handles for assertions.
    function deploy(address governor)
        external
        returns (VotingWeight, AureumGovernance, AureumGovernanceAuthorizer, AuMMMinterRouter)
    {
        vm.startPrank(governor);
        (
            VotingWeight votingWeight,
            AureumGovernance governance,
            AureumGovernanceAuthorizer authorizer,
            AuMMMinterRouter router
        ) = _deploy();
        _wire(votingWeight, governance, authorizer, router);
        vm.stopPrank();
        return (votingWeight, governance, authorizer, router);
    }
    /// @dev Deploys the four governance-stack contracts in constructor-dependency order and returns the
    ///      handles. No wiring (that is _wire). genesisBlock_ for VotingWeight is read from the deployed AuMM.
    function _deploy()
        internal
        returns (VotingWeight, AureumGovernance, AureumGovernanceAuthorizer, AuMMMinterRouter)
    {
        IAuMM aumm = IAuMM(vm.envAddress("AUMM"));
        VotingWeight votingWeight = new VotingWeight(
            ITVLOracle(vm.envAddress("TVL_ORACLE")),
            IGaugeRegistry(vm.envAddress("GAUGE_REGISTRY")),
            IEmissionDistributor(vm.envAddress("EMISSION_DISTRIBUTOR")),
            IMiliariumRegistry(vm.envAddress("MILIARIUM_REGISTRY")),
            aumm.GENESIS_BLOCK()
        );
        AureumGovernance governance = new AureumGovernance(
            votingWeight,
            IGaugeRegistry(vm.envAddress("GAUGE_REGISTRY")),
            IMiliariumSlotRegistry(vm.envAddress("MILIARIUM_REGISTRY")),
            IVault(vm.envAddress("VAULT")),
            SwapAndDepositToBodensee(vm.envAddress("SWAP_AND_DEPOSIT")),
            IERC20(vm.envAddress("SV_ZCHF")),
            IERC20(vm.envAddress("SUSDS")),
            vm.envAddress("BODENSEE_POOL")
        );
        AureumGovernanceAuthorizer authorizer = new AureumGovernanceAuthorizer(
            address(governance),
            vm.envAddress("EMERGENCY_MULTISIG"),
            vm.envAddress("VAULT")
        );
        AuMMMinterRouter router = new AuMMMinterRouter(
            aumm,
            vm.envAddress("BODENSEE_CHANNEL"),
            vm.envAddress("EMISSION_DISTRIBUTOR")
        );
        return (votingWeight, governance, authorizer, router);
    }
    /// @dev Wires the deployed stack into the live protocol as `governor` (single-governor caller model, K14):
    ///      eight calls in load-bearing order. (1) VaultClassRegistry.setVotingWeight self-seal; (2)
    ///      addAuthorizedDonator so AureumGovernance can post proposal deposits; (3) + (4) bind the mint router
    ///      on both emission channels BEFORE the handoff (K-D7); (5) AuMM one-shot setMinter to the router
    ///      (C-D11); (6) + (7) the gauge + Miliarium governance handoff (K-D9 scope — emission-layer and
    ///      VaultClassRegistry governance slots stay at the multisig); (8) the OQ-10 Vault authorizer migration,
    ///      LAST. `IVault` inherits `IVaultAdmin.setAuthorizer`; AureumGovernanceAuthorizer `is IAuthorizer`, so
    ///      the authorizer handle upcasts implicitly.
    function _wire(
        VotingWeight votingWeight,
        AureumGovernance governance,
        AureumGovernanceAuthorizer authorizer,
        AuMMMinterRouter router
    ) internal {
        // (1) self-seal the voting-weight reader into the VaultClassRegistry veto path
        VaultClassRegistry(vm.envAddress("VAULT_CLASS_REGISTRY")).setVotingWeight(address(votingWeight));
        // (2) authorize governance to post proposal deposits through the SwapAndDeposit channel
        SwapAndDepositToBodensee(vm.envAddress("SWAP_AND_DEPOSIT")).addAuthorizedDonator(address(governance));
        // (3) + (4) bind the mint router on both emission channels BEFORE the handoff (K-D7)
        BodenseeBootstrapChannel(vm.envAddress("BODENSEE_CHANNEL")).setMintRouter(address(router));
        EmissionDistributor(vm.envAddress("EMISSION_DISTRIBUTOR")).setMintRouter(address(router));
        // (5) hand AuMM's one-shot minter slot to the router (C-D11)
        IAuMM(vm.envAddress("AUMM")).setMinter(address(router));
        // (6) + (7) the gauge + Miliarium governance handoff (K-D9 scope)
        IGaugeRegistry(vm.envAddress("GAUGE_REGISTRY")).setGovernanceContract(address(governance));
        IMiliariumSlotRegistry(vm.envAddress("MILIARIUM_REGISTRY")).setGovernanceContract(address(governance));
        // (8) OQ-10 Vault authorizer migration — LAST, the actual governance handoff
        IVault(vm.envAddress("VAULT")).setAuthorizer(authorizer);
    }
}
