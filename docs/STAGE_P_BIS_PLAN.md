# Stage P-bis — Plan & Sub-Step Roadmap

> **Status:** Stage P-bis OPEN — entry freeze committed (`f84fa36` PB1.1 + `986a223` PB1.1a base amendment; PB-D1—PB-D5 locked, PB-D1/PB-D2 + the PB1.1a base user-adjudicated); CLAUDE.md §11 repointed (`db84611`); PB1.2 (this plan) in flight. Three sequenced workstreams per PB-D4: **(A)** open-issue close-out → **(B)** Sepolia deployment → **(C)** `aumm-app` frontend. Companion to STAGE_P_BIS_NOTES.md (the design-decision log); this file is the sub-step sequence + the Completion Log.
>
> **Last update:** 2026-07-11 — PB1 entry sequence complete through the §11 repoint; PB1.2 lands with this file. Branch `stage-p-bis` (cut from `main` @ f72b309 = the CM-series tip, per PB-D3-as-amended). Regression baseline carried from Stage P: 877 unit + 136 fork green. Next: PB2.1 (OQ-20/OQ-21 adjudication).
>
> **Mode:** Opus high entry (§13 stage table) — adjudications, wiring design, deploy-script work, and every non-trivial save audit are Opus beats; drops to Sonnet for read-back verdicts, commit drafts, Completion-Log housekeeping, and deploy-script scaffolding transcription.
>
> **Audience:** Sagix + any future Claude session resuming Stage P-bis. NOTES holds rationale; STAGES_OVERVIEW § "Stage P-bis" holds the canonical workstream roster; this file is the execution spine.

---
## Stage scope

Stage P-bis exists so the Stage-Q external audit receives a frozen, self-audited candidate running live on a public testnet with the `aumm-app` frontend connected — the audit becomes a verification event, not a discovery event (NOTES Framing). Everything pre-audit lands here: the live CLAUDE.md §11 carry-forwards, the ex-Stage-Q pulled-forward items (the P-D9 hevm/Act bundle, the F-13/F-15 dispositions), the Sepolia go-live (PB-D1), and the frontend gate. Workstream-A exit rule: every roster item exits **Fixed, Built, or Explicitly-descoped-with-rationale** — each descope its own PB-D entry, nothing silently carried past the tag (PB-D4). Adjudications precede builds (PB-D5, the §12 ambiguity-gate): PB2.1—PB2.5 lock PB-D entries first; build sub-steps materialize from those outcomes as lettered insertions (PB2.1b, PB2.3b, …).

### Surfaces produced at Stage P-bis
| Artifact | Workstream | Sub-step | Purpose |
| --- | --- | --- | --- |
| PB-D adjudication locks in `STAGE_P_BIS_NOTES.md` | A | PB2.1—PB2.5 | build-vs-descope dispositions (OQ-20/21, OQ-22, pools, F-13, F-15) |
| adjudication-dependent code/test surfaces | A | PB2.*b | drafted per outcome — not pre-committed here |
| governance-handoff rotation script + fork witness | A | PB2.6 | the PB-D2 wiring step (re-settable slice rotations; P-D36-style witness leg) |
| PB-D13 descope lock + RB-006 register row (no code surface) | A | PB2.7 | D36 permanent fix DESCOPED per PB-D13; `--threads 1` promoted to permanent canonical posture |
| direct `ReentrancyGuard.selector` test (roll-plus-accrue mock reentry per PB-D14) | A | PB2.8 | robustness backport (RB-007 created Closed at the landing hash) |
| P-D42 coverage-tooling re-eval attestation (PB-D15 re-affirm) | A | PB2.9 | re-probe reproduces the Yul stack-too-deep on the byte-identical toolchain; execution-evidence waiver re-affirmed |
| WK.18 thin-venue populated-roster fork sim (PB-D16 BUILD) | A | PB2.11 | F-04 surface Fixed (EMA gate); populated-roster positive-control + economics quantifier |
| hevm + Act formal-methods bundle + specs (PB-D17) | A | PB2.12 | P-D9, LAST in A; hevm 0.58.0 local runs + .act specs-as-artifact (proving firm-side); formal/ + RESULTS.md ship in the audit hand-off |
| `CCBMultiplier` all-gauged delta_global rebuild + zero-TVL disposition evidence + CCB formal re-attest (PB-D18) | A | PB2.13 | OQ-23 reopening close-out; the new LAST in A per PB-D18, superseding the PB2.12 row's LAST-in-A framing |
| `test-stubs/` testnet ERC-20s (+ registry) | B | PB3.2 | P8 roster (tier set per the Stage-P Builds list) |
| canonical Router deploy + `setTrustedRouter` binds | B | PB3.3 | P-D26 close-out; seats the F-09 allowlist |
| production `run()` path in `DeployStageP.s.sol` | B | PB3.4 | un-defer `ProductionOrchestrationDeferredToPbis` |
| Sepolia broadcast + explorer verification | B | PB3.5 | the live go-live (user-run, §8b) |
| F-14 ops + fee-custody process record | B | PB3.6 | ixAetheron off-chain-conversion rails (P-D12) |
| deployed-addresses artifact | B | PB3.7 | the C-integration contract the frontend consumes |
| frontend-reads-Sepolia completion evidence | C | PB4.2 | the PB-D4 workstream-C gate record |
| close set (`STAGES_OVERVIEW.md` row, Completion Log, §11, tag) | — | PB5 | PENDING_PBIS two-commit close (PB-D3) |

### Surfaces NOT produced at Stage P-bis
- No mainnet broadcast of any kind (§8c; Stage R).
- No external-audit engagement — Stage Q owns firm selection (OQ-17) and the audit itself.
- No `aumm-app` code in this repo — external repo per OQ-18; this repo tracks the milestone + the artifact (PB-D4).
- No §xxix constitutional amendment — the multisig gap closes via the wiring step (PB-D2).
- No Vault/submodule edits, as always (§8c) — the rotation script and Router work are CALL-layer only.
- Whatever PB2.1—PB2.5 explicitly descope, each recorded as its own PB-D entry.

---
## Decisions

Mirror of `STAGE_P_BIS_NOTES.md` (PB-D1—PB-D5 LOCKED at the entry freeze; this table grows as the PB2 adjudications lock further PB-D entries). The NOTES file holds the rationale; this table is the roadmap index.

| # | Decision (one-line) | Sub-step |
| --- | --- | --- |
| PB-D1 | Sepolia is the live-broadcast target (12s-block parity); verify pass opens workstream B | PB3.1 |
| PB-D2 | §xxix dissolution via the wiring step, no amendment (re-settable rotations + witness; `pauseManager` inert) | PB2.6 |
| PB-D3 | Branch + close mechanics mirror P-D4; base f72b309 (PB1.1a amendment); PENDING_PBIS close | PB5 |
| PB-D4 | Three sequenced workstreams A → B → C; per-item exit Fixed/Built/Descoped; hevm/Act + WK.18 LAST in A | roadmap |
| PB-D5 | Workstream-A adjudication queue runs FIRST, before any build | PB2.1—PB2.5 |
| PB-D6 | OQ-20/OQ-21 BUILD: `routeYieldFeeToHook(pool, token, amount)` + per-pool `BLOCKS_PER_EPOCH` throttle on the controller | PB2.1 |
| PB-D7 | OQ-22 BUILD: 2-hop TVLOracle valuation fallback (governance-append-only hop roster, ZCHF + USDS seeded; direct venues win, no transitive hops) | PB2.2 |
| PB-D8 | Pool restoration SPLIT: ixCasper waEthwstETH restored via Aureum `CompositeRateProvider` (QG 68% → 84%); 04/07 descoped to the Stage-O challenge path; OQ-I10 closed | PB2.3 |
| PB-D9 | F-13 SPLIT: routeYieldFee path Fixed via caller-supplied bounds; onAfterSwap Accepted-risk S5 Low (sandwich-sim evidence); dormant entries threaded + attested | PB2.4 |
| PB-D10 | F-15 ACCEPT: poke-invariant truth ceiling bounds the live veto denominator; both snapshot fixes rejected as regression-bearing | PB2.5 |
| PB-D11 | PB-D2 amendment: `VaultClassRegistry` one-shot-sealed, reroutes to the PB3.4 production bind; PB2.6 narrows to the five-rotation script | PB2.6 |
| PB-D12 | PB-D2 second amendment: rotations pinned to dissolution-time; the v1 freeze witnessed as truth; ossify-vs-extend one consolidated Stage-Q / pre-R input | PB2.6 |
| PB-D13 | PB2.7 DESCOPED: `--threads 1` permanent canonical fork-invocation posture; the D36 branch-(b) parameterization records as RB-006 | PB2.7 |
| PB-D14 | PB2.8 mechanism amendment: `vm.transientStore` absent at pinned forge-std; direct guard witness via roll-plus-accrue mock reentry; channel-only scope | PB2.8 |
| PB-D15 | PB2.9 coverage re-eval: re-probe reproduces the P-D42 Yul stack-too-deep on the byte-identical toolchain (forge `f83bad91` / solc 0.8.26); execution-evidence waiver re-affirmed, re-eval rides to post-audit / newer-toolchain | PB2.9 |
| PB-D16 | PB2.11 WK.18 BUILD: F-04's atomic surface Fixed (60-day EMA gate), so the thin-venue sim is a populated-roster positive-control + sustained-pump economics quantifier, not a bug hunt | PB2.11 |
| PB-D17 | PB2.12 BUILD: hevm 0.58.0 (argotorg, native arm64 + resident z3 4.15.4) runs locally; Act v0.2.0 source-only → .act specs as audit-handoff artifacts, proving attested firm-side; top-level formal/; exit BUILT | PB2.12 |
| PB-D18 | OQ-23 reopened: delta_global re-keys to the all-Active-gauge aggregate (P-D22 shape restored — ctor 2→3-arg + one-shot `setGaugeRegistry` seal); delta_basket withdrawn (damping inherent in F-5/F-6 proportionality, zero spec edits); zero-TVL disposition attached | PB2.13 |
| PB-D19 | GENESIS_BLOCK = broadcast block + 100_800 (one epoch) decouples the emission clock from deploy time; zero code change (one env value — no clamp, cross-contract genesis assertion, no deploy-time accrual); PB3.4 rehearsal runs the future-offset; two optional pre-genesis pins | PB3.4-pre |
| PB-D20 | PB3.2 stub architecture: base-level envOr override resolver in the miliarium base (STUB_ + vm.toString(literal) keys, passthrough default, non-zero-RP fail-fast); Tier D = emitted env-map, no on-chain registry; real ERC4626RateProviders over 18/18 stub 4626s (F-11-inclusive deviation recorded); two templates + named Tier-A instances; permissionless mint | PB3.2 |

---
## Sub-step roadmap (PB1—PB5)

> Execution spine. PB2 opens with the five PB-D5 adjudications — chat beats, each locking its own PB-D entry in NOTES (landed as one §8e.1 NOTES edit per lock), no build before its lock; build sub-steps from adjudication outcomes insert as lettered steps (PB2.1b, …). PB2.11/PB2.12 run LAST in A so their results bind the near-frozen tree (PB-D4). PB3 opens with the PB-D1 environment verify pass; the broadcast (PB3.5) is user-run per §8b. Every numbered sub-step is one §8e.1 per §8e unless marked chat-only, user-run, or user-side.

### PB1 — Stage entry: freeze + plan
- **PB1.1** — `docs/STAGE_P_BIS_NOTES.md` entry freeze (PB-D1—PB-D5). ✅ `f84fa36`.
- **PB1.1a** — PB-D3 base amendment b5f4b8b → f72b309 (user-adjudicated). ✅ `986a223`; CLAUDE.md §11 repointed `db84611`.
- **PB1.2** — `docs/STAGE_P_BIS_PLAN.md` — this file.
- Checkpoint: freeze + plan committed on `stage-p-bis`; §11 names the next sub-step.

### PB2 — Workstream A: open-issue close-out
- **PB2.1** — adjudicate OQ-20 / OQ-21 (controller-initiated `routeYieldFee` + `BLOCKS_PER_EPOCH` cadence throttle, E-D10): build vs descope; locks as its own PB-D entry, build inserts as PB2.1b+.
- **PB2.2** — adjudicate OQ-22 (2-hop TVLOracle valuation fallback through ZCHF / sUSDS; the pre-freeze "fee-routing" label was wording drift, corrected at PB-D7): build vs descope; own PB-D lock.
- **PB2.3** — adjudicate pool restoration: 04 ixViatica / 07 ixCambio (E-D17 literals bar) + the ixCasper waEthwstETH 16% leg (Aureum `CompositeRateProvider`) + the OQ-I10 recorder-binding remainder — restore vs descope-to-the-composition-challenge-path (exists since Stage O); own PB-D lock.
- **PB2.4** — adjudicate F-13 (S5 Low, unbounded internal-leg slippage): rate-derived `limitRaw` / `minBptAmountOut` bound vs accept-with-quantifying-sandwich-sim; own PB-D lock.
- **PB2.5** — adjudicate F-15 (S9 Low, `VaultClassRegistry` veto live-denominator): F-06-style snapshot propagation vs accept; own PB-D lock.
- **PB2.6** — the PB-D2 wiring build per the PB-D11 + PB-D12 amendments: the DISSOLUTION-TIME governance-handoff rotation script (standalone ops artifact, post-OQ-10 — the five re-settable rotations: `EmissionDistributor` / `BodenseeBootstrapChannel` / `TVLOracle` / `EfficiencyOracle` `setGovernanceContract` + `SwapAndDepositToBodensee.setDonateAuthorizer`; `VaultClassRegistry` is one-shot-sealed and reroutes to the PB3.4 production bind per PB-D11) + a P-D36-style fork-test witness on the orchestrator-deployed stack asserting the rotations land AND the stranded family reverts under `AureumGovernance` v1 (the PB-D12 freeze-witness) + the `pauseManager` inert-pointer attestation; includes the one-line `STAGES_OVERVIEW.md` roster-wording reconciliation with PB-D2 (`pauseManager` listed among rotations pre-freeze).
- **PB2.7** — DESCOPED per PB-D13 (user-adjudicated 2026-07-14): the one-file namespacing scope is stale by an order of magnitude (224 `vm.setEnv` sites across 16 fork files; 48 test contracts; six writer files run multiple sibling contracts over shared setEnv fixtures, so the race lives inside single-file H-D40 runs too), a real fix re-opens the P10-validated deploy plumbing (all 16 `Deploy*.s.sol` read fixed literal env keys inside `deploy`), and the "regression proves parallel-safe" exit gate is unevidenceable on the Ankr free-tier posture (D35 hang pattern). `--threads 1` is promoted from F-D11 workaround to permanent canonical fork-invocation posture; the D36 branch-(b) parameterization records as RB-006. Build roster: PB2.7a the PB-D13 lock (NOTES + this line + the L22 tracker row), PB2.7b the RB-006 row + hardening-class bullet, PB2.7c the `STAGES_OVERVIEW.md` bullet close, PB2.7d the Completion Log rows + the Decisions-table back-fill (PB-D6 through PB-D13), PB2.7e the CLAUDE.md §11 rewrite.
- **PB2.8** — direct `ReentrancyGuard.selector` test on `BodenseeBootstrapChannel.distribute()` via roll-plus-accrue mock reentry per PB-D14 (`vm.transientStore` absent from pinned forge-std v1.15.0; the Stage-G sibling guard already directly witnessed; H3.7e's bubble-up test stays as the stale-accrual pin). Build roster: PB2.8a this lock (NOTES + this line + the L23 tracker row + the Decisions row), PB2.8b the one-file test build, PB2.8c the RB-007 row (Closed at the b hash), PB2.8d the Completion Log rows + the CLAUDE.md §11 rewrite.
- **PB2.9** — P-D42 coverage-tooling re-eval RE-AFFIRMED per PB-D15 (user-adjudicated 2026-07-14): the confirmatory re-probe (`forge coverage --ir-minimum --no-match-path "test/fork/**"`, 2026-07-14) reproduces the P-D42 Yul stack-too-deep byte-identically on the byte-identical toolchain (forge `f83bad91` / solc 0.8.26; tree grown 316 → 319 coverage-compile files); the execution-evidence waiver re-affirms (908 Part-A unit + the PB2.x suites), coverage re-eval rides to the post-audit / newer-toolchain gate with the hevm / Act bundle. Build roster: PB2.9a this lock (NOTES + this line + the L24 tracker row + the Decisions row), PB2.9b the `STAGES_OVERVIEW.md` L386 P-D42-clause close, PB2.9c the Completion Log rows + the CLAUDE.md §11 rewrite.
- **PB2.10** — aumm-site spec edits (user-side, runs in parallel): §viii/§ix per OQ-20/21 + the I-reframe, §xxi sandbox row, F-2 Incendiary amendments, FINDINGS corrections, + the PB-D8 (iv) items — `03_ixCasper.md` Fluid-vs-"Flux Finance" mislabel (fWSTETH / fWETH are Fluid per the `07a` rows; the code always bound the Fluid addresses), `04_ixViatica.md` "Flux Finance BRZ vault" wording, `07a_tokens.md` slot-03 waEthwstETH row (M-D11 "RP unresolvable" → the PB-D8 Aureum-composite restoration). Gate: the spec matches the code before PB5.
- **PB2.11** — WK.18 thin-venue populated-roster fork sim BUILT per PB-D16 (user-adjudicated 2026-07-14): F-04's spot-tvl atomic surface is Fixed (the 60-day EMA maturity + freshness gate on `VotingWeight._positionPower`), so the sim is a populated-roster positive-control + economics quantifier — NOT a bug hunt — closing the R1-blocked WK.18 could-not-assess with fork-grade evidence; three faces: atomic pump moves `governanceWeight` ≈ 0 (gate holds), cross-venue mean dilutes 1/N, one sustained-pump scenario fee-negative. Build roster: PB2.11a this lock (NOTES + this line + the L25 tracker row + the Decisions row), PB2.11b the `test/fork/` sim build, PB2.11c the whitehat-ledger WK.18 closure + Completion Log + CLAUDE.md §11 rewrite.
- **PB2.12** — hevm + Act formal-methods bundle BUILT per PB-D17 (user-adjudicated 2026-07-15): hevm `release/0.58.0` (argotorg — the repos moved off ethereum/*; native `hevm-arm64-macos` asset + the resident z3 4.15.4) installs at the §8b beat (user-run) and runs locally against the four Aureum-owned surfaces (fee-routing hook, CCB/EMA engine, emission accrual, authorizer window); Act `v0.2.0` is source-only, so the `.act` specs are authored as audit-handoff artifacts with machine-checking attested firm-side (`STAGES_OVERVIEW.md` L411). Deliverable: top-level `formal/` (act/ + hevm/ + RESULTS.md, the property → status map). Build roster: PB2.12a this lock (NOTES + this line + the L26 tracker row + the Decisions row), PB2.12b the §8b hevm install (user-run), PB2.12c—f the per-surface spec + symbolic-run sub-steps (hook → CCB/EMA → emission accrual → authorizer window; property roster pinned at each pre-flight), PB2.12g formal/RESULTS.md + Completion Log + the CLAUDE.md §11 workstream-A close (LAST in A).
- **PB2.13** — the OQ-23 reopening BUILT per PB-D18 (user-adjudicated 2026-07-16; the new LAST in A, superseding the PB2.12 LAST-in-A phrasings in the Surfaces table, the roadmap preamble, and the PB-D4 row — all left unedited as historical state): `delta_global` re-keys from the Miliarium-only OQ-23 (iii.b) aggregate to the all-Active-gauge aggregate (`GaugeRegistry.gaugeCount()` / `gaugeAt()`, the P-D13 enumeration; raw ungated sum; F-D18 cold-start semantics carry over); `delta_basket` withdrawn same-day — the damping is inherent in F-5/F-6 one-denominator proportionality, so the spec needs no edit and the F-8/§vii items queued into PB2.10 at the g3b anchor drop; `delta_intra` decoupled-unchanged (OQ-23 iv.a); constants untouched (F-D7). Mechanism per PB-D18 (v): ctor 2→3-arg restoring the P-D22-removed gauge-registry slot with a live consumer + the F-D20-mirror one-shot `setGaugeRegistry` seal; 12 construction sites enumerated up front; EmissionDistributor / GaugeRegistry / EMASampler / ICCBMultiplier zero-change. Zero-TVL disposition per PB-D18 (vi): the F-5 multiplicative kill + the `_gatedTvlEMA` return-0 gate traced pre-lock; four residual windows (drain transient, stale score, dust-LP capture, equal-regime carve-out) evidenced at h. Build roster: a the PB-D18 lock; b this plan section (Surfaces row + Decisions row + this bullet); c the FINDINGS OQ-23 reopen ((iii.b) superseded, (iv.a) decoupled-unchanged, delta_basket recorded-and-withdrawn); d the `CCBMultiplier` rebuild (G16 `is IGaugeRegistry` sweep first; `gaugeCount`/`gaugeAt` additive on `src/ccb/IGaugeRegistry.sol`); e unit (enumeration mock restored, F-D20-mirror setter trio, mixed-roster delta_global math, cold-start/zero-aggregate pins); f fork + deploy-wiring (the 12 ctor sites, `DeployStageF` third arg, orchestrator seal + P10-family wiring assertion); g formal (`CCBEngineProofs.sol` ctor sites + mirrored setter proofs, suite 52 → ~55 with the §8b user-run re-attest; `ccb_multiplier.act` residual-footer rewrite; `formal/RESULTS.md` rows); h the zero-TVL disposition (unit pins; fork economics on the residual windows if the pins leave material doubt; exit Fixed / as-designed-with-evidence / Accepted-risk); i close (Completion Log family rows; §11 anchor amendments — the delta_basket sentence, the clamp/step clause, the PB2.10 item drop; workstream A closes → PB3.1).
- Checkpoint: every roster item Fixed / Built / Descoped-with-PB-D-entry; split-form regression green; whitehat ledger + RB register rows updated.

### PB3 — Workstream B: Sepolia deployment
- **PB3.1** — the PB-D1 environment verify pass (user-run, §8b network reads): faucet availability, Permit2 presence at the canonical address, explorer contract-verification flow. Red result blocks PB3 → fallback discussion, own PB-D entry.
- **PB3.2** — P8 testnet token stubs per PB-D20: `test-stubs/` two-template tier set (`StubERC4626` fixed 1:1 NAV, `StubERC20` ctor-set decimals; Tier-A anchors = named instances) + the base-level envOr override resolver in `deploy-miliarium-pool.s.sol` (STUB_-literal keys, passthrough default, non-zero-RP fail-fast) + the emitted Sepolia env-map (Tier D resolved to the env-map arm — no on-chain registry); roster = the Stage-P Builds list + the Tier-A underlyings (stub ZCHF/USDS); build ladder a–f per PB-D20 (vi).
- **PB3.3** — the canonical Balancer V3 Router redeployed against the Aureum Vault (P-D26; the Permit2 dependency) + `setTrustedRouter` binds + the F-09 allowlist seat (the F-17 fix's symmetric-accounting dependency goes live here).
- **PB3.4** — production orchestration path: un-defer `DeployStageP.run()` (`ProductionOrchestrationDeferredToPbis` → the env-keyed production flow), fork-rehearsed before any broadcast — the rehearsal runs with the PB-D19 future-genesis env (`GENESIS_BLOCK = broadcast + 100_800`, one epoch) and re-confirms the four post-conditions; the two optional pre-genesis evidence pins are PB3.4-scoped.
- **PB3.5** — Sepolia broadcast + explorer verification (user-run; per-command §8b approval; testnet only — §8c keeps mainnet banned).
- **PB3.6** — F-14 ops + fee-custody rails (ixAetheron off-chain conversion, P-D12).
- **PB3.7** — deployed-addresses artifact committed (the frontend-consumption contract).
- Checkpoint: full stack live on Sepolia, explorer-verified, artifact committed; the wiring witness re-run green where fork-replayable against the live deployment.

### PB4 — Workstream C: frontend
- **PB4.1** — hand the addresses artifact to `aumm-app` (OQ-18, separate repo); track the MVP milestone from this repo.
- **PB4.2** — completion gate: the frontend demonstrably reading the Sepolia deployment; evidence recorded in the Completion Log.
- Checkpoint: PB-D4's workstream-C gate satisfied from this repo's side.

### PB5 — Stage close
Two-commit PENDING_PBIS (PB-D3): the close commit writes `PENDING_PBIS` (the `STAGES_OVERVIEW.md` master row + this Completion Log; `CLAUDE.md` §11 stays hash-free) → the `*-backfill` commit substitutes the real hash → tag `stage-p-bis-complete` at the backfill commit → ff-merge `stage-p-bis` → `main`. `stage-p-bis-complete` is the frozen audit candidate handed to Stage Q.
- Checkpoint: zero open workstream-A items; Sepolia live; the frontend gate met; regression logged; the tag at the backfill commit on `main`.

---
## Completion Log
| Sub-step | Commit | Status |
| --- | --- | --- |
| PB1.1 | `f84fa36` | ✅ docs/STAGE_P_BIS_NOTES.md — entry freeze (PB-D1—PB-D5) |
| PB1.1a | `986a223` | ✅ PB-D3 base amendment b5f4b8b → f72b309 (user-adjudicated); CLAUDE.md §11 repointed at `db84611` |
| PB1.2 | `9446cbd` | ✅ docs/STAGE_P_BIS_PLAN.md — plan + PB1—PB5 roadmap + Completion Log |
| PB2.1 | `88c453d` | ✅ PB-D6 lock — OQ-20/OQ-21 BUILD adjudication (user-adjudicated) |
| PB2.1b | `7e250fc` | ✅ src — routeYieldFeeToHook entry point + per-pool BLOCKS_PER_EPOCH throttle |
| PB2.1c | `232b346` | ✅ unit tests — authenticate gate, throttle boundary, stamp-on-revert, bptMinted propagation (42/42) |
| PB2.1d | `28d4193` | ✅ fork witness — collect→route→throttle+auth end-to-end (8/8; closes OQ-20 D4.6 deferral) |
| PB2.1e | `516fa68` | FINDINGS OQ-20/21 closure + Completion Log — this commit |
| PB2.2 | `28c653b` | ✅ PB-D7 lock — OQ-22 BUILD adjudication (2-hop TVLOracle valuation fallback, user-adjudicated) |
| PB2.2b | `61cab54` | ✅ src — _directRatio extraction + _twoHopRatio + hop-underlying roster (ITVLOracle/consumers/constructor unchanged) |
| PB2.2c | `eacb600` | ✅ unit tests — hop gates, direct-wins precedence, mean-across-intermediates, h2-first cheap gate, no-transitive-hop (55/55) |
| PB2.2d | `78c4931` | ✅ fork witness — real USDC via USDS hop, Bodensee hop-2, EMASampler propagation, auth gate (12/12) |
| PB2.2e | `76c6be2` | FINDINGS OQ-22 Phase-2 addendum + L70 label reconciliation + Completion Log — this commit |
| PB2.3 | `1f07d4a` | ✅ PB-D8 lock — pool-restoration adjudication: ixCasper composite-RP BUILD; 04/07 DESCOPE to the challenge path; OQ-I10 closed (user-adjudicated) |
| PB2.3b | `602e5d7` | ✅ script — 03_ixCasper.s.sol config(address) param form + DeployIxCasper view/env read; waEthwstETH restored at index [1], QG 68% → 84% |
| PB2.3c | `fd3dfc2` | ✅ fork fixtures — StageM + StageP composite deploy + env-wire ahead of DeployIxCasper (StageM 7/7, StageP 13/13) |
| PB2.3d | `62e6846` | ✅ CompositeRateProvider.sol NatSpec — PB-D8 second-consumer note (comment-only) |
| PB2.3e | `50aa0e3` | STAGE_I_PLAN + STAGE_I_NOTES OQ-I10 closure + PB2.10 (iv) items + Completion Log — this commit |
| PB2.4 | `6fc8416` | ✅ PB-D9 lock — F-13 SPLIT adjudication (onAfterSwap ACCEPT + sim; routeYieldFee BUILD caller bounds; dormant entries threaded, user-adjudicated) |
| PB2.4b | `ebf5aaa` | ✅ src — caller-supplied minDepositTokenOut + minBptAmountOut threaded (IAureumFeeRoutingHook + AureumFeeRoutingHook + AureumProtocolFeeController pass-through; onAfterSwap 0/0) |
| PB2.4c1 | `69e77c9` | ✅ tests — arity ripple for the bound params across unit + fork call sites (zero bounds, no new coverage; 895 unit green) |
| PB2.4c2 | `1e91e2f` | ✅ unit — bound-threading coverage (order-pinned exact-calldata proofs, all three unlock payloads, controller pass-through, bound-revert stamp-not-advanced; 901 unit green) |
| PB2.4d1 | `6fc1625` | ✅ fork — bounded-route witness (real-Vault BptAmountOutBelowMin + SwapLimit on too-tight bounds, both legs green at realistic bounds; 12/12 fork) |
| PB2.4d2 | `137f1bd` | ✅ fork — onAfterSwap ACCEPT evidence (fee-rider sandwich sim; feeRider 0.375% of swap, skewCost 12× the prize; 14/14 fork) |
| PB2.4e | `5fa40db` | AUREUM_WHITEHAT_OUTPUT F-13 SPLIT row + Completion Log — this commit |
| PB2.5 | `34e4c27` | ✅ PB-D10 lock — F-15 ACCEPT adjudication (poke-invariant truth ceiling; both snapshot fixes rejected as regression-bearing, user-adjudicated) |
| PB2.5b | `f36155b` | ✅ unit — F-15 ACCEPT evidence (real-VotingWeight poke sim: baseline trip, suppression face, truth-ceiling kill, recruit-flip, zero-denominator panic + self-heal edges; 6/6, 907 unit green) |
| PB2.5c | `4e438ed` | AUREUM_WHITEHAT_OUTPUT F-15 Accepted-risk-standalone row + Completion Log — this commit |
| PB2.6-pre | `f444d32` | ✅ PB-D11 lock — VaultClassRegistry one-shot-sealed (not re-settable), reroutes to the PB3.4 production bind; PB2.6 narrows to the five-rotation script (user-adjudicated) |
| PB2.6-pre2 | `ef7ea12` | ✅ PB-D12 lock — emission-layer rotation strands the operational-wiring family under AureumGovernance v1; rotations pinned to dissolution-time, the freeze witnessed as v1 truth (user-adjudicated) |
| PB2.6b | `84a859d` | ✅ script/DissolutionGovernanceHandoff.s.sol — the five dissolution-time rotations (4× emission `setGovernanceContract` + `SwapAndDepositToBodensee.setDonateAuthorizer`); VaultClassRegistry not rotated |
| PB2.6c | `ad42757` | ✅ test/fork/DissolutionGovernanceHandoff.t.sol — PB-D12 rotation witness on the orchestrator-deployed stack (rotations land + multisig lockout + PB-D12(ii) freeze) |
| PB2.6c-fix2 | `b850e8c` | ✅ fork-witness fix — cache handles before `vm.prank`/`vm.expectRevert` (a chained `orchestrator.X()` getter was the "next call" the cheatcodes latched onto); 4/4 fork-green |
| PB2.6d | `7ee86ca` | ✅ pauseManager inert-pointer attestation (Miliarium pauseManager == the write-once GOVERNANCE_MULTISIG, non-exclusive via the authorizer per F-20); 5/5 fork-green |
| PB2.6e | `5cfbd2f` | ✅ docs/STAGES_OVERVIEW.md — multisig-dissolution remainder bullet CLOSED (VaultClassRegistry sealed + pauseManager inert both dropped from the rotation enumeration) |
| PB2.6f | `76e99cd` | STAGE_P_BIS_PLAN.md Completion Log — PB2.6 close — this commit |
| PB2.6g | `a0357ff` | ✅ docs/STAGE_P_BIS_NOTES.md — PB10 lesson (vm.prank AND vm.expectRevert latch a chained getter; P-D38 recurrence, promoted to the §11 index) |
| PB2.6h | `7e9d71f` | ✅ CLAUDE.md — PB10 index bullet + §11 resume anchor (PB2.6 closed; next PB2.7) |
| PB2.7a | `fc09269` | ✅ PB-D13 lock — PB2.7 DESCOPED (stale one-file scope vs the 224-site/16-file measured surface; `--threads 1` permanent posture; user-adjudicated) + plan L22/L75 re-scope |
| PB2.7b | `c6fd6fa` | ✅ ROBUSTNESS_BACKPORT_REGISTER.md — RB-006 row + Test-fixture isolation hardening class |
| PB2.7c | `04db2e4` | ✅ docs/STAGES_OVERVIEW.md — workstream-A D36/F-D11 bullet CLOSED at PB2.7 |
| PB2.7d | — | Decisions-table back-fill (PB-D6—PB-D13) + PB2.6g/h rows + PB2.5c/PB2.6f hash back-fill + Completion Log — this commit |
| PB2.8a | `02536d5` | ✅ PB-D14 lock — `vm.transientStore` absent at pinned forge-std v1.15.0; direct guard witness re-mechanized as roll-plus-accrue mock reentry, channel-only scope + plan L23/L84 re-scope |
| PB2.8b | `612ce0a` | ✅ test/unit/BodenseeBootstrapChannel.t.sol — direct ReentrancyGuard.selector witness on distribute() via roll-plus-accrue mock reentry; arm in MockVault.settle (the getPoolTokenInfo placement was a STATICCALL where the inner state write exceptionally halted — two fix rounds); 35/35 file-scoped, 908/908 Part A |
| PB2.8c | `d11f542` | ✅ ROBUSTNESS_BACKPORT_REGISTER.md — RB-007 row (Invariant-tests class, created Closed at 612ce0a) |
| PB2.8d | — | CLAUDE.md §11 rewrite (PB2.8 closed; ReentrancyGuard.selector carry-forward → Dropped-as-CLOSED; resume anchor → PB2.9) + Completion Log — this commit |
| PB2.9a | `c04b00e` | ✅ PB-D15 lock — P-D42 coverage re-eval: re-probe reproduces the Yul stack-too-deep on the byte-identical toolchain (forge f83bad91 / solc 0.8.26); execution-evidence waiver re-affirmed + plan L24/L86 re-word + Decisions row |
| PB2.9b | `38a68f9` | ✅ docs/STAGES_OVERVIEW.md — workstream-A WK.18/P-D42 bullet: P-D42 clause CLOSED at PB2.9 (WK.18 clause stays open → PB2.11) |
| PB2.9c | — | CLAUDE.md §11 rewrite (PB2.9 closed; resume anchor → PB2.11; no carry-forward drop) + Completion Log — this commit |
| PB2.11a | `505e538` | ✅ PB-D16 lock (NOTES + plan) — WK.18 sim BUILT disposition: F-04's atomic surface already Fixed via the 60-day EMA gate, so the sim is a populated-roster positive-control + economics quantifier, not a bug hunt; plan L25/L90 + L66 Decisions row |
| PB2.11b-i | `b2848ec` | ✅ test/fork/WK18ThinVenuePumpSim.t.sol — sim scaffold (StageN 21-pool populated-roster base + ported VotingWeight wiring; wiring self-test, 1/1 fork-green) |
| PB2.11b-ii | `aec5d67` | ✅ venue pricing layer — two hookless USDC/svZChf constellation venues (_directRatio(USDC) = their cross-venue mean; a one-sided venue pump moves the mean live; 2/2 fork-green) |
| PB2.11b-iii | `0d49203` | ✅ real matured-EMA scored pilot — gauge-seed + recorder position + updateEMA seed / +60d roll / refresh, no _mockPoolEma; 3/3 fork-green |
| PB2.11b-iv | `74ba708` | ✅ face 1 positive control — an atomic venue pump moves spot tvl but leaves governanceWeight byte-identical (the EMA-not-spot proof); 4/4 fork-green |
| PB2.11b-v | `8395d9c` | ✅ face 2 cross-venue dilution — a single-venue pump = 1/N of the both-venue delta (wei-exact, N=2); WH-P6 addConstellationPool double-append attestation; 5/5 fork-green |
| PB2.11b-vi | `b610ca2` | ✅ face 3 sustained-pump economics — +99.6% spot tvl but only +10.69% governanceWeight over 21 daily EMA samples, bounded fee-negative (weightGainBps×2 = 2138 vs spotInflationBps = 9959); on-ramp timeFactor confound caught + fixed; 6/6 fork-green |
| PB2.11c-a | `58ddc0e` | ✅ docs/white_hat/AUREUM_WHITEHAT_OUTPUT.md — WK.18 could-not-assess CLOSED (populated-roster fork-sim evidence; F-04 stays Fixed at c283371+3d80ac8, no findings-table change) |
| PB2.11c-b | `d76ee57` | ✅ docs/STAGES_OVERVIEW.md — WK.18 clause CLOSED at PB2.11 (the P-D42 clause stays byte-identical at PB2.9; the combined bullet now carries a distinct closure tag per clause) |
| PB2.11c-c | `b442248` | ✅ docs/STAGE_P_BIS_PLAN.md Completion Log — PB2.11 family rows (a through c-d planned; the family fanned out further at c-d/c-e/c-f, reconciled at c-g) |
| PB2.11c-d | `0a60321` | ✅ docs/STAGE_P_BIS_NOTES.md — PB11/PB12/PB13 engineering-lesson recipes (em-dash-in-string-literal / solc 8936; timeFactor/ON_RAMP pre-roll confound; insert-fence placement), the NOTES-backed precursor to the §11 index bullets (PB10 precedent) |
| PB2.11c-e | `1ced206` | ✅ CLAUDE.md §11 — two additive edits (WK.18 → Dropped-as-CLOSED; PB11/PB12/PB13 added to the Engineering-lesson index), anchor untouched |
| PB2.11c-f | `e2452a9` | ✅ CLAUDE.md §11 — Last-update resume-anchor advance (PB2.11 close sentence + roster-complete bump + Next sub-step → PB2.12, corrected plan line-refs); date → 2026-07-15 |
| PB2.11c-g | `—` | docs/STAGE_P_BIS_PLAN.md Completion Log — reconciles the c-c/c-d placeholder rows + adds c-e/c-f/c-g rows; PB2.11 CLOSED — this commit |
| PB2.12a | `56a46dd` | ✅ PB-D17 lock — hevm/Act BUILD disposition (PB2.12 hevm/Act bundle; user-adjudicated) |
| PB2.12b | `—` | ✅ §8b hevm 0.58.0 install (user-run; provenance recorded in `formal/RESULTS.md` §1) |
| PB2.12c1 | `47880cc` | ✅ test/formal/FeeRoutingHookProofs.sol — S5 hook harness, P-H1/P-H2 (pipeline validation) |
| PB2.12c3 | `c134fec` | ✅ test/formal/FeeRoutingHookProofs.sol — P-H3..P-H6, closing the S5 Tier-1 roster (9/9) |
| PB2.12c4 | `303445f` | ✅ formal/act/fee_routing_hook.act — S5 hook Act spec |
| PB2.12d1-d2 | `063a03f` | ✅ test/formal/CCBEngineProofs.sol — S7 CCB/EMA harness, P-E1 + rig validation |
| PB2.12d3 | `2e4f35e` | ✅ test/formal/CCBEngineProofs.sol — P-E2/P-E3/P-M1, closing S7 Tier-1 |
| PB2.12d4 | `629e16e` | ✅ formal/act/ema_sampler.act + ccb_multiplier.act — S7 Act spec pair |
| PB2.12d4b | `b51c48d` | ✅ formal/act/fee_routing_hook.act — operator reconciliation, closing the S5 spec's legacy-dialect residue |
| PB2.12e1 | `0aa7c15` | ✅ test/formal/EmissionProofs.sol — emission-accrual Tier-1 harness, AuMM cap/halving |
| PB2.12e2 | `33ae38d` | ✅ test/formal/EmissionProofs.sol — P-R*/P-ED* router + distributor cohorts (22 proofs) |
| PB2.12e3 | `3c41725` | ✅ test/formal/EmissionProofs.sol — P-BC* channel cohort, closing emission-accrual Tier-1 (30/30) |
| PB2.12e4a | `e87711c` | ✅ formal/act/aumm.act + aumm_minter_router.act — token-layer Act spec pair |
| PB2.12e4b | `7c3f65c` | ✅ formal/act/emission_distributor.act + bodensee_bootstrap_channel.act — engine-pair Act specs, closing PB2.12e |
| PB2.12f1 | `6eec86d` | ✅ test/formal/AuthorizerProofs.sol — authorizer-window Tier-1 harness, P-W1..P-W5 (7/7); suite at 52/52 |
| PB2.12f2 | `1e6e6d4` | ✅ formal/act/aureum_governance_authorizer.act + aureum_authorizer.act — authorizer-window Act pair, closing PB2.12f |
| PB2.12g1 | `a3b493e` | ✅ formal/RESULTS.md — property → status index over all four surfaces |
| PB2.12g2 | `408569e` | ✅ docs/STAGE_P_BIS_NOTES.md — PB14 lesson + PB-D17 as-built (vi) |
| PB2.12g3a | `8a4e15b` | ✅ CLAUDE.md — section-3 formal/ tree entries + PB14 index bullet |
| PB2.12g3b | `dd6d922` | ✅ CLAUDE.md — section-11 resume-anchor: PB2.12 CLOSED; OQ-23 reopened → PB2.13 threaded forward |
| PB2.12g4 | `—` | docs/STAGE_P_BIS_PLAN.md Completion Log — PB2.12 family rows (a through g4); PB2.12 CLOSED — this commit |
| PB2.13a | `f614f0e` | ✅ docs/STAGE_P_BIS_NOTES.md — PB-D18 lock (OQ-23 reopened; two same-day 2026-07-16 directives: delta_global → all-Active-gauge aggregate, delta_basket withdrawn; zero-TVL disposition attached; build roster a–i) |
| PB2.13b | `e24b746` | ✅ docs/STAGE_P_BIS_PLAN.md — PB2.13 plan section (Surfaces row + PB-D18 Decisions row + roadmap bullet), restoring plan-line citability for the family |
| PB2.13c | `005fbf5` | ✅ docs/FINDINGS.md — OQ-23 reopen: (iii.b) universe superseded to all-Active-gauges, (iv.a) decoupled-unchanged, delta_basket recorded-and-withdrawn (F-6 rationale); zero spec-side edits |
| PB2.13d1 | `c6a7c79` | ✅ src/ccb/IGaugeRegistry.sol — additive gaugeCount()/gaugeAt(uint256) enumeration members (P-D13 part (1); G16 inheritor sweep first) |
| PB2.13d2 | `3bac2ef` | ✅ src/ccb/CCBMultiplier.sol — the PB-D18 rebuild, full-file: ctor 2→3-arg (gauge-registry placeholder), F-D20-mirror one-shot setGaugeRegistry seal, delta_global re-keyed to the all-gauged aggregate |
| PB2.13e1 | `8529390` | ✅ test/unit/CCBMultiplier.t.sol — MockGaugeRegistry (settable dense gauge list) wired into the 3-arg ctor; 8 gauge tests; unit 916/916 |
| PB2.13e2 | `bb39704` | ✅ test/unit/CCBMultiplier.t.sol — five decoupling tests (gauge vs Miliarium universes genuinely independent; disjoint-roster 777e18-vs-1000e18 discriminator); file 44/44, Part-A 921/921 |
| PB2.13f1 | `72785ea` | ✅ CCBMultiplier 3-arg ctor ripple across the 9 remaining sites (1 script, 5 fork, 3 formal); GAUGE_REGISTRY_PLACEHOLDER env; empty MockGaugeRegistry keeps delta_global neutral; build green tree-wide, unit 916/916 |
| PB2.13f2 | `2b619ce` | ✅ script/DeployStageF.s.sol + DeployStageP.s.sol — post-G-stack orchestrator seal (sealAuthority + NotSealAuthority-guarded sealGaugeRegistry forwarder; DeployStageP post-condition (4) CCBGaugeRegistryNotSealed) |
| PB2.13f3 | `b4132a1` | ✅ test/fork/StageJIntegration.t.sol — retargets the two CCB aggregate assertions to the all-gauged universe; genuine decoupled witnesses at the integration level; file-scoped 5/5 fork-green |
| PB2.13g1 | `413aee7` | ✅ test/formal/CCBEngineProofs.sol — P-M2 gauge-registry one-shot mirror trio (mirrors P-M1 onto setGaugeRegistry); CCB proofs 6→9 |
| PB2.13g2 | `9c109b1` | ✅ formal/act/ccb_multiplier.act — 3-arg ctor rewrite (setGaugeRegistry transition mirroring setMiliariumRegistry; residual footer → the two-aggregate contract) |
| PB2.13g3 | `—` | ✅ §8b user-run hevm re-attest at the g2 tree (9c109b1); 55/55 prove_ PASS (forge clean && forge build --ast prerequisite recorded) |
| PB2.13g4 | `6ba6455` | ✅ formal/RESULTS.md — re-anchors the attested index to the g3 55/55 re-attest (superseding the PB2.12f1 52/52 baseline); 9 CCB proofs, P-M2 row, --ast solver-flag note |
| PB2.13h1 | `6a749c0` | ✅ test/unit/ZeroTvlDisposition.t.sol — F-8 clamp-ceiling resurrect-proof + windows (a)/(b): (59/61)^n drain half-life on the real EMASampler, poolScore persistence + permissionless self-clear both edges; 6/6 |
| PB2.13h2 | `59c7298` | ✅ test/unit/ZeroTvlDisposition.t.sol — ZeroTvlDustCaptureTest, window (c): 1-wei dust captures the full tranche wei-exactly while the score lives, zero after self-clear; 7/7 |
| PB2.13h3 | `6df0999` | ✅ docs/STAGE_P_BIS_NOTES.md — PB-D18 (viii) zero-TVL disposition outcome: all four (vi) windows quantified/closed (a–c as-designed-with-evidence, d note-only); no-fork-escalation rationale |
| PB2.13i1 | `691b8f5` | ✅ CLAUDE.md — section-11 resume-anchor: workstream A CLOSED at PB2.13; delta_basket withdrawn, clamp/step clause evaporated, PB2.10 F-8/§vii carry dropped; close-gate 928/928; Next → PB3.1 |
| PB2.13i2 | `—` | docs/STAGE_P_BIS_PLAN.md Completion Log — PB2.13 family rows (a through i2); workstream A CLOSED → PB3.1 — this commit |
| PB3.4-pre | `cded9c7` | ✅ docs/STAGE_P_BIS_NOTES.md — PB-D19 lock: GENESIS_BLOCK = broadcast + 100_800 (one epoch) decouples the emission clock from deploy; zero code change verified (env-only — DeployAuMM L33 no clamp, the P-D14 four-way assertion is cross-contract, no deploy-time schedule action); PB3.4 future-genesis rehearsal required; two optional pre-genesis pins |
| PB3.4-pre-b | `—` | docs/STAGE_P_BIS_PLAN.md — PB-D19 Decisions-table row + PB3.4 roster annotation + these Completion Log rows — this commit |
| PB3.1a | `51744cf` | ✅ CLAUDE.md — section-11 resume-anchor advance closing the PB3.1 Sepolia verify pass: RPC live (chain 11155111), Permit2 present, deployer 0xA851478dbee97375E784e9b98c0D7D599662bF85 funded 0.05 SepETH; Etherscan key + full gas budget carried non-blocking to PB3.5/PB3.4; PB-D19 backfilled into the anchor narrative; Next → PB3.2 |
| PB3.1b | `—` | docs/STAGE_P_BIS_PLAN.md Completion Log — PB3.1a row + this row; PB3.1 CLOSED → PB3.2 — this commit |
| PB3.2a1 | `414eddc` | ✅ docs/STAGE_P_BIS_NOTES.md — PB-D20 lock: base-level envOr resolver (STUB_-literal keys via vm.toString, passthrough default, non-zero-RP fail-fast), Tier D = env-map, real RPs over 18/18 stub 4626s (F-11 deviation recorded), two templates + named Tier-A instances, permissionless mint; build ladder a–f |
| PB3.2a2 | `—` | docs/STAGE_P_BIS_PLAN.md — PB-D20 Decisions row + PB3.2 roster annotation + these Completion Log rows — this commit |
| PB3.2b1 | `860bd2f` | ✅ test-stubs/StubERC20.sol — first template: ctor-set name/symbol/decimals over OZ ERC20 + permissionless uncapped mint(address,uint256); backs ixEDEL |
| PB3.2b2 | `5ac8799` | ✅ test-stubs/StubERC4626.sol — fixed-1:1-NAV 4626 stub (convertToAssets/previewRedeem identity, deposit/withdraw, seeding mint), deliberately not is-IERC4626 (mint-collision dodge), 18/18 inherited (F-11); backs svZCHF/sUSDS. Rung b complete |
| PB3.2c1 | `1ca2c9e` | ✅ test/unit/StubERC20.t.sol — 5 tests (metadata, decimals-respects-ctor at 6/8/18, permissionless mint, uncapped, accumulate); 5/5 |
| PB3.2c2 | `49fe65d` | ✅ test/unit/StubERC4626.t.sol — 11 tests: fuzzed 1:1 conversions, previewRedeem(1e18)==1e18, deposit/withdraw/allowance paths, unbacked seed-mint, both F-11 RP cases (accept 18/18, revert InvalidAssetDecimals(6)); 11/11. Rung c complete, 16/16 |
| PB3.2d1 | `b7bc0f7` | ✅ script/pools/deploy-miliarium-pool.s.sol — base-level STUB_ override resolver (_resolveStub vm.envOr passthrough + _resolveRateProvider WITH_RATE-zero fail-fast); QG loop reads pre-override cfg.* untouched; 26 config libs + 28 wrappers frozen; full-project build green |
| PB3.2d2 | `—` | ✅ no-STUB_-env byte-identity proof: the P10 fork suite (StagePIntegration.t.sol, --fork-url mainnet --threads 1) 13/13 green, passthrough byte-identical; verification-only, no commit |
| PB3.2e1 | `94a469c` | ✅ docs/STAGE_P_BIS_NOTES.md — PB-D21 lock: iterate-the-real-configs stub-deploy architecture (drift-free STUB_ derivation, two RP override paths, fork-derive-now / broadcast-at-PB3.5) |
| PB3.2e2a | `ad32d7b` | ✅ docs/STAGE_P_BIS_NOTES.md — PB-D21 (v) correction, address model user-adjudicated: plain CREATE, real map at PB3.5, rehearsal self-deploys via vm.setEnv |
| PB3.2e2b1 | `dd0f179` | ✅ test-stubs/DeployTestnetStubs.s.sol — iterate-and-deploy core: 26 config libs (21 zero-arg + 5 placeholder-arg), WITH_RATE/STANDARD classification, dedup by mainnet address |
| PB3.2e2b2 | `db7c23f` | ✅ test-stubs/DeployTestnetStubs.s.sol — named-key emission (5 N-D7 RPs + SV_ZCHF/SUSDS via config constants), coverage require gate, console2.log map |
| PB3.2e2c | `—` | ✅ mainnet-fork validation run (forge script --fork-url mainnet, no broadcast): script succeeded, coverage passed, 67 STUB_ pairs + 7 named keys with zero passthrough; verification-only, no commit |
| PB3.2e3 | `a867254` | ✅ test-stubs/sepolia-stubs.env — committed fork-sample map (67 STUB_ + 7 named), byte-verified via an independent determinism re-run; live addresses regenerated at PB3.5. Rung e complete |
| PB3.2f1 | `772292e` | ✅ CLAUDE.md — section-11 resume-anchor advance: PB3.2 COMPLETE, Next → PB3.3 |
| PB3.2f2 | `—` | docs/STAGE_P_BIS_PLAN.md Completion Log — the PB3.2 b1–f1 rows + this row; PB3.2 CLOSED → PB3.3 — this commit |
