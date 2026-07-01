// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AddLiquidityKind, RemoveLiquidityKind} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {AureumFeeRoutingHook} from "src/fee_router/AureumFeeRoutingHook.sol";
import {IAureumFeeRoutingHook} from "src/fee_router/IAureumFeeRoutingHook.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";

/// @dev Simulates a router that lies about the LP via getSender().
contract SpoofRouter {
    address internal immutable sender;

    constructor(address sender_) {
        sender = sender_;
    }

    function getSender() external view returns (address) {
        return sender;
    }
}

/// @dev Selector-compatible spy for recordDeposit / recordWithdrawal without inheriting IEmissionDistributor.
contract RecorderSpy {
    uint256 public depositCalls;
    uint256 public withdrawalCalls;
    address public lastPool;
    address public lastUser;
    uint256 public lastAmount;

    function recordDeposit(address pool, address user, uint256 amount) external {
        depositCalls++;
        lastPool = pool;
        lastUser = user;
        lastAmount = amount;
    }

    function recordWithdrawal(address pool, address user, uint256 amount) external {
        withdrawalCalls++;
        lastPool = pool;
        lastUser = user;
        lastAmount = amount;
    }
}

/// @notice F-09 fix regression (WM.2) — the hook resolves the LP via IRouterSender(router).getSender();
///         before the fix any router (including an attacker's self-deployed router) was trusted, letting it
///         spoof LP identity into recordDeposit / recordWithdrawal and credit an arbitrary address into the
///         emission / qualification clock. The fix gates the liquidity-callback recorder dispatch on a
///         governance-managed trustedRouter allowlist: empty by default (fail-closed), non-allowlisted routers
///         are skipped (no credit, no revert), and only governance-allowlisted routers credit the resolved LP.
contract F09_RouterSpoofRecorderAttributionTest is Test {
    event TrustedRouterSet(address indexed router, bool trusted);

    uint256 internal constant BPT_OUT = 1_000e18;
    uint256 internal constant BPT_IN = 500e18;

    address internal vault;
    address internal bodensee;
    address internal feeController;
    address internal moduleAdmin;
    address internal governance;
    address internal pool;
    address internal victim;
    address internal legitLp;
    address internal stranger;

    MockERC20 internal zchf;
    MockERC4626 internal svZchf;
    MockERC20 internal susds;
    MockERC20 internal aumm;
    AureumFeeRoutingHook internal hook;
    RecorderSpy internal recorder;
    SpoofRouter internal selfRouter;
    SpoofRouter internal legitRouter;

    function setUp() public {
        vault = makeAddr("vault");
        bodensee = makeAddr("bodensee");
        feeController = makeAddr("feeController");
        moduleAdmin = makeAddr("moduleAdmin");
        governance = makeAddr("governance");
        pool = makeAddr("pool");
        victim = makeAddr("victim");
        legitLp = makeAddr("legitLp");
        stranger = makeAddr("stranger");

        zchf = new MockERC20("Frankencoin", "ZCHF", 18);
        svZchf = new MockERC4626(IERC20(address(zchf)), "svZCHF", "svZCHF");
        susds = new MockERC20("Savings USDS", "sUSDS", 18);
        aumm = new MockERC20("Aureum", "AuMM", 18);

        hook = new AureumFeeRoutingHook(
            vault,
            bodensee,
            IERC20(address(svZchf)),
            IERC20(address(susds)),
            IERC20(address(aumm)),
            feeController,
            moduleAdmin
        );

        recorder = new RecorderSpy();
        vm.prank(moduleAdmin);
        hook.setEmissionRecorder(address(recorder));
        vm.prank(moduleAdmin);
        hook.setGovernanceModule(governance);

        selfRouter = new SpoofRouter(victim);
        legitRouter = new SpoofRouter(legitLp);
    }

    function _empty() private pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    function test_F09_onAdd_selfRouter_notAllowlisted_skipsRecorder() public {
        vm.prank(vault);
        hook.onAfterAddLiquidity(
            address(selfRouter),
            pool,
            AddLiquidityKind.UNBALANCED,
            _empty(),
            _empty(),
            BPT_OUT,
            _empty(),
            bytes("")
        );

        assertEq(recorder.depositCalls(), 0);
    }

    function test_F09_onAdd_allowlistedRouter_creditsResolvedLp() public {
        vm.prank(governance);
        hook.setTrustedRouter(address(legitRouter), true);

        vm.prank(vault);
        hook.onAfterAddLiquidity(
            address(legitRouter),
            pool,
            AddLiquidityKind.UNBALANCED,
            _empty(),
            _empty(),
            BPT_OUT,
            _empty(),
            bytes("")
        );

        assertEq(recorder.depositCalls(), 1);
        assertEq(recorder.lastUser(), legitLp);
        assertEq(recorder.lastAmount(), BPT_OUT);
        assertEq(recorder.lastPool(), pool);
    }

    function test_F09_onRemove_selfRouter_notAllowlisted_skipsRecorder() public {
        vm.prank(vault);
        hook.onAfterRemoveLiquidity(
            address(selfRouter),
            pool,
            RemoveLiquidityKind.PROPORTIONAL,
            BPT_IN,
            _empty(),
            _empty(),
            _empty(),
            bytes("")
        );

        assertEq(recorder.withdrawalCalls(), 0);
    }

    function test_F09_onRemove_allowlistedRouter_creditsResolvedLp() public {
        vm.prank(governance);
        hook.setTrustedRouter(address(legitRouter), true);

        vm.prank(vault);
        hook.onAfterRemoveLiquidity(
            address(legitRouter),
            pool,
            RemoveLiquidityKind.PROPORTIONAL,
            BPT_IN,
            _empty(),
            _empty(),
            _empty(),
            bytes("")
        );

        assertEq(recorder.withdrawalCalls(), 1);
        assertEq(recorder.lastUser(), legitLp);
        assertEq(recorder.lastAmount(), BPT_IN);
    }

    function test_F09_setTrustedRouter_revertsFromNonGovernance() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IAureumFeeRoutingHook.UnauthorizedCaller.selector, stranger));
        hook.setTrustedRouter(address(selfRouter), true);
    }

    function test_F09_setTrustedRouter_emitsEvent() public {
        vm.expectEmit(true, true, true, true, address(hook));
        emit TrustedRouterSet(address(legitRouter), true);
        vm.prank(governance);
        hook.setTrustedRouter(address(legitRouter), true);
    }

    function test_F09_revokeTrustedRouter_reblocksDispatch_onAdd() public {
        vm.startPrank(governance);
        hook.setTrustedRouter(address(legitRouter), true);
        hook.setTrustedRouter(address(legitRouter), false);
        vm.stopPrank();

        vm.prank(vault);
        hook.onAfterAddLiquidity(
            address(legitRouter),
            pool,
            AddLiquidityKind.UNBALANCED,
            _empty(),
            _empty(),
            BPT_OUT,
            _empty(),
            bytes("")
        );

        assertEq(recorder.depositCalls(), 0);
    }
}
