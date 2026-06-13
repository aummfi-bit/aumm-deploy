# Stage L — Notes & Design Freeze

> **Status:** L-D1—L-D9 LOCKED wholesale at L0.1 (this file) from the L0.2 design-freeze Opus beat. Stage L is "Small" (~300 lines, one new contract + one I13-class fix-forward), so it follows the Stage J wholesale-lock precedent rather than Stage K's per-unit deferral. Companion to STAGE_L_PLAN.md (authored next at L0.2-PLAN).
>
> **Last update:** 2026-06-13 — L1.0 pre-flight: L-D10—L-D15 LOCKED (gauge gate, direct Bodensee spot read, `boostIntegral` signature, `AureumTime` epoch helpers, the `_settlePool` boost-delivery leg, EfficiencyOracle F-10 bypass). Next: L1.1 `IIncendiaryRegistry` interface edit.
>
> **Mode:** Opus high per §13 (Stage L entry) — drops to Sonnet for test writing once design is set.
>
> **Audience:** Sagix plus any future Claude session that needs the running log of decisions resolved during Stage L implementation and the incidents caught at audit.

---

## How this file is organized

- Design decisions — L-D1—L-D9 LOCKED wholesale at L0.1 (Stage L is Small; matches the Stage J J-D1—J-D7 wholesale-lock precedent, not Stage K's per-unit deferral). The §12 ambiguity-gate was cleared at the L0.2 freeze beat; any residual typed-domain detail surfaced at a unit pre-flight becomes a new L-D entry.
- Findings (L10 onward) — implementation incidents, numbered from L10 to avoid collision with L-D* (matches C10 / D10 / … / K10).
- Cross-reference convention per CLAUDE.md §5: L-Dn = decision n; Ln (n ≥ 10) = finding n; OQ-N = FINDINGS open question; F-n = formula in `11_formulas.md`; §xxix = aumm-site numbered spec; K-Dn / H-Dn / I-Dn / … = prior-stage decisions; Kn / Hn / In / … = prior-stage findings.

---

## What Stage L builds

The Incendiary Boost (canonical F-2): anyone deposits svZCHF or sUSDS one-sided into der Bodensee in exchange for a 14-day supplementary AuMM emission stream directed at a gauged pool of their choice — funded from the existing fixed block emission (F-7 Step 1 priority skim off the LP tranche), never new inflation. Stage H already wired the *consumption* side: the distributor subtracts `IIncendiaryRegistry.integratedSkim` in its continuous-leg accrual per H-D29, defaulting to `address(0)` (zero skim) until governance binds the registry. Stage L ships the *producer* — the registry that sells boosts, prices them, caps them, and reports both the global skim and the per-pool delivery integral.

---

## Design decisions

| # | Status | Decision | Anchor | Locked at |
| --- | --- | --- | --- | --- |
| L-D1 | LOCKED | Architecture = one new contract `src/incendiary/IncendiaryRegistry.sol` (implements + extends `IIncendiaryRegistry`) + one additive I13-class fix-forward on the tagged `EmissionDistributor` for the per-pool delivery leg. The Stage D `AureumFeeRoutingHook` Incendiary leg (`routeIncendiaryDeposit` / `setIncendiaryModule`) stays dormant — `incendiaryModule` never set, mirroring the dormant governance-deposit leg. | STAGES_OVERVIEW Stage L; FINDINGS L269/L348; H-D29; I13 | L0.1 |
| L-D2 | LOCKED | Deposit path = pay tokens strictly {svZCHF, sUSDS}; tail mirrors `AureumGovernance` — `safeTransferFrom(buyer → BODENSEE_CHANNEL)` then `BODENSEE_CHANNEL.donate(payToken, amount)` (G-D21 allowlist, `AddLiquidityKind.DONATION`, zero-BPT enforced by `BptMintedOnDonation`). Non-refundable; 100% to der Bodensee; no BPT minted anywhere. | F-2; `SwapAndDepositToBodensee.donate` (G-D21); `AureumGovernance.sol:193-199` | L0.1 |
| L-D3 | LOCKED | Phase gate = purchases revert until `block.number > AureumTime.year1EndBlock(GENESIS_BLOCK)`. Matches H-D29's continuous-leg-only skim; H-D26 conservation holds with zero Stage H change. | F-2; F-3; H-D29; `AureumTime.year1EndBlock` (`AureumTime.sol:78`) | L0.1 |
| L-D4 | LOCKED | Pricing = `entitlement_AuMM = value_in_AuMM_at_EMA × 95%`. The 5% is never skimmed and never collected (no treasury — no-creator-fees hard rule); it stays in the distributor's `Remaining` and flows to the other qualified pools via normal CCB/equal-split. Purpose = anti-gaming friction, not protocol capture. Skim = 95% of value. | F-2; user decision 2026-06-13; no-creator-fees hard rule | L0.1 |
| L-D5 | LOCKED | Valuation = the registry's own price EMA of the der Bodensee AuMM/stable rate, two rails (AuMM/svZCHF, AuMM/sUSDS), using `EMASampler` constants verbatim — α = 2/61, one sample per `BLOCKS_PER_DAY`, `ema_new = (2·spot + 59·old)/61`, ~21-day half-life / 60-day horizon. Maturity gate copied from the F-04 fix: `EMA_MATURITY_BLOCKS = 60 × BLOCKS_PER_DAY = 432_000`; immature or unseeded rate ⇒ purchase reverts. Spot rate is never priced. | `EMASampler.sol:42-47`; `VotingWeight.sol:30,136-138` (F-04 fix); user decision 2026-06-13 | L0.1 |
| L-D6 | LOCKED | Cap = aggregate: Σ all boost allocations active in epoch E ≤ 15% × (E's emission integral). Integral form (not `rate × BLOCKS_PER_EPOCH`) because epochs straddle halvings (`BLOCKS_PER_ERA / BLOCKS_PER_EPOCH ≈ 104.29`). One shared 15% bucket all pools draw from — the anti-drought guard for ordinary LPs. | F-2; user decision 2026-06-13; OQ-3 / OQ-5 era/epoch arithmetic | L0.1 |
| L-D7 | LOCKED | Placement = FCFS walk-forward. From the next epoch boundary, allocate `min(remaining entitlement, 15%-bucket capacity left)` per epoch, carry the remainder forward, repeat until exhausted — a boost spans as many consecutive epochs as the cap requires. Per-block stream in an epoch = that epoch's allocation / `BLOCKS_PER_EPOCH`. | F-2; user decision 2026-06-13 | L0.1 |
| L-D8 | LOCKED | Delivery = inside the distributor's allocation, F-7 Step 1/Step 2 ordering. Global accrual subtracts `integratedSkim(from,to)` (wired, H-D29); per-pool settle/claim adds a new leg reading `boostIntegral(pool,from,to)` from the registry (new `IIncendiaryRegistry` method — G16 inheritor enumeration at L pre-flight). Mint stays distributor → `AuMMMinterRouter` (K-D7). Registry invariant `Σ_pools boostIntegral(p,a,b) = integratedSkim(a,b)`. | F-7; H-D26; H-D29; K-D7; I13; G16 | L0.1 |
| L-D9 | LOCKED | Accounting = epoch-bucketed cumulative sums keeping `integratedSkim` and `boostIntegral` O(1) per H-D29; permissionless `crystallize(from,to)` cache-updater outside the read interface; additive per-(epoch,pool) map (stacking allowed — F-2 "one boost per pool per epoch" dropped, queued spec edit); full boost provenance via events + enumerable state per the "track all boosts" requirement. | H-D29 (`IIncendiaryRegistry`); user decision 2026-06-13 | L0.1 |
| L-D10 | LOCKED | Gauge gate — `buyBoost` reverts unless `_gaugeRegistry.isGaugeApproved(pool)` at purchase; a mid-boost gauge revocation does not halt an already-sold stream (epoch buckets immutable once placed; the `_settlePool` boost leg is gauge-status-independent). | F-2 "a gauged pool"; `EmissionDistributor.recordScore` step-1 gauge primitive; user decision 2026-06-13 | L1.0 |
| L-D11 | LOCKED | Spot-rate read = direct der Bodensee 40/30/30 WeightedPool read via `IVaultExplorer.getPoolData(BODENSEE).balancesLiveScaled18` + `WeightedPool.getNormalizedWeights()` — `rate(AuMM/X) = (bal_X / w_X) / (bal_A / w_A)`, both svZCHF and sUSDS rails direct (Q4, no 2-hop). `TVLOracle.quoteSvZCHF(AUMM)` reuse REJECTED (returns 0 — AuMM ∉ `tokenToUnderlying`). | `DeployDerBodensee.s.sol` 40/30/30; `TVLOracle.sol:290` skip-on-zero; user decision 2026-06-13 | L1.0 |
| L-D12 | LOCKED | `boostIntegral(address pool, uint256 from, uint256 to) external view returns (uint256)` — per-pool delivery view mirroring `integratedSkim(uint256,uint256)`; added to `IIncendiaryRegistry` at L1.1. | `IIncendiaryRegistry.sol:41`; L-D8; G16 sweep (sole consumer = `EmissionDistributor`) | L1.0 |
| L-D13 | LOCKED | `AureumTime.epochStartBlock(genesisBlock, epochIndex)` + `epochEndBlock(genesisBlock, epochIndex)` — additive `internal pure` boundary helpers mirroring the `month6EndBlock` / `year1EndBlock` family; `epochIndex` already at `AureumTime.sol:48`. Added at L1.2; no existing signature touched. | `AureumTime.sol:48,62-80`; Q3 | L1.0 |
| L-D14 | LOCKED | Delivery (I13) = per-pool boost leg in `_settlePool` — new `poolBoostCursor[pool]`; `poolAccRewardPerLP[pool] += boostIntegral(pool, cursor+1, block.number).divDown(poolTotalLP[pool])` when `poolTotalLP > 0` (zero-LP stranded per H-D24), guarded by `incendiaryRegistry != address(0)` so the existing 106-test cohort stays no-op. Rides the existing claim / `mintFor` path. Conservation `Σ_pools boostIntegral = integratedSkim ⇒ total = full tranche`. | MasterChef `_settlePool` H-D24; H-D29 address(0)-guard symmetry; I13 sizing; L-D8 | L1.0 |
| L-D15 | LOCKED | Boost emission BYPASSES the EfficiencyOracle F-10 push — the `_settlePool` boost leg does NOT call `_efficiencyOracle.recordEmissions`; purchased directed emission is not CCB/efficiency-earned and must not inflate a pool's F-10 tournament denominator. | F-10 tournament integrity; `_settlePool` H-D23 push; user decision 2026-06-13 | L1.0 |

### L-D1 — Architecture: one contract + one fix-forward — status LOCKED

Stage L ships `src/incendiary/IncendiaryRegistry.sol`, the concrete producer behind the H-D29 forward-dep `IIncendiaryRegistry`. It carries the full registry surface: the purchase entry, the price EMA (L-D5), per-epoch bucket accounting (L-D6 / L-D7 / L-D9), the global `integratedSkim(from,to)` already consumed by the distributor, and a new per-pool `boostIntegral(pool,from,to)` for delivery (L-D8). The only other edit is an additive I13-class fix-forward on the tagged `EmissionDistributor` (per-pool settle/claim reads `boostIntegral`) — its test blast radius is sized at the L pre-flight beat, not at first prompt (the I13 lesson). The Stage D `AureumFeeRoutingHook` Incendiary leg stays dormant (`incendiaryModule` never set), exactly as the governance-deposit leg already does — no Stage D contract is touched.

### L-D2 — Deposit path: donate, no BPT — status LOCKED

Pay tokens are strictly svZCHF or sUSDS — both native der Bodensee constituents, so no swap leg is required. The registry mirrors `AureumGovernance`'s deposit tail (`AureumGovernance.sol:193-199`): pull via `safeTransferFrom(buyer → BODENSEE_CHANNEL)`, then `BODENSEE_CHANNEL.donate(payToken, amount)`. `SwapAndDepositToBodensee.donate` (G-D21) adds one-sided via `AddLiquidityKind.DONATION` and hard-reverts `BptMintedOnDonation` if any BPT would mint — so no BPT exists in this design (a directed epoch-emission is unrelated to any der Bodensee LP position). The registry is added to the channel's `authorizedDonators` allowlist at deploy/wiring. The deposit is non-refundable and 100% to der Bodensee.

### L-D3 — Phase gate: post-Year-1 only — status LOCKED

Purchases revert until `block.number > AureumTime.year1EndBlock(GENESIS_BLOCK)`. H-D29 locked the F-7 Step 1 skim to the distributor's continuous-leg only; a boost sold during the bootstrap or transition phase would route a deposit yet never skim, breaking the H-D26 conservation identity. Gating sales to the continuous phase keeps producer and consumer phase-aligned with zero Stage H change. F-2 / F-3 read as if Incendiary could run earlier; the post-Y1 restriction is an Aureum implementation lock, queued as an aumm-site edit.

### L-D4 — Pricing: 95% entitlement, 5% anti-gaming haircut — status LOCKED

Entitlement `= value_in_AuMM_at_EMA × 95%`, where the AuMM value of the deposit is taken at the EMA rate (L-D5). The 5% is never minted and never collected anywhere (no treasury — the no-creator-fees hard rule) — it simply is not skimmed, so it remains in the distributor's `Remaining` and accrues to the other qualified pools through normal CCB / equal-split. Its sole purpose is anti-gaming friction: a round-trip (dump AuMM → buy boost at the depressed price → buy back) pays the 5% haircut on top of the 60-day-EMA lag, making manipulation unprofitable. Net: the registry's reported skim is 95% of the priced value, and the L-D8 invariant rides that 95% figure.

### L-D5 — Valuation: 60-day price EMA, F-04 maturity gate — status LOCKED

Pricing reads a price EMA the registry maintains itself — the existing `EMASampler` tracks per-pool TVL, not the AuMM/stable rate, so it cannot be reused directly — using `EMASampler`'s constants verbatim: α = 2/61, one sample per `BLOCKS_PER_DAY`, `ema_new = (2·spot + 59·old)/61`, ~21-day half-life / 60-day horizon (`EMASampler.sol:42-47`). Two rails are tracked, AuMM/svZCHF and AuMM/sUSDS, both directly observable from the three-token der Bodensee. The cold-start defense is copied from the whitehat F-04 fix: `EMA_MATURITY_BLOCKS = 60 × BLOCKS_PER_DAY = 432_000`; a rate that has seeded for fewer than 60 days, or never seeded, reverts the purchase (`VotingWeight.sol:30,136-138`). Spot rate is never priced — closing the F-04-class flash-manipulation surface.

### L-D6 — Cap: aggregate 15% of the epoch's emission integral — status LOCKED

The ceiling is on the sum of all boosts active in an epoch, not per pool: Σ allocations in epoch E ≤ 15% × (E's emission integral). Integral form rather than `rate × BLOCKS_PER_EPOCH` because epochs do not divide eras evenly (`BLOCKS_PER_ERA / BLOCKS_PER_EPOCH ≈ 104.29`), so a halving-straddling epoch must be priced across both rates. One shared 15% bucket all pools draw from — the anti-drought guard that keeps at least 85% of every epoch's LP tranche flowing to ordinary LPs.

### L-D7 — Placement: FCFS walk-forward spill — status LOCKED

Boosts fill the shared per-epoch bucket first-come-first-serve. At purchase, starting at the next epoch boundary, the registry walks epochs forward, allocating `min(remaining entitlement, 15%-bucket capacity left)` in each and carrying the remainder forward until exhausted — so a boost spans as many consecutive epochs as the cap requires (a deposit worth 10% of an epoch lands whole; one worth 40% spreads across three). Per-block stream in each epoch = that epoch's allocation / `BLOCKS_PER_EPOCH`. Worked example: boost #1 takes 10% of E; boost #2 takes the remaining 5% in E, then up to 15% in E+1, remainder to E+2; a later buyer gets whatever those leave.

### L-D8 — Delivery: distributor per-pool leg, no new mint channel — status LOCKED

Delivery happens inside the distributor's allocation, honoring F-7 Step 1 / Step 2 ordering: global accrual subtracts `integratedSkim(from,to)` off the LP tranche (wired, H-D29), and the per-pool settle/claim path adds a new leg reading `boostIntegral(pool,from,to)` from the registry over the same interval. The boosted pool's AuMT holders receive the stream through the pool's existing claim machinery; minting stays distributor → `AuMMMinterRouter` (K-D7) — no new mint channel. `boostIntegral` is a new `IIncendiaryRegistry` method, so the L pre-flight beat enumerates inheritors via `grep -rn "is IIncendiaryRegistry"` (G16) before the interface edit. The registry invariant `Σ_pools boostIntegral(p,a,b) = integratedSkim(a,b)` slots into H-D26's `LP_integral + Bodensee_apsum + Incendiary_integral = rate × n` and is unit-tested.

### L-D9 — Accounting: epoch buckets, O(1) skim, additive stacking — status LOCKED

The registry keeps epoch-bucketed cumulative sums so `integratedSkim` and `boostIntegral` stay O(1) regardless of interval size per H-D29, fed by a permissionless `crystallize(from,to)` cache-updater that lives outside the `IIncendiaryRegistry` read surface. The per-(epoch,pool) map is additive: multiple boosts to the same pool in the same epoch stack, subject only to the aggregate L-D6 cap — F-2's literal "one boost per pool per epoch" is dropped (queued aumm-site edit). Full boost provenance is retained via events plus enumerable state, satisfying the "track all boosts acquired" requirement.

### L-D10 — Gauge gate at purchase + mid-boost completion — status LOCKED

Locked at the L1.0 pre-flight. F-2 funds "a gauged pool," so `buyBoost(pool, …)` reverts unless `_gaugeRegistry.isGaugeApproved(pool)` at purchase — the same primitive `EmissionDistributor.recordScore` gates on (step 1). A pool de-gauged mid-boost keeps receiving the already-purchased stream: the entitlement was paid (deposit donated, skim committed) and placed in immutable per-(epoch,pool) buckets, and the `_settlePool` boost leg (L-D14) reads `boostIntegral` without re-checking gauge status. The buyer paid for the full duration, so the stream completes to the pool's LPs regardless of a later revocation — correct, not an exploit (the skim is bounded by the 15% cap and the deposit is non-refundable either way).

### L-D11 — Spot-rate read = direct der Bodensee weighted-pool read — status LOCKED

Locked at L1.0 (Q2 / Q4). der Bodensee is a 40/30/30 WeightedPool (AuMM 40% / sUSDS 30% / svZCHF 30%; `DeployDerBodensee.s.sol`). The registry reads `IVaultExplorer.getPoolData(BODENSEE_POOL).balancesLiveScaled18` + `WeightedPool.getNormalizedWeights()` and computes the weighted-pool spot `rate(AuMM/X) = (bal_X / w_X) / (bal_A / w_A)` for both X = svZCHF and X = sUSDS — both pairs are in the pool, so the sUSDS rail is direct with no 2-hop (Q4). Reusing `TVLOracle.quoteSvZCHF(AUMM, 1e18)` was rejected: it returns 0 for any token absent from the governance-curated `tokenToUnderlying` map (`TVLOracle.sol:290`), and AuMM is never mapped there (the map seeds only stable / pilot tokens). The direct read is self-contained and venue-canonical; it is the per-sample input the L-D5 60-day EMA smooths (raw spot is never priced).

### L-D12 — `boostIntegral` signature — status LOCKED

`boostIntegral(address pool, uint256 from, uint256 to) external view returns (uint256)` — the per-pool delivery counterpart to the existing `integratedSkim(uint256 from, uint256 to)` (`IIncendiaryRegistry.sol:41`), returning the pool's boost allocation over `[from, to]` inclusive in AuMM-wei. Added to `IIncendiaryRegistry` at L1.1; the G16 sweep found the sole consumer is `EmissionDistributor` (+ its four test mock sites), so the interface edit is low-blast.

### L-D13 — `AureumTime` epoch-boundary helpers — status LOCKED

`epochStartBlock(uint256 genesisBlock, uint256 epochIndex)` and `epochEndBlock(uint256 genesisBlock, uint256 epochIndex)` — additive `internal pure` helpers mirroring the existing `month6EndBlock` / `year1EndBlock` boundary family (`AureumTime.sol:62-80`), computing `genesisBlock + epochIndex × BLOCKS_PER_EPOCH` and the inclusive last block. `epochIndex(genesisBlock, blockNumber)` already exists (`AureumTime.sol:48`). The registry's walk-forward placement (L-D7) and the distributor's per-pool boost interval (L-D14) both key on epoch boundaries; named helpers keep the arithmetic testable and consistent. Added at L1.2; no existing `AureumTime` signature is touched.

### L-D14 — Delivery via per-pool boost leg in `_settlePool` (I13) — status LOCKED

Locked at L1.0 after reading the distributor's MasterChef two-tier topology. The skim (`integratedSkim`) is already removed from the global score-distributed tranche by `_lpTrancheIntegral` (H-D29), so the boost cannot ride the score path — it is delivered as a second per-pool leg: a new `mapping(address => uint256) poolBoostCursor` slot, and inside `_settlePool(pool)`, when `incendiaryRegistry != address(0)`, `poolAccRewardPerLP[pool] += boostIntegral(pool, poolBoostCursor[pool] + 1, block.number).divDown(poolTotalLP[pool])` (zero-LP stranded per the H-D24 precedent), then advance the cursor. The boost rides the existing `pendingBalance` → `claim` → `mintRouter.mintFor` path — no new claim surface, no new mint channel. The `incendiaryRegistry != address(0)` guard mirrors the H-D29 skim guard, so every existing `EmissionDistributor` unit test (registry unset) sees the boost leg as a no-op — the I13 blast radius is bounded to additive new tests. Conservation: the score path emits `tranche − skim`, the boost legs emit `Σ_pools boostIntegral = skim`, total = full LP tranche, preserving H-D26 with no over/under-mint against the 21M cap.

### L-D15 — Boost bypasses the EfficiencyOracle F-10 push — status LOCKED

Locked at L1.0 (user decision 2026-06-13). The score-allocation path in `_settlePool` pushes to `_efficiencyOracle.recordEmissions(pool, allocation)` (H-D23), feeding the F-10 capital-efficiency tournament denominator. The L-D14 boost leg does NOT push — purchased, directed emission is not CCB / efficiency-earned, and counting it would let a pool buy a better tournament ranking. The boost lands in `poolAccRewardPerLP[pool]` only; the EfficiencyOracle sees a pool's earned emission, not its purchased boost.

---

## Deferred / carry-forward

- **FINDINGS.md corrections (docs; user-side or a later L sub-step):** L269 / L348 "deposit-anything mechanic" → svZCHF / sUSDS only; L369 / L377 governance/Incendiary "shared swap-and-deposit primitive (the hook)" → the actual route is the Stage G `SwapAndDepositToBodensee.donate` channel (the Stage D hook leg is dormant).
- **aumm-site spec edits (user-side):** F-2 amendments — the 5% anti-gaming haircut, the aggregate 15%-of-epoch cap, the post-Year-1 gate, 60-day-EMA pricing, FCFS walk-forward spill, and dropping "one boost per pool per epoch" in favor of additive stacking. Joins the existing CLAUDE.md §11 aumm-site edit queue.
- **Exact `AureumTime` epoch-boundary helper** (epoch start / end block) confirmed or added at the L1 pre-flight — `epochIndex` exists at `AureumTime.sol:48`; an explicit boundary helper may be an additive lib edit. §12 ambiguity-gate item for L1.

---

## Findings

None yet. L10 onward — implementation incidents caught at audit, numbered from L10 per CLAUDE.md §5.
