// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {GaugeRegistry} from "src/gauge/GaugeRegistry.sol";
import {GaugeEligibility} from "src/gauge/GaugeEligibility.sol";
import {EmissionDistributorHarness} from "test/unit/harness/EmissionDistributorHarness.sol";

import {IAuMM} from "src/token/IAuMM.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";
import {IEmissionDistributor} from "src/emission/IEmissionDistributor.sol";

import {MockAuMM, MockBpt, MockEMASampler, MockCCBMultiplier, MockMiliariumRegistry} from "test/unit/EmissionDistributor.t.sol";
import {MockEfficiencyOracle} from "test/fork/mocks/StageGMocks.sol";

/// @notice Reproduction PoC for seam-1 root cause E.5 (Medium). The gauge gate at
///         `EmissionDistributor.sol` L473 blocks correction as well as abuse: once a pool is
///         revoked, permissionless `recordScore` reverts `NotApproved`, so its contribution stays
///         welded into `totalScore` and `f5Total`, diluting every survivor. `claim` carries no
///         gauge gate, and `_settlePool` keeps allocating against the frozen score.
contract P1_E5_RevokedPoolScoreWeldedIntoTotalScoreTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant SCORE_BLOCK = GENESIS_BLOCK + 2_628_000 + 1;
    uint256 internal constant ACCRUE_BLOCK = SCORE_BLOCK + 1_000;

    address internal constant GOV = address(0x9011);
    address internal constant PLACEHOLDER = address(0xDEAD);
    address internal constant STRANGER = address(0xBEEF);
    address internal constant AUMT_REVOKED = address(0xAB01);
    address internal constant LP_USER = address(0xCD01);

    MockAuMM internal aumm;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockMiliariumRegistry internal miliReg;
    MockEfficiencyOracle internal effOracle;
    GaugeEligibility internal gaugeElig;
    GaugeRegistry internal gaugeRegistry;
    EmissionDistributorHarness internal distributor;

    address internal revokedPool;
    address internal survivorPool;

    function setUp() public {
        aumm = new MockAuMM();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        miliReg = new MockMiliariumRegistry();
        effOracle = new MockEfficiencyOracle();

        gaugeElig = new GaugeEligibility(
            PLACEHOLDER,
            PLACEHOLDER,
            PLACEHOLDER,
            PLACEHOLDER,
            PLACEHOLDER,
            address(this),
            address(effOracle),
            PLACEHOLDER,
            PLACEHOLDER
        );
        gaugeRegistry = new GaugeRegistry(
            GOV,
            address(gaugeElig),
            PLACEHOLDER,
            PLACEHOLDER,
            GENESIS_BLOCK
        );
        gaugeElig.setGaugeRegistry(address(gaugeRegistry));

        distributor = new EmissionDistributorHarness(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gaugeRegistry)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK,
            GOV
        );

        revokedPool = address(new MockBpt());
        survivorPool = address(new MockBpt());

        address[] memory pools = new address[](2);
        pools[0] = revokedPool;
        pools[1] = survivorPool;
        vm.prank(GOV);
        gaugeRegistry.seedFoundingPools(pools);

        vm.roll(GENESIS_BLOCK);
    }

    function _scoreBothPools() internal {
        ema.setTVLEMA(revokedPool, 200e18);
        ema.setTVLEMA(survivorPool, 100e18);
        mult.setMultiplier(revokedPool, 1e18);
        mult.setMultiplier(survivorPool, 1e18);
        vm.roll(SCORE_BLOCK);
        distributor.recordScore(revokedPool);
        distributor.recordScore(survivorPool);
    }

    function _revokeFirstPool() internal {
        vm.prank(GOV);
        gaugeRegistry.revokeGauge(revokedPool);
    }

    /// @notice After revocation, no caller can drive the revoked pool's score to zero through
    ///         `recordScore`, so `totalScore` and `f5Total` stay frozen with the welded share.
    function test_P1_E5_revokedPoolScoreCannotBeRemovedByAnyCaller() public {
        _scoreBothPools();

        uint256 totalBefore = distributor.totalScore();
        uint256 f5Before = distributor.f5Total();
        assertGt(totalBefore, 0, "precondition: aggregate scores are nonzero");

        _revokeFirstPool();
        assertFalse(gaugeRegistry.isGaugeApproved(revokedPool), "revoked pool is not approved");
        assertTrue(gaugeRegistry.gaugeStatus(revokedPool) == IGaugeRegistry.GaugeStatus.Revoked, "registry reports Revoked");

        vm.prank(STRANGER);
        vm.expectRevert(abi.encodeWithSelector(IEmissionDistributor.NotApproved.selector, revokedPool));
        distributor.recordScore(revokedPool);

        assertEq(distributor.totalScore(), totalBefore, "totalScore unchanged after blocked correction");
        assertEq(distributor.f5Total(), f5Before, "f5Total unchanged after blocked correction");
        assertGt(distributor.poolScore(revokedPool), 0, "revoked pool score remains welded");
    }

    /// @notice The frozen denominator still allocates emissions to the revoked pool via `_settlePool`,
    ///         diluting survivors whose constitution says the pool has lost emissions eligibility.
    function test_P1_E5_revokedPoolKeepsDrawingWhileSurvivorsAreDilutedByTheFrozenDenominator() public {
        _scoreBothPools();

        uint256 survivorScore = distributor.poolScore(survivorPool);
        uint256 total = distributor.totalScore();
        assertGt(distributor.poolScore(revokedPool), 0, "precondition: revoked-side score is nonzero");
        assertGt(total, survivorScore, "precondition: totalScore carries more than the survivor alone");

        _revokeFirstPool();

        vm.prank(GOV);
        distributor.setAuMTContractForPool(revokedPool, AUMT_REVOKED);
        MockBpt(revokedPool).mint(LP_USER, 100e18);
        vm.prank(AUMT_REVOKED);
        distributor.recordDeposit(revokedPool, LP_USER, 100e18);

        uint256 accBefore = distributor.poolAccRewardPerLP(revokedPool);

        vm.roll(ACCRUE_BLOCK);
        vm.prank(AUMT_REVOKED);
        distributor.recordDeposit(revokedPool, LP_USER, 0);

        assertGt(
            distributor.poolAccRewardPerLP(revokedPool),
            accBefore,
            "revoked pool poolAccRewardPerLP rises after accrual and settle"
        );
    }
}
