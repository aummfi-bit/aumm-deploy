# Tests

This directory contains the test suite for `aumm-deploy`. Each test file mirrors a contract in `src/` (or in some cases, exercises a deployment integration). Tests are organized into `unit/` (no external chain calls, mocked dependencies) and `fork/` (run against a forked mainnet RPC).

## Test files

| File | Tests | Kind | Targets |
|---|---|---|---|
| `unit/AureumAuthorizer.t.sol` | 4 | Unit | `src/AureumAuthorizer.sol` |
| `unit/AureumProtocolFeeController.t.sol` | 24 named tests + 4 invariants | Unit | `src/AureumProtocolFeeController.sol` |
| `fork/Sanity.t.sol` | 1 | Fork | Toolchain wiring (Stage A) |

Total as of B4: **29 named tests + 4 invariants** across the three files.

## What the tests prove

The `AureumProtocolFeeController.t.sol` test suite is the largest and the most consequential — it's the test surface for Aureum's most divergent contract from upstream Balancer V3. Reading the tests with audit eyes, here are the structural properties they demonstrate:

**Routing — B10 (the protocol fee destination is hardwired):**
- Wrong-recipient withdraws revert with `InvalidRecipient(DER_BODENSEE_POOL, recipient)` for any recipient other than `DER_BODENSEE_POOL`. Fuzzed at 1024 runs across the full `address` space.
- Right-recipient withdraws actually transfer to `DER_BODENSEE_POOL` at the bytecode level. The nonzero-balance test writes a value into `_protocolFeeAmounts[pool][token]` storage via `vm.store`, calls `withdrawProtocolFees` from governance with `recipient == DER_BODENSEE_POOL`, and asserts the `ProtocolFeesWithdrawn` event has the Bodensee address in its indexed recipient field. This is the only test in the suite that proves money actually moves to the right place; everything else proves money does not move to wrong places.
- *Lives in:* `test_withdrawProtocolFees_revertsIfRecipientNotBodensee`, `test_withdrawProtocolFeesForToken_revertsIfRecipientNotBodensee`, `test_withdrawProtocolFees_actuallyTransfersToBodensee_whenBalanceNonzero`.

**Creator fees are structurally impossible — B19 (modifier-stripped revert stubs):**
- All four creator-fee functions (`setPoolCreatorSwapFeePercentage`, `setPoolCreatorYieldFeePercentage`, both `withdrawPoolCreatorFees` overloads) revert unconditionally with `CreatorFeesDisabled()` for any caller, any pool, any percentage, any recipient. Fuzzed at 1024 runs each.
- The reverts happen *cold* — the function bodies are exactly `revert CreatorFeesDisabled();` with no modifier preamble, so no Vault state, no caller identity, and no on-chain condition can mask the revert. Confirmed empirically by the gas numbers (~9.4k gas per call = bare dispatch + revert with nothing else in between).
- The invariant suite drives 32,768 random calls per invariant against the four creator-fee functions plus the withdraw functions, and after every call sequence asserts that the creator-fee storage mappings (`_poolCreatorSwapFeePercentages`, `_poolCreatorYieldFeePercentages`, `_poolCreatorFeeAmounts`) are still zero for every pool and token the handler touched. This is the structural impossibility verified across 131,072 random fuzz calls per run.
- *Lives in:* `test_setPoolCreator{Swap,Yield}FeePercentage_revertsAlways`, `test_withdrawPoolCreatorFees_*_revertsAlways`, `invariant_creatorFeeStorageIsAlwaysZero`, `invariant_creatorFeeBalancesAreAlwaysZero`.

**Cap enforcement is preserved — upstream `withValidSwapFee` and `withValidYieldFee` modifiers:**
- Setting the protocol swap fee at exactly `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE` (50e16 = 50%) succeeds and the value is correctly written to storage as a packed `PoolFeeConfig` struct.
- Setting the protocol swap fee at `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE + FEE_SCALING_FACTOR` reverts. The increment is one `FEE_SCALING_FACTOR` (1e11) above the cap, chosen specifically so the precision check (`_ensureValidPrecision`) passes and the cap check (`withValidSwapFee`) is the actual rejection — otherwise the test could pass for the wrong reason.
- Same two tests for the yield-side setter.
- The invariant suite also asserts via `invariant_protocolFeePercentagesAlwaysWithinCap` that no fuzz sequence can produce a stored protocol fee percentage above the cap.
- *Lives in:* `test_setProtocol{Swap,Yield}FeePercentage_acceptsCapValue`, `test_setProtocol{Swap,Yield}FeePercentage_revertsAtCapPlusScalingFactor`, `invariant_protocolFeePercentagesAlwaysWithinCap`.

**Auth chain works end-to-end through the real `AureumAuthorizer`:**
- Non-governance callers of `setProtocolSwapFeePercentage` and `setProtocolYieldFeePercentage` are rejected with `IAuthentication.SenderNotAllowed()`. The rejection comes from the inherited `SingletonAuthentication.authenticate` modifier, which calls `_canPerform` → `getAuthorizer().canPerform(...)` — and the `getAuthorizer()` call is intercepted by `vm.mockCall` to return the *real* `AureumAuthorizer` instance deployed in `setUp()`. The full chain from the controller through the mocked Vault to the real authorizer's `canPerform` logic resolves end-to-end.
- Governance-pranked callers (`vm.prank(multisig)`) successfully reach the function body in the cap acceptance tests, proving the auth chain succeeds when it should.
- *Lives in:* `test_setProtocol{Swap,Yield}FeePercentage_revertsForNonGovernance`, `test_setProtocol{Swap,Yield}FeePercentage_acceptsCapValue` (positive proof).

**The Vault → controller callback is gated to the Vault only:**
- Non-Vault callers of `collectAggregateFeesHook` are rejected with `IVaultErrors.SenderIsNotVault(callerAddress)` — the upstream `onlyVault` modifier inherited from `VaultGuard`. Fuzzed at 1024 runs.
- *Lives in:* `test_collectAggregateFeesHook_revertsIfNotVault`.

**Constructor argument validation:**
- Passing `address(0)` as the Bodensee parameter reverts with `ZeroBodenseeAddress()`.
- The constructor correctly stores the Bodensee address in the `DER_BODENSEE_POOL` immutable, readable via the auto-generated public getter.
- *Lives in:* `test_constructor_revertsOnZeroBodensee`, `test_derBodenseePool_returnsConstructorArgument`, plus the smoke test which exercises both as part of its three-assertion check.

**Inherited auth chain wiring resolves correctly:**
- `controller.getAuthorizer()` (inherited from `SingletonAuthentication`) walks the chain `getVault().getAuthorizer()` → mocked Vault returns `address(authorizer)` → decoded as `IAuthorizer` → cast to address for comparison. All three constructor-set values (immutable `DER_BODENSEE_POOL`, immutable `_vault` from `VaultGuard`, mocked `getAuthorizer()` chain) verified in one assertion block.
- *Lives in:* `test_setUp_constructorWiringAndGetAuthorizerMockResolve` (the smoke test).

## What the tests do *not* yet prove

Honest scope — these are gaps that exist in the B4 suite and should be addressed in later stages:

- **The fee collection chain end-to-end.** Calling `collectAggregateFees(pool)` (the public entry point) triggers `_vault.unlock(...)` which is supposed to call back into the controller's `collectAggregateFeesHook`, which then calls `_vault.collectAggregateFees(pool)` and routes the result through `_receiveAggregateFees`. The B4 unit tests mock `unlock(bytes)` to return empty bytes without simulating the callback, which means the `_receiveAggregateFees` path is not exercised in unit tests. The path is byte-identical to upstream and is covered by upstream's audit. A live fork test (B5) will exercise it against the real Balancer V3 Vault.
- **Live ERC20 transfers.** The nonzero-balance withdraw test mocks `safeTransfer` on the dummy token to return success. It does not deploy a real ERC20 and verify the actual token balances change. A real-token test would require either a `MockERC20` deployment or a live token via fork test. Stage B5/D scope.
- **Slither static analysis.** Stage B6.
- **Real on-chain deployment.** Stage C.
- **Fork tests against the actual mainnet Balancer V3 Vault.** Stage B5.

## Test architecture (`AureumProtocolFeeController.t.sol`)

The file has the following structure:

```
test/unit/AureumProtocolFeeController.t.sol
├── Imports (forge-std, OpenZeppelin, Balancer interfaces, Aureum src)
├── AureumProtocolFeeControllerHandler
│   ├── State: touchedPools[], successfulWithdrawRecipients[]
│   ├── 5 wrapped controller entry points (with try/catch for swallowing reverts)
│   └── Helpers for invariant test contract to read recorded state
├── AureumProtocolFeeControllerTest
│   ├── State: authorizer, controller, multisig, mockVault, handler, DER_BODENSEE_POOL_PLACEHOLDER
│   ├── setUp() — deploys real AureumAuthorizer, mocks Vault.getAuthorizer, deploys controller, deploys handler, registers handler as fuzz target
│   ├── Mock helpers: _mockGetAuthorizer, _mockGetPoolTokens,
│   │                _mockGetPoolTokenCountAndIndexOfToken, _mockSafeTransfer,
│   │                _mockUnlock, _mockUpdateAggregateSwapFeePercentage,
│   │                _mockUpdateAggregateYieldFeePercentage
│   ├── Storage helpers: _protocolFeeAmountsSlot, _readPoolFeeConfig
│   ├── Smoke test
│   ├── Group: Divergence tests (B10 + creator-fee revert stubs)
│   ├── Group: Preservation tests (auth chain + Vault-only callback)
│   ├── Group: Positive-path withdraw tests (zero balance + nonzero balance)
│   ├── Group: Fee-setter happy path tests (cap acceptance + cap rejection)
│   └── Invariants (4)
```

### Mock surface

The test suite mocks the Vault via `vm.mockCall` rather than deploying a real `MockVault` contract. This keeps the test file self-contained but requires every Vault method the controller calls to have an explicit mock helper. The current set:

| Vault method | Mock helper | Used by |
|---|---|---|
| `IVault.getAuthorizer()` | `_mockGetAuthorizer` | All tests via setUp |
| `IVaultExtension.getPoolTokens(pool)` | `_mockGetPoolTokens` | Withdraw positive-path tests |
| `IVaultMain.getPoolTokenCountAndIndexOfToken(pool, token)` | `_mockGetPoolTokenCountAndIndexOfToken` | `withdrawProtocolFeesForToken` positive-path test |
| `IERC20.transfer(to, amount)` | `_mockSafeTransfer` | Nonzero-balance withdraw test |
| `IVaultMain.unlock(bytes)` | `_mockUnlock` | Fee-setter happy path tests (returns empty bytes, callback does not fire) |
| `IVaultAdmin.updateAggregateSwapFeePercentage(pool, pct)` | `_mockUpdateAggregateSwapFeePercentage` | Swap fee-setter happy path |
| `IVaultAdmin.updateAggregateYieldFeePercentage(pool, pct)` | `_mockUpdateAggregateYieldFeePercentage` | Yield fee-setter happy path |

The auth chain is **not** mocked — a real `AureumAuthorizer` is deployed in `setUp()` and its `canPerform` is called live during every governance-gated test. This exercises the actual Aureum auth logic end-to-end rather than stubbing it out.

### Storage operations

The test file uses raw `vm.store` and `vm.load` with manually-computed keccak slots for storage operations rather than `stdstore`. The slot map is taken from `forge inspect AureumProtocolFeeController storageLayout` and is captured in `docs/STAGE_B_NOTES.md` (B22).

| Slot | Variable | Purpose |
|---|---|---|
| 2 | `_poolProtocolSwapFeePercentages` | Read by invariant 3 |
| 3 | `_poolProtocolYieldFeePercentages` | Read by invariant 3 |
| 5 | `_poolCreatorSwapFeePercentages` | Read by invariant 1 |
| 6 | `_poolCreatorYieldFeePercentages` | Read by invariant 1 |
| 7 | `_protocolFeeAmounts` | Written by nonzero-balance withdraw test, read by invariant |
| 8 | `_poolCreatorFeeAmounts` | Read by invariant 2 |

For nested mappings (slots 7 and 8), the slot computation is:

```
inner = keccak256(abi.encode(token, keccak256(abi.encode(pool, baseSlot))))
```

For the packed `PoolFeeConfig` struct (slots 2 and 3), the unpacking is:

```
uint256 packed = uint256(vm.load(controller, keccak256(abi.encode(pool, baseSlot))));
uint64 feePercentage = uint64(packed);   // low 64 bits
bool isOverride = ((packed >> 64) & 1) == 1;
```

### Invariant framework

The handler contract `AureumProtocolFeeControllerHandler` is the fuzz target. Its job is to expose a constrained set of controller entry points to the Foundry invariant runner, swallow expected reverts via `try/catch` so the fuzz sequence can continue, and record metadata about successful calls (`successfulWithdrawRecipients[]`) so invariant 4 can verify routing.

`targetContract(address(handler))` is called in `setUp()` to register the handler as the fuzz target. Without this call, the invariant runner would call functions on the test contract directly, which would not exercise the controller and would produce trivially-passing-for-the-wrong-reason invariants.

The four invariants run at `runs: 256, calls: 128` per the `[profile.default.invariant]` config in `foundry.toml`, totaling 32,768 controller-touching calls per invariant per run.

## Running the tests

### Run everything

```bash
forge test
```

Runs all tests in `test/unit/` and `test/fork/`. The fork test (`Sanity.t.sol`) requires `MAINNET_RPC_URL` to be set in the environment.

### Run only the controller tests

```bash
forge test --match-path test/unit/AureumProtocolFeeController.t.sol -vv
```

Verbosity `-vv` prints individual test names and pass/fail status. Higher verbosity (`-vvv`, `-vvvv`) prints call traces and is useful for debugging failing tests.

### Run only invariants (slower, ~14 seconds)

```bash
forge test --match-test "invariant_" -vv
```

### Run only named tests, excluding invariants (faster, ~50ms)

```bash
forge test --no-match-test "invariant_" -vv
```

### Build verification

```bash
forge build --force
```

`--force` bypasses the build cache and re-runs the full lint and type-check pipeline. **Use `--force`, not plain `forge build`, when verifying that the code compiles cleanly.** Plain `forge build` may hit the cache and skip lint analysis, hiding warnings that a fresh build would surface. (Discipline established at Pass 6.5 of B4.)

## Adding new tests

When extending `AureumProtocolFeeController.t.sol`:

- **Naming.** Test functions start with `test_` followed by snake_case description. Invariant functions start with `invariant_`.
- **Visibility.** Test functions are `public`; helpers are `internal` (for reuse) or `private` (for file-local utilities).
- **State.** Test contract state variables are `internal` per existing convention.
- **Fuzzing.** Tests with parameters fuzz at 1024 runs (the `foundry.toml` default). Use `vm.assume` to filter out values that would cause spurious failures.
- **Pranking.** Use `vm.prank(multisig)` immediately before the call that needs governance auth. The prank is single-shot — it only affects the next call, not subsequent ones.
- **Mock ordering.** Set up `vm.mockCall` mocks before the call that needs them. Mocks persist across calls until explicitly cleared.
- **Storage operations.** When writing or reading storage slots manually, use the slot map in `docs/STAGE_B_NOTES.md` (B22) and the slot-computation helpers (`_protocolFeeAmountsSlot`, `_readPoolFeeConfig`).
- **Mock helpers.** New Vault methods that need mocking should get a new `_mockXxx` helper rather than inline `vm.mockCall` calls in the test body. Helpers go in the mock-helpers section after the existing ones.

## Conventions

- **Imports:** group by source. forge-std first, then OpenZeppelin, then Balancer interfaces (alphabetical within group), then Aureum sources. Only import what the current file uses — no forward declarations for future imports. (Discipline established at Test Spec 1 of B4.)
- **NatSpec on test functions:** not required. Test names should be descriptive enough to communicate intent.
- **Inline comments:** use `//` for all comments in test files, not `///` NatSpec. Test files are not part of the public API and `forge doc` should not pick them up.
