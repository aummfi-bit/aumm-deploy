// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { StageGIntegrationFixture } from "./StageGIntegration.t.sol";
import { MockMiliariumRegistry } from "./mocks/CCBMocks.sol";
import { IAuMM } from "../../src/token/IAuMM.sol";
import { EMASampler } from "../../src/ccb/EMASampler.sol";
import { IEMASampler } from "../../src/ccb/IEMASampler.sol";
import { CCBMultiplier } from "../../src/ccb/CCBMultiplier.sol";
import { ICCBMultiplier } from "../../src/ccb/ICCBMultiplier.sol";
import { AureumTime } from "../../src/lib/AureumTime.sol";
import { TVLOracle } from "../../src/emission/TVLOracle.sol";
import { EfficiencyOracle } from "../../src/emission/EfficiencyOracle.sol";
import { BodenseeBootstrapChannel } from "../../src/emission/BodenseeBootstrapChannel.sol";
import { IBodenseeBootstrapChannel } from "../../src/emission/IBodenseeBootstrapChannel.sol";
import { EmissionDistributor } from "../../src/emission/EmissionDistributor.sol";
import { IEmissionDistributor } from "../../src/emission/IEmissionDistributor.sol";

/**
 * @title StageIIntegrationFixture
 * @notice Stage I recorder-clock fork-test base — wires the I4 effectiveQualBlock clock + AureumFeeRoutingHook liquidity dispatch against real Bodensee + the 3 Stage E pilots.
 * @dev Inherits StageGIntegrationFixture (vault + factory + AuMM + Bodensee + pilots + hook + GaugeRegistry). Deploys its OWN emission stack mirroring StageHIntegrationFixture, but binds the per-pool recorder gate to the canonical AureumFeeRoutingHook (address(hook), NOT the test contract) and sets the hook one-shot emissionRecorder to this distributor, so real Balancer V3 add / remove-liquidity routes onAfterAddLiquidity / onAfterRemoveLiquidity into recordDeposit / recordWithdrawal. Does NOT inherit StageHIntegrationFixture: StageH one-shot-binds the pilots to address(this) (H6.3) and its EfficiencyOracle emissions-recorder handoff is one-shot, so the StageH distributor cannot be re-pointed at the hook — I6.1 deploys a fresh stack instead (user-chosen Option B). No AuMT token deploys (AuMT = BPT per I-D14). aumm.setMinter is NOT required — recordDeposit / recordWithdrawal do not mint (only claim mints, untested here). Anchors: I-D9 (recorder gate), I-D14 (clock), I-D16 (hook emissionRecorder one-shot), H13 (fixture-inheritance precedent).
 */
abstract contract StageIIntegrationFixture is StageGIntegrationFixture {
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
        vm.prank(GOVERNANCE_MULTISIG); // hook moduleAdmin_ per StageG hook ctor — authorises the one-shot setEmissionRecorder
        hook.setEmissionRecorder(address(emissionDistributor)); // I-D16 one-shot — hook dispatches recordDeposit/recordWithdrawal here
        emissionDistributor.setAuMTContractForPool(pilotPools[0], address(hook)); // I-D9 amend — recorder gate admits the hook as msg.sender
        emissionDistributor.setAuMTContractForPool(pilotPools[1], address(hook));
        emissionDistributor.setAuMTContractForPool(pilotPools[2], address(hook));

        // setMinter not wired — I6 recorder-clock tests exercise recordDeposit/recordWithdrawal only (no mint path).
    }
}

contract StageIWiringTest is StageIIntegrationFixture {
    function test_recorderGateAndHookRecorderBound() public {
        assertEq(emissionDistributor.auMTContractByPool(pilotPools[0]), address(hook));
        assertEq(emissionDistributor.auMTContractByPool(pilotPools[1]), address(hook));
        assertEq(emissionDistributor.auMTContractByPool(pilotPools[2]), address(hook));
        assertEq(hook.emissionRecorder(), address(emissionDistributor));
    }
}
