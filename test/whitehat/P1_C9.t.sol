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

/// @notice Reproduction PoC for seam-1 root cause C.9 (Medium). `recoverStrandedFees`
///         routes the hook's entire balance of any token through caller-chosen unvalidated
///         pools. The row's remaining clause — that a per-hop floor of zero permits an
///         arbitrarily bad execution price across the hops themselves — is NOT reproduced
///         here, since exercising the hops needs the real Vault.
contract P1_C9_RecoveryReportsSuccessIndependentOfDeliveryTest is Test {
    uint256 internal constant STRANDED = 5e18;

    event StrandedFeesRecovered(
        address indexed feeToken,
        address indexed depositToken,
        uint256 amountIn,
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

    /// @notice Success event reports the full stranded amount while the hook still holds it.
    function test_P1_C9_theSuccessEventReportsTheFullAmountWhileTheHookStillHoldsIt() public {
        // The single mock is legitimate under lesson PP10 and is not circular: the mechanism
        // under test is the EVENT's unconditional emission, not the callback. amountIn is read
        // from balanceOf at L831 BEFORE the unlock, the unlock's return is explicitly discarded
        // at L834-L840, and the event is emitted after it regardless of outcome, so making the
        // callback a no-op is what renders that independence observable. The assertion is a
        // MISMATCH between what the event claims and what the chain still holds. In production
        // the same mismatch arises without any mock, because L611's depositAmount == 0 early
        // return returns before the ReserveDidNotRise proof-of-delivery at L640-L642 can run.
        vm.prank(moduleAdmin);
        hook.setGovernanceModule(governance);

        susds.mint(address(hook), STRANDED);

        address[] memory swapPools = new address[](1);
        swapPools[0] = makeAddr("codelessPool");
        IERC20[] memory hopTokenOuts = new IERC20[](1);
        hopTokenOuts[0] = IERC20(address(svZchf));
        uint256[] memory minHopOuts = new uint256[](1);
        minHopOuts[0] = 0;

        vm.mockCall(vault, abi.encodeWithSelector(IVaultMain.unlock.selector), abi.encode(bytes("")));

        vm.expectEmit(true, true, false, true, address(hook));
        emit StrandedFeesRecovered(address(susds), address(svZchf), STRANDED, 1);

        vm.prank(governance);
        hook.recoverStrandedFees(
            IERC20(address(susds)),
            IERC20(address(svZchf)),
            swapPools,
            hopTokenOuts,
            minHopOuts
        );

        assertEq(
            susds.balanceOf(address(hook)),
            STRANDED,
            "hook still holds the full stranded amount after a success event that reported that same amount"
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
            minHopOuts
        );
    }
}
