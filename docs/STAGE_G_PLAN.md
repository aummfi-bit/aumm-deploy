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

### G1 — VaultClassRegistry + tunables lock

### G2 — GaugeEligibility + F-10 ranking

### G3 — GaugeRegistry + three activation paths

### G4 — Integration fork test

### G5 — Docs

### G9 — Close

---

## Completion Log

| Sub-step | Commit | Date | Summary |
|----------|--------|------|---------|