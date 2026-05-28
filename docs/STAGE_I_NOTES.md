# Stage I — Notes & Design Freeze

> **Status:** I0.0b NOTES amendment landed on `stage-i` — I-D9 LOCKED Option A (per-pool mapping in EmissionDistributor) + I-D10 LOCKED (AureumTime extension QUALIFICATION_PERIOD_BLOCKS + ON_RAMP_PERIOD_BLOCKS); I-D1—I-D10 all LOCKED; no code surface landed yet. Companion to STAGE_I_PLAN.md (lands at I0.0c).
>
> **Last update:** 2026-05-23 — I0.0b NOTES amendment (I-D9 LOCKED Option A per-pool mapping in EmissionDistributor mirroring H-D10 per-pool recorder pattern + I-D10 LOCKED AureumTime extension declaring QUALIFICATION_PERIOD_BLOCKS as BLOCKS_PER_EPOCH semantic alias + ON_RAMP_PERIOD_BLOCKS as 180 × BLOCKS_PER_DAY new declaration; this commit).
>
> **Mode:** Opus high entry per §13 stage-level defaults — AuMT interface design + soulbound ERC-20 state machine + governanceWeight root-curve formula. Drops to mostly Sonnet after I3 design closes (test writing + plan-row updates). I0.0c PLAN sub-step skeleton next.
>
> **Audience:** Sagix plus any future Claude session that needs the running log of decisions resolved during implementation and the incidents caught at audit.

---

## How this file is organized

- Design decisions during implementation. I-D1—I-D9 mirror STAGE_I_PLAN.md's I-D Decisions table (lands at I0.0b) — I-D1—I-D8 LOCKED at I0.0a from spec + IAuMT.sol + Stage D AureumFeeRoutingHook architectural read; I-D9 OPEN as placeholder pending I0.0b PLAN-drafting analysis of multi-AuMT-to-distributor routing. Any new decision resolved during implementation (i.e. not pre-seeded at I0.0a) gets the next free I-D* number (I-D10 onward) and is recorded as a new entry — not retro-edited into the plan file. Matches the C-D* / D-D* / E-D* / F-D* / G-D* / H-D* convention.
- Findings (I10 onward). Implementation incidents, drift caught at audit, RPC quirks, env-key surprises, scope-expansion catches, contract-interface gotchas — anything worth a numbered log entry. Numbered from I10 to avoid collision with I-D* planning codes (matches the C10 / D10 / E10 / F10 / G10 / H10 pattern).
- Cross-reference convention (per CLAUDE.md §5): I-Dn = planning or implementation decision n; In (n ≥ 10) = implementation finding n; OQ-N = open question N from FINDINGS.md; F-n = formula n from `11_formulas.md`; §xxix = section in aummfi-bit/aumm-site numbered spec; H-Dn / G-Dn / F-Dn / E-Dn / D-Dn / C-Dn = prior-stage decisions; Hn / Gn / Fn / En / Dn / Cn = prior-stage findings (carry forward across stages).

---

## Design decisions

The I-D rows below carry the design freeze locked across I0.0a—I0.0b. I-D1—I-D8 LOCKED at I0.0a from a pre-flight Opus beat reading `04_tokenomics.md` §ix + `IAuMT.sol` H6.0c skeleton + `AureumFeeRoutingHook.sol` Stage D architectural survey + `EmissionDistributor.sol` H-D16 recorder-slot gap analysis; I-D9 + I-D10 LOCKED at I0.0b from Opus-high analysis of multi-AuMT routing pattern (Option A per-pool mapping selected over Option B AuMTRouter multiplexer per H-D10 per-pool recorder precedent) and AureumTime constant extension (both declared in `src/lib/AureumTime.sol` per C-D3 canonical convention). Future entries I-D11 onward attach to specific sub-step locks during I1—I7 implementation.

| # | Status | Decision | Anchor | Locked at |
| --- | --- | --- | --- | --- |
| I-D1 | LOCKED | AuMT is soulbound — `transfer` / `transferFrom` / `approve` revert `NotTransferable` | §ix withdrawal-reset rule; spec silence on transfer = soulbound intent | I0.0a |
| I-D2 | LOCKED | 1 AuMT contract per Miliarium pool (3 pilot instances at Stage I; 28 at full deployment via Stages M/N) | H-D35; CLAUDE.md §1; IAuMT.sol L67 NatSpec | I0.0a |
| I-D3 | LOCKED | 18 decimals matching pool BPT (Balancer V3 convention) | Balancer V3 BPT convention; Stage E pilot pool deploys | I0.0a |
| I-D4 | LOCKED | `mint` + `burn` access: `onlyLiquidityHook` — bound `AureumFeeRoutingHook` only; `NotLiquidityHook` revert | Hook owns LP deposit/withdrawal moment; distributor is downstream consumer | I0.0a |
| I-D5 | LOCKED | Extend `AureumFeeRoutingHook.sol` in-place at I2 — bumps `getHookFlags()` + adds `onAfterAddLiquidity` / `onAfterRemoveLiquidity` + `auMTByPool` map + `setAuMTForPool` setter | Balancer V3 one-hook-per-pool constraint; nested-call precedent at L408-431 | I0.0a |
| I-D6 | LOCKED | Qualification clock: starts on first deposit (`qualificationBlock` slot set); top-up deposits don't reset; only withdrawal (burn) resets to 0 | §ix verbatim "Remove any amount... time_in_pool resets" | I0.0a |
| I-D7 | LOCKED | `governanceWeight(holder)` = `(balanceOf × min(time_in_pool, ON_RAMP_PERIOD_BLOCKS))^(1/4)` Era 0, `^(1/3)` Era 1+; ZERO if `time_in_pool < QUALIFICATION_PERIOD_BLOCKS` OR `!gaugeRegistry.isGaugeApproved(pool())` | §ix verbatim formula; F-9 dampening; AureumTime C-D3 era boundary; FINDINGS OQ-7 gauge-revoked rule | I0.0a |
| I-D8 | LOCKED | Stage I deployment scope: 3 AuMT instances for pilot pools at slots 02/03/07 + `AureumFeeRoutingHook` extension; Stage M/N rollout deferred | Stage E pilot pools; out-of-scope rollout per STAGES_OVERVIEW | I0.0a |
| I-D9 | LOCKED | Multi-AuMT routing: per-pool mapping in EmissionDistributor (Option A) — `auMTContract` → `auMTContractByPool` mapping; `onlyAuMTContract(pool)` modifier; `setAuMTContractForPool(pool, addr)` one-shot setter | H-D16 single-slot baseline; H-D10 per-pool recorder precedent; I-D2 per-pool topology | I0.0b |
| I-D10 | LOCKED | `AureumTime.sol` extension: `QUALIFICATION_PERIOD_BLOCKS = BLOCKS_PER_EPOCH` (100_800) + `ON_RAMP_PERIOD_BLOCKS = 180 * BLOCKS_PER_DAY` (1_296_000) | C-D3 canonical time library; §ix verbatim "14 days" + "day 180" | I0.0b |

### I-D1 — AuMT is soulbound; transfer / transferFrom / approve revert `NotTransferable` — status LOCKED

AuMT receipt tokens for a Miliarium pool are soulbound: the `transfer`, `transferFrom`, and `approve` overrides revert with the custom error `NotTransferable`, leaving only `mint` (driven by `AureumFeeRoutingHook.onAfterAddLiquidity`) and `burn` (driven by `AureumFeeRoutingHook.onAfterRemoveLiquidity`) as the legitimate balance-change paths. The `04_tokenomics.md` §ix specification is silent on transferability, but the withdrawal-reset rule ("Remove any amount of liquidity from a qualified pool — even 1% — and governance power for that position drops to zero immediately; `time_in_pool` resets") loses meaning if holders can sidestep the clock by transferring AuMT to alt-accounts. Silence-on-transfer reads as a meaningful omission given how detailed the withdrawal-reset is — soulbound is the cleanest semantic that preserves §ix's intent. Per-pool deployment per I-D2 means the soulbound rule applies independently to each AuMT instance — a holder can have qualified positions in multiple pools simultaneously, each tracked separately. Anchors: §ix withdrawal-reset rule; FINDINGS OQ-7 RESOLVED; IAuMT.sol H6.0c NatSpec.

### I-D2 — One AuMT contract per Miliarium pool — status LOCKED

Stage I deploys one AuMT contract per pilot Miliarium pool (3 instances at Stage I; 28 at full deployment across Stages M/N). Each AuMT's `pool()` view returns its bound pool address; the `distributor()` view returns the shared `EmissionDistributor` per H-D35. CLAUDE.md §1 establishes "AuMT — per-pool LP receipt" as the canonical token model; IAuMT.sol L67 NatSpec ("AuMT is per-pool per CLAUDE.md §1 — one AuMT deployment per Miliarium pool at Stage I") was locked at H6.0c per H-D35. The per-pool topology aligns with the spec's governance accounting: `time_in_pool` is per-(holder, pool) state, naturally encoded as per-contract state when each AuMT instance has a single bound pool. The multi-AuMT-to-single-distributor routing question this raises is tracked as I-D9 OPEN. Anchors: H-D35; CLAUDE.md §1; IAuMT.sol L67 NatSpec.

### I-D3 — 18 decimals matching pool BPT — status LOCKED

AuMT inherits 18 decimals from Balancer V3's BPT convention — every Stage E pilot pool's BPT is 18-decimal, and AuMT is minted 1:1 with BPT on LP deposit per I-D5. This avoids any decimal-conversion surface inside the hook's mint dispatch and keeps `AuMT.balanceOf(holder)` directly comparable to the underlying BPT balance for any auditor cross-check. The FixedPoint root-curve math in I-D7 assumes 18-decimal inputs throughout. Anchors: Balancer V3 BPT convention; Stage E pilot pool deploys.

### I-D4 — `mint` and `burn` access control is `onlyLiquidityHook` — status LOCKED

The bound `AureumFeeRoutingHook` is the only address permitted to call `mint(to, amount)` or `burn(from, amount)`; any other caller reverts `NotLiquidityHook`. The hook owns the LP deposit/withdrawal callback moment via Balancer V3's `onAfterAddLiquidity` / `onAfterRemoveLiquidity` (newly enabled in I-D5), so it is the natural authority for mint/burn dispatch. The `EmissionDistributor` is downstream of the recorder relationship per H-D35 — AuMT internally calls `distributor.recordDeposit` / `recordWithdrawal` after mint/burn — and never the inverse. IAuMT.sol H6.0c NatSpec at L35 (mint) and L47-L48 (burn) ("callable by the bound distributor only") are stale and get re-NatSpec'd at I3.7 to match the actual access-control surface (the H6.0c skeleton's wording confused producer with consumer; I-D4 fixes it). Anchors: I-D5 hook extension; H-D35 recorder semantics; IAuMT.sol H6.0c L35 + L47-L48 NatSpec correction.

### I-D5 — Extend `AureumFeeRoutingHook.sol` in-place at I2 — status LOCKED

Balancer V3 binds one hook contract per pool at registration; `AureumFeeRoutingHook` is already that contract for the 3 Stage E pilot Miliarium pools, so AuMT mint/burn dispatch must flow through the existing hook. I2 amends the hook: bumps `getHookFlags()` to set `shouldCallAfterAddLiquidity = true` and `shouldCallAfterRemoveLiquidity = true`; adds two new callbacks dispatching `AuMT(auMTByPool[pool]).mint(sender, bptAmountOut)` / `.burn(sender, bptAmountIn)`; adds `mapping(address pool => address auMTContract) public auMTByPool` storage slot; adds one-shot governance-gated `setAuMTForPool(address pool, address auMT)` setter (reverts `AuMTAlreadyBound` on second call per pool) and `AuMTBound(pool, auMT)` event. The 6 existing constructor immutables stay unchanged; existing `onAfterSwap` + fee-routing semantics are untouched. Established precedent for nested Vault calls from within hook callbacks exists at `AureumFeeRoutingHook.sol:408-431` (`_addLiquidityOneSidedToBodenseeViaVault` inside `onAfterSwap`'s open `unlock` session) and per D17 NOTES L227 — Stage I's new callbacks make NO nested Vault calls (mint/burn are local AuMT-state transitions), making the extension strictly simpler than the existing Stage D pattern. `onRegister`'s exclusion of Bodensee + svZCHF-pools at L251-262 is symmetric with Stage I's goal: Bodensee LPs do not receive AuMT (the spec scopes AuMT to Miliarium pools only). Stage D regression coverage: full Stage D unit + fork cohort re-run at I2-fix close as a green-light gate before any I3 unit test lands. Anchors: Balancer V3 one-hook-per-pool constraint; AureumFeeRoutingHook.sol L245-249 + L251-262 + L408-431; D17 NOTES L227; H-D35 recorder semantics.

### I-D6 — Qualification clock: first-deposit start, only withdrawal resets — status LOCKED

AuMT tracks `qualificationBlock[holder]` (the block at which the holder's current qualification clock started) and `lastDepositBlock[holder]` (informational, last mint block). On `mint(holder, amount)`: if `qualificationBlock[holder] == 0` set `qualificationBlock[holder] = block.number`; otherwise leave it alone (top-up deposits do not reset). On `burn(holder, any amount)`: set `qualificationBlock[holder] = 0` unconditionally per §ix's "Remove any amount — even 1% — `time_in_pool` resets" rule. The full-reset-on-any-withdrawal semantic matches §ix verbatim; the silence-on-top-ups is interpreted as "top-up doesn't change the clock" since the spec's formula `(qualified_AuMT_value × time_in_pool)` naturally handles top-ups via the value term, and qualification reset on top-up would punish LPs for adding liquidity — an anti-spec incentive. Anchors: §ix verbatim; FINDINGS OQ-7 governance-weight clarification; I-D7 weight formula.

### I-D7 — `governanceWeight` formula = root-curve over `(balance × time_in_pool_capped)` — status LOCKED

`governanceWeight(holder)` returns ZERO if `qualificationBlock[holder] == 0` OR `block.number - qualificationBlock[holder] < QUALIFICATION_PERIOD_BLOCKS` OR `!gaugeRegistry.isGaugeApproved(pool())`; otherwise returns `(balanceOf(holder) × time_in_pool_capped)^(1/4)` when `block.number < AureumTime.firstHalvingBlock(GENESIS_BLOCK)` (Era 0) else `^(1/3)` (Era 1+), where `time_in_pool_capped = min(block.number - qualificationBlock[holder], ON_RAMP_PERIOD_BLOCKS)`. The 14-day qualification cliff comes directly from §ix ("Voting power requires at least 14 days of continuous qualified AuMT holding"). The 6-month on-ramp cap (`ON_RAMP_PERIOD_BLOCKS`) implements §ix's "By month 6 (day 180), they reach full voting weight" via the `min(.)` capping. The fourth-root → cube-root era transition implements F-9 dampening per §ix verbatim ("The dampening exponent transitions from fourth root to cube root at the first halving block"). The gauge-revoked → zero rule implements OQ-7 RESOLVED (FINDINGS L633-637). FixedPoint root-curve math at 18-decimal precision; era boundary read from `AureumTime.firstHalvingBlock(GENESIS_BLOCK)` per C-D3. Anchors: §ix verbatim formula; FINDINGS OQ-7; F-9 dampening; AureumTime C-D3.

### I-D8 — Stage I deployment scope: 3 pilot pool AuMT instances + FeeRoutingHook extension — status LOCKED

Stage I deploys 3 AuMT contracts wired to the 3 Stage E pilot Miliarium pools at slots 02/03/07; each AuMT instance is constructor-immutable to its bound pool + the shared `EmissionDistributor` per H-D35. The `AureumFeeRoutingHook` extension at I2 lands once per the existing hook deployment; per-pool wiring happens via 3 calls to `setAuMTForPool(pool, auMT)` (one-shot per pool, governance-gated). The shared `EmissionDistributor` wiring depends on the I-D9 resolution: under Option A the distributor's per-pool `auMTContractByPool` mapping is set 3 times; under Option B a single AuMTRouter address is set via the existing `setAuMTContract`. Stage M/N rollout (remaining 25 AuMT deployments at slots 01/04/05/06/08—28) is out of Stage I scope. Anchors: Stage E pilot pools at slots 02/03/07; H-D35 distributor binding; I-D9 routing-pattern resolution.

### I-D9 — Multi-AuMT routing via per-pool mapping in EmissionDistributor (Option A) — status LOCKED

EmissionDistributor's recorder slot extends from a single `address public auMTContract` per H-D16 to `mapping(address pool => address) public auMTContractByPool` to support the 3 (and ultimately 28) Stage I AuMT instances per I-D2. The `onlyAuMTContract` modifier takes the pool address as parameter and gates against `auMTContractByPool[pool]`; both `recordDeposit(pool, user, amount)` and `recordWithdrawal(pool, user, amount)` already carry pool as their first argument per H-D16, so the gate-tightening is a localized signature change. The `setAuMTContract(addr)` governance setter becomes `setAuMTContractForPool(pool, addr)` — one-shot per pool, reverting `AuMTAlreadyBound(pool)` on second call to that pool (mirrors I-D5's `setAuMTForPool` setter on the hook). The `NotAuMTContract(address)` error extends to `NotAuMTContract(address pool, address sender)` to preserve the (pool, sender) shape at revert sites.

Option A mirrors H-D10's per-pool authorized recorder pattern (`EfficiencyOracle.recordScore` gated by `onlyAuthorizedRecorder(pool)`) — the distributor owns the (pool → AuMT) routing table directly rather than delegating to a router multiplexer. This avoids the ~50-line AuMTRouter contract that Option B would have introduced, the extra external call per mint/burn that the router hop would have added, and the architectural drift from H-D10's per-pool recorder convention. The cost is mechanical signature updates to ~115 Stage H tests (`EmissionDistributor.t.sol` 100 unit tests + `AuMMDistributorIntegration.t.sol` 4 unit tests + StageHIntegration fork suites 10 tests + `DeployStageH.t.sol` 1 test) — landed at I1 as the foundation sub-step before any AuMT.sol implementation begins, keeping the regression cohort green throughout Stage I.

Anchors: H-D16 single-slot baseline; H-D10 per-pool recorder precedent; I-D2 per-pool topology; I0.0b LOCK.

### I-D10 — AureumTime extension: QUALIFICATION_PERIOD_BLOCKS + ON_RAMP_PERIOD_BLOCKS — status LOCKED

`src/lib/AureumTime.sol` extends with two new `internal constant` declarations consumed by AuMT.sol's `governanceWeight` formula per I-D7. `QUALIFICATION_PERIOD_BLOCKS = BLOCKS_PER_EPOCH` (= 100_800; 14 days × 7200 blocks/day; semantic alias preserving single source of truth for the 14-day cliff value — equal to `BLOCKS_PER_EPOCH` by coincidence since 14 days is exactly 1 epoch per OQ-3/OQ-4). `ON_RAMP_PERIOD_BLOCKS = 180 * BLOCKS_PER_DAY` (= 1_296_000; 180 days × 7200 blocks/day; new declaration per §ix "By month 6 (day 180), they reach full voting weight" — derived from `BLOCKS_PER_DAY` rather than the calendar-month-average `BLOCKS_PER_MONTH` because §ix specifies exact 180-day not 6-calendar-month duration).

Decision: declare both in `AureumTime.sol` per C-D3 (canonical block-number time library) rather than as locally-declared constants in `AuMT.sol`. `AuMT.sol` reads via `AureumTime.QUALIFICATION_PERIOD_BLOCKS` and `AureumTime.ON_RAMP_PERIOD_BLOCKS` — preserves the project-wide convention that block-number constants live in AureumTime and only AureumTime, established at C-D3 and respected across Stages C—H. Lands at I2 sub-step (after I1 EmissionDistributor refactor, before I3 AuMT.sol implementation that consumes these constants).

Anchors: C-D3 canonical time library; §ix verbatim "14 days" + "By month 6 (day 180)"; OQ-3/OQ-4 `BLOCKS_PER_EPOCH` / `BLOCKS_PER_DAY` canonical values; I-D7 governanceWeight formula.

### I-D11 — AuMT constructor pattern: 4 immutables + 2 ERC20 name/symbol params — status LOCKED

AuMT.sol takes 6 constructor arguments: `address pool_` + `address distributor_` + `address liquidityHook_` + `uint256 genesisBlock_` + `string memory name_` + `string memory symbol_`, of which the first four are stored as `public immutable` slots (`pool` / `distributor` / `liquidityHook` / `GENESIS_BLOCK`) and the last two pass through to `ERC20(name_, symbol_)` for standard ERC20 name/symbol storage. ZeroAddress guards apply to `pool_` / `distributor_` / `liquidityHook_`; `genesisBlock_` accepts any `uint256` per the project-wide convention established at AuMM / EmissionDistributor / BodenseeBootstrapChannel / EfficiencyOracle (deploy-time correctness is governance's responsibility — no zero-check); `name_` / `symbol_` pass to OpenZeppelin's ERC20 base with no Aureum-side validation.

Decision: `GENESIS_BLOCK` is carried as AuMT's own constructor immutable rather than read at call time from `EmissionDistributor.GENESIS_BLOCK()`. The pattern mirrors every other major Aureum contract (AuMM / EmissionDistributor / BodenseeBootstrapChannel / EfficiencyOracle each carry their own immutable) — preserves a gas-cheap immutable read inside `governanceWeight` (~3 gas vs 700-2600 for external view CALL) and avoids inverting the H-D35 recorder direction (AuMT calls distributor, never reads from it for state). Construction-time read from `IEmissionDistributor(distributor_).GENESIS_BLOCK()` would resolve the deploy-time mismatch risk but is the **H13 pattern** verbatim (constructor makes external call to a constructor arg) — fork tests with keccak-placeholder env stubs would break `setUp()` on first attempt, costing a `setUp()` rewrite as at H10.2-revised. Deploy-time mismatch risk is mitigated by a defensive unit test at I5 asserting `AuMT.GENESIS_BLOCK() == IEmissionDistributor(AuMT.distributor()).GENESIS_BLOCK()`.

Decision: `name_` / `symbol_` are per-pool constructor params with the pool creator choosing the instance name, following the Balancer V3 BPT-naming convention. For the 28 Miliarium Aureum pools (created at protocol genesis per §ix), the AuMT instance names are pre-defined in the canonical spec as `ixEDEL` / `ixAUREBIT` / `ixXYZ` matching their respective pool BPT symbols (see `miliarium_profiles/` in `aummfi-bit/aumm-site`); for future post-genesis pools created at any later block, the pool creator chooses the AuMT name at deploy time. Static `"Aureum Market Tessera"` / `"AuMT"` for all instances would cause wallet UI collision and block-explorer indistinguishability (soulbound semantics already eliminate the transfer-UX concern, but governance dApps and audit tooling still need per-instance identification). Constructor-time read from `IERC20Metadata(pool_).symbol()` would lock AuMT name to BPT name and would be H13-risky (external call to constructor arg). Constructor params are the OpenZeppelin idiomatic pattern (factory clones with per-deployment naming).

Anchors: C-D3 canonical immutable convention (AuMM / EmissionDistributor pattern); H13 NOTES (constructor external-call risk); Balancer V3 BPT name-by-creator convention; OQ-I10 deferred 25-AuMT rollout where pool creators choose per-pool names; `04_tokenomics.md` §ix verbatim; `miliarium_profiles/` canonical 28-AuMT name list; I-D7 governanceWeight formula consumer of `GENESIS_BLOCK` via `AureumTime.firstHalvingBlock(GENESIS_BLOCK)`.

Extended: I-D12 below — `gaugeRegistry` added as 5th AuMT immutable; constructor arg count 6 → 7. I-D11 body text preserved verbatim for audit trail.

### I-D12 — AuMT 5th immutable: gaugeRegistry — extends I-D11 (6→7 args, 4→5 immutables) — status LOCKED

I-D7 LOCKED `governanceWeight` to short-circuit ZERO when `!gaugeRegistry.isGaugeApproved(pool())`, but I-D11 LOCKED the AuMT constructor at 6 args / 4 immutables (`pool` / `distributor` / `liquidityHook` / `GENESIS_BLOCK`) without a path to a gauge-registry binding. The `governanceWeight` formula therefore requires a 5th immutable `IGaugeRegistry public immutable gaugeRegistry` to be added to AuMT.sol. A new constructor arg `address gaugeRegistry_` is slotted between `liquidityHook_` and `genesisBlock_` (addresses-first-then-scalars per EmissionDistributor L119-122 precedent), with a ZeroAddress guard mirroring the existing three address guards on `pool_` / `distributor_` / `liquidityHook_`.

Decision: direct AuMT-side immutable (Option A) over distributor-chained read (Option B: `EmissionDistributor(distributor)._gaugeRegistry()` per `governanceWeight` call) or interface widening (Option C: extend `IEmissionDistributor` with a `gaugeRegistry()` view bridge). Option A justified by: (i) gas (~3 gas immutable read vs ~700-2600 for external view CALL), mirroring `EmissionDistributor.sol:L31` direct-binding precedent `IGaugeRegistry public immutable _gaugeRegistry`; (ii) honoring I-D11's stated "every other major Aureum contract carries its own immutable" principle. Option B critique: couples AuMT to EmissionDistributor's leading-underscore getter symbol `_gaugeRegistry()` as stable ABI. Option C critique: widens Stage H interface for a Stage I consumer.

Constructor arg ordering: `pool_` / `distributor_` / `liquidityHook_` / `gaugeRegistry_` / `genesisBlock_` / `name_` / `symbol_` (7 args total). Rationale: addresses contiguous at positions 1-4, `uint256` scalar at 5, `string memory` pair at 6-7 — mirrors EmissionDistributor's address-block-then-scalars convention at L119-122. Immutable storage order: `pool` / `distributor` / `liquidityHook` / `gaugeRegistry` / `GENESIS_BLOCK` (5 slots); the section header in AuMT.sol updates to `/* ---------- Immutables (I-D11 / I-D12) ---------- */` at I3.5-pre3. The I5 deploy-time consistency invariant test `AuMT.gaugeRegistry() == IEmissionDistributor(AuMT.distributor())._gaugeRegistry()` mirrors the I-D11 `GENESIS_BLOCK` invariant test pattern.

Anchors: I-D7 governanceWeight ZERO branch (`!gaugeRegistry.isGaugeApproved(pool())`); I-D11 constructor pattern (extended by this lock, body preserved verbatim for audit trail); EmissionDistributor.sol:L31 direct-binding precedent (`IGaugeRegistry public immutable _gaugeRegistry`); CCBMultiplier F-D23 mutable-with-one-shot-setter pattern NOT chosen (Stage I deploys after Stage G concrete registry exists); H13 no-constructor-external-call rule (no constructor-time `_gaugeRegistry()` call); I5 deploy-time consistency invariant test (`AuMT.gaugeRegistry() == IEmissionDistributor(AuMT.distributor())._gaugeRegistry()`).

---

## Interfaces

### Produced by Stage I

These interfaces are authoritative once I1—I2 conclude; widening or renaming them afterward requires documenting a fresh I-D* lock and clearing the §12 ambiguity-gate before implementation edits proceed.

| Interface | File | Locked surface | Sub-step |
| --- | --- | --- | --- |
| IAuMT (concrete) | `src/token/AuMT.sol` (NEW) implementing `src/token/IAuMT.sol` (H6.0c-locked) | IERC20 base reverting `NotTransferable` on transfer/transferFrom/approve per I-D1; `governanceWeight(holder)` per I-D7; `mint(to, amount)` + `burn(from, amount)` gated `onlyLiquidityHook` per I-D4 with internal post-mint/burn `EmissionDistributor.recordDeposit` / `recordWithdrawal` per H-D35; `distributor()` / `pool()` views; `qualificationBlock(holder)` + `lastDepositBlock(holder)` views | I1 |
| AuMT mint/burn hook callbacks | `src/fee_router/AureumFeeRoutingHook.sol` (EXTENDED in-place per I-D5) | New: `onAfterAddLiquidity(...)` + `onAfterRemoveLiquidity(...)` callbacks + `auMTByPool(address) → address` view + `setAuMTForPool(address pool, address auMT)` one-shot governance-gated setter + `AuMTBound(pool, auMT)` event; `getHookFlags()` returns true for `shouldCallAfterAddLiquidity` + `shouldCallAfterRemoveLiquidity` in addition to existing `shouldCallAfterSwap`; existing constructor + `onAfterSwap` + fee-routing semantics UNCHANGED | I2 |

### Consumed — frozen by prior stages

Stage I assumes every upstream ABI in this roster remains fixed for its duration — if a predecessor ever widened selectors mid-stream, Stage I would replicate the G16-style inheritor sweep auditors already paid once, so this table is treated as immutable for the life of the stage.

| Interface | File | Frozen at | Surface used |
| --- | --- | --- | --- |
| IERC20 | OpenZeppelin v5.6.1 | Stage C | Standard ERC20 base for soulbound AuMT inheritance |
| IGaugeRegistry | `src/ccb/IGaugeRegistry.sol` | Stage G G-D16a | `isGaugeApproved(address)` — gates `governanceWeight` to zero when bound pool ungauged per I-D7 |
| IEmissionDistributor | `src/emission/IEmissionDistributor.sol` | Stage H H1 (subject to I-D9 amendment of `setAuMTContract` signature under Option A) | `recordDeposit(pool, holder, amount)` + `recordWithdrawal(pool, holder, amount)` — called internally by AuMT.mint / AuMT.burn per H-D35 recorder semantics |
| AureumTime | `src/lib/AureumTime.sol` | Stage C | `firstHalvingBlock(GENESIS_BLOCK)` era boundary read by `governanceWeight` per I-D7; potential extension at I0.0b for `QUALIFICATION_PERIOD_BLOCKS` + `ON_RAMP_PERIOD_BLOCKS` constants (see Open questions) |
| AureumFeeRoutingHook (pre-I2 surface) | `src/fee_router/AureumFeeRoutingHook.sol` | Stage D | Constructor + 6 immutables + `onRegister` + `onAfterSwap` + fee-routing semantics UNCHANGED at I2 (extension adds new callbacks + new storage slot + new setter only) |

### Forward-dependency stubs

(none — Stage J / K / L do not produce surfaces consumed by Stage I)

---

## Findings queue

Entries labeled I10+ accumulate once Stage I exits pure documentation scaffolding and Solidity surfaces stabilize; numbering stays decoupled from I-D planners per the conventions above until incidents surface.

### I10 — Multi-file rename refactor: §8e.1 Must-match must enumerate NatSpec cross-references to the OLD symbol, not just the renamed declaration site

When a §8e.1 renames a function / event / error / storage slot — e.g., `setAuMTContract` → `setAuMTContractForPool`, `AuMTContractSet` → `AuMTContractBound` per I-D9 — the original Must-match enumerates the new symbols at their declaration sites but typically misses NatSpec `@notice` / `@dev` paragraphs elsewhere in the same file that cross-reference the OLD symbol by name. Both I1.1 and I1.2 surfaced isolated stale NatSpec lines requiring `*-fix1` sub-steps:

- I1.1-fix1 (`46a93c7`): `IEmissionDistributor.sol` L73 — `AuMTContractSet (H-D16)` cross-reference in `IncendiaryRegistrySet` event NatSpec.
- I1.2-fix1 (`1f9c74f`): `EmissionDistributor.sol` L19 / L81 / L100 / L107 / L191 — five stale `H-D16` + `auMTContract` + `setAuMTContract` cross-references in contract-level @dev + per-function @dev paragraphs.

Default rule for any rename §8e.1 drafted in the Opus beat: run `grep -n "<old-symbol>" <target-file>` first, enumerate every occurrence, and add a Must-match bullet asserting `Zero hits anywhere in the file for the standalone `<old-symbol>\b` token`. Each surviving NatSpec hit must be resolved per-line (update with new symbol + new anchor, or remove the cross-reference). This is intra-file NatSpec scope, distinct from G16's cross-file interface-inheritor scope (`grep -rn "is I<Interface>" src/ test/ script/`); the two rules complement.

Anchors: I1.1-fix1 (commit `46a93c7`), I1.2-fix1 (commit `1f9c74f`), G16 (interface-inheritor enumeration).

### I11 — Foundry `forge test --match-test` uses Rust regex; `\|` is literal pipe, not alternation

`forge test --match-test "<regex>"` evaluates `<regex>` as a Rust regex (the `regex` crate), not POSIX BRE/ERE or PCRE. The escape `\|` is the literal pipe character, not an alternation operator. At I2.2 USER VERIFY, the filter `--match-test "qualificationPeriodBlocks\|onRampPeriodBlocks"` matched zero tests (Foundry reported "No tests found in project!") because no test name contains a literal `|` character. The unescaped pipe `|` is the Rust regex alternation operator.

Default rule for §8e.1 USER VERIFY blocks that filter by test name: use the bare pipe `|` (unescaped) inside bash double-quoted strings — e.g., `--match-test "(testA|testB)"`. When the §8e.1 only adds tests to a single test file, prefer `--match-path "test/unit/<File>.t.sol"` alone over `--match-test` — the path filter is unambiguous and avoids regex pitfalls entirely. Pair with `forge clean &&` if a prior `forge build` reported "No files changed, compilation skipped" per F14 incremental-cache behavior.

Anchors: I2.2 USER VERIFY (commit `552300c`), F14 (Foundry incremental cache).

### I12 — Container-shape design decisions must cross-check prior LOCKs that consume their members

I-D11 LOCK at I3.0a (`ca2596e`) enumerated the AuMT immutables as `pool`, `distributor`, `liquidityHook`, `GENESIS_BLOCK` — four slots — without cross-checking against I-D7 (locked at I0.0a `9409d76`) which required `gaugeRegistry.isGaugeApproved(pool)` inside `governanceWeight`. The gap surfaced at the I3.5 §8e.1 pre-flight (Opus beat reading I-D7 against the I3.1-landed constructor pattern); §12 ambiguity-gate fired and blocked the I3.5 `governanceWeight` body from landing without a gaugeRegistry binding. Resolution: I-D12 LOCK at I3.5-pre1 (`4a595e8`) extending I-D11's four immutables to five, with three options evaluated and Option A (direct `IGaugeRegistry` immutable) chosen per `EmissionDistributor.sol:L31` precedent. I3.5-pre2 (`feab19d`) mirrored the LOCK into PLAN; I3.5-pre3 (`4178fd9`) landed the code (constructor 6 → 7 args, immutables 4 → 5).

The §12 ambiguity-gate worked exactly as designed — caught the gap at the next §8e.1 entry, before any code landed. The cost of the resolution was three sub-step round-trips (I3.5-pre1 / pre2 / pre3) plus one chat-level decision (Option A vs B vs C). The cost of NOT catching it would have been a code-side fix to add a fifth immutable to a published constructor signature, retroactive updates to any test fixtures already using the four-arg form, and a NOTES retro-amendment to I-D11 — strictly more cost in every dimension.

Default rule for the Opus beat that locks a "container" design decision (an enumeration of immutables, storage slots, function signatures, hook callbacks, or any N-tuple where the cardinality is contract-design-load-bearing): before declaring the LOCK, enumerate ALL prior `-D*` LOCK bodies that consume members of the new tuple and verify the enumeration covers them. For an immutables tuple, the cross-check is: grep prior `-D*` bodies for external calls, library reads, or address arguments that would need a binding slot. The enumeration is provisional until that cross-check completes; LOCK only after. Distinct scope from the §12 ambiguity-gate (which catches typed-domain ambiguity at the next §8e.1 entry); this is a pre-LOCK preventive check, the §12 gate is the post-LOCK structural backstop.

Anchors: I-D7 (I0.0a `9409d76`), I-D11 (I3.0a `ca2596e`), I-D12 (I3.5-pre1 `4a595e8`), I3.5-pre2 PLAN mirror (`feab19d`), I3.5-pre3 code (`4178fd9`), §12 ambiguity-gate (CLAUDE.md).

---

## Open questions

Documented ambiguity here disappears only after translation into FINDINGS.md rows whenever resolution carries protocol-wide implication; until then NOTES remain provisional scratch space.

- OQ-I10 (deferred to Stage M/N) — Rollout of remaining 25 AuMT instances (slots 01/04/05/06/08—28). Out of Stage I scope per STAGES_OVERVIEW.md dependency graph.
