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
| **C12** | **STAGE_C_PLAN.md inaccurately lists `src/AureumVault.sol` as a Stage B artifact to move.** `git ls-tree -r main \| grep '^src/'` at Stage C kickoff returned three files: `AureumAuthorizer.sol`, `AureumProtocolFeeController.sol`, `AureumVaultFactory.sol`. No `AureumVault.sol` has ever existed in this repo (`git log --all --oneline -- src/AureumVault.sol` empty). The error appears in three places in the plan: scope (line 42), C1.1 `git mv` list (line 171), and "Files Stage C produces" block (line 1113). Root cause: `AureumVault.sol` is the *Balancer* vault in `lib/balancer-v3-monorepo/pkg/vault/contracts/Vault.sol`, which is byte-identical-deployed-unforked per cursorrules rule 1 — the plan's author appears to have conflated the Balancer vault with a nonexistent Aureum fork of it. Resolution: C1 moves three files, not four; C1.6 README update lists three; the "Files Stage C produces" block is updated to list three in the C1 commit alongside the moves. The plan file itself is not edited mid-stage; this note is the correction of record. Also: `STAGES_OVERVIEW.md`'s Scope section says "Stage B built the substrate — forked `AureumVault.sol` with 22-line authorizer redirect" — that phrase is equally wrong (the 22-line authorizer redirect is in `AureumVaultFactory.sol`) but the overview fix is deferred out of Stage C scope. |

(populated further as implementation surfaces questions)
