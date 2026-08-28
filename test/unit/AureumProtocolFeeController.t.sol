// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import { IAureumProtocolFeeControllerHookExtension } from "../../src/fee_router/IAureumProtocolFeeControllerHookExtension.sol";

import { AureumAuthorizer } from "../../src/vault/AureumAuthorizer.sol";
import { AureumProtocolFeeController } from "../../src/vault/AureumProtocolFeeController.sol";
import { IAureumFeeRoutingHook } from "../../src/fee_router/IAureumFeeRoutingHook.sol";
import { AureumTime } from "../../src/lib/AureumTime.sol";

// ─── Invariant handler ─────────────────────────────────────────────────────
// Exposes a constrained set of controller entry points to the Foundry invariant
// fuzzer. Uses try/catch on every call so expected reverts don't terminate the
// fuzz sequence early.
contract AureumProtocolFeeControllerHandler {
    AureumProtocolFeeController internal immutable CONTROLLER;
    address internal immutable MULTISIG;

    // Pools the handler has touched — used by invariants to know which keys to check.
    address[] public touchedPools;
    mapping(address => bool) internal _seenPool;

    // Every recipient for which withdrawProtocolFees actually succeeded (try block ran).
    address[] public successfulWithdrawRecipients;

    constructor(AureumProtocolFeeController controller_, address multisig_) {
        CONTROLLER = controller_;
        MULTISIG = multisig_;
    }

    function _touch(address pool) internal {
        if (!_seenPool[pool]) {
            _seenPool[pool] = true;
            touchedPools.push(pool);
        }
    }

    // Creator-fee functions — always revert per Pass 4; swallow and record pool.
    function callSetPoolCreatorSwapFeePercentage(address pool, uint256 pct) external {
        _touch(pool);
        try CONTROLLER.setPoolCreatorSwapFeePercentage(pool, pct) {} catch {}
    }

    function callSetPoolCreatorYieldFeePercentage(address pool, uint256 pct) external {
        _touch(pool);
        try CONTROLLER.setPoolCreatorYieldFeePercentage(pool, pct) {} catch {}
    }

    function callWithdrawPoolCreatorFees(address pool) external {
        _touch(pool);
        try CONTROLLER.withdrawPoolCreatorFees(pool) {} catch {}
    }

    function callWithdrawPoolCreatorFeesWithRecipient(address pool, address recipient) external {
        _touch(pool);
        try CONTROLLER.withdrawPoolCreatorFees(pool, recipient) {} catch {}
    }

    // Withdraw — records recipient only when the call actually succeeds.
    function callWithdrawProtocolFees(address pool, address recipient) external {
        _touch(pool);
        try CONTROLLER.withdrawProtocolFees(pool, recipient) {
            successfulWithdrawRecipients.push(recipient);
        } catch {}
    }

    // View helpers for invariant functions.
    function touchedPoolsLength() external view returns (uint256) {
        return touchedPools.length;
    }

    function successfulWithdrawRecipientsLength() external view returns (uint256) {
        return successfulWithdrawRecipients.length;
    }
}

contract AureumProtocolFeeControllerTest is Test {
    // ─── Aureum contracts under test ───────────────────────────────────────
    AureumAuthorizer internal authorizer;
    AureumProtocolFeeController internal controller;
    AureumProtocolFeeControllerHandler internal handler;

    // ─── Addresses ─────────────────────────────────────────────────────────
    address internal multisig;
    address internal mockVault;
    // B5: Stage B placeholder for der Bodensee Pool — the immutable destination
    // for all protocol fee withdrawals. Matches what the deploy script will use
    // during Stage B fork tests (Stage B decision B5 in STAGE_B_PLAN.md).
    address internal constant DER_BODENSEE_POOL_PLACEHOLDER = address(0xDEAD);
    // D-D7: Stage D placeholder for the fee-routing hook — the immutable B10
    // withdrawal-recipient target (protocol fees route to the hook, not to
    // Bodensee directly). Separate from DER_BODENSEE_POOL per Option A
    // (two-immutables architecture) — STAGE_D_NOTES.md D23.
    address internal constant FEE_ROUTING_HOOK_PLACEHOLDER = address(0xBEEF);

    function setUp() public {
        // Deploy a real AureumAuthorizer so the mocked Vault's getAuthorizer()
        // returns a live contract and the inherited SingletonAuthentication
        // chain resolves end-to-end during tests. Decision B4-test-1 in
        // docs/STAGE_B_NOTES.md (Test file design notes).
        multisig = makeAddr("multisig");
        authorizer = new AureumAuthorizer(multisig);

        // The Vault itself is a mock address. The controller's constructor
        // (inherited SingletonAuthentication + VaultGuard) only stores the
        // address as immutables and does NOT call into the Vault at construction
        // time, so the mock doesn't need to be "live" until tests start calling
        // controller functions.
        mockVault = makeAddr("mockVault");

        // Wire the mock Vault's getAuthorizer() response before any test runs.
        // Every governance-gated test will hit SingletonAuthentication's
        // authenticate modifier, which calls getVault().getAuthorizer() ->
        // canPerform(...). This mock makes the first hop return the real
        // Aureum authorizer we just deployed.
        _mockGetAuthorizer(address(authorizer));

        // Deploy the controller with the mock Vault, the Stage B Bodensee
        // pool-identity placeholder, and the Stage D fee-routing hook placeholder.
        controller = new AureumProtocolFeeController(
            IVault(mockVault),
            DER_BODENSEE_POOL_PLACEHOLDER,
            FEE_ROUTING_HOOK_PLACEHOLDER
        );

        // PP-D48 clause (v): `routeYieldFeeToHook` and `setYieldRouteKeeper` both read
        // the hook's `governanceModule` as their authority, so the codeless placeholder
        // must answer that getter — otherwise every route reverts on a call to a
        // non-contract address before the gate can decide anything. Seating `multisig`
        // keeps every pre-existing route test valid through the Safe-fallback leg.
        vm.mockCall(
            FEE_ROUTING_HOOK_PLACEHOLDER,
            abi.encodeWithSelector(IAureumFeeRoutingHook.governanceModule.selector),
            abi.encode(multisig)
        );

        // Deploy the invariant handler and register it as the fuzz target.
        handler = new AureumProtocolFeeControllerHandler(controller, multisig);
        targetContract(address(handler));
    }

    // ─── Mock Vault helpers ────────────────────────────────────────────────
    // These helpers register vm.mockCall interceptions for the specific Vault
    // methods the controller calls back into. Each helper is idempotent: calling
    // it again re-registers the mock with new return values. Not all helpers are
    // used by this spec's smoke test — they exist for Test Spec 2 and Test Spec 3
    // to reuse without each test having to re-derive the selectors.

    function _mockGetAuthorizer(address returnedAuthorizer) internal {
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(IVaultMain.getAuthorizer.selector),
            abi.encode(returnedAuthorizer)
        );
    }

    function _mockGetPoolTokens(address pool, IERC20[] memory tokens) internal {
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(IVaultExtension.getPoolTokens.selector, pool),
            abi.encode(tokens)
        );
    }

    function _mockGetPoolTokenCountAndIndexOfToken(
        address pool,
        IERC20 token,
        uint256 count,
        uint256 index
    ) internal {
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(
                IVaultMain.getPoolTokenCountAndIndexOfToken.selector,
                pool,
                token
            ),
            abi.encode(count, index)
        );
    }

    function _mockSafeTransfer(IERC20 token) internal {
        // Mock the underlying ERC20 transfer so OZ SafeERC20.safeTransfer succeeds.
        // Selector-only match so any transfer call to this token returns true.
        vm.mockCall(
            address(token),
            abi.encodeWithSelector(IERC20.transfer.selector),
            abi.encode(true)
        );
    }

    function _mockUnlock() internal {
        // The withLatestFees modifier calls collectAggregateFees which calls _vault.unlock.
        // Mock unlock to return empty bytes so the modifier completes without the real
        // callback chain firing.
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(IVaultMain.unlock.selector),
            abi.encode(bytes(""))
        );
    }

    function _mockUpdateAggregateSwapFeePercentage() internal {
        // _updatePoolSwapFeePercentage calls _vault.updateAggregateSwapFeePercentage(pool, pct).
        // Selector-only mock: matches any pool/pct combination, returns no data.
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(IVaultAdmin.updateAggregateSwapFeePercentage.selector),
            ""
        );
    }

    function _mockUpdateAggregateYieldFeePercentage() internal {
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(IVaultAdmin.updateAggregateYieldFeePercentage.selector),
            ""
        );
    }

    function _mockCollectAggregateFees(
        address pool,
        uint256[] memory swapFees,
        uint256[] memory yieldFees
    ) internal {
        // Mock IVaultAdmin.collectAggregateFees(pool) → (swapFees, yieldFees).
        // The new collectAggregateFeesHookSwapForward callback (D4.7a) calls
        // this Vault entry point with the pool argument.
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(IVaultAdmin.collectAggregateFees.selector, pool),
            abi.encode(swapFees, yieldFees)
        );
    }

    function _mockSendToAny() internal {
        // Selector-only mock for IVaultMain.sendTo(token, recipient, amount).
        // Both legs of the new D4.7a callback (yield → controller, swap →
        // FEE_ROUTING_HOOK) hit this entry point. Tests use vm.expectCall to
        // assert the (token, recipient, amount) tuples per call.
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(IVaultMain.sendTo.selector),
            ""
        );
    }

    // ─── Storage slot helpers ──────────────────────────────────────────────

    // Compute the storage slot for _protocolFeeAmounts[pool][token].
    // Base slot 7 confirmed by: forge inspect AureumProtocolFeeController storageLayout
    // Nested mapping slot formula:
    //   outer = keccak256(pool, baseSlot)
    //   inner = keccak256(token, outer)
    function _protocolFeeAmountsSlot(address pool, IERC20 token) private pure returns (bytes32) {
        bytes32 outerSlot = keccak256(abi.encode(pool, uint256(7)));
        return keccak256(abi.encode(token, outerSlot));
    }

    // Read the PoolFeeConfig struct for a given pool from the given base slot.
    // Slot layout (forge inspect confirmed):
    //   slot 2 = _poolProtocolSwapFeePercentages
    //   slot 3 = _poolProtocolYieldFeePercentages
    // Struct packing: uint64 feePercentage (bits 0–63), bool isOverride (bit 64).
    function _readPoolFeeConfig(
        uint256 baseSlot,
        address pool
    ) private view returns (uint64 feePercentage, bool isOverride) {
        bytes32 slot = keccak256(abi.encode(pool, baseSlot));
        uint256 packed = uint256(vm.load(address(controller), slot));
        // forge-lint: disable-next-line(unsafe-typecast)
        feePercentage = uint64(packed);
        isOverride = ((packed >> 64) & 1) == 1;
    }

    // ─── Smoke test ────────────────────────────────────────────────────────
    // Verifies that setUp()'s constructor wiring + mock interception + type
    // decoding all work end-to-end. If this test fails, Test Spec 2 and Test
    // Spec 3 cannot proceed — this is the foundation they build on.

    function test_setUp_constructorWiringAndGetAuthorizerMockResolve() public view {
        // 1. The immutable Bodensee pool-identity is what we constructed with.
        assertEq(controller.DER_BODENSEE_POOL(), DER_BODENSEE_POOL_PLACEHOLDER);

        // 1b. The immutable fee-routing hook target (B10 recipient per D-D7).
        assertEq(controller.FEE_ROUTING_HOOK(), FEE_ROUTING_HOOK_PLACEHOLDER);

        // 2. The inherited SingletonAuthentication.getVault() returns the mock
        //    Vault address we passed into the constructor.
        assertEq(address(controller.getVault()), mockVault);

        // 3. Calling getAuthorizer() on the controller follows the full chain:
        //    controller -> SingletonAuthentication.getAuthorizer() ->
        //    getVault().getAuthorizer() -> mocked Vault returns
        //    address(authorizer) -> decoded as IAuthorizer -> compared here.
        //    This one assertion exercises the entire auth-chain resolution
        //    that every governance-gated test in Test Spec 2 depends on.
        assertEq(address(controller.getAuthorizer()), address(authorizer));
    }

    // ─── Divergence tests — Aureum-specific behavior ──────────────────────

    // B10 + constructor

    function test_constructor_revertsOnZeroBodensee() public {
        vm.expectRevert(AureumProtocolFeeController.ZeroBodenseeAddress.selector);
        new AureumProtocolFeeController(IVault(mockVault), address(0), FEE_ROUTING_HOOK_PLACEHOLDER);
    }

    function test_constructor_revertsOnZeroHook() public {
        vm.expectRevert(AureumProtocolFeeController.ZeroHookAddress.selector);
        new AureumProtocolFeeController(IVault(mockVault), DER_BODENSEE_POOL_PLACEHOLDER, address(0));
    }

    function test_withdrawProtocolFees_revertsIfRecipientNotFeeRoutingHook(
        address pool,
        address wrongRecipient
    ) public {
        vm.assume(wrongRecipient != FEE_ROUTING_HOOK_PLACEHOLDER);

        // The authenticate modifier resolves first (calling the real authorizer
        // via the mocked Vault), and we want that check to pass so the fuzzer
        // reaches the Aureum recipient check. Prank as the governance multisig.
        vm.prank(multisig);

        vm.expectRevert(
            abi.encodeWithSelector(
                AureumProtocolFeeController.InvalidRecipient.selector,
                FEE_ROUTING_HOOK_PLACEHOLDER,
                wrongRecipient
            )
        );
        controller.withdrawProtocolFees(pool, wrongRecipient);
    }

    function test_withdrawProtocolFeesForToken_revertsIfRecipientNotFeeRoutingHook(
        address pool,
        address wrongRecipient,
        address token
    ) public {
        vm.assume(wrongRecipient != FEE_ROUTING_HOOK_PLACEHOLDER);

        vm.prank(multisig);

        vm.expectRevert(
            abi.encodeWithSelector(
                AureumProtocolFeeController.InvalidRecipient.selector,
                FEE_ROUTING_HOOK_PLACEHOLDER,
                wrongRecipient
            )
        );
        controller.withdrawProtocolFeesForToken(pool, wrongRecipient, IERC20(token));
    }

    // D-D9: single-pool collectAggregateFees reverts for the Bodensee pool
    function test_collectAggregateFees_revertsOnBodenseePool() public {
        vm.expectRevert(
            AureumProtocolFeeController.BodenseeYieldCollectionDisabled.selector
        );
        controller.collectAggregateFees(DER_BODENSEE_POOL_PLACEHOLDER);
    }

    // Creator-fee revert stubs — all four, all cold, all callers

    function test_setPoolCreatorSwapFeePercentage_revertsAlways(
        address caller,
        address pool,
        uint256 pct
    ) public {
        vm.prank(caller);
        vm.expectRevert(AureumProtocolFeeController.CreatorFeesDisabled.selector);
        controller.setPoolCreatorSwapFeePercentage(pool, pct);
    }

    function test_setPoolCreatorYieldFeePercentage_revertsAlways(
        address caller,
        address pool,
        uint256 pct
    ) public {
        vm.prank(caller);
        vm.expectRevert(AureumProtocolFeeController.CreatorFeesDisabled.selector);
        controller.setPoolCreatorYieldFeePercentage(pool, pct);
    }

    function test_withdrawPoolCreatorFees_poolRecipient_revertsAlways(
        address caller,
        address pool,
        address recipient
    ) public {
        vm.prank(caller);
        vm.expectRevert(AureumProtocolFeeController.CreatorFeesDisabled.selector);
        controller.withdrawPoolCreatorFees(pool, recipient);
    }

    function test_withdrawPoolCreatorFees_pool_revertsAlways(address caller, address pool) public {
        vm.prank(caller);
        vm.expectRevert(AureumProtocolFeeController.CreatorFeesDisabled.selector);
        controller.withdrawPoolCreatorFees(pool);
    }

    // ─── Preservation tests — upstream behavior explicitly kept ───────────

    // Vault-only callback guard on collectAggregateFeesHook

    function test_collectAggregateFeesHook_revertsIfNotVault(address notVault, address pool) public {
        vm.assume(notVault != mockVault);

        vm.prank(notVault);
        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, notVault)
        );
        controller.collectAggregateFeesHook(pool);
    }

    // authenticate modifier on governance-gated protocol fee setters

    function test_setProtocolSwapFeePercentage_revertsForNonGovernance(
        address notGovernance,
        address pool,
        uint256 pct
    ) public {
        vm.assume(notGovernance != multisig);

        vm.prank(notGovernance);
        vm.expectRevert(AureumProtocolFeeController.SplitIsImmutable.selector);
        controller.setProtocolSwapFeePercentage(pool, pct);
    }

    function test_setProtocolYieldFeePercentage_revertsForNonGovernance(
        address notGovernance,
        address pool,
        uint256 pct
    ) public {
        vm.assume(notGovernance != multisig);

        vm.prank(notGovernance);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        controller.setProtocolYieldFeePercentage(pool, pct);
    }

    // ─── Positive-path tests — authenticate + InvalidRecipient bypass ─────

    function test_derBodenseePool_returnsConstructorArgument() public view {
        assertEq(controller.DER_BODENSEE_POOL(), DER_BODENSEE_POOL_PLACEHOLDER);
    }

    function test_withdrawProtocolFees_succeedsForGovernanceOnEmptyPool() public {
        address pool = makeAddr("pool");

        // Mock getPoolTokens(pool) to return an empty array. The loop in
        // withdrawProtocolFees will iterate zero times, _withdrawProtocolFees
        // is never called, the function returns cleanly.
        IERC20[] memory emptyTokens = new IERC20[](0);
        _mockGetPoolTokens(pool, emptyTokens);

        vm.prank(multisig);
        controller.withdrawProtocolFees(pool, FEE_ROUTING_HOOK_PLACEHOLDER);
    }

    function test_withdrawProtocolFees_succeedsForGovernanceOnOneTokenPoolZeroBalance() public {
        address pool = makeAddr("pool");
        IERC20 token = IERC20(makeAddr("token"));

        // Mock getPoolTokens(pool) to return a one-element array with the
        // dummy token. The loop iterates once, calls _withdrawProtocolFees,
        // reads _protocolFeeAmounts[pool][token] which is zero by default,
        // skips the if (amountToWithdraw > 0) block, and returns. No safeTransfer
        // is called, no event is emitted, no mock for the token is needed.
        IERC20[] memory oneTokenArray = new IERC20[](1);
        oneTokenArray[0] = token;
        _mockGetPoolTokens(pool, oneTokenArray);

        vm.prank(multisig);
        controller.withdrawProtocolFees(pool, FEE_ROUTING_HOOK_PLACEHOLDER);
    }

    function test_withdrawProtocolFeesForToken_succeedsForGovernanceWithZeroBalance() public {
        address pool = makeAddr("pool");
        IERC20 token = IERC20(makeAddr("token"));

        // Mock getPoolTokenCountAndIndexOfToken(pool, token) to return (0, 0).
        // Upstream discards the return values — the call exists solely to revert
        // if the pool is unregistered or the token isn't in the pool. A successful
        // mock return just means "pool/token combo is valid, proceed." Then
        // _withdrawProtocolFees reads the zero balance and short-circuits.
        _mockGetPoolTokenCountAndIndexOfToken(pool, token, 0, 0);

        vm.prank(multisig);
        controller.withdrawProtocolFeesForToken(pool, FEE_ROUTING_HOOK_PLACEHOLDER, token);
    }

    // ─── Group A — Nonzero-balance positive-path withdraw ─────────────────

    function test_withdrawProtocolFees_actuallyTransfersToFeeRoutingHook_whenBalanceNonzero() public {
        address pool = makeAddr("pool");
        IERC20 token = IERC20(makeAddr("token"));
        uint256 feeAmount = 12345e18;

        // 1. Mock getPoolTokens so the loop finds one token.
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = token;
        _mockGetPoolTokens(pool, tokens);

        // 2. Write a nonzero balance into _protocolFeeAmounts[pool][token].
        bytes32 slot = _protocolFeeAmountsSlot(pool, token);
        vm.store(address(controller), slot, bytes32(feeAmount));

        // 3. Sanity-check the write landed in the expected slot.
        uint256 storedAmount = uint256(vm.load(address(controller), slot));
        assertEq(storedAmount, feeAmount, "vm.store write did not land in the expected slot");

        // 4. Mock the token's transfer so SafeERC20.safeTransfer succeeds.
        _mockSafeTransfer(token);

        // 5. Record logs to verify the event and recipient after the call.
        vm.recordLogs();

        // 6. Call from governance with recipient == FEE_ROUTING_HOOK (B10 target per D-D7).
        vm.prank(multisig);
        controller.withdrawProtocolFees(pool, FEE_ROUTING_HOOK_PLACEHOLDER);

        // 7. Verify storage was zeroed (controller zeros before transferring).
        uint256 storedAmountAfter = uint256(vm.load(address(controller), slot));
        assertEq(storedAmountAfter, 0, "Storage should be zeroed after withdraw");

        // 8. Verify ProtocolFeesWithdrawn event with correct recipient and amount.
        //    Event: ProtocolFeesWithdrawn(address indexed pool, IERC20 indexed token,
        //                                 address indexed recipient, uint256 amount)
        //    topic[0] = sig hash, topic[1] = pool, topic[2] = token, topic[3] = recipient
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics.length == 4 &&
                logs[i].topics[0] ==
                keccak256("ProtocolFeesWithdrawn(address,address,address,uint256)")
            ) {
                address recipient = address(uint160(uint256(logs[i].topics[3])));
                assertEq(
                    recipient,
                    FEE_ROUTING_HOOK_PLACEHOLDER,
                    "ProtocolFeesWithdrawn event recipient should be FEE_ROUTING_HOOK"
                );
                uint256 emittedAmount = abi.decode(logs[i].data, (uint256));
                assertEq(emittedAmount, feeAmount, "Emitted amount should match the original fee amount");
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "ProtocolFeesWithdrawn event was not emitted");
    }

    // ─── Group B — Fee-setter happy path: cap acceptance + cap rejection ──

    function test_setProtocolYieldFeePercentage_acceptsCapValue() public {
        address pool = makeAddr("pool");
        uint256 capValue = controller.MAX_PROTOCOL_YIELD_FEE_PERCENTAGE();

        _mockUnlock();
        _mockUpdateAggregateYieldFeePercentage();

        vm.prank(multisig);
        controller.setProtocolYieldFeePercentage(pool, capValue);

        (uint64 storedPct, bool isOverride) = _readPoolFeeConfig(3, pool);
        assertEq(uint256(storedPct), capValue, "Stored yield fee percentage should equal cap");
        assertTrue(isOverride, "isOverride should be true for governance-set fee");
    }

    function test_setProtocolYieldFeePercentage_revertsAtCapPlusScalingFactor() public {
        address pool = makeAddr("pool");
        uint256 aboveCap = controller.MAX_PROTOCOL_YIELD_FEE_PERCENTAGE() + 1e11;

        vm.prank(multisig);
        vm.expectRevert();
        controller.setProtocolYieldFeePercentage(pool, aboveCap);
    }

    // ─── Group D — D-D15 retrofit coverage (split-is-immutable + pin) ─────
    function test_constructor_pinsGlobalSwapFeePercentageAtCap() public view {
        assertEq(
            controller.getGlobalProtocolSwapFeePercentage(),
            controller.MAX_PROTOCOL_SWAP_FEE_PERCENTAGE(),
            "Global protocol swap-fee percentage should be pinned to the cap"
        );
    }
    function test_setGlobalProtocolSwapFeePercentage_revertsForGovernance(uint256 pct) public {
        vm.prank(multisig);
        vm.expectRevert(AureumProtocolFeeController.SplitIsImmutable.selector);
        controller.setGlobalProtocolSwapFeePercentage(pct);
    }
    function test_setGlobalProtocolSwapFeePercentage_revertsForNonGovernance(
        address caller,
        uint256 pct
    ) public {
        vm.assume(caller != multisig);
        vm.prank(caller);
        vm.expectRevert(AureumProtocolFeeController.SplitIsImmutable.selector);
        controller.setGlobalProtocolSwapFeePercentage(pct);
    }
    function test_setProtocolSwapFeePercentage_revertsForGovernance(address pool, uint256 pct) public {
        vm.prank(multisig);
        vm.expectRevert(AureumProtocolFeeController.SplitIsImmutable.selector);
        controller.setProtocolSwapFeePercentage(pool, pct);
    }
    function test_registerPool_pinsSwapFeeEvenWhenExempt(address pool, address poolCreator) public {
        vm.assume(pool != address(0));
        vm.prank(mockVault);
        (uint256 aggregateSwapFee, uint256 aggregateYieldFee) =
            controller.registerPool(pool, poolCreator, true);
        // Swap-side: pinned to the global regardless of the exempt flag. This closes
        // the factory-level bypass where `protocolFeeExempt = true` would have zeroed
        // the pool's swap fee and circumvented the 50/50 split.
        assertEq(aggregateSwapFee, controller.MAX_PROTOCOL_SWAP_FEE_PERCENTAGE());
        // Yield-side: the exempt flag still zeros the yield fee (D-D9 preserved).
        assertEq(aggregateYieldFee, 0);
        // Storage: swap-side isOverride is false (pinned = canonical); yield-side is
        // true because the exempt flag sticks on the yield side.
        (uint256 storedSwapPct, bool swapIsOverride) = controller.getPoolProtocolSwapFeeInfo(pool);
        assertEq(storedSwapPct, controller.MAX_PROTOCOL_SWAP_FEE_PERCENTAGE());
        assertFalse(swapIsOverride);
        (uint256 storedYieldPct, bool yieldIsOverride) = controller.getPoolProtocolYieldFeeInfo(pool);
        assertEq(storedYieldPct, 0);
        assertTrue(yieldIsOverride);
    }
    function test_registerPool_pinsSwapFeeWhenNotExempt(address pool, address poolCreator) public {
        vm.assume(pool != address(0));
        vm.prank(mockVault);
        (uint256 aggregateSwapFee, uint256 aggregateYieldFee) =
            controller.registerPool(pool, poolCreator, false);
        assertEq(aggregateSwapFee, controller.MAX_PROTOCOL_SWAP_FEE_PERCENTAGE());
        // _globalProtocolYieldFeePercentage is unpinned (Stage D does not touch yield);
        // default is 0 for the non-exempt path as well.
        assertEq(aggregateYieldFee, 0);
        (uint256 storedSwapPct, bool swapIsOverride) = controller.getPoolProtocolSwapFeeInfo(pool);
        assertEq(storedSwapPct, controller.MAX_PROTOCOL_SWAP_FEE_PERCENTAGE());
        assertFalse(swapIsOverride);
        (uint256 storedYieldPct, bool yieldIsOverride) = controller.getPoolProtocolYieldFeeInfo(pool);
        assertEq(storedYieldPct, 0);
        assertFalse(yieldIsOverride);
    }
    // ─── Group C — Invariants ─────────────────────────────────────────────

    // Invariant 1: Creator-fee percentage storage is always zero.
    // _poolCreatorSwapFeePercentages → slot 5, _poolCreatorYieldFeePercentages → slot 6
    function invariant_creatorFeeStorageIsAlwaysZero() public view {
        uint256 numPools = handler.touchedPoolsLength();
        for (uint256 i = 0; i < numPools; i++) {
            address pool = handler.touchedPools(i);
            bytes32 swapSlot = keccak256(abi.encode(pool, uint256(5)));
            bytes32 yieldSlot = keccak256(abi.encode(pool, uint256(6)));
            assertEq(
                uint256(vm.load(address(controller), swapSlot)),
                0,
                "Creator swap fee percentage was nonzero for a touched pool"
            );
            assertEq(
                uint256(vm.load(address(controller), yieldSlot)),
                0,
                "Creator yield fee percentage was nonzero for a touched pool"
            );
        }
    }

    // Invariant 2: Creator-fee balances are always zero.
    // _poolCreatorFeeAmounts → slot 8 (nested mapping; checks address(0) token — intentionally narrow)
    function invariant_creatorFeeBalancesAreAlwaysZero() public view {
        uint256 numPools = handler.touchedPoolsLength();
        for (uint256 i = 0; i < numPools; i++) {
            address pool = handler.touchedPools(i);
            bytes32 outerSlot = keccak256(abi.encode(pool, uint256(8)));
            bytes32 innerSlot = keccak256(abi.encode(address(0), outerSlot));
            assertEq(
                uint256(vm.load(address(controller), innerSlot)),
                0,
                "Creator fee balance was nonzero for a touched pool"
            );
        }
    }

    // Invariant 3: Protocol fee percentages are always within cap.
    // _poolProtocolSwapFeePercentages → slot 2, _poolProtocolYieldFeePercentages → slot 3
    // PoolFeeConfig packs uint64 feePercentage in the low 64 bits of the slot.
    function invariant_protocolFeePercentagesAlwaysWithinCap() public view {
        uint256 capSwap = controller.MAX_PROTOCOL_SWAP_FEE_PERCENTAGE();
        uint256 capYield = controller.MAX_PROTOCOL_YIELD_FEE_PERCENTAGE();

        uint256 numPools = handler.touchedPoolsLength();
        for (uint256 i = 0; i < numPools; i++) {
            address pool = handler.touchedPools(i);

            bytes32 swapSlot = keccak256(abi.encode(pool, uint256(2)));
            uint64 swapFee = uint64(uint256(vm.load(address(controller), swapSlot)));
            assertLe(uint256(swapFee), capSwap, "Protocol swap fee exceeded cap");

            bytes32 yieldSlot = keccak256(abi.encode(pool, uint256(3)));
            uint64 yieldFee = uint64(uint256(vm.load(address(controller), yieldSlot)));
            assertLe(uint256(yieldFee), capYield, "Protocol yield fee exceeded cap");
        }
    }

    // Invariant 4: Every successful withdrawal targeted FEE_ROUTING_HOOK (D-D7 B10 target).
    // The handler only appends to successfulWithdrawRecipients when withdrawProtocolFees
    // completes without reverting, proving B10 routing end-to-end.
    function invariant_allWithdrawalsTargetFeeRoutingHook() public view {
        uint256 num = handler.successfulWithdrawRecipientsLength();
        for (uint256 i = 0; i < num; i++) {
            assertEq(
                handler.successfulWithdrawRecipients(i),
                FEE_ROUTING_HOOK_PLACEHOLDER,
                "A successful withdraw targeted a non-hook recipient"
            );
        }
    }

    // ─── Group E — D4 additions (FEE_ROUTING_HOOK immutable, OQ-11 bands) ──

    function test_B10_TargetIsHookAddress() public view {
        // Dedicated coverage for the FEE_ROUTING_HOOK immutable: the B10
        // withdrawal-recipient guard targets the fee-routing hook, not
        // der Bodensee directly. Two-immutables shape per STAGE_D_NOTES D23.
        assertEq(controller.FEE_ROUTING_HOOK(), FEE_ROUTING_HOOK_PLACEHOLDER);
    }

    function test_SwapFeeConstants() public view {
        // OQ-11 superseded 2026-04-26 (E-D22): Bodensee fee is immutable at 0.75%
        // (no band, no governance lever); Miliarium genesis 0.02% within 0.01%–0.30% band.
        // Canonical per docs/FINDINGS.md OQ-11 and docs/STAGE_E_NOTES.md E-D22.
        assertEq(controller.BODENSEE_SWAP_FEE(),          0.0075e18, "Bodensee 0.75% immutable");
        assertEq(controller.MILIARIUM_SWAP_FEE_MIN(),     0.0001e18, "Miliarium MIN 0.01%");
        assertEq(controller.MILIARIUM_SWAP_FEE_MAX(),     0.003e18,  "Miliarium MAX 0.30%");
        assertEq(controller.MILIARIUM_SWAP_FEE_GENESIS(), 0.0002e18, "Miliarium GENESIS 0.02%");
    }

    // ─── Group F — D4.7b β1 swap-leg forward (controller-side) ──────────

    function test_collectSwapAggregateFeesForHook_revertsOnNonHookCaller(
        address attacker,
        address pool
    ) public {
        vm.assume(attacker != FEE_ROUTING_HOOK_PLACEHOLDER);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAureumProtocolFeeControllerHookExtension.OnlyFeeRoutingHook.selector,
                attacker
            )
        );
        controller.collectSwapAggregateFeesForHook(pool);
    }

    function test_collectAggregateFeesHookSwapForward_zeroAmountShortCircuit() public {
        address pool = makeAddr("poolZero");
        IERC20 tokenA = IERC20(makeAddr("tokenA"));
        IERC20 tokenB = IERC20(makeAddr("tokenB"));

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        _mockGetPoolTokens(pool, tokens);

        uint256[] memory zeros = new uint256[](2);
        _mockCollectAggregateFees(pool, zeros, zeros);
        _mockSendToAny();

        vm.recordLogs();

        vm.prank(mockVault);
        (IERC20[] memory retTokens, uint256[] memory forwardedAmounts) =
            controller.collectAggregateFeesHookSwapForward(pool);

        assertEq(retTokens.length, 2, "retTokens length");
        assertEq(address(retTokens[0]), address(tokenA), "retTokens[0]");
        assertEq(address(retTokens[1]), address(tokenB), "retTokens[1]");
        assertEq(forwardedAmounts.length, 2, "forwardedAmounts length");
        assertEq(forwardedAmounts[0], 0, "forwardedAmounts[0]");
        assertEq(forwardedAmounts[1], 0, "forwardedAmounts[1]");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sigSwapLeg = keccak256("SwapLegFeeForwarded(address,address,uint256)");
        bytes32 sigYield   = keccak256("ProtocolYieldFeeCollected(address,address,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0) {
                assertTrue(
                    logs[i].topics[0] != sigSwapLeg,
                    "SwapLegFeeForwarded must not fire on zero-amount path"
                );
                assertTrue(
                    logs[i].topics[0] != sigYield,
                    "ProtocolYieldFeeCollected must not fire on zero-amount path"
                );
            }
        }
    }

    function test_collectAggregateFeesHookSwapForward_nonZeroForward() public {
        address pool = makeAddr("poolForward");
        IERC20 tokenA = IERC20(makeAddr("tokenAFwd"));
        IERC20 tokenB = IERC20(makeAddr("tokenBFwd"));

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        _mockGetPoolTokens(pool, tokens);

        uint256[] memory swapFees = new uint256[](2);
        swapFees[0] = 100e18;
        swapFees[1] = 200e18;
        uint256[] memory yieldZeros = new uint256[](2);
        _mockCollectAggregateFees(pool, swapFees, yieldZeros);
        _mockSendToAny();

        vm.expectCall(
            mockVault,
            abi.encodeWithSelector(
                IVaultMain.sendTo.selector,
                tokenA,
                FEE_ROUTING_HOOK_PLACEHOLDER,
                uint256(100e18)
            )
        );
        vm.expectCall(
            mockVault,
            abi.encodeWithSelector(
                IVaultMain.sendTo.selector,
                tokenB,
                FEE_ROUTING_HOOK_PLACEHOLDER,
                uint256(200e18)
            )
        );

        vm.recordLogs();

        vm.prank(mockVault);
        (IERC20[] memory retTokens, uint256[] memory forwardedAmounts) =
            controller.collectAggregateFeesHookSwapForward(pool);

        assertEq(forwardedAmounts[0], 100e18, "forwardedAmounts[0]");
        assertEq(forwardedAmounts[1], 200e18, "forwardedAmounts[1]");
        assertEq(address(retTokens[0]), address(tokenA), "retTokens[0]");

        // Invariant 1: swap leg never credits _protocolFeeAmounts.
        assertEq(
            uint256(vm.load(address(controller), _protocolFeeAmountsSlot(pool, tokenA))),
            0,
            "swap leg must not credit _protocolFeeAmounts[pool][tokenA]"
        );
        assertEq(
            uint256(vm.load(address(controller), _protocolFeeAmountsSlot(pool, tokenB))),
            0,
            "swap leg must not credit _protocolFeeAmounts[pool][tokenB]"
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sigSwapLeg = keccak256("SwapLegFeeForwarded(address,address,uint256)");
        uint256 swapLegCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 3 && logs[i].topics[0] == sigSwapLeg) {
                swapLegCount++;
            }
        }
        assertEq(swapLegCount, 2, "exactly 2 SwapLegFeeForwarded events expected");
    }

    function test_collectAggregateFeesHookSwapForward_yieldLegUntouched() public {
        address pool = makeAddr("poolYield");
        IERC20 token = IERC20(makeAddr("tokenYield"));

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = token;
        _mockGetPoolTokens(pool, tokens);

        uint256[] memory swapZeros = new uint256[](1);
        uint256[] memory yieldFees = new uint256[](1);
        yieldFees[0] = 50e18;
        _mockCollectAggregateFees(pool, swapZeros, yieldFees);
        _mockSendToAny();

        // Yield-leg invariant: existing _receiveAggregateFees path must
        // sendTo(token, address(controller), 50e18).
        vm.expectCall(
            mockVault,
            abi.encodeWithSelector(
                IVaultMain.sendTo.selector,
                token,
                address(controller),
                uint256(50e18)
            )
        );

        vm.recordLogs();

        vm.prank(mockVault);
        (, uint256[] memory forwardedAmounts) =
            controller.collectAggregateFeesHookSwapForward(pool);

        assertEq(forwardedAmounts[0], 0, "swap-side forwardedAmount must be 0");

        // Yield leg credits _protocolFeeAmounts[pool][token].
        assertEq(
            uint256(vm.load(address(controller), _protocolFeeAmountsSlot(pool, token))),
            50e18,
            "yield leg must credit _protocolFeeAmounts[pool][token]"
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sigSwapLeg = keccak256("SwapLegFeeForwarded(address,address,uint256)");
        bytes32 sigYield   = keccak256("ProtocolYieldFeeCollected(address,address,uint256)");
        uint256 swapLegCount = 0;
        uint256 yieldCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0) {
                if (logs[i].topics[0] == sigSwapLeg) swapLegCount++;
                if (logs[i].topics[0] == sigYield)   yieldCount++;
            }
        }
        assertEq(swapLegCount, 0, "no SwapLegFeeForwarded on zero-swap path");
        assertEq(yieldCount,   1, "exactly 1 ProtocolYieldFeeCollected event expected");
    }

    function test_collectAggregateFeesHookSwapForward_emitsSwapLegFeeForwardedPerNonZeroToken() public {
        address pool = makeAddr("poolMixed");
        IERC20 tokenA = IERC20(makeAddr("tokenAMixed"));
        IERC20 tokenB = IERC20(makeAddr("tokenBMixed"));
        IERC20 tokenC = IERC20(makeAddr("tokenCMixed"));

        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        tokens[2] = tokenC;
        _mockGetPoolTokens(pool, tokens);

        uint256[] memory swapFees = new uint256[](3);
        swapFees[0] = 100e18;
        swapFees[1] = 0;
        swapFees[2] = 200e18;
        uint256[] memory yieldZeros = new uint256[](3);
        _mockCollectAggregateFees(pool, swapFees, yieldZeros);
        _mockSendToAny();

        // Only the two non-zero tokens get sendTo calls; tokenB at index 1
        // is skipped entirely (no sendTo, no event).
        vm.expectCall(
            mockVault,
            abi.encodeWithSelector(
                IVaultMain.sendTo.selector,
                tokenA,
                FEE_ROUTING_HOOK_PLACEHOLDER,
                uint256(100e18)
            )
        );
        vm.expectCall(
            mockVault,
            abi.encodeWithSelector(
                IVaultMain.sendTo.selector,
                tokenC,
                FEE_ROUTING_HOOK_PLACEHOLDER,
                uint256(200e18)
            )
        );

        vm.recordLogs();

        vm.prank(mockVault);
        (, uint256[] memory forwardedAmounts) =
            controller.collectAggregateFeesHookSwapForward(pool);

        assertEq(forwardedAmounts[0], 100e18, "forwardedAmounts[0]");
        assertEq(forwardedAmounts[1], 0,      "forwardedAmounts[1] must stay 0");
        assertEq(forwardedAmounts[2], 200e18, "forwardedAmounts[2]");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sigSwapLeg = keccak256("SwapLegFeeForwarded(address,address,uint256)");
        uint256 swapLegCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 3 && logs[i].topics[0] == sigSwapLeg) {
                // topics[2] is the indexed token. Confirm tokenB is never
                // the subject of an emission.
                address emittedToken = address(uint160(uint256(logs[i].topics[2])));
                assertTrue(
                    emittedToken != address(tokenB),
                    "tokenB must not be subject of any SwapLegFeeForwarded"
                );
                swapLegCount++;
            }
        }
        assertEq(swapLegCount, 2, "exactly 2 SwapLegFeeForwarded events expected");
    }

    // ─── Group — routeYieldFeeToHook (OQ-20 entry point + OQ-21 throttle) ──

    function _mockHookRouteReturns(uint256 bptMinted) internal {
        vm.mockCall(
            FEE_ROUTING_HOOK_PLACEHOLDER,
            abi.encodeWithSelector(IAureumFeeRoutingHook.routeYieldFee.selector),
            abi.encode(bptMinted)
        );
    }

    function _mockTokenApprove(IERC20 token) internal {
        // forceApprove calls approve(spender, value); OZ 5.x _callOptionalReturnBool
        // gates on returndata (32 bytes == true) before any code-length check, so a
        // codeless mocked token approves cleanly. See the withdraw-path precedent.
        vm.mockCall(
            address(token),
            abi.encodeWithSelector(IERC20.approve.selector),
            abi.encode(true)
        );
    }

    // E.4 (PP-D48 (i)): the routed amount is READ from the controller's ledger rather
    // than passed, so every route these tests drive must first credit
    // `_protocolFeeAmounts[pool][token]`. A SUCCESSFUL route zeroes that slot, so a test
    // routing twice seeds twice; a REVERTING route unwinds the zeroing and needs no
    // reseed, which is why the negative legs below re-use the credit already in place.
    function _seedLedger(address pool, IERC20 token, uint256 amount) private {
        vm.store(address(controller), _protocolFeeAmountsSlot(pool, token), bytes32(amount));
    }

    function test_routeYieldFeeToHook_revertsForNonKeeperNonSafe(address notAdmissible) public {
        vm.assume(notAdmissible != multisig);
        // address(0) is excluded because with no keeper seated the slot is zero, so a
        // pranked zero sender would match it. `msg.sender` is never zero on chain, which
        // is why the contract carries no explicit guard for it.
        vm.assume(notAdmissible != address(0));
        address pool = makeAddr("pool");
        IERC20 token = IERC20(makeAddr("token"));
        // The caller check runs BEFORE the throttle, so an inadmissible caller sees
        // NotYieldRouteKeeper rather than RouteThrottled, and needs no roll or seed.
        vm.prank(notAdmissible);
        vm.expectRevert(
            abi.encodeWithSelector(
                AureumProtocolFeeController.NotYieldRouteKeeper.selector,
                notAdmissible
            )
        );
        controller.routeYieldFeeToHook(pool, token, 0);
    }

    function test_routeYieldFeeToHook_throttleRevertsWithinEpoch() public {
        address pool = makeAddr("pool");
        IERC20 token = IERC20(makeAddr("token"));
        _mockTokenApprove(token);
        _mockHookRouteReturns(1e18);

        // The throttle has no zero-special-case: block.number must be >= BLOCKS_PER_EPOCH
        // for the first-ever route to clear `block.number < 0 + BLOCKS_PER_EPOCH`.
        vm.roll(AureumTime.BLOCKS_PER_EPOCH * 100);
        _seedLedger(pool, token, 5e18);
        vm.prank(multisig);
        controller.routeYieldFeeToHook(pool, token, 0);

        // One block short of a full epoch later: throttled. The throttle is checked
        // before the ledger read, so the negative leg needs no fresh credit.
        vm.roll(block.number + AureumTime.BLOCKS_PER_EPOCH - 1);
        vm.prank(multisig);
        vm.expectRevert(AureumProtocolFeeController.RouteThrottled.selector);
        controller.routeYieldFeeToHook(pool, token, 0);
    }

    function test_routeYieldFeeToHook_succeedsAtEpochBoundary() public {
        address pool = makeAddr("pool");
        IERC20 token = IERC20(makeAddr("token"));
        _mockTokenApprove(token);
        _mockHookRouteReturns(1e18);

        vm.roll(AureumTime.BLOCKS_PER_EPOCH * 100);
        _seedLedger(pool, token, 5e18);
        vm.prank(multisig);
        controller.routeYieldFeeToHook(pool, token, 0);

        // Exactly one epoch later: gate is `block.number < last + EPOCH`, so == passes.
        // The first route consumed the credit, so the boundary route needs its own.
        vm.roll(block.number + AureumTime.BLOCKS_PER_EPOCH);
        _seedLedger(pool, token, 5e18);
        vm.prank(multisig);
        uint256 bpt = controller.routeYieldFeeToHook(pool, token, 0);
        assertEq(bpt, 1e18, "boundary route should succeed and propagate bptMinted");
    }

    function test_routeYieldFeeToHook_stampNotAdvancedOnHookRevert() public {
        address pool = makeAddr("pool");
        IERC20 token = IERC20(makeAddr("token"));
        _mockTokenApprove(token);
        _mockHookRouteReturns(1e18);

        vm.roll(AureumTime.BLOCKS_PER_EPOCH * 100);
        _seedLedger(pool, token, 5e18);
        vm.prank(multisig);
        controller.routeYieldFeeToHook(pool, token, 0);
        uint256 stampBlock = block.number;

        // One epoch later the throttle passes, but the hook reverts.
        vm.roll(stampBlock + AureumTime.BLOCKS_PER_EPOCH);
        _seedLedger(pool, token, 5e18);
        vm.mockCallRevert(
            FEE_ROUTING_HOOK_PLACEHOLDER,
            abi.encodeWithSelector(IAureumFeeRoutingHook.routeYieldFee.selector),
            bytes("hook reverted")
        );
        vm.prank(multisig);
        vm.expectRevert(bytes("hook reverted"));
        controller.routeYieldFeeToHook(pool, token, 0);

        // Same block, hook restored: succeeds — proving the failed attempt did not
        // advance the stamp (else this same-block retry would revert RouteThrottled).
        // The reverted attempt also unwound its own debit, so the credit is still there.
        _mockHookRouteReturns(2e18);
        vm.prank(multisig);
        uint256 bpt = controller.routeYieldFeeToHook(pool, token, 0);
        assertEq(bpt, 2e18, "same-block retry after hook revert should succeed");
    }

    function test_routeYieldFeeToHook_approvesHookAndPropagatesBptMinted() public {
        address pool = makeAddr("pool");
        IERC20 token = IERC20(makeAddr("token"));
        uint256 amount = 7e18;
        _mockTokenApprove(token);
        _mockHookRouteReturns(42e18);

        vm.roll(AureumTime.BLOCKS_PER_EPOCH * 100);
        _seedLedger(pool, token, amount);

        // The approval and the hook call both carry the LEDGER credit, which no caller
        // supplied — that flow is E.4's fix. The fifth argument is the hardcoded 0.
        vm.expectCall(
            address(token),
            abi.encodeCall(IERC20.approve, (FEE_ROUTING_HOOK_PLACEHOLDER, amount))
        );
        vm.expectCall(
            FEE_ROUTING_HOOK_PLACEHOLDER,
            abi.encodeCall(IAureumFeeRoutingHook.routeYieldFee, (pool, token, amount, 0, 0))
        );
        vm.prank(multisig);
        uint256 bpt = controller.routeYieldFeeToHook(pool, token, 0);
        assertEq(bpt, 42e18, "bptMinted from the hook should be propagated");
        assertEq(
            uint256(vm.load(address(controller), _protocolFeeAmountsSlot(pool, token))),
            0,
            "the routed credit was not debited from the ledger"
        );
    }

    function test_routeYieldFeeToHook_forwardsBoundsToHook() public {
        address pool = makeAddr("pool");
        IERC20 token = IERC20(makeAddr("token"));
        _mockTokenApprove(token);
        _mockHookRouteReturns(42e18);

        vm.roll(AureumTime.BLOCKS_PER_EPOCH * 100);
        _seedLedger(pool, token, 7e18);

        // minDepositTokenOut is forwarded; the BPT floor is no longer a parameter and
        // is pinned to 0, since PB-D68 (xiv) makes any non-zero floor unsatisfiable.
        vm.expectCall(
            FEE_ROUTING_HOOK_PLACEHOLDER,
            abi.encodeCall(IAureumFeeRoutingHook.routeYieldFee, (pool, token, 7e18, 5e17, 0))
        );
        vm.prank(multisig);
        uint256 bpt = controller.routeYieldFeeToHook(pool, token, 5e17);
        assertEq(bpt, 42e18);
    }

    function test_routeYieldFeeToHook_stampNotAdvancedOnBoundRevert() public {
        address pool = makeAddr("pool");
        IERC20 token = IERC20(makeAddr("token"));
        _mockTokenApprove(token);
        _mockHookRouteReturns(1e18);

        vm.roll(AureumTime.BLOCKS_PER_EPOCH * 100);
        _seedLedger(pool, token, 5e18);
        vm.prank(multisig);
        controller.routeYieldFeeToHook(pool, token, 5e17);
        uint256 stampBlock = block.number;

        vm.roll(stampBlock + AureumTime.BLOCKS_PER_EPOCH);
        _seedLedger(pool, token, 5e18);
        bytes memory revertData = abi.encodeWithSelector(
            IVaultErrors.SwapLimit.selector,
            uint256(1e18),
            uint256(2e18)
        );
        vm.mockCallRevert(
            FEE_ROUTING_HOOK_PLACEHOLDER,
            abi.encodeWithSelector(IAureumFeeRoutingHook.routeYieldFee.selector),
            revertData
        );
        vm.prank(multisig);
        vm.expectRevert(revertData);
        controller.routeYieldFeeToHook(pool, token, 5e17);

        _mockHookRouteReturns(2e18);
        vm.prank(multisig);
        uint256 bpt = controller.routeYieldFeeToHook(pool, token, 5e17);
        assertEq(bpt, 2e18, "same-block retry after bound revert should succeed");
    }

    // ─── Group — the PP-D48 clause (v) keeper surface ──────────────────────

    function test_setYieldRouteKeeper_seatsRotatesAndEmits() public {
        address keeper = makeAddr("keeper");
        address successor = makeAddr("successor");
        assertEq(controller.yieldRouteKeeper(), address(0), "precondition: no keeper seated");

        vm.expectEmit(true, true, false, false, address(controller));
        emit AureumProtocolFeeController.YieldRouteKeeperChanged(address(0), keeper);
        vm.prank(multisig);
        controller.setYieldRouteKeeper(keeper);
        assertEq(controller.yieldRouteKeeper(), keeper, "keeper was not seated");

        // Decision (b): ROTATABLE, never one-shot. A second call must succeed, or a
        // compromised keeper would be permanent and the route effectively dead.
        vm.expectEmit(true, true, false, false, address(controller));
        emit AureumProtocolFeeController.YieldRouteKeeperChanged(keeper, successor);
        vm.prank(multisig);
        controller.setYieldRouteKeeper(successor);
        assertEq(controller.yieldRouteKeeper(), successor, "keeper did not rotate");
    }

    function test_setYieldRouteKeeper_revertsForNonAuthority(address stranger) public {
        vm.assume(stranger != multisig);
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(AureumProtocolFeeController.NotKeeperAuthority.selector, stranger)
        );
        controller.setYieldRouteKeeper(makeAddr("keeper"));
    }

    function test_setYieldRouteKeeper_revertsWhenSafeUnseated() public {
        // Decision (c) fails CLOSED: before the hook's one-shot setGovernanceModule
        // fires there is no authority, so not even the multisig may seat a keeper.
        vm.mockCall(
            FEE_ROUTING_HOOK_PLACEHOLDER,
            abi.encodeWithSelector(IAureumFeeRoutingHook.governanceModule.selector),
            abi.encode(address(0))
        );
        vm.prank(multisig);
        vm.expectRevert(
            abi.encodeWithSelector(AureumProtocolFeeController.NotKeeperAuthority.selector, multisig)
        );
        controller.setYieldRouteKeeper(makeAddr("keeper"));
    }

    function test_routeYieldFeeToHook_seatedKeeperMayRoute() public {
        address keeper = makeAddr("keeper");
        address pool = makeAddr("pool");
        IERC20 token = IERC20(makeAddr("token"));
        vm.prank(multisig);
        controller.setYieldRouteKeeper(keeper);

        _mockTokenApprove(token);
        _mockHookRouteReturns(3e18);
        vm.roll(AureumTime.BLOCKS_PER_EPOCH * 100);
        _seedLedger(pool, token, 5e18);

        // The keeper is neither the multisig nor authenticate-permitted; it routes
        // purely on the seated slot, which is the leg clause (v) exists to create.
        vm.prank(keeper);
        uint256 bpt = controller.routeYieldFeeToHook(pool, token, 0);
        assertEq(bpt, 3e18, "seated keeper could not route");
    }

    function test_setYieldRouteKeeper_zeroDisablesKeeperLegAndSafeStillRoutes() public {
        address keeper = makeAddr("keeper");
        address pool = makeAddr("pool");
        IERC20 token = IERC20(makeAddr("token"));
        vm.prank(multisig);
        controller.setYieldRouteKeeper(keeper);
        vm.prank(multisig);
        controller.setYieldRouteKeeper(address(0));
        assertEq(controller.yieldRouteKeeper(), address(0), "keeper leg was not disabled");

        _mockTokenApprove(token);
        _mockHookRouteReturns(4e18);
        vm.roll(AureumTime.BLOCKS_PER_EPOCH * 100);
        _seedLedger(pool, token, 5e18);

        // The retired keeper is now inadmissible ...
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(AureumProtocolFeeController.NotYieldRouteKeeper.selector, keeper)
        );
        controller.routeYieldFeeToHook(pool, token, 0);

        // ... while the Safe fallback keeps the skim reachable, which is why a zero
        // keeper is a valve rather than a brick.
        vm.prank(multisig);
        uint256 bpt = controller.routeYieldFeeToHook(pool, token, 0);
        assertEq(bpt, 4e18, "Safe fallback could not route with the keeper leg disabled");
    }
}
