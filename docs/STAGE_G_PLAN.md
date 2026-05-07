# Stage G — gauge state machine + auto-gauge eligibility

> **Status:** In progress on `stage-g`. Companion to `docs/STAGE_G_NOTES.md`.
>
> **Audience:** Sagix plus any future Claude session that needs to know what Stage G is and what it produces.
>
> **Why this file exists:** resumption anchor outside chat scrollback — this file is the entry point for Stage G work.

---

## Scope of Stage G

**Goal:** ship the gauge state machine — auto-gauge eligibility, three activation paths (permissionless / composition / founding-pool seeding), the Vault-Class Registry that gates the 52% Quality Gate numerator, and the epoch-boundary efficiency tournament cohort assignment that the Stage H emission distributor consumes. Pure protocol logic; no emissions yet, no AuMT yet, no on-chain governance yet — placeholder + one-shot setter pattern per F-D20–F-D23 for forward dependencies.

**The Solidity files Stage G produces:**

1. **`src/gauge/VaultClassRegistry.sol`** — Frankencoin-inspired proposal-and-veto class admission for ERC-4626 vault classes counted toward the 52% Quality Gate numerator. Three admission fingerprints (`ImplementationAddress`, `FactoryAddress`, `BytecodeHash`) per **G-D9**. Genesis class set seeded via constructor-hardcoded constants (Option a — bytecode-immutable). Bond routes via the OQ-G3 swap-and-one-sided-deposit primitive to der Bodensee. Veto threshold + window + bond magnitude lock at G1.x. Forward deps (`IAuMT`, `governanceContract`) wired via placeholder + one-shot setter mirroring Stage F's F-D20–F-D23 pattern. Companion interface `IVaultClassRegistry.sol` for narrow read surface.

2. **`src/gauge/GaugeEligibility.sol`** — epoch-boundary eligibility evaluator. Reads pool weights via `IBasePool.getNormalizedWeights()`, classifies each token via the ERC-4626 detection method (try/catch `IERC4626.asset()` per **G-D10**), looks up admitted classes in `VaultClassRegistry`, and checks: (i) 52% numerator gate per **G-D8**; (ii) $10K TVL 7-day-SMA floor per **OQ-G2**; (iii) F-10 efficiency tournament cohort assignment per **G-D3** (top-15% favored cohort vs bottom-85% residual); (iv) pool-type whitelist per **G-D6** (fails closed); (v) forbidden-token block (AuMM, AuMT) per **T-I3**. Eligibility latches per epoch and is recomputed at boundaries only. Emits `GaugeEfficiencyDropped` / `GaugeEfficiencyRising` exactly once per pool per boundary crossing per **G-D5**. Companion interface `IGaugeEligibility.sol`. F-10 ranking math may live as a colocated pure helper (inline or `src/gauge/EfficiencyRanking.sol`) per **G-DP3** — physical factoring is a G2 implementation choice, not a protocol fork.

3. **`src/gauge/GaugeRegistry.sol`** — concrete gauge-registration surface implementing the three activation entry points per **G-D1** + **G-D7**: (i) permissionless `activateGauge(pool)` (any caller, full eligibility gate, OQ-G3 anti-spam fee, **no** boost); (ii) `registerGaugeFromComposition(pool)` (`onlyGovernanceContract`, composition-criteria subset, **applies 90-day boost atomically**); (iii) `seedFoundingPool(pool, seedAmount)` (`onlyGovernanceContract`, eligibility bypassed for zero-TVL deploy shim, **applies 90-day boost**). Boost asymmetry enforced structurally — boost-application code path unreachable from `activateGauge`. Concrete registry replaces the placeholder consumed by Stage F's `IGaugeRegistry` mocks via the F-D23 one-shot seal pattern. Reuses or extends Stage F's `IGaugeRegistry.sol`; if extended (richer surface needed), keeps original interface bytecode-stable for F callers.

**The tests Stage G produces:**

- **`test/unit/VaultClassRegistry.t.sol`** — proposal-and-veto state machine, three admission fingerprints, bond routing to der Bodensee via OQ-G3, genesis-seeded class assertion, veto window + threshold guards, `revokeVaultClass` + grandfather policy, placeholder-then-one-shot-setter unreachability of veto + governance-restricted entry points.

- **`test/unit/GaugeEligibility.t.sol`** — 52% numerator computation across mixed token sets (admitted/non-admitted 4626 + plain ERC-20), ERC-4626 detection (try/catch behavior), forbidden-token block (T-I3), pool-type whitelist (T-I4 fast-track absent, G-D6 fails-closed), TVL-floor gate (OQ-G2), F-10 cohort assignment direction (T-T1/T-T2 transition events), epoch-snapshot determinism (T-I5).

- **`test/unit/GaugeRegistry.t.sol`** — three activation paths, T-I1 atomic-boundary check, T-I2 anti-spam non-refund, T-T4 composition path with boost application + atomic substitution, T-R1 founding-pool seeding via Authorizer-Safe deploy shim, gate-failure paths (each immutable criterion).

- **`test/fork/GaugeFlow.t.sol`** — fork integration against Stage E pilot pools + Stage F CCB engine: full permissionless activation path, founding-pool seeding shim, composition substitution, epoch-boundary cohort assignment with synthetic TVL signals via Stage F's `MockTVLOracle` (re-imported from `test/fork/mocks/CCBMocks.sol`), `GaugeEfficiencyDropped` / `GaugeEfficiencyRising` end-to-end emission verification.

**The directory addition Stage G performs:** Create `src/gauge/` for the three contracts + companion interfaces + any colocated pure-math helpers (e.g. F-10 ranking per **G-DP3**). No other directory reorganization.

---

## Pragma + license note (Stage G)

All Aureum-authored Stage G files use `pragma solidity ^0.8.26` per cursorrules rule 4. License `SPDX-License-Identifier: GPL-3.0-or-later`. Consistent with Stage C / Stage D / Stage E / Stage F Aureum-authored files.

No upstream Balancer V3 inheritance at Stage G (gauge logic is pure Aureum), so there is no `^0.8.24` precedent at this stage like the Stage B `AureumVaultFactory` or Stage E `AureumWeightedPoolFactory`.

---

## Decisions locked in before Stage G starts

These are the answers to the planning-stage questions resolved before this file was written. They are recorded here so implementation doesn't re-litigate them.

The Stage G **design freeze** lives in `docs/STAGE_G_NOTES.md` as `G-D1` through `G-D10`. The PLAN does not duplicate that prose — it points to it. Mid-stage NOTES additions continue as **`G-D11`, `G-D12`, …**; mid-stage implementation findings are numbered **`G10`, `G11`, …** (two-digit) per `CLAUDE.md` §5. The PLAN's own planning-mechanics decisions (sub-step layout, branch model, test invocation, file factoring) use the **`G-DP*`** prefix to avoid collision with the NOTES-owned `G-D*` series.

| ID | Subject | One-line summary | Canonical record |
|----|---------|------------------|------------------|
| **G-D1** | Auto-gauge vs governance-only paths | Permissionless `activateGauge(pool)` once eligibility gate + OQ-G3 anti-spam fee clear; governance composition path via `registerGaugeFromComposition` is the execution leg of an approved composition proposal, not a fourth vote type. | `STAGE_G_NOTES.md` G-D1 |
| **G-D2** | Sandbox fast-track deprecated | Must not appear as callable logic on `GaugeRegistry` / `GaugeEligibility`; `aumm-site` `08_bootstrap.md` §xxi fast-track row obsolete relative to repo truth. | `STAGE_G_NOTES.md` G-D2 |
| **G-D3** | Efficiency tournament semantics | Sort descending by `efficiency_ratio` per `11_formulas.md` F-10; favored cohort = ranks `1 ≤ rank ≤ ceil(0.15 × N)` (top 15%); bottom 85% receives residual CCB flow only. Caps clause defers to G1.x. | `STAGE_G_NOTES.md` G-D3 |
| **G-D4** | Growth-signal doctrine | Miliarium losing top-tier standing post-Month-11 is expected competitive dynamics, not a protocol failure state; `GaugeEfficiencyDropped` feeds bot/aggregator surfaces. | `STAGE_G_NOTES.md` G-D4 |
| **G-D5** | Threshold transition events | `GaugeEfficiencyDropped` / `GaugeEfficiencyRising` ABI; emitted exactly once per pool per boundary crossing per epoch resolution; svZCHF-denominated 18-decimal `tvlSma` (OQ-22) + 1e18-scaled `efficiencyRatio` (OQ-G1). | `STAGE_G_NOTES.md` G-D5 |
| **G-D6** | Pool-type whitelist | At activation, pool factory-derived type must be in allowed set; exact enum locks at G1.x against deployed factories; fails closed. | `STAGE_G_NOTES.md` G-D6 |
| **G-D7** | Three activation paths + per-path boost policy | `activateGauge` (no boost), `registerGaugeFromComposition` (90-day boost), `seedFoundingPool` (90-day boost); boost asymmetry enforced structurally — boost path unreachable from `activateGauge`. `seedFoundingPool` parameter shape locks at G1.x. | `STAGE_G_NOTES.md` G-D7 |
| **G-D8** | Canonical 52% numerator definition | Sum of pool weights assigned to ERC-4626 tokens whose class is admitted in `VaultClassRegistry`; re-evaluated per epoch boundary; admissions/revocations take effect at next boundary. Verbatim from FINDINGS OQ-G4. | `STAGE_G_NOTES.md` G-D8 |
| **G-D9** | Vault-Class Registry mechanism | Frankencoin-inspired proposal + veto + auto-finalize + revocable-with-grandfather; three admission fingerprints (`ImplementationAddress` / `FactoryAddress` / `BytecodeHash`); genesis class set via constructor-hardcoded constants (Option a); bond / veto threshold / window defer to G1.x with non-regressable constraints. | `STAGE_G_NOTES.md` G-D9 |
| **G-D10** | ERC-4626 detection method | Try/catch `IERC4626.asset()`; non-revert ⇒ 4626-claiming, gated by `VaultClassRegistry` admission; revert ⇒ plain ERC-20. Stateless on registry side; T-I3 forbidden-token check runs first. | `STAGE_G_NOTES.md` G-D10 |

Planning-mechanics decisions specific to PLAN authoring (sub-step layout, branch model, test invocation, file factoring, forward-dependency wiring) are captured below as `G-DP*`.

| ID | Decision |
|----|----------|
| **G-DP1** | **Stage G scope:** auto-gauge eligibility (52% numerator gate + TVL floor + F-10 cohort + pool-type whitelist + forbidden-token block + epoch-snapshot determinism), three activation paths (permissionless / composition / founding-pool seeding), Vault-Class Registry (proposal + veto + revoke), threshold transition events, anti-spam fee routing via the OQ-G3 swap-and-one-sided-deposit primitive. **Not in scope:** F-10 numeric caps tunable values (deferred to G1.x within Stage G), Sandbox fast-track (deprecated per **G-D2**), permissionless-veto governance variant (post-Stage-G design question per **G-D8**), AuMT vote-weight resolution (Stage I; placeholder + one-shot setter), `governanceContract` resolution (Stage K; same placeholder pattern), `GaugeChallenge.sol` separate contract (only modeled if permissionless-challenge variant adopted post-G), Incendiary boost (Stage L). |
| **G-DP2** | **Contract layout: 3 separate contracts under `src/gauge/`** — `VaultClassRegistry.sol`, `GaugeEligibility.sol`, `GaugeRegistry.sol`, plus narrow companion interfaces and any colocated pure-math helpers (F-10 ranking). Decomposition rationale: the registry holds class-admission state with its own access-control surface; eligibility holds epoch-boundary read logic with no privileged state; the gauge registry holds activation entry points + boost-application with the three-path access matrix. Three distinct audit surfaces with discrete state and gate models. |
| **G-DP3** | **F-10 efficiency tournament factoring.** F-10 cohort + ranking math ships **as part of `GaugeEligibility.sol`'s G2 surface** (same epoch-boundary latch as TVL floor + 52% gate). Physical factoring (inline within `GaugeEligibility` vs colocated pure library `src/gauge/EfficiencyRanking.sol`) is a **G2 implementation choice** — not a protocol fork — driven by contract size, audit clarity, and any circular-dependency surface that surfaces at G2 entry. No separate `EfficiencyTournament.sol` in scaffold scope. |
| **G-DP4** | **Forward-dependency wiring — placeholder + one-shot setter pattern (mirrors Stage F F-D20–F-D23).** `IAuMT` (Stage I) and `governanceContract` (Stage K) ship as placeholder addresses + one-shot setters in `VaultClassRegistry.sol` and `GaugeRegistry.sol`. Pre-Stage-I + pre-Stage-K, the veto path and governance-restricted entry points (`registerGaugeFromComposition`, `seedFoundingPool`, `revokeVaultClass`) are **structurally unreachable**. Permissionless `activateGauge` against genesis-seeded classes remains usable for testing and integration before either dependency lands. |
| **G-DP5** | **Anti-spam fee routing.** OQ-G3 fee (100 svZCHF/sUSDS equivalent) routes via the shared swap-and-one-sided-deposit primitive to der Bodensee. The same primitive serves the `VaultClassRegistry` proposal bond. Whether the primitive ships fresh in Stage G (likely a colocated helper under `src/gauge/` or `src/fee_router/`), imports from a Stage D/L precursor, or piggybacks on `AureumFeeRoutingHook`'s settlement path is determined at **G-DP10**. Both surfaces depend on this primitive being callable. |
| **G-DP6** | **Test layout.** Per-contract unit-test file under `test/unit/` (`VaultClassRegistry.t.sol`, `GaugeEligibility.t.sol`, `GaugeRegistry.t.sol`); one integration fork-test file under `test/fork/GaugeFlow.t.sol` exercising the Stage D + Stage E pilot-pool deployment chain plus Stage F's `MockTVLOracle` (re-imported from `test/fork/mocks/CCBMocks.sol`) for synthetic TVL feeds — avoids depending on OQ-22's concrete oracle. Test invocation follows the D35 split-form: unit suite via `--no-match-path "test/fork/**"`; fork suite via `--match-path "test/fork/**" --fork-url $URL --threads 1` (per F-D11 / D36). |
| **G-DP7** | **Sub-step layout.** **G0** plan + notes scaffold (G0a NOTES landed at `STAGE_G_NOTES.md`; G0b is this PLAN scaffold). **G1** `VaultClassRegistry.sol` + `IVaultClassRegistry.sol` + unit tests + tunables lock (bond / veto threshold / window / pool-type whitelist enum / OQ-G3 fee primitive resolution per **G-DP10**) — internal sub-rows **G1.1, G1.2, …** rather than a floating top-level G6 per scope-clarification. **G2** `GaugeEligibility.sol` + `IGaugeEligibility.sol` + unit tests, including F-10 ranking + cohort assignment per **G-DP3**. **G3** `GaugeRegistry.sol` + interface (extend or replace Stage F's `IGaugeRegistry.sol`) + unit tests for the three activation paths. **G4** `test/fork/GaugeFlow.t.sol` integration test against pilot pools + Stage F CCB engine. **G5** docs (`STAGES_OVERVIEW.md` Stage G row update + this file's Completion Log + `CLAUDE.md` §11 refresh + FINDINGS cross-refs as needed). **G9** close (FF merge to `main`, tag `stage-g-complete`, push). Final numbering may refine at G1 entry; broad shape locked. |
| **G-DP8** | **Pragma `^0.8.26` + license `GPL-3.0-or-later` for all Stage G files.** No upstream Balancer-V3 inheritance at Stage G (gauge logic is pure Aureum), so no `^0.8.24` precedent at this stage. Compiler is `solc 0.8.26` per `foundry.toml`. License matches Stage C / Stage D / Stage E / Stage F Aureum-authored files. |
| **G-DP9** | **Branch model:** `stage-g` working branch from `main` (created at the post-Stage-F tip — F5.3 CLAUDE.md §11 refresh on `main`); `git push origin stage-g` early per the D9 lesson — don't let origin lag the local branch. Fast-forwards to `main` at G9; `stage-g-complete` lightweight tag applied on `main` at the tip. Preserve `stage-g` on origin as a snapshot marker per the C0 / D0 / E-D8 / F-D14 convention. No PR workflow. |
| **G-DP10** | **OQ-G3 swap-and-one-sided-deposit primitive — sourcing resolved at G1 entry.** The primitive is the shared rail for both the `VaultClassRegistry` proposal bond and the `GaugeRegistry` anti-spam fee. Three live options at G1 entry: (a) ship fresh as a colocated helper under `src/gauge/` (e.g. `src/gauge/SwapAndDepositToBodensee.sol`); (b) import from a Stage D / Stage L precursor if one exists at G1 entry — verified against repo state; (c) extend `AureumFeeRoutingHook`'s settlement path with a non-swap-leg entry point that performs the swap-then-one-sided-deposit and settles. Pre-G1 sub-step resolution required — `VaultClassRegistry.sol` constructor + `proposeVaultClass` shape both depend on the primitive's call signature. |

---

## Mid-stage supersessions

> Decisions resolved during Stage G that revise values or framing locked in by the entry-time decisions above. Each entry preserves the canonical record location in `docs/STAGE_G_NOTES.md` (full reasoning) and `docs/FINDINGS.md` (OQ marker, when applicable). The lock table is left intact as historical context — read these supersessions alongside it.

- **G-DP10 → G-D11 (RESOLVED at G1.0, `STAGE_G_NOTES.md` G-D11):** OQ-G3 swap-and-deposit primitive sourcing — Option A confirmed (fresh helper at `src/gauge/SwapAndDepositToBodensee.sol`); Stage D `AureumFeeRoutingHook` bytecode untouched. α-via-DONATION (`AddLiquidityKind.DONATION`, zero BPT minted) supersedes the BPT-to-recipient framing implicit in G-DP10's option list. Pre-requisite: Bodensee deploy-script `enableDonation` flag flip at `script/DeployDerBodensee.s.sol` line 81 lands as discrete sub-step **G1.1** ahead of `VaultClassRegistry.sol` Solidity; coexists with Stage D's UNBALANCED fee-routing path on a single Bodensee instance. Two-numéraire support (svZCHF + sUSDS) via Bodensee's existing Rate Providers, svZCHF-anchored (**G-D11.eq**). Caller surface gated via placeholder + one-shot setter pattern (F-D20–F-D23 family).

---

## What is explicitly NOT in Stage G

- F-10 numeric caps tunable values (15/10/5 → 1%/0.5%/0.1%) — retain/drop/replace defers to G1.x within Stage G; cohort direction is the Stage G lock per **G-D3**.
- Sandbox fast-track entry point — deprecated per **G-D2**; must not ship as dead code.
- Permissionless-veto governance variant (anyone may revoke with bond, Frankencoin-style open challenge) — post-Stage-G design question per **G-D8**.
- `GaugeChallenge.sol` separate contract — only modeled if a permissionless-challenge variant is later adopted; not in current scope.
- AuMT (LP receipt token, per-pool, governance vote weight) — Stage I; placeholder + one-shot setter at Stage G per **G-DP4**.
- On-chain governance contract (`governanceContract` for `revokeVaultClass`, `registerGaugeFromComposition`, `seedFoundingPool`) — Stage K; same placeholder + one-shot setter pattern per **G-DP4**.
- F-7 emission distribution (per-block AuMM minting and routing) — Stage H.
- F-3 linear blend (Months 11–12 transition) — Stage H.
- F-0 bootstrap channel (one-sided AuMM deposits to der Bodensee Months 0–10) — Stage H.
- Incendiary Boost (priority skim from emission stream pre-CCB) — Stage L.
- `MiliariumRegistry.sol` — Stage J. Stage F injects an `IMiliariumRegistry` placeholder; Stage G continues to consume it via the same shape.
- Concrete TVL oracle implementation — OQ-22 resolution stage; Stage G integration tests use Stage F's `MockTVLOracle`.
- Aureum's own Router — D33 deferred, post-D / re-entry at K or O.
- OQ-20 controller yield-fee entry point + OQ-21 bi-weekly cadence — post-D, tracked.
- Mainnet deployment of the gauge state machine — Stage R.
- `aumm-site` spec amendments (user-side follow-up): `08_bootstrap.md` §xxi Sandbox fast-track row deprecation (precheck C-3); FINDINGS OQ-11 + OQ-10 fee + proposal-types prose (precheck C-1 / C-2); Stage M/N gauge-approvals wording (C-4); Stage P four-types wording (C-5); F-11 vs F-10 efficiency-formula label correction (C-6).

---

## Sub-steps

> Sub-step bodies populate as they are planned. This section's headers are placeholders for G0 through G9 detail.

### G0 — Plan + notes scaffold

G0 lands the Stage G design freeze, planning-mechanics layer, and FINDINGS addendum ahead of any source. Three docs commits:

- **G0a + G0b** — `docs/STAGE_G_NOTES.md` + `docs/STAGE_G_PLAN.md` paired scaffold (commit `61fb085`, 2026-05-05) — design freeze **G-D1** through **G-D10** in NOTES, planning-mechanics **G-DP1** through **G-DP10** in PLAN, test matrix `T-I1`–`T-I5` / `T-T1`–`T-T4` / `T-R1`, efficiency-event ABI (`GaugeEfficiencyDropped` / `GaugeEfficiencyRising`), Vault-Class Registry mechanism lock per **G-D9**, ERC-4626 detection method per **G-D10**, "what is explicitly NOT in Stage G" boundary.
- **G0c** — `docs/FINDINGS.md` Stage G addendum (commits `37d985b` / `b9a30c6` / `dd3d7df`, 2026-05-05) — **OQ-G1** (efficiency metric → F-10 `efficiency_ratio`), **OQ-G2** (TVL floor cadence → epoch-boundary snapshot), **OQ-G3** (anti-spam fee destination → der Bodensee via the swap-and-one-sided-deposit primitive), **OQ-G4** (Vault-Class Registry — Frankencoin-inspired veto, three admission fingerprints, genesis-seeded constants).

- **Cursor prompt:** N/A — G0a/G0b/G0c landed pre-PLAN-body-fill on the `stage-g` branch; this section documents the scaffold completed at stage entry, not future work.

### G1 — VaultClassRegistry + tunables lock

G1 ships **two** contracts under `src/gauge/`: the **OQ-G3** swap-and-one-sided-deposit primitive (`SwapAndDepositToBodensee.sol`, the shared rail for both the registry's proposal bond and the gauge registry's anti-spam fee per **G-D11** + **G-D12**) and the Vault-Class Registry (`VaultClassRegistry.sol` + `IVaultClassRegistry.sol`, the Frankencoin-inspired class-admission state machine per **G-D9**). Plus their unit tests, one fork-only suite for the helper's V3 callback contract, and a NOTES-only tunables lock that pins concrete `proposalBond` / `vetoThreshold` / veto-window-blocks ahead of any source consuming them.

Sub-row layout: G1.0–G1.3-fix landed pre-source (NOTES + Bodensee deploy-script flag + stale-language sweeps); G1.4–G1.8 deliver the helper (scaffold + constructor + callback + unit tests + fork tests); G1.9 locks registry tunables in NOTES; G1.10–G1.16 deliver the registry (interface + scaffold + constructor + propose / veto / revoke + unit tests).

#### G1.0 — Option A + DONATION decision (G-D11 + G-DP10 supersession) ✅ done (commit `5567533`)

OQ-G3 primitive sourcing resolved at **G-DP10 → G-D11** (Option A): fresh helper at `src/gauge/SwapAndDepositToBodensee.sol`; Stage D `AureumFeeRoutingHook` bytecode untouched (`stage-d-complete` audit-inheritance preserved); α-via-DONATION (`AddLiquidityKind.DONATION`, zero BPT minted) supersedes G-DP10's BPT-to-recipient framing; two-numéraire (svZCHF + sUSDS), svZCHF-anchored; caller surface gated via placeholder + one-shot setter pattern (F-D20–F-D23 family).

- **Cursor prompt:** N/A — landed at `5567533`.

#### G1.1 — Bodensee `enableDonation = true` + test fixture updates ✅ done (commit `07b65a6`)

`script/DeployDerBodensee.s.sol` line 81 flag flip from `false` to `true` per **G-D11** pre-requisite. Test-fixture updates in `test/fork/AureumFeeRoutingHook.t.sol`, `test/fork/PilotPools.t.sol`, `test/fork/CCBEngine.t.sol` to keep Stage D's UNBALANCED fee-routing path and Stage G's DONATION anti-spam path coexistent on a single Bodensee instance. V3 supports both add-liquidity kinds when `enableDonation = true` AND `disableUnbalancedLiquidity = false`. Stage D contract bytecode untouched.

- **Cursor prompt:** N/A — landed at `07b65a6`.

#### G1.2 — Helper full spec lock (G-D12) ✅ done (commit `7afca17`)

Resolves G-D11 "Tunables / sub-decisions deferred to G1.x" residual in NOTES. Locks signature (`swapAndDeposit(IERC20, uint256)` + `requiredAmount(IERC20)` view) + payment pattern (caller pre-pushes; helper transfers OWN balance; post-callback balance == 0 assertion) + pay-token allowlist (svZCHF / sUSDS only — every other token reverts `InvalidPayToken`) + strict-equality fee policy (`FEE_SVZCHF = 100e18`, `FEE_SUSDS = 125e18`; underpay/overpay reverts `IncorrectAmount`) + one-shot caller-gate model (placeholder → `setVaultClassRegistry` / `setGaugeRegistry`, irreversible admin burn at second set) + nine-step callback discipline + token-index resolution at constructor + CEI rules + custom-error enumeration. Audit surface fully enumerated for G1.7 (unit) + G1.8 (fork) + Stage Q (formal).

- **Cursor prompt:** N/A — landed at `7afca17`.

#### G1.3 — 90-day boost deprecation (G-D13 + G-D7 / G-D1 / T-T4 inline amendments) ✅ done (commit `7164b13`)

90-day boost deprecated entirely across all three activation paths per **G-D13**. Cold-start emission lift, if any, funded out-of-band via Incendiary Boost (Stage L) — opt-in, user-funded, applicable to any already-gauged pool. **G-D7** boost columns flipped to "no"; "Per-path symmetry — no boost on any path" replaces the earlier asymmetry framing. **G-D1** composition-path bullet drops boost language. **T-T4** test scenario drops "boost clock starts." Companion spec sweep landed at `aumm-site` `08_bootstrap.md`, `09_transitions.md`, `04_tokenomics.md`, `05_miliarium_aureum.md`, `06_miliarium_manifest.md`, `12_aureum_glossary.md`, `14_ux_ui.md`, `17_faq.md` (receipt commit `055d89f`, "SG.AMEND-1"). `CCBMultiplier.sol` boost machinery (OQ-23 `activateBoost`, M_i clamp, F-D24 reset) is **unaffected** — Incendiary Boost (Stage L) reuses it.

- **Cursor prompt:** N/A — landed at `7164b13`.

#### G1.3-fix — Stale fee-language sweep (G-D9 + G-D11) ✅ done (commit `07e3c98`)

Replaces remaining "100 svZCHF/sUSDS" symmetric framing in **G-D9** + **G-D11** with the asymmetric per-token constants from **G-D12** (`FEE_SVZCHF = 100e18`, `FEE_SUSDS = 125e18`). G-D9 `proposalBond` constraint reframed to `proposalBond ≥ FEE_SVZCHF` (= 100e18) since the bond is svZCHF-denominated and must not undercut the cheaper of the two anti-spam fees. G-D11 "Equivalence" subsection notes supersession by G-D12.

- **Cursor prompt:** N/A — landed at `07e3c98`.

#### G1.4 — Helper scaffold (`src/gauge/SwapAndDepositToBodensee.sol`)

Lands storage / immutables / constants / custom-errors / event surface per **G-D12**. Pragma `^0.8.26`; license `GPL-3.0-or-later`. Imports: `IVault` from `lib/balancer-v3-monorepo`, `IERC20` + `SafeERC20` from `lib/openzeppelin-contracts`. Immutables: `_vault`, `_bodensee`, `_svZchf`, `_sUsds`, `_moduleAdmin`, `_svZchfIndex`, `_sUsdsIndex` (G1.5 fills constructor logic that populates the indices from `_vault.getPoolTokens(_bodensee)`). Storage: `moduleAdmin`, `vaultClassRegistry`, `gaugeRegistry`, plus reentrancy + transient-callback slots (`_executing`, `_pendingPayToken`, `_pendingAmount`, `_originalCaller`). Constants `FEE_SVZCHF = 100e18`, `FEE_SUSDS = 125e18`. Fourteen custom errors per G-D12: `OnlyAuthorizedCaller`, `OnlyVault`, `OnlyModuleAdmin`, `SetterAlreadyCalled`, `ZeroAddress`, `InvalidPayToken`, `ZeroAmount`, `IncorrectAmount`, `BptMintedOnDonation`, `ReserveDeltaMismatch`, `HelperBalanceNonZero`, `ReentrancyGuard`, `TokenNotInPool`, `CallbackPayloadMismatch`. `event FeeRoutedToBodensee(address indexed originalCaller, IERC20 indexed payToken, uint256 amount)`. No constructor body, no functions — type / state / error / event surface only.

- **Cursor prompt:** Create `src/gauge/SwapAndDepositToBodensee.sol`; declare immutables / storage / constants / custom errors / event per G-D12; no constructor body, no functions, no logic.

#### G1.5 — Helper constructor + token-index resolution + one-shot setters (`src/gauge/SwapAndDepositToBodensee.sol`)

Fills the constructor + `setVaultClassRegistry` + `setGaugeRegistry` + `onlyAuthorizedCaller` modifier per **G-D12** caller-gate model. Constructor: zero-address checks on all params (revert `ZeroAddress`); call `_vault.getPoolTokens(_bodensee)` → locate svZCHF + sUSDS indices; revert `TokenNotInPool` if either is absent; store as `_svZchfIndex` / `_sUsdsIndex` immutables. Set `moduleAdmin = _moduleAdmin`. Decision on `_moduleAdmin == address(0)` rejection vs test-harness acceptance pinned at this sub-step against deploy-script ergonomics (default = reject; if accepted, NOTES note required). Both setters (`setVaultClassRegistry` / `setGaugeRegistry`) gated to `moduleAdmin`, one-shot (revert `SetterAlreadyCalled` if slot already set), zero-input rejected (`ZeroAddress`), atomic admin-burn at second-set per G-D12. `onlyAuthorizedCaller` modifier: revert `OnlyAuthorizedCaller(msg.sender)` unless `msg.sender == vaultClassRegistry || msg.sender == gaugeRegistry` — partial-activation correctness is structural since `address(0)` never matches a real `msg.sender`.

- **Cursor prompt:** Add constructor + `setVaultClassRegistry` + `setGaugeRegistry` + `onlyAuthorizedCaller` modifier per G-D12; no entry point, no callback yet.

#### G1.6 — Helper `swapAndDeposit` outer + `_swapAndDepositCallback` (`src/gauge/SwapAndDepositToBodensee.sol`)

Fills the entry point + V3 Vault callback per **G-D12** nine-step callback discipline. `requiredAmount(IERC20 payToken) external view returns (uint256)`: returns `FEE_SVZCHF` for svZCHF, `FEE_SUSDS` for sUSDS, reverts `InvalidPayToken(payToken)` otherwise. `swapAndDeposit(IERC20, uint256) external onlyAuthorizedCaller`: allowlist guard, zero-amount guard, strict-equality fee guard (`if (amount != _requiredAmount(payToken)) revert IncorrectAmount(amount, required);`), reentrancy lock set, payload cache (`_pendingPayToken` / `_pendingAmount` / `_originalCaller = msg.sender`), `_vault.unlock(abi.encodeCall(this._swapAndDepositCallback, (payToken, amount)))`, transient teardown, post-balance assertion `if (payToken.balanceOf(address(this)) != 0) revert HelperBalanceNonZero(...)`. `_swapAndDepositCallback(IERC20, uint256) external`: sender-strict (`OnlyVault`), payload cross-check (`CallbackPayloadMismatch`), `preReserve` snapshot via canonical V3 reserve read (selector locked at this sub-step against `lib/balancer-v3-monorepo` HEAD — candidates `Vault.getReservesOf` / `IVault.getPoolTokenInfo` / `IVault.getCurrentLiveBalances`; same selector reused for `postReserve` to prevent mixed-source drift), `payToken.safeTransfer(address(_vault), amount)` + `_vault.settle(payToken, amount)`, build `maxAmountsIn[3]` with `payToken` slot = `amount` and other slots zero, `_vault.addLiquidity({pool: _bodensee, kind: AddLiquidityKind.DONATION, ...})`, defensive `if (bptOut != 0) revert BptMintedOnDonation(bptOut)`, `postReserve` read + `if (postReserve != preReserve + amount) revert ReserveDeltaMismatch(...)`, `emit FeeRoutedToBodensee(_originalCaller, payToken, amount)` — caller identity sourced from cached outer caller, never from callback `msg.sender`. Transient-storage-vs-storage choice for `_pendingPayToken` / `_pendingAmount` / `_originalCaller` / `_executing` decided at this sub-step against gas benchmark per G-D12 "Out of scope at G1.2."

- **Cursor prompt:** Add `requiredAmount` view + `swapAndDeposit` outer + `_swapAndDepositCallback` per G-D12 nine-step callback discipline; resolve V3 reserve-read selector against `lib/balancer-v3-monorepo` HEAD; transient-storage decision pinned in NOTES if non-default.

#### G1.7 — Helper unit tests (`test/unit/SwapAndDepositToBodensee.t.sol`)

Lands the 14 unit invariants enumerated in **G-D12**: unauthorized caller revert (`OnlyAuthorizedCaller`); pre-setter helper unreachable from any caller; partial-activation correctness (only-registry-set call path; only-gauge-set call path); post-both-set both callers allowed; second-set revert (`SetterAlreadyCalled`); admin-burn verification after second set (`moduleAdmin == address(0)`); invalid pay-token revert (`InvalidPayToken`); zero-amount revert (`ZeroAmount`); svZCHF underpay/overpay revert (`IncorrectAmount`); sUSDS underpay/overpay revert (`IncorrectAmount`); reentrancy guard fires on nested call attempt; non-Vault callback sender revert (`OnlyVault`); callback payload mismatch revert (`CallbackPayloadMismatch`); constructor `TokenNotInPool` revert when given a Bodensee that does not contain svZCHF or sUSDS. Mock fixtures: a `MockVault` with controllable `getPoolTokens` returns, controllable callback re-entry, and revert-injection hooks for the reentrancy / payload-mismatch / non-Vault-sender tests. Pure unit; no mainnet fork.

- **Cursor prompt:** Create `test/unit/SwapAndDepositToBodensee.t.sol` covering the 14 G-D12 unit invariants against a `MockVault`; pure unit (no fork).

#### G1.8 — Helper fork tests (`test/fork/SwapAndDepositToBodensee.t.sol`)

Lands the four fork invariants enumerated in **G-D12** against real Bodensee on mainnet fork (with `enableDonation = true` per G1.1). Setup: deploy fresh `AureumVault` + `WeightedPoolFactory` + Bodensee per Stage D's `script/DeployDerBodensee.s.sol`, deploy fresh `SwapAndDepositToBodensee`, wire `setVaultClassRegistry` + `setGaugeRegistry` to test-contract addresses (test contract acts as both authorized callers). svZCHF happy path: caller pre-pushes 100e18 svZCHF; calls `swapAndDeposit`; verify `bptOut == 0`, `postReserve - preReserve == 100e18` for svZCHF, helper post-balance == 0, `FeeRoutedToBodensee(test, svZCHF, 100e18)` event emitted with cached caller identity (not Vault). sUSDS happy path: same shape with 125e18 sUSDS. Counterfactual fee-on-transfer: synthetic FoT behaviour injected via `vm.mockCall` on `payToken.transfer` reverts `ReserveDeltaMismatch`. Test invocation per D35 split-form: `--match-path "test/fork/**" --fork-url $MAINNET_RPC_URL -vv --threads 1` per **F-D11** / **D36**.

- **Cursor prompt:** Create `test/fork/SwapAndDepositToBodensee.t.sol` covering the 4 G-D12 fork invariants against real mainnet-fork Bodensee with `enableDonation = true`; D35 split-form invocation.

#### G1.9 — VaultClassRegistry tunables lock (`docs/STAGE_G_NOTES.md`; NOTES-only)

Resolves the **G-D9** "tunables deferred to G1.x" residual ahead of any source consuming them. NOTES-only sub-step — no source, no test, no PLAN edit beyond a cross-link. Three values to pin, recorded as **G-D14** (or next available NOTES decision number):

- `proposalBond` — concrete svZCHF amount; constraint `proposalBond ≥ FEE_SVZCHF` (= 100e18) per G-D9 + G-D12 amendment; class-admission bond is higher-stakes governance and must not undercut the simpler permissionless-activation fee.
- `vetoThreshold` — AuMT-weighted vote-share threshold for successful veto; constraint `vetoThreshold ≤ governanceQuorumThreshold` per G-D9; governance quorum locks at Stage K, so G1.9 picks against the conservative ≤ 20% upper bound or a registry-specific lower fraction.
- Veto-window blocks — bounded `[BLOCKS_PER_EPOCH, 3 × BLOCKS_PER_EPOCH]` per G-D9; minimum gives a governance reaction window, maximum avoids stalling legitimate admissions.

If any value is still open at G1.9 entry, resolution happens in chat (Opus) before the Cursor prompt fires. Mode dispatch per §13 then routes the NOTES write itself to Sonnet (mechanical transcription).

- **Cursor prompt:** Add **G-D14** (tunables lock) to `docs/STAGE_G_NOTES.md` with the three values + rationale + constraints; NOTES-only — no `src/gauge/` edit, no PLAN edit beyond a cross-link entry, no test edit.

#### G1.10 — `IVaultClassRegistry` interface (`src/gauge/IVaultClassRegistry.sol`)

Lands the narrow read surface consumed by `GaugeEligibility` (G2) for class-admission lookups per **G-D8** + **G-D9**. `enum AdmissionType { ImplementationAddress, FactoryAddress, BytecodeHash }` per G-D9 three fingerprints. `function isAdmittedClass(address token) external view returns (bool)` — runtime check `GaugeEligibility` invokes per pool token after ERC-4626 detection per **G-D10**. `function admissionType(address token) external view returns (AdmissionType)` — diagnostic / event surfaces; not on the eligibility hot path. External read-only; mutations live on the concrete `VaultClassRegistry.sol`. Pragma `^0.8.26`; license `GPL-3.0-or-later`.

- **Cursor prompt:** Create `src/gauge/IVaultClassRegistry.sol` with `AdmissionType` enum + `isAdmittedClass` + `admissionType` read-only function surface; narrow read interface.

#### G1.11 — `VaultClassRegistry.sol` scaffold (`src/gauge/VaultClassRegistry.sol`)

Lands storage / immutables / constants (per G1.9 lock) / custom errors / events / struct definitions per **G-D9** + **G-D14** (G1.9 lock). No constructor body, no functions. Pragma `^0.8.26`; license `GPL-3.0-or-later`. Imports: `IVaultClassRegistry`, `SwapAndDepositToBodensee` (for bond routing), `IAuMT` placeholder (Stage I forward dep), governance-contract address placeholder (Stage K forward dep), `IERC20` + `SafeERC20` from OpenZeppelin. Constants from G1.9 NOTES lock: `PROPOSAL_BOND_SVZCHF`, `VETO_THRESHOLD_BPS` (or equivalent shape), `VETO_WINDOW_BLOCKS`. Storage: `mapping(uint256 => VaultClassProposal) public proposals; uint256 public nextProposalId; mapping(address => bool) public admittedClasses; mapping(address => AdmissionType) public admissionTypes;`. Forward-dep placeholder + one-shot setter pattern (F-D20–F-D23): `IAuMT public auMT; address public governanceContract; address public auMTSetter; address public governanceSetter;`. Struct `VaultClassProposal { AdmissionType admissionType; address admissionValue; bytes32 constraintsHash; uint256 createdBlock; uint256 vetoSupport; bool finalized; bool revoked; }`. Events: `VaultClassProposed(uint256 indexed proposalId, address indexed proposer, AdmissionType admissionType, address admissionValue, bytes32 constraintsHash)`, `VaultClassVetoed(uint256 indexed proposalId, address indexed vetoer, uint256 weight)`, `VaultClassFinalized(uint256 indexed proposalId, address indexed admissionValue)`, `VaultClassRevoked(address indexed admissionValue)`. Custom errors: `OnlyGovernance`, `ZeroAddress`, `InvalidAdmissionType`, `ProposalAlreadyFinalized`, `VetoWindowExpired`, `VetoWindowOpen`, `InsufficientVetoWeight`, `ClassAlreadyAdmitted`, `ClassNotAdmitted`, `SetterAlreadyCalled`.

- **Cursor prompt:** Create `src/gauge/VaultClassRegistry.sol` with type / state / constants / error / event / setter-stub surface per G-D9 + G1.9 NOTES lock; no constructor body, no propose / veto / revoke logic.

#### G1.12 — Constructor + genesis seeding + one-shot setters (`src/gauge/VaultClassRegistry.sol`)

Fills the constructor (genesis class admission via constructor-hardcoded constants per **G-D9** Option a) and the one-shot setters for `IAuMT` + `governanceContract`. Constructor: zero-address checks on `_helper` (the `SwapAndDepositToBodensee` instance), `_auMTSetter`, `_governanceSetter`. Genesis class set locked at this sub-step against deployed Stage E pilot tokens + planned Stage M/N profiles in `aummfi-bit/aumm-site/miliarium_profiles/` — exact set NOTES'd if it expands beyond the obvious waEthUSDC + ixEDEL + sUSDS-class wrappers. For each genesis class: `admittedClasses[token] = true; admissionTypes[token] = ...;` plus `VaultClassFinalized` emit. `setAuMT(address)`: gated to `auMTSetter`; one-shot; revert `SetterAlreadyCalled` if `auMT != IAuMT(address(0))`; sets `auMT` and zeroes `auMTSetter`. `setGovernanceContract(address)`: symmetric, gated to `governanceSetter`. Pre-setter, the veto path (consumes `IAuMT.governanceWeight`) and `revokeVaultClass` (gated to `governanceContract`) are structurally unreachable.

- **Cursor prompt:** Add constructor + genesis class seeding + `setAuMT` + `setGovernanceContract` per G-D9 Option a + F-D23 setter pattern; resolve genesis class set against Stage E + Stage M/N profiles at sub-step entry.

#### G1.13 — `proposeVaultClass` + bond routing via helper (`src/gauge/VaultClassRegistry.sol`)

Fills the public proposal entry point per **G-D9**. `proposeVaultClass(AdmissionType admissionType, address admissionValue, bytes32 constraintsHash) external returns (uint256 proposalId)`: validate `admissionValue != address(0)` (revert `ZeroAddress`); validate `admissionType` is one of the three enum variants (revert `InvalidAdmissionType` otherwise); check `!admittedClasses[admissionValue]` (revert `ClassAlreadyAdmitted` if already admitted); pull `PROPOSAL_BOND_SVZCHF` svZCHF from `msg.sender` via `safeTransferFrom`; push to helper via `safeTransfer`; call `helper.swapAndDeposit(svZCHF, PROPOSAL_BOND_SVZCHF)` per the **G-D12** caller-pre-push pattern; allocate `proposalId = nextProposalId++`; populate the `VaultClassProposal` struct (`createdBlock = block.number`, `vetoSupport = 0`, `finalized = false`, `revoked = false`); emit `VaultClassProposed`. No upfront approval check — tx reverts at `safeTransferFrom` if approval missing. No state mutation of `admittedClasses` — that happens at finalize. Bond is non-refundable (one-way to Bodensee via DONATION).

- **Cursor prompt:** Add `proposeVaultClass` per G-D9 mechanism — bond routing via helper using G-D12 caller-pre-push pattern, proposal struct allocation, event emission.

#### G1.14 — `vetoProposal` + auto-finalize on window expiry (`src/gauge/VaultClassRegistry.sol`)

Fills `vetoProposal` + `finalizeProposal` per **G-D9** "Veto window" + "Auto-finalize". `vetoProposal(uint256 proposalId) external`: revert `ProposalAlreadyFinalized` if `finalized || revoked`; revert `VetoWindowExpired` if `block.number > proposal.createdBlock + VETO_WINDOW_BLOCKS`; read AuMT-weighted veto weight via `auMT.governanceWeight(msg.sender)` (function name approximate — locks against Stage I `IAuMT` shape; pre-Stage-I, the placeholder returns zero so vetoes are impossible); add to `proposal.vetoSupport`; if `proposal.vetoSupport >= VETO_THRESHOLD`, set `proposal.finalized = true; proposal.revoked = true;` (proposal is dead, bond stays in Bodensee per the G-D9 "no refund" rule); emit `VaultClassVetoed`. `finalizeProposal(uint256 proposalId) external`: revert `ProposalAlreadyFinalized` if finalized; revert `VetoWindowOpen` if `block.number <= proposal.createdBlock + VETO_WINDOW_BLOCKS`; set `proposal.finalized = true`, `admittedClasses[proposal.admissionValue] = true`, `admissionTypes[proposal.admissionValue] = proposal.admissionType`; emit `VaultClassFinalized`. "Auto-finalize" per G-D9: not a separate timer — the first call to `finalizeProposal` after the veto window expires executes the state transition; permissionless caller. Single-tx state transition matches G-D9's "no explicit two-stage `finalize`-then-`execute`."

- **Cursor prompt:** Add `vetoProposal` (AuMT-weighted veto, threshold finalization, window-expiry guard) + `finalizeProposal` (window-expiry guard, admission-state set, event emission) per G-D9.

#### G1.15 — `revokeVaultClass` + grandfather logic (`src/gauge/VaultClassRegistry.sol`)

Fills `revokeVaultClass(address admissionValue) external onlyGovernance` per **G-D9** "Revocable-with-grandfather." `onlyGovernance` modifier: `if (msg.sender != governanceContract) revert OnlyGovernance(msg.sender);`. Pre-`setGovernanceContract`, the placeholder address rejects all calls — structurally unreachable. Function body: check `admittedClasses[admissionValue]` (revert `ClassNotAdmitted` otherwise); set `admittedClasses[admissionValue] = false`; emit `VaultClassRevoked`. "Grandfather policy" per G-D9: revocation blocks new numerator credit at the next epoch boundary per **G-D8** canonical definition; existing pools holding the now-revoked class lose numerator credit at the boundary; if they fall below 52%, they enter the standard graduated grace period from `08_bootstrap.md` §xxiii. The grace-period machinery itself is a `GaugeRegistry` (G3) concern; `revokeVaultClass` does not touch any pool state.

- **Cursor prompt:** Add `revokeVaultClass` per G-D9 — `onlyGovernance` gate, admission-flag flip, event emission; no pool state mutation (grace-period logic lives at GaugeRegistry G3).

#### G1.16 — `VaultClassRegistry` unit tests (`test/unit/VaultClassRegistry.t.sol`)

Lands unit invariants per the test matrix in `STAGE_G_NOTES.md` plus governance-restricted entry points. Proposal-and-veto state machine: propose → veto with sufficient weight → finalized-as-revoked; propose → veto with insufficient weight → window expires → finalize → admitted. Three admission fingerprints exercised (`ImplementationAddress` / `FactoryAddress` / `BytecodeHash`). Bond routing to der Bodensee via helper: mock helper to verify `swapAndDeposit(svZCHF, PROPOSAL_BOND_SVZCHF)` was called with correct args. Genesis-seeded class assertion: constructor admits the locked genesis set; `isAdmittedClass(genesisToken) == true` for each. Veto-window guards: `vetoProposal` reverts `VetoWindowExpired` after window; `finalizeProposal` reverts `VetoWindowOpen` before window. `revokeVaultClass`: governance-gated; `admittedClasses[token] = false` after revoke; pre-revoke admittedness asserted. Placeholder-then-one-shot-setter unreachability: pre-`setAuMT`, `vetoProposal` cannot reach finalization (placeholder `IAuMT` returns zero weight); pre-`setGovernanceContract`, `revokeVaultClass` reverts `OnlyGovernance(placeholder)`. Mock fixtures: `MockSwapAndDepositToBodensee`, `MockAuMT` (controllable per-address `governanceWeight` returns), `MockGovernance` (acts as `governanceContract` post-setter). Pure unit; no mainnet fork.

- **Cursor prompt:** Create `test/unit/VaultClassRegistry.t.sol` covering proposal + veto + finalize + revoke + genesis-seed + placeholder-unreachability invariants per G-D9 + G1.9 lock; pure unit (no fork).

### G2 — GaugeEligibility + F-10 ranking

G2 ships `GaugeEligibility.sol` + `IGaugeEligibility.sol` — the epoch-boundary eligibility evaluator. It reads pool weights via `IBasePool.getNormalizedWeights()`, classifies each token via ERC-4626 detection (**G-D10**), checks class admission in `VaultClassRegistry` (**G-D8**), enforces the $10K TVL 7-day-SMA floor (**OQ-G2**), applies the pool-type whitelist (**G-D6**), blocks forbidden tokens (**T-I3**), runs the F-10 efficiency tournament cohort assignment (**G-D3**), and emits threshold transition events (**G-D5**). The contract is primarily read-path logic; the only state written is the per-pool eligibility latch and cohort assignment, updated at epoch boundaries.

Sub-row layout: G2.0 locks pool-type whitelist enum + F-10 caps disposition + $10K TVL floor encoding in NOTES; G2.1–G2.2 deliver the interface + scaffold; G2.3–G2.5 fill the core computation methods; G2.6 delivers the public eligibility surface; G2.7 delivers unit tests.

#### G2.0 — GaugeEligibility tunables lock (`docs/STAGE_G_NOTES.md`; NOTES-only)

Resolves the G-D6 "exact pool-type enum locks at G1.x" residual and the G-D3 "caps clause deferred to G1.x" residual ahead of any source consuming them. NOTES-only sub-step — no source, no test. Three decisions to record as **G-D15** (or next available NOTES number):

- **Pool-type whitelist enum** — the set of factory-derived pool types eligible for `activateGauge`. Candidates: Balancer V3 `WeightedPool` (Stage E `WeightedPoolFactory`), `StablePool` if deployed, any additional factory-derived types confirmed at G2.0 entry. Exact enum locked against deployed Stage E factory addresses. Fails-closed per G-D6.
- **F-10 caps clause** — whether to retain the numeric caps (15/10/5 → 1%/0.5%/0.1%) from `11_formulas.md` F-10 as anti-concentration controls within the favored cohort, drop them as unnecessary complexity, or replace with a single flat cap. Decision at sub-step entry in Opus; if retained, exact cap values and application logic lock at G-D15.
- **$10K TVL floor encoding** — OQ-G2 is USD-denominated; concrete encoding is svZCHF-denominated 18-decimal (`TVL_FLOOR_SVZCHF`). Candidate concrete value: `10_000e18` (10 000 svZCHF, treating svZCHF ≈ 1 USD for the anti-spam floor gate — rough magnitude, not oracle-precise equivalence). Confirm at sub-step entry against OQ-G2 + OQ-22 framing.

If any decision is still open at G2.0 entry, resolution happens in chat (Opus) before the Cursor prompt fires. Mode dispatch per §13 routes the NOTES write itself to Sonnet.

- **Cursor prompt:** Add **G-D15** (GaugeEligibility tunables lock) to `docs/STAGE_G_NOTES.md` — pool-type whitelist enum + F-10 caps disposition + `TVL_FLOOR_SVZCHF` encoding with rationale + constraints; NOTES-only — no `src/gauge/` edit, no PLAN edit beyond cross-link entry, no test edit.

#### G2.1 — `IGaugeEligibility` interface (`src/gauge/IGaugeEligibility.sol`)

Lands the narrow read surface consumed by `GaugeRegistry` (G3) for pre-activation eligibility checks. Core functions: `evaluateEligibility(address pool) external returns (bool)` — the state-writing gate that `GaugeRegistry.activateGauge` calls, running all eligibility criteria and writing the per-pool latch; `isEligible(address pool) external view returns (bool)` — latched eligibility state, not re-evaluated on read; `cohortOf(address pool) external view returns (bool favored)` — returns `true` if pool is in the top-15% favored cohort at the last epoch snapshot; `snapshotEpoch() external view returns (uint256)` — the epoch index at which the current eligibility latch was computed per T-I5 epoch-snapshot determinism. Pragma `^0.8.26`; license `GPL-3.0-or-later`.

- **Cursor prompt:** Create `src/gauge/IGaugeEligibility.sol` with `evaluateEligibility`, `isEligible`, `cohortOf`, and `snapshotEpoch` function surface; narrow interface for `GaugeRegistry` consumption.

#### G2.2 — `GaugeEligibility.sol` scaffold (`src/gauge/GaugeEligibility.sol`)

Lands storage / imports / constants / custom errors / events per **G-D5** + **G-D6** + **G-D8** + **G-D15** (G2.0 lock). No constructor body, no functions. Pragma `^0.8.26`; license `GPL-3.0-or-later`. Imports: `IGaugeEligibility`, `IVaultClassRegistry`, `ITVLOracle` (Stage F shape reused), `IBasePool` (Balancer V3 — `getNormalizedWeights`), `IVault` (Balancer V3 — `getPoolTokens`; vault address stored as immutable; exact selector confirmed at G2.3 against submodule HEAD), `IERC4626` + `IERC20` from OpenZeppelin. Constants from G2.0 lock: `TVL_FLOOR_SVZCHF`, `FAVORED_COHORT_BPS = 1500`, `SMOOTHING_EPOCHS = 3`. Immutables: `address public vaultClassRegistry`, `address public tvlOracle`, `address public vault`, `address internal _auMM`, `address internal _auMT`. Storage: `mapping(address => bool) public isGaugeEligible; mapping(address => bool) public isFavoredCohort; mapping(address => uint256) public lastSnapshotEpoch; uint256 public currentSnapshotEpoch;`. Events per G-D5 ABI verbatim (`GaugeEfficiencyDropped` / `GaugeEfficiencyRising`). Custom errors: `ZeroAddress`, `ForbiddenToken`, `PoolTypeNotWhitelisted`, `TVLFloorNotMet`, `InsufficientQualityGate`, `EfficiencyDataUnavailable`.

- **Cursor prompt:** Create `src/gauge/GaugeEligibility.sol` with type / state / constants / error / event surface per G-D5 + G-D8 + G-D15; no constructor body, no functions.

#### G2.3 — Constructor + ERC-4626 detection + 52% Quality Gate (`src/gauge/GaugeEligibility.sol`)

Fills the constructor + `_compute52PctNumerator(IERC20[] memory tokens, uint256[] memory weights) internal view returns (uint256)` per **G-D8** + **G-D10**. Constructor: zero-address checks on `_vaultClassRegistry`, `_tvlOracle`, `_vault`, `_auMM`, `_auMT`; store immutables. `_compute52PctNumerator`: iterate `tokens` + `weights` in lock-step; for each pair: (i) T-I3 forbidden-token check first — `if (address(tokens[i]) == _auMM || address(tokens[i]) == _auMT) revert ForbiddenToken(address(tokens[i]));`; (ii) ERC-4626 detection via `try IERC4626(address(tokens[i])).asset() returns (address) { /* 4626-claiming */ } catch { /* plain ERC-20, no numerator contribution */ }` per G-D10; (iii) if 4626-claiming: `IVaultClassRegistry(vaultClassRegistry).isAdmittedClass(address(tokens[i]))` — admitted → `numerator += weights[i]`; not admitted → no contribution; (iv) return `numerator`. Caller fetches `(tokens, weights)` from `IVault(vault).getPoolTokens(pool)` + `IBasePool(pool).getNormalizedWeights()` before calling.

- **Cursor prompt:** Add constructor (forbidden-token immutables + zero-address checks) + `_compute52PctNumerator` internal (G-D10 try/catch ERC-4626, VaultClassRegistry admission lookup, weight accumulation); no TVL / whitelist logic yet.

#### G2.4 — TVL floor + pool-type whitelist + `_checkEligibilityCriteria` (`src/gauge/GaugeEligibility.sol`)

Fills `_checkEligibilityCriteria(address pool) internal view` — the aggregate binary gate run before tournament ranking. Internally fetches `IERC20[] memory tokens` from `IVault(vault).getPoolTokens(pool)` + `uint256[] memory weights` from `IBasePool(pool).getNormalizedWeights()`. Criterion order — cheapest-first per G-D10 note: (i) forbidden-token — inline `_compute52PctNumerator` call covers T-I3 reverts; (ii) pool-type whitelist — derive factory address via Balancer V3 pool-config read (exact selector locked at G2.4 sub-step entry against `lib/balancer-v3-monorepo` HEAD; candidate: `IVault(vault).getPoolFactoryAddress(pool)` or equivalent call chain); compare against G-D15 whitelist set; revert `PoolTypeNotWhitelisted(factory)` if absent; (iii) TVL floor — `uint256 tvl = ITVLOracle(tvlOracle).getTVL(pool)`; revert `TVLFloorNotMet(tvl, TVL_FLOOR_SVZCHF)` if below; (iv) 52% Quality Gate — `uint256 numerator = _compute52PctNumerator(tokens, weights)`; revert `InsufficientQualityGate(numerator)` if `numerator < 0.52e18`.

- **Cursor prompt:** Add `_checkEligibilityCriteria` per OQ-G2 + G-D6 + G-D10 + G-D15; resolve pool-factory-address selector against `lib/balancer-v3-monorepo` HEAD at sub-step entry; criterion order: forbidden-token → pool-type → TVL floor → 52%-gate.

#### G2.5 — F-10 efficiency tournament + cohort assignment + transition events (`src/gauge/GaugeEligibility.sol`)

Fills `computeEpochSnapshot(address[] calldata eligiblePools) external` — the epoch-boundary entry point per **G-D3** + **OQ-G1** + **T-I5** + **G-D5**. Caller restriction locked at G2.5 sub-step entry in Opus (candidate: `onlyGaugeRegistry` to prevent spurious epoch resets). For each pool: compute `efficiency_ratio` per F-10 (`fee_revenue / tvl_sma`, both via `ITVLOracle` per OQ-G1, `SMOOTHING_EPOCHS = 3`, 1e18 fixed-point); revert `EfficiencyDataUnavailable(pool)` if oracle returns zero TVL. Sort descending in memory — no storage write during sort. Compute cutoff: `favored_count = (N * 15 + 99) / 100` (ceiling arithmetic). Apply F-10 caps per G-D15 resolution. For each pool: compare new cohort to previous `isFavoredCohort[pool]`; emit `GaugeEfficiencyDropped` on top-to-bottom crossing (T-T2); emit `GaugeEfficiencyRising` on bottom-to-top crossing (T-T1) — exactly once per pool per epoch per G-D5; event args include `currentSnapshotEpoch + 1`, `tvlSma`, `efficiencyRatio`. Update `isFavoredCohort[pool]` + `lastSnapshotEpoch[pool]`; increment `currentSnapshotEpoch`.

- **Cursor prompt:** Add `computeEpochSnapshot` per G-D3 + OQ-G1 + T-I5 + G-D5; descending in-memory sort by `efficiency_ratio`, ceiling 15% cutoff, transition-event emission exactly once per crossing; apply F-10 caps per G-D15 resolution; resolve caller-restriction decision at G2.5 sub-step entry in chat (Opus).

#### G2.6 — Public eligibility surface (`src/gauge/GaugeEligibility.sol`)

Fills the `IGaugeEligibility` interface implementations: `evaluateEligibility(address pool) external returns (bool)` — calls `_checkEligibilityCriteria(pool)` (reverts on any criteria failure); writes `isGaugeEligible[pool] = true` and `lastSnapshotEpoch[pool] = currentSnapshotEpoch`; returns `true`. `isEligible(address pool) external view returns (bool)` — returns `isGaugeEligible[pool]` latched state. `cohortOf(address pool) external view returns (bool favored)` — returns `isFavoredCohort[pool]`. `snapshotEpoch() external view returns (uint256)` — returns `currentSnapshotEpoch`. T-I5 epoch-snapshot determinism: two reads at the same block return identical latched state — eligibility is written only by `evaluateEligibility` (per-pool first-pass write) and `computeEpochSnapshot` (epoch-boundary write), never on external view reads.

- **Cursor prompt:** Add `evaluateEligibility` + `isEligible` + `cohortOf` + `snapshotEpoch` per IGaugeEligibility interface; `evaluateEligibility` writes latch via `_checkEligibilityCriteria`; view functions return latched state only.

#### G2.7 — `GaugeEligibility` unit tests (`test/unit/GaugeEligibility.t.sol`)

Lands unit invariants per the test matrix in `STAGE_G_NOTES.md`: 52% numerator across mixed token sets (admitted 4626 + non-admitted 4626 + plain ERC-20 combinations); ERC-4626 detection — non-reverting `asset()` triggers class-lookup path, reverting gives plain ERC-20 path; T-I3 forbidden-token block (AuMM / AuMT in any pool token position reverts `ForbiddenToken`); T-I4 fast-track selector absent (`GaugeEligibility` bytecode has no Sandbox fast-track function — ABI-level check); G-D6 pool-type whitelist fails-closed (unrecognized factory reverts `PoolTypeNotWhitelisted`); OQ-G2 TVL-floor gate (below-floor reverts `TVLFloorNotMet`; borderline-floor passes); T-T1 — `GaugeEfficiencyRising` emitted exactly once on bottom-to-top cohort crossing; T-T2 — `GaugeEfficiencyDropped` emitted exactly once on top-to-bottom crossing; T-T3 tie-break — equal `efficiency_ratio` produces stable sort by deterministic tiebreak (address ascending); T-I5 epoch-snapshot determinism — `isEligible` reads at the same block return identical latched state. Mocks: `MockVaultClassRegistry` (controllable `isAdmittedClass`), `MockTVLOracle` (per-pool TVL + fee-revenue returns), `MockBasePool` (controllable `getNormalizedWeights` + factory-address). Pure unit; no mainnet fork.

- **Cursor prompt:** Create `test/unit/GaugeEligibility.t.sol` covering T-I3/T-I4/T-I5, T-T1/T-T2/T-T3 invariants against mock fixtures; pure unit (no fork).

### G3 — GaugeRegistry + three activation paths

G3 ships `GaugeRegistry.sol` + extends `IGaugeRegistry.sol` (from Stage F `src/ccb/interfaces/`) — the registry and state machine for all three gauge activation paths. Path 1: permissionless `activateGauge` pulls the OQ-G3 anti-spam fee (100 svZCHF, ERC-20 pull) and routes it to der Bodensee via the G-D12 SwapAndDeposit helper before running `GaugeEligibility`; fee is non-refundable on success or failed check per OQ-G3, so eligibility failure does not revert but emits `GaugeActivationFailed` and returns. Path 2: governance-only `registerGaugeFromComposition` registers a composition-replacement pool without eligibility check. Path 3: governance-only `seedFoundingPool` seeds Miliarium genesis pools at deploy with eligibility bypassed per **STAGE_G_PRECHECK_AUTO_GAUGE** C-4. No 90-day boost on any path per **G-D13**.

Sub-row layout: G3.0 locks three design decisions in NOTES (G-D16); G3.1 extends the Stage F `IGaugeRegistry` interface; G3.2–G3.5 fill the registry implementation; G3.6 delivers unit tests.

#### G3.0 — GaugeRegistry design decisions (`docs/STAGE_G_NOTES.md`; NOTES-only)

Resolves three G3-scoped design decisions recorded as **G-D16** (or next available NOTES number). NOTES-only sub-step — no source, no test.

- **IGaugeRegistry extend-vs-replace (G-D16a)** — Stage F's `CCBMultiplier.sol` imports `src/ccb/interfaces/IGaugeRegistry.sol` with a single `isGaugeApproved(address pool) returns (bool)` signature per F-D17. Option A: create a new `IGaugeRegistryV2` in `src/gauge/`; Stage F bytecode unchanged but interface fragments. Option B: extend the existing `src/ccb/interfaces/IGaugeRegistry.sol` in-place with Stage G functions and enums; Stage F recompiles cleanly since `CCBMultiplier` only calls `isGaugeApproved`. Decision at G3.0 entry — default Option B (extend same file) to avoid interface fragmentation; confirm at Opus entry.
- **`seedFoundingPool` parameter shape (G-D16b)** — Miliarium genesis pools are known at deploy; Vault already holds token/weight metadata. Options: full basket (pool + token addresses + weights — redundant), scalar `address pool` per-call, or batch `address[]`. Decision at G3.0 entry — scalar `address pool` for `seedFoundingPool` plus a batch `seedFoundingPools(address[] calldata)` variant for seeding all 28 Miliarium pools in one governance transaction; confirm at Opus entry.
- **`activateGauge` fee-fail semantics (G-D16c)** — OQ-G3 specifies the anti-spam fee is "non-refundable on success or on any failed criteria check." EVM revert unwinds `safeTransferFrom`, returning the fee. To honor OQ-G3: `activateGauge` must NOT revert on eligibility failure — pull fee first (revert only on transfer failure, which is a precondition, not an eligibility check), route fee to Bodensee via SwapAndDeposit helper using the G-D12 caller-pre-push pattern, then run `gaugeEligibility.evaluateEligibility` in a `try/catch`; on catch or false return emit `GaugeActivationFailed(pool, reason)` and `return` without reverting; on success activate. Confirm at Opus entry.

- **Cursor prompt:** Add **G-D16** (GaugeRegistry design decisions: IGaugeRegistry extend-vs-replace + seedFoundingPool param shape + activateGauge fee-fail semantics per OQ-G3) to `docs/STAGE_G_NOTES.md`; NOTES-only — no `src/gauge/` edit, no PLAN edit beyond a cross-link entry, no test edit.

#### G3.1 — `IGaugeRegistry` interface (extend `src/ccb/interfaces/IGaugeRegistry.sol`)

Extends the existing Stage F interface per **G-D16a**. Retains: `isGaugeApproved(address pool) external view returns (bool)` (Stage F compat surface; implementation returns `_gaugeStatus[pool] == GaugeStatus.Active`). Adds enums: `enum GaugeStatus { None, Active, Revoked }` and `enum GaugeActivationPath { Permissionless, Composition, Founding }`. Adds functions: `activateGauge(address pool) external` — permissionless, ERC-20 fee pull (not `payable`); `registerGaugeFromComposition(address pool) external` — governance-only; `seedFoundingPool(address pool) external` — governance-only; `seedFoundingPools(address[] calldata pools) external` — governance-only batch; `revokeGauge(address pool) external` — governance-only; `setGovernanceContract(address newGovernance) external` — governance-only handoff for Stage K; `gaugeStatus(address pool) external view returns (GaugeStatus)`. Adds events: `GaugeActivated(address indexed pool, GaugeActivationPath indexed path)`, `GaugeActivationFailed(address indexed pool, bytes failureReason)`, `GaugeRevoked(address indexed pool)`, `AntiSpamFeeRouted(address indexed payer, uint256 amount)`, `GovernanceTransferred(address indexed oldGovernance, address indexed newGovernance)`. Adds custom errors: `NotGovernance(address caller)`, `AlreadyGauged(address pool)`, `AlreadyRevoked(address pool)`, `NotGauged(address pool)`. Pragma `^0.8.26`; license `GPL-3.0-or-later`.

- **Cursor prompt:** Extend `src/ccb/interfaces/IGaugeRegistry.sol` with `GaugeStatus` + `GaugeActivationPath` enums, activation functions (`activateGauge`, `registerGaugeFromComposition`, `seedFoundingPool`, `seedFoundingPools`, `revokeGauge`, `setGovernanceContract`), view `gaugeStatus`, events (`GaugeActivated`, `GaugeActivationFailed`, `GaugeRevoked`, `AntiSpamFeeRouted`, `GovernanceTransferred`), and errors; retain `isGaugeApproved` as Stage F compat surface.

#### G3.2 — `GaugeRegistry.sol` scaffold (`src/gauge/GaugeRegistry.sol`)

Lands storage / immutables / constants / imports / modifier surface per **G-D16**. No constructor body, no functions. Pragma `^0.8.26`; license `GPL-3.0-or-later`. Imports: `IGaugeRegistry` (from `src/ccb/interfaces/IGaugeRegistry.sol`), `IGaugeEligibility`, `ISwapAndDeposit` (G-D12 helper interface; reused from `src/gauge/` per G1 sub-steps), `IERC20` + `SafeERC20` from OpenZeppelin. Immutables: `IERC20 public immutable svZCHF` (anti-spam fee token), `ISwapAndDeposit public immutable swapAndDeposit` (Bodensee fee router, G-D12). Constants: `uint256 public constant ANTI_SPAM_FEE = 100e18` (100 svZCHF at 18 decimals per OQ-G3 / STAGE_G_PRECHECK_AUTO_GAUGE §1). State: `mapping(address => GaugeStatus) private _gaugeStatus`, `address public governanceContract` (NOT immutable — updated via `setGovernanceContract` at Stage K handoff), `IGaugeEligibility public gaugeEligibility`. Modifier: `modifier onlyGovernance() { if (msg.sender != governanceContract) revert NotGovernance(msg.sender); _; }`.

- **Cursor prompt:** Create `src/gauge/GaugeRegistry.sol` with type / state / constants / imports / `onlyGovernance` modifier surface per G-D16; no constructor body, no functions.

#### G3.3 — Constructor + `setGovernanceContract` + `activateGauge` (`src/gauge/GaugeRegistry.sol`)

Constructor: `constructor(address governance, address eligibility_, address swapAndDeposit_, address svZCHF_)` — zero-address checks on all four arguments; store `governanceContract = governance`, `gaugeEligibility = IGaugeEligibility(eligibility_)`, `swapAndDeposit = ISwapAndDeposit(swapAndDeposit_)`, `svZCHF = IERC20(svZCHF_)`.

`setGovernanceContract(address newGovernance) external onlyGovernance`: zero-address check; `address old = governanceContract; governanceContract = newGovernance; emit GovernanceTransferred(old, newGovernance)`. Stage K handoff path.

`activateGauge(address pool) external` — non-reverting on eligibility failure per **G-D16c** + **OQ-G3**: (1) check `_gaugeStatus[pool] == GaugeStatus.None` — revert `AlreadyGauged(pool)` if Active, revert `AlreadyRevoked(pool)` if Revoked; (2) `IERC20(svZCHF).safeTransferFrom(msg.sender, address(this), ANTI_SPAM_FEE)` — reverts on transfer failure (precondition, acceptable revert); (3) `IERC20(svZCHF).safeTransfer(address(swapAndDeposit), ANTI_SPAM_FEE)` per G-D12 caller-pre-push pattern; (4) `swapAndDeposit.swapAndDeposit(svZCHF, ANTI_SPAM_FEE)` — routes fee to Bodensee; (5) `emit AntiSpamFeeRouted(msg.sender, ANTI_SPAM_FEE)`; (6) eligibility via try-block: `try gaugeEligibility.evaluateEligibility(pool) returns (bool ok) { if (!ok) { emit GaugeActivationFailed(pool, ""); return; } } catch (bytes memory reason) { emit GaugeActivationFailed(pool, reason); return; }` — `evaluateEligibility` reverts on failure per G2.6, so the catch branch is the primary failure path; the `!ok` branch is defensive for future evolution; (7) (reached only if eligible): `_gaugeStatus[pool] = GaugeStatus.Active; emit GaugeActivated(pool, GaugeActivationPath.Permissionless)`.

- **Cursor prompt:** Add constructor (four args, zero-address checks, store governance + eligibility + swapAndDeposit + svZCHF) + `setGovernanceContract` (onlyGovernance, `GovernanceTransferred` emit) + `activateGauge` (fee pull → safeTransfer push → swapAndDeposit call → AntiSpamFeeRouted emit → try/catch eligibility → non-reverting failure path → GaugeActivated emit) per G-D16c + OQ-G3.

#### G3.4 — `registerGaugeFromComposition` + `revokeGauge` + view functions (`src/gauge/GaugeRegistry.sol`)

`registerGaugeFromComposition(address pool) external onlyGovernance`: revert `AlreadyGauged(pool)` if Active; revert `AlreadyRevoked(pool)` if Revoked; no eligibility check (composition-governance path already vetted the replacement pool; Stage O wire-up hooks this); no anti-spam fee; G-D13 no boost — gauge is Active from activation block; `_gaugeStatus[pool] = GaugeStatus.Active; emit GaugeActivated(pool, GaugeActivationPath.Composition)`.

`revokeGauge(address pool) external onlyGovernance`: revert `NotGauged(pool)` if not Active; `_gaugeStatus[pool] = GaugeStatus.Revoked; emit GaugeRevoked(pool)`. Grace-period machinery (graduated emission reduction post-revocation) is Stage H's concern; revocation at Stage G is a binary state flip only.

`isGaugeApproved(address pool) external view returns (bool)` (Stage F compat per G-D16a): `return _gaugeStatus[pool] == GaugeStatus.Active`.

`gaugeStatus(address pool) external view returns (GaugeStatus)`: `return _gaugeStatus[pool]`.

- **Cursor prompt:** Add `registerGaugeFromComposition` (onlyGovernance, no eligibility check, G-D13 no-boost, Composition path emit) + `revokeGauge` (onlyGovernance, Active-check, Revoked state, GaugeRevoked emit) + `isGaugeApproved` compat view + `gaugeStatus` view per G-D7 + G-D13 + G-D16a.

#### G3.5 — `seedFoundingPool` + `seedFoundingPools` (`src/gauge/GaugeRegistry.sol`)

`seedFoundingPool(address pool) external onlyGovernance`: revert `AlreadyGauged(pool)` if already Active (double-seed is a governance error); revert `AlreadyRevoked(pool)` if Revoked (re-seeding a revoked founding pool is a governance amendment out of scope for Stage G — silent overwrite must not occur); no eligibility check (Miliarium pools bypassed per STAGE_G_PRECHECK_AUTO_GAUGE C-4); no anti-spam fee (governance path); G-D13 no boost — Active from seed block; `_gaugeStatus[pool] = GaugeStatus.Active; emit GaugeActivated(pool, GaugeActivationPath.Founding)`.

`seedFoundingPools(address[] calldata pools) external onlyGovernance`: iterates `pools`, inlining the `seedFoundingPool` logic for each (not an external call to `seedFoundingPool` — avoids reentrancy surface on the governance path); reverts atomically on any individual pool error; enables seeding all 28 Miliarium genesis pools in one governance transaction.

- **Cursor prompt:** Add `seedFoundingPool` (onlyGovernance, no eligibility, no fee, Founding path emit, AlreadyRevoked guard) + `seedFoundingPools` batch variant (inline loop, atomic revert, 28-pool genesis) per STAGE_G_PRECHECK_AUTO_GAUGE C-4 + G-D13 + G-D16b.

#### G3.6 — `GaugeRegistry` unit tests (`test/unit/GaugeRegistry.t.sol`)

Lands unit invariants per the test matrix in `STAGE_G_NOTES.md` **T-R1** + governance-access gates. Permissionless path (eligibility pass): `MockGaugeEligibility.evaluateEligibility` returns `true`; `MockSvZCHF.safeTransferFrom` + `safeTransfer` recorded; `MockSwapAndDeposit.swapAndDeposit` recorded; assert `GaugeActivated(pool, Permissionless)` emitted, `isGaugeApproved(pool)` == `true`, `gaugeStatus(pool)` == `Active`. Permissionless path (evaluateEligibility reverts): mock eligibility reverts with encoded reason; fee pulled and routed before check (verify `safeTransferFrom` + `safeTransfer` + `swapAndDeposit` all recorded); assert `GaugeActivationFailed(pool, reason)` emitted, NO tx revert, `gaugeStatus(pool)` == `None`. Permissionless path (evaluateEligibility returns false): mock eligibility returns `false`; assert `GaugeActivationFailed(pool, "")` emitted, `gaugeStatus(pool)` == `None`. Fee precondition: mock svZCHF with insufficient allowance; `safeTransferFrom` reverts; assert NO `AntiSpamFeeRouted` event, pool status unchanged. Double-activation: second `activateGauge` on Active pool reverts `AlreadyGauged`; on Revoked pool reverts `AlreadyRevoked`. Composition path: non-governance call reverts `NotGovernance`; governance call activates without touching eligibility mock; `GaugeActivated(pool, Composition)` emitted. Founding path: `seedFoundingPool` governance-only gate; no fee, no eligibility; `GaugeActivated(pool, Founding)`; `seedFoundingPools` activates 3-address test vector atomically (covers 28-pool semantics). Revocation: `revokeGauge` governance-only; Active → Revoked; `GaugeRevoked` emitted; `isGaugeApproved(pool)` == `false`; subsequent `activateGauge` reverts `AlreadyRevoked`. `setGovernanceContract`: old governance transfers; `GovernanceTransferred` emitted; new governance passes `onlyGovernance`; old governance reverts `NotGovernance`. Stage F compat: `isGaugeApproved(pool)` == `(gaugeStatus(pool) == Active)` for all three `GaugeStatus` values. Mock fixtures: `MockGaugeEligibility` (controllable per-pool return + revert injection), `MockSwapAndDeposit` (captures call args), `MockERC20` (controllable allowance/balance for svZCHF). Pure unit; no mainnet fork.

- **Cursor prompt:** Create `test/unit/GaugeRegistry.t.sol` covering T-R1: three activation paths, fee-fail non-revert semantics, fee precondition revert, governance gates, revocation, `setGovernanceContract` handoff, Stage F `isGaugeApproved` compat; pure unit (no fork).

### G4 — Integration fork test

### G5 — Docs

### G9 — Close

---

## Completion Log

| Sub-step | Commit | Date | Summary |
|----------|--------|------|---------|