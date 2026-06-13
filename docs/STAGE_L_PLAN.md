# Stage L — Plan & Sub-Step Roadmap

> **Status:** L0.1 NOTES design freeze (L-D1—L-D9 LOCKED) landed at `cd58d22` on `stage-l`. This file (L0.2-PLAN) lays out the L0—L9 sub-step roadmap. Implementation not yet begun — L0.3 (`CLAUDE.md` §11 refresh) then the L1 interface/pre-flight beat are next. Companion to STAGE_L_NOTES.md.
>
> **Last update:** 2026-06-13 — L2.1 pre-flight: L-D16—L-D17 LOCKED in NOTES (`3d4b7cb`); mirrored here (Decisions + roadmap L2.1a/b split + crystallize-cache→L5.3). Next: L2.1a `IncendiaryRegistry` compiling skeleton.
>
> **Mode:** Opus high per §13 (Stage L entry) for the L1 interface/pre-flight beat and the registry design beats (L2—L7 — the EMA spot-read, the emission-integral cap, the FCFS walk-forward, and the `EmissionDistributor` I13 delivery leg are the load-bearing surfaces), dropping to Sonnet for test writing (L8) and plan-row housekeeping once each unit's design is set.
>
> **Audience:** Sagix plus any future Claude session that needs the operational roadmap for Stage L sub-step execution. NOTES (STAGE_L_NOTES.md) is the running design-decision log; this file is the sub-step sequence + Completion Log + grep-verifiable checkpoint catalog.

---

## Stage scope

Stage L ships the Incendiary Boost producer (canonical F-2): a registry that sells 14-day directed AuMM emission boosts, funded by skimming the existing fixed block emission (F-7 Step 1) rather than minting new supply. A buyer deposits svZCHF or sUSDS one-sided into der Bodensee and receives, for a gauged pool of their choice, a supplementary per-block emission stream over one or more epochs. The producer side is entirely new; the consumer side already exists — Stage H wired the distributor to subtract `IIncendiaryRegistry.integratedSkim` in its continuous-leg accrual (H-D29), defaulting to `address(0)` (zero skim) until governance binds the registry. The load-bearing engineering surfaces are (1) the manipulation-resistant valuation — a 60-day price EMA mirroring the whitehat F-04 fix (L-D5); (2) the aggregate 15%-of-epoch cap on a shared bucket with FCFS walk-forward spill (L-D6 / L-D7); and (3) the per-pool delivery leg — an additive I13-class fix-forward on the tagged `EmissionDistributor` reading a new `boostIntegral(pool, from, to)` view (L-D8), preserving the H-D26 conservation invariant.

### Surfaces produced at Stage L

| File | Status | Sub-step | LOC estimate |
| --- | --- | --- | --- |
| `src/incendiary/IIncendiaryRegistry.sol` | EDIT (+`boostIntegral`) | L1.1 | +~12 |
| `src/lib/AureumTime.sol` | EDIT? (epoch-boundary helper; L1.0 §12 gate) | L1.2 | +~10 |
| `src/incendiary/IncendiaryRegistry.sol` | NEW | L2—L6 | ~340 |
| `src/emission/EmissionDistributor.sol` | EDIT (I13 per-pool boost leg) | L7.1 | +~35 |
| `test/unit/IncendiaryRegistry.t.sol` | NEW | L8.1—L8.4 | ~360 |
| `test/unit/EmissionDistributor.t.sol` | EDIT (delivery + invariant tests) | L8.5 | +~90 |
| `test/fork/StageLIntegration.t.sol` | NEW | L8.6 | ~190 |
| `script/DeployStageL.s.sol` | NEW | L9.1 | ~75 |
| `test/fork/DeployStageL.t.sol` | NEW | L9.2 | ~110 |

### Surfaces NOT produced at Stage L

- No new mint channel — minting stays on the K-D7 `AuMMMinterRouter`; the boost leg rides the distributor's existing `mintFor` call (L-D8).
- No `AureumFeeRoutingHook` edit — the Stage D Incendiary leg (`routeIncendiaryDeposit` / `setIncendiaryModule`) stays dormant (L-D1); deposits route via the Stage G `SwapAndDepositToBodensee.donate` channel (L-D2).
- No `stage-h-complete` re-tag — the `EmissionDistributor` edit is an I13-class fix-forward landing on `stage-l`.
- No `FINDINGS.md` or aumm-site spec edits — queued in the NOTES Deferred section, not applied here.

---

## Decisions

Mirror of STAGE_L_NOTES.md Decisions table (L-D1—L-D9 LOCKED wholesale at L0.1; L-D10—L-D15 LOCKED at L1.0 pre-flight; L-D16—L-D17 LOCKED at L2.1 pre-flight). See NOTES for full bodies.

| # | Status | Decision (summary) | Locked at |
| --- | --- | --- | --- |
| L-D1 | LOCKED | One new `src/incendiary/IncendiaryRegistry.sol` + additive I13 fix-forward on `EmissionDistributor`; Stage D hook Incendiary leg stays dormant. | L0.1 |
| L-D2 | LOCKED | Deposit {svZCHF, sUSDS} → `safeTransferFrom(buyer → BODENSEE_CHANNEL)` + `BODENSEE_CHANNEL.donate` (G-D21, `DONATION`, zero-BPT); non-refundable. | L0.1 |
| L-D3 | LOCKED | Purchases revert until `block.number > AureumTime.year1EndBlock(GENESIS_BLOCK)` (continuous-phase only, H-D29-aligned). | L0.1 |
| L-D4 | LOCKED | `entitlement = value_in_AuMM_at_EMA × 95%`; the 5% is never skimmed (anti-gaming friction, stays in `Remaining` for other pools). | L0.1 |
| L-D5 | LOCKED | Own 60-day price EMA (two rails), `EMASampler` constants verbatim; `EMA_MATURITY_BLOCKS = 432_000` maturity gate; spot never priced. | L0.1 |
| L-D6 | LOCKED | Aggregate cap: Σ boosts in epoch E ≤ 15% × (E's emission integral); shared bucket; anti-drought. | L0.1 |
| L-D7 | LOCKED | FCFS walk-forward spill across consecutive epochs; per-block stream = epoch allocation / `BLOCKS_PER_EPOCH`. | L0.1 |
| L-D8 | LOCKED | Delivery in distributor allocation (F-7 Step 1/Step 2): global `integratedSkim` + per-pool `boostIntegral`; invariant `Σ_pools boostIntegral = integratedSkim`. | L0.1 |
| L-D9 | LOCKED | Epoch-bucketed cumulative sums (O(1) views); permissionless `crystallize`; additive per-(epoch,pool) map (stacking); full provenance. | L0.1 |
| L-D10 | LOCKED | `buyBoost` reverts unless `_gaugeRegistry.isGaugeApproved(pool)` at purchase; mid-boost gauge revocation does not halt already-sold stream (epoch buckets immutable once placed). | L1.0 |
| L-D11 | LOCKED | Spot-rate = direct Bodensee `balancesLiveScaled18` + `getNormalizedWeights()`; both svZCHF and sUSDS rails direct (no 2-hop); `TVLOracle.quoteSvZCHF` rejected (returns 0 for unmapped AuMM). | L1.0 |
| L-D12 | LOCKED | `boostIntegral(address pool, uint256 from, uint256 to) external view returns (uint256)` — per-pool delivery view; added to `IIncendiaryRegistry` at L1.1; G16 sweep: zero inheritors, four `integratedSkim`-selector mocks unaffected. | L1.0 |
| L-D13 | LOCKED | `AureumTime.epochStartBlock(genesisBlock, epochIndex_)` + `epochEndBlock(genesisBlock, epochIndex_)` — additive `internal pure` helpers; params `epochIndex_` (trailing underscore avoids G15-class shadow of `epochIndex()` function). Added at L1.2. | L1.0 |
| L-D14 | LOCKED | `_settlePool` boost leg — new `poolBoostCursor[pool]`; `poolAccRewardPerLP[pool] += boostIntegral(pool, cursor+1, block.number).divDown(poolTotalLP[pool])` when `poolTotalLP > 0`; guard `incendiaryRegistry != address(0)` keeps 106-test cohort no-op. | L1.0 |
| L-D15 | LOCKED | `_settlePool` boost leg does NOT call `_efficiencyOracle.recordEmissions` — purchased emission must not inflate the F-10 tournament denominator. | L1.0 |
| L-D16 | LOCKED | Immutable set = 8 (PLAN's 7 + `VAULT_EXPLORER`, the I12 gap L-D11 consumes): `SwapAndDepositToBodensee BODENSEE_CHANNEL`, `address BODENSEE_POOL`, `IVaultExplorer VAULT_EXPLORER`, `IAuMM AUMM`, `IERC20 SVZCHF`, `IERC20 SUSDS`, `IGaugeRegistry GAUGE_REGISTRY`, `uint256 GENESIS_BLOCK`. `AUMM`=`IAuMM` (`blockEmissionRate` feeds the L-D6 cap). Constructor wires all + ZeroAddress-guards the 7 address-bearing args. | L2.1 |
| L-D17 | LOCKED | Storage: `RailEMA {ema, lastSampleBlock, seedBlock}` in `mapping(address => RailEMA) railEMA`; `epochSkimAllocated[epoch]` (15% bucket); `epochPoolSkim[epoch][pool]` (additive). Crystallize cumulative-cache slots deferred L2.1→L5.3 (§12 design-before-materialize; I12). L2.1 split: L2.1a skeleton (imports+8 immutables+constructor+stub views `return 0`), L2.1b constants+settled storage (errors/events deferred to L4/L5). | L2.1 |
| L-D18 | LOCKED | `_spotRate(payToken)` internal view; identity-match `iA`/`iX` on `getPoolData(BODENSEE_POOL).tokens` (address-sorted); spot = `(bal_X·w_A).divDown(bal_A·w_X)` on `balancesLiveScaled18` + live `getNormalizedWeights()` → 18-dec X-per-AuMM (stable-per-AuMM, L-D17); reverts `TokenNotInPool`/`ZeroSpotBalance`; feeds L3.2 EMA only. | L3.1 |

---

## Pre-flight checklist

- [x] `main` at `stage-k-whitehat-complete` (`7f98cc2`); `stage-l` branched and at `cd58d22` (L0.1 NOTES).
- [x] STAGE_L_NOTES.md design freeze L-D1—L-D9 LOCKED at L0.1 (`cd58d22`).
- [x] (L1.0 pre-flight, §12) `boostIntegral(address pool, uint256 from, uint256 to) → uint256` signature locked + G16 inheritor sweep — RESOLVED → L-D12. Zero inheritors (producer not yet built); four `integratedSkim.selector` mocks in `EmissionDistributor.t.sol` unaffected. L1.1 is zero-blast.
- [x] (L1.0 pre-flight, §12) `AureumTime` epoch-boundary helper decision — RESOLVED → L-D13. Named helper selected (additive `internal pure`); params `epochIndex_` (G15-class shadow avoidance). Lands at L1.2.
- [x] (L1.0 pre-flight, §12) der Bodensee spot-rate read mechanism — RESOLVED → L-D11. Direct `balancesLiveScaled18` + `getNormalizedWeights()` for both rails; `TVLOracle.quoteSvZCHF` rejected.
- [x] (L1.0 pre-flight) `EmissionDistributor` I13 blast-radius sizing — RESOLVED → L-D14. 106-test cohort stays no-op via `incendiaryRegistry != address(0)` guard; new tests at L8.5 are additive only.
- [ ] (resolves L8) Stage L unit cohort green — `test/unit/IncendiaryRegistry.t.sol` + `EmissionDistributor.t.sol` delivery tests.
- [ ] (resolves L8) `StageLIntegration` fork green — buy → donate → skim → per-pool delivery + conservation invariant.
- [ ] (resolves L9) `DeployStageL` fork green.
- [ ] (resolves L9) full split-form regression (D35 / D36) + `stage-l → main` ff-merge + `stage-l-complete` tag + push.

---

## Sub-step roadmap

### L0 — Stage entry (3 sub-steps)

- **L0.1** (DONE — `cd58d22`) `docs/STAGE_L_NOTES.md` — Stage L design freeze (L-D1—L-D9 LOCKED). Cursor §8e.1.
- **L0.2-PLAN** (THIS COMMIT) `docs/STAGE_L_PLAN.md` — roadmap + Decisions mirror + Pre-flight checklist + Completion log + Open questions. Cursor §8e.1.
- **L0.3** `CLAUDE.md` §11 — Stage K→L resume refresh: Stage L in progress, resume anchor (L0 done, L1 next), Stage L entry mode. Cursor §8e.1.

### L1 — Interface + lib pre-flight (per L-D1 / L-D8; §12 gates)

- **L1.0** (DONE — L-D10—L-D15 LOCKED in NOTES + mirrored here) lock `boostIntegral` signature, G16 sweep (zero inheritors), `AureumTime` boundary helper (L-D13 named helper + `epochIndex_`), Bodensee spot-rate (L-D11 direct read), I13 blast-radius (L-D14 106-test cohort no-op). Opus pre-flight beat 2026-06-13.
- **L1.1** `src/incendiary/IIncendiaryRegistry.sol` — add `boostIntegral(pool, from, to)` (the per-pool delivery view); update every inheritor/mock the G16 sweep found in the same beat. Cursor §8e.1.
- **L1.2** `src/lib/AureumTime.sol` — add the epoch-boundary helper if L1.0 selects the named-helper option (additive `internal pure`, no existing signature touched). Cursor §8e.1. (Skipped if L1.0 selects inline.)

### L2 — `IncendiaryRegistry` scaffold (per L-D1 / L-D9)

- **L2.1a** `src/incendiary/IncendiaryRegistry.sol` — compiling skeleton (L-D16): SPDX, `pragma ^0.8.26`, imports, `contract IncendiaryRegistry is IIncendiaryRegistry`, the 8 immutables (`SwapAndDepositToBodensee BODENSEE_CHANNEL`, `address BODENSEE_POOL`, `IVaultExplorer VAULT_EXPLORER`, `IAuMM AUMM`, `IERC20 SVZCHF`, `IERC20 SUSDS`, `IGaugeRegistry GAUGE_REGISTRY`, `uint256 GENESIS_BLOCK`), the constructor (wires all + ZeroAddress-guards the 7 address-bearing args), and `integratedSkim` / `boostIntegral` stubbed `return 0` (concrete + deployable, H-D21 stub precedent). Cursor §8e.1.
- **L2.1b** `src/incendiary/IncendiaryRegistry.sol` — constants (EMA α 2/61, `EMA_MATURITY_BLOCKS = 432_000`, `BOOST_CAP_BPS = 1_500`, `HAIRCUT_BPS = 500`) + settled storage (L-D17: `RailEMA {ema, lastSampleBlock, seedBlock}` in `mapping(address => RailEMA) railEMA`; `epochSkimAllocated[epoch]`; `epochPoolSkim[epoch][pool]`). Errors (beyond `ZeroAddress`) + events deferred to their L4/L5 emit/revert sites (§12 — field sets not settled until purchase/placement logic). Crystallize cumulative-cache slots NOT here — deferred to L5.3 (L-D17). Cursor §8e.1.

### L3 — Price EMA (per L-D5)

- **L3.1** spot-rate read — derive AuMM/svZCHF and AuMM/sUSDS from der Bodensee per the L1.0 mechanism. Cursor §8e.1.
- **L3.2** EMA update + daily-sample cadence + first-seed + `EMA_MATURITY_BLOCKS` maturity gate (immature/unseeded ⇒ revert). Cursor §8e.1.

### L4 — Purchase entry + valuation (per L-D2 / L-D3 / L-D4)

- **L4.1** `buyBoost(pool, payToken, amount)` gates — post-Y1 (L-D3), token ∈ {svZCHF, sUSDS} (L-D2), target pool gauge-approved (Open question Q1), EMA mature (L-D5), `amount > 0` — then valuation `value_in_AuMM_at_EMA × 95%` (L-D4). Cursor §8e.1.
- **L4.2** deposit routing — `safeTransferFrom(buyer → BODENSEE_CHANNEL)` then `BODENSEE_CHANNEL.donate(payToken, amount)` (L-D2); then placement call. Cursor §8e.1.

### L5 — Placement + accounting + crystallize (per L-D6 / L-D7 / L-D9)

- **L5.1** epoch-emission-integral basis + 15% aggregate cap computation (integral form per L-D6). Cursor §8e.1.
- **L5.2** FCFS walk-forward placement into the per-(epoch,pool) additive buckets + per-epoch aggregate bucket (L-D7); per-block stream = allocation / `BLOCKS_PER_EPOCH`. Cursor §8e.1.
- **L5.3** permissionless `crystallize(from, to)` cumulative-sum cache updater (L-D9) + its storage slots deferred from L2.1 (L-D17: the global + per-pool epoch-boundary prefix-sum maps and the crystallize cursor — designed with the O(1) algorithm here, not guessed at scaffold), outside the `IIncendiaryRegistry` read surface. Cursor §8e.1.

### L6 — Views (per L-D8 / L-D9)

- **L6.1** `integratedSkim(from, to)` — O(1) over the cumulative buckets (the H-D29 surface the distributor already consumes). Cursor §8e.1.
- **L6.2** `boostIntegral(pool, from, to)` — O(1) per-pool view + close-of-family (`forge clean && forge build` per F14). Cursor §8e.1.

### L7 — `EmissionDistributor` fix-forward (per L-D8; I13)

- **L7.1** per-pool settle/claim adds the `boostIntegral` leg (reads the registry, adds to the pool's score-based share, mints via the existing K-D7 router) — sized at L1.0; invariant `Σ_pools boostIntegral = integratedSkim` honored. Cursor §8e.1.

### L8 — Tests (6 sub-steps)

- **L8.1** `test/unit/IncendiaryRegistry.t.sol` harness + EMA tests (seed, daily sample, maturity gate, two rails). Cursor §8e.1.
- **L8.2** purchase/valuation/gate tests (post-Y1, token whitelist, 95% haircut, donate routing, gauge gate). Cursor §8e.1.
- **L8.3** placement/cap/spill tests (15% aggregate cap, FCFS walk-forward, multi-epoch spill, stacking). Cursor §8e.1.
- **L8.4** views + `crystallize` tests (`integratedSkim` / `boostIntegral` O(1), conservation `Σ_pools = global`). Cursor §8e.1.
- **L8.5** `test/unit/EmissionDistributor.t.sol` delivery tests (I13 blast-radius cohort — per-pool boost leg, mock registry). Cursor §8e.1.
- **L8.6** `test/fork/StageLIntegration.t.sol` — end-to-end: buy → donate → skim → per-pool delivery + H-D26 conservation (split-form per D35, `--threads 1` per D36). Cursor §8e.1.

### L9 — Deploy + close-of-stage (5 sub-steps)

- **L9.1** `script/DeployStageL.s.sol` — deploy `IncendiaryRegistry`, add it to the channel `authorizedDonators` allowlist, and call `distributor.setIncendiaryRegistry(registry)` (governance slot still deployer-held). Cursor §8e.1.
- **L9.2** `test/fork/DeployStageL.t.sol` — deploy-script fork test (state assertions + skim/delivery smoke). Cursor §8e.1.
- **L9.3** full split-form regression per D35/D36 — record actual pass counts. User runs in terminal.
- **L9.4** `CLAUDE.md` §11 Stage L COMPLETE refresh + checklist flips + next-stage entry mode. Cursor §8e.1.
- **L9.5** Stage close — ff-merge `stage-l → main` + `stage-l-complete` tag + snapshot push. User runs in terminal.

---

## Completion log

| Sub-step | Commit | Summary |
| --- | --- | --- |
| L0.1 | `cd58d22` | `docs/STAGE_L_NOTES.md` — Stage L Incendiary Boost design freeze (L-D1—L-D9 LOCKED) |
| L0.2-PLAN | `7bcadd1` | `docs/STAGE_L_PLAN.md` — sub-step roadmap (L0—L9) + Decisions mirror + Pre-flight checklist + Completion log + Open questions |
| L0.3 | `dc4a594` | `CLAUDE.md` §11 — Stage L L0-entry resume refresh (resume anchor L1.0; IncendiaryBoost→IncendiaryRegistry rename) |
| L1.0 | `0946cec` | `docs/STAGE_L_NOTES.md` + `docs/STAGE_L_PLAN.md` — L1.0 Opus pre-flight: L-D10—L-D15 LOCKED (gauge gate, Bodensee spot read, boostIntegral sig, AureumTime helpers, _settlePool boost leg, F-10 bypass) |
| L1.1 | `edabe8a` | `src/incendiary/IIncendiaryRegistry.sol` — add `boostIntegral(pool, from, to)` per-pool delivery view (L-D12) |
| L1.2 | `2274ad1` | `src/lib/AureumTime.sol` — add `epochStartBlock` / `epochEndBlock` epoch-boundary helpers (L-D13) |
| L2.0-pre | `3d4b7cb` + `93a95e2` | `docs/STAGE_L_NOTES.md` + `docs/STAGE_L_PLAN.md` — L-D16—L-D17 LOCKED (8-immutable set incl. VAULT_EXPLORER I12-gap, AUMM=IAuMM; RailEMA storage + crystallize-cache→L5.3 + L2.1a/b split) |
| L2.1a | `5dca67c` | `src/incendiary/IncendiaryRegistry.sol` — compiling skeleton (8 immutables + constructor + stubbed IIncendiaryRegistry views) per L-D16 |
| L2.1b | `ca5a48b` | `src/incendiary/IncendiaryRegistry.sol` — L-D17 constants (5) + settled storage (RailEMA + 3 maps); errors/events deferred to L4/L5 |

---

## Open questions

- **Q1 — target pool gauge gate.** RESOLVED → L-D10 (L1.0). `buyBoost` reverts if `_gaugeRegistry.isGaugeApproved(pool)` fails at purchase; mid-boost revocation leaves already-sold stream intact (immutable epoch buckets).
- **Q2 — Bodensee spot-rate read.** RESOLVED → L-D11 (L1.0). Direct `IVaultExplorer.getPoolData(BODENSEE_POOL).balancesLiveScaled18` + `WeightedPool.getNormalizedWeights()`; `TVLOracle.quoteSvZCHF` rejected (returns 0 for unmapped AuMM).
- **Q3 — `AureumTime` epoch-boundary helper.** RESOLVED → L-D13 (L1.0). Named helper selected; additive `internal pure`; params `epochIndex_` (G15-class shadow avoidance). Lands at L1.2.
- **Q4 — sUSDS valuation path.** RESOLVED → L-D11 (L1.0). sUSDS rail prices directly off Bodensee (no 2-hop); both AuMM/sUSDS and AuMM/svZCHF pairs are in the 40/30/30 pool.

---

## Anchors

- STAGE_L_NOTES.md — L-D bodies (L-D1—L-D9) + Deferred / carry-forward + Findings queue.
- STAGES_OVERVIEW.md Stage L; FINDINGS.md L269 / L348 / L369 / L377 (Incendiary scope rows, correction queued) + L499 / L522 / L538 (epoch/duration constants).
- `src/incendiary/IIncendiaryRegistry.sol` — H-D29 forward-dep (integratedSkim); `EmissionDistributor.sol:277,318,330` — continuous-leg skim consumer (L-D8 constraint).
- `src/gauge/SwapAndDepositToBodensee.sol` `donate` (G-D21) + `AureumGovernance.sol:193-199` — deposit-tail precedent (L-D2).
- `src/ccb/EMASampler.sol:42-47` + `src/governance/VotingWeight.sol:30,136-138` — EMA constants + F-04 maturity-gate precedent (L-D5).
- `11_formulas.md` F-2 / F-7 / F-3; `AureumTime.sol:48,78` — `epochIndex` / `year1EndBlock`.
