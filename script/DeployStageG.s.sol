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
 *         seal + the Class-C donateAuthorizer handoff. Per P-D30 + P-D31.
 *
 * @dev Scope — 4 constructors + the internal seal + one in-script authority handoff (P-D25
 *      granular-script rule: one source of truth per constructor call lives here; the P9.5
 *      orchestrator owns sequence + assertions). Per P-D31 the authorities split into three classes:
 *      Class A (seal-only, = `deployer`, must be msg.sender during the seal) — SwapAndDeposit
 *      `moduleAdmin` + GaugeEligibility `gaugeRegistrySetter`; Class B (governance, = `GOVERNANCE_MULTISIG`
 *      at construction, consumed later by the unified governor; VCR's setters are one-shot, unrotatable) —
 *      VaultClassRegistry `votingWeightSetter` + `governanceSetter` + GaugeRegistry `governance`;
 *      Class C (`donateAuthorizer`) = `deployer` through the seal so `addAuthorizedDonator(vcr)` fires,
 *      then handed to `GOVERNANCE_MULTISIG` in-script via `setDonateAuthorizer` at the end of `_deploy`.
 *
 * @dev Deferred to the downstream governor (DeployStageK / the P9.5 orchestrator), reading the
 *      SWAP_AND_DEPOSIT / VAULT_CLASS_REGISTRY / GAUGE_REGISTRY addresses this script produces:
 *      `vaultClassRegistry.setVotingWeight` (K wire 1, as `votingWeightSetter` = GOVERNANCE_MULTISIG),
 *      `vaultClassRegistry.setGovernanceContract` (P9.5 orchestrator, WH-P6 (c), as `governanceSetter`),
 *      `gaugeRegistry.setGovernanceContract` (K rebinds `governance` = GOVERNANCE_MULTISIG to AureumGovernance),
 *      and `swapAndDeposit.addAuthorizedDonator(gov)` (K wire 2, reachable because `donateAuthorizer` was
 *      handed to GOVERNANCE_MULTISIG here). The Class-B authorities bind to GOVERNANCE_MULTISIG at
 *      construction rather than deferring, because the VCR setters are one-shot self-sealing (P-D31).
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
 *        GOVERNANCE_MULTISIG   address  — unified governor (P-D31 Class B/C: VCR setters + GaugeRegistry.governance + the donateAuthorizer handoff target)
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
     *         the env `GOVERNANCE_MULTISIG` governor (PB-D23 (ii) — composable from the
     *         production `DeployStageP.run()`), returns the four deployed contracts.
     */
    function run()
        external
        returns (SwapAndDepositToBodensee, VaultClassRegistry, GaugeEligibility, GaugeRegistry)
    {
        address governor = vm.envAddress("GOVERNANCE_MULTISIG");
        vm.startBroadcast(governor);
        _deploy(governor);
        vm.stopBroadcast();
        return (swapAndDeposit, vaultClassRegistry, gaugeEligibility, gaugeRegistry);
    }

    /**
     * @notice Testable entry point — the same deployment sequence as `run()` without
     *         `vm.startBroadcast`, callable from a fork test as `deployer.deploy(address(this))`.
     *         `deployer` owns the CREATE context and becomes the Class-A seal authority plus the
     *         Class-C `donateAuthorizer` (until the in-script handoff), so the internal seal fires
     *         from the authority that deployed the stack.
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
        address governanceMultisig = vm.envAddress("GOVERNANCE_MULTISIG");
        uint256 genesisBlock     = aumm.GENESIS_BLOCK();

        // -- 1. SwapAndDepositToBodensee (Class A moduleAdmin + Class C donateAuthorizer = deployer) --
        swapAndDeposit = new SwapAndDepositToBodensee(
            vault,
            bodenseePool,
            svZchf,
            sUsds,
            deployer,
            deployer
        );

        // -- 2. VaultClassRegistry (Class B votingWeightSetter + governanceSetter = GOVERNANCE_MULTISIG;
        //       genesis admitted-4626 from GaugeGenesisManifest) --
        (
            address[] memory genesisTokens,
            IVaultClassRegistry.AdmissionType[] memory genesisTypes
        ) = GaugeGenesisManifest.genesis();

        vaultClassRegistry = new VaultClassRegistry(
            svZchf,
            swapAndDeposit,
            governanceMultisig,
            governanceMultisig,
            genesisTokens,
            genesisTypes
        );

        // -- 3. GaugeEligibility (Class A gaugeRegistrySetter = deployer; 8-arg AuMM-only per P9.4a) --
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

        // -- 4. GaugeRegistry (Class B governance = GOVERNANCE_MULTISIG; genesisBlock from aumm.GENESIS_BLOCK()) --
        gaugeRegistry = new GaugeRegistry(
            governanceMultisig,
            address(gaugeEligibility),
            address(swapAndDeposit),
            address(svZchf),
            genesisBlock
        );

        // -- 5. Internal seal (as deployer — Class A/C seal authorities) ------------------
        swapAndDeposit.setVaultClassRegistry(address(vaultClassRegistry));
        swapAndDeposit.setGaugeRegistry(address(gaugeRegistry));
        gaugeEligibility.setGaugeRegistry(address(gaugeRegistry));
        swapAndDeposit.addAuthorizedDonator(address(vaultClassRegistry));

        // -- 6. Class C handoff — donateAuthorizer: deployer -> GOVERNANCE_MULTISIG (P-D31), after the
        //       seal's addAuthorizedDonator(vcr) fired as deployer; setDonateAuthorizer is multi-shot.
        swapAndDeposit.setDonateAuthorizer(governanceMultisig);
    }
}
