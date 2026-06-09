# Stage K — Plan & Sub-Step Roadmap

> **Status:** K2 in progress on `stage-k` — K0—K1 complete (K1 = `AureumGovernanceAuthorizer` `73ceaae` + 12-green unit `e72104c`); K2.0a landed K-D4 LOCKED reuse-direct (`3e8250d`); this commit lands K2.0b (PLAN K-D4 mirror + K2 documentation-only framing). K2 produces no code surface; K3 `VotingWeight` pre-flight next. K-D1—K-D4 LOCKED; K-D5—K-D9 forward-declared per K-D2. Companion to STAGE_K_NOTES.md.
>
> **Last update:** 2026-06-08 — K2.0b PLAN (this commit): K-D4 mirror flipped to LOCKED + K2 marked documentation-only (no code surface) + Completion Log catch-up (K1.0b—K2.0b).
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
| `src/governance/AureumGovernance.sol` | NEW | K4 | ~500 |
| `test/unit/AureumGovernance.t.sol` | NEW | K4 | ~600 |
| `test/fork/StageKIntegration.t.sol` | NEW | K4 / K7 | ~300 |
| `src/emission/TVLOracle.sol` | EDIT (fix-forward) | K6 | roster re-wire |
| `script/DeployAuMM.s.sol` | NEW | K7 | ~30 |
| `script/DeployStageK.s.sol` | NEW | K7 | ~120 |
| `test/fork/DeployStageK.t.sol` | NEW | K7 | ~150 |

### Surfaces NOT produced at Stage K

- No D33 Aureum Router (deferred to Stage O per K-D1).
- No OQ-20 / OQ-21 yield-fee entry point (stays deferred).
- No Vault edits — byte-identical preserved; migration is `setAuthorizer` + `setStaticSwapFeePercentage` calls only.
- No AuMM or EmissionDistributor contract edits — `setMinter` (K5) is a deploy-script call.
- No interface change to `IGaugeRegistry` / `IMiliariumSlotRegistry` — consumed as-is.

---

## Decisions

Mirror of STAGE_K_NOTES.md Decisions table (K-D1 + K-D2 LOCKED at K0.2; K-D3 LOCKED at K1 pre-flight; K-D4 LOCKED at K2 pre-flight; K-D5—K-D9 forward-declared, each locking at its unit pre-flight).

| # | Status | Decision | Anchor | Locked at |
| --- | --- | --- | --- | --- |
| K-D1 | LOCKED | Stage K scope = tight governance handoff, seven dependency-ordered units K1—K7. D33 Aureum Router DEFERRED to Stage O; OQ-20 / OQ-21 controller yield-fee leg stays DEFERRED (user scope decision 2026-06-07). New contracts: `AureumGovernanceAuthorizer` (K1), `VotingWeight` (K3), `AureumGovernance` (K4). New scripts: `script/DeployAuMM.s.sol` (H-D42), `script/DeployStageK.s.sol` (K7). Fix-forward edit to tagged contract: `TVLOracle` roster re-wire (K6, J-D8, I13-class). `AuMM.setMinter` is a deploy-script call (K5, H-D41) — no AuMM contract edit. | STAGES_OVERVIEW Stage K; OQ-10; user scope decision 2026-06-07; H-D41 / H-D42 / J-D8 carry-forward | K0.2 |
| K-D2 | LOCKED | Dependency-ordered build sequence: K1 `AureumGovernanceAuthorizer` → K2 TVL-oracle binding → K3 `VotingWeight` → K4 `AureumGovernance` → K5 `setMinter` handoff → K6 `TVLOracle` re-wire → K7 deploy + migration. Each unit's deep design locks at its own Opus pre-flight as a new K-D entry (K-D3 onward), NOT at K0.2 — F-12 deposit math, F-9 dampening, the snapshot mechanism, and the `VotingWeight` value-curve each need a focused beat reading the canonical formulas. The §12 ambiguity-gate fires fresh at each unit pre-flight. | Stage K size vs Stage J; J-D8 precedent; §12 ambiguity-gate; §13 per-unit Opus pre-flight | K0.2 |
| K-D3 | LOCKED | `AureumGovernanceAuthorizer` per OQ-10 — `is IAuthorizer`, no new Aureum interface (external surface is `canPerform` + public-immutable getters). Constructor `(governanceContract_, emergencyMultisig_, vault_)` all zero-checked; immutables `GOVERNANCE_CONTRACT` / `EMERGENCY_MULTISIG` / `EMERGENCY_WINDOW_END_BLOCK` + two `bytes32` emergency action IDs; constant `EMERGENCY_WINDOW_BLOCKS = 2_628_000`. `EMERGENCY_WINDOW_END_BLOCK = block.number + EMERGENCY_WINDOW_BLOCKS` (from construction block). Emergency set = {`pauseVault`, `enableRecoveryMode`} (user 2026-06-07; `disableQuery` dropped — permanent defensive-config, not crisis-response). Action IDs computed locally H13-safe; disambiguator = Vault address (verified `Authentication.sol:51` + `VaultAdmin.sol:77`). `canPerform`: governance → true; multisig ∧ emergency ∧ `block.number < END_BLOCK` → true; else false. | OQ-10 (FINDINGS L722-794); `Authentication.sol:51` / `VaultAdmin.sol:77` encoding; `IVaultAdmin` selectors; Stage B `AureumAuthorizer.sol`; user decision 2026-06-07 | K1 |
| K-D4 | LOCKED | TVL-oracle binding for vote-weighting = **reuse-direct**. `ITVLOracle` already exposes `tvl(address pool) → uint256` (svZCHF, 18-dec; `ITVLOracle.sol` L14, implemented at `TVLOracle.sol` L211) — exactly the whole-pool valuation K3 `VotingWeight` multiplies by BPT share (`holderValue = tvl(pool) × balanceOf(holder) / totalSupply()`; BPT reads direct off the pool per I-D14). No adapter, no new K2 contract, no `IVotingWeight` change — `VotingWeight` takes an `ITVLOracle` immutable and calls `tvl(pool)`; injection lands at K3. Single shared `TVLOracle` instance (emission `EfficiencyOracle` + governance; one roster, one `setGovernanceContract` handoff); deploy ordering at K-D9. K6 `_constellationRatio` re-wire is signature-stable (does not touch `tvl` ABI). | OQ-22 (FINDINGS L1106); `src/ccb/ITVLOracle.sol` L14; `src/emission/TVLOracle.sol` L211; I-D14 (AuMT=BPT); K-D9 | K2 |
| K-D5 | forward-declared | `VotingWeight` value-weighted view — `(qualified_AuMT_value × time_in_pool_capped)^(1/4 → 1/3)` over the `EmissionDistributor` recorder clock; 14-day cliff, 6-month on-ramp, F-9 era root, gauged-only; `is IVotingWeight` (I9.1 stub). I-D17 `totalSupply()` denominator = total qualified voting weight (pre-flight recommendation), fixing the veto-bps semantic. | I-D15; I-D17; OQ-25; `src/governance/IVotingWeight.sol`; F-9 | K3 |
| K-D6 | forward-declared | `AureumGovernance` three proposal types (gauge challenge F-12 / composition challenge / fee proposal) + F-9 dampening + snapshot voting + timelock. Sub-splits K-D6a—K-D6f at K4 pre-flight: base proposal machinery, snapshot mechanism, F-9 era root, F-12 elite-tail deposit, per-type quorum/majority/deposit, timelock + execution routing. | STAGES_OVERVIEW Stage K L245-252; OQ-7 / OQ-8 / OQ-9 / OQ-11 / OQ-13; F-9 / F-12 | K4 |
| K-D7 | forward-declared | `AuMM.setMinter(EmissionDistributor)` handoff sequencing per H-D41 — deploy-script call, no AuMM contract edit; `distribute()` / `claim()` unblock from `NotMinter` at this call. | H-D41 (CLAUDE.md §11 deferred); `AuMM.setMinter` | K5 |
| K-D8 | forward-declared | `TVLOracle` H-D8 roster re-wire — re-point `_constellationRatio` to enumerate the live `MiliariumRegistry` dense view (`miliariumPoolsCount` / `miliariumPoolAt`); I13-class fix-forward on the tagged Stage H contract. | J-D8 (STAGE_J_NOTES.md); H-D8 roster; I13 blast-radius | K6 |
| K-D9 | forward-declared | Deploy + authorizer-migration sequencing — `script/DeployAuMM.s.sol` (H-D42, ~30 lines) + `script/DeployStageK.s.sol`: deploy governance stack, multisig one-shot `Vault.setAuthorizer(newAuthorizer)`, registry + gauge `setGovernanceContract` one-shots, `AuMM.setMinter`. | OQ-10 migration sequence (FINDINGS L788-792); H-D42; J-D5 / G-D16d `setGovernanceContract` | K7 |

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

### K3 — VotingWeight (per K-D5; design locks at K3 pre-flight)

The value-weighted governance reader implementing `IVotingWeight` (I9.1 stub); surfaces `src/governance/VotingWeight.sol` + `test/unit/VotingWeight.t.sol`; K3 pre-flight locks K-D5 (the `(qualified_AuMT_value × time_capped)^(1/4 → 1/3)` curve, 14-day cliff, 6-month on-ramp, F-9 era root, I-D17 `totalSupply()` semantics) reading F-9 from `11_formulas.md`; depends on K2 oracle, `IEmissionDistributor` recorder clock, `IGaugeRegistry` (gauged-only gate).

### K4 — AureumGovernance (per K-D6; the largest unit; designs lock at K4 pre-flight)

The three proposal types (gauge challenge F-12 / composition challenge / fee proposal) + F-9 dampening + snapshot voting + timelock; surfaces `src/governance/AureumGovernance.sol` + `test/unit/AureumGovernance.t.sol` + `test/fork/StageKIntegration.t.sol`; K4 pre-flight sub-splits K-D6a—K-D6f reading F-9 / F-12 from `11_formulas.md` + OQ-7 / OQ-8 / OQ-9 / OQ-11 / OQ-13; depends on K3 `VotingWeight`, `IGaugeRegistry` (`revokeGauge` / `registerGaugeFromComposition`), `IMiliariumSlotRegistry` (`replaceSlot`), Vault (`setStaticSwapFeePercentage`), the Stage D fee-routing primitive (proposal-deposit-to-Bodensee).

### K5 — setMinter handoff (per K-D7)

`AuMM.setMinter(EmissionDistributor)` per H-D41, a deploy-script call sequenced in K7's script (no AuMM contract edit) that unblocks `distribute()` / `claim()` from `NotMinter`; K5 is the design/sequencing lock (K-D7), executed in the K7 deploy script.

### K6 — TVLOracle roster re-wire (per K-D8)

Re-point `src/emission/TVLOracle.sol` `_constellationRatio` to the live `MiliariumRegistry` dense enumeration (`miliariumPoolsCount` / `miliariumPoolAt`) — J-D8 carry-forward, an I13-class fix-forward on a tagged Stage H contract; K6 pre-flight sizes the TVLOracle / EMASampler / CCB fork-test blast radius.

### K7 — Deploy + authorizer migration (per K-D9)

`script/DeployAuMM.s.sol` (H-D42, ~30 lines) + `script/DeployStageK.s.sol` (deploy governance stack, multisig one-shot `Vault.setAuthorizer`, registry + gauge `setGovernanceContract` one-shots, `AuMM.setMinter`) + `test/fork/DeployStageK.t.sol`; K7 pre-flight locks K-D9 migration tx order per OQ-10 (FINDINGS L788-792).

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
| K2.0b | (this commit) | docs/STAGE_K_PLAN.md — K-D4 mirror flip to LOCKED + K2 documentation-only framing + Completion Log catch-up |
