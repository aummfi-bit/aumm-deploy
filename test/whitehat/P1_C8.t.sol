// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AddLiquidityKind, HookFlags, RemoveLiquidityKind} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

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
import {MockRegisteredVault} from "../mocks/MockRegisteredVault.sol";

/// @dev Seats permanently because setEmissionRecorder guards non-zero only and never probes the interface;
///      after PP4.15c2 its reverts reach the hook's dispatch and degrade rather than lock.
contract RevertingRecorder {
    error RecorderAlwaysReverts();

    function recordDeposit(address, address, uint256) external pure {
        revert RecorderAlwaysReverts();
    }

    function recordWithdrawal(address, address, uint256) external pure {
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

/// @dev A trusted router whose getSender reverts, so the hook can name no holder.
contract RevertingSenderRouter {
    function getSender() external pure returns (address) {
        revert("no sender");
    }
}

/// @dev A trusted router that answers getSender with arbitrary raw bytes through its fallback,
///      for the return shapes a typed call would fail to decode in the caller.
contract RawReturnRouter {
    bytes private _ret;

    constructor(bytes memory ret_) {
        _ret = ret_;
    }

    fallback() external {
        bytes memory r = _ret;
        assembly {
            return(add(r, 32), mload(r))
        }
    }
}

/// @notice Seam-1 root cause C.8 (Medium). The row spans fifteen irreversible seatings from the
///         G12 table; this file holds the CLASS on its two sharpest instances rather than
///         enumerating all fifteen. The first, the hook's uncaught recorder dispatch, is FIXED at
///         PP4.15c2 per PP-D58 (vi) and its case is the regression below; the second, the AuMT
///         binding, stays a reproduction for rung 16's binding hygiene. The remaining instances
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
            GOV,
            address(new MockRegisteredVault())
        );

        vm.roll(GENESIS_BLOCK);
    }

    /// @notice C.8 / PP-D58 (vi) regression, inverted at PP4.15c3 from the PoC that pinned a
    ///         reverting recorder's uncaught dispatch locking add-liquidity: every recorder or
    ///         router fault on the dispatch path now emits `RecorderDispatchFailed` and the
    ///         liquidity operation completes, on the add callback and the remove callback alike.
    function test_recorderFaultDegradesNotLocks() public {
        // The seating half of the class still stands and is rung 16's: the recorder seat below
        // guards non-zero only and probes nothing, like the other irreversible one-shot seatings
        // the row names, and `src/gauge/SwapAndDepositToBodensee.sol:297` declines the
        // `code.length` check in NatSpec, calling the review duty operational rather than on-chain.
        RevertingRecorder recorder = new RevertingRecorder();
        address other = makeAddr("otherRecorder");

        vm.prank(moduleAdmin);
        hook.setEmissionRecorder(address(recorder));
        assertEq(
            hook.emissionRecorder(),
            address(recorder),
            "a reverting recorder still seats: the only guard is non-zero, nothing probes the interface"
        );

        vm.expectRevert(AureumFeeRoutingHook.NotEmissionRecorderAdmin.selector);
        vm.prank(moduleAdmin);
        hook.setEmissionRecorder(other);

        address lp = makeAddr("lp");
        address pool = makeAddr("pool");
        SenderRouter router = new SenderRouter(lp);
        vm.prank(moduleAdmin);
        hook.setGovernanceModule(governance);
        vm.prank(governance);
        hook.setTrustedRouter(address(router), true);

        HookFlags memory flags = hook.getHookFlags();
        assertTrue(
            flags.shouldCallAfterAddLiquidity && flags.shouldCallAfterRemoveLiquidity,
            "the Vault genuinely invokes both callbacks, so the dispatch sits on the live liquidity path"
        );

        // A reverting recorder degrades the add and the remove rather than reverting them.
        _assertAddDegrades(hook, address(router), pool, lp);
        _assertRemoveDegrades(hook, address(router), pool, lp);

        // A trusted router whose sender cannot be read as one clean address word degrades too,
        // naming no holder: a reverting getSender, a codeless address, a dirty upper word and a
        // short return, the last three being shapes a typed call would fail to decode in the hook.
        address[4] memory unreadable = [
            address(new RevertingSenderRouter()),
            makeAddr("codelessRouter"),
            address(new RawReturnRouter(abi.encode(type(uint256).max))),
            address(new RawReturnRouter(hex"1234"))
        ];
        for (uint256 i = 0; i < unreadable.length; i++) {
            vm.prank(governance);
            hook.setTrustedRouter(unreadable[i], true);
            _assertAddDegrades(hook, unreadable[i], pool, address(0));
        }

        // A codeless recorder degrades as well: the hook's explicit code check stands in for the
        // extcodesize check a `try` cannot catch. It needs a fresh hook, the recorder seat being
        // one-shot.
        AureumFeeRoutingHook codelessHook = new AureumFeeRoutingHook(
            vault,
            bodensee,
            IERC20(address(svZchf)),
            IERC20(address(susds)),
            IERC20(address(aummToken)),
            address(feeController),
            moduleAdmin
        );
        vm.startPrank(moduleAdmin);
        codelessHook.setEmissionRecorder(makeAddr("codelessRecorder"));
        codelessHook.setGovernanceModule(governance);
        vm.stopPrank();
        vm.prank(governance);
        codelessHook.setTrustedRouter(address(router), true);
        _assertAddDegrades(codelessHook, address(router), pool, lp);
    }

    /// @dev Drives the add callback as the Vault and asserts it completes, passes its amounts
    ///      through unadjusted and emits `RecorderDispatchFailed` naming `namedLp`.
    function _assertAddDegrades(AureumFeeRoutingHook target, address router, address pool, address namedLp)
        internal
    {
        uint256[] memory empty = new uint256[](0);
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = 7;
        amountsIn[1] = 11;
        vm.expectEmit(address(target));
        emit AureumFeeRoutingHook.RecorderDispatchFailed(pool, namedLp, true);
        vm.prank(vault);
        (bool ok, uint256[] memory out) = target.onAfterAddLiquidity(
            router, pool, AddLiquidityKind.UNBALANCED, empty, amountsIn, BPT_OUT, empty, bytes("")
        );
        assertTrue(ok, "the add completes rather than reverting");
        assertEq(out, amountsIn, "the add's amounts pass through unadjusted");
    }

    /// @dev Drives the remove callback as the Vault and asserts it completes, passes its amounts
    ///      through unadjusted and emits `RecorderDispatchFailed` naming `namedLp`.
    function _assertRemoveDegrades(AureumFeeRoutingHook target, address router, address pool, address namedLp)
        internal
    {
        uint256[] memory empty = new uint256[](0);
        uint256[] memory amountsOut = new uint256[](2);
        amountsOut[0] = 13;
        amountsOut[1] = 17;
        vm.expectEmit(address(target));
        emit AureumFeeRoutingHook.RecorderDispatchFailed(pool, namedLp, false);
        vm.prank(vault);
        (bool ok, uint256[] memory out) = target.onAfterRemoveLiquidity(
            router, pool, RemoveLiquidityKind.PROPORTIONAL, BPT_OUT, empty, amountsOut, empty, bytes("")
        );
        assertTrue(ok, "the remove completes rather than reverting");
        assertEq(out, amountsOut, "the remove's amounts pass through unadjusted");
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
