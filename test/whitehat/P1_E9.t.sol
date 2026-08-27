// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {GaugeRegistry} from "src/gauge/GaugeRegistry.sol";
import {GaugeEligibility} from "src/gauge/GaugeEligibility.sol";
import {EfficiencyOracle} from "src/emission/EfficiencyOracle.sol";
import {EmissionDistributorHarness} from "test/unit/harness/EmissionDistributorHarness.sol";

import {IAuMM} from "src/token/IAuMM.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";

import {MockAuMM, MockBpt, MockEMASampler, MockCCBMultiplier, MockMiliariumRegistry} from "test/unit/EmissionDistributor.t.sol";
import {MockEfficiencyTVLOracle} from "test/unit/EfficiencyOracle.t.sol";
import {MockRegisteredVault} from "../mocks/MockRegisteredVault.sol";

/// @notice Reproduction PoC for seam-1 root cause E.9 (Medium). `EmissionDistributor.sol` L396
///         pushes `recordEmissions` un-caught inside `_settlePool`, so repointing or clearing the
///         oracle's emissions recorder bricks deposits, withdrawals and scoring protocol-wide. The
///         Router-mediated add and remove faces are the same defect through a different entry and
///         are not reproduced here.
contract P1_E9_EmissionsRecorderIsAProtocolWideKillSwitchTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant SCORE_BLOCK = GENESIS_BLOCK + 2_628_000 + 1;
    uint256 internal constant ACCRUE_BLOCK = SCORE_BLOCK + 1_000;
    uint256 internal constant REPOINT_BLOCK = ACCRUE_BLOCK + 1_000;

    address internal constant GOV = address(0x9011);
    address internal constant PLACEHOLDER = address(0xDEAD);
    address internal constant STRANGER = address(0xBEEF);
    address internal constant AUMT = address(0xAB01);
    address internal constant LP_USER = address(0xCD01);
    address internal constant OTHER_RECORDER = address(0xCAFE);

    MockAuMM internal aumm;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockMiliariumRegistry internal miliReg;
    MockEfficiencyTVLOracle internal tvlMock;
    EfficiencyOracle internal effOracle;
    GaugeEligibility internal gaugeElig;
    GaugeRegistry internal gaugeRegistry;
    EmissionDistributorHarness internal distributor;

    address internal pool;

    function setUp() public {
        aumm = new MockAuMM();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        miliReg = new MockMiliariumRegistry();
        tvlMock = new MockEfficiencyTVLOracle();
        effOracle = new EfficiencyOracle(tvlMock, address(aumm), GENESIS_BLOCK, GOV);

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
            GOV,
            address(new MockRegisteredVault())
        );

        vm.prank(GOV);
        effOracle.setEmissionsRecorder(address(distributor));
        tvlMock.setRate(address(aumm), 1e18);

        pool = address(new MockBpt());

        address[] memory pools = new address[](1);
        pools[0] = pool;
        vm.prank(GOV);
        gaugeRegistry.seedFoundingPools(pools);

        vm.roll(GENESIS_BLOCK);
    }

    function _establishAccruedAllocation() internal {
        ema.setTVLEMA(pool, 100e18);
        mult.setMultiplier(pool, 1e18);
        vm.roll(SCORE_BLOCK);
        distributor.recordScore(pool);

        vm.prank(GOV);
        distributor.setAuMTContractForPool(pool, AUMT);
        MockBpt(pool).mint(LP_USER, 100e18);
        vm.prank(AUMT);
        distributor.recordDeposit(pool, LP_USER, 100e18);

        vm.roll(ACCRUE_BLOCK);
    }

    /// @notice With the distributor bound, settle succeeds; after governance repoints the recorder,
    ///         deposit, withdrawal and scoring all revert through the same uncaught push.
    function test_P1_E9_repointingTheRecorderBricksDepositsWithdrawalsAndScoring() public {
        _establishAccruedAllocation();

        uint256 accBefore = distributor.poolAccRewardPerLP(pool);
        vm.prank(AUMT);
        distributor.recordDeposit(pool, LP_USER, 0);
        assertGt(
            distributor.poolAccRewardPerLP(pool),
            accBefore,
            "positive control: poolAccRewardPerLP rises while recorder is bound"
        );

        vm.prank(GOV);
        effOracle.setEmissionsRecorder(STRANGER);
        vm.roll(REPOINT_BLOCK);

        vm.prank(AUMT);
        vm.expectRevert(abi.encodeWithSelector(EfficiencyOracle.NotEmissionsRecorder.selector, address(distributor)));
        distributor.recordDeposit(pool, LP_USER, 0);

        vm.prank(AUMT);
        vm.expectRevert(abi.encodeWithSelector(EfficiencyOracle.NotEmissionsRecorder.selector, address(distributor)));
        distributor.recordWithdrawal(pool, LP_USER, 0);

        vm.expectRevert(abi.encodeWithSelector(EfficiencyOracle.NotEmissionsRecorder.selector, address(distributor)));
        distributor.recordScore(pool);
    }

    /// @notice The emissions recorder setter is multi-shot, accepts zero with no validation, and
    ///         leaving the slot cleared is as fatal as repointing it away from the distributor.
    function test_P1_E9_theRecorderSetterIsMultiShotAndAcceptsZeroWithNoValidation() public {
        _establishAccruedAllocation();

        vm.prank(GOV);
        effOracle.setEmissionsRecorder(address(0));
        assertEq(effOracle.emissionsRecorder(), address(0));

        vm.prank(GOV);
        effOracle.setEmissionsRecorder(OTHER_RECORDER);
        assertEq(effOracle.emissionsRecorder(), OTHER_RECORDER);

        vm.prank(GOV);
        effOracle.setEmissionsRecorder(address(0));
        assertEq(effOracle.emissionsRecorder(), address(0));

        vm.roll(REPOINT_BLOCK);

        vm.prank(AUMT);
        vm.expectRevert(abi.encodeWithSelector(EfficiencyOracle.NotEmissionsRecorder.selector, address(distributor)));
        distributor.recordDeposit(pool, LP_USER, 0);
    }
}
