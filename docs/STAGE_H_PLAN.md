# Stage H — Emission Distributor

> **Status:** Implementation in progress. H2a complete — TVLOracle concrete + 28 unit tests passing; H-D1—H-D6 + H-D8—H-D9 LOCKED; H-D7 OPEN (lock at H10). Next: H2b (concrete EfficiencyOracle).
>
> **Last update:** 2026-05-15 — H2a closed (TVLOracle implementation + 28 unit tests, 28 pass); Completion Log through H2a.7c (H2a.9a).
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
| H-D6 | F-1 share denominator — fixed 1/28 literal vs dynamic 1/N_miliarium | LOCKED | Literal 1/28 per F-1 canonical text — pre-N=28 fraction structurally unminted by design (no treasury buffer, no deferred mint); F-3 equal-split leg inherits same denominator; dynamic-N enumeration rejected per H-D5; no FINDINGS promotion needed — see STAGE_H_NOTES.md H-D6 |
| H-D7 | AuMM.setMinter() handoff timing — Stage H deploy vs Stage K governance migration | OPEN | To lock at H10; affects emission start block and upgrade path |

## Completion Log

| Sub-step | Commit | Date | Notes |
|----------|--------|------|-------|
| H0.1 | 86d166c | 2026-05-14 | docs/STAGE_H_PLAN.md scaffold created (header + Goal + Dependencies + Sub-step skeleton + H-D Decisions table H-D1—H-D7 + Completion Log header) |
| H0.2 | 610b07e | 2026-05-14 | docs/STAGE_H_NOTES.md scaffold created (status header + organization rubric + H-D1—H-D5 LOCKED bodies + H-D6/H-D7 OPEN placeholders + findings queue + open questions queue) |
| H0.3 | d8d67d4 | 2026-05-14 | docs/STAGE_H_PLAN.md — Completion Log H0.1 hash fill + H0.2 row added |
| H1.1 | b6f37d2 | 2026-05-14 | docs/STAGE_H_NOTES.md — ## Architecture section (new contracts/interfaces inventory + consumer surface + schedules-by-phase table) |
| H1.2 | 5f36a89 | 2026-05-14 | docs/STAGE_H_NOTES.md — ## Interface boundary section (Produced + Consumed + Forward-dependency stubs) |
| H1.3 | 87b62a7 | 2026-05-14 | docs/STAGE_H_NOTES.md — H-D6 OPEN → LOCKED (1/28 literal per F-1; supply-deflationary by design; H-D6 Open-questions bullet removed) |
| H1.4 | d992f68 | 2026-05-14 | docs/STAGE_H_PLAN.md + docs/STAGE_H_NOTES.md — H-D6 row LOCKED + Completion Log rows H0.3/H1.1—H1.3 + NOTES status header refresh |
| H1.x-bis | 3d39978 | 2026-05-15 | src/ccb/ICCBMultiplier.sol — ICCBMultiplier interface retrofit RB-005 (getMultiplier per OQ-23) |
| H1.5 | 4e25a57 | 2026-05-15 | docs/STAGE_H_NOTES.md — H-D8 LOCKED (constellation enumeration source for OQ-22 cross-asset leg) |
| H1.6 | b0403b5 | 2026-05-15 | docs/STAGE_H_PLAN.md — status header refresh (H-D8 LOCKED) + Completion Log rows H1.4/H1.x-bis/H1.5 |
| H1.7 | 20614e3 | 2026-05-15 | docs/STAGE_H_NOTES.md — H-D9 LOCKED (TVLOracle arithmetic: balancesLiveScaled18 step 1, tokenToUnderlying map, balance-ratio α step 2, Phase 1 direct-venues-only + OQ-22 L1115 carry-forward) |
| H1.8 | 342932e | 2026-05-15 | docs/STAGE_H_PLAN.md — status header refresh (H-D9 LOCKED) + Completion Log rows H1.6/H1.7 |
| H2a.1 | e48a61c | 2026-05-15 | src/emission/TVLOracle.sol — skeleton scaffold (abstract contract, storage layout per H-D8 + H-D9, IVaultExplorer + ITVLOracle imports) |
| H2a.2 | 6f157f7 | 2026-05-15 | src/emission/TVLOracle.sol — constructor (IVaultExplorer + BODENSEE_POOL + governance init, ZeroAddress guard) |
| H2a.3 | 685a81e | 2026-05-15 | src/emission/TVLOracle.sol — tokenToUnderlying seed loop (2 new constructor params, ArrayLengthMismatch, genesis mapping loop) |
| H2a.4 | 321c8c7 | 2026-05-15 | src/emission/TVLOracle.sol — governance setter (NotGovernance error, GovernanceTransferred event, onlyGovernance modifier, setGovernanceContract) |
| H2a.5 | 1db1085 | 2026-05-15 | src/emission/TVLOracle.sol — addConstellationPool (AlreadyAdded error, ConstellationPoolAdded event, IERC20 import, _underlyingToPools incremental append) |
| H2a.6 | 8b69cbb | 2026-05-15 | src/emission/TVLOracle.sol — setTokenUnderlying (TokenUnderlyingSet event, Token underlying management section, reverse-map staleness NatSpec) |
| H2a.7a | e4a9eee | 2026-05-15 | src/emission/TVLOracle.sol — SVZCHF immutable + constructor param (_svzchf, ZeroAddress guard, assignment, @param NatSpec) |
| H2a.7b | cdb94f8 | 2026-05-15 | src/emission/TVLOracle.sol — _constellationRatio helper (H-D9 Step 2 balance-ratio averaging, PoolData import, Internal helpers section) |
| H2a.7c | 00eb759 | 2026-05-15 | src/emission/TVLOracle.sol — concrete tvl() body (H-D9 Step 1+2), abstract keyword removal, title + @dev NatSpec fix |
