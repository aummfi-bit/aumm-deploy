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
