# Stage M — Plan & Sub-Step Roadmap
> **Status:** M0.2 design freeze COMPLETE — M-D1—M-D6 LOCKED on `stage-m` (`docs/STAGE_M_NOTES.md`, `8e3dcb5`). This file is M0.3 (the sub-step roadmap); M1—M6 execution pending, no code surface landed yet. Companion to STAGE_M_NOTES.md (the running design-decision log).
>
> **Last update:** 2026-06-19 — M3.1—M3.5 complete: all five clean Majors built (03 ixCasper / 08 ixBrevis / 09 ixAltrix / 10 ixMediox / 11 ixLongus) — each a config lib + DeployIx* wrapper, forge build green; M-D8 locked (07a address-disambiguation rule). Completion log caught up M1-close—M3.5. Next: M4 `DeployStageM` orchestration.
>
> **Mode:** §13 has no Stage M entry-mode row — default to the Stage-J posture: Opus-high for pool-class / interface / token-literal authoring (the load-bearing per-pool composition surfaces), Sonnet for unit/fork test writing + plan-row housekeeping.
>
> **Audience:** Sagix plus any future Claude session that needs the operational roadmap for Stage M sub-step execution. NOTES (STAGE_M_NOTES.md) is the running design-decision log; this file is the sub-step sequence + Completion Log + grep-verifiable checkpoint catalog.
---
## Stage scope
Stage M deploys the "Majors / yield-core" Miliarium pools — originally conceived as 9 of the 28 constellation slots (M-D2) — and binds them into the live registry / gauge / emission layer via the tagged Stage E pool-deployment framework. The M2 token-availability preflight cleared only 5 of those 9 for build; Stage M's actual build scope narrows to `{03 ixCasper, 08 ixBrevis, 09 ixAltrix, 10 ixMediox, 11 ixLongus}` (M-D7), built in canonical slot order. The other 4 — `{02 ixAetheron, 04 ixViatica, 06 ixLibertas, 07 ixCambio}` — defer to Stage N alongside the originally-scoped remaining 16 (M-D7); slots 01/05/14 are Stage E pilots already deployed. No new contract logic ships — Stage M is config + deployment + binding over the tagged Stage E/G/H/I/J/K substrate: per-pool composition libraries + deployer wrappers (M-D4), a deploy-then-bind orchestration script (M-D6), and a mainnet-fork validation suite (Quality Gate, Rate Providers, hook attach, emission reach). A prerequisite correctness fix lands first — the live registry genesis seed is corrected from the synthetic `[2,3,7]` to the canonical `[1,5,14]` (M-D3), fix-forward on `stage-m` with the Stage-J tag untouched. All per-pool composition / weights / token-addresses / Rate-Providers are sourced from the on-disk `aumm-site` clone (`/Users/janus/code/aumm-site/`), never WebFetch (M-D1), and grounded against verified mainnet addresses (E-D17-class) at the M2 token-availability preflight.
### Surfaces produced at Stage M
| File | Status | Sub-step | LOC estimate |
| --- | --- | --- | --- |
| `script/DeployStageJ.s.sol` + `MiliariumRegistry` ctor NatSpec + Stage-J fork tests + `docs/STAGES_OVERVIEW.md` | EDIT | M1 | seed `[2,3,7]`→`[1,5,14]` + env keys + NatSpec/assertions |
| Token-availability preflight table (→ `STAGE_M_NOTES.md`) | NOTES | M2 | — |
| `script/pools/configs/NN_ixName.s.sol` × 5 (03/08/09/10/11) | NEW | M3.1—M3.5 | ~80—140 each |
| `script/pools/DeployIxName.s.sol` × 5 (03/08/09/10/11) | NEW | M3.1—M3.5 | ~25 each |
| `script/DeployStageM.s.sol` | NEW | M4 | ~120 |
| `test/fork/StageMIntegration.t.sol` | NEW | M5 | ~200 |
| `test/fork/DeployStageM.t.sol` | NEW | M5 | ~120 |
### Surfaces NOT produced at Stage M
- No new or modified contract logic in `src/` — Stage M is config + deployment over the tagged substrate (the `MiliariumPoolDeployer` base in `script/pools/deploy-miliarium-pool.s.sol` and all `src/` contracts are unchanged). The M-D3 seed correction touches a deploy script + its fork tests + NatSpec only; `MiliariumRegistry.sol` runtime logic is untouched (slot numbers are ctor inputs).
- No Stage N pools — slots 12/13/15/16 (crypto-rem) + 17—26 (stocks) + 27/28 (metals) are deferred to Stage N (M-D2); slots 02/04/06/07 join them per the M2 token-availability gap (M-D7).
- No re-tag of Stage E/G/H/I/J/K — the M-D3 seed correction and all binding are fix-forward on `stage-m` (I13-class).
- No governance-vote path for founding pools — Stage M founding pools are seeded at deploy via multisig calls, not proposals (M-D6).

---
## Decisions

Mirror of STAGE_M_NOTES.md Decisions table (LOCKED at M0.2 from a pre-flight Opus beat). Entries beyond the M0.2 design freeze (M-D7 onward) attach to specific sub-step locks as decisions are resolved during M1—M6 execution, recorded as new entries in both this table and the NOTES file.

| # | Status | Decision | Anchor | Locked at |
| --- | --- | --- | --- | --- |
| M-D1 | LOCKED | Stage M = config/deployment registry stage. Three pre-flight decisions: (i) canonical pool data read directly from the on-disk `aumm-site` clone (`/Users/janus/code/aumm-site/`), NOT WebFetch (confabulated on spec literals 2026-06-17, per CLAUDE.md §4); (ii) the live `[2,3,7]` registry-seed inconsistency corrected to canonical `[1,5,14]` at Stage M entry (M-D3); (iii) build scope = per-pool config libs + `DeployIx*` wrappers + `DeployStageM.s.sol` deploy-and-bind orchestration + fork tests. | User pre-flight decisions 2026-06-17; CLAUDE.md §4 spec source; STAGES_OVERVIEW Stage M; STAGE_K_NOTES L139 / L191 | M0.2 |
| M-D2 | LOCKED | Stage M binds the "Majors / yield-core" set = Yield-remaining + Bonds = 9 slots `{02 ixAetheron, 03 ixCasper, 04 ixViatica, 06 ixLibertas, 07 ixCambio, 08 ixBrevis, 09 ixAltrix, 10 ixMediox, 11 ixLongus}`; pilots `{01, 05, 14}` already deployed (Stage E). Stage N takes the remaining 16: crypto-native-rem `{12, 13, 15, 16}` + stocks `{17—26}` + metals `{27, 28}`. STAGES_OVERVIEW's coarse "Sector 2/3" deployment buckets are NOT the spec's 5-way taxonomy (Yield 01—07 / Bonds 08—11 / Crypto 12—16 / Stocks 17—26 / Metals 27—28); the M-tag boundary is soft — built in canonical slot order (02→11), cut at ~9—10. | `07_miliarium_sectors.md` xvi/xviii; `06_miliarium_manifest.md` xiii; STAGES_OVERVIEW Stage M "~10 Majors / yield-core"; Stage E pilots 01/05/14 | M0.2 |
| M-D3 | LOCKED | Correct the live registry genesis seed from synthetic `[2,3,7]` to canonical `[1,5,14]` (ixHelvetia=01, ixEdelweiss=05, ixAurebit=14). Touched artifacts: `script/DeployStageJ.s.sol` (seed array + env keys `PILOT_POOL_02/03/07` → `01/05/14` + NatSpec), `src/registry/MiliariumRegistry.sol` ctor NatSpec, `test/fork/DeployStageJ.t.sol` + `test/fork/StageJIntegration.t.sol` slot literals/assertions, `docs/STAGES_OVERVIEW.md` L125—126 (stale Stage E ixCambio/02/03/07) + L226. `MiliariumRegistry.sol` runtime logic unchanged (slot numbers are ctor inputs, not contract constants). Stage J/K tags untouched (fix-forward on `stage-m`). | STAGE_K_NOTES L139 adjudication; `06_miliarium_manifest.md` xiii; Stage E config filenames `01/05/14`; `StageGIntegration.t.sol:83`; `DeployStageI` env `PILOT_POOL_01/05/14` | M0.2 |
| M-D4 | LOCKED | Per-pool config follows E-D21 / E-D23: one library `script/pools/configs/NN_ixName.s.sol` exposing `config() returns (PoolConfig memory)` + a thin `script/pools/DeployIxName.s.sol` wrapper extending `MiliariumPoolDeployer`. ONE pool per §8e.1 sub-step, canonical slot order 02→11. Each pool's composition / weights / token-addresses / Rate-Providers read from `/Users/janus/code/aumm-site/miliarium_profiles/NN_ixName.md` + `06_miliarium_manifest.md` xiii + `07a_tokens.md`, grounded against verified mainnet addresses (E-D17-class); ascending-address token sort at literal-write time per Balancer V3 registration convention. | E-D21 library shape; E-D23 base + wrappers; E-D17 mainnet literals; `MiliariumPoolDeployer`; Balancer V3 ascending-address sort | M0.2 |
| M-D5 | LOCKED | Canonical "Standard" template (`06_miliarium_manifest.md` xiii) = 26/26/16/16/16: Yield Core A (ERC-4626) 26% + Yield Core B (ERC-4626) 26% + ixEDEL routing anchor 16% + Theme A 16% + Theme B 16%; the two yield cores (52%) form the `MIN_ERC4626_WEIGHT = 52e16` Quality-Gate numerator, cleared at the floor (tight validation). Standard pools in M: `03, 04, 08, 09, 10`. Non-Standard (bespoke weights): `02 ixAetheron` (two ETH-staking cores, no svZCHF), `06 ixLibertas` + `07 ixCambio` (routing / FX connectors — OQ-12/12a lineage), `11 ixLongus` (single 32% theme). | `06_miliarium_manifest.md` xiii Standard template; `MiliariumPoolDeployer.MIN_ERC4626_WEIGHT = 52e16`; E-D3 QG re-assertion; OQ-12 / OQ-12a | M0.2 |
| M-D6 | LOCKED | Stage M founding pools bound into registry / gauge / emission via MULTISIG calls, not governance proposals — per K-D9 (STAGE_K_NOTES L191) the `MiliariumRegistry` + `GaugeRegistry` governance slot is retained at the multisig post-Stage-K so M/N can drive `MiliariumRegistry.replaceSlot` (zero→nonzero = `SlotPopulated`), `GaugeRegistry.seedFoundingPool`, and `EmissionDistributor.setAuMTContractForPool` (OQ-I10). `DeployStageM.s.sol` orchestrates deploy-then-bind; gauge seeding is founding-pool, not vote-gated. | STAGE_K_NOTES L191 (K-D9); OQ-I10; `GaugeRegistry.sol:158` `seedFoundingPool`; `EmissionDistributor.sol:206` `setAuMTContractForPool`; STAGES_OVERVIEW Stage M "seeded at deploy" | M0.2 |
| M-D7 | LOCKED | M2 token-availability preflight (the M-D4 gate) cleared 5 of the 9 M-D2 Majors; Stage M's build scope narrows to those five — `{03 ixCasper, 08 ixBrevis, 09 ixAltrix, 10 ixMediox, 11 ixLongus}`, built in canonical slot order — and the four gap pools `{02 ixAetheron (waEthrETH Aave-static-wrapper anomaly), 04 ixViatica (fBRZ no mainnet address), 06 ixLibertas (USDC/USDT bare-vs-wrapped form), 07 ixCambio (aEURS not yet listed — QG-critical)}` defer to Stage N alongside the existing 16, because the on-disk `aumm-site` clone cannot resolve their composition / Quality-Gate to the verified mainnet literals M-D4 requires (E-D17 bar). M-D2's 9-slot set stands as the originally-conceived Sector-2 Majors set — M-D7 records the build-time narrowing forced by the preflight gate, not a retro-edit. Knock-on: M3 roadmap → M3.1—M3.5 over the five clean pools; M4 `DeployStageM` orchestrates five; M5 fork suite validates five; `stage-m-complete` tags the five-pool stage. The deferred four carry their per-token gap detail in the M2 preflight table for Stage N pickup. | M2 preflight table (this file, M2); M-D4 E-D17 verified-literal bar; M-D2 9-slot set; `07a_tokens.md` token gaps; STAGES_OVERVIEW Stage M/N | M2 |
| M-D8 | LOCKED | `07a_tokens.md` address-disambiguation rule: when a token row commits a value in the "Ethereum address" column AND the row-note flags an alternative deployment instance, the config literal binds the primary-column value; the note's alternative is informational, not a competing binding (lower-surprise, spec-faithful). First instance — ixCasper (slot 03) waEthwstETH (16% theme, ERC-4626): binds Aave V3 Core stataEthwstETH `0x322AA5F5Be95644d6c36544B6c5061F072D16DF5` + Rate Provider `0xe1D97bF61901B075E9626c8A2340a7De385861Ef` (the 07a primary column / "wstETH oracle (Aave)"); the Aave Lido-market instance `0x775F661b0bD1739349b9A2A3EF60be277c5d2D29` (07a footnote) is NOT bound — its Rate Provider is also absent from 07a. User-adjudicated at M3.1 pre-flight. | `07a_tokens.md` slot-03 row (waEthwstETH); M-D4 E-D17 verified-literal bar; ixCasper profile `03_ixCasper.md`; user adjudication 2026-06-19 | M3.1 |

---
## Sub-step roadmap (M1—M6)

> Execution spine is M1 → M6 in order; M3 fans out into M3.1—M3.5 (one Major per §8e.1, over the 5 pools the M2 preflight cleared — canonical slot order 03/08/09/10/11, per M-D7). The M-D NOTES L23 provisional "M1—M9" range predates this roadmap — the original nine per-pool sub-steps were to collapse into M3.1—M3.9, but the M2 gate narrowed that to the five-pool M3.1—M3.5 spine here (M-D7); the deferred four (02/04/06/07) move to Stage N. M1 (seed correction) and M2 (token preflight) gate M3: a config lib cannot bake a slot or an address literal until the registry seed reflects the deployed pilots (M1) and every ERC-4626 / Rate-Provider address is confirmed live on-chain (M2). M3.1—M3.5 are mutually independent and may pause/resume between any two. M4 (orchestration) requires all five M3 surfaces; M5 (fork tests) requires M4; M6 closes and tags.

### M1 — Registry genesis-seed correction `[2,3,7]` → `[1,5,14]` (M-D3)

The Stage-J registry was seeded with the synthetic slot set `[2,3,7]`, but the three pilots actually deployed at Stage E sit at slots `01 / 05 / 14` (`ixHelvetia` / `ixEdelweiss` / `ixAurebit`). M1 corrects the seed to the canonical `[1,5,14]` and renames the slot-keyed env vars `PILOT_POOL_02/03/07` → `PILOT_POOL_01/05/14`. `MiliariumRegistry.sol` runtime logic is untouched — slot numbers are constructor inputs, not contract constants — so this is a deploy-script + NatSpec + test-literal correction, I13-class fix-forward on `stage-m` with no Stage-J/K re-tag.

- Surfaces: `script/DeployStageJ.s.sol` (`slotNumbers` array L48-51 + env keys L52-55 + NatSpec L11/L16-17/L25-27); `src/registry/MiliariumRegistry.sol` (constructor-example NatSpec); `test/fork/DeployStageJ.t.sol` + `test/fork/StageJIntegration.t.sol` (slot literals / seed assertions); `docs/STAGES_OVERVIEW.md` (L125—126 stale `ixCambio`/02/03/07 + L226).
- Checkpoint: a residual-reference grep across `script/ src/ test/ docs/` returns zero `[2,3,7]`-era slot or `PILOT_POOL_02/03/07` references; `forge build` green; the Stage-J fork suite (`DeployStageJ.t.sol` + `StageJIntegration.t.sol`) green against the new seed.

### M2 — Token-availability preflight → `STAGE_M_NOTES.md` (M-D4 + STAGES_OVERVIEW preflight gate)

For each of the nine Majors, enumerate every component token — the two Yield-Core ERC-4626 wrappers + the `ixEDEL` routing anchor + the two themes for Standard pools, plus the bespoke compositions for `02 / 06 / 07 / 11` — and resolve each to a verified mainnet address + Rate Provider (E-D17-class), sourced from `/Users/janus/code/aumm-site/miliarium_profiles/NN_ixName.md` + `06_miliarium_manifest.md` §xiii + `07a_tokens.md`. Record the resolved table in `STAGE_M_NOTES.md`. NOTES-only, no code surface. This gates M3 — a config lib must never bake an address literal that has not been confirmed live on-chain (the E10 / `ixEDEL` dynamic-supply class of surprise is found here, not at fork-test time).

### M3.1—M3.5 — Per-pool config libs + deploy wrappers (M-D4 + M-D7, canonical slot order 03/08/09/10/11)

Each M3.x produces the Stage-E pilot pair: a `library Ix<Name>Config` at `script/pools/configs/NN_ixName.s.sol` exposing `config() internal pure returns (PoolConfig memory)` (token + Rate-Provider address constants, ascending-address sorted per Balancer V3 registration; `tokens` / `tokenTypes` / `rateProviders` / `paysYieldFees` / `normalizedWeights` arrays; `name` / `symbol` / `slot` / `sectorLabel` / `swapFeePercentage` / `salt` = `bytes32(uint256(NN))`; NatSpec citing the manifest row + the M-D locks + the per-token Quality-Gate arithmetic), plus a thin `contract DeployIx<Name> is MiliariumPoolDeployer` at `script/pools/DeployIxName.s.sol` overriding `_config()`. One pool per §8e.1.

| Sub-step | Slot | Pool | Template (M-D5) |
| --- | --- | --- | --- |
| M3.1 | 03 | `ixCasper` | Standard — 26/26/16/16/16 |
| M3.2 | 08 | `ixBrevis` | Standard — 26/26/16/16/16 |
| M3.3 | 09 | `ixAltrix` | Standard — 26/26/16/16/16 |
| M3.4 | 10 | `ixMediox` | Standard — 26/26/16/16/16 |
| M3.5 | 11 | `ixLongus` | Non-Standard — single 32% theme |

Standard pools (`03 / 08 / 09 / 10`) clear the `MIN_ERC4626_WEIGHT = 52e16` Quality Gate exactly at the floor — the two 26% yield cores sum to 52%; the one Non-Standard pool (`11 ixLongus`) carries its own ≥ 52% ERC-4626 numerator, re-asserted both in the config NatSpec and by `MiliariumPoolDeployer.run()` before broadcast. Checkpoint per pool: `forge build` green (the config compiles against the base deployer's QG re-assert) + a weight-sum grep confirming the normalized weights total `1e18` and the ERC-4626 share ≥ `52e16`.

### M4 — Deploy-and-bind orchestration `script/DeployStageM.s.sol` (M-D6)

A single `forge script` that deploys all five Majors (via the M3 `DeployIx*` wrappers / the factory) and then binds each as a founding pool through the K-D9 MULTISIG-call path — `MiliariumRegistry.replaceSlot` (zero→nonzero `SlotPopulated`), `GaugeRegistry.seedFoundingPool` (`GaugeRegistry.sol:158`), and `EmissionDistributor.setAuMTContractForPool` (`EmissionDistributor.sol:206`, OQ-I10). Gauge seeding is founding-pool, not vote-gated. Env-var driven (no hardcoded addresses); mirrors `DeployStageL.s.sol`'s deploy-then-dual-gate-wire shape.

### M5 — Fork integration + deploy-script tests (`test/fork/StageMIntegration.t.sol` + `test/fork/DeployStageM.t.sol`)

`StageMIntegration` deploys the five Majors on a mainnet fork, β-pattern-inits liquidity, and asserts: each pool clears the Quality Gate; Rate Providers resolve; the fee-routing hook is attached; the registry / gauge / emission binding is live; and block emission reaches each pool. `DeployStageM` is the deploy-script fork test — the H13 caveat applies: if any consumed constructor external-calls its argument, inherit a real-state fixture rather than keccak placeholders. Split-form fork invocation per D35 (`--match-path "test/fork/**" --fork-url $MAINNET_RPC_URL`); `--threads 1` per D36 if env-key races surface.

### M6 — Stage M close + tag `stage-m-complete`

Full split-form regression green (unit + fork); §11 resume-anchor refresh; this PLAN's Completion log finalized; `STAGES_OVERVIEW.md` Stage M row marked complete; tag `stage-m-complete`; ff-merge to `main`. The WM whitehat back-fill (F-08 / F-09 / F-10) already closed at the Stage-M entry, so no whitehat gate remains for the tag.

---
## Completion log

| Sub-step | Commit | Summary |
| --- | --- | --- |
| M0.2 | `8e3dcb5` | `STAGE_M_NOTES.md` — design freeze M-D1—M-D6 |
| M0.3 | `edd66e5` | `STAGE_M_PLAN.md` — header + scope + Surfaces + Decisions mirror + M1—M6 roadmap |
| M1 | `4b15d50` | registry genesis-seed [2,3,7]→[1,5,14] (M-D3) — DeployStageJ seed/env/NatSpec + MiliariumRegistry NatSpec + Stage-J fork tests (replaceSlot 2→1) + STAGES_OVERVIEW pilots ixCambio→ixAurebit; 847/847 + 99/99 green |
| M1-close | `3bcfad3` | M1 close (M1.7+M1.8) — `STAGE_M_NOTES.md` M10 (PILOT_POOL env-key overlap, D36-class) + Completion-log seed (M0.3 / M1) |
| M2 | `f4ac45e` | `STAGE_M_NOTES.md` M2 token-availability preflight — 5/9 Majors resolved (03/08/09/10/11), 4 deferred to Stage N (M-D7) |
| M2.1—M2.4 | `8237e81` | M-D7 lock — Stage M build scope 9→5 — NOTES + PLAN Decisions + Stage-scope / Surfaces / M3-roadmap + STAGES_OVERVIEW Stage M/N rows |
| M3.1a—M3.1b | `9bfd8fe` | M-D8 lock — 07a address-disambiguation rule (primary-column binds); ixCasper waEthwstETH = Aave V3 Core (not Lido instance) — NOTES + PLAN Decisions |
| M3.1c | `8a62b78` | `03_ixCasper.s.sol` + `DeployIxCasper.s.sol` — slot 03 Standard, 84% ERC-4626 QG (+32pp); forge build green |
| M3.2 | `842656f` | `08_ixBrevis.s.sol` + `DeployIxBrevis.s.sol` — slot 08 Standard, 52% ERC-4626 QG at floor; forge build green |
| M3.3 | `9493da6` | `09_ixAltrix.s.sol` + `DeployIxAltrix.s.sol` — slot 09 Standard, 52% ERC-4626 QG at floor; forge build green |
| M3.4 | `63ca0b6` | `10_ixMediox.s.sol` + `DeployIxMediox.s.sol` — slot 10 Standard, 52% ERC-4626 QG at floor; forge build green |
| M3.5 | `1ddbbc1` | `11_ixLongus.s.sol` + `DeployIxLongus.s.sol` — slot 11 Non-Standard (4-token, TLTon 32%), 52% ERC-4626 QG at floor; forge build green |
