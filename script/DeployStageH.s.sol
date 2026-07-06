// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { AuMM } from "../src/token/AuMM.sol";
import { IAuMM } from "../src/token/IAuMM.sol";
import { IEfficiencyOracle } from "../src/gauge/IEfficiencyOracle.sol";
import { BodenseeBootstrapChannel } from "../src/emission/BodenseeBootstrapChannel.sol";
import { EmissionDistributor } from "../src/emission/EmissionDistributor.sol";
import { IGaugeRegistry } from "../src/ccb/IGaugeRegistry.sol";
import { IEMASampler } from "../src/ccb/IEMASampler.sol";
import { ICCBMultiplier } from "../src/ccb/ICCBMultiplier.sol";
import { IMiliariumRegistry } from "../src/ccb/IMiliariumRegistry.sol";

/**
 * @title DeployStageH
 * @notice Deploys the Stage H emission stack in a single broadcast:
 *         TVLOracle, EfficiencyOracle, BodenseeBootstrapChannel,
 *         and EmissionDistributor. AuMM is consumed as an input via the
 *         AUMM env var per H-D42 — it must already be deployed before
 *         this script runs.
 *
 * @dev H-D42 — AuMM is a Stage H input, not a Stage H output. The
 *      chicken-and-egg: `BodenseeBootstrapChannel`'s constructor calls
 *      `_vault.getPoolTokens(BODENSEE_POOL)` to resolve the AuMM token
 *      index per H-D12, which requires `BODENSEE_POOL` to already exist
 *      in `VAULT` with AuMM in its token roster — impossible if AuMM is
 *      deployed in-script (the address is not yet known when the Bodensee
 *      pool was registered). The canonical convention is established by
 *      `script/DeployDerBodensee.s.sol:L39` (`address aumm =
 *      vm.envAddress("AUMM")`): any downstream script that references
 *      `BODENSEE_POOL` must consume AuMM via env var rather than redeploy.
 *      Implied production chain: DeployAuMM → DeployDerBodensee →
 *      DeployStageH. `script/DeployAuMM.s.sol` is deferred to a later
 *      H-x sub-step or Stage K opening.
 *
 * @dev H-D7 Option C — `aumm.setMinter()` is NOT called by this script.
 *      AuMM must have been deployed with `_minterAdmin = GOVERNANCE_MULTISIG`
 *      and `setMinter()` must not yet have been called (`aumm.minter() ==
 *      address(0)`). The Stage K governance migration can then invoke
 *      `setMinter()` exactly once to wire the resolved minter target per
 *      H-D41 (Option A or Option B). The post-deploy invariant assertion
 *      in `_deploy` Step 8 confirms `aumm.minter() == address(0)` before
 *      returning — a `MinterNotZero` revert surfaces a misconfigured AuMM
 *      input rather than an in-script deployment error.
 *
 * @dev `genesisBlock` is derived from `aumm.GENESIS_BLOCK()` (public
 *      immutable) rather than a separate env var — single source of truth,
 *      no drift possible between the AuMM emission schedule anchor and the
 *      downstream `EfficiencyOracle`, `BodenseeBootstrapChannel`, and
 *      `EmissionDistributor` constructor arguments.
 *
 * @dev Governance handoff pattern — the deployer address is passed as
 *      `initialGovernance` to the four governance-bearing contracts
 *      (TVLOracle, EfficiencyOracle, BodenseeBootstrapChannel,
 *      EmissionDistributor).  After post-deploy wiring (Step 6,
 *      `efficiencyOracle.setEmissionsRecorder`), Step 7 calls
 *      `setGovernanceContract(GOVERNANCE_MULTISIG)` on all four contracts
 *      in sequence, leaving the deployer with no residual authority.
 *
 * @dev Env vars required (no defaults — a real deploy must never silently
 *      fall back to zero values):
 *
 *        GOVERNANCE_MULTISIG   address  — final governance for all four emission-stack
 *                                         contracts; must match the AuMM input's
 *                                         _minterAdmin (verify before deploy)
 *        AUMM                  address  — AuMM ERC-20 (H-D42 input; must satisfy
 *                                         minter() == address(0) precondition)
 *        VAULT                 address  — Balancer V3 Vault (BodenseeBootstrapChannel H-D12)
 *        VAULT_EXPLORER        address  — Balancer V3 IVaultExplorer (TVLOracle H-D9)
 *        BODENSEE_POOL         address  — bootstrap destination per H-D14
 *        SVZCHF                address  — svZCHF numéraire per H-D9
 *        GAUGE_REGISTRY        address  — Stage G GaugeRegistry (EmissionDistributor H-D5)
 *        EMA_SAMPLER           address  — Stage F EMASampler (EmissionDistributor H-D17)
 *        CCB_MULTIPLIER        address  — Stage F CCBMultiplier (EmissionDistributor H-D17)
 *        MILIARIUM_REGISTRY    address  — Stage J placeholder (EmissionDistributor H-D31)
 */
contract DeployStageH is Script {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Reverts if `aumm.minter() != address(0)` at the end of `_deploy` —
    ///         confirms the H-D42 input precondition (AUMM env var must point at an
    ///         AuMM whose `setMinter()` has not yet been called) and the H-D7 Option C
    ///         invariant (setMinter deferred to Stage K).
    error MinterNotZero(address minter);

    // -------------------------------------------------------------------------
    // State — populated during _deploy() so a fork test can read them back
    // -------------------------------------------------------------------------

    AuMM public aumm;
    BodenseeBootstrapChannel public bodenseeBootstrapChannel;
    EmissionDistributor public emissionDistributor;

    // -------------------------------------------------------------------------
    // Entry points
    // -------------------------------------------------------------------------

    /**
     * @notice `forge script` entry point. Reads env vars, broadcasts all
     *         deployments as `msg.sender`, returns the EmissionDistributor.
     */
    function run() external returns (EmissionDistributor) {
        vm.startBroadcast();
        EmissionDistributor d = _deploy(msg.sender);
        vm.stopBroadcast();
        return d;
    }

    /**
     * @notice Testable entry point. Performs the same deployment sequence as
     *         `run()` but without `vm.startBroadcast`, so it can be called
     *         directly from a fork test as `deployer.deploy(address(this))`.
     *         The `deployer` argument is the address used as `initialGovernance`
     *         for the four governance-bearing contracts — it must be the address
     *         that owns the current CREATE context so that Step 6 wiring
     *         succeeds before the Step 7 handoff fires.
     */
    function deploy(address deployer) external returns (EmissionDistributor) {
        return _deploy(deployer);
    }

    // -------------------------------------------------------------------------
    // Internal deploy sequence
    // -------------------------------------------------------------------------

    function _deploy(address deployer) internal returns (EmissionDistributor) {
        // -- 0. Read config from env (no defaults on purpose) ----------------
        // H-D42: AuMM consumed as input; genesisBlock derived from aumm.GENESIS_BLOCK()
        // (single source of truth — no separate GENESIS_BLOCK env var).
        // P-D28: TVLOracle + EfficiencyOracle moved to DeployStageF; EFFICIENCY_ORACLE
        // is consumed as an input here alongside EMA_SAMPLER + CCB_MULTIPLIER.

        address governanceMultisig           = vm.envAddress("GOVERNANCE_MULTISIG");
        aumm                                 = AuMM(vm.envAddress("AUMM"));
        IVault vault                         = IVault(vm.envAddress("VAULT"));
        address bodenseePool                 = vm.envAddress("BODENSEE_POOL");
        IGaugeRegistry gaugeRegistry         = IGaugeRegistry(vm.envAddress("GAUGE_REGISTRY"));
        IEMASampler emaSampler               = IEMASampler(vm.envAddress("EMA_SAMPLER"));
        ICCBMultiplier ccbMultiplier         = ICCBMultiplier(vm.envAddress("CCB_MULTIPLIER"));
        IEfficiencyOracle efficiencyOracle   = IEfficiencyOracle(vm.envAddress("EFFICIENCY_ORACLE"));
        IMiliariumRegistry miliariumRegistry = IMiliariumRegistry(vm.envAddress("MILIARIUM_REGISTRY"));
        uint256 genesisBlock                 = aumm.GENESIS_BLOCK();

        // -- 1. AuMM consumed as input per H-D42; setMinter() not called per H-D7 Option C --
        // Input precondition aumm.minter() == address(0) asserted at Step 4.
        // Input precondition _minterAdmin == GOVERNANCE_MULTISIG is the caller's
        // responsibility — surfaces at Stage K governance migration if violated.

        // -- 2. BodenseeBootstrapChannel ----------------------------------------

        bodenseeBootstrapChannel = new BodenseeBootstrapChannel(
            vault,
            bodenseePool,
            IAuMM(address(aumm)),
            genesisBlock,
            deployer
        );

        // -- 3. EmissionDistributor ---------------------------------------------

        emissionDistributor = new EmissionDistributor(
            IAuMM(address(aumm)),
            gaugeRegistry,
            emaSampler,
            ccbMultiplier,
            efficiencyOracle,
            miliariumRegistry,
            genesisBlock,
            deployer
        );

        // -- 4. Governance handoff to GOVERNANCE_MULTISIG ----------------------
        // P-D28: TVLOracle + EfficiencyOracle handoffs happen in DeployStageF; the
        // efficiencyOracle.setEmissionsRecorder(distributor) wiring is the P9.5
        // orchestrator's job (cross-script — EfficiencyOracle in F, distributor here).

        bodenseeBootstrapChannel.setGovernanceContract(governanceMultisig);
        emissionDistributor.setGovernanceContract(governanceMultisig);

        // -- 5. Invariant assertion — H-D7 Option C + H-D42 input precondition --------
        // A MinterNotZero revert here means the AUMM env var pointed at an AuMM
        // whose setMinter() was already called, which the Stage K migration cannot
        // then proceed against.

        if (aumm.minter() != address(0)) revert MinterNotZero(aumm.minter());

        return emissionDistributor;
    }
}
