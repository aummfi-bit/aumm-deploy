// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaultMain} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";

import {AureumFeeRoutingHook} from "src/fee_router/AureumFeeRoutingHook.sol";
import {IAureumFeeRoutingHook} from "src/fee_router/IAureumFeeRoutingHook.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";
import {MockFeeController} from "test/mocks/MockFeeController.sol";

/// @notice Seam-1 root cause C.9. `recoverStrandedFees` routes the hook's entire balance of any
///         token through caller-chosen pools. The first case is the C.9 regression per PP-D58
///         (vii): a non-zero delivery floor enforced as a post-condition, with the delivered amount
///         in the event. The second stays a reproduction, the seat's rotation being deferred to
///         PP-D22 with C.2; venue restriction is deferred to rung 16, and the hops need the real Vault.
contract P1_C9_RecoveryReportsSuccessIndependentOfDeliveryTest is Test {
    uint256 internal constant STRANDED = 5e18;

    event StrandedFeesRecovered(
        address indexed feeToken,
        address indexed depositToken,
        uint256 amountIn,
        uint256 donated,
        uint256 hops
    );

    AureumFeeRoutingHook internal hook;
    address internal vault;
    address internal bodensee;
    address internal moduleAdmin;
    address internal governance;
    address internal stranger;

    MockERC20 internal zchf;
    MockERC4626 internal svZchf;
    MockERC20 internal aumm;
    MockERC20 internal susds;
    MockFeeController internal feeController;

    function setUp() public {
        vault = makeAddr("vault");
        bodensee = makeAddr("bodensee");
        moduleAdmin = makeAddr("moduleAdmin");
        governance = makeAddr("governance");
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
    }

    /// @notice C.9 / PP-D58 (vii) regression, inverted at PP4.15g from the PoC in which the success
    ///         event reported the full stranded amount while the hook still held it: a recovery must
    ///         name a non-zero floor, the entry reverts when less than it reached der Bodensee, and
    ///         the event reports the amount delivered rather than the amount spent.
    function test_recoverStrandedFeesEnforcesMinimum() public {
        // The single mock is legitimate under lesson PP10 and is not circular: it stubs the unlock
        // so the callback's delivered amount is chosen, which is exactly the value the entry now
        // checks and reports; the hops themselves need the real Vault, the fork witness's domain.
        vm.prank(moduleAdmin);
        hook.setGovernanceModule(governance);

        susds.mint(address(hook), STRANDED);

        address[] memory swapPools = new address[](1);
        swapPools[0] = makeAddr("codelessPool");
        IERC20[] memory hopTokenOuts = new IERC20[](1);
        hopTokenOuts[0] = IERC20(address(svZchf));
        uint256[] memory minHopOuts = new uint256[](1);
        minHopOuts[0] = 0;

        // A zero floor is refused before anything moves.
        vm.expectRevert(IAureumFeeRoutingHook.MinimumDonationRequired.selector);
        vm.prank(governance);
        hook.recoverStrandedFees(
            IERC20(address(susds)),
            IERC20(address(svZchf)),
            swapPools,
            hopTokenOuts,
            minHopOuts,
            0
        );

        // The PoC's delivery of nothing: the callback reports zero, so the entry reverts rather than
        // emitting a success event over a balance the hook still holds.
        vm.mockCall(
            vault, abi.encodeWithSelector(IVaultMain.unlock.selector), abi.encode(abi.encode(uint256(0)))
        );
        vm.expectRevert(abi.encodeWithSelector(IAureumFeeRoutingHook.DonationBelowMinimum.selector, 0, 1));
        vm.prank(governance);
        hook.recoverStrandedFees(
            IERC20(address(susds)),
            IERC20(address(svZchf)),
            swapPools,
            hopTokenOuts,
            minHopOuts,
            1
        );
        assertEq(
            susds.balanceOf(address(hook)),
            STRANDED,
            "a refused recovery leaves the stranded balance where it was"
        );

        // A delivery meeting the floor succeeds, and the event carries the amount delivered.
        uint256 delivered = 4e18;
        vm.mockCall(
            vault, abi.encodeWithSelector(IVaultMain.unlock.selector), abi.encode(abi.encode(delivered))
        );
        vm.expectEmit(true, true, false, true, address(hook));
        emit StrandedFeesRecovered(address(susds), address(svZchf), STRANDED, delivered, 1);
        vm.prank(governance);
        hook.recoverStrandedFees(
            IERC20(address(susds)),
            IERC20(address(svZchf)),
            swapPools,
            hopTokenOuts,
            minHopOuts,
            delivered
        );
    }

    /// @notice governanceModule is burn-on-use with no rotation; it is the sole recovery authority.
    function test_P1_C9_theSoleAuthorityForRecoveryIsSeatedOnceWithNoRotationPath() public {
        // governanceModule is assigned in exactly ONE place in the whole contract, inside that
        // same burn-on-use setter, so no rotation path exists at any privilege level.
        vm.prank(moduleAdmin);
        hook.setGovernanceModule(governance);
        assertEq(hook.governanceModule(), governance, "seated governanceModule reads back");

        address other = makeAddr("otherGov");
        vm.expectRevert(AureumFeeRoutingHook.NotGovernanceAdmin.selector);
        vm.prank(moduleAdmin);
        hook.setGovernanceModule(other);

        address[] memory swapPools = new address[](1);
        swapPools[0] = makeAddr("codelessPool");
        IERC20[] memory hopTokenOuts = new IERC20[](1);
        hopTokenOuts[0] = IERC20(address(svZchf));
        uint256[] memory minHopOuts = new uint256[](1);
        minHopOuts[0] = 0;

        vm.expectRevert(
            abi.encodeWithSelector(IAureumFeeRoutingHook.UnauthorizedCaller.selector, stranger)
        );
        vm.prank(stranger);
        hook.recoverStrandedFees(
            IERC20(address(susds)),
            IERC20(address(svZchf)),
            swapPools,
            hopTokenOuts,
            minHopOuts,
            1
        );
    }
}
