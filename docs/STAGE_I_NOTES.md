# Stage I — Notes & Design Freeze

> **Status:** I0.0a NOTES design freeze landed on `stage-i` (branched from `stage-h-complete` at `2a33649`) — I-D1—I-D8 LOCKED + I-D9 OPEN. No code surface landed yet. Companion to STAGE_I_PLAN.md (lands at I0.0b).
>
> **Last update:** 2026-05-23 — I0.0a NOTES design freeze (I-D1—I-D8 LOCKED + I-D9 OPEN via Opus-high entry pre-flight: §ix spec read + IAuMT.sol H6.0c skeleton survey + AureumFeeRoutingHook Stage D architectural read + EmissionDistributor single-slot `auMTContract` gap surfaced; this commit).
>
> **Mode:** Opus high entry per §13 stage-level defaults — AuMT interface design + soulbound ERC-20 state machine + governanceWeight root-curve formula + I-D9 multi-AuMT routing resolution. Drops to mostly Sonnet after I1 design closes (test writing + plan-row updates). I0.0b PLAN sub-step skeleton + I-D9 LOCK next.
>
> **Audience:** Sagix plus any future Claude session that needs the running log of decisions resolved during implementation and the incidents caught at audit.

---

## How this file is organized

- Design decisions during implementation. I-D1—I-D9 mirror STAGE_I_PLAN.md's I-D Decisions table (lands at I0.0b) — I-D1—I-D8 LOCKED at I0.0a from spec + IAuMT.sol + Stage D AureumFeeRoutingHook architectural read; I-D9 OPEN as placeholder pending I0.0b PLAN-drafting analysis of multi-AuMT-to-distributor routing. Any new decision resolved during implementation (i.e. not pre-seeded at I0.0a) gets the next free I-D* number (I-D10 onward) and is recorded as a new entry — not retro-edited into the plan file. Matches the C-D* / D-D* / E-D* / F-D* / G-D* / H-D* convention.
- Findings (I10 onward). Implementation incidents, drift caught at audit, RPC quirks, env-key surprises, scope-expansion catches, contract-interface gotchas — anything worth a numbered log entry. Numbered from I10 to avoid collision with I-D* planning codes (matches the C10 / D10 / E10 / F10 / G10 / H10 pattern).
- Cross-reference convention (per CLAUDE.md §5): I-Dn = planning or implementation decision n; In (n ≥ 10) = implementation finding n; OQ-N = open question N from FINDINGS.md; F-n = formula n from `11_formulas.md`; §xxix = section in aummfi-bit/aumm-site numbered spec; H-Dn / G-Dn / F-Dn / E-Dn / D-Dn / C-Dn = prior-stage decisions; Hn / Gn / Fn / En / Dn / Cn = prior-stage findings (carry forward across stages).

---

## Design decisions

The I-D rows below carry the design freeze locked at I0.0a from a pre-flight Opus beat reading `04_tokenomics.md` §ix + `IAuMT.sol` H6.0c skeleton + `AureumFeeRoutingHook.sol` Stage D architectural survey + `EmissionDistributor.sol` H-D16 recorder-slot gap analysis. Entries I-D1—I-D8 LOCKED at I0.0a, 2026-05-23. Entry I-D9 OPEN — locks at I0.0b PLAN drafting after Option A vs B analysis of multi-AuMT routing through the distributor's single-slot `auMTContract` per H-D16. Future entries I-D10 onward attach to specific sub-step locks during I1—I7 implementation.

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
| I-D9 | OPEN | Multi-AuMT routing through `EmissionDistributor` per H-D16 single-slot `auMTContract` gap — Option A (per-pool mapping in distributor; Stage H amendment) vs Option B (Stage I AuMTRouter multiplexer; no Stage H change) | EmissionDistributor.sol L96 + L155-158 + L181-183; H-D16; H-D10 per-recorder precedent | I0.0b |

### I-D1 — AuMT is soulbound; transfer / transferFrom / approve revert `NotTransferable` — status LOCKED

AuMT receipt tokens for a Miliarium pool are soulbound: the `transfer`, `transferFrom`, and `approve` overrides revert with the custom error `NotTransferable`, leaving only `mint` (driven by `AureumFeeRoutingHook.onAfterAddLiquidity`) and `burn` (driven by `AureumFeeRoutingHook.onAfterRemoveLiquidity`) as the legitimate balance-change paths. The `04_tokenomics.md` §ix specification is silent on transferability, but the withdrawal-reset rule ("Remove any amount of liquidity from a qualified pool — even 1% — and governance power for that position drops to zero immediately; `time_in_pool` resets") loses meaning if holders can sidestep the clock by transferring AuMT to alt-accounts. Silence-on-transfer reads as a meaningful omission given how detailed the withdrawal-reset is — soulbound is the cleanest semantic that preserves §ix's intent. Per-pool deployment per I-D2 means the soulbound rule applies independently to each AuMT instance — a holder can have qualified positions in multiple pools simultaneously, each tracked separately. Anchors: §ix withdrawal-reset rule; FINDINGS OQ-7 RESOLVED; IAuMT.sol H6.0c NatSpec.

### I-D2 — One AuMT contract per Miliarium pool — status LOCKED

Stage I deploys one AuMT contract per pilot Miliarium pool (3 instances at Stage I; 28 at full deployment across Stages M/N). Each AuMT's `pool()` view returns its bound pool address; the `distributor()` view returns the shared `EmissionDistributor` per H-D35. CLAUDE.md §1 establishes "AuMT — per-pool LP receipt" as the canonical token model; IAuMT.sol L67 NatSpec ("AuMT is per-pool per CLAUDE.md §1 — one AuMT deployment per Miliarium pool at Stage I") was locked at H6.0c per H-D35. The per-pool topology aligns with the spec's governance accounting: `time_in_pool` is per-(holder, pool) state, naturally encoded as per-contract state when each AuMT instance has a single bound pool. The multi-AuMT-to-single-distributor routing question this raises is tracked as I-D9 OPEN. Anchors: H-D35; CLAUDE.md §1; IAuMT.sol L67 NatSpec.

### I-D3 — 18 decimals matching pool BPT — status LOCKED

AuMT inherits 18 decimals from Balancer V3's BPT convention — every Stage E pilot pool's BPT is 18-decimal, and AuMT is minted 1:1 with BPT on LP deposit per I-D5. This avoids any decimal-conversion surface inside the hook's mint dispatch and keeps `AuMT.balanceOf(holder)` directly comparable to the underlying BPT balance for any auditor cross-check. The FixedPoint root-curve math in I-D7 assumes 18-decimal inputs throughout. Anchors: Balancer V3 BPT convention; Stage E pilot pool deploys.

### I-D4 — `mint` and `burn` access control is `onlyLiquidityHook` — status LOCKED

The bound `AureumFeeRoutingHook` is the only address permitted to call `mint(to, amount)` or `burn(from, amount)`; any other caller reverts `NotLiquidityHook`. The hook owns the LP deposit/withdrawal callback moment via Balancer V3's `onAfterAddLiquidity` / `onAfterRemoveLiquidity` (newly enabled in I-D5), so it is the natural authority for mint/burn dispatch. The `EmissionDistributor` is downstream of the recorder relationship per H-D35 — AuMT internally calls `distributor.recordDeposit` / `recordWithdrawal` after mint/burn — and never the inverse. IAuMT.sol H6.0c NatSpec at L35 ("callable by the bound distributor only") is stale and gets re-NatSpec'd at I1 to match the actual access-control surface (the H6.0c skeleton's wording confused producer with consumer; I-D4 fixes it). Anchors: I-D5 hook extension; H-D35 recorder semantics; IAuMT.sol H6.0c L35 NatSpec correction.

### I-D5 — Extend `AureumFeeRoutingHook.sol` in-place at I2 — status LOCKED

Balancer V3 binds one hook contract per pool at registration; `AureumFeeRoutingHook` is already that contract for the 3 Stage E pilot Miliarium pools, so AuMT mint/burn dispatch must flow through the existing hook. I2 amends the hook: bumps `getHookFlags()` to set `shouldCallAfterAddLiquidity = true` and `shouldCallAfterRemoveLiquidity = true`; adds two new callbacks dispatching `AuMT(auMTByPool[pool]).mint(sender, bptAmountOut)` / `.burn(sender, bptAmountIn)`; adds `mapping(address pool => address auMTContract) public auMTByPool` storage slot; adds one-shot governance-gated `setAuMTForPool(address pool, address auMT)` setter (reverts `AuMTAlreadyBound` on second call per pool) and `AuMTBound(pool, auMT)` event. The 6 existing constructor immutables stay unchanged; existing `onAfterSwap` + fee-routing semantics are untouched. Established precedent for nested Vault calls from within hook callbacks exists at `AureumFeeRoutingHook.sol:408-431` (`_addLiquidityOneSidedToBodenseeViaVault` inside `onAfterSwap`'s open `unlock` session) and per D17 NOTES L227 — Stage I's new callbacks make NO nested Vault calls (mint/burn are local AuMT-state transitions), making the extension strictly simpler than the existing Stage D pattern. `onRegister`'s exclusion of Bodensee + svZCHF-pools at L251-262 is symmetric with Stage I's goal: Bodensee LPs do not receive AuMT (the spec scopes AuMT to Miliarium pools only). Stage D regression coverage: full Stage D unit + fork cohort re-run at I2-fix close as a green-light gate before any I3 unit test lands. Anchors: Balancer V3 one-hook-per-pool constraint; AureumFeeRoutingHook.sol L245-249 + L251-262 + L408-431; D17 NOTES L227; H-D35 recorder semantics.

### I-D6 — Qualification clock: first-deposit start, only withdrawal resets — status LOCKED

AuMT tracks `qualificationBlock[holder]` (the block at which the holder's current qualification clock started) and `lastDepositBlock[holder]` (informational, last mint block). On `mint(holder, amount)`: if `qualificationBlock[holder] == 0` set `qualificationBlock[holder] = block.number`; otherwise leave it alone (top-up deposits do not reset). On `burn(holder, any amount)`: set `qualificationBlock[holder] = 0` unconditionally per §ix's "Remove any amount — even 1% — `time_in_pool` resets" rule. The full-reset-on-any-withdrawal semantic matches §ix verbatim; the silence-on-top-ups is interpreted as "top-up doesn't change the clock" since the spec's formula `(qualified_AuMT_value × time_in_pool)` naturally handles top-ups via the value term, and qualification reset on top-up would punish LPs for adding liquidity — an anti-spec incentive. Anchors: §ix verbatim; FINDINGS OQ-7 governance-weight clarification; I-D7 weight formula.

### I-D7 — `governanceWeight` formula = root-curve over `(balance × time_in_pool_capped)` — status LOCKED

`governanceWeight(holder)` returns ZERO if `qualificationBlock[holder] == 0` OR `block.number - qualificationBlock[holder] < QUALIFICATION_PERIOD_BLOCKS` OR `!gaugeRegistry.isGaugeApproved(pool())`; otherwise returns `(balanceOf(holder) × time_in_pool_capped)^(1/4)` when `block.number < AureumTime.firstHalvingBlock(GENESIS_BLOCK)` (Era 0) else `^(1/3)` (Era 1+), where `time_in_pool_capped = min(block.number - qualificationBlock[holder], ON_RAMP_PERIOD_BLOCKS)`. The 14-day qualification cliff comes directly from §ix ("Voting power requires at least 14 days of continuous qualified AuMT holding"). The 6-month on-ramp cap (`ON_RAMP_PERIOD_BLOCKS`) implements §ix's "By month 6 (day 180), they reach full voting weight" via the `min(.)` capping. The fourth-root → cube-root era transition implements F-9 dampening per §ix verbatim ("The dampening exponent transitions from fourth root to cube root at the first halving block"). The gauge-revoked → zero rule implements OQ-7 RESOLVED (FINDINGS L633-637). FixedPoint root-curve math at 18-decimal precision; era boundary read from `AureumTime.firstHalvingBlock(GENESIS_BLOCK)` per C-D3. Anchors: §ix verbatim formula; FINDINGS OQ-7; F-9 dampening; AureumTime C-D3.

### I-D8 — Stage I deployment scope: 3 pilot pool AuMT instances + FeeRoutingHook extension — status LOCKED

Stage I deploys 3 AuMT contracts wired to the 3 Stage E pilot Miliarium pools at slots 02/03/07; each AuMT instance is constructor-immutable to its bound pool + the shared `EmissionDistributor` per H-D35. The `AureumFeeRoutingHook` extension at I2 lands once per the existing hook deployment; per-pool wiring happens via 3 calls to `setAuMTForPool(pool, auMT)` (one-shot per pool, governance-gated). The shared `EmissionDistributor` wiring depends on the I-D9 resolution: under Option A the distributor's per-pool `auMTContractByPool` mapping is set 3 times; under Option B a single AuMTRouter address is set via the existing `setAuMTContract`. Stage M/N rollout (remaining 25 AuMT deployments at slots 01/04/05/06/08—28) is out of Stage I scope. Anchors: Stage E pilot pools at slots 02/03/07; H-D35 distributor binding; I-D9 routing-pattern resolution.

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

(empty)

---

## Open questions

Documented ambiguity here disappears only after translation into FINDINGS.md rows whenever resolution carries protocol-wide implication; until then NOTES remain provisional scratch space.

- I0.0b `AureumTime` library extension — `QUALIFICATION_PERIOD_BLOCKS` (= 14 × 7200 = 100_800; equal to `BLOCKS_PER_EPOCH` per OQ-3/OQ-4) and `ON_RAMP_PERIOD_BLOCKS` (= 180 × 7200 = 1_296_000; new). Decision deferred to I0.0b PLAN drafting: alias existing constant vs declare new named constant; new `ON_RAMP_PERIOD_BLOCKS` declaration unambiguous.
- I-D9 (locks at I0.0b PLAN drafting) — `EmissionDistributor.auMTContract` is a single-slot `address` per H-D16 (EmissionDistributor.sol L96 + L155-158 + L181-183 + `NotAuMTContract(msg.sender)` revert in `onlyAuMTContract` modifier). With I-D2's 3 AuMT instances, only ONE can occupy the slot — the other 2 revert. Option A extends `auMTContract` to `mapping(pool => address)` with amended `setAuMTContract(pool, addr)` signature (Stage H amendment; mirrors H-D10 per-recorder mapping precedent). Option B introduces a Stage I AuMTRouter multiplexer contract (no Stage H bytecode change; adds a hop). Option A leaning per architectural cleanliness; LOCK after I0.0b PLAN drafting analyzes blast radius.
- OQ-I10 (deferred to Stage M/N) — Rollout of remaining 25 AuMT instances (slots 01/04/05/06/08—28). Out of Stage I scope per STAGES_OVERVIEW.md dependency graph.
