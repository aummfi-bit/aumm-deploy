// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { DeployStageF } from "./DeployStageF.s.sol";
import { DeployStageG } from "./DeployStageG.s.sol";
import { DeployStageH } from "./DeployStageH.s.sol";
import { DeployStageI } from "./DeployStageI.s.sol";
import { DeployStageJ } from "./DeployStageJ.s.sol";
import { DeployStageK } from "./DeployStageK.s.sol";
import { DeployStageL } from "./DeployStageL.s.sol";
import { DeployStageM } from "./DeployStageM.s.sol";
import { DeployStageN } from "./DeployStageN.s.sol";
import { AureumAuthorizer } from "../src/vault/AureumAuthorizer.sol";
import { AuMM } from "../src/token/AuMM.sol";
import { MiliariumRegistry } from "../src/registry/MiliariumRegistry.sol";
import { TVLOracle } from "../src/emission/TVLOracle.sol";
import { EfficiencyOracle } from "../src/emission/EfficiencyOracle.sol";
import { EmissionDistributor } from "../src/emission/EmissionDistributor.sol";
import { BodenseeBootstrapChannel } from "../src/emission/BodenseeBootstrapChannel.sol";
import { EMASampler } from "../src/ccb/EMASampler.sol";
import { CCBMultiplier } from "../src/ccb/CCBMultiplier.sol";
import { SwapAndDepositToBodensee } from "../src/gauge/SwapAndDepositToBodensee.sol";
import { VaultClassRegistry } from "../src/gauge/VaultClassRegistry.sol";
import { GaugeRegistry } from "../src/gauge/GaugeRegistry.sol";
import { IncendiaryRegistry } from "../src/incendiary/IncendiaryRegistry.sol";
import { VotingWeight } from "../src/governance/VotingWeight.sol";
import { AureumGovernance } from "../src/governance/AureumGovernance.sol";
import { AureumGovernanceAuthorizer } from "../src/governance/AureumGovernanceAuthorizer.sol";
import { AuMMMinterRouter } from "../src/token/AuMMMinterRouter.sol";

/**
 * @title DeployStageP
 * @notice Thin P9.5 orchestrator per P-D32 — deploys no contract itself; delegates to J/F/G/H/I/M/N/L/K
 *         in chain order, 3 direct binds, 4 post-conditions.
 * @dev The base layer (tokens/vault/factory/hook/der Bodensee/26 pools) is a fixture/env input per P-D31
 *      Tier A and MUST be deployed with GOVERNANCE_MULTISIG == address(this) — fixture ordering:
 *      new DeployStageP → setEnv GOVERNANCE_MULTISIG=address(orchestrator) → deploy base layer → deploy().
 * @dev run() reverts — production is per-granular-script Safe batches (P-bis, P-D23/P-D26).
 */
contract DeployStageP is Script {
    error BaseLayerGovernorMismatch(address expected, address actual);
    error ProductionOrchestrationDeferredToPbis();
    error GenesisBlockMismatch(address contractAddr, uint256 expected, uint256 actual);
    error RosterPoolNotGauged(address pool);
    error RosterPoolRecorderUnbound(address pool);
    error AuthorizerNotMigrated(address expected, address actual);
    error CCBGaugeRegistryNotSealed(address expected, address actual);

    MiliariumRegistry public miliariumRegistry;
    TVLOracle public tvlOracle;
    EfficiencyOracle public efficiencyOracle;
    EMASampler public emaSampler;
    CCBMultiplier public ccbMultiplier;
    SwapAndDepositToBodensee public swapAndDeposit;
    VaultClassRegistry public vaultClassRegistry;
    GaugeRegistry public gaugeRegistry;
    EmissionDistributor public emissionDistributor;
    BodenseeBootstrapChannel public bodenseeBootstrapChannel;
    IncendiaryRegistry public incendiaryRegistry;
    VotingWeight public votingWeight;
    AureumGovernance public governance;
    AureumGovernanceAuthorizer public authorizer;
    AuMMMinterRouter public minterRouter;

    /// @notice Hard footgun-guard — production orchestration is deferred to P-bis per-granular Safe batches.
    function run() external {
        revert ProductionOrchestrationDeferredToPbis();
    }

    /// @notice Testable entry — env setup, base-layer governor sentinel, chain-order delegation, post-conditions.
    function deploy() external {
        _setupEnv();
        _assertBaseLayerGovernor();
        _orchestrate();
        _assertPostConditions();
    }

    function _setupEnv() internal {
        vm.setEnv("GOVERNANCE_MULTISIG", vm.toString(address(this)));
        vm.setEnv("VAULT_EXPLORER", vm.toString(vm.envAddress("VAULT")));
        vm.setEnv("SVZCHF", vm.toString(vm.envAddress("SV_ZCHF")));
    }

    function _assertBaseLayerGovernor() internal view {
        address actual = AureumAuthorizer(address(IVault(vm.envAddress("VAULT")).getAuthorizer())).GOVERNANCE_MULTISIG();
        if (actual != address(this)) revert BaseLayerGovernorMismatch(address(this), actual);
    }

    function _orchestrate() internal {
        miliariumRegistry = (new DeployStageJ()).deploy(address(this));
        vm.setEnv("MILIARIUM_REGISTRY", vm.toString(address(miliariumRegistry)));
        // GAUGE_REGISTRY_PLACEHOLDER — CCBMultiplier ctor input per PB-D18 (v); the real GaugeRegistry
        // deploys later (G after F), so a non-zero throwaway (this orchestrator) is passed and replaced by
        // f.sealGaugeRegistry() once the G-stack lands. Never read pre-seal (no updateMultiplier during orchestration).
        vm.setEnv("GAUGE_REGISTRY_PLACEHOLDER", vm.toString(address(this)));

        DeployStageF f = new DeployStageF();
        (tvlOracle, efficiencyOracle, emaSampler, ccbMultiplier) = f.deploy(address(f));
        vm.setEnv("TVL_ORACLE", vm.toString(address(tvlOracle)));
        vm.setEnv("EFFICIENCY_ORACLE", vm.toString(address(efficiencyOracle)));
        vm.setEnv("EMA_SAMPLER", vm.toString(address(emaSampler)));
        vm.setEnv("CCB_MULTIPLIER", vm.toString(address(ccbMultiplier)));

        DeployStageG g = new DeployStageG();
        (swapAndDeposit, vaultClassRegistry, , gaugeRegistry) = g.deploy(address(g));
        vm.setEnv("SWAP_AND_DEPOSIT", vm.toString(address(swapAndDeposit)));
        vm.setEnv("VAULT_CLASS_REGISTRY", vm.toString(address(vaultClassRegistry)));
        vm.setEnv("GAUGE_REGISTRY", vm.toString(address(gaugeRegistry)));

        // PB-D18 (v) — seal the CCBMultiplier delta_global enumeration to the concrete GaugeRegistry now that
        // the G-stack exists; forwarded through `f` because f (not this orchestrator) is the pinned setter.
        f.sealGaugeRegistry(gaugeRegistry);

        DeployStageH h = new DeployStageH();
        emissionDistributor = h.deploy(address(h));
        bodenseeBootstrapChannel = h.bodenseeBootstrapChannel();
        vm.setEnv("EMISSION_DISTRIBUTOR", vm.toString(address(emissionDistributor)));
        vm.setEnv("BODENSEE_CHANNEL", vm.toString(address(bodenseeBootstrapChannel)));

        efficiencyOracle.setEmissionsRecorder(address(emissionDistributor));

        (new DeployStageI()).deploy(address(this));

        (new DeployStageM()).deploy(address(this));

        (new DeployStageN()).deploy(address(this));

        gaugeRegistry.seedFoundingPool(vm.envAddress("PILOT_POOL_01"));
        gaugeRegistry.seedFoundingPool(vm.envAddress("PILOT_POOL_05"));
        gaugeRegistry.seedFoundingPool(vm.envAddress("PILOT_POOL_14"));

        incendiaryRegistry = (new DeployStageL()).deploy(address(this));

        DeployStageK k = new DeployStageK();
        (votingWeight, governance, authorizer, minterRouter) = k.deploy(address(this));

        // PB-D11 (iii) / PB-D23 (iii) — the VaultClassRegistry governance one-shot binds POST-K to the
        // AureumGovernance instance (never the multisig), so revokeVaultClass lives at on-chain governance.
        vaultClassRegistry.setGovernanceContract(address(governance));
    }

    function _assertPostConditions() internal view {
        uint256 gb = gaugeRegistry.GENESIS_BLOCK();

        uint256 actual = efficiencyOracle.GENESIS_BLOCK();
        if (actual != gb) revert GenesisBlockMismatch(address(efficiencyOracle), gb, actual);

        actual = emissionDistributor.GENESIS_BLOCK();
        if (actual != gb) revert GenesisBlockMismatch(address(emissionDistributor), gb, actual);

        actual = AuMM(vm.envAddress("AUMM")).GENESIS_BLOCK();
        if (actual != gb) revert GenesisBlockMismatch(vm.envAddress("AUMM"), gb, actual);

        address hook = vm.envAddress("FEE_ROUTING_HOOK");
        address[26] memory pools = _rosterPools();
        for (uint256 i = 0; i < pools.length; i++) {
            address p = pools[i];
            if (!gaugeRegistry.isGaugeApproved(p)) revert RosterPoolNotGauged(p);
            if (emissionDistributor.auMTContractByPool(p) != hook) revert RosterPoolRecorderUnbound(p);
        }

        // Post-condition (3) — trustedRouter: the orchestrator makes no setTrustedRouter call (P-D26 (4), structural).

        if (address(IVault(vm.envAddress("VAULT")).getAuthorizer()) != address(authorizer)) {
            revert AuthorizerNotMigrated(address(authorizer), address(IVault(vm.envAddress("VAULT")).getAuthorizer()));
        }

        // Post-condition (4) — the CCBMultiplier gauge-registry seal landed on the concrete GaugeRegistry (PB-D18 (v)).
        address sealedGauge = address(ccbMultiplier.gaugeRegistry());
        if (sealedGauge != address(gaugeRegistry)) {
            revert CCBGaugeRegistryNotSealed(address(gaugeRegistry), sealedGauge);
        }
    }

    function _rosterPools() internal view returns (address[26] memory) {
        return [
            vm.envAddress("PILOT_POOL_01"),
            vm.envAddress("PILOT_POOL_05"),
            vm.envAddress("PILOT_POOL_14"),
            vm.envAddress("MAJOR_POOL_03"),
            vm.envAddress("MAJOR_POOL_08"),
            vm.envAddress("MAJOR_POOL_09"),
            vm.envAddress("MAJOR_POOL_10"),
            vm.envAddress("MAJOR_POOL_11"),
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
    }
}
