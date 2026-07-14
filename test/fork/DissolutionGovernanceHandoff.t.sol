// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { StagePIntegrationFixture } from "./StagePIntegration.t.sol";
import { DissolutionGovernanceHandoff } from "../../script/DissolutionGovernanceHandoff.s.sol";
import { IEmissionDistributor } from "../../src/emission/IEmissionDistributor.sol";
import { TVLOracle } from "../../src/emission/TVLOracle.sol";
import { EfficiencyOracle } from "../../src/emission/EfficiencyOracle.sol";
import { BodenseeBootstrapChannel } from "../../src/emission/BodenseeBootstrapChannel.sol";
import { SwapAndDepositToBodensee } from "../../src/gauge/SwapAndDepositToBodensee.sol";

/**
 * @title DissolutionGovernanceHandoffWitness
 * @notice PB2.6 dissolution-time rotation witness per PB-D2 / PB-D11 / PB-D12
 * @dev The in-fork multisig identity is address(orchestrator) (DeployStageP.s.sol L81); the rotation target is orchestrator.governance() (the AureumGovernance instance from DeployStageK)
 * @dev The freeze's "no successor path" — AureumGovernance v1 exposes no generic-call hatch to reach these setters (typed execute dispatch, STAGE_K_NOTES K-D9 / PB-D12 ii) — is the documented structural fact; this witness runtime-asserts only the multisig lockout.
 */
contract DissolutionGovernanceHandoffWitness is StagePIntegrationFixture {
    /// @dev Seeds the DissolutionGovernanceHandoff env from typed orchestrator handles and runs rotate as the in-fork multisig.
    function _executeDissolutionRotation() internal returns (address gov) {
        gov = address(orchestrator.governance());
        DissolutionGovernanceHandoff handoff = new DissolutionGovernanceHandoff();
        vm.setEnv("GOVERNANCE_MULTISIG", vm.toString(address(orchestrator)));
        vm.setEnv("AUREUM_GOVERNANCE", vm.toString(gov));
        vm.setEnv("EMISSION_DISTRIBUTOR", vm.toString(address(orchestrator.emissionDistributor())));
        vm.setEnv("BODENSEE_CHANNEL", vm.toString(address(orchestrator.bodenseeBootstrapChannel())));
        vm.setEnv("TVL_ORACLE", vm.toString(address(orchestrator.tvlOracle())));
        vm.setEnv("EFFICIENCY_ORACLE", vm.toString(address(orchestrator.efficiencyOracle())));
        vm.setEnv("SWAP_AND_DEPOSIT", vm.toString(address(orchestrator.swapAndDeposit())));
        handoff.rotate(address(orchestrator));
    }

    /// @notice Precondition face — the in-fork multisig still holds all five authority slots before dissolution.
    function test_preRotation_multisigHoldsAllFive() public view {
        assertEq(orchestrator.emissionDistributor().governance(), address(orchestrator));
        assertEq(orchestrator.bodenseeBootstrapChannel().governance(), address(orchestrator));
        assertEq(orchestrator.tvlOracle().governance(), address(orchestrator));
        assertEq(orchestrator.efficiencyOracle().governance(), address(orchestrator));
        assertEq(orchestrator.swapAndDeposit().donateAuthorizer(), address(orchestrator));
    }

    /// @notice PB-D12(iv) face 1 — after dissolution rotation, all five slots equal AureumGovernance.
    function test_rotation_landsAllFiveSlots() public {
        address gov = _executeDissolutionRotation();
        assertEq(orchestrator.emissionDistributor().governance(), gov);
        assertEq(orchestrator.bodenseeBootstrapChannel().governance(), gov);
        assertEq(orchestrator.tvlOracle().governance(), gov);
        assertEq(orchestrator.efficiencyOracle().governance(), gov);
        assertEq(orchestrator.swapAndDeposit().donateAuthorizer(), gov);
    }

    /// @notice PB-D12(iv) face 2 — the multisig is locked out of the five rotated setters.
    function test_rotation_multisigLockedOutOfRotatedSetters() public {
        _executeDissolutionRotation();

        IEmissionDistributor ed = orchestrator.emissionDistributor();
        BodenseeBootstrapChannel bod = orchestrator.bodenseeBootstrapChannel();
        TVLOracle tvl = orchestrator.tvlOracle();
        EfficiencyOracle eff = orchestrator.efficiencyOracle();
        SwapAndDepositToBodensee swp = orchestrator.swapAndDeposit();

        vm.prank(address(orchestrator));
        vm.expectRevert(
            abi.encodeWithSelector(IEmissionDistributor.NotGovernance.selector, address(orchestrator))
        );
        ed.setGovernanceContract(address(orchestrator));

        vm.prank(address(orchestrator));
        vm.expectRevert(
            abi.encodeWithSelector(BodenseeBootstrapChannel.NotGovernance.selector, address(orchestrator))
        );
        bod.setGovernanceContract(address(orchestrator));

        vm.prank(address(orchestrator));
        vm.expectRevert(abi.encodeWithSelector(TVLOracle.NotGovernance.selector, address(orchestrator)));
        tvl.setGovernanceContract(address(orchestrator));

        vm.prank(address(orchestrator));
        vm.expectRevert(
            abi.encodeWithSelector(EfficiencyOracle.NotGovernance.selector, address(orchestrator))
        );
        eff.setGovernanceContract(address(orchestrator));

        vm.prank(address(orchestrator));
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.OnlyDonateAuthorizer.selector, address(orchestrator))
        );
        swp.setDonateAuthorizer(address(orchestrator));
    }

    /// @notice PB-D12(ii) freeze — the load-bearing operational-wiring family reverts for the multisig.
    function test_freeze_loadBearingFamilyRevertsForMultisig() public {
        _executeDissolutionRotation();

        IEmissionDistributor ed = orchestrator.emissionDistributor();
        TVLOracle tvl = orchestrator.tvlOracle();
        EfficiencyOracle eff = orchestrator.efficiencyOracle();
        SwapAndDepositToBodensee swp = orchestrator.swapAndDeposit();

        vm.prank(address(orchestrator));
        vm.expectRevert(
            abi.encodeWithSelector(IEmissionDistributor.NotGovernance.selector, address(orchestrator))
        );
        ed.setAuMTContractForPool(pilotPools[0], address(0xBEEF));

        vm.prank(address(orchestrator));
        vm.expectRevert(abi.encodeWithSelector(TVLOracle.NotGovernance.selector, address(orchestrator)));
        tvl.setTokenUnderlying(address(0xA11), address(0xB22));

        vm.prank(address(orchestrator));
        vm.expectRevert(abi.encodeWithSelector(TVLOracle.NotGovernance.selector, address(orchestrator)));
        tvl.addConstellationPool(address(0xC33));

        vm.prank(address(orchestrator));
        vm.expectRevert(abi.encodeWithSelector(TVLOracle.NotGovernance.selector, address(orchestrator)));
        tvl.addHopUnderlying(address(0xD44));

        vm.prank(address(orchestrator));
        vm.expectRevert(
            abi.encodeWithSelector(EfficiencyOracle.NotGovernance.selector, address(orchestrator))
        );
        eff.setFeeRecorder(address(0xE55));

        vm.prank(address(orchestrator));
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.OnlyDonateAuthorizer.selector, address(orchestrator))
        );
        swp.addAuthorizedDonator(address(0xF66));

        vm.prank(address(orchestrator));
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.OnlyDonateAuthorizer.selector, address(orchestrator))
        );
        swp.removeAuthorizedDonator(address(0xF77));
    }
}
