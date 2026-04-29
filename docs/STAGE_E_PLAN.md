# Stage E — Pool-deployment framework + 3 pilot pools

> **Status:** Complete at `stage-e-complete` (commit `41a7590`, 2026-04-28). 168/168 tests green on mainnet fork (156 unit + 12 fork) per the D35 split-form invocation.
>
> **Audience:** Sagix, plus any future Claude session that needs to know what Stage E is and what it produces.
>
> **Why this file exists:** so the plan survives outside chat scrollback. This file is the entry point for Stage E work.

---

## Scope of Stage E

**Goal:** ship the parameterized pool-deployment framework and validate it by deploying three pilot Miliarium pools — **ixHelvetia (slot 01)**, **ixEdelweiss (slot 05)**, **ixAurebit (slot 14)** — chosen to span the framework's three template classes (two-asset, ixEDEL-heavy non-standard, canonical Standard 52/16/32). The 52% ERC-4626 Quality Gate enforcement lands at factory level via `AureumWeightedPoolFactory.sol`; Vault bytecode untouched.

**The Solidity files Stage E produces:**

1. **`src/factory/AureumWeightedPoolFactory.sol`** — Aureum-side factory peer-inherited from `BasePoolFactory` (per E-D11 in `docs/STAGE_E_NOTES.md`). Inherits `IPoolVersion, BasePoolFactory, Version`; implements its own external `create(...)` with the 52% ERC-4626 Quality Gate inline, reverting `QualityGateUnsatisfied(uint256 erc4626WeightSum, uint256 minRequired)` when `sum(weights[i] where tokenTypes[i] == WITH_RATE && rateProviders[i] != IRateProvider(address(0))) < 52e16`. Does **not** subclass `WeightedPoolFactory` — upstream's `create()` is `external` (not `virtual`) at `lib/balancer-v3-monorepo/pkg/pool-weighted/contracts/WeightedPoolFactory.sol:55-66`, so a subclass cannot `override` it, and inheriting it would expose a publicly-callable QG bypass. Constructor passes `type(WeightedPool).creationCode` to `BasePoolFactory` — same pool bytecode produced. Custom errors, not revert strings. No upgradability, no admin keys. Vault bytecode untouched; zero edits to `lib/balancer-v3-monorepo/`. ~80–120 LOC.

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
| **E-D3** | **52% ERC-4626 Quality Gate at factory level via `AureumWeightedPoolFactory.sol`** (new Aureum-side factory peer-inherited from `BasePoolFactory`; see E-D11 in `docs/STAGE_E_NOTES.md`). Implements its own external `create(...)` that reverts `QualityGateUnsatisfied(uint256 erc4626WeightSum, uint256 minRequired)` when `sum(weights[i] where tokenTypes[i] == WITH_RATE && rateProviders[i] != IRateProvider(address(0))) < 52e16`. The deploy script (`deploy-miliarium-pool.s.sol`) re-asserts the same condition before the factory call as belt-and-suspenders against a pool deployed via a non-Aureum factory. **Vault bytecode untouched; zero edits to `lib/balancer-v3-monorepo/`.** Peer-inheritance pattern (rather than subclassing `WeightedPoolFactory`) decided at E1 design time after grepping the upstream `WeightedPoolFactory.create(...)` signature: it is `external` not `virtual`, so a subclass cannot `override`, and a subclass would inherit upstream's `create()` as a publicly-callable QG bypass. The `STAGES_OVERVIEW.md` Stage E "Builds" bullet's "at Vault registration" wording supersedes at E5 docs. |
| **E-D4** | **Pilot Rate Provider + composition tables locked.** **ixHelvetia (slot 01):** svZCHF 80% (RP `0xf32dc0ee2cc78dca2160bb4a9b614108f28b176c`) + sUSDS 20% (RP `0x1195be91e78ab25494c855826ff595eef784d47b`); 100% ERC-4626. **ixEdelweiss (slot 05):** ixEDEL 46% (`0xe4a10951f962e6cB93Cb843a4ef05d2F99DB1F94`, STANDARD, no RP) + waEthUSDC 18% (`0xD4fa2D31b7968E448877f69A96DE69f5de8cD23E`, RP `0x8f4E8439b970363648421C692dd897Fb9c0Bd1D9`) + waEthUSDT 18% (`0x7Bc3485026Ac48b6cf9BaF0A377477Fff5703Af8`, RP `0xEdf63cce4bA70cbE74064b7687882E71ebB0e988`) + svZCHF 18% (RP per ixHelvetia); 54% ERC-4626 (margin: +2 pp). **ixAurebit (slot 14):** svZCHF 26% + Aave Prime GHO 26% (`0xC71Ea051a5F82c67ADcF634c36FFE6334793D24C`, RP `0x851b73c4BFd5275D47FFf082F9e8B4997dCCB253`) + ixEDEL 16% (STANDARD, no RP) + WBTC 16% (`0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599`, STANDARD, no RP) + cbBTC 16% (`0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf`, STANDARD, no RP); 52% ERC-4626 (margin: +0 pp, gate boundary case). All addresses + RPs verified in `aumm-site/07a_tokens.md` and the OQ-12 / OQ-12a resolution path. Aave Prime GHO is the Aave-issued ERC-4626 vault wrapping bare GHO; the bare GHO ERC-20 stablecoin (`0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f`) is distinct and not a pilot component — see E11 in `docs/STAGE_E_NOTES.md` for the rename rationale. Genesis swap fee 0.03% Miliarium default. |
| **E-D5** | **Mainnet-fork pool-init pattern (per D32):** β-pattern `Vault.unlock` → `IVault.initialize(pool, sender, tokens, exactAmountsIn, minBptAmountOut, wethIsEth, userData)` → per-token `IERC20.transfer(vault, amount)` → `IVault.settle(token, amount)`. **No Router. No Permit2.** Same idiom used in `test/fork/AureumFeeRoutingHook.t.sol` for D7's AuMM/svZCHF trading-pool init. The mainnet Balancer V3 Router is bound to mainnet Vault (per D32) and cannot operate against the Aureum Vault. |
| **E-D6** | **Test-harness layout:** shared parameterized fork-test base contract under `test/fork/PilotPools.t.sol`; per-pilot derived contracts (`IxHelvetiaForkTest`, `IxEdelweissForkTest`, `IxAurebitForkTest`) each set a unique env-key suffix (e.g. `IXHELVETIA_FEE_ROUTING_HOOK`, `IXEDELWEISS_FEE_ROUTING_HOOK`, `IXAUREBIT_FEE_ROUTING_HOOK`) to satisfy the D36 invariant. **Acceptance criterion (D36 closer):** *no two fork-test contracts in one `forge test` run may write the same `vm.setEnv` key.* This invariant is enforced at the harness level, not as a per-test workaround. The D35 split-form (`--no-match-path "test/fork/**"` for unit + `--match-path "test/fork/**" --fork-url $URL` for fork) remains the standard invocation. |
| **E-D7** | **Pool-init liquidity-source policy on fork:** `deal(token, address(this), amount, true)` per Foundry `StdCheats` — ERC-20s and ERC-4626 shares directly (matches D-D20 / D7 doctrine). Real `IERC4626.deposit(...)` paths are **not** used by default; if a future test asserts something that depends on real share issuance growth, it can use the real deposit path narrowly without changing the default. `deal` (unprefixed) is the token-balance cheat; `vm.deal` is the distinct native-ETH cheat — not interchangeable. |
| **E-D8** | **Branch model:** `stage-e` working branch from `main` (created from commit `57cd2ce` on 2026-04-25); `git push origin stage-e` early per the D9 lesson — don't let origin lag the local branch. Fast-forwards to `main` at E9; `stage-e-complete` lightweight tag applied on `main` at the tip. Preserve `stage-e` on origin as a snapshot marker per the C0 / D0 convention. No PR workflow. |
| **E-D9** | **Sub-step shape (B):** **E0** plan + notes scaffold (this file). **E1** framework + ixHelvetia (simplest pool validates framework end-to-end). **E2** ixEdelweiss. **E3** ixAurebit. **E4** integration tests + Quality Gate fail-case unit tests. **E5** docs (`STAGES_OVERVIEW.md` Stage E row + this file's Completion Log + `CLAUDE.md` §11 refresh). **E9** close (FF merge to main, tag, push). Final numbering may refine at E1 entry; broad shape is locked. |
| **E-D10** | **OQ-20 / OQ-21 status:** tracked, **not** Stage-E-resolved. Per-token `paysYieldFees: true` flags in pilot configs match the intended production semantics so configs are forward-compatible with the eventual OQ-20 controller yield-fee entry point and OQ-21 bi-weekly cadence. No controller-side yield-collection wiring lands at E. |

---

## Mid-stage supersessions

Decisions resolved during Stage E that revise values or framing locked in by the planning-stage decisions above. Each entry preserves the canonical record location in `docs/STAGE_E_NOTES.md` (full reasoning) and `docs/FINDINGS.md` (OQ marker). The lock table is left intact as historical context — read these supersessions alongside it.

### OQ-11 swap fees — Bodensee 0.75% immutable, Miliarium genesis 0.02% (2026-04-26)

Supersedes the tail clause of **E-D4** ("Genesis swap fee 0.03% Miliarium default.") and the original 2026-04-15 OQ-11 resolution. **Canonical record:** `docs/STAGE_E_NOTES.md` E-D22. **FINDINGS marker:** `docs/FINDINGS.md` OQ-11 (Status 2026-04-26 blockquote; original 2026-04-15 body preserved verbatim below the blockquote for audit reference).

Two values changed:

1. **Der Bodensee** — fee re-pinned at `0.0075e18` (0.75%) **immutable** from block 0 (`swapFeeManager: address(0)` at deployment, no governance lever); the 0.10%–1.00% governance-adjustable band is dropped. Re-aligns with the constitutional "deep-friction reserve" framing in `10_constitution.md` §xxix.
2. **Miliarium genesis** — `0.0003e18` (0.03%) → `0.0002e18` (0.02%); the 0.01%–0.30% band and `BLOCKS_PER_EPOCH` cooldown remain unchanged.

On-chain landings (E1.3a-quater through E1.3a-septies):

- `src/vault/AureumProtocolFeeController.sol` — `BODENSEE_SWAP_FEE_MIN/MAX` removed; `BODENSEE_SWAP_FEE_GENESIS` renamed to `BODENSEE_SWAP_FEE`; `MILIARIUM_SWAP_FEE_MIN/MAX/GENESIS` added.
- `test/unit/AureumProtocolFeeController.t.sol` — `test_BodenseeBand_Constants` → `test_SwapFeeConstants`, referencing the new constants.
- `script/DeployDerBodensee.s.sol` — `swapFeeManager: governanceMultisig` → `address(0)`, with natspec paragraph + inline comment.
- `test/fork/AureumFeeRoutingHook.t.sol` — `bodenseePool` `swapFeeManager` → `address(0)` with inline comment; `tradingPool` (non-Miliarium AuMM/svZCHF test pool, not subject to E-D22) retains `GOVERNANCE_MULTISIG`.

### E-D6 env-key suffix — superseded by E-D24 in-process pattern (2026-04-27)

Supersedes the wording in **E-D6** ("Shared parameterized base contract per E-D6; three derived contracts per pilot, each setting a unique env-key suffix to satisfy the D36 invariant") in the `test/fork/PilotPools.t.sol` plan line. **Canonical record:** `docs/STAGE_E_NOTES.md` E-D24.

The E-D6 wording assumed race-safety required per-contract key namespacing. E-D24 establishes that within Stage E, all three pilot test contracts write the E-D23 fixed env names with the *same value* (the deployed-once hook address from the shared base's `setUp`), making them race-safe without per-contract key suffixes. The `--threads 1` fork-suite invocation flag (D35 / D36) remains the cross-suite belt against legacy Stage D fork tests that write `FEE_ROUTING_HOOK` to conflicting addresses; it is a per-suite invocation flag, not a per-test harness workaround. No per-pool key suffix is introduced to `test/fork/PilotPools.t.sol`; the E-D23 fixed env names are used as-is.

### E10 deal(adjust=true) vs Reserve-DTF tokens — drop the third argument for ixEDEL compatibility (2026-04-27)

Supersedes the example in **E-D7** ("`deal(token, address(this), amount, true)`") and the corresponding example in the Stage E Builds section above ("Account funding via `deal(token, address(this), amount, true)`"). **Canonical record:** `docs/STAGE_E_NOTES.md` E10.

forge-std `deal()` third-argument `adjust=true` writes both the holder balance slot and the `totalSupply()` slot via heuristic. For tokens with dynamic `totalSupply()` like Reserve DTFs (ixEDEL — fee-decay accrual), no canonical supply slot exists; the supply-adjust path arithmetic-wraps and reverts panic 0x11 on first call. Fix: drop the third argument (`deal(token, holder, amount)`) — writes holder balance only, leaves `totalSupply()` untouched. Vault / WeightedPool initialization reads raw transferred balances during `IVault.settle`, not ERC20 `totalSupply()`, so the omission is functionally equivalent for the pool-init liquidity-source policy.

Mixed-decimal pilots additionally require per-token decimal-matched seed amounts in `_seedAmounts()` instead of a uniform `INIT_SEED` literal: ixEdelweiss `1_000e6 / 1_000e6 / 1_000e18 / 1_000e18` for waEthUSDT (6-dec) / waEthUSDC (6-dec) / ixEDEL (18-dec) / svZCHF (18-dec) at address-sorted slot order; ixAurebit similarly threads `1_000e8` for the 8-decimal WBTC and cbBTC slots alongside `1_000e18` for the three 18-decimal slots.

DTF-as-`tokenIn` swap-path consideration: the same `adjust=false` rule applies to `_performSwap` when `tokenIn` is a Reserve DTF; current `_performSwap` retains `adjust=true` because the deployed E2 / E3 representative swap vectors (waEthUSDC 6-dec, WBTC 8-dec) are not DTFs. A future ixAurebit or other-pilot vector using ixEDEL as `tokenIn` will need the same drop.

On-chain landing:

- **E2.3-fix** (`fd554c1`, 2026-04-27): `test/fork/PilotPools.t.sol` — drops `, true` from `_initializePool` mint loop at L302; per-decimal `_seedAmounts()` literals matched to address-sorted slot order at L383–L386; ixEdelweiss representative swap vector amended to `1e6` (not `1e18`) for 6-dec waEthUSDC at L393.


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
| E0 | 24a0e7d | 2026-04-26 | E0: docs/STAGE_E_PLAN.md + docs/STAGE_E_NOTES.md — Stage E scaffold |
| docs (E-D11–E-D15) | 793f504 | 2026-04-26 | docs: STAGE_E_NOTES.md E-D11–E-D15 + STAGE_E_PLAN.md E-D3 + FINDINGS.md OQ-14 — E1 pre-flight factory-pattern decisions |
| docs (E-D16) | 0037104 | 2026-04-26 | docs: STAGE_E_NOTES.md E-D16 — AureumWeightedPoolFactory additive; Bodensee retains upstream WPF |
| E1.1 | 472c023 | 2026-04-26 | E1.1: src/factory/AureumWeightedPoolFactory.sol |
| E1.2 | eabc787 | 2026-04-26 | E1.2: script/pools/PoolConfig.sol |
| docs (E-D17–E-D21) | 796787f | 2026-04-26 | docs: STAGE_E_NOTES.md E-D17–E-D21 — pilot-pool config decisions (token addresses, name/symbol, sectorLabel, salt, config artifact) |
| docs (E-D22) | 2b5d216 | 2026-04-26 | docs: STAGE_E_NOTES.md E-D22 — pilot swap fee 0.02% + Bodensee 0.75% immutable (OQ-11 supersession pointer) |
| docs (OQ-11 FINDINGS) | 92a5d89 | 2026-04-26 | docs: FINDINGS.md OQ-11 supersession — Bodensee 0.75% immutable + Miliarium genesis 0.02% |
| OQ-11 (src) | 46fee7b | 2026-04-26 | src: AureumProtocolFeeController.sol — BODENSEE_SWAP_FEE_GENESIS→BODENSEE_SWAP_FEE (rename); BODENSEE_SWAP_FEE_MIN/MAX removed; MILIARIUM_SWAP_FEE_MIN/MAX/GENESIS added (E-D22 / OQ-11 supersession) |
| OQ-11 (test) | cd0cc56 | 2026-04-26 | test: AureumProtocolFeeController.t.sol — test_BodenseeBand_Constants→test_SwapFeeConstants; BODENSEE_SWAP_FEE + MILIARIUM_SWAP_FEE_* constants (E-D22 / OQ-11) |
| OQ-11 (script) | dc62325 | 2026-04-26 | script: DeployDerBodensee.s.sol — swapFeeManager: address(0) (Bodensee fee immutable per E-D22 / OQ-11 supersession) |
| OQ-11 (test) | 778ecb5 | 2026-04-26 | test: AureumFeeRoutingHook.t.sol — bodenseePool swapFeeManager: address(0) (immutable per E-D22 / OQ-11 supersession) |
| docs (OQ-11 PLAN) | ece718f | 2026-04-26 | docs: STAGE_E_PLAN.md — Mid-stage supersessions section; OQ-11 swap fees (Bodensee 0.75% immutable, Miliarium genesis 0.02% / E-D22) |
| E1.3b | 0f53d65 | 2026-04-26 | E1.3b: script/pools/configs/01_ixHelvetia.s.sol — IxHelvetiaConfig per-pool config library (svZCHF 80% / sUSDS 20%, slot 01) |
| docs (E-D23) | 6a98eae | 2026-04-26 | docs: STAGE_E_NOTES.md E-D23 — deploy script architecture (abstract base + per-pilot wrappers, flat layout, env-var contract) |
| E1.4a | 9d6db38 | 2026-04-27 | E1.4a: script/pools/deploy-miliarium-pool.s.sol — MiliariumPoolDeployer abstract base (E-D23) |
| E1.4c | 36c6f88 | 2026-04-27 | E1.4c: script/pools/DeployIxHelvetia.s.sol — DeployIxHelvetia concrete wrapper (E-D23) |
| docs (E-D24) | 7276398 | 2026-04-27 | docs: STAGE_E_NOTES.md E-D24 — fork-test harness shape (in-process deployer, --threads 1 belt, INIT_SEED parity) |
| docs (E-D6→E-D24) | ec25324 | 2026-04-27 | docs: STAGE_E_PLAN.md — E-D6 env-key suffix superseded by E-D24 (mid-stage supersession) |
| E1.6a | 3f47f43 | 2026-04-27 | E1.6a: test/fork/PilotPools.t.sol — MiliariumPilotPoolBase abstract shared base |
| E1.6b | 041d517 | 2026-04-27 | E1.6b: test/fork/PilotPools.t.sol — IxHelvetiaPilotTest derived contract + fee-routing test |
| docs (E-D25) | e079457 | 2026-04-27 | docs: STAGE_E_NOTES.md E-D25 — E2 ixEdelweiss sub-step layout + locked decisions |
| E2.1 | 3289ade | 2026-04-27 | E2.1: script/pools/configs/05_ixEdelweiss.s.sol — IxEdelweissConfig per-pool config library (waEthUSDT 18% / waEthUSDC 18% / ixEDEL 46% / svZCHF 18%, slot 05) |
| E2.2 | cdd7a5d | 2026-04-27 | E2.2: script/pools/DeployIxEdelweiss.s.sol — concrete MiliariumPoolDeployer wrapper for ixEdelweiss (slot 05) |
| E2.3 | efb7a10 | 2026-04-27 | E2.3: test/fork/PilotPools.t.sol — IxEdelweissPilotTest derived contract + fee-routing test (waEthUSDC → svZCHF) |
| docs (E10) | 393cea0 | 2026-04-27 | docs: STAGE_E_NOTES.md E10 — forge-std deal(adjust=true) vs Reserve-DTF ixEDEL; per-decimal _seedAmounts() for mixed-decimal pilots |
| E2.3-fix | fd554c1 | 2026-04-27 | E2.3-fix: test/fork/PilotPools.t.sol — drop deal(adjust=true) in _initializePool, per-decimal _seedAmounts(), 1e6 swap vector (per E10) |
| docs (§11 mid) | 752c032 | 2026-04-28 | docs: CLAUDE.md §11 refresh — Stage E mid-stage (E1 + E2 closed, E3 ixAurebit next) |
| docs (E11) | 6a92d3c | 2026-04-28 | docs: STAGE_E_NOTES.md E11 — Aave Prime GHO naming convention locked; GHO misnaming corrected |
| docs (E11 sweep) | 5dec629 | 2026-04-28 | docs: E11.2–E11.6 rename sweep — GHO → Aave Prime GHO across STAGE_E_NOTES / STAGE_E_PLAN / FINDINGS / STAGES_OVERVIEW / CLAUDE.md §11 |
| E3.1 | 34ceacb | 2026-04-28 | E3.1: script/pools/configs/14_ixAurebit.s.sol — IxAurebitConfig per-pool config library (WBTC 16% / Aave Prime GHO 26% / cbBTC 16% / ixEDEL 16% / svZCHF 26%, slot 14) |
| E3.2 | 9a3bb18 | 2026-04-28 | E3.2: script/pools/DeployIxAurebit.s.sol — concrete MiliariumPoolDeployer wrapper for ixAurebit (slot 14) |
| E3.3 | 4a5fcb6 | 2026-04-28 | E3.3: test/fork/PilotPools.t.sol — IxAurebitPilotTest derived contract + fee-routing test (WBTC → svZCHF) |
| E4.1 | 3d35244 | 2026-04-28 | E4.1: test/unit/AureumWeightedPoolFactory.t.sol — QG revert-path unit tests (5 methods, mock vault, per E-D13) |
| docs (E-D26) | cf9fc37 | 2026-04-28 | docs: STAGE_E_NOTES.md E-D26 — E4 unit-test scope, E-D9 closure, Cursor NatSpec-hyperlink artifact |
| docs (§11 close) | ca24e5c | 2026-04-28 | docs: CLAUDE.md §11 refresh — Stage E mid-stage (E1+E2+E3+E4 closed, E5 docs / E9 close ahead) |
| docs (E10 PLAN) | 301d67b | 2026-04-28 | docs: STAGE_E_PLAN.md — E10 mid-stage supersession (deal(adjust=true) / E-D7 superseded) |
| docs (E-D26 amend) | 41a7590 | 2026-04-28 | docs: STAGE_E_NOTES.md E-D26 amendment — NatSpec-hyperlink artifact reclassified as paste-rendering (E5 docs sweep) |
