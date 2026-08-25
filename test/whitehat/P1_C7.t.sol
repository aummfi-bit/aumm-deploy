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

/// @notice Reproduction PoC for seam-1 root cause C.7 (Medium, author-validated).
///         Two one-shot admin slots that were never fired remain live on the deployer:
///         `AureumFeeRoutingHook`'s private `_incendiaryAdmin`, and `CCBMultiplier`'s
///         `registrySetter`. Both slots buy availability rather than magnitude — the CCB
///         multiplier's [0.75, 1.25] clamp is an inductive invariant independent of which
///         registry is bound. D.8 shares this row's redeploy unit.
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

    /// @notice The hook's constructor-set `_incendiaryAdmin` still authorises
    ///         `setIncendiaryModule`; the slot was never rotated or renounced.
    function test_P1_C7_theHooksIncendiaryAdminSlotIsStillLiveOnTheDeployer() public {
        // The hook's slot must be proved behaviorally because `_incendiaryAdmin` is private
        // with no getter at src/fee_router/AureumFeeRoutingHook.sol L137 — the missing getter
        // is itself part of what C.7 reports.
        address module = makeAddr("incendiaryModule");

        vm.expectRevert(AureumFeeRoutingHook.NotIncendiaryAdmin.selector);
        vm.prank(stranger);
        hook.setIncendiaryModule(module);

        vm.prank(moduleAdmin);
        hook.setIncendiaryModule(module);

        assertEq(
            hook.incendiaryModule(),
            module,
            "constructor-set moduleAdmin still fires setIncendiaryModule; the one-shot slot is live as at deploy"
        );
    }

    /// @notice CCBMultiplier's deployer-pinned registrySetter still fires
    ///         setMiliariumRegistry; no deploy script ever sealed it.
    function test_P1_C7_theCCBMultiplierRegistrySetterIsStillLiveOnTheDeployer() public {
        // Verified asymmetry: CCBMultiplier carries TWO sibling one-shot slots pinned to the
        // deployer at construction, registrySetter and gaugeRegistrySetter. script/DeployStageP.s.sol
        // L201 calls setGaugeRegistry and therefore seals the gauge one; no script anywhere calls
        // setMiliariumRegistry on CCBMultiplier — the only setMiliariumRegistry in script/ is
        // DeployStageK.s.sol L161 on TVLOracle. Sealing one sibling but not the other is what makes
        // this an omission rather than a design choice.
        IMiliariumRegistry replacement = IMiliariumRegistry(makeAddr("replacementRegistry"));
        assertEq(
            multiplier.registrySetter(),
            address(this),
            "slot is unsealed and still pinned to the address that deployed the contract"
        );

        vm.expectRevert(CCBMultiplier.OnlyRegistrySetter.selector);
        vm.prank(stranger);
        multiplier.setMiliariumRegistry(replacement);

        multiplier.setMiliariumRegistry(replacement);
        assertEq(
            multiplier.registrySetter(),
            address(0),
            "firing the setter seals it; production never fires this one, so the slot stays at its deploy-time value forever"
        );

        assertEq(
            address(multiplier.miliariumRegistry()),
            address(replacement),
            "test-contract registrySetter still fires setMiliariumRegistry; the one-shot slot is live as at deploy"
        );
    }
}
