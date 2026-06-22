# Stage N — Plan & Sub-Step Roadmap
> **Status:** N0 design freeze COMPLETE — N-D0—N-D6 LOCKED on `stage-m` (`docs/STAGE_N_NOTES.md`, `ccfb392`). This file is N0.3 (the sub-step roadmap); N1—N7 execution pending, no code surface landed yet. Companion to STAGE_N_NOTES.md (the running design-decision log). Stage N builds on the post-M tree — no `stage-n` branch cut yet.
>
> **Last update:** 2026-06-22 — N0.3 PLAN authored. Roadmap: N1 (STAGES_OVERVIEW Stage N fact-fix) → N2 (16 clean Standard config pairs) → N3 (`src/rate_provider/` pair + the N-D7 RP-address-threading lock + unit tests) → N4 (the two resolvable Majors 02 ixAetheron / 06 ixLibertas) → N5 (`DeployStageN.s.sol` bind-only) → N6 (fork suite) → N7 (WN whitehat + close + tag `stage-n-complete`). Next: N1.
>
> **Mode:** Opus high entry (Stage-J/M posture — §13 has no Stage N row). N3 `src/rate_provider/` contract drafting is Opus extra-high (novel `src/` surface). Per-pool composition + literal authoring + the N-D7 RP-threading design are Opus beats; the 14 new-RP-free clean-16 config transcriptions + unit/fork test writing + plan-row housekeeping drop to Sonnet.
>
> **Audience:** Sagix plus any future Claude session that needs the operational roadmap for Stage N sub-step execution. NOTES (STAGE_N_NOTES.md) is the running design-decision log; this file is the sub-step sequence + Completion Log + grep-verifiable checkpoint catalog.
---
## Stage scope
Stage N is the final Miliarium config/deployment stage — it completes the 28-slot constellation by deploying the Sector-3 (Equity + thematic) pools plus the two Sector-2 Majors deferred from Stage M (M-D7), binding all 18 into the live registry / gauge / emission layer via the tagged Stage E pool-deployment framework, and adding the protocol's first Aureum-owned rate-provider surface (`src/rate_provider/`). Build scope = 18 pools (N-D0): the 16 originally-scoped Sector-3 slots `{12, 13, 15, 16, 17—26, 27, 28}` + the two resolvable Majors `{02 ixAetheron, 06 ixLibertas}`; the two hard-blocked Majors `{04 ixViatica, 07 ixCambio}` stay deferred — `fBRZ` / `aEURS` are undeployable to the E-D17 bar. Beyond the RP pair, no new contract logic ships — Stage N is config + deployment + binding over the tagged Stage E/G/H/I/J/K substrate, mirroring Stage M: per-pool composition libraries + deployer wrappers (M-D4 framework), a bind-only orchestration script (M-D9 shape), and a mainnet-fork validation suite (M-D10 scope). The new RP surface exists because two ixAetheron yield cores (waEthrETH / waEthweETH) and two ixLibertas / Standard yield cores (scrvUSD / sfrxUSD) have no usable mainnet Rate Provider — the M-D11 Aave-static-wrapper anomaly class — so Aureum deploys a generic `ERC4626RateProvider` (scrvUSD / sfrxUSD, N-D2) and a `CompositeRateProvider` (the two ixAetheron stata wrappers, N-D1). All per-pool composition / weights / token-addresses / Rate-Providers are sourced from the on-disk `aumm-site` clone (`/Users/janus/code/aumm-site/`), never WebFetch (M-D1), grounded against verified mainnet addresses (E-D17 bar) at the N2 / N4 per-pool pre-flights.
### Surfaces produced at Stage N
| File | Status | Sub-step | LOC estimate |
| --- | --- | --- | --- |
| `docs/STAGES_OVERVIEW.md` Stage N section | EDIT | N1 | pool-name fact-fix + 18-pool count + {04/07} deferred rationale |
| `script/pools/configs/NN_ixName.s.sol` × 16 + `script/pools/DeployIxName.s.sol` × 16 (clean Sector-3) | NEW | N2.1—N2.16 | ~80—140 + ~25 each |
| `src/rate_provider/ERC4626RateProvider.sol` | NEW | N3.1 | ~25 |
| `src/rate_provider/CompositeRateProvider.sol` | NEW | N3.2 | ~35 |
| `test/unit/RateProvider.t.sol` | NEW | N3.3 | ~150 |
| `script/pools/configs/02_ixAetheron.s.sol` + `06_ixLibertas.s.sol` + their `DeployIx*.s.sol` wrappers | NEW | N4.1—N4.2 | ~120 each |
| `script/DeployStageN.s.sol` | NEW | N5 | ~140 |
| `test/fork/StageNIntegration.t.sol` | NEW | N6 | ~240 |
| `test/fork/DeployStageN.t.sol` | NEW | N6 | ~120 |
### Surfaces NOT produced at Stage N
- No new contract logic beyond `src/rate_provider/` — the RP pair is the only `src/` addition; all 18 pool deployments ride the tagged Stage E framework (`MiliariumPoolDeployer` + per-pool config libs), unchanged.
- No `{04 ixViatica, 07 ixCambio}` — hard-deferred (N-D0); `fBRZ` (no mainnet address) / `aEURS` (not listed) cannot resolve to the E-D17 verified-literal bar.
- No re-tag of Stage E/G/H/I/J/K — the `src/rate_provider/` surface and all binding are fix-forward on the post-M tree (I13-class).
- No governance-vote path for founding pools — Stage N founding pools are seeded at deploy via multisig calls, not proposals (mirrors M-D6 / K-D9).
- No mainnet broadcast — `DeployStageN.s.sol` is a simulation / Safe-batch reference (mirrors M-D9); real on-chain RP + bind submission is out of scope (8c-class).

---
## Decisions

Mirror of STAGE_N_NOTES.md Decisions table (LOCKED at N0 from a pre-flight Opus beat). Entries beyond the N0 freeze (N-D7 onward) attach to specific sub-step locks as decisions are resolved during N1—N7 execution, recorded as new entries in both this table and the NOTES file. The first such entry — N-D7 (new-RP-address threading) — is forward-referenced in the N2 / N3 roadmap below and lands at the N3 pre-flight.

| # | Status | Decision | Anchor | Locked at |
| --- | --- | --- | --- | --- |
| N-D0 | LOCKED | Stage N build scope = **18 pools**: the 16 originally-scoped Sector-3 slots `{12 ixStrata, 13 ixForum, 15 ixRegistrum, 16 ixDebitum, 17 ixEquitix, 18 ixInnovix, 19 ixGigantus, 20 ixMagnix, 21 ixNubix, 22 ixMoneta, 23 ixColossix, 24 ixVitalix, 25 ixMedicix, 26 ixMercatura, 27 ixAurix, 28 ixMetallum}` + the two resolvable Majors deferred from M-D7 `{02 ixAetheron, 06 ixLibertas}`. The two hard-blocked M-D7 Majors `{04 ixViatica, 07 ixCambio}` stay deferred — `fBRZ` (ixViatica theme) has no mainnet address (Flux lists none) and `aEURS` (ixCambio yield core, QG-critical) is not in the Aave address book; neither resolves to the E-D17 verified-literal bar. Supersedes STAGES_OVERVIEW's stale "~20 pools" + fictional "ixNovae / ixArtifex / …" pool-name prose (fixed at N1). Of the 16 clean: all Standard 26/26/16/16/16, QG = svZCHF 26% + stable-core 26% = 52% at floor; the `*on` tokenized equities / ETFs are `TokenType.STANDARD` ERC-20 theme legs (address-only, no RP), so they do not gate. | `06_miliarium_manifest.md` xiii (slot table); `07a_tokens.md` (token addresses); M-D2 9-slot Majors set; M-D7 deferral characterization; profiles `02_ixAetheron.md` / `06_ixLibertas.md`; user scope adjudication 2026-06-22 | N0 |
| N-D1 | LOCKED | **`CompositeRateProvider`** — new Aureum-owned `src/rate_provider/CompositeRateProvider.sol` `is IRateProvider`, the Stage-N restoration pattern M-D11 prescribed. Two immutables `(IERC4626 wrapper, IRateProvider underlyingRP)`, zero admin, zero storage; `getRate() = wrapper.previewRedeem(FixedPoint.ONE).mulDown(underlyingRP.getRate())` — Balancer `FixedPoint` math (mirrors the submodule `ERC4626RateProvider` `previewRedeem` + round-down), wrapper-shares → underlying-LST → ETH. Deployed **twice** for ixAetheron (02): `(waEthrETH, Rocket Pool rETH RP 0x1a8F81c256aee9C640e14bB0453ce247ea0DFE6F)` and `(waEthweETH 0x867b0CDC4B39a19945E616c29639b0390b39db3B, Aave weETH oracle 0x87625393534d5C102cADB66D37201dF24cc26d4C)`. Rejected: (a) two bespoke single-purpose RPs (more code, no benefit); (b) plain rETH / weETH fallback (kills the ixAetheron dual-yield thesis per `02_ixAetheron.md`). N4 preflight (NOT an architecture blocker, hard gate before literals land): (i) resolve the real `waEthrETH` Aave-stataToken wrapper address — `07a` lists canonical rETH `0xae78736…`, not the wrapper; (ii) fork-verify both underlying RPs return nonzero — the Aave weETH oracle `0x8762…` is the same stataToken-oracle family as the `0xe1D9…` wstETH oracle that reverted in M-D11, so it may itself be revert-class, in which case the weETH composite rebinds to an EtherFi weETH→ETH source (new N-D, mirroring M-D11). | M-D11 (composite-RP Stage-N restoration); `03_ixCasper.s.sol` L45—46 (`0x8Be2` / `0x72D07D` fWSTETH composite precedent); submodule `ERC4626RateProvider.sol` (`previewRedeem` pattern); `02_ixAetheron.md` (27/27 dual-core thesis); Balancer `FixedPoint.mulDown`; M5.1b RP-revert lesson; user sign-off 2026-06-22 | N0 |
| N-D2 | LOCKED | Missing-ERC4626-RP rule → Aureum-owned generic `src/rate_provider/ERC4626RateProvider.sol` (a ~22-line copy of the Balancer submodule pattern `previewRedeem(FixedPoint.ONE)`, NOT a submodule edit per CLAUDE.md §8c). Deployed for the two QG-critical ERC-4626 tokens whose `07a` RP column is absent / a non-RP link: **scrvUSD** `0x0655977FEb2f289A4aB78af67BAB0d17aAb84367` (ixLibertas 15%) and **sfrxUSD** `0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6` (ixLibertas 14% + **ixMagnix 20** 26% + **ixAurix 27** 26%). One sfrxUSD RP deployment address is reused as a shared constant across all three configs. Without these, scrvUSD / sfrxUSD register `STANDARD` and drop from the `_compute52PctNumerator` count — ixLibertas QG falls to 42% (fail), and the sfrxUSD-core Standard pools lose a 26pp leg. | `07a_tokens.md` L48 (scrvUSD, no RP) / L47 (sfrxUSD, token-link not RP); submodule `ERC4626RateProvider.sol`; `06_ixLibertas.md` (57% QG); `GaugeEligibility._compute52PctNumerator`; CLAUDE.md §8c (no submodule edits); user sign-off 2026-06-22 | N0 |
| N-D3 | LOCKED | ixLibertas (06) `USDC` / `USDT` bind **canonical bare ERC-20**, `TokenType.STANDARD`, `rateProvider = address(0)` — NOT the `07a` "USDC" / "USDT" rows, whose "Ethereum address" cells carry the waEth *wrapper* addresses (`0xD4fa…` / `0x7Bc3…`). The `06_ixLibertas.md` profile specs bare stablecoins (USD Stable 6 / 7, ERC-20). Canonical mainnet: USDC `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`, USDT `0xdAC17F958D2ee523a2206206994597C13D831ec7`. Resolves the M-D7 "USDC / USDT bare-vs-wrapped form" deferral reason. | `06_ixLibertas.md` (bare ERC-20 USD Stable 6 / 7); `07a_tokens.md` L63—64 (wrapper-address-in-bare-row gap); M-D7 ixLibertas deferral; canonical USDC / USDT mainnet addresses | N0 |
| N-D4 | LOCKED | ixLibertas (06) `PYUSD` binds bare ERC-20 `0xb51EDdDD8c47856D81C8681EA71404Cec93E92c6`, `TokenType.STANDARD`, no RP — the `07a` PYUSD row's Aave-Core PYUSD RP (`0xdd8AEBC1…`) is ignored (profile specs bare PYUSD, USD Stable 2). ixLibertas final composition (7-token hub, no ixEDEL): scrvUSD 15% (4626, N-D2 RP) / PYUSD 15% (STD) / GHO 14% (4626, RP `0x851b73c4BFd5275D47FFf082F9e8B4997dCCB253`) / sUSDS 14% (4626, RP `0x1195be91e78ab25494c855826ff595eef784d47b`) / sfrxUSD 14% (4626, N-D2 RP) / USDT 14% (STD, N-D3) / USDC 14% (STD, N-D3); QG numerator = scrvUSD + GHO + sUSDS + sfrxUSD = 57% (+5pp over the 52% floor, per FINDINGS F8b). | `06_ixLibertas.md` (PYUSD USD Stable 2 bare); `07a_tokens.md` L41 (PYUSD); FINDINGS F8b (57% QG); pilot RP literals (GHO / sUSDS) | N0 |
| N-D5 | LOCKED | N6 fork-test architecture + assertion scope mirror M-D10: `test/fork/StageNIntegration.t.sol` (`StageNIntegrationFixture` on `StageIIntegrationFixture`, fresh real `MiliariumRegistry(address(this), [1,5,14], [pilots])`, `new DeployIx*().run()` for all 18, `vm.setEnv`-wire, `new DeployStageN().deploy(address(this))`) + `test/fork/DeployStageN.t.sol` (fail-fast governance reverts). Assertion scope = binding-liveness + QG re-assert (`evaluateEligibility`) + Rate-Provider resolve (`getRate() > 0` per the inherited `test_rateProvidersResolve_nonzeroGetRate` gate — now covering the two composite + two ERC4626 instances and the sfrxUSD legs on 20 / 27) + hook attach — NOT β-init emission accrual. `script/DeployStageN.s.sol` (N5) is bind-only per M-D9 (`replaceSlot` + `seedFoundingPool` + `setAuMTContractForPool` over the 18 slots, three fail-fast governance preconditions). | M-D10 (M5 fork architecture); M-D9 (bind-only orchestration); `StageMIntegration.t.sol` `test_rateProvidersResolve_nonzeroGetRate`; `StageIIntegrationFixture`; user M5-depth precedent | N0 |
| N-D6 | LOCKED | The new `src/rate_provider/` surface (`CompositeRateProvider` + `ERC4626RateProvider`) gets a Stage-N whitehat pass at N7 (the WN pass) before the `stage-n-complete` tag — first Aureum-owned RP contract surface, so it carries genuine review weight (rounding direction, `previewRedeem` vs `convertToAssets`, zero-rate / revert propagation from the underlying RP, decimals scaling). Unit tests (N3) + fork liveness (N6) + whitehat (N7) is the three-gate close, mirroring the WM / WL cadence. | CLAUDE.md §1 (small reviewable surface); white-hat per-stage cadence; WM / WL precedent; N3 `src/rate_provider/` | N0 |

---
## Sub-step roadmap (N1—N7)

> Execution spine is N1 → N7 in order. N2 fans into N2.1—N2.16 (one clean Sector-3 pool per §8e.1, canonical slot order 12/13/15/16/17—26/27/28); N3 into N3.1—N3.3 (the RP pair + unit tests, gated by the N3.0 N-D7 pre-flight); N4 into N4.1—N4.2 (the two resolvable Majors, gated by the N4.0 token/RP preflight). Dependency: pools `20 ixMagnix` and `27 ixAurix` carry a sfrxUSD yield core whose Rate Provider is the Aureum-deployed `ERC4626RateProvider` from N3 (N-D2), so their config RP reference is NOT a known mainnet literal like the other 14 clean pools — it resolves per the N-D7 new-RP-address-threading decision (locked at N3.0). The 14 new-RP-free clean pools `{12, 13, 15, 16, 17, 18, 19, 21, 22, 23, 24, 25, 26, 28}` bind only pre-existing mainnet RPs and are unblocked by N3. N5 (orchestration) requires all 18 config surfaces; N6 (fork tests) requires N5; N7 closes and tags.

### N1 — STAGES_OVERVIEW.md Stage N section fact-fix (N-D0)

The STAGES_OVERVIEW Stage N section carries fictional pool names ("ixNovae / ixArtifex / …" — none in `06_miliarium_manifest.md`) and a stale "~20 pools" count. N1 replaces them with the real 18-pool scope (N-D0): the 16 Sector-3 slots `{12 ixStrata … 28 ixMetallum}` + `{02 ixAetheron, 06 ixLibertas}`, the `{04 ixViatica, 07 ixCambio}` hard-deferral rationale (fBRZ / aEURS), and the `src/rate_provider/` surface note. Docs-only, no code surface; I13-class fix-forward, no re-tag.

- Surfaces: `docs/STAGES_OVERVIEW.md` (Stage N section prose + any Stage-N row in the master sequence / Completion Log).
- Checkpoint: a residual-reference grep returns zero `ixNovae` / `ixArtifex` / `ixSophia` / `ixMercatus` / "~20 pools" hits in the Stage N section; the real 18 pool names + the {04/07} deferral are present.

### N2.1—N2.16 — Clean Sector-3 config libs + deploy wrappers (M-D4 framework, canonical slot order)

Each N2.x produces the Stage-E pilot pair: a `library Ix<Name>Config` at `script/pools/configs/NN_ixName.s.sol` exposing `config() internal pure returns (PoolConfig memory)` (ascending-address-sorted token + Rate-Provider constants; `tokens` / `tokenTypes` / `rateProviders` / `paysYieldFees` / `normalizedWeights` arrays; `name` / `symbol` / `slot` / `sectorLabel` / `swapFeePercentage` / `salt = bytes32(uint256(NN))`; NatSpec citing the manifest row + the per-token Quality-Gate arithmetic), plus a thin `contract DeployIx<Name> is MiliariumPoolDeployer` wrapper at `script/pools/DeployIxName.s.sol`. One pool per §8e.1. Composition read from `/Users/janus/code/aumm-site/miliarium_profiles/NN_ixName.md` + `06_miliarium_manifest.md` xiii + `07a_tokens.md`, grounded to E-D17 mainnet literals.

| Sub-step | Slot | Pool | Template (M-D5) |
| --- | --- | --- | --- |
| N2.1 | 12 | `ixStrata` | Standard — 26/26/16/16/16 |
| N2.2 | 13 | `ixForum` | Standard — 26/26/16/16/16 |
| N2.3 | 15 | `ixRegistrum` | Standard — 26/26/16/16/16 |
| N2.4 | 16 | `ixDebitum` | Standard — 26/26/16/16/16 |
| N2.5 | 17 | `ixEquitix` | Standard — 26/26/16/16/16 |
| N2.6 | 18 | `ixInnovix` | Standard — 26/26/16/16/16 |
| N2.7 | 19 | `ixGigantus` | Standard — 26/26/16/16/16 |
| N2.8 | 20 | `ixMagnix` | Standard — sfrxUSD core (N3-dep, N-D7) |
| N2.9 | 21 | `ixNubix` | Standard — 26/26/16/16/16 |
| N2.10 | 22 | `ixMoneta` | Standard — 26/26/16/16/16 |
| N2.11 | 23 | `ixColossix` | Standard — 26/26/16/16/16 |
| N2.12 | 24 | `ixVitalix` | Standard — 26/26/16/16/16 |
| N2.13 | 25 | `ixMedicix` | Standard — 26/26/16/16/16 |
| N2.14 | 26 | `ixMercatura` | Standard — 26/26/16/16/16 |
| N2.15 | 27 | `ixAurix` | Standard — sfrxUSD core (N3-dep, N-D7) |
| N2.16 | 28 | `ixMetallum` | Standard — 26/26/16/16/16 |

The 14 new-RP-free pools clear the `MIN_ERC4626_WEIGHT = 52e16` Quality Gate at the floor (svZCHF 26% + stable-core 26% = 52%); `20 ixMagnix` and `27 ixAurix` defer their sfrxUSD RP reference to N3 (N-D7). Checkpoint per pool: `forge build` green + a weight-sum grep confirming normalized weights total `1e18` and the ERC-4626 share ≥ `52e16`.

### N3.0—N3.3 — `src/rate_provider/` surface + N-D7 lock + unit tests (N-D1 / N-D2 / N-D6)

- N3.0 — **N-D7 pre-flight (Opus extra-high):** lock how an Aureum-deployed Rate Provider address threads into a `pure`-literal config lib AND the N6 fork fixture. Candidates: (a) CREATE2-deterministic deploy → bake the predicted address as the config literal; (b) fixture-side deploy + `vm.etch` / address-pin to a baked literal; (c) config-parameter injection (the sfrxUSD / scrvUSD / composite RP is passed in, not baked). The choice determines whether the sfrxUSD configs (20 / 27), the scrvUSD + sfrxUSD legs of ixLibertas (06), and the two ixAetheron composites (02) can stay pure-literal. §12 ambiguity-gate: this blocks the N2.8 / N2.15 / N4 RP-literal §8e.1 prompts until locked as N-D7 in NOTES + this table.
- N3.1 — `src/rate_provider/ERC4626RateProvider.sol` (Opus extra-high): Aureum-owned `is IRateProvider`, `getRate()` returns `IERC4626(wrapper).previewRedeem(FixedPoint.ONE)`; one immutable, zero admin, zero storage. The ~22-line Balancer pattern (NOT a submodule edit, §8c).
- N3.2 — `src/rate_provider/CompositeRateProvider.sol` (Opus extra-high): `(IERC4626 wrapper, IRateProvider underlyingRP)`, `getRate() = wrapper.previewRedeem(FixedPoint.ONE).mulDown(underlyingRP.getRate())`; two immutables, zero admin, zero storage (N-D1).
- N3.3 — `test/unit/RateProvider.t.sol` (Sonnet after design set): `getRate()` correctness vs a mock ERC-4626 + mock underlying RP; round-down direction; zero-rate / revert propagation from the underlying RP; mixed-decimals scaling.
- Checkpoint: `forge build` green; `forge test --match-path "test/unit/RateProvider.t.sol"` green; N-D7 recorded in NOTES + this table.

### N4.0—N4.2 — The two resolvable Majors (N-D1 / N-D3 / N-D4)

- N4.0 — **Token/RP preflight (Opus, N-D1 gate):** resolve the real `waEthrETH` Aave-stataToken wrapper mainnet address to the E-D17 bar (`07a` lists canonical rETH `0xae78736…`, not the wrapper), and fork-verify both ixAetheron underlying RPs return nonzero (`0x1a8F81…` rETH RP; `0x8762…` Aave weETH oracle — the M-D11 revert-class watch). NOTES-only; gates N4.1.
- N4.1 — `02_ixAetheron.s.sol` + `DeployIxAetheron.s.sol`: Non-Standard 27/27/15/15/16 — waEthrETH 27% + waEthweETH 27% (both via N3.2 `CompositeRateProvider`, N-D1) + ixEDEL 15% + RPL 15% + ETHFI 16%; QG = the two composite cores = 54%.
- N4.2 — `06_ixLibertas.s.sol` + `DeployIxLibertas.s.sol`: Non-Standard 7-token USD hub (N-D4 composition) — scrvUSD 15% + PYUSD 15% + GHO 14% + sUSDS 14% + sfrxUSD 14% + USDT 14% + USDC 14%; scrvUSD / sfrxUSD via N3.1 `ERC4626RateProvider` (N-D2), USDC / USDT / PYUSD bare STANDARD (N-D3 / N-D4); QG = scrvUSD + GHO + sUSDS + sfrxUSD = 57%.
- Checkpoint per pool: `forge build` green + weight-sum grep totals `1e18` and ERC-4626 share ≥ `52e16`.

### N5 — Bind orchestration `script/DeployStageN.s.sol` (M-D9 shape)

A bind-only, `GOVERNANCE_MULTISIG`-authored `forge script` over the 18 pools, mirroring `DeployStageM.s.sol` exactly: consume the 18 deployed pool addresses as env inputs plus `MILIARIUM_REGISTRY` / `GAUGE_REGISTRY` / `EMISSION_DISTRIBUTOR` / `FEE_ROUTING_HOOK` / `GOVERNANCE_MULTISIG`; after three fail-fast governance preconditions (`registry.governanceContract()` / `gauge.governanceContract()` / `distributor.governance()` each `== governor`), per (slot, pool) call `registry.replaceSlot(slot, pool)` (zero→nonzero `SlotPopulated`), `gauge.seedFoundingPool(pool)`, and `distributor.setAuMTContractForPool(pool, FEE_ROUTING_HOOK)` (shared-hook recorder, OQ-I10). `hook.setEmissionRecorder` is one-shot-bound at Stage I and is NOT re-called. `run()` simulates as the multisig; `deploy(governor)` is the testable `vm.startPrank` entry.

- Checkpoint: `forge build` green; the 18 env keys + three fail-fast errors present; bind loop covers all 18 (slot, pool) pairs.

### N6 — Fork integration + deploy-script tests (N-D5; `test/fork/StageNIntegration.t.sol` + `test/fork/DeployStageN.t.sol`)

Both files inherit `StageIIntegrationFixture` per N-D5. `StageNIntegrationFixture` deploys the 18 pools via their `DeployIx*.run()` wrappers, stands up a fresh real `MiliariumRegistry` seeded `[1,5,14]`, deploys the four new RP instances (two `CompositeRateProvider` + two `ERC4626RateProvider`) per the N-D7 mechanism, env-wires the `DeployStageN` inputs, and runs `DeployStageN.deploy(address(this))`. Assertion scope (N-D5 / M-D10): binding-liveness + QG re-assert (`evaluateEligibility`) + Rate-Provider resolve (`getRate() > 0`, covering the four new RP instances + the sfrxUSD legs on 20 / 27) + hook attach — NOT live emission accrual. `DeployStageN.t.sol` adds the three fail-fast governance-precondition reverts (per `DeployStageL.t.sol:100`). Split-form fork invocation per D35 (`--match-path "test/fork/**" --fork-url $MAINNET_RPC_URL`); `--threads 1` per D36 if env-key races surface.

- Checkpoint: full split-form regression green (unit + fork); the new RP `getRate()` resolve assertions pass on the four instances + 20 / 27.

### N7 — WN whitehat pass + Stage N close + tag `stage-n-complete`

WN whitehat pass over the new `src/rate_provider/` surface (N-D6) — first Aureum-owned RP contracts; review rounding direction, `previewRedeem` vs `convertToAssets`, zero-rate / revert propagation, decimals — with PoC suite(s) under `test/whitehat/` per the WM / WL cadence; any finding fixed fix-forward. Then: full split-form regression green; §11 resume-anchor refresh; this PLAN's Completion log finalized; `STAGES_OVERVIEW.md` Stage N row marked complete; tag `stage-n-complete`; ff-merge to `main`.

---
## Completion log

| Sub-step | Commit | Summary |
| --- | --- | --- |
| N0.1 | `ccfb392` | `STAGE_N_NOTES.md` — design freeze N-D0—N-D6 (18-pool scope; CompositeRateProvider + ERC4626RateProvider surface; ixLibertas bare-stable + 57% QG; M-D10-mirror fork scope; WN whitehat gate) |
