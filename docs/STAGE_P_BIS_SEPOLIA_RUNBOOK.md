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

## 1. Environment files

Three files, two canonical and one derived. `.env.mainnet` and `.env.sepolia` each hold a COMPLETE variable set for their own chain; `.env` is a working copy of exactly one of them and is the only file foundry reads. All three are gitignored and untracked, and only `.env.example` is tracked. This is the PB-D36 model, which replaces PB-D35 (iv)'s overlay: there is no precedence rule and no inheritance, so whichever set is active is the whole answer and nothing shows through from the other chain.

**Switching posture.** Run `cp .env.sepolia .env` before the broadcast sequence, and `cp .env.mainnet .env` to return to mainnet fork testing. Nothing is sourced and no command in this runbook carries a `set -a` preamble — foundry auto-loads `.env`, and that is the whole mechanism.

**Write direction is canonical to `.env`, never the reverse.** Every address captured in this runbook is written into `.env.sepolia`, never into `.env`, never into a tracked file, and never through `vm.setEnv`. `.env` is then refreshed from the canonical file. Editing `.env` directly is exactly the drift PB-D35 (vii) had to repair by hand, and the check that catches it is `diff .env .env.sepolia`, which must be empty while the Sepolia posture is active.

**The pre-run check, and it fails closed.** Each canonical file carries `AUMM_ENV_CHAIN` as its first key. Before any mainnet fork suite, `grep -c '^AUMM_ENV_CHAIN=mainnet$' .env` must return exactly 1. Before any broadcast command in section 6, `grep -c '^AUMM_ENV_CHAIN=sepolia$' .env` must return exactly 1. A count of 0 is a failure and not a pass, because an absent marker means the active copy's provenance is unknown. Do not proceed on a missing marker, and do not hand-add the marker to make the check pass.

**Why the values must land on disk.** Each `forge script --broadcast` invocation is its own operating-system process and reads `.env` at start, so a value set during one invocation is invisible to the next unless it has landed on disk first. That is the PB-D27 (iii) reasoning and it stands unchanged; what PB-D35 and PB-D36 corrected is only which file receives the write.

## 2. Prerequisites

| # | Item | State at authoring | Gate |
| --- | --- | --- | --- |
| 1 | `SEPOLIA_RPC_URL` reachable, chain id 11155111 | verified at PB3.1 | — |
| 2 | Deployer EOA funded with SepETH | 0.05 at PB3.1; target ~1-2 SepETH per the rung f gas measurement, section 6 | before phase 1 |
| 3 | `ETHERSCAN_API_KEY` present in both canonical files | ABSENT at PB3.1 — must be provisioned | before verification |
| 4 | Canonical Permit2 at `0x000000000022D473030F116dDEE9F6B43aC78BA3` | verified present at PB3.1 | — |
| 5 | `script/config/mainnet-token-decimals.env` merged into `.env.sepolia` | committed at PB3.5b2 | before phase 1 |

## 3. Prediction model

**Why every rehearsal formula is wrong here.** Under `--broadcast` forge never puts the script contract on chain. Each `new X(...)` inside a script becomes a transaction sent from the deployer EOA, so the CREATE originates at that EOA's address and nonce, not at the script's. Every prediction formula in the fork fixtures is therefore a harness artifact: `vm.computeCreateAddress(address(hookScript), 1)` and the harness-creator CREATE3 at `test/fork/StagePRunRehearsal.t.sol` L130-L138 are correct in a test process and structurally wrong live. Re-reading the live nonce between steps does not rescue them, because the addresses that must be known first are produced several steps later.

**The cycle is four deep.** `script/DeployAureumVault.s.sol` L127-L128 reads BOTH `DER_BODENSEE_POOL` and `FEE_ROUTING_HOOK` before it deploys anything, and the fee controller seals both as immutables at L184-L188. The hook needs the Vault. Der Bodensee is created by the weighted-pool factory, and the factory needs the Vault. So the two addresses the FIRST step consumes are produced by two of the LAST steps.

**Inside the vault step the projection is already live-correct.** `run()` passes `msg.sender` into `_deploy` at L95-L97, which reads that EOA's live nonce and projects the authorizer at N, the fee controller at N+1 and the factory at N+2 (L164), then derives the Vault as a CREATE3 from the predicted factory (L171). Nothing there needs external help; only the step's INPUTS do.

**Der Bodensee's salt is scoped to the broadcast sender.** `BasePoolFactory._computeFinalSalt` is `keccak256(abi.encode(msg.sender, block.chainid, salt))` at `lib/balancer-v3-monorepo/pkg/pool-utils/contracts/BasePoolFactory.sol` L126-L128, and the CREATE3 creator is the factory rather than the caller. `DeployDerBodensee.run()` opens a bare `vm.startBroadcast()`, so the `msg.sender` the factory hashes is the broadcast sender, which under `--broadcast` is the deployer EOA. PB3.5d established this by execution rather than by reading: `test/fork/DerBodenseeScriptWitness.t.sol` drives the real script, and the pool lands exactly at the address derived from the broadcast sender rather than from the script contract or the test contract. That witness pins the MECHANISM; the live case substitutes the deployer EOA for the test default sender.

**What the operator must project, and when.** Before the first broadcast: the weighted-pool factory, as an EOA CREATE at the nonce the vault step leaves behind; der Bodensee, as `CREATE3.getDeployed(keccak256(abi.encode(deployerEOA, 11155111, BODENSEE_SALT)), predictedFactory)`, which carries no nonce term of its own beyond the one fixing the factory; and the hook, as an EOA CREATE at the nonce reached after the factory and AuMM steps — the hook precedes der Bodensee per PB-D30, so no der-Bodensee count enters its projection. The last two are written into `.env` as `DER_BODENSEE_POOL` and `FEE_ROUTING_HOOK` before `DeployAureumVault` runs. Each projection advances the nonce by the per-step transaction totals of the steps in between — which is exactly what section 5 does not yet contain. Rung h phase A derives those totals at the real deployer nonce and fills section 5 in. Until it has, the projection cannot be computed and no broadcast may begin.

**Three self-asserts, and what they do not undo.** `DeployAureumVault` reverts `FactoryAddressMismatch` if its own factory lands off-projection (L203-L205); `DeployDerBodensee` reverts `BodenseeAddressMismatch` if the created pool diverges from `DER_BODENSEE_POOL` (PB3.5c1b); `DeployFeeRoutingHook` reverts `HookAddressMismatch` if the deployed hook diverges from `FEE_ROUTING_HOOK` (PB3.5c2). The first is self-contained within its step. The other two compare against predictions the fee controller has ALREADY sealed as immutables, so by the time either fires the damage is done: the assert stops the sequence from compounding, but it cannot unwind the vault. Recovery is a full restart of the whole sequence on fresh addresses. That is tolerable on testnet gas and is precisely why the rung h dry run is mandatory rather than advisory.

## 4. Phase overview

The base layer stays per-granular per PB-D23 (vii); the Stage F-to-K orchestration stays the single composed `DeployStageP.run()`. Collapsing either was rejected at PB-D27 (i).

1. **Stubs.** `test-stubs/DeployTestnetStubs.s.sol` deploys the testnet token roster.
2. **Base layer, per-granular.** `DeployAureumVault`, `DeployAureumWeightedPoolFactory`, `DeployAuMM`, `DeployFeeRoutingHook`, `DeployDerBodensee`, `DeployRouter` — in an order fixed by the PB-D27 (iv) address cycle and the PB-D30 hook-before-Bodensee swap, not by convenience.
3. **Pools.** The 26 pool scripts under `script/pools/`. All 26 are Miliarium pools occupying slots in one flat slot space numbered 1 to 28; the `PILOT_`, `MAJOR_` and `MILIARIUM_` env-key prefixes are deploy-plumbing artifacts of the stage each pool first landed in, not a pool taxonomy. All 26 keys must be in `.env` before phase 4, because `DeployStageP` drives Stage I, M and N internally and those read them.
4. **Orchestration.** `DeployStageP.run()`, one process, composing Stage F through Stage K and threading its own intermediate addresses internally.
5. **Router seat.** The F-09 trusted-router seat. No script performs it: `DeployStageP.s.sol` L255 records that the orchestrator makes no `setTrustedRouter` call, structurally, per P-D26 (4). An unseated Router mints BPT but records nothing, so this step is load-bearing rather than cosmetic.
6. **Verification.** Explorer verification of the deployed set.

## 5. Per-step EOA transaction counts

Rows 1 through 4 and row 9 carry measured counts; rows 5 through 8 and row 10 still read PENDING-h. PB-D27 (iv)(1) requires these counts be derived from a run rather than read off the source, and PB-D28 (ii) deferred that derivation to rung h. Phase A measured rows 1 through 4 at the live deployer nonce, which is all the projection arithmetic consumes per PB-D30 (iii); the remaining rows fill from the broadcast itself at rung i, since no projection reads them.

A count written here from source-reading would be a number an operator could act on, and the failure mode of an undercount is a mis-projected address sealing a vault immutable — the unrecoverable class PB-D27 (iv) exists to convert into an abort. An empty cell cannot be misread as an answer.

Row 1's 87 decomposes as 3 CREATEs for each of 14 WITH_RATE tokens plus 1 for each of 45 STANDARD tokens; the 67 `STUB_` pairs the script emits are those 14 plus 45 plus 8 distinct rate-provider literals, which are recorded as aliases of an already-deployed provider rather than as fresh deploys. Row 2's 4 is three CREATEs — authorizer, fee controller, vault factory — plus the `factory.create()` call. Every transaction in rows 1 through 4 is a CREATE except that one call.

**Resume caveat.** Row 1's 87 is the count for a FRESH stub deploy. On a resume onto stubs already live on chain — the PB-D38 (ii) branch, where step 1 is not re-broadcast — that figure is history rather than an addend, and the phase A arithmetic in section 8 drops every `c1` term. Rows 2 through 4 are invariant under both branches.

**Row 9 is a dry-run count, not a broadcast count.** Every other filled row in this table is either derived from phase A projection or, per the sentence above, waits for the broadcast itself. Row 9 is neither: `DeployStageP.run()` has never been broadcast, and 114 is what a live-Sepolia `forge script` simulation produced without `--broadcast`, against real chain state, per PB-D48. It is written here because it answers this exact cell, not because rung i has occurred.

| # | Step | Count |
| --- | --- | --- |
| 1 | `DeployTestnetStubs` | 87 |
| 2 | `DeployAureumVault` | 4 |
| 3 | `DeployAureumWeightedPoolFactory` | 1 |
| 4 | `DeployAuMM` | 1 |
| 5 | `DeployFeeRoutingHook` | PENDING-h |
| 6 | `DeployDerBodensee` | PENDING-h |
| 7 | `DeployRouter` | PENDING-h |
| 8 | Each pool script, per invocation | PENDING-h |
| 9 | `DeployStageP.run()` | 114 |
| 10 | Router seat | PENDING-h |

## 6. Phase 1 and 2 — commands and capture

**Invocation form.** Every command in this section is `forge script <path>:<Contract> --rpc-url $SEPOLIA_RPC_URL --broadcast --account aumm-sepolia --sender 0xA851478dbee97375E784e9b98c0D7D599662bF85`. Once `ETHERSCAN_API_KEY` is provisioned per prerequisite 3, append `--verify --etherscan-api-key $ETHERSCAN_API_KEY`.

**Capture and refresh.** Every address this runbook captures is written into `.env.sepolia`, never into `.env` directly, per section 1's write-direction rule. Because forge reads only `.env`, run `cp .env.sepolia .env` after each capture and before the next command — a step whose predecessor captured a key it needs will otherwise read the pre-capture value, aborting on an empty key or sealing a stale address into an immutable. Before step 1, confirm the posture once with `grep -c '^AUMM_ENV_CHAIN=sepolia$' .env`, which must return exactly 1.

**Key posture (PB-D27 (vii)(3)).** The deployer key is imported once into forge's keystore with `cast wallet import aumm-sepolia --interactive` and referenced thereafter as `--account aumm-sepolia`. The key never appears on a command line, in shell history, or in `.env`. Chosen over per-invocation `--interactive` because this sequence runs to roughly three dozen invocations and paste-fatigue across that many prompts is its own failure mode.

**Salts pinned for this deployment.** `SALT` is `0x0000000000000000000000000000000000000000000000000000000000000001`. `BODENSEE_SALT` is `0x0000000000000000000000000000000000000000000000000000000000000002`, matching the PB3.4 rehearsal so that the rung h dry run exercises the same der-Bodensee derivation the live broadcast will. `.env.example` L96 carries a zero value for `BODENSEE_SALT` and is stale against this decision; correcting it is a later rung, and the value above is authoritative.

**Keys absent from `.env.example`.** `EMERGENCY_MULTISIG` (read by `DeployStageK.s.sol` L125), `WETH_ADDRESS` and `GENESIS_BLOCK` are all consumed by this sequence but are not in the committed template. Add them to `.env.sepolia` before the steps that need them. `WETH_ADDRESS` has no Sepolia value anywhere in this repo — the fork fixtures inject the mainnet WETH literal, which has no code on Sepolia — so a Sepolia WETH must be pinned by the operator before step 7.

**Aliases the orchestrator bridges, and the ones it does not.** `DeployStageP` sets `VAULT_EXPLORER` and `SVZCHF` from `VAULT` and `SV_ZCHF` inside its own process (L152-L153), so neither is an operator obligation. Every other alias pair below IS: `VAULT` and `AUREUM_VAULT` hold the same address under two keys, and so do `BODENSEE_POOL` and `DER_BODENSEE_POOL`. Setting only one of a pair leaves a later step reading an empty key and aborting mid-sequence.

**Which branch this sequence is on — read before running anything.** Section 6 is written for a GREENFIELD deployment that starts at step 1. The live Sepolia sequence is a RESUME: the 87 stubs at nonces 0—86 are already deployed and are reused from the committed `STUB_` map, so step 1 is NOT run and the sequence begins at step 2. Re-broadcasting step 1 mints a fresh stub roster from the live nonce upward, orphans the map every later step reads, and consumes the nonces all seven address projections derive from, voiding them and forcing phase A to restart against a re-funded deployer. Before step 2, confirm the reused map is real rather than assumed: every address in the `STUB_` block of `.env` must have code on chain, which is the confirm-and-skip form A2 takes on this branch. Per PB-D38 (ii); the live projections are in `docs/STAGE_P_BIS_PHASE_A_RECORD.md` section 7.

**Step 1 — testnet stubs.**

- Command: `forge script test-stubs/DeployTestnetStubs.s.sol:DeployTestnetStubs`
- Reads: the `DECIMALS_` table merged per prerequisite 5. Every STANDARD slot reads its key with no default, so a missing entry aborts before any stub is constructed.
- Emits: the stub map on stdout, already `.env`-shaped, as `STUB_<mainnet literal>=<sepolia stub>` pairs plus seven named keys: `WAETHWSTETH_COMPOSITE_RATE_PROVIDER`, `SFRXETH_RATE_PROVIDER`, `WOETH_RATE_PROVIDER`, `YSYBOLD_RATE_PROVIDER`, `SCRVUSD_RATE_PROVIDER`, `SV_ZCHF`, `SUSDS`.
- Capture: redirect the emitted map and append it to `.env.sepolia`. Because the emission is already `.env`-shaped this is a redirect, not a parse (PB-D27 (iii)). It must land before step 5, which is the first consumer of `SV_ZCHF`, `SUSDS` and the two rate-provider `STUB_` keys.

**Step 2 — Aureum Vault.**

- Command: `forge script script/DeployAureumVault.s.sol:DeployAureumVault`
- Reads: `GOVERNANCE_MULTISIG`, `DER_BODENSEE_POOL`, `FEE_ROUTING_HOOK`, `SALT`, `PAUSE_WINDOW_DURATION`, `BUFFER_PERIOD_DURATION`, `MIN_TRADE_AMOUNT`, `MIN_WRAP_AMOUNT`. The two prediction keys must already hold the section 3 projections.
- Emits: nothing on stdout. This script logs no address.
- Capture: none is required, and none should be parsed out of `broadcast/*.json`. All four addresses are projections the operator already computed: the authorizer at nonce N, the fee controller at N+1, the vault factory at N+2, and the Vault as `CREATE3.getDeployed(SALT, factory)`. The script asserts the factory itself at L203-L205; the broadcast confirms the projection rather than revealing it.
- Set in `.env.sepolia`: `VAULT` and `AUREUM_VAULT`, both to the projected Vault address, and `FEE_CONTROLLER` to the nonce-N+1 projection.

**Step 3 — weighted pool factory.**

- Command: `forge script script/DeployAureumWeightedPoolFactory.s.sol:DeployAureumWeightedPoolFactory`
- Reads: `AUREUM_VAULT`.
- Emits: `Aureum WeightedPoolFactory (WPF) deployed at:` followed by the address.
- Set in `.env.sepolia`: `WEIGHTED_POOL_FACTORY` and `AUREUM_WEIGHTED_POOL_FACTORY`, both to that one address, per PB-D27 (ix). Sepolia deploys the UPSTREAM Balancer factory; the two `create()` parameter lists are selector-identical, so the pool scripts' Aureum-typed cast dispatches against it and executes the upstream body with the factory-level quality gate skipped silently. The script-side gate remains operative, so the admitted set is unchanged.
- Confirm the logged address equals the projection used to derive der Bodensee in section 3. A divergence here invalidates that derivation and the sequence must stop.

**Step 4 — AuMM.**

- Command: `forge script script/DeployAuMM.s.sol:DeployAuMM`
- Reads: `GENESIS_BLOCK`, `GOVERNANCE_MULTISIG`.
- Set `GENESIS_BLOCK` immediately before this step, to the current Sepolia head plus one epoch of blocks per PB-D19, decoupling the emission clock from deploy time. `DeployAuMM.s.sol` L33 reads it with no `block.number` clamp, so the value is taken literally.
- Emits: `AuMM deployed at:` followed by the address.
- Set in `.env.sepolia`: `AUMM`.

**Step 5 — fee routing hook.**

- Command: `forge script script/DeployFeeRoutingHook.s.sol:DeployFeeRoutingHook`
- Reads: `FEE_ROUTING_HOOK`, `VAULT`, `DER_BODENSEE_POOL`, `SV_ZCHF`, `SUSDS`, `AUMM`, `FEE_CONTROLLER`, `GOVERNANCE_MULTISIG`.
- Emits: `AureumFeeRoutingHook deployed at:` followed by the address.
- The script asserts the deployed hook equals `FEE_ROUTING_HOOK` and reverts `HookAddressMismatch` otherwise, before the success log.
- Set in `.env.sepolia`: nothing new. `FEE_ROUTING_HOOK` already holds the projection; confirm the logged address matches it.
- This step precedes der Bodensee deliberately, per PB-D30. `DER_BODENSEE_POOL` is read here as a projection only — the hook's constructor zero-checks it and then stores it without ever calling it, so der Bodensee needs no code yet, and `DeployDerBodensee` in turn reads no `FEE_ROUTING_HOOK` key at all. Do not restore the older Bodensee-then-hook order: it puts a step that cannot be simulated before the broadcast inside the hook's own nonce projection, which is what made the pre-broadcast count set unobtainable.

**Step 6 — der Bodensee.**

- Command: `forge script script/DeployDerBodensee.s.sol:DeployDerBodensee`
- Reads: `WEIGHTED_POOL_FACTORY`, `AUMM`, `SV_ZCHF`, `SUSDS`, `GOVERNANCE_MULTISIG`, `BODENSEE_SALT`, `DER_BODENSEE_POOL`, plus the two rate-provider `STUB_` keys from step 1.
- Emits: `der-Bodensee pool deployed at:` followed by the address.
- The script asserts the created pool equals `DER_BODENSEE_POOL` and reverts `BodenseeAddressMismatch` otherwise, before the success log.
- Set in `.env.sepolia`: `BODENSEE_POOL`, to the same address. Do NOT rewrite `DER_BODENSEE_POOL` — it already holds the projection, and the two keys are read by different scripts.

**Step 7 — Router.**

- Command: `forge script script/DeployRouter.s.sol:DeployRouter`
- Reads: `AUREUM_VAULT`, `WETH_ADDRESS`, `PERMIT2_ADDRESS`. `PERMIT2_ADDRESS` is the canonical cross-chain instance verified present at PB3.1; `WETH_ADDRESS` is the operator-pinned Sepolia value described above.
- Emits: `Aureum Router deployed at:` followed by the address.
- Set in `.env.sepolia`: `ROUTER`. No script reads this key — the operator needs it for the phase 5 trusted-router seat, which no script performs.

**Gas budget (PB-D27 (vii)(1)).** The full spine — testnet stubs through the Router seat, replayed end-to-end at `test/fork/StagePRunRehearsal.t.sol` `setUp()` — measures 367,079,280 gas, identical across all nine fork tests: `setUp` re-runs per test, so nine matching values is the harness's own determinism check, confirming nothing nondeterministic sits in the deployment path. At 1-3 gwei Sepolia basefee this is 0.37-1.10 SepETH. The figure is a floor, not the live cost: `forge script --broadcast` sends each `new X(...)` as its own transaction, adding per-transaction intrinsic gas plus init-code calldata at 16 gas/byte on top of the fork-measured opcode cost, on the order of 2-3%. Fund the deployer to roughly 1-2 SepETH via the pk910 PoW faucet before starting phase 1 — the 0.05 SepETH from PB3.1 is 7 to 22 times short.

## 7. Phase 3 to 6 — pools, orchestration, Router seat, verification

**Phase 3 — the 26 Miliarium pools.**

All 26 are Miliarium Aureum pools. They occupy slots in one flat slot space numbered 1 to 28, and `MiliariumRegistry.slotOf(pool)` returns a single slot number for any of them — there is no second pool class anywhere in the registry, and der Bodensee, the only other pool in the protocol, holds no slot and is not one of them. Every key is `MILIARIUM_POOL_nn` for the pool's slot number, uniformly. The `PILOT_` and `MAJOR_` prefixes that eight of these keys carried until PB-D40 recorded only which stage each pool first landed in, never a class; they survive in completed-stage plans and notes as history, and nothing in the deploy path reads them.

Each pool is its own invocation, in the same form as section 6. Every one of the 26 scripts emits the SAME stdout line — `Miliarium pool deployed at:` — from the shared base at `script/pools/deploy-miliarium-pool.s.sol` L129, with nothing in the line identifying which pool it was. Stdout alone therefore cannot tell the deployments apart. Run one script at a time and record its address before starting the next, or key the capture off `broadcast/<ScriptName>.s.sol/11155111/run-latest.json`, which is named per script and is unambiguous. Do not batch the 26 and reconcile the log afterwards.

The slot each script fills appears nowhere in the script itself. The mapping below comes from `test/fork/StagePRunRehearsal.t.sol` L216-L256 paired with L268-L318, the only place in the repo binding script to key, validated by that fixture running 9/9 fork-green. It is listed in slot order; deployment order is unconstrained, since the pool scripts have no dependency on one another and every base-layer address projection is already fixed before phase 3 begins.

| Slot | Script | `.env.sepolia` key |
| --- | --- | --- |
| 01 | `DeployIxHelvetia` | `MILIARIUM_POOL_01` |
| 02 | `DeployIxAetheron` | `MILIARIUM_POOL_02` |
| 03 | `DeployIxCasper` | `MILIARIUM_POOL_03` |
| 05 | `DeployIxEdelweiss` | `MILIARIUM_POOL_05` |
| 06 | `DeployIxLibertas` | `MILIARIUM_POOL_06` |
| 08 | `DeployIxBrevis` | `MILIARIUM_POOL_08` |
| 09 | `DeployIxAltrix` | `MILIARIUM_POOL_09` |
| 10 | `DeployIxMediox` | `MILIARIUM_POOL_10` |
| 11 | `DeployIxLongus` | `MILIARIUM_POOL_11` |
| 12 | `DeployIxStrata` | `MILIARIUM_POOL_12` |
| 13 | `DeployIxForum` | `MILIARIUM_POOL_13` |
| 14 | `DeployIxAurebit` | `MILIARIUM_POOL_14` |
| 15 | `DeployIxRegistrum` | `MILIARIUM_POOL_15` |
| 16 | `DeployIxDebitum` | `MILIARIUM_POOL_16` |
| 17 | `DeployIxEquitix` | `MILIARIUM_POOL_17` |
| 18 | `DeployIxInnovix` | `MILIARIUM_POOL_18` |
| 19 | `DeployIxGigantus` | `MILIARIUM_POOL_19` |
| 20 | `DeployIxMagnix` | `MILIARIUM_POOL_20` |
| 21 | `DeployIxNubix` | `MILIARIUM_POOL_21` |
| 22 | `DeployIxMoneta` | `MILIARIUM_POOL_22` |
| 23 | `DeployIxColossix` | `MILIARIUM_POOL_23` |
| 24 | `DeployIxVitalix` | `MILIARIUM_POOL_24` |
| 25 | `DeployIxMedicix` | `MILIARIUM_POOL_25` |
| 26 | `DeployIxMercatura` | `MILIARIUM_POOL_26` |
| 27 | `DeployIxAurix` | `MILIARIUM_POOL_27` |
| 28 | `DeployIxMetallum` | `MILIARIUM_POOL_28` |

Slots 04 and 07 are absent by design: ixViatica and ixCambio were descoped to the Stage-O composition-challenge path at PB-D8, so the constellation launches 26 of 28. The gaps are expected and are not missed deployments.

Every one of the 26 keys must be in `.env` before phase 4. `DeployStageP` drives Stage I, M and N inside its own process and those read the keys directly, so a single missing key aborts the orchestrator partway through a sequence that has already broadcast.

**Phase 4 — the orchestrator.**

- Command: `forge script script/DeployStageP.s.sol:DeployStageP`
- One invocation, one process, composing Stage F through Stage K per PB-D23 (vii). It threads its own intermediate addresses internally, so nothing between Stage F and Stage K needs capturing: `MILIARIUM_REGISTRY`, `TVL_ORACLE`, `EFFICIENCY_ORACLE`, `EMA_SAMPLER`, `CCB_MULTIPLIER`, `SWAP_AND_DEPOSIT`, `VAULT_CLASS_REGISTRY`, `GAUGE_REGISTRY`, `EMISSION_DISTRIBUTOR` and `BODENSEE_CHANNEL` are all set by the orchestrator on itself as it goes.
- Reads from `.env`: everything phases 1 to 3 wrote, plus `EMERGENCY_MULTISIG`, consumed by `DeployStageK.s.sol` L125 and one of the keys missing from `.env.example`.
- The run asserts its own post-conditions, including the four-way genesis check and the authorizer migration. A revert here stops the sequence with the base layer already live; it does not unwind.

**Phase 5 — the Router seat (F-09).**

No script performs this. `DeployStageP.s.sol` L255 records that the orchestrator makes no `setTrustedRouter` call, structurally, per P-D26 (4). The seat is two governor-signed transactions, in this order: point the governance module at the governor, then seat the Router. `script/DeployRouter.s.sol` L25 documents the pair as `setGovernanceModule(GOVERNANCE_MULTISIG)` followed by `setTrustedRouter(router, true)`, using the `ROUTER` address captured at step 7.

Load-bearing rather than cosmetic: an unseated Router still mints BPT on an add, but the position is never recorded, so the LP holds a receipt the protocol does not know about — the F-09 fail-closed behaviour the PB3.3 fork witness pinned as a negative case before seating and as a credited add afterwards.

**Phase 6 — verification.**

With `ETHERSCAN_API_KEY` provisioned per prerequisite 3, contracts deployed with `--verify` are submitted automatically. Anything deployed before the key was in place, or whose verification failed in flight, is re-submitted with `forge verify-contract` against the Sepolia explorer. Der Bodensee and the 26 Miliarium pools are CREATE3 deployments made by the factory rather than by the deployer EOA, so verification is submitted against the pool address with the factory's pool creation code, not against a deployer transaction.

Recording the full deployed set into `test-stubs/sepolia-stubs.env` per PB-D21 (v), replacing the committed fork-sample addresses with live Sepolia ones, is rung i rather than this one.

## 8. Rung h — the pre-broadcast dry run

Governed by PB-D29 and PB-D30. Phase A runs once, before the first broadcast command of section 6. Phase B runs per step, interleaved with that sequence.

**Why this is two phases and not one dry run.** Two mechanics rule out a single upfront full-sequence run. Simulation sends nothing, so the deployer nonce never advances: every step simulated before any broadcast places its CREATEs at the same live nonce, never at the chained nonce it will occupy, so a chained projection cannot be verified in advance even in principle. And every step past the vault consumes a live predecessor, so it reverts pre-broadcast against an address carrying no code, for a reason unrelated to prediction. Phase A therefore computes the projections analytically; phase B verifies each one against reality at the moment it becomes checkable.

**Simulation form.** Every command in phase A and phase B is a section 6 command with `--broadcast` omitted: `forge script <path>:<Contract> --rpc-url $SEPOLIA_RPC_URL --sender 0xA851478dbee97375E784e9b98c0D7D599662bF85`. Nothing is sent and no nonce moves.

**Where phase A writes.** Every projection phase A computes is written into `.env.sepolia`, never into `.env` directly, per section 1's write-direction rule. Phase A's simulations read `.env` like any other command, and several of them read a key an earlier step just projected — A6 reads `AUREUM_VAULT` from A3, A8 reads `GENESIS_BLOCK` — so run `cp .env.sepolia .env` after each write and before the next simulation. A projection that never reaches `.env` produces a simulation that fails on an empty key, or worse one that silently runs against the previous value.

**Reading a transaction count.** The count is the number of entries in the `transactions` array of the dry-run artifact forge writes under `broadcast/<ScriptFile>.s.sol/11155111/dry-run/run-latest.json`: `jq '.transactions | length' <that path>`, or any equivalent parse scoped to that top-level array. Confirm the artifact path on the first invocation and use whatever path forge actually reports if it differs on this toolchain. The grep-based fallback that counted occurrences of the per-transaction type field is WITHDRAWN per PB-D38 (iv) and must not be reintroduced: entries inside a transaction's `additionalContracts` array carry that same field, so such a count is inflated by every contract a call deploys internally. Measured at step 2, where `factory.create()` deploys VaultAdmin, VaultExtension, the CREATE3 proxy and the Vault, that form returns 8 against the authoritative 4.

**Greenfield versus resume.** Phase A runs in one of two modes and the arithmetic below differs between them, per PB-D38 (ii). GREENFIELD, which is the case every A-step below is written for: step 1 is broadcast within this sequence, A2 measures `c1`, and A3, A5 and A9 consume it exactly as written. RESUME: the stubs at nonces `[0, n0)` are already live on chain from an earlier sequence and step 1 is NOT re-broadcast, so effective `c1 = 0` and every `c1` term below drops out — A3 projects the authorizer at `n0`, the fee controller at `n0 + 1` and the vault factory at `n0 + 2`; A5 projects the weighted-pool factory at `n0 + c2`; A9 projects the fee-routing hook at `n0 + c2 + c3 + c4`. On the resume branch A2 becomes confirm-and-skip: verify that every address in the reused `STUB_` map has code on chain, and do not re-broadcast step 1, which would mint a fresh roster from `n0` upward and orphan the live map. Section 5 row 1's count of 87 is the fresh-deploy figure and is never an addend on a resume.

### Phase A — before any broadcast

**A1. Record the live nonce.** `cast nonce 0xA851478dbee97375E784e9b98c0D7D599662bF85 --rpc-url $SEPOLIA_RPC_URL`. Call it `n0`. Every projection below is relative to it, and any transaction sent from the deployer between A1 and the first broadcast invalidates all of them — if that happens, restart phase A.

**A2. Count step 1.** Simulate `DeployTestnetStubs`. Record the count as `c1` in section 5 row 1.

**A3. Project the vault step.** `cast compute-address 0xA851478dbee97375E784e9b98c0D7D599662bF85 --nonce <n0 + c1>` is the authorizer; `--nonce <n0 + c1 + 1>` is the fee controller, which is `FEE_CONTROLLER`; `--nonce <n0 + c1 + 2>` is the vault factory. The Vault itself is a CREATE3 from that factory using the RAW `SALT` value — not the sender-hashed form — per the derivation in the closing subsection. Write it to both `VAULT` and `AUREUM_VAULT`.

**A4. Count step 2.** Set `DER_BODENSEE_POOL` and `FEE_ROUTING_HOOK` to any non-zero placeholder for this run only. The fee controller zero-checks both (`ZeroBodenseeAddress`, `ZeroHookAddress`) but never calls them, so a placeholder passes and no code is needed at either address. Simulate `DeployAureumVault`. Record the count as `c2` in section 5 row 2. The addresses this run reports will NOT match the A3 projections, because the simulation runs at `n0` rather than at `n0 + c1`. That divergence is expected and is not an error. Take only the count from this run and write none of its addresses into `.env.sepolia`.

**A5. Project the weighted-pool factory.** `cast compute-address 0xA851478dbee97375E784e9b98c0D7D599662bF85 --nonce <n0 + c1 + c2>`. Write it to both `WEIGHTED_POOL_FACTORY` and `AUREUM_WEIGHTED_POOL_FACTORY`, one address under two keys per PB-D27 (ix).

**A6. Count step 3.** With `AUREUM_VAULT` holding the A3 projection, simulate `DeployAureumWeightedPoolFactory`. Record the count as `c3` in section 5 row 3. The projected vault needs no code here: the constructor chain is pure storage — `WeightedPoolFactory` into `BasePoolFactory` stores `_creationCode`, `SingletonAuthentication` stores `_vault`, and nothing in that chain calls the vault.

**A7. Project der Bodensee.** A CREATE3 from the A5 factory, using the SENDER-HASHED salt, per the closing subsection. Write it to `DER_BODENSEE_POOL`, replacing the A4 placeholder.

**A8. Count step 4.** Set `GENESIS_BLOCK` first, per section 6 step 4. Simulate `DeployAuMM`. Record the count as `c4` in section 5 row 4.

**A9. Project the fee-routing hook.** `cast compute-address 0xA851478dbee97375E784e9b98c0D7D599662bF85 --nonce <n0 + c1 + c2 + c3 + c4>`. Write it to `FEE_ROUTING_HOOK`, replacing the A4 placeholder. This is the step the PB-D30 reorder exists to make computable: with the hook at step 5 no der-Bodensee count enters this sum, and der Bodensee at step 6 needs no nonce projection at all.

**A10. Close phase A.** Section 5 rows 1 through 4 now hold real counts; rows 5 through 8 and row 10 stay `PENDING-h` and fill from the broadcast itself at rung i, since no projection reads them. Row 9 is separately filled per PB-D48, from a rung-h9 dry run rather than from phase A or the broadcast. Before step 2 may run, `.env.sepolia` must hold, with `.env` refreshed from it: `VAULT`, `AUREUM_VAULT`, `FEE_CONTROLLER`, `WEIGHTED_POOL_FACTORY`, `AUREUM_WEIGHTED_POOL_FACTORY`, `DER_BODENSEE_POOL` and `FEE_ROUTING_HOOK`, all from the projections above and none from a simulation's reported output.

### Phase B — interleaved with the broadcast

**Before each broadcast step, simulate it.** Run that step's exact section 6 command with `--broadcast` omitted, and confirm the address it reports equals the projection already in `.env`. By this point the step's predecessors are live, so the simulation runs at the true nonce and its reported address is the one the send will produce. Any divergence aborts the sequence — do not broadcast the step and do not edit the projection to match.

**The self-asserts do this for three steps automatically.** `FactoryAddressMismatch`, `HookAddressMismatch` and `BodenseeAddressMismatch` fire identically under simulation and under broadcast, so for steps 2, 5 and 6 a mismatch reverts the simulation rather than requiring a manual compare.

**What phase B cannot undo.** The vault seals `DER_BODENSEE_POOL` and `FEE_ROUTING_HOOK` as immutables at step 2. If either projection is wrong, it is already immutable by the time step 5 or step 6 asserts against it: the assert stops the sequence compounding but cannot unwind the vault, and recovery is a full restart of the whole sequence on fresh addresses. That is the accepted failure mode PB-D27 (iv) records, tolerable on testnet gas, and it is why the A3 through A9 arithmetic is double-checked before step 2 rather than trusted to the asserts.

### The CREATE3 derivation

`CREATE3.getDeployed(salt, creator)` at `lib/balancer-v3-monorepo/pkg/solidity-utils/contracts/solmate/CREATE3.sol` L64-L86 is two steps: a CREATE2 proxy from the creator, then a plain CREATE from that proxy at nonce 1. Both are computable with stock `cast`, in four commands. The proxy init-code hash is `0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f`, reproducible as `cast keccak 0x67363d3d37363d34f03d5260086018f3`; confirm it matches before relying on it.

For der Bodensee the salt is sender-hashed, because `BasePoolFactory._computeFinalSalt` hashes the broadcast sender: `cast keccak $(cast abi-encode "f(address,uint256,bytes32)" 0xA851478dbee97375E784e9b98c0D7D599662bF85 11155111 $BODENSEE_SALT)` gives the final salt; then `cast create2 --deployer <the A5 factory> --salt <that final salt> --init-code-hash 0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f` gives the proxy; then `cast compute-address <that proxy> --nonce 1` gives the pool.

For the Vault the salt is RAW — the vault factory's CREATE3 does not hash the sender — so the same three commands run with `--salt $SALT` directly and `--deployer <the A3 vault factory>`. Applying the sender-hashed form to the Vault, or the raw form to der Bodensee, produces a wrong address that nothing catches until the corresponding step aborts.

**Residual, narrowed at the first phase A run.** The command chain itself is no longer unvalidated: at PB3.5h2 the three plain CREATEs and the CREATE3 Vault were all reproduced exactly by these commands at nonce 0, checked against forge's own dry-run artifact, with the artifact's `additionalContracts` corroborating the two-step mechanism — recorded in full at `docs/STAGE_P_BIS_PHASE_A_RECORD.md` section 5. What remains is narrower and still real: that validation was performed at nonce 0, and applying it to nonces 87 through 93 rests entirely on the section 5 counts being right. A count wrong by one shifts every projection downstream of it, and no check here would catch that — the derivation would still be correct, applied to the wrong nonce. The first live confirmation remains `BodenseeAddressMismatch` at step 6, which is after the vault has sealed its immutables.
