// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AddLiquidityKind, HookFlags} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {AureumFeeRoutingHook} from "src/fee_router/AureumFeeRoutingHook.sol";
import {GaugeRegistry} from "src/gauge/GaugeRegistry.sol";
import {GaugeEligibility} from "src/gauge/GaugeEligibility.sol";
import {EmissionDistributorHarness} from "test/unit/harness/EmissionDistributorHarness.sol";
import {IEmissionDistributor} from "src/emission/IEmissionDistributor.sol";

import {IAuMM} from "src/token/IAuMM.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";
import {MockFeeController} from "test/mocks/MockFeeController.sol";

import {MockAuMM, MockEMASampler, MockCCBMultiplier, MockMiliariumRegistry} from "test/unit/EmissionDistributor.t.sol";
import {MockEfficiencyOracle} from "test/fork/mocks/StageGMocks.sol";

/// @dev Seats permanently because setEmissionRecorder guards non-zero only and never probes the interface.
contract RevertingRecorder {
    error RecorderAlwaysReverts();

    function recordDeposit(address, address, uint256) external pure {
        revert RecorderAlwaysReverts();
    }
}

/// @dev Matches the IRouterSender surface the hook calls for LP attribution.
contract SenderRouter {
    address private immutable _sender;

    constructor(address sender_) {
        _sender = sender_;
    }

    function getSender() external view returns (address) {
        return _sender;
    }
}

/// @notice Reproduction PoC for seam-1 root cause C.8 (Medium). The row spans fifteen
///         irreversible seatings from the G12 table; this file reproduces the CLASS on its
///         two sharpest instances rather than enumerating all fifteen. The remaining instances
///         named in the row — TVLOracle.setMiliariumRegistry sealing on a codeless target, the
///         authorizer constructor accepting a codeless governance and governance equal to the
///         emergency multisig, the immutable approvedFactory, the conditional moduleAdmin burn,
///         and the untested inert factory owner — are NOT reproduced here.
contract P1_C8_IrreversibleBindingsAreGuardedOnlyAgainstZeroTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant BPT_OUT = 1e18;

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
            GOV
        );

        vm.roll(GENESIS_BLOCK);
    }

    /// @notice A reverting recorder seats permanently; its uncaught dispatch locks add-liquidity.
    function test_P1_C8_aRevertingRecorderSeatsPermanentlyAndItsUncaughtDispatchLocksLiquidity() public {
        // Survey claim verified rather than asserted: exactly ONE code.length guard exists in all
        // of src/, at AureumGovernance.sol L279, and it sits on proposeVaultAuthorizerChange, a
        // proposal path a vote can defeat and therefore the one REVERSIBLE seating; every
        // irreversible one-shot in the tree guards non-zero only.
        // src/gauge/SwapAndDepositToBodensee.sol L294 explicitly declines the check in NatSpec,
        // calling the review duty operational rather than on-chain.
        RevertingRecorder recorder = new RevertingRecorder();
        address other = makeAddr("otherRecorder");

        vm.prank(moduleAdmin);
        hook.setEmissionRecorder(address(recorder));
        assertEq(
            hook.emissionRecorder(),
            address(recorder),
            "reverting recorder seats: the only guard is non-zero, nothing probes the interface"
        );

        vm.expectRevert(AureumFeeRoutingHook.NotEmissionRecorderAdmin.selector);
        vm.prank(moduleAdmin);
        hook.setEmissionRecorder(other);

        SenderRouter router = new SenderRouter(makeAddr("lp"));
        vm.prank(moduleAdmin);
        hook.setGovernanceModule(governance);
        vm.prank(governance);
        hook.setTrustedRouter(address(router), true);

        address pool = makeAddr("pool");
        uint256[] memory empty = new uint256[](0);

        HookFlags memory flags = hook.getHookFlags();
        assertTrue(
            flags.shouldCallAfterAddLiquidity,
            "the Vault genuinely invokes this callback, so the uncaught dispatch sits on the live add-liquidity path rather than a dormant one and a recorder fault therefore reverts the whole liquidity operation"
        );

        vm.expectRevert(RevertingRecorder.RecorderAlwaysReverts.selector);
        vm.prank(vault);
        hook.onAfterAddLiquidity(
            address(router),
            pool,
            AddLiquidityKind.UNBALANCED,
            empty,
            empty,
            BPT_OUT,
            empty,
            bytes("")
        );
    }

    /// @notice AuMT binding accepts a codeless pool and cannot be rebound once set.
    function test_P1_C8_theAuMTBindingTakesAWhollyUnvalidatedPoolAndCannotBeRebound() public {
        address pool = makeAddr("codelessPool");
        address firstBinding = makeAddr("firstAuMT");
        address secondBinding = makeAddr("secondAuMT");

        assertEq(pool.code.length, 0, "pool argument has no code; the absence of validation is stated");

        vm.prank(GOV);
        distributor.setAuMTContractForPool(pool, firstBinding);
        assertEq(
            distributor.auMTContractByPool(pool),
            firstBinding,
            "AuMT binding succeeds for a wholly unvalidated pool"
        );

        vm.expectRevert(abi.encodeWithSelector(IEmissionDistributor.AuMTAlreadyBound.selector, pool));
        vm.prank(GOV);
        distributor.setAuMTContractForPool(pool, secondBinding);
    }
}
