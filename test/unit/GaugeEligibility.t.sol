// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {GaugeEligibility} from "src/gauge/GaugeEligibility.sol";
import {IVaultClassRegistry} from "src/gauge/IVaultClassRegistry.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";
import {ITVLOracle} from "src/ccb/ITVLOracle.sol";
import {IVaultExtension} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import {HooksConfig} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

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

    function quoteSvZCHF(address, uint256) external pure override returns (uint256) {
        return 0;
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

    /// @notice No-op stub for H4.1.x-bis interface conformance; tests pin `efficiencyInputs` directly via `setEfficiencyInputs`.
    function recordEmissions(address, uint256) external override {}
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

    address public gaugeRegistrySetter;

    address public gaugeRegistry;

    address public feeRoutingHook;

    address public admissionAuthority;

    GaugeEligibility public eligibility;

    function setUp() public virtual {
        mockVaultClassRegistry = new MockVaultClassRegistry();
        mockTvlOracle = new MockTVLOracle();
        mockEfficiencyOracle = new MockEfficiencyOracle();
        mockFactory = new MockBasePoolFactory();
        vault = makeAddr("vault");
        auMM = makeAddr("auMM");
        gaugeRegistrySetter = makeAddr("gaugeRegistrySetter");
        gaugeRegistry = makeAddr("gaugeRegistry");
        feeRoutingHook = makeAddr("feeRoutingHook");
        admissionAuthority = makeAddr("admissionAuthority");
        eligibility = new GaugeEligibility(
            address(mockFactory),
            address(mockVaultClassRegistry),
            address(mockTvlOracle),
            vault,
            auMM,
            gaugeRegistrySetter,
            address(mockEfficiencyOracle),
            feeRoutingHook,
            admissionAuthority
        );
        vm.prank(gaugeRegistrySetter);
        eligibility.setGaugeRegistry(gaugeRegistry);
        HooksConfig memory _hc;
        _hc.hooksContract = feeRoutingHook;
        vm.mockCall(vault, abi.encodeWithSelector(IVaultExtension.getHooksConfig.selector), abi.encode(_hc));
    }

    function _deployUnwiredEligibility() internal returns (GaugeEligibility freshEligibility, address freshSetter) {
        freshSetter = makeAddr("freshSetter");
        freshEligibility = new GaugeEligibility(
            address(mockFactory),
            address(mockVaultClassRegistry),
            address(mockTvlOracle),
            vault,
            auMM,
            freshSetter,
            address(mockEfficiencyOracle),
            feeRoutingHook,
            admissionAuthority
        );
    }
}

/// @title GaugeEligibilityWiringTest
/// @notice G2.7a — mocks + fixture + wiring/constructor/setter tests per docs/STAGE_G_PLAN.md L345-L349 + G2.7-decompose umbrella row.
/// @dev Mock signatures (MockVaultClassRegistry / MockTVLOracle / MockEfficiencyOracle / MockBasePoolFactory / MockWeightedPool) lock here per ABI-stability constraint; G2.7b / G2.7c append test contracts only and configure mocks via the setters declared here. Per **G-D25c**, `MockEfficiencyOracle` also mirrors verbatim at `test/fork/mocks/StageGMocks.sol` for Stage G fork integration (`StageGIntegrationFixture`); this in-file embed remains the ABI-stability source-of-truth — any future signature change MUST be propagated to the StageGMocks.sol mirror in the same commit.
contract GaugeEligibilityWiringTest is GaugeEligibilityFixture {
    function testConstructorRevertsOnZeroApprovedFactory() public {
        vm.expectRevert(GaugeEligibility.ZeroAddress.selector);
        new GaugeEligibility(
            address(0),
            address(mockVaultClassRegistry),
            address(mockTvlOracle),
            vault,
            auMM,
            gaugeRegistrySetter,
            address(mockEfficiencyOracle),
            feeRoutingHook,
            admissionAuthority
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
            gaugeRegistrySetter,
            address(mockEfficiencyOracle),
            feeRoutingHook,
            admissionAuthority
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
            gaugeRegistrySetter,
            address(mockEfficiencyOracle),
            feeRoutingHook,
            admissionAuthority
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
            gaugeRegistrySetter,
            address(mockEfficiencyOracle),
            feeRoutingHook,
            admissionAuthority
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
            gaugeRegistrySetter,
            address(mockEfficiencyOracle),
            feeRoutingHook,
            admissionAuthority
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
            address(0),
            address(mockEfficiencyOracle),
            feeRoutingHook,
            admissionAuthority
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
            gaugeRegistrySetter,
            address(0),
            feeRoutingHook,
            admissionAuthority
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
        // PB-D69 conjunct: pool carries a rail so evaluateEligibility reaches its original checkpoint.
        vm.mockCall(
            feeRoutingHook,
            abi.encodeWithSignature("poolBodenseeDepositToken(address)", pool),
            abi.encode(makeAddr("gaugeRail"))
        );
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

    function testHookGateWrongHookReverts() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(_admittedFourSixTwoSix());
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;
        address pool = _wirePool(tokens, weights);
        address wrongHook = makeAddr("wrongHook");
        HooksConfig memory hc;
        hc.hooksContract = wrongHook;
        vm.mockCall(vault, abi.encodeWithSignature("getHooksConfig(address)", pool), abi.encode(hc));
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.WrongFeeRoutingHook.selector, pool, wrongHook));
        eligibility.evaluateEligibility(pool);
    }

    function testHookGateNoHookReverts() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(_admittedFourSixTwoSix());
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;
        address pool = _wirePool(tokens, weights);
        HooksConfig memory hc;
        hc.hooksContract = address(0);
        vm.mockCall(vault, abi.encodeWithSignature("getHooksConfig(address)", pool), abi.encode(hc));
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.WrongFeeRoutingHook.selector, pool, address(0)));
        eligibility.evaluateEligibility(pool);
    }

    function testHookGateCorrectHookPasses() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(_admittedFourSixTwoSix());
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;
        address pool = _wirePool(tokens, weights);
        // base setUp mock returns hooksContract == feeRoutingHook for any pool — the otherwise-eligible pool passes the gate
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

/// @notice T-I5 arbitrary-contract caller test helper for `computeEpochSnapshot` modifier coverage.
contract _SnapshotAttacker {
    GaugeEligibility public eligibility;

    constructor(GaugeEligibility e) {
        eligibility = e;
    }

    function attack(address[] calldata pools) external {
        eligibility.computeEpochSnapshot(pools);
    }
}

/// @notice G2.7c — computeEpochSnapshot matrix per STAGE_G_PLAN.md L357-L361.
contract GaugeEligibilitySnapshotTest is GaugeEligibilityFixture {
    event GaugeEfficiencyRising(
        address indexed pool,
        uint256 indexed epoch,
        uint256 numeratorSma,
        uint256 denominatorSma,
        uint256 efficiencyRatio
    );

    event GaugeEfficiencyDropped(
        address indexed pool,
        uint256 indexed epoch,
        uint256 numeratorSma,
        uint256 denominatorSma,
        uint256 efficiencyRatio
    );

    function _advanceWarmup(address[] memory pools) internal {
        for (uint256 i = 0; i < 3; ++i) {
            vm.prank(gaugeRegistry);
            eligibility.computeEpochSnapshot(pools);
        }
    }

    function testNonGaugeRegistryEOAReverts() public {
        address eoa = makeAddr("eoa");
        vm.prank(eoa);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.OnlyGaugeRegistry.selector, eoa));
        eligibility.computeEpochSnapshot(new address[](0));
    }

    function testNonGaugeRegistrySetterReverts() public {
        vm.prank(gaugeRegistrySetter);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.OnlyGaugeRegistry.selector, gaugeRegistrySetter));
        eligibility.computeEpochSnapshot(new address[](0));
    }

    function testNonGaugeRegistryArbitraryContractReverts() public {
        _SnapshotAttacker attacker = new _SnapshotAttacker(eligibility);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.OnlyGaugeRegistry.selector, address(attacker)));
        attacker.attack(new address[](0));
    }

    function testColdStartGraceFirstSightingDoesNotRevertOrEmit() public {
        address p = makeAddr("p");
        mockEfficiencyOracle.setEfficiencyInputs(p, 100e18, 50e18);
        address[] memory pools = new address[](1);
        pools[0] = p;

        vm.recordLogs();
        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        assertEq(eligibility.firstTournamentEpoch(p), 1);
        assertEq(eligibility.isFavoredCohort(p), false);
        assertEq(eligibility.lastSnapshotEpoch(p), 0);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(eligibility.currentSnapshotEpoch(), 1);
    }

    function testColdStartGraceWithZeroDenominatorDoesNotRevert() public {
        address p = makeAddr("pZeroDenom");
        address[] memory pools = new address[](1);
        pools[0] = p;

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        assertEq(eligibility.firstTournamentEpoch(p), 1);
    }

    function testWarmupWindowSkipsWithoutEventOrRevert() public {
        address p = makeAddr("pWarmSkip");
        address[] memory pools = new address[](1);
        pools[0] = p;

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);
        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);
        vm.recordLogs();
        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(eligibility.currentSnapshotEpoch(), 3);
        assertEq(eligibility.lastSnapshotEpoch(p), 0);
    }

    function testZeroDenominatorSkippedPostWarmup() public {
        address p = makeAddr("pEffUnavailable");
        address[] memory pools = new address[](1);
        pools[0] = p;

        _advanceWarmup(pools);

        // Post-warmup (epoch 4: newEpoch - firstTournamentEpoch == 3, not < SMOOTHING_EPOCHS) with
        // denominatorSma == 0 (mock default): the pool is skipped — excluded from ranking, no cap,
        // no revert — per P-D15 (3). One dead gauge must not brick the permissionless tournament.
        vm.recordLogs();
        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(eligibility.currentSnapshotEpoch(), 4);
        assertEq(eligibility.lastSnapshotEpoch(p), 0);
        assertEq(eligibility.isFavoredCohort(p), false);
        assertEq(eligibility.poolEmissionCapBps(p), 0);
    }

    function testGaugeEfficiencyRisingEmitsOnAscension() public {
        address p = makeAddr("pRisingAscend");
        mockEfficiencyOracle.setEfficiencyInputs(p, 100e18, 50e18);
        address[] memory pools = new address[](1);
        pools[0] = p;

        _advanceWarmup(pools);

        vm.expectEmit(true, true, false, true, address(eligibility));
        emit GaugeEfficiencyRising(p, 4, 100e18, 50e18, 2e18);
        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        assertEq(eligibility.isFavoredCohort(p), true);
        assertEq(eligibility.lastSnapshotEpoch(p), 4);
    }

    function testGaugeEfficiencyDroppedEmitsOnDescent() public {
        address a = address(uint160(0x1111));
        address b = address(uint160(0x2222));
        mockEfficiencyOracle.setEfficiencyInputs(a, 200e18, 50e18);
        mockEfficiencyOracle.setEfficiencyInputs(b, 100e18, 50e18);
        address[] memory pools = new address[](2);
        pools[0] = a;
        pools[1] = b;

        _advanceWarmup(pools);

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        mockEfficiencyOracle.setEfficiencyInputs(a, 100e18, 50e18);
        mockEfficiencyOracle.setEfficiencyInputs(b, 200e18, 50e18);
        vm.expectEmit(true, true, false, true, address(eligibility));
        emit GaugeEfficiencyRising(b, 5, 200e18, 50e18, 4e18);
        vm.expectEmit(true, true, false, true, address(eligibility));
        emit GaugeEfficiencyDropped(a, 5, 100e18, 50e18, 2e18);
        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        assertEq(eligibility.isFavoredCohort(a), false);
        assertEq(eligibility.isFavoredCohort(b), true);
    }

    function testTieBreakAddressAscendingWins() public {
        address low = address(uint160(0x1111));
        address high = address(uint160(0x2222));
        mockEfficiencyOracle.setEfficiencyInputs(low, 100e18, 50e18);
        mockEfficiencyOracle.setEfficiencyInputs(high, 100e18, 50e18);
        address[] memory pools = new address[](2);
        pools[0] = low;
        pools[1] = high;

        _advanceWarmup(pools);

        vm.expectEmit(true, true, false, true, address(eligibility));
        emit GaugeEfficiencyRising(low, 4, 100e18, 50e18, 2e18);
        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        assertEq(eligibility.isFavoredCohort(low), true);
        assertEq(eligibility.isFavoredCohort(high), false);
    }

    function testCeilingCutoffNRanked1() public {
        address poolAddr = address(uint160(0x3333));
        mockEfficiencyOracle.setEfficiencyInputs(poolAddr, 200e18, 50e18);
        address[] memory pools = new address[](1);
        pools[0] = poolAddr;

        _advanceWarmup(pools);

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        assertEq(eligibility.isFavoredCohort(pools[0]), true);
    }

    function testCeilingCutoffNRanked7() public {
        address[] memory pools = new address[](7);
        for (uint256 i = 0; i < 7; ++i) {
            pools[i] = makeAddr(string.concat("pool", vm.toString(i)));
            mockEfficiencyOracle.setEfficiencyInputs(pools[i], (200 - i) * 1e18, 50e18);
        }

        _advanceWarmup(pools);

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        assertEq(eligibility.isFavoredCohort(pools[0]), true);
        assertEq(eligibility.isFavoredCohort(pools[1]), true);
        for (uint256 j = 2; j < 7; ++j) {
            assertEq(eligibility.isFavoredCohort(pools[j]), false);
        }
    }

    function testCeilingCutoffNRanked20() public {
        address[] memory pools = new address[](20);
        for (uint256 i = 0; i < 20; ++i) {
            pools[i] = makeAddr(string.concat("pool", vm.toString(i)));
            mockEfficiencyOracle.setEfficiencyInputs(pools[i], (500 - i) * 1e18, 50e18);
        }

        _advanceWarmup(pools);

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        for (uint256 j = 0; j < 3; ++j) {
            assertEq(eligibility.isFavoredCohort(pools[j]), true);
        }
        for (uint256 k = 3; k < 20; ++k) {
            assertEq(eligibility.isFavoredCohort(pools[k]), false);
        }
    }

    function testCapTierAssignmentNRanked20() public {
        address[] memory pools = new address[](20);
        for (uint256 i = 0; i < 20; ++i) {
            pools[i] = makeAddr(string.concat("captier", vm.toString(i)));
            mockEfficiencyOracle.setEfficiencyInputs(pools[i], (500 - i) * 1e18, 50e18);
        }

        _advanceWarmup(pools);

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        // Descending efficiency (pool0 best, pool19 worst). Floor tiers at nRanked=20:
        // cap10Count = floor(20*5/100) = 1, cap50Count = floor(20*10/100) = 2, cap100Count = floor(20*15/100) = 3.
        assertEq(eligibility.poolEmissionCapBps(pools[19]), 10);  // bottom 5%   -> 0.1%
        assertEq(eligibility.poolEmissionCapBps(pools[18]), 50);  // bottom 10-5% -> 0.5%
        assertEq(eligibility.poolEmissionCapBps(pools[17]), 100); // bottom 15-10% -> 1%
        assertEq(eligibility.poolEmissionCapBps(pools[16]), 0);   // top 85% (first uncapped rank)
        assertEq(eligibility.poolEmissionCapBps(pools[0]), 0);    // most efficient
    }

    function testCapTierNoCapsUnderThreshold() public {
        // nRanked = 6: cap100Count = floor(6*15/100) = 0 -> no pool is capped (P-D15 (1) floor degradation).
        address[] memory pools = new address[](6);
        for (uint256 i = 0; i < 6; ++i) {
            pools[i] = makeAddr(string.concat("nocaptier", vm.toString(i)));
            mockEfficiencyOracle.setEfficiencyInputs(pools[i], (500 - i) * 1e18, 50e18);
        }

        _advanceWarmup(pools);

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        for (uint256 j = 0; j < 6; ++j) {
            assertEq(eligibility.poolEmissionCapBps(pools[j]), 0);
        }
    }

    function testCeilingCutoffNRanked100() public {
        address[] memory pools = new address[](100);
        for (uint256 i = 0; i < 100; ++i) {
            pools[i] = makeAddr(string.concat("pool", vm.toString(i)));
            mockEfficiencyOracle.setEfficiencyInputs(pools[i], (500 - i) * 1e18, 50e18);
        }

        _advanceWarmup(pools);

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        for (uint256 j = 0; j < 15; ++j) {
            assertEq(eligibility.isFavoredCohort(pools[j]), true);
        }
        for (uint256 k = 15; k < 100; ++k) {
            assertEq(eligibility.isFavoredCohort(pools[k]), false);
        }
    }

    function testMonotonicSnapshotEpochIncrementsByOne() public {
        address[] memory empty = new address[](0);

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(empty);
        assertEq(eligibility.snapshotEpoch(), uint256(1));

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(empty);
        assertEq(eligibility.snapshotEpoch(), uint256(2));

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(empty);
        assertEq(eligibility.snapshotEpoch(), uint256(3));

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(empty);
        assertEq(eligibility.snapshotEpoch(), uint256(4));

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(empty);
        assertEq(eligibility.snapshotEpoch(), uint256(5));
    }

    function testLastSnapshotEpochUpdatedForRankedPool() public {
        address p = makeAddr("pLastSnap");
        mockEfficiencyOracle.setEfficiencyInputs(p, 100e18, 50e18);
        address[] memory pools = new address[](1);
        pools[0] = p;

        _advanceWarmup(pools);

        assertEq(eligibility.lastSnapshotEpoch(p), 0);

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        assertEq(eligibility.lastSnapshotEpoch(p), 4);
    }

    function testLastSnapshotEpochNotUpdatedDuringColdStart() public {
        address p = makeAddr("pColdLast");
        mockEfficiencyOracle.setEfficiencyInputs(p, 100e18, 50e18);
        address[] memory pools = new address[](1);
        pools[0] = p;

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        assertEq(eligibility.lastSnapshotEpoch(p), 0);
        assertEq(eligibility.firstTournamentEpoch(p), 1);
    }

    function testLastSnapshotEpochNotUpdatedDuringWarmup() public {
        address p = makeAddr("pWarmLast");
        mockEfficiencyOracle.setEfficiencyInputs(p, 100e18, 50e18);
        address[] memory pools = new address[](1);
        pools[0] = p;

        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);
        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        assertEq(eligibility.lastSnapshotEpoch(p), 0);
    }

    function testNoCohortCrossingEmitsNoEvent() public {
        address p = makeAddr("pNoCross");
        mockEfficiencyOracle.setEfficiencyInputs(p, 100e18, 50e18);
        address[] memory pools = new address[](1);
        pools[0] = p;

        _advanceWarmup(pools);

        vm.expectEmit(true, true, false, true, address(eligibility));
        emit GaugeEfficiencyRising(p, 4, 100e18, 50e18, 2e18);
        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        vm.recordLogs();
        vm.prank(gaugeRegistry);
        eligibility.computeEpochSnapshot(pools);

        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(eligibility.isFavoredCohort(p), true);
        assertEq(eligibility.lastSnapshotEpoch(p), 5);
    }
}

contract GaugeEligibilityCompositionGateTest is GaugeEligibilityFixture {
    function _wireCompositionPool(address[] memory tokensArr, uint256[] memory weightsArr) internal returns (address pool) {
        MockWeightedPool weightedPool = new MockWeightedPool();
        weightedPool.setNormalizedWeights(weightsArr);
        pool = address(weightedPool);
        vm.mockCall(
            vault,
            abi.encodeWithSignature("getPoolTokens(address)", pool),
            abi.encode(tokensArr)
        );
        mockFactory.setPoolFromFactory(pool, true);
        // PB-D69 conjunct: pool carries a rail so meetsCompositionQualityGate reaches its original checkpoint.
        vm.mockCall(
            feeRoutingHook,
            abi.encodeWithSignature("poolBodenseeDepositToken(address)", pool),
            abi.encode(makeAddr("gaugeRail"))
        );
    }

    function _admittedToken() internal returns (MockERC4626Token token) {
        token = new MockERC4626Token(makeAddr("compositionAdmittedAsset"));
        mockVaultClassRegistry.setAdmittedClass(address(token), true);
    }

    function testMeetsCompositionQualityGateAtFiftyTwoPercentPasses() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(_admittedToken());
        tokens[1] = address(new MockERC20Plain());
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.52e18;
        weights[1] = 0.48e18;
        address pool = _wireCompositionPool(tokens, weights);
        assertTrue(eligibility.meetsCompositionQualityGate(pool));
    }

    function testMeetsCompositionQualityGateBelowFiftyTwoPercentReturnsFalse() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(_admittedToken());
        tokens[1] = address(new MockERC20Plain());
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.51e18;
        weights[1] = 0.49e18;
        address pool = _wireCompositionPool(tokens, weights);
        assertFalse(eligibility.meetsCompositionQualityGate(pool));
    }

    function testMeetsCompositionQualityGateForbiddenTokenReverts() public {
        address[] memory tokens = new address[](2);
        tokens[0] = auMM;
        tokens[1] = address(_admittedToken());
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.6e18;
        weights[1] = 0.4e18;
        address pool = _wireCompositionPool(tokens, weights);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.ForbiddenToken.selector, auMM));
        eligibility.meetsCompositionQualityGate(pool);
    }

    function testMeetsCompositionQualityGateWrongHookReverts() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(_admittedToken());
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;
        address pool = _wireCompositionPool(tokens, weights);
        address wrongHook = makeAddr("compositionWrongHook");
        HooksConfig memory hc;
        hc.hooksContract = wrongHook;
        vm.mockCall(vault, abi.encodeWithSignature("getHooksConfig(address)", pool), abi.encode(hc));
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.WrongFeeRoutingHook.selector, pool, wrongHook));
        eligibility.meetsCompositionQualityGate(pool);
    }

    function testMeetsCompositionQualityGateIgnoresTvlFloor() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(_admittedToken());
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;
        address pool = _wireCompositionPool(tokens, weights);
        mockTvlOracle.setTvl(pool, 0);
        // The composition gate runs no TVL floor (O-D2) — a factory-provenanced, ≥52% pool with zero TVL passes:
        assertTrue(eligibility.meetsCompositionQualityGate(pool));
        // Full eligibility rejects the same pool at the TVL floor (factory provenance is set by _wireCompositionPool):
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.TVLFloorNotMet.selector, uint256(0), uint256(10_000e18)));
        eligibility.evaluateEligibility(pool);
    }
}

/// @notice PB3.12d1 — PB-D69 fee-rail conjunct semantics: the disjunction, the latch, and the short-circuit.
/// @dev Slot 7 is `recoveryPathAdmitted` per `forge inspect storage-layout` at PB3.12d1. The short-circuit pair
///      below is self-validating: the admitted case asserts the slot IS read, so a stale slot number cannot let
///      the rail-carrying case pass vacuously.
contract GaugeEligibilityAdmissionGateTest is GaugeEligibilityFixture {
    uint256 internal constant RECOVERY_PATH_ADMITTED_SLOT = 7;

    function _wireAdmissionPool(address rail) internal returns (address pool) {
        MockERC4626Token token = new MockERC4626Token(makeAddr("admissionAsset"));
        mockVaultClassRegistry.setAdmittedClass(address(token), true);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;
        MockWeightedPool weightedPool = new MockWeightedPool();
        weightedPool.setNormalizedWeights(weights);
        pool = address(weightedPool);
        vm.mockCall(vault, abi.encodeWithSignature("getPoolTokens(address)", pool), abi.encode(tokens));
        mockFactory.setPoolFromFactory(pool, true);
        mockTvlOracle.setTvl(pool, 10_000e18);
        vm.mockCall(
            feeRoutingHook,
            abi.encodeWithSignature("poolBodenseeDepositToken(address)", pool),
            abi.encode(rail)
        );
    }

    function _admittedSlotWasRead(address pool) internal returns (bool) {
        bytes32 target = keccak256(abi.encode(pool, RECOVERY_PATH_ADMITTED_SLOT));
        (bytes32[] memory reads,) = vm.accesses(address(eligibility));
        for (uint256 i = 0; i < reads.length; ++i) {
            if (reads[i] == target) return true;
        }
        return false;
    }

    function testRailLessUnadmittedPoolRevertsInEvaluateEligibility() public {
        address pool = _wireAdmissionPool(address(0));
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.NoFeeRailAndNotAdmitted.selector, pool));
        eligibility.evaluateEligibility(pool);
    }

    function testRailLessUnadmittedPoolRevertsInCompositionGate() public {
        address pool = _wireAdmissionPool(address(0));
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.NoFeeRailAndNotAdmitted.selector, pool));
        eligibility.meetsCompositionQualityGate(pool);
    }

    function testRailLessAdmittedPoolPassesBothGates() public {
        address pool = _wireAdmissionPool(address(0));
        vm.prank(admissionAuthority);
        eligibility.setRecoveryPathAdmitted(pool, true);
        assertTrue(eligibility.meetsCompositionQualityGate(pool));
        assertTrue(eligibility.evaluateEligibility(pool));
        assertTrue(eligibility.isEligible(pool));
    }

    function testRailCarryingPoolPassesWithoutReadingAdmissionState() public {
        address pool = _wireAdmissionPool(makeAddr("svZchfRail"));
        assertFalse(eligibility.recoveryPathAdmitted(pool));
        vm.record();
        assertTrue(eligibility.evaluateEligibility(pool));
        assertFalse(_admittedSlotWasRead(pool));
    }

    function testRailLessAdmittedPoolDoesReadAdmissionState() public {
        address pool = _wireAdmissionPool(address(0));
        vm.prank(admissionAuthority);
        eligibility.setRecoveryPathAdmitted(pool, true);
        vm.record();
        assertTrue(eligibility.evaluateEligibility(pool));
        assertTrue(_admittedSlotWasRead(pool));
    }

    function testRevocationBarsLaterEvaluationButLeavesLatchSet() public {
        address pool = _wireAdmissionPool(address(0));
        vm.prank(admissionAuthority);
        eligibility.setRecoveryPathAdmitted(pool, true);
        assertTrue(eligibility.evaluateEligibility(pool));
        assertTrue(eligibility.isEligible(pool));
        vm.prank(admissionAuthority);
        eligibility.setRecoveryPathAdmitted(pool, false);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.NoFeeRailAndNotAdmitted.selector, pool));
        eligibility.evaluateEligibility(pool);
        assertTrue(eligibility.isEligible(pool));
    }
}

/// @notice PB3.12d2 — PB-D69 admission-authority surface: access control on both setters, the two zero-address
///         guards, the idempotent re-emit, and rotation that is deliberately repeatable rather than one-shot.
/// @dev The events asserted below are redeclared locally, matching this file's existing convention at L574 and L582.
contract GaugeEligibilityAdmissionAuthorityTest is GaugeEligibilityFixture {
    event AdmissionAuthorityTransferred(address indexed oldAuthority, address indexed newAuthority);

    event RecoveryPathAdmissionSet(address indexed pool, bool admitted);

    event RecoveryPathRevocationScheduled(address indexed pool, uint256 effectiveBlock);

    event AdmissionAuthorityProposed(address indexed currentAuthority, address indexed pendingAuthority);

    function testSetRecoveryPathAdmittedRevertsForNonAuthority() public {
        address intruder = makeAddr("intruder");
        vm.prank(intruder);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.OnlyAdmissionAuthority.selector, intruder));
        eligibility.setRecoveryPathAdmitted(makeAddr("admissionPool"), true);
    }

    function testSetAdmissionAuthorityRevertsForNonAuthority() public {
        address intruder = makeAddr("intruder");
        vm.prank(intruder);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.OnlyAdmissionAuthority.selector, intruder));
        eligibility.proposeAdmissionAuthority(makeAddr("usurper"));
    }

    function testSetRecoveryPathAdmittedRevertsOnZeroPool() public {
        vm.prank(admissionAuthority);
        vm.expectRevert(GaugeEligibility.ZeroAddress.selector);
        eligibility.setRecoveryPathAdmitted(address(0), true);
    }

    function testSetAdmissionAuthorityRevertsOnZeroAuthority() public {
        vm.prank(admissionAuthority);
        vm.expectRevert(GaugeEligibility.ZeroAddress.selector);
        eligibility.proposeAdmissionAuthority(address(0));
    }

    function testAdmitEmitsImmediatelyWhileRevokeOnlySchedules() public {
        address pool = makeAddr("admissionPool");
        vm.expectEmit(true, false, false, true, address(eligibility));
        emit RecoveryPathAdmissionSet(pool, true);
        vm.prank(admissionAuthority);
        eligibility.setRecoveryPathAdmitted(pool, true);
        assertTrue(eligibility.recoveryPathAdmitted(pool));
        vm.expectEmit(true, false, false, true, address(eligibility));
        emit RecoveryPathRevocationScheduled(pool, block.number + eligibility.REVOCATION_DELAY_BLOCKS());
        vm.prank(admissionAuthority);
        eligibility.setRecoveryPathAdmitted(pool, false);
        assertTrue(eligibility.recoveryPathAdmitted(pool), "the flag survives the scheduling call");
        uint256 effectiveBlock = eligibility.revocationEffectiveBlock(pool);
        vm.roll(effectiveBlock);
        vm.expectEmit(true, false, false, true, address(eligibility));
        emit RecoveryPathAdmissionSet(pool, false);
        vm.prank(makeAddr("strangerFinalizer"));
        eligibility.finalizeRecoveryPathRevocation(pool);
        assertFalse(eligibility.recoveryPathAdmitted(pool));
        assertEq(eligibility.revocationEffectiveBlock(pool), 0, "stamp cleared on finalize");
    }

    function testSetRecoveryPathAdmittedIsIdempotentAndReEmits() public {
        address pool = makeAddr("admissionPool");
        vm.prank(admissionAuthority);
        eligibility.setRecoveryPathAdmitted(pool, true);
        vm.expectEmit(true, false, false, true, address(eligibility));
        emit RecoveryPathAdmissionSet(pool, true);
        vm.prank(admissionAuthority);
        eligibility.setRecoveryPathAdmitted(pool, true);
        assertTrue(eligibility.recoveryPathAdmitted(pool));
    }

    function testAdmissionAuthorityRotationLocksOutOldHolderOnAccept() public {
        address newAuthority = makeAddr("newAdmissionAuthority");
        address pool = makeAddr("admissionPool");
        vm.expectEmit(true, true, false, true, address(eligibility));
        emit AdmissionAuthorityProposed(admissionAuthority, newAuthority);
        vm.prank(admissionAuthority);
        eligibility.proposeAdmissionAuthority(newAuthority);
        assertEq(eligibility.pendingAdmissionAuthority(), newAuthority);
        assertEq(eligibility.admissionAuthority(), admissionAuthority, "a nomination alone does not move the authority");
        vm.prank(admissionAuthority);
        eligibility.setRecoveryPathAdmitted(pool, true);
        assertTrue(eligibility.recoveryPathAdmitted(pool), "the incumbent still governs while a nomination is pending");
        vm.expectEmit(true, true, false, true, address(eligibility));
        emit AdmissionAuthorityTransferred(admissionAuthority, newAuthority);
        vm.prank(newAuthority);
        eligibility.acceptAdmissionAuthority();
        assertEq(eligibility.admissionAuthority(), newAuthority);
        assertEq(eligibility.pendingAdmissionAuthority(), address(0), "pending cleared on accept");
        vm.prank(admissionAuthority);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.OnlyAdmissionAuthority.selector, admissionAuthority));
        eligibility.setRecoveryPathAdmitted(makeAddr("secondPool"), true);
    }

    function testAdmissionAuthorityRotationIsRepeatableNotOneShot() public {
        address second = makeAddr("secondAuthority");
        address third = makeAddr("thirdAuthority");
        vm.prank(admissionAuthority);
        eligibility.proposeAdmissionAuthority(second);
        vm.prank(second);
        eligibility.acceptAdmissionAuthority();
        assertEq(eligibility.admissionAuthority(), second);
        vm.prank(second);
        eligibility.proposeAdmissionAuthority(third);
        vm.prank(third);
        eligibility.acceptAdmissionAuthority();
        assertEq(eligibility.admissionAuthority(), third);
        vm.prank(third);
        eligibility.setRecoveryPathAdmitted(makeAddr("admissionPool"), true);
        assertTrue(eligibility.recoveryPathAdmitted(makeAddr("admissionPool")));
    }
}

