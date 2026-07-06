// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";

import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";

import { AuMM } from "../src/token/AuMM.sol";
import { TVLOracle } from "../src/emission/TVLOracle.sol";
import { ITVLOracle } from "../src/ccb/ITVLOracle.sol";
import { EfficiencyOracle } from "../src/emission/EfficiencyOracle.sol";
import { EMASampler } from "../src/ccb/EMASampler.sol";
import { IEMASampler } from "../src/ccb/IEMASampler.sol";
import { CCBMultiplier } from "../src/ccb/CCBMultiplier.sol";
import { IMiliariumRegistry } from "../src/ccb/IMiliariumRegistry.sol";

/**
 * @title DeployStageF
 * @notice Deploys the Stage F CCB engine as four contracts in dependency order:
 *         TVLOracle then EfficiencyOracle then EMASampler then CCBMultiplier. Carved
 *         out of DeployStageH per P-D28 so EfficiencyOracle exists before the Stage G
 *         stack (GaugeEligibility's constructor takes it as an argument), breaking the
 *         script-granularity cycle where DeployStageH deployed EfficiencyOracle yet
 *         consumed GAUGE_REGISTRY. TVLOracle + EfficiencyOracle move here verbatim from
 *         DeployStageH; EMASampler + CCBMultiplier are net-new production deploys
 *         (previously built only inside fork fixtures).
 *
 * @dev P-D28 — governance handoff: TVLOracle + EfficiencyOracle deploy with governance =
 *      deployer, then hand off to GOVERNANCE_MULTISIG (mirroring the DeployStageH
 *      deployer-then-handoff pattern). EMASampler + CCBMultiplier carry no governance slot.
 *      This script does NOT call efficiencyOracle.setEmissionsRecorder — the distributor is
 *      born in DeployStageH; that cross-script wiring is the P9.5 DeployStageP orchestrator's
 *      job (Option 1, P-D28), executed as the multisig after F and H.
 *
 * @dev P-D27 — VAULT_EXPLORER is the Aureum Vault's own address (the Vault serves the two
 *      getPoolTokens / getPoolData selectors TVLOracle reads; no standalone VaultExplorer).
 *
 * @dev P-D14 — genesisBlock is read from aumm.GENESIS_BLOCK() (the H-D42 single source) and
 *      MUST equal the value later given to GaugeRegistry + EmissionDistributor; the P9.5
 *      orchestrator asserts the four-way GENESIS_BLOCK equality.
 *
 * @dev P-D3 / D-D6 — fork-only scope; no production broadcast within Stage P. run() reads the
 *      six inputs from env and broadcasts; deploy(deployer) is the testable no-broadcast entry
 *      the P9.5 orchestrator and fork fixtures call with deployer = the executing address.
 *
 * @dev Env vars required (no defaults — a real deploy must never silently fall back to zero):
 *
 *        GOVERNANCE_MULTISIG  address  — the governance handoff target for TVLOracle + EfficiencyOracle
 *        AUMM                 address  — deployed AuMM (genesisBlock source; EfficiencyOracle input)
 *        VAULT_EXPLORER       address  — the Aureum Vault address (P-D27; TVLOracle input)
 *        BODENSEE_POOL        address  — der Bodensee pool (TVLOracle input)
 *        SVZCHF               address  — svZCHF (TVLOracle input)
 *        MILIARIUM_REGISTRY   address  — MiliariumRegistry (CCBMultiplier input)
 */
contract DeployStageF is Script {
    TVLOracle public tvlOracle;
    EfficiencyOracle public efficiencyOracle;
    EMASampler public emaSampler;
    CCBMultiplier public ccbMultiplier;

    /// @notice `forge script` entry — deploys the four F-engine contracts as msg.sender under broadcast.
    function run() external returns (TVLOracle, EfficiencyOracle, EMASampler, CCBMultiplier) {
        vm.startBroadcast();
        _deploy(msg.sender);
        vm.stopBroadcast();
        return (tvlOracle, efficiencyOracle, emaSampler, ccbMultiplier);
    }

    /// @notice Testable entry — same sequence without broadcast; deployer is the initial governance
    ///         for TVLOracle + EfficiencyOracle (it must own the CREATE context so the handoff succeeds).
    function deploy(address deployer)
        external
        returns (TVLOracle, EfficiencyOracle, EMASampler, CCBMultiplier)
    {
        _deploy(deployer);
        return (tvlOracle, efficiencyOracle, emaSampler, ccbMultiplier);
    }

    function _deploy(address deployer) internal {
        // -- 0. Read config from env (no defaults on purpose) ----------------
        address governanceMultisig           = vm.envAddress("GOVERNANCE_MULTISIG");
        AuMM aumm                            = AuMM(vm.envAddress("AUMM"));
        IVaultExplorer vaultExplorer         = IVaultExplorer(vm.envAddress("VAULT_EXPLORER"));
        address bodenseePool                 = vm.envAddress("BODENSEE_POOL");
        address svzchf                       = vm.envAddress("SVZCHF");
        IMiliariumRegistry miliariumRegistry = IMiliariumRegistry(vm.envAddress("MILIARIUM_REGISTRY"));
        uint256 genesisBlock                 = aumm.GENESIS_BLOCK();

        // -- 1. TVLOracle — empty tokenToUnderlying seed; governance populates post-deploy --
        address[] memory emptySeed = new address[](0);
        tvlOracle = new TVLOracle(
            vaultExplorer,
            bodenseePool,
            svzchf,
            deployer,
            emptySeed,
            emptySeed
        );

        // -- 2. EfficiencyOracle -----------------------------------------------
        efficiencyOracle = new EfficiencyOracle(
            ITVLOracle(address(tvlOracle)),
            address(aumm),
            genesisBlock,
            deployer
        );

        // -- 3. EMASampler ------------------------------------------------------
        emaSampler = new EMASampler(ITVLOracle(address(tvlOracle)));

        // -- 4. CCBMultiplier ---------------------------------------------------
        ccbMultiplier = new CCBMultiplier(
            miliariumRegistry,
            IEMASampler(address(emaSampler))
        );

        // -- 5. Governance handoff — TVLOracle + EfficiencyOracle to GOVERNANCE_MULTISIG (P-D28).
        //      EMASampler + CCBMultiplier carry no governance slot. setEmissionsRecorder is
        //      deferred to the P9.5 orchestrator (the distributor is born in DeployStageH).
        tvlOracle.setGovernanceContract(governanceMultisig);
        efficiencyOracle.setGovernanceContract(governanceMultisig);

        console2.log("Stage F engine deployed:");
        console2.log("  TVLOracle:       ", address(tvlOracle));
        console2.log("  EfficiencyOracle:", address(efficiencyOracle));
        console2.log("  EMASampler:      ", address(emaSampler));
        console2.log("  CCBMultiplier:   ", address(ccbMultiplier));
    }
}
