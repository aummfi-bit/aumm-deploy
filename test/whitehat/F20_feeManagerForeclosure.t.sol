// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {PoolRoleAccounts} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {AureumGovernance} from "../../src/governance/AureumGovernance.sol";
import {IVotingWeight} from "../../src/governance/IVotingWeight.sol";
import {IGaugeRegistry} from "../../src/ccb/IGaugeRegistry.sol";
import {IMiliariumSlotRegistry} from "../../src/registry/IMiliariumSlotRegistry.sol";
import {SwapAndDepositToBodensee} from "../../src/gauge/SwapAndDepositToBodensee.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Fee-path-only IGaugeRegistry double — every pool reads gauge-approved (the F-20 gate under test sits AFTER this check).
contract MockGaugeRegistry {
    function isGaugeApproved(address) external pure returns (bool) {
        return true;
    }
}

/// @notice Settable-manager Vault double for the F-20 gate — `getPoolRoleAccounts` returns a struct whose only non-zero field is the per-pool `swapFeeManager` set by the test (mirrors the unit-suite zeroed double; kept inline for PoC isolation per the F18 house style).
contract MockVault {
    mapping(address => address) internal _swapFeeManagerOf;

    function setSwapFeeManager(address pool, address manager) external {
        _swapFeeManagerOf[pool] = manager;
    }

    function getPoolRoleAccounts(address pool) external view returns (PoolRoleAccounts memory roleAccounts) {
        roleAccounts.swapFeeManager = _swapFeeManagerOf[pool];
    }
}

/// @notice Donate-counting SwapAndDepositToBodensee double — the `_createProposal` deposit tail lands here.
contract MockBodenseeChannel {
    uint256 public donateCalls;

    function donate(IERC20, uint256) external {
        donateCalls++;
    }
}

/// @notice Constructor-placeholder double — the fee-propose path never reads the voting weight.
contract MockVotingWeight {}

/// @notice Constructor-placeholder double — the fee-propose path never reads the slot registry.
contract MockSlotRegistry {}

/// @title F20_feeManagerForeclosure — F-20 (S8/S9 Medium) witness for the FeeChange executability gate.
/// @notice Balancer's `setStaticSwapFeePercentage` authenticates by EXCLUSIVE role: a non-zero pool
///         `swapFeeManager` locks fee changes to that one address and never consults the authorizer, so a
///         FeeChange proposal against such a pool passed propose/vote/queue and then always reverted
///         `SenderNotAllowed()` at execute — AFTER the non-refundable 1_000e18 svZCHF bond was donated
///         (surfaced by the P10.3c Leg C3 first fork run; the roster-wide foreclosure is fixed pool-side by
///         F20b `swapFeeManager: address(0)`). This PoC witnesses the governance-side Fix B (P-D40): the
///         propose-time `ExclusiveSwapFeeManager` gate refuses the bond BEFORE any transfer, and the two
///         legitimate manager shapes — `address(0)` (authorizer-deferral) and the governance contract
///         itself — pass. Role accounts are immutable post-registration, so propose-time screening is
///         complete (no execute re-check needed).
contract F20FeeManagerForeclosureTest is Test {
    uint256 internal constant DEPOSIT = 1_000e18; // AureumGovernance.PROPOSAL_DEPOSIT_SVZCHF (internal there)
    uint256 internal constant FEE_OK = 1e15; // inside [SWAP_FEE_MIN 1e14, SWAP_FEE_MAX 3e15]
    uint256 internal constant FEE_TOO_HIGH = 3e15 + 1;

    MockGaugeRegistry internal gaugeReg;
    MockVault internal vault;
    MockBodenseeChannel internal channel;
    MockERC20 internal svZchf;
    MockERC20 internal sUsds;
    AureumGovernance internal gov;

    address internal bodenseePool = makeAddr("bodenseePool");
    address internal feePool = makeAddr("feePool");
    address internal creatorManager = makeAddr("creatorManager");
    address internal proposer = makeAddr("proposer");

    function setUp() public {
        gaugeReg = new MockGaugeRegistry();
        vault = new MockVault();
        channel = new MockBodenseeChannel();
        svZchf = new MockERC20("Staked Frankencoin", "svZCHF", 18);
        sUsds = new MockERC20("Savings USDS", "sUSDS", 18);
        gov = new AureumGovernance(
            IVotingWeight(address(new MockVotingWeight())),
            IGaugeRegistry(address(gaugeReg)),
            IMiliariumSlotRegistry(address(new MockSlotRegistry())),
            IVault(address(vault)),
            SwapAndDepositToBodensee(address(channel)),
            IERC20(address(svZchf)),
            IERC20(address(sUsds)),
            bodenseePool
        );
        svZchf.mint(proposer, DEPOSIT);
        vm.prank(proposer);
        svZchf.approve(address(gov), type(uint256).max);
    }

    /// @notice A creator-set exclusive manager is refused at propose — full-encoded arg-carrying error,
    ///         zero bond pulled, zero proposal recorded, zero donate.
    function test_F20_exclusiveManager_revertsAndProtectsBond() public {
        vault.setSwapFeeManager(feePool, creatorManager);
        vm.prank(proposer);
        vm.expectRevert(
            abi.encodeWithSelector(AureumGovernance.ExclusiveSwapFeeManager.selector, feePool, creatorManager)
        );
        gov.proposeFeeChange(feePool, FEE_OK, IERC20(address(svZchf)));
        assertEq(svZchf.balanceOf(proposer), DEPOSIT);
        assertEq(gov.proposalCount(), 0);
        assertEq(channel.donateCalls(), 0);
    }

    /// @notice `swapFeeManager == address(0)` — the F20b roster shape — passes: the Vault defers to the
    ///         authorizer at execute, so the proposal is executable and the bond is legitimately taken.
    function test_F20_zeroManager_passes() public {
        vm.prank(proposer);
        uint256 id = gov.proposeFeeChange(feePool, FEE_OK, IERC20(address(svZchf)));
        assertEq(id, 1);
        assertEq(svZchf.balanceOf(proposer), 0);
        assertEq(svZchf.balanceOf(address(channel)), DEPOSIT);
        assertEq(channel.donateCalls(), 1);
    }

    /// @notice `swapFeeManager == address(gov)` passes: the exclusive role IS the governance contract, so
    ///         execute's Vault call succeeds without the authorizer.
    function test_F20_governanceAsManager_passes() public {
        vault.setSwapFeeManager(feePool, address(gov));
        vm.prank(proposer);
        uint256 id = gov.proposeFeeChange(feePool, FEE_OK, IERC20(address(svZchf)));
        assertEq(id, 1);
        assertEq(channel.donateCalls(), 1);
    }

    /// @notice Gate ordering — the fee-band check precedes the manager read, so the pre-F20 negative tests
    ///         keep their reverts (the I13 blast-radius contract from P-D40).
    function test_F20_gateOrder_bandCheckFirst() public {
        vault.setSwapFeeManager(feePool, creatorManager);
        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.InvalidFeeValue.selector, FEE_TOO_HIGH));
        gov.proposeFeeChange(feePool, FEE_TOO_HIGH, IERC20(address(svZchf)));
    }
}
