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
