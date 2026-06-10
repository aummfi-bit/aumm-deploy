# Stage K — Plan & Sub-Step Roadmap

> **Status:** K7 design LOCKED (K-D9) on `stage-k` — K0—K6 done + K7 pre-flight closed (`AureumGovernanceAuthorizer` K1, TVL-oracle binding K2 doc-only, `VotingWeight` K3, `AureumGovernance` K4, `AuMMMinterRouter` minter handoff K5, `TVLOracle` roster re-wire K6; full unit + fork coverage green). K-D9 LOCKED — deploy + authorizer migration = two scripts (`DeployAuMM` H-D42 + `DeployStageK`) + a load-bearing wiring chain, handoff set = gauge + registry only (K-D4 reconciled). K7.0a NOTES lock `9502025`; this commit lands K7.0b (PLAN K-D9 mirror flip + K7 sub-step ladder + Completion Log catch-up + Status/Last-update banner refresh). Next: K7.1 `script/DeployAuMM.s.sol`. **K-D1—K-D9 LOCKED.** Companion to STAGE_K_NOTES.md.
>
> **Last update:** 2026-06-10 — K7.0b PLAN (this commit): K-D9 mirror flip forward-declared → LOCKED + K7 sub-step ladder (K7.0a—K7.3 + K-close) + Completion Log catch-up (K6-log `f5b85ee` back-fill / K6-§11 `ea23b6f` / K7.0a `9502025` rows) + Decisions preamble update + Status/Last-update banner refresh to K7. Handoff set = gauge + registry only (user decision 2026-06-10; K-D4 reconciled). Next: K7.1 `script/DeployAuMM.s.sol` (H-D42 micro-script).
>
> **Mode:** Opus extra-high entry per §13 stage-level defaults — governance handoff; stay on Opus through the stage. Each unit K1—K7 opens with an Opus pre-flight that locks its K-D and details its sub-steps.
>
> **Audience:** Sagix plus any future Claude session needing the operational roadmap for Stage K sub-step execution. STAGE_K_NOTES.md is the running design-decision log; this file is the sub-step sequence + Completion Log + grep-verifiable checkpoint catalog.

---

## Stage scope

Stage K ships the on-chain governance stack (`AureumGovernance`) plus the value-weighted voting reader (`VotingWeight`) plus the B-strict 12-month time-bomb authorizer (`AureumGovernanceAuthorizer`), and migrates the Vault's authorizer from the Stage B Safe to the governance contract; scope is the tight handoff per K-D1 (D33 Router → Stage O, OQ-20 / OQ-21 deferred). The load-bearing constraint is that the deep designs (F-12 deposit, F-9 dampening, snapshot, the `VotingWeight` value-curve) lock at each unit's own Opus pre-flight per K-D2, not at entry. Vault bytecode stays byte-identical — the migration is `setAuthorizer` / `setStaticSwapFeePercentage` CALLS, never edits.

### Surfaces produced at Stage K

| File | Status | Sub-step | LOC estimate |
| --- | --- | --- | --- |
| `src/governance/AureumGovernanceAuthorizer.sol` | NEW | K1 | ~80 |
| `test/unit/AureumGovernanceAuthorizer.t.sol` | NEW | K1 | ~150 |
| `src/governance/VotingWeight.sol` | NEW | K3 | ~180 |
| `test/unit/VotingWeight.t.sol` | NEW | K3 | ~250 |
| `src/emission/IEmissionDistributor.sol` | EDIT (fix-forward) | K3 | +1 getter |
| `src/emission/EmissionDistributor.sol` | EDIT (fix-forward) | K3 | +override |
| `src/governance/AureumGovernance.sol` | NEW | K4 | ~500 |
| `test/unit/AureumGovernance.t.sol` | NEW | K4 | ~600 |
| `test/fork/StageKIntegration.t.sol` | NEW | K4 / K7 | ~300 |
| `src/token/IAuMMMinterRouter.sol` | NEW | K5 | ~20 |
| `src/token/AuMMMinterRouter.sol` | NEW | K5 | ~40 |
| `test/unit/AuMMMinterRouter.t.sol` | NEW | K5 | ~200 |
| `src/emission/BodenseeBootstrapChannel.sol` | EDIT (fix-forward) | K5 | +setter +mint swap |
| `src/emission/EmissionDistributor.sol` | EDIT (fix-forward) | K5 | +setter +mint swap |
| `test/unit/BodenseeBootstrapChannel.t.sol` | EDIT (K13 retrofit) | K5 | +router setUp +setMintRouter cohort |
| `test/unit/EmissionDistributor.t.sol` | EDIT (K13 retrofit) | K5 | +router setUp +setMintRouter cohort |
| `src/emission/TVLOracle.sol` | EDIT (fix-forward) | K6.1 / K6.2 | +setMiliariumRegistry +Leg2 enum +dedup |
| `test/unit/TVLOracle.t.sol` | EDIT (K6 cohort) | K6.3 | +setMiliariumRegistry cohort +Leg2 enum +dedup tests |
| `script/DeployAuMM.s.sol` | NEW | K7 | ~30 |
| `script/DeployStageK.s.sol` | NEW | K7 | ~120 |
| `test/fork/DeployStageK.t.sol` | NEW | K7 | ~150 |

### Surfaces NOT produced at Stage K

- No D33 Aureum Router (deferred to Stage O per K-D1).
- No OQ-20 / OQ-21 yield-fee entry point (stays deferred).
- No Vault edits — byte-identical preserved; migration is `setAuthorizer` + `setStaticSwapFeePercentage` calls only.
- No AuMM contract edit — AuMM stays byte-untouched (K-D1 clause holds); the C-D11 one-shot minter slot is consumed by `AuMMMinterRouter` (K5) at the K7 `aumm.setMinter(router)` call per K-D7 / K-D9.
- No interface change to `IGaugeRegistry` / `IMiliariumSlotRegistry` — consumed as-is.

---

## Decisions

Mirror of STAGE_K_NOTES.md Decisions table (K-D1 + K-D2 LOCKED at K0.2; K-D3 LOCKED at K1 pre-flight; K-D4 LOCKED at K2 pre-flight; K-D5 LOCKED at K3 pre-flight; K-D6 LOCKED at K4 pre-flight; K-D7 LOCKED at K5 pre-flight; K-D8 LOCKED at K6 pre-flight; K-D9 LOCKED at K7 pre-flight).

| # | Status | Decision | Anchor | Locked at |
| --- | --- | --- | --- | --- |
| K-D1 | LOCKED | Stage K scope = tight governance handoff, seven dependency-ordered units K1—K7. D33 Aureum Router DEFERRED to Stage O; OQ-20 / OQ-21 controller yield-fee leg stays DEFERRED (user scope decision 2026-06-07). New contracts: `AureumGovernanceAuthorizer` (K1), `VotingWeight` (K3), `AureumGovernance` (K4). New scripts: `script/DeployAuMM.s.sol` (H-D42), `script/DeployStageK.s.sol` (K7). Fix-forward edit to tagged contract: `TVLOracle` roster re-wire (K6, J-D8, I13-class). `AuMM.setMinter` is a deploy-script call (K5, H-D41) — no AuMM contract edit. | STAGES_OVERVIEW Stage K; OQ-10; user scope decision 2026-06-07; H-D41 / H-D42 / J-D8 carry-forward | K0.2 |
| K-D2 | LOCKED | Dependency-ordered build sequence: K1 `AureumGovernanceAuthorizer` → K2 TVL-oracle binding → K3 `VotingWeight` → K4 `AureumGovernance` → K5 `setMinter` handoff → K6 `TVLOracle` re-wire → K7 deploy + migration. Each unit's deep design locks at its own Opus pre-flight as a new K-D entry (K-D3 onward), NOT at K0.2 — F-12 deposit math, F-9 dampening, the snapshot mechanism, and the `VotingWeight` value-curve each need a focused beat reading the canonical formulas. The §12 ambiguity-gate fires fresh at each unit pre-flight. | Stage K size vs Stage J; J-D8 precedent; §12 ambiguity-gate; §13 per-unit Opus pre-flight | K0.2 |
| K-D3 | LOCKED | `AureumGovernanceAuthorizer` per OQ-10 — `is IAuthorizer`, no new Aureum interface (external surface is `canPerform` + public-immutable getters). Constructor `(governanceContract_, emergencyMultisig_, vault_)` all zero-checked; immutables `GOVERNANCE_CONTRACT` / `EMERGENCY_MULTISIG` / `EMERGENCY_WINDOW_END_BLOCK` + two `bytes32` emergency action IDs; constant `EMERGENCY_WINDOW_BLOCKS = 2_628_000`. `EMERGENCY_WINDOW_END_BLOCK = block.number + EMERGENCY_WINDOW_BLOCKS` (from construction block). Emergency set = {`pauseVault`, `enableRecoveryMode`} (user 2026-06-07; `disableQuery` dropped — permanent defensive-config, not crisis-response). Action IDs computed locally H13-safe; disambiguator = Vault address (verified `Authentication.sol:51` + `VaultAdmin.sol:77`). `canPerform`: governance → true; multisig ∧ emergency ∧ `block.number < END_BLOCK` → true; else false. | OQ-10 (FINDINGS L722-794); `Authentication.sol:51` / `VaultAdmin.sol:77` encoding; `IVaultAdmin` selectors; Stage B `AureumAuthorizer.sol`; user decision 2026-06-07 | K1 |
| K-D4 | LOCKED | TVL-oracle binding for vote-weighting = **reuse-direct**. `ITVLOracle` already exposes `tvl(address pool) → uint256` (svZCHF, 18-dec; `ITVLOracle.sol` L14, implemented at `TVLOracle.sol` L211) — exactly the whole-pool valuation K3 `VotingWeight` multiplies by BPT share (`holderValue = tvl(pool) × balanceOf(holder) / totalSupply()`; BPT reads direct off the pool per I-D14). No adapter, no new K2 contract, no `IVotingWeight` change — `VotingWeight` takes an `ITVLOracle` immutable and calls `tvl(pool)`; injection lands at K3. Single shared `TVLOracle` instance (emission `EfficiencyOracle` + governance; one roster, one `setGovernanceContract` handoff); deploy ordering at K-D9. K6 `_constellationRatio` re-wire is signature-stable (does not touch `tvl` ABI). | OQ-22 (FINDINGS L1106); `src/ccb/ITVLOracle.sol` L14; `src/emission/TVLOracle.sol` L211; I-D14 (AuMT=BPT); K-D9 | K2 |
| K-D5 | LOCKED | `VotingWeight is IVotingWeight` (I9.1 stub) = **stateful poke-accumulator** delivering an exact veto fraction (`vetoSupport ≤ totalSupply` by construction). Per-position F-9 power `(value × cappedTime/ON_RAMP)^(1/4 Era 0 → 1/3 Era 1+)` via `FixedPoint.powDown`, era flip at `AureumTime.firstHalvingBlock(GENESIS_BLOCK)`; value = recorder share `ORACLE.tvl(pool) × userLP / poolTotalLP` (OQ-25 anti-flash-loan, **supersedes the K-D4 `balanceOf` shorthand**); clock = `RECORDER.effectiveQualBlock` (14-day cliff `QUALIFICATION_PERIOD_BLOCKS`, 6-month cap `ON_RAMP_PERIOD_BLOCKS`); gauge-gated read-time. Two slots `_holderWeight[h]` + `_totalQualifiedWeight`; `governanceWeight`/`totalSupply` are `view` over checkpoints; permissionless `poke(holder)` recomputes the holder aggregate over the gauge-filtered `MiliariumRegistry` enumeration (≤28) and applies the signed delta (F12/F13). Five immutables `ORACLE`/`GAUGE_REGISTRY`/`RECORDER`/`REGISTRY`/`GENESIS_BLOCK`. K3.0c exposes `IEmissionDistributor.effectiveQualBlock` (I13-class). I-D17 denominator = total checkpointed qualified weight. | I-D15; I-D17; OQ-25 (FINDINGS L1302-1318); F-9 (`11_formulas.md`); `04_tokenomics.md` §viii; user decision 2026-06-08; `src/governance/IVotingWeight.sol`; `IMiliariumRegistry`; `AureumTime` cliff/on-ramp/`firstHalvingBlock` | K3 |
| K-D6 | LOCKED | `AureumGovernance` — three proposal types (gauge challenge / composition challenge / fee change), 20% quorum (`QUORUM_BPS = 2_000`), simple-majority gauge+fee / 2/3-supermajority composition, snapshot voting (poke-at-vote weight from K3 `VotingWeight` + frozen `totalSupply` denominator), `VOTING_PERIOD_BLOCKS = 100_800`, `EXECUTION_TIMELOCK_BLOCKS = 14_400`, `EXECUTION_GRACE_BLOCKS = 100_800`. Deposits flat `1_000e18` svZCHF / `1_250e18` sUSDS via `SwapAndDepositToBodensee.donate` (non-refundable); gauge-challenge F-12 deposit deferred to Stage O. Execution: gauge → `revokeGauge`, composition → `replaceSlot` + atomic gauge swap, fee → `setStaticSwapFeePercentage` (band 0.01—0.30%, Bodensee excluded, epoch cooldown). Sub-splits K-D6a—K-D6f in STAGE_K_NOTES.md. F-9 dampening consumed from K3 `VotingWeight`, not reimplemented. | STAGES_OVERVIEW Stage K L245-252; OQ-7 / OQ-8 / OQ-9 / OQ-10 / OQ-11 / OQ-13; F-9 / F-12; user decisions 2026-06-08 | K4 |
| K-D7 | LOCKED | H-D41 minter handoff = **Option B** — new dumb allowlist forwarder `AuMMMinterRouter` (`src/token/`) holds AuMM's C-D11 one-shot minter slot. Three zero-checked immutables `AUMM` / `BOOTSTRAP_CHANNEL` / `EMISSION_DISTRIBUTOR`; single external `mintFor(address recipient, uint256 amount)` — non-allowlisted caller reverts `NotAllowlisted(msg.sender)`, else forwards `AUMM.mint(recipient, amount)`; no amount policy, no cap math (21M cap stays in AuMM), no governance surface, no setters. Both consumers gain a one-shot `onlyGovernance` `setMintRouter` (I-D9 / H-D5 precedent — constructor signatures unchanged, zero construction-site retrofit) and swap mint sites to `mintRouter.mintFor(...)` — I13-class fix-forward on the two tagged Stage H contracts; AuMM untouched (K-D1 clause holds). Amends the K-D1 roster: +1 new contract (K5), +2 fix-forward edits. `aumm.setMinter(router)` executes at K7 per K-D9. | H-D41 / H-D2 / H-D7 / C-D11; I-D9 / H-D5 one-shot precedent; D36; user decision 2026-06-10 | K5 |
| K-D8 | LOCKED | `TVLOracle` H-D8 roster re-wire = **live second enumeration leg** in `_constellationRatio` over the `MiliariumRegistry` dense view (`miliariumPoolsCount` / `miliariumPoolAt`), guarded by `if (address(miliariumRegistry) != address(0))` so an unbound registry = exact pre-K6 behavior. Binding = **F-D20 one-shot self-seal `setMiliariumRegistry`** mirroring `CCBMultiplier` (mutable `miliariumRegistry` slot + deployer-pinned `registrySetter` self-zeroing on first write); constructor SIGNATURE unchanged (body gains `registrySetter = msg.sender`) → zero ctor-site blast radius. Dedup = the existing reverse-map leg skips venues where `miliariumRegistry.isMiliarium(v)`. `tvl()` / `ITVLOracle` ABI unchanged (K-D4 / K-D5 bindings survive). I13-class fix-forward on tagged `stage-h-complete` `TVLOracle`; edits land on `stage-k`. | J-D8 (STAGE_J_NOTES.md); H-D8 roster; `CCBMultiplier` F-D20 / F-D23 one-shot precedent; `_constellationRatio` reverse-map (`TVLOracle.sol` L178); I13 blast-radius; user decisions 2026-06-10 | K6 |
| K-D9 | LOCKED | Deploy + authorizer migration = **two scripts + a load-bearing wiring chain**. `script/DeployAuMM.s.sol` (H-D42 micro-script: `new AuMM(genesisBlock, governanceMultisig)` + address emit) is the production-chain prerequisite before `DeployStageH`. `script/DeployStageK.s.sol` deploys the stack in ctor order (`VotingWeight` → `AureumGovernance` → `AureumGovernanceAuthorizer` → `AuMMMinterRouter`; genesis from `aumm.GENESIS_BLOCK()`), then wires (1) `vaultClassRegistry.setVotingWeight`; (2) `channel` + `distributor` `setMintRouter` (governance slot still = deployer); (3) `gaugeRegistry` + `miliariumRegistry` `setGovernanceContract(gov)` — **handoff set = gauge + registry ONLY**; (4) `aumm.setMinter(router)` C-D11 one-shot; (5) multisig `vault.setAuthorizer(authorizer)` OQ-10 migration. Emission-layer + `VaultClassRegistry` governance slots stay at the multisig (deferred to L/M/N/O) — `AureumGovernance.execute()` is a typed 3-way dispatch with no generic-call hatch, so rebinding them would strand `setAuMTContractForPool` / `addConstellationPool` / `setIncendiaryRegistry` / `proposeVaultClass`. Refines K-D4 (single-instance intent holds; rebind timing deferred). `DeployStageK.t.sol` inherits the Stage-I/J fork fixture (H13: all 4 ctors zero-check-only, but wiring needs real targets). | OQ-10 (FINDINGS L788-792); H-D42; K-D4 reconciliation; K-D7 L159; J-D5 / G-D16d; `AureumGovernance.sol` L320-348 execute paths; H13 ctor-audit; user decision 2026-06-10 | K7 |

---

## Pre-flight checklist

- [x] `main` at `stage-j-complete` (commit `83ef71e`); `origin/main` synced.
- [x] `stage-k` branched from `stage-j-complete` per the C0 / D0 / E-D8 / F9 / G9 / H12 convention — K0.1.
- [x] STAGE_K_NOTES.md design freeze (K-D1 + K-D2 LOCKED) landed at K0.2 (`e241c22`).
- [x] Scope confirmed tight (D33 → Stage O, OQ-20 / OQ-21 deferred) — user decision 2026-06-07.
- [x] No upstream tracking for `stage-k` yet — snapshot push deferred to K-close.
- [ ] (resolves at K1) `AureumGovernanceAuthorizer` unit green.
- [ ] (resolves at K3) `VotingWeight` unit green.
- [ ] (resolves at K4) `AureumGovernance` unit + `StageKIntegration` fork green.
- [ ] (resolves at K7) `DeployStageK` fork green + authorizer migration verified.
- [ ] (resolves at K-close) full split-form regression green + `stage-k` ff-merge → `main` + `stage-k-complete` tag + push.

---

## Sub-step roadmap

### K0 — Stage entry (4 sub-steps)

- **K0.1** (DONE — branch op) `stage-k` branched from `stage-j-complete` (`83ef71e`); user ran in terminal.
- **K0.2** (DONE — `e241c22`) `docs/STAGE_K_NOTES.md` design freeze (K-D1 + K-D2 LOCKED, K-D3—K-D9 forward-declared); Cursor §8e.1.
- **K0.3** (THIS COMMIT) `docs/STAGE_K_PLAN.md` roadmap; Cursor §8e.1.
- **K0.4** `CLAUDE.md` §11 — Stage J→K terminal refresh: confirm Stage J COMPLETE/tagged, set `stage-k` resume anchor (K0 done, K1 next), Stage K entry mode (Opus extra-high); Cursor §8e.1.

### K1 — AureumGovernanceAuthorizer (per K-D3 LOCKED)

The B-strict 12-month time-bomb authorizer per OQ-10; surfaces `src/governance/AureumGovernanceAuthorizer.sol` (~80 LOC) + `test/unit/AureumGovernanceAuthorizer.t.sol` (~150 LOC); depends on Balancer `IAuthorizer` + `IVaultAdmin` (selectors) and the Stage B `AureumAuthorizer` migration-target framing. K-D3 locked the full design at the K1 pre-flight Opus beat (NOTES body landed K1.0a, `130c39d`).

- **K1.0a** (DONE — `130c39d`) `docs/STAGE_K_NOTES.md` — K-D3 `AureumGovernanceAuthorizer` design LOCKED (emergency set {`pauseVault`, `enableRecoveryMode`}, H13-safe local action-ID encoding, full design body); Cursor §8e.1.
- **K1.0b** (THIS COMMIT) `docs/STAGE_K_PLAN.md` — K-D3 mirror flip to LOCKED + K1 sub-step detail + Completion Log catch-up; Cursor §8e.1.
- **K1.1** `src/governance/AureumGovernanceAuthorizer.sol` — the concrete contract per K-D3: `is IAuthorizer`, constructor `(governanceContract_, emergencyMultisig_, vault_)` (all zero-checked), three address immutables (`GOVERNANCE_CONTRACT` / `EMERGENCY_MULTISIG` / `EMERGENCY_WINDOW_END_BLOCK`) + two `bytes32` emergency action IDs + `EMERGENCY_WINDOW_BLOCKS = 2_628_000`, locally-computed H13-safe action IDs, `canPerform` routing; Cursor §8e.1.
- **K1.2** `test/unit/AureumGovernanceAuthorizer.t.sol` — unit cohort (8 cases): governance all-access; emergency × in-window; emergency × post-window; non-emergency × in-window; random account; action-ID encoding matches `getActionId`; window boundary at `== EMERGENCY_WINDOW_END_BLOCK`; three zero-address constructor reverts; Cursor §8e.1.

### K2 — TVL-oracle binding for vote-weighting (per K-D4 LOCKED; documentation-only — no code surface)

K-D4 resolved reuse-direct at the K2 pre-flight: `ITVLOracle` already exposes `tvl(address pool) → uint256` (svZCHF, 18-dec), exactly the whole-pool valuation K3 `VotingWeight` multiplies by BPT share (`holderValue = tvl(pool) × balanceOf(holder) / totalSupply()`, BPT direct off the pool per I-D14). So `VotingWeight` takes an `ITVLOracle` immutable and calls `tvl(pool)` — no adapter, no new K2 contract, single shared `TVLOracle` instance; the oracle injection folds into the K3 constructor. K2 produces no Surfaces row. (NOTES body landed K2.0a, `3e8250d`.)

- **K2.0a** (DONE — `3e8250d`) `docs/STAGE_K_NOTES.md` — K-D4 TVL-oracle binding LOCKED reuse-direct (`ITVLOracle.tvl(pool)`, single shared instance, K6 re-wire signature-stable, full design body); Cursor §8e.1.
- **K2.0b** (THIS COMMIT) `docs/STAGE_K_PLAN.md` — K-D4 mirror flip to LOCKED + K2 documentation-only framing + Completion Log catch-up; Cursor §8e.1.

### K3 — VotingWeight (per K-D5 LOCKED)

The value-weighted governance reader implementing `IVotingWeight` (I9.1 stub) = a **stateful poke-accumulator** delivering an exact veto fraction (`vetoSupport ≤ totalSupply` by construction); surfaces `src/governance/VotingWeight.sol` (~180 LOC) + `test/unit/VotingWeight.t.sol` (~250 LOC) + the K3.0c `IEmissionDistributor` / `EmissionDistributor` fix-forward (expose `effectiveQualBlock`). K-D5 locked the full design at the K3 pre-flight Opus beat (NOTES body landed K3.0a, `d66688b`): per-position F-9 power `(value × cappedTime/ON_RAMP)^(1/4 Era 0 → 1/3 Era 1+)` via `FixedPoint.powDown`, era flip at `AureumTime.firstHalvingBlock(GENESIS_BLOCK)`; value = recorder share `ORACLE.tvl(pool) × userLP / poolTotalLP` (OQ-25 anti-flash-loan, supersedes the K-D4 `balanceOf` shorthand); clock = `RECORDER.effectiveQualBlock` (14-day cliff, 6-month on-ramp cap); gauge-gated read-time over the `MiliariumRegistry` dense enumeration (≤28); permissionless `poke(holder)` applies the F12/F13 signed delta to `_holderWeight` + `_totalQualifiedWeight`. Depends on the K2 `ITVLOracle` immutable, the `IEmissionDistributor` recorder clock (`effectiveQualBlock` / `userLP` / `poolTotalLP`), `IGaugeRegistry` (gauged-only gate), `IMiliariumRegistry` (pool enumeration), and `AureumTime` (cliff / on-ramp / `firstHalvingBlock`).

- **K3.0a** (DONE — `d66688b`) `docs/STAGE_K_NOTES.md` — K-D5 `VotingWeight` LOCKED (stateful poke-accumulator, recorder-share value per OQ-25, exact veto fraction, full design body); Cursor §8e.1.
- **K3.0b** (THIS COMMIT) `docs/STAGE_K_PLAN.md` — K-D5 mirror flip to LOCKED + K3 sub-step ladder + Surfaces table K3.0c rows + Completion Log catch-up; Cursor §8e.1.
- **K3.0c** `src/emission/IEmissionDistributor.sol` + `src/emission/EmissionDistributor.sol` — expose `effectiveQualBlock(address pool, address user) → uint256` on the interface + `override` on the concrete public mapping (I13-class fix-forward; no behavioural change); Cursor §8e.1.
- **K3.1** `src/governance/VotingWeight.sol` — the concrete reader per K-D5: `is IVotingWeight`, five zero-checked immutables (`ORACLE` / `GAUGE_REGISTRY` / `RECORDER` / `REGISTRY` / `GENESIS_BLOCK`), two slots (`_holderWeight` / `_totalQualifiedWeight`), `view` `governanceWeight` + `totalSupply`, permissionless `poke(holder)` with internal `_positionPower` (gauge gate, 14-day cliff, on-ramp cap, recorder-share value, F-9 `powDown` root, era flip), F12/F13 signed-delta application, div-by-zero guards; Cursor §8e.1.
- **K3.2** `test/unit/VotingWeight.t.sol` — unit cohort: 14-day cliff zero; on-ramp cap; era-root flip at `firstHalvingBlock`; gauge-gate zero; withdrawal → `poke` → zero; recorder-share value; multi-pool aggregation; multi-holder `vetoSupport ≤ totalSupply` invariant under mixed poke states (matching `VaultClassRegistry.sol:277-279`); signed-delta on weight drop; div-by-zero guards; Cursor §8e.1.
- **K3.3** (FOLDED → K4) fork test folded into K4 `test/fork/StageKIntegration.t.sol` (resolved at K3 close 2026-06-08 per user decision — the recorder clock `effectiveQualBlock` needs real hook-recorded deposits, whose fork harness is the K4 integration test; a standalone K3 fork test would duplicate it). **K3 complete.**

### K4 — AureumGovernance (per K-D6 LOCKED; the largest unit)

The three proposal types (gauge challenge / composition challenge / fee change) + snapshot voting + timelock; surfaces `src/governance/AureumGovernance.sol` (~500 LOC, standalone — no `IAureumGovernance` interface; the registries gate on a `governanceContract` address, not a typed interface) + `test/unit/AureumGovernance.t.sol` (~600 LOC) + `test/fork/StageKIntegration.t.sol` (~300 LOC, absorbs the folded K3.3 `VotingWeight` fork coverage). K-D6 locked the full design at the K4 pre-flight Opus extra-high beat (NOTES body landed K4.0a, `4e3b5e6`): `ProposalType {GaugeChallenge, CompositionChallenge, FeeChange}`; voter weight poked-fresh from K3 `VotingWeight.governanceWeight` (F-9 dampening consumed, not reimplemented); `snapshotTotalSupply` frozen at `propose` as the 20% quorum denominator; simple-majority gauge+fee / 2/3-supermajority composition; flat `1_000e18` svZCHF / `1_250e18` sUSDS deposit via `SwapAndDepositToBodensee.donate` (non-refundable; gauge-challenge F-12 deposit deferred to Stage O); `VOTING_PERIOD_BLOCKS = 100_800`, `EXECUTION_TIMELOCK_BLOCKS = 14_400`, `EXECUTION_GRACE_BLOCKS = 100_800`; execution routing gauge → `revokeGauge`, composition → `replaceSlot` + gauge swap (atomic), fee → `setStaticSwapFeePercentage` (band-validated 0.01—0.30%, Bodensee excluded, epoch cooldown). Depends on K3 `VotingWeight` (`poke` / `governanceWeight` / `totalSupply`), `IGaugeRegistry` (`revokeGauge` / `registerGaugeFromComposition` / `gaugeStatus` / `isGaugeApproved`), `IMiliariumSlotRegistry` (`replaceSlot` / `poolAtSlot` / `slotOf`), Balancer `IVault` (`setStaticSwapFeePercentage`, authorizer-gated via K-D3), and `SwapAndDepositToBodensee.donate` (G-D21 authorized-donator, wired at K7).

- **K4.0a** (DONE — `4e3b5e6`) `docs/STAGE_K_NOTES.md` — K-D6 `AureumGovernance` design LOCKED (three proposal types + sub-splits K-D6a—K-D6f: base machinery / weight sourcing / snapshot & tally / per-type deposit / execution routing / timelock); Cursor §8e.1.
- **K4.0b** (THIS COMMIT) `docs/STAGE_K_PLAN.md` — K-D6 mirror flip to LOCKED + K4 sub-step ladder (K4.0a—K4.7) + Completion Log catch-up (K3.4 / K4.0a / K4.0b); Cursor §8e.1.
- **K4.1** `src/governance/AureumGovernance.sol` — scaffold per K-D6a: imports, eight zero-checked immutables (`VOTING_WEIGHT` / `GAUGE_REGISTRY` / `SLOT_REGISTRY` / `VAULT` / `BODENSEE_CHANNEL` / `SVZCHF` / `SUSDS` / `BODENSEE_POOL`) + constructor, nine constants (`VOTING_PERIOD_BLOCKS` / `EXECUTION_TIMELOCK_BLOCKS` / `EXECUTION_GRACE_BLOCKS` / `QUORUM_BPS` / `PROPOSAL_DEPOSIT_SVZCHF` / `PROPOSAL_DEPOSIT_SUSDS` / `SWAP_FEE_MIN` / `SWAP_FEE_MAX` / `FEE_CHANGE_COOLDOWN_BLOCKS`), `ProposalType` + `ProposalState` enums, `Proposal` struct, storage (`proposalCount` / `_proposals` / `hasVoted` / `lastFeeChangeBlock`), events, errors — no function bodies yet; the §12 storage-packing + constant-sourcing gate (local literal vs `AureumTime`) fires here; Cursor §8e.1.
- **K4.2** `src/governance/AureumGovernance.sol` — `propose` family: three per-type entrypoints, per-type propose-time validation, `snapshotTotalSupply` freeze, flat deposit pull `safeTransferFrom(proposer → BODENSEE_CHANNEL)` + `BODENSEE_CHANNEL.donate`, `ProposalCreated` event; Cursor §8e.1.
- **K4.3** `src/governance/AureumGovernance.sol` — `castVote`: `VOTING_WEIGHT.poke(msg.sender)` + `governanceWeight` read, FOR/AGAINST accrual, `hasVoted` double-vote guard, inline voting-window check (`block.number <= endBlock`), `VoteCast` event; Cursor §8e.1.
- **K4.4** `src/governance/AureumGovernance.sol` — `state(id)` derived view + tally: quorum `(forVotes + againstVotes) * 10_000 >= snapshotTotalSupply * QUORUM_BPS`, per-type majority (simple `forVotes > againstVotes` gauge+fee / `forVotes * 3 >= (forVotes + againstVotes) * 2` composition); Cursor §8e.1.
- **K4.5** `src/governance/AureumGovernance.sol` — `queue` (eta = `block.number + EXECUTION_TIMELOCK_BLOCKS`, requires `state == Succeeded`) + `execute` (requires `state == Queued`, grace-window check, per-type routing: gauge `revokeGauge`; composition read-old + `revokeGauge` + `replaceSlot` + `registerGaugeFromComposition` atomic; fee band/Bodensee/cooldown validation + `setStaticSwapFeePercentage` + `lastFeeChangeBlock` write), `ProposalQueued` / `ProposalExecuted` events; Cursor §8e.1.
- **K4.6** `test/unit/AureumGovernance.t.sol` — unit cohort: per-type propose validation + deposit; castVote poke/guard/window; quorum + majority/supermajority boundaries; queue/execute timelock + grace + per-type routing against mocked registries/vault; Cursor §8e.1.
- **K4.7** `test/fork/StageKIntegration.t.sol` — fork integration: real `VotingWeight` poke over hook-recorded deposits (absorbs the folded K3.3 coverage) + an end-to-end governance proposal lifecycle; Cursor §8e.1.

### K5 — AuMMMinterRouter minter handoff (per K-D7 LOCKED)

H-D41 minter handoff resolved Option B at the K5 pre-flight (K-D7, user decision 2026-06-10): a new dumb allowlist forwarder `AuMMMinterRouter` (`src/token/`) holds AuMM's C-D11 one-shot minter slot, both Stage H mint consumers gain a one-shot `onlyGovernance` `setMintRouter` and swap their mint sites to `mintRouter.mintFor(...)` (I13-class fix-forward; `stage-h-complete` untouched), and the multisig `aumm.setMinter(router)` executes at K7 per K-D9 — flushing the bootstrap backlog and unblocking `distribute()` / `claim()` from the `MintRouterNotSet` pre-wiring guard. Surfaces `src/token/IAuMMMinterRouter.sol` + `src/token/AuMMMinterRouter.sol` + `test/unit/AuMMMinterRouter.t.sol` + the two consumer fix-forward edits (`src/emission/BodenseeBootstrapChannel.sol`, `src/emission/EmissionDistributor.sol`); AuMM stays byte-untouched (K-D1 clause holds). Full design body + wiring order + Stage-P fixed-emission-path flag in STAGE_K_NOTES.md K-D7.

- **K5.0a** (DONE — `5058f8f`) `docs/STAGE_K_NOTES.md` — K-D7 `AuMMMinterRouter` (Option B) minter handoff LOCKED (dumb allowlist forwarder, two-member immutable allowlist, one-shot `setMintRouter` consumer fix-forward, wiring order, Stage-P flag, full design body); Cursor §8e.1.
- **K5.0b** (THIS COMMIT) `docs/STAGE_K_PLAN.md` — K-D7 mirror flip to LOCKED + K5 sub-step ladder + Surfaces table K5 rows + Completion Log catch-up; Cursor §8e.1.
- **K5.1** `src/token/IAuMMMinterRouter.sol` — the allowlist-forwarder interface: `mintFor(address recipient, uint256 amount)` external + `NotAllowlisted(address caller)` error (event surface bare-vs-`MintRouted` locks at K5.2 per the §12 gate); Cursor §8e.1.
- **K5.2** `src/token/AuMMMinterRouter.sol` — the concrete forwarder per K-D7: `is IAuMMMinterRouter`, three zero-checked immutables (`AUMM` / `BOOTSTRAP_CHANNEL` / `EMISSION_DISTRIBUTOR`), single `mintFor` reverting `NotAllowlisted(msg.sender)` unless the caller is one of the two consumers else `AUMM.mint(recipient, amount)`; no amount policy, no cap math, no governance slot, no setters; Cursor §8e.1.
- **K5.3a** `src/emission/BodenseeBootstrapChannel.sol` — channel fix-forward: add `IAuMMMinterRouter public mintRouter` + a one-shot `onlyGovernance` `setMintRouter` (`ZeroAddress` + `MintRouterAlreadySet` guards, `MintRouterBound` event), swap the `distribute()` mint site `AuMM.mint(address(this), amount)` → `mintRouter.mintFor(address(this), amount)` behind a `MintRouterNotSet` pre-wiring guard, I10 NatSpec sweep of stale `setMinter` prerequisite lines (grep-first); the `AuMM` immutable is retained for `blockEmissionRate` reads + IERC20 transfer / balance casts; Cursor §8e.1.
- **K5.3b** `src/emission/EmissionDistributor.sol` — distributor fix-forward (same shape as K5.3a): `IAuMMMinterRouter public mintRouter` + one-shot `setMintRouter`, swap the `claim()` mint site `AuMM.mint(to, amount)` → `mintRouter.mintFor(to, amount)` behind a `MintRouterNotSet` guard, I10 NatSpec sweep; the `AuMM` immutable is retained for `blockEmissionRate` reads; Cursor §8e.1.
- **K5.4a** `test/unit/AuMMMinterRouter.t.sol` (NEW) — router unit cohort: three zero-address constructor reverts + immutable wiring, `mintFor` allowlist accept (from both consumers) / reject (`NotAllowlisted`), `MintRouted` emit, passthrough including cap-boundary against a real AuMM with the test as `minterAdmin`; Cursor §8e.1.
- **K5.4b** `test/unit/BodenseeBootstrapChannel.t.sol` (EDIT, K13 retrofit) — setUp deploys a real `AuMMMinterRouter(aumm, channel, dummyDistributor)`, re-points `aumm.setMinter(router)`, binds `channel.setMintRouter(router)` (greening the 6 K13-red `distribute()` tests; the in-test `ch2` site re-wires identically), plus the channel `setMintRouter` one-shot cohort (zero-address, already-set, caller-not-governance, `MintRouterBound` emit) and a `MintRouterNotSet` pre-wiring revert test on a fresh unbound channel; Cursor §8e.1.
- **K5.4c** `test/unit/EmissionDistributor.t.sol` (EDIT, K13 retrofit) — same retrofit shape (greening the 5 K13-red `claim()` tests) plus the distributor `setMintRouter` one-shot cohort and a `MintRouterNotSet` pre-wiring revert test on a fresh unbound distributor; Cursor §8e.1.
- **Fork transition coverage** (FOLDED → K7) end-to-end `MintRouterNotSet`-to-live minter-transition coverage folds into K7's `DeployStageK` fork test per K-D9 — the wiring order (router deploy → consumer `setMintRouter` → multisig `aumm.setMinter(router)`) is a K7 deploy-sequence concern.

### K6 — TVLOracle roster re-wire (per K-D8)

Re-point `src/emission/TVLOracle.sol` `_constellationRatio` to the live `MiliariumRegistry` dense enumeration (`miliariumPoolsCount` / `miliariumPoolAt`) — J-D8 carry-forward, an I13-class fix-forward on a tagged Stage H contract; K6 pre-flight sizes the TVLOracle / EMASampler / CCB fork-test blast radius.

- **K6.0a** (DONE — `bd28e72`) `docs/STAGE_K_NOTES.md` — K-D8 LOCKED: TVLOracle roster re-wire (F-D20 setter binding + live MiliariumRegistry Leg 2 + isMiliarium dedup) + full design body + K6 sub-step ladder; Cursor §8e.1.
- **K6.0b** (THIS COMMIT) `docs/STAGE_K_PLAN.md` — K-D8 mirror flip to LOCKED + K6 sub-step ladder + Surfaces `test/unit/TVLOracle.t.sol` row + Completion Log catch-up + Status/Last-update banner refresh; Cursor §8e.1.
- **K6.1** `src/emission/TVLOracle.sol` (additive) — `IMiliariumRegistry` import + `miliariumRegistry` slot + deployer-pinned `registrySetter` slot + ctor-body `registrySetter = msg.sender` (6-arg signature untouched) + one-shot self-seal `setMiliariumRegistry` (`OnlyRegistrySetter` auth, `ZeroAddress` zero-check, self-zero seal) + `MiliariumRegistrySet(address indexed registry)` event; no `_constellationRatio` change yet; Cursor §8e.1.
- **K6.2** `src/emission/TVLOracle.sol` (behavioral) — `_constellationRatio` Leg 2 live registry enumeration (`miliariumPoolsCount` / `miliariumPoolAt`, guarded by the unbound-registry check) + Leg 1 `isMiliarium(v)` dedup skip + NatSpec; Cursor §8e.1.
- **K6.3** `test/unit/TVLOracle.t.sol` (EDIT) — `setMiliariumRegistry` one-shot self-seal cohort (happy-path emit + `OnlyRegistrySetter` post-seal + `ZeroAddress`) + Leg 2 enumeration contribution to `tvl()` + Leg 1 dedup-skip assertion, mock `IMiliariumRegistry`; Cursor §8e.1.

### K7 — Deploy + authorizer migration (per K-D9 LOCKED)

Two deploy scripts + a fork test materializing the governance handoff: `script/DeployAuMM.s.sol` (H-D42 micro-script, the production-chain prerequisite before `DeployStageH`) + `script/DeployStageK.s.sol` (deploy the governance stack in ctor order, then the five-step wiring chain) + `test/fork/DeployStageK.t.sol` (H13-safe — all four K7 ctors zero-check-only, wiring hits real fork targets). Handoff set = gauge + registry only per K-D9; emission-layer + `VaultClassRegistry` governance slots stay at the multisig (deferred to L/M/N/O).

- **K7.0a** (DONE — `9502025`) `docs/STAGE_K_NOTES.md` — K-D9 LOCKED: deploy + authorizer-migration sequencing + full design body (two scripts / deploy order / wiring chain / handoff set / fork test / K7 sub-steps) + Status/Last-update banner refresh; Cursor §8e.1.
- **K7.0b** (THIS COMMIT) `docs/STAGE_K_PLAN.md` — K-D9 mirror flip to LOCKED + K7 sub-step ladder + Completion Log catch-up (K6-log `f5b85ee` back-fill / K6-§11 / K7.0a) + Decisions preamble + Status/Last-update banner refresh; Cursor §8e.1.
- **K7.1** `script/DeployAuMM.s.sol` (NEW, ~30 lines) — H-D42 micro-script: `run()` broadcasts `new AuMM(vm.envUint("GENESIS_BLOCK"), vm.envAddress("GOVERNANCE_MULTISIG"))` + a stdout address emit, mirroring the `DeployDerBodensee.s.sol:L39` `AUMM` env convention; H13-safe (AuMM ctor is storage-only). Production-chain prerequisite that runs before `DeployStageH`; Cursor §8e.1.
- **K7.2** `script/DeployStageK.s.sol` (NEW, ~120 lines) — `DeployStageJ` `run()` / `deploy(governor)` / `_deploy()` triad with env-input addresses (no silent zero fallbacks): deploy `VotingWeight` → `AureumGovernance` → `AureumGovernanceAuthorizer` → `AuMMMinterRouter` (genesis from `aumm.GENESIS_BLOCK()`), then the five-step wiring chain — (1) `vaultClassRegistry.setVotingWeight`, (2) `channel` + `distributor` `setMintRouter` (before handoff, governance slot still = deployer per K-D7), (3) `gaugeRegistry` + `miliariumRegistry` `setGovernanceContract(gov)`, (4) `aumm.setMinter(router)`, (5) multisig `vault.setAuthorizer(authorizer)`; sub-splits K7.2a (deploy) / K7.2b (wiring) at K7.2 pre-flight if the script is large; Cursor §8e.1.
- **K7.3** `test/fork/DeployStageK.t.sol` (NEW, ~150 lines) — inherits the Stage-I/J fork fixture (real Vault + AuMM + Bodensee + gauge + oracle + distributor + registry per H13), runs `DeployStageK.deploy(...)`, asserts the `MintRouterNotSet`→live transition (post-wiring `distribute()` / `claim()` mint succeeds), the gauge + registry handoff (`governanceContract == gov`), and the OQ-10 migration (governance `canPerform` = true / multisig emergency-action gated / non-emergency multisig denied); the exact fixture base is fixed at the K7.3 pre-flight; Cursor §8e.1.

### K-close — stage close

Full split-form regression (unit + fork per D35 / D36) green; `CLAUDE.md` §11 close-out refresh; ff-merge `stage-k` → `main`; `stage-k-complete` tag; push `main` + tag + `stage-k` to `origin`.

---

## Completion Log

| Sub-step | Commit | Summary |
| --- | --- | --- |
| K0.1 | (branch op) | `stage-k` branched from `stage-j-complete` (`83ef71e`) |
| K0.2 | `e241c22` | docs/STAGE_K_NOTES.md — Stage K design freeze (K-D1 + K-D2 LOCKED) |
| K0.3 | `597880e` | docs/STAGE_K_PLAN.md — sub-step roadmap + Decisions mirror + Pre-flight checklist + Completion Log skeleton |
| K0.4 | `5a165a9` | CLAUDE.md §11 — Stage J→K terminal refresh (resume anchor: K0 entry landed, Stage K open, K1 pre-flight next) |
| K1.0a | `130c39d` | docs/STAGE_K_NOTES.md — K-D3 AureumGovernanceAuthorizer design LOCKED (emergency set {pauseVault, enableRecoveryMode}, H13-safe action-ID encoding) |
| K1.0b | `e3b8f57` | docs/STAGE_K_PLAN.md — K-D3 mirror flip to LOCKED + K1 sub-step detail + Completion Log catch-up |
| K1.1 | `73ceaae` | src/governance/AureumGovernanceAuthorizer.sol — B-strict 12-month time-bomb authorizer per OQ-10 / K-D3 (emergency set {pauseVault, enableRecoveryMode}, H13-safe action-ID encoding) |
| K1.2 | `e72104c` | test/unit/AureumGovernanceAuthorizer.t.sol — unit cohort (12 cases: governance/emergency routing, window boundary, action-ID encoding, constructor reverts) |
| K2.0a | `3e8250d` | docs/STAGE_K_NOTES.md — K-D4 TVL-oracle binding LOCKED reuse-direct (ITVLOracle.tvl(pool); no new K2 contract) |
| K2.0b | `29d4b71` | docs/STAGE_K_PLAN.md — K-D4 mirror flip to LOCKED + K2 documentation-only framing + Completion Log catch-up |
| K3.0a | `d66688b` | docs/STAGE_K_NOTES.md — K-D5 VotingWeight LOCKED (stateful poke-accumulator, recorder-share value per OQ-25, exact veto fraction) |
| K3.0b | `0b790c3` | docs/STAGE_K_PLAN.md — K-D5 mirror flip to LOCKED + K3 sub-step ladder + Surfaces table K3.0c rows + Completion Log catch-up |
| K3.0c | `888f0bd` | src/emission/IEmissionDistributor.sol + EmissionDistributor.sol — effectiveQualBlock interface getter + override (I13-class fix-forward per K-D5) |
| K3.1 | `50d9f95` | src/governance/VotingWeight.sol — stateful poke-accumulator per K-D5 |
| K3.2a | `4d81ffc` | test/unit/VotingWeight.t.sol — scaffold, mocks, constructor cohort (7 tests) |
| K3.2b | `8e345b5` | test/unit/VotingWeight.t.sol — single-position behavioral cohort (13 tests) |
| K3.2c | `d2f90d1` | test/unit/VotingWeight.t.sol — aggregate behavioral cohort (9 tests) |
| K3.3a | `e69652c` | docs/STAGE_K_NOTES.md — K3.3 fold into K4 + K3 complete recorded |
| K3.3b | `1ad18ea` | docs/STAGE_K_PLAN.md — K3.3 fold mirror + status refresh + Completion Log catch-up (K3.0b—K3.3b) |
| K3.4 | `632e23d` | CLAUDE.md §11 — K3 complete + K4 pre-flight next (resume anchor) |
| K4.0a | `4e3b5e6` | docs/STAGE_K_NOTES.md — K-D6 LOCKED (AureumGovernance three proposal types + K-D6a—K-D6f sub-splits) |
| K4.0b | `8ca9d3b` | docs/STAGE_K_PLAN.md — K-D6 mirror flip to LOCKED + K4 sub-step ladder (K4.0a—K4.7) + Completion Log catch-up (K3.4 / K4.0a / K4.0b) |
| K4.1 | `d7cc7b5` | src/governance/AureumGovernance.sol — scaffold (8 immutables + 9 constants + ProposalType/ProposalState enums + 13-field Proposal struct + storage/events/errors per K-D6a) |
| K4.2 | `e88a8f8` | src/governance/AureumGovernance.sol — propose family |
| K4.2-post-a | `1625ec4` | docs/STAGE_K_NOTES.md — K10 finding (IVotingWeight poke I13-class fix-forward) |
| K4.2-post-b | `81d246d` | src/governance/IVotingWeight.sol + mock stubs — add poke (K10 / G16) |
| K4.3 | `dd0dbf2` | src/governance/AureumGovernance.sol — castVote |
| K4.4 | `5523e71` | src/governance/AureumGovernance.sol — state, _voteSucceeded, getProposal |
| K4.5 | `dc7eb99` | src/governance/AureumGovernance.sol — queue, execute, _executeProposal |
| K4.6a | `c2dd343` | test/unit/AureumGovernance.t.sol — harness, mocks, setUp, 1/1 green |
| K4.6b | `a5f615c` | test/unit/AureumGovernance.t.sol — constructor zero-reverts, deposit mechanics, propose-family validation |
| K4.6b-post | `44fb7ec` | docs/STAGE_K_NOTES.md — K11 finding (Foundry parameterized expectRevert) |
| K4.6c | `01c3db0` | test/unit/AureumGovernance.t.sol — castVote accrual, poke obligation, window boundary, guards |
| K4.6d | `a6b18c4` | test/unit/AureumGovernance.t.sol — state/tally, quorum boundary, supermajority |
| K4.6e | `828eb86` | test/unit/AureumGovernance.t.sol — queue/execute guards, per-type routing, cooldown |
| K4.7.0a | `594eb5b` | docs/STAGE_K_NOTES.md — K4.7 fork-integration design (pre-flight lock) |
| K4.7a | `dcf94f9` | test/fork/StageKIntegration.t.sol — fixture, setUp, wiring smoke (1/1 green) |
| K4.7b-fix1 | `e599b0e` | docs/STAGE_K_NOTES.md — correct R1 fork-runtime risk (tvl mocked via _mockTvl) |
| K4.7b | `3f845ea` | test/fork/StageKIntegration.t.sol — VotingWeight poke fork tests, 4 shapes (5/5 green) |
| K4.7c | `dd37cd1` | test/fork/StageKIntegration.t.sol — composition-challenge lifecycle (6/6 green) |
| K4.7c-notes | `f68c978` | docs/STAGE_K_NOTES.md — K12 optimizer CSE block.number finding (F10 extension) |
| K4-§11 | `b628a22` | CLAUDE.md §11 — K4 complete + K5 pre-flight next (resume-anchor refresh) |
| K5.0a | `5058f8f` | docs/STAGE_K_NOTES.md — K-D7 LOCKED (AuMMMinterRouter Option B minter handoff: dumb allowlist forwarder + one-shot setMintRouter consumer fix-forward) |
| K5.0b | `056e08c` | docs/STAGE_K_PLAN.md — K-D7 mirror flip to LOCKED + K5 sub-step ladder + Surfaces table K5 rows + Completion Log catch-up |
| K5.1 | `47aaddc` | src/token/IAuMMMinterRouter.sol — allowlist-forwarder interface (mintFor + NotAllowlisted) |
| K5.2-pre | `e3e60a8` | docs/STAGE_K_NOTES.md — K-D7 event-surface §12 gate LOCKED (MintRouted indexed caller) |
| K5.2 | `104e724` | src/token/AuMMMinterRouter.sol — allowlist mint forwarder (MintRouted + ZeroAddress, three immutables) |
| K5.3a-i | `99d2f92` | src/emission/BodenseeBootstrapChannel.sol — mintRouter storage + MintRouterAlreadySet + MintRouterBound + setMintRouter (K-D7 additive) |
| K5.3a-ii | `e866682` | src/emission/BodenseeBootstrapChannel.sol — MintRouterNotSet + mintFor swap + NatSpec sweep (K-D7 behavioral) |
| K5.3b-i | `4950059` | src/emission/IEmissionDistributor.sol + EmissionDistributor.sol — mintRouter storage + setMintRouter setter + 3 interface symbols (K-D7 additive) |
| K5.3b-ii | `fcdccac` | src/emission/EmissionDistributor.sol — MintRouterNotSet guard + mintFor swap + claim NatSpec sweep (K-D7 behavioral) |
| K5.3b-iii | `45335d0` | src/emission/EmissionDistributor.sol — mint-posture NatSpec sweep (K-D7 doc consistency) |
| K5.4-pre-a | `f1cc54a` | docs/STAGE_K_NOTES.md — K13 MintRouterNotSet blast radius finding + K5.4a/b/c sub-step decomposition |
| K5.4-pre-b | `7d97a0b` | docs/STAGE_K_PLAN.md — K13 PLAN mirror: K5.4a/b/c ladder + Surfaces table +2 consumer-test rows + Completion Log catch-up |
| K5.4a | `36de306` | test/unit/AuMMMinterRouter.t.sol — router unit cohort (10/10 green, K-D7) |
| K5.4b-i | `cea9ad9` | test/unit/BodenseeBootstrapChannel.t.sol — K13 retrofit: setUp + ch2 route distribute() mints through real AuMMMinterRouter (6 red → green, 29/29) |
| K5.4b-ii | `8a63db6` | test/unit/BodenseeBootstrapChannel.t.sol — setMintRouter one-shot cohort + MintRouterNotSet guard test + _freshUnboundChannel helper (5 new, 34/34) |
| K5.4c-i | `03c528c` | test/unit/EmissionDistributor.t.sol — K13 retrofit: setUp routes claim() mints through real AuMMMinterRouter (5 red → green, 101/101) |
| K5.4c-ii | `ad7566e` | test/unit/EmissionDistributor.t.sol — setMintRouter one-shot cohort + claim MintRouterNotSet guard test + _freshUnboundDistributor helper (5 new, 106/106) |
| K5.4-log | `81793f3` | docs/STAGE_K_PLAN.md — Completion Log catch-up: K5.4a / b-i / b-ii / c-i / c-ii rows + K5.4-pre-b hash back-fill |
| K6.0a | `bd28e72` | docs/STAGE_K_NOTES.md — K-D8 LOCKED: TVLOracle roster re-wire (F-D20 setter binding + live MiliariumRegistry Leg 2 + isMiliarium dedup) + K6 sub-step ladder |
| K6.0b | `7fc8a85` | docs/STAGE_K_PLAN.md — K-D8 mirror flip to LOCKED + K6 sub-step ladder + Surfaces test/unit/TVLOracle.t.sol row + Completion Log catch-up + banner refresh |
| K6.1 | `5a0a809` | src/emission/TVLOracle.sol — additive setMiliariumRegistry surface (F-D20 self-seal: miliariumRegistry + registrySetter slots, OnlyRegistrySetter error, MiliariumRegistrySet event; _constellationRatio untouched) |
| K6.2 | `e05b52d` | src/emission/TVLOracle.sol — _constellationRatio two-leg re-wire (Leg 1 reverse-map + isMiliarium dedup skip / Leg 2 live MiliariumRegistry enumeration) + _venueRatio helper (K-D8; 36/36 green) |
| K6.3 | `aef852c` | test/unit/TVLOracle.t.sol — K-D8 cohort: setMiliariumRegistry one-shot self-seal + Leg 2 enumeration contribution + isMiliarium dedup-skip (local dense mock; 6 new, 42/42) |
| K6-log | `f5b85ee` | docs/STAGE_K_PLAN.md — Completion Log catch-up: K6.1 / K6.2 / K6.3 rows + K5.4-log / K6.0b hash back-fill + Status/Last-update banner refresh to K6 close |
| K6-§11 | `ea23b6f` | CLAUDE.md §11 — K6 complete + K7 pre-flight next (resume-anchor refresh) |
| K7.0a | `9502025` | docs/STAGE_K_NOTES.md — K-D9 LOCKED (deploy + authorizer-migration sequencing) + full design body + K7 sub-step ladder + Status/Last-update banner refresh to K7 |
| K7.0b | (this commit) | docs/STAGE_K_PLAN.md — K-D9 mirror flip to LOCKED + K7 sub-step ladder + Completion Log catch-up (K6-log `f5b85ee` back-fill / K6-§11 / K7.0a) + Decisions preamble + Status/Last-update banner refresh |
