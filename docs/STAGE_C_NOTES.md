# Stage C Notes

Design decisions, grep-verified findings, and implementation notes made during Stage C.

Planning-stage decisions (C-D1 through C-D13) live in `STAGE_C_PLAN.md`. Implementation-stage decisions land here, numbered from C10 onward.

## Branch model

Same as Stage B per `STAGE_B_NOTES.md` "Branch model deviation" (2026-04-09): tag directly on main without a PR; `stage-c` branch on origin preserved as a snapshot marker. No PR-gated review for solo work.

## Open Stage C decisions

| ID | Decision |
|----|----------|
| **C10** | **Baseline deviation from plan's recorded tip.** `STAGE_C_PLAN.md` prerequisites section says `git log --oneline -1` must match `b627a92`. At Stage C kickoff on 2026-04-16, `main`'s actual tip was `6a1be15` — three commits past `b627a92`: `96d1d1c` (B7 Completion Log fill, 1 line), `42543fd` (docs upload of root-level `STAGE_C_PLAN.md` via GitHub web UI), `324a4ed` (docs upload of `docs/STAGE_C_PLAN.md` via GitHub web UI), then `6a1be15` (housekeeping: removed the stray root-level duplicate). All four are docs-only, zero Solidity/config/test changes. `stage-b-complete` tag unchanged at `b627a92`. Stage B baseline therefore remained correctly green; Stage C branches from `6a1be15`. |
| **C11** | **Prerequisites check invocation corrected post hoc.** `STAGE_C_PLAN.md` line 114 reads `forge test --fork-url $MAINNET_RPC_URL -vv` as a single invocation. On forge 1.5.1-stable against Alchemy mainnet, that one-liner routes the local-only `AureumProtocolFeeController` handler-based invariant runs through RPC, inflating wall time from ~14s (local, no RPC) to 2+ minutes. Split invocation reproduces Stage B timings: `forge test --no-match-path 'test/fork/**' -vv` for local unit tests (~14s, 28 tests), then `forge test --match-path 'test/fork/**' --fork-url $MAINNET_RPC_URL -vv` for fork tests (~3s, 3 tests). Total 31 tests passed, 0 failed at Stage C kickoff. Carry this split-invocation pattern into Stage D-onward prerequisites checks. The plan file itself is not edited mid-stage; this note serves as the correction of record. |

(populated further as implementation surfaces questions)
