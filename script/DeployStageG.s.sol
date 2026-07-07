// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { IAuMM } from "../src/token/IAuMM.sol";
import { SwapAndDepositToBodensee } from "../src/gauge/SwapAndDepositToBodensee.sol";
import { VaultClassRegistry } from "../src/gauge/VaultClassRegistry.sol";
import { IVaultClassRegistry } from "../src/gauge/IVaultClassRegistry.sol";
import { GaugeEligibility } from "../src/gauge/GaugeEligibility.sol";
import { GaugeRegistry } from "../src/gauge/GaugeRegistry.sol";
import { GaugeGenesisManifest } from "./config/GaugeGenesisManifest.sol";

/**
 * @title DeployStageG
 * @notice Deploys the Stage G gauge stack in a single broadcast — SwapAndDepositToBodensee,
 *         VaultClassRegistry, GaugeEligibility, GaugeRegistry — then applies the internal wiring
 *         seal. Per P-D30.
 *
 * @dev Scope — 4 constructors + the internal seal only (P-D25 granular-script rule: one source of
 *      truth per constructor call lives here; the P9.5 orchestrator owns sequence + assertions).
 *      Every setter/admin authority (SwapAndDeposit moduleAdmin + donateAuthorizer, VaultClassRegistry
 *      votingWeightSetter + governanceSetter, GaugeEligibility gaugeRegistrySetter) and GaugeRegistry's
 *      initial governance are set to `deployer`, so the deployer retains the authority the downstream
 *      governance handoff needs.
 *
 * @dev Deferred out of this script (no in-script governance handoff). Per K14 the DeployStageK run
 *      completes the cross-stage wiring against Stage-K contracts that do not exist yet when G deploys
 *      — `vaultClassRegistry.setVotingWeight`, `gaugeRegistry.setGovernanceContract`,
 *      `swapAndDeposit.addAuthorizedDonator(gov)` — reading the SWAP_AND_DEPOSIT / VAULT_CLASS_REGISTRY
 *      / GAUGE_REGISTRY addresses this script produces; the P9.5 orchestrator adds
 *      `vaultClassRegistry.setGovernanceContract(multisig)` (WH-P6 (c)).
 *
 * @dev genesisBlock is derived from `aumm.GENESIS_BLOCK()` (public immutable) — single source of
 *      truth, auto-satisfies the P-D14 (1) 4-way GENESIS_BLOCK equality against EfficiencyOracle /
 *      EmissionDistributor (asserted by the P9.5 orchestrator). No separate GENESIS_BLOCK env var.
 *
 * @dev The genesis admitted-ERC-4626 class set (VaultClassRegistry constructor arrays) comes from
 *      GaugeGenesisManifest.genesis() — the P-D30 11-token full union; governance-mutable thereafter.
 *
 * @dev Env vars required (no defaults — a real deploy must never silently fall back to zero):
 *
 *        VAULT                 address  — Balancer V3 Aureum Vault
 *        BODENSEE_POOL         address  — der Bodensee pool (SwapAndDeposit G-D12 token-index resolution)
 *        AUMM                  address  — AuMM ERC-20 (GaugeEligibility forbidden token + genesisBlock source)
 *        SV_ZCHF               address  — svZCHF (bond + fee token; SwapAndDeposit / VaultClassRegistry / GaugeRegistry)
 *        SUSDS                 address  — sUSDS (SwapAndDeposit Bodensee pay-token)
 *        WEIGHTED_POOL_FACTORY address  — AureumWeightedPoolFactory (GaugeEligibility G-D15a approvedFactory)
 *        TVL_ORACLE            address  — Stage F TVLOracle (GaugeEligibility OQ-G2)
 *        EFFICIENCY_ORACLE     address  — Stage F EfficiencyOracle (GaugeEligibility G-D23)
 *        FEE_ROUTING_HOOK      address  — Stage D AureumFeeRoutingHook (GaugeEligibility I-D13 canonical-hook gate)
 */
contract DeployStageG is Script {
    // -------------------------------------------------------------------------
    // State — populated during _deploy() so a fork test can read them back
    // -------------------------------------------------------------------------

    SwapAndDepositToBodensee public swapAndDeposit;
    VaultClassRegistry public vaultClassRegistry;
    GaugeEligibility public gaugeEligibility;
    GaugeRegistry public gaugeRegistry;

    // -------------------------------------------------------------------------
    // Entry points
    // -------------------------------------------------------------------------

    /**
     * @notice `forge script` entry point. Reads env vars, broadcasts all deployments as
     *         `msg.sender`, returns the four deployed contracts.
     */
    function run()
        external
        returns (SwapAndDepositToBodensee, VaultClassRegistry, GaugeEligibility, GaugeRegistry)
    {
        vm.startBroadcast();
        _deploy(msg.sender);
        vm.stopBroadcast();
        return (swapAndDeposit, vaultClassRegistry, gaugeEligibility, gaugeRegistry);
    }

    /**
     * @notice Testable entry point — the same deployment sequence as `run()` without
     *         `vm.startBroadcast`, callable from a fork test as `deployer.deploy(address(this))`.
     *         `deployer` owns the CREATE context and becomes every setter/admin authority plus
     *         GaugeRegistry's initial governance, so the internal seal fires from the authority
     *         that deployed the stack.
     */
    function deploy(address deployer)
        external
        returns (SwapAndDepositToBodensee, VaultClassRegistry, GaugeEligibility, GaugeRegistry)
    {
        _deploy(deployer);
        return (swapAndDeposit, vaultClassRegistry, gaugeEligibility, gaugeRegistry);
    }

    // -------------------------------------------------------------------------
    // Internal deploy sequence
    // -------------------------------------------------------------------------

    function _deploy(address deployer) internal {
        // -- 0. Read config from env (no defaults on purpose) -----------------
        IVault vault             = IVault(vm.envAddress("VAULT"));
        address bodenseePool     = vm.envAddress("BODENSEE_POOL");
        IAuMM aumm               = IAuMM(vm.envAddress("AUMM"));
        IERC20 svZchf            = IERC20(vm.envAddress("SV_ZCHF"));
        IERC20 sUsds             = IERC20(vm.envAddress("SUSDS"));
        address approvedFactory  = vm.envAddress("WEIGHTED_POOL_FACTORY");
        address tvlOracle        = vm.envAddress("TVL_ORACLE");
        address efficiencyOracle = vm.envAddress("EFFICIENCY_ORACLE");
        address feeRoutingHook   = vm.envAddress("FEE_ROUTING_HOOK");
        uint256 genesisBlock     = aumm.GENESIS_BLOCK();

        // -- 1. SwapAndDepositToBodensee (moduleAdmin + donateAuthorizer = deployer) ----
        swapAndDeposit = new SwapAndDepositToBodensee(
            vault,
            bodenseePool,
            svZchf,
            sUsds,
            deployer,
            deployer
        );

        // -- 2. VaultClassRegistry (genesis admitted-4626 from GaugeGenesisManifest; setters = deployer) --
        (
            address[] memory genesisTokens,
            IVaultClassRegistry.AdmissionType[] memory genesisTypes
        ) = GaugeGenesisManifest.genesis();

        vaultClassRegistry = new VaultClassRegistry(
            svZchf,
            swapAndDeposit,
            deployer,
            deployer,
            genesisTokens,
            genesisTypes
        );

        // -- 3. GaugeEligibility (8-arg AuMM-only per P9.4a; gaugeRegistrySetter = deployer) -----
        gaugeEligibility = new GaugeEligibility(
            approvedFactory,
            address(vaultClassRegistry),
            tvlOracle,
            address(vault),
            address(aumm),
            deployer,
            efficiencyOracle,
            feeRoutingHook
        );

        // -- 4. GaugeRegistry (initial governance = deployer; genesisBlock from aumm.GENESIS_BLOCK()) --
        gaugeRegistry = new GaugeRegistry(
            deployer,
            address(gaugeEligibility),
            address(swapAndDeposit),
            address(svZchf),
            genesisBlock
        );

        // -- 5. Internal seal (as deployer — every setter authority is deployer) ----------
        swapAndDeposit.setVaultClassRegistry(address(vaultClassRegistry));
        swapAndDeposit.setGaugeRegistry(address(gaugeRegistry));
        gaugeEligibility.setGaugeRegistry(address(gaugeRegistry));
        swapAndDeposit.addAuthorizedDonator(address(vaultClassRegistry));
    }
}
