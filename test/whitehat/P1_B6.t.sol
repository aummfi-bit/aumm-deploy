// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    AddLiquidityKind,
    RemoveLiquidityKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {AureumFeeRoutingHook} from "src/fee_router/AureumFeeRoutingHook.sol";
import {GaugeRegistry} from "src/gauge/GaugeRegistry.sol";
import {GaugeEligibility} from "src/gauge/GaugeEligibility.sol";
import {EmissionDistributorHarness} from "test/unit/harness/EmissionDistributorHarness.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

import {IAuMM} from "src/token/IAuMM.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";
import {MockFeeController} from "test/mocks/MockFeeController.sol";

import {
    MockAuMM,
    MockBpt,
    MockEMASampler,
    MockCCBMultiplier,
    MockMiliariumRegistry
} from "test/unit/EmissionDistributor.t.sol";
import {MockEfficiencyOracle} from "test/fork/mocks/StageGMocks.sol";
import {MockRegisteredVault} from "../mocks/MockRegisteredVault.sol";

/// @dev Matches the IRouterSender surface the hook calls; sender is settable so one
///      instance can name different holders across a test.
contract SenderRouter {
    address private _sender;

    constructor(address sender_) {
        _sender = sender_;
    }

    function setSender(address sender_) external {
        _sender = sender_;
    }

    function getSender() external view returns (address) {
        return _sender;
    }
}

/// @notice Reproduction PoC for seam-1 root cause B.6 (High). Both liquidity callbacks
///         resolve the liquidity provider through `IRouterSender(router).getSender()` rather
///         than through the Vault's own `AddLiquidityParams.to` or `RemoveLiquidityParams.from`.
///         The seat's lifetime is C.9's concern rather than this row's.
contract P1_B6_TrustedRouterNamesAnyHolderThroughGetSenderTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant DEPOSIT_BLOCK = GENESIS_BLOCK;
    uint256 internal constant MATURE_BLOCK = DEPOSIT_BLOCK + AureumTime.ON_RAMP_PERIOD_BLOCKS;
    uint256 internal constant DEPOSIT_AMOUNT = 100e18;
    uint256 internal constant DUST = 1;

    address internal constant GOV = address(0x9011);
    address internal constant PLACEHOLDER = address(0xDEAD);

    AureumFeeRoutingHook internal hook;
    address internal vault;
    address internal bodensee;
    address internal moduleAdmin;
    address internal governance;

    MockERC20 internal zchf;
    MockERC4626 internal svZchf;
    MockERC20 internal aummToken;
    MockERC20 internal susds;
    MockFeeController internal feeController;

    MockAuMM internal aumm;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockMiliariumRegistry internal miliReg;
    MockEfficiencyOracle internal effOracle;
    GaugeEligibility internal gaugeElig;
    GaugeRegistry internal gaugeRegistry;
    EmissionDistributorHarness internal distributor;

    MockBpt internal pool;
    SenderRouter internal trustedRouter;

    function setUp() public {
        vault = makeAddr("vault");
        bodensee = makeAddr("bodensee");
        moduleAdmin = makeAddr("moduleAdmin");
        governance = makeAddr("governance");

        zchf = new MockERC20("Frankencoin", "ZCHF", 18);
        svZchf = new MockERC4626(IERC20(address(zchf)), "Savings Frankencoin", "svZCHF");
        aummToken = new MockERC20("Aureum", "AuMM", 18);
        susds = new MockERC20("Savings USDS", "sUSDS", 18);
        feeController = new MockFeeController();

        hook = new AureumFeeRoutingHook(
            vault,
            bodensee,
            IERC20(address(svZchf)),
            IERC20(address(susds)),
            IERC20(address(aummToken)),
            address(feeController),
            moduleAdmin
        );

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
            GOV,
            address(new MockRegisteredVault())
        );

        pool = new MockBpt();

        // Production wiring: hook is emissionRecorder; pool AuMT binding points at the hook
        // (script/DeployStageN.s.sol L20), admitting the hook through onlyAuMTContract.
        vm.prank(moduleAdmin);
        hook.setEmissionRecorder(address(distributor));
        vm.prank(moduleAdmin);
        hook.setGovernanceModule(governance);
        vm.prank(GOV);
        distributor.setAuMTContractForPool(address(pool), address(hook));

        trustedRouter = new SenderRouter(address(0));
        vm.prank(governance);
        hook.setTrustedRouter(address(trustedRouter), true);

        vm.roll(GENESIS_BLOCK);
    }

    /// @notice A trusted router naming any holder zeroes that holder's matured clock for one wei.
    function test_P1_B6_aTrustedRouterZeroesAnyHoldersMaturedClockForADustBurn() public {
        // Verified negative this row carries and which this file must not contradict: a hostile
        // router CANNOT fabricate weight, because the F-17 read-cap in VotingWeight bounds any
        // position at live BPT and claim syncs down first. This file therefore claims destruction
        // and denial only, never inflation, consistent with the B-family negative results at
        // docs/STAGE_P_PRIME_PLAN.md L77.
        address victim = makeAddr("victim");
        trustedRouter.setSender(victim);

        pool.mint(victim, DEPOSIT_AMOUNT);
        uint256[] memory empty = new uint256[](0);

        vm.roll(DEPOSIT_BLOCK);
        vm.prank(vault);
        hook.onAfterAddLiquidity(
            address(trustedRouter),
            address(pool),
            AddLiquidityKind.UNBALANCED,
            empty,
            empty,
            DEPOSIT_AMOUNT,
            empty,
            bytes("")
        );

        vm.roll(MATURE_BLOCK);
        assertTrue(
            distributor.effectiveQualBlock(address(pool), victim) != 0,
            "victim clock is nonzero after the on-ramp window"
        );
        assertEq(
            distributor.userLP(address(pool), victim),
            DEPOSIT_AMOUNT,
            "victim recorded userLP is the full deposit"
        );

        uint256 bptBefore = pool.balanceOf(victim);
        vm.prank(vault);
        hook.onAfterRemoveLiquidity(
            address(trustedRouter),
            address(pool),
            RemoveLiquidityKind.PROPORTIONAL,
            DUST,
            empty,
            empty,
            empty,
            bytes("")
        );

        assertEq(
            distributor.effectiveQualBlock(address(pool), victim),
            0,
            "dust burn through a router the seat trusts destroys a matured clock the victim spent an on-ramp period earning"
        );
        assertEq(
            distributor.userLP(address(pool), victim),
            DEPOSIT_AMOUNT - DUST,
            "recorded userLP fell by only one wei; the attacker supplied no capital of their own"
        );
        assertEq(
            pool.balanceOf(victim),
            bptBefore,
            "live BPT balance is essentially untouched; the attacker supplied no capital of their own"
        );
    }

    /// @notice An un-trusted router never credits the named holder; new qualification freezes.
    function test_P1_B6_unTrustingARouterFreezesNewQualificationEntirely() public {
        address holder = makeAddr("freshHolder");
        SenderRouter untrusted = new SenderRouter(holder);

        pool.mint(holder, DEPOSIT_AMOUNT);
        uint256[] memory empty = new uint256[](0);

        vm.roll(DEPOSIT_BLOCK);
        vm.prank(vault);
        hook.onAfterAddLiquidity(
            address(untrusted),
            address(pool),
            AddLiquidityKind.UNBALANCED,
            empty,
            empty,
            DEPOSIT_AMOUNT,
            empty,
            bytes("")
        );

        assertEq(
            distributor.userLP(address(pool), holder),
            0,
            "untrusted router freezes new qualification; the distributor recorded nothing (same seat, other side)"
        );
        assertEq(
            distributor.effectiveQualBlock(address(pool), holder),
            0,
            "untrusted router freezes new qualification; one fix closes both faces of the row"
        );
    }
}
