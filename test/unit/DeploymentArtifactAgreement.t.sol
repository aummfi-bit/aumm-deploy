// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {SepoliaPhase4Addresses} from "script/config/SepoliaPhase4Addresses.sol";

/**
 * @title DeploymentArtifactAgreementTest
 * @notice INTERSECTION guard: the sixteen phase-4 addresses in `deployments/11155111.json`
 *         must agree with `SepoliaPhase4Addresses.sol`.
 *
 * @dev Per PB-D65 (vi) this is an intersection over the phase-4 overlap only. The JSON
 *      additionally carries the base layer, the pools and the stubs, which this test does
 *      NOT check. A green result therefore proves agreement on the overlap rather than
 *      full-set coverage. The Solidity surface is deliberately not widened to mirror the
 *      JSON.
 */
contract DeploymentArtifactAgreementTest is Test {
    using stdJson for string;

    string internal artifact;

    function setUp() public {
        artifact = vm.readFile("deployments/11155111.json");
    }

    /// @dev Build `.phase4.<name>.address` and return the JSON address.
    function _phase4Address(string memory name) internal view returns (address) {
        return artifact.readAddress(string.concat(".phase4.", name, ".address"));
    }

    function test_phase4_intersection_agreesWithSolidityLibrary() public view {
        assertEq(_phase4Address("MiliariumRegistry"), SepoliaPhase4Addresses.MILIARIUM_REGISTRY, "MiliariumRegistry");
        assertEq(_phase4Address("TVLOracle"), SepoliaPhase4Addresses.TVL_ORACLE, "TVLOracle");
        assertEq(_phase4Address("EfficiencyOracle"), SepoliaPhase4Addresses.EFFICIENCY_ORACLE, "EfficiencyOracle");
        assertEq(_phase4Address("EMASampler"), SepoliaPhase4Addresses.EMA_SAMPLER, "EMASampler");
        assertEq(_phase4Address("CCBMultiplier"), SepoliaPhase4Addresses.CCB_MULTIPLIER, "CCBMultiplier");
        assertEq(
            _phase4Address("SwapAndDepositToBodensee"),
            SepoliaPhase4Addresses.SWAP_AND_DEPOSIT_TO_BODENSEE,
            "SwapAndDepositToBodensee"
        );
        assertEq(_phase4Address("VaultClassRegistry"), SepoliaPhase4Addresses.VAULT_CLASS_REGISTRY, "VaultClassRegistry");
        assertEq(_phase4Address("GaugeEligibility"), SepoliaPhase4Addresses.GAUGE_ELIGIBILITY, "GaugeEligibility");
        assertEq(_phase4Address("GaugeRegistry"), SepoliaPhase4Addresses.GAUGE_REGISTRY, "GaugeRegistry");
        assertEq(
            _phase4Address("BodenseeBootstrapChannel"),
            SepoliaPhase4Addresses.BODENSEE_BOOTSTRAP_CHANNEL,
            "BodenseeBootstrapChannel"
        );
        assertEq(
            _phase4Address("EmissionDistributor"), SepoliaPhase4Addresses.EMISSION_DISTRIBUTOR, "EmissionDistributor"
        );
        assertEq(_phase4Address("IncendiaryRegistry"), SepoliaPhase4Addresses.INCENDIARY_REGISTRY, "IncendiaryRegistry");
        assertEq(_phase4Address("VotingWeight"), SepoliaPhase4Addresses.VOTING_WEIGHT, "VotingWeight");
        assertEq(_phase4Address("AureumGovernance"), SepoliaPhase4Addresses.AUREUM_GOVERNANCE, "AureumGovernance");
        assertEq(
            _phase4Address("AureumGovernanceAuthorizer"),
            SepoliaPhase4Addresses.AUREUM_GOVERNANCE_AUTHORIZER,
            "AureumGovernanceAuthorizer"
        );
        assertEq(_phase4Address("AuMMMinterRouter"), SepoliaPhase4Addresses.AUMM_MINTER_ROUTER, "AuMMMinterRouter");
    }

    function test_chainId_matchesSepolia() public view {
        assertEq(artifact.readUint(".chainId"), 11155111);
    }

    function test_deployCount_matchesLibraryConstant() public pure {
        assertEq(SepoliaPhase4Addresses.DEPLOY_COUNT, 16);
    }
}
