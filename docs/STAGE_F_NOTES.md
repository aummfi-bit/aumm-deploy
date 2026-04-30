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
