# Aureum — Stage Sequence Overview (C through R)

> **Status:** Stage-sequence proposal, derived from `FINDINGS.md` (all 19 open questions resolved or deferred, 2026-04-15) and a stage-sequencing conversation on 2026-04-16. This file is the master sequence; detailed per-stage plans (`STAGE_C_PLAN.md`, `STAGE_D_PLAN.md`, etc.) land in separate files following the Stage A / Stage B template.
>
> **Audience:** Sagix, working solo, picking up this sequence in a fresh Claude chat after the planning conversation ends. Future stage-planning conversations start by reading this file plus the relevant prior stage plans.
>
> **Why this file exists:** the planning conversation that produced this sequence will be split across multiple chats — each stage gets its own detailed-planning conversation, and contexts don't persist. This file is the durable reference for "what is the full sequence and where am I in it" across all future chats.

---

## Scope and framing

**Starting state:** `stage-b-complete` (commit `b627a92`, tag pushed 2026-04-14). Stage B built the substrate — forked `AureumVault.sol` with 22-line authorizer redirect, `AureumVaultFactory`, `AureumProtocolFeeController`, and `AureumAuthorizer` with a single `GOVERNANCE_MULTISIG`. Roughly 5% of total protocol work by line count.

**Terminal state:** `stage-r-complete` a.k.a. `mainnet-genesis`. The full tokenomics layer (~4,500 LOC of new Solidity per `13_appendices.md` §xxxvi) deployed to Ethereum mainnet, with governance active, the 28 Miliarium pools gauged, der Bodensee unhidden at Month 6, and the emission schedule running.

**Sequencing principles (locked in via the planning conversation):**

1. **Bottom-up build.** Deepest primitives first, no stubs-to-replace-later. Each stage ships real, audit-grade code.
2. **Close F1 early.** The fee-routing hook (OQ-1) and der Bodensee land in Stage D, right after the AuMM token makes Bodensee deployable. This retires the F1 architectural gap at the earliest mechanically possible point.
3. **Coupling rule.** Two contract groups merge into one stage if and only if neither has independent testability against a mainnet fork. Example: emission distributor and gauge registry were initially coupled under this rule, then split once the testing angle was found — emission distributor tests against the gauge registry from Stage G, gauge registry tests via test-harness calls without real emissions.
4. **Each stage is independently testable against mainnet fork**, tagged in git, and documented with a completion-log row in its own `STAGE_X_PLAN.md`. Same discipline as Stages A and B.
5. **Mainnet is the LAST stage.** Testnet (Holesky hybrid per OQ-15) and external audit (OQ-17, firm deferred) happen before mainnet.
6. **Frontend is out of scope for this sequence.** Per OQ-18, frontend lives in separate repo `aumm-app` with its own plan. Stage P depends on the frontend MVP being ready; coordination is a project-management item, not part of this contract sequence.

**Terminology:** following OQ-5, block numbers are canonical time units everywhere in the protocol. Calendar terms ("month," "year," "14 days") are aliases. `BLOCKS_PER_MONTH = 219,000`, `BLOCKS_PER_EPOCH = 100,800`, `BLOCKS_PER_YEAR = 2,628,000`, `BLOCKS_PER_ERA = 10,512,000`.

---

## Folder layout (proposed, finalized during Stage C kickoff)

```
aumm-deploy/src/
├── vault/            # Stage B output; AureumVault, AureumVaultFactory, AureumProtocolFeeController, AureumAuthorizer
├── lib/              # Stage C; AureumTime.sol (block-number math library)
├── token/            # Stage C (AuMM), Stage I (AuMT)
├── fee_router/       # Stage D; AureumFeeRoutingHook.sol + shared swap-and-one-sided-deposit primitive
├── ccb/              # Stage F; F-4 EMA, F-5 score, F-6 share, F-8 multiplier
├── gauge/            # Stage G; GaugeRegistry + eligibility checker
├── emission/         # Stage H; EmissionDistributor (F-0, F-1, F-3, F-7)
├── registry/         # Stage J; MiliariumRegistry
├── governance/       # Stage K; AureumGovernance, AureumGovernanceAuthorizer, composition challenge (Stage O)
└── incendiary/       # Stage L; IncendiaryBoost
```

Existing Stage B contracts move from `src/` to `src/vault/` as the first step of Stage C.

---

## Stage sequence summary

| Stage | Name | Scope (LOC est.) | Duration | Type |
|---|---|---|---|---|
| C | Time library + AuMM token | ~400 | 1 week | Small |
| D | Fee-routing hook + der Bodensee | ~500 | 1-2 weeks | Medium |
| E | Pool-deployment framework + 3 pilot pools | ~400 (scripts + configs) | 1-2 weeks | Medium |
| F | CCB engine | ~500 | 1 week | Small-medium |
| G | Gauge registry + eligibility | ~600 | 1-2 weeks | Medium |
| H | Emission distributor | ~700 | 1-2 weeks | Medium |
| I | AuMT token | ~400 | 1 week | Small |
| J | Miliarium registry | ~200 | 1 week | Small |
| K | Governance + authorizer migration | ~900 | 2 weeks | Large |
| L | Incendiary Boost | ~300 | 1 week | Small |
| M | Miliarium pools, Sector 2 (Majors / yield-core, ~10) | configs | 1-2 weeks | Deployment |
| N | Miliarium pools, Sector 3 (Equity + thematic, ~14) | configs | 1-2 weeks | Deployment |
| O | Composition challenge / replacement-launch | ~350 | 1 week | Small |
| P | Holesky full-system deployment + stubs + integration validation | stubs + scripts | 2-3 weeks | Integration |
| Q | External audit + patch cycle | patches only | 6-10 weeks | Calendar |
| R | Mainnet deployment | scripts | 1 week | Launch |

**Total wall-clock estimate:** ~20-28 weeks of focused implementation work (C through P), plus 6-10 weeks of audit calendar (Q), plus launch (R). End-to-end from `stage-b-complete` to `mainnet-genesis`: roughly 8-10 months if work runs continuously and no major surprises surface.

**Dependency graph is clean** — no stage's prerequisites are blocked by a later stage. Per-stage testnet works at every stage: C-D test on mainnet fork directly, E adds live pilot pools, F-L test against the pilot-pool substrate from E, M-O test the full 28-pool constellation, P validates as one system, Q audits, R launches.

---

## Stage C — Time/epoch library + AuMM token

**Goal:** ship the two deepest primitives everything else depends on.

**Builds:**
- `src/lib/AureumTime.sol` — the canonical block-number math library. Constants: `BLOCKS_PER_DAY = 7200`, `BLOCKS_PER_EPOCH = 100_800`, `BLOCKS_PER_MONTH = 219_000`, `BLOCKS_PER_QUARTER = 657_000`, `BLOCKS_PER_YEAR = 2_628_000`, `BLOCKS_PER_ERA = 10_512_000`. Helper functions: `monthIndex(genesis, block)`, `epochIndex(genesis, block)`, `eraIndex(genesis, block)`, boundary checks.
- `src/token/AuMM.sol` — ERC-20 with 21M fixed cap, halving math hooks, emission-authorization interface (allows the Stage H emission distributor to mint within the schedule). No treasury, no pre-mint, no owner.

**Dependencies:** none beyond Stage B substrate.

**Testing strategy:** pure unit tests + property-based fuzz for the time library; AuMM cap/halving behavior tested with mocked emission calls.

**Why these two together:** the time library is ~150 LOC of pure arithmetic with nothing to test except fuzz vectors; pairing it with AuMM (which consumes the time library in its halving math) gives real integration coverage and still fits comfortably in 1-2 weeks. Everything else in the protocol reads from one or both — nothing can precede them.

**Also done this stage:** move existing Stage B contracts from `src/*.sol` to `src/vault/*.sol`, update deploy script paths, update the README's "Repository layout" section.

**Tag:** `stage-c-complete`.

---

## Stage D — Fee-routing hook + der Bodensee

**Goal:** close the F1 architectural gap. Build the OQ-1 hook, deploy der Bodensee, re-point the Stage B fee controller.

**Builds:**
- `src/fee_router/AureumFeeRoutingHook.sol` — implements `IHooks.onAfterSwap`, houses the shared swap-and-one-sided-deposit primitive used by all three fee layers (swap fees, yield fees, governance/Incendiary deposits). Swaps fee tokens to svZCHF (per OQ-2), one-sided-adds to der Bodensee atomically.
- Der Bodensee pool deployment script — standard Balancer V3 `WeightedPoolFactory.create(...)` → `AureumVault.registerPool(...)`. 40/30/30 AuMM/sUSDS/svZCHF weights. 0.75% genesis swap fee. Rate Providers on svZCHF and sUSDS. **No hook attached** (per OQ-2, Bodensee is excluded from the fee-routing mechanism; its yield compounds in-pool via Rate Providers).
- Modification to `AureumProtocolFeeController`: re-point B10 enforcement target from `DER_BODENSEE_POOL` to the hook/router address. Relax the Bodensee 0.75% immutability per OQ-11 — fee becomes governance-adjustable within 0.10%-1.00% band.

**Dependencies:** AuMM (C) exists as deployable token.

**Testing strategy:** mainnet-fork Anvil. Deploy a minimal test pool with the hook attached, send swaps through it, verify the hook's `onAfterSwap` correctly (a) calculates the fee, (b) swaps to svZCHF against real mainnet Balancer V3 pools, (c) one-sided-adds to Bodensee. Not as thorough as real Miliarium pools but sufficient to validate the core primitive before Stage E scales it up.

**Flagged implementation concerns (from OQ-1, revisit at design-doc time):**
- **Gas cost on every swap.** Hook adds fee calc + internal swap + one-sided add. Easily 200k+ extra gas per hooked swap. Model at design time.
- **Recursion guard.** Routing a fee swap *through* a Miliarium pool that itself has the hook attached re-triggers the hook. Either the hook special-cases its own internal swaps (trusted-router check on `params.router`), or fee swaps route directly through Bodensee (only viable if input/output tokens are present in Bodensee), or accept geometric-series overhead.
- **Audit hot path.** The hook runs on every swap on every gauged pool. Dedicated review pass during Stage Q audit.

**Tag:** `stage-d-complete`.

---

## Stage E — Pool-deployment framework + 3 pilot pools

**Goal:** build the parameterized pool-deployment script framework and validate it by deploying 3 Infrastructure-sector Miliarium pools.

**Builds:**
- `script/pools/deploy-miliarium-pool.s.sol` — parameterized Foundry script. Takes a parameter file (JSON or `.s.sol` struct) describing composition, weights, theme tokens, Rate Providers, initial swap fee. Orchestrates: standard `WeightedPoolFactory.create(...)` → `AureumVault.registerPool(...)` with Aureum-specific parameters including hook attachment and 52% ERC-4626 Quality Gate check at Vault registration.
- Per-pool parameter files: `script/pools/configs/02_ixHelvetia.json`, `03_ixEdelweiss.json`, `07_ixCambio.json` (slot numbers per `06_miliarium_manifest.md`).
- Three live pilot pools deployed: **ixHelvetia** (100% ERC-4626: 80% svZCHF + 20% sUSDS, simplest composition, routing anchor), **ixEdelweiss** (46% ixEDEL routing hub, the primary connector pool), **ixCambio** (6-token FX hub per OQ-12/OQ-12a: svZCHF 19% / st-EURA 18% / aEURS 18% / ixEDEL 15% / tGBP 15% / JPYC 15%, exercises MAX_TOKENS edge and 4626-heavy composition).

**Dependencies:** hook and Bodensee (D) deployed; AuMM (C) exists.

**Testing strategy:** each pilot pool deployment runs against mainnet fork. Verify pool registers successfully, Quality Gate check passes, hook fires correctly on a test swap, fee routes to Bodensee. Integration tests per pool with realistic token balances.

**Why these three:** maximum composition diversity with minimum count — one pure-stablecoin simplest-case pool, one connector/routing pool, one 6-token FX hub that stresses the edge of Balancer V3 `MAX_TOKENS`. If the framework handles these three, it handles anything in the remaining 25.

**Tag:** `stage-e-complete`.

---

## Stage F — CCB engine

**Goal:** implement the Compound Centrifugal Balance scoring system.

**Builds:**
- `src/ccb/EMASampler.sol` — implements F-4 per-day TVL EMA with intra-day 1-hour TWAP (per OQ-5a). Permissionless `sample(pool)` callable once per `BLOCKS_PER_DAY`. Alpha = 2/61 for 60-day half-life.
- `src/ccb/CCBScore.sol` — implements F-5 CCB score per pool.
- `src/ccb/CCBShare.sol` — implements F-6 CCB share normalization across gauged pools.
- `src/ccb/CCBMultiplier.sol` — implements F-8 multiplier update with clamp/dead-zone/step rules. Updates every `BLOCKS_PER_EPOCH`.

**Dependencies:** time library (C), pilot pools from E for real TVL readings.

**Testing strategy:** pure math contracts, deterministic outputs, independently testable against mock TVL inputs. EMA decay verification, score-to-share normalization, multiplier convergence behavior. Integration tests against the 3 pilot pools from E.

**Why this earns its own stage:** independent test surface. Can verify F-4 through F-8 math in isolation without emissions, gauges, or AuMT existing. Clean audit boundary.

**Tag:** `stage-f-complete`.

---

## Stage G — Gauge registry + eligibility

**Goal:** build the gauge state machine.

**Builds:**
- `src/gauge/GaugeRegistry.sol` — approval/revocation/90-day boost tracking per pool. `approveGauge(pool)` and `revokeGauge(pool)` gated by `onlyGovernanceContract` (governance contract doesn't exist yet — use a placeholder address that Stage K's deployment script will replace via a one-shot setter).
- `src/gauge/GaugeEligibility.sol` — eligibility checker: 4626 Quality Gate (≥52% ERC-4626 by weight, per-token vault floor of $5M / 30 BTC / 4M svZCHF), minimum TVL floor ($10K 7-day SMA), volume percentile floor (5%/10%/15% at Months 3/6/13), efficiency tournament F-10 (top 15/10/5 percentiles → 1%/0.5%/0.1% caps), no self-referential tokens check, Sandbox fast-track (top 10% efficiency for 3 consecutive epochs), graduated grace period per `08_bootstrap.md` §xxiii.
- Hysteresis buffer state + 4-consecutive-disqualified-epoch revocation counter.

**Dependencies:** time library (C), pilot pools (E), CCB engine (F, for efficiency tournament ranks).

**Testing strategy:** test-harness calls to `approveGauge` / `revokeGauge` without real governance. Verify eligibility-check state transitions: Active → Warning → Disqualified ⇄ Composition Challenge. Feed synthetic percentile-rank inputs to validate the Quality Gate / floor-check / efficiency-tier math.

**Testing without emissions:** the gauge registry is a state machine over pool eligibility. Its correctness is verifiable without AuMM actually flowing — the eligibility decisions, not the emission consequences, are the test subject.

**Tag:** `stage-g-complete`.

---

## Stage H — Emission distributor

**Goal:** implement the AuMM emission schedule.

**Builds:**
- `src/emission/EmissionDistributor.sol` — per-block AuMM emission with:
  - F-0 piecewise bootstrap decay (Months 0-6: 80% → 50% to Bodensee; Months 6-10: 50% → 0%; Month 10+: 0% permanent).
  - F-1 equal split across gauged pools (Months 0-10).
  - F-3 linear blend equal → CCB-weighted (Months 10-13).
  - F-7 full sequence (Month 13+: 100% CCB-weighted via F-6 shares).
  - Halving block boundary handler (`BLOCKS_PER_ERA` boundaries, rate halves).
- Claim interface for AuMT-weighted per-pool emission claiming (AuMT ships in Stage I, but the interface is defined here so Stage I's AuMT can integrate directly).

**Dependencies:** AuMM (C, for minting), time library (C), gauge registry (G, to know which pools are eligible), CCB engine (F, for the CCB-weighted blend starting Month 10).

**Testing strategy:** mainnet-fork tests that advance block number past `MONTH_6_END_BLOCK`, `MONTH_10_END_BLOCK`, `MONTH_13_START_BLOCK`, and at least one halving boundary. Verify piecewise transitions, halving behavior, total-emission-over-N-years matches the expected integral of F-0 + F-7.

**Tag:** `stage-h-complete`.

---

## Stage I — AuMT token

**Goal:** ship the LP tessera.

**Builds:**
- `src/token/AuMT.sol` — ERC-20-like (non-transferable or transfer-restricted depending on final design-doc decision) LP tessera with:
  - Per-pool AuMT issued on pool deposit, burned on withdrawal.
  - Time-weighting for governance: 14-day qualification period, 6-month on-ramp to full governance weight.
  - Withdrawal-reset rule: partial withdrawal resets the time-weighting clock.
  - Governance-weight tracking: zero if the underlying pool's gauge is revoked (per OQ-7 AuMT governance-weight clarification).
  - Integration with emission distributor (H): AuMT holders claim their proportional AuMM share per epoch.

**Dependencies:** emission distributor (H), gauge registry (G), CCB engine (F), time library (C).

**Testing strategy:** deposit/withdraw flows against pilot pools (E). Verify qualification + on-ramp clocks. Verify withdrawal-reset. Verify governance-weight zeroing when a test-harness gauge revocation fires.

**Tag:** `stage-i-complete`.

---

## Stage J — Miliarium registry

**Goal:** track the slot → pool mapping.

**Builds:**
- `src/registry/MiliariumRegistry.sol` — 28 slots, each holding a `currentPoolAddress`. Seeded at deploy time with the 3 pilot pools from Stage E at slots 02/03/07 and placeholder zero-addresses for the other 25 slots (populated in Stages M and N).
- `replaceSlot(slotN, newPoolAddress)` — governance-gated (placeholder address until Stage K, replaced via one-shot setter in Stage K's deployment script).
- Emits `SlotPopulated(slot, pool, blockNumber)` and `SlotReplaced(slot, oldPool, newPool, blockNumber)`.

**Dependencies:** pilot pools (E) for initial slot population.

**Testing strategy:** seed registry with pilot pools, verify slot-read correctness, test `replaceSlot` via test-harness call (bypassing the placeholder governance gate). Verify slot-to-pool reverse lookup helpers.

**Why split from AuMT:** AuMT tracks LP positions; registry tracks pool-to-slot binding. Different conceptual layer. Splitting gives each its own audit-inheritance boundary.

**Tag:** `stage-j-complete`.

---

## Stage K — Governance + authorizer migration

**Goal:** ship on-chain governance and migrate the Vault's authorizer.

**Builds:**
- `src/governance/AureumGovernance.sol` — the four proposal types:
  1. **Gauge proposal** — approve a new gauge. 20% quorum, simple majority. Deposit: 100 svZCHF/sUSDS equivalent.
  2. **Gauge challenge** — revoke an existing gauge. F-12 elite-tail-progressive deposit: max(10-BTC-equivalent-in-CHF, `1M CHF × √((1 − p_tvl)(1 − p_eff))`). BTC price = average spot rate across all gauged pools holding any registered BTC wrapper (per OQ-8). 20% quorum, simple majority.
  3. **Composition challenge** — replace a Miliarium slot. 1,000 svZCHF/sUSDS deposit. **2/3 supermajority.**
  4. **Fee proposal** — adjust per-pool swap fee within the pool-class band (Miliarium 0.01%-0.30%, Bodensee 0.10%-1.00%). 1,000 svZCHF/sUSDS deposit. 20% quorum, simple majority. Cooldown: `BLOCKS_PER_EPOCH`.
  - F-9 governance dampening: Era 0 fourth root, Era 1+ cube root (per `11_formulas.md`).
  - Vote-weight lookup via AuMT (I).
  - Timelock between vote-pass and execution.
- `src/governance/AureumGovernanceAuthorizer.sol` — B-strict authorizer with 12-month multisig time-bomb per OQ-10. `EMERGENCY_WINDOW_BLOCKS = 2_628_000` (12 months / `BLOCKS_PER_YEAR`). After that block, multisig clause permanently dead. Emergency actions set: `pauseVault`, `enableRecoveryMode`, possibly `disableQuery` (finalized at design-doc time).
- **Authorizer migration** (part of this stage's deployment script, not a separate stage): multisig signs one-shot `Vault.setAuthorizer(newAuthorizerAddress)`. Also sets the Miliarium registry's and gauge registry's governance-contract addresses via their one-shot setters.

**Dependencies:** AuMT (I, for vote weight), Miliarium registry (J, for composition challenges), gauge registry (G, for gauge proposals/challenges), fee-routing hook (D, for the deposit-into-Bodensee mechanism on proposal submission), time library (C, for the emergency-window end block and governance timelock).

**Testing strategy:** mainnet fork. Submit each of the four proposal types, run votes with test-harness AuMT balances, verify F-9 dampening, verify 20% quorum floor, verify 2/3 supermajority on composition challenges, verify F-12 deposit math with live BTC-price reads from pilot pools. Test the authorizer migration transaction against the Stage B `AureumAuthorizer` and verify the new authorizer's `canPerform` routes correctly post-migration.

**Largest stage.** Probably the full 2 weeks, possibly slightly more.

**Tag:** `stage-k-complete`.

---

## Stage L — Incendiary Boost

**Goal:** ship the F-2 priority skim mechanism.

**Builds:**
- `src/incendiary/IncendiaryBoost.sol` — priority skim from the emission stream before F-1/F-7 distribution. 14-day epoch lock (`INCENDIARY_BOOST_DURATION_BLOCKS = BLOCKS_PER_EPOCH`). Deposit-anything mechanic: anyone can boost any gauged pool by depositing any token, which the shared swap-and-one-sided-deposit primitive (D) converts to svZCHF and routes to Bodensee as the boost payment. In return, the boosted pool receives a priority emission skim for the 14-day boost window.

**Dependencies:** emission distributor (H, for the priority skim), gauge registry (G, for valid targets), fee-routing primitive (D), AuMT (I, for claim tracking).

**Testing strategy:** mainnet fork. Boost a pilot pool with a variety of deposit tokens (ETH, a random ERC-20, an ERC-4626). Verify the priority skim reaches the boosted pool for `BLOCKS_PER_EPOCH` blocks. Verify post-boost-window the skim returns to zero.

**Tag:** `stage-l-complete`.

---

## Stage M — Miliarium pools, Sector 2 (Majors / yield-core)

**Goal:** deploy ~10 Major / yield-core pools.

**Builds:** per-pool parameter files and per-pool deployment runs via the Stage E framework. Expected pools (subject to `07_miliarium_sectors.md` final sectoring): **ixAurum, ixSilva, ixBellator, ixLibertas, ixViatica, ixAetheron**, and the other yield-anchored majors.

**Dependencies:** pool-deployment framework (E), full governance stack (K) live — so that any gauge approvals needed for these pools route through the real proposal mechanism rather than test-harness calls. In practice all 10 are seeded with gauge-approved status at deployment time (they're founding Miliarium pools per `08_bootstrap.md` §xxi), but the governance stack being live means deployment scripts can verify the end-to-end flow.

**Testing strategy:** mainnet fork. Deploy each pool, verify Quality Gate check passes (per F8b, ixAetheron/ixEdelweiss/ixLibertas sit 2-5% above floor — tight validation), verify Rate Providers wire correctly, verify the hook attaches, verify initial emission distribution reaches each pool.

**Token-availability preflight:** before running the deploy scripts, verify on-chain addresses for all ERC-4626 vault components (waEth*** wrappers, GHO, sUSDS, scrvUSD, sfrxUSD, various Aave V3 stataTokens) and confirm each has sufficient depth for the registration-time minimum-liquidity check.

**Tag:** `stage-m-complete`.

---

## Stage N — Miliarium pools, Sector 3 (Equity + thematic)

**Goal:** deploy the remaining ~14 pools.

**Builds:** per-pool parameter files and deployment runs via the Stage E framework. Expected pools: equity-exposure pools (the `*on` tokenized ETFs — ixNovae, ixArtifex, ixSophia, ixMercatus, and others) and thematic pools (ixDebitum, ixFulmen, ixLumen, and the remaining governance-token / DeFi-native pools).

**Dependencies:** same as Stage M, plus token-availability confirmation is more critical here — per F8d, several theme assets (`Morpho`, `SPK`, `ETHPLUS`, `OPEN`, the `*on` series) need verified on-chain addresses and acceptable liquidity at deployment time. Flux Finance tokens (`fBRZ`, `fWETH`, `fWSTETH`) need Flux's operational status confirmed at deployment time.

**Testing strategy:** same per-pool validation as Stage M. Additional attention to the `*on` tokenized-ETF pools — these have less battle-tested on-chain behavior than the major yield-core pools in M.

**Tag:** `stage-n-complete`.

---

## Stage O — Composition challenge / replacement-launch path

**Goal:** ship the OQ-7 deprecate-and-replace machinery.

**Builds:**
- Wire up `MiliariumRegistry.replaceSlot(slotN, newPoolAddress)` with the full precondition checks:
  - `newPoolAddress` is an already-deployed pool (permissionless deploy per `08_bootstrap.md` §xxi).
  - Programmatic composition-type checks (same template role, ≥52% ERC-4626 by weight, etc.).
  - 2/3-supermajority vote from governance (K) has passed.
- Atomic execution in one governance-execute transaction:
  - Call `gaugeRegistry.revokeGauge(oldPool)` — AuMT on the deprecated pool loses governance weight at this block.
  - Call `gaugeRegistry.approveGauge(newPool)` with 90-day boost activated.
  - Call `miliariumRegistry.replaceSlot(slotN, newPoolAddress)`.
  - The deprecated pool's hook stays attached per Q1.5 — it continues routing fees to Bodensee for as long as anyone trades on it.

**Dependencies:** governance (K), registry (J), gauge registry (G), all 28 pools deployed (M, N) as the realistic replacement-target universe.

**Testing strategy:** mainnet fork. Deploy a candidate replacement pool, submit composition challenge via governance, run the vote, execute the replacement, verify all four state changes happen atomically, verify the deprecated pool's hook keeps firing on post-deprecation swaps.

**Why placement here (not inside Stage K):** replacement-pool testing benefits from having all 28 pools deployed as the replacement-target universe.

**Tag:** `stage-o-complete`.

---

## Stage P — Holesky full-system deployment + testnet stubs + integration validation

**Goal:** get the full protocol running as one system on a public testnet. First stage where the whole stack exists in one deployment.

**Builds:**
- `test-stubs/` — minimal stub contracts for: svZCHF, sUSDS, ixEDEL, and the major theme tokens (waEth wrappers, GHO, fBRZ, `*on` tokenized-asset stand-ins, JPYC, tGBP). Each stub: deterministic, non-upgradeable, ~50-100 LOC, implements the relevant interfaces (`IERC20`, `IERC4626` with `totalAssets` / `convertToShares` / `convertToAssets`, NAV-providing methods for ixEDEL). Kept under the same audit-inheritance discipline as real contracts.
- Holesky deployment scripts for the full Aureum stack pointing at the stubs.
- Frontend integration: the `aumm-app` MVP (separate repo per OQ-18) wires against the Holesky deployment.

**Dependencies:** all prior stages (C through O) complete and tagged. Frontend MVP ready (OQ-18/OQ-19 — external dependency, not part of this contract sequence).

**Testing strategy:** end-to-end validation of the full system:
- Governance flows: submit and pass each of the four proposal types.
- Gauge approval workflow: propose a non-Miliarium gauge, run vote, verify emission flows to it.
- Fee routing through hook: real trades on Holesky-deployed Miliarium pools, verify svZCHF reaches Bodensee.
- CCB scoring: advance Holesky blocks to simulate a protocol-month, verify multiplier updates and EMA decay.
- Composition challenge dry-run: deploy a replacement candidate, submit proposal, pass supermajority, verify replacement.
- Authorizer migration: execute the `Vault.setAuthorizer` transaction, verify governance now holds authorizer power.
- Halving boundary (if feasible given Holesky's block rate and time-budget): simulate a halving transition.

**Mainnet-fork complement:** during this stage, also run the Aureum stack against a Tenderly mainnet-fork devnet for integration testing against real Frankencoin / Aave V3 / Reserve Protocol DTF / Sky / Flux behavior. Not publicly accessible; used by the founding team and (in Stage Q) the audit firm.

**Tag:** `stage-p-complete`.

---

## Stage Q — External audit + patch cycle

**Goal:** audit sign-off on `stage-p-complete`.

**Process:**
- Engage audit firm (selection deferred per OQ-17 — candidate list: Trail of Bits, OpenZeppelin, Spearbit, Sigma Prime, Zellic for tier-1; Cantina/Code4rena/Sherlock for contests; Firepan for continuous monitoring).
- Scope: ~4,500 LOC of Aureum-owned new Solidity. Balancer V3 substrate (Vault, pool factories, hooks framework, rate providers) inherits existing Certora verification per `13_appendices.md` §xxxvi and is out of audit scope.
- **Code freeze in effect throughout.** No new features. Only fixes for audit findings.
- Patches land as numbered sub-steps Q1, Q2, ... — each with its own commit, test updates, and completion-log row. Regression-test against mainnet fork after each patch.
- The OQ-1 hook is explicitly on the audit hot path — dedicated review pass recommended.

**Duration:** 6-10 weeks calendar time per FINDINGS OQ-17. Your work during this stage is patch turnaround, not new implementation.

**Funding (separate decision from firm selection):** self-funding, pre-launch protocol grants (Frankencoin / Reserve / Sky), Ethereum Foundation / Optimism RetroPGF, or audit-firm sponsorship (Trail of Bits Open Crypto Audit Project does reduced-cost audits for fair-launch protocols).

**Tag:** `stage-q-complete` after audit sign-off and all critical/high findings resolved.

---

## Stage R — Mainnet deployment

**Goal:** deploy the full Aureum stack to Ethereum mainnet. Terminal stage.

**Process:**
- Deploy in dependency order (mirroring stage sequence): time lib + AuMM → fee-routing hook + der Bodensee → pool-deployment framework + 3 pilot pools → CCB → gauge registry → emission distributor → AuMT → Miliarium registry → governance + authorizer migration → Incendiary → remaining 25 Miliarium pools (M and N sectors).
- Genesis block becomes `block 0` for all block-number-indexed constants: `MONTH_6_END_BLOCK`, `MONTH_10_END_BLOCK`, halving-era boundaries, governance on-ramp periods.
- Stage B authorizer's 4-year pause window starts ticking.
- New governance authorizer's 12-month emergency clause (`EMERGENCY_WINDOW_BLOCKS = 2_628_000`) starts ticking at the authorizer-migration transaction.
- Der Bodensee remains unannounced / unsurfaced per OQ-6 until `MONTH_6_END_BLOCK + 1`.

**Testing strategy:** dry-run the entire deployment against the Tenderly mainnet-fork devnet one final time immediately before mainnet execution. Verify every contract's constructor parameters, every immutable address, every token mainnet address resolved correctly. The dry-run is the last checkpoint; mainnet execution is one-shot.

**Tag:** `stage-r-complete` a.k.a. `mainnet-genesis`.

---

## Completion Log

Updated at the close of each stage. Full per-stage completion logs live in the corresponding `STAGE_X_PLAN.md` files.

| Stage | Tag | Date | Commit | Notes |
|---|---|---|---|---|
| C | `stage-c-complete` |  |  |  |
| D | `stage-d-complete` |  |  |  |
| E | `stage-e-complete` |  |  |  |
| F | `stage-f-complete` |  |  |  |
| G | `stage-g-complete` |  |  |  |
| H | `stage-h-complete` |  |  |  |
| I | `stage-i-complete` |  |  |  |
| J | `stage-j-complete` |  |  |  |
| K | `stage-k-complete` |  |  |  |
| L | `stage-l-complete` |  |  |  |
| M | `stage-m-complete` |  |  |  |
| N | `stage-n-complete` |  |  |  |
| O | `stage-o-complete` |  |  |  |
| P | `stage-p-complete` |  |  |  |
| Q | `stage-q-complete` |  |  |  |
| R | `stage-r-complete` / `mainnet-genesis` |  |  |  |

---

## For the next conversation

The next planning conversation should open with **Stage C's detailed plan** — a `STAGE_C_PLAN.md` file in the Stage A / Stage B format: step-by-step C1, C2, ... C-N numbered steps, each with a time estimate, commands to run, files to create or modify, testing procedure, and a Completion Log table at the bottom.

Start that conversation by attaching this file (`STAGES_OVERVIEW.md`), `FINDINGS.md`, `STAGE_A_PLAN.md`, and `STAGE_B_PLAN.md` as context. Ask for "the detailed Stage C plan following the Stage A / Stage B template."
