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
- During boost: `updateMultiplier(pool)` ticks `lastMultiplierUpdateBlock` but leaves `M_i[pool]` unchanged (per OQ-23 (v.d)).
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

**Edge case — single Miliarium pool active.** Pre-full-constellation Stage J could ship the registry incrementally (one pool at a time). With one Miliarium pool, `protocolTVLEMA = pool's EMA`, `miliariumAvgEMA = pool's EMA / 28`. The sole pool's `delta_intra` registers as far above `miliariumAvgEMA` (its own EMA is 28× the mean), pushing `M_i` upward. Correct math given the constellation isn't full but operationally degenerate. Not Stage F's concern: production Stage J ships the full 28-pool registry per `04_tokenomics.md` §vii.

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
