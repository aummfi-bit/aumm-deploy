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
import {IEmissionDistributor} from "src/emission/IEmissionDistributor.sol";
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

/// @notice Seam-1 root cause B.6 (High). Both liquidity callbacks resolve the liquidity provider
///         through `IRouterSender(router).getSender()`; the Vault forwards no `to` or `from` to a
///         hook, so attribution stays there per PP-D58 (ii) and (v). The first case is the B.6
///         regression, the recorder crediting or debiting a named holder only for BPT their live
///         balance shows moving; the second, the un-trusting face, stays a reproduction, the seat's
///         lifetime being C.9's concern rather than this row's.
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

    /// @notice B.6 / PP-D58 (v) regression, inverted at PP4.15d from the PoC in which a trusted
    ///         router naming any holder zeroed that holder's matured clock for a one-wei burn: the
    ///         recorder now credits or debits a named holder only for BPT their live balance shows.
    function test_namedHolderIsCreditedOrDebitedOnlyWhenTheirBptMoves() public {
        // Verified negative this row carries and which this file must not contradict: a hostile
        // router CANNOT fabricate weight, because the F-17 read-cap in VotingWeight bounds any
        // position at live BPT and claim syncs down first. The regression therefore closes
        // destruction and denial, never inflation, consistent with the B-family negative results at
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
        assertEq(
            distributor.userLP(address(pool), victim),
            DEPOSIT_AMOUNT,
            "an honest deposit the victim's live BPT shows is credited in full"
        );

        vm.roll(MATURE_BLOCK);
        uint256 maturedClock = distributor.effectiveQualBlock(address(pool), victim);
        assertTrue(maturedClock != 0, "victim clock is nonzero after the on-ramp window");

        // The dust burn the PoC drove: the victim's BPT does not move, so the recorder debits
        // nothing, reports a zero debit, and the matured clock survives.
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IEmissionDistributor.WithdrawalRecorded(address(pool), victim, 0);
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
            maturedClock,
            "a burn the victim's live BPT does not show leaves the matured clock intact"
        );
        assertEq(distributor.userLP(address(pool), victim), DEPOSIT_AMOUNT, "and debits nothing");

        // The deposit face the row does not list: a credit the victim's BPT does not show is
        // refused, where the sync-down it replaced zeroed the named holder's clock.
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IEmissionDistributor.DepositRefused(address(pool), victim, DUST, DEPOSIT_AMOUNT);
        vm.prank(vault);
        hook.onAfterAddLiquidity(
            address(trustedRouter),
            address(pool),
            AddLiquidityKind.UNBALANCED,
            empty,
            empty,
            DUST,
            empty,
            bytes("")
        );
        assertEq(
            distributor.effectiveQualBlock(address(pool), victim),
            maturedClock,
            "a refused credit leaves the matured clock intact"
        );
        assertEq(distributor.userLP(address(pool), victim), DEPOSIT_AMOUNT, "and credits nothing");

        // An honest exit still debits and still resets: the victim's own BPT falls first, standing
        // in for the Vault's burn, so the recorder follows it by exactly the burned amount.
        uint256 burned = DEPOSIT_AMOUNT / 4;
        vm.prank(victim);
        IERC20(address(pool)).transfer(makeAddr("burnSink"), burned);
        vm.prank(vault);
        hook.onAfterRemoveLiquidity(
            address(trustedRouter),
            address(pool),
            RemoveLiquidityKind.PROPORTIONAL,
            burned,
            empty,
            empty,
            empty,
            bytes("")
        );
        assertEq(
            distributor.effectiveQualBlock(address(pool), victim),
            0,
            "a withdrawal the victim's live BPT shows still resets the clock per section viii"
        );
        assertEq(
            distributor.userLP(address(pool), victim),
            DEPOSIT_AMOUNT - burned,
            "and debits exactly the burned amount"
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
