# Stage I — Plan & Sub-Step Roadmap

> **Status:** I1 (EmissionDistributor per-pool refactor, I-D9), I2 (AureumTime constants, I-D10), and I3 (AuMT.sol concrete implementation, I-D1/I-D4/I-D6/I-D7/I-D11/I-D12) COMPLETE; I8 — gauge-eligibility hook-gate add-on (OQ-24 / I-D13) COMPLETE on `stage-i` (HEAD at the I8.6 sweep) — `GaugeEligibility` now requires the canonical `AureumFeeRoutingHook` (9th constructor immutable + `WrongFeeRoutingHook` fail-fast gate); 49/49 GaugeEligibility unit + 71/71 fork green. I4 — AureumFeeRoutingHook AuMT extension (I-D5) — PARKED at I4.2 pending the I-D5/I-D8 AuMT-scope reconciliation (AuMT for all gauged pools, not Miliarium-only) + `setAuMTForPool` binding-authority decision (leaning permissionless per I-D13). I-D1—I-D13 Decisions LOCKED; I10—I13 Findings landed. Companion to STAGE_I_NOTES.md.
>
> **Last update:** 2026-05-29 — I8 gauge-eligibility hook-gate add-on COMPLETE (this sweep). I8.0a OQ-24 (`f2d9da4`) → I8.0b I-D13 LOCK (`b09605c`) → I8.0c PLAN roadmap (`2589788`) → I8.0d STAGES_OVERVIEW (`ac8ff94`) → I8.1 immutable+error (`20ee4bc`) → I8.2 fail-fast gate (`189e949`) → I8.3a/b/c ctor-sites + setUp mock + fork wiring (`aee6c2f` / `a7b1bdd` / `10689c7`) → I8.4 three hook-gate tests (`fc36d60`) → I8.5 regression (619/620 unit — lone failure pre-I8 I4.1 getHookFlags artifact deferred I4.5 — + 71/71 fork) → I8.6a I13 Findings (`dcca7fe`) → I8.6b/c Completion + Surfaces (`74b3add` / `0dc3798`) → I8.6d status/mode this commit + I8.6e CLAUDE §11 pending. I4.2 resume next (after the parked I-D5/I-D8 reconciliation + binding-authority LOCK).
>
> **Mode:** Opus high per §13 stage-level defaults. I1/I2/I3 COMPLETE; I8 gauge-eligibility hook-gate add-on COMPLETE (I8.0a—I8.6c landed; I8.6d status/mode this commit; I8.6e CLAUDE §11 next). I4 — AureumFeeRoutingHook AuMT extension (I-D5) — PARKED at I4.2: resume requires the I-D5/I-D8 AuMT-scope reconciliation + `setAuMTForPool` binding-authority decision (chat-level, leaning permissionless per I-D13) before the I4.2 §8e.1. I5 unit tests + I6 fork integration + I7 deploy + close-of-stage ahead.
>
> **Audience:** Sagix plus any future Claude session that needs the operational roadmap for Stage I sub-step execution. NOTES (STAGE_I_NOTES.md) is the running design-decision log; this file is the sub-step sequence + Completion Log + grep-verifiable checkpoint catalog.

---

## Stage scope

Stage I implements the AuMT (Aureum Market Tessera) governance spine. Per OQ-25 / I-D14, AuMT is not a separate token — it is the pool's own Balancer V3 BPT under the Aureum brand; there is no `AuMT.sol`, no soulbound mirror, no token mint/burn. Stage I ships the security-critical, oracle-free half of the design: (1) the EmissionDistributor recorder clock — per-(pool, user) `effectiveQualBlock` (weighted-average top-up per I-D14, reset on any withdrawal) alongside the existing `userLP[pool][user]` amount; (2) the `AureumFeeRoutingHook` dispatch — `onAfterAddLiquidity` / `onAfterRemoveLiquidity` (I4.1 `getHookFlags` bump retained) call `recordDeposit` / `recordWithdrawal` on the shared EmissionDistributor, with the hook holding a one-shot `emissionRecorder` slot per I-D16 and `auMTContractByPool[pool] = address(hook)` binding the recorder gate per the I-D9 amend. The value-weighted voting view — `(qualified_AuMT_value × time_in_pool_capped)^(1/4 → 1/3)`, 14-day cliff, 6-month on-ramp, F-9 era transition, gauged-only — is deferred out of Stage I per I-D15 (its `ITVLOracle` value source is a forward stub until OQ-22, and snapshot voting is a Stage K concern); it lands as a thin `src/governance/VotingWeight.sol` reader when those dependencies exist. The I1 per-pool recorder refactor (I-D9), I2 AureumTime constants (I-D10), and I8 gauge-eligibility hook-gate (I-D13) stand unchanged.

### Surfaces produced at Stage I

| File | Status | Sub-step | LOC estimate |
| --- | --- | --- | --- |
| `src/emission/IEmissionDistributor.sol` | EDITED | I1.1 | +5 / -3 |
| `src/emission/EmissionDistributor.sol` | EDITED | I1.2 | +20 / -10 |
| `src/lib/AureumTime.sol` | EDITED | I2.1 | +10 / 0 |
| `src/token/AuMT.sol` | NEW | I3.1—I3.7 | ~250 |
| `src/token/IAuMT.sol` | EDITED | I3.7 | +0 / -2 (NatSpec correction at L35 + L47-L48) |
| `src/fee_router/AureumFeeRoutingHook.sol` | EDITED | I4.1—I4.4 | +60 / 0 |
| `src/gauge/GaugeEligibility.sol` | EDITED | I8.1—I8.2 | +11 / -1 |
| `test/unit/EmissionDistributor.t.sol` | EDITED | I1.3 | mechanical signature updates |
| `test/unit/AuMMDistributorIntegration.t.sol` | EDITED | I1.4 | mechanical signature updates |
| `test/fork/StageHIntegrationFixture.sol` + 4 derived suites | EDITED | I1.5 | mechanical signature updates |
| `test/fork/DeployStageH.t.sol` | EDITED | I1.6 | assertion update |
| `test/unit/AureumTime.t.sol` | EDITED | I2.2 | +6 lines (constant assertions) |
| `test/unit/AuMT.t.sol` | NEW | I5.1—I5.6 | ~600 |
| `test/fork/StageIIntegration.t.sol` | NEW | I6.1—I6.5 | ~400 |
| `script/DeployStageI.s.sol` | NEW | I7.1 | ~150 |
| `test/fork/DeployStageI.t.sol` | NEW | I7.2 | ~200 |
| `test/unit/GaugeEligibility.t.sol` | EDITED | I8.3a—I8.4 | +66 / -10 |
| `test/fork/StageGIntegration.t.sol` | EDITED | I8.3c | +6 / -1 |

### Surfaces NOT produced at Stage I

- Stage M/N AuMT rollout for remaining 25 pilot pools (slots 01/04/05/06/08—28) — out of Stage I scope per STAGES_OVERVIEW.
- AuMM.setMinter handoff — deferred to Stage K per H-D7 Option C.
- IAuMT.sol skeleton at H6.0c preserved verbatim except for the L35 (mint) + L47-L48 (burn) NatSpec corrections at I3.7 (re: I-D4 access control re-NatSpec'd from "callable by the bound distributor only" to "callable by the bound liquidity hook only").

---

## Decisions

Mirror of STAGE_I_NOTES.md Decisions table (LOCKED at I0.0a—I0.0b). Future I-D11 onward attach to sub-step-specific locks during I1—I7 execution and are recorded as new entries in both this table and the NOTES file.

| # | Status | Decision | Anchor | Locked at |
| --- | --- | --- | --- | --- |
| I-D1 | SUPERSEDED by I-D14 | AuMT is soulbound — transfer/transferFrom/approve revert `NotTransferable` | §ix withdrawal-reset rule; spec silence on transfer = soulbound intent | I0.0a |
| I-D2 | SUPERSEDED by I-D14 | 1 AuMT contract per Miliarium pool (3 pilot @ Stage I; 28 @ full) | H-D35; CLAUDE.md §1; IAuMT.sol L67 NatSpec | I0.0a |
| I-D3 | SUPERSEDED by I-D14 | 18 decimals matching pool BPT | Balancer V3 BPT convention; Stage E pilot pool deploys | I0.0a |
| I-D4 | SUPERSEDED by I-D14 | mint + burn access: `onlyLiquidityHook` — bound AureumFeeRoutingHook only | Hook owns LP deposit/withdrawal moment; distributor is downstream consumer | I0.0a |
| I-D5 | AMENDED by I-D14 | Extend `AureumFeeRoutingHook.sol` in-place at I4 — `getHookFlags` bump + `onAfterAddLiquidity` / `onAfterRemoveLiquidity` + `auMTByPool` + `setAuMTForPool` | Balancer V3 one-hook-per-pool constraint; nested-call precedent at L408-431 | I0.0a |
| I-D6 | AMENDED by I-D14 | Qualification clock — first-deposit start; top-up doesn't reset; withdrawal resets to 0 | §ix verbatim "Remove any amount... time_in_pool resets" | I0.0a |
| I-D7 | AMENDED by I-D14 | `governanceWeight` = (balance × time_in_pool_capped)^(1/4 Era 0; 1/3 Era 1+); ZERO if unqualified OR ungauged | §ix verbatim formula; F-9 dampening; AureumTime C-D3 era boundary; FINDINGS OQ-7 gauge-revoked rule | I0.0a |
| I-D8 | AMENDED by I-D14 | Stage I scope — 3 pilot AuMT + FeeRoutingHook extension; Stage M/N deferred | Stage E pilot pools; out-of-scope rollout per STAGES_OVERVIEW | I0.0a |
| I-D9 | AMENDED by I-D14 | Multi-AuMT routing — per-pool mapping in EmissionDistributor (Option A); `auMTContractByPool` + `onlyAuMTContract(pool)` modifier + `setAuMTContractForPool(pool, addr)` | H-D16 single-slot baseline; H-D10 per-pool recorder precedent; I-D2 per-pool topology | I0.0b |
| I-D10 | LOCKED | `AureumTime.sol` extension — `QUALIFICATION_PERIOD_BLOCKS = BLOCKS_PER_EPOCH` (100_800) + `ON_RAMP_PERIOD_BLOCKS = 180 * BLOCKS_PER_DAY` (1_296_000) | C-D3 canonical time library; §ix verbatim "14 days" + "day 180" | I0.0b |
| I-D11 | SUPERSEDED by I-D14 | AuMT constructor pattern — 6 args (pool_/distributor_/liquidityHook_/genesisBlock_/name_/symbol_); 4 immutables (pool/distributor/liquidityHook/GENESIS_BLOCK); name/symbol per-creator (Balancer BPT convention; ixXYZ for 28 Miliarium pools) | C-D3 canonical immutable convention; H13 NOTES (no constructor external calls); Balancer V3 BPT name-by-creator | I3.0a |
| I-D12 | SUPERSEDED by I-D14 | AuMT 5th immutable `gaugeRegistry` — extends I-D11 (6→7 args, 4→5 immutables); new `address gaugeRegistry_` constructor arg slotted at position 4 (between `liquidityHook_` and `genesisBlock_`); Option A direct-binding (not B distributor-chained, not C interface widening) | I-D7 governanceWeight ZERO branch; EmissionDistributor.sol:L31 precedent; H13 no-constructor-external-call; I5 deploy-time consistency invariant | I3.5-pre1 |
| I-D13 | LOCKED | Gauge eligibility requires canonical `AureumFeeRoutingHook` — `GaugeEligibility._checkEligibilityCriteria` asserts `getHooksConfig(pool).hooksContract == feeRoutingHook` (9th ctor immutable) else `WrongFeeRoutingHook`; AuMT scope = all gauged pools (I-D5/I-D8 Miliarium-only = pilot cadence, not ceiling) | OQ-24; OQ-1/OQ-2; D-D15 swap-fee pin; G-D8 52% gate; I-D5 AuMT mint; G16 ctor-site enum | I8.0b |
| I-D14 | LOCKED | AuMT = the pool's BPT (branded; no separate ERC-20); value-weighted snapshot voting; clock in EmissionDistributor recorder (`effectiveQualBlock` weighted-avg top-up per I-D6 amend; vote-time gauge gate per I-D7 amend); `auMTContractByPool[pool]` → hook address at deploy (I-D9 amend); supersedes I-D1/I-D2/I-D3/I-D4/I-D11/I-D12; amends I-D5/I-D6/I-D7/I-D8/I-D9 | OQ-25; `04_tokenomics.md` §viii; OQ-7; I-D13 (hook required infra); I1 recorder (clock host) | I-reframe.2 |
| I-D15 | LOCKED | Voting-weight value-weighted view DEFERRED out of Stage I (deps downstream — `ITVLOracle` concrete = OQ-22/F-D3; snapshot layer = Stage K); Stage I ships the recorder clock + hook dispatch only; `src/token/AuMT.sol` + `src/token/IAuMT.sol` DELETED | OQ-25 (view-location sub-point L1314); I-D14; `ITVLOracle` deferred (OQ-22/F-D3); Stage K snapshot layer | I-reframe.3b |
| I-D16 | LOCKED | Hook→recorder reference = one-shot settable `emissionRecorder` slot + `setEmissionRecorder` on `AureumFeeRoutingHook` (mirrors `setGovernanceModule`), NOT a constructor immutable (deploy ordering Stage D < Stage H = H13-class; avoids G16 ripple to 5 ctor sites); old per-pool `auMTByPool` / `setAuMTForPool` dropped | I-D14 hook dispatch; I-D9 distributor-side bind; H13 deploy ordering; G16; `setGovernanceModule` one-shot precedent | I-reframe.3c |

---

## Pre-flight checklist

- [x] `main` at `stage-h-complete` (commit `2a33649`); `origin/main` synced.
- [x] `stage-i` branched from `stage-h-complete` per the C0 / D0 / E-D8 / F9 / G9 / H12 convention.
- [x] No upstream tracking for `stage-i` yet — snapshot push deferred to I7.4 close-of-stage.
- [x] STAGE_I_NOTES.md design freeze (I-D1—I-D10 LOCKED) landed at I0.0b commit `1404b2d`.
- [x] All Stage H locked surfaces frozen: `IGaugeRegistry`, `IEmissionDistributor`, `AureumTime`, `AureumFeeRoutingHook` (pre-I4 surface), `IAuMT` H6.0c skeleton.
- [ ] (resolves at I1.7) Stage H test cohort 612/612 unit + 10/10 fork + 1/1 deploy fork green after Stage I per-pool refactor.
- [ ] (resolves at I4.5) Stage D test cohort green after AureumFeeRoutingHook extension.
- [ ] (resolves at I7.3) Full Stage I test cohort green (AuMT unit + StageIIntegration fork + DeployStageI fork).
- [ ] (resolves at I7.4) `stage-i` fast-forward merge → `main` + `stage-i-complete` tag + push.

---

## Sub-step roadmap

### I0 — Stage entry (3 sub-steps)

- **I0.0a** (DONE — `9409d76`) `docs/STAGE_I_NOTES.md` — Stage I design freeze (I-D1—I-D8 LOCKED + I-D9 OPEN). Cursor §8e.1.
- **I0.0b** (DONE — `1404b2d`) `docs/STAGE_I_NOTES.md` — I-D9 LOCKED Option A + I-D10 LOCKED. Cursor §8e.1.
- **I0.0c** (THIS COMMIT) `docs/STAGE_I_PLAN.md` — initial sub-step roadmap + Decisions table + Completion Log. Cursor §8e.1.

### I1 — EmissionDistributor per-pool refactor (per I-D9; foundation; 8 sub-steps)

- **I1.1** `src/emission/IEmissionDistributor.sol` — interface signature updates: `auMTContract()` view replaced with `auMTContractByPool(address) → address`; `setAuMTContract(address)` → `setAuMTContractForPool(address, address)`; `NotAuMTContract(address)` error → `NotAuMTContract(address pool, address sender)`. Cursor §8e.1.
- **I1.2** `src/emission/EmissionDistributor.sol` — implement per-pool mapping: storage `auMTContract` → `mapping(address => address) public auMTContractByPool`; modifier `onlyAuMTContract` → `onlyAuMTContract(address pool)`; setter renamed; `recordDeposit` + `recordWithdrawal` modifier-update to take pool. Cursor §8e.1.
- **I1.3** `test/unit/EmissionDistributor.t.sol` — update ~100 unit tests: mock setup `setAuMTContractForPool(pool, mockAddr)`; assertion `auMTContractByPool(pool)`; revert `NotAuMTContract(pool, sender)` shape. Mechanical search-and-replace. Cursor §8e.1.
- **I1.4** `test/unit/AuMMDistributorIntegration.t.sol` — update 4 unit tests for new signature. Cursor §8e.1.
- **I1.5** `test/fork/StageHIntegrationFixture.sol` + 4 derived suites — update fork test fixture + StageHBootstrapPhaseTest accrue/distribute cohorts + StageHContinuousPhaseTest + StageHHalvingBoundaryTest + StageHCrossStackTest. Cursor §8e.1.
- **I1.6** `test/fork/DeployStageH.t.sol` — update 1 deploy fork test assertion. Cursor §8e.1.
- **I1.7** Regression run — 612/612 unit green + 10/10 fork green + 1/1 deploy fork green. User runs in terminal. No commit.
- **I1.8** Close-of-family sweep — PLAN Completion Log rows for I1.1—I1.7 + NOTES Findings entries if surfaced + status/mode refresh. Cursor §8e.1.

### I2 — AureumTime constants extension (per I-D10; 3 sub-steps)

- **I2.1** `src/lib/AureumTime.sol` — add `QUALIFICATION_PERIOD_BLOCKS = BLOCKS_PER_EPOCH` (= 100_800) + `ON_RAMP_PERIOD_BLOCKS = 180 * BLOCKS_PER_DAY` (= 1_296_000) `internal constant` declarations with NatSpec per I-D10. Cursor §8e.1.
- **I2.2** `test/unit/AureumTime.t.sol` — add constant-existence + value-assertion tests. Cursor §8e.1.
- **I2.3** Close-of-family sweep — PLAN Completion Log + status refresh.

### I3 — `src/token/AuMT.sol` concrete implementation (per I-D1, I-D3, I-D4, I-D6, I-D7, I-D11, I-D12; 11 sub-steps)

- **I3.1** AuMT.sol skeleton — pragma + imports + constructor (6 params per I-D11: pool_ / distributor_ / liquidityHook_ / genesisBlock_ / name_ / symbol_) + 4 immutable slot bindings (pool + distributor + liquidityHook + GENESIS_BLOCK) + IAuMT inheritance + ERC20 inheritance (name/symbol forwarded). Amended to 7 params + 5 immutables at I3.5-pre3 per I-D12. Cursor §8e.1.
- **I3.2** Soulbound overrides — `transfer` / `transferFrom` / `approve` revert `NotTransferable` per I-D1. Cursor §8e.1.
- **I3.3** mint() + burn() — `onlyLiquidityHook` gate (`NotLiquidityHook` revert per I-D4) + internal ERC20 `_mint` / `_burn`. Cursor §8e.1.
- **I3.4** qualificationBlock + lastDepositBlock state machine per I-D6. On mint: set qualificationBlock if zero, always update lastDepositBlock. On burn: reset qualificationBlock to 0. Cursor §8e.1.
- **I3.5-pre1** `docs/STAGE_I_NOTES.md` — I-D12 LOCK (gaugeRegistry 5th AuMT immutable; extends I-D11 6→7 args / 4→5 immutables; Option A direct-binding per EmissionDistributor.sol:L31 precedent). Cursor §8e.1.
- **I3.5-pre2** `docs/STAGE_I_PLAN.md` — Decisions table I-D12 row + §I3 header bump + I3.1 amendment pointer + I3.5-pre1/2/3 narrative insertion + anchors footer LOCKED-range refresh. Cursor §8e.1.
- **I3.5-pre3** `src/token/AuMT.sol` — add `IGaugeRegistry` import + `gaugeRegistry_` constructor arg (position 4) + `gaugeRegistry` immutable (slot 4) + ZeroAddress guard + assignment; section header updates to `/* ---------- Immutables (I-D11 / I-D12) ---------- */`. Cursor §8e.1.
- **I3.5** governanceWeight() — root-curve formula per I-D7 (qualification cliff + on-ramp cap + era transition + gauge check via I-D12 immutable `gaugeRegistry` + FixedPoint 18-decimal arithmetic). Cursor §8e.1.
- **I3.6** Distributor recorder integration — internal recordDeposit / recordWithdrawal calls post-mint/burn per H-D35 recorder semantics. Cursor §8e.1.
- **I3.7** `src/token/IAuMT.sol` NatSpec correction at L35 (mint) + L47-L48 (burn) — re: I-D4 access control. Two-edit targeted correction. Cursor §8e.1.
- **I3.8** Close-of-family sweep — PLAN Completion Log + status refresh.

### I4 — Extend `AureumFeeRoutingHook.sol` (per I-D5; 6 sub-steps)

- **I4.1** `getHookFlags()` bump — set `shouldCallAfterAddLiquidity = true` + `shouldCallAfterRemoveLiquidity = true`. Cursor §8e.1.
- **I4.2** `auMTByPool` storage slot + `setAuMTForPool(pool, auMT)` one-shot governance-gated setter + `AuMTBound(pool, auMT)` event + `AuMTAlreadyBound(pool)` error. Cursor §8e.1.
- **I4.3** `onAfterAddLiquidity` callback — dispatches `AuMT(auMTByPool[pool]).mint(sender, bptAmountOut)`. Returns true per BaseHooks signature. Cursor §8e.1.
- **I4.4** `onAfterRemoveLiquidity` callback — dispatches `AuMT(auMTByPool[pool]).burn(sender, bptAmountIn)`. Returns true. Cursor §8e.1.
- **I4.5** Stage D regression — full unit + fork cohort re-run green. User runs in terminal. No commit.
- **I4.6** Close-of-family sweep — PLAN Completion Log + status refresh.

### I5 — AuMT unit tests (`test/unit/AuMT.t.sol`; 7 sub-steps)

- **I5.1** Constructor + immutable slot tests — pool / distributor / liquidityHook binding; zero-address reverts. Cursor §8e.1.
- **I5.2** Soulbound tests — `transfer` / `transferFrom` / `approve` revert `NotTransferable` regardless of caller. Cursor §8e.1.
- **I5.3** mint/burn access tests — `NotLiquidityHook` revert on non-hook callers; happy-path from hook. Cursor §8e.1.
- **I5.4** qualificationBlock state machine tests — first mint sets clock; top-up doesn't reset; partial burn resets; re-deposit fresh. Cursor §8e.1.
- **I5.5** governanceWeight tests — qualification cliff; on-ramp cap; era transition (4th → 3rd root); gauge-revoked; zero balance. Cursor §8e.1.
- **I5.6** Distributor recorder integration tests — mocked distributor; assert recordDeposit/recordWithdrawal called with (pool, holder, amount). Cursor §8e.1.
- **I5.7** Close-of-family sweep — PLAN Completion Log + status refresh.

### I6 — Stage I fork integration tests (`test/fork/StageIIntegration.t.sol`; 6 sub-steps)

- **I6.1** StageIIntegrationFixture (inherits StageHIntegrationFixture per H13 lesson) — deploys 3 AuMT instances wired to 3 pilot pools at slots 02/03/07; binds hook extension; sets auMTByPool + auMTContractByPool. Cursor §8e.1.
- **I6.2** Multi-AuMT scenario tests — 3 holders deposit into 3 different pools; per-pool balance accounting; governance weight isolated per pool. Cursor §8e.1.
- **I6.3** Qualification clock tests — fork-state vm.roll past QUALIFICATION_PERIOD_BLOCKS. Cursor §8e.1.
- **I6.4** Halving boundary tests — vm.roll past `AureumTime.firstHalvingBlock(GENESIS_BLOCK)`; governance weight uses 3rd-root after boundary. Cursor §8e.1.
- **I6.5** Withdrawal-reset tests — partial 1% withdrawal triggers full clock reset; governance weight drops to zero immediately. Cursor §8e.1.
- **I6.6** Close-of-family sweep — PLAN Completion Log + status refresh.

### I7 — Stage I deploy script + close-of-stage (4 sub-steps)

- **I7.1** `script/DeployStageI.s.sol` — deploy 3 AuMT instances + setAuMTForPool ×3 on hook + setAuMTContractForPool ×3 on distributor + deployer→GOVERNANCE_MULTISIG handoff. Cursor §8e.1.
- **I7.2** `test/fork/DeployStageI.t.sol` (inherits StageIIntegrationFixture) — 9+ assertions on AuMT instances + hook wiring + distributor wiring + governance handoff. Cursor §8e.1.
- **I7.3** Close-of-family sweep + CLAUDE.md §11 refresh — Stage I close-out summary, Completion Log tail rows, Findings queue final state.
- **I7.4** Stage close — fast-forward merge stage-i → main + tag stage-i-complete + push. User runs in terminal.

### I8 — Gauge eligibility hook-gate (per I-D13 / OQ-24; Stage I add-on; 10 sub-steps)

Execution note: I8 runs now — before resuming the parked I4, and necessarily before I6, because it changes `GaugeEligibility`'s constructor (8 → 9 args) which the I6 `StageIIntegrationFixture` consumes transitively (G16 — land the ctor change before the fork fixtures are written). Numeric position is append-order; execution position is immediate. I7.4 stage-close gates on I8.

- **I8.0a** (DONE — `f2d9da4`) `docs/FINDINGS.md` — OQ-24 RESOLVED. Cursor §8e.1.
- **I8.0b** (DONE — `b09605c`) `docs/STAGE_I_NOTES.md` — I-D13 LOCKED. Cursor §8e.1.
- **I8.0c** `docs/STAGE_I_PLAN.md` — Decisions I-D13 row + this I8 roadmap. Cursor §8e.1.
- **I8.0d** `docs/STAGES_OVERVIEW.md` — gauge-eligibility criteria bullet adds the canonical-hook gate. Cursor §8e.1.
- **I8.1** `src/gauge/GaugeEligibility.sol` — `WrongFeeRoutingHook(address pool, address actualHook)` error + `feeRoutingHook` immutable + 9th constructor param `feeRoutingHook_` + ZeroAddress guard. Cursor §8e.1.
- **I8.2** `src/gauge/GaugeEligibility.sol` — `HooksConfig` import + hook check in `_checkEligibilityCriteria` (`IVault(vault).getHooksConfig(pool).hooksContract != feeRoutingHook` → revert `WrongFeeRoutingHook`). Cursor §8e.1.
- **I8.3** Construction-site updates per G16 — `test/fork/StageGIntegration.t.sol:211` plus 10 sites in `test/unit/GaugeEligibility.t.sol` (add 9th arg). Cursor §8e.1.
- **I8.4** `test/unit/GaugeEligibility.t.sol` — new tests: wrong-hook reject + no-hook reject + correct-hook admit (`vm.mockCall` on `getHooksConfig`). Cursor §8e.1.
- **I8.5** Regression — `forge clean && forge build` + full Stage F/G/H/I cohort green (split-form per D35; `--threads 1` fork per D36). User runs in terminal. No commit.
- **I8.6** Close-of-family sweep — Surfaces-produced rows (GaugeEligibility.sol + test files, actual diffs) + PLAN Completion Log + status refresh + CLAUDE.md §11. Cursor §8e.1.

---

## Completion log

Hash backfills occur at next close-of-family sweep when committed sub-step hash is known.

| Sub-step | Hash | Files | Sum diff | Notes |
| --- | --- | --- | --- | --- |
| I0.0a | `9409d76` | docs/STAGE_I_NOTES.md | +114 / 0 | Stage I design freeze (I-D1—I-D8 LOCKED + I-D9 OPEN); 114-line file landed (Cursor condensed; structural anchors verified) |
| I0.0b | `1404b2d` | docs/STAGE_I_NOTES.md | +22 / -7 | I-D9 LOCKED Option A (per-pool mapping in EmissionDistributor) + I-D10 LOCKED (AureumTime extension) |
| I0.0c | `984456a` | docs/STAGE_I_PLAN.md | +182 / 0 | PLAN creation: sub-step roadmap I0—I7 + Decisions table (I-D1—I-D10 LOCKED mirror) + Pre-flight checklist + Completion Log + Open questions + Anchors |
| I1.1 | `5ff9072` | src/emission/IEmissionDistributor.sol | +47 / -28 | Interface signature updates per I-D9: rename AuMTContractSet→AuMTContractBound event + amend NotAuMTContract(pool, caller) error + add AuMTAlreadyBound(pool) error + rename setAuMTContract→setAuMTContractForPool + rename auMTContract()→auMTContractByPool(pool) view; H-D16 zero-address safety valve removed |
| I1.1-fix1 | `46a93c7` | src/emission/IEmissionDistributor.sol | +1 / -1 | Stale L73 NatSpec cross-ref (AuMTContractSet → AuMTContractBound per I1.1 rename) — surfaced I10 default rule for rename §8e.1 NatSpec sweep |
| I1.2 | `c3147c1` | src/emission/EmissionDistributor.sol | +19 / -17 | Per-pool auMTContractByPool mapping per I-D9: storage slot + onlyAuMTContract(pool) modifier + setAuMTContractForPool one-shot setter (ZeroAddress + AuMTAlreadyBound guards) + recordDeposit/recordWithdrawal modifier annotation update |
| I1.2-fix1 | `1f9c74f` | src/emission/EmissionDistributor.sol | +5 / -5 | Stale NatSpec cross-refs at L19/L81/L100/L107/L191 (auMTContract single-slot → auMTContractByPool per I-D9) — five fixes; I10 default rule applied |
| I1.3 | `887b656` | test/unit/EmissionDistributor.t.sol | +27 / -20 | Update 8 tests + add AuMTAlreadyBound test per I-D9 (setUp binds POOL_A via setAuMTContractForPool; rename governance-gate/constructor-default/bind+emit tests; zero-address test inverts to ZeroAddress revert; new test_RevertWhen_SetAuMTContractForPoolAlreadyBound; NotAuMTContract reverts add POOL_A first arg; 100→101 tests) |
| I1.4 | `a20245a` | test/unit/AuMMDistributorIntegration.t.sol | +1 / -1 | setUp setAuMTContractForPool(POOL_A, AUMT_REC) per I-D9 |
| I1.5 | `009e591` | test/fork/StageHIntegration.t.sol | +4 / -2 | setAuMTContractForPool(pilotPools[0..2], address(this)) per I-D9 — expand single fixture recorder binding to all 3 pilot pools |
| I1.6 | `401f047` | test/fork/DeployStageH.t.sol | +7 / 0 | Add (3b-bis) assertion auMTContractByPool(bodenseePool)==address(0) post-deploy per H-D7 Option C + I-D9 deferred binding |
| I1.7 | (no commit — regression run) | — | — | Regression: 613/613 unit (+1 from I1.3 AuMTAlreadyBound test, was 612) + 10/10 fork integration (StageHBootstrapPhaseTest 7 + Continuous 1 + CrossStack 1 + HalvingBoundary 1) + 1/1 deploy fork; all green under D35 split-form + D36 --threads 1 + H-D40 canonical invocation |
| I1.8a | `44a94bb` | docs/STAGE_I_NOTES.md | +10 / -1 | I10 Findings entry: multi-file rename refactor NatSpec drift (I1.1-fix1 + I1.2-fix1 lessons; intra-file old-symbol grep rule) |
| I1.8b | `c33ea30` | docs/STAGE_I_PLAN.md | +11 / -1 | Completion Log catch-up — I0.0c hash backfill (`<pending>` → `984456a`; `+N` → `+182`) + 10 new rows I1.1—I1.8a (182 → 192 lines) |
| I1.8c | `6cf219f` | docs/STAGE_I_PLAN.md | +3 / -3 | Status header + Last update + Mode refresh (L3/L5/L7 in-place replacements; I1 family complete, I2/I3 ahead; 192 lines unchanged) |
| I1.8d | `be09f35` | CLAUDE.md | +33 / -29 | §11 refresh — Stage H→Stage I transition (Stage I in progress; I1 family COMPLETE 624/624 green; I1.8 sweep in flight; I10 housekeeping bullet after H13; 14 Stage I commit bullets) |
| I1.8e | `f978e58` | docs/STAGE_I_PLAN.md | +4 / 0 | Completion Log tail — append I1.8b/I1.8c/I1.8d rows + self-row to close I1 family Completion Log enumeration (192 → 196 lines) |
| I2.1 | `783bdf6` | src/lib/AureumTime.sol | +8 / 0 | QUALIFICATION_PERIOD_BLOCKS (= BLOCKS_PER_EPOCH) + ON_RAMP_PERIOD_BLOCKS (= 180 * BLOCKS_PER_DAY) constants per I-D10 — new // governance time periods (I-D10) sub-section between BLOCKS_PER_ERA and // index helpers; RHS uses named constants per single-source-of-truth (no literal 100_800 / 1_296_000); 83 → 91 lines |
| I2.2 | `552300c` | test/unit/AureumTime.t.sol | +18 / 0 | 4 I-D10 governance time period tests (2 value-assertion + 2 SSoT alias/derivation): test_qualificationPeriodBlocks_equals_100800, test_qualificationPeriodBlocks_equalsBlocksPerEpoch, test_onRampPeriodBlocks_equals_1296000, test_onRampPeriodBlocks_equals180TimesBlocksPerDay; new // --- I-D10 governance time periods --- sub-section between constant-value tests and index tests at boundaries; 178 → 196 lines; 37/37 AureumTime tests green via forge clean && forge test |
| I2.3a | `f143b7a` | docs/STAGE_I_NOTES.md | +8 / 0 | I11 Findings entry: Foundry forge test --match-test uses Rust regex; escaped pipe is literal not alternation, bare pipe is the alternation operator; default rule prefers --match-path filter for single-file scope and pairs with forge clean for F14 incremental-cache miss; I2.2 USER VERIFY lesson (138 → 146 lines) |
| I2.3b | `b651676` | docs/STAGE_I_PLAN.md | +5 / -1 | Completion Log catch-up — I1.8e hash backfill (`<pending>` → `f978e58`) + 4 new rows I2.1 / I2.2 / I2.3a + self-row (196 → 200 lines) |
| I2.3c | `bac5ff3` | docs/STAGE_I_PLAN.md | +3 / -3 | Status header + Last update + Mode refresh (L3/L5/L7 in-place replacements; I1+I2 families complete, I2.3d/e in flight, I3 ahead; 200 lines unchanged) |
| I2.3d | `b4b4b48` | CLAUDE.md | +17 / -13 | §11 refresh — I1+I2 families complete (HEAD bac5ff3; 16 Stage I commit bullets; I11 housekeeping bullet after I10; 611 → 615 lines) |
| I2.3e | `9ae7819` | docs/STAGE_I_PLAN.md | +3 / 0 | Completion Log tail — I2.3b hash backfill (`<pending>` → `b651676`) + I2.3c/I2.3d rows + self-row; closes I2.3 close-of-family sweep (200 → 203 lines) |
| I3.0a | `ca2596e` | docs/STAGE_I_NOTES.md | +11 / -1 | I-D11 LOCKED (AuMT constructor pattern — 6 args / 4 immutables: pool_/distributor_/liquidityHook_/genesisBlock_/name_/symbol_; ZeroAddress guards on address params; H13 avoidance via GENESIS_BLOCK as constructor immutable, not constructor-time external call to EmissionDistributor; name/symbol per-creator per Balancer BPT convention with ixXYZ for the 28 Miliarium pools) + I-D4 amendment (L35 mint + L47-L48 burn dual NatSpec scope at I3.7) (146 → 156 lines) |
| I3.0b | `efd8654` | docs/STAGE_I_PLAN.md | +5 / -4 | I-D11 row in Decisions table + 4 wording amendments (L25 IAuMT.sol +0/-2, L41 verbatim-preservation line L47-L48 mention, L106 I3.1 6-param constructor per I-D11, L112 I3.7 dual NatSpec scope) (203 → 204 lines) |
| I3.0c | `58790ca` | docs/STAGE_I_PLAN.md | +6 / -3 | Completion Log catch-up — I2.3e hash backfill (`<pending>` → `9ae7819`) + 3 new rows I3.0a/I3.0b/self + Anchors refresh (L195 I-D1—I-D11 + L201 L47-L48 mention); status/mode header refresh defers to I3.0d (204 → 207 lines) |
| I3.0d | `609d751` | docs/STAGE_I_PLAN.md | +3 / -3 | Status header + Last update + Mode refresh (L3/L5/L7 in-place replacements; I3.0 prep family complete; I3.1 AuMT.sol skeleton next; 207 lines unchanged) |
| I3.1 | `0bd199d` | src/token/AuMT.sol | +115 / 0 | AuMT skeleton landing per I-D11: pragma + 4 imports (ERC20, IERC20, IAuMT, IEmissionDistributor) + ZeroAddress error + 4 public immutables (pool, distributor, liquidityHook, GENESIS_BLOCK) + 6-arg constructor (pool_/distributor_/liquidityHook_/genesisBlock_/name_/symbol_) with 3 ZeroAddress guards on address params + stub bodies for mint/burn/governanceWeight; forge build green |
| I3.2 | `e068d4a` | src/token/AuMT.sol | +24 / 0 | Soulbound overrides per I-D1: NotTransferable error + transfer/transferFrom/approve unconditional reverts via ERC20+IERC20 dual-override syntax; forge build green |
| I3.3 | `7163c93` | src/token/AuMT.sol | +20 / -6 | mint/burn activation per I-D4: NotLiquidityHook(caller) error + onlyLiquidityHook modifier + _mint/_burn bodies in place of stub returns; forge build green |
| I3.4 | `a2a11bc` | src/token/AuMT.sol | +17 / -4 | I-D6 qualification clock: qualificationBlock + lastDepositBlock mappings + mint sets qualificationBlock if zero + always updates lastDepositBlock + burn unconditional qualificationBlock reset (any-amount withdrawal-reset rule per §ix verbatim); forge build green |
| I3.5-pre1 | `4a595e8` | docs/STAGE_I_NOTES.md | +12 / 0 | I-D12 LOCKED: gaugeRegistry as 5th AuMT immutable (extends I-D11 4→5 immutables, 6→7 constructor args); Option A direct-binding per EmissionDistributor.sol:L31 precedent; closes §12 ambiguity-gate fired at I3.5 pre-flight when I-D7 governanceWeight zero-branch required gaugeRegistry access not present in I-D11 tuple |
| I3.5-pre2 | `feab19d` | docs/STAGE_I_PLAN.md | +8 / -4 | I-D12 mirrored in PLAN: Decisions table row + §I3 11-sub-step header refresh + I3.1 amendment pointer + I3.5-pre1/2/3 narrative + Anchors I-D1—I-D12 |
| I3.5-pre3 | `4178fd9` | src/token/AuMT.sol | +15 / -3 | I-D12 landed in AuMT.sol: IGaugeRegistry import + gaugeRegistry 5th immutable (slot 4) + gaugeRegistry_ 7th constructor arg (position 4) + ZeroAddress guard + IGaugeRegistry cast-assignment; forge build green |
| I3.5 | `1daf212` | src/token/AuMT.sol | +41 / -4 | governanceWeight per I-D7 root-curve: AureumTime+FixedPoint imports + Constants (I-D7) section (FOURTH_ROOT_EXP=0.25e18, CUBE_ROOT_EXP=333_333_333_333_333_333) + 3-branch ZERO short-circuit (qualBlock==0 / pre-cliff / gauge-revoked) + on-ramp cap + era-boundary exponent selection (firstHalvingBlock) + FixedPoint.powDown active formula; forge build clean 0 warnings |
| I3.6 | `d96e7dd` | src/token/AuMT.sol | +6 / -3 | H-D35 recorder integration: IEmissionDistributor import + recordDeposit(pool,to,amount) post-_mint + recordWithdrawal(pool,from,amount) post-_burn (CEI ordering preserved); section header updated to "IAuMT implementations (I3.3 / I3.5 / I3.6)"; NatSpec tails refreshed; forge build green |
| I3.7 | `c285738` | src/token/IAuMT.sol | +3 / -3 | I-D4 NatSpec dual correction: mint L35 + burn L47-L48 — "NotDistributor"/"distributor only" → "NotLiquidityHook"/"liquidity hook only"; Cursor stripped trailing blank (75 → 74 lines; cosmetic); forge build green |
| I3.8a | `d11dbb7` | docs/STAGE_I_NOTES.md | +10 / 0 | I12 Findings entry: container-shape LOCKs must cross-check prior D* consumers; I-D11 4-immutable tuple LOCKed without grep-against I-D7 gaugeRegistry consumer; §12 ambiguity-gate fired at I3.5 pre-flight; I-D12 added as 5th immutable per Option A direct-binding (I3.5-pre1/2/3); default rule: before locking any container-shape decision, grep prior D* bodies for member-name references in consumer formulas |
| I3.8b | `c8360b9` | src/token/AuMT.sol | +17 / -17 | Contract-level NatSpec refresh: @notice + @dev rewritten to "I-D11 + I-D12 — 5 public immutable slots" + gaugeRegistry entry in immutables prose + "7-arg constructor: pool_/distributor_/liquidityHook_/gaugeRegistry_/genesisBlock_/name_/symbol_" + I5 invariant sentence broadened to cover both GENESIS_BLOCK and gaugeRegistry; scaffolding markers stripped ("lands at I3.2", "land at I3.3", "full implementation lands at I3.5", "I-D1 soulbound state machine ... land across I3.2—I3.6", "IAuMT NatSpec dual correction ... at I3.7"); 218 → 218 lines net 0; em-dash 24 → 23 |
| I3.8c | `38ac23b` | docs/STAGE_I_PLAN.md | +15 / -1 | Completion Log catch-up — I3.0c hash backfill (`<pending>` → `58790ca`) + 14 new rows I3.0d / I3.1 / I3.2 / I3.3 / I3.4 / I3.5-pre1 / I3.5-pre2 / I3.5-pre3 / I3.5 / I3.6 / I3.7 / I3.8a / I3.8b + self-row; closes I3 close-of-family Completion Log enumeration up to and including I3.8b (211 → 225 lines) |
| I3.8d | `6671a29` | docs/STAGE_I_PLAN.md | +3 / -3 | PLAN status header + Last update + Mode refresh (I3 family complete; I3.8 close-of-family sweep in flight; HEAD `38ac23b`; 3 in-place L3/L5/L7 replacements; 225 lines unchanged) |
| I3.8e | `5892143` | CLAUDE.md | +26 / -4 | §11 refresh: I3 COMPLETE; I-D1—I-D12 LOCKED (12 total); 36-bullet commit stack; I12 housekeeping bullet (container-shape LOCK §12 cross-check rule); HEAD `6671a29`; 615 → 637 lines |
| I3.8f | `0bafa19` | docs/STAGE_I_PLAN.md | +4 / -1 | Completion Log tail: I3.8c hash backfill (`<pending>` → `38ac23b`) + 3 new rows I3.8d / I3.8e + self-row; closes I3 close-of-family Completion Log enumeration (225 → 228 lines) |
| I8.0a | `f2d9da4` | docs/FINDINGS.md | +14 / 0 | OQ-24 (RESOLVED) — gauge eligibility requires canonical AureumFeeRoutingHook; WrongFeeRoutingHook error + feeRoutingHook 9th immutable + I-D13 cross-ref (1418 → 1432 lines) |
| I8.0b | `b09605c` | docs/STAGE_I_NOTES.md | +12 / 0 | I-D13 LOCKED — gauge eligibility hook-gate; 9th constructor immutable; AuMT scope correction (all gauged pools); fix-forward stage-i (178 → 190 lines) |
| I8.0c | `2589788` | docs/STAGE_I_PLAN.md | +16 / 0 | Decisions I-D13 row + I8 family roadmap (10 sub-steps; I8.0a/0b DONE markers) (228 → 244 lines) |
| I8.0d | `ac8ff94` | docs/STAGES_OVERVIEW.md | +1 / -1 | GaugeEligibility criteria bullet — canonical-hook gate (in-place L167 edit; 430 lines) |
| I8.1 | `20ee4bc` | src/gauge/GaugeEligibility.sol | +9 / -1 | feeRoutingHook immutable + WrongFeeRoutingHook error + 9th constructor param/guard/assignment (363 → 371 lines) |
| I8.2 | `189e949` | src/gauge/GaugeEligibility.sol | +2 / 0 | _checkEligibilityCriteria hook-gate — poolHook local + WrongFeeRoutingHook revert as fail-fast first check (371 → 373 lines) |
| I8.3a | `aee6c2f` | test/unit/GaugeEligibility.t.sol | +23 / -10 | feeRoutingHook fixture var + setUp + 9th arg on all 10 GaugeEligibility constructions |
| I8.3b | `a7b1bdd` | test/unit/GaugeEligibility.t.sol | +5 / 0 | IVaultExtension + HooksConfig imports + getHooksConfig vm.mockCall in setUp — all existing eligibility tests pass the gate (878 → 883 lines) |
| I8.3c | `10689c7` | test/fork/StageGIntegration.t.sol | +6 / -1 | HooksConfig import + 9th ctor arg address(hook) + Bodensee ForbiddenToken mock; fix1 abi.encodeWithSignature; forge build GREEN |
| I8.4 | `fc36d60` | test/unit/GaugeEligibility.t.sol | +38 / 0 | 3 hook-gate tests (wrong-hook + no-hook revert WrongFeeRoutingHook; correct-hook admits); 46 → 49 tests green |
| I8.5 | (no commit) | — | — | Full regression: forge clean + split-form per D35/D36; 619/620 unit (lone failure pre-I8 I4.1 getHookFlags artifact, deferred I4.5) + 71/71 fork green |
| I8.6a | `dcca7fe` | docs/STAGE_I_NOTES.md | +10 / 0 | I13 Findings — fail-fast gate blast-radius rule (size test retrofit at pre-flight; setUp-mock; Foundry longest-match) (190 → 200 lines) |
| I8.6b | `<pending>` | docs/STAGE_I_PLAN.md | +13 / 0 | Completion Log catch-up — I3.8f hash backfill (`<pending>` → `0bafa19`) + 13 new rows I8.0a—I8.6a + I8.5 no-commit + self-row |

---

## Open questions

Synced with STAGE_I_NOTES.md Open questions — pending entries become I-D* LOCK rows in the Decisions table once resolved.

- **OQ-I10** (deferred to Stage M/N) — Rollout of remaining 25 AuMT instances (slots 01/04/05/06/08—28). Out of Stage I scope per STAGES_OVERVIEW.md dependency graph.

---

## Anchors

- `docs/STAGE_I_NOTES.md` — Stage I design freeze (I-D1—I-D12 LOCKED).
- `docs/STAGE_H_NOTES.md` — H-D7 / H-D10 / H-D16 / H-D35 / H-D42 anchors for Stage I.
- `docs/FINDINGS.md` — OQ-3 / OQ-4 / OQ-5 / OQ-7 anchors for AureumTime constants + governance weight + qualification semantics.
- `04_tokenomics.md` §ix — AuMT spec (verbatim): 14-day qualification cliff, 6-month on-ramp, withdrawal-reset rule, F-9 dampening exponent transition.
- `11_formulas.md` F-9 — Dampening exponent (4th → 3rd root at first halving block).
- `src/lib/AureumTime.sol` — block-number constants per C-D3.
- `src/token/IAuMT.sol` — H6.0c-locked interface (NatSpec corrections at L35 mint + L47-L48 burn land at I3.7).
- `src/fee_router/AureumFeeRoutingHook.sol` — Stage D-locked surface (extended in-place per I-D5 at I4).
- `src/emission/EmissionDistributor.sol` — Stage H-locked surface (per-pool mapping refactor per I-D9 at I1).
- `src/ccb/IGaugeRegistry.sol` — `isGaugeApproved(pool)` consumed at I-D7 governanceWeight zero-rule.
