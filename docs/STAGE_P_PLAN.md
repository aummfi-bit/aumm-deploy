# Stage P — Plan & Sub-Step Roadmap

> **Status:** Stage P OPEN — P0.1 design freeze committed (`6aebebe`, P-D0—P-D11 + four amendments); P0.2 (this plan) in flight. Two workstreams: **(A)** the white-hat back-fill sweep (opens the stage), **(B)** full-system deployment + dual integration validation. Companion to STAGE_P_NOTES.md (the design-decision log); this file is the sub-step sequence + the WH contract×surface matrix + the Completion Log + grep-verifiable checkpoints.
>
> **Last update:** 2026-07-01 — P0 complete (freeze `6aebebe` + plan `6f913ac` + testnet reconciliation `ff32941`/`4696112`); P1 WH-D fee-routing back-fill audited (S2/S5/S6 — F-13 S5 Low Accepted-risk logged; S2/S6 NO FINDING). Branch `stage-p` @ `4696112` (cut from `main` @ f50b4cd = `stage-o-complete`, P-D4). Regression baseline carried from Stage O: 872 unit + 124 fork green. Next: P2 (WH-G pass).
>
> **Mode:** Opus high entry — the white-hat sweep (audit reasoning) + the O-D4 / P-D8 `activateBoost` removal (I13, tagged contract) are §13 Opus-high beats. The §13 table's "P/Q/R extra-high" is the formal-verification character of Stage Q's Act proofs + Stage R; Stage P's optional hevm shakeout (P7) is not that beat. Drops to Sonnet for: PoC-test transcription once a finding's attack path is characterised, stub-template transcription (P8), Completion-Log housekeeping, and the P0.3 doc strike (O-D3-class).
>
> **Audience:** Sagix + any future Claude session resuming Stage P execution. NOTES (STAGE_P_NOTES.md) is the design-rationale source-of-truth; this file is the execution spine + the audit matrix.

---
## Stage scope

Stage P is the first stage where the whole stack runs as one system — the integration boundary every prior stage built toward, and the pre-audit hardening pass before Stage Q's external audit + code freeze. Two workstreams. **(A) White-hat back-fill sweep** (opens the stage, P-D5 / P-D6): the per-stage audit cadence began at the Stage K close, so Stages D / G / H / I / J / L were never audited in isolation — Stage P runs those back-fill passes (WH-D…WH-L), then the four named cross-seams a per-stage pass cannot see, then the INV-2 invariant harness and the O-D4 / P-D8 `activateBoost` removal, then an optional hevm symbolic shakeout. **(B) Full-system deployment** (P-D1 / P-D2 / P-D3): tiered testnet token stubs, network-parameterised deploy scripts (the live testnet target — Sepolia or Hoodi — is a P-bis decision per P-D1), the Balancer V3 substrate redeploy, and dual integration validation — Tenderly mainnet-fork e2e (real literals) is the primary `stage-p-complete` gate; the live testnet broadcast + the `aumm-app` frontend wiring is the deferred P-bis sub-phase. All sweep fixes land fix-forward on `stage-p`; no tagged stage is re-tagged (P-D5, I13-class).

### Surfaces produced at Stage P
| Artifact | Workstream | Sub-step | Purpose |
| --- | --- | --- | --- |
| `docs/FINDINGS.md` + `docs/STAGES_OVERVIEW.md` (testnet) | B | P0.3 | P-D1b Holesky→network-agnostic strike (O-D3-class) |
| `test/whitehat/F-NN_*.t.sol` PoCs | A | P1—P6 | per-finding Foundry PoCs (mirror F-01…F-12) |
| `docs/white_hat/AUREUM_WHITEHAT_OUTPUT.md` rows + roll-up | A | P1—P7 | ledger findings + per-surface coverage attestation |
| `test/invariant/*.t.sol` + `ReferenceEmission.sol` | A | P6 | INV-1/6 + INV-2 (non-circular) + INV-3 (+ INV-4 opt) harness |
| `src/ccb/CCBMultiplier.sol` (edit) | A | P6 | O-D4 / P-D8 `activateBoost` + boost-machinery removal (I13) |
| `test-stubs/*.sol` (Tier A—D) | B | P8 | testnet token stubs + `TestnetTokenRegistry` |
| `script/DeployStageP.s.sol` (+ network-param) | B | P9 | full-stack orchestrator + Balancer V3 Router redeploy (D33 / O-D5) |
| `test/fork/StagePIntegration.t.sol` | B | P10 | Tenderly mainnet-fork e2e (real literals) |
| hevm artifacts (optional) | A | P7 | S5 / S7 / S8-relabeled symbolic shakeout |
| `STAGE_P_PLAN.md` / `CLAUDE.md` §11 / `STAGES_OVERVIEW.md` / ledger | — | P11 | Stage P close + tag `stage-p-complete` |

### Surfaces NOT produced at Stage P
- No live-network broadcast — a live testnet or mainnet `--broadcast` is the deferred P-bis sub-phase (§8b / §8c, P-D3).
- No `aumm-app` frontend wiring — external repo, OQ-18, P-bis.
- No re-audit of the K / L / M / N / O fixes (F-01…F-12 all Fixed) — Stage P back-fills the never-audited pre-K stages only, unless a fix-forward diff reopens a surface (P-D11).
- No Router source fork — the Balancer V3 Router source is redeployed bound to the Aureum Vault, not forked (D33 / O-D5).
- No pool restoration — 04 ixViatica / 07 ixCambio / the ixCasper waEthwstETH leg stay deferred on the E-D17 bar (O-D6).
- No `aumm-site` canonical-spec edit — the spec names no testnet; the Holesky→network-agnostic strike is repo-side only (P-D1b).
- No Act spec / formal proofs — Stage Q owns the formal-verification budget; hevm (P7) is kept separate (P-D9).

---
## Decisions

Mirror of `STAGE_P_NOTES.md` (P-D0—P-D11, LOCKED at P0.1 from the Stage-P pre-flight Opus beats + the user design-review; freeze committed `6aebebe`). The NOTES file holds the rationale; this table is the roadmap index.

| # | Decision (one-line) | Sub-step |
| --- | --- | --- |
| P-D0 | Two workstreams (A sweep opens, B deploy); gated P-bis; sweep-before-deploy | P0—P11 |
| P-D0b | Tenderly mainnet-fork e2e (real literals) = primary close gate; live testnet + stubs = P-bis | P10 |
| P-D1 | Testnet posture network-agnostic; live target (Sepolia/Hoodi) deferred to P-bis; supersedes OQ-16 | P0.3 / P9 |
| P-D1b | `FINDINGS.md` + `STAGES_OVERVIEW.md` Holesky→network-agnostic strike (O-D3-class) | P0.3 |
| P-D2 | Tiered stubs (A anchors / B ERC4626 / C ERC20 / D wiring); AuMM + RPs deploy real | P8 |
| P-D3 | Broadcast-gated — scripts + Tenderly fork only; no `--broadcast` in Stage P | P9 / P10 |
| P-D4 | Fresh `stage-p` off `main` @ f50b4cd; two-commit PENDING_P close | P0 / P11 |
| P-D5 | WH methodology = process doc; scope = back-fill + cross-seam; fix-forward (I13) | P1—P7 |
| P-D6 | Order WH-D→G→H→I→J→L→cross-seam→INV-2→O-D4 fix→hevm; 4 named seams | P1—P7 |
| P-D7 | INV-1/6 + INV-2 + INV-3 (+ INV-4 opt); drop gov-weight monotonicity | P6 |
| P-D8 | `activateBoost` deprecate-and-remove; impl after WH-H clears CCBMultiplier; I13 | P6 |
| P-D9 | hevm S5 / S7 / S8-relabeled; install §8b at P7; optional, not a close gate | P7 |
| P-D10 | WH PoCs + invariant harness + Tenderly e2e + split-form regression (D35 / D36 / F14) | P1—P10 |
| P-D11 | Back-fill = pre-K stages (D / G / H / I / J / L), not re-audit of K—O | P1—P7 |

---
## White-hat contract × surface matrix (workstream A)

The operational spine of the sweep — one row = one §8e.1 step (process-doc §1: one surface × one contract). Surfaces are the S0—S12 catalog (process-doc §7) filtered to what each contract exposes; skipped surfaces are attested explicitly, never silently omitted (§3). Severity-ordered per §4 (`*.1` is S1 supply / mint wherever a contract can mint). Each step ends with the §9 attestation line; each finding becomes a ledger row + a `test/whitehat/` PoC.

| Step | Surface | Contract(s) | Lens focus |
| --- | --- | --- | --- |
| WH-D.1 | S2 fee conservation | `AureumProtocolFeeController` | 50/50 split immutable; no third destination; creator-fee functions revert; no post-deploy destination setter |
| WH-D.2 | S5 hook hot path | `AureumFeeRoutingHook` | reentrancy via `Vault.unlock` + nested svZCHF swap + one-sided Bodensee add; recursion-guard bypass; spoofed router |
| WH-D.3 | S6 reentrancy | `AureumFeeRoutingHook` | cross-function / read-only reentrancy on the callback path |
| WH-G.1 | S8 access | `GaugeRegistry` | `onlyGovernance` gates; one-shot setters; the `registerGaugeFromComposition` path |
| WH-G.2 | S9 gauge-gaming | `GaugeEligibility` | 52% floor + the $10k-TVL snapshot; wash-liquidity to trip the gauge floor |
| WH-G.3 | S4 4626 rate | `GaugeEligibility` | the O-D2 / F-12 provenance gate (re-verify post fix-forward, P-D11); admitted-class rate reads |
| WH-G.4 | S8 access | `VaultClassRegistry` | F-08 veto-dedup regression; `proposeVaultClass` / `vetoProposal` bond + threshold |
| WH-G.5 | S5 / S6 | `SwapAndDepositToBodensee` | swap-and-deposit reentrancy; rate-read freshness on the deposit leg |
| WH-H.1 | S1 supply / mint | `EmissionDistributor` + `BodenseeBootstrapChannel` + `AuMMMinterRouter` | cap-budget decrement on every mint path; halving-era boundary; no path mints without charging the cap |
| WH-H.2 | S7 TVL-EMA | `EMASampler` + `TVLOracle` + `EfficiencyOracle` | timed / flash deposits skewing the 60-day EMA; observation cadence; the F-05 / F-07 / F-10 EMA-gate lineage |
| WH-H.3 | S3 rounding | `CCBMultiplier` + `CCBScore` + `CCBShare` | rounding direction favours the protocol; the int / uint signed-delta clamp discipline; div-before-mul |
| WH-I.1 | S9 attribution | `EmissionDistributor` recorder + `AureumFeeRoutingHook` dispatch | recorder-clock attribution; the F-09 router-spoof seat; `effectiveQualBlock` top-up / reset |
| WH-I.2 | S8 recorder gate | `EmissionDistributor` + `VotingWeight` | recorder one-shot binding; gauged-only qualification; the `setGovernanceContract` gate |
| WH-J.1 | S8 access | `MiliariumRegistry` | slot-mutation `onlyGovernance`; the `replaceSlot` / `seedFoundingPool` gates |
| WH-J.2 | S9 roster | `MiliariumRegistry` + `TVLOracle` | roster gaming; cross-seam (d) slot-dedup in the TVL aggregate |
| WH-L.1 | S9 economic | `IncendiaryRegistry` | boost-buy gaming; the 5 gates + 5% haircut + 15%-of-epoch cap; FCFS walk-forward |
| WH-L.2 | S4 / S1 | `IncendiaryRegistry` + `EmissionDistributor` boost leg | 60-day-EMA pricing freshness (F-07); cross-seam (a) boost-mint conservation (L-D25) |

Cross-seam steps (P6.1—P6.4) and the INV harness (P6.5) draw their assertions from this matrix; the `AureumVaultFactory` S11 fork-diff + the S10 deployment surfaces are exercised in P9—P10 (workstream B) and rolled up there.

---
## Sub-step roadmap (P0—P11)

> Execution spine. Workstream A (the white-hat sweep) opens the stage and runs P1—P7 in back-fill order (WH-D→G→H→I→J→L per P-D6), then the cross-seam synthesis + invariant harness + O-D4 fix (P6), then the optional hevm shakeout (P7, fixed there per P-D9). Workstream B (deployment) follows P8—P10; P11 closes. Sweep-before-deploy is deliberate (P-D0): the deploy scripts wire contracts the sweep may patch fix-forward. Each WH pass is a sequence of §8e.1 steps drawn from the matrix above — one surface × one contract (process-doc §1), severity-ordered (§4), each ending in a §9 attestation. Every numbered sub-step is one §8e.1 per §8e.

### P0 — Stage entry: freeze + plan + testnet-doc reconciliation
- **P0.1** — `docs/STAGE_P_NOTES.md` design freeze (P-D0—P-D11 + four amendments). ✅ `6aebebe`.
- **P0.2** — `docs/STAGE_P_PLAN.md` — P0.2a reference half (scope + decisions + WH matrix) + P0.2b roadmap + Completion Log. This sub-step.
- **P0.3** — testnet reconciliation (network-agnostic, the P-D1 amendment): P0.3a `STAGE_P_NOTES.md` P-D1 amend + P0.3b this file's testnet-site rewrite (Opus — design + multi-site) → P0.3c `docs/FINDINGS.md` OQ-15 / OQ-16 + P0.3d `docs/STAGES_OVERVIEW.md` Stage P heading + body (Sonnet — Holesky→network-agnostic strike; the live testnet target deferred to P-bis). O-D3-class repo-side docs fix; no `aumm-site` edit.
- Checkpoint: `grep -n Holesky` returns zero residual hits outside the explicit supersession context; the testnet-name grep shows only the two network-agnostic candidate-pair mentions (no single-testnet commitment phrasing survives); the network-agnostic + P-bis-deferral rationale present.

### P1 — WH-D pass (Stage D fee-routing surface, P-D6)
Execute the WH-D.* matrix rows (S2 / S5 / S6) over `AureumFeeRoutingHook` + `AureumProtocolFeeController`. `*.1` is S2 fee conservation (the crown-jewel fee surface — no mint path here). Fix-forward on `stage-p`, no Stage-D re-tag (P-D5).
- Checkpoint: per-step §9 attestation + coverage roll-up row; any finding → `test/whitehat/F-NN_*.t.sol` PoC + ledger row.

### P2 — WH-G pass (Stage G gauge surface, P-D6)
WH-G.* rows (S8 / S9 / S4 / S5—S6) over `GaugeRegistry`, `GaugeEligibility`, `VaultClassRegistry`, `SwapAndDepositToBodensee`. WH-G.3 re-verifies the O-D2 / F-12 provenance gate on the fix-forward diff — the P-D11 reopened-surface case (a Stage-O change to a Stage-G contract).
- Checkpoint: as P1; explicit attestation that the F-12 fix holds.

### P3 — WH-H pass (Stage H emission + Stage-F CCB engine, P-D6)
WH-H.* rows (S1 / S7 / S3). `*.1` is S1 supply / mint — the highest-value miss (the Orchard analog, process-doc §4), spanning `EmissionDistributor` + `BodenseeBootstrapChannel` + `AuMMMinterRouter`. The CCB engine (`EMASampler` … `CCBShare`) carries S7 / S3.
- Checkpoint: as P1; the S1 attestation pasted with the cited mint lines.

### P4 — WH-I pass (AuMT governance spine, P-D6)
WH-I.* rows (S9 attribution + S8 recorder gate). Per I-D14 there is no `AuMT.sol`; the spine is the `EmissionDistributor` recorder + `AureumFeeRoutingHook` dispatch + `VotingWeight`. Not a re-audit of the host contracts' S1 / S2 (covered by P3 / P1, P-D11) — the lens is attribution integrity only.
- Checkpoint: as P1; confirm the F-09 `trustedRouter` seat holds under WH-I.1.

### P5 — WH-J + WH-L passes (P-D6)
- **P5.1** — WH-J (`MiliariumRegistry`): S8 slot-mutation access + S9 roster gaming (WH-J.1 / WH-J.2).
- **P5.2** — WH-L (`IncendiaryRegistry` + the `EmissionDistributor` boost leg, L-D25): S9 economic + S4 / S1 (WH-L.1 / WH-L.2). The formal WL pass — the SPOT-only F-07 review is superseded (P-D6).
- Checkpoint: as P1, per sub-pass.

### P6 — Cross-seam synthesis + invariant harness + O-D4 fix
- **P6.1—P6.4** — the four named cross-seams (process-doc §2; the matrix tail): (a) channel ↔ distributor mint split, (b) hook ↔ recorder attribution, (c) governance ↔ registry `onlyGovernance`, (d) roster ↔ TVLOracle dedup. One §8e.1 per seam.
- **P6.5** — the INV-2 invariant harness (`test/invariant/` + an independent `ReferenceEmission.sol`): INV-1 / INV-6 (≤ 21M across all mint paths), INV-2 (non-circular emission conservation), INV-3 (50/50 fee split), INV-4 (optional vault solvency). Lands after WH-H (P3) + the cross-seams characterise the mint split (P-D7).
- **P6.6** — O-D4 / P-D8: remove `CCBMultiplier.activateBoost` + the boost machinery (`BOOST_FACTOR`, `GAUGE_BOOST_DURATION_BLOCKS`, `boostExpiryBlock`, `BoostAlreadyActive`) + the now-dead `boostExpiryBlock` read branches on the multiplier hot path. Presumed-deprecate per O-D3 unless WH-H surfaced a re-wire requirement. I13 blast-radius sized at this sub-step's pre-flight; fix-forward, no Stage-F re-tag.
- Checkpoint: invariant gate `runs >= 5000` green (process-doc §10); `forge clean && forge build` (F14) after P6.5 + P6.6; split-form regression (D35 / D36) green.

### P7 — hevm symbolic-execution pass (optional, P-D9)
§8b decision: install hevm (Argot Collective) — presented + approved at this sub-step, not pre-committed at the freeze. Targets S5 (the OQ-1 hook), S7 (the CCB / EMA engine), S8-relabeled (the `AureumGovernanceAuthorizer` timelock / emergency window + the `Vault.setAuthorizer` one-shot migration). Optional pre-audit shakeout, NOT a `stage-p-complete` gate; Act stays Stage Q (P-D9). If install is blocked, attest "hevm deferred to Q" and proceed.
- Checkpoint: hevm proof output (or the deferral attestation); no gate on the close.

### P8 — Testnet token stubs (P-D2, workstream B)
- **P8.1** — Tier A protocol anchors: `svZCHF`, `sUSDS`, `ixEDEL` (NAV / DTF shape), spec-faithful, non-upgradeable, under audit-inheritance discipline.
- **P8.2** — Tier B: one `StubERC4626` template (+ optional waEth-style wrapper variant), N deterministic instances.
- **P8.3** — Tier C: one `StubERC20` template (`*on` equities, BTC wrappers, plain stables, JPYC / tGBP / fBRZ stand-ins).
- **P8.4** — Tier D: `test-stubs/TestnetTokenRegistry.sol` (or a JSON env-map) — pool-config token slot → stub address, mirroring `DeployIxAetheron`'s env injection.
- Out of scope: 04 ixViatica / 07 ixCambio (deferred, O-D6); AuMM + the `src/rate_provider/` RPs deploy REAL, not stubs (P-D2).

### P9 — Deploy scripts + Balancer V3 substrate (workstream B, P-D3)
Network-parameterised (RPC + chain-id from env) full-stack orchestrator (`script/DeployStageP.s.sol` or a chained `DeployStage*` sequence) + the Balancer V3 substrate redeploy on the fork target (Vault + factories + the Router bound to the Aureum Vault, D33 / O-D5). No `--broadcast` (P-D3). The `AureumVaultFactory` S11 fork-diff differential vs upstream + the S10 deployment surface are exercised + attested here.
- Checkpoint: scripts deploy clean on a local / Tenderly fork; the factory differential isolates only the documented ~25-line diff (S11).

### P10 — Integration validation (P-D0b, workstream B)
Tenderly mainnet-fork e2e (`test/fork/StagePIntegration.t.sol` or a devnet run) against REAL mainnet literals — the `STAGES_OVERVIEW.md` Stage P testing matrix: the three proposal types, the gauge-activation workflow, fee routing → Bodensee, CCB scoring over a simulated protocol-month, the composition-challenge dry-run, authorizer migration (`Vault.setAuthorizer`), the halving boundary if feasible. Full split-form regression + `forge coverage` (confirm surfaces REACHED) + `slither .`.
- Checkpoint: e2e green on the real-state fork; regression count logged; coverage confirms the audited surfaces are reached.

### P11 — Stage P close
Two-commit PENDING_P (P-D4): the close commit writes `PENDING_P` (the `STAGES_OVERVIEW.md` master row + this Completion Log; `CLAUDE.md` §11 stays hash-free) → a `*-backfill` commit substitutes the real hash → tag `stage-p-complete` at the backfill commit → ff-merge `stage-p` → `main`. The whitehat ledger coverage roll-up is complete before the tag (process-doc §2). P-bis (the live testnet broadcast + the `aumm-app` frontend) is deferred beyond the tag.
- Checkpoint: the ledger carries zero open findings; the tag sits at the backfill commit on `main`; regression count logged.

---
## Completion Log
| Sub-step | Commit | Status |
| --- | --- | --- |
| P0.1 | `6aebebe` | ✅ docs/STAGE_P_NOTES.md — design freeze (P-D0—P-D11; four amendments) |
| P0.2 | `6f913ac` | ✅ docs/STAGE_P_PLAN.md — plan + WH contract×surface matrix + P0—P11 roadmap (P0.2a + P0.2b) |
| P0.3ab | `ff32941` | ✅ STAGE_P_NOTES.md + STAGE_P_PLAN.md — P-D1 testnet posture amended to network-agnostic; live target Sepolia/Hoodi deferred to P-bis |
| P0.3cd | `4696112` | ✅ FINDINGS.md + STAGES_OVERVIEW.md — Holesky→network-agnostic doc strike (P-D1b); FINDINGS supersession-preserved, STAGES_OVERVIEW live-sequence rewritten |
| P1 (WH-D) | `b96ca6c` | ✅ WH-D Stage-D fee-routing back-fill — S2/S5/S6 on AureumFeeRoutingHook + AureumProtocolFeeController; F-13 (S5 Low, Accepted-risk) logged, S2/S6 NO FINDING; ledger coverage roll-up filled |
| P2 (WH-G) | `fef4815` | ✅ WH-G Stage-G gauge-surface back-fill — S8/S9/S4/S5-S6 on GaugeRegistry + GaugeEligibility + VaultClassRegistry + SwapAndDepositToBodensee; F-14 (S5 High — svZCHF-membership settlement-liveness) Fixed via P-D12 fail-safe + sUSDS generalization (`1af89f3`/`1decb70`/`fdb158c`); F-15 (S9 Low — VaultClassRegistry veto live-denominator, F-06 sibling) Accepted-risk → Stage Q; F-08 + F-12 re-verified holding; F-10 favored-cohort tournament dormant observation escalated 2026-07-02 to F-16 (Medium), wired end-to-end F16a-h and now Fixed (ledger backfill `0ce5003`) — see the F-16 findings-table row; coverage roll-up filled |
| P3 (WH-H) | `08616d7` | ✅ WH-H Stage-H emission + Stage-F CCB engine back-fill — S1/S7/S3 across `EmissionDistributor` + `BodenseeBootstrapChannel` + `AuMMMinterRouter` + the CCB engine (`EMASampler`/`TVLOracle`/`EfficiencyOracle`/`CCBMultiplier`/`CCBScore`/`CCBShare`); all three steps **NO FINDING** — WH-H.1 S1 supply/mint conservation (sole `_mint` cap-gated + one-shot minter, exactly 2 `mintFor` sites, LP/Bodensee AP-sum partition byte-identical, halving-era no off-by-one), WH-H.2 S7 TVL-EMA (F-04/F-05/F-10/F-16 gate lineage re-verified; the CCBMultiplier ungated `tvlEMA` reads are bounded — anti-cyclical, sign-only, clamped [0.75,1.25], × gated-EMA in the sole consumer), WH-H.3 S3 rounding (every mul/div rounds down protocol-favorable; F-16 clamp cap-never-exceeded; no div-before-mul); F-16 (S9 Medium, escalated at P2) the sole pass finding, already Fixed; adjacent obs deferred to P6 (`EmissionDistributor` L263 B-leg-anchor doc-nit; `CCBShare` orphaned library — MasterChef superseded the F-6 normalizer); ledger roll-up CLOSED (rows `9ef5471`/`e9bb218`/`08616d7`) |
