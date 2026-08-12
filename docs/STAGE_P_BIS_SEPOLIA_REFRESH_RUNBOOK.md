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
