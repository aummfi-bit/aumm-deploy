// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AureumFeeRoutingHook} from "src/fee_router/AureumFeeRoutingHook.sol";
import {CCBMultiplier} from "src/ccb/CCBMultiplier.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";
import {MockFeeController} from "test/mocks/MockFeeController.sol";

import {MockMiliariumRegistry, MockEMASampler, MockGaugeRegistry} from "test/unit/CCBMultiplier.t.sol";

/// @notice Regression for seam-1 root cause C.7 (Medium, author-validated), inverted from its PP3.2
///         reproduction per PP-D57 (vi), (vii) and (xiii). The two one-shot admin slots that stayed live
///         on the deployer are now closed by the deploy spine: `CCBMultiplier`'s `registrySetter` by a
///         same-registry seal on both deploy paths, and `AureumFeeRoutingHook`'s `_incendiaryAdmin` by
///         `renounceIncendiaryAdmin`, each asserted by a `DeployStageP` post-condition and by the
///         done-criteria cases in `test/fork/StagePRunRehearsal.t.sol`. These unit cases pin the two
///         primitives the spine calls. D.8 shares this row's redeploy unit.
contract P1_C7_UnfiredOneShotAdminSlotsRemainLiveOnTheDeployerTest is Test {
    AureumFeeRoutingHook internal hook;
    CCBMultiplier internal multiplier;

    address internal vault;
    address internal bodensee;
    address internal moduleAdmin;
    address internal stranger;

    MockERC20 internal zchf;
    MockERC4626 internal svZchf;
    MockERC20 internal aumm;
    MockERC20 internal susds;
    MockFeeController internal feeController;

    MockMiliariumRegistry internal miliReg;
    MockEMASampler internal ema;
    MockGaugeRegistry internal gauges;

    /// @dev Redeclared for `vm.expectEmit`, as the hook's unit suite does.
    event IncendiaryAdminRenounced(address indexed formerAdmin);

    function setUp() public {
        vault = makeAddr("vault");
        bodensee = makeAddr("bodensee");
        moduleAdmin = makeAddr("moduleAdmin");
        stranger = makeAddr("stranger");

        zchf = new MockERC20("Frankencoin", "ZCHF", 18);
        svZchf = new MockERC4626(IERC20(address(zchf)), "Savings Frankencoin", "svZCHF");
        aumm = new MockERC20("Aureum", "AuMM", 18);
        susds = new MockERC20("Savings USDS", "sUSDS", 18);
        feeController = new MockFeeController();

        hook = new AureumFeeRoutingHook(
            vault,
            bodensee,
            IERC20(address(svZchf)),
            IERC20(address(susds)),
            IERC20(address(aumm)),
            address(feeController),
            moduleAdmin
        );

        miliReg = new MockMiliariumRegistry();
        ema = new MockEMASampler();
        gauges = new MockGaugeRegistry();
        // Called from this test contract, so address(this) becomes registrySetter.
        multiplier = new CCBMultiplier(miliReg, ema, gauges);
    }

    /// @notice Inverts the reproduction that fired `setIncendiaryModule` from the still-live admin: after
    ///         `renounceIncendiaryAdmin` the slot reads zero through the new getter, and no caller, the
    ///         former admin included, can set a module or renounce again (PP-D57 (vii) and (xiii)).
    function test_P1_C7_theRenouncedIncendiaryAdminCanNeverSetAModule() public {
        address module = makeAddr("incendiaryModule");
        assertEq(hook.incendiaryAdmin(), moduleAdmin, "premise - the constructor seats moduleAdmin, now readable");

        vm.expectRevert(AureumFeeRoutingHook.NotIncendiaryAdmin.selector);
        vm.prank(stranger);
        hook.renounceIncendiaryAdmin();

        vm.expectEmit(true, false, false, false, address(hook));
        emit IncendiaryAdminRenounced(moduleAdmin);
        vm.prank(moduleAdmin);
        hook.renounceIncendiaryAdmin();
        assertEq(hook.incendiaryAdmin(), address(0), "the renounce burns the slot");

        vm.expectRevert(AureumFeeRoutingHook.NotIncendiaryAdmin.selector);
        vm.prank(moduleAdmin);
        hook.setIncendiaryModule(module);

        vm.expectRevert(AureumFeeRoutingHook.NotIncendiaryAdmin.selector);
        vm.prank(moduleAdmin);
        hook.renounceIncendiaryAdmin();

        assertEq(hook.incendiaryModule(), address(0), "no module was ever set");
    }

    /// @notice Inverts the reproduction that showed `registrySetter` live on its deployer: the spine's seal
    ///         re-sets the registry the multiplier already reads, burning the setter without moving the
    ///         registry, after which no caller can set it again (PP-D57 (vi) and (xiii)).
    function test_P1_C7_theSameRegistrySealBurnsTheSetterForever() public {
        IMiliariumRegistry replacement = IMiliariumRegistry(makeAddr("replacementRegistry"));
        assertEq(multiplier.registrySetter(), address(this), "premise - the constructor pins the deployer");
        assertEq(
            address(multiplier.miliariumRegistry()),
            address(miliReg),
            "premise - the constructor already bound the registry"
        );

        multiplier.setMiliariumRegistry(miliReg);

        assertEq(multiplier.registrySetter(), address(0), "the same-registry seal burns the setter");
        assertEq(
            address(multiplier.miliariumRegistry()),
            address(miliReg),
            "and leaves the bound registry where the constructor put it"
        );

        vm.expectRevert(CCBMultiplier.OnlyRegistrySetter.selector);
        multiplier.setMiliariumRegistry(replacement);
    }
}
