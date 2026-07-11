# Aureum — Stage Sequence Overview (C through R)

> **Status:** Stage-sequence proposal, derived from `FINDINGS.md` (all 19 baseline open questions resolved or deferred, 2026-04-15; **Stage G addendum OQ-G1–G4**, 2026-05-05) and a stage-sequencing conversation on 2026-04-16. This file is the master sequence; detailed per-stage plans (`STAGE_C_PLAN.md`, `STAGE_D_PLAN.md`, etc.) land in separate files following the Stage A / Stage B template.
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
5. **Mainnet is the LAST stage.** Testnet (hybrid per OQ-15 — network-agnostic target, P-D1) and external audit (OQ-17, firm deferred) happen before mainnet.
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
| M | Miliarium pools, Sector 2 (Majors / yield-core, 5 per M-D7) | configs | 1-2 weeks | Deployment |
| N | Miliarium pools, Sector 3 (Equity + thematic) + 2 resolvable ex-M Majors (18 pools per N-D0; 04/07 deferred) | configs | 1-2 weeks | Deployment |
| O | Composition challenge / replacement-launch | ~350 | 1 week | Small |
| P | Full-system deployment + stubs + integration validation | stubs + scripts | 2-3 weeks | Integration |
| P-bis | Open-issue close-out + testnet go-live + frontend | fixes + stubs + scripts | 3-6 weeks | Integration |
| Q | External audit + patch cycle | patches only | 6-10 weeks | Calendar |
| R | Mainnet deployment | scripts | 1 week | Launch |

**Total wall-clock estimate:** ~20-28 weeks of focused implementation work (C through P), plus 6-10 weeks of audit calendar (Q), plus launch (R). End-to-end from `stage-b-complete` to `mainnet-genesis`: roughly 8-10 months if work runs continuously and no major surprises surface.

**Dependency graph is clean** — no stage's prerequisites are blocked by a later stage. Per-stage testnet works at every stage: C-D test on mainnet fork directly, E adds live pilot pools, F-L test against the pilot-pool substrate from E, M-O test the full 28-pool constellation, P validates as one system, P-bis closes the open ledger and goes live on a public testnet with the frontend, Q audits, R launches.

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
- Per-pool parameter files: `script/pools/configs/01_ixHelvetia.s.sol`, `05_ixEdelweiss.s.sol`, `14_ixAurebit.s.sol` (slot numbers per `06_miliarium_manifest.md`).
- Three live pilot pools deployed: **ixHelvetia** (100% ERC-4626: 80% svZCHF + 20% sUSDS, simplest composition, routing anchor), **ixEdelweiss** (46% ixEDEL routing hub, the primary connector pool), **ixAurebit** (5-asset Standard pool: svZCHF 26% / Aave Prime GHO 26% / ixEDEL 16% / WBTC 16% / cbBTC 16%, Digital Gold / Bitcoin sector, exercises mixed 8/18-decimal composition and the 52% Quality-Gate boundary).

**Dependencies:** hook and Bodensee (D) deployed; AuMM (C) exists.

**Testing strategy:** each pilot pool deployment runs against mainnet fork. Verify pool registers successfully, Quality Gate check passes, hook fires correctly on a test swap, fee routes to Bodensee. Integration tests per pool with realistic token balances.

**Why these three:** maximum composition diversity with minimum count — one pure-stablecoin simplest-case pool, one connector/routing pool, one mixed-decimal Bitcoin/gold pool that exercises 8-decimal tokens and the 52% Quality-Gate boundary. If the framework handles these three, it handles anything in the remaining 25.

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

## Stage G — Gauge registry + eligibility (auto-gauge pivot)

**Goal:** build the gauge state machine with **permissionless gauge activation** — no governance vote for admission.

**Design freeze:** [STAGE_G_NOTES.md](STAGE_G_NOTES.md) · decision record: [STAGE_G_PRECHECK_AUTO_GAUGE.md](STAGE_G_PRECHECK_AUTO_GAUGE.md). Open questions **OQ-G1–OQ-G4** resolved in [FINDINGS.md](FINDINGS.md).

**Builds:**
- `src/gauge/VaultClassRegistry.sol` — Frankencoin-inspired proposal-and-veto admission of ERC-4626 vault classes counted toward the 52% Quality Gate numerator. Three admission fingerprints (`ImplementationAddress` / `FactoryAddress` / `BytecodeHash`) per **G-D9**; constructor-injected genesis arrays per **G-D20**; 201_600-block veto window per **G-D19**; bond routes via `SwapAndDepositToBodensee.donate` to der Bodensee.
- `src/gauge/SwapAndDepositToBodensee.sol` — OQ-G3 swap-and-deposit primitive per **G-D11** + **G-D12** + **G-D21**. Two entry points: strict-equality `swapAndDeposit` (activation fee, 100 svZCHF or 125 sUSDS per **G-D12**) and variable-amount `donate` (governance-allowlisted bonds + future emission-router donations). Transient-storage reserve-delta guard via Balancer V3 `calculateSlot` + `tload` / `tstore` per **G-D14** + **G-D18** (solc 0.8.26 — no language-level `transient` keyword per **G10**).
- `src/gauge/GaugeEligibility.sol` — epoch-boundary eligibility evaluator. `IWeightedPool.getNormalizedWeights` × `IERC4626.asset()` try/catch (**G-D10**) × `VaultClassRegistry` admission lookup → 52% numerator gate (**G-D8**); plus OQ-G2 TVL floor, F-10 efficiency tournament cohort via `computeEpochSnapshot` per **G-D3** + **G-D23** (top-15% favored / bottom-85% residual; insertion-sort address-ascending tiebreak per **T-T3**), factory whitelist (**G-D6** + **G-D15a**, fails-closed), forbidden-token block (AuMM / AuMT per **T-I3**), and — Stage I add-on per **I-D13** / **OQ-24** — canonical-hook gate (`IVault(vault).getHooksConfig(pool).hooksContract == feeRoutingHook` else revert `WrongFeeRoutingHook`; `feeRoutingHook` a 9th constructor immutable; ensures only pools carrying the canonical `AureumFeeRoutingHook` — the sole AuMT minter and Bodensee swap-fee + yield-skim router — can gauge). `computeEpochSnapshot` gated `onlyGaugeRegistry` per **G-D22** + **F-D23** one-shot setter; reshaped transition events `GaugeEfficiencyDropped` / `GaugeEfficiencyRising` carry `(numeratorSma, denominatorSma, efficiencyRatio)` per **G-D23 (iii)**.
- `src/gauge/GaugeRegistry.sol` — three activation paths per **G-D1** + **G-D7**: (i) permissionless `activateGauge(pool)` — pulls anti-spam fee via `SwapAndDepositToBodensee.swapAndDeposit`, then try/catches eligibility and emits non-reverting `GaugeActivationFailed` on failure per **G-D16c**; (ii) governance `registerGaugeFromComposition`; (iii) governance `seedFoundingPool` / `seedFoundingPools` per **STAGE_G_PRECHECK_AUTO_GAUGE** C-4. Terminal `revokeGauge` per **G-D17**; Stage K handoff via `setGovernanceContract`. 90-day boost deprecated at Stage G per **G-D13** (M_i reset at activation in Stage F `CCBMultiplier`). Interface extended in place at `src/ccb/IGaugeRegistry.sol` per **G-D16a** — Stage F `isGaugeApproved` ABI preserved; sibling `IEfficiencyOracle` interface added per **G-D23 (ii)** (concrete oracle deferred to Stage H).

**Dependencies:** time library (C), AuMM (C), der Bodensee (D), pilot pools (E), CCB engine (F — `IGaugeRegistry.isGaugeApproved` consumer per **F-D17**; `CCBMultiplier` seals to real `GaugeRegistry` via **F-D23** one-shot setter).

**Testing strategy:** unit tests per contract (`test/unit/VaultClassRegistry.t.sol` 37/37, `test/unit/GaugeEligibility.t.sol` 46/46, `test/unit/GaugeRegistry.t.sol` happy + revert + governance + view); fork integration `test/fork/StageGIntegration.t.sol` covers propose→finalize→evaluate→activate→revoke on the Stage E pilot pools with synthetic F-10 inputs via `MockEfficiencyOracle` (**G-D23 (i)**) + TVL floor via `MockTVLOracle`. `StageGRegistryStageFRegressionTest` exercises the Stage F **F-D17** boost-gate via the real `GaugeRegistry`. Sibling mock home `test/fork/mocks/StageGMocks.sol` per **G-D25c**.

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
- `src/registry/MiliariumRegistry.sol` — 28 slots, each holding a `currentPoolAddress`. Seeded at deploy time with the 3 pilot pools from Stage E at slots 01/05/14 and placeholder zero-addresses for the other 25 slots (populated in Stages M and N).
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
- `src/governance/AureumGovernance.sol` — the **three** proposal types:
  1. **Gauge challenge** — revoke an existing **non-Miliarium** gauge. F-12 elite-tail-progressive deposit: max(10-BTC-equivalent-in-CHF, `1M CHF × √((1 − p_tvl)(1 − p_eff))`). BTC price = average spot rate across all gauged pools holding any registered BTC wrapper (per OQ-8). 20% quorum, simple majority.
  2. **Composition challenge** — replace a Miliarium slot. 1,000 svZCHF/sUSDS deposit. **2/3 supermajority.**
  3. **Fee proposal** — adjust per-pool swap fee within the pool-class band (Miliarium 0.01%-0.30%, Bodensee 0.10%-1.00%). 1,000 svZCHF/sUSDS deposit. 20% quorum, simple majority. Cooldown: `BLOCKS_PER_EPOCH`.
  - **Gauge activation** for new non-Miliarium pools — **permissionless** (Stage G `activateGauge`); **not** a governance proposal.
  - F-9 governance dampening: Era 0 fourth root, Era 1+ cube root (per `11_formulas.md`).
  - Vote-weight lookup via AuMT (I).
  - Timelock between vote-pass and execution.
- `src/governance/AureumGovernanceAuthorizer.sol` — B-strict authorizer with 12-month multisig time-bomb per OQ-10. `EMERGENCY_WINDOW_BLOCKS = 2_628_000` (12 months / `BLOCKS_PER_YEAR`). After that block, multisig clause permanently dead. Emergency actions set: `pauseVault`, `enableRecoveryMode`, possibly `disableQuery` (finalized at design-doc time).
- **Authorizer migration** (part of this stage's deployment script, not a separate stage): multisig signs one-shot `Vault.setAuthorizer(newAuthorizerAddress)`. Also sets the Miliarium registry's and gauge registry's governance-contract addresses via their one-shot setters.

**Dependencies:** AuMT (I, for vote weight), Miliarium registry (J, for composition challenges), gauge registry (G, for gauge challenges + composition **execution** callbacks), fee-routing hook (D, for the deposit-into-Bodensee mechanism on proposal submission), time library (C, for the emergency-window end block and governance timelock).

**Testing strategy:** mainnet fork. Submit each **proposal** type, run votes with test-harness AuMT balances, verify F-9 dampening, verify 20% quorum floor, verify 2/3 supermajority on composition challenges, verify F-12 deposit math with live BTC-price reads from pilot pools. **Separately** verify permissionless **gauge activation** on a deploy-when-ready pool (Stage G). Test the authorizer migration transaction against the Stage B `AureumAuthorizer` and verify the new authorizer's `canPerform` routes correctly post-migration.

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

**Goal:** deploy 5 Major / yield-core pools (M-D7 — narrowed from the originally-conceived ~10 by the M2 token-availability preflight; the other 4 defer to Stage N).

**Builds:** per-pool parameter libraries (`script/pools/configs/`) + per-pool deployment wrappers (`script/pools/DeployIx*.s.sol`) via the Stage E framework, plus the bind-only `script/DeployStageM.s.sol` orchestration. Built pools: **ixCasper** (03), **ixBrevis** (08), **ixAltrix** (09), **ixMediox** (10), **ixLongus** (11) — the five Majors the M2 token-availability preflight cleared (M-D7); the four deferred (ixAetheron 02, ixViatica 04, ixLibertas 06, ixCambio 07) move to Stage N.

**Dependencies:** pool-deployment framework (E), full governance stack (K) live — deployment scripts assume **gauge-active** founding pools (**seeded at deploy**, not subjected to gauge vote). The governance stack being live verifies **fee / challenge / composition** flows end-to-end.

**Testing strategy:** mainnet fork (`test/fork/StageMIntegration.t.sol` + `test/fork/DeployStageM.t.sol`). Per M-D10 the assertion scope is binding-liveness: each Major clears the 52% Quality Gate via `evaluateEligibility` (ixCasper at 68% post-M-D11; the other four at the 52% floor), Rate Providers resolve (`getRate() > 0`), the fee-routing hook attaches, `registry.poolAtSlot` returns the pool, the gauge is founding-seeded, and the distributor recorder binds to the hook — not live emission accrual.

**Token-availability preflight (M2):** verified on-chain addresses and Rate-Provider resolvability for the candidate Majors' ERC-4626 components; 5 of 9 cleared (the four with unresolvable composition / Rate Providers deferred to Stage N per M-D7). M-D11 records the one post-preflight RP failure caught at the M5 fork stage (ixCasper waEthwstETH → plain wstETH).

**Tag:** `stage-m-complete`.

---

## Stage N — Miliarium pools, Sector 3 (Equity + thematic)

**Goal:** deploy the final **18** Miliarium pools (N-D0), completing the 28-slot constellation: the 16 Sector-3 slots — **12 ixStrata, 13 ixForum, 15 ixRegistrum, 16 ixDebitum, 17 ixEquitix, 18 ixInnovix, 19 ixGigantus, 20 ixMagnix, 21 ixNubix, 22 ixMoneta, 23 ixColossix, 24 ixVitalix, 25 ixMedicix, 26 ixMercatura, 27 ixAurix, 28 ixMetallum** — plus the two resolvable Majors deferred from Stage M (M-D7), **02 ixAetheron** and **06 ixLibertas**. (Slots 01 / 05 / 14 are the pilots; 03 / 08 / 09 / 10 / 11 are the Stage-M Majors — hence the gaps in the Sector-3 run.)

**Builds:** per-pool parameter libraries (`script/pools/configs/`) + per-pool deployment wrappers (`script/pools/DeployIx*.s.sol`) via the Stage E framework, plus the bind-only `script/DeployStageN.s.sol` orchestration (M-D9 shape). New this stage: the protocol's first Aureum-owned rate-provider surface — **`src/rate_provider/ERC4626RateProvider.sol`** (scrvUSD / sfrxUSD yield cores with no usable mainnet RP, N-D2) and **`src/rate_provider/CompositeRateProvider.sol`** (the two ixAetheron stata-wrapper cores, N-D1) — the M-D11 Aave-static-wrapper restoration pattern, not a Balancer-submodule edit (§8c). Of the 16 Sector-3 slots, 14 are clean Standard 26/26/16/16/16 (QG = svZCHF 26% + stable-core 26% = 52% floor); the `*on` tokenized equities / ETFs bind as `TokenType.STANDARD` ERC-20 theme legs (address-only, no RP), so they do not gate the Quality Gate.

**Deferred (not built):** the two hard-blocked Majors **04 ixViatica** and **07 ixCambio** stay deferred (N-D0) — `fBRZ` (ixViatica theme) has no mainnet address and `aEURS` (ixCambio yield core, QG-critical) is not in the Aave address book; neither resolves to the E-D17 verified-literal bar. They re-enter only once their token / RP composition resolves to verified mainnet literals.

**Dependencies:** same as Stage M — pool-deployment framework (E) + full governance stack (K) live; founding pools seeded at deploy (M-D6 / K-D9), not gauge-voted. The two sfrxUSD-core Standard pools (**20 ixMagnix**, **27 ixAurix**) and both ex-M Majors depend on the N3 Aureum-deployed RP surface, whose address threads into the `pure`-literal configs and the fork fixture per N-D7 (locked at N3.0).

**Testing strategy:** mainnet fork (`test/fork/StageNIntegration.t.sol` + `test/fork/DeployStageN.t.sol`), mirroring M-D10 — binding-liveness + 52% Quality-Gate re-assert via `evaluateEligibility` + Rate-Provider resolve (`getRate() > 0`, now covering the four new RP instances + the sfrxUSD legs on 20 / 27) + hook attach; not live emission accrual. The new `src/rate_provider/` surface also carries unit tests (N3) and a WN whitehat pass (N7, N-D6) before the tag.

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
  - Call `gaugeRegistry.registerGaugeFromComposition(newPool)` (or equivalent **governance-only** entry — exact name at Stage G lock) — no automatic boost (**O-D3**); cold-start support is the optional Incendiary Boost available to any gauged pool, per `08_bootstrap.md` §xxi.
  - Call `miliariumRegistry.replaceSlot(slotN, newPoolAddress)`.
  - The deprecated pool's hook stays attached per Q1.5 — it continues routing fees to Bodensee for as long as anyone trades on it.

**Dependencies:** governance (K), registry (J), gauge registry (G), all 28 pools deployed (M, N) as the realistic replacement-target universe.

**Testing strategy:** mainnet fork. Deploy a candidate replacement pool, submit composition challenge via governance, run the vote, execute the replacement, verify all four state changes happen atomically, verify the deprecated pool's hook keeps firing on post-deprecation swaps.

**Why placement here (not inside Stage K):** replacement-pool testing benefits from having all 28 pools deployed as the replacement-target universe.

**Completion (2026-06-30, `stage-o-complete`):** Landed narrower than the "Builds" sketch above (O-D0). Stage K already shipped the atomic deprecate-and-replace skeleton (`proposeCompositionChallenge` → 2/3 vote → `_executeProposal`: `revokeGauge` + `replaceSlot` + `registerGaugeFromComposition`); Stage O's delivered surface is the one programmatic §xxvii check K-D6e omitted — `GaugeEligibility.meetsCompositionQualityGate(pool)` (≥52% admitted-4626 + canonical fee-routing hook (O-D2a) + Aureum-factory provenance), delegated through `IGaugeRegistry` / `GaugeRegistry` (K constructor untouched) and gating `AureumGovernance.proposeCompositionChallenge` (pre-deposit) + `_executeProposal` (pre-mutation) via `CompositionQualityGateFailed` (O-D2 / O-D7, I13-class fix-forward — Stage-K tag untouched). Stale 90-day-boost docs struck (O-D3); orphaned `CCBMultiplier.activateBoost` flagged for the Stage-P sweep (O-D4); no Aureum Router (O-D5, D33 closed); no pool restoration (O-D6). Whitehat WO: F-12 Fixed (factory-provenance spoof). Fork-tested via `test/fork/StageOIntegration.t.sol`; 872 unit + 124 fork green. Detail: `docs/STAGE_O_PLAN.md` (Completion log) + `docs/STAGE_O_NOTES.md` (O-D0—O-D9 + O-D2a).

**Tag:** `stage-o-complete`.

---

## Stage P — Full-system deployment + testnet stubs + integration validation

**Goal:** get the full protocol running as one system on a public testnet. First stage where the whole stack exists in one deployment.

**Builds:**
- `test-stubs/` — minimal stub contracts for: svZCHF, sUSDS, ixEDEL, and the major theme tokens (waEth wrappers, Aave Prime GHO, fBRZ, `*on` tokenized-asset stand-ins, JPYC, tGBP). Each stub: deterministic, non-upgradeable, ~50-100 LOC, implements the relevant interfaces (`IERC20`, `IERC4626` with `totalAssets` / `convertToShares` / `convertToAssets`, NAV-providing methods for ixEDEL). Kept under the same audit-inheritance discipline as real contracts.
- Testnet deployment scripts (network-parameterised per P-D1) for the full Aureum stack pointing at the stubs.
- Frontend integration: the `aumm-app` MVP (separate repo per OQ-18) wires against the testnet deployment (the live target is a P-bis decision, P-D1).

**Dependencies:** all prior stages (C through O) complete and tagged. Frontend MVP ready (OQ-18/OQ-19 — external dependency, not part of this contract sequence).

**Testing strategy:** end-to-end validation of the full system:
- Governance flows: submit and pass each of the **three** proposal types (gauge challenge, composition challenge, fee).
- **Gauge activation workflow:** satisfy Stage G eligibility on a deployed non-Miliarium pool (`activateGauge`), verify AuMM emission path opens without a vote.
- Fee routing through hook: real trades on testnet-deployed Miliarium pools, verify svZCHF reaches Bodensee.
- CCB scoring: advance testnet blocks to simulate a protocol-month, verify multiplier updates and EMA decay.
- Composition challenge dry-run: deploy a replacement candidate, submit proposal, pass supermajority, verify replacement.
- Authorizer migration: execute the `Vault.setAuthorizer` transaction, verify governance now holds authorizer power.
- Halving boundary (if feasible given the testnet's block rate and time-budget): simulate a halving transition.
- Symbolic-execution pass (pre-audit): run hevm (Argot Collective) against the Aureum-owned contracts — especially the OQ-1 fee-routing hook, CCB multiplier/EMA engine, and the authorizer-migration window invariants — as cheap shakeout before Stage Q's code freeze. Intent is to catch the class of issues the tier-1 audit would otherwise find on billed hours.

**Mainnet-fork complement:** during this stage, also run the Aureum stack against a Tenderly mainnet-fork devnet for integration testing against real Frankencoin / Aave V3 / Reserve Protocol DTF / Sky / Flux behavior. Not publicly accessible; used by the founding team and (in Stage Q) the audit firm.

**Completion (2026-07-11, `stage-p-complete`):** Landed as two workstreams (P-D0), materially narrower than the Builds sketch above. **(A) White-hat back-fill sweep** — the per-stage audit cadence began only at the Stage-K close, so Stages D/G/H/I/J/L were never audited in isolation; Stage P ran those passes (WH-D/G/H/I/J/L) plus the P6 cross-contract-seam synthesis and the P6.5 INV-1/2/6 invariant harness (640k calls). Findings F-13…F-20 all **Fixed** except F-13 (S5 Low, internal-leg slippage) and F-15 (S9 Low, `VaultClassRegistry` veto live-denominator), both **Accepted-risk** deferred to Stage Q; the ledger carries ZERO open findings (F-01…F-20 = 18 Fixed + 2 Accepted-risk). **(B) Full-system deployment** (P9) — the never-scripted per-stage deploy scripts (`DeployStageF`/`G`/`H` + the granular `DeployIx*` wrappers) and the thin `DeployStageP` orchestrator (12-step `_orchestrate` chain + 4 fail-fast post-conditions, P-D32), validated by `test/fork/StagePIntegration.t.sol` against REAL mainnet literals (P-D0b): `StagePWiringTest` (15 handles + 14 wire-by-wire handoffs) + `StagePEndToEndTest`'s P-D36 7-leg e2e roster (recorder-claim-mint, swap-fee-sweep, the three governance proposal types, CCB month-walk, halving boundary). The e2e's first executions surfaced **F-19** (S7 Low, `TVLOracle._venueRatio` uninitialized-venue liveness) and **F-20** (S8/S9 Medium, the FeeChange proposal type structurally foreclosed by the roster-wide EXCLUSIVE `swapFeeManager` role), both Fixed. **Deferred to P-bis** (P-D23): the `test-stubs/` testnet ERC-20s, the live testnet broadcast, and the `aumm-app` frontend — the fork-based mainnet-literal e2e is the `stage-p-complete` gate, so no testnet stubs gate the tag. **Deferred to Stage Q**: the hevm symbolic pass (P-D9, non-gating, bundles with Act) and F-13 / F-15. `forge coverage` is structurally unavailable under the pinned Balancer-parity toolchain (P-D42 — Yul stack-too-deep); the surfaces-REACHED intent is met by the 877-unit / 136-fork split-form regression + the 20 whitehat PoC suites + the invariant harness + the e2e roster, and `slither .` shows ZERO high/critical in `src/` (155 benign findings; the 2 project-wide highs are upstream Balancer-submodule false-positives, out of scope per §1/§8c). Detail: `docs/STAGE_P_PLAN.md` (Completion Log P0—P11) + `docs/STAGE_P_NOTES.md` (P-D0—P-D42).

**Tag:** `stage-p-complete`.

---

## Stage P-bis — Open-issue close-out + testnet go-live + frontend

> **Restructure decision (2026-07-11, user-directed):** inserted between P and Q so the external audit receives a self-audited, testnet-proven, frontend-connected, frozen candidate — Stage Q narrows to the audit engagement itself. Pulled forward from the former Stage-Q remit: the P-D9 hevm/Act formal-methods bundle and the F-13 / F-15 Accepted-risk dispositions. The letters keep their semantics (Q = audit, R = mainnet); "P-bis" was already the documented name for the deferred deployment bundle (P-D23 / P-D26), widened here to a full tagged stage.

**Goal:** zero open items, the full stack live on a public testnet, and the `aumm-app` frontend running against it. `stage-p-bis-complete` is the frozen audit candidate Stage Q hands to the firm.

**Workstream A — open-issue close-out.** Exit rule per item: **Fixed, Built, or Explicitly-descoped-with-rationale** — nothing silently carried past the tag. Roster as of the P11 close:

- **F-13** (S5 Low, unbounded internal-leg slippage): implement the rate-derived `limitRaw` / `minBptAmountOut` bound, or accept via the quantifying sandwich sim. Pulled forward from Q.
- **F-15** (S9 Low, `VaultClassRegistry` veto live-denominator): propagate the F-06-style snapshot fix, or accept. Pulled forward from Q.
- **hevm + Act formal-methods bundle (P-D9):** run pre-audit against the Aureum-owned contracts (fee-routing hook, CCB engine, emission accrual, authorizer window); specs and results ship in the audit hand-off package. Pulled forward from Q.
- **Multisig-dissolution remainder** (§xxix ↔ K-D9, post-F-20): adjudicate the final wiring step vs an §xxix amendment; if wiring, fire the `setGovernanceContract` rotations (emission-layer governance, `VaultClassRegistry`, `SwapAndDepositToBodensee` donate authority, Miliarium `pauseManager` accounts).
- **D36 permanent fix / F-D11:** env-key namespacing in `test/fork/DeployAureumVault.t.sol`.
- **Direct `ReentrancyGuard.selector` test** via `vm.transientStore` (robustness backport).
- **OQ-20 / OQ-21** (controller-initiated `routeYieldFee` + `BLOCKS_PER_EPOCH` cadence throttle, E-D10) and **OQ-22** (2-hop fallback through ZCHF / sUSDS): build-vs-descope adjudications.
- **Pool restoration:** 04 ixViatica / 07 ixCambio (E-D17 literals bar) + the ixCasper waEthwstETH 16% leg via an Aureum `CompositeRateProvider` + the OQ-I10 recorder-binding remainder — restore, or explicitly descope to the post-launch composition-challenge path (which now exists, Stage O).
- **WK.18** thin-venue populated-roster fork sim; **P-D42** coverage-tooling re-eval.
- **aumm-site spec edits** (user-side, runs in parallel): §viii/§ix per OQ-20/21 + the I-reframe, §xxi sandbox row, F-2 Incendiary amendments, FINDINGS corrections — so the auditors read a spec that matches the code.

**Workstream B — testnet deployment** (the original P-bis bundle, P-D23 / P-D26): the `test-stubs/` testnet ERC-20s (P8; token roster per the Stage-P Builds list above), the canonical Balancer V3 Router redeployed against the Aureum Vault + the `setTrustedRouter` binds (the D33 / O-D5 close-out; the F-09 allowlist seat is waiting), the live testnet broadcast of the full `DeployStageP` orchestration (network choice per P-D1 is the first stage-entry decision), and the F-14 ixAetheron off-chain-conversion ops process + fee-custody item.

**Workstream C — frontend:** the `aumm-app` MVP (separate repo per OQ-18) wired against the live testnet. This repo tracks the milestone plus the deployed-addresses artifact the frontend consumes.

**Ordering:** A → B → C. A before B so the one broadcast carries the fixed code; B before C so the frontend integrates against live addresses.

**Dependencies:** `stage-p-complete`. The `aumm-app` MVP (OQ-18) becomes load-bearing at workstream C.

**Tag:** `stage-p-bis-complete` — the audit-candidate freeze.

---

## Stage Q — External audit + patch cycle

**Goal:** audit sign-off on `stage-p-bis-complete` — the audit engagement only. All pre-audit work (open-issue close-out, the P-D9 formal-methods self-run, testnet go-live, the frontend) completes at Stage P-bis per the 2026-07-11 restructure; the firm receives a frozen, self-audited candidate running live on a public testnet with the `aumm-app` frontend connected.

**Process:**
- Engage audit firm (selection deferred per OQ-17 — candidate list: Trail of Bits, OpenZeppelin, Spearbit, Sigma Prime, Zellic for tier-1; Cantina/Code4rena/Sherlock for contests; Firepan for continuous monitoring).
- Scope: ~4,500 LOC of Aureum-owned new Solidity. Balancer V3 substrate (Vault, pool factories, hooks framework, rate providers) inherits existing Certora verification per `13_appendices.md` §xxxvi and is out of audit scope.
- **Code freeze in effect throughout.** No new features. Only fixes for audit findings.
- Patches land as numbered sub-steps Q1, Q2, ... — each with its own commit, test updates, and completion-log row. Regression-test against mainnet fork after each patch.
- The OQ-1 hook is explicitly on the audit hot path — dedicated review pass recommended.
- The P-D9 hevm + Act formal-methods bundle runs at Stage P-bis (pulled forward per the 2026-07-11 restructure); its specs and results ship in the audit hand-off package. The audit-firm kickoff can still commission additional Act properties where the firm identifies invariants worth exhaustive sweep (the original candidates: 21M AuMM cap never exceeded, halving-era boundaries produce the documented emission curve, no admin-key redirect path exists for emissions).

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
- Verify all Aureum-owned contracts on Sourcify (Argot Collective) in addition to Etherscan. For the byte-identical-to-Balancer-V3 audit-inheritance claim, Sourcify provides independent, decentralised source verification that doesn't depend on one block-explorer's database continuing to serve the source — materially hardens the inheritance argument and costs effectively nothing to do at deployment time.

**Testing strategy:** dry-run the entire deployment against the Tenderly mainnet-fork devnet one final time immediately before mainnet execution. Verify every contract's constructor parameters, every immutable address, every token mainnet address resolved correctly. The dry-run is the last checkpoint; mainnet execution is one-shot.

**Tag:** `stage-r-complete` a.k.a. `mainnet-genesis`.

---

## Completion Log

Updated at the close of each stage. Full per-stage completion logs live in the corresponding `STAGE_X_PLAN.md` files.

| Stage | Tag | Date | Commit | Notes |
|---|---|---|---|---|
| C | `stage-c-complete` | 2026-04-18 | `5342126` | `AureumTime` library + `AuMM` ERC-20 (21M cap, Bitcoin-style halving on `BLOCKS_PER_ERA = 10_512_000`); directory reorg to `src/vault/` / `src/lib/` / `src/token/`; 61 Stage C unit tests + 3 Stage B fork tests = 64/64 green; Slither clean modulo Stage B `unindexed-event-address` residual on `AureumVaultFactory.VaultCreated` |
| D | `stage-d-complete` | 2026-04-25 | `951c338` | `AureumFeeRoutingHook` (568 lines, `BaseHooks` + `IAureumFeeRoutingHook` + `VaultGuard`) implementing OQ-1 50% swap-leg saturation via `Vault.unlock` + nested swap to svZCHF + one-sided add to der Bodensee with trusted-router recursion guard per D10, plus three governance-callable primitives (`routeYieldFee` / `routeGovernanceDeposit` / `routeIncendiaryDeposit`) per D-D2 Option A; `AureumProtocolFeeController` retrofit (D-D7 B10 retarget to `FEE_ROUTING_HOOK`, D-D9/OQ-2 Bodensee yield-collection guard, D-D8/OQ-11 swap-fee band 0.10%/1.00%/0.75%, D-D15 `SplitIsImmutable` lock, D4.7 β1 controller-side `collectSwapAggregateFeesForHook`); `script/DeployDerBodensee.s.sol` fork-only 40/30/30 WeightedPool (AuMM/sUSDS/svZCHF, D11 Rate Providers); 151 Stage D unit + 9 fork = 160/160 green via split-form (Part B `--threads 1` per D35/D36); Slither D8 triage 19/19 inline-suppress (4 structural patterns: `Vault.unlock` transient-lock, deliberate balance-sweep, bounded fee-token loop, `SplitIsImmutable` layout), 0 genuine fixes, post-suppression re-run 0 findings |
| E | `stage-e-complete` | 2026-04-28 | `41a7590` | `AureumWeightedPoolFactory` (peer-inherited `BasePoolFactory` — external `create()` override bypass prevention per E-D11; `QualityGateUnsatisfied(uint256,uint256)` at `MIN_ERC4626_WEIGHT = 52e16`); pool-deployment framework: `script/pools/PoolConfig.sol` struct + abstract `MiliariumPoolDeployer` base + per-pilot deploy wrappers; three pilot Miliarium pools: **ixHelvetia** (slot 01, svZCHF 80% / sUSDS 20%), **ixEdelweiss** (slot 05, waEthUSDC 26% / svZCHF 26% / ixEDEL 48%), **ixAurebit** (slot 14, WBTC 16% / Aave Prime GHO 26% / cbBTC 16% / ixEDEL 16% / svZCHF 26%); fork harness `test/fork/PilotPools.t.sol` (`MiliariumPilotPoolBase` + 3 derived pilot test contracts); 5 QG revert-path unit tests (`test/unit/AureumWeightedPoolFactory.t.sol`); OQ-11 supersession — Bodensee swap fee `0.75%` immutable (`BODENSEE_SWAP_FEE`), Miliarium genesis `0.02%` (`MILIARIUM_SWAP_FEE_GENESIS`), band `0.01%–0.30%`; E10 — forge-std `deal(adjust=true)` Reserve-DTF incompatibility (drop third arg); 156 unit + 12 fork = 168/168 green via D35 split-form |
| F | `stage-f-complete` | 2026-05-04 | `9751378` | CCB scoring engine — F-4/F-5/F-6/F-8 math layer for Stage H emission distribution. Four contracts under `src/ccb/`: **`EMASampler.sol`** (per-pool TVL EMA, alpha = 2/61, permissionless `updateEMA(pool)` once per `BLOCKS_PER_DAY`, F-D15 cold-start sentinel), **`CCBScore.sol`** (F-5 pure-math `score = tvlEMA × multiplier / 1e18` via `FixedPoint.mulDown`), **`CCBShare.sol`** (F-6 pure-math share normalization to 1e18 via `FixedPoint.divDown`, `EmptyScores`/`AllScoresZero` reverts), **`CCBMultiplier.sol`** (F-8 stateful `M_i(t)` with clamp `[0.75e18, 1.25e18]`, ±0.05 per-channel step, dead zone, permissionless `updateMultiplier` per `BLOCKS_PER_EPOCH`, gauge-gated `activateBoost` 1.2× over `GAUGE_BOOST_DURATION_BLOCKS = 648_000` per F-D24); injected `IMiliariumRegistry`/`IGaugeRegistry`/`IEMASampler` interfaces with F-D20/F-D23 one-shot self-seal. OQs RESOLVED — **OQ-22** (svZCHF numéraire, RP-unwrap + constellation-spot, `ITVLOracle`; concrete oracle deferred), **OQ-5a-bis** (per-day spot read; accumulator dropped; layered defense via EMA(60) + F-10 + tier caps), **OQ-23** (i.a per-channel ±0.05 step; ii.c both-channel dead zone; iii.b sum-of-EMAs; iv.a simple-mean-28; v.d boost-gate-and-pause). Test suite: **263/263 green** (247 unit + 16 fork) via D35 split-form. F-D26 (f) artifact accepted (3-pool harness + divisor-28 forces `deltaIntra = -STEP_SIZE`); F-D27 28-pool padding mitigates in unit tests. Vault bytecode untouched — zero edits to `lib/balancer-v3-monorepo/`. Cross-stage lessons: F10 (optimizer hoists `block.number` out of vm.roll loops), F11 (chat auto-links TLD-suffix tokens), F12 (int/uint type discipline in delta arithmetic). |
| G | `stage-g-complete` | 2026-05-14 | `384a40b` | Gauge state machine + auto-gauge eligibility (Stage G pivot, OQ-G1–OQ-G4). Four contracts under `src/gauge/` plus extended-in-place `src/ccb/IGaugeRegistry.sol`: **`VaultClassRegistry.sol`** (Frankencoin-inspired proposal-and-veto admission of ERC-4626 vault classes counted toward the 52% Quality Gate numerator; three admission fingerprints `ImplementationAddress` / `FactoryAddress` / `BytecodeHash` per **G-D9**; constructor-injected genesis arrays per **G-D20**; 201_600-block veto window per **G-D19**; bond routes via `SwapAndDepositToBodensee.donate`), **`SwapAndDepositToBodensee.sol`** (OQ-G3 primitive per **G-D11** + **G-D12** + **G-D21**: strict-equality `swapAndDeposit` for activation fees + variable-amount `donate` for governance-allowlisted bonds; Balancer V3 `calculateSlot` + `tload` / `tstore` transient guard per **G-D14** + **G-D18**), **`GaugeEligibility.sol`** (epoch-boundary evaluator: 52% numerator per **G-D8** + OQ-G2 TVL floor + F-10 cohort via `computeEpochSnapshot` per **G-D3** + **G-D23** with **T-T3** insertion-sort tiebreak + factory whitelist per **G-D6** / **G-D15a** + forbidden-token block per **T-I3**; `onlyGaugeRegistry` gate per **G-D22** + **F-D23**), **`GaugeRegistry.sol`** (three activation paths per **G-D1** + **G-D7**: permissionless `activateGauge` with non-reverting `GaugeActivationFailed` per **G-D16c**, governance `registerGaugeFromComposition`, governance `seedFoundingPool` / `seedFoundingPools` per **STAGE_G_PRECHECK_AUTO_GAUGE** C-4; terminal `revokeGauge` per **G-D17**; Stage K `setGovernanceContract`; 90-day boost deprecated per **G-D13**); plus `IEfficiencyOracle.sol` sibling interface per **G-D23 (ii)** (concrete oracle deferred to Stage H). OQs RESOLVED — **OQ-G1** (F-10 sibling-oracle encoding; `numeratorSma + denominatorSma + efficiencyRatio` event ABI per **G-D23**), **OQ-G2** ($10K svZCHF TVL floor + 7-day SMA cadence), **OQ-G3** (100 svZCHF / 125 sUSDS anti-spam fee + Bodensee donation routing per **G-D12** strict-equality), **OQ-G4** (VaultClassRegistry Frankencoin-style admission per **G-D9** + **G-D20**). Test suite: `VaultClassRegistry.t.sol` 37/37 + `GaugeEligibility.t.sol` 46/46 + `GaugeRegistry.t.sol` unit + `StageGIntegration.t.sol` fork (G4.1–G4.4e + `StageGRegistryStageFRegressionTest`) — all green via D35 split-form (`--threads 1` fork per **D36** / **F-D11**). Stage F **F-D17** regression intact (CCBMultiplier → real `GaugeRegistry` boost-gate via **F-D23** one-shot seal). Vault bytecode untouched — zero edits to `lib/balancer-v3-monorepo/`. Cross-stage findings: **G10** (compile-probe typed-domain syntax before NOTES lock — `transient` keyword unavailable in solc 0.8.26, assembly-helper pattern locked), **G11** (`calculateSlot` not constant-expression-eligible — `immutable` required), **G12** (`using StorageSlotExtension for *;` required to chain typed slot; `for bytes32;` fails second leg), **G13** (`vm.expectRevert(bytes4)` strict-match + `vm.mockCall` synthetic FoT), **G14** (solc 0.8.26 rejects `calldata` on constructor parameters; `memory` mandatory), **G15** (scaffold NatSpec interface-promise drift — close-of-family ambiguity-gate), **G16** (interface-touching §8e.1 fix scope must enumerate ALL inheritors via `grep -rn "is I<InterfaceName>" src/ test/ script/`). |
| H | `stage-h-complete` | 2026-05-23 | `2a33649` | Emission layer — `BodenseeBootstrapChannel` (F-0 bootstrap A/B-leg accrual + Vault-donation `distribute`), `EmissionDistributor` (F-7 continuous per-pool CCB-scored accrual, halving-aware `claim` via `AuMMMinterRouter`), `AuMMMinterRouter` (cap-guarded mint passthrough). H-D1—H-D42. Detail: `STAGE_H_PLAN.md`. |
| I | `stage-i-complete` | 2026-06-06 | `0ee2089` | AuMT LP-receipt layer — per-pool `AuMT` (governance weight with qualification + on-ramp + withdrawal-reset per I-D7, 5-immutable constructor per I-D12), recorder-clock binding through the shared fee-routing hook (I-D9 `setAuMTContractForPool`), `GaugeEligibility` hook-gate add-on (I-D13 / OQ-24). Detail: `STAGE_I_PLAN.md`. |
| J | `stage-j-complete` | 2026-06-07 | `83ef71e` | `MiliariumRegistry` — canonical 28-slot constellation registry (J-D1 dual sparse-slot + dense-enumeration structure, J-D3 fixed 28 slots, J-D5 governance-gated `replaceSlot` + Stage-K handoff), implementing both `IMiliariumRegistry` (CCB read view) and `IMiliariumSlotRegistry` (slot surface) per J-D2. Detail: `STAGE_J_PLAN.md`. |
| K | `stage-k-complete` | 2026-06-11 | `63471f9` | Governance handoff — `AureumGovernance` (three proposal types), `VotingWeight` value-weighted reader, `AureumGovernanceAuthorizer` (OQ-10 12-month emergency time-bomb); Vault authorizer migrated off the Stage-B Safe via `setAuthorizer` (Vault bytecode untouched). Whitehat K-pass + WK-R: F-01—F-06 all Fixed. Detail: `STAGE_K_PLAN.md`. |
| L | `stage-l-complete` | 2026-06-16 | `ae16e3f` | Incendiary Boost — `IncendiaryRegistry` (`buyBoost`: 5 gates + 60-day-EMA rate-scaled valuation, F-04 maturity gate, 5% anti-gaming haircut, FCFS walk-forward into per-(epoch,pool) buckets under the 15%-of-epoch cap; deposit tail donates to der Bodensee), `EmissionDistributor` `poolBoostCursor` delivery leg (L-D25 / I13 fix-forward). Whitehat WL: F-07 Fixed. Detail: `STAGE_L_PLAN.md`. |
| M | `stage-m-complete` | 2026-06-22 | `6c1f5cd` | Miliarium Sector-2 Majors — five yield-core pools (ixCasper 03 / ixBrevis 08 / ixAltrix 09 / ixMediox 10 / ixLongus 11; M-D7 narrowed from ~10 by the M2 token-availability preflight, the other four → Stage N). Per-pool config libs + `DeployIx*.run()` deploys + bind-only `DeployStageM.s.sol` (M-D9: `replaceSlot` + `seedFoundingPool` + `setAuMTContractForPool`); M-D11 ixCasper waEthwstETH→wstETH (Aave-static-wrapper RP revert). Whitehat WM: F-08 / F-09 / F-10 Fixed. 847 unit + 109 fork green. Detail: `STAGE_M_PLAN.md`. |
| N | `stage-n-complete` | 2026-06-26 | `a760421` | 18 pools (N-D0: 16 Sector-3 Standard slots + 02 ixAetheron + 06 ixLibertas); N-D8 native-4626 redesign for ixAetheron (sfrxETH/wOETH, dropping N-D1 stata composites); N-D9 sfrxUSD→ysyBOLD swap (sfrxUSD mainnet `previewRedeem` == 0 post-Fraxtal) across 06/20/27 via new `CompositeRateProvider`. First Aureum-owned `src/rate_provider/` surface: `ERC4626RateProvider` + `CompositeRateProvider` (N-D2/N-D9, re-authored under `src/`, §8c). Bind-only `script/DeployStageN.s.sol` (M-D9 shape; `MILIARIUM_POOL_NN` env scheme, D36-collision-safe). Whitehat WN: F-11 Fixed (fail-closed 18/18-decimal constructor guard on both RP contracts). 864 unit + 119 fork green. Detail: `STAGE_N_PLAN.md`. |
| O | `stage-o-complete` | 2026-06-30 | `e69252f` | OQ-7 composition-fitness gate. K shipped the atomic deprecate-and-replace skeleton (K-D6a—K-D6e); Stage O adds the programmatic §xxvii check K-D6e omitted — `GaugeEligibility.meetsCompositionQualityGate` (≥52% admitted-4626 + canonical hook (O-D2a) + Aureum-factory provenance; supersedes K-D6e per O-D2 / O-D7, I13-class fix-forward), delegated via `IGaugeRegistry` and gating `AureumGovernance.proposeCompositionChallenge` (pre-deposit) + `_executeProposal` (pre-mutation) through `CompositionQualityGateFailed`. Stale 90-day-boost docs struck (O-D3); `CCBMultiplier.activateBoost` orphan flagged for Stage P (O-D4); no Router (O-D5, D33 closed); no pool restoration (O-D6). Whitehat WO: F-12 Fixed. 872 unit + 124 fork green. Detail: `STAGE_O_PLAN.md`. |
| P | `stage-p-complete` | 2026-07-11 | `e25a5dc` | Full-system deployment + the deferred per-stage white-hat back-fill sweep (P-D0). **(A)** WH-D/G/H/I/J/L + P6 cross-seam + the INV-1/2/6 harness — findings F-13…F-20 all Fixed except F-13/F-15 Accepted-risk → Stage Q; ledger ZERO open. **(B)** the P9 deploy scripts + the `DeployStageP` orchestrator, validated by `test/fork/StagePIntegration.t.sol` (`StagePWiringTest` + the P-D36 7-leg e2e roster) against REAL mainnet literals (P-D0b); the e2e surfaced + Fixed F-19 (uninitialized-venue liveness) + F-20 (FeeChange EXCLUSIVE-role foreclosure). Testnet stubs + live broadcast + `aumm-app` → P-bis (P-D23); hevm → Stage Q (P-D9). `forge coverage` structurally unavailable (P-D42); 877 unit / 136 fork green; `slither .` ZERO high/critical in `src/`. Detail: `STAGE_P_PLAN.md`. |
| P-bis | `stage-p-bis-complete` |  |  |  |
| Q | `stage-q-complete` |  |  |  |
| R | `stage-r-complete` / `mainnet-genesis` |  |  |  |

---

## For the next conversation

The next planning conversation should open with **Stage C's detailed plan** — a `STAGE_C_PLAN.md` file in the Stage A / Stage B format: step-by-step C1, C2, ... C-N numbered steps, each with a time estimate, commands to run, files to create or modify, testing procedure, and a Completion Log table at the bottom.

Start that conversation by attaching this file (`STAGES_OVERVIEW.md`), `FINDINGS.md`, `STAGE_A_PLAN.md`, and `STAGE_B_PLAN.md` as context. Ask for "the detailed Stage C plan following the Stage A / Stage B template."
