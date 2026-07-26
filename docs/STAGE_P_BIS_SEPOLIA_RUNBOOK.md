# Stage P-bis — Sepolia go-live runbook

**Audience:** the broadcast operator. This document is operational. The stage reader's account is `docs/STAGE_P_BIS_PLAN.md` PB3.5; the decision record is `docs/STAGE_P_BIS_NOTES.md` PB-D27 and PB-D28.

**Chain:** Sepolia, chain id 11155111, per PB-D1.

**Status at authoring:** PB3.5 rung e. The per-step EOA transaction counts in section 5 are deliberately unpopulated until rung h, per PB-D28 (ii).

## 0. Safety posture

- Every `forge script --broadcast` command in this document is user-run under CLAUDE.md §8b, approved one command at a time. Neither Claude Code nor Cursor executes any of them.
- `--rpc-url` resolves to the Sepolia endpoint on every command here. A mainnet RPC on any command in this document is a §8c violation rather than a typo to correct in place: stop, discard the shell, restart the step.
- `DEPLOYER_PRIVATE_KEY` is entered by the operator alone. Never committed, never echoed to the terminal, never pasted into chat, never written where git can see it.
- The deployer EOA is `0xA851478dbee97375E784e9b98c0D7D599662bF85` (PB3.1) and is also `GOVERNANCE_MULTISIG` on Sepolia per PB-D23 (iv). The broadcast key MUST be that address. This is enforced operationally, not by an in-script assert, per PB-D27 (vii)(4).
- D-D6 reserves mainnet for Stage R. Nothing in this document targets mainnet.

## 1. `.env` hygiene

`.env` is gitignored at `.gitignore` L12 and is untracked; only `.env.example` is tracked. Re-verified 2026-07-26 via `git ls-files`.

Every address captured in this runbook is written into `.env` on disk, never into a tracked file and never through `vm.setEnv`. Each `forge script --broadcast` invocation is its own operating-system process and reads `.env` at start, so a value set during one invocation is invisible to the next unless it has landed on disk first. This is the PB-D27 (iii) amendment to PB-D21 (v): the rehearsal's one-process `vm.setEnv` threading is rehearsal-true and live-false.

## 2. Prerequisites

| # | Item | State at authoring | Gate |
| --- | --- | --- | --- |
| 1 | `SEPOLIA_RPC_URL` reachable, chain id 11155111 | verified at PB3.1 | — |
| 2 | Deployer EOA funded with SepETH | 0.05 at PB3.1; the target is fixed by the rung f gas measurement | rung f |
| 3 | `ETHERSCAN_API_KEY` present in `.env` | ABSENT at PB3.1 — must be provisioned | before verification |
| 4 | Canonical Permit2 at `0x000000000022D473030F116dDEE9F6B43aC78BA3` | verified present at PB3.1 | — |
| 5 | `script/config/mainnet-token-decimals.env` merged into `.env` | committed at PB3.5b2 | before phase 1 |

## 3. Prediction model

Placeholder. The PB-D27 (iv) EOA-scoped prediction model lands at rung e1b.

## 4. Phase overview

The base layer stays per-granular per PB-D23 (vii); the Stage F-to-K orchestration stays the single composed `DeployStageP.run()`. Collapsing either was rejected at PB-D27 (i).

1. **Stubs.** `test-stubs/DeployTestnetStubs.s.sol` deploys the testnet token roster.
2. **Base layer, per-granular.** `DeployAureumVault`, `DeployAureumWeightedPoolFactory`, `DeployAuMM`, `DeployDerBodensee`, `DeployFeeRoutingHook`, `DeployRouter` — in an order fixed by the PB-D27 (iv) address cycle, not by convenience.
3. **Pools.** The 26 pool scripts under `script/pools/`, three pilots plus five majors plus eighteen Miliarium slots. All 26 must be on disk in `.env` before phase 4, because `DeployStageP` drives Stage I, M and N internally and those read the pool keys.
4. **Orchestration.** `DeployStageP.run()`, one process, composing Stage F through Stage K and threading its own intermediate addresses internally.
5. **Router seat.** The F-09 trusted-router seat. No script performs it: `DeployStageP.s.sol` L255 records that the orchestrator makes no `setTrustedRouter` call, structurally, per P-D26 (4). An unseated Router mints BPT but records nothing, so this step is load-bearing rather than cosmetic.
6. **Verification.** Explorer verification of the deployed set.

## 5. Per-step EOA transaction counts

Every cell below reads PENDING-h by design. PB-D27 (iv)(1) requires these counts be derived from a dry run rather than read off the source, and PB-D28 (ii) defers that derivation to rung h — the Sepolia-fork dry run at the real deployer's live nonce. Rung h populates this table before any broadcast command is issued.

A count written here from source-reading would be a number an operator could act on, and the failure mode of an undercount is a mis-projected address sealing a vault immutable — the unrecoverable class PB-D27 (iv) exists to convert into an abort. An empty cell cannot be misread as an answer.

| # | Step | Count |
| --- | --- | --- |
| 1 | `DeployTestnetStubs` | PENDING-h |
| 2 | `DeployAureumVault` | PENDING-h |
| 3 | `DeployAureumWeightedPoolFactory` | PENDING-h |
| 4 | `DeployAuMM` | PENDING-h |
| 5 | `DeployDerBodensee` | PENDING-h |
| 6 | `DeployFeeRoutingHook` | PENDING-h |
| 7 | `DeployRouter` | PENDING-h |
| 8 | Each pool script, per invocation | PENDING-h |
| 9 | `DeployStageP.run()` | PENDING-h |
| 10 | Router seat | PENDING-h |
