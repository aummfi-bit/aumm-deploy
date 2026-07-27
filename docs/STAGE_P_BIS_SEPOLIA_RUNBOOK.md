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
| 2 | Deployer EOA funded with SepETH | 0.05 at PB3.1; target ~1-2 SepETH per the rung f gas measurement, section 6 | before phase 1 |
| 3 | `ETHERSCAN_API_KEY` present in `.env` | ABSENT at PB3.1 — must be provisioned | before verification |
| 4 | Canonical Permit2 at `0x000000000022D473030F116dDEE9F6B43aC78BA3` | verified present at PB3.1 | — |
| 5 | `script/config/mainnet-token-decimals.env` merged into `.env` | committed at PB3.5b2 | before phase 1 |

## 3. Prediction model

**Why every rehearsal formula is wrong here.** Under `--broadcast` forge never puts the script contract on chain. Each `new X(...)` inside a script becomes a transaction sent from the deployer EOA, so the CREATE originates at that EOA's address and nonce, not at the script's. Every prediction formula in the fork fixtures is therefore a harness artifact: `vm.computeCreateAddress(address(hookScript), 1)` and the harness-creator CREATE3 at `test/fork/StagePRunRehearsal.t.sol` L130-L138 are correct in a test process and structurally wrong live. Re-reading the live nonce between steps does not rescue them, because the addresses that must be known first are produced several steps later.

**The cycle is four deep.** `script/DeployAureumVault.s.sol` L127-L128 reads BOTH `DER_BODENSEE_POOL` and `FEE_ROUTING_HOOK` before it deploys anything, and the fee controller seals both as immutables at L184-L188. The hook needs the Vault. Der Bodensee is created by the weighted-pool factory, and the factory needs the Vault. So the two addresses the FIRST step consumes are produced by two of the LAST steps.

**Inside the vault step the projection is already live-correct.** `run()` passes `msg.sender` into `_deploy` at L95-L97, which reads that EOA's live nonce and projects the authorizer at N, the fee controller at N+1 and the factory at N+2 (L164), then derives the Vault as a CREATE3 from the predicted factory (L171). Nothing there needs external help; only the step's INPUTS do.

**Der Bodensee's salt is scoped to the broadcast sender.** `BasePoolFactory._computeFinalSalt` is `keccak256(abi.encode(msg.sender, block.chainid, salt))` at `lib/balancer-v3-monorepo/pkg/pool-utils/contracts/BasePoolFactory.sol` L126-L128, and the CREATE3 creator is the factory rather than the caller. `DeployDerBodensee.run()` opens a bare `vm.startBroadcast()`, so the `msg.sender` the factory hashes is the broadcast sender, which under `--broadcast` is the deployer EOA. PB3.5d established this by execution rather than by reading: `test/fork/DerBodenseeScriptWitness.t.sol` drives the real script, and the pool lands exactly at the address derived from the broadcast sender rather than from the script contract or the test contract. That witness pins the MECHANISM; the live case substitutes the deployer EOA for the test default sender.

**What the operator must project, and when.** Before the first broadcast: the weighted-pool factory, as an EOA CREATE at the nonce the vault step leaves behind; der Bodensee, as `CREATE3.getDeployed(keccak256(abi.encode(deployerEOA, 11155111, BODENSEE_SALT)), predictedFactory)`; and the hook, as an EOA CREATE at the nonce reached after the factory, AuMM and der-Bodensee steps. The last two are written into `.env` as `DER_BODENSEE_POOL` and `FEE_ROUTING_HOOK` before `DeployAureumVault` runs. Each projection advances the nonce by the per-step transaction totals of the steps in between — which is exactly what section 5 does not yet contain. Rung h derives those totals from its own dry run at the real deployer nonce and fills section 5 in. Until it has, the projection cannot be computed and no broadcast may begin.

**Three self-asserts, and what they do not undo.** `DeployAureumVault` reverts `FactoryAddressMismatch` if its own factory lands off-projection (L203-L205); `DeployDerBodensee` reverts `BodenseeAddressMismatch` if the created pool diverges from `DER_BODENSEE_POOL` (PB3.5c1b); `DeployFeeRoutingHook` reverts `HookAddressMismatch` if the deployed hook diverges from `FEE_ROUTING_HOOK` (PB3.5c2). The first is self-contained within its step. The other two compare against predictions the fee controller has ALREADY sealed as immutables, so by the time either fires the damage is done: the assert stops the sequence from compounding, but it cannot unwind the vault. Recovery is a full restart of the whole sequence on fresh addresses. That is tolerable on testnet gas and is precisely why the rung h dry run is mandatory rather than advisory.

## 4. Phase overview

The base layer stays per-granular per PB-D23 (vii); the Stage F-to-K orchestration stays the single composed `DeployStageP.run()`. Collapsing either was rejected at PB-D27 (i).

1. **Stubs.** `test-stubs/DeployTestnetStubs.s.sol` deploys the testnet token roster.
2. **Base layer, per-granular.** `DeployAureumVault`, `DeployAureumWeightedPoolFactory`, `DeployAuMM`, `DeployDerBodensee`, `DeployFeeRoutingHook`, `DeployRouter` — in an order fixed by the PB-D27 (iv) address cycle, not by convenience.
3. **Pools.** The 26 pool scripts under `script/pools/`. All 26 are Miliarium pools occupying slots in one flat slot space numbered 1 to 28; the `PILOT_`, `MAJOR_` and `MILIARIUM_` env-key prefixes are deploy-plumbing artifacts of the stage each pool first landed in, not a pool taxonomy. All 26 keys must be in `.env` before phase 4, because `DeployStageP` drives Stage I, M and N internally and those read them.
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

## 6. Phase 1 and 2 — commands and capture

**Invocation form.** Every command in this section is `forge script <path>:<Contract> --rpc-url $SEPOLIA_RPC_URL --broadcast --account aumm-sepolia --sender 0xA851478dbee97375E784e9b98c0D7D599662bF85`. Once `ETHERSCAN_API_KEY` is provisioned per prerequisite 3, append `--verify --etherscan-api-key $ETHERSCAN_API_KEY`.

**Key posture (PB-D27 (vii)(3)).** The deployer key is imported once into forge's keystore with `cast wallet import aumm-sepolia --interactive` and referenced thereafter as `--account aumm-sepolia`. The key never appears on a command line, in shell history, or in `.env`. Chosen over per-invocation `--interactive` because this sequence runs to roughly three dozen invocations and paste-fatigue across that many prompts is its own failure mode.

**Salts pinned for this deployment.** `SALT` is `0x0000000000000000000000000000000000000000000000000000000000000001`. `BODENSEE_SALT` is `0x0000000000000000000000000000000000000000000000000000000000000002`, matching the PB3.4 rehearsal so that the rung h dry run exercises the same der-Bodensee derivation the live broadcast will. `.env.example` L96 carries a zero value for `BODENSEE_SALT` and is stale against this decision; correcting it is a later rung, and the value above is authoritative.

**Keys absent from `.env.example`.** `EMERGENCY_MULTISIG` (read by `DeployStageK.s.sol` L125), `WETH_ADDRESS` and `GENESIS_BLOCK` are all consumed by this sequence but are not in the committed template. Add them before the steps that need them. `WETH_ADDRESS` has no Sepolia value anywhere in this repo — the fork fixtures inject the mainnet WETH literal, which has no code on Sepolia — so a Sepolia WETH must be pinned by the operator before step 7.

**Aliases the orchestrator bridges, and the ones it does not.** `DeployStageP` sets `VAULT_EXPLORER` and `SVZCHF` from `VAULT` and `SV_ZCHF` inside its own process (L152-L153), so neither is an operator obligation. Every other alias pair below IS: `VAULT` and `AUREUM_VAULT` hold the same address under two keys, and so do `BODENSEE_POOL` and `DER_BODENSEE_POOL`. Setting only one of a pair leaves a later step reading an empty key and aborting mid-sequence.

**Step 1 — testnet stubs.**

- Command: `forge script test-stubs/DeployTestnetStubs.s.sol:DeployTestnetStubs`
- Reads: the `DECIMALS_` table merged per prerequisite 5. Every STANDARD slot reads its key with no default, so a missing entry aborts before any stub is constructed.
- Emits: the stub map on stdout, already `.env`-shaped, as `STUB_<mainnet literal>=<sepolia stub>` pairs plus seven named keys: `WAETHWSTETH_COMPOSITE_RATE_PROVIDER`, `SFRXETH_RATE_PROVIDER`, `WOETH_RATE_PROVIDER`, `YSYBOLD_RATE_PROVIDER`, `SCRVUSD_RATE_PROVIDER`, `SV_ZCHF`, `SUSDS`.
- Capture: redirect the emitted map and append it to `.env`. Because the emission is already `.env`-shaped this is a redirect, not a parse (PB-D27 (iii)). It must land before step 5, which is the first consumer of `SV_ZCHF`, `SUSDS` and the two rate-provider `STUB_` keys.

**Step 2 — Aureum Vault.**

- Command: `forge script script/DeployAureumVault.s.sol:DeployAureumVault`
- Reads: `GOVERNANCE_MULTISIG`, `DER_BODENSEE_POOL`, `FEE_ROUTING_HOOK`, `SALT`, `PAUSE_WINDOW_DURATION`, `BUFFER_PERIOD_DURATION`, `MIN_TRADE_AMOUNT`, `MIN_WRAP_AMOUNT`. The two prediction keys must already hold the section 3 projections.
- Emits: nothing on stdout. This script logs no address.
- Capture: none is required, and none should be parsed out of `broadcast/*.json`. All four addresses are projections the operator already computed: the authorizer at nonce N, the fee controller at N+1, the vault factory at N+2, and the Vault as `CREATE3.getDeployed(SALT, factory)`. The script asserts the factory itself at L203-L205; the broadcast confirms the projection rather than revealing it.
- Set in `.env`: `VAULT` and `AUREUM_VAULT`, both to the projected Vault address, and `FEE_CONTROLLER` to the nonce-N+1 projection.

**Step 3 — weighted pool factory.**

- Command: `forge script script/DeployAureumWeightedPoolFactory.s.sol:DeployAureumWeightedPoolFactory`
- Reads: `AUREUM_VAULT`.
- Emits: `Aureum WeightedPoolFactory (WPF) deployed at:` followed by the address.
- Set in `.env`: `WEIGHTED_POOL_FACTORY` and `AUREUM_WEIGHTED_POOL_FACTORY`, both to that one address, per PB-D27 (ix). Sepolia deploys the UPSTREAM Balancer factory; the two `create()` parameter lists are selector-identical, so the pool scripts' Aureum-typed cast dispatches against it and executes the upstream body with the factory-level quality gate skipped silently. The script-side gate remains operative, so the admitted set is unchanged.
- Confirm the logged address equals the projection used to derive der Bodensee in section 3. A divergence here invalidates that derivation and the sequence must stop.

**Step 4 — AuMM.**

- Command: `forge script script/DeployAuMM.s.sol:DeployAuMM`
- Reads: `GENESIS_BLOCK`, `GOVERNANCE_MULTISIG`.
- Set `GENESIS_BLOCK` immediately before this step, to the current Sepolia head plus one epoch of blocks per PB-D19, decoupling the emission clock from deploy time. `DeployAuMM.s.sol` L33 reads it with no `block.number` clamp, so the value is taken literally.
- Emits: `AuMM deployed at:` followed by the address.
- Set in `.env`: `AUMM`.

**Step 5 — der Bodensee.**

- Command: `forge script script/DeployDerBodensee.s.sol:DeployDerBodensee`
- Reads: `WEIGHTED_POOL_FACTORY`, `AUMM`, `SV_ZCHF`, `SUSDS`, `GOVERNANCE_MULTISIG`, `BODENSEE_SALT`, `DER_BODENSEE_POOL`, plus the two rate-provider `STUB_` keys from step 1.
- Emits: `der-Bodensee pool deployed at:` followed by the address.
- The script asserts the created pool equals `DER_BODENSEE_POOL` and reverts `BodenseeAddressMismatch` otherwise, before the success log.
- Set in `.env`: `BODENSEE_POOL`, to the same address. Do NOT rewrite `DER_BODENSEE_POOL` — it already holds the projection, and the two keys are read by different scripts.

**Step 6 — fee routing hook.**

- Command: `forge script script/DeployFeeRoutingHook.s.sol:DeployFeeRoutingHook`
- Reads: `FEE_ROUTING_HOOK`, `VAULT`, `DER_BODENSEE_POOL`, `SV_ZCHF`, `SUSDS`, `AUMM`, `FEE_CONTROLLER`, `GOVERNANCE_MULTISIG`.
- Emits: `AureumFeeRoutingHook deployed at:` followed by the address.
- The script asserts the deployed hook equals `FEE_ROUTING_HOOK` and reverts `HookAddressMismatch` otherwise, before the success log.
- Set in `.env`: nothing new. `FEE_ROUTING_HOOK` already holds the projection; confirm the logged address matches it.

**Step 7 — Router.**

- Command: `forge script script/DeployRouter.s.sol:DeployRouter`
- Reads: `AUREUM_VAULT`, `WETH_ADDRESS`, `PERMIT2_ADDRESS`. `PERMIT2_ADDRESS` is the canonical cross-chain instance verified present at PB3.1; `WETH_ADDRESS` is the operator-pinned Sepolia value described above.
- Emits: `Aureum Router deployed at:` followed by the address.
- Set in `.env`: `ROUTER`. No script reads this key — the operator needs it for the phase 5 trusted-router seat, which no script performs.

**Gas budget (PB-D27 (vii)(1)).** The full spine — testnet stubs through the Router seat, replayed end-to-end at `test/fork/StagePRunRehearsal.t.sol` `setUp()` — measures 367,079,280 gas, identical across all nine fork tests: `setUp` re-runs per test, so nine matching values is the harness's own determinism check, confirming nothing nondeterministic sits in the deployment path. At 1-3 gwei Sepolia basefee this is 0.37-1.10 SepETH. The figure is a floor, not the live cost: `forge script --broadcast` sends each `new X(...)` as its own transaction, adding per-transaction intrinsic gas plus init-code calldata at 16 gas/byte on top of the fork-measured opcode cost, on the order of 2-3%. Fund the deployer to roughly 1-2 SepETH via the pk910 PoW faucet before starting phase 1 — the 0.05 SepETH from PB3.1 is 7 to 22 times short.

## 7. Phase 3 to 6 — pools, orchestration, Router seat, verification

**Phase 3 — the 26 Miliarium pools.**

All 26 are Miliarium pools. They occupy slots in one flat slot space numbered 1 to 28, and `MiliariumRegistry.slotOf(pool)` returns a single slot number for any of them — there is no second pool class anywhere in the registry. The `PILOT_`, `MAJOR_` and `MILIARIUM_` prefixes on the `.env` keys record only which stage each pool first landed in, and carry no meaning at deploy time. Reading `MAJOR_POOL_03` as a different kind of pool from `MILIARIUM_POOL_12` is the misreading this paragraph exists to prevent.

Each pool is its own invocation, in the same form as section 6. Every one of the 26 scripts emits the SAME stdout line — `Miliarium pool deployed at:` — from the shared base at `script/pools/deploy-miliarium-pool.s.sol` L129, with nothing in the line identifying which pool it was. Stdout alone therefore cannot tell the deployments apart. Run one script at a time and record its address before starting the next, or key the capture off `broadcast/<ScriptName>.s.sol/11155111/run-latest.json`, which is named per script and is unambiguous. Do not batch the 26 and reconcile the log afterwards.

The slot each script fills appears nowhere in the script itself. The mapping below comes from `test/fork/StagePRunRehearsal.t.sol` L216-L256 paired with L268-L318, the only place in the repo binding script to key, validated by that fixture running 9/9 fork-green. It is listed in slot order; deployment order is unconstrained, since the pool scripts have no dependency on one another and every base-layer address projection is already fixed before phase 3 begins.

| Slot | Script | `.env` key |
| --- | --- | --- |
| 01 | `DeployIxHelvetia` | `PILOT_POOL_01` |
| 02 | `DeployIxAetheron` | `MILIARIUM_POOL_02` |
| 03 | `DeployIxCasper` | `MAJOR_POOL_03` |
| 05 | `DeployIxEdelweiss` | `PILOT_POOL_05` |
| 06 | `DeployIxLibertas` | `MILIARIUM_POOL_06` |
| 08 | `DeployIxBrevis` | `MAJOR_POOL_08` |
| 09 | `DeployIxAltrix` | `MAJOR_POOL_09` |
| 10 | `DeployIxMediox` | `MAJOR_POOL_10` |
| 11 | `DeployIxLongus` | `MAJOR_POOL_11` |
| 12 | `DeployIxStrata` | `MILIARIUM_POOL_12` |
| 13 | `DeployIxForum` | `MILIARIUM_POOL_13` |
| 14 | `DeployIxAurebit` | `PILOT_POOL_14` |
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
