# Stage F — CCB engine

> **Status:** Stage F open at the `stage-f` branch from `main` (commit `26178db` on 2026-04-29). Companion to `docs/STAGE_F_NOTES.md`.
>
> **Audience:** Sagix plus any future Claude session that needs to know what Stage F is and what it produces.
>
> **Why this file exists:** resumption anchor outside chat scrollback — this file is the entry point for Stage F work.

---

## Scope of Stage F

**Goal:** ship the Compound Centrifugal Balance (CCB) scoring engine — the per-pool score, share, and multiplier math that Stage H's emission distributor consumes to allocate AuMM emissions across gauged pools post-Year-1. Pure protocol math; no emissions, no gauges, no AuMT, no governance dependencies satisfied yet.

**The Solidity files Stage F produces:**

1. **`src/ccb/EMASampler.sol`** — F-4 per-pool TVL EMA with intra-day TWAP per OQ-5a. Stateful: `tvlEMA`, `lastEMAUpdateBlock`, intra-day TWAP accumulator per pool. Permissionless `updateEMA(pool)` callable once `block.number >= lastEMAUpdateBlock + BLOCKS_PER_DAY`. EMA update: `tvlEMA_new = (2 × twapTVL + 59 × tvlEMA_old) / 61` (alpha = 2/61, half-life ~21 days, 60-day horizon framing). `TWAP_WINDOW_BLOCKS = 720`. Reads spot TVL via injectable `ITVLOracle` interface; concrete oracle is OQ-22 (deferred). Pragma `^0.8.26`. ~150–200 LOC.

2. **`src/ccb/CCBScore.sol`** — F-5 pure-math library, no state. Single `score(uint256 tvlEMA, uint256 multiplier) pure returns (uint256)` returning `tvlEMA × multiplier / 1e18` (FixedPoint). Trivial; lives as a separate contract for audit visibility and F-formula-to-file legibility. ~30 LOC.

3. **`src/ccb/CCBShare.sol`** — F-6 pure-math library, no state. `shares(uint256[] memory scores) pure returns (uint256[] memory)` normalizing scores to fractional shares summing to `1e18`. Empty array reverts `EmptyScores()`; all-zero scores revert `AllScoresZero()`. ~50 LOC.

4. **`src/ccb/CCBMultiplier.sol`** — F-8 stateful per-pool multiplier engine. Stores `M_i(t)` per pool. Permissionless `updateMultiplier()` callable once `block.number >= lastUpdateBlock + BLOCKS_PER_EPOCH`. Update: `M_i(t) = clamp(M_i(t-1) + delta_global + delta_intra_i, 0.75e18, 1.25e18)` with dead-zone, ±0.05 step, and 90-day gauge boost (1.2× factor) — boost composition flagged at OQ-23. Multiplier scope: only Miliarium pools per `04_tokenomics.md` §vii (non-Miliarium gauged pools use M = 1.0); membership read via injected `IMiliariumRegistry` (placeholder address at deployment, replaced via one-shot setter at Stage J). ~250–350 LOC.

**The tests Stage F produces:**

- **`test/unit/EMASampler.t.sol`** — mock `ITVLOracle`, synthetic spot TVL signals, daily `updateEMA` cadence, intra-day TWAP per OQ-5a, revert when called before `BLOCKS_PER_DAY`.

- **`test/unit/CCBScore.t.sol`** — purity and FixedPoint identity for `tvlEMA × multiplier / 1e18`.

- **`test/unit/CCBShare.t.sol`** — normalized shares summing to `1e18`, plus `EmptyScores()` / `AllScoresZero()` reverts.

- **`test/unit/CCBMultiplier.t.sol`** — clamp `[0.75e18, 1.25e18]`, dead-zone, ±step, boost window hook-up (full OQ-23 semantics pinned at F3), registry-placeholder Miliarium filtering.

- **`test/fork/CCBEngine.t.sol`** — fork integration wiring Stage D + Stage E three pilot pools with mock oracle-driven TVL feeds (covers end-to-end shape without requiring OQ-22's concrete oracle).

**The directory addition Stage F performs:** Create `src/ccb/` for the four CCB contracts. No other directory reorganization.

---

## Pragma + license note (Stage F)

All Aureum-authored Stage F files use `pragma solidity ^0.8.26` per cursorrules rule 4. License `SPDX-License-Identifier: GPL-3.0-or-later`. Consistent with Stage C `src/lib/AureumTime.sol`, Stage C `src/token/AuMM.sol`, Stage D `src/fee_router/AureumFeeRoutingHook.sol`.

No upstream Balancer V3 inheritance at Stage F (CCB is pure Aureum math), so there is no `^0.8.24` precedent at this stage like the Stage B `AureumVaultFactory` or Stage E `AureumWeightedPoolFactory`.

---

## Decisions locked in before Stage F starts

These are the answers to the planning-stage questions resolved before this file was written. They are recorded here so implementation doesn't re-litigate them.

| ID | Decision |
|----|----------|
| **F-D1** | **Stage F scope:** F-4 EMA, F-5 score, F-6 share, F-8 multiplier — the four contracts under `src/ccb/`, plus their unit tests and one integration fork test against the 3 pilot pools from Stage E. **Not in scope:** F-7 emission distribution (Stage H), F-3 transition blend (Stage H), F-0 bootstrap channel (Stage H), F-9 governance dampening (Stage K), F-10 efficiency tournament (Stage G), gauge state machine (Stage G), AuMT (Stage I), governance (Stage K), Incendiary (Stage L), `MiliariumRegistry.sol` (Stage J — Stage F injects an `IMiliariumRegistry` interface placeholder), real TVL oracle implementation (deferred — see F-D3 / OQ-22), TVL accumulator hook integration (deferred — see F-D4 / OQ-5a-bis), F-8 detail interpretation (deferred — see F-D7 / F-D8 / OQ-23). |
| **F-D2** | **Contract layout: 4 separate contracts under `src/ccb/`** per `STAGES_OVERVIEW.md` Stage F Builds. `EMASampler.sol` stateful (per-pool EMA + accumulator). `CCBScore.sol` stateless library. `CCBShare.sol` stateless library. `CCBMultiplier.sol` stateful (per-pool M_i + last-update block + boost-end block). Discrete responsibilities per F-formula; minimal cross-contract coupling at Stage F. Stage H's emission distributor composes the four into an end-to-end allocation pipeline. |
| **F-D3** | **TVL denomination — DEFERRED, raised as OQ-22 at F0.** The spec (`02_mental_model.md` §iii, `03_theoretical_foundation.md` §vi-b, `11_formulas.md` F-4, `10_constitution.md` §xxix) does not pin a numéraire, oracle, or price source for "TVL." Pre-F1 resolution required. Three live options: (a) svZCHF as numéraire, on-chain price via constellation-spot averaging — extends OQ-8's BTC-pricing precedent to the general TVL case; (b) USD via external oracle (Chainlink / Pyth) — adds an oracle dependency, contradicts §xxvii's "no off-chain dependencies for core operation" framing; (c) hybrid — Rate Provider rate × balance for ERC-4626 with RP, constellation-spot for STANDARD tokens. Stage F implementation at F1 takes an injectable `ITVLOracle` interface so the contract structure does not block on OQ-22 resolution; concrete oracle implementation lands at the OQ-22 resolution stage (likely Stage G or pre-Stage-H, before live emissions). |
| **F-D4** | **TVL accumulator vs spot-at-sample — DEFERRED, raised as OQ-5a-bis at F0.** OQ-5a (FINDINGS L555+) specifies a Uniswap-style cumulative TVL accumulator updated on every swap / liquidity event, with TWAP read at sample time as `(cumulativeTVL_now − cumulativeTVL_dayAgo) / TWAP_WINDOW_BLOCKS`. This requires a Balancer V3 pool hook to perform accumulator writes on `onAfterSwap` / `onAfterAddLiquidity` / `onAfterRemoveLiquidity`. Stage D's `AureumFeeRoutingHook` already occupies the hook slot on every gauged pool (Balancer V3 allows one hook per pool). Two paths: (a) extend `AureumFeeRoutingHook` with TVL accumulator state and accumulator-write logic on the relevant after-callbacks — touches a Stage D contract, requires careful audit; (b) read TVL spot at sample time via `ITVLOracle` (no accumulator), accepting OQ-5a's noted single-block-spike attack surface and revising OQ-5a to "spot-at-sample with no in-day TWAP." Pre-F1 resolution required. |
| **F-D5** | **Permissionless EMA sampling.** Locked at OQ-5a in `docs/FINDINGS.md`: anyone can call `updateEMA(pool)` once `block.number >= lastEMAUpdateBlock + BLOCKS_PER_DAY`. Function takes no privileged input, deterministic math. Reverts if called too early. No keeper requirement; the CCB scoring path (Stage H) will trigger EMA refresh as part of pre-emission validation. |
| **F-D6** | **Permissionless multiplier update.** F-8 multiplier update follows the same permissionless pattern as F-4: `updateMultiplier()` callable once `block.number >= lastMultiplierUpdateBlock + BLOCKS_PER_EPOCH`. Takes no privileged input. Reverts if called too early. F-8's inputs (per-pool EMA values, protocol-aggregate EMA, Miliarium-set average EMA) are all derived from on-chain state via `EMASampler` reads — no governance call, no oracle dependency at this layer. |
| **F-D7** | **F-8 numerical constants — locked from `10_constitution.md` §xxix where pinned, ambiguities flagged at OQ-23.** §xxix pins: `Step size: ±0.05`, `Clamp: [0.75, 1.25]`, `Dead zone: 0.1%`. Stage F renders these as `STEP_SIZE = 0.05e18`, `CLAMP_FLOOR = 0.75e18`, `CLAMP_CEILING = 1.25e18`, `DEAD_ZONE = 1e15` (0.1% in 1e18 fixed-point), `INITIAL_MULTIPLIER = 1e18` (per F-8 spec text "initialized at 1.00"; not in §xxix), `BOOST_FACTOR = 1.2e18`, `GAUGE_BOOST_DURATION_BLOCKS = 648,000`. Interpretive ambiguities deferred to OQ-23 (raised at F0): (i) whether `Step size: ±0.05` is the per-channel cap (delta_global ±0.05 AND delta_intra ±0.05, total max ±0.10) or the per-update total (combined ±0.05); (ii) whether `Dead zone: 0.1%` applies to delta_global only, delta_intra only, or both; (iii) protocol-aggregate-EMA definition (separate EMA on summed protocol TVL, or sum of per-pool EMAs); (iv) Miliarium-average-EMA definition (simple mean of 28 per-pool EMAs, or weighted). Pre-F3 resolution required. |
| **F-D8** | **90-day gauge boost composition — DEFERRED, OQ-23 sub-item.** `08_bootstrap.md` §xxi specifies "1.2× CCB multiplier for 90 days" but does not specify how this composes with F-8's M_i(t) state and clamp band [0.75, 1.25]. Three live readings: (a) M_i is initialized at 1.2 at gauge approval (replaces 1.0 cold-start), F-8 evolution during boost is normal, boost "expires" via natural F-8 decay toward steady-state, clamp applies to M_i; (b) effective multiplier returned by `CCBMultiplier` is `boost ? 1.2e18 : M_i(t)` for boost window — M_i state still updates via F-8 every BLOCKS_PER_EPOCH but isn't read for scoring during boost — clamp applies to M_i, not effective; (c) effective = `min(1.2e18 × M_i / 1e18, CLAMP_CEILING)` (multiplicative, ceiling re-applied). Stage F implementation at F3 selects + resolves with user. Pre-F3 review required. |
| **F-D9** | **Non-Miliarium gauged pools: CCB_mult = 1.0.** Per `04_tokenomics.md` §vii, the F-8 multiplier engine applies *only* to the 28 Miliarium pools. Non-Miliarium gauged pools score with `EMA × 1.0` and do not participate in F-8 step updates. `CCBMultiplier.sol` determines Miliarium membership via an injected `IMiliariumRegistry` interface; deployment uses a placeholder registry address that Stage J's `MiliariumRegistry.sol` deployment script replaces via a one-shot setter (same pattern as Stage G's gauge-registry → governance dependency). Pre-Stage-J, the placeholder returns `false` for all queries, so all pools are non-Miliarium and multiplier = 1.0 for testing and integration. |
| **F-D10** | **`CCBShare` design — pure function, no state, no `IGaugeRegistry`.** `CCBShare.shares(uint256[] memory scores) pure returns (uint256[] memory)` takes the eligible-pool score array (already filtered + ordered by the caller) and returns normalized shares summing to `1e18`. No state, no enumeration of pools, no dependency on gauge registry at Stage F. Stage H's emission distributor (the eventual caller) is responsible for enumerating gauged pools, computing per-pool scores via `CCBScore`, then passing the score array to `CCBShare`. Edge cases: empty array reverts `EmptyScores()`; all-zero scores reverts `AllScoresZero()` — Stage H must handle the all-zero case (theoretically reachable at protocol genesis, though F-0 bootstrap inflows make this practically impossible after block 0). |
| **F-D11** | **Test layout.** Per-contract unit-test file under `test/unit/` (`EMASampler.t.sol`, `CCBScore.t.sol`, `CCBShare.t.sol`, `CCBMultiplier.t.sol`); one integration fork-test file under `test/fork/CCBEngine.t.sol` exercising the Stage D + Stage E pilot-pool deployment chain plus a mock TVL oracle to drive synthetic TVL signals. Mock-oracle pattern keeps the fork test independent of OQ-22 resolution; once OQ-22's concrete oracle ships, a follow-up integration test verifies against real on-chain TVL. Test invocation follows the D35 split-form: unit suite via `--no-match-path "test/fork/**"`; fork suite via `--match-path "test/fork/**" --fork-url $URL --threads 1`. |
| **F-D12** | **Sub-step layout.** **F0** plan + notes scaffold (this commit). **F1** `EMASampler.sol` + unit tests + OQ-22 resolution + OQ-5a-bis resolution. **F2** `CCBScore.sol` + `CCBShare.sol` + their unit tests (combined sub-step — both are simple pure-math libraries; bundling avoids two trivial-commits' worth of overhead). **F3** `CCBMultiplier.sol` + unit tests, including 90-day boost integration and Miliarium-only scope; OQ-23 resolution. **F4** `test/fork/CCBEngine.t.sol` integration test against the 3 pilot pools. **F5** docs (`STAGES_OVERVIEW.md` Stage F row update + this file's Completion Log + `CLAUDE.md` §11 refresh). **F9** close (FF merge to main, tag `stage-f-complete`, push). Final numbering may refine at F1 entry; broad shape locked. |
| **F-D13** | **Pragma `^0.8.26` + license `GPL-3.0-or-later` for all Stage F files.** No upstream Balancer-V3 inheritance at Stage F (CCB is pure Aureum math), so no `^0.8.24` precedent at this stage. Compiler is `solc 0.8.26` per `foundry.toml`. License matches Stage C / Stage D / Stage E Aureum-authored files. |
| **F-D14** | **Branch model:** `stage-f` working branch from `main` (created from commit `26178db` on 2026-04-29 — the post-Stage-E aumm-specs hallucination cross-repo sweep tip); `git push origin stage-f` early per the D9 lesson — don't let origin lag the local branch. Fast-forwards to `main` at F9; `stage-f-complete` lightweight tag applied on `main` at the tip. Preserve `stage-f` on origin as a snapshot marker per the C0 / D0 / E-D8 convention. No PR workflow. |

---

## Mid-stage supersessions

> Decisions resolved during Stage F that revise values or framing locked in by the planning-stage decisions above. Each entry preserves the canonical record location in `docs/STAGE_F_NOTES.md` (full reasoning) and `docs/FINDINGS.md` (OQ marker). The lock table is left intact as historical context — read these supersessions alongside it.

- **F-D3 → OQ-22 (RESOLVED at F0.2, FINDINGS L1102):** TVL denomination = svZCHF; per-token valuation = RP-aware unwrap + constellation-spot averaging (option (c) of the F-D3 stub); concrete oracle implementation deferred to OQ-22 resolution stage; `ITVLOracle.tvl(address pool) external view returns (uint256)` interface shape pinned. F-D3's "three live options" superseded by the resolved single-option valuation pipeline.

- **F-D4 → OQ-5a-bis (RESOLVED at F0.3, FINDINGS L1150):** TVL accumulator vs spot-at-sample — option (b) selected. `EMASampler.sol` reads `ITVLOracle.tvl(pool)` once per `BLOCKS_PER_DAY` at the sample boundary; no cumulative-balance accumulator; no Stage D `AureumFeeRoutingHook` modification. F-D4's "two paths, pre-F1 resolution required" superseded. OQ-5a's cumulative-TVL framing is superseded in part by this resolution (cumulative accumulator dropped; per-day spot read substituted; protection model relies on EMA(60) + F-10 efficiency tournament + tier caps as a layered defense).

- **F-D7 + F-D8 → OQ-23 (RESOLVED at F0.4, FINDINGS L1200):** F-8 multiplier interpretive ambiguities (i)–(iv) + 90-day boost composition (v) all resolved. (i) per-channel ±0.05 cap (`delta_global` and `delta_intra` each ∈ `{−0.05, 0, +0.05}` independently); (ii) per-channel dead zone (each channel's TVL ratio filtered at 0.1% independently); (iii) protocol-aggregate EMA = sum of per-pool EMAs (no separate accumulator); (iv) Miliarium-average EMA = simple arithmetic mean of 28 per-pool EMAs; (v) NEW option (v.d) supersedes stub options (v.a)/(v.b)/(v.c) — boost gates effective output to `1.2e18` AND pauses F-8 state evolution during the 90-day window; `M_i` initialized at `1e18` at gauge approval, frozen during boost; at boost expiry effective output transitions 1.2 → 1.0 (16.7% drop) and F-8 evolution resumes from `1e18` baseline. F-D7's (i)–(iv) deferral closed; F-D8's (a)/(b)/(c) live readings superseded by (v.d).

---

## What is explicitly NOT in Stage F

- F-7 emission distribution (per-block AuMM minting and routing) — Stage H.
- F-3 linear blend (Months 11–12 transition between equal split and CCB-weighted shares) — Stage H.
- F-0 bootstrap channel (one-sided AuMM deposits to der Bodensee Months 0–10) — Stage H.
- F-9 governance dampening (Era 0 ¼-power → Era 1+ ⅓-power AuMT power calculation) — Stage K.
- F-10 efficiency tournament (top-15/10/5-percentile emission caps starting Month 13) — Stage G eligibility checker.
- Gauge registry / approval / revocation state machine — Stage G.
- Gauge eligibility checks (4626 Quality Gate already at Stage E factory; min TVL floor + volume percentile floor + 4-consecutive-disqualified-epoch revocation + Sandbox fast-track + hysteresis buffer) — Stage G.
- AuMT (LP receipt token, per-pool, governance weight) — Stage I.
- `MiliariumRegistry.sol` (slot → currentPoolAddress) — Stage J. Stage F injects the registry interface; concrete contract is Stage J.
- Incendiary Boost (priority skim from emission stream pre-CCB) — Stage L.
- Concrete TVL oracle implementation — OQ-22 resolution stage (likely Stage G or pre-Stage-H, before live emissions).
- TVL accumulator hook integration into `AureumFeeRoutingHook` — OQ-5a-bis resolution at F1.
- F-8 detail interpretation (step-size scope, dead-zone scope, aggregate-EMA / Miliarium-average definitions, 90-day boost composition) — OQ-23 resolution at F3.
- Aureum's own Router — D33 deferred, post-D / re-entry at K or O.
- OQ-20 controller yield-fee entry point — post-D, tracked.
- OQ-21 bi-weekly cadence throttle — post-D, tracked.
- Mainnet deployment of CCB engine — Stage R.

---

## Sub-steps

> Sub-step bodies populate as they are planned. This section's headers are placeholders for F0 through F9 detail.

### F0 — Plan + notes scaffold

### F1 — EMASampler + OQ-22 / OQ-5a-bis resolution

### F2 — CCBScore + CCBShare

### F3 — CCBMultiplier + OQ-23 resolution

### F4 — Integration fork test

### F5 — Docs

### F9 — Close

---

## Completion Log

| Sub-step | Commit | Date | Summary |
|----------|--------|------|---------|
| F0 | TBD | 2026-04-29 | F0: docs/STAGE_F_PLAN.md + docs/STAGE_F_NOTES.md — Stage F scaffold |
