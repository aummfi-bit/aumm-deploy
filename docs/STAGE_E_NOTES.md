# Stage E — Living design + findings log

> **Status:** Stage E open at the `stage-e` branch from `main` (commit `57cd2ce` on 2026-04-25). Companion to `docs/STAGE_E_PLAN.md`.
>
> **Audience:** Sagix, plus any future Claude session that needs the running log of decisions resolved during implementation and the incidents caught at audit.
>
> **Why this file exists:** to keep design decisions resolved *during* implementation (not pre-locked at plan-authoring time) and implementation findings out of the plan file. `docs/STAGE_E_PLAN.md` is the operational document — sub-step bodies, verbatim commit messages, the Completion Log. This file is the living archive.

---

## How this file is organized

- **Design decisions during implementation (`E-D11` onward).** `E-D1` through `E-D10` are pre-locked in `docs/STAGE_E_PLAN.md`'s "Decisions locked in before Stage E starts" table. Any new design decision resolved *during* E1 / E2 / E3 / E4 / E5 gets the next free `E-D*` number and is recorded in this file's next subsection — not retro-edited into the plan file. Matches the `C-D*` / `D-D*` convention.
- **Findings (`E10` onward).** Implementation incidents, drift caught at audit, RPC quirks, env-key surprises, scope-expansion catches, contract-interface gotchas — anything worth a numbered log entry. Numbered from `E10` to avoid collision with `E-D*` planning codes (matches the `C10` / `D10` pattern in `docs/STAGE_C_NOTES.md` and `docs/STAGE_D_NOTES.md`).
- **Cross-reference convention** (per `CLAUDE.md` §5): `E-Dn` = planning decision n; `En` (n ≥ 10) = implementation finding n; `OQ-N` = open question N from `docs/FINDINGS.md`. `Cn` / `Dn` codes carry forward across stages — Stage E entries can cite `D32` or `D36` directly without re-explaining.

---

## Design decisions during implementation

### E-D11 — Pattern: peer-inheritance from `BasePoolFactory` (2026-04-26)

`AureumWeightedPoolFactory` inherits `IPoolVersion, BasePoolFactory, Version` and implements its own external `create(...)` with the 52% ERC-4626 Quality Gate inline. It does **not** subclass `WeightedPoolFactory`.

Three reasons: (1) upstream `WeightedPoolFactory.create()` is `external` (not `virtual`) at `lib/balancer-v3-monorepo/pkg/pool-weighted/contracts/WeightedPoolFactory.sol:55-66` — Solidity does not permit a subclass `override`; (2) a subclass would inherit upstream's `create()` as a publicly-callable bypass of the QG, defeating the gate at the contract level; (3) Stage B's `AureumVaultFactory` precedent — Stage B's factory is its own contract built on the same upstream primitives, not a subclass of `VaultFactory`.

`BasePoolFactory` exposes the deployment glue (`_create`, `_registerPoolWithVault`, `getDefaultLiquidityManagement`) as `internal` / `public`, so peer-inheritance reaches the same building blocks upstream `WeightedPoolFactory` uses. The constructor passes `type(WeightedPool).creationCode` to `BasePoolFactory`, identical to upstream — same pool bytecode produced.

**OQ-14 supersession (2026-04-26).** OQ-14 in `docs/FINDINGS.md` (resolved 2026-04-15) headlined "no `AureumWeightedPoolFactory` fork" — Aureum was to use upstream factories directly with QG enforcement at deployment-script-side. E-D3 + E-D11 supersede that headline. The replacement statement: **a new `src/factory/AureumWeightedPoolFactory.sol` peer-inherited from `BasePoolFactory`, zero edits to `lib/balancer-v3-monorepo/`, same pool bytecode produced.** This preserves OQ-14's underlying invariant — don't muck with Balancer's vendored `WeightedPoolFactory` source — while replacing OQ-14's headline that ruled out a new Aureum-side factory contract entirely. Reason for supersession: factory-level enforcement makes the QG non-bypassable for "pools this repo's scripts create"; script-only enforcement could be silently skipped if the deploy script were ever modified or replaced. See `docs/FINDINGS.md` OQ-14 Status block (added at E1.0b) for the FINDINGS-side record.

### E-D12 — `PoolConfig` lives in `script/pools/PoolConfig.sol` (2026-04-26)

Types-only file — one `struct PoolConfig`, no contract, no logic. Both `script/pools/deploy-miliarium-pool.s.sol` and `script/pools/configs/<NN>_*.s.sol` import `PoolConfig` from there. Avoids the cross-script import (`import {PoolConfig} from "script/pools/deploy-miliarium-pool.s.sol";`) and keeps the deploy script focused on logic. Struct fields per E-D2 in `docs/STAGE_E_PLAN.md`: `string name`, `string symbol`, `uint8 slot`, `string sectorLabel`, `address[] tokens`, `TokenType[] tokenTypes`, `IRateProvider[] rateProviders`, `bool[] paysYieldFees`, `uint256[] normalizedWeights`, `uint256 swapFeePercentage`, `bytes32 salt`.

### E-D13 — QG predicate per OQ-12 / OQ-12a wording (2026-04-26)

The 52% ERC-4626 Quality Gate sums `normalizedWeights[i]` for each `i` where `tokens[i].tokenType == TokenType.WITH_RATE` AND `tokens[i].rateProvider != IRateProvider(address(0))`. Reverts `QualityGateUnsatisfied(uint256 erc4626WeightSum, uint256 minRequired)` if the sum is below `MIN_ERC4626_WEIGHT = 52e16` (52% scaled by `FixedPoint.ONE = 1e18`).

**Predicate locked to OQ-12 / OQ-12a wording (with E11 underlying-vs-wrapper distinction).** OQ-12a's resolution table in `docs/FINDINGS.md` (L863–870) classifies underlying tokens by type: svZCHF, st-EURA, aEURS (and by extension waEthUSDC, waEthUSDT) are "ERC-4626" — gate-eligible; ixEDEL (Reserve DTF), the bare GHO stablecoin (`0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f`, ERC-20), WBTC, cbBTC, tGBP, JPYC are "ERC-20" / "ERC-20 (Reserve DTF)" — gate-ineligible at the underlying-token level. The Solidity-level predicate `WITH_RATE && rateProvider != address(0)` matches that classification at registration time: a directly-registered underlying token registers as `TokenType.WITH_RATE` with a non-zero Rate Provider iff it is gate-eligible; a gate-ineligible underlying registers as `TokenType.STANDARD` with no Rate Provider.

**ERC-4626 wrappers of gate-ineligible underlyings are themselves gate-eligible when registered with a non-zero Rate Provider.** Aave Prime GHO (`0xC71Ea051a5F82c67ADcF634c36FFE6334793D24C`, RP `0x851b73c4BFd5275D47FFf082F9e8B4997dCCB253`) is the Aave-issued ERC-4626 vault wrapping bare GHO; it registers as `TokenType.WITH_RATE` with a non-zero RP and contributes its full weight to the QG sum. The classification is per-token-as-registered, not per-underlying-asset. See E11 for the canonical record of this distinction and the rename sweep that removed the prior conflation of "GHO" between the bare stablecoin and the Aave Prime GHO wrapper.

**STANDARD-with-RP edge case excluded by design.** A token registered with `TokenType.STANDARD` *and* a non-zero Rate Provider (legal under Balancer V3) does not contribute to the QG sum. Reason: a Rate Provider attached to a STANDARD-typed token does not feed yield-fee accrual into the Vault's accounting, so its weight does not represent ERC-4626 share-stack participation in the OQ-12a sense. If a future pool uses a STANDARD-with-RP token (e.g. a price oracle attached to a non-yielding asset), it is correctly excluded from the gate sum. Recorded here so the audit-relevant interpretation is not re-litigated at review.

Implementation guards: pre-loop `WeightsLengthMismatch(uint256 tokensLength, uint256 weightsLength)` check guards against array out-of-bounds; loop bounded by upstream `WeightedPool` `MAX_TOKENS = 8`.

### E-D14 — Pragma split: `^0.8.24` for factory, `^0.8.26` for siblings (2026-04-26)

`src/factory/AureumWeightedPoolFactory.sol` uses `pragma solidity ^0.8.24` to match the upstream `BasePoolFactory` and `WeightedPoolFactory` pragma — preserves the upstream-inheritance pragma regime that underlies the audit-inheritance strategy. Stage E sibling files (`script/pools/PoolConfig.sol`, `script/pools/deploy-miliarium-pool.s.sol`, `script/pools/configs/*.s.sol`, `test/unit/AureumWeightedPoolFactory.t.sol`, `test/fork/PilotPools.t.sol`) use `pragma solidity ^0.8.26` per `.cursorrules` rule 4.

Compiler is `solc 0.8.26` per `foundry.toml`; both carets coexist in the compilation set. Same pattern as Stage B's `AureumVaultFactory.sol` (`^0.8.24`, upstream-inheritance) vs `AureumAuthorizer.sol` (`^0.8.26`, Aureum-authored).

### E-D15 — License: `GPL-3.0-or-later` for all Stage E files (2026-04-26)

`SPDX-License-Identifier: GPL-3.0-or-later` for all Stage E files — matches upstream `BasePoolFactory` / `WeightedPoolFactory` and Stage B's `AureumVaultFactory.sol`. No license boundary mid-tree.

### E-D16 — AureumWeightedPoolFactory is additive; Bodensee + Stage D pipeline retain upstream WPF (2026-04-26)

`src/factory/AureumWeightedPoolFactory.sol` (new at E1) is additive — used only by `script/pools/deploy-miliarium-pool.s.sol` to deploy Miliarium pools under the 52% ERC-4626 Quality Gate. Bodensee and the existing Stage D fork pipeline (`script/DeployAureumWeightedPoolFactory.s.sol` → `script/DeployDerBodensee.s.sol`, plus `test/fork/AureumFeeRoutingHook.t.sol` and `test/fork/DeployAureumVault.t.sol` consumers) continue to use upstream `WeightedPoolFactory` via the current `WEIGHTED_POOL_FACTORY` env contract — unchanged at Stage E.

**Why additive, not unified.** Migrating the Stage D Bodensee deploy chain to the new Aureum-side factory would force every fork path that exercises `DeployAureumVault` → `DeployAureumWeightedPoolFactory` → `DeployDerBodensee` to re-qualify under the new factory before the Miliarium script is itself proven in isolation — a real triage cost for the benefit of one factory symbol in the repo. Bodensee's 40/30/30 (AuMM 40% STANDARD, sUSDS 30% WITH_RATE+RP, svZCHF 30% WITH_RATE+RP) is already 60% ERC-4626 on the QG sum, so unification would not change Bodensee's economics. Stage E's purpose per E-D1 / E-D3 is the Miliarium framework + factory-level QG; re-baselining Stage D's Bodensee bootstrap is out of that scope.

**Implementation contract.** `script/pools/deploy-miliarium-pool.s.sol` (new at E1) instantiates or references `AureumWeightedPoolFactory` and never reaches into the `WEIGHTED_POOL_FACTORY` env that Bodensee uses; the Miliarium env-key naming is decided at E1.5 (deploy-script sub-step). `script/DeployAureumWeightedPoolFactory.s.sol` (the Stage D script) and `script/DeployDerBodensee.s.sol` retain their existing upstream `WeightedPoolFactory` import and the `WEIGHTED_POOL_FACTORY` env contract — neither file is edited at Stage E.

**Naming ambiguity acknowledged.** `script/DeployAureumWeightedPoolFactory.s.sol` (Stage D) deploys upstream's `WeightedPoolFactory` but its filename reads as "deploys `AureumWeightedPoolFactory`" once `src/factory/AureumWeightedPoolFactory.sol` lands at E1.1 — readable but ambiguous. A one-line clarifying comment in the script's NatSpec is targeted for E5 (docs phase). **Rename of `script/DeployAureumWeightedPoolFactory.s.sol` is out of scope for Stage E unless pulled in as its own sub-step.**

### E-D17 — Token addresses hardcoded as address constant literals in pilot configs (2026-04-26)

`script/pools/configs/<NN>_*.s.sol` declare token vault addresses as address constant literals at file scope, consumed inline by function config(). The pure constraint locked at E-D2 precludes vm.envAddress(...) indirection — pure is a hard property of the function selector, not a soft preference.

Canonical mainnet vault addresses for the pilot trio are anchored to aumm-site/07a_tokens.md (rows 58–59 for sUSDS / svZCHF; additional rows for ixEDEL, waEthUSDC, waEthUSDT, Aave Prime GHO, WBTC, cbBTC where pilot composition requires them per E-D4), with in-repo provenance via the docs/STAGE_D_NOTES.md D1 probe table (live getRate() values recorded at fork-pin block):

svZCHF — 0xE5F130253fF137f9917C0107659A4c5262abf6b0 (rate provider 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c)
sUSDS — 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD (rate provider 0x1195BE91e78ab25494C855826FF595Eef784d47B)
script/DeployDerBodensee.s.sol and the Stage D fork-test fleet retain the vm.envAddress("SV_ZCHF") / vm.envAddress("SUSDS") lookup pattern unchanged per E-D16 (additive). Pilot configs and Stage D env values describe the same canonical mainnet contracts; consistency is established by .env-side population, not by source-tree linkage.

### E-D18 — name / symbol convention for Miliarium pilot pools (2026-04-26)

`name` field — verbatim canonical pool name from `aumm-site/06_miliarium_manifest.md` §xiii. ixHelvetia → "ixHelvetia", ixEdelweiss → "ixEdelweiss", ixAurebit → "ixAurebit". No "Aureum" / "Miliarium" prefix; the canonical lower-camel ix-prefix name is the brand surface.

`symbol` field — ALL-CAPS of the canonical name, ix-prefix uppercased uniformly. ixHelvetia → "IXHELVETIA", ixEdelweiss → "IXEDELWEISS", ixAurebit → "IXAUREBIT". Parallel to Bodensee's "der-Bodensee" / "BODENSEE" (`script/DeployDerBodensee.s.sol:70-71`): on-chain symbol is uppercase-uniform across the repo.

Mixed-case alternative "ixHELVETIA" (preserving the ix semantic prefix in the symbol) considered and declined: would invent a one-off Miliarium-specific casing rule diverging from the Bodensee precedent, and the ix mark is preserved at the name field's lower-camel form for human-facing surfaces.

### E-D19 — sectorLabel content + two-axis taxonomy note (2026-04-26)

`PoolConfig.sectorLabel` carries the finer sector label verbatim from `aumm-site/06_miliarium_manifest.md` §xiii column "Sector". Pilot trio:

ixHelvetia (slot 01) — "Frankencoin MMA"

ixEdelweiss (slot 05) — "Routing Infrastructure"

ixAurebit (slot 14) — "Digital Gold / Bitcoin"

Two-axis manifest taxonomy. Per `aumm-site/06_miliarium_manifest.md` §xiv, each Miliarium pool carries two orthogonal labels: registry category (five-way split: Yield / Bonds / Crypto-native gov / Stocks / Metals) and sector (the finer profile-file label captured here). `PoolConfig` carries the sector axis only; the registry-category axis is not in-config at Stage E. Recorded so Stage J does not assume `sectorLabel` is the five-way split.

`registryCategory` deferred. Adding string `registryCategory` to `PoolConfig` is cheap mechanically (one field, all consumers re-touched) but widens every per-pool config file to carry a string the deploy script does not consume. Deferred until Stage J (`MiliariumRegistry.sol`) or Stage G (gauge-eligibility) demonstrates an in-config requirement to key off the five-way category from the same struct the deploy script reads. Tracked here, not promoted to OQ-* status; if J / G design pulls it in, a follow-up E-D* (or its stage-equivalent) extends `PoolConfig` and bumps `script/pools/PoolConfig.sol` before the per-pool consumers are re-touched.

### E-D20 — Salt strategy: slot-derived bytes32(uint256(slot)) (2026-04-26)

Pilot-pool salts are slot-derived literals: `bytes32(uint256(1))` for ixHelvetia, `bytes32(uint256(5))` for ixEdelweiss, `bytes32(uint256(14))` for ixAurebit. The convention scales to all 28 Miliarium slots without collision, is trivially readable in source, and requires no hash computation at config-write time.

Stage E is fork-only (E-D5) so create3 address determinism is cosmetic at this stage; the convention establishes the salt pattern for Stage M / N production deploys. A future provenance-tagged variant — for example `keccak256(abi.encode("aureum-miliarium", uint256(slot), uint64(chainId)))` — is recordable at Stage R if production deployment policy requires pilot-vs-mainnet address differentiation. Slot-only is sufficient for Stage E and the lock carries forward to Stage M / N unless a later stage explicitly revises.

### E-D21 — Config artifact shape: per-pool library + Bodensee-tier NatSpec (2026-04-26)

Each per-pool config file is a Solidity library with a single internal pure function config():

library IxHelvetiaConfig {
    function config() internal pure returns (PoolConfig memory) { ... }
}
Caller idiom: `import { IxHelvetiaConfig } from "script/pools/configs/01_ixHelvetia.s.sol";` `PoolConfig memory cfg = IxHelvetiaConfig.config();`. `internal` visibility keeps the function inlined at call site (no external dispatch overhead in the deploy script). Free-function alternative considered and declined — would pollute the global function namespace as the framework scales to 28 configs, and a per-file function `ixHelvetiaConfig()` rename is uglier than `IxHelvetiaConfig.config()`.

NatSpec richness matches the `script/DeployDerBodensee.s.sol` precedent: file-level `@title` / `@notice` / `@dev` block with cross-references to manifest row, E-D17 (token addresses), E-D18 (name / symbol), E-D19 (`sectorLabel`), E-D20 (salt), and E-D4 in `docs/STAGE_E_PLAN.md` (composition lock). Inline NatSpec on `config()` lists the composition (token / weight / RP / `paysYieldFees` triples) and explicitly notes the ascending-address sort decision applied at literal-write time.

### E-D22 — Pilot-pool initial swap fee `0.0002e18` (0.02%); Bodensee 0.75% immutable (2026-04-26)

Miliarium pilot pools (and by extension all 28 Miliarium pools) initialize at `swapFeePercentage = 0.0002e18` (0.02%), governance-adjustable within OQ-11's revised band of 0.01% – 0.30% (`MILIARIUM_SWAP_FEE_MIN = 0.0001e18`, `MILIARIUM_SWAP_FEE_MAX = 0.003e18`, `MILIARIUM_SWAP_FEE_GENESIS = 0.0002e18`). Per-pool `swapFeeManager` is `governanceMultisig` so the rate is reachable through the standard governance proposal path with `BLOCKS_PER_EPOCH` cooldown.

Der Bodensee retains `swapFeePercentage = 0.0075e18` (0.75%) as **immutable** from block 0 — `swapFeeManager: address(0)` at deployment, no governance lever. This reverts the 2026-04-15 OQ-11 resolution's Bodensee-band stance (0.10% – 1.00% governance-adjustable) and re-aligns Bodensee with the constitutional "deep-friction reserve" framing (`10_constitution.md` §xxix) and the long-standing in-spec assertion of "0.75% immutable" across `aumm-site` (`docs/FINDINGS.md` L197).

**Why the genesis revision (0.03% → 0.02%).** The 2026-04-15 genesis figure was anchored on a "stable-pair routing tier" reading. Pilot-pool composition spans FX-with-yield (ixHelvetia), routing infrastructure (ixEdelweiss), and yield-bearing BTC (ixAurebit); 0.02% better positions Miliarium pools as low-friction routing infrastructure inside the Aureum mesh while preserving the 0.30% upper bound for governance to react to volume / TVL conditions.

**Why the Bodensee revision (governance-adjustable → immutable).** The 2026-04-15 governance-adjustable framing introduced a real policy lever that conflicted with the constitutional and tokenomic framing of Bodensee as a structurally immutable reserve. Re-pinning to `address(0)` matches the audit-visible `swapFeeManager` pattern for "no one can change," removes a governance attack surface, and aligns code with the dominant `aumm-site` narrative.

**Stage D scope acknowledgment.** This revision modifies `src/vault/AureumProtocolFeeController.sol` (constants — remove `BODENSEE_SWAP_FEE_MIN` and `BODENSEE_SWAP_FEE_MAX`; rename `BODENSEE_SWAP_FEE_GENESIS` to `BODENSEE_SWAP_FEE` with immutability NatSpec — the `_GENESIS` suffix loses meaning once Bodensee carries a single, perpetual value; add `MILIARIUM_SWAP_FEE_MIN`, `MILIARIUM_SWAP_FEE_MAX`, `MILIARIUM_SWAP_FEE_GENESIS`) and `script/DeployDerBodensee.s.sol` (`swapFeeManager: governanceMultisig` → `address(0)`). Both are policy-parameter adjustments to existing Stage D surfaces, not architectural changes; E-D16's "Bodensee + Stage D pipeline unchanged at Stage E" framing covered the factory architecture, not the swap-fee policy parameters.

`docs/FINDINGS.md` OQ-11 supersession is recorded at E1.3a-ter as a layered 2026-04-26 revision under the original 2026-04-15 resolution.

### E-D23 — Deploy script architecture: abstract base + per-pilot wrappers, flat layout (2026-04-26)

The Miliarium framework deploy script is split into a single abstract base + thin per-pilot concrete wrappers:

- `script/pools/deploy-miliarium-pool.s.sol` — `abstract contract MiliariumPoolDeployer is Script`. Exposes `_config() internal pure virtual returns (PoolConfig memory)` and a concrete `run() external returns (address pool)`. The base reads env vars, builds the `TokenConfig[]` from `cfg.tokens / cfg.tokenTypes / cfg.rateProviders / cfg.paysYieldFees`, builds `PoolRoleAccounts`, performs the QG belt-and-suspenders re-assertion (per `docs/STAGE_E_PLAN.md` E-D3), and calls `AureumWeightedPoolFactory.create(...)`.
- `script/pools/Deploy<PoolName>.s.sol` — concrete wrapper per pilot pool (`DeployIxHelvetia` at E1.4c, `DeployIxEdelweiss` at E2, `DeployIxAurebit` at E3). Each is ~5–10 lines: import the matching `*Config` library, override `_config()` to return its `config()`. No other logic in the wrapper.

**Why abstract-base + wrappers (not single-contract dispatch).** Three reasons:

1. **Explicit `<file>:<contract>` binding.** Invocation is `forge script script/pools/DeployIxHelvetia.s.sol:DeployIxHelvetia ...` — the path-and-name pair is the source of truth. No env-var dispatch (e.g. `POOL_KEY=ixHelvetia`) that can silently bind to the wrong config on a typo.
2. **Additive at scale.** Adding the 27 remaining Miliarium pools means one new wrapper file per pool — purely additive, no edits to a central dispatch table that would grow linearly with pool count and concentrate merge conflicts on one file.
3. **Matches the Stage D Bodensee precedent.** `script/DeployDerBodensee.s.sol` is one concrete script per deliverable, not a multiplexer. Stage A's `DeployAureumAuthorizer.s.sol` and Stage B's `DeployAureumVault.s.sol` follow the same shape. The Miliarium wrappers extend that style under `script/pools/`.

**Why flat (not a `script/pools/deployers/` subdirectory).** Co-locates the abstract base, `PoolConfig.sol`, `configs/`, and the per-pilot wrappers under the single `script/pools/` bracket. Consistent with the existing top-level layout — `script/*.s.sol` is flat, and the only nested directory under `script/pools/` is `configs/` for the per-pool config libraries. A `script/pools/deployers/` (or `entrypoints/`) split is recordable as an optional refactor at Stage R if many one-off / chain-specific pool scripts proliferate; Stage E does not need it.

**Env-var contract for the abstract base:**

- `AUREUM_WEIGHTED_POOL_FACTORY` — address of `src/factory/AureumWeightedPoolFactory.sol` (deployed at E1.1; new env var introduced here at E1.4 first use; parallels the existing `AUREUM_VAULT` naming).
- `FEE_ROUTING_HOOK` — existing Stage D env var, address of the deployed `AureumFeeRoutingHook`. Passed as the `poolHooksContract` argument to `AureumWeightedPoolFactory.create(...)`. Same hook is shared by Bodensee and all gauged Miliarium pools (the hook routes fees TO Bodensee from any attached pool).
- `GOVERNANCE_MULTISIG` — existing Stage A env var. Used for both `pauseManager` and `swapFeeManager` on Miliarium pools.

`WEIGHTED_POOL_FACTORY` (the existing env var pointing to the upstream Balancer `WeightedPoolFactory`) is **not** read by this script — that env continues to serve only the Stage D Bodensee chain per E-D16.

**Pool role accounts (Miliarium):**

- `pauseManager: governanceMultisig`
- `swapFeeManager: governanceMultisig` — Miliarium swap fee is governance-adjustable within OQ-11's revised 0.01%–0.30% band per E-D22 (contrast Bodensee's `swapFeeManager: address(0)` immutability).
- `poolCreator: address(0)` — consistent with Bodensee and with the factory's `StandardPoolWithCreator` revert when non-zero.

**QG belt-and-suspenders re-assertion.** Before calling `AureumWeightedPoolFactory.create(...)`, the abstract base sums `cfg.normalizedWeights[i]` for each `i` where `cfg.tokenTypes[i] == TokenType.WITH_RATE && cfg.rateProviders[i] != IRateProvider(address(0))`; reverts with a deploy-script-side `QualityGateUnsatisfied(uint256 erc4626WeightSum, uint256 minRequired)` if the sum is below `52e16`. The factory enforces the same predicate at the contract level (E1.1) — this script-side check is defense-in-depth per `docs/STAGE_E_PLAN.md` E-D3 against (a) a future config-library bug producing a sub-52% composition (caught at script time before contract deployment), and (b) hypothetical reuse of this script against a non-Aureum factory.

**Pool initialization is out of scope.** `AureumWeightedPoolFactory.create(...)` deploys + registers the pool with the Vault (per Stage D D28). Initial liquidity (β-pattern `Vault.unlock` + `IVault.initialize` + per-token `transfer` + `settle`, per E-D5 / D32) is the responsibility of the fork-test harness at E1.6, not the deploy script.

### E-D24 — Fork-test harness shape: in-process deployer, --threads 1 belt, INIT_SEED parity (2026-04-27)

The Stage E pilot-pool fork tests live in `test/fork/PilotPools.t.sol` and follow a shared-base + per-pilot-derived-contract layout. Six closed decisions:

**Invocation pattern — in-process, not `forge script` simulation.** Each derived test contract instantiates its concrete deployer directly: `DeployIxHelvetia ixHelvetiaDeployer = new DeployIxHelvetia();`, sets the three E-D23 fixed env names (`AUREUM_WEIGHTED_POOL_FACTORY`, `FEE_ROUTING_HOOK`, `GOVERNANCE_MULTISIG`) via `vm.setEnv` in `setUp()`, then calls `ixHelvetiaDeployer.run()`. No `forge script` binary path, no script-name dispatch — normal Solidity calls under the test's deploy chain. This honors the E-D23 env-var contract as-shipped without any rework of the deployer API.

**D36 race revisited — `--threads 1` is the cross-suite belt, not a structural defect of the harness.** The D36 race was specifically about *two flows writing the same env key with conflicting values* under default Foundry parallelism (`AureumFeeRoutingHook.t.sol` and `DeployAureumVault.t.sol` both wrote `FEE_ROUTING_HOOK` to incompatible addresses). Within Stage E itself, all three pilot test contracts (`IxHelvetiaPilotTest`, `IxEdelweissPilotTest`, `IxAurebitPilotTest`) write the same E-D23 env names with the *same value* (the deployed-once hook address from the shared base's `setUp`), so they are race-safe internally. The `--threads 1` flag on the fork-suite invocation per D35 / D36 remains required as a belt against the legacy Stage D fork tests that still write `FEE_ROUTING_HOOK` to their own predicted addresses — a per-suite flag, not a per-test workaround. **Supersedes** the E-D6 plan-stage wording "unique env-key suffix per derived contract": that wording assumed race-safety required per-contract key namespacing, which is true only for value-conflicting writes; same-value writes within a stage are race-safe under the E-D23 env-var contract. PLAN.md mid-stage supersession entry follows at the next sub-step.

**Shared base + per-pilot derived contracts.** `MiliariumPilotPoolBase` is `abstract contract MiliariumPilotPoolBase is Test` at the top of `test/fork/PilotPools.t.sol`. It exposes virtual hooks `_deployer() internal returns (MiliariumPoolDeployer)` and `_seedAmounts() internal pure returns (uint256[] memory)`, performs the full Stage D + E1.1 deployment chain (Vault, hook, controller, der-Bodensee, controller wiring, AureumWeightedPoolFactory) in `setUp()`, and provides shared β-pattern `_initializePool(address pool, IERC20[] memory tokens, uint256[] memory amountsIn)` and `_performSwap(address pool, IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn)` helpers. Each pilot's derived contract (`IxHelvetiaPilotTest` and the future `IxEdelweissPilotTest` / `IxAurebitPilotTest`) overrides `_deployer()` and `_seedAmounts()`; otherwise inherits all deploy + init + swap plumbing.

**INIT_SEED — `1_000e18` per token, Bodensee parity.** Same constant value as `test/fork/AureumFeeRoutingHook.t.sol`'s `INIT_SEED = 1_000e18`. The harness writes `amountsIn[i] = INIT_SEED` for every token regardless of normalizedWeights. Rationale: (a) style continuity with the D fork test makes side-by-side reading direct; (b) the test's purpose is "enough liquidity to swap and observe fee routing," not a TVL or geometric-mean-price assertion; (c) the representative swap is small (1e18 of one token) so the off-axis curve excursion from a 1:1 raw seed against the 20:80 ixHelvetia weights is negligible for the fee-routing assertion. Weight-aligned raw amounts (e.g. `200e18` sUSDS + `800e18` svZCHF) would falsely imply the test is making an economic claim it does not.

**β-pattern liquidity init wiring.** Mirrors `test/fork/AureumFeeRoutingHook.t.sol:L299-L329`: `vault.unlock(abi.encodeCall(this._initializePoolCallback, (...)))`, callback asserts `msg.sender == address(vault)`, calls `vault.initialize(pool, address(this), tokens, amountsIn, 0, "")`, then for each token transfers `amountsIn[i]` to the Vault and calls `vault.settle(token, amountsIn[i])`. Tokens are funded via `deal(token, address(this), amount, true)` per E-D7 immediately before the unlock. No Router, no Permit2, per E-D5 / D32.

**Representative swap and fee-landing assertion.** Single direction per E-D7: sUSDS → svZCHF, 1e18 sUSDS in. The swap callback mirrors `test/fork/AureumFeeRoutingHook.t.sol:L367-L385`: inside `vault.unlock`, call `vault.swap(EXACT_IN, ixHelvetiaPool, sUSDS, svZCHF, 1e18, 0, "")`, then `transfer(sUSDS) + settle + sendTo(svZCHF)`. The hook fires via the Vault's onAfterSwap dispatch under the same open unlock; recursion-guard at `params.router == address(this)` short-circuits the hook's own nested-swap leg per D10. Fee-landing assertion mirrors `test/fork/AureumFeeRoutingHook.t.sol:L480-L489`: snapshot `IERC20(DER_BODENSEE).totalSupply()` before the swap; after the swap, assert `IERC20(DER_BODENSEE).totalSupply() > bptSupplyBefore` (one-sided add minted new BPT) and `SV_ZCHF.balanceOf(address(hook)) == 0` (hook swept its full svZCHF balance into Bodensee). This pair is *fee-token-agnostic by design* — whichever token the Vault collects the fee in (sUSDS or svZCHF on ixHelvetia), the hook's two-phase routing converts to svZCHF and adds to Bodensee, so the assertion never has to name the specific fee-token side.

**Sub-step layout.** **E1.6a** — `MiliariumPilotPoolBase` shared base contract (deploy chain in `setUp`, β-pattern `_initializePool` and `_performSwap` helpers, virtual `_deployer` and `_seedAmounts`). **E1.6b** — `IxHelvetiaPilotTest` derived contract (overrides + `test_Fork_IxHelvetia_DeploysAndRoutesFee()` body). Edelweiss + Aurebit derived contracts land at E2 / E3 atop the same base, with their own derived-contract sub-steps.

### E-D25 — E2 ixEdelweiss sub-step layout + locked decisions (2026-04-27)

E2 ships ixEdelweiss (slot 05) atop the E1 framework with no new framework artifacts. Five sub-steps, each one §8e.1 + commit:

- **E2.1** — `script/pools/configs/05_ixEdelweiss.s.sol`: `IxEdelweissConfig` library mirroring `IxHelvetiaConfig` shape (E-D21). `internal constant` literals for the four token addresses + three Rate Provider addresses; `function config() internal pure returns (PoolConfig memory)` returning the locked composition. NatSpec block cross-references E-D4 (composition lock), E-D17 (token addresses sourcing), E-D18 (`name = "ixEdelweiss"`, `symbol = "IXEDELWEISS"`), E-D19 (`sectorLabel = "Routing Infrastructure"`), E-D20 (`salt = bytes32(uint256(5))`), E-D21 (library shape), and E-D22 (`swapFeePercentage = 0.0002e18`).
- **E2.2** — `script/pools/DeployIxEdelweiss.s.sol`: ~17-line concrete wrapper inheriting `MiliariumPoolDeployer` (E-D23), overriding `_config()` to return `IxEdelweissConfig.config()`. Mirrors `script/pools/DeployIxHelvetia.s.sol`.
- **E2.3** — `IxEdelweissPilotTest` derived contract appended to `test/fork/PilotPools.t.sol`, atop `MiliariumPilotPoolBase` (E-D24). Overrides `_deployer()` (returns `new DeployIxEdelweiss()`) and `_seedAmounts()` (returns four `INIT_SEED` literals). Test method `test_Fork_IxEdelweiss_DeploysAndRoutesFee()` mirrors the E1.6b body shape: `assertTrue(pilotPool != address(0))`, snapshot `IERC20(bodenseePool).totalSupply()`, perform swap, assert BPT supply expansion + `svZchf.balanceOf(address(hook)) == 0`.
- **E2.4** — Single-test fork run: `forge test --match-path "test/fork/PilotPools.t.sol" --match-test "test_Fork_IxEdelweiss" --fork-url $MAINNET_RPC_URL -vv --threads 1`.
- **E2.5** — Full fork-suite regression: `forge test --match-path "test/fork/**" --fork-url $MAINNET_RPC_URL -vv --threads 1`. Expect 11/11 (the 10 confirmed at E1.6b + IxEdelweiss).

**Composition recap (locked by E-D4 + E-D17, sorted ascending-address at literal-write time per E-D21):** index 0 waEthUSDT (`0x7Bc3485026Ac48b6cf9BaF0A377477Fff5703Af8`, WITH_RATE, RP `0xEdf63cce4bA70cbE74064b7687882E71ebB0e988`, `0.18e18`, `paysYieldFees: true`); index 1 waEthUSDC (`0xD4fa2D31b7968E448877f69A96DE69f5de8cD23E`, WITH_RATE, RP `0x8f4E8439b970363648421C692dd897Fb9c0Bd1D9`, `0.18e18`, `paysYieldFees: true`); index 2 ixEDEL (`0xe4a10951f962e6cB93Cb843a4ef05d2F99DB1F94`, STANDARD, no RP, `0.46e18`, `paysYieldFees: false`); index 3 svZCHF (`0xE5F130253fF137f9917C0107659A4c5262abf6b0`, WITH_RATE, RP `0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c`, `0.18e18`, `paysYieldFees: true`). ERC-4626 weight sum = `0.54e18` (54%); clears the 52% Quality Gate (E-D3) by +2 pp.

**E2.3 swap direction — `waEthUSDC → svZCHF`, 1e18 in.** Continuity with E1.6b's `sUSDS → svZCHF` (same structural story: ERC-4626-with-RP → svZCHF), so the new fork test reads as "same fee-routing story, next pool." The fee-landing assertion is fee-token-agnostic per E-D24, so the choice is about coverage breadth across pilots, not correctness. STANDARD-token-input coverage is reserved for E3 (ixAurebit) where WBTC / cbBTC / ixEDEL provide three STANDARD-typed `tokenIn` candidates.

**Constants exposure in derived test.** Pilot-specific tokens (waEthUSDC) accessed via `IxEdelweissConfig.WAETHUSDC` qualifier in `IxEdelweissPilotTest`. The `MiliariumPilotPoolBase` carries only svZCHF + sUSDS as base-contract state because Bodensee composition requires both at base-contract `setUp` (E-D24); pilot-specific tokens stay scoped to their pilot's config library to avoid base-contract bloat as more pilots land at E3 / Stage M / N.

**INIT_SEED parity per E-D24.** `[INIT_SEED, INIT_SEED, INIT_SEED, INIT_SEED]` (four `1_000e18` literals). Equal-amount seeding with uneven 18/18/46/18 weights produces a valid initial Balancer-V3 weighted-pool invariant; the 1e18 representative swap is small enough that the off-axis curve excursion against the 18/46 differential is negligible for the fee-routing assertion, matching the same rationale that justifies INIT_SEED parity at ixHelvetia's 20/80 differential.

**Cross-suite race expectations.** `IxEdelweissPilotTest`'s `setUp` writes the same E-D23 fixed env names (`AUREUM_WEIGHTED_POOL_FACTORY`, `FEE_ROUTING_HOOK`, `GOVERNANCE_MULTISIG`) that `IxHelvetiaPilotTest` writes; each pilot test contract independently re-runs the full deploy chain in its own `setUp`, producing the same env values from the same nonce-prediction sequence. Same-value writes are race-safe per E-D24; the `--threads 1` flag remains required as the cross-suite belt against legacy Stage D fork tests writing `FEE_ROUTING_HOOK` to its own predicted addresses.
### E-D26 — E4 unit-test scope: mock-vault revert-path-only, boundary case via pilot fork; NatSpec backtick-hyperlink artifact (2026-04-28)

**Scope of `test/unit/AureumWeightedPoolFactory.t.sol` (E4.1, commit `3d35244`).** Five revert-path tests exercising the factory's deterministic guards before any Vault interaction:

- `test_RevertWhen_QGSubFiftyTwo_NoERC4626Tokens` — all `TokenType.STANDARD`, QG sum = `0`, expects `QualityGateUnsatisfied(0, 52e16)`.
- `test_RevertWhen_QGSubFiftyTwo_PartialERC4626` — 60% STANDARD + 40% WITH_RATE+RP, QG sum = `0.4e18`, expects `QualityGateUnsatisfied(0.4e18, 52e16)`.
- `test_RevertWhen_QGSubFiftyTwo_StandardWithRPExcluded` — three-token mix: index 0 is `STANDARD` with non-zero RP at 51% weight, index 1 is `STANDARD` no RP at 11%, index 2 is `WITH_RATE+RP` at 38%. Correct QG sum = 38% < 52% → revert. A wrong predicate counting "any non-zero RP" would inflate the sum to 89% and falsely clear the gate. Pins the E-D13 predicate (`WITH_RATE && rateProvider != address(0)`) at the contract level, beyond what the Solidity type checker enforces on the loop body.
- `test_RevertWhen_WeightsLengthMismatch` — `tokens.length = 2`, `normalizedWeights.length = 3`, expects `WeightsLengthMismatch(2, 3)`.
- `test_RevertWhen_PoolCreatorNotZero` — non-zero `poolCreator`, expects the inherited `BasePoolFactory.StandardPoolWithCreator()` selector (no params).

**Why mock-vault is sufficient.** Each test reverts at lines 82 / 87 / 100 of `src/factory/AureumWeightedPoolFactory.sol` — before `_create` (L107) and `_registerPoolWithVault` (L121). `BasePoolFactory`'s constructor only stores the vault as immutable via `SingletonAuthentication`, so a `makeAddr("mockVault")` placeholder satisfies the factory's construction without any `vm.mockCall` interceptions. Pattern mirrors `test/unit/AureumProtocolFeeController.t.sol` L105–L138 (Stage B `B4-test-1`).

**Why the boundary-pass test is omitted from the unit file.** A test asserting "QG sum exactly `52e16` clears via `<` comparator at L99" requires `_create` + `_registerPoolWithVault` to succeed, which would need either a real local Vault deployment (BalancerContractRegistry / `BaseVaultTest` complexity) or a fork. The ixAurebit pilot fork test (`IxAurebitPilotTest::test_Fork_IxAurebit_DeploysAndRoutesFee` in `test/fork/PilotPools.t.sol`) already exercises this boundary — ixAurebit's QG sum is exactly `52e16` (svZCHF `26e16` + Aave Prime GHO `26e16`) and the test passes by deploying a registered pool through `AureumWeightedPoolFactory.create()`. Implicit boundary verification is preferred over duplicating the factory's `_create` chain in a local-Vault unit harness.

**Why "integration tests" beyond per-pilot fork tests are not added.** Each of the three pilot fork tests (E1.6b ixHelvetia, E2.3 ixEdelweiss, E3.3 ixAurebit) already exercises the full Stage D + E1 chain end-to-end: deploy `Vault` + `AureumProtocolFeeController` + `AureumFeeRoutingHook` + `AureumWeightedPoolFactory` + `derBodensee`, then deploy and initialize the pilot via the abstract `MiliariumPoolDeployer`, then perform a representative swap and assert hook-routed fee landing on Bodensee BPT supply. The cross-component coverage that "integration" would name is in those tests already; a separate harness reusing the same plumbing under a different label would be churn, not coverage.

**E-D9 closure.** E-D9's "**E4** integration tests + Quality Gate fail-case unit tests" line resolves with: (1) factory revert-path unit tests at `test/unit/AureumWeightedPoolFactory.t.sol` (this entry); (2) integration covered by per-pilot fork tests (E1.6b, E2.3, E3.3); (3) boundary covered by the ixAurebit pilot fork test. Test counts post-E4 (E4.2 regression at branch tip `3d35244`): **156 unit + 12 fork = 168 total, 0 failures.**

**Toolchain note — Cursor NatSpec-hyperlink artifact.** At E4.1 verify, Cursor saved the new test file's NatSpec block with two backtick-wrapped doc paths (`docs/STAGE_E_PLAN.md`, `docs/STAGE_E_NOTES.md`) converted into Markdown hyperlink syntax (`docs/STAGE_E_[PLAN.md](http://PLAN.md)`, `docs/STAGE_E_[NOTES.md](http://NOTES.md)`). Cursor evidently parses `.md` extensions as autolink-eligible inside Solidity NatSpec, the same class of corruption as the **D32** follow-up §D7.1e plan-doc backtick-stripping incident (commit `fbdef2f`, recorded in `docs/STAGE_D_NOTES.md` D32). The artifact is cosmetic-only — `forge build` is clean, test logic untouched — and was accepted at E4.1 commit; can be reverted at E5 docs sweep if desired. **Future §8e.1 prompts that include backtick-wrapped `.md` paths in Solidity-NatSpec or Markdown payload prose should add an explicit "do not auto-link `.md` references; backticks are literal" clause to the Instruction or Must match block.**

**Amendment (2026-04-28, E5 docs sweep).** Re-audit at E5 finds the file content is clean: `grep -n "\.md\]\|http://" test/unit/AureumWeightedPoolFactory.t.sol` returns no matches; the NatSpec block at L20–L29 has both `docs/STAGE_E_PLAN.md` and `docs/STAGE_E_NOTES.md` properly backtick-wrapped, no Markdown-link corruption on disk. The `[PLAN.md](http://PLAN.md)` / `[NOTES.md](http://NOTES.md)` rendering observed at E4.1 verify was the user's terminal / chat-message-renderer auto-linking `.md` extensions in the pasted `cat` / `shasum` audit output, not corruption Cursor wrote to the file. **Reclassification:** paste-rendering artifact, not file-content artifact; no E5.3 revert needed. **Discipline implication:** "Cursor saved corrupt content" observations whose only evidence is the rendered chat paste must be cross-checked against the file's actual content (`git show <branch>:<path>` or a direct read) before being recorded as a Cursor bug. The forward-looking "do not auto-link `.md` references" clause in the original Toolchain note paragraph remains useful defensive practice — D32 backtick-stripping is independently confirmed — but does not apply to this E4.1 instance.

---

## Findings

> `E11` onward populates as implementation incidents emerge.

### E10 — forge-std `deal(adjust=true)` incompatible with Reserve-DTF dynamic-supply tokens (ixEDEL); per-decimal `_seedAmounts()` required for mixed-decimal pilots (2026-04-27)

E2.4's first attempt panicked on the third `deal(...)` call inside `MiliariumPilotPoolBase._initializePool` (`test/fork/PilotPools.t.sol` L301–L303). `forge test -vvvv` traces the panic inside forge-std `deal` against ixEDEL—not in `vault.initialize` or `WeightedMath.computeInvariant()`.

ixEDEL is a Reserve DTF: `totalSupply()` is dynamic (fee-decay accrual), and there is no single canonical balance/supply slot for forge-std's `adjust` heuristic to update consistently, so the supply-adjust path arithmetic-wraps and reverts with panic `0x11`.

**Resolution:** call `deal(...)` without the third argument (i.e. `adjust=false`) in pilot mint loops—writes the holder balance slot only and leaves `totalSupply()` untouched. The Vault/WeightedPool init path reads raw token balances transferred to the Vault, not ERC20 `totalSupply()`, so the unadjusted `deal` is sound for pool-initialization seeding.

**Amendment to E-D24:** the `MiliariumPilotPoolBase._initializePool` mint loop at `test/fork/PilotPools.t.sol` L301–L303 drops `adjust=true`; the same rule applies to any `_performSwap` (current L324) where `tokenIn` is itself a Reserve DTF—flag this for E3 so DTF-as-`tokenIn` swap paths inherit the constraint.

**Amendment to E-D25:** the uniform `INIT_SEED` constant is wrong for mixed-decimal pilots (6 / 6 / 18 / 18 in ixEdelweiss; 8 / 8 in ixAurebit's WBTC/cbBTC). `_seedAmounts()` must return per-token `1_000 * 10**decimals(token)`. Call out 8-decimal WBTC/cbBTC explicitly so it is not re-discovered at ixAurebit.

**Amendment to E2.3 swap-vector:** the waEthUSDC representative swap amount is `1e6` (6 decimals), not `1e18`.

### E11 — "GHO" misnaming corrected: pilot composition uses Aave Prime GHO (ERC-4626 wrapper of GHO), not the underlying GHO stablecoin (2026-04-28)

E-D4 locks ixAurebit's "GHO 26%" at vault `0xC71Ea051a5F82c67ADcF634c36FFE6334793D24C` and RP `0x851b73c4BFd5275D47FFf082F9e8B4997dCCB253` with +0 pp boundary margin. E-D13 L39 lists "GHO" as gate-ineligible alongside ixEDEL / WBTC / cbBTC / tGBP / JPYC; read literally, the two collapse the gate sum to svZCHF 26% and `AureumWeightedPoolFactory.create()` would revert `QualityGateUnsatisfied(26e16, 52e16)`.

Reconciliation — **naming, not predicate**. Vault `0xC71Ea051a5F82c67ADcF634c36FFE6334793D24C` is Aave Prime GHO, an Aave-issued ERC-4626 vault wrapping the GHO stablecoin, with a deployed rate provider at `0x851b73c4BFd5275D47FFf082F9e8B4997dCCB253`; registers as `TokenType.WITH_RATE` with non-zero RP, gate-eligible. Bare GHO stablecoin lives at `0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f` — ERC-20, no Aureum-side RP, gate-ineligible — and is not used in any Aureum pilot composition through Stage E.

**Predicate-vs-list distinction** — E-D13's `WITH_RATE && rateProvider != address(0)` predicate is correct; the L39 summary list was wrong to lump "GHO" with the gate-ineligible ERC-20 set. Once Aave Prime GHO and bare GHO ERC-20 are named distinctly, both sources reconcile.

**Naming convention locked.** Docs: "Aave Prime GHO" verbose form. Solidity at E3.1 (`IxAurebitConfig`): `AAVE_PRIME_GHO` for the vault address constant; `AAVE_PRIME_GHO_RATE_PROVIDER` for the rate provider. Matches the SCREAMING_SNAKE_CASE precedent of `IxEdelweissConfig` (`WAETHUSDT`, `WAETHUSDC`, `IXEDEL`, `SVZCHF`). Bare GHO ERC-20 at `0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f` is not referenced in any pilot config.

**In-repo rename sweep (E11.1 through E11.6).**

- E11.1 — this finding section appended to `docs/STAGE_E_NOTES.md`, locking the convention.
- E11.2 — `docs/STAGE_E_NOTES.md` E-D13 (L39) carve-out + E-D17 (L69) anchor-list rename.
- E11.3 — `docs/STAGE_E_PLAN.md` E-D4 (L76) rename + inline disambiguation pointer to bare GHO ERC-20.
- E11.4 — `docs/FINDINGS.md` rename at L226 (ixLibertas margin), L312 (mainnet ERC-4626 vault list), L895 (ixViatica composition in OQ-12a's "Spec edits required" list), L941 (Holesky testnet stubs).
- E11.5 — `docs/STAGES_OVERVIEW.md` rename at L288 (preflight) + L338 (test stubs).
- E11.6 — `CLAUDE.md` §11 rename at L403 (composition recap) + L436 (resume step 3) + L440 (decimal mapping step 7).

**Project-knowledge-only fixes (out-of-repo, user-side).** Per CLAUDE.md §4 these are invisible to Claude Code; the user owns the edit.

- `aumm-site/07a_tokens.md` — distinguish bare GHO (ERC-20 stablecoin) row from Aave Prime GHO (ERC-4626 vault) row; latter is the canonical pilot token.
- `aumm-site/06_miliarium_manifest.md` — ixAurebit (slot 14), ixViatica, ixLibertas rows: rename "GHO" to "Aave Prime GHO".
- `aumm-site/05_miliarium_aureum.md` Section xi Yield table — ixAurebit / ixViatica / ixLibertas rows: same.
- `aumm-site/miliarium_profiles/04_ixViatica.md`, `09_ixLibertas.md`, `14_ixAurebit.md` — composition tables, "ERC-4626 composition" lines, Quality Gate lines.

**OQ-12a relationship.** OQ-12a is specifically about ixCambio reweighting and does not enumerate ixAurebit / ixViatica / ixLibertas compositions. Its "ERC-4626 / ERC-20" type tags map cleanly to wrapper-vs-underlying once "GHO" in pool compositions is read as Aave Prime GHO. No content change required to OQ-12a itself.

**Implementation impact for E3.** `IxAurebitConfig` (E3.1) declares `AAVE_PRIME_GHO = 0xC71Ea051a5F82c67ADcF634c36FFE6334793D24C` and `AAVE_PRIME_GHO_RATE_PROVIDER = 0x851b73c4BFd5275D47FFf082F9e8B4997dCCB253`; registers as `TokenType.WITH_RATE` with non-zero RP at the position dictated by ascending-address sort. ixAurebit's QG sum is exactly `52e16` (svZCHF `26e16` + Aave Prime GHO `26e16`); `AureumWeightedPoolFactory.create()` uses the `>=` comparator at the gate check per E-D11, so the boundary case clears without revert. `_seedAmounts()` decimal mapping per E-D25 + E10: Aave Prime GHO is 18-decimal (ERC-4626 share decimals match the underlying GHO's 18 decimals).
