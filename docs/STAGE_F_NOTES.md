# Stage F — Living design + findings log

> **Status:** Stage F open at the `stage-f` branch from `main` (commit `26178db` on 2026-04-29). Companion to `docs/STAGE_F_PLAN.md`.
>
> **Audience:** Sagix plus any future Claude session that needs the running log of decisions resolved during implementation and the incidents caught at audit.
>
> **Why this file exists:** to keep design decisions resolved *during* implementation (not pre-locked at plan-authoring time) and implementation findings out of the plan file. `docs/STAGE_F_PLAN.md` is the operational document — sub-step bodies, verbatim commit messages, the Completion Log. This file is the living archive.

---

## How this file is organized

- **Design decisions during implementation (`F-D15` onward).** `F-D1` through `F-D14` are pre-locked in `docs/STAGE_F_PLAN.md`'s "Decisions locked in before Stage F starts" table. Any new design decision resolved *during* F1 / F2 / F3 / F4 / F5 gets the next free `F-D*` number and is recorded in this file's next subsection — not retro-edited into the plan file. Matches the `C-D*` / `D-D*` / `E-D*` convention.
- **Findings (`F10` onward).** Implementation incidents, drift caught at audit, RPC quirks, env-key surprises, scope-expansion catches, contract-interface gotchas — anything worth a numbered log entry. Numbered from `F10` to avoid collision with `F-D*` planning codes (matches the `C10` / `D10` / `E10` pattern in earlier stage notes).
- **Cross-reference convention (per `CLAUDE.md` §5):** `F-Dn` = planning decision n; `Fn` (n ≥ 10) = implementation finding n; `OQ-N` = open question N from `docs/FINDINGS.md`. `Cn` / `Dn` / `En` codes carry forward across stages — Stage F entries can cite `D32` or `E10` directly without re-explaining.

---

## Design decisions during implementation

> `F-D15` onward populates as F1 sub-steps land.

### F-D15 — `EMASampler` cold-start: sentinel seed when `lastEMAUpdateBlock[pool] == 0`

**Resolved 2026-04-29 at F1.2.** On the very first `updateEMA(pool)` call — detected by `lastEMAUpdateBlock[pool] == 0` — seed `tvlEMA[pool] = spotTVL` directly, bypassing the F-4 EMA formula. Subsequent calls apply the standard update `tvlEMA_new = (2 × spotTVL + 59 × tvlEMA_old) / 61` per OQ-5a-bis (FINDINGS L1152-L1198). The same `EMAUpdated` event fires on both paths.

**The gap.** OQ-5a-bis pins state shape, the per-day cadence, and the `alpha = 2/61` formula, but does not specify first-call behavior. Naive application with `tvlEMA_old == 0` yields `tvlEMA_new = 2 × spotTVL / 61 ≈ 3.28% × spotTVL`; the EMA then needs ~3× the 21-day half-life (~63 days) to reach ~88% of true spot. Newly gauged pools would be severely under-weighted in CCB share allocation for two months at every gauge approval — the wrong cold-start protocol.

**Why option (a) over alternatives:**

- **(b) Constructor seeding** — `(pool, initialEMA)[]` at deployment. Operationally infeasible: pools are added post-Stage-J via the permissionless `MiliariumRegistry` (per F-D9) and post-Stage-G via gauge approval, so the pool set is not knowable at `EMASampler` deployment.

- **(c) Apply formula always** — accept the slow ramp. Breaks `08_bootstrap.md` §xxi's "the CCB takes over seamlessly" framing: per OQ-23 (v.d) (FINDINGS L1212-L1230) the boost-to-F-8 handoff at day 91 expects ~90 days of EMA bake-time, which a cold-start ramp would not deliver before boost expiry. (a) aligns by construction; (c) does not.

**Sentinel reliability.** `lastEMAUpdateBlock[pool] == 0` is unambiguously "never sampled" because (i) the slot is only written by `updateEMA`; (ii) `updateEMA` always writes `block.number > 0` post-genesis; (iii) no constructor pre-seed path exists per (b)'s rejection above. The cadence guard `block.number >= 0 + BLOCKS_PER_DAY = 7_200` is satisfied by any post-block-7200 mainnet block — no extra "wait one day after deploy" branching beyond what OQ-5a-bis already implies.

**Edge case — `spotTVL == 0` at first call.** Seed writes `tvlEMA[pool] = 0`; the next daily update applies the formula with `tvlEMA_old = 0`, restoring the slow-ramp path the seed exists to avoid. Practical impact bounded: pools shouldn't be sampled before they have nonzero TVL (gauge approval implies active liquidity), and the realistic first-sample case (`spotTVL > 0`) is correctly seeded. No second-order "re-seed if `tvlEMA == 0` and `spotTVL > 0`" sentinel — adds state-machine complexity without clear protocol benefit; if a pool is briefly drained mid-life and later re-funded, natural EMA decay/regrowth is correct, not a re-seed.

**Cross-references:**

- **OQ-5a-bis** (FINDINGS L1152-L1198) — pins formula and cadence; F-D15 fills the cold-start gap.
- **OQ-23 (v.d)** (FINDINGS L1212-L1230) — boost-to-F-8 handoff expects ~90 days of EMA bake-time, delivered by F-D15's seed from day 0.
- **F-4** (`11_formulas.md`) — formula unchanged; F-D15 only specifies first-call seed behavior.
- **F-D9** — Miliarium-only filtering happens downstream in `CCBMultiplier`, not in `EMASampler`; F-D15's "newly gauged pools" framing applies to all gauge-eligible pools.

**Test surface flagged for F1.4:**

- First call seeds `tvlEMA[pool] = spotTVL` regardless of `spotTVL` value (including `0`).
- First call sets `lastEMAUpdateBlock[pool] = block.number`.
- Second call (after `BLOCKS_PER_DAY`) applies the F-4 formula against the seeded `tvlEMA`.
- Calling before `last + BLOCKS_PER_DAY` reverts `TooEarly` with the next-eligible block in the error data.
- `spotTVL == 0` at second call (post non-zero seed) decays via formula; no re-seed path.

### F-D16 — `updateMultiplier` reverts for non-Miliarium pools; `getMultiplier` returns `1e18`; unit tests inject mock `IMiliariumRegistry`

**Resolved 2026-04-30 at F3.0.** `updateMultiplier(pool)` reverts `NotMiliariumPool(pool)` if `miliariumRegistry.isMiliarium(pool) == false`. `getMultiplier(pool) view` returns `INITIAL_MULTIPLIER = 1e18` for non-Miliarium pools without reverting. Unit tests inject a `MockMiliariumRegistry` exposing `setMiliarium(pool, bool)` to flag tested pools as Miliarium and `setPoolList(address[])` to populate the enumeration surface (`miliariumPoolsCount` + `miliariumPoolAt(i)`) per OQ-23 (iii.b)'s protocol-aggregate-EMA sum.

**The gap.** F-D9 pins `CCB_mult = 1.0` for non-Miliarium gauged pools via `04_tokenomics.md` §vii but leaves the implementation choice between revert and no-op explicit at F3 — both are F-D9-compliant. Conflating a write entry point (`updateMultiplier`) with a read entry point (`getMultiplier`) under one rule misses that the two have different consumer-side ergonomics.

**Why `updateMultiplier` reverts.** Explicit failure is loud; a silent no-op would consume gas with no state change and obscure miswiring at higher layers. Stage H's emission distributor pre-filters by Miliarium status before scoring (per F-D10's eligible-pool array semantics), so a non-Miliarium `updateMultiplier` call is a caller-side bug, not protocol-routine. Pre-Stage-J the placeholder registry returns `false` for every pool (per F-D9), so all `updateMultiplier` calls revert until Stage J's `MiliariumRegistry` ships and is wired via the one-shot setter — acceptable: pre-Stage-J the protocol isn't running gauged emissions yet.

**Why `getMultiplier` does not revert.** `getMultiplier(pool)` is a hot-path read for Stage H's emission distributor, which scores all gauged pools (Miliarium and non-Miliarium together) every block per F-D9. Reverting would force the distributor to branch on Miliarium status before reading. Returning `INITIAL_MULTIPLIER = 1e18` for non-Miliarium pools lets the distributor read uniformly and matches F-D9's mathematical contract (`CCB_mult = 1.0`). The boost-window check is also inside `getMultiplier` and only fires for Miliarium pools — a non-Miliarium pool cannot have an active boost because `activateBoost` is gated by both `IGaugeRegistry` caller verification and the same Miliarium check applied to `updateMultiplier`.

**Mock registry pattern.** `MockMiliariumRegistry` is a test-only contract co-located with `test/unit/CCBMultiplier.t.sol` (separate file under `test/unit/mocks/` only if Cursor finds the inline pattern unwieldy at F3.4). Surface: `setMiliarium(pool, bool)`, `setPoolList(address[])`, `isMiliarium(pool) view`, `miliariumPoolsCount() view`, `miliariumPoolAt(i) view`. Defaults: `false` for all `isMiliarium` queries unless explicitly set, matching F-D9's pre-Stage-J placeholder behavior. Reuses the test-shape used for `ITVLOracle` in F1's EMASampler tests.

**Cross-references:**

- **F-D9** (`STAGE_F_PLAN.md` L63) — Miliarium-only scope; F-D16 disambiguates the revert-vs-no-op choice flagged at plan time.
- **F-D11** (`STAGE_F_PLAN.md` L65) — test layout; mock registry pattern matches F-D11's "registry-placeholder Miliarium filtering" callout.
- **OQ-23 (iii.b)** (FINDINGS L1208) — protocol-aggregate-EMA = sum of per-pool EMAs; mock must expose enumeration to support this read.
- **OQ-23 (iv.a)** (FINDINGS L1210) — Miliarium-average-EMA = `protocolTVLEMA / 28`; division denominator is the constant `28`, not `miliariumPoolsCount()`, per `04_tokenomics.md` §vii's fixed 28-pool constellation. Mock enumeration is for the sum, not the divisor.

**Test surface flagged for F3.4:**

- `updateMultiplier(nonMiliariumPool)` reverts `NotMiliariumPool(pool)`.
- `getMultiplier(nonMiliariumPool)` returns `1e18`, no revert.
- `getMultiplier(miliariumPool, no_boost)` returns `M_i[pool]` (= `1e18` if F-8 has not yet fired).
- `getMultiplier(miliariumPool, in_boost)` returns `BOOST_FACTOR = 1.2e18`.
- Mock registry returns `false` for unconfigured pools by default.
- Mock registry's `setMiliarium(pool, false)` toggles a previously-true pool back to non-Miliarium for revert-path tests.

---

### F-D17 — `activateBoost(pool)` reverts on active boost; permits post-expiry re-activation

**Resolved 2026-04-30 at F3.0.** `activateBoost(pool)` reverts `BoostAlreadyActive(pool)` if `block.number < boostExpiryBlock[pool]`. Otherwise sets `boostExpiryBlock[pool] = block.number + GAUGE_BOOST_DURATION_BLOCKS` (`= 648_000` blocks ≈ 90 days). Caller is gated by `IGaugeRegistry.isGaugeApproved(msg.sender)` (final shape locked at F3.2 when `IGaugeRegistry.sol` lands) plus `miliariumRegistry.isMiliarium(pool)` Miliarium check.

**The gap.** `08_bootstrap.md` §xxi specifies "fixed 1.2× CCB multiplier for 90 days" plus "activates when the gauge passes, expires on its own — no vote, no renewal". OQ-23 (v.d) (FINDINGS L1212-L1230) inherits this and pins boost composition (effective output gated to `BOOST_FACTOR`, F-8 state paused during window). But the implementation must decide what happens if `activateBoost` is called twice for the same pool — reachable via gauge-registry replay, gauge-registry bug, or attacker holding placeholder access pre-Stage-G.

**Why revert during active boost.** Allowing re-activation while a boost is live would be effective extension, contradicting §xxi's "no vote, no renewal" rule. Explicit revert makes the rule loud and gives Stage G's gauge-registry implementation a clear failure signal if it ever tries to double-activate (e.g. a gauge re-approval path that calls `activateBoost` unconditionally without checking the pool's current boost state). The gauge registry should not ship that bug, but Stage F's `activateBoost` defends in depth.

**Why post-expiry re-activation succeeds.** After `boostExpiryBlock[pool]` passes, `activateBoost(pool)` allows another 90-day window to start. Whether Stage G's gauge-approval flow ever does this is Stage G's concern — Stage F's `activateBoost` does not restrict post-expiry calls. `M_i` remains at `INITIAL_MULTIPLIER = 1e18` across the prior boost (F-8 paused per OQ-23 (v.d)), so a post-expiry re-activation effectively gives another 90-day boost from a fresh `M_i = 1.0` baseline — clean re-seeding behavior with no boost-decay state to clean up. §xxi's "expires on its own" describes the natural one-shot lifecycle; it does not prohibit deliberate Stage-G-side renewal mechanisms layered above.

**Layered defense.** Stage G's gauge approval flow ships at Stage G; Stage F cannot constrain its replay safety. F-D17's revert path is Stage F's contribution: the gauge registry might mis-call `activateBoost` for various reasons (re-org replay, governance proposal that re-runs the approval flow, etc.); the revert ensures the boost window cannot be silently extended.

**Cross-references:**

- **OQ-23 (v.d)** (FINDINGS L1212-L1230) — boost composition pinned: effective output gated to BOOST_FACTOR during window; F-8 paused during window; expiry hands off to `M_i[pool] = INITIAL_MULTIPLIER`.
- **F-D8** — superseded by OQ-23 (v.d); F-D17 fills the entry-point semantics gap that OQ-23 (v.d) does not address.
- **`08_bootstrap.md` §xxi** — "expires on its own — no vote, no renewal"; F-D17's active-boost revert is the no-renewal enforcement.
- **F-D9 / F-D16** — Miliarium check on `activateBoost` complements the Miliarium check on `updateMultiplier`.

**Test surface flagged for F3.4:**

- `activateBoost(pool)` from approved gauge succeeds at block `t`, sets `boostExpiryBlock[pool] = t + 648_000`.
- `activateBoost(pool)` from approved gauge at block `t + 1` (boost still active) reverts `BoostAlreadyActive(pool)`.
- `activateBoost(pool)` from non-approved caller reverts the gauge-registry access-control error (final shape per F3.2).
- `activateBoost(nonMiliariumPool)` from approved gauge reverts the Miliarium check error per F-D16.
- `activateBoost(pool)` at block `t + 648_001` (post-expiry) succeeds; new `boostExpiryBlock = t + 648_001 + 648_000`.
- During boost: `updateMultiplier(pool)` is a full no-op per F-D21 — does not tick `lastMultiplierUpdateBlock`, does not write `M_i[pool]`, does not update `lastProtocolAggregateEMA`.
- `getMultiplier(pool)` returns `BOOST_FACTOR` for `block.number < boostExpiryBlock[pool]`; returns `M_i[pool]` thereafter.

---

### F-D18 — `lastProtocolAggregateEMA` cold-start: seed on first protocol-wide `updateMultiplier`; `delta_global = 0` for that epoch

**Resolved 2026-04-30 at F3.0.** First `updateMultiplier(pool)` call across the entire protocol — detected by `lastProtocolAggregateEMA == 0` — seeds `lastProtocolAggregateEMA = currentProtocolAggregateEMA` and computes that pool's multiplier with `delta_global = 0` for that epoch. `delta_intra` is computed normally (against the seeded `miliariumAvgEMA = currentProtocolAggregateEMA / 28`). Subsequent `updateMultiplier` calls compare current aggregate to the seeded baseline per OQ-23 (iii.b)'s direction-comparison rule.

**The gap.** OQ-23 (iii.b) (FINDINGS L1208) pins `protocolTVLEMA(t) = sum(emaSampler.tvlEMA(pool_i) for i ∈ MiliariumPools)` and the next-epoch direction comparison `delta_global = sign(protocolTVLEMA(t) − lastProtocolAggregateEMA(t-1)) × STEP_SIZE` (with dead-zone gating). But it does not specify first-epoch behavior. Naive application with `lastProtocolAggregateEMA = 0` baseline yields `protocolTVLEMA(t) − 0 > 0` for any nonzero aggregate, so `delta_global` registers nonzero universally on first epoch — every Miliarium pool's `M_i` shifts by the same amount despite no actual aggregate movement. Same defect class as F-D15's EMA cold-start ramp: a baseline of zero is a pathological starting point for direction comparisons.

**Why seed-and-zero rather than alternatives.**

- **Apply formula always (`delta_global` derived from `0` baseline).** Produces the universal first-epoch shift described above. Wrong cold-start protocol; wastes one of F-8's per-epoch step credits on a non-event.
- **Skip first-epoch entirely (no `M_i` update on the first call).** Asymmetric across pools: if pool A's `updateMultiplier` triggers the seed, pool B's later first call in the same epoch would see a populated baseline and compute a real `delta_global` despite being "the first call" for pool B. The semantic distinction "first call protocol-wide" vs "first call per pool" matters: F-D18 picks the former.
- **Seed on construction.** Operationally infeasible: the Miliarium pool set is not known at `CCBMultiplier` deployment (Stage J's registry has not shipped). Even if seeded with placeholder `0`, the seed is meaningless until the registry is wired. F-D18 defers seeding to first call, when the registry is guaranteed populated (otherwise `updateMultiplier` reverts `NotMiliariumPool` per F-D16 and the seed code path is unreachable).

**Sentinel reliability.** `lastProtocolAggregateEMA == 0` is unambiguously "never updated" because (i) the slot is only written by `updateMultiplier`'s aggregate update path; (ii) `updateMultiplier` always writes a nonzero value post-cold-start (sum of at least one nonzero per-pool EMA after F-D15's seed ensures EMASampler returns nonzero values for any sampled pool); (iii) no constructor pre-seed. Same sentinel reasoning as F-D15: a zero baseline is provably "never written" given the write surface.

**Edge case — pre-Stage-J empty Miliarium set.** Placeholder `IMiliariumRegistry` returns `miliariumPoolsCount() == 0`, so `currentProtocolAggregateEMA = sum of empty set = 0`. First `updateMultiplier` call would attempt to seed `lastProtocolAggregateEMA = 0`, leaving the sentinel unchanged. But this code path is unreachable: `updateMultiplier(pool)` reverts `NotMiliariumPool` per F-D16 before reaching the aggregate computation. F-D18's seed runs only after Stage J ships the MiliariumRegistry with at least one pool, at which point `currentProtocolAggregateEMA > 0` (post-F-D15 EMASampler seed) and the sentinel transitions cleanly.

**Edge case — single Miliarium pool active.** Pre-full-constellation Stage J could ship the registry incrementally (one pool at a time). With one Miliarium pool, `protocolTVLEMA = pool's EMA`, `miliariumAvgEMA = pool's EMA / 28`. The sole pool's `delta_intra` registers as far above `miliariumAvgEMA` (its own EMA is 28× the mean), pushing `M_i` downward per F-D19 anti-cyclical polarity. Correct math given the constellation isn't full but operationally degenerate. Not Stage F's concern: production Stage J ships the full 28-pool registry per `04_tokenomics.md` §vii.

**Cross-references:**

- **F-D15** — same cold-start sentinel pattern (per-pool EMASampler vs protocol-wide CCBMultiplier); F-D18 mirrors F-D15's design rationale at a different scope.
- **OQ-23 (iii.b)** (FINDINGS L1208) — protocol-aggregate-EMA definition + direction-comparison rule; F-D18 fills the first-epoch behavior gap.
- **F-D9 / F-D16** — Miliarium-only scope; aggregate is summed only over Miliarium pools, not all gauged pools.

**Test surface flagged for F3.4:**

- First `updateMultiplier` across protocol seeds `lastProtocolAggregateEMA = currentProtocolAggregateEMA`; `delta_global` for that epoch's pool is `0`.
- Second `updateMultiplier` at next epoch with aggregate movement above dead-zone yields nonzero `delta_global`.
- Second `updateMultiplier` at next epoch with aggregate movement below dead-zone yields `delta_global = 0`.
- First `updateMultiplier` does NOT cause universal `M_i` shift across Miliarium pools (verifies seed-and-zero, not formula-always).
- Sentinel is one-shot: subsequent calls do not re-seed even if `currentProtocolAggregateEMA == lastProtocolAggregateEMA` momentarily.

---

### F-D19 — F-8 anti-cyclical sign convention; relative-band dead-zone with strict inequalities; baselines guarded by F-D15 + F-D18 seeds

**Resolved 2026-04-30 at F3.2.5.** F-8's `delta_global` and `delta_intra_i` follow F-8's anti-cyclical narrative authority in `11_formulas.md`: rising aggregate TVL applies *downward* pressure on `M_i` (`delta_global = −STEP_SIZE` outside the dead zone); falling aggregate applies *upward* pressure (`+STEP_SIZE`). Per-channel polarity:

- `delta_global = −STEP_SIZE` when `currentProtocolAggregateEMA > lastProtocolAggregateEMA × (FixedPoint.ONE + DEAD_ZONE) / FixedPoint.ONE`.
- `delta_global = +STEP_SIZE` when `currentProtocolAggregateEMA < lastProtocolAggregateEMA × (FixedPoint.ONE − DEAD_ZONE) / FixedPoint.ONE`.
- `delta_global = 0` otherwise (relative move within `±DEAD_ZONE` of the seeded baseline; equality at boundary stays neutral).
- `delta_intra_i = −STEP_SIZE` when `poolEMA > miliariumAvgEMA × (FixedPoint.ONE + DEAD_ZONE) / FixedPoint.ONE`.
- `delta_intra_i = +STEP_SIZE` when `poolEMA < miliariumAvgEMA × (FixedPoint.ONE − DEAD_ZONE) / FixedPoint.ONE`.
- `delta_intra_i = 0` otherwise.

**The gap.** OQ-23 (i) at FINDINGS L1234, (ii.c) at L1206, (iv.a) at L1210, and (v.b) at L1228 each frame F-8 as anti-cyclical in narrative — "signal-aligned channels (both saying 'shrink' or both 'grow')", "dominant pools see `delta_intra` pushing them down", "rising aggregate + faster-than-average growth both push `delta_global` and `delta_intra` downward". OQ-23 (iii.b) at L1208 introduces the term "next-epoch direction comparison" and pins `lastProtocolAggregateEMA` storage for that comparison, but the resolution body does not include an explicit polarity formula. F-D18 at L119 attributes a procyclical reading `delta_global = sign(curr − last) × STEP_SIZE` to OQ-23 (iii.b) when in fact FINDINGS L1208 only pins the aggregate definition + baseline storage, not polarity. Risk path absent F-D19: an implementer reads "direction comparison" (or F-D18's quoted shorthand) and writes the naive `sign(currentAgg − lastAgg) × STEP_SIZE`, which is *procyclical* and contradicts F-8's spec narrative + (v.b)'s rejection rationale. F-D19 closes the gap by making polarity explicit at NOTES authority for downstream `Must match` consumption; F-D18's seed-and-zero mechanic is independent of polarity and unchanged.

**F-8 spec authority.** `11_formulas.md` F-8 narrative pins anti-cyclical direction in both channels: rising TVL applies downward pressure on the multiplier; falling TVL applies upward pressure; pools growing faster than average are nudged down; pools shrinking relative to average are nudged up. F-D19 maps this directly to the polarity table above.

**Why strict inequalities at the dead-zone boundary.** Equality `currentAgg == lastAgg × (FixedPoint.ONE ± DEAD_ZONE) / FixedPoint.ONE` denotes a relative move *exactly* at the 0.1% boundary. F-8 narrative reads "if the TVL ratio is within the dead zone of neutral, no step is applied" — the boundary is part of "within". Strict `<` / `>` at the firing path keeps boundary cases in the neutral band; the inverse choice (`<=` / `>=` firing) would emit `±STEP_SIZE` for a movement that is exactly the threshold, contradicting the "within" framing.

**Why relative-band-against-baseline rather than absolute |Δ|.** `DEAD_ZONE = 1e15` is 0.1% of `FixedPoint.ONE = 1e18`, not 0.1% of TVL in svZCHF. Reading `|currentAgg − lastAgg| < DEAD_ZONE` literally yields a 1e15-wei svZCHF threshold ≈ 0.001 svZCHF — vanishing against any real protocol TVL, so the dead zone would never fire. The relative formulation `current vs last × (FixedPoint.ONE ± DEAD_ZONE) / FixedPoint.ONE` reads as `|Δ/last| < 0.1%`, matching OQ-23 (ii.c)'s "TVL ratio" framing and `10_constitution.md` §xxix's "0.1% nominal threshold" framing. Multiplication-form preserves precision; an explicit `mulDiv(abs(Δ), FixedPoint.ONE, last)` div-form risks precision loss when `last` is large and `Δ` is small relative to it (the realistic case for daily aggregate movement).

**Baseline guards — why no zero-baseline divide.** `lastProtocolAggregateEMA × (FixedPoint.ONE ± DEAD_ZONE) / FixedPoint.ONE` operates on a zero baseline only if `lastProtocolAggregateEMA == 0`. F-D18's first-epoch seed writes `lastProtocolAggregateEMA = currentProtocolAggregateEMA` and forces `delta_global = 0` for that epoch *before* the dead-zone gate runs, so the gate never sees a zero baseline. Symmetrically: `miliariumAvgEMA = currentProtocolAggregateEMA / 28` is nonzero whenever the Miliarium pool set has at least one pool with a nonzero EMA — guaranteed post-F-D15 seed for any sampled pool. The empty-Miliarium-set degeneracy is unreachable per F-D16's `NotMiliariumPool` revert ahead of any aggregate computation. `CCBMultiplier`'s implementation does *not* need explicit zero-baseline branches; F-D15 + F-D18 + F-D16 form the layered precondition.

**Cross-references:**

- **F-8** (`11_formulas.md`) — anti-cyclical narrative authority for both channels; F-D19's polarity table is the literal mapping.
- **OQ-23 (i)** (FINDINGS L1234) — "signal-aligned channels" anti-cyclical confirmation in `Why (i.a) over (i.b)` rationale.
- **OQ-23 (ii.c)** (FINDINGS L1206) — "TVL ratio" framing matches relative-band formulation.
- **OQ-23 (iii.b)** (FINDINGS L1208) — direction-comparison shorthand reconciled here; aggregate definition + baseline storage pinned in (iii.b), polarity unspecified in resolution body.
- **OQ-23 (iv.a)** (FINDINGS L1210) — intra anti-cyclical narrative quoted directly from the (iv.a) resolution bullet ("dominant pools see `delta_intra` pushing them down, small pools see it pushing them up").
- **OQ-23 (iv.a) supplementary** (FINDINGS L1244–L1246) — `Why (iv.a) over (iv.b)` rationale: TVL-weighted mean has a perverse minimal-correction property for dominant pools, contradicting F-8 anti-cyclical intent.
- **OQ-23 (v.b)** (FINDINGS L1228) — `(v.b)` rejection rationale explicitly cites anti-cyclical polarity ("rising aggregate + faster-than-average growth both push `delta_global` and `delta_intra` downward").
- **F-D7** (`STAGE_F_PLAN.md` L61) — `STEP_SIZE = 5e16`, `DEAD_ZONE = 1e15`, `CLAMP = [75e16, 125e16]`. Constants unchanged.
- **F-D15** (`STAGE_F_NOTES.md` L23) — per-pool EMA cold-start seed; ensures `poolEMA > 0` for any sampled pool.
- **F-D17** (`STAGE_F_NOTES.md` L84) — boost window suspends F-8 state evolution; F-D19 polarity rules apply only outside boost windows.
- **F-D18** (`STAGE_F_NOTES.md` L115) — `lastProtocolAggregateEMA` cold-start seed; first-epoch `delta_global = 0` ensures dead-zone gate never operates against a zero baseline. F-D18's L119 attribution of the procyclical formula to OQ-23 (iii.b) is corrected here at the polarity layer; F-D18's seed-and-zero resolution mechanic is unchanged. F-D18's L131 single-pool-degeneracy direction ("pushing `M_i` upward") is inconsistent with F-D19's polarity table and is scheduled for one-sentence reconciliation at F3.2.6 before F3.3 lands.

**Test surface flagged for F3.4:**

- Aggregate growth above `DEAD_ZONE`: `delta_global = −STEP_SIZE` (anti-cyclical down).
- Aggregate decline below `−DEAD_ZONE`: `delta_global = +STEP_SIZE` (anti-cyclical up).
- Aggregate flat (`currentAgg == lastAgg`): `delta_global = 0` (strict inequality keeps boundary neutral).
- Aggregate exactly at upper boundary (`currentAgg == lastAgg × (FixedPoint.ONE + DEAD_ZONE) / FixedPoint.ONE`): `delta_global = 0`.
- Aggregate one wei above upper boundary: `delta_global = −STEP_SIZE`.
- Aggregate one wei below lower boundary: `delta_global = +STEP_SIZE`.
- Pool above `miliariumAvgEMA × (FixedPoint.ONE + DEAD_ZONE) / FixedPoint.ONE`: `delta_intra = −STEP_SIZE`.
- Pool below `miliariumAvgEMA × (FixedPoint.ONE − DEAD_ZONE) / FixedPoint.ONE`: `delta_intra = +STEP_SIZE`.
- Pool exactly at mean: `delta_intra = 0`.
- Combined alignment (aggregate growing AND pool above mean): total Δ `= −2 × STEP_SIZE`; channels reinforce.
- Combined opposition (aggregate growing BUT pool below mean): total Δ `= 0`; channels cancel.
- Boundary-exact combinations: dead-zone strict-inequality boundary applied per channel independently, so global-fires + intra-neutral and global-neutral + intra-fires both reachable in adjacent test cases.

---

### F-D20 — `IMiliariumRegistry` one-shot setter: sealed-after-first-write owner-once setter

**Resolved 2026-05-02 at F3.2.7.** `CCBMultiplier`'s constructor takes a placeholder `IMiliariumRegistry` address and stores `msg.sender` as `registrySetter` in a mutable storage slot. A function `setMiliariumRegistry(IMiliariumRegistry newRegistry)` checks `msg.sender == registrySetter` (revert `OnlyRegistrySetter()` otherwise), checks `address(newRegistry) != address(0)` (revert `InvalidRegistry()` otherwise), writes `miliariumRegistry = newRegistry`, then writes `registrySetter = address(0)` to seal the setter permanently. Subsequent `setMiliariumRegistry` calls fail at the `OnlyRegistrySetter()` check because no caller can hold `address(0)`. Custom error names are illustrative and may be refined at the implementation sub-step.

**The gap.** F-D9 pins the operational shape — "deployment uses a placeholder registry address that Stage J's `MiliariumRegistry.sol` deployment script replaces via a one-shot setter (same pattern as Stage G's gauge-registry → governance dependency)" — but does not enumerate the access-control mechanism for the setter call itself. Three implementations satisfy F-D9 with different permanent governance surfaces.

**Why option (a) — sealed-after-first-write owner-once setter:**

- **(b) Authorizer-gated multi-shot setter (`AureumAuthorizer`-checked).** The Authorizer is the governance Safe multisig per CLAUDE.md §2; (b) hands it the permanent power to swap the Miliarium registry indefinitely throughout protocol life. This contradicts the operational reality that registry replacement is a *one-time* deployment-handoff event from Stage F (placeholder) to Stage J (concrete). Permanent authority over a registry-swap surface is over-broad: any future Authorizer compromise (key loss, signer turnover bug, social engineering of the multisig) could swap in a malicious registry that re-classifies pools and corrupts F-8 multiplier scoring across the entire 28-pool Miliarium constellation. The sealed-after-first-write design eliminates this attack surface by construction.
- **(c) Immutable address known at constructor time.** Operationally infeasible: `CCBMultiplier` deploys at Stage F, before Stage J ships the concrete `MiliariumRegistry`, so the registry address does not exist at constructor time. Even if deployment order were reversed, tying the registry address to `CCBMultiplier`'s bytecode prevents any future protocol upgrade that re-deploys the registry against the same multiplier (e.g. registry bugfix that doesn't require multiplier redeployment).

**Setter-self-disable mechanic.** `registrySetter` is `address public` (mutable), not `immutable`. Successful `setMiliariumRegistry` execution overwrites the slot to `address(0)` in the same transaction. Any subsequent caller (including the original deployer) fails the `msg.sender == registrySetter` check because `address(0)` cannot transact. Single SSTORE on activation, single SLOAD on subsequent calls; the `OnlyRegistrySetter()` revert path is the same for "called by wrong address" and "called after sealing" — both are unauthorized, the user-facing distinction is recoverable from `registrySetter()` view (returns `address(0)` post-seal). A separate `bool sealed` flag with a distinct `RegistryAlreadyPinned()` error is rejected as redundant storage; the post-seal `registrySetter == address(0)` state is itself the seal.

**Pre-Stage-J behavior.** Until `setMiliariumRegistry` is called, the placeholder registry returns `false` for every `isMiliarium(pool)` query (per F-D9). This causes every `updateMultiplier(pool)` call to revert `NotMiliariumPool(pool)` per F-D16. Acceptable: pre-Stage-J the gauge-emission machinery is not running (Stage G ships gauge approval; Stage H ships emissions; both gate on Stage J's registry being live). The `CCBMultiplier` contract is deployed for fork-test integration and forward wiring; production activation requires the Stage J handoff regardless.

**Cross-references:**

- **F-D9** (`STAGE_F_PLAN.md` L63) — operational shape pinned (placeholder + Stage J one-shot replacement); F-D20 specifies the access-control mechanic.
- **C-D2 lineage** — AuMM minter-once setter pattern (Stage C); F-D20 inherits the same sealed-after-first-write shape at the registry-replacement layer. Stage G's gauge-registry → governance handoff per F-D9's parallel reference is the next consumer of the same pattern.
- **CLAUDE.md §2** — `AureumAuthorizer` is the governance Safe multisig during Stages A–K; F-D20's rejection of (b) protects the Miliarium classification surface from the Authorizer's permanent reach.
- **F-D16** (`STAGE_F_NOTES.md` L54) — pre-Stage-J `updateMultiplier` revert path; F-D20's seal mechanism does not change this — pre-seal calls still revert at the F-D16 Miliarium check because the placeholder returns `false`.

**Test surface flagged for F3.4:**

- Constructor stores `msg.sender` in `registrySetter`; `miliariumRegistry` initialized to placeholder.
- `setMiliariumRegistry(addr)` from `registrySetter` succeeds, writes `miliariumRegistry = addr`, zeros `registrySetter`.
- `setMiliariumRegistry(addr)` from non-deployer reverts `OnlyRegistrySetter()` before any state change.
- `setMiliariumRegistry(addr2)` after a prior successful seal reverts `OnlyRegistrySetter()` regardless of caller.
- `setMiliariumRegistry(address(0))` from `registrySetter` reverts `InvalidRegistry()` (protects against an accidental zero-address pin that would brick the contract permanently).
- Post-seal `registrySetter()` view returns `address(0)`; post-seal `miliariumRegistry()` view returns the pinned address.

---

### F-D21 — `updateMultiplier(pool)` during active boost: full silent no-op (no cadence tick, no `M_i` write, no aggregate-baseline update); supersedes F-D17 L110

**Resolved 2026-05-02 at F3.2.7.** When `updateMultiplier(pool)` is called for a pool with `block.number < boostExpiryBlock[pool]`, the function returns silently after the cadence and Miliarium gates without modifying any state — no `M_i[pool]` write, no `lastMultiplierUpdateBlock[pool]` advance, no `lastProtocolAggregateEMA` update. Order of checks inside `updateMultiplier`: (1) Miliarium check per F-D16 (revert `NotMiliariumPool(pool)` if false); (2) cadence guard per F-D6 (revert `TooEarly(...)` if `block.number < lastMultiplierUpdateBlock[pool] + BLOCKS_PER_EPOCH`); (3) boost-skip branch (return silently if `block.number < boostExpiryBlock[pool]`); (4) F-8 evolution per F-D18 + F-D19. Boost-skip is downstream of cadence — a too-early call during boost still reverts `TooEarly` rather than silently returning. Supersedes F-D17 L110's test-surface bullet (which read "ticks `lastMultiplierUpdateBlock` but leaves `M_i[pool]` unchanged"); L110 is rewritten at this sub-step to align with F-D21.

**The gap.** OQ-23 (v.d) (FINDINGS L1212-L1230) pins "F-8 paused during window" — boost gates effective output to `BOOST_FACTOR` AND pauses F-8 state evolution during the 90-day window. Two implementation readings of "paused":

- **(i) Tick the cadence, skip the `M_i` write.** `updateMultiplier(pool)` advances `lastMultiplierUpdateBlock[pool]` by `BLOCKS_PER_EPOCH` but does not change `M_i[pool]`. The visible per-epoch cadence machine continues; only the `M_i` side effect is suppressed. F-D17 L110's original framing.
- **(ii) Full no-op.** `updateMultiplier(pool)` makes no state changes — neither cadence advance, nor `M_i` write, nor protocol-aggregate baseline update. The boost makes the per-pool epoch machine completely invisible to external callers.

**Why option (ii) — full no-op:**

- **Phantom epoch alignment.** `GAUGE_BOOST_DURATION_BLOCKS = 648,000 ≈ 6.43 × BLOCKS_PER_EPOCH (100,800)`. Under (i), six phantom cadence ticks would land mid-boost, advancing `lastMultiplierUpdateBlock` to a position with no semantic meaning — the epoch boundary is the moment when `M_i` would have been written, but no `M_i` write happens. At boost expiry, the next eligible epoch fires from whatever phantom-ticked position is most recent — typically a multi-week drift away from the cadence the pool would have had absent boost. Under (ii), `lastMultiplierUpdateBlock` is whatever it was at boost activation; the next eligible epoch fires `BLOCKS_PER_EPOCH` after that, with no phantom advance to clean up. The post-boost cadence is exactly the pre-boost cadence shifted forward by the boost's call-time elapsed.
- **Pause-means-pause semantics.** OQ-23 (v.d)'s "F-8 paused" reads as "the F-8 state machine is suspended" — pausing a state machine means no transitions, including the cadence-advance transition that (i) preserves. Under (i), part of the state machine continues running, which is incongruent with the "paused" framing across all of F-8's surface (M_i, cadence, aggregate baseline). (ii) makes "paused" mean one thing everywhere.
- **Knock-on: protocol aggregate baseline.** F-D18 pins `lastProtocolAggregateEMA` updated as part of `updateMultiplier`'s aggregate-computation path. Under (i)'s "tick but skip M_i" reading, whether the aggregate-baseline update fires is a separate decision (both readings are F-D18-compatible). Under (ii)'s full no-op, the aggregate baseline is not touched for the boosted-pool call; pause-means-pause applies uniformly. (ii) makes the F-D18 question moot for boosted pools — the next non-boosted pool's `updateMultiplier` call drives the aggregate baseline update.
- **Stage H caller simplicity.** Stage H's emission distributor calls `updateMultiplier` on all eligible pools per epoch (per F-D6 / F-D10). Under (ii), Stage H does not need to know which pools are boosted — the call returns silently for boosted pools and updates state for non-boosted pools. Under (i), the cadence-tick-but-no-M_i-write behavior is visible to any orchestrator that reads `lastMultiplierUpdateBlock` between epochs (e.g. a stale-state checker or emergency-recovery script), creating a misleading "epoch ran but multiplier didn't update" inference path.

**Why silent no-op rather than revert.** A revert (e.g. `BoostActive(pool)`) would force Stage H's distributor to either pre-filter boosted pools or wrap calls in try/catch, coupling the distributor to `CCBMultiplier`'s boost machinery. Silent no-op is the natural "I'm busy, skip me" signal at the abstraction boundary. Contrast: F-D17's `activateBoost` reverts on double-call because the alternative (silently extending the window) is *wrong semantics*, not just a wasted call. F-D16's `updateMultiplier(nonMiliariumPool)` reverts because the call is a *caller-side wiring bug*. During boost, `updateMultiplier(pool)` is the correct call from a correct caller at the correct time — just suppressed by the pause window — so silent return is the right primitive. The cost is a wasted gas allotment per boosted pool per epoch (the cadence and Miliarium gates each fire, then the boost-skip branch returns; on the order of a few thousand gas per skipped call).

**Boundary behavior at boost expiry.** The boost-skip branch uses strict inequality `block.number < boostExpiryBlock[pool]`, matching F-D17 L111's `getMultiplier` boundary convention. At exactly `block.number == boostExpiryBlock[pool]`, the boost branch does NOT fire and `updateMultiplier` proceeds to F-8 evolution: `M_i[pool]` is written per F-D19 polarity rules, `lastMultiplierUpdateBlock[pool] = block.number`, `lastProtocolAggregateEMA` updated. Per OQ-23 (v.d), F-8 evolution resumes from `M_i = INITIAL_MULTIPLIER = 1e18` baseline — the implementation MUST reset `M_i[pool]` to `1e18` at boost-end if it was written to during pre-boost protocol life; the natural way is to leave `M_i[pool]` at its `1e18` initialization throughout boost (since (ii) suppresses M_i writes during boost) and let F-8 evolution take over from there. No special "first post-boost call" branch needed — `M_i[pool]` is already at `1e18` because nothing wrote to it during boost.

**Cross-references:**

- **OQ-23 (v.d)** (FINDINGS L1212-L1230) — "F-8 paused" framing; F-D21 specifies that pause covers the cadence tick AND aggregate baseline update, not just `M_i` writes.
- **F-D17** (`STAGE_F_NOTES.md` L84) — boost activation + double-call revert; F-D17 L110 test-surface bullet superseded at this sub-step to align with full no-op (rewritten in-place).
- **F-D18** (`STAGE_F_NOTES.md` L115) — protocol aggregate baseline; F-D21 pause includes the baseline update for boosted-pool calls. The aggregate baseline still updates on non-boosted pools' `updateMultiplier` calls within the same epoch.
- **F-D19** (`STAGE_F_NOTES.md` L149) — anti-cyclical polarity rules; apply at the post-boost-expiry `updateMultiplier` call from a clean `M_i[pool] = 1e18` baseline.
- **F-D6** (`STAGE_F_PLAN.md` L60) — cadence guard; the cadence check fires before the boost-skip branch, so a too-early call during boost reverts `TooEarly` rather than silently returning.
- **F-D16** (`STAGE_F_NOTES.md` L54) — `NotMiliariumPool` revert; the Miliarium check fires before both the cadence and the boost-skip branch (a non-Miliarium boosted pool is unreachable per F-D17's Miliarium gate on `activateBoost`, but the layered check defends in depth).

**Test surface flagged for F3.4:**

- `updateMultiplier(pool)` during boost (`block.number < boostExpiryBlock[pool]`, cadence satisfied) returns without state change: `M_i[pool]`, `lastMultiplierUpdateBlock[pool]`, `lastProtocolAggregateEMA` all unchanged.
- `updateMultiplier(pool)` during boost called too early (cadence not yet satisfied) reverts `TooEarly(...)` per F-D6 — boost-skip is downstream of cadence.
- `updateMultiplier(nonMiliariumBoostedPool)` reverts `NotMiliariumPool(pool)` per F-D16 (theoretical — F-D17's `activateBoost` gate prevents the precondition, but the layered defense fires).
- `updateMultiplier(pool)` at exactly `block.number == boostExpiryBlock[pool]` updates state per F-D19 (boost expired, F-8 cadence resumes from `M_i = 1e18`).
- Multi-pool scenario: `updateMultiplier(boostedPool)` silent + `updateMultiplier(unboostedPool)` real-update in the same epoch — verifies aggregate-baseline update fires only on the unboosted call's path.
- Post-expiry first call: `M_i[pool]` is `1e18` going in (never written during boost); F-8 evolution writes per F-D19 polarity from this baseline.

---

### F-D22 — `IEMASampler` read-only interface; `CCBMultiplier` reads via interface, never calls `updateEMA`

**Resolved 2026-05-02 at F3.2.7.** `CCBMultiplier` reads per-pool EMA values through an injected `IEMASampler` view interface — `tvlEMA(address pool) external view returns (uint256)` and `lastEMAUpdateBlock(address pool) external view returns (uint256)`. The interface does not expose `updateEMA(pool)`; `CCBMultiplier` never refreshes the EMA itself. Stage H's emission distributor is the natural ordering layer: refresh EMA via `EMASampler.updateEMA` first, then call `updateMultiplier`. The concrete `EMASampler` (per F1.3 commit `b01bdcc`) satisfies the interface via Solidity's auto-generated getters on its `public` mappings; no implementation change to `EMASampler.sol` is required. The interface file `src/ccb/IEMASampler.sol` lands as a separate sub-step (F3.2b) after this NOTES amendment.

**The gap.** F-D5 pins permissionless `updateEMA` (anyone can call once per `BLOCKS_PER_DAY`); F-D6 pins permissionless `updateMultiplier` (anyone can call once per `BLOCKS_PER_EPOCH`). Both cadences are independent. The unspecified question is whether `CCBMultiplier`'s consumption of EMA values reads through a concrete-type binding, a write+read interface, or a read-only interface — three designs with different mock surfaces, gas profiles, and side-effect coupling.

**Why option (α) — read-only interface:**

- **(β) Read + write interface (`updateEMA` exposed; CCBMultiplier opportunistically refreshes).** Couples per-day EMA cadence with per-epoch multiplier cadence inside `CCBMultiplier`'s call path. `BLOCKS_PER_DAY = 7,200`; `BLOCKS_PER_EPOCH = 100,800` (= 14 × `BLOCKS_PER_DAY`). One epoch spans 14 EMA-refresh windows; (β) would force `CCBMultiplier` to either (β.1) call `updateEMA` once per `updateMultiplier` (refreshing only the most recent EMA window despite 13 other unsampled days during the epoch — semantically wrong, the EMA reads stale data 13 days deep), (β.2) call `updateEMA` 14 times in a loop (gas-prohibitive and shifts cadence-skip detection into `CCBMultiplier`), or (β.3) skip the refresh and accept potentially-stale EMA reads (defeating the purpose of (β)). All three are worse than separating concerns at the interface boundary.
- **(γ) Concrete-type binding (no interface).** Requires `CCBMultiplier.t.sol` to deploy a real `EMASampler` plus its `ITVLOracle` mock, then drive synthetic spot-TVL signals through the EMASampler cadence to set up multiplier-test fixtures. Inflates test setup by 100+ LOC per test path and entangles `CCBMultiplier`'s tests with `EMASampler`'s cadence-guard semantics. (α)'s thin interface lets `MockEMASampler` be a single-mapping setter — `setTVLEMA(pool, value)` — keeping `CCBMultiplier` tests focused on F-8 multiplier semantics.
- **Stage H ordering responsibility.** Stage H's distributor explicitly orders state refreshes per epoch: refresh all eligible pools' EMA via `EMASampler.updateEMA`, then call `CCBMultiplier.updateMultiplier`, then read `EMASampler.tvlEMA` + `CCBMultiplier.getMultiplier` for scoring. This ordering is Stage H's responsibility, not `CCBMultiplier`'s. (α) reflects the responsibility boundary: `CCBMultiplier` consumes EMA reads as inputs; Stage H ensures the inputs are fresh.

**Interface shape — what's exposed and what's not.** `IEMASampler` exposes only the two view getters that `CCBMultiplier`'s F-8 computation requires:

- `tvlEMA(address pool) external view returns (uint256)` — per-pool EMA value, used in `delta_intra_i` and `protocolTVLEMA` summation.
- `lastEMAUpdateBlock(address pool) external view returns (uint256)` — sampling-recency check; not required for F-8 itself but included now to avoid a Stage H amendment when stale-EMA guard logic ships.

Not exposed: `updateEMA(address pool)`, `oracle()`, intra-day TWAP accumulator state. These are concrete-`EMASampler` implementation details with no consumer outside Stage F internals and Stage H's update-orchestration layer (which calls `EMASampler` directly via concrete type, not through the interface).

**File location and shape.** `src/ccb/IEMASampler.sol`, `pragma solidity ^0.8.26`, `SPDX-License-Identifier: GPL-3.0-or-later`. Mirrors `IGaugeRegistry.sol` (F3.2 commit `f30e720`) and `IMiliariumRegistry.sol` (F3.1 commit `d967141`) — single interface declaration, NatSpec `@notice` per method, no inheritance. Approximately 14 LOC.

**No `EMASampler.sol` change required.** The concrete `EMASampler.sol` (F1.3) declares `mapping(address => uint256) public tvlEMA` and `mapping(address => uint256) public lastEMAUpdateBlock` — Solidity auto-generates `external view` accessor functions whose signatures match the `IEMASampler` interface exactly. `EMASampler` satisfies `IEMASampler` implicitly without an explicit `is IEMASampler` declaration. F-D22 does not require touching the concrete contract; the interface lands as a new file at F3.2b and `CCBMultiplier` (F3.3+) reads through it.

**Cross-references:**

- **F-D5** (`STAGE_F_PLAN.md` L59) — permissionless `updateEMA`; F-D22 lifts the `updateEMA` call out of `CCBMultiplier`'s path entirely, keeping the read/write-cadence separation clean.
- **F-D6** (`STAGE_F_PLAN.md` L60) — permissionless `updateMultiplier`; cadence independence from F-D5 motivates the interface separation rather than collapsing both cadences into one contract.
- **F-D11** (`STAGE_F_PLAN.md` L65) — test layout; mock-`EMASampler` pattern matches the F1 mock-`ITVLOracle` and F3 mock-`IMiliariumRegistry` (per F-D16) shapes.
- **`src/ccb/EMASampler.sol`** (F1.3 commit `b01bdcc`) — concrete contract; `public tvlEMA` and `public lastEMAUpdateBlock` mappings satisfy the interface via Solidity's auto-generated getters.
- **`src/ccb/IGaugeRegistry.sol`** (F3.2 commit `f30e720`) — peer interface shape; F3.2b `IEMASampler.sol` mirrors NatSpec + structure.
- **`src/ccb/IMiliariumRegistry.sol`** (F3.1 commit `d967141`) — peer interface shape; same.

**Test surface flagged for F3.4:**

- `MockEMASampler.setTVLEMA(pool, value)` setter populates the mock's per-pool EMA without requiring oracle wiring or cadence-guard advances.
- `MockEMASampler.setLastEMAUpdateBlock(pool, value)` setter populates the recency slot for any future stale-EMA guard tests.
- `CCBMultiplier` reads `tvlEMA(pool)` through the `IEMASampler` interface; mock returns the configured value; no `updateEMA` call originates from `CCBMultiplier`.
- `MockEMASampler` defaults to zero for unconfigured pools; F-D15-style cold-start behavior is upstream of the interface boundary and tested in `EMASampler.t.sol`, not at the `CCBMultiplier` layer.
- Type check: a `CCBMultiplier` constructor argument typed as `IEMASampler` accepts a deployed concrete `EMASampler` instance without explicit cast (verifies the implicit interface satisfaction).

---

### F-D23 — `IGaugeRegistry` one-shot setter: parallel sealed-after-first-write setter (mirrors F-D20)

**Resolved 2026-05-04 at F3.2.8.** `CCBMultiplier`'s constructor takes a placeholder `IGaugeRegistry` address and stores `msg.sender` as `gaugeRegistrySetter` in a mutable storage slot. A function `setGaugeRegistry(IGaugeRegistry newRegistry)` checks `msg.sender == gaugeRegistrySetter` (revert `OnlyGaugeRegistrySetter()` otherwise), checks `address(newRegistry) != address(0)` (revert `InvalidRegistry()` otherwise), writes `gaugeRegistry = newRegistry`, then writes `gaugeRegistrySetter = address(0)` to seal the setter permanently. Subsequent `setGaugeRegistry` calls fail at the `OnlyGaugeRegistrySetter()` check because no caller can hold `address(0)`. Custom error names are illustrative and may be refined at the implementation sub-step.

**The gap.** F-D9 pins the operational shape for both registries — Stage F deployment binds placeholder addresses; Stage G replaces the gauge registry and Stage J replaces the Miliarium registry via one-shot setters — and F-D20 authors the Miliarium-side access-control mechanic in full. F-D20 L219 references Stage G's gauge handoff as the "next consumer of the same pattern" without specifying whether setter authority is a **second slot** parallel to `registrySetter` or a **shared** slot gating both `setMiliariumRegistry` and `setGaugeRegistry`. F3.3a's storage layout requires an explicit choice; transitivity-only NatSpec risks ambiguity for downstream reviewers.

**Why option (a) — parallel `gaugeRegistrySetter` slot, independent seal:**

- **(b) Shared `registrySetter` gating both setters.** One successful handoff zeros the sole authority slot; whichever registry ships second cannot complete its setter call without an upgrade path the constitution avoids. Stage J's `MiliariumRegistry` and Stage G's gauge registry land on independent timelines; coupling the two handoffs is an operational footgun.

**Why not immutable constructor binding.** Same rejection class as F-D20's (c): `CCBMultiplier` deploys at Stage F before Stage G's concrete `GaugeRegistry` exists, so the production gauge address is not knowable at constructor time.

**Setter-self-disable mechanic.** Same structural shape as F-D20: `gaugeRegistrySetter` is `address public` (mutable), not `immutable`. Successful `setGaugeRegistry` execution overwrites the slot to `address(0)` in the same transaction. Post-seal `gaugeRegistrySetter()` returns `address(0)`; a separate `bool sealed` flag is redundant.

**Pre-Stage-G behavior.** Until `setGaugeRegistry` is called, tests deploy against the placeholder `IGaugeRegistry` wired at construction — matching whatever mock or stub satisfies `isGaugeApproved` for `activateBoost` harnesses per F-D17 and F3.4. Production Stage G handoff pins the real registry regardless.

**Cross-references:**

- **F-D9** (`STAGE_F_PLAN.md` L63) — gauge-registry replacement uses the same pattern as Miliarium; F-D23 specifies the parallel setter mechanic.
- **F-D20** (`STAGE_F_NOTES.md` L201) — Miliarium one-shot setter authority; F-D23 is the gauge-side twin — independent slots, independent seals, identical self-disable shape.
- **F-D17** (`STAGE_F_NOTES.md` L84) — `activateBoost` gates on `IGaugeRegistry.isGaugeApproved(msg.sender)`; consumes `gaugeRegistry` after Stage G wiring.
- **CLAUDE.md §2** — rejection of permanent Authorizer-gated multi-shot registry swap for Miliarium (F-D20 (b)) applies symmetrically to gauge; parallel sealed-after-first-write preserves that posture without coupling Stage G and Stage J ordering.

**Test surface flagged for F3.4:**

- Constructor stores `msg.sender` in `gaugeRegistrySetter`; `gaugeRegistry` initialized to placeholder.
- `setGaugeRegistry(addr)` from `gaugeRegistrySetter` succeeds, writes `gaugeRegistry = addr`, zeros `gaugeRegistrySetter`.
- `setGaugeRegistry(addr)` from non-deployer reverts `OnlyGaugeRegistrySetter()` before any state change.
- `setGaugeRegistry(addr2)` after a prior successful seal reverts `OnlyGaugeRegistrySetter()` regardless of caller.
- `setGaugeRegistry(address(0))` from `gaugeRegistrySetter` reverts `InvalidRegistry()` (blocks accidental zero-address pin).
- Post-seal `gaugeRegistrySetter()` view returns `address(0)`; post-seal `gaugeRegistry()` view returns the pinned address.
- Independence: successful `setMiliariumRegistry` does not zero `gaugeRegistrySetter`, and vice versa — ordering of the two handoffs is unconstrained.

---

### F-D24 — `activateBoost` resets `M_i[pool] = INITIAL_MULTIPLIER` on activation; closes F-D17 L92 + F-D21 L252 boost-entry baseline gap

**Resolved 2026-05-04 at F3.2.9.** `activateBoost(pool)`'s state-write list extends F-D17 L86's single write to two writes: `boostExpiryBlock[pool] = block.number + GAUGE_BOOST_DURATION_BLOCKS;` and `M_i[pool] = INITIAL_MULTIPLIER;`. The reset fires on every successful activation — initial cold-start activation, post-expiry re-activation after F-8 evolution in the gap between boosts. F-D17 L92's "fresh `M_i = 1.0` baseline" promise becomes a local invariant of `activateBoost` rather than an implicit cross-stage operational ordering assumption. F-D21 L252's "MUST reset to `1e18` at boost-end if it was written to during pre-boost protocol life" is satisfied by pinning `M_i` at activation rather than at expiry — the reset upstream of the boost window achieves the same post-boost-evolution behavior without a "first post-boost call" branch in `updateMultiplier`.

**The gap.** F-D17 L92 reads "`M_i` remains at `INITIAL_MULTIPLIER = 1e18` across the prior boost ... so a post-expiry re-activation effectively gives another 90-day boost from a fresh `M_i = 1.0` baseline." This claim only holds if `M_i[pool]` was at `INITIAL_MULTIPLIER` when boost started. F-D21's pause-during-boost keeps `M_i` constant within the window but does not pin its entry value. F-D21 L252 acknowledges the case where pre-boost F-8 evolution wrote `M_i[pool]` to a non-1e18 value ("MUST reset ... at boost-end") but contradicts itself in the next clause ("No special 'first post-boost call' branch needed — `M_i[pool]` is already at `1e18` because nothing wrote to it during boost"). The "natural way" framing presupposes the cold-start case (no pre-boost evolution); the "MUST reset" clause acknowledges the F-8-evolved case but specifies no mechanism. F3.3c's `activateBoost` implementation cannot land without a pinned mechanism for the F-8-evolved entry case.

**Why option (α) — `activateBoost` resets `M_i[pool] = INITIAL_MULTIPLIER` on every activation:**

- **(β) Pin operational invariant: boost-eligible pools never have pre-boost F-8 evolution.** Requires Stage G's gauge-approval flow to gate the first `activateBoost(pool)` ahead of any `updateMultiplier(pool)` for that pool, *and* to maintain the invariant across post-expiry windows where the pool may evolve via F-8 in the gap between boosts. The post-expiry case alone defeats (β): a pool boosted at block `t`, expired at `t + 648_000`, F-8 evolved at `t + 700_000`, re-boosted at `t + 800_000` enters the second boost with `M_i ≠ 1e18`. The cross-stage timing guarantee cannot be enforced inside Stage F.
- **(γ) `updateMultiplier` detects "first post-boost call" and resets `M_i[pool]` there.** Requires either a new tracking slot (e.g., `lastBoostExpiryProcessed[pool]`) or boundary-detection logic comparing `block.number`, `boostExpiryBlock[pool]`, and `lastMultiplierUpdateBlock[pool]`. Adds storage or conditional complexity to the hot path. Contradicts F-D21 L252's framing of "No special 'first post-boost call' branch needed" — that framing only holds if the upstream invariant (`M_i` at `1e18` entering boost) is locally enforceable, which is exactly what (α) provides.

**Cold-start interaction.** Default `M_i[pool] = 0` for never-evolved pools. F-D24's reset writes `1e18` over the `0` — equivalent in observable behavior to the cold-start "natural way" path in F-D21 L252 (the F3.3a scaffold's `M_i` NatSpec already documents that `getMultiplier` reads `0` as `INITIAL_MULTIPLIER`). The reset costs one extra SSTORE on activation in the cold-start case for no semantic gain, but the implementation cannot distinguish cold-start from post-evolution at activation-time without an extra sentinel — and the unconditional reset is simpler than per-pool sentinel tracking.

**Cost.** One additional SSTORE per `activateBoost` call. Cold-start activation is `0 → INITIAL_MULTIPLIER` (~22,100 gas); subsequent re-activations after intervening F-8 evolution are non-zero → non-zero (~5,000 gas). `activateBoost` fires at most once per 90 days per pool (per F-D17's no-renewal rule), and the 28-pool Miliarium constellation bounds total activations to ~28 per quarter. Aggregate annual gas overhead is negligible at protocol scale.

**State-write order in `activateBoost`.** F-D24 pins the order as `boostExpiryBlock[pool]` first, then `M_i[pool]`. Rationale: F-D17 L86 frames `boostExpiryBlock` as the function's primary effect ("Otherwise sets `boostExpiryBlock[pool] = ...`"); the `M_i` reset is the consistency-maintaining secondary write. Order is functionally interchangeable (no read-after-write dependency between the two slots), so the convention is documentation-first rather than gas-driven.

**Cross-references:**

- **F-D17** (`STAGE_F_NOTES.md` L84) — `activateBoost` entry-point semantics; F-D24 extends F-D17 L86's state-write list and closes F-D17 L92's "fresh `M_i = 1.0` baseline" promise locally rather than via cross-stage operational ordering.
- **F-D21** (`STAGE_F_NOTES.md` L234) — `updateMultiplier` full no-op during boost; F-D24 satisfies F-D21 L252's "MUST reset at boost-end" requirement upstream at activation, preserving F-D21 L252's "no special 'first post-boost call' branch needed" framing for `updateMultiplier`.
- **F-D7** (`STAGE_F_PLAN.md` L61) — `INITIAL_MULTIPLIER = 1e18` constant; the reset target.
- **F-D9 / F-D16** (`STAGE_F_PLAN.md` L63 / `STAGE_F_NOTES.md` L54) — Miliarium-only scope; `activateBoost`'s Miliarium gate fires before the `M_i` reset, so non-Miliarium pools never see the reset write.
- **OQ-23 (v.d)** (FINDINGS L1212-L1230) — boost composition spec; F-D24's reset implementation closes the "expiry hands off to `M_i[pool] = INITIAL_MULTIPLIER`" cross-reference (F-D17 L98) by ensuring boost entry pins `M_i` and the F-D21 pause preserves it through the window.

**Test surface flagged for F3.4 (extends F-D17 L105-L109 surface):**

- Cold-start `activateBoost(pool)`: `M_i[pool] == 0` pre-call, `M_i[pool] == INITIAL_MULTIPLIER` post-call. Boost expiry block set per F-D17 L86.
- Pre-evolved `activateBoost(pool)`: pool's `M_i[pool]` set to non-1e18 value pre-call (e.g., `0.85e18` simulating prior F-8 evolution); post-call `M_i[pool] == INITIAL_MULTIPLIER`. Boost expiry block set per F-D17.
- Post-expiry re-activation with mid-gap F-8 evolution: activate, advance past expiry, drive F-8 evolution to `M_i ≈ 0.90e18`, re-activate; `M_i` back to `INITIAL_MULTIPLIER`. Verifies F-D24 reset fires on every activation, not only the first.
- Boost-active double-call still reverts `BoostAlreadyActive(pool)` per F-D17 — no `M_i` write occurs (revert before any state change).
- Non-Miliarium / non-approved-gauge revert paths still revert per F-D17 — no `M_i` write occurs.
- Post-boost-expiry first `updateMultiplier(pool)` reads `M_i[pool] == INITIAL_MULTIPLIER` (the activation-time reset value, preserved across F-D21's pause window) and applies F-8 step from the `1e18` baseline per F-D19 polarity.

---

### F-D25 — `updateMultiplier` arithmetic-base sentinel: `M_i[pool] == 0 → INITIAL_MULTIPLIER` for F-8 evolution (closes pre-`activateBoost` permissionless `updateMultiplier` path)

**Resolved 2026-05-04 at F3.3.d.0.** When `updateMultiplier(pool)` reaches the F-8 evolution step (past Miliarium, cadence, and boost-skip gates), the prior multiplier is read as `M_i[pool] == 0 ? INITIAL_MULTIPLIER : M_i[pool]` — same `0 → INITIAL_MULTIPLIER` sentinel as `getMultiplier`. The F-8 step `M_i[pool] = clamp(prior + delta_global + delta_intra)` operates on the sentinel-resolved prior; subsequent calls read the written non-zero value directly. The sentinel branch fires at most once per pool over its lifetime.

**The gap.** Three artifacts touch the cold-start surface — (1) L84 NatSpec for `getMultiplier`, (2) F-D24's `activateBoost` reset, (3) F-D17 / F-D21 boost-entry framing — and none of them pin `updateMultiplier`'s arithmetic base when `M_i[pool] == 0` and `activateBoost` has never fired (reachable because `updateMultiplier` is permissionless per F-D6 while `activateBoost` is gauge-gated per F-D17). Naive `M_i[pool] + delta` reads literal `0`, applies delta, clamps to `CLAMP_FLOOR = 75e16` — silently locks the pool at `0.75×`.

**Why option (α) — read-time sentinel matching `getMultiplier`:**

- **(β) Revert when `M_i[pool] == 0`.** — couples `updateMultiplier`'s success path to `activateBoost` having been called; brittle across pre-Stage-G test fixtures and Stage J / Stage G handoff transitionals; cadence independence between F-D6 and F-D17 makes the coupling unenforceable inside Stage F.
- **(γ) Initialize `M_i[pool] = INITIAL_MULTIPLIER` at Miliarium-pool registration.** — requires registry → multiplier callback or event subscription; adds Stage J ↔ Stage F write-direction dependency; heavier than read-side sentinel.
- **(α)'s symmetry with `getMultiplier`.** — L84 NatSpec already pins read-side sentinel; (α) extends the same sentinel into `updateMultiplier`'s read path; no new convention, no new storage slot.

**Sentinel reliability.** `M_i[pool] == 0` is unambiguously "never written" because (i) only `updateMultiplier`'s F-8 path and `activateBoost`'s F-D24 reset write the slot; (ii) both write-paths produce values in `{INITIAL_MULTIPLIER}` ∪ `[CLAMP_FLOOR, CLAMP_CEILING] = [75e16, 125e16]` — all non-zero; (iii) no constructor pre-seed.

**Boost-window invariant preserved.** F-D21 silent no-op makes the F-8 evolution path unreachable during boost, so the sentinel never fires inside a boost window. F-D24's activation-time reset writes `M_i[pool] = INITIAL_MULTIPLIER` upstream of any boost, so post-expiry first `updateMultiplier` reads `1e18` directly from storage, not via sentinel. The sentinel's per-pool firing is genuinely once-per-lifetime: the first-ever F-8 evolution call on a never-boosted, never-evolved Miliarium pool.

**Cross-references:**

- **L84** (`src/ccb/CCBMultiplier.sol`) — read-side `M_i[pool] == 0 → INITIAL_MULTIPLIER` sentinel in `getMultiplier`; F-D25 extends the same convention into `updateMultiplier`'s F-8 arithmetic base.
- **F-D24** (`STAGE_F_NOTES.md` L351) — `activateBoost` writes `M_i[pool] = INITIAL_MULTIPLIER` on activation; cold-start and post-evolution paths upstream of permissionless evolution.
- **F-D17** (`STAGE_F_NOTES.md` L84) — `activateBoost` gauge gate vs permissionless `updateMultiplier` per F-D6; F-D25 closes the pre-boost arithmetic-base gap without coupling cadences.
- **F-D19** (`STAGE_F_NOTES.md` L149) — F-8 evolution polarity and clamp semantics; arithmetic applies after sentinel resolution of `prior`.
- **F-D21** (`STAGE_F_NOTES.md` L234) — boost-window no-op for evolution; sentinel inactive during boost.
- **F-D6** (`STAGE_F_PLAN.md` L60) — permissionless `updateMultiplier` surface motivating reachable `M_i[pool] == 0` before any `activateBoost`.

**Test surface flagged for F3.4:**

- Cold-start `updateMultiplier(MiliariumPool)` with storage `M_i[pool] == 0` writes a value in `{INITIAL_MULTIPLIER, INITIAL_MULTIPLIER ± STEP_SIZE, INITIAL_MULTIPLIER ± 2×STEP_SIZE} ∩ [CLAMP_FLOOR, CLAMP_CEILING]` (never relative to `0`); subsequent `updateMultiplier` calls on the same pool read the written non-zero value (sentinel does not re-fire); evolution post-`activateBoost` writes a value relative to `INITIAL_MULTIPLIER` (F-D24 path, sentinel unreached).

---

## Findings

> `F10` onward populates as implementation incidents emerge.

### F10 — Solidity optimizer hoists `block.number` out of `vm.roll`-driven loops

**Caught 2026-04-29 at F1.4 forge-test (commit `7e47283` corrective).** `test_updateEMA_convergesTowardSpot_overManyDays` reverted `TooEarly(727_200, 734_400)` on the *second* loop iteration; total gas usage `89_967` (close to a single-second-call test's `89_849`, far short of two successful updates plus a revert) confirmed the failure was at iteration 1, not later. The loop body `vm.roll(block.number + AureumTime.BLOCKS_PER_DAY)` was hoisted out of the loop by the Solidity optimizer (solc 0.8.26 with `via_ir = true` + 9999 runs). Because `block.number` is constant within a transaction in real EVM execution, the optimizer treats `block.number + BLOCKS_PER_DAY` as loop-invariant — and the cheatcode's effect on `block.number` is opaque to the compiler's effect model (`vm.roll` is a `CALL` to the cheatcode address with no declared semantics). Result: every iteration's `vm.roll` received the same hoisted target `START_BLOCK + BLOCKS_PER_DAY = 727_200`, advancing on iteration 0 and degenerating to a no-op for iterations 1..59. Iteration 1's `updateEMA` then reverted `TooEarly` because `last == 727_200 == block.number` and `nextEligible == 734_400`.

**Fix.** Replace `vm.roll(block.number + BLOCKS_PER_DAY)` inside the loop with an explicit local counter:

```solidity
uint256 currentBlock = START_BLOCK;
for (uint256 i = 0; i < 60; i++) {
    currentBlock += AureumTime.BLOCKS_PER_DAY;
    vm.roll(currentBlock);
    ...
}
```

**Why the fix works.** An explicit `currentBlock` counter is a loop-carried dependency: each iteration's `vm.roll(currentBlock)` depends on the mutable `currentBlock` incremented in the same body. The optimizer cannot hoist a value that is provably different on every iteration. The local variable is the correct forcing mechanism; wrapping `block.number` in a no-op function call would not help — the optimizer sees through transparent wrappers in the Yul IR.

**Why other tests in this file pass.** All other multi-call tests advance `block.number` *once* before a *single* `updateEMA` call — there is no loop with a repeated increment. `vm.roll(block.number + AureumTime.BLOCKS_PER_DAY)` outside a loop advances to the correct target on first call and is never revisited. The hoisting defect is strictly a loop-body pattern; single `vm.roll` calls are unaffected.

**Generalization for future stages.** Any test with a `for` or `while` loop that advances chain state via `vm.roll(block.number + k)` is potentially unsafe under `via_ir = true` + aggressive optimization. The safe pattern is always an explicit tracked counter incremented inside the loop body. The same caution applies to `vm.warp` (`block.timestamp`) under identical conditions.

**Cross-references:**

- **`test/unit/EMASampler.t.sol` L150-168** (`test_updateEMA_convergesTowardSpot_overManyDays`) — affected test; tracked-counter pattern applied at F1.4b.
- **Solidity `via_ir` + Yul IR optimizer** — IR compilation exposes `block.number` reads as pure SSA values with no declared side-effects; loop-invariant code motion hoists the computation before Foundry's `vm.roll` `CALL` executes.
- **F1.4b** (commit `7e47283`) — corrective commit that introduced the tracked-counter fix.

---

### F11 — Paste-rendering auto-links `FixedPoint.ONE` in chat (E-D26 recurrence at F2.2 audit)

**Caught 2026-04-29 at F2.2 save-audit.** The `cat test/unit/CCBScore.t.sol` output pasted into chat displayed `FixedPoint.ONE` as `[FixedPoint.ONE](http://FixedPoint.ONE)` throughout — in comments and in code-position `assertEq` arguments. This triggered a false ❌ Fix verdict and an unnecessary F2.2-fix Cursor sub-step (which Cursor correctly declined, reporting no artifacts on disk). Cursor's read-back also showed the hyperlink form — not a real artifact in the file, but the chat renderer converting it again.

**Root cause.** `.one` is a registered top-level domain. Markdown auto-linkers (Claude chat, Cursor's response pane) treat `FixedPoint.ONE` as `<identifier>.<tld>` and convert it to a hyperlink on render. Same pattern as **E-D26** (Stage E docs sweep).

**Bypass-grep verdict.** `grep -c "\["` on the saved file returned `0` (no `[` characters on disk), and `grep -c "(http"` returned `0`. Combined with `grep -c "FixedPoint\.ONE"` = 4 (expected count), the file was confirmed clean without relying on chat rendering.

**Procedural rule (additive to E-D26).** For any file containing tokens matching `<identifier>.<tld>` — including `FixedPoint.ONE`, method names ending in `.fi` / `.io` / `.com` — the default audit primitive is `grep -c "\["` (count opening square brackets), not `cat`. A result of `0` proves no markdown link artifacts exist on disk regardless of how chat renders the content.

**Cross-references:**

- **E-D26** (`docs/STAGE_E_NOTES.md`) — first occurrence; reclassified as paste-rendering at E5 docs sweep.
- **`test/unit/CCBScore.t.sol` L15, L19, L24** — three `FixedPoint.ONE` code positions that triggered auto-link at F2.2 audit.
- **F2.2** (`dd1baf2`) — commit whose `cat` output triggered the false ❌.

---

### F12 — Unsafe-cast `disable-next-line` suppression rejected; type discipline + `SafeCast` adopted as project standard (F3.3d-fix corrective)

**Caught 2026-05-04 at F3.3e forge-lint verify (commit `4412b2c`, F3.3d-fix combined with F3.3e per single-paste commit ergonomics).** `forge lint src/ccb/CCBMultiplier.sol` returned eight `unsafe-typecast` warnings, all on F3.3d's committed `updateMultiplier` body — four `int256(STEP_SIZE)` casts in the global / intra-pool ± step-delta arithmetic (L255, L256, L264, L265) and four `int256(CLAMP_FLOOR)` / `int256(CLAMP_CEILING)` casts in the post-step clamp (L271 ×2, L272 ×2). Two adjacent casts — `int256(prior)` (L270) and `uint256(newM)` (L276) — already carried `// forge-lint: disable-next-line(unsafe-typecast)` annotations from F3.3d, paired with multi-line numerical-bounds-justification comments. The eight uncovered casts shipped in commit `d8959de` and were not flagged at F3.3d audit because that sub-step's verify block did not include `forge lint`.

**Wrong fix initially proposed.** Six additional `// forge-lint: disable-next-line(unsafe-typecast)` annotations to cover the eight uncovered casts, matching the existing F3.3d L268-L270 / L274-L276 pattern. **Rejected.** Suppression annotations are not a fix. A `disable-next-line` paired with a numerical-bounds comment is a vow to remember the cast invariant forever — the kind of vow that survives the comment but does not survive the diff. The most consequential typecast / rounding incidents in this protocol's substrate (Balancer V2 era) reduced to assumptions of exactly this class.

**Right fix applied at F3.3d-fix (`4412b2c`).** Two-layer type discipline:

1. **Typed constants where consumed in a single signed domain.** `STEP_SIZE`, `CLAMP_FLOOR`, `CLAMP_CEILING` were declared `uint256` at F3.3a but are referenced *only* in `int256` arithmetic (the `delta_global` / `delta_intra` ± step assignments and the post-step clamp). Retyped to `int256`. Eight cast sites collapsed to bare constant references with zero runtime overhead. `DEAD_ZONE`, `INITIAL_MULTIPLIER`, `BOOST_FACTOR`, `GAUGE_BOOST_DURATION_BLOCKS`, `MILIARIUM_POOL_COUNT` stay `uint256` — each is consumed only in unsigned arithmetic.
2. **`SafeCast` for cross-domain dynamic values.** `prior` (uint256, L267) and `newM` (int256, L276) cross integer-sign domains and carry runtime values. `int256(prior)` → `prior.toInt256()` reverts `SafeCastOverflowedUintToInt` if `prior > type(int256).max`. `uint256(newM)` → `newM.toUint256()` reverts `SafeCastOverflowedIntToUint` if `newM < 0`. Both reverts are provably unreachable under the `M_i[pool]` clamp invariant — but the runtime check survives any future code path that violates the invariant, which a comment never can.

The four lines of suppression-justification comments at L268-L269 and L274-L275 were deleted. `SafeCast` makes the safety mechanical, not commentary. The file post-fix carries zero `// forge-lint: disable-next-line` directives. `forge lint src/ccb/CCBMultiplier.sol` returns zero warnings.

**Process lesson — `forge lint` is mandatory in verify blocks for files containing arithmetic.** F3.3d's verify ran `wc`, `shasum`, `cat`, `grep`, and `forge build`, but not `forge lint`. The eight unsafe casts shipped in `d8959de` and would have continued shipping had F3.3e's verify not included `forge lint` for unrelated reasons. The §8e.1 USER VERIFY default for any file under `src/` containing `int256(...)` / `uint256(...)` casts, fixed-point arithmetic, EMA / clamp / step computations, or signed-unsigned domain crossings *must* include `forge lint <path> 2>&1`. Non-arithmetic files (interfaces, pure-storage scaffolds, NatSpec-only docs commits) need not. The cost of including `forge lint` is one second of compute and zero risk; the cost of omitting it is debt accumulating under audit cover.

**Engineering lesson — declare each constant in the integer domain in which it is consumed.** The F3.3a constants block typed `STEP_SIZE` / `CLAMP_FLOOR` / `CLAMP_CEILING` as `uint256` likely because every other constant in the same block was `uint256` (block-counts, durations, pool-count). The signed-arithmetic consumption was not observed at constant-declaration time. Going forward: when consumption is single-domain, the declaration carries no cast; when consumption is cross-domain, the constant gets one declared form and `SafeCast` mediates at use sites — no anonymous typecasts.

**Anti-pattern catalog — reject on sight in this codebase:**

- `int256(uint256_value)` / `uint256(int256_value)` without a `SafeCast` substitute, except for compile-time literals demonstrably within range.
- `// forge-lint: disable-next-line(unsafe-typecast)` paired with a comment proving safety. The comment is a justification, not a check. If the safety is provable, the cast is a `SafeCast` call; if it is not provable, the cast is a bug.
- The `// casting to <type> is safe because <reason>` boilerplate lifted from forge-lint's own template. The template is a nudge to suppress; we treat it as a nudge to fix.

**Out-of-scope deferred — `erc20-unchecked-transfer` warnings in fork test harnesses.** The `forge build` run that surfaced the F3.3d casts also flagged two pre-existing `erc20-unchecked-transfer` warnings: `test/fork/PilotPools.t.sol:348` (Stage E pilot-pool `_performSwap`, `tokenIn.transfer(address(vault), inUsed);`) and `test/fork/AureumFeeRoutingHook.t.sol:382` (Stage D hook fork-test setup, `svZchf.transfer(address(vault), amountIn);`). Same class of issue: ERC20 `transfer` return-value unchecked. Both must be replaced with `SafeERC20.safeTransfer` (OZ canonical pattern); added to the Stage F deferred queue, addressable as a `stage-d/e-fix` sub-step at any natural break in F3 implementation.

**Cross-references:**

- **`src/ccb/CCBMultiplier.sol` L9, L36-L37, L44, L50, L53, L255-L276 region** — F3.3d-fix's edit surface: `SafeCast` import, `using` directives, three constant retypes, six cast simplifications, two `SafeCast`-method casts, four deleted suppression-comment lines.
- **F3.3d-fix** (commit `4412b2c`) — corrective combined with F3.3e per single-paste commit ergonomics; lands the type-discipline pattern.
- **F3.3d** (commit `d8959de`) — original `updateMultiplier` commit that shipped the unsafe casts under suppression-annotation cover. Verify block omitted `forge lint`.
- **D34** (`docs/STAGE_D_NOTES.md`) — parallel "verification surface narrower than audit surface" pattern. D34's verify ran behavioral tests but not cross-side selector assertions; F12's verify ran `forge build` but not `forge lint`. Both gaps shipped under audit cover until a later sub-step's wider verify exposed them.
- **`test/fork/PilotPools.t.sol:348`**, **`test/fork/AureumFeeRoutingHook.t.sol:382`** — deferred `erc20-unchecked-transfer` warnings; `SafeERC20.safeTransfer` replacement pending.
- **OpenZeppelin `SafeCast`** (`lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol`) — canonical bounds-checked cast library; remap `@openzeppelin/contracts/utils/math/SafeCast.sol`.

---

### F-D26 — F4 fork-harness scope: 3 pilot pools, fixed divisor 28, intra-channel always −STEP_SIZE accepted as fork-test artifact (not implementation defect)

**Resolved 2026-05-04 at F4.0.** F4 (`docs/STAGE_F_PLAN.md` Scope L35) wires Stage E's three pilot pools — ixHelvetia (slot 01), ixEdelweiss (slot 05), ixAurebit (slot 14) — through a mock `ITVLOracle` and mock `IMiliariumRegistry` / `IGaugeRegistry`, exercising the four CCB contracts end-to-end.

**Divisor mechanics.** `MILIARIUM_POOL_COUNT = 28` is a hardcoded `uint256` constant at `src/ccb/CCBMultiplier.sol` L65, consumed at L263 as `currentAgg / MILIARIUM_POOL_COUNT` to derive `miliariumAvg` for the intra-channel baseline (OQ-23 (iv.a) simple-mean Miliarium-average EMA).

**Partial constellation in fork.** With only 3 pilot pools registered in the mock `IMiliariumRegistry`, the F-D18 enumeration loop sums three EMAs into `currentAgg`; division by 28 yields `miliariumAvg ≈ currentAgg / 28`, on the order of 3/28 ≈ 10.7% of any per-pool EMA when EMAs are roughly equal across the three pilots.

**Intra-channel consequence.** Result: `poolEMA > upperBoundIntra` is true for every pilot under near-equal-TVL conditions; per F-8 evolution at L268-L269, `deltaIntra = -STEP_SIZE` for every pool every epoch. This is mechanical-divisor arithmetic, not an implementation defect.

**Rejected option (b)** — padding mock registry to count = 28 with 25 zero-address slots: `tvlEMA(0) = 0` by mapping default, so `currentAgg` is unchanged; divisor stays 28; same skew. Padding with 25 nonzero meaningful EMAs simulating production constellation dynamics is heavier than F4's lean-integration scope and still does not match mainnet truth.

**F4 assertion scope under (2a).** EMA path correctness (per-day cadence, oracle reads, F-4 smoothing); boost lifecycle (`activateBoost` → `getMultiplier == BOOST_FACTOR` → expiry → `INITIAL_MULTIPLIER`); `getMultiplier` taxonomy (non-Miliarium → `1e18`; active boost → `1.2e18`; unwritten `M_i` → `1e18`; evolved → clamped value); `CCBScore` × `CCBShare` composition (scores → normalized shares summing to `1e18`); directional intra-channel behavior (`deltaIntra = -STEP_SIZE` always under near-equal-TVL pilot configuration — assert direction, not symmetry).

**Precedent.** F-D18 (`docs/STAGE_F_NOTES.md` L115) already records partial-constellation dynamics for the cold-start single-pool case — `delta_global = 0` for the seeding epoch. F-D26 extends the same "partial constellation in test contexts produces predictable arithmetic artifacts" framing to F4's 3-pool fork case, with intra-channel direction pinned rather than aggregate-baseline seeding.

**Cross-references:**

- **F-D11** (`STAGE_F_PLAN.md` L65) — F4 test layout: `test/fork/CCBEngine.t.sol` integration test against 3 pilot pools with mock TVL oracle.
- **F-D18** (`STAGE_F_NOTES.md` L115) — partial-constellation precedent (cold-start single-pool aggregate seed).
- **OQ-23 (iii.b) / OQ-23 (iv.a)** (`docs/FINDINGS.md`) — sum-of-EMAs / simple-mean baseline definitions.
- **`04_tokenomics.md` §vii** — fixed 28-pool Miliarium constellation (canonical divisor source).
- **`src/ccb/CCBMultiplier.sol` L65** — `MILIARIUM_POOL_COUNT = 28` constant declaration.
- **`src/ccb/CCBMultiplier.sol` L263** — `miliariumAvg = currentAgg / MILIARIUM_POOL_COUNT` consumption.
- **`src/ccb/CCBMultiplier.sol` L268-L269** — `deltaIntra` ± step assignments under intra-channel inequality.

### F-D27 — Unit-test mocks must align with `MILIARIUM_POOL_COUNT == 28` divisor semantics

**Resolved 2026-05-04 at F3.4-fix2.** `CCBMultiplier.sol` L263 derives `miliariumAvg = currentAgg / MILIARIUM_POOL_COUNT` using the hardcoded canonical divisor 28 (per OQ-23 (iv.a) — `04_tokenomics.md` §vii). Unit tests using `MockMiliariumRegistry` with sub-28-pool lists produce the same partial-constellation artifact F-D26 (f) flags for fork tests: per-pool `tvlEMA` values stay above `miliariumAvg` under any reasonable uniform-TVL setup, forcing `deltaIntra = -STEP_SIZE` independent of the pool's actual intra-band relationship.

**Rule.** Unit tests asserting specific `M_i` deltas under controlled global/intra-channel direction populate the mock registry with **28 pool entries** — one focal pool (e.g. `POOL_A`) at index 0, optionally a secondary perturbed pool (e.g. `POOL_B`) at index 1, and 26-or-27 filler addresses generated via `address(uint160(0xC0FE0000 + i))` at the remaining indices. All 28 are Miliarium-flagged and seeded at uniform-baseline TVL EMA; the focal pool's EMA (and optionally the secondary's) is then perturbed for intra-channel tests, or all 28 EMAs proportionally for global-channel tests. Filler addresses participate in `currentAgg` and `miliariumAvg` arithmetic but are otherwise transparent to the assertion target.

**F-D24 separability.** Tests asserting `M_i` preservation across boost activation (e.g. `test_updateMultiplier_boostNoOp_noStateChange`) capture the snapshot AFTER `activateBoost`, not before — F-D24's reset writes `INITIAL_MULTIPLIER` at activation, invalidating any pre-activation `M_i` capture. This is orthogonal to the 28-pool divisor rule above; tests in this category remain single-pool (or sub-28-pool) when they do not assert delta-channel direction.

**Sibling tests passing under 3-pool setups.** `test_updateMultiplier_globalRising_decrement`, `test_updateMultiplier_intraAbove_decrement`, `test_updateMultiplier_channelsReinforce`, and `test_updateMultiplier_channelsCancel` retain their pre-F3.4-fix2 sub-28-pool registry setups. They pass because the partial-constellation artifact (`deltaIntra = -STEP_SIZE` always) aligns with the direction their assertions expect — a coincidence rather than a correctness property. Future test additions or refactors should follow the F-D27 rule above; these legacy tests are tolerable in current form but should not be used as a pattern.

**Cross-references:**

- **F-D26 (f)** (`STAGE_F_NOTES.md` L513) — fork-harness analog (3 pilot pools, artifact accepted via direction-only assertions); F-D27 is the unit-test counterpart (pad to 28, artifact eliminated).
- **F-D24** (`STAGE_F_NOTES.md` L351) — `activateBoost` resets `M_i[pool] = INITIAL_MULTIPLIER`; informs the boost-snapshot rule above.
- **OQ-23 (iv.a)** (`docs/FINDINGS.md`) — divisor-28 spec source.
- **`src/ccb/CCBMultiplier.sol` L65** — `MILIARIUM_POOL_COUNT = 28` constant declaration.
- **`src/ccb/CCBMultiplier.sol` L263** — `miliariumAvg = currentAgg / MILIARIUM_POOL_COUNT` consumption.
- **`test/unit/CCBMultiplier.t.sol`** — `test_updateMultiplier_globalFalling_increment`, `test_updateMultiplier_intraBelow_increment`, `test_updateMultiplier_boostNoOp_noStateChange` corrected at F3.4-fix2 per this rule.

---

### F13 — F12 type-discipline pattern extended to test-side signed-delta arithmetic (RB-004.0b corrective)

**Caught 2026-05-07 at RB-004.0b verify.** `forge lint test/unit/CCBMultiplier.t.sol` returned 19 `unsafe-typecast` warnings at RB-004.open, mirroring the F12-class pattern that `src/ccb/CCBMultiplier.sol` had already cleaned up at F3.3d-fix. The test file's clamp-band assertions and signed-delta accumulator constructions used `int256(uint256_const)` / `uint256(int256(uint256(prior)) + delta)` chains identical to the original production source before F12, plus duplicated bare typecasts at every `STEP_SIZE` / `CLAMP_FLOOR` / `CLAMP_CEILING` consumption point. The F12 fix had stopped at the `src/` boundary; the test file was the next surface to bring under the same discipline.

**Wrong fix initially proposed.** A branch-on-sign helper that selects between `base + uint256(delta)` and `base - uint256(-delta)` based on the sign of `delta`. **Rejected** — `uint256(delta)` and `uint256(-delta)` are the same unsafe-typecast pattern F12 ruled out; relocating the casts inside a helper does not eliminate them, `forge lint` would re-emit two warnings on the helper's body lines (net warning count unchanged), and `-delta` overflows when `delta == type(int256).min`. A new defect inside a helper that was supposed to remove defects.

**Right fix applied at RB-004.0b (`67ce558`).** Mirror F12's production-side pattern at file scope, in two layers:

1. **Dual-typed constants where consumption crosses domains.** `STEP_SIZE` retained as `uint256` (used in unsigned assertion arithmetic — e.g., `assertEq(multiplier.M_i(POOL_A), INITIAL_MULTIPLIER + STEP_SIZE)`); a sibling `STEP_DELTA_I256` declared as `int256` (used in signed accumulator passes). `CLAMP_FLOOR` and `CLAMP_CEILING` stay `uint256` only — they are never accumulator inputs, only assertion bounds. Eliminates 14 of 16 cast sites at constant-reference points.
2. **`SafeCast` member-function helper.** A single-line `_applySignedDelta(uint256 base, int256 delta) internal pure returns (uint256)` that computes `(base.toInt256() + delta).toUint256()`, paired with `using SafeCast for uint256;` and `using SafeCast for int256;`. `base.toInt256()` reverts `SafeCastOverflowedUintToInt` if `base > type(int256).max`; the trailing `.toUint256()` reverts `SafeCastOverflowedIntToUint` if the post-add result is negative. Both reverts are unreachable under the production `M_i[pool]` clamp invariant — same proof as the F12 production helper — but the runtime check survives any future code path that violates the invariant, which a comment never can.

**Project-wide rule — F12 covers production AND tests; zero typecast suppressions in either.** Any test exercising a stateful FixedPoint accumulator with signed deltas — or asserting against signed-arithmetic results from production — uses the same SafeCast-backed pattern as production: dual-typed constants when consumption is single-domain on both sides, and a thin SafeCast-member helper at cross-domain crossings. Branch-on-sign helpers are rejected on the same grounds as `// forge-lint: disable-next-line` directives. `forge lint` is mandatory in `### USER VERIFY` blocks for any test file that imports from a contract under `src/ccb/`, `src/fee_router/`, or any future stage with FixedPoint or signed-delta arithmetic. The F12 anti-pattern catalog applies identically in `test/`.

**Cross-references:**

- **F12** (`STAGE_F_NOTES.md` L469) — original production-side adoption; F13 extends F12's scope from `src/` to `test/`.
- **`src/ccb/CCBMultiplier.sol` L9, L36-L37, L255-L276** — production reference: SafeCast import, `using` directives, signed-delta call sites in `updateMultiplier`. Canonical implementation of the SafeCast helper pattern referenced above.
- **`test/unit/CCBMultiplier.t.sol` L10, L74-L75, L88-L91, L106** — test-side mirror: SafeCast import, `using` directives, dual-typed constants block, `_applySignedDelta` helper as adopted at RB-004.0b.
- **RB-004.0b** (`docs/ROBUSTNESS_BACKPORT_REGISTER.md`, commit `67ce558`) — corrective sub-step that landed the test-side pattern.

---

### F14 — `forge test --list` silently omits a discoverable test contract from cached artifacts; `forge clean` is the deterministic recovery (RB-004.1 verify)

**Caught 2026-05-07 at RB-004.1 verify.** The unit-test invocation `forge test --no-match-path "test/fork/**" --summary` reported `192 tests passed, 0 failed (10 test suites)` — 55 tests short of the 247 unit baseline anchored in `CLAUDE.md` §11 at `stage-f-complete`. The 55-test delta matched exactly the count of `function test_*` declarations in `test/unit/CCBMultiplier.t.sol`, and forge omitted `CCBMultiplierTest` from the suite list entirely while every other unit suite enumerated normally. Direct invocation `forge test --match-test "test_getMultiplier_writtenMi_returnsMi"` returned `No tests found in project!`. Brace-balance grep on the source confirmed structure intact (4 contract opens, 4 matching closes, `contract CCBMultiplierTest is Test {` at L73, last `}` at L849). Every `forge build` invocation reported `No files changed, compilation skipped` — forge's cache index treated the file as up-to-date but the cached test-discovery list lacked the contract.

**Symptom signature.** Pattern-match on these three observations together:

1. `forge test --summary` total **drops by exactly the test-count of one or more contracts** versus a known baseline (here: 247 → 192, a 55-test delta).
2. Compilation reports **`Compiler run successful!` or `compilation skipped`** with no error output — the file builds, lint runs against it, source is valid Solidity.
3. `forge test --list` **does not contain the missing contract anywhere** in its output — neither under its file path nor under `--match-contract` filter; `forge test --match-test <known_test_name>` returns `No tests found in project!`.

When all three present together, the cache index is the cause, not a code regression.

**Deterministic recovery.** Run `forge clean && forge build` from the repo root. The clean removes `out/` and `cache/`; the rebuild repopulates with a fresh test-discovery index. After clean + rebuild, the missing contract reappears in `forge test --list` and the suite total returns to baseline. RB-004.1 verify after `forge clean && forge build`: 247 unit + 16 fork = 263/263 green, exactly matching the `stage-f-complete` anchor.

**When this triggers.** The defect surfaces after structural rewrites of an existing test file — non-additive edits like `using` directive insertions, constant-block retypes, helper introduction, and in-place cast removals across many call sites in a single commit (RB-004.0b touched 16 cast sites and added a SafeCast helper plus two `using` directives). Forge's incremental cache appears to update artifact contents but occasionally fails to refresh the test-discovery index entry for the rewritten contract. Adding a new file is fine; deleting and re-adding is fine; the silent-skip mode is specifically structural-rewrite-of-existing-file with the file path unchanged.

**Project-wide rule — `forge clean` before trusting `forge test --summary` totals after structural rewrites.** Any §8e.1 verify block that follows a structural rewrite of an existing test file — `using` directive insertions, constant-block retypes, helper introduction, multi-site cast removals — runs `forge clean && forge build` ahead of the `forge test --summary` invocation. Single-line edits, comment-only changes, and additive sub-step append patterns do not need the clean. When unit / fork totals do not match the §11 baseline at any verify checkpoint, **suspect cache before suspecting a regression**; `forge clean` is a one-time ~100-second tax that rules out the cache-index hypothesis cleanly.

**Cross-references:**

- **`CLAUDE.md` §11 anchor** — `stage-f-complete` baseline 263/263 (247 unit + 16 fork) via D35 split-form invocation.
- **D35** (`STAGE_D_NOTES.md`) — split-form invocation pattern: `--no-match-path "test/fork/**"` for unit + `--match-path "test/fork/**" --fork-url $MAINNET_RPC_URL --threads 1` for fork. F14's symptom signature applies to either half.
- **F11** (`STAGE_F_NOTES.md` L451) — sibling tooling-discipline finding; same class of "rendering / caching layer falsifies what looks like a real defect" pattern (F11 is paste-rendering; F14 is build-cache).
- **RB-004.1** (`docs/ROBUSTNESS_BACKPORT_REGISTER.md`, verify after commit `7bdfbcc`) — where the symptom surfaced; recovery via `forge clean && forge build` confirmed 247 + 16 totals.
