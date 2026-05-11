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

/// @notice Plain ERC-20 double with no asset() — G-D10 empty-catch path for numerator zero.
contract MockERC20Plain {}

/// @notice Minimal ERC-4626 double — asset() only — so GaugeEligibility 4626 probe succeeds.
contract MockERC4626Token {
    address public asset_;

    constructor(address asset__) {
        asset_ = asset__;
    }

    function asset() external view returns (address) {
        return asset_;
    }
}

/// @notice G2.7b — evaluateEligibility matrix (T-I3, T-I4, G-D6, OQ-G2, G-D10, 52% gate, latch, T-I5).
contract GaugeEligibilityEvaluateTest is GaugeEligibilityFixture {
    function _wirePool(address[] memory tokensArr, uint256[] memory weightsArr) internal returns (address pool) {
        MockWeightedPool weightedPool = new MockWeightedPool();
        weightedPool.setNormalizedWeights(weightsArr);
        pool = address(weightedPool);
        vm.mockCall(
            vault,
            abi.encodeWithSignature("getPoolTokens(address)", pool),
            abi.encode(tokensArr)
        );
        mockFactory.setPoolFromFactory(pool, true);
        mockTvlOracle.setTvl(pool, 10_000e18);
    }

    function _admittedFourSixTwoSix() internal returns (MockERC4626Token token) {
        token = new MockERC4626Token(makeAddr("fourSixTwoSixAsset"));
        mockVaultClassRegistry.setAdmittedClass(address(token), true);
    }

    function _nonAdmittedFourSixTwoSix() internal returns (MockERC4626Token token) {
        token = new MockERC4626Token(makeAddr("fourSixTwoSixAssetNA"));
    }

    function testForbiddenTokenAuMMRevertsAtPositionZero() public {
        address[] memory tokens = new address[](2);
        tokens[0] = auMM;
        tokens[1] = address(_admittedFourSixTwoSix());
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.6e18;
        weights[1] = 0.4e18;
        address pool = _wirePool(tokens, weights);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.ForbiddenToken.selector, auMM));
        eligibility.evaluateEligibility(pool);
    }

    function testForbiddenTokenAuMTRevertsAtPositionOne() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(_admittedFourSixTwoSix());
        tokens[1] = auMT;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.6e18;
        weights[1] = 0.4e18;
        address pool = _wirePool(tokens, weights);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.ForbiddenToken.selector, auMT));
        eligibility.evaluateEligibility(pool);
    }

    function testFastTrackSelectorsAbsent() public {
        bytes4[] memory forbidden = new bytes4[](4);
        forbidden[0] = bytes4(keccak256("activateFromSandbox(address)"));
        forbidden[1] = bytes4(keccak256("fastTrackActivation(address)"));
        forbidden[2] = bytes4(keccak256("sandboxFastTrack(address)"));
        forbidden[3] = bytes4(keccak256("activateWithFastTrack(address)"));
        for (uint256 i = 0; i < 4; ++i) {
            (bool ok,) = address(eligibility).call(abi.encodeWithSelector(forbidden[i], makeAddr("anyPool")));
            assertFalse(ok);
        }
    }

    function testPoolTypeNotWhitelistedReverts() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(_admittedFourSixTwoSix());
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;
        address pool = _wirePool(tokens, weights);
        mockFactory.setPoolFromFactory(pool, false);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.PoolTypeNotWhitelisted.selector, address(mockFactory)));
        eligibility.evaluateEligibility(pool);
    }

    function testTVLFloorRevertsBelowFloor() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(_admittedFourSixTwoSix());
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;
        address pool = _wirePool(tokens, weights);
        mockTvlOracle.setTvl(pool, 9_999e18);
        vm.expectRevert(
            abi.encodeWithSelector(GaugeEligibility.TVLFloorNotMet.selector, uint256(9_999e18), uint256(10_000e18))
        );
        eligibility.evaluateEligibility(pool);
    }

    function testTVLFloorPassesAtBorderline() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(_admittedFourSixTwoSix());
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;
        address pool = _wirePool(tokens, weights);
        assertTrue(eligibility.evaluateEligibility(pool));
        assertTrue(eligibility.isEligible(pool));
    }

    function testPlainERC20ContributesZeroNumerator() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(new MockERC20Plain());
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;
        address pool = _wirePool(tokens, weights);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.InsufficientQualityGate.selector, uint256(0)));
        eligibility.evaluateEligibility(pool);
    }

    function testAdmittedFourSixTwoSixContributesWeight() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(_admittedFourSixTwoSix());
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;
        address pool = _wirePool(tokens, weights);
        assertTrue(eligibility.evaluateEligibility(pool));
        assertTrue(eligibility.isEligible(pool));
    }

    function testNonAdmittedFourSixTwoSixContributesZero() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(_nonAdmittedFourSixTwoSix());
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;
        address pool = _wirePool(tokens, weights);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.InsufficientQualityGate.selector, uint256(0)));
        eligibility.evaluateEligibility(pool);
    }

    function testQualityGateAllAdmittedPasses() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(_admittedFourSixTwoSix());
        tokens[1] = address(_admittedFourSixTwoSix());
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.6e18;
        weights[1] = 0.4e18;
        address pool = _wirePool(tokens, weights);
        assertTrue(eligibility.evaluateEligibility(pool));
        assertTrue(eligibility.isEligible(pool));
    }

    function testQualityGateBorderlineFiftyTwoPercentPasses() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(_admittedFourSixTwoSix());
        tokens[1] = address(new MockERC20Plain());
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.52e18;
        weights[1] = 0.48e18;
        address pool = _wirePool(tokens, weights);
        assertTrue(eligibility.evaluateEligibility(pool));
        assertTrue(eligibility.isEligible(pool));
    }

    function testQualityGateBelowFiftyTwoPercentReverts() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(_admittedFourSixTwoSix());
        tokens[1] = address(new MockERC20Plain());
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.51e18;
        weights[1] = 0.49e18;
        address pool = _wirePool(tokens, weights);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.InsufficientQualityGate.selector, uint256(0.51e18)));
        eligibility.evaluateEligibility(pool);
    }

    function testQualityGateAllPlainReverts() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(new MockERC20Plain());
        tokens[1] = address(new MockERC20Plain());
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;
        address pool = _wirePool(tokens, weights);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.InsufficientQualityGate.selector, uint256(0)));
        eligibility.evaluateEligibility(pool);
    }

    function testPositivePathLatchWrites() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(_admittedFourSixTwoSix());
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;
        address pool = _wirePool(tokens, weights);
        uint256 epochBefore = eligibility.currentSnapshotEpoch();
        eligibility.evaluateEligibility(pool);
        assertTrue(eligibility.isGaugeEligible(pool));
        assertEq(eligibility.lastSnapshotEpoch(pool), epochBefore);
        assertTrue(eligibility.isEligible(pool));
    }

    function testEpochSnapshotDeterministicReads() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(_admittedFourSixTwoSix());
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;
        address pool = _wirePool(tokens, weights);
        eligibility.evaluateEligibility(pool);
        bool first = eligibility.isEligible(pool);
        bool second = eligibility.isEligible(pool);
        assertEq(first, second);
        assertTrue(first);
    }
}

