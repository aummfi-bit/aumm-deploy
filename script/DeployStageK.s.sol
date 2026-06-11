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

/**
 * @title DeployStageK
 * @notice Deploys the Stage K governance stack in constructor-dependency order —
 *         VotingWeight -> AureumGovernance -> AureumGovernanceAuthorizer ->
 *         AuMMMinterRouter — per K-D9 and the K14 wiring inventory. This is the
 *         deploy half (K7.2a); the 8-call wiring chain and the Vault.setAuthorizer
 *         governance migration land in K7.2b (_wire).
 * @dev K7.2a scope: the four `new` calls only. The script compiles and deploys the
 *      stack but performs no wiring — no setVotingWeight, setMintRouter,
 *      setGovernanceContract, setMinter, addAuthorizedDonator, or setAuthorizer.
 * @dev H13 — the four governance-stack constructors are all zero-check-only (no external
 *      calls), so they tolerate keccak placeholder env values; however _deploy itself
 *      external-calls IAuMM(AUMM).GENESIS_BLOCK(), so AUMM must be real contract state
 *      in fork tests (K7.3 inherits the Stage-I/J fork fixture per K-D9).
 * @dev Two distinct Bodensee channels — SWAP_AND_DEPOSIT (SwapAndDepositToBodensee, the
 *      proposal-deposit channel) feeds AureumGovernance; BODENSEE_CHANNEL
 *      (BodenseeBootstrapChannel) feeds AuMMMinterRouter. Do not conflate them (K14).
 * @dev One dual-interface registry — MILIARIUM_REGISTRY binds as IMiliariumRegistry
 *      (VotingWeight) and as IMiliariumSlotRegistry (AureumGovernance) per J-D2.
 * @dev Production chain position — DeployStageJ -> DeployStageK per STAGES_OVERVIEW.
 * @dev Env vars required (no defaults — a real deploy must never silently fall back to zero values):
 *
 *        GOVERNANCE_MULTISIG    address  — broadcast/prank deployer + governance gate
 *        AUMM                   address  — deployed AuMM (genesis source via GENESIS_BLOCK())
 *        TVL_ORACLE             address  — shared TVLOracle (VotingWeight value oracle)
 *        GAUGE_REGISTRY         address  — GaugeRegistry (VotingWeight + AureumGovernance)
 *        EMISSION_DISTRIBUTOR   address  — EmissionDistributor (VotingWeight recorder + router consumer)
 *        MILIARIUM_REGISTRY     address  — MiliariumRegistry (IMiliariumRegistry + IMiliariumSlotRegistry)
 *        VAULT                  address  — Balancer V3 Vault (AureumGovernance + Authorizer)
 *        SWAP_AND_DEPOSIT       address  — SwapAndDepositToBodensee proposal-deposit channel
 *        SV_ZCHF                address  — svZCHF deposit token
 *        SUSDS                  address  — sUSDS deposit token
 *        BODENSEE_POOL          address  — der Bodensee pool
 *        EMERGENCY_MULTISIG     address  — emergency authorizer multisig
 *        BODENSEE_CHANNEL       address  — BodenseeBootstrapChannel (AuMMMinterRouter consumer)
 *
 *      (K7.2b wiring additionally reads VAULT_CLASS_REGISTRY.)
 */
contract DeployStageK is Script {
    /// @notice `forge script` entry — broadcasts the governance-stack deployment as GOVERNANCE_MULTISIG.
    function run() external {
        address governor = vm.envAddress("GOVERNANCE_MULTISIG");
        vm.startBroadcast(governor);
        _deploy();
        vm.stopBroadcast();
    }

    /// @notice Testable entry — deploys via vm.startPrank(governor) for fork tests without a live
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
        vm.stopPrank();
        return (votingWeight, governance, authorizer, router);
    }

    /// @dev Deploys the four governance-stack contracts in constructor-dependency order and returns the
    ///      handles. No wiring (K7.2b). genesisBlock_ for VotingWeight is read from the deployed AuMM.
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
}
