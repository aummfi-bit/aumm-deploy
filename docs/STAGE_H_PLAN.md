# Stage H — Emission Distributor

> **Status:** Pre-implementation. H-D design surface partially locked (H-D1 through H-D5 resolved). Awaiting plan review and approval before §8e.1 sub-step prompts beyond H0.X scaffold work begin.
>
> **Last update:** 2026-05-14 — H0.1 plan scaffold authored.
>
> **Mode:** Opus extra-high entry per §13 stage-level defaults (halving math + F12 type-discipline domain). Drops to Opus high after H4 (post core distributor lock). Sonnet beats only for plan-row updates, commit drafts on closed sub-steps, and mechanical Completion Log entries.

## Goal

Stage H delivers the emission distributor: F-0 piecewise bootstrap decay (Months 0—6 then 6—10), F-1 equal split across Miliarium pools for Months 0—10, F-3 linear blend across Months 11—12, and F-7 full CCB-weighted distribution from Year 2 onward, with geometric era halving at BLOCKS_PER_ERA boundaries per the canonical schedule. Minted AuMM authority hands off through IAuMM.setMinter() as a one-shot; the stage also exposes an AuMT-claim interface forward dependency for Stage I and an IIncendiaryRegistry interface forward dependency for Stage L. Stage H tag: stage-h-complete.

## Dependencies

- src/lib/AureumTime.sol (Stage C)
- src/token/AuMM.sol + src/token/IAuMM.sol (Stage C — IAuMM.setMinter one-shot handoff)
- src/fee_router/AureumFeeRoutingHook.sol + der Bodensee deployment (Stage D)
- src/ccb/CCBScore.sol + src/ccb/CCBShare.sol + src/ccb/EMASampler.sol + src/ccb/CCBMultiplier.sol (Stage F)
- src/gauge/GaugeRegistry.sol + src/gauge/IEfficiencyOracle.sol interface (Stage G — IGaugeRegistry.isGaugeApproved consumer; IEfficiencyOracle concrete ships at H2b)
- src/ccb/ITVLOracle.sol interface (Stage F — concrete ships at H2a)

## Sub-step skeleton

```text
H0 — Stage H scaffolding: PLAN/NOTES/overview prep (H0.X family commits)
H1 — Architecture + schedules inventory; lock H-D6 (F-1 share denominator); interface boundary freeze
H2 — In-stage oracles per H-D1 — H2a concrete ITVLOracle; H2b concrete IEfficiencyOracle
H3 — BodenseeBootstrapChannel per H-D2 — isolated F-0 bootstrap rail to der Bodensee
H4 — Pool-scoped emission distributor per H-D4—H-D5 — lazy accrual, incremental totalScore, isGaugeApproved on score record; epoch cadence alignment
H5 — Era halving + phased schedule wiring — F-0/F-1/F-3/F-7 transitions, F12-signed accumulators where applicable
H6 — AuMM minter plumbing — IAuMM.setMinter one-shot; AuMT claim interface surface for Stage I
H7 — IIncendiaryRegistry interface surface for Stage L
H8 — Unit tests — schedule math, distributor core, bootstrap channel, oracle adapters
H9 — Fork integration — Stage E pilots + Stage F/G stack + synthetic gauges as needed
H10 — Deployment scripts; lock H-D7 (AuMM.setMinter timing — Stage H deploy vs Stage K governance migration)
H11 — Completion Log + cross-docs (FINDINGS cross-refs as needed)
H12 — Stage close — fast-forward merge, stage-h-complete tag, preserved stage-h snapshot convention
```

## H-D Decisions

| ID | Decision | Status | Rationale |
|----|----------|--------|-----------|
| H-D1 | Oracles in-stage as H2a/H2b | LOCKED | Matches Stage G precedent of single-branch stage with sub-step families inside |
| H-D2 | Separate BodenseeBootstrapChannel contract | LOCKED | Mirrors G-D11 / G-D21 audit-isolation precedent |
| H-D3 | F-7 share weights step-function sampled at BLOCKS_PER_EPOCH boundaries | LOCKED | F-7 spec literal "every block" discretised to epoch cadence — matches F-8 multiplier cadence per F-D24; deviation documented in STAGE_H_NOTES.md |
| H-D4 | Pull / lazy accrual via MasterChef-style accRewardPerScoreUnit accumulator | LOCKED | Spec language "deposit triggers accrual; withdrawal stops it immediately" and gas economics dictate pull model |
| H-D5 | Pool-scoped distributor; no IGaugeRegistry enumeration; incremental totalScore aggregate updated permissionlessly per recordScore(pool) | LOCKED | isGaugeApproved(pool) per score-record call suffices — no G16-class mock sweep needed |
| H-D6 | F-1 share denominator — fixed 1/28 literal vs dynamic 1/N_miliarium | OPEN | To lock at H1 design; spec says "1/28" but pre-mainnet only 3 pilot pools live |
| H-D7 | AuMM.setMinter() handoff timing — Stage H deploy vs Stage K governance migration | OPEN | To lock at H10; affects emission start block and upgrade path |

## Completion Log

| Sub-step | Commit | Date | Notes |
|----------|--------|------|-------|
| H0.1 | 86d166c | 2026-05-14 | docs/STAGE_H_PLAN.md scaffold created (header + Goal + Dependencies + Sub-step skeleton + H-D Decisions table H-D1—H-D7 + Completion Log header) |
| H0.2 | 610b07e | 2026-05-14 | docs/STAGE_H_NOTES.md scaffold created (status header + organization rubric + H-D1—H-D5 LOCKED bodies + H-D6/H-D7 OPEN placeholders + findings queue + open questions queue) |
