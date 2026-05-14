# Stage H — Notes & Design Freeze

> **Status:** Pre-implementation. H-D design surface partially locked (H-D1—H-D5 LOCKED at H0.1; H-D6, H-D7 OPEN — to be locked at H1 and H10 respectively). Companion to STAGE_H_PLAN.md.
>
> **Last update:** 2026-05-14 — H0.2 NOTES scaffold created.
>
> **Mode:** Opus extra-high entry per §13 stage-level defaults (halving math + F12 type-discipline domain). Drops to Opus high after H4. Sonnet beats only for plan-row updates, commit drafts on closed sub-steps, and mechanical Completion Log entries.
>
> **Audience:** Sagix plus any future Claude session that needs the running log of decisions resolved during implementation and the incidents caught at audit.

---

## How this file is organized

- Design decisions during implementation. H-D1—H-D7 mirror STAGE_H_PLAN.md’s H-D Decisions table — H-D1—H-D5 fleshed out as LOCKED at H0.1; H-D6 and H-D7 OPEN as placeholders, to be filled in-place when locked at H1 and H10. Any new decision resolved during implementation (i.e. not pre-seeded in the plan table) gets the next free H-D* number (H-D8 onward) and is recorded as a new entry — not retro-edited into the plan file. Matches the C-D* / D-D* / E-D* / F-D* / G-D* convention.
- Findings (H10 onward). Implementation incidents, drift caught at audit, RPC quirks, env-key surprises, scope-expansion catches, contract-interface gotchas — anything worth a numbered log entry. Numbered from H10 to avoid collision with H-D* planning codes (matches the C10 / D10 / E10 / F10 / G10 pattern).
- Cross-reference convention (per CLAUDE.md §5): H-Dn = planning or implementation decision n; Hn (n ≥ 10) = implementation finding n; OQ-N = open question N from FINDINGS.md; F-n = formula n from `11_formulas.md`; §xxix = section in aummfi-bit/aumm-site numbered spec; G-Dn / F-Dn / E-Dn / D-Dn / C-Dn = prior-stage decisions; Gn / Fn / En / Dn / Cn = prior-stage findings (carry forward across stages).

---

## Design decisions

The H-D rows below replay STAGE_H_PLAN.md:L40-L51 while expanding rationale. Entries H-D1—H-D5 reflect the design-freeze lock asserted at plan scaffold H0.1 (2026-05-14). Entries H-D6 and H-D7 remain deliberately OPEN placeholders until architectural lock (H-D6 expected at Stage H architecture sub-steps around H1) and deployment-timing lock (H-D7 expected at H10 scripting).

### H-D1 — Oracles in-stage as H2a (concrete TVLOracle) + H2b (concrete EfficiencyOracle) — status LOCKED

Concrete oracle implementations arrive as sibling sub-step families inside Stage H: H2a delivers the production-ready `ITVLOracle` implementation; H2b delivers the deterministic on-chain successor to Mock efficiency feeds under `IEfficiencyOracle`. The team rejected a separate pre-mainnet micro-stage devoted solely to oracles because Stage G proved that a single long-lived branch with internal H2a/H2b rows keeps tagging, completion logs, and branch hygiene contiguous without sacrificing scope boundaries. Interfaces are already stabilized—`ITVLOracle` at Stage F milestone F0.2 per F-D11 and FINDINGS-linked G-D25c; `IEfficiencyOracle` at G-D23(ii) with the same FINDINGS scaffolding—plus Mock variants under `test/fork/mocks/`, so substantive remaining work sits in auditable Solidity rather than in interface churn. Embedding that work alongside the emission distributor aligns dependency ordering with GaugeRegistry callers that already anticipate LIVE feeds at Stage H handoff rather than dangling cross-repo promises. Operational risk concentrates in deployment sequencing reviewed once at H2 instead of juggling an extra stage-complete tag prematurely. Canonical TVL-shape discussion remains tracked via FINDINGS OQ-22, while sibling-oracle efficiency semantics tied to GaugeEligibility snapshots remain FINDINGS OQ-G1 complements to G-D23. Primary anchors: F-D11, G-D23, G-D25c, FINDINGS OQ-22, FINDINGS OQ-G1.

### H-D2 — Separate BodenseeBootstrapChannel contract (not inline in distributor) — status LOCKED

F-0 bootstrap emissions funnel through `src/emission/BodenseeBootstrapChannel.sol`, a narrowly scoped ledger that accrues per block toward AuMM earmarked for der Bodensee and exposes a deterministic deposit-and-distribute path marrying one-sided AuMM placements with der Bodensee liquidity while respecting the ancillary F-2 swap-and-buyback machinery. Folding those mechanics into the post-Month-10 emission distributor would interleave unrelated bootstrap accounting with accumulator math meant for gauged pools, increasing failure modes around reserve deltas and treasury routing. Separation mirrors Stage G carve-outs: SwapAndDepositToBodensee stayed outside GaugeRegistry per G-D11, and reserve-delta enforcement remained isolated inside the transient-storage primitive per G-D21. Dedicated contracts keep auditors focused on discrete trust boundaries touching der Bodensee’s bilateral reserves rather than a monolith that evolves every schedule tweak. Operational deploy scripts can instantiate the channel independently of downstream schedule logic, simplifying smoke tests tied solely to Bodensee accounting. Lifecycle clarity—bootstrap rail retires cleanly after Month 10 logic hands off weights to the distributor—reduces regressions tracked through formal reviews. Anchors tying back to rationales: F-0, F-2, G-D11, G-D21.

### H-D3 — F-7 share weights = step function sampled at BLOCKS_PER_EPOCH boundaries — status LOCKED

F-7’s CCB-weighted pool shares recomputed from live score inputs update only once per BLOCKS_PER_EPOCH boundary rather than recomputing on every Ethereum block cited by the textual “every block” reading in `11_formulas.md` F-7. Literal every-block fidelity would amplify gas by forcing synchronized reads across every gauged pool’s TVL lanes and multiplier state on arbitrarily dense swap traffic, collapsing feasibility on mainnet. Instead the refresh cadence aligns with Stage F precedent that pins multiplier evolution to epoch granularity via F-D24, keeping F-8 style multiplier math and F-7 share math co-tenants on BLOCKS_PER_EPOCH (OQ-3 anchors the 100_800 block cadence practitioners already rely on elsewhere). Harmonizing timelines reduces divergence bugs where auditors must reconcile contradictory cadences between boost updates and emitted weights feeding claim math. Divergence from verbatim spec wording stays documented herein until a FINDINGS row records the discrepancy if downstream surfaces ever assume block-perfect weight streams. FINDINGS elevation is warranted if UI dashboards, aggregator heuristics, or governance payloads treat block-frequency F-7 as authoritative; schedule that decision no later than H4 once integration tests illuminate consumer expectations. Anchors referenced during lock: F-7, F-8, F-D24, OQ-3.

### H-D4 — Pull / lazy accrual via MasterChef-style accRewardPerScoreUnit accumulator — status LOCKED

The distributor advances a solitary global `accRewardPerScoreUnit`, FixedPoint-encoded with 18-decimal normalization, ticking forward whenever an emission-bearing block segments accrue protocol mints into the staking ledger. Participant claims dereference snapshots of prior `accRewardPerScoreUnit`, multiplying deltas by persisted pool-specific score totals to reconcile AuMM payouts without iterating every deposit on payout. Matching spec language—“deposit triggers accrual; withdrawal stops it immediately”—means deposit and withdraw mutations refresh per-stake bookkeeping exactly like canonical MasterChef pull semantics instead of spraying push transfers each block across every vault. Attempting naive push accruals would collide with Gas realities once hundreds of gauges exist and would undermine the intra-epoch constancy ensured by H-D3’s stepwise weights. Accumulator bookkeeping must obey F12 and F13 signed-delta safeguards because CCB-derived scores shrink as aggressively as they grow epoch to epoch under tournament losses. Neglecting int/uint discipline while folding negative corrections risks underflow faults identical to Stage F counterexamples that forced explicit signed-add middleware. Operational monitoring therefore treats both boosts and slashes as first-class events feeding the accumulator rather than ephemeral hints. Supporting references: F-7, H-D3, F12, F13.

### H-D5 — Pool-scoped distributor; no IGaugeRegistry enumeration; incremental totalScore aggregate — status LOCKED

Each mutating distributor entry accepts an explicit pool key and consults `IGaugeRegistry.isGaugeApproved(pool)` before mutating aggregates, guaranteeing no hidden enumeration across the upstream registry ABI. GaugeRegistry consciously omits iterators per G-D5 and G-D7, so cloning parallel mirrors inside the emission module would bifurcate truth about which factories remain approved. Instead totalScore evolves via deltas applied alongside every sanctioned score-update path, amortizing bookkeeping to O(1) increments instead of Ω(N) sweeps before claims. Sweep-based reconciliation would resurrect the G16-style mock-registry sweep debt found when interface expansions raced ahead of enumerated consumers in Stage G forks. Liquidity bots and staking front-ends naturally know which pool they target, shifting discovery burdens where context already exists off-chain rather than forcing protocol-level listing APIs. Anchors guarding this rationale: G-D5, G-D7, G16.

### H-D6 — F-1 share denominator (fixed 1/28 vs dynamic 1/N_miliarium) — status OPEN

The literal F-1 text in `11_formulas.md` fixes a 28-way equal-split denominator during Months 0—10 yet only three Stage E pilots (ixEdelweiss, ixAurebit, waEthUSDC) realistically exist ahead of fuller Miliarium rollout, implying 3/28 of that window’s mint could land on live gauges while roughly twenty-five denominators correspond to dormant slots absent further policy. Architectural lock happens around H1 so engineers can weigh honoring the untouched spec fractions (accepting purposeful undermint relative to notional denominator), interpreting 28 purely as eventual max(N,28) scaffolding, or re-deriving N per accrual from live gauge cardinality. Divergences touching canonical numerator copy require a fresh FINDINGS OQ promotion plus coordinated `aumm-site` §ix text once wording departs materially from today's literal. FINDINGS anchors already discussing cadence intersections include OQ-3 plus Stage E pilot inventory notes that contextualize numerator counts cited above.

### H-D7 — AuMM.setMinter() handoff timing (Stage H deploy vs Stage K governance migration) — status OPEN

`IAuMM.setMinter()` remains an irreversible one-shot per Stage C precedent, leaving no recovery if the wired minter mishandles accumulator invariants downstream. Selecting whether emission begins during Stage H’s deployment window versus deferring mint authority activation until Stage K governance migration completes determines whether pre-governance timelines may emit AuMM earmarked toward bootstrap ramps or whether every mint awaits post-handoff governors. Earlier wiring favors faster bootstrap ramps scripted with auditor-reviewed bytecode even while governance ballots remain offline, whereas deferral keeps issuance paused until rehearsals finish cleanly at the governance layer. Locks therefore anchor to the H10 deployment sub-step alongside multisig-dry-run evidence. Cross-references: `IAuMM.setMinter`, Stage K governance handoff.

---

## Architecture

Stage H concentrates new Solidity under `src/emission/`—the emission distributor itself, concrete `TVLOracle` at H2a, concrete `EfficiencyOracle` at H2b, the separate BodenseeBootstrapChannel per H-D2, and the Stage L forward-dependency stub `src/incendiary/IIncendiaryRegistry.sol` slated for H7. AuMM enforces era halving internally through `IAuMM.blockEmissionRate(blockNumber)` returning `GENESIS_RATE >> eraIndex`, which means Stage H consumes (does not reimplement) the halving schedule—and every halving-aware call site in Stage H collapses into a single `IAuMM.blockEmissionRate(block.number)` read. Routine orchestration traverses four schedule phases tied to formulae references: F-0 piecewise bootstrap across Months 0—6 followed by Months 6—10, F-1 equal splitting across twenty-eight nominal Miliarium lanes through Month 10, F-3 linear blending from equal weights toward CCB-weighted shares spanning Months 11—12, and F-7’s full tournament allocations once Year 2 begins. Readers reach backward into Stage F and Stage G solely through immutable, read-only accessors—TVL EMA probes, multiplier reads, roster membership predicates, gauge approval—with mutating workload isolated to accumulator slots inside Stage H contracts plus mediated `IAuMM.mint` calls once deployments satisfy the eventual H-D7 `setMinter` timing gate. Matching H-D5, every guarded entry exposes an explicit `address pool` parameter and predicates on `IGaugeRegistry.isGaugeApproved(pool)`, so enumeration across the upstream registry ABI never enters the distributor design.

### New contracts and interfaces

Files Stage H creates or retrofits. Sub-step landing targets are indicative — exact ordering may shift during execution but the inventory is locked.

| File | Role | Sub-step |
| --- | --- | --- |
| `src/emission/IEmissionDistributor.sol` | Stage H distributor interface — claim entry points for AuMT holders + recordDeposit/recordWithdrawal entry points for the Stage I AuMT contract + accumulator getters | H4 |
| `src/emission/EmissionDistributor.sol` | Pull / lazy-accrual distributor (H-D4) with MasterChef-style `accRewardPerScoreUnit`; pool-scoped state with incremental `totalScore` aggregate (H-D5); epoch-cadence F-7 share weights (H-D3); F-3 blend factor α evolution; F-7 Incendiary-skim integration | H4 + H5 |
| `src/emission/IBodenseeBootstrapChannel.sol` | F-0 bootstrap rail interface — accrual + deposit-and-distribute to der Bodensee, governance one-shot wiring | H3 |
| `src/emission/BodenseeBootstrapChannel.sol` | F-0 piecewise routing (Months 0—6 then 6—10) + one-sided AuMM deposit to der Bodensee via the Vault unlock pattern; audit-isolated per H-D2 mirroring G-D11 / G-D21 precedent | H3 |
| `src/emission/TVLOracle.sol` | Concrete `ITVLOracle` per FINDINGS OQ-22 — svZCHF-denominated TVL via RP-aware unwrap plus constellation-spot averaging | H2a |
| `src/emission/EfficiencyOracle.sol` | Concrete `IEfficiencyOracle` per G-D23 (i) — 3-epoch SMA of `(swap_fee_revenue + yield_fee_revenue) / emissions_received`; consumed by Stage G `GaugeEligibility.computeEpochSnapshot`, not by the H distributor directly | H2b |
| `src/ccb/ICCBMultiplier.sol` | Stage F retrofit interface — Stage F shipped CCBMultiplier without an interface; Stage H needs typed cross-contract access for `getMultiplier(pool)` reads. Robustness backport (RB-005) candidate | H1.x-bis or pre-H micro-stage |
| `src/incendiary/IIncendiaryRegistry.sol` | Stage L forward-dep stub — read-only shape for per-block Incendiary boost claims surface; pre-Stage-L stub returns zero claims | H7 |

### Consumer surface (read-only)

Stage H contracts consume the following from earlier stages — no writes, no state mutation upstream. Forward-dep consumers are listed separately at the end.

- `IAuMM.blockEmissionRate(blockNumber)` (Stage C): per-block AuMM mint budget; internal era halving already applied via `GENESIS_RATE >> eraIndex`. Stage H queries this view — never reimplements halving math.
- `IAuMM.mint(to, amount)` (Stage C): gated by `msg.sender == minter`; Stage H deploys with the `setMinter` one-shot handoff timing locked at H-D7.
- `AureumTime` boundary helpers (Stage C, `src/lib/AureumTime.sol`): `month6EndBlock`, `month10EndBlock`, `month13StartBlock`, `year1EndBlock`, `firstHalvingBlock`, `nthHalvingBlock`, `monthIndex`, `epochIndex`, `eraIndex` — all in place; Stage H phase-boundary checks reduce to library calls against the genesis-block immutable.
- `IMiliariumRegistry.isMiliarium(pool)` plus pool enumeration (Stage F per F-D9; concrete implementation lives at Stage J): identifies the F-1 / F-3 equal-split slots. Pre-Stage-J the placeholder returns `false` for every pool, so F-1 / F-3 mints exclude all pools until Stage J's registry is wired in.
- `IGaugeRegistry.isGaugeApproved(pool)` (Stage G per G-D16a, retained ABI from pre-G-D16a callers): per-call gate on every distributor entry point per H-D5; no enumeration consumed — pool-scoped is the design.
- `IEMASampler.tvlEMA(pool)` (Stage F per F-D5 plus OQ-5a-bis): per-day-sampled svZCHF-denominated TVL EMA with α = 2/61; `TVL_EMA60` input to F-7 Step 3 score.
- `CCBMultiplier.getMultiplier(pool)` (Stage F per OQ-23): per-pool multiplier `CCB_mult` input to F-7 Step 3 score; the 90-day boost gate (F-D17) is deprecated at G-D13, so Stage H consumes the returned value as a plain multiplier without special-casing the boost window.
- `CCBShare.shares(uint256[])` (Stage F per F-D10): F-6 share normalization library — converts per-pool scores into a FixedPoint share vector summing to approximately `FixedPoint.ONE` (modulo `divDown` floor rounding); Stage H feeds Step 3 scores into this lib to obtain Step 4 shares.

`IIncendiaryRegistry.activeBoostClaims(pool, block)` (forward-dep stub at H7): drives F-7 Step 1 Incendiary skim — Stage H ships a zero-claim stub interface at H7 to keep distributor compile-targets stable; Stage L lands the concrete registry that returns nonzero claim amounts per active boost.

### Schedules by phase

Per-block routing rules, organised by phase. Block ranges are inclusive of the lower bound; upper-bound semantics follow `AureumTime` boundary-helper conventions (`monthNEndBlock` returns the last block of month N — see `src/lib/AureumTime.sol`). Halving (era) cadence is orthogonal to phase and applies multiplicatively at every era boundary.

| Phase | Block range | Routing rule | Inputs consumed |
| --- | --- | --- | --- |
| Bootstrap A (F-0 + F-1) | [genesisBlock, month6EndBlock] — Months 0—6 | F-0 piecewise: `bodensee_share(block) = 0.80 − 0.30 × t1` where `t1 = (block − genesisBlock) / (month6EndBlock − genesisBlock)` (linear 80% → 50% as `t1` runs 0 → 1); `lp_share = 1 − bodensee_share`; F-1 equal-split: `emission_to_pool_i(block) = lp_share × block_emission × (1/28)`. Pre-N=28 the `(28 − N)/28` LP-tranche fraction is unminted per H-D6 lock | `IAuMM.blockEmissionRate`, `IMiliariumRegistry` enumeration, `AureumTime.month6EndBlock` |
| Bootstrap B (F-0 + F-1) | (month6EndBlock, month10EndBlock] — Months 6—10 | F-0 piecewise: `bodensee_share(block) = 0.50 − 0.50 × t2` where `t2 = (block − month6EndBlock) / (month10EndBlock − month6EndBlock)` (linear 50% → 0% as `t2` runs 0 → 1); F-1 equal-split unchanged | `IAuMM.blockEmissionRate`, `IMiliariumRegistry` enumeration, `AureumTime.month6EndBlock`, `AureumTime.month10EndBlock` |
| Transition (F-3) | (month10EndBlock, year1EndBlock] — Months 11—12 | F-0: `bodensee_share = 0` permanently; F-3 blend: `share_i(block) = (1 − α(block)) × (1/28) + α(block) × CCB_share_i(block)`; α(block) linear, 0 at the first block of Month 11 and 1 at `year1EndBlock` | `IAuMM.blockEmissionRate`, `IMiliariumRegistry`, `IEMASampler.tvlEMA`, `CCBMultiplier.getMultiplier`, `CCBShare.shares`, `AureumTime.month10EndBlock`, `AureumTime.year1EndBlock` |
| Tournament (F-7) | (year1EndBlock, ∞) — Year 2 onward | F-7 full sequence: EMA update (per-day per Stage F OQ-5a-bis) → Incendiary skim first (`Remaining = block_emission − Incendiary_total`) → CCB scoring `Score(pool_i) = TVL_EMA60(pool_i) × CCB_mult(pool_i)` → share computation `CCB_share(pool_i) = Remaining × Score(pool_i) / Σ Score(eligible)` via `CCBShare.shares` → `Total = CCB_share + Incendiary_claim`. F-7 share weights refresh per `BLOCKS_PER_EPOCH` (H-D3 deviation from spec literal `every block` — locked) | All Stage F consumer interfaces above + `IGaugeRegistry.isGaugeApproved` for eligibility + `IIncendiaryRegistry.activeBoostClaims` once Stage L is live |
| Halving (orthogonal — every era) | Every `BLOCKS_PER_ERA = 10_512_000` blocks since genesis (firstHalvingBlock, secondHalvingBlock, …) | `IAuMM.blockEmissionRate(block) = GENESIS_RATE >> eraIndex`; halves the per-block budget independent of phase. Era 0 rate = `1e18` (1 AuMM/block); Era 1 rate = `0.5e18`; Era N rate = `1e18 >> N`. Stage H consumes `blockEmissionRate` per call and never special-cases the era boundary — the halving is multiplicative on every routing rule above | `IAuMM.blockEmissionRate`, `AureumTime.eraIndex`, `AureumTime.nthHalvingBlock` |

---

## Findings queue

Entries labeled H10+ accumulate once Stage H exits pure documentation scaffolding and Solidity surfaces stabilize; numbering stays decoupled from H-D planners per the conventions above until incidents surface.

(empty)

---

## Open questions

Documented ambiguity here disappears only after translation into FINDINGS.md rows whenever resolution carries protocol-wide implication; until then NOTES remain provisional scratch space.

- H-D3 F-7 epoch-discretisation — H-D3 documents the design choice; spec-side every-block literal may warrant a new OQ-N row in FINDINGS.md if material to any consumer surface; defer promotion until H4 confirms test exposure.
- H-D6 F-1 share denominator — locked at H1; if resolution diverges from the 1/28 spec literal, promote to a new OQ-N row in FINDINGS.md (canonical-spec deviation requires aumm-site §ix prose-amendment carry-forward).
