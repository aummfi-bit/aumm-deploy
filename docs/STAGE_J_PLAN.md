# Stage J — Plan & Sub-Step Roadmap

> **Status:** J0.3 PLAN landed on `stage-j` — initial sub-step roadmap (J0—J6) + Decisions mirror (J-D1—J-D7 LOCKED) + Pre-flight checklist + Completion Log. J0.2 NOTES design freeze committed (`8270cc7`). Code phase opens at J1 (`src/registry/IMiliariumSlotRegistry.sol`). Companion to STAGE_J_NOTES.md.
>
> **Last update:** 2026-06-06 — J0.3 PLAN initial roadmap (this commit): Stage scope + Surfaces tables + Decisions mirror + Pre-flight checklist + J0—J6 sub-step roadmap + empty Completion Log.
>
> **Mode:** Opus high for the interface/contract design beats (J0 entry + J1 interface + J2 concrete — the J-D1 dual-structure reconciliation against tagged Stage F `CCBMultiplier` is the load-bearing surface), dropping to Sonnet for the unit/fork test writing + deploy scaffold + plan-row housekeeping (J3—J6, most of the stage) per §13's Stage J row ("Sonnet entry, Opus for interface design").
>
> **Audience:** Sagix plus any future Claude session that needs the operational roadmap for Stage J sub-step execution. NOTES (STAGE_J_NOTES.md) is the running design-decision log; this file is the sub-step sequence + Completion Log + grep-verifiable checkpoint catalog.

---

## Stage scope

Stage J ships the Miliarium slot↔pool registry — the 28-slot binding layer that records which pool currently occupies each Miliarium constellation slot, consumed by Stage K composition challenges (`replaceSlot`) and by the CCB layer (the frozen Stage F `IMiliariumRegistry` read view). No emissions flow and the registry makes no external calls; it is a pure state machine over slot assignments. The load-bearing engineering constraint is the J-D1 dual-structure reconciliation: the concrete must satisfy the tagged Stage F dense `IMiliariumRegistry` enumeration — `CCBMultiplier.sol:249-251` iterates `0..miliariumPoolsCount()` summing `tvlEMA(miliariumPoolAt(i))` and must never read `tvlEMA(address(0))` — while presenting the spec's sparse 28-slot model (3 pilots seeded at slots 02/03/07, 25 `address(0)` placeholders until Stages M/N). The slot/governance surface lands in a new `src/registry/IMiliariumSlotRegistry.sol` (J-D2), keeping the CCB read view untouched; the governance gate is a placeholder Authorizer Safe until the Stage K `setGovernanceContract` handoff (J-D5).

### Surfaces produced at Stage J

| File | Status | Sub-step | LOC estimate |
| --- | --- | --- | --- |
| `src/registry/IMiliariumSlotRegistry.sol` | NEW | J1.1 | ~55 |
| `src/registry/MiliariumRegistry.sol` | NEW | J2.1—J2.6 | ~150 |
| `test/unit/MiliariumRegistry.t.sol` | NEW | J3.1—J3.6 | ~300 |
| `test/fork/StageJIntegration.t.sol` | NEW | J4.1—J4.3 | ~140 |
| `script/DeployStageJ.s.sol` | NEW | J5.1 | ~60 |
| `test/fork/DeployStageJ.t.sol` | NEW | J5.2 | ~90 |

### Surfaces NOT produced at Stage J

- No `CCBMultiplier` edit — the tagged Stage F dense enumeration is preserved by the J-D1 dual structure; `src/ccb/IMiliariumRegistry.sol` is untouched.
- No Stage K governance wiring — the `setGovernanceContract` handoff is a Stage K deploy-script call; Stage J ships only the placeholder + the gated setter.
- No population of slots 01 / 04 / 05 / 06 / 08—28 — those land in Stages M/N.
- No TVLOracle H-D8 roster re-wire — open question, resolved at J4 pre-flight (see Open questions).

---

## Decisions

Mirror of STAGE_J_NOTES.md Decisions table (LOCKED at J0.2). Future J-D8 onward attach to sub-step-specific locks during J1—J6 execution and are recorded as new entries in both this table and the NOTES file.

| # | Status | Decision | Anchor | Locked at |
| --- | --- | --- | --- | --- |
| J-D1 | LOCKED | Enumeration reconciliation = dual structure: 28-entry slot store (`address[28] _slots`, governance layer) + dense packed `address[] _enumerated` (CCB view). `miliariumPoolsCount` = `_enumerated.length`; `miliariumPoolAt(i)` = `_enumerated[i]` — real pools only, never `address(0)`. `replaceSlot` keeps both in sync (swap-remove old + append new). Tagged Stage F `CCBMultiplier` untouched. | `CCBMultiplier.sol:249-251` dense iteration; `src/ccb/IMiliariumRegistry.sol` frozen; OQ-23 (iii.b) aggregate-EMA `tvlEMA(address(0))` hazard | J0.2 |
| J-D2 | LOCKED | New `src/registry/IMiliariumSlotRegistry.sol` for the slot/governance surface (`replaceSlot`, `poolAtSlot`, `slotOf`, `setGovernanceContract`, `governanceContract`, slot events/errors); concrete `MiliariumRegistry is IMiliariumRegistry, IMiliariumSlotRegistry`. CCB read view `src/ccb/IMiliariumRegistry.sol` untouched. | G-D16a in-place extension rejected here — `IMiliariumRegistry` is the CCB read view; STAGES_OVERVIEW `src/registry/` layout | J0.2 |
| J-D3 | LOCKED | Slot index 1-based external API `[1..28]` (matches `04_tokenomics.md` §vii + STAGES_OVERVIEW "slots 02/03/07"); 0-based internal `_slots[slotN - 1]`; `slotOf` returns `0` for non-members (`0` = sentinel, never a valid slot). Out-of-range slot reverts `InvalidSlot(slot)`. | STAGES_OVERVIEW Stage J "slots 02/03/07"; §vii 28-pool constellation; sentinel-0 reverse-lookup cleanliness | J0.2 |
| J-D4 | LOCKED | Genesis seeding constructor-injected: `constructor(address governance_, uint256[] memory slotNumbers, address[] memory pools)` — validates `governance_ != 0`, equal lengths, each slot ∈ [1,28], each pool ≠ 0, no duplicate slot, no duplicate pool; seeds all four mirror structures + emits `SlotPopulated` per seed. No external calls in ctor (H13-safe). Stage J passes `[2,3,7]` + the 3 Stage E pilots. | G-D20 constructor-injected genesis arrays; H13 no-constructor-external-call; G14 ctor-param `memory`; Stage E pilots at slots 02/03/07 | J0.2 |
| J-D5 | LOCKED | Governance gate mirrors `GaugeRegistry` (G-D16d / G3.3): `address public governanceContract` (not immutable) set to the placeholder authority (Stage A–K Authorizer Safe) at construction; `replaceSlot` is `onlyGovernance` (`revert NotGovernance(msg.sender)`); `setGovernanceContract(newGovernance) onlyGovernance` rebinds + emits `GovernanceTransferred(old, new)`. STAGES_OVERVIEW "one-shot setter" is loose wording for this governance-gated handoff — aligned to the precedent, not revert-on-second-call. | `GaugeRegistry.sol:46-47/59-60/87/98-101`; CLAUDE.md §1 Authorizer Safe; STAGES_OVERVIEW Stage K L254 | J0.2 |
| J-D6 | LOCKED | `SlotPopulated(uint256 indexed slot, address indexed pool, uint256 blockNumber)` at genesis seeding + any zero→nonzero population; `SlotReplaced(uint256 indexed slot, address indexed oldPool, address indexed newPool, uint256 blockNumber)` on nonzero→nonzero. `blockNumber` = `block.number` per CLAUDE.md §5, passed as an explicit arg. | STAGES_OVERVIEW Stage J events; CLAUDE.md §5 block-number-as-time | J0.2 |
| J-D7 | LOCKED | Ship `script/DeployStageJ.s.sol` + `test/fork/DeployStageJ.t.sol` at Stage J (mirrors DeployStageH/I) — registry independently deployable + fork-verified; Stage K wires `setGovernanceContract` later. H-D42 DeployAuMM deferral does NOT transfer (registry ctor takes only addresses, no Stage-K-only dependency). | DeployStageH/I precedent; STAGES_OVERVIEW deploy order L388; H-D42 contrast | J0.2 |
| J-D8 | LOCKED | TVLOracle H-D8 roster re-wire DEFERRED to Stage K — no `TVLOracle.sol` change in Stage J. The constellation roster stays placeholder-collapsed to `{BODENSEE_POOL} ∪ {governanceAddedPools}` (F-D9); re-wiring `_constellationRatio` to enumerate the live `IMiliariumRegistry` dense enumeration is an I13-class fix-forward on the tagged Stage H contract (TVLOracle/EMASampler/CCB fork-test blast radius), deferred to Stage K where the registry↔TVLOracle↔governance wiring is finalized. Interim: governance mirrors the 3 pilots via `addConstellationPool`. The J4 fork fixture mocks the TVL leg (`MockTVLOracle`), so this does not affect J4. | H-D8 roster union; F-D9 placeholder-collapse; I13 fix-forward blast-radius; `TVLOracle.addConstellationPool` interim leg; STAGES_OVERVIEW Stage K | J4.0 |

---

## Pre-flight checklist

- [x] `main` at `stage-i-complete` (commit `0ee2089`); `origin/main` synced.
- [x] `stage-j` branched from `stage-i-complete` per the C0 / D0 / E-D8 / F9 / G9 / H12 convention (and Stage I) — J0.1.
- [x] STAGE_J_NOTES.md design freeze (J-D1—J-D7 LOCKED) landed at J0.2 (`8270cc7`).
- [x] No upstream tracking for `stage-j` yet — snapshot push deferred to J6 close-of-stage.
- [x] Tagged Stage F `IMiliariumRegistry` identified as the dense-enumeration constraint (`CCBMultiplier.sol:249-251`); J-D1 dual structure reconciles it.
- [ ] (resolves at J3) Stage J unit cohort green — `test/unit/MiliariumRegistry.t.sol`.
- [ ] (resolves at J4) `StageJIntegration` fork green — real registry → `CCBMultiplier` dense-enumeration regression.
- [ ] (resolves at J5) `DeployStageJ` fork green.
- [ ] (resolves at J6) Full split-form regression green + `stage-j` fast-forward merge → `main` + `stage-j-complete` tag + push.

---

## Sub-step roadmap

### J0 — Stage entry (4 sub-steps)

- **J0.1** (DONE — branch op) `stage-j` branched from `stage-i-complete` (`0ee2089`). User ran in terminal.
- **J0.2** (DONE — `8270cc7`) `docs/STAGE_J_NOTES.md` — Stage J design freeze (J-D1—J-D7 LOCKED). Cursor §8e.1.
- **J0.3** (THIS COMMIT) `docs/STAGE_J_PLAN.md` — initial sub-step roadmap + Decisions mirror + Pre-flight checklist + Completion Log. Cursor §8e.1.
- **J0.4** `CLAUDE.md` §11 — Stage I→J terminal refresh: mark Stage I COMPLETE/tagged, set `stage-j` resume anchor (J0 done, J1 next), Stage J entry mode. Cursor §8e.1.

### J1 — `IMiliariumSlotRegistry` interface (per J-D2; 1 sub-step)

- **J1.1** `src/registry/IMiliariumSlotRegistry.sol` — the slot/governance interface: `replaceSlot(uint256 slot, address newPool)`, `poolAtSlot(uint256 slot) → address`, `slotOf(address pool) → uint256`, `setGovernanceContract(address newGovernance)`, `governanceContract() → address`; events `SlotPopulated` / `SlotReplaced` / `GovernanceTransferred` (J-D6); errors `InvalidSlot` / `ZeroAddress` / `LengthMismatch` / `NotGovernance` / `PoolAlreadyRegistered` / `SlotAlreadyAssigned`. SPDX + `pragma solidity ^0.8.26`. Cursor §8e.1.

### J2 — `MiliariumRegistry` concrete (per J-D1 / J-D3 / J-D4 / J-D5 / J-D6; 6 sub-steps)

- **J2.1** `src/registry/MiliariumRegistry.sol` — scaffold: SPDX, pragma, imports (`IMiliariumRegistry`, `IMiliariumSlotRegistry`), `contract MiliariumRegistry is IMiliariumRegistry, IMiliariumSlotRegistry`, `uint256 constant SLOT_COUNT = 28`, dual-structure storage (`address[28] private _slots`, `address[] private _enumerated`, `mapping(address => bool) private _isMiliarium`, `mapping(address => uint256) private _slotOf`, `mapping(address => uint256) private _enumIndex`, `address public governanceContract`), `onlyGovernance` modifier. Cursor §8e.1.
- **J2.2** constructor genesis seeding per J-D4 — validation (`governance_ != 0`, `slotNumbers.length == pools.length`, per-element slot/pool/duplicate checks) then seed loop writing all four mirror structures + emitting `SlotPopulated`; `governanceContract = governance_`. An internal `_assign(slot, pool)` helper may be extracted for reuse by `replaceSlot`. Cursor §8e.1.
- **J2.3** `IMiliariumRegistry` dense views per J-D1 — `isMiliarium`, `miliariumPoolsCount` (= `_enumerated.length`), `miliariumPoolAt(i)` (= `_enumerated[i]`). Cursor §8e.1.
- **J2.4** slot views per J-D3 — `poolAtSlot(slot)` (`InvalidSlot` guard, returns `_slots[slot-1]`), `slotOf(pool)` (returns `_slotOf[pool]`, 0 if absent). `governanceContract` is the public-var auto-getter. Cursor §8e.1.
- **J2.5** `replaceSlot(slot, newPool)` per J-D1 + J-D5 — `onlyGovernance`; guards `InvalidSlot` / `ZeroAddress` / `PoolAlreadyRegistered`; dual-structure sync (zero→nonzero = append + `SlotPopulated`; nonzero→nonzero = swap-remove old from `_enumerated` + append new + deregister old in `_isMiliarium`/`_slotOf` + `SlotReplaced`). Cursor §8e.1.
- **J2.6** `setGovernanceContract(newGovernance)` per J-D5 (`onlyGovernance`, `ZeroAddress` guard, rebind + `GovernanceTransferred` emit) + NatSpec sweep + close-of-family (`forge build` green gate). Cursor §8e.1.

### J3 — Unit tests `test/unit/MiliariumRegistry.t.sol` (6 sub-steps)

- **J3.1** harness / `setUp` — deploy `MiliariumRegistry` with `slotNumbers = [2,3,7]`, three mock pool addresses, a `governance` address; helper accessors. Cursor §8e.1.
- **J3.2** genesis + view tests — `poolAtSlot(2/3/7)` = pilots, other slots = `address(0)`; `slotOf` reverse; `isMiliarium` membership; `miliariumPoolsCount() == 3`; `miliariumPoolAt(0..2)` dense (no zeros). Cursor §8e.1.
- **J3.3** `replaceSlot` populate (empty slot → pool) — dense `_enumerated` grows by one, new pool registered, `SlotPopulated` emitted. Cursor §8e.1.
- **J3.4** `replaceSlot` replace (pool → pool) — swap-remove correctness (dense array length unchanged, old pool deregistered from `isMiliarium`/`slotOf`, new pool at the old dense index or tail per swap-remove), `SlotReplaced` emitted. Cursor §8e.1.
- **J3.5** revert vectors — `InvalidSlot` (slot 0, slot 29), `ZeroAddress` (newPool = 0), `NotGovernance` (non-gov caller), `PoolAlreadyRegistered` (newPool already in another slot); constructor reverts (`LengthMismatch`, duplicate slot, duplicate pool, zero governance). Cursor §8e.1.
- **J3.6** `setGovernanceContract` tests (rebind + `GovernanceTransferred` + `NotGovernance` revert) + close-of-family (`forge clean && forge build` per F14 + targeted `--match-path` test green per I11). Cursor §8e.1.

### J4 — Fork integration `test/fork/StageJIntegration.t.sol` (3 sub-steps)

- **J4.1** `StageJIntegrationFixture` — deploy a real `MiliariumRegistry` seeded with the 3 Stage E pilot pools (slots 02/03/07) + the CCB stack (`EMASampler` + `CCBMultiplier` wired to the real registry). J4 pre-flight (Opus) resolves the EMASampler TVL source (mock vs. real `TVLOracle` — see Open questions). Cursor §8e.1.
- **J4.2** dense-enumeration regression — `CCBMultiplier`'s aggregate-EMA loop reads `miliariumPoolsCount()` / `miliariumPoolAt(i)` from the real registry, summing over the 3 real pools with no `address(0)` access (the J-D1 end-to-end proof against the tagged Stage F consumer). Cursor §8e.1.
- **J4.3** `replaceSlot` → CCB re-enumeration — after a governance `replaceSlot`, `CCBMultiplier` sees the new pool in the dense enumeration and drops the old one + close-of-family (split-form fork green per D35, `--threads 1` per D36). Cursor §8e.1.

### J5 — Deploy script + fork test (per J-D7; 3 sub-steps)

- **J5.1** `script/DeployStageJ.s.sol` — deploy `MiliariumRegistry(governance_, [2,3,7], [pilot02, pilot03, pilot07])` with `governance_` = placeholder Authorizer Safe (`GOVERNANCE_MULTISIG` env); structurally mirrors `DeployStageH/I.s.sol` (`run()` / `deploy(...)`). Env: `PILOT_POOL_02/03/07` (slot-named per I-D18 convention), `GOVERNANCE_MULTISIG`. No external calls in the registry ctor (J-D4) → keccak placeholders OK (H13). Cursor §8e.1.
- **J5.2** `test/fork/DeployStageJ.t.sol` — runs `DeployStageJ.deploy(...)`, asserts `poolAtSlot(2/3/7)` = pilots, `miliariumPoolsCount() == 3`, `governanceContract() == GOVERNANCE_MULTISIG`, and a light `CCBMultiplier` wiring smoke (1/1 fork). Cursor §8e.1.
- **J5.3** close-of-family — PLAN Completion Log rows + status/mode refresh. Cursor §8e.1.

### J6 — Close-of-stage (3 sub-steps)

- **J6.1** full split-form regression per D35/D36 — `--no-match-path "test/fork/**"` unit + `--match-path "test/fork/**" --fork-url $MAINNET_RPC_URL --threads 1` fork; record actual pass counts. User runs in terminal.
- **J6.2** `CLAUDE.md` §11 Stage J COMPLETE refresh + Pre-flight checklist L flips backed by actual results + Stage K entry mode. Cursor §8e.1.
- **J6.3** Stage close — fast-forward merge `stage-j → main` + `stage-j-complete` tag + snapshot push to `origin` per the C0 / D0 / E-D8 / F9 / G9 / H12 convention. User runs in terminal.

---

## Completion log

| Sub-step | Commit | Summary |
| --- | --- | --- |
| J0.1 | (branch op) | `stage-j` branched from `stage-i-complete` (`0ee2089`) |
| J0.2 | `8270cc7` | `docs/STAGE_J_NOTES.md` — Stage J design freeze (J-D1—J-D7 LOCKED) |
| J0.3 | (this commit) | `docs/STAGE_J_PLAN.md` — initial sub-step roadmap (J0—J6) + Decisions mirror + Pre-flight checklist + Completion Log |

---

## Open questions

- TVLOracle H-D8 roster re-wire. RESOLVED at J4.0 → DEFERRED to Stage K per J-D8 (no `TVLOracle.sol` change in Stage J; roster stays `{BODENSEE_POOL} ∪ {governanceAddedPools}` per F-D9; the `_constellationRatio` re-wire is an I13-class fix-forward deferred to Stage K). Mirror of STAGE_J_NOTES.md Open questions + J-D8.
- `replaceSlot` un-population. Locked NO (`newPool ≠ 0`) per J-D4 — Stages M/N only populate. Revisit if a Stage O composition-challenge needs slot clearing.

---

## Anchors

- STAGE_J_NOTES.md — J-D bodies (J-D1—J-D7) + Interfaces + Findings queue + Open questions.
- STAGES_OVERVIEW.md Stage J (L221-236) + Stage K (L240-262) + production deploy order (L388).
- `src/ccb/IMiliariumRegistry.sol` — frozen Stage F read view; `CCBMultiplier.sol:249-251` — dense consumer (J-D1 constraint).
- `GaugeRegistry.sol:46-47/59-60/87/98-101` — governance-gate precedent (J-D5).
- `04_tokenomics.md` §vii — fixed 28-pool Miliarium constellation.
