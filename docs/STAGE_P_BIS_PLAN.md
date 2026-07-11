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
| `test/fork/DeployAureumVault.t.sol` env-key namespacing | A | PB2.7 | D36 permanent fix; retires the F-D11 `--threads 1` workaround |
| direct `ReentrancyGuard.selector` test (`vm.transientStore`) | A | PB2.8 | robustness backport (RB register row closure) |
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
- **PB2.2** — adjudicate OQ-22 (2-hop fee-routing fallback through ZCHF / sUSDS): build vs descope; own PB-D lock.
- **PB2.3** — adjudicate pool restoration: 04 ixViatica / 07 ixCambio (E-D17 literals bar) + the ixCasper waEthwstETH 16% leg (Aureum `CompositeRateProvider`) + the OQ-I10 recorder-binding remainder — restore vs descope-to-the-composition-challenge-path (exists since Stage O); own PB-D lock.
- **PB2.4** — adjudicate F-13 (S5 Low, unbounded internal-leg slippage): rate-derived `limitRaw` / `minBptAmountOut` bound vs accept-with-quantifying-sandwich-sim; own PB-D lock.
- **PB2.5** — adjudicate F-15 (S9 Low, `VaultClassRegistry` veto live-denominator): F-06-style snapshot propagation vs accept; own PB-D lock.
- **PB2.6** — the PB-D2 wiring build: governance-handoff rotation script (`setGovernanceContract` rotations for the re-settable slice — emission-layer governance, `VaultClassRegistry`, `SwapAndDepositToBodensee` donate authority) + a P-D36-style fork-test witness on the orchestrator-deployed stack + the `pauseManager` inert-pointer attestation; includes the one-line `STAGES_OVERVIEW.md` roster-wording reconciliation with PB-D2 (`pauseManager` listed among rotations pre-freeze).
- **PB2.7** — D36 permanent fix: env-key namespacing in `test/fork/DeployAureumVault.t.sol`; retire the F-D11 `--threads 1` workaround once regression proves parallel-safe.
- **PB2.8** — direct `ReentrancyGuard.selector` test via `vm.transientStore` (robustness backport; H3.7e covers transitively today).
- **PB2.9** — P-D42 coverage-tooling re-eval: re-probe `forge coverage` viability on the current tree or re-affirm the execution-evidence waiver; attestation either way.
- **PB2.10** — aumm-site spec edits (user-side, runs in parallel): §viii/§ix per OQ-20/21 + the I-reframe, §xxi sandbox row, F-2 Incendiary amendments, FINDINGS corrections. Gate: the spec matches the code before PB5.
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
| PB1.2 | — | this file — pending |
