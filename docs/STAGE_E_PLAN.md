# Stage E — Pool-deployment framework + 3 pilot pools

> **Status:** Ready to start. Stage D is complete at `stage-d-complete` (commit `951c338`, 2026-04-25). Prerequisites checked and green on 2026-04-25: 160/160 tests green on mainnet fork (151 unit + 9 fork) per the D35 split-form invocation.
>
> **Audience:** Sagix, plus any future Claude session that needs to know what Stage E is and what it produces.
>
> **Why this file exists:** so the plan survives outside chat scrollback. This file is the entry point for Stage E work.

---

## Scope of Stage E

**Goal:** ship the parameterized pool-deployment framework and validate it by deploying three pilot Miliarium pools — **ixHelvetia (slot 01)**, **ixEdelweiss (slot 05)**, **ixAurebit (slot 14)** — chosen to span the framework's three template classes (two-asset, ixEDEL-heavy non-standard, canonical Standard 52/16/32). The 52% ERC-4626 Quality Gate enforcement lands at factory level via `AureumWeightedPoolFactory.sol`; Vault bytecode untouched.

**The Solidity files Stage E produces:**

1. **`src/factory/AureumWeightedPoolFactory.sol`** — Aureum-side shim around Balancer V3's `WeightedPoolFactory`. Inherits from upstream `WeightedPoolFactory` and overrides / wraps `create(...)` to revert `QualityGateUnsatisfied()` when `sum(weights[i] where tokenTypes[i] == WITH_RATE && rateProviders[i] != IRateProvider(address(0))) < 52e16`. Custom errors, not revert strings. No upgradability, no admin keys. Vault bytecode untouched. ~80–120 LOC. Override-vs-wrap pattern decided at E1 design time after grepping `lib/balancer-v3-monorepo/pkg/pool-weighted/contracts/WeightedPoolFactory.sol`.

2. **`script/pools/deploy-miliarium-pool.s.sol`** — parameterized Foundry deployment script. Reads a `PoolConfig` struct from a per-pool config file, asserts the 52% Quality Gate condition (belt-and-suspenders against direct factory bypass), calls `AureumWeightedPoolFactory.create(...)` with the config's tokens / weights / rate providers / role accounts / swap fee, then attaches the Stage D fee-routing hook. Genesis swap fee per pool from the config file (Miliarium genesis 0.03% per `aumm-site/04_tokenomics.md` §x worked example). Mainnet-broadcast wiring deferred to Stage R; Stage E exercises the script fork-only.

3. **`script/pools/configs/01_ixHelvetia.s.sol`**, **`05_ixEdelweiss.s.sol`**, **`14_ixAurebit.s.sol`** — per-pool config files. Each exports `function config() pure returns (PoolConfig)`. `PoolConfig` struct fields: `string name`, `string symbol`, `uint8 slot`, `string sectorLabel`, `address[] tokens` (sorted ascending by address per Balancer V3 registration convention), `TokenType[] tokenTypes`, `IRateProvider[] rateProviders`, `bool[] paysYieldFees`, `uint256[] normalizedWeights`, `uint256 swapFeePercentage`, `bytes32 salt`. Composition tables locked at E-D4.

**The tests Stage E produces:**

- **`test/unit/AureumWeightedPoolFactory.t.sol`** — mock-backed unit tests on the Quality Gate logic. Cover: pass at 52% boundary, revert at 51% (just below), revert at multi-token configurations dropping below 52%, pass at 100% all-ERC-4626, behavior when rate provider is non-zero but `tokenType == STANDARD` (excluded from gate sum). Uses Balancer's `BaseVaultTest` stack per D-D17 doctrine.

- **`test/fork/PilotPools.t.sol`** — mainnet-fork integration. Shared parameterized base contract per E-D6; three derived contracts per pilot, each setting a unique env-key suffix to satisfy the D36 invariant. Per pilot: deploy via `deploy-miliarium-pool.s.sol`, initialize liquidity via β-pattern (`Vault.unlock` → `IVault.initialize` → per-token `transfer` → `settle`, no Router, no Permit2, per E-D5 / D32), execute a representative swap, verify hook fires correctly and fee routes to der Bodensee. Account funding via `deal(token, address(this), amount, true)` per E-D7 (matches D-D20 / D7 doctrine).

**The directory additions Stage E performs:**

- Create `src/factory/` for `AureumWeightedPoolFactory.sol`.
- Create `script/pools/` and `script/pools/configs/` for the framework script and per-pool configs.

No directory reorganization at Stage E — Stages B / C / D pinned the existing layout.

---

## Pragma note (Stage B vs C vs D vs E)

Stage B's `AureumVaultFactory.sol` and `AureumProtocolFeeController.sol` use `pragma solidity ^0.8.24` — upstream Balancer V3 inheritance, deliberate byte-identity with audited source. Stage B's `AureumAuthorizer.sol` uses `^0.8.26`. Stage C / Stage D Aureum-authored contracts use `^0.8.26` per cursorrules rule 4.

**Stage E `AureumWeightedPoolFactory.sol` inherits from upstream `WeightedPoolFactory` and therefore uses `pragma solidity ^0.8.24`** — same upstream-inheritance pattern as Stage B's `AureumVaultFactory` precedent. Aureum-authored Stage E files (`deploy-miliarium-pool.s.sol`, per-pool configs, tests) use `^0.8.26`. Both pragmas coexist in the compilation set — `solc 0.8.26` satisfies both carets.

If any E-executing Claude proposes "upgrading" the factory to `^0.8.26` "for consistency," refuse: byte-identity with upstream's pragma regime is the audit-inheritance foundation per CLAUDE.md §1.

---

## Import-path convention note

Stage C pinned `src/`-rooted paths for intra-Aureum sibling imports. Stage E follows the same convention:

- `import {AureumWeightedPoolFactory} from "src/factory/AureumWeightedPoolFactory.sol";`
- `import {AureumFeeRoutingHook} from "src/fee_router/AureumFeeRoutingHook.sol";`
- `import {AureumProtocolFeeController} from "src/vault/AureumProtocolFeeController.sol";`

External imports continue to use the remapped forms:

- `import {WeightedPoolFactory} from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";`
- `import {IRateProvider} from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";`
- `import {TokenConfig, TokenType, PoolRoleAccounts} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";`
- `import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";`

Exact paths under `@balancer-labs/v3-*` are verified against the submodule at E1 (pinned at commit `68057fda`, section 2 of CLAUDE.md). If a path doesn't exist where expected, the submodule layout wins — stop and grep `lib/balancer-v3-monorepo/` rather than guessing.

---

## Decisions locked in before Stage E starts

These are the answers to the planning-stage questions resolved before this file was written. They are recorded here so implementation doesn't re-litigate them.

| ID | Decision |
|----|----------|
| **E-D1** | **Stage E scope:** parameterized pool-deployment framework + factory-level 52% Quality Gate + 3 pilot pools (ixHelvetia / ixEdelweiss / ixAurebit). **Not in scope:** gauge approval (G), CCB scoring (F), AuMT minting (I), the remaining 25 Miliarium pools (M / N), `MiliariumRegistry.sol` (J — pilot-pool addresses are reserved for J to seed at slots 01 / 05 / 14, but the registry contract itself is Stage J), governance-path fee adjustment (K), Incendiary (L), mainnet deployment (R). Pilot trio chosen to span template classes: ixHelvetia (two-asset 100% ERC-4626 baseline), ixEdelweiss (46% ixEDEL non-standard hub), ixAurebit (canonical Standard 52/16/32, exactly at 52% gate boundary). ixCambio (slot 07) dropped from the pilot trio — aEURS lacks a deployed mainnet address per `aumm-site/07a_tokens.md`; deferred post-Stage E. |
| **E-D2** | **Parameter file format:** `.s.sol` Solidity structs at `script/pools/configs/<NN>_<Name>.s.sol`, each exporting `function config() pure returns (PoolConfig)`. Compile-time typing; no JSON parsing surface; matches `script/DeployDerBodensee.s.sol`'s inline shape. `PoolConfig` struct fields: `string name`, `string symbol`, `uint8 slot`, `string sectorLabel`, `address[] tokens` (sorted ascending), `TokenType[] tokenTypes`, `IRateProvider[] rateProviders`, `bool[] paysYieldFees`, `uint256[] normalizedWeights`, `uint256 swapFeePercentage`, `bytes32 salt`. The earlier `STAGES_OVERVIEW.md` Stage E "Builds" bullet's "JSON or `.s.sol` struct" framing and `02_ixHelvetia.json`-style paths supersede at E5 docs. |
| **E-D3** | **52% ERC-4626 Quality Gate at factory level via `AureumWeightedPoolFactory.sol`** (new Aureum-side shim around upstream `WeightedPoolFactory`). The override or wrap exposes a public entry that reverts `QualityGateUnsatisfied()` when `sum(weights[i] where tokenTypes[i] == WITH_RATE && rateProviders[i] != IRateProvider(address(0))) < 52e16`. The deploy script (`deploy-miliarium-pool.s.sol`) re-asserts the same condition before the factory call as belt-and-suspenders against a pool deployed via a non-Aureum factory. **Vault bytecode untouched.** Override-vs-wrap pattern decided at E1 design time after grepping the upstream `WeightedPoolFactory.create(...)` virtual signature. The `STAGES_OVERVIEW.md` Stage E "Builds" bullet's "at Vault registration" wording supersedes at E5 docs. |
| **E-D4** | **Pilot Rate Provider + composition tables locked.** **ixHelvetia (slot 01):** svZCHF 80% (RP `0xf32dc0ee2cc78dca2160bb4a9b614108f28b176c`) + sUSDS 20% (RP `0x1195be91e78ab25494c855826ff595eef784d47b`); 100% ERC-4626. **ixEdelweiss (slot 05):** ixEDEL 46% (`0xe4a10951f962e6cB93Cb843a4ef05d2F99DB1F94`, STANDARD, no RP) + waEthUSDC 18% (`0xD4fa2D31b7968E448877f69A96DE69f5de8cD23E`, RP `0x8f4E8439b970363648421C692dd897Fb9c0Bd1D9`) + waEthUSDT 18% (`0x7Bc3485026Ac48b6cf9BaF0A377477Fff5703Af8`, RP `0xEdf63cce4bA70cbE74064b7687882E71ebB0e988`) + svZCHF 18% (RP per ixHelvetia); 54% ERC-4626 (margin: +2 pp). **ixAurebit (slot 14):** svZCHF 26% + GHO 26% (`0xC71Ea051a5F82c67ADcF634c36FFE6334793D24C`, RP `0x851b73c4BFd5275D47FFf082F9e8B4997dCCB253`) + ixEDEL 16% (STANDARD, no RP) + WBTC 16% (`0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599`, STANDARD, no RP) + cbBTC 16% (`0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf`, STANDARD, no RP); 52% ERC-4626 (margin: +0 pp, gate boundary case). All addresses + RPs verified in `aumm-site/07a_tokens.md` and the OQ-12 / OQ-12a resolution path. Genesis swap fee 0.03% Miliarium default. |
| **E-D5** | **Mainnet-fork pool-init pattern (per D32):** β-pattern `Vault.unlock` → `IVault.initialize(pool, sender, tokens, exactAmountsIn, minBptAmountOut, wethIsEth, userData)` → per-token `IERC20.transfer(vault, amount)` → `IVault.settle(token, amount)`. **No Router. No Permit2.** Same idiom used in `test/fork/AureumFeeRoutingHook.t.sol` for D7's AuMM/svZCHF trading-pool init. The mainnet Balancer V3 Router is bound to mainnet Vault (per D32) and cannot operate against the Aureum Vault. |
| **E-D6** | **Test-harness layout:** shared parameterized fork-test base contract under `test/fork/PilotPools.t.sol`; per-pilot derived contracts (`IxHelvetiaForkTest`, `IxEdelweissForkTest`, `IxAurebitForkTest`) each set a unique env-key suffix (e.g. `IXHELVETIA_FEE_ROUTING_HOOK`, `IXEDELWEISS_FEE_ROUTING_HOOK`, `IXAUREBIT_FEE_ROUTING_HOOK`) to satisfy the D36 invariant. **Acceptance criterion (D36 closer):** *no two fork-test contracts in one `forge test` run may write the same `vm.setEnv` key.* This invariant is enforced at the harness level, not as a per-test workaround. The D35 split-form (`--no-match-path "test/fork/**"` for unit + `--match-path "test/fork/**" --fork-url $URL` for fork) remains the standard invocation. |
| **E-D7** | **Pool-init liquidity-source policy on fork:** `deal(token, address(this), amount, true)` per Foundry `StdCheats` — ERC-20s and ERC-4626 shares directly (matches D-D20 / D7 doctrine). Real `IERC4626.deposit(...)` paths are **not** used by default; if a future test asserts something that depends on real share issuance growth, it can use the real deposit path narrowly without changing the default. `deal` (unprefixed) is the token-balance cheat; `vm.deal` is the distinct native-ETH cheat — not interchangeable. |
| **E-D8** | **Branch model:** `stage-e` working branch from `main` (created from commit `57cd2ce` on 2026-04-25); `git push origin stage-e` early per the D9 lesson — don't let origin lag the local branch. Fast-forwards to `main` at E9; `stage-e-complete` lightweight tag applied on `main` at the tip. Preserve `stage-e` on origin as a snapshot marker per the C0 / D0 convention. No PR workflow. |
| **E-D9** | **Sub-step shape (B):** **E0** plan + notes scaffold (this file). **E1** framework + ixHelvetia (simplest pool validates framework end-to-end). **E2** ixEdelweiss. **E3** ixAurebit. **E4** integration tests + Quality Gate fail-case unit tests. **E5** docs (`STAGES_OVERVIEW.md` Stage E row + this file's Completion Log + `CLAUDE.md` §11 refresh). **E9** close (FF merge to main, tag, push). Final numbering may refine at E1 entry; broad shape is locked. |
| **E-D10** | **OQ-20 / OQ-21 status:** tracked, **not** Stage-E-resolved. Per-token `paysYieldFees: true` flags in pilot configs match the intended production semantics so configs are forward-compatible with the eventual OQ-20 controller yield-fee entry point and OQ-21 bi-weekly cadence. No controller-side yield-collection wiring lands at E. |

---

## What is explicitly NOT in Stage E

- Gauge registry, gauge approval, eligibility checker — Stage G.
- CCB engine (EMA, scoring, multiplier) — Stage F.
- AuMT token + LP receipt — Stage I.
- Emission distributor — Stage H.
- `MiliariumRegistry.sol` — Stage J. Pilot-pool addresses *are* reserved at slots 01 / 05 / 14 for J's seeding step, but the registry contract itself is Stage J.
- The remaining 25 Miliarium pools (slots 02–04, 06, 08–13, 15–28) — Stages M / N.
- ixCambio (slot 07) — deferred post-Stage E pending aEURS mainnet listing.
- Governance-path fee adjustment, gauge approval mechanism, governance handoff — Stage K.
- Incendiary Boost — Stage L.
- Aureum's own Router — D33 deferred, post-D / re-entry at K or O.
- OQ-20 controller yield-fee entry point — post-D, tracked.
- OQ-21 bi-weekly cadence throttle — post-D, tracked.
- Mainnet deployment of factory + pilot pools — Stage R.
- Frontend integration — `aumm-app` separate repo, separate plan.

---

## Sub-steps

> Sub-step bodies populate as they are planned. This section's headers are placeholders for E0 through E9 detail.

### E0 — Plan + notes scaffold

### E1 — Framework + ixHelvetia

### E2 — ixEdelweiss

### E3 — ixAurebit

### E4 — Integration + Quality Gate fail-case tests

### E5 — Docs

### E9 — Close

---

## Completion Log

| Sub-step | Commit | Date | Summary |
|----------|--------|------|---------|
