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

**Predicate locked to OQ-12 / OQ-12a wording.** OQ-12a's resolution table in `docs/FINDINGS.md` (L863–870) classifies tokens by type: svZCHF, st-EURA, aEURS (and by extension waEthUSDC, waEthUSDT) are "ERC-4626" — gate-eligible; ixEDEL, GHO, WBTC, cbBTC, tGBP, JPYC are "ERC-20" / "ERC-20 (Reserve DTF)" — gate-ineligible. The Solidity-level predicate `WITH_RATE && rateProvider != address(0)` matches that classification at registration time: gate-eligible tokens register with `TokenType.WITH_RATE` and a non-zero Rate Provider; gate-ineligible tokens register with `TokenType.STANDARD` and no Rate Provider.

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

Canonical mainnet vault addresses for the pilot trio are anchored to aumm-site/07a_tokens.md (rows 58–59 for sUSDS / svZCHF; additional rows for ixEDEL, waEthUSDC, waEthUSDT, GHO, WBTC, cbBTC where pilot composition requires them per E-D4), with in-repo provenance via the docs/STAGE_D_NOTES.md D1 probe table (live getRate() values recorded at fork-pin block):

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

---

## Findings

> `E10` onward populates as implementation incidents emerge.
