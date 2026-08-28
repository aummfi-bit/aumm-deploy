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
 * @dev run() composes the sub-scripts' own run() entries under the env GOVERNANCE_MULTISIG (PB-D23); the base layer stays per-granular user-run (PB3.5). deploy() is the fork/prank spine (GOVERNANCE_MULTISIG == address(this)).
 */
contract DeployStageP is Script {
    error BaseLayerGovernorMismatch(address expected, address actual);
    error GenesisBlockMismatch(address contractAddr, uint256 expected, uint256 actual);
    error RosterPoolNotGauged(address pool);
    error RosterPoolRecorderUnbound(address pool);
    error AuthorizerNotMigrated(address expected, address actual);
    error CCBGaugeRegistryNotSealed(address expected, address actual);
    /// @dev Fires when the accept entry runs but the L-D25 boost leg is still unbound, per PP-D46.
    error IncendiaryRegistryNotBound(address expected, address actual);

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

    /// @notice Production orchestration entry (PB-D23) — composes the sub-scripts' `run()` entries under the
    ///         env governor; the un-defer of the former `ProductionOrchestrationDeferredToPbis` footgun-guard.
    ///         Fork-rehearsed at PB3.4d before any broadcast; the live Sepolia broadcast is PB3.5 (§8b).
    function run() external {
        _setupEnvProduction();
        _assertBaseLayerGovernorProduction();
        _orchestrateProduction();
        _assertPostConditions();
    }

    /// @notice Second production invocation — run after `run()` at a strictly later block, because
    ///         `forge script` executes an entry at a single `block.number` and the PP-D44 two-step
    ///         requires the accept to land after the propose. `run()` arms the registry and this
    ///         commits it, after which the L-D25 boost leg is live.
    /// @dev This assertion lives here and NOT in `_assertPostConditions()` because that runs at the
    ///      end of `run()`, where the registry is legitimately still unbound — asserting it there
    ///      would fail the spine by design, per PP-D46.
    function runAcceptRegistry() external {
        (new DeployStageL()).runAcceptRegistry();
        EmissionDistributor distributor = EmissionDistributor(vm.envAddress("EMISSION_DISTRIBUTOR"));
        address bound = distributor.incendiaryRegistry();
        if (bound != vm.envAddress("INCENDIARY_REGISTRY")) {
            revert IncendiaryRegistryNotBound(vm.envAddress("INCENDIARY_REGISTRY"), bound);
        }
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

        gaugeRegistry.seedFoundingPool(vm.envAddress("MILIARIUM_POOL_01"));
        gaugeRegistry.seedFoundingPool(vm.envAddress("MILIARIUM_POOL_05"));
        gaugeRegistry.seedFoundingPool(vm.envAddress("MILIARIUM_POOL_14"));

        incendiaryRegistry = (new DeployStageL()).deploy(address(this));

        DeployStageK k = new DeployStageK();
        (votingWeight, governance, authorizer, minterRouter) = k.deploy(address(this));

        // PB-D11 (iii) / PB-D23 (iii) — the VaultClassRegistry governance one-shot binds POST-K to the
        // AureumGovernance instance (never the multisig), so revokeVaultClass lives at on-chain governance.
        vaultClassRegistry.setGovernanceContract(address(governance));
    }

    /// @notice Production env setup — mirrors `_setupEnv` but NEVER overrides `GOVERNANCE_MULTISIG` (PB-D23 (i);
    ///         production reads the real governor from env). Only the intra-run passthrough aliases are set.
    function _setupEnvProduction() internal {
        vm.setEnv("VAULT_EXPLORER", vm.toString(vm.envAddress("VAULT")));
        vm.setEnv("SVZCHF", vm.toString(vm.envAddress("SV_ZCHF")));
    }

    /// @notice Production base-layer governor check — asserts the base-layer authorizer's GOVERNANCE_MULTISIG
    ///         equals the ENV governor (PB-D23 (i); the fork `_assertBaseLayerGovernor` checks address(this)).
    function _assertBaseLayerGovernorProduction() internal view {
        address governor = vm.envAddress("GOVERNANCE_MULTISIG");
        address actual = AureumAuthorizer(address(IVault(vm.envAddress("VAULT")).getAuthorizer())).GOVERNANCE_MULTISIG();
        if (actual != governor) revert BaseLayerGovernorMismatch(governor, actual);
    }

    /// @notice Production orchestration per PB-D23 (i) — composes the sub-scripts' own `run()` entries (each
    ///         self-broadcasting as the env GOVERNANCE_MULTISIG), captures their handles from the PB-D24 (ii)
    ///         public storage / the F-G-H returns, and fires the orchestrator's own binds under its own
    ///         `vm.startBroadcast(governor)` blocks (sequential, never nested inside a sub-`run()` broadcast).
    ///         The CCB seal is the direct-governor path — the CCBMultiplier's CREATE sender is the governor
    ///         under F's broadcast, so `setGaugeRegistry` is a direct call, not the `f.sealGaugeRegistry`
    ///         forward the fork `deploy()` uses.
    function _orchestrateProduction() internal {
        address governor = vm.envAddress("GOVERNANCE_MULTISIG");

        DeployStageJ j = new DeployStageJ();
        j.run();
        miliariumRegistry = j.miliariumRegistry();
        vm.setEnv("MILIARIUM_REGISTRY", vm.toString(address(miliariumRegistry)));
        // PB3.8: `governor`, NOT `address(this)`. `forge script` rejects `address(this)` in a
        // script contract: under --broadcast the script is ephemeral and never deployed, so its
        // address is meaningless. Any non-zero address satisfies the CCBMultiplier constructor,
        // which zero-checks all three registries and calls none of them, and this slot is sealed
        // to the real GaugeRegistry below once the G stack lands. The fork `deploy()` path at L102
        // keeps `address(this)` deliberately — there the script contract genuinely exists.
        vm.setEnv("GAUGE_REGISTRY_PLACEHOLDER", vm.toString(governor));

        DeployStageF f = new DeployStageF();
        (tvlOracle, efficiencyOracle, emaSampler, ccbMultiplier) = f.run();
        vm.setEnv("TVL_ORACLE", vm.toString(address(tvlOracle)));
        vm.setEnv("EFFICIENCY_ORACLE", vm.toString(address(efficiencyOracle)));
        vm.setEnv("EMA_SAMPLER", vm.toString(address(emaSampler)));
        vm.setEnv("CCB_MULTIPLIER", vm.toString(address(ccbMultiplier)));

        DeployStageG g = new DeployStageG();
        (swapAndDeposit, vaultClassRegistry, , gaugeRegistry) = g.run();
        vm.setEnv("SWAP_AND_DEPOSIT", vm.toString(address(swapAndDeposit)));
        vm.setEnv("VAULT_CLASS_REGISTRY", vm.toString(address(vaultClassRegistry)));
        vm.setEnv("GAUGE_REGISTRY", vm.toString(address(gaugeRegistry)));

        // CCB seal — direct governor call (PB-D23 (i) dual-path; broadcast rewrote the CREATE sender to governor).
        vm.startBroadcast(governor);
        ccbMultiplier.setGaugeRegistry(gaugeRegistry);
        vm.stopBroadcast();

        DeployStageH h = new DeployStageH();
        emissionDistributor = h.run();
        bodenseeBootstrapChannel = h.bodenseeBootstrapChannel();
        vm.setEnv("EMISSION_DISTRIBUTOR", vm.toString(address(emissionDistributor)));
        vm.setEnv("BODENSEE_CHANNEL", vm.toString(address(bodenseeBootstrapChannel)));

        vm.startBroadcast(governor);
        efficiencyOracle.setEmissionsRecorder(address(emissionDistributor));
        vm.stopBroadcast();

        (new DeployStageI()).run();
        (new DeployStageM()).run();
        (new DeployStageN()).run();

        vm.startBroadcast(governor);
        gaugeRegistry.seedFoundingPool(vm.envAddress("MILIARIUM_POOL_01"));
        gaugeRegistry.seedFoundingPool(vm.envAddress("MILIARIUM_POOL_05"));
        gaugeRegistry.seedFoundingPool(vm.envAddress("MILIARIUM_POOL_14"));
        vm.stopBroadcast();

        DeployStageL l = new DeployStageL();
        l.run();
        incendiaryRegistry = l.incendiaryRegistry();

        DeployStageK k = new DeployStageK();
        k.run();
        votingWeight = k.votingWeight();
        governance = k.governance();
        authorizer = k.authorizer();
        minterRouter = k.minterRouter();

        // PB-D11 (iii) / PB-D23 (iii) — the VaultClassRegistry governance one-shot binds POST-K to AureumGovernance.
        vm.startBroadcast(governor);
        vaultClassRegistry.setGovernanceContract(address(governance));
        vm.stopBroadcast();
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
            vm.envAddress("MILIARIUM_POOL_01"),
            vm.envAddress("MILIARIUM_POOL_05"),
            vm.envAddress("MILIARIUM_POOL_14"),
            vm.envAddress("MILIARIUM_POOL_03"),
            vm.envAddress("MILIARIUM_POOL_08"),
            vm.envAddress("MILIARIUM_POOL_09"),
            vm.envAddress("MILIARIUM_POOL_10"),
            vm.envAddress("MILIARIUM_POOL_11"),
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
