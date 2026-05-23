// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";

import { AuMM } from "../src/token/AuMM.sol";
import { IAuMM } from "../src/token/IAuMM.sol";
import { TVLOracle } from "../src/emission/TVLOracle.sol";
import { ITVLOracle } from "../src/ccb/ITVLOracle.sol";
import { EfficiencyOracle } from "../src/emission/EfficiencyOracle.sol";
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
 *         AuMM, TVLOracle, EfficiencyOracle, BodenseeBootstrapChannel,
 *         and EmissionDistributor.
 *
 * @dev H-D7 Option C — `aumm.setMinter()` is NOT called by this script.
 *      AuMM is constructed with `_minterAdmin = GOVERNANCE_MULTISIG` so that
 *      the Stage K governance migration can invoke `setMinter()` exactly once
 *      to wire the resolved minter target per H-D41 (Option A or Option B).
 *      Until then, `aumm.minter() == address(0)` and `distribute()` / `claim()`
 *      revert `NotMinter` if called.  The post-deploy invariant assertion in
 *      `_deploy` confirms `aumm.minter() == address(0)` before returning.
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
 *        GOVERNANCE_MULTISIG   address  — AuMM minterAdmin + final governance
 *        VAULT                 address  — Balancer V3 Vault (BodenseeBootstrapChannel H-D12)
 *        VAULT_EXPLORER        address  — Balancer V3 IVaultExplorer (TVLOracle H-D9)
 *        BODENSEE_POOL         address  — bootstrap destination per H-D14
 *        SVZCHF                address  — svZCHF numéraire per H-D9
 *        GAUGE_REGISTRY        address  — Stage G GaugeRegistry (EmissionDistributor H-D5)
 *        EMA_SAMPLER           address  — Stage F EMASampler (EmissionDistributor H-D17)
 *        CCB_MULTIPLIER        address  — Stage F CCBMultiplier (EmissionDistributor H-D17)
 *        MILIARIUM_REGISTRY    address  — Stage J placeholder (EmissionDistributor H-D31)
 *        GENESIS_BLOCK         uint256  — emission schedule anchor per H-D11 / H-D21
 */
contract DeployStageH is Script {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Reverts if `aumm.minter() != address(0)` at the end of `_deploy` —
    ///         confirms H-D7 Option C invariant (setMinter deferred to Stage K).
    error MinterNotZero(address minter);

    // -------------------------------------------------------------------------
    // State — populated during _deploy() so a fork test can read them back
    // -------------------------------------------------------------------------

    AuMM public aumm;
    TVLOracle public tvlOracle;
    EfficiencyOracle public efficiencyOracle;
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

        address governanceMultisig          = vm.envAddress("GOVERNANCE_MULTISIG");
        IVault vault                        = IVault(vm.envAddress("VAULT"));
        IVaultExplorer vaultExplorer        = IVaultExplorer(vm.envAddress("VAULT_EXPLORER"));
        address bodenseePool                = vm.envAddress("BODENSEE_POOL");
        address svzchf                      = vm.envAddress("SVZCHF");
        IGaugeRegistry gaugeRegistry        = IGaugeRegistry(vm.envAddress("GAUGE_REGISTRY"));
        IEMASampler emaSampler              = IEMASampler(vm.envAddress("EMA_SAMPLER"));
        ICCBMultiplier ccbMultiplier        = ICCBMultiplier(vm.envAddress("CCB_MULTIPLIER"));
        IMiliariumRegistry miliariumRegistry = IMiliariumRegistry(vm.envAddress("MILIARIUM_REGISTRY"));
        uint256 genesisBlock                = vm.envUint("GENESIS_BLOCK");

        // -- 1. AuMM — minterAdmin is GOVERNANCE_MULTISIG per H-D7 Option C --
        // setMinter() is NOT called by this script. aumm.minter() remains
        // address(0) until Stage K governance migration consumes the C-D11
        // one-shot per H-D41.

        aumm = new AuMM(genesisBlock, governanceMultisig);

        // -- 2. TVLOracle — empty tokenToUnderlying seed; governance populates post-deploy --

        address[] memory emptySeed = new address[](0);
        tvlOracle = new TVLOracle(
            vaultExplorer,
            bodenseePool,
            svzchf,
            deployer,
            emptySeed,
            emptySeed
        );

        // -- 3. EfficiencyOracle -----------------------------------------------

        efficiencyOracle = new EfficiencyOracle(
            ITVLOracle(address(tvlOracle)),
            address(aumm),
            genesisBlock,
            deployer
        );

        // -- 4. BodenseeBootstrapChannel ----------------------------------------

        bodenseeBootstrapChannel = new BodenseeBootstrapChannel(
            vault,
            bodenseePool,
            IAuMM(address(aumm)),
            genesisBlock,
            deployer
        );

        // -- 5. EmissionDistributor ---------------------------------------------

        emissionDistributor = new EmissionDistributor(
            IAuMM(address(aumm)),
            gaugeRegistry,
            emaSampler,
            ccbMultiplier,
            IEfficiencyOracle(address(efficiencyOracle)),
            miliariumRegistry,
            genesisBlock,
            deployer
        );

        // -- 6. Post-deploy wiring — EfficiencyOracle → EmissionDistributor ----

        efficiencyOracle.setEmissionsRecorder(address(emissionDistributor));

        // -- 7. Governance handoff to GOVERNANCE_MULTISIG ----------------------

        tvlOracle.setGovernanceContract(governanceMultisig);
        efficiencyOracle.setGovernanceContract(governanceMultisig);
        bodenseeBootstrapChannel.setGovernanceContract(governanceMultisig);
        emissionDistributor.setGovernanceContract(governanceMultisig);

        // -- 8. Invariant assertion — H-D7 Option C: minter must be address(0) --

        if (aumm.minter() != address(0)) revert MinterNotZero(aumm.minter());

        return emissionDistributor;
    }
}
