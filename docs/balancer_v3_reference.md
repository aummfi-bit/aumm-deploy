# Balancer V3 Reference

Canonical sources for the Balancer V3 code Aureum inherits from, and rules for working with them.

## Submodule location

The Aureum-owned fork of Balancer V3 is at [`aummfi-bit/balancer-v3-monorepo`](https://github.com/aummfi-bit/balancer-v3-monorepo) and is added to this repo as a git submodule at `lib/balancer-v3-monorepo/`.

The submodule is **pinned** to a specific commit where `pkg/vault/contracts/VaultFactory.sol` matches the verified Etherscan source of the Balancer V3 Vault Factory deployed on Ethereum mainnet. The exact pinned commit is identified in Stage A Step A5 and recorded in `docs/STAGE_A_PLAN.md` Completion Log.

## Key mainnet addresses

| Contract | Address | Role |
|---|---|---|
| Balancer V3 Vault | `0xbA1333333333a1BA1108E8412f11850A5C319bA9` | The audited Vault Aureum inherits from. Same address on mainnet, Arbitrum, Optimism, Base — CREATE3 deployment. |
| Balancer V3 Vault Factory | `0xAc27df81663d139072E615855eF9aB0Af3FBD281` | The factory that deployed the Vault above. Aureum forks this into `src/AureumVaultFactory.sol` in Stage B. |
| Factory deployer | `0x3877188e9e5da25b11fdb7f5e8d4fdddce2d2270` | Balancer's deployer EOA. Used for cross-referencing deployment transactions. |
| Factory deploy tx | `0x49a4986a672bcc20eecf99a3603f0099b19ab663eebe5dd5fe04808c380147b4` | Block 21332121, Dec 4, 2024. |

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
