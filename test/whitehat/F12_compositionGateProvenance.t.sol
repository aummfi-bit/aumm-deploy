// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HooksConfig} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {GaugeEligibility} from "src/gauge/GaugeEligibility.sol";

/// @notice F-12 attacker pool — a hand-rolled contract reports a faked 100%-admitted weight (any contract can
///         return whatever `getNormalizedWeights` it likes). It is NOT from the Aureum weighted-pool factory.
contract F12_SpoofWeightedPool {
    function getNormalizedWeights() external pure returns (uint256[] memory weights) {
        weights = new uint256[](1);
        weights[0] = 1e18;
    }
}

/// @notice F-12 admitted-class ERC-4626 token double — `asset()` resolves so `_compute52PctNumerator` treats it
///         as a yield-bearing class; the VaultClassRegistry is mocked to admit it.
contract F12_AdmittedYieldToken {
    function asset() external view returns (address) {
        return address(this);
    }
}

/// @notice F-12 fix regression (WO whitehat pass) — the composition Quality Gate enforces Aureum-factory
///         provenance, so a hand-rolled non-factory pool carrying the canonical fee-routing hook (the hook's
///         `onRegister` is permissive — it accepts any non-Bodensee pool) cannot spoof the ≥52% bar with a
///         faked `getNormalizedWeights`. The faked weights still clear the numerator logic; provenance is the
///         backstop that blocks the spoof.
contract F12_CompositionGateFactoryProvenanceTest is Test {
    GaugeEligibility internal eligibility;
    address internal factory = makeAddr("approvedFactory");
    address internal vcr = makeAddr("vaultClassRegistry");
    address internal vault = makeAddr("vault");
    address internal feeRoutingHook = makeAddr("feeRoutingHook");
    address internal spoof;

    function setUp() public {
        eligibility = new GaugeEligibility(
            factory,
            vcr,
            makeAddr("tvlOracle"),
            vault,
            makeAddr("auMM"),
            makeAddr("gaugeRegistrySetter"),
            makeAddr("efficiencyOracle"),
            feeRoutingHook
        );

        spoof = address(new F12_SpoofWeightedPool());
        address yieldToken = address(new F12_AdmittedYieldToken());

        // Canonical hook attached (models the permissive onRegister); 100%-admitted faked composition.
        HooksConfig memory hc;
        hc.hooksContract = feeRoutingHook;
        vm.mockCall(vault, abi.encodeWithSignature("getHooksConfig(address)", spoof), abi.encode(hc));
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(yieldToken);
        vm.mockCall(vault, abi.encodeWithSignature("getPoolTokens(address)", spoof), abi.encode(tokens));
        vm.mockCall(vcr, abi.encodeWithSignature("isAdmittedClass(address)", yieldToken), abi.encode(true));
    }

    function test_F12_fakedWeightsClearBar_butProvenanceGateBlocksNonFactorySpoof() public {
        // (a) The faked weights clear the 52% numerator logic — were the pool factory-provenanced, it would pass.
        vm.mockCall(factory, abi.encodeWithSignature("isPoolFromFactory(address)", spoof), abi.encode(true));
        assertTrue(eligibility.meetsCompositionQualityGate(spoof), "faked 100%-admitted weights clear the bar");

        // (b) The real attack — a hand-rolled, non-factory pool — is rejected by the F-12 provenance check.
        vm.mockCall(factory, abi.encodeWithSignature("isPoolFromFactory(address)", spoof), abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.PoolTypeNotWhitelisted.selector, factory));
        eligibility.meetsCompositionQualityGate(spoof);
    }
}
