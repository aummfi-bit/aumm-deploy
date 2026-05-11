// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {GaugeEligibility} from "src/gauge/GaugeEligibility.sol";
import {IVaultClassRegistry} from "src/gauge/IVaultClassRegistry.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";
import {ITVLOracle} from "src/ccb/ITVLOracle.sol";

/// @notice Test double exposing configurable class admission bits for GaugeEligibility.
contract MockVaultClassRegistry is IVaultClassRegistry {
    mapping(address => bool) public admittedClasses;

    mapping(address => IVaultClassRegistry.AdmissionType) public admissionTypes;

    /// @notice Sets admitted status for `token` in isolation tests.
    function setAdmittedClass(address token, bool admitted) external {
        admittedClasses[token] = admitted;
    }

    /// @notice Returns whether `token` is marked admitted on this mock.
    function isAdmittedClass(address token) external view override returns (bool) {
        return admittedClasses[token];
    }

    /// @notice Returns fingerprint kind stored for `token`, else zero slot (ImplementationAddress).
    function admissionType(address token) external view override returns (IVaultClassRegistry.AdmissionType) {
        return admissionTypes[token];
    }
}

/// @notice Minimal ITVLOracle double with per-pool TVL slot writes.
contract MockTVLOracle is ITVLOracle {
    mapping(address => uint256) public tvlOf;

    /// @notice Pins TVL for `pool` in isolation tests.
    function setTvl(address pool, uint256 value) external {
        tvlOf[pool] = value;
    }

    /// @notice Returns pinned TVL for `pool`.
    function tvl(address pool) external view override returns (uint256) {
        return tvlOf[pool];
    }
}

/// @notice Minimal IEfficiencyOracle double storing SMA pair per pool.
contract MockEfficiencyOracle is IEfficiencyOracle {
    mapping(address => uint256) public numeratorSmaOf;

    mapping(address => uint256) public denominatorSmaOf;

    /// @notice Pins numerator and denominator SMA for `pool` in isolation tests.
    function setEfficiencyInputs(address pool, uint256 numeratorSma_, uint256 denominatorSma_) external {
        numeratorSmaOf[pool] = numeratorSma_;
        denominatorSmaOf[pool] = denominatorSma_;
    }

    /// @notice Returns pinned SMA inputs for `pool`.
    function efficiencyInputs(address pool) external view override returns (uint256, uint256) {
        return (numeratorSmaOf[pool], denominatorSmaOf[pool]);
    }
}

/// @notice Factory-shaped double exposing only `isPoolFromFactory` for selector dispatch tests.
contract MockBasePoolFactory {
    mapping(address => bool) public isFromFactory;

    /// @notice Sets whether Balancer associates `pool` with this factory.
    function setPoolFromFactory(address pool, bool fromFactory) external {
        isFromFactory[pool] = fromFactory;
    }

    /// @notice Returns factory membership flag stored for `pool`.
    function isPoolFromFactory(address pool) external view returns (bool) {
        return isFromFactory[pool];
    }
}

/// @notice Weighted-pool-shaped double exposing only normalized weights reads.
contract MockWeightedPool {
    uint256[] public weights;

    /// @notice Rewrites normalized weight vector used by GaugeEligibility reads.
    function setNormalizedWeights(uint256[] memory weights_) external {
        delete weights;
        for (uint256 i = 0; i < weights_.length; ++i) {
            weights.push(weights_[i]);
        }
    }

    /// @notice Returns the configured normalized weights array.
    function getNormalizedWeights() external view returns (uint256[] memory) {
        return weights;
    }
}

abstract contract GaugeEligibilityFixture is Test {
    MockVaultClassRegistry public mockVaultClassRegistry;

    MockTVLOracle public mockTvlOracle;

    MockEfficiencyOracle public mockEfficiencyOracle;

    MockBasePoolFactory public mockFactory;

    address public vault;

    address public auMM;

    address public auMT;

    address public gaugeRegistrySetter;

    address public gaugeRegistry;

    GaugeEligibility public eligibility;

    function setUp() public virtual {
        mockVaultClassRegistry = new MockVaultClassRegistry();
        mockTvlOracle = new MockTVLOracle();
        mockEfficiencyOracle = new MockEfficiencyOracle();
        mockFactory = new MockBasePoolFactory();
        vault = makeAddr("vault");
        auMM = makeAddr("auMM");
        auMT = makeAddr("auMT");
        gaugeRegistrySetter = makeAddr("gaugeRegistrySetter");
        gaugeRegistry = makeAddr("gaugeRegistry");
        eligibility = new GaugeEligibility(
            address(mockFactory),
            address(mockVaultClassRegistry),
            address(mockTvlOracle),
            vault,
            auMM,
            auMT,
            gaugeRegistrySetter,
            address(mockEfficiencyOracle)
        );
        vm.prank(gaugeRegistrySetter);
        eligibility.setGaugeRegistry(gaugeRegistry);
    }

    function _deployUnwiredEligibility() internal returns (GaugeEligibility freshEligibility, address freshSetter) {
        freshSetter = makeAddr("freshSetter");
        freshEligibility = new GaugeEligibility(
            address(mockFactory),
            address(mockVaultClassRegistry),
            address(mockTvlOracle),
            vault,
            auMM,
            auMT,
            freshSetter,
            address(mockEfficiencyOracle)
        );
    }
}

/// @title GaugeEligibilityWiringTest
/// @notice G2.7a — mocks + fixture + wiring/constructor/setter tests per docs/STAGE_G_PLAN.md L345-L349 + G2.7-decompose umbrella row.
/// @dev Mock signatures (MockVaultClassRegistry / MockTVLOracle / MockEfficiencyOracle / MockBasePoolFactory / MockWeightedPool) lock here per ABI-stability constraint; G2.7b / G2.7c append test contracts only and configure mocks via the setters declared here.
contract GaugeEligibilityWiringTest is GaugeEligibilityFixture {
    function testConstructorRevertsOnZeroApprovedFactory() public {
        vm.expectRevert(GaugeEligibility.ZeroAddress.selector);
        new GaugeEligibility(
            address(0),
            address(mockVaultClassRegistry),
            address(mockTvlOracle),
            vault,
            auMM,
            auMT,
            gaugeRegistrySetter,
            address(mockEfficiencyOracle)
        );
    }

    function testConstructorRevertsOnZeroVaultClassRegistry() public {
        vm.expectRevert(GaugeEligibility.ZeroAddress.selector);
        new GaugeEligibility(
            address(mockFactory),
            address(0),
            address(mockTvlOracle),
            vault,
            auMM,
            auMT,
            gaugeRegistrySetter,
            address(mockEfficiencyOracle)
        );
    }

    function testConstructorRevertsOnZeroTvlOracle() public {
        vm.expectRevert(GaugeEligibility.ZeroAddress.selector);
        new GaugeEligibility(
            address(mockFactory),
            address(mockVaultClassRegistry),
            address(0),
            vault,
            auMM,
            auMT,
            gaugeRegistrySetter,
            address(mockEfficiencyOracle)
        );
    }

    function testConstructorRevertsOnZeroVault() public {
        vm.expectRevert(GaugeEligibility.ZeroAddress.selector);
        new GaugeEligibility(
            address(mockFactory),
            address(mockVaultClassRegistry),
            address(mockTvlOracle),
            address(0),
            auMM,
            auMT,
            gaugeRegistrySetter,
            address(mockEfficiencyOracle)
        );
    }

    function testConstructorRevertsOnZeroAuMM() public {
        vm.expectRevert(GaugeEligibility.ZeroAddress.selector);
        new GaugeEligibility(
            address(mockFactory),
            address(mockVaultClassRegistry),
            address(mockTvlOracle),
            vault,
            address(0),
            auMT,
            gaugeRegistrySetter,
            address(mockEfficiencyOracle)
        );
    }

    function testConstructorRevertsOnZeroAuMT() public {
        vm.expectRevert(GaugeEligibility.ZeroAddress.selector);
        new GaugeEligibility(
            address(mockFactory),
            address(mockVaultClassRegistry),
            address(mockTvlOracle),
            vault,
            auMM,
            address(0),
            gaugeRegistrySetter,
            address(mockEfficiencyOracle)
        );
    }

    function testConstructorRevertsOnZeroGaugeRegistrySetter() public {
        vm.expectRevert(GaugeEligibility.ZeroAddress.selector);
        new GaugeEligibility(
            address(mockFactory),
            address(mockVaultClassRegistry),
            address(mockTvlOracle),
            vault,
            auMM,
            auMT,
            address(0),
            address(mockEfficiencyOracle)
        );
    }

    function testConstructorRevertsOnZeroEfficiencyOracle() public {
        vm.expectRevert(GaugeEligibility.ZeroAddress.selector);
        new GaugeEligibility(
            address(mockFactory),
            address(mockVaultClassRegistry),
            address(mockTvlOracle),
            vault,
            auMM,
            auMT,
            gaugeRegistrySetter,
            address(0)
        );
    }

    function testSetGaugeRegistryHappyPath() public {
        assertEq(eligibility.gaugeRegistry(), gaugeRegistry);
        assertEq(eligibility.gaugeRegistrySetter(), address(0));
    }

    function testSetGaugeRegistryNonSetterReverts() public {
        (GaugeEligibility fresh,) = _deployUnwiredEligibility();
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(GaugeEligibility.OnlyGaugeRegistrySetter.selector);
        fresh.setGaugeRegistry(gaugeRegistry);
    }

    function testSetGaugeRegistryZeroAddressReverts() public {
        (GaugeEligibility fresh, address freshSetter) = _deployUnwiredEligibility();
        vm.prank(freshSetter);
        vm.expectRevert(GaugeEligibility.ZeroAddress.selector);
        fresh.setGaugeRegistry(address(0));
    }

    function testSetGaugeRegistryPostSealReverts() public {
        vm.prank(gaugeRegistrySetter);
        vm.expectRevert(GaugeEligibility.OnlyGaugeRegistrySetter.selector);
        eligibility.setGaugeRegistry(makeAddr("anotherRegistry"));
    }
}
