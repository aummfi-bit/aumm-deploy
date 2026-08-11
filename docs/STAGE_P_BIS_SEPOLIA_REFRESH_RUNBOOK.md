# Stage P-bis — Sepolia refresh runbook (generation 2)

**Audience:** the broadcast operator. This document is operational and standalone. The stage reader's account is `docs/STAGE_P_BIS_PLAN.md` PB3.13; the decision record is `docs/STAGE_P_BIS_NOTES.md` PB-D70.

**This is not the first-deploy runbook.** `docs/STAGE_P_BIS_SEPOLIA_RUNBOOK.md` is the generation-1 procedure as executed history and stays unamended per PB-D70 (x). Nothing here edits it. Where a section below repeats it the text is restated rather than cross-referenced, because an operator mid-broadcast must not be reading two documents.

**Chain:** Sepolia, chain id 11155111, per PB-D1.

**Why generation 2 exists.** A corrected fee-routing hook cannot be swapped under a live constellation: the Vault seals `_hooksContracts` at registration, `AureumProtocolFeeController.FEE_ROUTING_HOOK` is immutable, and F-22's accepted residual leaves `setProtocolFeeController` unreachable by design. Everything pointing at the hook therefore redeploys, and the refresh carries five corrections in one batch — the F-23 hook, `recoverStrandedFees`, `GaugeEligibility`'s rail conjunct, the PB-D50-corrected `TVLOracle`, and the F-22 governance stack. Only the 87 testnet stubs survive. PB-D70 (i) and (ii).

**Status at authoring:** PB3.13 rung g1. Sections 3 onward land at g2 through g6.

## 0. Safety posture

- Every `forge script --broadcast` command in this document is user-run under CLAUDE.md §8b, approved one command at a time. Neither Claude Code nor Cursor executes any of them.
- `--rpc-url` resolves to the Sepolia endpoint on every command here. A mainnet RPC on any command in this document is a §8c violation rather than a typo to correct in place: stop, discard the shell, restart the step.
- `DEPLOYER_PRIVATE_KEY` is entered by the operator alone. Never committed, never echoed to the terminal, never pasted into chat, never written where git can see it.
- The deployer EOA is `0xA851478dbee97375E784e9b98c0D7D599662bF85` (PB3.1) and is also `GOVERNANCE_MULTISIG` on Sepolia per PB-D23 (iv). The broadcast key MUST be that address. This is enforced operationally, not by an in-script assert, per PB-D27 (vii)(4).
- The deployer EOA sends NOTHING outside a broadcast sequence while one is in flight — no faucet top-up, no probe transaction, no wallet-initiated approval. Every such transaction moves the nonce, and both phase A's address projections and phase 4's `--resume` fail closed against a moved nonce. Per PB-D49 (vii); the phase 4 case and its recovery are section 9.
- D-D6 reserves mainnet for Stage R. Nothing in this document targets mainnet.

## 1. Environment files

Three files, two canonical and one derived. `.env.mainnet` and `.env.sepolia` each hold a COMPLETE variable set for their own chain; `.env` is a working copy of exactly one of them and is the only file foundry reads. All three are gitignored and untracked, and only `.env.example` is tracked. This is the PB-D36 model, which replaces PB-D35 (iv)'s overlay: there is no precedence rule and no inheritance, so whichever set is active is the whole answer and nothing shows through from the other chain.

**Switching posture.** Run `cp .env.sepolia .env` before the broadcast sequence, and `cp .env.mainnet .env` to return to mainnet fork testing. Nothing is sourced and no command in this runbook carries a `set -a` preamble — foundry auto-loads `.env`, and that is the whole mechanism. That mechanism belongs to foundry alone, which is why every command in this document writes `--rpc-url sepolia` rather than passing the URL as a shell variable reference: the shell expands a variable on the command line before foundry is ever launched, and the shell has never read `.env`, so the variable form resolves to an empty string and the command dies with a missing-value error. The alias is defined at `foundry.toml` L103, where `sepolia` maps to the `SEPOLIA_RPC_URL` value foundry itself reads from `.env`.

**Write direction is canonical to `.env`, never the reverse.** Every address captured in this runbook is written into `.env.sepolia`, never into `.env`, never into a tracked file, and never through `vm.setEnv`. `.env` is then refreshed from the canonical file. Editing `.env` directly is exactly the drift PB-D35 (vii) had to repair by hand, and the check that catches it is `diff .env .env.sepolia`, which must be empty while the Sepolia posture is active.

**The pre-run check, and it fails closed.** Each canonical file carries `AUMM_ENV_CHAIN` as its first key. Before any mainnet fork suite, `grep -c '^AUMM_ENV_CHAIN=mainnet$' .env` must return exactly 1. Before any broadcast command in section 6, `grep -c '^AUMM_ENV_CHAIN=sepolia$' .env` must return exactly 1. A count of 0 is a failure and not a pass, because an absent marker means the active copy's provenance is unknown. Do not proceed on a missing marker, and do not hand-add the marker to make the check pass.

**Why the values must land on disk.** Each `forge script --broadcast` invocation is its own operating-system process and reads `.env` at start, so a value set during one invocation is invisible to the next unless it has landed on disk first. That is the PB-D27 (iii) reasoning and it stands unchanged; what PB-D35 and PB-D36 corrected is only which file receives the write.

**One value changed in `.env.sepolia` since generation 1.** `BODENSEE_SALT` is now `0xe8adfe84affa1498e12af213d44eb960718a5223d3c3d4c7e1af1dbc1e56c25e`, reproducible by `cast keccak "aureum.derBodensee"`, replacing the slot-space value 2 that collided with ixAetheron's own salt in the factory's CREATE3 namespace. `.env.mainnet` carries the identical value, because `BasePoolFactory._computeFinalSalt` hashes `block.chainid` alongside the salt and so separates the chains by itself. PB-D70 (vi) and (xvii); the collision is PB-D39.

## 2. Prerequisites

Six of these were already satisfied before this rung and are listed so the operator confirms rather than assumes; rows 6 and 7 are refresh-specific and had no generation-1 equivalent. Phase 1 is not run at all, so every gate below reads against phase 2.

| # | Item | State | Gate |
| --- | --- | --- | --- |
| 1 | `SEPOLIA_RPC_URL` reachable, chain id 11155111 | verified at PB3.1, in continuous use since | — |
| 2 | Deployer funded | 5.782928979297694346 SepETH read at PB3.13e against roughly 0.2 needed; not a gate this time | before phase 2 |
| 3 | `ETHERSCAN_API_KEY` present in both canonical files | provisioned at PB3.5i; generation 1 authored this row ABSENT | before verification |
| 4 | Canonical Permit2 at `0x000000000022D473030F116dDEE9F6B43aC78BA3` | verified at PB3.1 | — |
| 5 | `script/config/mainnet-token-decimals.env` merged into `.env.sepolia` | committed at PB3.5b2 | before phase 2 |
| 6 | `BODENSEE_SALT` outside the 1-28 Miliarium slot space | written at PB3.13f2 into both canonical files | before phase 2 |
| 7 | All 87 stubs hold code, the 14 vaults resolve their recorded underlying, and the `STUB_` map is present in `.env.sepolia` | verified against the chain at PB3.13e | before phase 2 |
| 8 | `.env` refreshed from `.env.sepolia`, `AUMM_ENV_CHAIN` reading sepolia | operator action at the pre-flight | before phase 2 |

## 3. Prediction model

**Why every rehearsal formula is wrong here.** Under `--broadcast` forge never puts the script contract on chain. Each `new X(...)` inside a script becomes a transaction sent from the deployer EOA, so the CREATE originates at that EOA's address and nonce, not at the script's. Every prediction formula in the fork fixtures is therefore a harness artifact: `vm.computeCreateAddress(address(hookScript), 1)` and the harness-creator CREATE3 at `test/fork/StagePRunRehearsal.t.sol` L130-L138 are correct in a test process and structurally wrong live. Re-reading the live nonce between steps does not rescue them, because the addresses that must be known first are produced several steps later.

**The cycle is four deep.** `script/DeployAureumVault.s.sol` L127-L128 reads BOTH `DER_BODENSEE_POOL` and `FEE_ROUTING_HOOK` before it deploys anything, and the fee controller seals both as immutables at L184-L188. The hook needs the Vault. Der Bodensee is created by the weighted-pool factory, and the factory needs the Vault. So the two addresses the FIRST step consumes are produced by two of the LAST steps.

**Inside the vault step the projection is already live-correct.** `run()` passes `msg.sender` into `_deploy` at L95-L97, which reads that EOA's live nonce and projects the authorizer at N, the fee controller at N+1 and the factory at N+2 (L164), then derives the Vault as a CREATE3 from the predicted factory (L171). Nothing there needs external help; only the step's INPUTS do.

**Der Bodensee's salt is scoped to the broadcast sender.** `BasePoolFactory._computeFinalSalt` is `keccak256(abi.encode(msg.sender, block.chainid, salt))` at `lib/balancer-v3-monorepo/pkg/pool-utils/contracts/BasePoolFactory.sol` L126-L128, and the CREATE3 creator is the factory rather than the caller. `DeployDerBodensee.run()` opens a bare `vm.startBroadcast()`, so the `msg.sender` the factory hashes is the broadcast sender, which under `--broadcast` is the deployer EOA. PB3.5d established this by execution rather than by reading: `test/fork/DerBodenseeScriptWitness.t.sol` drives the real script, and the pool lands exactly at the address derived from the broadcast sender rather than from the script contract or the test contract. That witness pins the MECHANISM; the live case substitutes the deployer EOA for the test default sender.

**What the operator must project, and when.** Before the first broadcast: the weighted-pool factory, as an EOA CREATE at the nonce the vault step leaves behind; der Bodensee, as `CREATE3.getDeployed(keccak256(abi.encode(deployerEOA, 11155111, BODENSEE_SALT)), predictedFactory)`, which carries no nonce term of its own beyond the one fixing the factory; and the hook, as an EOA CREATE at the nonce reached after the factory and AuMM steps — the hook precedes der Bodensee per PB-D30, so no der-Bodensee count enters its projection. The last two are written into `.env.sepolia` as `DER_BODENSEE_POOL` and `FEE_ROUTING_HOOK`, and refreshed into `.env`, before `DeployAureumVault` runs. Each projection advances the nonce by the per-step transaction totals of the steps in between, and unlike generation 1 the refresh has all of them already: section 5 ships complete, because generation 1's own broadcast supplied every count its runbook left PENDING-h. What phase A must still do is read `n0`, the deployer's live nonce, and recompute all eight projections from it. No generation-1 address carries over, and none may be reused.

**Three self-asserts, and what they do not undo.** `DeployAureumVault` reverts `FactoryAddressMismatch` if its own factory lands off-projection (L203-L205); `DeployDerBodensee` reverts `BodenseeAddressMismatch` if the created pool diverges from `DER_BODENSEE_POOL` (PB3.5c1b); `DeployFeeRoutingHook` reverts `HookAddressMismatch` if the deployed hook diverges from `FEE_ROUTING_HOOK` (PB3.5c2). The first is self-contained within its step. The other two compare against predictions the fee controller has ALREADY sealed as immutables, so by the time either fires the damage is done: the assert stops the sequence from compounding, but it cannot unwind the vault. Recovery is a full restart of the whole sequence on fresh addresses. That is tolerable on testnet gas and is precisely why the rung h dry run is mandatory rather than advisory.

## 4. Phase overview

The base layer stays per-granular per PB-D23 (vii); the Stage F-to-K orchestration stays the single composed `DeployStageP.run()`. Collapsing either was rejected at PB-D27 (i).

1. **Stubs — NOT RUN.** The 87 stubs of generation 1 are reused unchanged per PB-D70 (i), so `test-stubs/DeployTestnetStubs.s.sol` is not invoked, no `STUB_` address moves, and the phase A arithmetic drops every `c1` term. Their code and their vault-to-underlying relations were verified against the chain at PB3.13e. The phase keeps its number rather than renumbering the five below it, so that every later phase still reads as it does in the generation-1 runbook and the deployment record.
2. **Base layer, per-granular.** `DeployAureumVault`, `DeployAureumWeightedPoolFactory`, `DeployAuMM`, `DeployFeeRoutingHook`, `DeployDerBodensee`, `DeployRouter` — in an order fixed by the PB-D27 (iv) address cycle and the PB-D30 hook-before-Bodensee swap, not by convenience.
3. **Pools.** The 26 pool scripts under `script/pools/`. All 26 are Miliarium pools occupying slots in one flat slot space numbered 1 to 28; the `PILOT_`, `MAJOR_` and `MILIARIUM_` env-key prefixes are deploy-plumbing artifacts of the stage each pool first landed in, not a pool taxonomy. All 26 keys must be in `.env` before phase 4, because `DeployStageP` drives Stage I, M and N internally and those read them.
4. **Orchestration.** `DeployStageP.run()`, one process, composing Stage F through Stage K and threading its own intermediate addresses internally.
5. **Router seat.** The F-09 trusted-router seat. No script performs it: `DeployStageP.s.sol` L255 records that the orchestrator makes no `setTrustedRouter` call, structurally, per P-D26 (4). An unseated Router mints BPT but records nothing, so this step is load-bearing rather than cosmetic.
6. **Verification.** Explorer verification of the deployed set.

