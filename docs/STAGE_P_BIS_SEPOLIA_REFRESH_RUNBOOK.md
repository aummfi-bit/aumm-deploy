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

## 5. Per-step EOA transaction counts

**This table ships COMPLETE, and that is the one place the refresh is better off than generation 1.** Its runbook shipped five cells reading PENDING-h because no broadcast had happened yet; here every count comes from a broadcast that has. PB-D27 (iv)(1) requires counts be derived from a run rather than read off the source, and a deployment that ran to completion satisfies that more strongly than the dry run the rule was written for. Every cell below names the deployment-record section it was measured from, so each is checkable against a committed artifact rather than against this document.

**Counts are invariant; addresses are not.** PB-D28 (ii) and PB-D29 (v) establish that a step's transaction count follows from its own CREATE and call sequence and does not move with the deployer's nonce or the chain. So phase A does NOT re-derive these. What phase A must do is read `n0` and recompute the projections, per section 3.

**Row 1 is not run** and carries no count. The 87 stubs are reused per PB-D70 (i), so `c1` leaves the arithmetic entirely rather than being carried as history.

**Rows 11 and 12 are new.** Generation 1's table stopped at row 10 because the oracle wiring and the pool seeding were PB3.8 work rather than PB3.5 work, and no single document ever costed the whole deployment. PB-D70 (xiv) puts them inside the refresh, so they are counted here.

**Row 9 is now a broadcast count.** Generation 1 recorded 114 from a `forge script` simulation and said so explicitly. The broadcast then landed 114 transactions at nonces 125 to 238 contiguous, so the figure is confirmed rather than merely projected.

| # | Step | Count | Measured from |
| --- | --- | --- | --- |
| 1 | `DeployTestnetStubs` | not run | PB-D70 (i) |
| 2 | `DeployAureumVault` | 4 | record s1, nonces 90-93 |
| 3 | `DeployAureumWeightedPoolFactory` | 1 | record s1, nonce 94 |
| 4 | `DeployAuMM` | 1 | record s1, nonce 95 |
| 5 | `DeployFeeRoutingHook` | 1 | record s1, nonce 96 |
| 6 | `DeployDerBodensee` | 1 | record s1, nonce 97 |
| 7 | `DeployRouter` | 1 | record s1, nonce 98 |
| 8 | Each pool script, per invocation | 1 | record s7, 25 rows at nonces 99-123, plus s10 |
| 9 | `DeployStageP.run()` | 114 | record s11, nonces 125-238 |
| 10 | Router seat | 2 | record s14, nonces 690-691 |
| 11 | `WireTVLOracleSepolia` | 62 | record s12, nonces 239-300 |
| 12 | `SeedMiliariumPoolsSepolia` | 389 | record s13, nonces 301-689 |

**The whole refresh is 602 transactions**, as 9 for the base layer, 26 for the pools now that all of them broadcast from the single deployer, 114 for the orchestration, 2 for the Router seat, 62 for the wiring and 389 for the seeding. At the `n0` of 692 read at PB3.13e that spans nonces 692 to 1293, but treat the span as illustrative and the arithmetic as binding: phase A re-reads `n0` immediately before the first send, and any transaction from this EOA in between shifts every number.

**Phase 5 may run before or after rows 11 and 12, and generation 1 ran it after.** Nothing depends on the order. Pool initialization reaches `onAfterInitialize`, which this hook neither implements nor enables — `AureumFeeRoutingHook` sets `shouldCallAfterAddLiquidity` alone — so seeding never reaches the recorder dispatch that `trustedRouter` gates, and an unseated Router costs nothing during seeding. The seat matters for LP adds and removes after initialization, which is why it must be done before the constellation is opened to anyone.

## 6. Phase 1 and 2 — commands and capture

**Invocation form.** Every command in this section is `forge script <path>:<Contract> --rpc-url sepolia --broadcast --account aumm-sepolia --sender 0xA851478dbee97375E784e9b98c0D7D599662bF85`. The `sepolia` alias is required rather than stylistic, for the reason section 1 gives. `ETHERSCAN_API_KEY` is present per prerequisite 3, unlike at generation 1 where it was absent and verification became a separate phase, so `--verify` may be appended from the first command; if an explicit `--etherscan-api-key` proves necessary, supply its value literally rather than as a shell variable reference, which expands to an empty string exactly as the RPC URL does — the same trap, one flag over. RB-018 applies whenever verification runs: a vault-profile build immediately beforehand rewrites the shared compiler cache and makes the default-profile `Router` unverifiable with an error naming a compiler version rather than a build order.

**Capture and refresh.** Every address this runbook captures is written into `.env.sepolia`, never into `.env` directly, per section 1's write-direction rule. Because forge reads only `.env`, run `cp .env.sepolia .env` after each capture and before the next command — a step whose predecessor captured a key it needs will otherwise read the pre-capture value, aborting on an empty key or sealing a stale address into an immutable. Before step 1, confirm the posture once with `grep -c '^AUMM_ENV_CHAIN=sepolia$' .env`, which must return exactly 1.

**Key posture (PB-D27 (vii)(3)).** The deployer key is imported once into forge's keystore with `cast wallet import aumm-sepolia --interactive` and referenced thereafter as `--account aumm-sepolia`. The key never appears on a command line, in shell history, or in `.env`. Chosen over per-invocation `--interactive` because this sequence runs to roughly three dozen invocations and paste-fatigue across that many prompts is its own failure mode.

**Salts pinned for this deployment.** `SALT` is `0x0000000000000000000000000000000000000000000000000000000000000001`, unchanged from generation 1. `BODENSEE_SALT` is `0xe8adfe84affa1498e12af213d44eb960718a5223d3c3d4c7e1af1dbc1e56c25e`, reproducible by `cast keccak "aureum.derBodensee"` and written into both canonical env files at PB3.13f2. It replaces generation 1's value of 2, which sat inside the 1-to-28 Miliarium slot space and collided with ixAetheron's own slot-derived salt in the factory's CREATE3 namespace, forcing that pool onto a second sender and then a third. The collision reproduces on any fresh factory, since a new namespace moves both pools together rather than apart, and this refresh is the first moment since PB-D39 at which nothing is sealed and the fix is free. PB-D70 (vi) and (xvii). `.env.example` L96 still carries a zero placeholder and is not authoritative.

**Keys absent from `.env.example`.** `EMERGENCY_MULTISIG` (read by `DeployStageK.s.sol` L125), `WETH_ADDRESS` and `GENESIS_BLOCK` are all consumed by this sequence but are not in the committed template. All three already sit in `.env.sepolia` from generation 1 and carry over, with one exception: `GENESIS_BLOCK` is recomputed at step 4 per section 3, because generation 1's 11477620 is abandoned along with the AuMM that sealed it. `WETH_ADDRESS` was pinned by the operator for generation 1's step 7 and that value stands; the fork fixtures still inject the mainnet WETH literal, which has no code on Sepolia, so do not take the address from a test file.

**Aliases the orchestrator bridges, and the ones it does not.** `DeployStageP` sets `VAULT_EXPLORER` and `SVZCHF` from `VAULT` and `SV_ZCHF` inside its own process (L152-L153), so neither is an operator obligation. Every other alias pair below IS: `VAULT` and `AUREUM_VAULT` hold the same address under two keys, and so do `BODENSEE_POOL` and `DER_BODENSEE_POOL`. Setting only one of a pair leaves a later step reading an empty key and aborting mid-sequence.

**This sequence is a refresh, and step 1 is not run.** The 87 stubs at nonces 0 to 86 stay deployed and are reused from the `STUB_` block of `.env.sepolia`, so the sequence begins at step 2. Re-broadcasting step 1 would mint a fresh roster from the live nonce upward, orphan the map every later step reads, and consume the nonces all seven address projections derive from, voiding them. This is not a contingency to weigh but the shape of the whole operation per PB-D70 (i): the stub roster surviving is the only reason this is a refresh rather than a from-zero deployment. Their liveness is not assumed either — all 87 were confirmed to hold code and all 14 vaults to resolve their recorded underlying at PB3.13e, recorded at PB-D70 (xvi).

**Step 1 — testnet stubs. NOT RUN.**

- The 87 stubs of generation 1 are reused. Do not invoke `test-stubs/DeployTestnetStubs.s.sol`, and do not append a fresh map to `.env.sepolia` — the `STUB_` block already there is the live one.
- Confirm rather than assume. All 87 addresses held code and all 14 `StubERC4626` vaults resolved their recorded underlying when read against the chain at PB3.13e, recorded at PB-D70 (xvi). Re-run that check if material time has passed since.
- The full roster with nonces, kinds and mainnet literals is `docs/STAGE_P_BIS_STUB_TOPOLOGY_LEDGER.md`; the committed env-shaped map is `test-stubs/sepolia-stubs.env`, regenerated to live values at PB3.5i15c.
- Nothing is captured here, and `c1` does not enter the phase A arithmetic at all.

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

**Gas budget.** Not a gate this time, and generation 1's own execution replaces the estimate. The deployer holds 5.782928979297694346 SepETH as read at PB3.13e. Generation 1 spent 0.029383870046196392 on the orchestration, 0.00341643207547946 on the oracle wiring, 0.035700732881202711 on the seeding and 0.000102087744842786 on the Router seat — 0.068603122747721349 for everything from phase 4 onward, with the base layer and the 26 pools ahead of it bringing the whole deployment to roughly 0.2 SepETH per PB-D68 (ix). Three consecutive generation-1 broadcasts landed near a third under forge's own figure, so read the printed `Estimated total gas used for script` as a ceiling carrying the `--gas-estimate-multiplier` buffer rather than as a forecast. The 367,079,280-gas fork measurement from `test/fork/StagePRunRehearsal.t.sol` is retained only as a determinism check on the deployment path; live cost is now known from execution and supersedes it for budgeting.

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

**All 26 broadcast from the canonical deployer.** Generation 1 could not: `BODENSEE_SALT` held the value 2, which collided with ixAetheron's slot-derived salt in the factory's CREATE3 namespace, so slot 02 went out from a second EOA and then, after the rate-provider collision at PB-D47, from a third. Both deviations are retired here by the salt move recorded in section 6, so the nonce sequence stays contiguous and every pool address is re-derivable from `0xA851478dbee97375E784e9b98c0D7D599662bF85` alone. Do not reintroduce a second sender: if `DeploymentFailed()` appears at any pool, stop and re-check the salt rather than switching keys.

Every one of the 26 keys must be in `.env` before phase 4. `DeployStageP` drives Stage I, M and N inside its own process and those read the keys directly, so a single missing key aborts the orchestrator partway through a sequence that has already broadcast.

**Phase 4 — the orchestrator.**

- Command: `forge script script/DeployStageP.s.sol:DeployStageP --slow`, otherwise the section 6 invocation form. `--slow` is mandatory here rather than optional: it confirms each transaction before sending the next, which is what leaves a stalled run a clean confirmed-versus-unsent boundary for `--resume` to recover from. Per PB-D49 (iii).
- One invocation, one process, composing Stage F through Stage K per PB-D23 (vii). It threads its own intermediate addresses internally, so nothing between Stage F and Stage K needs capturing: `MILIARIUM_REGISTRY`, `TVL_ORACLE`, `EFFICIENCY_ORACLE`, `EMA_SAMPLER`, `CCB_MULTIPLIER`, `SWAP_AND_DEPOSIT`, `VAULT_CLASS_REGISTRY`, `GAUGE_REGISTRY`, `EMISSION_DISTRIBUTOR` and `BODENSEE_CHANNEL` are all set by the orchestrator on itself as it goes.
- Reads from `.env`: everything phases 1 to 3 wrote, plus `EMERGENCY_MULTISIG`, consumed by `DeployStageK.s.sol` L125 and one of the keys missing from `.env.example`.
- The run asserts its own post-conditions, including the four-way genesis check and the authorizer migration. A revert here stops the sequence with the base layer already live; it does not unwind.
- A stall does not end the sequence, and phase 4 is the only phase with a recovery procedure of its own: `--resume` behind a mandatory nonce-reconciliation gate, in section 9. Do not re-invoke phase 4 from the top after a partial run — that redeploys all sixteen CREATEs at new addresses and orphans everything the stalled run already landed.

**Phase 5 — the Router seat (F-09).**

No script performs this. `DeployStageP.s.sol` L255 records that the orchestrator makes no `setTrustedRouter` call, structurally, per P-D26 (4). The seat is two governor-signed transactions in order: `setGovernanceModule(GOVERNANCE_MULTISIG)`, then `setTrustedRouter(router, true)` using the `ROUTER` address captured at step 7. The first is ONE-SHOT and burns its own admin — it assigns `governanceModule` and zeroes `_governanceAdmin` in the same call, and either flag alone rejects every later attempt, so whatever address is named here holds the hook's gated levers permanently on this deployment with no rotation path anywhere. There are now THREE such levers rather than generation 1's two: `setTrustedRouter` at L328, `routeGovernanceDeposit` at L723 and `recoverStrandedFees` at L816, the last built at PB3.10 and the whole of F-14's custody exit. It must be the governance Safe and must NEVER be `AureumGovernance`, whose `execute()` dispatches over a fixed proposal-type enumeration with no path to any of the three, so seating it there would not delegate those levers but delete them, silently and permanently, on a hook 26 live pools are bound to. RB-017 and PB-D61. Prove the caller before sending: run the exact transaction as an `eth_call` from the deployer, which sends nothing and reverts `NotGovernanceAdmin` if the caller is wrong. `_governanceAdmin` has no getter, so this exercises every guard in the function where a storage-slot read would cover only one.

Load-bearing rather than cosmetic: an unseated Router still mints BPT on an add, but the position is never recorded, so the LP holds a receipt the protocol does not know about — the F-09 fail-closed behaviour the PB3.3 fork witness pinned as a negative case before seating and as a credited add afterwards.

**Phase 6 — verification.**

`ETHERSCAN_API_KEY` is present from the start per prerequisite 3, so `--verify` may ride on each broadcast under per-command §8b approval rather than verification becoming a separate phase as it was at generation 1. Either way the target set is 53 contracts: eleven base-layer, the sixteen the orchestrator deploys, and the twenty-six Miliarium pools. Generation 1 verified 50 and excluded six — nonces 87 to 89, permanently orphaned by the EIP-170 fix, plus `TVLOracle`, `AureumGovernance` and `AureumGovernanceAuthorizer`, whose source had moved under PB-D50, F-21 and F-22 after they were deployed. NEITHER exclusion survives into this deployment. There is no orphaned set, and all three drifted contracts are deployed here from the corrected source whose absence caused the exclusion, which is a substantial part of why this refresh exists at all. Expect zero deliberate exclusions; the only unverifiable artifact is the CREATE3 proxy the nonce-93 CALL leaves behind, which carries no source worth publishing.

**Verify locally before spending a submission.** Two read-only checks answer for free what a failed submission answers slowly and ambiguously. Compare each target's on-chain deployed-code length against its local artifact's `deployedBytecode`, which catches source drift and settles which compiler profile built a contract. Then extract each constructor argument by stripping the artifact's creation code off the init code forge recorded under `broadcast/`, which yields exact arguments and proves byte-exact creation-code identity in the same operation, creation code carrying no immutables and therefore having to be an exact prefix. Both ran clean across all 50 of generation 1's submissions before the first was sent, and both should be run across this deployment's 53 the same way. Do not hand-encode constructor arguments, and do not rely on `--guess-constructor-args`, which contacts the explorer and is unreliable for CREATE3.

**Build order is load-bearing, and getting it wrong produces a misleading error.** `[profile.vault]` overrides `out` but not `cache_path`, so both profiles write `cache/solidity-files-cache.json` and the last build wins for every file they both compile. Running the vault build immediately before verification rewrote every `pkg/vault/contracts` entry to 0.8.30, and `Router`, the only vault-package contract the DEFAULT profile deploys, then failed lookup against a compiler version it was never built with while a correct artifact sat in `out/`. A plain `forge build` restored the entry and the submission passed. Run the default build last before verifying default-profile contracts. Registered as RB-018, and Stage R reproduces it by construction.

**Which profile, and what to submit against.** `Vault`, `VaultAdmin` and `VaultExtension` verify under `FOUNDRY_PROFILE=vault`; every other contract verifies under the default profile, `Router` included despite its source living in the Balancer vault package. der Bodensee and the 26 Miliarium pools are CREATE3 deployments made by the factory rather than by the deployer EOA, so each is submitted against the pool address as `WeightedPool`, not against a deployer transaction. Etherscan matches at the runtime-bytecode layer, so one submission links the rest: all 26 pools returned already-verified off der Bodensee's.

**The nonce-93 CALL deploys four contracts, not one.** `VaultAdmin`, `VaultExtension`, a CREATE3 proxy and the Vault. The first two hold most of the Vault's logic behind delegatecall and appear in no deployer transaction, so their addresses come from `broadcast/CreateAureumVault.s.sol/11155111/run-latest.json` and each is identified by init-code prefix match against a named artifact. Both were absent from the deployment record and from `deployments/11155111.json` until PB3.5i12 and i15b.

**The stub map needs no regeneration.** PB-D21 (v)'s obligation to record the deployed stub set into `test-stubs/sepolia-stubs.env` was discharged at PB3.5i15c with live Sepolia addresses, and none of those addresses moves in this refresh, the 87 stubs being reused rather than redeployed per PB-D70 (i). That committed file stands unchanged, all 67 `STUB_` pairs plus the PB-D47 `STUB_RP_` key and the seven named protocol keys, and so does `docs/STAGE_P_BIS_STUB_TOPOLOGY_LEDGER.md`. What DOES need regenerating once this deployment lands is `deployments/11155111.json`, every protocol entry of which moves; that is PB-D70 (viii) and rung j, and it derives from the deployment record rather than from here.

## 8. The pre-broadcast dry run

Governed by PB-D29 and PB-D30. Phase A runs once, before the first broadcast command of section 6. Phase B runs per step, interleaved with that sequence.

**Why this is two phases and not one dry run.** Two mechanics rule out a single upfront full-sequence run. Simulation sends nothing, so the deployer nonce never advances: every step simulated before any broadcast places its CREATEs at the same live nonce, never at the chained nonce it will occupy, so a chained projection cannot be verified in advance even in principle. And every step past the vault consumes a live predecessor, so it reverts pre-broadcast against an address carrying no code, for a reason unrelated to prediction. Phase A therefore computes the projections analytically; phase B verifies each one against reality at the moment it becomes checkable.

**Simulation form.** Every command in phase A and phase B is a section 6 command with `--broadcast` omitted: `forge script <path>:<Contract> --rpc-url sepolia --sender 0xA851478dbee97375E784e9b98c0D7D599662bF85`. Nothing is sent and no nonce moves.

**Where phase A writes.** Every projection phase A computes is written into `.env.sepolia`, never into `.env` directly, per section 1's write-direction rule. Phase A's simulations read `.env` like any other command, and several of them read a key an earlier step just projected — A6 reads `AUREUM_VAULT` from A3, A8 reads `GENESIS_BLOCK` — so run `cp .env.sepolia .env` after each write and before the next simulation. A projection that never reaches `.env` produces a simulation that fails on an empty key, or worse one that silently runs against the previous value.

**Reading a transaction count.** The count is the number of entries in the `transactions` array of the dry-run artifact forge writes under `broadcast/<ScriptFile>.s.sol/11155111/dry-run/run-latest.json`: `jq '.transactions | length' <that path>`, or any equivalent parse scoped to that top-level array. Confirm the artifact path on the first invocation and use whatever path forge actually reports if it differs on this toolchain. The grep-based fallback that counted occurrences of the per-transaction type field is WITHDRAWN per PB-D38 (iv) and must not be reintroduced: entries inside a transaction's `additionalContracts` array carry that same field, so such a count is inflated by every contract a call deploys internally. Measured at step 2, where `factory.create()` deploys VaultAdmin, VaultExtension, the CREATE3 proxy and the Vault, that form returns 8 against the authoritative 4.

**One mode only: this is a resume.** Generation 1's runbook carried both a greenfield and a resume arithmetic because it did not yet know which branch it would take. This one does. The 87 stubs at nonces 0 to 86 are live and reused per PB-D70 (i), step 1 is not broadcast, and `c1` is therefore not a term in any projection below — it is removed from the arithmetic rather than set to zero, so there is no expression left to mis-evaluate. A2 becomes confirm-and-skip. Section 5 row 1 carries no count at all, and the 87 generation 1 recorded there is history rather than an addend.

### Phase A — before any broadcast

**A1. Record the live nonce.** `cast nonce 0xA851478dbee97375E784e9b98c0D7D599662bF85 --rpc-url sepolia`. Call it `n0`. Every projection below is relative to it, and any transaction sent from the deployer between A1 and the first broadcast invalidates all of them — if that happens, restart phase A.

**A2. Confirm the stubs, then CLEAR the inherited projection keys.** Step 1 is not run, so there is nothing to simulate and no `c1` to record. Two duties replace the count. FIRST, confirm the reused map is real: every address in the `STUB_` block of `.env.sepolia` must have code on chain, and each of the 14 `StubERC4626` vaults must return its recorded underlying from `asset()`. Both were verified at PB3.13e and recorded at PB-D70 (xvi); re-run them if material time has passed. A codeless address here is a hard stop rather than a note, the stub roster surviving being the only thing that makes this a refresh instead of a from-zero deployment. SECOND, delete nine keys from `.env.sepolia` before A3 writes anything, then refresh `.env` from it: `VAULT`, `AUREUM_VAULT`, `FEE_CONTROLLER`, `WEIGHTED_POOL_FACTORY`, `AUREUM_WEIGHTED_POOL_FACTORY`, `DER_BODENSEE_POOL`, `FEE_ROUTING_HOOK`, `AUMM` and `GENESIS_BLOCK`. Every one of them arrives at this rung holding generation 1's live value, so a projection this phase forgets to write is inherited rather than caught: `AUREUM_VAULT`, `FEE_CONTROLLER` and `AUMM` are consumed at steps 3, 5 and 6 with no assertion anywhere, and `GENESIS_BLOCK` would seal the abandoned 11477620 as a fresh emission clock. Deleting rather than blanking is what makes a forgotten write fail closed on `vm.envAddress`, per PB-D36 (vii) and PB-D70 (xviii). `BODENSEE_POOL` and `ROUTER` stay as they are, both being phase 2 captures read off a broadcast log rather than projections phase A could check. `DER_BODENSEE_POOL` and `FEE_ROUTING_HOOK` are then re-populated with A4's non-zero placeholder and replaced by their real derivations at A7 and A9.

**A3. Project the vault step, and write the four keys it owns.** `cast compute-address 0xA851478dbee97375E784e9b98c0D7D599662bF85 --nonce <n0>` is the authorizer; `--nonce <n0 + 1>` is the fee controller; `--nonce <n0 + 2>` is the vault factory. The Vault itself is a CREATE3 from that factory using the RAW `SALT` value — not the sender-hashed form — per the derivation in the closing subsection. Three of those four addresses carry env keys and all four keys are written now, then `.env` refreshed from `.env.sepolia`: `FEE_CONTROLLER` takes the `<n0 + 1>` projection, `AUREUM_VAULT_FACTORY` takes the `<n0 + 2>` projection, and `VAULT` and `AUREUM_VAULT` both take the CREATE3 Vault address. Only the authorizer carries no env key, and it is projected here solely because the fee controller and the vault factory occupy the nonces after it. `AUREUM_VAULT_FACTORY` is not a phase A input and no step of the intended sequence reads it: it is consumed by `script/CreateAureumVault.s.sol` L41, the recovery script generation 1 needed when step 2's fourth transaction was refused at submission after nonces 90 to 92 had landed, and that script fails closed on a stale value by comparing `factory.getDeploymentAddress(salt)` against `AUREUM_VAULT`. Writing it here costs nothing and arms the recovery path before it is needed rather than leaving it to be discovered mid-failure. Naming the `FEE_CONTROLLER` write explicitly is the PB-D70 (xviii) correction: this step identified that projection without ever instructing the write, and A10 requires the key, a gap generation-1 residue concealed for as long as the key arrived already populated. After A2 the key is absent, so a skipped write aborts step 5 on `vm.envAddress` rather than binding generation 1's fee controller. This step's previous form claimed the vault factory carries no env key; that was FALSE and is corrected here per PB-D70 (xix).

**A4. Count step 2, and cross-check A3 while you are there.** Set `DER_BODENSEE_POOL` and `FEE_ROUTING_HOOK` to any non-zero placeholder for this run only. The fee controller zero-checks both (`ZeroBodenseeAddress`, `ZeroHookAddress`) but never calls them, so a placeholder passes and no code is needed at either address. Simulate `DeployAureumVault`. Record the count as `c2` and confirm it against section 5 row 2. Unlike generation 1, the addresses this run reports SHOULD match the A3 projections exactly: with `c1` gone from the arithmetic both are computed from the same live `n0`, and a CREATE address is a pure function of sender and nonce. Generation 1's runbook told the operator to expect a mismatch here and disregard it, which was correct under its arithmetic and is false under this one — a mismatch now means either `n0` moved between A1 and A4 or the A3 projection is wrong, and either is a stop rather than an expected divergence. Take only the count into section 5 and still write none of these addresses into `.env.sepolia`: projections come from `cast compute-address` and never from a simulation's output, so each value keeps one source.

**A5. Project the weighted-pool factory.** `cast compute-address 0xA851478dbee97375E784e9b98c0D7D599662bF85 --nonce <n0 + c2>`. Write it to both `WEIGHTED_POOL_FACTORY` and `AUREUM_WEIGHTED_POOL_FACTORY`, one address under two keys per PB-D27 (ix).

**A6. Count step 3.** With `AUREUM_VAULT` holding the A3 projection, simulate `DeployAureumWeightedPoolFactory`. Record the count as `c3` in section 5 row 3. The projected vault needs no code here: the constructor chain is pure storage — `WeightedPoolFactory` into `BasePoolFactory` stores `_creationCode`, `SingletonAuthentication` stores `_vault`, and nothing in that chain calls the vault.

**A7. Project der Bodensee.** A CREATE3 from the A5 factory, using the SENDER-HASHED salt, per the closing subsection. Write it to `DER_BODENSEE_POOL`, replacing the A4 placeholder.

**A8. Count step 4.** Set `GENESIS_BLOCK` first, per section 6 step 4. Simulate `DeployAuMM`. Record the count as `c4` in section 5 row 4.

**A9. Project the fee-routing hook.** `cast compute-address 0xA851478dbee97375E784e9b98c0D7D599662bF85 --nonce <n0 + c2 + c3 + c4>`. Write it to `FEE_ROUTING_HOOK`, replacing the A4 placeholder. This is the step the PB-D30 reorder exists to make computable: with the hook at step 5 no der-Bodensee count enters this sum, and der Bodensee at step 6 needs no nonce projection at all.

**A10. Close phase A, and confirm every projection has genuinely moved rather than merely arrived.** Section 5 is already complete and phase A does not fill it. Every count there came from generation 1's broadcast, so A4, A6 and A8 re-derive `c2`, `c3` and `c4` as a CROSS-CHECK against rows 2, 3 and 4 rather than as their source. A disagreement between a re-derived count and its recorded row is a stop, not a correction: investigate before broadcasting, because a count wrong by one shifts every projection downstream of it and no later check catches that. The gate below is discriminating rather than a presence check, per PB-D70 (xviii): A2 already cleared the nine generation-scoped keys, so presence alone would only prove that the writes ran, not that they wrote anything new. Before step 2 may run, `.env.sepolia` must hold, with `.env` refreshed from it, seven keys each DIFFERING from its generation-1 value at `docs/STAGE_P_BIS_SEPOLIA_DEPLOYMENT_RECORD.md` section 1: `FEE_CONTROLLER` against the nonce-91 row at L19, `VAULT` and `AUREUM_VAULT` against the nonce-93 Vault at L21, `WEIGHTED_POOL_FACTORY` and `AUREUM_WEIGHTED_POOL_FACTORY` against the nonce-94 factory at L22, `FEE_ROUTING_HOOK` against the nonce-96 hook at L24, and `DER_BODENSEE_POOL` against the nonce-97 pool at L25, checked against that committed table rather than against a transcription of it, per §8e.1's source-diff rule. `GENESIS_BLOCK` carries its own predicate rather than joining the row comparison, since PB-D19 sets it fresh at A8 as a live-head computation rather than as a CREATE projection: it must differ from the literal 11477620 and must exceed the Sepolia head read at A1, so an inherited or already-past value is caught here rather than left to `DeployAuMM`'s unclamped read at step 4. All seven come from the projections above and none from a simulation's reported output.

### Phase B — interleaved with the broadcast

**Before each broadcast step, simulate it.** Run that step's exact section 6 command with `--broadcast` omitted, and confirm the address it reports equals the projection already in `.env`. By this point the step's predecessors are live, so the simulation runs at the true nonce and its reported address is the one the send will produce. Any divergence aborts the sequence — do not broadcast the step and do not edit the projection to match.

**The self-asserts do this for three steps automatically.** `FactoryAddressMismatch`, `HookAddressMismatch` and `BodenseeAddressMismatch` fire identically under simulation and under broadcast, so for steps 2, 5 and 6 a mismatch reverts the simulation rather than requiring a manual compare.

**What phase B cannot undo.** The vault seals `DER_BODENSEE_POOL` and `FEE_ROUTING_HOOK` as immutables at step 2. If either projection is wrong, it is already immutable by the time step 5 or step 6 asserts against it: the assert stops the sequence compounding but cannot unwind the vault, and recovery is a full restart of the whole sequence on fresh addresses. That is the accepted failure mode PB-D27 (iv) records, tolerable on testnet gas, and it is why the A3 through A9 arithmetic is double-checked before step 2 rather than trusted to the asserts.

### The CREATE3 derivation

`CREATE3.getDeployed(salt, creator)` at `lib/balancer-v3-monorepo/pkg/solidity-utils/contracts/solmate/CREATE3.sol` L64-L86 is two steps: a CREATE2 proxy from the creator, then a plain CREATE from that proxy at nonce 1. Both are computable with stock `cast`, in four commands. The proxy init-code hash is `0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f`, reproducible as `cast keccak 0x67363d3d37363d34f03d5260086018f3`; confirm it matches before relying on it.

For der Bodensee the salt is sender-hashed, because `BasePoolFactory._computeFinalSalt` hashes the broadcast sender: `cast keccak $(cast abi-encode "f(address,uint256,bytes32)" 0xA851478dbee97375E784e9b98c0D7D599662bF85 11155111 0xe8adfe84affa1498e12af213d44eb960718a5223d3c3d4c7e1af1dbc1e56c25e)` gives the final salt; then `cast create2 --deployer <the A5 factory> --salt <that final salt> --init-code-hash 0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f` gives the proxy; then `cast compute-address <that proxy> --nonce 1` gives the pool. The salt is written out in full rather than as a shell variable reference, and that is not a style choice: the shell expands such a reference before `cast` is launched and the shell has never read `.env`, so the variable form silently substitutes an empty string and yields a plausible but wrong address. That is PB17. Generation 1's runbook carried the variable form in both derivation commands, because the fix at PB3.8h9f4 was scoped to the RPC flag and never reached them.

For the Vault the salt is RAW — the vault factory's CREATE3 does not hash the sender — so the same three commands run with `--salt 0x0000000000000000000000000000000000000000000000000000000000000001` directly and `--deployer <the A3 vault factory>`, again written out in full rather than as a shell variable reference, for the reason above. Applying the sender-hashed form to the Vault, or the raw form to der Bodensee, produces a wrong address that nothing catches until the corresponding step aborts.

**Residual.** The command chain itself is validated: at PB3.5h2 the three plain CREATEs and the CREATE3 Vault were all reproduced exactly by these commands, checked against forge's own dry-run artifact, with the artifact's `additionalContracts` corroborating the two-step mechanism — recorded in full at `docs/STAGE_P_BIS_PHASE_A_RECORD.md` section 5. What remains is narrower and still real: that validation was performed at nonce 0, and applying it at this refresh's `n0` rests on the section 5 counts being right. A count wrong by one shifts every projection downstream of it, and no check in this section would catch it, since the derivation would still be correct and merely applied to the wrong nonce. The refresh narrows this further than generation 1 could: its counts are measurements from a completed broadcast rather than projections, and A4, A6 and A8 re-derive three of them as a live cross-check per A10. The first on-chain confirmation is still `BodenseeAddressMismatch` at step 6, which is after the vault has sealed its immutables.

## 9. Phase 4 stall recovery — the pre-flight gate and `--resume`

**This section is unchanged from generation 1, deliberately.** Everything in it turns on forge's artifact format, the `--resume` contract and the §8f no-receipts gap, none of which depends on which generation is being deployed: phase 4 is still one invocation of 114 transactions with no idempotency, the pre-flight is still R1 through R6, and the resume invocation is still the one command in this runbook that cannot take the `sepolia` alias. The base-layer episode cited below is generation 1's and stands as history.

**Scope.** This section applies to phase 4 alone. Phases 1 through 3 send one transaction per invocation, so their recovery is to re-read the projection and re-run the single step. Phase 4 is one invocation carrying 114 sequential transactions with no idempotency anywhere in `DeployStageP`, `DeployStageF` or `DeployStageJ` — a stall part way therefore cannot be re-invoked from the top, and a fresh run redeploys all sixteen CREATEs at new addresses while the first set is orphaned on chain. Locked as PB-D49.

**The posture, in one line.** `--slow` on the first send; on any stall, pass the pre-flight gate below and then `--resume`. Never a fresh invocation after a partial run, and never a resume before the gate.

### The rule

`--resume` is FORBIDDEN until the deployer's live confirmed nonce equals the recorded nonce of the first unsent transaction in the broadcast artifact. This is a prohibition and not a recommendation — where the two disagree, the operator reconciles the difference, establishes its cause, and writes the finding into `docs/STAGE_P_BIS_SEPOLIA_DEPLOYMENT_RECORD.md` before resuming anything.

forge states the contract itself in `forge script --help`: `--resume` does not simulate the script again and expects nonces to have remained the same, with the worked example that a transaction carrying nonce 22 requires the account to be at nonce 22 or the resume fails. The failure is loud rather than silent, so this gate exists to be passed deliberately rather than to catch an error that would otherwise slip through.

### Why the artifact can disagree with the chain

CLAUDE.md §8f records the mechanism as structural rather than accidental: a `forge script` that aborts mid-sequence writes its `transactions` array with no `receipts`, so a transaction that DID land carries a hash but no block, no gas and no status — the artifact then under-reports what happened, and a resume computed from it targets a nonce the chain has already consumed.

This is not hypothetical on this chain. Base-layer nonces 90 to 92 were recorded only after a manual chain read, and `script/CreateAureumVault.s.sol` exists as a bespoke recovery because that episode had no procedure to follow — this section is that procedure, written before the second occasion rather than after it.

Field semantics, confirmed at PB3.8h9f against both a dry-run artifact and a live one rather than assumed:

| Artifact state | Meaning |
| --- | --- |
| `.transactions[].hash` is null | never submitted |
| `.transactions[].hash` is non-null | submitted; may or may not have confirmed |
| a `.receipts[]` entry with `status` of `0x1` | forge saw it confirm and succeed |
| a non-null hash with no matching receipt | the §8f gap; this transaction's fate must be read from chain |

`--slow` narrows the window in which that gap opens, by confirming each transaction before sending the next, but it does not close the window — an RPC provider dying, an operator interrupt, a suspended machine, or the process being killed between a successful send and the receipt write all produce the same artifact against a nonce that has already moved.

### The pre-flight, in order

Run every step. Do not skip one because the previous run looked clean, and do not reorder them: R2 and R3 must both be read before R4, because a transaction still sitting in the mempool changes what R5's comparison means.

**R1. Confirm the active environment.** `grep -c '^AUMM_ENV_CHAIN=sepolia$' .env` must return exactly 1, per section 1. A count of 0 is a failure and not a pass.

**R2. Read the confirmed nonce.** `cast nonce 0xA851478dbee97375E784e9b98c0D7D599662bF85 --block latest --rpc-url sepolia`. This is how many transactions the deployer has actually had confirmed, and it is the ground truth the artifact is checked against.

**R3. Read the pending nonce.** `cast nonce 0xA851478dbee97375E784e9b98c0D7D599662bF85 --block pending --rpc-url sepolia`. It must equal R2 — a higher pending nonce means a transaction from this deployer is still in the mempool, and a resume will collide with it. Wait for that transaction to confirm or drop, then re-read both.

**R4. Read the artifact's boundary.** `jq -r '{sent: ([.transactions[]|select(.hash != null)]|length), unsent: ([.transactions[]|select(.hash == null)]|length), receipts: (.receipts|length), next_nonce: ([.transactions[]|select(.hash == null)][0].transaction.nonce)}' broadcast/DeployStageP.s.sol/11155111/run-latest.json`. Note the path carries no `dry-run` component: the dry-run artifact holds 114 null hashes and is not what a resume reads.

**R5. Compare.** `next_nonce` is hex and R2's reading is decimal; convert with `cast to-dec <next_nonce>` and require exact equality. Equality means every transaction the artifact shows as submitted did land, and the chain sits exactly where the resume will start — the gate is passed and R6 is skipped. Any inequality sends you to R6, and `sent` exceeding `receipts` in R4's output names the transactions to investigate first.

**R6. Reconcile before anything else.** For every transaction whose hash is non-null, read its fate from chain with `cast receipt <hash> --rpc-url sepolia`, and record each one that landed into `docs/STAGE_P_BIS_SEPOLIA_DEPLOYMENT_RECORD.md` per §8f — nonce, contract, address, block, gas used and status. Two outcomes are possible and they point opposite ways: a hash returning a receipt landed and consumed its nonce, so the artifact under-reported; a hash returning nothing was dropped from the mempool and never consumed its nonce, so the artifact over-reported and the chain sits behind the boundary. Only once every submitted hash resolves into one of those two may the boundary be judged, and resuming before that is complete is the prohibited action this section exists to prevent.

### The resume invocation

`forge script script/DeployStageP.s.sol:DeployStageP --rpc-url "$(grep '^SEPOLIA_RPC_URL=' .env | cut -d= -f2-)" --broadcast --resume --slow --account aumm-sepolia --sender 0xA851478dbee97375E784e9b98c0D7D599662bF85`

`--resume` accompanies `--broadcast` rather than replacing it — the foundry scripting guide's own resume example is `forge script script/Deploy.s.sol --broadcast --rpc-url $RPC_URL --resume`, checked 2026-08-02. Two details beyond that are load-bearing. `--slow` stays on for the same reason it was on the first send, so that a resume which itself stalls still leaves a clean boundary for the next one. And this is the one command in the runbook that does NOT take the `sepolia` alias: foundry issue 4346 reports that `--resume` stops resolving RPC aliases and demands a literal URL, so the invocation above lifts the value straight out of `.env` by command substitution, which needs neither an export nor a `set -a` and therefore leaves the section 1 posture intact. The trailing dash in `-f2-` is load-bearing in its own right, since an API key embedded in the URL may itself contain an equals sign.

### What not to do

- Do not re-invoke phase 4 without `--resume` after a partial run. A fresh invocation starts from the live nonce, redeploys all sixteen CREATEs at new addresses, and leaves everything the stalled run landed orphaned on chain while the second run's wiring binds the second set — the exact failure that produced `script/CreateAureumVault.s.sol`.
- Do not delete, truncate or hand-edit `broadcast/DeployStageP.s.sol/11155111/run-latest.json` to make a resume begin where you would like it to. `broadcast/` is gitignored, so that file is the only local record of what was sent, and editing it destroys the evidence R4 through R6 depend on.
- Do not send anything else from the deployer EOA between the first send and the last confirmation, or between a stall and its resume. A faucet top-up, a probe transaction or a wallet-initiated approval all move the nonce and void the resume. Per PB-D49 (vii), and the same discipline phase A carries at A1, extended from a four-transaction window to a 114-transaction one.
