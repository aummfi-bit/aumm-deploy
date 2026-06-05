# Stage I — Plan & Sub-Step Roadmap

> **Status:** Code phase open — I9 (AuMT deprecation + IVotingWeight migration) COMPLETE (I9.1—I9.5f) + I4 (recorder dispatch + clock) COMPLETE. Per OQ-25 / I-D14, AuMT is the pool's own Balancer V3 BPT, not a separate token; Stage I is the oracle-free **recorder clock + hook dispatch** only. Decisions I-D1—I-D17 LOCKED: I-D14 (AuMT = BPT), I-D15 (value-weighted view deferred to a Stage K `VotingWeight.sol`), I-D16 (hook one-shot `emissionRecorder` slot), I-D17 (`IVotingWeight` forward stub + `VaultClassRegistry` full-rename fix-forward); I-D1—I-D4 / I-D11 / I-D12 SUPERSEDED + I-D5—I-D9 AMENDED by I-D14. I3 (concrete `AuMT.sol`) TOMBSTONED — superseded, removed at I9.4. I1 (I-D9), I2 (I-D10), I8 (I-D13) complete pre-reframe, unchanged. Findings I10—I17. Vault bytecode untouched. Next: I5 (recorder-clock unit tests) → I6 (fork integration) → I7 (deploy + close-of-stage). Companion to STAGE_I_NOTES.md.
>
> **Last update:** 2026-06-05 — I4 family (recorder dispatch + clock) COMPLETE: I4.1 `getHookFlags` bump (`409f51a`) → I4.2 `emissionRecorder` slot + `setEmissionRecorder` two-flag lock (`3f8e8d5`, +I4.2-post `961af69`) → I4.3 `effectiveQualBlock` clock (`5fb3c3f`) → I4.4 `onAfterAddLiquidity` + `IRouterSender` Permit2-free shim (`c47e6df`, via I4.4a `62f7741`) → I4.5 `onAfterRemoveLiquidity` (`2b85263`) → I4.6a/b/c regression + post-I4.2 storage-slot-layout fix (`5e63b3b` / `56bc143`; 620/620 unit + 71/71 fork green) → I4.7a/b Findings I16/I17 + Completion Log catch-up (`1bd2248` / `7fb2991`). I4.7c status refresh this commit; I4.7d CLAUDE §11 pending. Code phase continues at I5 (recorder-clock unit tests).
>
> **Mode:** Opus high per §13 stage-level defaults. I4 (recorder dispatch + clock) COMPLETE. Code phase continues: I5 (recorder-clock unit tests `test/unit/RecorderClock.t.sol` — first-deposit clock-set / weighted-average top-up / reset-on-any-withdrawal / hook-gate access per I-D14) → I6 (fork integration `test/fork/StageIIntegration.t.sol`) → I7 (deploy + close-of-stage). Entry mode Opus high for the I5 test-harness design (the `effectiveQualBlock` weighted-average + over-qualification vectors), dropping to Sonnet for repetitive test-case bodies per §13.
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
| `src/emission/EmissionDistributor.sol` | EDITED again | I4 | +~25 / 0 — `effectiveQualBlock` per-(pool, user) clock: weighted-average top-up + reset-on-any-withdrawal inside `recordDeposit` / `recordWithdrawal`, alongside the existing `userLP` amount |
| `src/lib/AureumTime.sol` | EDITED | I2.1 | +10 / 0 |
| `src/token/AuMT.sol` | DELETED | I-reframe (deprecation) | — I3 scaffold `git rm`'d; AuMT is the BPT per OQ-25 / I-D14 |
| `src/token/IAuMT.sol` | DELETED | I-reframe (deprecation) | — removed per I-D15 (amended by I-D17 — `VaultClassRegistry` consumer migrated to `IVotingWeight`) |
| `src/fee_router/AureumFeeRoutingHook.sol` | EDITED | I4.1—I4.5 | +~35 / 0 |
| `src/gauge/GaugeEligibility.sol` | EDITED | I8.1—I8.2 | +11 / -1 |
| `src/governance/IVotingWeight.sol` | NEW | I9.1 | ~20 |
| `src/gauge/VaultClassRegistry.sol` | EDITED | I9.2 | +~8 / -~8 — full rename: `auMT`→`votingWeight` / `setAuMT`→`setVotingWeight` / `auMTSetter`→`votingWeightSetter` / `OnlyAuMTSetter`→`OnlyVotingWeightSetter` per I-D17 |
| `test/unit/EmissionDistributor.t.sol` | EDITED | I1.3 | mechanical signature updates |
| `test/unit/AuMMDistributorIntegration.t.sol` | EDITED | I1.4 | mechanical signature updates |
| `test/fork/StageHIntegrationFixture.sol` + 4 derived suites | EDITED | I1.5 | mechanical signature updates |
| `test/fork/DeployStageH.t.sol` | EDITED | I1.6 | assertion update |
| `test/unit/AureumTime.t.sol` | EDITED | I2.2 | +6 lines (constant assertions) |
| `test/unit/RecorderClock.t.sol` | NEW | I5.1—I5.5 | ~400 |
| `test/fork/StageIIntegration.t.sol` | NEW | I6.1—I6.5 | ~350 |
| `script/DeployStageI.s.sol` | NEW | I7.1 | ~80 |
| `test/fork/DeployStageI.t.sol` | NEW | I7.2 | ~120 |
| `test/unit/GaugeEligibility.t.sol` | EDITED | I8.3a—I8.4 | +66 / -10 |
| `test/fork/StageGIntegration.t.sol` | EDITED | I8.3c | +6 / -1 |
| `test/fork/mocks/StageGMocks.sol` | EDITED | I9.3a | +0 / -~15 — `MockAuMT`→`MockVotingWeight is IVotingWeight`; drop IERC20 boilerplate stubs |
| `test/unit/VaultClassRegistry.t.sol` | EDITED | I9.3b | +0 / -~15 — `MockAuMT`→`MockVotingWeight is IVotingWeight`; drop IERC20 boilerplate stubs; update `setAuMT` wiring |

### Surfaces NOT produced at Stage I

- No AuMT token contracts deployed — AuMT is the pool's own Balancer V3 BPT per OQ-25 / I-D14; `src/token/AuMT.sol` + `src/token/IAuMT.sol` are deleted at the I-reframe deprecation sub-step (no soulbound mirror, no token mint/burn, no per-pool token rollout, no Stage M/N AuMT instances).
- `src/governance/VotingWeight.sol` value-weighted voting view — deferred out of Stage I per I-D15 (its `ITVLOracle` value source is a forward stub until OQ-22 / F-D3; snapshot voting is a Stage K concern; the future reader carries its own interface).
- AuMM.setMinter handoff — deferred to Stage K per H-D7 Option C.

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
| I-D15 | LOCKED (amended by I-D17) | Voting-weight value-weighted view DEFERRED out of Stage I (deps downstream — `ITVLOracle` concrete = OQ-22/F-D3; snapshot layer = Stage K); Stage I ships the recorder clock + hook dispatch only; `src/token/AuMT.sol` + `src/token/IAuMT.sol` DELETED | OQ-25 (view-location sub-point L1314); I-D14; `ITVLOracle` deferred (OQ-22/F-D3); Stage K snapshot layer | I-reframe.3b |
| I-D16 | LOCKED | Hook→recorder reference = one-shot settable `emissionRecorder` slot + `setEmissionRecorder` on `AureumFeeRoutingHook` (mirrors `setGovernanceModule`), NOT a constructor immutable (deploy ordering Stage D < Stage H = H13-class; avoids G16 ripple to 5 ctor sites); old per-pool `auMTByPool` / `setAuMTForPool` dropped | I-D14 hook dispatch; I-D9 distributor-side bind; H13 deploy ordering; G16; `setGovernanceModule` one-shot precedent | I-reframe.3c |
| I-D17 | LOCKED | `IAuMT.sol` deletion (I-D15) has a live Stage-G consumer — `VaultClassRegistry.vetoProposal` reads `governanceWeight` + `totalSupply` via `IAuMT`. Introduce minimal `src/governance/IVotingWeight.sol` (`governanceWeight(address)→uint256` + `totalSupply()→uint256`, not `is IERC20`); full-rename re-point of `VaultClassRegistry` (`auMT`→`votingWeight` / `setAuMT`→`setVotingWeight` / `auMTSetter`→`votingWeightSetter` / `OnlyAuMTSetter`→`OnlyVotingWeightSetter`) + 2 `MockAuMT`→`MockVotingWeight` doubles; fix-forward on `stage-i` (Stage G tag untouched) | I-D15; G-D9 veto-weight; `VaultClassRegistry.sol` L85/L208-211/L277/L279; G16 consumer sweep; I8 fix-forward precedent | I-reframe.3c2-pre1 |

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

### I3 — `src/token/AuMT.sol` concrete implementation — SUPERSEDED by I-D14 / I-D15 / I-D17 (built pre-reframe; removed at I9)

I3.1—I3.8f built a concrete soulbound-ERC-20 `AuMT.sol` (skeleton → soulbound overrides → `mint` / `burn` → qualification-block state machine → `governanceWeight` root curve → distributor recorder integration; 115 → 218 lines) plus targeted `IAuMT.sol` NatSpec corrections, per the pre-reframe design (I-D1 / I-D3 / I-D4 / I-D6 / I-D7 / I-D11 / I-D12). The full sub-step detail is preserved in the Completion Log below and in git history at the I3.1—I3.8f commits.

The I-reframe reckoning supersedes that work: per I-D14 AuMT is the pool's own Balancer V3 BPT, not a separate token, so the concrete `AuMT.sol` has no place; per I-D15 the token-named `IAuMT.sol` goes with it; per I-D17 `IAuMT`'s one live consumer (Stage-G `VaultClassRegistry`) migrates to a minimal `IVotingWeight` reader first. The deletion + migration is **I9**. The logic this section built is not lost — the qualification clock relocates to the EmissionDistributor recorder (I4) and the value-weighted governance view is deferred to a `src/governance/VotingWeight.sol` reader (I-D15), each on the oracle-appropriate side. No live sub-steps remain under I3.

### I4 — Recorder dispatch + clock (`AureumFeeRoutingHook` + `EmissionDistributor`; per I-D14 / I-D16; 7 sub-steps)

- **I4.1** (DONE — `409f51a`) `getHookFlags()` bump — `shouldCallAfterAddLiquidity = true` + `shouldCallAfterRemoveLiquidity = true`. Cursor §8e.1.
- **I4.2** `src/fee_router/AureumFeeRoutingHook.sol` — one-shot `emissionRecorder` reference per I-D16, a full byte-parallel mirror of the hook's `setGovernanceModule` two-flag lock (slots L102 / L114, ctor seed L200, setter L214-222): adds `address public emissionRecorder` + `address private _emissionRecorderAdmin` (seeded `= moduleAdmin_` in the ctor body — no ctor-signature change, preserving I-D16's no-G16-ripple), the admin-gated one-shot `setEmissionRecorder(address recorder)` setter (`msg.sender == _emissionRecorderAdmin` → `emissionRecorder == 0` → `recorder != 0`; sets the slot, zeros the admin, emits), the `EmissionRecorderSet(address indexed recorder)` event, and two errors `NotEmissionRecorderAdmin` (admin gate) + `EmissionRecorderAlreadySet` (second-call gate); the existing `ZeroAddress` error is reused for the zero guard. No `auMTByPool` / `setAuMTForPool` (dropped per I-D16). Cursor §8e.1.
- **I4.3** `src/emission/EmissionDistributor.sol` — `effectiveQualBlock` per-(pool, user) clock per I-D14 (I-D6 semantics relocated from the deleted `AuMT.sol`). Adds `mapping(address => mapping(address => uint256)) public effectiveQualBlock` to the per-user state block (`public`, no interface getter — the Stage K view's typed access is deferred per I-D15). In `recordDeposit`, guarded by `amount > 0` and placed BEFORE `userLP[pool][user] += amount`: if `effectiveQualBlock[pool][user] == 0` fresh-start `= block.number`, else weighted-average `= (oldAmount * effectiveQualBlock[pool][user] + amount * block.number) / (oldAmount + amount)` where `oldAmount = userLP[pool][user]` (pre-increment). In `recordWithdrawal`, guarded by `amount > 0`: `effectiveQualBlock[pool][user] = 0` (§viii "remove any amount — even 1% — drops to zero"). The fresh-start branch keys on `effectiveQualBlock == 0` (NOT `oldAmount == 0`) so a re-deposit after a PARTIAL withdrawal (`userLP > 0`, clock already reset to 0) restarts at `block.number` instead of computing a near-zero weighted average that would instantly over-qualify the un-aged remaining capital. The `amount > 0` guard makes zero-amount deposits/withdrawals clock-neutral and guarantees `effectiveQualBlock > 0 ⟹ oldAmount > 0`, so the weighted-average denominator is never zero. Plain `uint256` block-number arithmetic — no FixedPoint (block numbers + raw LP amounts, not 18-decimal ratios); integer truncation < 1 block, favorable-to-protocol. No new event or error. Cursor §8e.1.
- **I4.4** `src/fee_router/AureumFeeRoutingHook.sol` — `onAfterAddLiquidity` callback override (placed after `onAfterSwap`; `public override onlyVault returns (bool, uint256[] memory)`) dispatching `IEmissionDistributor(emissionRecorder).recordDeposit(pool, lp, bptAmountOut)` where `lp = IRouterSender(router).getSender()`. The full Balancer `IRouterCommon` is NOT imported — it transitively imports `permit2/src/interfaces/IAllowanceTransfer.sol`, and this project neither vendors nor remaps Permit2 (D32 — Aureum's fork init avoids the Router and Permit2 entirely); I4.4a instead adds a minimal `src/fee_router/IRouterSender.sol` shim declaring only `getSender()` (ABI selector identical to `IRouterCommon`, so the runtime call against the real Router is byte-identical). Adds two imports: `IRouterSender` from `src/fee_router/IRouterSender.sol` + `IEmissionDistributor` from `src/emission/IEmissionDistributor.sol`. Recorder-unset guard per I-D16 deploy ordering — the dispatch is wrapped in `if (emissionRecorder != address(0))` and the callback returns `(true, amountsInRaw)` unchanged whether or not it dispatches: `getHookFlags` (I4.1) calls this on every add-liquidity for any hooked pool, but `emissionRecorder` stays unbound through Stages D—H (it is bound only at I6/I7), so an unguarded dispatch into `address(0)` would revert every add-liquidity in the Stage E—H fork cohort and in the pre-binding production window. Mirrors the `onAfterSwap` trusted-router early-return spirit; no amount adjustment — `amountsInRaw` passes through. Cursor §8e.1.
- **I4.5** `onAfterRemoveLiquidity` callback — dispatches `recordWithdrawal(pool, lp, bptAmountIn)` on `emissionRecorder`. Returns true. Cursor §8e.1.
- **I4.6** (a/b/c) Stage D regression — I4.6a renamed + fixed the getHookFlags test (`test_getHookFlags_shouldCallAfterSwapOnly` → `test_getHookFlags_afterSwapAndLiquidityCallbacks`, clearing the I4.1 flag-bump artifact, `5e63b3b`); I4.6b ran the full unit + fork cohort (D35/D36 split-form, `--threads 1`); I4.6c synced the hook test's storage-slot constants to the post-I4.2 six-slot layout (`SLOT_GOV_ADMIN` 2→3, `SLOT_INC_ADMIN` 3→4, per I17, `56bc143`). 620/620 unit + 71/71 fork green. User ran in terminal.
- **I4.7** (a/b/c/d) Close-of-family sweep — I4.7a NOTES Findings I16/I17 (`1bd2248`); I4.7b PLAN Completion Log catch-up + I9.5f hash backfill (`7fb2991`); I4.7c PLAN status/mode + Anchors refresh + I4.6 bullet rename fix; I4.7d CLAUDE §11 resume-anchor refresh.
- **Deferred from I4:** `setEmissionRecorder`'s unit-level two-flag-lock revert tests (`NotEmissionRecorderAdmin` / `EmissionRecorderAlreadySet` / `ZeroAddress`) mirroring the `setGovernanceModule` AlreadySet tests in `test/unit/AureumFeeRoutingHook.t.sol` — fork-covered at I6.1 (happy-path bind) + I7.2 (second-call revert); the unit-level revert-path coverage is deferred to a hook-test extension (I7-adjacent or post-Stage-I).

### I5 — Recorder-clock unit tests (`test/unit/RecorderClock.t.sol`; 5 sub-steps)

- **I5.1** First-deposit clock-set — `recordDeposit(pool, lp, amount)` from the bound recorder sets `effectiveQualBlock[pool][lp]` to `block.number` when previously zero; `userLP[pool][lp]` accrues the amount. Cursor §8e.1.
- **I5.2** Weighted-average top-up — a second `recordDeposit` blends `effectiveQualBlock` by the deposit-weighted average per I-D14 (a top-up advances the clock proportionally, not a full reset); assert the blended block + accrued `userLP`. Cursor §8e.1.
- **I5.3** Reset-on-any-withdrawal — `recordWithdrawal(pool, lp, amount)` of any nonzero amount resets `effectiveQualBlock[pool][lp]` to 0 per I-D6 / I-D14 (qualification lost on any exit); assert reset + `userLP` decrement. Cursor §8e.1.
- **I5.4** Hook-gate access — `recordDeposit` / `recordWithdrawal` revert `NotAuMTContract(pool, caller)` when called by a non-bound address; happy-path admits the address bound via `setAuMTContractForPool(pool, hook)` (I-D9). Cursor §8e.1.
- **I5.5** Close-of-family sweep — PLAN Completion Log + status refresh. Note: the value-weighted-view tests (qualification cliff, on-ramp cap, era transition, gauge-revoked) are deferred out of Stage I with `src/governance/VotingWeight.sol` per I-D15. Cursor §8e.1.

### I6 — Recorder-clock fork integration (`test/fork/StageIIntegration.t.sol`; 5 sub-steps)

- **I6.1** `StageIIntegrationFixture` (inherits `StageHIntegrationFixture` per H13) — `setEmissionRecorder(distributor)` on the canonical `AureumFeeRoutingHook` (I-D16) + `setAuMTContractForPool(pilotPool, hook)` ×3 binding the recorder gate to the hook (I-D9 amend); no AuMT deploys. Cursor §8e.1.
- **I6.2** Deposit-dispatch — a real Balancer V3 add-liquidity to each of the 3 pilot pools routes through `onAfterAddLiquidity` → `recordDeposit`, setting `effectiveQualBlock` + accruing `userLP` on the EmissionDistributor; per-pilot-pool isolation (the 3 pools track independently). Cursor §8e.1.
- **I6.3** Top-up — a second add-liquidity to a pool blends `effectiveQualBlock` by the deposit-weighted average per I-D14; assert the blended block. Cursor §8e.1.
- **I6.4** Aging + withdrawal-reset — `vm.roll` past `QUALIFICATION_PERIOD_BLOCKS` after a deposit (assert `block.number − effectiveQualBlock ≥ QUALIFICATION_PERIOD_BLOCKS`, the raw input the deferred view will threshold), then a real remove-liquidity → `onAfterRemoveLiquidity` → `recordWithdrawal` resets `effectiveQualBlock` to 0 even on a fully-aged position. Cursor §8e.1.
- **I6.5** Close-of-family sweep — PLAN Completion Log + status refresh.

### I7 — Stage I deploy script + close-of-stage (4 sub-steps)

- **I7.1** `script/DeployStageI.s.sol` — wire the recorder path (no AuMT deploys): `setEmissionRecorder(distributor)` ×1 on the canonical `AureumFeeRoutingHook` (I-D16) + `setAuMTContractForPool(pilotPool, hook)` ×3 on the EmissionDistributor (I-D9 amend) + deployer→GOVERNANCE_MULTISIG handoff. AuMM + hook + distributor are Stage inputs per H-D42, not deploy artifacts. Cursor §8e.1.
- **I7.2** `test/fork/DeployStageI.t.sol` (inherits `StageIIntegrationFixture`) — assertions: `hook.emissionRecorder() == distributor`; `distributor.auMTContractByPool(pilotPool) == hook` ×3; one-shot setters revert on second call; deployer→GOVERNANCE_MULTISIG handoff; no AuMT-token assertions. Cursor §8e.1.
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

### I9 — AuMT deprecation + `IVotingWeight` consumer migration (per I-D14 / I-D15 / I-D17; I-reframe code phase; 5 sub-steps)

Execution note: I9 is the code-phase removal of the pre-reframe AuMT token. I3.1—I3.8f built a concrete soulbound `AuMT.sol` (115 → 218 lines) + `IAuMT.sol` NatSpec corrections; per I-D14 (AuMT = the pool's BPT) that token has no place, and per I-D15 the token-named interface goes with it. I-D17 found `IAuMT`'s one live consumer — Stage-G `VaultClassRegistry` (veto-weight per G-D9) — so the deletion is gated behind migrating that consumer to a correctly-named `IVotingWeight` reader (Stage-G fix-forward; Stage G tag untouched). I9 runs first in the code phase — the clean removal of the dead token before the I4 hook/recorder rewrite; the two are independent (post-reframe I4 calls the EmissionDistributor, not AuMT), so the order is a convenience, not a constraint. The concrete `AuMT.sol` is preserved in git history at the I3.1—I3.8f commits.

- **I9.1** `src/governance/IVotingWeight.sol` (NEW) — minimal forward-stub interface: `governanceWeight(address holder) → uint256` + `totalSupply() → uint256`; NOT `is IERC20`; NatSpec marks it the voting-weight reader surface that the deferred `src/governance/VotingWeight.sol` (Stage K) implements per I-D15. First file under `src/governance/`. Cursor §8e.1.
- **I9.2** `src/gauge/VaultClassRegistry.sol` (EDITED — Stage-G fix-forward) — full rename per I-D17: import `IVotingWeight` (drop `IAuMT`); `IAuMT auMT` → `IVotingWeight votingWeight` slot; `setAuMT` → `setVotingWeight`; `auMTSetter` → `votingWeightSetter`; `OnlyAuMTSetter` → `OnlyVotingWeightSetter`; constructor param + NatSpec; the two call sites (`votingWeight.governanceWeight(msg.sender)` / `votingWeight.totalSupply()`). Cursor §8e.1.
- **I9.3** `test/fork/mocks/StageGMocks.sol` + `test/unit/VaultClassRegistry.t.sol` + `test/fork/StageGIntegration.t.sol` (EDITED) — migrate the `MockAuMT is IAuMT` doubles → `MockVotingWeight is IVotingWeight` (4-member shrink: drop `balanceOf` / `allowance` / `transfer` / `approve` / `transferFrom` / `mint` / `burn` / `distributor` / `pool`) and all `setAuMT` → `setVotingWeight` consumers. Landed as three sub-steps per the mirror invariant + the I15 tree-wide-enumeration miss: **I9.3a** the two mirror-synced mock contracts (StageGMocks + VaultClassRegistry.t embed, byte-identical per `StageGMocks.sol:L10`) + VaultClassRegistry.t functional refs; **I9.3b** `test/fork/StageGIntegration.t.sol` — the consumer the assumed-files pre-flight missed (`import`, `MockVotingWeight` var, `setVotingWeight`; build green here); **I9.3c** cosmetic full rename (var / fixture / test-method names / `makeAddr` seeds). Cursor §8e.1 ×3.
- **I9.4** `git rm src/token/AuMT.sol src/token/IAuMT.sol` — remove both files; nothing references them after I9.1—I9.3. User stages + commits in terminal (git mutation per §8b); `forge clean && forge build` + full Stage F/G/H/I unit + fork cohort green confirms no dangling reference (split-form per D35; `--threads 1` fork per D36).
- **I9.5** Close-of-family sweep — PLAN Completion Log rows (I9.1—I9.4) + an I3.1—I3.8f superseded-marker line + status/mode refresh + NOTES Findings if surfaced + CLAUDE.md §11. Cursor §8e.1.

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
| I8.6b | `74b3add` | docs/STAGE_I_PLAN.md | +13 / 0 | Completion Log catch-up — I3.8f hash backfill (`<pending>` → `0bafa19`) + 13 new rows I8.0a—I8.6a + I8.5 no-commit + self-row |
| I8.6c | `0dc3798` | docs/STAGE_I_PLAN.md | +3 / 0 | Surfaces-produced rows — GaugeEligibility.sol + GaugeEligibility.t.sol + StageGIntegration.t.sol (257 → 260 lines) |
| I8.6d | `2d6fc8f` | docs/STAGE_I_PLAN.md | +3 / -3 | Status / Last update / Mode refresh (I8 COMPLETE; I4 PARKED at I4.2; 260 lines unchanged) |
| I8.6e | `50f51d7` | CLAUDE.md | +2 / -2 | §11 Last update + Branch refresh (I3 COMPLETE; I8 hook-gate COMPLETE; I-D1—I-D13 LOCKED; 637 lines unchanged) |
| I-reframe.2 | `60faad2` | docs/STAGE_I_NOTES.md | +16 / 0 | I-D14 LOCKED — AuMT = branded BPT (no separate ERC-20); value-weighted snapshot voting; recorder clock; first reckoning (200 → 216 lines) |
| I-reframe.2-fix1 | `8c58de6` | docs/STAGE_I_NOTES.md | +9 / -5 | I-D14 complete reckoning — add I-D2/I-D8/I-D9/I-D11/I-D12 + fix I-D5 header slip (6 superseded, 5 amended, 2 untouched; 216 → 220 lines) |
| I-reframe.2-fix2 | `15c9a35` | docs/STAGE_I_NOTES.md | +13 / -9 | Decisions table — 9 status cells flipped (SUPERSEDED/AMENDED by I-D14) + I-D11—I-D14 rows; 14 rows (220 → 224 lines) |
| I-reframe.3a | `4156160` | docs/STAGE_I_PLAN.md | +12 / -11 | Decisions table — 11 status cells flipped + I-D14 row; 14 rows; mirrors NOTES (260 → 261 lines) |
| I-reframe.3b-pre1 | `dbcc92d` | docs/STAGE_I_NOTES.md | +13 / 0 | I-D15 LOCKED — voting-weight view deferred out of Stage I; clock-only; AuMT.sol/IAuMT.sol deletion; 15 I-D rows (224 → 237 lines) |
| I-reframe.3b | `dc07257` | docs/STAGE_I_PLAN.md | +1 / 0 | Decisions table — I-D15 row; 15 rows; mirrors NOTES (261 → 262 lines) |
| I-reframe.3c-pre1 | `9f33163` | docs/STAGE_I_NOTES.md | +13 / 0 | I-D16 LOCKED — hook→recorder one-shot `emissionRecorder` slot (not ctor immutable; H13/G16 avoided); auMTByPool/setAuMTForPool dropped; 16 I-D rows (237 → 250 lines) |
| I-reframe.3c-pre2 | `da70271` | docs/STAGE_I_PLAN.md | +1 / 0 | Decisions table — I-D16 row; 16 rows; mirrors NOTES (262 → 263 lines) |
| I-reframe.3c1a | `25f0cb8` | docs/STAGE_I_PLAN.md | +1 / -1 | Stage scope paragraph — clock-only AuMT-is-BPT framing (no AuMT.sol; effectiveQualBlock; emissionRecorder slot; VotingWeight view deferred; I1/I2/I8 unchanged; 263 lines unchanged) |
| I-reframe.3c1b | `09bfc34` | docs/STAGE_I_PLAN.md | +10 / -9 | Surfaces produced/NOT produced tables rewritten — clock-only; AuMT.sol+IAuMT.sol DELETED; RecorderClock.t.sol; VotingWeight deferred (263 → 264 lines) |
| I-reframe.3c2-pre1 | `118b8e7` | docs/STAGE_I_NOTES.md | +13 / 0 | I-D17 LOCKED — IVotingWeight forward stub + VaultClassRegistry full-rename fix-forward + IAuMT consumer-migration (NOTES 250 → 263 lines) |
| I-reframe.3c2-pre1b | `4a4b1d8` | docs/STAGE_I_NOTES.md | +2 / -2 | I-D15 Status cell amended by I-D17 + "deletion is total" paragraph → IVotingWeight consumer-migration pointer (NOTES 263 lines unchanged) |
| I-reframe.3c2-pre2 | `f894c82` | docs/STAGE_I_NOTES.md | +10 / 0 | I14 Findings — interface-deletion LOCKs must grep consumers at lock-time (I-D15 "no implementor" miss; extends I12+G16; NOTES 263 → 273 lines) |
| I-reframe.3c2-pre3 | `5a4c66c` | docs/STAGE_I_PLAN.md | +2 / -1 | Decisions table — I-D15 Status amended by I-D17 + I-D17 row; 17 rows (264 → 265 lines) |
| I-reframe.3c2a | `d16365d` | docs/STAGE_I_PLAN.md | +10 / 0 | I9 family roadmap — AuMT deprecation + IVotingWeight migration (5 sub-steps; 265 → 275 lines — commit msg's "278" was an inferred-count slip, corrected here) |
| I-reframe.3c2b | `0bf7eef` | docs/STAGE_I_PLAN.md | +5 / -13 | I3 section tombstone — SUPERSEDED by I-D14/I-D15/I-D17; removed at I9; 2-para body (275 → 267 lines) |
| I-reframe.3c2c | `1990479` | docs/STAGE_I_PLAN.md | +5 / -1 | Surfaces table — IAuMT.sol reason + 4 I9 rows (IVotingWeight.sol/VaultClassRegistry.sol/StageGMocks/VaultClassRegistry.t; 267 → 271 lines) |
| I-reframe.3c3 | `c327d22` | docs/STAGE_I_PLAN.md | +9 / -8 | I4 section — recorder dispatch + clock header + bullets (emissionRecorder/effectiveQualBlock/recordDeposit/recordWithdrawal; 7 sub-steps; 271 → 272 lines) |
| I-reframe.3c4 | `c8c24be` | docs/STAGE_I_PLAN.md | +7 / -9 | I5 section — AuMT-unit-tests → recorder-clock unit tests (RecorderClock.t.sol; set/top-up/reset/hook-gate; 5 sub-steps; view-tests deferred per I-D15; 272 → 270 lines) |
| I-reframe.3c5 | `d338109` | docs/STAGE_I_PLAN.md | +7 / -8 | I6 section — AuMT-instance fork tests → recorder-clock fork integration (setEmissionRecorder/recordDeposit/effectiveQualBlock; 5 sub-steps; 270 → 269 lines) |
| I-reframe.3c6 | `a1a1bbd` | docs/STAGE_I_PLAN.md | +2 / -2 | I7.1+I7.2 — recorder-wiring deploy script (setEmissionRecorder + setAuMTContractForPool; no AuMT deploys; 269 lines unchanged) |
| I-reframe.3c7a | `784f6b0` | docs/STAGE_I_NOTES.md | +4 / -3 | Interfaces Produced table — 2 stale AuMT rows → 3 reframed (IVotingWeight/recorder-dispatch/recorder-clock; NOTES 273 → 274 lines) |
| I-reframe.3c7b | `1e638bd` | docs/STAGE_I_NOTES.md | +4 / -5 | Interfaces Consumed table — 5 stale rows → 2 reframed (hook pre-I4/Balancer base) + Deferred-consumers note (NOTES 274 → 273 lines) |
| I-reframe.3c8a | `c2a7964` | docs/STAGE_I_PLAN.md | +3 / -3 | Status/Last update/Mode headers — I-reframe doc sweep COMPLETE; I-D1—I-D17; code phase I9→I4→I5/I6→I7 next (269 lines unchanged) |
| I-reframe.3c8b | `ac216f7` | docs/STAGE_I_PLAN.md | +10 / -9 | Anchors — 10 stale bullets → 11 reframed (IVotingWeight.sol + VaultClassRegistry added; IAuMT.sol removed; effectiveQualBlock; 269 → 270 lines) |
| I-reframe.3c8c-1 | `db45a96` | docs/STAGE_I_PLAN.md | +12 / -1 | Completion Log — I8.6b hash backfill + 11 rows (I8.6c/d/e + I-reframe.2 through 3c-pre2; 270 → 281 lines) |
| I-reframe.3c8c-2 | `5d1fda9` | docs/STAGE_I_PLAN.md | +9 / 0 | Completion Log — 9 rows (I-reframe.3c1a through 3c2c; 281 → 290 lines) |
| I-reframe.3c8c-3 | `fe1a014` | docs/STAGE_I_PLAN.md | +11 / 0 | Completion Log — 10 rows (I-reframe.3c3 through 3c8c-2) + self-row; closes the I-reframe Completion Log catch-up (290 → 301 lines) |
| I-reframe.3c8d-1 | `f163d1c` | CLAUDE.md | +2 / -2 | §11 Last update + Branch paragraphs refreshed — I-reframe COMPLETE; I-D1—I-D17; recorder clock; code phase next (657 lines unchanged) |
| I-reframe.3c8d-2 | `d7b6f51` | CLAUDE.md | +11 / -58 | §11 commit stack condensed to 7 phase-summary bullets + PLAN Completion Log pointer (657 → 610 lines) |
| I-reframe.3c8d-3 | `cdcded8` | CLAUDE.md | +2 / -2 | §11 Stage I position + Next sub-step paragraphs refreshed — reframe COMPLETE; I9.1 code-phase opens (610 lines unchanged) |
| I-reframe.3c8d-4 | `9d52ca6` | CLAUDE.md | +3 / -2 | §11 Deferred bullets — aumm-site (I-D14—I-D17) + OQ-I10 (BPT model) + new VotingWeight.sol view bullet (610 → 611 lines) |
| I-reframe.3c8d-5 | `6140c7f` | docs/STAGE_I_PLAN.md | +6 / -1 | Completion Log — I-reframe.3c8c-3 hash backfill + 4 CLAUDE.md §11 rows (3c8d-1—4) + self-row; closes the I-reframe doc-sweep record (301 → 306 lines) |
| I9.1 | `16e1d5c` | src/governance/IVotingWeight.sol | +41 / 0 | NEW — forward-stub voting-weight reader interface (governanceWeight + totalSupply; NOT is IERC20) per I-D17; first file under src/governance/; forge build green |
| I9.2 | `77a9164` | src/gauge/VaultClassRegistry.sol | +19 / -19 | Full rename IAuMT→IVotingWeight per I-D17 (13 sites; zero AuMT survivors); build red until I9.3 — the I15 mid-migration transient |
| I9.3a | `25c4793` | test/fork/mocks/StageGMocks.sol + test/unit/VaultClassRegistry.t.sol | +13 / -77 | Both MockAuMT→MockVotingWeight mirror-synced (byte-identical; 4-member shrink) + VaultClassRegistry.t functional refs; mirror invariant per StageGMocks.sol:L10 |
| I9.3b | `ad9783e` | test/fork/StageGIntegration.t.sol | +4 / -4 | The I15-missed consumer — import + var type + setVotingWeight; build GREEN |
| I9.3c | `476e77e` | test/unit/VaultClassRegistry.t.sol + test/fork/StageGIntegration.t.sol | +33 / -33 | Cosmetic full rename — mockVotingWeight / votingWeightSetter / INITIAL_VOTING_WEIGHT_SUPPLY / 4 test methods / 7 makeAddr seeds; build green |
| I9.4 | `0b5e572` | src/token/AuMT.sol + src/token/IAuMT.sol (deleted) | 0 / -292 | git rm both files (the I3.1—I3.8f concrete build) per I-D14/I-D15; tree-wide deletion pre-flight clean (I15 applied); 619/620 unit (pre-existing I4.1 artifact) + 71/71 fork green |
| I9.5a | `6f3fa30` | docs/STAGE_I_NOTES.md | +10 / 0 | I15 Findings — rename/deletion pre-flight must grep whole tree (I9.2 StageGIntegration miss; extends G16+I10) (273 → 283 lines) |
| I9.5b | `8d84adb` | docs/STAGE_I_PLAN.md | +1 / -1 | I9.3 bullet corrected — 3 files + a/b/c split + I15 reference (306 lines unchanged) |
| I9.5c | `825f94a` | docs/STAGE_I_PLAN.md | +9 / -1 | Completion Log — I-reframe.3c8d-5 hash backfill + 8 rows I9.1—I9.5b + self-row (306 → 315 lines) |
| I9.5d | `66afa4a` | docs/STAGE_I_PLAN.md + docs/STAGE_I_NOTES.md | +5 / -5 | PLAN status/mode headers (L3/L5/L7) + I9.5c self-row hash backfill; NOTES OQ-I10 recorder-binding reframe (both files line-count unchanged) |
| I9.5e | `90a34f1` | CLAUDE.md | +8 / -7 | §11 resume-anchor refresh — I9 COMPLETE + I4.2 next; Last update / Branch / commit-stack (+ I9 bullet) / Stage-I-position / Next-sub-step (611 → 612 lines) |
| I9.5f | `23cb192` | docs/STAGE_I_PLAN.md | +4 / -1 | Completion Log — I9.5d / I9.5e rows + self-row + Anchors `Findings I10—I14` → `I10—I15` fix; closes I9 family Completion Log (315 → 318 lines) |
| I4.1 | `409f51a` | src/fee_router/AureumFeeRoutingHook.sol | +2 / 0 | getHookFlags() bump per I-D5 — shouldCallAfterAddLiquidity + shouldCallAfterRemoveLiquidity = true (568 → 570); landed early (ancestor of I9.5f), logged here to close the I4-family catalog gap; the resulting afterSwap-only test failure was the 619/620 artifact cleared at I4.6a |
| docs §11 | `ba8b18c` | CLAUDE.md | +1 / -1 | §11 L447 AureumFeeRoutingHook path fix (src/gauge/ → src/fee_router/); ad-hoc housekeeping preceding the I4.2 resumption |
| I4.2-pre | `cc10a40` | docs/STAGE_I_PLAN.md | +1 / -1 | I4.2 bullet — admin-gated two-flag emissionRecorder lock spelled out; resolves PLAN ambiguity (L127) |
| I4.2 | `3f8e8d5` | src/fee_router/AureumFeeRoutingHook.sol | +45 / 0 | emissionRecorder one-shot slot + _emissionRecorderAdmin + setEmissionRecorder + 2 errors + event; mirrors setGovernanceModule two-flag lock per I-D16 (570 → 615) |
| I4.2-post | `961af69` | src/fee_router/AureumFeeRoutingHook.sol | +7 / -5 | contract @dev invariant — two admin slots → three + emissionRecorder pair in the post-state invariant (615 → 617) |
| I4.3-pre | `e756168` | docs/STAGE_I_PLAN.md | +1 / -1 | I4.3 bullet — exact effectiveQualBlock algorithm + fresh-start-on-zero rationale (L128; resolves the partial-withdrawal over-qualification vector) |
| I4.3 | `5fb3c3f` | src/emission/EmissionDistributor.sol | +30 / 0 | effectiveQualBlock per-(pool, user) clock per I-D14 — mapping + fresh-start/weighted-average deposit + reset-on-any-withdrawal (500 → 530) |
| I4.4-pre | `8af75b5` | docs/STAGE_I_PLAN.md | +1 / -1 | I4.4 bullet — lp = getSender() + IRouterCommon/IEmissionDistributor imports + recorder-unset guard rationale (L129) |
| I4.4-pre2 | `9667586` | docs/STAGE_I_PLAN.md | +1 / -1 | I4.4 bullet — IRouterCommon → IRouterSender shim + D32/Permit2-avoidance rationale (L129; per I16) |
| I4.4a | `62f7741` | src/fee_router/IRouterSender.sol | +20 / 0 | minimal getSender() shim — Permit2-free IRouterCommon substitute per D32 / I16 |
| I4.4 | `c47e6df` | src/fee_router/AureumFeeRoutingHook.sol | +30 / 0 | onAfterAddLiquidity → emissionRecorder.recordDeposit(pool, lp, bptAmountOut) with recorder-unset guard + IRouterSender/IEmissionDistributor imports (617 → 647) |
| I4.5 | `2b85263` | src/fee_router/AureumFeeRoutingHook.sol | +26 / -1 | onAfterRemoveLiquidity → emissionRecorder.recordWithdrawal(pool, lp, bptAmountIn) + RemoveLiquidityKind import (647 → 672) |
| I4.6a | `5e63b3b` | test/unit/AureumFeeRoutingHook.t.sol | +3 / -3 | getHookFlags test rename → afterSwapAndLiquidityCallbacks + assertTrue for the add/remove-liq flags; clears the I4.1 619/620 artifact |
| I4.6b | (no commit) | — | — | Stage D full regression — unit split-form + fork --threads 1 per D35/D36; surfaced the I4.2 storage-slot-shift setUp failure (→ I4.6c); the renamed flags test passes |
| I4.6c | `56bc143` | test/unit/AureumFeeRoutingHook.t.sol | +11 / -6 | sync storage-slot constants to the post-I4.2 six-slot layout (SLOT_GOV_ADMIN 2→3, SLOT_INC_ADMIN 3→4) + messages + layout NatSpec; 620/620 unit + 71/71 fork green (per I17) |
| I4.7a | `1bd2248` | docs/STAGE_I_NOTES.md | +20 / 0 | Findings I16 (Permit2 transitive import → IRouterSender shim) + I17 (storage slot shift breaks vm.load/store constants) (283 → 303) |
| I4.7b | `<pending>` | docs/STAGE_I_PLAN.md | +18 / -1 | Completion Log — I9.5f hash backfill (23cb192) + 16 rows (I4.1 / docs §11 / I4.2-pre through I4.7a, incl. I4.6b no-commit) + self-row; closes I4 family Completion Log (318 → 335) |

---

## Open questions

Synced with STAGE_I_NOTES.md Open questions — pending entries become I-D* LOCK rows in the Decisions table once resolved.

- **OQ-I10** (deferred to Stage M/N) — Rollout of remaining 25 AuMT instances (slots 01/04/05/06/08—28). Out of Stage I scope per STAGES_OVERVIEW.md dependency graph.

---

## Anchors

- `docs/STAGE_I_NOTES.md` — Stage I design log (I-D1—I-D17; the I-reframe AuMT=BPT reckoning at I-D14—I-D17; Findings I10—I17).
- `docs/STAGE_H_NOTES.md` — H-D7 / H-D10 / H-D16 / H-D35 / H-D42 anchors for Stage I.
- `docs/FINDINGS.md` — OQ-3 / OQ-4 / OQ-5 / OQ-7 (AureumTime constants + qualification semantics) + OQ-24 (gauge hook-gate) + OQ-25 (AuMT = BPT) anchors.
- `04_tokenomics.md` §viii / §ix — AuMT-as-BPT + value-weighted voting (§viii, I-D14); withdrawal-reset + qualification clock (§ix); 14-day cliff + 6-month on-ramp + F-9 dampening consumed by the deferred view per I-D15.
- `11_formulas.md` F-9 — Dampening exponent (4th → 3rd root at first halving block); consumed by the deferred `VotingWeight.sol` view, not the Stage I clock.
- `src/lib/AureumTime.sol` — block-number constants per C-D3; `QUALIFICATION_PERIOD_BLOCKS` + `ON_RAMP_PERIOD_BLOCKS` per I-D10 (I2.1).
- `src/governance/IVotingWeight.sol` — NEW forward-stub reader (`governanceWeight` + `totalSupply`) per I-D17 (I9.1); implemented by the deferred `VotingWeight.sol` (Stage K).
- `src/gauge/VaultClassRegistry.sol` — Stage G veto consumer; full-rename `IAuMT` → `IVotingWeight` per I-D17 (I9.2).
- `src/fee_router/AureumFeeRoutingHook.sol` — Stage D-locked surface; recorder dispatch extension (`emissionRecorder` + liquidity callbacks) per I-D16 at I4.
- `src/emission/EmissionDistributor.sol` — Stage H-locked surface; per-pool mapping per I-D9 (I1) + `effectiveQualBlock` clock per I-D14 (I4).
- `src/ccb/IGaugeRegistry.sol` — `isGaugeApproved(pool)`; the I-D7 governanceWeight gauge-gate is deferred with the `VotingWeight.sol` view per I-D15.
