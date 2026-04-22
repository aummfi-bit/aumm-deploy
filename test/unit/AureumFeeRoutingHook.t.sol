// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    AfterSwapParams,
    HookFlags,
    LiquidityManagement,
    SwapKind,
    TokenConfig
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {IVaultMain} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import {IVaultErrors} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import {AureumFeeRoutingHook} from "src/fee_router/AureumFeeRoutingHook.sol";
import {IAureumFeeRoutingHook} from "src/fee_router/IAureumFeeRoutingHook.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";
import {MockFeeController} from "test/mocks/MockFeeController.sol";

/// @title  AureumFeeRoutingHookTest
/// @notice Unit coverage for `AureumFeeRoutingHook` per Stage D5.1.
/// @dev    Harness per D-D18 / STAGE_D_NOTES D27: no `BaseVaultTest`
///         inheritance (permit2 absent from the repo), instead
///         `vault = makeAddr("vault")` plus `vm.mockCall` stubs for the
///         narrow IVault surface the hook actually touches
///         (getPoolTokenCountAndIndexOfToken, addLiquidity, settle).
///         Real MockERC20 / MockERC4626 / MockFeeController drive the
///         phase-1 svZCHF conversion and the fee-controller hand-off.
///         Branch C (nested `_vault.swap` + `sendTo`) and all
///         routeX-via-unlock success paths are deferred to D7 fork
///         tests — `vm.mockCall` cannot replicate the unlock callback
///         side-effects.
contract AureumFeeRoutingHookTest is Test {
    using stdStorage for StdStorage;

    // -------------------------------------------------------------------------
    // Fixtures
    // -------------------------------------------------------------------------

    address internal vault;
    address internal bodensee;
    address internal poolAb;
    address internal poolC;
    address internal admin;
    address internal gov;
    address internal inc;
    address internal stranger;

    MockERC20 internal zchf;
    MockERC4626 internal svZchf;
    MockERC20 internal aumm;
    MockERC20 internal tokenY;

    MockFeeController internal feeController;

    AureumFeeRoutingHook internal hook;

    /// @dev Storage layout for `AureumFeeRoutingHook`. `BaseHooks` is
    ///      stateless (abstract, all-virtual) and `VaultGuard` stores
    ///      only an immutable `_vault`, so the four post-construction
    ///      slots are contiguous from 0. `setUp` asserts the layout.
    uint256 internal constant SLOT_GOV_MODULE = 0;
    uint256 internal constant SLOT_INC_MODULE = 1;
    uint256 internal constant SLOT_GOV_ADMIN  = 2;
    uint256 internal constant SLOT_INC_ADMIN  = 3;

    // -------------------------------------------------------------------------
    // Event redeclarations (for vm.expectEmit)
    // -------------------------------------------------------------------------

    event GovernanceModuleSet(address indexed module);
    event IncendiaryModuleSet(address indexed module);

    event SwapFeeRouted(
        address indexed pool,
        address indexed feeToken,
        uint256 feeAmount,
        uint256 bptMinted
    );

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public virtual {
        vault    = makeAddr("vault");
        bodensee = makeAddr("bodensee");
        poolAb   = makeAddr("poolAb");
        poolC    = makeAddr("poolC");
        admin    = makeAddr("admin");
        gov      = makeAddr("gov");
        inc      = makeAddr("inc");
        stranger = makeAddr("stranger");

        zchf   = new MockERC20("Frankencoin", "ZCHF", 18);
        svZchf = new MockERC4626(IERC20(address(zchf)), "Savings Frankencoin", "svZCHF");
        aumm   = new MockERC20("Aureum", "AuMM", 18);
        tokenY = new MockERC20("Other", "Y", 18);

        feeController = new MockFeeController();

        hook = new AureumFeeRoutingHook(
            vault,
            bodensee,
            IERC20(address(svZchf)),
            IERC20(address(aumm)),
            address(feeController),
            admin
        );

        // Base mock-calls applied to every test. addLiquidity is stubbed
        // per-test via `_mockAddLiquidity` because its return tuple
        // depends on the amount in flight.
        vm.mockCall(
            vault,
            abi.encodeWithSelector(
                IVaultMain.getPoolTokenCountAndIndexOfToken.selector,
                bodensee,
                IERC20(address(svZchf))
            ),
            abi.encode(uint256(2), uint256(1))
        );
        vm.mockCall(
            vault,
            abi.encodeWithSelector(IVaultMain.settle.selector),
            abi.encode(uint256(0))
        );

        // Storage-layout sanity check: `_governanceAdmin` and
        // `_incendiaryAdmin` are private; the defensive-AlreadySet
        // tests reach them via `vm.store` at the hard-coded slots
        // above. If an upstream refactor ever introduces storage into
        // `BaseHooks` or `VaultGuard`, this assertion flags the drift
        // immediately rather than letting later tests silently address
        // the wrong slots.
        assertEq(
            address(uint160(uint256(vm.load(address(hook), bytes32(SLOT_GOV_ADMIN))))),
            admin,
            "slot 2 is not _governanceAdmin"
        );
        assertEq(
            address(uint160(uint256(vm.load(address(hook), bytes32(SLOT_INC_ADMIN))))),
            admin,
            "slot 3 is not _incendiaryAdmin"
        );
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev Per-test addLiquidity stub. Returns an `amountsIn[]` with
    ///      `svZchfAmount` at the svZCHF index (1, per the setUp mock
    ///      for `getPoolTokenCountAndIndexOfToken`), and `bptOut` plus
    ///      empty `returnData`.
    function _mockAddLiquidity(uint256 svZchfAmount, uint256 bptOut) internal {
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[1] = svZchfAmount;
        vm.mockCall(
            vault,
            abi.encodeWithSelector(IVaultMain.addLiquidity.selector),
            abi.encode(amountsIn, bptOut, bytes(""))
        );
    }

    function _afterSwap(
        address pool_,
        address router_,
        uint256 amountCalcRaw
    ) internal view returns (AfterSwapParams memory p) {
        p.kind = SwapKind.EXACT_IN;
        p.tokenIn = IERC20(address(zchf));
        p.tokenOut = IERC20(address(svZchf));
        p.amountCalculatedRaw = amountCalcRaw;
        p.router = router_;
        p.pool = pool_;
        p.userData = bytes("");
    }

    function _setForward(
        address pool_,
        address token,
        uint256 amount
    ) internal {
        IERC20[] memory ts = new IERC20[](1);
        ts[0] = IERC20(token);
        uint256[] memory amts = new uint256[](1);
        amts[0] = amount;
        feeController.setForward(pool_, ts, amts);
    }

    function _setForward2(
        address pool_,
        address t0,
        uint256 a0,
        address t1,
        uint256 a1
    ) internal {
        IERC20[] memory ts = new IERC20[](2);
        ts[0] = IERC20(t0);
        ts[1] = IERC20(t1);
        uint256[] memory amts = new uint256[](2);
        amts[0] = a0;
        amts[1] = a1;
        feeController.setForward(pool_, ts, amts);
    }

    function _tc0() internal pure returns (TokenConfig[] memory tc) {
        tc = new TokenConfig[](0);
    }

    function _tc(address t0) internal pure returns (TokenConfig[] memory tc) {
        tc = new TokenConfig[](1);
        tc[0].token = IERC20(t0);
    }

    function _tc(address t0, address t1, address t2) internal pure returns (TokenConfig[] memory tc) {
        tc = new TokenConfig[](3);
        tc[0].token = IERC20(t0);
        tc[1].token = IERC20(t1);
        tc[2].token = IERC20(t2);
    }

    function _lm() internal pure returns (LiquidityManagement memory lm) {
        // All defaults: unbalanced-enabled, custom-disabled, donation-disabled.
    }

    // -------------------------------------------------------------------------
    // Constructor (8)
    // -------------------------------------------------------------------------

    function test_constructor_immutables() public view {
        assertEq(hook.AUREUM_VAULT(), vault);
        assertEq(hook.DER_BODENSEE(), bodensee);
        assertEq(address(hook.SV_ZCHF()), address(svZchf));
        assertEq(address(hook.AUMM()), address(aumm));
        assertEq(hook.FEE_CONTROLLER(), address(feeController));
        assertEq(address(hook.ZCHF()), address(zchf));
        // Two-flag lock initial state: modules zero, admins non-zero.
        assertEq(hook.governanceModule(), address(0));
        assertEq(hook.incendiaryModule(), address(0));
    }

    function test_constructor_revertsOnZeroVault() public {
        vm.expectRevert(IAureumFeeRoutingHook.ZeroAddress.selector);
        new AureumFeeRoutingHook(
            address(0), bodensee, IERC20(address(svZchf)), IERC20(address(aumm)),
            address(feeController), admin
        );
    }

    function test_constructor_revertsOnZeroBodensee() public {
        vm.expectRevert(IAureumFeeRoutingHook.ZeroAddress.selector);
        new AureumFeeRoutingHook(
            vault, address(0), IERC20(address(svZchf)), IERC20(address(aumm)),
            address(feeController), admin
        );
    }

    function test_constructor_revertsOnZeroSvZchf() public {
        vm.expectRevert(IAureumFeeRoutingHook.ZeroAddress.selector);
        new AureumFeeRoutingHook(
            vault, bodensee, IERC20(address(0)), IERC20(address(aumm)),
            address(feeController), admin
        );
    }

    function test_constructor_revertsOnZeroAuMM() public {
        vm.expectRevert(IAureumFeeRoutingHook.ZeroAddress.selector);
        new AureumFeeRoutingHook(
            vault, bodensee, IERC20(address(svZchf)), IERC20(address(0)),
            address(feeController), admin
        );
    }

    function test_constructor_revertsOnZeroFeeController() public {
        vm.expectRevert(IAureumFeeRoutingHook.ZeroAddress.selector);
        new AureumFeeRoutingHook(
            vault, bodensee, IERC20(address(svZchf)), IERC20(address(aumm)),
            address(0), admin
        );
    }

    function test_constructor_revertsOnZeroModuleAdmin() public {
        vm.expectRevert(IAureumFeeRoutingHook.ZeroAddress.selector);
        new AureumFeeRoutingHook(
            vault, bodensee, IERC20(address(svZchf)), IERC20(address(aumm)),
            address(feeController), address(0)
        );
    }

    function test_constructor_revertsOnNonERC4626SvZchf() public {
        // Passing a `MockERC20` as `svZchf_` — no `asset()` function;
        // the constructor's `IERC4626(...).asset()` low-level call
        // returns empty, then abi-decoding empty bytes reverts with no
        // reason. `vm.expectRevert()` with no selector matches.
        MockERC20 notVault = new MockERC20("Fake", "FAKE", 18);
        vm.expectRevert();
        new AureumFeeRoutingHook(
            vault, bodensee, IERC20(address(notVault)), IERC20(address(aumm)),
            address(feeController), admin
        );
    }

    // -------------------------------------------------------------------------
    // getHookFlags (1)
    // -------------------------------------------------------------------------

    function test_getHookFlags_shouldCallAfterSwapOnly() public view {
        HookFlags memory f = hook.getHookFlags();
        assertFalse(f.enableHookAdjustedAmounts,       "enableHookAdjustedAmounts");
        assertFalse(f.shouldCallBeforeInitialize,      "shouldCallBeforeInitialize");
        assertFalse(f.shouldCallAfterInitialize,       "shouldCallAfterInitialize");
        assertFalse(f.shouldCallComputeDynamicSwapFee, "shouldCallComputeDynamicSwapFee");
        assertFalse(f.shouldCallBeforeSwap,            "shouldCallBeforeSwap");
        assertTrue (f.shouldCallAfterSwap,             "shouldCallAfterSwap");
        assertFalse(f.shouldCallBeforeAddLiquidity,    "shouldCallBeforeAddLiquidity");
        assertFalse(f.shouldCallAfterAddLiquidity,     "shouldCallAfterAddLiquidity");
        assertFalse(f.shouldCallBeforeRemoveLiquidity, "shouldCallBeforeRemoveLiquidity");
        assertFalse(f.shouldCallAfterRemoveLiquidity,  "shouldCallAfterRemoveLiquidity");
    }

    // -------------------------------------------------------------------------
    // onRegister (6)
    // -------------------------------------------------------------------------

    function test_onRegister_revertsOnNonVaultCaller() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        hook.onRegister(address(0), poolAb, _tc0(), _lm());
    }

    function test_onRegister_returnsFalseForBodenseeAsPool() public {
        vm.prank(vault);
        bool ok = hook.onRegister(address(0), bodensee, _tc0(), _lm());
        assertFalse(ok);
    }

    function test_onRegister_returnsFalseForBodenseeAtFirstIndex() public {
        vm.prank(vault);
        bool ok = hook.onRegister(
            address(0),
            poolAb,
            _tc(bodensee, address(zchf), address(aumm)),
            _lm()
        );
        assertFalse(ok);
    }

    function test_onRegister_returnsFalseForBodenseeAtLastIndex() public {
        vm.prank(vault);
        bool ok = hook.onRegister(
            address(0),
            poolAb,
            _tc(address(zchf), address(aumm), bodensee),
            _lm()
        );
        assertFalse(ok);
    }

    function test_onRegister_returnsTrueForEmptyTokenConfig() public {
        vm.prank(vault);
        bool ok = hook.onRegister(address(0), poolAb, _tc0(), _lm());
        assertTrue(ok);
    }

    function test_onRegister_returnsTrueForNormalPool() public {
        vm.prank(vault);
        bool ok = hook.onRegister(
            address(0),
            poolAb,
            _tc(address(zchf), address(aumm), address(svZchf)),
            _lm()
        );
        assertTrue(ok);
    }

    // -------------------------------------------------------------------------
    // setGovernanceModule (6)
    // -------------------------------------------------------------------------

    function test_setGovernanceModule_success() public {
        vm.expectEmit(true, false, false, false, address(hook));
        emit GovernanceModuleSet(gov);
        vm.prank(admin);
        hook.setGovernanceModule(gov);

        assertEq(hook.governanceModule(), gov);
        // Admin slot zeroed atomically.
        assertEq(
            address(uint160(uint256(vm.load(address(hook), bytes32(SLOT_GOV_ADMIN))))),
            address(0)
        );
    }

    function test_setGovernanceModule_revertsFromNonAdmin() public {
        vm.expectRevert(AureumFeeRoutingHook.NotGovernanceAdmin.selector);
        vm.prank(stranger);
        hook.setGovernanceModule(gov);
    }

    function test_setGovernanceModule_revertsOnZeroModule() public {
        vm.expectRevert(IAureumFeeRoutingHook.ZeroAddress.selector);
        vm.prank(admin);
        hook.setGovernanceModule(address(0));
    }

    function test_setGovernanceModule_secondCallRevertsNotAdmin() public {
        // Second call from the original admin fails Gate 1
        // (`NotGovernanceAdmin`) because `_governanceAdmin` was zeroed
        // atomically on the first successful call. `AlreadySet` is not
        // reachable from this path under normal flow — see the
        // `_defensive_viaStorage` test for Gate 2 coverage.
        vm.prank(admin);
        hook.setGovernanceModule(gov);

        vm.expectRevert(AureumFeeRoutingHook.NotGovernanceAdmin.selector);
        vm.prank(admin);
        hook.setGovernanceModule(stranger);
    }

    function test_setGovernanceModule_alreadySetGate_defensive_viaStorage() public {
        // Craft a pathological state that cannot arise under normal flow:
        // `governanceModule != 0` AND `_governanceAdmin == admin`.
        // Only then does the `GovernanceModuleAlreadySet` gate fire.
        uint256 modSlot = stdstore.target(address(hook)).sig("governanceModule()").find();
        assertEq(modSlot, SLOT_GOV_MODULE, "governanceModule slot drift");
        vm.store(address(hook), bytes32(modSlot), bytes32(uint256(uint160(gov))));
        assertEq(hook.governanceModule(), gov);

        vm.expectRevert(AureumFeeRoutingHook.GovernanceModuleAlreadySet.selector);
        vm.prank(admin);
        hook.setGovernanceModule(stranger);
    }

    function test_setGovernanceModule_doesNotMutateIncendiaryLock() public {
        vm.prank(admin);
        hook.setGovernanceModule(gov);

        // Incendiary side untouched: admin still non-zero, module still zero.
        assertEq(hook.incendiaryModule(), address(0));
        assertEq(
            address(uint160(uint256(vm.load(address(hook), bytes32(SLOT_INC_ADMIN))))),
            admin
        );
        // Incendiary setter still callable by admin.
        vm.prank(admin);
        hook.setIncendiaryModule(inc);
        assertEq(hook.incendiaryModule(), inc);
    }

    // -------------------------------------------------------------------------
    // setIncendiaryModule (6) — mirror of setGovernanceModule
    // -------------------------------------------------------------------------

    function test_setIncendiaryModule_success() public {
        vm.expectEmit(true, false, false, false, address(hook));
        emit IncendiaryModuleSet(inc);
        vm.prank(admin);
        hook.setIncendiaryModule(inc);

        assertEq(hook.incendiaryModule(), inc);
        assertEq(
            address(uint160(uint256(vm.load(address(hook), bytes32(SLOT_INC_ADMIN))))),
            address(0)
        );
    }

    function test_setIncendiaryModule_revertsFromNonAdmin() public {
        vm.expectRevert(AureumFeeRoutingHook.NotIncendiaryAdmin.selector);
        vm.prank(stranger);
        hook.setIncendiaryModule(inc);
    }

    function test_setIncendiaryModule_revertsOnZeroModule() public {
        vm.expectRevert(IAureumFeeRoutingHook.ZeroAddress.selector);
        vm.prank(admin);
        hook.setIncendiaryModule(address(0));
    }

    function test_setIncendiaryModule_secondCallRevertsNotAdmin() public {
        vm.prank(admin);
        hook.setIncendiaryModule(inc);

        vm.expectRevert(AureumFeeRoutingHook.NotIncendiaryAdmin.selector);
        vm.prank(admin);
        hook.setIncendiaryModule(stranger);
    }

    function test_setIncendiaryModule_alreadySetGate_defensive_viaStorage() public {
        uint256 modSlot = stdstore.target(address(hook)).sig("incendiaryModule()").find();
        assertEq(modSlot, SLOT_INC_MODULE, "incendiaryModule slot drift");
        vm.store(address(hook), bytes32(modSlot), bytes32(uint256(uint160(inc))));
        assertEq(hook.incendiaryModule(), inc);

        vm.expectRevert(AureumFeeRoutingHook.IncendiaryModuleAlreadySet.selector);
        vm.prank(admin);
        hook.setIncendiaryModule(stranger);
    }

    function test_setIncendiaryModule_doesNotMutateGovernanceLock() public {
        vm.prank(admin);
        hook.setIncendiaryModule(inc);

        assertEq(hook.governanceModule(), address(0));
        assertEq(
            address(uint160(uint256(vm.load(address(hook), bytes32(SLOT_GOV_ADMIN))))),
            admin
        );
        vm.prank(admin);
        hook.setGovernanceModule(gov);
        assertEq(hook.governanceModule(), gov);
    }

    // -------------------------------------------------------------------------
    // onAfterSwap (10)
    // -------------------------------------------------------------------------

    function test_onAfterSwap_revertsOnNonVaultCaller() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        hook.onAfterSwap(_afterSwap(poolAb, address(0xDEAD), 1234));
    }

    function test_onAfterSwap_recursionGuardReturnsEarly() public {
        // Router is this hook itself → early return with amountCalculatedRaw.
        // No call to the fee controller (no schedule configured).
        vm.prank(vault);
        (bool ok, uint256 ret) = hook.onAfterSwap(_afterSwap(poolAb, address(hook), 9_999));
        assertTrue(ok);
        assertEq(ret, 9_999);
    }

    function test_onAfterSwap_branchA_svZchfFee() public {
        // Branch A: feeToken == SV_ZCHF, phase-1 no-op, phase-2 sweep.
        uint256 amount = 100e18;
        // Fund feeController with svZCHF so it can hand them to the hook.
        // MockERC4626 has `mint` inherited? No — MockERC4626 has no mint.
        // Route svZCHF into feeController via the real deposit path:
        // mint ZCHF to this test, approve svZCHF, deposit to feeController.
        zchf.mint(address(this), amount);
        zchf.approve(address(svZchf), amount);
        svZchf.deposit(amount, address(feeController));
        assertEq(svZchf.balanceOf(address(feeController)), amount);

        _setForward(poolAb, address(svZchf), amount);
        _mockAddLiquidity(amount, 123e18);

        vm.expectEmit(true, true, false, true, address(hook));
        emit SwapFeeRouted(poolAb, address(svZchf), amount, 123e18);

        vm.prank(vault);
        (bool ok, uint256 ret) = hook.onAfterSwap(_afterSwap(poolAb, address(0xDEAD), 7));
        assertTrue(ok);
        assertEq(ret, 7);

        // Hook swept everything to the mocked Vault EOA.
        assertEq(svZchf.balanceOf(address(hook)), 0, "hook holds no svZchf");
        assertEq(svZchf.balanceOf(address(feeController)), 0, "controller drained");
        assertEq(svZchf.balanceOf(vault), amount, "vault received the sweep");
    }

    function test_onAfterSwap_branchB_zchfFee() public {
        // Branch B: feeToken == ZCHF, phase 1 `forceApprove` + real
        // `MockERC4626.deposit`, phase 2 sweep.
        uint256 amount = 250e18;
        zchf.mint(address(feeController), amount);

        _setForward(poolAb, address(zchf), amount);
        _mockAddLiquidity(amount, 500e18);

        vm.expectEmit(true, true, false, true, address(hook));
        emit SwapFeeRouted(poolAb, address(zchf), amount, 500e18);

        vm.prank(vault);
        hook.onAfterSwap(_afterSwap(poolAb, address(0xDEAD), 0));

        // ZCHF now in svZchf as backing; 1:1 shares swept to the Vault.
        assertEq(zchf.balanceOf(address(hook)), 0, "hook holds no zchf");
        assertEq(zchf.balanceOf(address(svZchf)), amount, "svZchf holds backing");
        assertEq(svZchf.balanceOf(address(hook)), 0, "hook holds no svZchf");
        assertEq(svZchf.balanceOf(vault), amount, "vault received the sweep");
    }

    function test_onAfterSwap_zeroAmountIsNoop() public {
        // Schedule a token with zero amount; loop continues, no event,
        // no addLiquidity call (no mock configured — test fails loudly
        // if one is attempted).
        _setForward(poolAb, address(zchf), 0);

        vm.prank(vault);
        hook.onAfterSwap(_afterSwap(poolAb, address(0xDEAD), 0));

        assertEq(svZchf.balanceOf(vault), 0);
        assertEq(zchf.balanceOf(address(hook)), 0);
    }

    function test_onAfterSwap_multiToken_orderDependentSweep() public {
        // Two non-zero entries: ZCHF then svZCHF. `collectSwapAggregateFeesForHook`
        // drains both to the hook in one call; phase 2 of the first
        // iteration sweeps the combined svZCHF (dust from branch B's
        // fresh deposit + the branch-A forwarded balance). The second
        // iteration finds balance == 0, emits with `bptMinted == 0`.
        uint256 zAmt = 100e18;
        uint256 sAmt = 50e18;

        zchf.mint(address(feeController), zAmt);
        zchf.mint(address(this), sAmt);
        zchf.approve(address(svZchf), sAmt);
        svZchf.deposit(sAmt, address(feeController));

        _setForward2(poolAb, address(zchf), zAmt, address(svZchf), sAmt);
        _mockAddLiquidity(zAmt + sAmt, 999e18);

        vm.expectEmit(true, true, false, true, address(hook));
        emit SwapFeeRouted(poolAb, address(zchf), zAmt, 999e18);
        vm.expectEmit(true, true, false, true, address(hook));
        emit SwapFeeRouted(poolAb, address(svZchf), sAmt, 0);

        vm.prank(vault);
        hook.onAfterSwap(_afterSwap(poolAb, address(0xDEAD), 0));

        assertEq(svZchf.balanceOf(address(hook)), 0);
        assertEq(svZchf.balanceOf(vault), zAmt + sAmt);
    }

    function test_onAfterSwap_mixedZeroAndNonZero() public {
        // First entry zero (skipped), second entry non-zero (executed).
        uint256 amount = 80e18;
        zchf.mint(address(feeController), amount);

        IERC20[] memory ts = new IERC20[](2);
        ts[0] = IERC20(address(tokenY)); // zero amount — branch-C not reached
        ts[1] = IERC20(address(zchf));
        uint256[] memory amts = new uint256[](2);
        amts[0] = 0;
        amts[1] = amount;
        feeController.setForward(poolAb, ts, amts);

        _mockAddLiquidity(amount, 1e18);

        vm.expectEmit(true, true, false, true, address(hook));
        emit SwapFeeRouted(poolAb, address(zchf), amount, 1e18);

        vm.prank(vault);
        hook.onAfterSwap(_afterSwap(poolAb, address(0xDEAD), 0));

        assertEq(svZchf.balanceOf(vault), amount);
    }

    function test_onAfterSwap_balanceSweep_includesDust() public {
        // D3.3.4 Q1 / Option X — phase 2 uses `SV_ZCHF.balanceOf(hook)`,
        // not `amount`, so pre-existing dust on the hook is swept along
        // with the freshly minted shares.
        uint256 dust = 5e18;
        uint256 freshZchf = 100e18;

        // Pre-mint dust svZCHF directly to the hook.
        zchf.mint(address(this), dust);
        zchf.approve(address(svZchf), dust);
        svZchf.deposit(dust, address(hook));
        assertEq(svZchf.balanceOf(address(hook)), dust);

        zchf.mint(address(feeController), freshZchf);
        _setForward(poolAb, address(zchf), freshZchf);
        _mockAddLiquidity(dust + freshZchf, 777e18);

        vm.expectEmit(true, true, false, true, address(hook));
        emit SwapFeeRouted(poolAb, address(zchf), freshZchf, 777e18);

        vm.prank(vault);
        hook.onAfterSwap(_afterSwap(poolAb, address(0xDEAD), 0));

        assertEq(svZchf.balanceOf(address(hook)), 0, "dust + fresh both swept");
        assertEq(svZchf.balanceOf(vault), dust + freshZchf);
    }

    function test_onAfterSwap_branchC_deferredRevertShape() public {
        // Branch C — non-ZCHF-family token with a valid pool — calls
        // `_vault.swap(...)` which is not mocked. `vault` is an
        // empty-code EOA from `makeAddr`; the call to a non-existent
        // `swap` selector reverts. This test locks in the revert shape
        // so D7 can safely promote branch C to a real-Vault fork test
        // without a silent scope expansion.
        uint256 amount = 10e18;
        tokenY.mint(address(feeController), amount);
        _setForward(poolAb, address(tokenY), amount);

        vm.prank(vault);
        vm.expectRevert();
        hook.onAfterSwap(_afterSwap(poolAb, address(0xDEAD), 0));
    }

    function test_onAfterSwap_returnsAmountCalculatedRaw() public {
        // Explicit coverage of the second return value across a regular
        // (non-recursion-guarded) call. Branch A minimal path.
        uint256 amount = 1e18;
        zchf.mint(address(this), amount);
        zchf.approve(address(svZchf), amount);
        svZchf.deposit(amount, address(feeController));

        _setForward(poolAb, address(svZchf), amount);
        _mockAddLiquidity(amount, 1);

        vm.prank(vault);
        (, uint256 ret) = hook.onAfterSwap(_afterSwap(poolAb, address(0xDEAD), 424242));
        assertEq(ret, 424242);
    }

    // -------------------------------------------------------------------------
    // routeYieldFee reverts (4)
    // -------------------------------------------------------------------------

    function test_routeYieldFee_revertsOnUnauthorizedCaller() public {
        vm.expectRevert(abi.encodeWithSelector(
            IAureumFeeRoutingHook.UnauthorizedCaller.selector, stranger
        ));
        vm.prank(stranger);
        hook.routeYieldFee(poolAb, IERC20(address(zchf)), 1e18);
    }

    function test_routeYieldFee_revertsOnZeroPool() public {
        vm.expectRevert(IAureumFeeRoutingHook.ZeroAddress.selector);
        vm.prank(address(feeController));
        hook.routeYieldFee(address(0), IERC20(address(zchf)), 1e18);
    }

    function test_routeYieldFee_revertsOnBodenseePool() public {
        vm.expectRevert(abi.encodeWithSelector(
            IAureumFeeRoutingHook.InvalidPool.selector, bodensee
        ));
        vm.prank(address(feeController));
        hook.routeYieldFee(bodensee, IERC20(address(zchf)), 1e18);
    }

    function test_routeYieldFee_revertsOnZeroAmount() public {
        vm.expectRevert(IAureumFeeRoutingHook.ZeroAmount.selector);
        vm.prank(address(feeController));
        hook.routeYieldFee(poolAb, IERC20(address(zchf)), 0);
    }

    // -------------------------------------------------------------------------
    // routeGovernanceDeposit reverts (3)
    // -------------------------------------------------------------------------

    function test_routeGovernanceDeposit_revertsOnModuleNotSet() public {
        vm.expectRevert(IAureumFeeRoutingHook.ModuleNotSet.selector);
        vm.prank(gov);
        hook.routeGovernanceDeposit(IERC20(address(zchf)), 1e18);
    }

    function test_routeGovernanceDeposit_revertsOnUnauthorizedCaller() public {
        vm.prank(admin);
        hook.setGovernanceModule(gov);

        vm.expectRevert(abi.encodeWithSelector(
            IAureumFeeRoutingHook.UnauthorizedCaller.selector, stranger
        ));
        vm.prank(stranger);
        hook.routeGovernanceDeposit(IERC20(address(zchf)), 1e18);
    }

    function test_routeGovernanceDeposit_revertsOnZeroAmount() public {
        vm.prank(admin);
        hook.setGovernanceModule(gov);

        vm.expectRevert(IAureumFeeRoutingHook.ZeroAmount.selector);
        vm.prank(gov);
        hook.routeGovernanceDeposit(IERC20(address(zchf)), 0);
    }

    // -------------------------------------------------------------------------
    // routeIncendiaryDeposit reverts (3) — mirror of Governance
    // -------------------------------------------------------------------------

    function test_routeIncendiaryDeposit_revertsOnModuleNotSet() public {
        vm.expectRevert(IAureumFeeRoutingHook.ModuleNotSet.selector);
        vm.prank(inc);
        hook.routeIncendiaryDeposit(IERC20(address(zchf)), 1e18);
    }

    function test_routeIncendiaryDeposit_revertsOnUnauthorizedCaller() public {
        vm.prank(admin);
        hook.setIncendiaryModule(inc);

        vm.expectRevert(abi.encodeWithSelector(
            IAureumFeeRoutingHook.UnauthorizedCaller.selector, stranger
        ));
        vm.prank(stranger);
        hook.routeIncendiaryDeposit(IERC20(address(zchf)), 1e18);
    }

    function test_routeIncendiaryDeposit_revertsOnZeroAmount() public {
        vm.prank(admin);
        hook.setIncendiaryModule(inc);

        vm.expectRevert(IAureumFeeRoutingHook.ZeroAmount.selector);
        vm.prank(inc);
        hook.routeIncendiaryDeposit(IERC20(address(zchf)), 0);
    }

    // -------------------------------------------------------------------------
    // Fuzz (2)
    // -------------------------------------------------------------------------

    function testFuzz_onAfterSwap_branchA_amount(uint256 amount) public {
        // Bounded to [1, 1e27] to stay clear of ERC-20 mint overflow
        // while exercising the full realistic numeric range.
        amount = bound(amount, 1, 1e27);

        zchf.mint(address(this), amount);
        zchf.approve(address(svZchf), amount);
        svZchf.deposit(amount, address(feeController));

        _setForward(poolAb, address(svZchf), amount);
        _mockAddLiquidity(amount, amount); // 1:1 bpt for the fuzz path

        vm.expectEmit(true, true, false, true, address(hook));
        emit SwapFeeRouted(poolAb, address(svZchf), amount, amount);

        vm.prank(vault);
        hook.onAfterSwap(_afterSwap(poolAb, address(0xDEAD), 0));

        assertEq(svZchf.balanceOf(address(hook)), 0);
        assertEq(svZchf.balanceOf(vault), amount);
    }

    function testFuzz_onAfterSwap_branchB_amount(uint256 amount) public {
        amount = bound(amount, 1, 1e27);

        zchf.mint(address(feeController), amount);

        _setForward(poolAb, address(zchf), amount);
        _mockAddLiquidity(amount, amount);

        vm.expectEmit(true, true, false, true, address(hook));
        emit SwapFeeRouted(poolAb, address(zchf), amount, amount);

        vm.prank(vault);
        hook.onAfterSwap(_afterSwap(poolAb, address(0xDEAD), 0));

        assertEq(zchf.balanceOf(address(hook)), 0);
        assertEq(svZchf.balanceOf(address(hook)), 0);
        assertEq(svZchf.balanceOf(vault), amount);
    }
}

