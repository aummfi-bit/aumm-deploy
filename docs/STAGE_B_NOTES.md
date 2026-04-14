# STAGE_B_NOTES — upstream (Balancer VaultFactory + ProtocolFeeController)

Informal notes to re-anchor in two weeks without re-reading the submodule. Sources at the bottom of each part.

---

## Part 1 — VaultFactory

### 1. Constructor — params & what’s stored

Takes: `IAuthorizer authorizer`, `uint32 pauseWindowDuration`, `uint32 bufferPeriodDuration`, `uint256 minTradeAmount`, `uint256 minWrapAmount`, and three bytecode hashes: `vaultCreationCodeHash_`, `vaultExtensionCreationCodeHash_`, `vaultAdminCreationCodeHash_`.

All of that is stored as **immutables**: the three public `...CreationCodeHash` fields plus private `_authorizer`, `_pauseWindowDuration`, `_bufferPeriodDuration`, `_minTradeAmount`, `_minWrapAmount`.

The four **mappings** (`deployedProtocolFeeControllers`, `deployedVaultExtensions`, `deployedVaultAdmins`, `isDeployed`) start empty — not set in the constructor.

**Precision:** upstream both **constructs** `ProtocolFeeController` inline **and** stores it in `deployedProtocolFeeControllers[vault]` on each successful `create()`. **Aureum fork:** drop that mapping; expose **`INITIAL_FEE_CONTROLLER`** instead (`public immutable`). See **B11**.

### 2. `create()` — step by step (verified order)

1. Revert if `isDeployed[targetAddress]` is already true.
2. Check `keccak256(vaultCreationCode)` vs `vaultCreationCodeHash`; same for VaultAdmin and VaultExtension vs their stored hashes — revert `InvalidBytecode` if any mismatch.
3. Compute `vaultAddress = getDeploymentAddress(salt)` and revert unless `targetAddress == vaultAddress`.
4. `new ProtocolFeeController(IVault(vaultAddress))`, assign `deployedProtocolFeeControllers[vaultAddress]`.
5. `Create2.deploy` VaultAdmin (same `salt`, admin creation code + constructor args from immutables); `deployedVaultAdmins[vaultAddress] = ...`
6. `Create2.deploy` VaultExtension (same `salt`, extension code + `vaultAddress` + `vaultAdmin`); `deployedVaultExtensions[vaultAddress] = ...`
7. `CREATE3.deploy` the Vault with that `salt` and init data `(vaultExtension, _authorizer, protocolFeeController)`.
8. Revert if the address returned by CREATE3 ≠ `vaultAddress` (sanity check).
9. `emit VaultCreated(vaultAddress)`; set `isDeployed[vaultAddress] = true`.

So in upstream: **ProtocolFeeController → VaultAdmin → VaultExtension → Vault (CREATE3)**. Order matters for mental model; the predicted vault address is salt-derived either way.

### 3. The three `keccak256` checks

Each hashes the **full creation code bytes** passed in for that contract (`vaultCreationCode`, `vaultAdminCreationCode`, `vaultExtensionCreationCode`). Each hash is compared to the **matching immutable** stored at factory deploy time: `vaultCreationCodeHash`, `vaultAdminCreationCodeHash`, `vaultExtensionCreationCodeHash`.

The factory does **not** store the bytecode (too large) — only the hashes. The **caller** supplies the actual `bytes` as calldata to `create()`. Anything that doesn’t hash to the stored value reverts. For Aureum, B5 scripts will load bytecode from compiled artifacts (e.g. Foundry `vm.getCode("Vault.sol:Vault")` or equivalent) and pass it in.

### 4. `new ProtocolFeeController(...)` (~L115–116)

The **explicit** constructor takes **one** argument: `IVault vault_` (here the **predicted** `vaultAddress`, still empty). Base contracts get the same pointer: `SingletonAuthentication(vault_)`, `VaultGuard(vault_)` — there is **no** separate `authorizer` argument on `ProtocolFeeController`; governance auth later goes through `getVault().getAuthorizer()`.

The factory records the instance in `deployedProtocolFeeControllers`. That address is passed into the Vault constructor as `protocolFeeController`. The Vault stores it and asserts `protocolFeeController.vault() == address(this)` so this controller is wired to **this** Vault only.

**Why deploy controller before Vault is safe:** the controller stores the **future** Vault address; when the Vault’s constructor runs, `address(this)` is that address, so `vault()` on the controller matches. Without that check, you could pass a controller aimed at another vault. Aureum’s script deploys `AureumProtocolFeeController(futureVault, derBodensee)` before `create()`; the same assertion applies as long as `futureVault` matches `getDeploymentAddress(salt)`. B3: forked factory may accept an externally deployed controller — ordering on the script must still satisfy this wiring.

### 5. `getDeploymentAddress(salt)`

Returns `CREATE3.getDeployed(salt)`: the address where the Vault will appear after `CREATE3.deploy(salt, …)` **from this factory contract**. Derivation uses `address(this)` (the factory), so it’s deterministic without prior deployment. Safe to call before `create()` because nothing on-chain needs to exist yet.

**Nuance:** the same `salt` yields **different** predicted Vault addresses for **upstream `VaultFactory` vs `AureumVaultFactory`** (different factory addresses). That’s what you want: Aureum’s Vault sits beside Balancer’s canonical Vault with no address collision.

**Sources (VaultFactory + wiring):** `59:78`, `91:163` — `lib/balancer-v3-monorepo/pkg/vault/contracts/VaultFactory.sol`; `60:70` — `Vault.sol`; `158:160` — `ProtocolFeeController.sol` (constructor); `60:87` — `lib/balancer-v3-monorepo/pkg/solidity-utils/contracts/solmate/CREATE3.sol`; `16:22` — `SingletonAuthentication.sol` (vault immutable + constructor).

---

## Part 2 — ProtocolFeeController (upstream)

### Gist (one sentence)

Companion contract that holds **per-pool and global fee percentages**, **pulls** aggregate fee tokens from the Vault via `unlock` + hook, **splits** them into protocol vs pool-creator balances, and exposes **withdrawals** to the authorized parties.

### State — top-level storage

| What | Keys / values |
|------|----------------|
| `_globalProtocolSwapFeePercentage`, `_globalProtocolYieldFeePercentage` | Two `uint256` globals. Each is bounded above by `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE` / `MAX_PROTOCOL_YIELD_FEE_PERCENTAGE` (both `50e16` = 50%). `setGlobalProtocolSwapFeePercentage` / `setGlobalProtocolYieldFeePercentage` revert if called with a value above the cap. Aureum inherits this cap unchanged. |
| `_poolProtocolSwapFeePercentages`, `_poolProtocolYieldFeePercentages` | `pool → PoolFeeConfig` (`feePercentage` + `isOverride`) |
| `_poolCreators` | `pool → poolCreator` address |
| `_poolCreatorSwapFeePercentages`, `_poolCreatorYieldFeePercentages` | `pool → uint256` creator fee % |
| `_protocolFeeAmounts`, `_poolCreatorFeeAmounts` | `pool → (IERC20 → uint256)` balances after split |

Disaggregated “owed” amounts live here after collection runs; the Vault keeps aggregate percentages in pool config, not this ledger.

### Calls from the Vault **into** the controller

- **`Vault.sol` (constructor only):** `protocolFeeController.vault()` — sanity that the controller points at this Vault.
- **`VaultExtension`:** `_protocolFeeController.registerPool(pool, poolCreator, protocolFeeExempt)` during pool registration (must keep compatible behavior/returns for pool registration to work). The **`protocolFeeExempt`** flag lets pool factories register a pool with **no** protocol swap/yield fees (and governance override semantics — exempt pools don’t get overwritten by permissionless global sync). Upstream behavior; Aureum inherits it unless `registerPool` is **deliberately** changed to ignore or flatten that flag.

`getProtocolFeeController()` is a view passthrough — not a behavioral dependency.

**Reverse (controller → Vault):** `unlock`, internal fee collection paths, `sendTo`, `updateAggregateSwapFeePercentage` / `updateAggregateYieldFeePercentage`, `getPoolTokens`, `getPoolTokenCountAndIndexOfToken` — Aureum’s Vault side must still implement these interactions.

### Permissioning (who can call what)

- **`authenticate` (authorizer / governance):** global protocol fee setters, per-pool protocol fee setters (with `withLatestFees`), `withdrawProtocolFees` / `withdrawProtocolFeesForToken`.
- **`onlyPoolCreator(pool)`:** `setPoolCreatorSwapFeePercentage`, `setPoolCreatorYieldFeePercentage`, `withdrawPoolCreatorFees` (creator path with explicit recipient).
- **`onlyVault`:** `collectAggregateFeesHook`, `registerPool`.

**Permissionless:** e.g. `collectAggregateFees`, `updateProtocolSwapFeePercentage` / `updateProtocolYieldFeePercentage` (sync non-override pools to globals), `computeAggregateFeePercentage` (pure).

### Pool creator fees — set, collected, withdrawn

- **Set:** `setPoolCreatorSwapFeePercentage` / `setPoolCreatorYieldFeePercentage` (`onlyPoolCreator`).
- **Collected:** same `collectAggregateFees` flow; amounts land in `_poolCreatorFeeAmounts` after `_receiveAggregateFees` splits.
- **Withdraw:** `withdrawPoolCreatorFees` (to chosen recipient or default registered creator).

Per **B4**, `AureumProtocolFeeController` **reverts** creator-facing setters (see Interface divergences below); upstream allows them.

### Protocol fees — withdraw and destination (upstream)

`withdrawProtocolFees(pool, recipient)` and `withdrawProtocolFeesForToken(pool, recipient, token)` are **`authenticate`**; they transfer from `_protocolFeeAmounts` to **`recipient` passed by the caller**.

There is **no** hardcoded treasury in upstream — “treasury” is whatever address governance passes. **B4** (immutable der Bodensee) plus the **B4 contract-spec** divergences below replace that pattern.

### Interface divergences from upstream (B4 contract spec)

All function signatures below are **preserved** because `IProtocolFeeController` declares them — Aureum must implement the interface verbatim or compilation fails. The divergence is entirely in the **bodies**.

- **`withdrawProtocolFees(address pool, address recipient)`** — fees route to immutable `derBodenseePool`. **B10:** revert if `recipient != derBodenseePool` (see Open decisions) — avoids silently ignoring a wrong `recipient`. Emit an event on withdraw so off-chain observers can see the **actual** destination.
- **`withdrawProtocolFeesForToken(address pool, address recipient, IERC20 token)`** — same: route to `derBodenseePool`, **B10** recipient check, emit event.
- **`setPoolCreatorSwapFeePercentage(address pool, uint256 poolCreatorSwapFeePercentage)`** — reverts unconditionally with a custom error such as `CreatorFeesDisabled()`. The `poolCreatorSwapFeePercentage` parameter is never read.
- **`setPoolCreatorYieldFeePercentage(address pool, uint256 poolCreatorYieldFeePercentage)`** — same: reverts unconditionally.
- **`withdrawPoolCreatorFees(address pool, address recipient)`** — reverts unconditionally; there are no creator fee balances to withdraw because the pool-creator setter functions above prevent any from ever accruing.
- **`withdrawPoolCreatorFees(address pool)`** — same: reverts unconditionally for the same reason.

**Not diverging:** the **50% cap** on protocol fee shares, the **split math** in `_receiveAggregateFees`, and the **residual-to-LPs** property. These all live in upstream `Vault.sol` / libraries (**byte-identical, off-limits**) and in the split arithmetic Aureum keeps unchanged. Aureum governance sets **protoFee ∈ [0%, 50%]** per pool; **100%** of that share routes to **der Bodensee**; LPs get the rest.

**Sources (ProtocolFeeController + VaultExtension):** `86:89` (max protocol fee constants), `94:119`, `158:160`, `168:259`, `387:537` — `lib/balancer-v3-monorepo/pkg/vault/contracts/ProtocolFeeController.sol`; `259:260`, `720:721` — `lib/balancer-v3-monorepo/pkg/vault/contracts/VaultExtension.sol`.

---

## Plan divergences (small, intentional)

- **B2 — `AureumAuthorizer.sol`:** immutable renamed `governanceMultisig` → `GOVERNANCE_MULTISIG` (Foundry lint `screaming-snake-case-immutable`); constructor param renamed `_governanceMultisig` → `governanceMultisig_` (matches upstream Balancer V3 trailing-underscore convention). Functional behavior identical to plan source.
- **B3 — `AureumVaultFactory.sol`:** `ProtocolFeeController` import replaced with `IProtocolFeeController` from interfaces — no `new` in the fork, so the concrete type is unnecessary. **`INITIAL_FEE_CONTROLLER`** is typed as the interface; upstream’s local was the concrete contract. **`abi.encode` of an interface-typed address and of a concrete-typed address are identical** (both encode the 20-byte address in 32 bytes), so Vault init bytecode matches upstream’s for that argument.
- **B3 — immutable naming vs lint:** upstream’s forked immutables keep Balancer’s camelCase (`vaultCreationCodeHash`, `_authorizer`, `_pauseWindowDuration`, etc.) so the diff against `VaultFactory.sol` stays small and future merges from the submodule stay mechanical. Renaming all eight to `SCREAMING_SNAKE_CASE` would inflate the diff and create avoidable merge conflicts for no runtime benefit. The **Aureum-only** immutable **`INITIAL_FEE_CONTROLLER`** uses `SCREAMING_SNAKE_CASE` (no upstream name to preserve). Foundry’s linter otherwise emits `screaming-snake-case-immutable` **notes** on the upstream-named lines; those are **suppressed for this file only** via `foundry.toml` `[lint] ignore = ["src/AureumVaultFactory.sol"]` so `forge build` stays quiet without touching the contract body.

---

## Branch model deviation (2026-04-09)

During the B3→B4 transition, Stage B work was fast-forwarded onto `main` (originally intended to stay frozen at the Stage A baseline until B7's PR merge). Decision: accept the deviation and continue Stage B directly on `main`. Driven by token-budget constraints — the cost of fixing was real in chat tokens, the benefit was contingent on a future audit step.

Cost accepted:

- No PR-as-review-gate at B7
- No single-diff artifact for audit review of "what is Stage B"
- Harder rollback if Stage B work needs to be reverted wholesale
- B7 in STAGE_B_PLAN.md is partially defunct — it becomes "tag stage-b-complete and update completion log" only, no PR step

The `stage-b` branch still exists on origin and can serve as a snapshot of "Stage B as a coherent unit" if needed, but main is now the working trunk for the rest of Stage B and Stage C will branch from main as-is.

---

## Open Stage B decisions (added during B1)

More rows may land here as Stage B progresses; B12 and B13 (resolved during B4 pre-design grep phase) live in the section below.

| ID | Decision |
|----|----------|
| **B10** | **`withdrawProtocolFees` / `withdrawProtocolFeesForToken`:** revert if `recipient != derBodenseePool` rather than silently ignoring the parameter. Rationale: the interface signature must stay fixed for compilation, but silently ignoring an explicit `recipient` is a footgun for governance operators. Use a custom error such as `InvalidRecipient(address expected, address provided)` so behavior is self-documenting and mis-formed Safe transactions fail loud. *(STAGE_B_PLAN already assigns **B8** to “no upgradability”; this rule is **B10**.)* |
| **B11** | **Drop `deployedProtocolFeeControllers` mapping from `AureumVaultFactory`.** Upstream stores the freshly deployed controller per vault; Aureum’s fork does not deploy a controller per vault — it accepts one shared controller via constructor immutable. Keeping the mapping would be structurally misleading (the name implies a per-vault relationship that does not exist in the fork). The same information is exposed via **`public immutable INITIAL_FEE_CONTROLLER`** on the factory (constructor param **`initialFeeController_`**). The `INITIAL_` prefix is semantic: it is the controller the Vault was *initialized* with, which may diverge from `vault.getProtocolFeeController()` if governance ever calls `setProtocolFeeController` on the Vault post-deployment. Cleaner diff vs upstream, smaller bytecode, no false surface area. Decided in B3 design phase. |

---

## B4 design decisions (resolved during pre-design grep phase, 2026-04-09)

**B12 — Authorization inheritance.** `AureumProtocolFeeController` inherits `SingletonAuthentication` from upstream Balancer V3 (matches `lib/balancer-v3-monorepo/pkg/vault/contracts/ProtocolFeeController.sol:51`). `SingletonAuthentication` itself inherits only `Authentication` (verified: `lib/balancer-v3-monorepo/pkg/vault/contracts/SingletonAuthentication.sol:16`). Authorization flows: `authenticate` modifier → `Authentication._canPerform()` → `Vault.getAuthorizer()` → `AureumAuthorizer.canPerform()` → `account == GOVERNANCE_MULTISIG`. No competing auth system (no OZ `AccessControl`, no `Ownable`, no per-role mappings).

**B13 — Reentrancy guard inheritance.** `AureumProtocolFeeController` inherits `ReentrancyGuardTransient` from `@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol` to mirror upstream `ProtocolFeeController:52`. The `nonReentrant` modifier is applied to **zero** functions, matching upstream's zero applications (verified: `grep -n "nonReentrant" ProtocolFeeController.sol` returned empty). Verified that this inheritance is **not** transitively required: neither `SingletonAuthentication` (inherits only `Authentication`) nor `VaultGuard` (no inheritance at all) pulls in `ReentrancyGuardTransient`. Upstream lists it explicitly and deliberately. The reentrancy story for fee collection lives at the Vault layer: `collectAggregateFees` calls `Vault.unlock(...)`, which the Vault gates via its own transient lock and intentionally allows authorized reentrant token-transfer callbacks during the unlocked context. Adding `nonReentrant` on the controller would either no-op (if it permits the unlock-reentry) or break fee collection (if it blocks it). Mirror upstream exactly; preserve audit-inheritance argument; document the absence of the modifier as a *deliberate* choice rather than an oversight.

---

## B4 implementation notes (post-implementation, 2026-04-12)

`AureumProtocolFeeController` was implemented over six grep-verified passes against a compile-clean baseline forked from `lib/balancer-v3-monorepo/pkg/vault/contracts/ProtocolFeeController.sol` (upstream). Final file: `src/AureumProtocolFeeController.sol`, **622 lines** (upstream is 587 lines), with **12 diff hunks** totaling ~35 changed/added lines. The audit-inheritance argument is embedded in two `// AUREUM NOTE:` provenance annotations inside the contract source itself, at post-implementation lines 222–228 and 536–538.

### Six-pass implementation summary

| Pass | What | Line delta | Hunks added |
|------|------|---|---|
| 1 | Fork upstream verbatim; rename contract; rewrite two relative imports; update `abi.encodeCall` self-reference | 0 | 3 |
| 2 | Add `DER_BODENSEE_POOL` immutable + constructor `derBodenseePool_` parameter + zero-address check + three custom error declarations in new "Aureum-Added State" block | +19 | 1 |
| 3 | Insert `InvalidRecipient` precondition check at line 1 of both `withdrawProtocolFees` and `withdrawProtocolFeesForToken` (B10 enforcement at the public boundary) | +6 | 2 |
| 4 | Replace bodies of all four creator-fee functions with `revert CreatorFeesDisabled();`; strip all modifiers; comment out unused parameter names | 0 | 4 |
| 5 | Add two `// AUREUM NOTE:` provenance annotations above `_receiveAggregateFees` (three-arg private overload) and `_withdrawProtocolFees` | +10 | 2 |
| 6 | `foundry.toml` lint suppression + this notes section (no contract source changes) | 0 | 0 |

### Design decisions locked in *during* implementation (added to the open decisions list)

The B1–B3 decisions **B10** (recipient revert-if-mismatch) and **B11** (drop `deployedProtocolFeeControllers` mapping) plus the B4 pre-design decisions **B12** (inherit `SingletonAuthentication`) and **B13** (inherit `ReentrancyGuardTransient`, apply `nonReentrant` to zero functions) were all resolved before Pass 1. The following additional decisions were made during Passes 2–5:

| ID | Decision |
|----|----------|
| **B14** | **Unused-parameter commenting style for creator-fee revert stubs.** The four stubbed functions use `address /* pool */` and `uint256 /* poolCreatorSwapFeePercentage */` (comment-out-the-name) rather than leading-underscore, no-name, or named-with-suppression patterns. Rationale: matches Balancer V3's own pattern for unused interface parameters; silences the `unused-parameter` warning at source without requiring lint suppression; self-documenting — the `/* */` comment signals "ABI slot, deliberately ignored" more explicitly than alternatives. Verified warning-free in Pass 4's `forge build`. |
| **B15** | **Per-function signature shape preservation in Pass 4.** When stubbing the four creator-fee functions, the upstream per-function signature layout was preserved exactly: multi-line for the two setters (`setPoolCreatorSwapFeePercentage`, `setPoolCreatorYieldFeePercentage`) because upstream wrote them multi-line; single-line for the two withdraw overloads because upstream wrote them single-line. No cosmetic reformatting for symmetry across the four stubs. Rationale: smaller diff against upstream; stylistic changes made purely for symmetry cost diff-legibility without buying anything semantic. |
| **B16** | **`// AUREUM NOTE:` prefix convention for provenance annotations.** Plain `//` comments (not NatSpec `///`), uppercase `AUREUM NOTE:` prefix, no decorative borders. Applied in Pass 5 above `_receiveAggregateFees` and `_withdrawProtocolFees`. Rationale: internal implementation notes belong in `//` not `///` (NatSpec `///` gets pulled into `forge doc` output as public API documentation, which is the wrong audience for audit-provenance notes); the uppercase `AUREUM NOTE:` prefix gives visual salience without decorative noise and is grep-able via `grep -n "AUREUM NOTE:" src/AureumProtocolFeeController.sol`. |
| **B17** | **Public-boundary enforcement of B10, not internal-helper enforcement.** The `InvalidRecipient` precondition check lives in the two public wrapper functions (`withdrawProtocolFees` and `withdrawProtocolFeesForToken`), **not** in the internal `_withdrawProtocolFees` helper. The helper stays byte-identical to upstream including the `safeTransfer` call and the `_protocolFeeAmounts[pool][token] = 0` storage zeroing. The `recipient` parameter is passed through to the helper but has already been validated to equal `DER_BODENSEE_POOL` by the public wrapper. Rationale: the internal helper is the function that does the actual money movement and storage updates, and its byte-identity to upstream is the load-bearing part of the audit-inheritance argument for the money-movement path. The public wrapper is a thin validation layer above it. The `// AUREUM NOTE:` annotation above the helper documents this boundary explicitly so an auditor reading the helper alone doesn't wonder where `recipient` got validated. |
| **B18** | **All three new custom errors declared together in Pass 2.** `InvalidRecipient`, `CreatorFeesDisabled`, and `ZeroBodenseeAddress` are all declared in a single block at the top of the "Aureum-Added State" section inserted by Pass 2, even though `InvalidRecipient` isn't used until Pass 3 and `CreatorFeesDisabled` isn't used until Pass 4. Rationale: one canonical location for "errors Aureum introduced" improves audit readability over scattering them across the passes that first use them; pure declarations have no runtime side effects until invoked, so there's no semantic drift from declaring them early; future readers scanning for "what errors does this contract define beyond upstream" find the answer in one place. |
| **B19** | **Modifier stripping from creator-fee revert stubs.** All modifiers (`onlyPoolCreator`, `withValidPoolCreatorFee`, `withLatestFees`) removed from the four stubbed functions in Pass 4. Rationale: `withLatestFees` invokes `collectAggregateFees` → `_vault.unlock(...)`, which is an external Vault call that could fail or revert for reasons unrelated to the "creator fees are disabled" story (unregistered pool, Vault paused, transient-storage lock contention). Leaving the modifier in place would mean callers with typo'd pool addresses or calls during unusual Vault states could see a Vault-internal error *before* hitting `CreatorFeesDisabled`, which is confusing. Stripping all modifiers makes the revert fire cold with no dependencies on Vault state — the "this function doesn't exist in Aureum" story is deterministic regardless of any on-chain condition. `onlyPoolCreator(pool)` and `withValidPoolCreatorFee` are stripped for the same reason (uniform policy: disabled functions have zero modifiers). |
| **B20** | **`pure` mutability on the four creator-fee revert stubs.** After Pass 4 replaced the four creator-fee function bodies with unconditional `revert CreatorFeesDisabled();`, `solc` (not `forge lint`) emits Warning 2018 — "Function state mutability can be restricted to pure" — because the new bodies read no state, write no state, and call nothing that does. Pass 6.5 adds `pure` to all four function signatures (`external pure`) to silence the warning at source. This narrows the declared mutability relative to upstream's implicit `nonpayable`, which is legal Solidity (implementations may use stricter mutability than their interface) and cosmetically shifts the ABI's `stateMutability` field from `nonpayable` to `pure` for these four functions. The shift has no practical effect because the functions revert unconditionally regardless of how callers dispatch them — the tightened mutability is a source-level signal that matches the semantic truth ("this function does nothing"), not a behavior change. `solc` Warning 2018 was not caught during Pass 4 because Pass 4 verification checked `forge lint` output but not `forge build --force` output; Pass 6's `--force` rebuild surfaced it, and Pass 6.5 is the retroactive fix. |
| **B21** | **Test mock surface strategy.** The test suite for `AureumProtocolFeeController` uses `vm.mockCall` to intercept Vault method calls rather than deploying a real `MockVault` contract. Each Vault method the controller calls has its own `_mockXxx` helper in the test file. Exact-argument matching is used for tests that care about specific call values (e.g. `getPoolTokens(pool)` is matched on the exact pool address); selector-only matching is used for catch-all interception (e.g. `safeTransfer` is matched only by selector regardless of recipient/amount). The auth chain is **not** mocked — a real `AureumAuthorizer` is deployed in `setUp()` and its `canPerform` is called live during every governance-gated test. This exercises the actual Aureum auth logic end-to-end rather than stubbing it out, and the gas numbers from the test runs empirically demonstrate that the auth chain runs through real contract code (~10k gas per auth check, vs ~1k for mocked Vault calls). For invariant testing, a separate `AureumProtocolFeeControllerHandler` contract is defined inline in the test file as the fuzz target; the handler swallows expected reverts via `try/catch` so the fuzz sequence can continue across calls that are designed to revert. |
| **B22** | **Storage operation strategy.** The test suite uses raw `vm.store` and `vm.load` with manually-computed keccak slots rather than `stdstore`. Reason: the controller's mappings are `internal`, not `public`, so they don't have auto-generated public getters, and `stdstore`'s slot detection requires a public getter that returns the mapping value directly. Manually computing slots from the storage layout dump (`forge inspect AureumProtocolFeeController storageLayout`) is two lines of test code per slot and is unambiguous. The captured slot map for `AureumProtocolFeeController` (relative to slot 0 of its own state, which starts at slot 0 because the inherited contracts `SingletonAuthentication`, `VaultGuard`, and `ReentrancyGuardTransient` only declare immutables and no storage variables): slot 0 = `_globalProtocolSwapFeePercentage`, slot 1 = `_globalProtocolYieldFeePercentage`, slot 2 = `_poolProtocolSwapFeePercentages` (mapping → `PoolFeeConfig` struct), slot 3 = `_poolProtocolYieldFeePercentages` (mapping → `PoolFeeConfig` struct), slot 4 = `_poolCreators` (mapping → address), slot 5 = `_poolCreatorSwapFeePercentages` (mapping → uint256), slot 6 = `_poolCreatorYieldFeePercentages` (mapping → uint256), slot 7 = `_protocolFeeAmounts` (nested mapping → uint256), slot 8 = `_poolCreatorFeeAmounts` (nested mapping → uint256). For nested mapping slot computation: `inner = keccak256(abi.encode(token, keccak256(abi.encode(pool, baseSlot))))`. For the `PoolFeeConfig` struct unpacking: `uint64 feePercentage = uint64(packed)` (low 64 bits), `bool isOverride = ((packed >> 64) & 1) == 1`. |
| **B23** | **Lint suppression for intentional narrowing casts in test code.** The `_readPoolFeeConfig` helper in the test file performs an intentional narrowing cast `uint64(packed)` to extract the low 64 bits of a packed `PoolFeeConfig` struct read from storage. Forge lint emits an `unsafe-typecast` note on this cast because narrowing casts can lose data. The cast is suppressed via `// forge-lint: disable-next-line(unsafe-typecast)` on the line immediately above, which is the canonical Forge lint per-line suppression directive. The suppression scope is one line, the intent is documented inline by the surrounding comment, and the discipline ("clean warnings for Aureum code, suppressions only for upstream-preserved patterns or documented narrow exceptions") is preserved. **Pattern for future Aureum code:** when a narrowing cast is intentional and unavoidable (e.g. unpacking a packed storage struct), use this directive on the line above rather than refactoring around the lint rule. If the same pattern appears in multiple places, consider an explicit mask (`uint64(packed & type(uint64).max)`) as an alternative that doesn't need suppression — but for one-off cases the directive is the smaller, cleaner fix. |

### Test file architecture (post-Test-Spec-3b, 2026-04-13)

The test file `test/unit/AureumProtocolFeeController.t.sol` is **628 lines** and contains:
- **24 named tests** covering divergence, preservation, positive paths, and constructor validation
- **4 invariants** running at 256 × 128 = 32,768 controller-touching calls each (131,072 total per `forge test` invocation)
- **1 inline handler contract** (`AureumProtocolFeeControllerHandler`) as the invariant fuzz target
- **7 mock helpers** for Vault method interception
- **2 storage helpers** for slot computation and `PoolFeeConfig` struct unpacking

Operator-facing documentation lives in `test/README.md`, including the test architecture, the mock surface table, the storage slot map, the invariant framework explanation, run commands, and a "What the tests prove" subsection that maps each structural property of the contract to the specific tests that demonstrate it. The "What the tests prove" subsection is intended as a navigation aid for anyone reading the test file with audit eyes — including future Aureum contributors and Stage D auditors.

The test suite was developed across four sequential test specs (Test Spec 1 — scaffolding + smoke test; Test Spec 2 — pure-revert tests; Test Spec 3a — positive-path withdraw tests; Test Spec 3b — invariant suite + fee-setter happy path + nonzero-balance withdraw). Each spec was applied and verified independently before moving to the next, following the same paired-pass-and-verify discipline used for the contract source itself. All four specs landed first-try with the exception of one minor amendment (Test Spec 1 had an unused `IAuthorizer` import that was removed before sign-off).

**Run command for the full test suite:**

```bash
forge test --match-path test/unit/AureumProtocolFeeController.t.sol -vv
```

Expected output: `24 passed; 0 failed; 0 skipped; finished in ~14s` (the invariants take most of the runtime; the 20 named tests finish in ~50ms).

### Lint notes suppressed by `foundry.toml` (point-in-time snapshot, post-Pass-5)

The following six upstream-preserved lint notes are suppressed via the `foundry.toml` `[lint] ignore` entry added in Pass 6. Line numbers are current as of the post-Pass-5 state (622-line file):

| Note | Line | Source | Why preserved |
|------|------|--------|---------------|
| `unused-import` | L9 | Upstream imports `MAX_FEE_PERCENTAGE` from `VaultTypes.sol` but never uses it | Removing would be a gratuitous divergence from upstream |
| `unwrapped-modifier-logic` | L128 | Upstream's `withValidSwapFee` modifier is inline | Refactoring into an internal helper would save bytecode at the cost of byte-divergence |
| `unwrapped-modifier-logic` | L137 | Upstream's `withValidYieldFee` modifier is inline | Same rationale |
| `unwrapped-modifier-logic` | L145 | Upstream's `withValidPoolCreatorFee` modifier is inline | Same rationale |
| `divide-before-multiply` | L389 | Precision-truncation idiom `(x / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR` inside `computeAggregateFeePercentage` or similar helper | The divide-then-multiply is deliberate — it truncates to a precision boundary. False positive on this idiom |
| `divide-before-multiply` | L618 | Same idiom in `_ensureValidPrecision` or similar | Same rationale |

These line numbers will drift if any future Stage B or Stage C commit shifts the file contents. The stable information — the *kinds* of notes being suppressed and why — lives in the `foundry.toml` comment block.

### Provenance annotations in the source

Two `// AUREUM NOTE:` annotations inside `src/AureumProtocolFeeController.sol` serve as in-source audit pointers. Grep-able via `grep -n "AUREUM NOTE:" src/AureumProtocolFeeController.sol`:

| Location (post-Pass-5) | Target function | Upstream range | What it says |
|---|---|---|---|
| L222–228 | `_receiveAggregateFees(address pool, ProtocolFeeType feeType, uint256[] memory feeAmounts) private` | Upstream L203–259 | Function is byte-identical to upstream; the Aureum short-circuit makes the creator-fee split branch always dead because the creator-fee percentage mappings are never written |
| L536–538 | `_withdrawProtocolFees(address pool, address recipient, IERC20 token) internal` | Upstream L504–512 | Function is byte-identical to upstream; B10 recipient enforcement happens at the public boundary, not in this helper — the helper "trusts the public boundary" |

### Open Stage B housekeeping todos

The following items are real and worth doing before `stage-b-complete`, but are out of scope for B4's commit and are logged here as reminders for a separate housekeeping commit:

1. **Harmonize `AureumAuthorizer.sol`'s zero-address check with the controller's custom-error idiom.** Currently the Authorizer uses `require(governanceMultisig_ != address(0), "AureumAuthorizer: zero multisig")` (Pass B2 convention), while the controller uses `error ZeroBodenseeAddress()` + `if (...) revert ZeroBodenseeAddress()` (Pass B4 convention). Options: (a) add `error ZeroMultisig()` to the Authorizer and swap the `require` for a `revert`, plus update the unit test's `vm.expectRevert` assertion; (b) document the divergence and leave both as-is. **Recommended path: (a).** Target commit message: `stage-b housekeeping: harmonize zero-address check idiom across Aureum contracts`. Target location: between B4 and B5, or between B6 and B7.

2. **Update the main `README.md` repository layout to reflect post-B0–B4 state.** The current `README.md` shows the test directory with placeholder content (`test/unit/` says "Stage B+" with no files listed). After B2 and B4, the actual contents are `test/unit/AureumAuthorizer.t.sol` and `test/unit/AureumProtocolFeeController.t.sol`. Update the layout block to show the real files. Also update the "Current status" line which still says "Stage A" — it should say "Stage B (in progress, B0-B4 complete)" or similar. Target: separate `stage-b housekeeping: refresh main README repository layout and status` commit, or fold into a combined housekeeping commit.

3. **Reconcile the architecture-table description of `AureumProtocolFeeController` in the main `README.md` with the actual implemented behavior.** The current table row says "Routes 50% of swap fees + 100% of protocol-extractable yield fees to der Bodensee Pool." The actual Aureum behavior (verified by the contract source and the test suite) is "Routes 100% of protocol-extractable fees (both swap and yield, per the protocol fee percentage set per pool by governance up to a 50% cap) to der Bodensee Pool. Pool creator fees are structurally disabled — all four pool-creator-fee functions revert unconditionally with `CreatorFeesDisabled()`." The "50% of swap fees" phrasing in the README is a remnant of an earlier design or a misread of the upstream cap and should be corrected for accuracy.

- **Stage C pre-deploy: pin mainnet Vault constructor params.** Before running
  `DeployAureumVault.s.sol` against real mainnet, `cast call` the Balancer V3
  mainnet VaultFactory for `_pauseWindowDuration`, `_bufferPeriodDuration`,
  `_minTradeAmount`, `_minWrapAmount` and record the values in `.env.example`
  as the recommended Stage C defaults (replacing the B5 placeholder values).
  Flagged during B5 Pass 1: the values are currently env vars without a pinned
  source because B1/B2/B3 grepped the types but not the mainnet values.

- **Slither 0.11.4 accepted residual: `unindexed-event-address` on
  `AureumVaultFactory.VaultCreated`.** The event is upstream-verbatim from
  `balancer-v3-monorepo/pkg/vault/contracts/VaultFactory.sol#42` and cannot
  be suppressed inline due to a Slither 0.11.4 parser bug where this detector
  emits findings with empty `elements`, bypassing the ignore-comment check in
  `slither/core/slither_core.py` `has_ignore_comment`. The finding persists
  in every Slither run as `1 result(s) found` and is documented in full in
  the B6 triage section below. Reconsider on Slither upgrade — if the bug is
  fixed, replace the accept-and-document with an inline suppression.

### Commit chain reference (post-Pass-6, pre-B4-work-commit)

The chain of commits on `main` from the Stage A skeleton to the pre-B4-work-commit tip, for navigation:

```
fb0216a  Stage A: Foundry skeleton, Cursor rules, planning docs
b60492f  Pin balancer-v3-monorepo submodule to 68057fda
283847f  A6: install openzeppelin-contracts v5.6.1 and forge-std v1.15.0
25b9298  A7: fix Natspec parser issue in Sanity.t.sol
9afb636  STAGE_A_PLAN: log A6-A8 complete, RPC sanity test green
c198739  STAGE_A_PLAN: log A9 complete, stage-a-complete tagged
1a7e44b  B0: stage-b branch opened, slither installed (.venv already gitignored in Stage A)
9b91c49  B0: log completion in Stage B plan
45d160c  B1: notes from reading upstream VaultFactory and ProtocolFeeController
758183b  B1: log completion in Stage B plan
e792f09  B2: AureumAuthorizer + unit test (4 tests, all green)
5e2156a  B2: log completion in Stage B plan
a4e4ed2  B3: AureumVaultFactory fork + lint ignore + notes
4680179  B3: log completion in Stage B plan
93f557d  B4 prep: add B12/B13 design decisions from pre-design grep phase
defb2d5  docs: list all docs/ files in README repository layout
3c065ab  Stage B branch model deviation: documented, working on main
```

B4's work commit (next) will add the new `src/AureumProtocolFeeController.sol`, its unit+invariant test file `test/unit/AureumProtocolFeeController.t.sol`, and these `foundry.toml` + STAGE_B_NOTES updates. B4's log commit will follow, updating `docs/STAGE_B_PLAN.md`'s Completion Log.

---

## B6 — Slither triage

Slither 0.11.4 was run per the plan's prescribed invocation:

```bash
slither . --filter-paths "lib|test"
```

The `--filter-paths` excludes the submodule and the test directory. With
`foundry.toml`'s `--skip ./test/** ./script/**` passed through crytic-compile,
the effective scope is the three Aureum source files:

- `src/AureumAuthorizer.sol`
- `src/AureumVaultFactory.sol`
- `src/AureumProtocolFeeController.sol`

**Initial run: 32 findings across 11 detectors. Final run after B6 suppressions: 1 finding (accepted, see below).**

### Triage summary

| Detector | Count | Disposition |
| --- | --- | --- |
| reentrancy-events | 11 | Suppressed inline — upstream Balancer V3 Vault-unlock pattern; Vault reentrancy lock held during external calls and subsequent event emissions |
| encode-packed-collision | 3 | Suppressed inline — `Create2.deploy` / `CREATE3.deploy` initcode construction with constant bytecode + `abi.encode` of constructor args (collision-safe); standard Balancer V3 deployment pattern |
| dead-code | 3 | Suppressed inline — three internal pool-creator-fee helpers (`_ensureCallerIsPoolCreator`, `_setPoolCreatorFeePercentage`, `_withdrawPoolCreatorFees`) orphaned by B19 design (public entry points replaced with revert stubs). Preserved rather than deleted to minimize diff vs upstream |
| naming-convention | 3 | Suppressed inline — Aureum immutables `GOVERNANCE_MULTISIG`, `DER_BODENSEE_POOL`, `INITIAL_FEE_CONTROLLER` use SCREAMING_CASE matching Balancer V3 upstream convention for protocol-critical addresses. Consistent with `foundry.toml` `[lint] ignore` decisions for forked files |
| reentrancy-no-eth | 3 | Suppressed inline — two on fee-controller `_receiveAggregateFees` overloads (Vault lock held in unlock context), one on factory `CREATE3.deploy` followed by `isDeployed = true` (fresh contract, no caller can reenter) |
| divide-before-multiply | 2 | Suppressed inline — intentional precision-truncation idiom `(x / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR`. Upstream fee math |
| unused-return | 2 | Suppressed inline — `_vault.unlock()` return (hook writes state directly), `_vault.getPoolTokenCountAndIndexOfToken()` (called for revert side effect, validates token belongs to pool) |
| boolean-equal | 2 | Suppressed inline — `isOverride == false` stylistic nit. Upstream-verbatim |
| uninitialized-local | 1 | Suppressed inline — `uint256 aggregateFeePercentage;` default-initializes to 0, then assigned before first use. Upstream pattern |
| calls-loop | 1 | Suppressed inline — `_vault.sendTo` inside fee-distribution loop. Pool tokens validated at pool registration; controlled iteration set. Upstream pattern |
| unindexed-event-address | 1 | **Accepted unsuppressable.** See below |

**Totals:** 32 findings initially → 31 suppressed inline → 1 accepted residual.

### Zero Aureum-introduced bugs

Every finding was classified as either upstream-inherited from the forked
Balancer V3 code, or as a deliberate Aureum design choice (the three
SCREAMING_CASE immutables and the three B19-orphaned dead-code helpers).
No finding revealed a real Aureum-introduced bug. This is the expected
outcome for forked-and-minimally-modified upstream code, but the triage
was performed finding-by-finding rather than waved through — the
classification rationale is attached inline as a site-local comment at
every suppression site.

### The accepted residual finding

`Detector: unindexed-event-address` on
`AureumVaultFactory.VaultCreated(address)` cannot be suppressed inline in
Slither 0.11.4 due to a parser bug.

**Reproduction.** The `unindexed-event-address` detector emits findings
with an empty `elements` array. In
`slither/core/slither_core.py`, `has_ignore_comment` iterates over
`r["elements"]` to check each element's source mapping against the
preceding-line directive. If `elements` is empty, the loop body never
runs, the function falls through to `return False`, and
`valid_result` considers the finding valid.

Verified via:

```python
import json, subprocess

r = subprocess.run(
    ["slither", ".", "--filter-paths", "lib|test", "--json", "-"],
    capture_output=True,
    text=True,
)
d = json.loads(r.stdout)
for det in d["results"]["detectors"]:
    if det["check"] == "unindexed-event-address":
        print("elements:", det["elements"])
```

Output: `elements: []`.

**Why accept rather than suppress via alternative means.** Four options
were considered:

1. `slither.config.json` with `detectors_to_exclude: unindexed-event-address`
   — disables the detector globally, losing coverage on any future Aureum
   event with an unindexed address.
2. Patch the `VaultCreated` event to `event VaultCreated(address indexed vault)`
   — breaks upstream-verbatim invariant; `lib/balancer-v3-monorepo/pkg/vault/contracts/VaultFactory.sol#42`
   is the source of truth and we preserve its signature to minimize fork diff.
3. Upgrade Slither to a version that fixes the empty-elements bug —
   out of scope for Stage B; affects the rest of B6 if the new version
   changes other detector outputs.
4. **Chosen: accept and document.** The finding stays visible in every
   Slither run as `1 result(s) found`. The inline rationale comment at
   the event declaration references this `STAGE_B_NOTES.md` section.

**What changes if Slither is upgraded.** If a future Slither version fixes
the empty-elements bug, `unindexed-event-address` becomes suppressable
inline like every other detector. The remediation is a single edit:
add `// slither-disable-next-line unindexed-event-address` immediately
above the `event VaultCreated(address vault);` declaration, and remove the
"accepted residual" bullet from the housekeeping queue above. The inline
rationale comment can stay — it still documents why the event is not
changed to use `indexed`.

### Verification command for future runs

From project root, with `.venv` activated:

```bash
slither . --filter-paths "lib|test" 2>&1 | grep "result(s) found"
```

Expected output: `INFO:Slither:. analyzed (81 contracts with 100 detectors), 1 result(s) found`.
Anything other than `1 result(s) found` means either a new finding has
appeared (investigate) or the Slither empty-elements bug has been fixed
and the `VaultCreated` suppression needs to be applied inline (see above).
