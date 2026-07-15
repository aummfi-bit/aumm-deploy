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
| P-D42 coverage-tooling re-eval attestation | A | PB2.9 | re-probe `forge coverage` or re-affirm the execution-evidence waiver |
| WK.18 thin-venue populated-roster fork sim | A | PB2.11 | LAST-in-A binding of the near-frozen tree |
| hevm + Act formal-methods bundle + specs | A | PB2.12 | P-D9, LAST in A; ships in the audit hand-off package |
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
- **PB2.9** — P-D42 coverage-tooling re-eval: re-probe `forge coverage` viability on the current tree or re-affirm the execution-evidence waiver; attestation either way.
- **PB2.10** — aumm-site spec edits (user-side, runs in parallel): §viii/§ix per OQ-20/21 + the I-reframe, §xxi sandbox row, F-2 Incendiary amendments, FINDINGS corrections, + the PB-D8 (iv) items — `03_ixCasper.md` Fluid-vs-"Flux Finance" mislabel (fWSTETH / fWETH are Fluid per the `07a` rows; the code always bound the Fluid addresses), `04_ixViatica.md` "Flux Finance BRZ vault" wording, `07a_tokens.md` slot-03 waEthwstETH row (M-D11 "RP unresolvable" → the PB-D8 Aureum-composite restoration). Gate: the spec matches the code before PB5.
- **PB2.11** — WK.18 thin-venue populated-roster fork sim (LAST-in-A block, after all fix items land).
- **PB2.12** — hevm + Act formal-methods bundle (P-D9): the §8b install approval happens at this sub-step; targets the Aureum-owned surfaces (fee-routing hook, CCB engine, emission accrual, authorizer window); specs + results archived for the audit hand-off (LAST in A).
- Checkpoint: every roster item Fixed / Built / Descoped-with-PB-D-entry; split-form regression green; whitehat ledger + RB register rows updated.

### PB3 — Workstream B: Sepolia deployment
- **PB3.1** — the PB-D1 environment verify pass (user-run, §8b network reads): faucet availability, Permit2 presence at the canonical address, explorer contract-verification flow. Red result blocks PB3 → fallback discussion, own PB-D entry.
- **PB3.2** — P8 testnet token stubs: `test-stubs/` ERC-20 tier set + registry, roster per the Stage-P Builds list.
- **PB3.3** — the canonical Balancer V3 Router redeployed against the Aureum Vault (P-D26; the Permit2 dependency) + `setTrustedRouter` binds + the F-09 allowlist seat (the F-17 fix's symmetric-accounting dependency goes live here).
- **PB3.4** — production orchestration path: un-defer `DeployStageP.run()` (`ProductionOrchestrationDeferredToPbis` → the env-keyed production flow), fork-rehearsed before any broadcast.
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
