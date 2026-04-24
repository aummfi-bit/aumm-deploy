# Balancer V3 Reference

Canonical sources, addresses, wire-level signatures, and rules for the Balancer V3 code Aureum inherits from.

**Sources**: `docs.balancer.fi` (concepts, developer-reference, deployment-addresses), `github.com/balancer/balancer-deployments` (per-chain task JSONs), and the vendored submodule `lib/balancer-v3-monorepo` at commit `68057fda`. The submodule is authoritative for interface signatures and contract behavior; the deployment-addresses JSON under `balancer-deployments` is the git-grep-able anchor for addresses (the docs page renders them dynamically, so raw crawls show "Loading…").

Update this file when a Balancer V3 fact that matters to Aureum is pinned or corrected. Cross-referenced from STAGE_D_NOTES (D32 onward), STAGE_D_PLAN, and CLAUDE.md §11 (OQ-22 / D33 candidate).

## Canonical external references

| Resource | URL |
|---|---|
| Docs root | `https://docs.balancer.fi` |
| Concepts — introduction | `https://docs.balancer.fi/concepts/core-concepts/introduction.html` |
| Integration guides | `https://docs.balancer.fi/integration-guides/` |
| Developer reference | `https://docs.balancer.fi/developer-reference/` |
| Mainnet deployment addresses | `https://docs.balancer.fi/developer-reference/contracts/deployment-addresses/mainnet.html` |
| Sepolia deployment addresses | `https://docs.balancer.fi/developer-reference/contracts/deployment-addresses/sepolia.html` |
| ABI overview | `https://docs.balancer.fi/developer-reference/contracts/abi/` |
| `balancer-deployments` tasks tree | `https://github.com/balancer/balancer-deployments/tree/master/v3/tasks` |

## Submodule location

The Aureum-owned fork of Balancer V3 is at [`aummfi-bit/balancer-v3-monorepo`](https://github.com/aummfi-bit/balancer-v3-monorepo) and is added to this repo as a git submodule at `lib/balancer-v3-monorepo/`.

The submodule is **pinned** to a specific commit where `pkg/vault/contracts/VaultFactory.sol` matches the verified Etherscan source of the Balancer V3 Vault Factory deployed on Ethereum mainnet. The exact pinned commit is identified in Stage A Step A5 and recorded in `docs/STAGE_A_PLAN.md` Completion Log.

## Mainnet V3 addresses

From `balancer-deployments/v3/tasks/<task>/output/mainnet.json` and on-chain verification:

| Contract | Address | Notes |
|---|---|---|
| Balancer V3 Vault | `0xbA1333333333a1BA1108E8412f11850A5C319bA9` | The audited Vault Aureum inherits from. CREATE3 — same address on mainnet, Arbitrum, Optimism, Base. |
| Balancer V3 Vault Factory | `0xAc27df81663d139072E615855eF9aB0Af3FBD281` | The factory that deployed the Vault above. Aureum forks this into `src/AureumVaultFactory.sol` in Stage B. |
| Factory deployer (EOA) | `0x3877188e9e5da25b11fdb7f5e8d4fdddce2d2270` | Balancer's deployer EOA. Used for cross-referencing deployment transactions. |
| Factory deploy tx | `0x49a4986a672bcc20eecf99a3603f0099b19ab663eebe5dd5fe04808c380147b4` | Block 21332121, Dec 4, 2024. |
| Balancer V3 Router v2 | `0xAE563E3f8219521950555F5962419C8919758Ea2` | Task `20250307-v3-router-v2`. Immutably bound to the mainnet Vault — **unreachable for Aureum pools** (see Aureum-specific architectural implications §1 below). |
| Permit2 (Uniswap singleton) | `0x000000000022D473030F116dDEE9F6B43aC78BA3` | Cross-chain Uniswap Permit2. Required spender chain for any Router-mediated token pull (see Wire-level interface facts §5 below). |
| WETH | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` | Mainnet WETH. |

Aureum deploys its own Vault via `script/DeployAureumVault.s.sol`; the mainnet Router above is **not** reachable for Aureum-Vault-registered pools.

## Wire-level interface facts

### 1. `IVault.initialize` — 6 parameters

`lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVaultExtension.sol:139-146`:

    function initialize(
        address pool,
        address to,
        IERC20[] memory tokens,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external returns (uint256 bptAmountOut);

`onlyWhenUnlocked` + `nonReentrant`. Tokens must be in ascending address order (matches pool registration); the amounts array length must equal the registered token count.

### 2. `IRouter.initialize` — 7 parameters (adds `wethIsEth`)

`lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IRouter.sol:46-53`. The Router opens its own `_vault.unlock` and delegates to `Router.initializeHook`; the Vault never sees `wethIsEth`.

### 3. `Router.initializeHook` — canonical post-initialize settle loop

`lib/balancer-v3-monorepo/pkg/vault/contracts/Router.sol:75-116`. Inside `unlock`: call `_vault.initialize(...)` first, then per-token:

1. `if (amountIn == 0) continue;`
2. Move tokens to the Vault:
   - WETH branch: `_weth.deposit{value: amountIn}()` then `_weth.transfer(vault, amountIn)`.
   - Default: `_permit2.transferFrom(sender, vault, uint160(amountIn), token)`.
3. `_vault.settle(token, amountIn)` to reconcile the transient debit.

Without Permit2 (test-only path): substitute step 2 with `token.transfer(vault, amountIn)` from whichever address holds the balances (e.g., the test contract after `deal`).

### 4. `Vault.unlock` — callback via `msg.sender.functionCall(data)`

`unlock(bytes calldata data) external transient returns (bytes memory result)`. The Vault calls back into `msg.sender` with `data` as calldata (OpenZeppelin `Address.functionCall`). The callback must be `external` on the caller; inside it, `msg.sender == address(vault)` is the correct guard.

The `transient` modifier requires every token delta opened during the call to net to zero by end of execution; otherwise the Vault reverts with `BalanceNotSettled`. Every credit side (`sendTo`, BPT mint to `to`) pairs with a debit side (`transfer-to-vault + settle`).

### 5. Permit2 approval chain (for any Router-mediated pull)

Two approvals per token, once per test-account:

1. `IERC20(token).approve(PERMIT2, maxAllowance)` — user authorises Permit2.
2. `IAllowanceTransfer(PERMIT2).approve(token, spender, uint160(amount), uint48(expiration))` — user authorises a specific Permit2 spender (e.g., Router) for amount + deadline.

Only after both does `Router._permit2.transferFrom(user, vault, amount, token)` succeed.

## Files Aureum imports from the submodule

### Vault core (byte-identical — never modify)

| File | Role in Aureum |
|---|---|
| `pkg/interfaces/contracts/vault/IVault.sol` | Main interface for all Vault ops |
| `pkg/interfaces/contracts/vault/IVaultMain.sol` | Swap, add/remove liquidity |
| `pkg/interfaces/contracts/vault/IVaultExtension.sol` | Pool registration, queries |
| `pkg/interfaces/contracts/vault/IVaultAdmin.sol` | Pause, recovery, `setProtocolFeeController` |
| `pkg/interfaces/contracts/vault/IVaultErrors.sol` | All custom errors |
| `pkg/interfaces/contracts/vault/IVaultEvents.sol` | All events |
| `pkg/interfaces/contracts/vault/VaultTypes.sol` | Shared structs |
| `pkg/interfaces/contracts/vault/IAuthorizer.sol` | **Implemented by `AureumAuthorizer.sol`** |
| `pkg/interfaces/contracts/vault/IProtocolFeeController.sol` | **Implemented by `AureumProtocolFeeController.sol`** |
| `pkg/vault/contracts/Vault.sol` | Deployed byte-identically via `AureumVaultFactory` |
| `pkg/vault/contracts/VaultExtension.sol` | Deployed byte-identically |
| `pkg/vault/contracts/VaultAdmin.sol` | Deployed byte-identically |
| `pkg/vault/contracts/ProtocolFeeController.sol` | **Reference only** — Aureum replaces this with its own impl |

### Forked (modified)

| File | Modification |
|---|---|
| `pkg/vault/contracts/VaultFactory.sol` | Forked into `src/AureumVaultFactory.sol`. Diff: ~5 lines to accept an external `IProtocolFeeController` via constructor parameter instead of deploying the stock one inline. |

### Not used in Stage A or B (noted for future reference)

Pool factories (`WeightedPoolFactory`, `StablePoolFactory`), routers (`Router`, `BatchRouter`, `BufferRouter`), and math libraries (`FixedPoint`, `WeightedMath`, `StableMath`) are needed in future stages for der Bodensee Pool deployment and Miliarium Aureum pool creation. They are not touched in `aumm-deploy`.

## Key Balancer V3 constraints (verified from source)

- **Max tokens per pool:** 8 (`MAX_TOKENS`, all pool types)
- **Max tokens in Stable Pool:** 5 (`MAX_STABLE_TOKENS`, StableSwap math limit)
- **Max protocol swap fee:** 50% (`MAX_PROTOCOL_SWAP_FEE_PERCENTAGE`) — **this is why Aureum routes 50% to Bodensee and 50% stays with LPs; 100% protocol fee is not permitted by the Vault**
- **Max protocol yield fee:** 50% (`MAX_PROTOCOL_YIELD_FEE_PERCENTAGE`)
- **Max pause window:** 4 years (`_MAX_PAUSE_WINDOW_DURATION`)
- **Max buffer period:** 180 days (`_MAX_BUFFER_PERIOD_DURATION`)
- **Min weight in Weighted Pool:** 1% (`_MIN_WEIGHT`)
- **Min swap fee:** 0.001% (Weighted Pool)
- **Max swap fee:** 10% (Weighted Pool)
- **Token sort order:** addresses must be registered in ascending order
- **Rebasing tokens:** not supported
- **Max token decimals:** 18

## Aureum-specific architectural implications

### 1. Router's immutable `IVault` binding

Balancer V3's `Router` is constructed with a single-immutable `IVault` (see `RouterCommon` constructor). The mainnet Router at `0xAE56…` is bound to the mainnet Vault at `0xbA13…`. Aureum's fork-deployed Vault is a distinct contract at a distinct address; the mainnet Router cannot address pools registered in Aureum's Vault.

Consequences:

- **Fork tests.** `IRouter(mainnet_router).initialize(aureumPool, …)` reverts. Either (α) deploy a fresh `new Router(IVault(address(aureumVault)), IWETH(weth), IPermit2(permit2), "…")` at test time, or (β) bypass Router entirely via `Vault.unlock` + direct `Vault.initialize` + `Vault.settle`. Stage D's D7.1e uses (β); see STAGE_D_NOTES D32.
- **Production user-facing path.** Same binding rules out the mainnet Router for Aureum pools — see "Open architectural question — Aureum's own Router (D33 candidate)" below.

### 2. OQ-22 (redefined)

Originally framed in the D7 Gate 3 plan as "pin the mainnet Router for fork-test use." The §1 binding above invalidates that framing. OQ-22 is retained as a **documentation anchor** — the mainnet Router address is recorded here and in CLAUDE.md §11 for reference — but fork tests do not call it. STAGE_D_NOTES D32 records the (β) pivot; the D33 candidate (below) tracks the surviving production question.

### 3. What's not load-bearing for Aureum (Stage D)

- **BatchRouter / BufferRouter / CompositeLiquidityRouter.** Multi-pool swap paths, ERC-4626 buffer ops, nested-pool liquidity. The fee-routing hook and current Stage D pool set do not use these.
- **Sepolia addresses.** Fork target is mainnet; Sepolia is a pattern cross-check only.
- **ABI overview page.** Supplementary for frontend / off-chain. The vendored submodule is authoritative for Solidity imports.

## Rules for LLM-assisted Solidity work

These rules are copied to `.cursorrules` at the repo root so Cursor enforces them in-editor. They are repeated here as documentation.

1. **Read the actual file.** When writing code that calls into Balancer V3, open the actual file in `lib/balancer-v3-monorepo/pkg/...` and read the function signature. Never write a call from memory.
2. **Quote the signature before writing the call.** In a comment or mental note, write out the exact function signature being called. Then write the call. Then verify once more.
3. **Check `IVaultErrors.sol` for revert reasons.** If a call might revert, identify which error is emitted and handle or document it.
4. **Never modify Balancer V3 source.** The ONE exception is the factory fork in `src/AureumVaultFactory.sol`, with a constrained diff.
5. **If a type or import cannot be resolved, follow the chain.** Do not guess at definitions. If the chain leads outside the submodule, check whether the dependency is installed under `lib/`.

## Pinning rationale

The audit-inheritance argument is only valid against the bytecode Balancer actually audited and shipped. This bytecode corresponds to a specific commit in the Balancer V3 monorepo. The submodule MUST be pinned to that commit. Tracking `main` would drift away from the audited state as upstream evolves.

The pinning procedure is documented in `docs/STAGE_A_PLAN.md` Step A5. The pinned commit hash is recorded in the Completion Log.

## Verifying the pin matches mainnet

To confirm the submodule's `VaultFactory.sol` matches what's deployed on mainnet:

1. Fetch the verified source from Etherscan: <https://etherscan.io/address/0xAc27df81663d139072E615855eF9aB0Af3FBD281#code>
2. Compare against `lib/balancer-v3-monorepo/pkg/vault/contracts/VaultFactory.sol` at the pinned commit.
3. They should be identical modulo import path formatting (Etherscan flattens imports; the monorepo uses `@balancer-labs/...` remapped imports).

The same verification should be done for `Vault.sol`, `VaultAdmin.sol`, `VaultExtension.sol` — these are the three files that MUST remain byte-identical.

## Open architectural question — Aureum's own Router (D33 candidate)

**Question.** Does Aureum deploy its own Router (bound to `AUREUM_VAULT`) for production user-facing interactions with Aureum pools?

**Why it surfaces here.** The immutable `IVault` binding (Aureum-specific architectural implications §1) rules out reusing the mainnet Router for Aureum pools. A production UX that swaps / adds-liquidity against Aureum pools needs some Router-like entry point. Options:

- Deploy Aureum's own `Router` (vault-bound), shipped alongside `DeployAureumVault`.
- Ship a thin Aureum-specific wrapper around `Vault.unlock` for the UX.
- Rely on third-party aggregators to deploy their own routing infrastructure against Aureum pools.

Not a Stage D blocker; not answered here. Logged for a later-stage (K / governance, or Stage O / integration) decision. Tracked as the **D33 candidate** in STAGE_D_NOTES.
