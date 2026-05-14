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

## Findings queue

Entries labeled H10+ accumulate once Stage H exits pure documentation scaffolding and Solidity surfaces stabilize; numbering stays decoupled from H-D planners per the conventions above until incidents surface.

(empty)

---

## Open questions

Documented ambiguity here disappears only after translation into FINDINGS.md rows whenever resolution carries protocol-wide implication; until then NOTES remain provisional scratch space.

- H-D3 F-7 epoch-discretisation — H-D3 documents the design choice; spec-side every-block literal may warrant a new OQ-N row in FINDINGS.md if material to any consumer surface; defer promotion until H4 confirms test exposure.
- H-D6 F-1 share denominator — locked at H1; if resolution diverges from the 1/28 spec literal, promote to a new OQ-N row in FINDINGS.md (canonical-spec deviation requires aumm-site §ix prose-amendment carry-forward).
