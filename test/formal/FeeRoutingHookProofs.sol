// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AureumFeeRoutingHook} from "src/fee_router/AureumFeeRoutingHook.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";
import {MockFeeController} from "test/mocks/MockFeeController.sol";

/// @title  FeeRoutingHookProofs
/// @notice hevm symbolic proofs for the S5 fee-routing hook one-shot module
///         locks (PB2.12c / PB-D17). Invoke: hevm test --match prove_ --solver z3.
/// @dev    Tier-1 of the PB-D17 roster (P-H1..P-H6): the C-D11 / I-D16 two-flag
///         locks are pure storage state machines with no Vault call, so setUp
///         needs only the constructor-satisfying mocks and no vm.mockCall stubs.
///         This sub-step (PB2.12c1) carries P-H1 + P-H2 to validate the hevm
///         pipeline end-to-end; P-H3..P-H6 land at PB2.12c3 once green.
contract FeeRoutingHookProofs is Test {
    AureumFeeRoutingHook internal hook;

    address internal constant VAULT    = address(0x1000);
    address internal constant BODENSEE = address(0x2000);
    address internal constant ADMIN    = address(0xA11CE);

    function setUp() public {
        MockERC20 zchf = new MockERC20("Frankencoin", "ZCHF", 18);
        MockERC4626 svZchf = new MockERC4626(IERC20(address(zchf)), "Savings Frankencoin", "svZCHF");
        MockERC20 aumm = new MockERC20("Aureum", "AuMM", 18);
        MockERC20 susds = new MockERC20("Savings USDS", "sUSDS", 18);
        MockFeeController feeController = new MockFeeController();

        hook = new AureumFeeRoutingHook(
            VAULT,
            BODENSEE,
            IERC20(address(svZchf)),
            IERC20(address(susds)),
            IERC20(address(aumm)),
            address(feeController),
            ADMIN
        );
    }

    /// P-H1 one-shot: once governanceModule is set, every later
    /// setGovernanceModule reverts, for all callers and all args.
    function prove_governanceModule_setOnce(address first, address second, address caller) public {
        vm.assume(first != address(0));

        vm.prank(ADMIN);
        hook.setGovernanceModule(first);
        assert(hook.governanceModule() == first);

        vm.prank(caller);
        (bool ok, ) = address(hook).call(
            abi.encodeCall(AureumFeeRoutingHook.setGovernanceModule, (second))
        );
        assert(!ok);
    }

    /// P-H2 auth gate: before any set, setGovernanceModule reverts for
    /// every caller other than the constructor-set module admin.
    function prove_setGovernanceModule_onlyAdmin(address caller, address module) public {
        vm.assume(caller != ADMIN);

        vm.prank(caller);
        (bool ok, ) = address(hook).call(
            abi.encodeCall(AureumFeeRoutingHook.setGovernanceModule, (module))
        );
        assert(!ok);
    }
}
