# Stage O — Plan & Sub-Step Roadmap

> **Status:** Stage O COMPLETE — tagged `stage-o-complete`, ff-merged to `main` (O-D8). The OQ-7 composition-fitness gate (`GaugeEligibility.meetsCompositionQualityGate`, O-D2 / O-D2a, supersedes K-D6e) + WO whitehat F-12 fix; 872 unit + 124 fork green. Companion to STAGE_O_NOTES.md (the design-decision log); this file is the sub-step sequence + Completion Log + grep-verifiable checkpoints.
>
> **Last update:** 2026-06-30 — O7.2 (Stage O close) committed; full regression 872 unit + 124 fork green; tag `stage-o-complete` placed at the O7.2-backfill commit, ff-merged to `main`. Stage O COMPLETE. Next: Stage P.
>
> **Mode:** Opus high (§13 Stage-O default — the composition-gate wiring touches a tagged-complete contract (`AureumGovernance`) + an interface (`IGaugeRegistry`, G16)). Drops to Sonnet for: the G16 compile-stubs (O2.3), the stale-doc edits (O6), unit-test transcription once the harness is confirmed, and Completion-Log housekeeping.
>
> **Audience:** Sagix + any future Claude session resuming Stage O execution. NOTES (STAGE_O_NOTES.md) is the design-rationale source-of-truth; this file is the execution spine.

---
## Stage scope

Stage O ships the OQ-7 composition-challenge fitness gate — the one programmatic check canonical §xxvii requires that the Stage-K atomic-execute skeleton (K-D6a—K-D6e) left out (O-D0 / O-D2, supersedes K-D6e). The atomic deprecate-and-replace path (`proposeCompositionChallenge` → 2/3 vote → `_executeProposal`: `revokeGauge` + `replaceSlot` + `registerGaugeFromComposition`) already exists. Stage O adds the registry-level 4626-Quality-Gate-≥52% + canonical-hook check on the replacement pool (O-D2 / O-D2a), corrects stale "90-day boost" docs (O-D3 — the spec mandates no automatic boost; cold-start = optional Incendiary Boost), flags the orphaned `CCBMultiplier.activateBoost` for the Stage-P sweep (O-D4), and proves the path on a mainnet fork (O-D9). No Router (O-D5), no pool restoration (O-D6). All code lands fix-forward on `stage-o`; the Stage-G/I/K tags stay untouched (O-D7, I13-class).

### Surfaces produced at Stage O
| File | Status | Sub-step | Change |
| --- | --- | --- | --- |
| `src/gauge/IGaugeEligibility.sol` | EDIT | O1.1 | + `meetsCompositionQualityGate(address) external view returns (bool)` sig |
| `src/gauge/GaugeEligibility.sol` | EDIT | O1.2 | + view impl (`_compute52PctNumerator ≥ 0.52e18` + hook assert + forbidden-token revert) |
| `src/ccb/IGaugeRegistry.sol` | EDIT | O2.1 | + delegating `meetsCompositionQualityGate(address) external view returns (bool)` |
| `src/gauge/GaugeRegistry.sol` | EDIT | O2.2 | + pass-through to `IGaugeEligibility(gaugeEligibility)` |
| `CCBMocks.sol` / `VotingWeight.t.sol` / `EmissionDistributor.t.sol` / `CCBMultiplier.t.sol` | EDIT | O2.3 | G16 — compile-stub the new method on the 4 other `is IGaugeRegistry` inheritors |
| `src/governance/AureumGovernance.sol` | EDIT | O3.1 | + `CompositionQualityGateFailed` error + gate at `proposeCompositionChallenge` (pre-deposit) + `_executeProposal` |
| `test/unit/AureumGovernance.t.sol` | EDIT | O3.2 | I13 — duck-typed `MockGaugeRegistry` gains `meetsCompositionQualityGate` (controllable, default true); + gate-reject tests |
| `test/unit/GaugeEligibility.t.sol` | EDIT | O4 | new `GaugeEligibilityCompositionGateTest` — accept/reject/ForbiddenToken/WrongFeeRoutingHook/delegation |
| `test/fork/StageOIntegration.t.sol` | NEW | O5 | composition lifecycle (mirror K4.7b) + QG accept/reject at propose & execute + deprecated-hook-survives swap |
| `docs/STAGES_OVERVIEW.md` | EDIT | O6.1 | drop "with 90-day boost activated" from Stage O |
| `docs/FINDINGS.md` | EDIT | O6.2 | strike the stale 90-day-boost-at-composition language (OQ-7 Q2 + the gauge-integration note) |
| `STAGE_O_PLAN.md` / `CLAUDE.md` §11 / `STAGES_OVERVIEW.md` / whitehat ledger | EDIT | O7 | WO whitehat pass + Stage O close + tag `stage-o-complete` |

### Surfaces NOT produced at Stage O
- No re-architecture of the K atomic-execute skeleton — O3 adds two guard calls + one error, not a rewrite of `_executeProposal`.
- No `CCBMultiplier.sol` edit — O-D4 only logs the `activateBoost` orphan for the Stage-P whitehat sweep (stage-f-complete, I13-class).
- No Router contract (O-D5); no `{04 ixViatica, 07 ixCambio}` / ixCasper-leg restoration (O-D6).
- No `aumm-site` canonical-spec edit — §xxi/§xxvii/§xxiv already say no boost; the stale text is repo-side only (O6).
- No re-tag of Stage G / I / K — all wiring is fix-forward on `stage-o` (O-D7, I13-class).
- No mainnet broadcast.

---
## Decisions

Mirror of `STAGE_O_NOTES.md` (O-D0—O-D9 + O-D2a, LOCKED at O0.1 from the O pre-flight Opus beats; freeze committed `bd6ae82`). The NOTES file holds the rationale; this table is the roadmap index.

| # | Decision (one-line) | Sub-step |
| --- | --- | --- |
| O-D0 | K shipped the atomic skeleton; O = fitness gate + doc fix + fork test | O1—O6 |
| O-D1 | Composition challenge survives the auto-gauge pivot as a 2/3 vote — K shape correct | (no code) |
| O-D2 | `meetsCompositionQualityGate` view (≥52%), wired via `IGaugeRegistry`; supersedes K-D6e | O1—O3 |
| O-D2a | View also asserts the canonical `feeRoutingHook` (I-D13) | O1.2 |
| O-D3 | No automatic 90-day boost; cold-start = optional Incendiary Boost; fix stale docs | O6 |
| O-D4 | `CCBMultiplier.activateBoost` orphaned — flag for Stage-P, do not remove | (logged) |
| O-D5 | No Aureum Router (D33 closed — Balancer's, Stage-P deploy) | (no code) |
| O-D6 | Pool restoration stays deferred (E-D17 bar) | (no code) |
| O-D7 | O-D2 supersedes K-D6e fix-forward; Stage-K tag untouched (I13-class) | O3 / O7 |
| O-D8 | Fresh `stage-o` off `main` @ ef8cf54; close tag `stage-o-complete` | O0 / O7 |
| O-D9 | Unit (QG view) + fork (StageOIntegration) test strategy | O4 / O5 |

---
## Sub-step roadmap (O1—O7)

> Execution spine O1 → O7 in dependency order (interface-down). O1 (the GaugeEligibility view) before O2 (the IGaugeRegistry delegation depends on the view sig) before O3 (AureumGovernance calls through its existing `GAUGE_REGISTRY` handle). O4/O5 (tests) after O3. O6 (doc fixes) is independent — schedulable anytime. O7 closes. Each numbered sub-step is one §8e.1 per §8e.

### O1 — `meetsCompositionQualityGate` on GaugeEligibility (O-D2 / O-D2a)
- **O1.1** — `src/gauge/IGaugeEligibility.sol`: add `meetsCompositionQualityGate(address pool) external view returns (bool)` (alongside `evaluateEligibility` / `isEligible` / `cohortOf` / `snapshotEpoch`).
- **O1.2** — `src/gauge/GaugeEligibility.sol`: implement the view — reads `IVault(vault).getPoolTokens(pool)` + `IWeightedPool(pool).getNormalizedWeights()`, asserts `getHooksConfig(pool).hooksContract == feeRoutingHook` (revert `WrongFeeRoutingHook`, O-D2a), returns `_compute52PctNumerator(tokens, weights) >= 0.52e18` (inherits the T-I3 `ForbiddenToken` revert). Narrower than `_checkEligibilityCriteria` — no TVL floor / factory / anti-spam (O-D2). `external view`, no state, no latch.
- Checkpoint: `forge build` green; grep confirms the new sig in both files; `0.52e18` + `WrongFeeRoutingHook` + `getHooksConfig` present in the impl.

### O2 — IGaugeRegistry delegation (O-D2, G16)
- **O2.1** — `src/ccb/IGaugeRegistry.sol`: add `meetsCompositionQualityGate(address pool) external view returns (bool)`. Re-grep the authoritative inheritor set at pre-flight: `grep -rln "is IGaugeRegistry" src/ test/ script/`.
- **O2.2** — `src/gauge/GaugeRegistry.sol`: implement as a pass-through — `return IGaugeEligibility(gaugeEligibility).meetsCompositionQualityGate(pool);` (the `gaugeEligibility` immutable is already held, G-D16d).
- **O2.3** — G16 compile-stubs (one coordinated §8e.1): add `meetsCompositionQualityGate` returning `false` to the four other `is IGaugeRegistry` inheritors — `test/fork/mocks/CCBMocks.sol`, `test/unit/VotingWeight.t.sol`, `test/unit/EmissionDistributor.t.sol`, `test/unit/CCBMultiplier.t.sol` (none exercise composition; stub only to satisfy the interface).
- Checkpoint: `forge build` green across all 5 implementors; full unit suite still green (the new method is unused in these mocks).

### O3 — AureumGovernance gate wiring (O-D2 / O-D7, I13)
- **O3.1** — `src/governance/AureumGovernance.sol`: add error `CompositionQualityGateFailed(address pool)`; gate `proposeCompositionChallenge` (call `GAUGE_REGISTRY.meetsCompositionQualityGate(newPool_)` BEFORE `_createProposal`, so the deposit is not pulled on a reject) and the `_executeProposal` CompositionChallenge branch (re-check before `replaceSlot`; revert on false). Constructor untouched — reaches the view through the existing `GAUGE_REGISTRY` immutable.
- **O3.2** — `test/unit/AureumGovernance.t.sol`: I13 retrofit. The duck-typed `MockGaugeRegistry` (L39, not `is IGaugeRegistry`) gains `meetsCompositionQualityGate(address) returns (bool)` backed by a settable field defaulting to `true`, so the 7 existing composition tests (L164/237/281/297/299/303/307) keep passing; add tests asserting `CompositionQualityGateFailed` at propose (pre-deposit — assert no deposit transfer) and at execute (flip the flag false mid-lifecycle).
- Checkpoint: full unit suite green; the 7 prior composition tests unchanged in intent; new reject tests pass; `forge build` green.

### O4 — GaugeEligibility unit tests for the QG view (O-D9)
New `GaugeEligibilityCompositionGateTest is GaugeEligibilityFixture` in `test/unit/GaugeEligibility.t.sol` — reuses the existing harness (`MockWeightedPool`, `MockERC4626Token`, `MockVaultClassRegistry`, the `vm.mockCall` getPoolTokens/getHooksConfig pattern). Cases: ≥52% admitted-4626 → true; <52% → false; AuMM/AuMT → `ForbiddenToken`; wrong hook → `WrongFeeRoutingHook` (O-D2a); a zero-TVL conforming pool still → true (confirms the O-D2 narrowness — no TVL-floor dependence).
- Checkpoint: `forge clean && forge build` (F14) + `forge test --match-path test/unit/GaugeEligibility.t.sol` green.

### O5 — StageOIntegration fork test (O-D9)
New `test/fork/StageOIntegration.t.sol` mirroring the K4.7b composition-lifecycle (reuse the Stage-K / Stage-G fixtures). On the mainnet fork: deploy a conforming candidate replacement pool, run propose → castVote → queue → execute against a seeded slot, assert (a) atomic `revokeGauge(old)` + `replaceSlot(slot,new)` + `registerGaugeFromComposition(new)`; (b) the QG gate accepts the conforming candidate and rejects a <52% candidate at BOTH propose and execute; (c) the deprecated pool's fee-routing hook still fires on a post-deprecation swap (§xxvii / Q1.5); (d) no boost on the replacement (O-D3 — `boostExpiryBlock[new] == 0`). Split-form fork run per D35 (`--match-path test/fork/**`); `--threads 1` if the D36 env-race surfaces. May fan into O5.1—O5.x at pre-flight if the fixture setup warrants a split.
- Checkpoint: fork suite green (split-form per D35); full regression (unit + fork) green.

### O6 — Stale-doc corrections (O-D3)
- **O6.1** — `docs/STAGES_OVERVIEW.md` Stage O section: strike the "with 90-day boost activated" clause from the `registerGaugeFromComposition` bullet (cold-start = optional Incendiary Boost per §xxi).
- **O6.2** — `docs/FINDINGS.md`: OQ-7 Q2 ("the 90-day gauge boost … applies as usual") + the gauge-integration "register … with 90-day boost (Stage O wire-up)" note — correct to "no automatic boost; optional Incendiary Boost per §xxi (O-D3)".
- Checkpoint: grep returns zero residual composition-tied "90-day boost" hits in both files; the no-boost rationale + O-D3 ref present.

### O7 — WO whitehat pass + Stage O close
- **O7.1** — WO whitehat pass over the new composition-fitness gate (`meetsCompositionQualityGate` + the AureumGovernance call sites + the IGaugeRegistry delegation), per the per-stage whitehat cadence (WK-R / WL / WM / WN lineage). Focus: the gate's deliberate narrowness (zero-TVL slot-seat — design vs gap), the propose-vs-execute re-check window (admitted-class mid-vote change), the O-D2a hook assertion, and ordering/reentrancy in `_executeProposal`. Findings (if any) fixed fix-forward on `stage-o`; ledger `docs/white_hat/AUREUM_WHITEHAT_OUTPUT.md` + a self-identifying WO entry + a CLAUDE.md §11 pointer.
- **O7.2** — Stage O close: `CLAUDE.md` §11 anchor, `STAGES_OVERVIEW.md` Stage O Completion + master-sequence row, `STAGE_O_PLAN.md` Completion Log; full regression green; tag `stage-o-complete`; ff-merge `stage-o` → `main`.
- Checkpoint: WO carries zero open findings; the tag sits at the close commit on `main`; regression count logged.

---
## Completion Log
| Sub-step | Commit | Status |
| --- | --- | --- |
| O0.1 | bd6ae82 | ✅ docs/STAGE_O_NOTES.md — design freeze (O-D0—O-D9 + O-D2a) |
| O0.2 | a9eea66 | ✅ docs/STAGE_O_PLAN.md — plan + sub-step roadmap |
| O1 | 0d07659 | ✅ src/gauge/IGaugeEligibility.sol + GaugeEligibility.sol — `meetsCompositionQualityGate` view (≥52% numerator + canonical-hook assert O-D2a + ForbiddenToken; narrower than `_checkEligibilityCriteria`) |
| O2 | 433d340 | ✅ src/ccb/IGaugeRegistry.sol + src/gauge/GaugeRegistry.sol — delegating pass-through to `IGaugeEligibility`; G16 compile-stubs on the 4 other `is IGaugeRegistry` inheritors |
| O3 | 7de8f4f | ✅ src/governance/AureumGovernance.sol + test/unit/AureumGovernance.t.sol — `CompositionQualityGateFailed` gate at `proposeCompositionChallenge` (pre-deposit) + `_executeProposal` (pre-mutation); I13 mock retrofit |
| O4 | 6417818 | ✅ test/unit/GaugeEligibility.t.sol — `GaugeEligibilityCompositionGateTest` (accept at 52% / reject below / ForbiddenToken / WrongHook / TVL-floor-blind) |
| O5 | e6efdf9 | ✅ test/fork/StageOIntegration.t.sol — composition lifecycle (Approach B): accept + atomic replace, reject at propose & execute, deprecated-hook survives, no boost (O-D3) |
| O6 | c0fba45 | ✅ docs/STAGES_OVERVIEW.md + docs/FINDINGS.md — strike stale "90-day boost" composition claim (O-D3; 5 occurrences) |
| O7.1 (WO) | b7d64a6 + e3ab8cf + add6e75 + 7100736 | ✅ WO whitehat pass — F-12 (Low) Fixed: `isPoolFromFactory` provenance check added to the gate (b7d64a6 fix + e3ab8cf PoC + add6e75 docs + 7100736 ledger 119→124) |
| O7.2 | PENDING_O7 | ✅ Stage O close — CLAUDE.md §11 + STAGES_OVERVIEW.md (Completion + master row) + STAGE_O_PLAN.md Completion Log; 872 unit + 124 fork green; tag `stage-o-complete`; ff-merge → `main` |
