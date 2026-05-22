// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";

import { StageGIntegrationFixture } from "./StageGIntegration.t.sol";
import { MockMiliariumRegistry } from "./mocks/CCBMocks.sol";
import { IAuMM } from "../../src/token/IAuMM.sol";
import { EMASampler } from "../../src/ccb/EMASampler.sol";
import { IEMASampler } from "../../src/ccb/IEMASampler.sol";
import { CCBMultiplier } from "../../src/ccb/CCBMultiplier.sol";
import { ICCBMultiplier } from "../../src/ccb/ICCBMultiplier.sol";
import { TVLOracle } from "../../src/emission/TVLOracle.sol";
import { EfficiencyOracle } from "../../src/emission/EfficiencyOracle.sol";
import { BodenseeBootstrapChannel } from "../../src/emission/BodenseeBootstrapChannel.sol";
import { EmissionDistributor } from "../../src/emission/EmissionDistributor.sol";

/**
 * @title StageHIntegrationFixture
 * @notice Stage H cross-stack fork-test base wiring the H1—H6 emission stack against real Bodensee + Stage E pilots per H-D37.
 * @dev Inherits `StageGIntegrationFixture` (vault + factory + AuMM + Bodensee + pilots + GaugeRegistry /
 *      VaultClassRegistry / GaugeEligibility / SwapAndDepositToBodensee) and extends setUp with the Stage H
 *      production stack: TVLOracle + EMASampler + CCBMultiplier + EfficiencyOracle + BodenseeBootstrapChannel +
 *      EmissionDistributor + MockMiliariumRegistry. Post-construction wiring: H-D23
 *      `setEmissionsRecorder(address(emissionDistributor))` on efficiencyOracle + H6.3
 *      `setAuMTContract(address(this))` on emissionDistributor (test contract impersonates the Stage I AuMT
 *      recorder for `recordDeposit` / `recordWithdrawal` calls). `aumm.setMinter(...)` is deferred to each
 *      derived contract's setUp override per H-D37 amended at H9.0c (Option A — avoids Bodensee-pool AuMM
 *      token conflict: `StageHBootstrapPhaseTest` needs `bootstrapChannel` as minter for H-D39 DONATION
 *      callback, other tests need `emissionDistributor` as minter for H-D20 `claim` path; C-D11 one-shot
 *      `_minterAdmin` disallows fixture-level wiring). `incendiaryRegistry` stays `address(0)` per H-D29
 *      zero-stub (slot default — no setter call required; F-7 Step 1 Incendiary skim collapses to 0 per
 *      H5.1c continuous-leg short-circuit).
 *      Anchors: H-D37, H-D7 (OPEN), C-D11, H-D11, H-D20, H-D23, H-D29, H-D31, D35 + D36 + H-D40, E10.
 */
abstract contract StageHIntegrationFixture is StageGIntegrationFixture {
    TVLOracle internal tvlOracle;
    EMASampler internal emaSampler;
    CCBMultiplier internal ccbMultiplier;
    EfficiencyOracle internal efficiencyOracle;
    BodenseeBootstrapChannel internal bootstrapChannel;
    EmissionDistributor internal emissionDistributor;
    MockMiliariumRegistry internal miliariumRegistry;

    function setUp() public virtual override {
        super.setUp();

        address[3] memory miliariumPools;
        miliariumPools[0] = pilotPools[0];
        miliariumPools[1] = pilotPools[1];
        miliariumPools[2] = pilotPools[2];
        miliariumRegistry = new MockMiliariumRegistry(miliariumPools);

        tvlOracle = new TVLOracle(
            IVaultExplorer(address(vault)),
            bodenseePool,
            address(svZchf),
            address(this),
            new address[](0),
            new address[](0)
        );

        emaSampler = new EMASampler(tvlOracle);

        ccbMultiplier = new CCBMultiplier(miliariumRegistry, gaugeRegistry, IEMASampler(address(emaSampler)));

        efficiencyOracle = new EfficiencyOracle(
            tvlOracle,
            address(aumm),
            aumm.GENESIS_BLOCK(),
            address(this)
        );

        bootstrapChannel = new BodenseeBootstrapChannel(
            vault,
            bodenseePool,
            IAuMM(address(aumm)),
            aumm.GENESIS_BLOCK(),
            address(this)
        );

        emissionDistributor = new EmissionDistributor(
            IAuMM(address(aumm)),
            gaugeRegistry,
            IEMASampler(address(emaSampler)),
            ICCBMultiplier(address(ccbMultiplier)),
            efficiencyOracle,
            miliariumRegistry,
            aumm.GENESIS_BLOCK(),
            address(this)
        );

        efficiencyOracle.setEmissionsRecorder(address(emissionDistributor)); // H-D23 — distributor pushes recordEmissions; oracle must whitelist
        emissionDistributor.setAuMTContract(address(this)); // H6.3 — recorder impersonation; test contract drives recordDeposit/recordWithdrawal

        // aumm.setMinter(...) deferred to each derived contract's setUp override per H-D37 amended at H9.0c (Option A — Bodensee-pool AuMM token shared between bootstrapChannel and emissionDistributor minter paths; one-shot C-D11 _minterAdmin disallows fixture-level wiring)
        // incendiaryRegistry stays address(0) per H-D29 zero-stub (slot default — no setter call required; F-7 Step 1 Incendiary skim collapses to 0 per H5.1c continuous-leg short-circuit)
    }
}
