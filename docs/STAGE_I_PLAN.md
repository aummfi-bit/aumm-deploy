# Stage I — Plan & Sub-Step Roadmap

> **Status:** I1 — EmissionDistributor per-pool refactor (per I-D9; foundation) and I2 — AureumTime constants extension (per I-D10) complete on `stage-i` (branched from `stage-h-complete` at `2a33649`; HEAD `b651676`) — interface signature updates + per-pool mapping implementation + 4 test files refactored across I1.1—I1.6; I1.7 regression 624/624 green (613/613 unit + 10/10 fork integration + 1/1 deploy fork) under D35 split-form + D36 --threads 1 + H-D40 canonical invocation; I1.8 close-of-family sweep landed; I2.1 + I2.2 added QUALIFICATION_PERIOD_BLOCKS + ON_RAMP_PERIOD_BLOCKS constants + 4 I-D10 tests (37/37 AureumTime green via forge clean && forge test); I2.3a—I2.3b close-of-family sweep landed (NOTES I11 Findings + PLAN Completion Log catch-up). I-D1—I-D10 Decisions LOCKED at I0.0b; I10 + I11 Findings entries landed. Companion to STAGE_I_NOTES.md.
>
> **Last update:** 2026-05-26 — I2.3c PLAN status header + Last update + Mode refresh (this commit). I2 close-of-family sweep in flight: I2.3a NOTES I11 Findings (`f143b7a`) + I2.3b PLAN Completion Log catch-up (`b651676`) + I2.3c PLAN status/mode refresh this commit; I2.3d CLAUDE.md §11 refresh + I2.3e PLAN Completion Log tail pending.
>
> **Mode:** Opus high continues per §13 stage-level defaults. I2 family completing in I2.3 sweep (PLAN / NOTES / CLAUDE.md housekeeping; Sonnet-friendly per §13 Sonnet beats). Next family is I3 — AuMT.sol concrete implementation — the next Opus-high focus block (soulbound ERC-20 state machine + I-D7 root-curve formula + I-D6 qualification clock + I-D4 onlyLiquidityHook access + I-D1 NotTransferable reverts).
>
> **Audience:** Sagix plus any future Claude session that needs the operational roadmap for Stage I sub-step execution. NOTES (STAGE_I_NOTES.md) is the running design-decision log; this file is the sub-step sequence + Completion Log + grep-verifiable checkpoint catalog.

---

## Stage scope

Stage I implements AuMT (Aureum Market Tessera) — the per-pool LP-receipt token. One soulbound ERC-20 contract per Miliarium pool (3 instances at Stage I pilot; 28 at full deployment per Stages M/N). AuMT tracks per-holder governance weight via a root-curve formula over (balance × time_in_pool_capped), with a 14-day qualification cliff, 6-month on-ramp cap, era-boundary exponent transition (4th root → 3rd root), and gauge-revoked → zero rule. Mint/burn dispatch flows through the existing `AureumFeeRoutingHook` (extended in-place per I-D5 to add `onAfterAddLiquidity` / `onAfterRemoveLiquidity` callbacks). The shared `EmissionDistributor` recorder slot extends from single-slot to per-pool mapping (per I-D9 Option A) to support the multi-AuMT architecture.

### Surfaces produced at Stage I

| File | Status | Sub-step | LOC estimate |
| --- | --- | --- | --- |
| `src/emission/IEmissionDistributor.sol` | EDITED | I1.1 | +5 / -3 |
| `src/emission/EmissionDistributor.sol` | EDITED | I1.2 | +20 / -10 |
| `src/lib/AureumTime.sol` | EDITED | I2.1 | +10 / 0 |
| `src/token/AuMT.sol` | NEW | I3.1—I3.7 | ~250 |
| `src/token/IAuMT.sol` | EDITED | I3.7 | +0 / -1 (NatSpec correction at L35) |
| `src/fee_router/AureumFeeRoutingHook.sol` | EDITED | I4.1—I4.4 | +60 / 0 |
| `test/unit/EmissionDistributor.t.sol` | EDITED | I1.3 | mechanical signature updates |
| `test/unit/AuMMDistributorIntegration.t.sol` | EDITED | I1.4 | mechanical signature updates |
| `test/fork/StageHIntegrationFixture.sol` + 4 derived suites | EDITED | I1.5 | mechanical signature updates |
| `test/fork/DeployStageH.t.sol` | EDITED | I1.6 | assertion update |
| `test/unit/AureumTime.t.sol` | EDITED | I2.2 | +6 lines (constant assertions) |
| `test/unit/AuMT.t.sol` | NEW | I5.1—I5.6 | ~600 |
| `test/fork/StageIIntegration.t.sol` | NEW | I6.1—I6.5 | ~400 |
| `script/DeployStageI.s.sol` | NEW | I7.1 | ~150 |
| `test/fork/DeployStageI.t.sol` | NEW | I7.2 | ~200 |

### Surfaces NOT produced at Stage I

- Stage M/N AuMT rollout for remaining 25 pilot pools (slots 01/04/05/06/08—28) — out of Stage I scope per STAGES_OVERVIEW.
- AuMM.setMinter handoff — deferred to Stage K per H-D7 Option C.
- IAuMT.sol skeleton at H6.0c preserved verbatim except for the L35 NatSpec correction at I3.7 (re: I-D4 access control re-NatSpec'd from "callable by the bound distributor only" to "callable by the bound liquidity hook only").

---

## Decisions

Mirror of STAGE_I_NOTES.md Decisions table (LOCKED at I0.0a—I0.0b). Future I-D11 onward attach to sub-step-specific locks during I1—I7 execution and are recorded as new entries in both this table and the NOTES file.

| # | Status | Decision | Anchor | Locked at |
| --- | --- | --- | --- | --- |
| I-D1 | LOCKED | AuMT is soulbound — transfer/transferFrom/approve revert `NotTransferable` | §ix withdrawal-reset rule; spec silence on transfer = soulbound intent | I0.0a |
| I-D2 | LOCKED | 1 AuMT contract per Miliarium pool (3 pilot @ Stage I; 28 @ full) | H-D35; CLAUDE.md §1; IAuMT.sol L67 NatSpec | I0.0a |
| I-D3 | LOCKED | 18 decimals matching pool BPT | Balancer V3 BPT convention; Stage E pilot pool deploys | I0.0a |
| I-D4 | LOCKED | mint + burn access: `onlyLiquidityHook` — bound AureumFeeRoutingHook only | Hook owns LP deposit/withdrawal moment; distributor is downstream consumer | I0.0a |
| I-D5 | LOCKED | Extend `AureumFeeRoutingHook.sol` in-place at I4 — `getHookFlags` bump + `onAfterAddLiquidity` / `onAfterRemoveLiquidity` + `auMTByPool` + `setAuMTForPool` | Balancer V3 one-hook-per-pool constraint; nested-call precedent at L408-431 | I0.0a |
| I-D6 | LOCKED | Qualification clock — first-deposit start; top-up doesn't reset; withdrawal resets to 0 | §ix verbatim "Remove any amount... time_in_pool resets" | I0.0a |
| I-D7 | LOCKED | `governanceWeight` = (balance × time_in_pool_capped)^(1/4 Era 0; 1/3 Era 1+); ZERO if unqualified OR ungauged | §ix verbatim formula; F-9 dampening; AureumTime C-D3 era boundary; FINDINGS OQ-7 gauge-revoked rule | I0.0a |
| I-D8 | LOCKED | Stage I scope — 3 pilot AuMT + FeeRoutingHook extension; Stage M/N deferred | Stage E pilot pools; out-of-scope rollout per STAGES_OVERVIEW | I0.0a |
| I-D9 | LOCKED | Multi-AuMT routing — per-pool mapping in EmissionDistributor (Option A); `auMTContractByPool` + `onlyAuMTContract(pool)` modifier + `setAuMTContractForPool(pool, addr)` | H-D16 single-slot baseline; H-D10 per-pool recorder precedent; I-D2 per-pool topology | I0.0b |
| I-D10 | LOCKED | `AureumTime.sol` extension — `QUALIFICATION_PERIOD_BLOCKS = BLOCKS_PER_EPOCH` (100_800) + `ON_RAMP_PERIOD_BLOCKS = 180 * BLOCKS_PER_DAY` (1_296_000) | C-D3 canonical time library; §ix verbatim "14 days" + "day 180" | I0.0b |

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

### I3 — `src/token/AuMT.sol` concrete implementation (per I-D1, I-D3, I-D4, I-D6, I-D7; 8 sub-steps)

- **I3.1** AuMT.sol skeleton — pragma + imports + constructor + immutable slot bindings (pool address + distributor address + liquidityHook address) + IAuMT inheritance + ERC20 inheritance. Cursor §8e.1.
- **I3.2** Soulbound overrides — `transfer` / `transferFrom` / `approve` revert `NotTransferable` per I-D1. Cursor §8e.1.
- **I3.3** mint() + burn() — `onlyLiquidityHook` gate (`NotLiquidityHook` revert per I-D4) + internal ERC20 `_mint` / `_burn`. Cursor §8e.1.
- **I3.4** qualificationBlock + lastDepositBlock state machine per I-D6. On mint: set qualificationBlock if zero, always update lastDepositBlock. On burn: reset qualificationBlock to 0. Cursor §8e.1.
- **I3.5** governanceWeight() — root-curve formula per I-D7 (qualification cliff + on-ramp cap + era transition + gauge check + FixedPoint 18-decimal arithmetic). Cursor §8e.1.
- **I3.6** Distributor recorder integration — internal recordDeposit / recordWithdrawal calls post-mint/burn per H-D35 recorder semantics. Cursor §8e.1.
- **I3.7** `src/token/IAuMT.sol` NatSpec correction at L35 — re: I-D4 access control. One-line targeted edit. Cursor §8e.1.
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
| I2.3e | `<pending>` | docs/STAGE_I_PLAN.md | +3 / 0 | Completion Log tail — I2.3b hash backfill (`<pending>` → `b651676`) + I2.3c/I2.3d rows + self-row; closes I2.3 close-of-family sweep (200 → 203 lines) |

---

## Open questions

Synced with STAGE_I_NOTES.md Open questions — pending entries become I-D* LOCK rows in the Decisions table once resolved.

- **OQ-I10** (deferred to Stage M/N) — Rollout of remaining 25 AuMT instances (slots 01/04/05/06/08—28). Out of Stage I scope per STAGES_OVERVIEW.md dependency graph.

---

## Anchors

- `docs/STAGE_I_NOTES.md` — Stage I design freeze (I-D1—I-D10 LOCKED).
- `docs/STAGE_H_NOTES.md` — H-D7 / H-D10 / H-D16 / H-D35 / H-D42 anchors for Stage I.
- `docs/FINDINGS.md` — OQ-3 / OQ-4 / OQ-5 / OQ-7 anchors for AureumTime constants + governance weight + qualification semantics.
- `04_tokenomics.md` §ix — AuMT spec (verbatim): 14-day qualification cliff, 6-month on-ramp, withdrawal-reset rule, F-9 dampening exponent transition.
- `11_formulas.md` F-9 — Dampening exponent (4th → 3rd root at first halving block).
- `src/lib/AureumTime.sol` — block-number constants per C-D3.
- `src/token/IAuMT.sol` — H6.0c-locked interface (NatSpec correction at L35 lands at I3.7).
- `src/fee_router/AureumFeeRoutingHook.sol` — Stage D-locked surface (extended in-place per I-D5 at I4).
- `src/emission/EmissionDistributor.sol` — Stage H-locked surface (per-pool mapping refactor per I-D9 at I1).
- `src/ccb/IGaugeRegistry.sol` — `isGaugeApproved(pool)` consumed at I-D7 governanceWeight zero-rule.
