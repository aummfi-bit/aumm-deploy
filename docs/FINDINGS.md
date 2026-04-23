# Aureum — Findings & Open Questions

*Reconciliation of the `aumm-site` specification (18 numbered docs + 28 pool profiles) against the `aumm-deploy` repository as of `stage-b-complete` (`b627a92`).*

> **Status:** Pre-stage-planning input. Replaces the old "Stage C = mainnet deploy" plan that was implicit in `STAGE_B_PLAN.md`.
>
> **Purpose:** Record (a) the gaps between the spec and the existing code, (b) the corrections needed in the existing code or docs, and (c) the open questions that need human resolution before stage planning can proceed. Lightweight and focused — intentionally not a contract-by-contract inventory. The inventory will land in stage-specific design docs later.
>
> **Sequencing recap (from prior conversation):** mainnet is the LAST stage. Everything before it — implementation of the full tokenomics layer, full-system integration on a public testnet, external audit — happens first. This document does not assign letters; it just records what's there and what isn't. Stage assignment is a separate exercise.
>
> **Code organization:** one repo (`aumm-deploy`), multi-folder layout. Existing `src/Aureum*.sol` will move under `src/vault/`. New work lands in `src/token/`, `src/emission/`, `src/ccb/`, `src/gauge/`, `src/governance/`, `src/registry/`, `src/pools/`, `src/incendiary/` (proposed; subject to refinement).

---

## TL;DR — The five things that matter most

If you read nothing else in this document, read these:

1. **Stage B's fee controller doesn't actually route fees the way the spec demands.** It does an in-kind `safeTransfer` of fee tokens to der Bodensee's address. The spec requires (a) a swap into sUSDS or svZCHF, then (b) a one-sided pool deposit. Both steps are missing. **Architecture resolved as of 2026-04-15** (OQ-1, OQ-1a): a Balancer V3 `IHooks` contract attached to every gauged pool handles swap-fee routing atomically on `onAfterSwap` via the hooks' reentrancy property; the existing fee controller stays for yield-fee collection with its withdraw target re-pointed; a shared swap-and-one-sided-deposit primitive serves all three layers (swap fees, yield fees, governance/Incendiary deposits). Implementation still pending. *(F1 — affects every fee stream the protocol captures)*

2. **There is no Aureum-owned tokenomics code yet — nothing.** No AuMM token, no AuMT, no emission distributor, no CCB, no gauges, no governance, no Incendiary, no Miliarium registry. Stage B built the substrate (a forked Balancer V3 vault + fee controller + authorizer) which is roughly 5% of the total work by line count. The other 95% is what `13_appendices.md` §xxxvi calls "the new tokenomics layer" — ~4,500 lines of new Solidity, none of which has been written. *(F9 — sets the scope)*

3. **ixCambio (slot 07) resolved** — Partner Stable = JPYC (regulated Japanese yen stablecoin); s-tGBP dropped back to plain tGBP (no ERC-4626 wrapper exists on mainnet); pool reweighted to svZCHF 19% / st-EURA 18% / aEURS 18% / ixEDEL 15% / tGBP 15% / JPYC 15%. ERC-4626 composition = 55%, 3 points above the immutable 52% Quality Gate floor. Spec's `07a_tokens.md` also corrected: st-EURA was mislabeled ERC-20, is actually ERC-4626 (Angle's `SavingsNameable` extends OpenZeppelin `ERC4626Upgradeable`), which also bumps ixViatica from 52% to 68% ERC-4626. *(OQ-12, OQ-12a — resolved; F8a / F8b severity revised downward)*

4. **The constitution's §xxix list of "immutable parameters" is incomplete.** At least 10 parameters are described as immutable in other documents (epoch length, quorum floor, deposit amounts, fast-track threshold, Quality Gate threshold, percentile floor schedule, halving block count, etc.) but aren't enumerated in §xxix's canonical list. Pure doc-side fix in `aumm-site`. *(F3)*

5. **Several "obvious" numeric constants aren't actually pinned anywhere.** Specifically: how many blocks is a "protocol month"? How many blocks is a "bi-weekly epoch"? How does der Bodensee's price get derived in a way that's "oracle-free"? Each of these has a probable answer, but the spec doesn't say. Each needs to be decided before code gets written. *(OQ-3, OQ-4, OQ-6, OQ-8)*

The full document below has 12 findings (F1–F12, plus F8a–F8d) and 19 open questions (OQ-1 through OQ-19, plus OQ-12a). Findings are things I'm confident about. Open questions need your call.

**All 19 open questions resolved or deferred (2026-04-15):**

**Resolved:** OQ-1 + OQ-1a (fee router via Balancer V3 hook on `onAfterSwap`, 100% to Bodensee, no LP residual) · OQ-2 (fee-routing target = svZCHF; der Bodensee itself excluded from yield-fee collection — its own yield compounds in-pool via Rate Providers; full mechanism documented as proposed `04_tokenomics.md` §x-a addition) · OQ-3 (protocol month = 219,000 blocks) · OQ-4 (bi-weekly epoch = 100,800 blocks) · OQ-5 (halving = 10,512,000 blocks; **block numbers are canonical time units across the protocol — calendar terms are aliases**) · OQ-5a (EMA = per-day sample with 1-hour intra-day TWAP, alpha = 2/61) · OQ-6 (der Bodensee "hidden Months 0–6" = frontend-only + no router-sharing policy; pool self-hides via lopsided F-0 composition) · OQ-7 + OQ-13 (composition challenge = gauge-revoked-only deprecation, hook stays attached for life, specified-pool model for replacements, no LP migration assistance; AuMT governance weight requires gauged status) · OQ-8 (F-12 BTC = unit of account; price = spot average across all gauged pools holding any registered BTC wrapper; deposit paid in svZCHF/sUSDS one-sided to Bodensee) · OQ-9 (F-12 N includes all gauged pools including target) · OQ-10 (governance↔authorizer = B-strict with 12-month multisig time-bomb) · OQ-11 (per-pool swap fees governable within bands — Miliarium & non-Miliarium 0.01–0.30% with genesis 0.03%, Bodensee 0.10–1.00% with genesis 0.75%, cooldown = `BLOCKS_PER_EPOCH`) · OQ-12 (ixCambio Partner Stable = JPYC; s-tGBP → plain tGBP) · OQ-12a (ixCambio reweighted to svZCHF 19% / st-EURA 18% / aEURS 18% / ixEDEL 15% / tGBP 15% / JPYC 15% = 55% ERC-4626) · OQ-14 (use upstream Balancer V3 pool factories as-is; no fork) · OQ-15 (testnet = hybrid: Holesky stubs + mainnet fork) · OQ-16 (Holesky now) · OQ-18 (frontend = separate repo `aumm-app`, separate plan, MVP required for testnet and mainnet launch; post-MVP roadmap rolled out over subsequent protocol-months).

**Deferred (not blockers):** OQ-17 (audit firm — candidate list captured: Trail of Bits, OpenZeppelin, Spearbit, Sigma Prime, Zellic for tier-1; Cantina/Code4rena/Sherlock for contests; Firepan for continuous AI-augmented monitoring) · OQ-19 (founding team roles — stays TBD; cross-dep with OQ-18 for frontend timing).

**FINDINGS is complete.** All architectural, design, and protocol-ambiguity questions have been resolved. The two deferred items are operational/organizational, not gating for stage-sequence planning.

---



## Table of contents

1. [Methodology](#methodology)
2. [Findings](#findings) — what's wrong, missing, or needs aligning
3. [Implied contracts inventory (summary)](#implied-contracts-inventory-summary) — the size of the gap
4. [Open questions](#open-questions) — what needs human resolution
5. [What this document does NOT decide](#what-this-document-does-not-decide)

---

## Methodology

- Read the full canonical spec corpus — 18 numbered/supporting docs (`/mnt/user-data/uploads/aumm-specs.md`, 2190 lines) and the 28 pool profiles (`/mnt/user-data/uploads/aumm-pools.md`, 1542 lines).
- Cross-referenced against the `aumm-deploy` source tree at `stage-b-complete` (project knowledge sync).
- Used `script.md` (the spec-side internal review log) as a hint, but verified each item — multiple R-* items in `script.md` are now stale and have been fixed in the live spec.
- For every claim with a numeric or structural implication, cite the source line in the spec bundle (line numbers are within `aumm-specs.md` unless noted).
- Where the spec is ambiguous or under-specified, log it as an open question (`OQ-N`) instead of guessing.

---

## Findings

The findings are grouped by severity:

- **F1–F2: Architectural** — significant implementation/spec gaps in the existing Stage B code.
- **F3–F8: Doc-alignment** — places where docs (spec or stage plans) say slightly different things and need to be unified.
- **F9–F12: Scope** — the size and shape of what doesn't exist yet.

### F1 — Fee routing in Stage B is in-kind transfer, but spec requires swap-and-one-sided-deposit

**Severity: HIGH (architectural).**

**Spec says** (`10_constitution.md` §xxix, line 286; `04_tokenomics.md` §x lines 553–567; `11_formulas.md` F-11 lines 882–884; `12_aureum_glossary.md` xxxii lines 1714):

> Fee routing (swap fees on Miliarium and other non–der Bodensee pools): **100% to der Bodensee Pool as one-sided stablecoin (sUSDS/svZCHF) inflows**. ERC-4626 yield fee (10% skim): 100% to der Bodensee Pool as one-sided stablecoin inflows.

The spec is consistent across at least four documents that fees arrive at der Bodensee as **(1) sUSDS or svZCHF, after a swap from whatever fee token was collected**, and **(2) as a one-sided pool deposit, not a token transfer**.

**Current code does** (`src/AureumProtocolFeeController.sol`, `withdrawProtocolFees` and `withdrawProtocolFeesForToken`): a `_withdrawProtocolFees` helper that calls `SafeERC20.safeTransfer(token, DER_BODENSEE_POOL, amount)`. For every fee token of every pool, the raw fee token (could be WBTC, LINK, NVDAon, anything) is transferred directly to der Bodensee's address.

**Two missing pieces:**

1. **The swap.** Fee tokens that aren't already sUSDS or svZCHF need to be swapped into one of the two before deposit. The current contract has no swap logic.
2. **The one-sided deposit.** A `safeTransfer` to a Balancer V3 pool's address puts tokens in the pool's ERC-20 balance, but **does not register them as pool liquidity** — the pool's accounted reserves don't update, no LP tokens (or non-LP-token credit, in the one-sided case) are issued, and the weighted-pool math doesn't see the added depth. To actually deepen der Bodensee's reserves, the controller (or a separate fee router) needs to call `Vault.addLiquidity(...)` (or whatever the Balancer V3 weighted-pool one-sided-add primitive is) on der Bodensee's behalf. The current implementation results in orphaned token balances, not reserve deepening.

**What this means for Stage B status.** The existing fee controller is correct in its access control, its B10 recipient enforcement, its B3 creator-fee disabling, and its constructor immutability. None of that needs to change. What's wrong is the *withdraw destination behavior* — the literal `safeTransfer` step.

**Disposition (resolved 2026-04-15 via OQ-1):** A Balancer V3 `IHooks` contract attached to every gauged pool handles swap-fee routing atomically on `onAfterSwap`, exploiting hooks' reentrancy property to swap-to-stablecoin and one-sided-add to der Bodensee in the same transaction as the originating swap. The existing `AureumProtocolFeeController` stays in place to handle the yield-fee leg (which can't ride a swap hook because ERC-4626 yield doesn't accrue through swaps); its B10 recipient enforcement target moves from `DER_BODENSEE_POOL` to the new hook/router address. A shared swap-and-one-sided-deposit primitive serves all three layers (swap fees, yield fees, governance/Incendiary deposits). See OQ-1 for the full design.

**Note on the upstream pattern.** Balancer V3's stock `ProtocolFeeController.withdrawProtocolFees` is also a token transfer to a recipient — the spec's requirement to swap-and-deposit is fundamentally a deviation from the upstream pattern, not an oversight of the Aureum implementation. Designing the swap-and-deposit pipeline is genuinely new work, but the hook approach localizes that work in a new Aureum-owned contract (`AureumFeeRoutingHook.sol`) rather than expanding the diff against upstream `ProtocolFeeController.sol`.

---

### F2 — README mis-describes the fee controller (and Stage A decision #3 is superseded)

**Severity: MEDIUM (doc alignment).**

**README.md current text:** *"Routes 100% of protocol-extractable fees (both swap and yield, per the protocol fee percentage set per pool by governance up to a 50% cap) to the immutable der Bodensee Pool address set at deploy time."*

This was already noted in `STAGE_B_NOTES.md` housekeeping queue item #4 as needing reconciliation. The text accurately describes what the *current code* does, but per F1+OQ-1 the current code is itself incomplete relative to the spec. After OQ-1 is implemented, the README should describe the hook-based architecture, not the current `safeTransfer` behavior.

**Also: Stage A decision #3 is superseded.** Decision #3 says: *"Fee split: 50% of swap fees (the maximum the V3 Vault permits via MAX_PROTOCOL_SWAP_FEE_PERCENTAGE) routes to der Bodensee. The other 50% stays in-pool with LPs."* This was an honest workaround for the Vault's hard cap on protocol-extractable swap fees. Under the OQ-1 hook design, the hook takes 100% of the fee directly (Vault-side protocol fee on Miliarium pools is set to 0; the cap doesn't apply because the fee is collected outside the Vault's protocol-fee mechanism). Per OQ-1a, **none of the fee stays with Miliarium LPs** — the spec is unambiguous that 100% goes to der Bodensee. Decision #3's "50% stays with LPs" is therefore wrong under the spec as resolved. **`STAGE_A_PLAN.md` decision #3 needs to be updated** to reflect the OQ-1 hook design and the OQ-1a "no LP residual" rule.

**Also: README minor cleanups (already housekeeping items):**
- Says *"Stage B (B0–B4 complete, B5–B7 in progress)"* — should say *"Stage B complete (`stage-b-complete` tag at `b627a92`)"*.
- Says *"It does not contain the AuMM token, gauges, CCB engine, or any tokenomics-layer contracts. Those live in a separate repository."* — superseded; everything will live in this repo per the one-repo decision.

---

### F3 — Constitution §xxix immutable parameters list is missing several parameters that are immutable per the rest of the spec

**Severity: MEDIUM (doc alignment, single-source-of-truth violation).**

§xxix says it is the "Single canonical source for all immutable protocol parameters. Other documents should cite this section rather than restating values" (line 278). But the bullet list at lines 282–294 doesn't include the following items, all of which are immutable per other documents:

| Missing item | Asserted immutable in |
|---|---|
| Bi-weekly epoch length (14 days, in blocks) | Bootstrap §xxii line 1442 ("All parameters immutable from block 0: 1-epoch (14-day) duration"); referenced everywhere |
| 20% governance quorum floor | Constitution §xxvii line 237; tokenomics §ix Low-Turnout Safeguard line 519 |
| Gauge proposal deposit: 100 svZCHF/sUSDS equivalent | Constitution §xxvii table line 230; bootstrap §xxiv line 1543 |
| Fee proposal / composition challenge deposit: 1,000 svZCHF/sUSDS equivalent | Constitution §xxvii table lines 232–233 |
| Composition challenge 2/3 supermajority threshold | Constitution §xxvii line 233 |
| 90-day gauge boost duration and 1.2× multiplier value | Bootstrap §xxi line 1421; §xxiii line 1457 |
| der Bodensee swap fee 0.75% | Asserted in §xxix narrative at line 287 but not in the canonical bullet list |
| Sandbox fast-track threshold (top 10% efficiency for 3 epochs) | Bootstrap §xxi line 1404 |
| ERC-4626 Quality Gate threshold (≥52% by weight; per-token vault floor of $5M / 30 BTC / 4M svZCHF) | Bootstrap §xxiii line 1451 |
| Volume percentile floor schedule (5% / 10% / 15% by month 3 / 6 / 13) | Bootstrap §xxiii line 1452, §xxiii grace-period table line 1471 |
| Efficiency tournament tier breakpoints (15/10/5 percentiles → 1%/0.5%/0.1% caps) | Bootstrap §xxiii line 1502 |
| Minimum TVL floor ($10K, 7-day SMA) | Bootstrap §xxiii line 1452 |
| Disqualification threshold (4 consecutive epochs → gauge revocation) | Bootstrap §xxiii line 1527 |
| Governance qualification period (14 days) and on-ramp duration (~6 months) | Tokenomics §ix lines 505–507 |
| Emission halving block count (10,512,000) | Tokenomics §ix table line 427 (asserted in tokenomics, but §xxix only says "Emission halving schedule and block emission rates" without the constant) |

Most of these have a single concrete number, asserted once in the file that introduces them, and referenced as "immutable" elsewhere. §xxix's job is to be the canonical home for all of them. The discrepancy isn't a design problem — these *are* immutable — it's a single-source-of-truth completeness problem.

**Disposition:** edit `10_constitution.md` §xxix to enumerate everything. Pure doc-side change in `aumm-site`. No code impact.

---

### F4 — `script.md` is stale and should be updated or replaced

**Severity: LOW (doc hygiene).**

`script.md` is the internal review log on the spec side. I checked the items it flags:

- **R-1** (Era labeling error in `13_appendices.md:84`, "fourth root in Era 1" should be "Era 0"): I confirmed the fix has landed. `13_appendices.md` Governance Capture row at line 1849 of the spec bundle now correctly says "fourth root in Era 0".
- **R-2** (Six pool profiles incomplete at 22-25 lines): I confirmed all six (08, 09, 10, 21, 23, 25) are now 55-56 lines, same as the standard profiles. Fixed.
- **R-3** (§xxix missing governance dampening exponents): Fixed — now line 292 of the spec bundle.

So three of the four "Required" items in script.md are already resolved. Only R-4 (missing `sitemap.xml`) and R-5 (TBD founding team roles) remain.

**Disposition:** update or delete `script.md` — it's misleading as currently written. Pure spec-side cleanup. No code impact, but worth doing so future readers (human or LLM) don't trust stale guidance.

---

### F5 — Glossary §xxxiv "Controls (Immutable)" duplicates the constitution but with slightly different wording

**Severity: LOW (doc alignment).**

`12_aureum_glossary.md` §xxxiv (line 1741–1748) lists:

```
- no admin keys
- no multisig
- no upgradeability
- no pause function
- no voting over emissions
- no external oracle dependency for core operation
```

`10_constitution.md` §xxvii lists the same six (line 213–218) but says "no off-chain dependencies for core operation" instead of "no external oracle dependency". Also the constitution's §xxix bullet list (line 294) compresses these into one bullet: "No admin keys, no multisig, no upgradability, no pause functions" — without the "voting over emissions" or "off-chain/oracle" parts.

**Disposition:** unify the wording. The "no multisig" / "no pause function" framing is also where the constitutional carve-out for the bounded 4-year emergency capability needs a footnote (see F6 below).

---

### F6 — Constitutional carve-out for the bounded 4-year emergency capability is documented in `STAGE_A_PLAN.md` but not in the constitution itself

**Severity: MEDIUM (doc alignment, between spec and stage plan).**

The constitution says "no multisig, no pause function" three times (`10_constitution.md` §xxvii, §xxix; `12_aureum_glossary.md` §xxxiv) without qualification.

`STAGE_A_PLAN.md` decision #4 explicitly defines the carve-out: *"a single Safe multisig address ... matches 'no treasury, no wallet' in spirit while preserving the ability to pause/recover for the Balancer-default 4-year window. After the pause window expires, even the multisig cannot pause."* And decision #7: *"After 4 years from deployment, even the governance multisig can never pause the Vault again."*

Per the previous conversation, this carve-out is intentional, settled, and analogous to Balancer's own pattern. But the constitution doesn't acknowledge it. A fresh reader of the spec would see "no multisig, no pause function" and conclude the implementation is wrong.

**Disposition:** Add a footnote to `10_constitution.md` §xxvii (and probably §xxix and `12_aureum_glossary.md` §xxxiv) acknowledging that during the bounded 4-year pause window inherited from Balancer V3, a single emergency multisig exists with pause/recovery capability only — and that after the pause window expires, all six "no..." controls become unconditionally true. Pure doc-side change in `aumm-site`. No code impact.

---

### F7 — Glossary FAQ duplicates the cap on der Bodensee swap fee differently than the canonical source

**Severity: LOW (numeric consistency).**

A small but worth-noting pattern: der Bodensee's 0.75% swap fee is asserted in many places — `10_constitution.md` §xxix line 287; `04_tokenomics.md` §x-a line 579; `11_formulas.md` F-11 line 877; `05_miliarium_aureum.md` §xii line 1089; `12_aureum_glossary.md` line 1714 ("0.75%"); `09_transitions.md` Month 1 line 1632 ("0.75%"); UX §xlvi line 1953. All consistent at 0.75%.

But the worked example in `04_tokenomics.md` Reserve Depth Growth table (line 620) uses `$20M/day × **0.05%** fee × 100% to Bodensee` — a 0.05% rate. This is for **non-Bodensee pool** swap fees (the routing/Miliarium pools, which target a 0.01–0.05% fee tier per `13_appendices.md` line 1884) so it's not actually wrong, but it can confuse readers who skim.

**Disposition:** clarify the example caption to say "0.05% representative non-Bodensee pool fee" or similar. Pure doc-side. No code impact. **Also note:** the "0.01–0.05%" Miliarium-pool fee tier asserted in `13_appendices.md` line 1884 is described as "(attracts routing)" — but I don't see this stated as immutable anywhere. **Is the per-pool swap fee for Miliarium pools immutable, or is it within the "fee parameters within immutable bounds" governance scope?** This is **OQ-11** below.

---

### F8a — ixCambio (slot 07) self-reports 4626 Quality Gate compliance as borderline; depends on Partner Stable being ERC-4626

**Severity: HIGH (architectural — interacts with immutable rule).**

`miliarium_profiles/07_ixCambio.md` (Composition note): *"32% minimum (svZCHF + aEURS) — may require Partner Stable to be ERC-4626 to meet 52% gate, or may qualify under a non-standard exemption given its routing infrastructure role."*

The 4626 Quality Gate is asserted as **immutable** in `08_bootstrap.md` §xxiii line 1457: *"All eligibility criteria are immutable from block 0. No governance vote can waive, modify, or relax them."* So "non-standard exemption" is not actually possible under the spec as written.

This means one of two things must be true:
- **(a)** Partner Stable must be an ERC-4626 vault. With 32% existing 4626 (svZCHF 16% + aEURS 16%) plus a 16% ERC-4626 Partner Stable, ixCambio hits 48% — still 4% short. So Partner Stable being ERC-4626 alone isn't enough; weights would also need to shift, OR another existing component would need to be re-weighted.
- **(b)** ixCambio launches in Sandbox mode (no gauge, no emissions) until composition issues resolve, then submits a gauge proposal once compliant.
- **(c)** The Quality Gate spec needs an explicit carve-out for routing-infrastructure pools (slots 05, 06, 07) — but this requires a constitution edit.

Either way, ixCambio is not deployable as a gauged pool under the current spec without resolving this. **Not a finding I can resolve unilaterally** — it's a real spec-vs-pool inconsistency. Logged as **OQ-12a** below.

### F8b — Several connector pools sit very close to the 4626 Quality Gate floor

While I'm here:
- ixHelvetia: 100% ERC-4626 (svZCHF 80% + sUSDS 20%) — comfortable margin
- ixAetheron: 54% (waEthrETH 27% + waEthweETH 27%) — 2% margin
- ixEdelweiss: 54% (waEthUSDC 18% + waEthUSDT 18% + svZCHF 18%) — 2% margin
- ixLibertas: 57% (scrvUSD 15% + GHO 14% + sUSDS 14% + sfrxUSD 14%) — 5% margin
- ixCambio: 32% (svZCHF 16% + aEURS 16%) — 20% **deficit** (per F8a)

The 2–5% margins on ixAetheron, ixEdelweiss, ixLibertas mean small drift in token weights (e.g. due to rebalancing or composition challenges) could trip the 52% floor. Worth knowing — not actionable yet.

### F8c — ixLibertas at 7 tokens is at the edge of Balancer V3 Weighted Pool MAX_TOKENS

Per `docs/balancer_v3_reference.md` (Stage A reference doc), Balancer V3 Weighted Pool's `MAX_TOKENS = 8`. ixLibertas has 7. ixCambio has 6 (5 + Partner Stable placeholder). The other 26 pools have 4–5 tokens. Within limits, but a structural constraint to keep in mind: composition challenges to ixLibertas can't add tokens, only swap.

### F8d — Pool profile 16 (ixDebitum) names `Morpho` and `SPK` as theme assets without confirming they exist as ERC-20s with sufficient liquidity

**Severity: LOW (sourcing).**

Spot-check while reading the profiles. The 28-pool registry lists every theme asset, and most are well-known established tokens. A few are less obvious:

- **`Morpho`** — Morpho protocol governance token. Exists.
- **`SPK`** — Spark protocol governance token. Exists.
- **`ETHPLUS`** — Reserve Protocol ETH+ basket. Exists.
- **`OPEN`** — Reserve Protocol governance. Exists.
- **All `*on` tickers** (SPYon, NVDAon, SHYon, etc.) — labeled as "Tokenised ETF/equity, Backed/tokenised ETF wrapper" in `07a_tokens.md`. These are real but require confirmation of issuer and liquidity at deploy time.
- **`[Partner Stable]`** in ixCambio (`07a_tokens.md` line 1373) — explicitly TBD. **Blocks ixCambio deployment** until decided. This is **OQ-12** below.
- **`fBRZ`, `fWETH`, `fWSTETH`** (Flux Finance) — these need to still exist on mainnet at launch time. Flux's status should be confirmed.
- **`s-tGBP`** in ixCambio (line 1355) — "Tokenised GBP". Single source, smaller than the others.

This isn't a finding so much as a flag for what the launch-prep stage will need: a token-by-token verification pass with on-chain addresses and liquidity check. Several entries in `07a_tokens.md` have blank "Ethereum address" and "Rate providers" columns by design ("blank until wired on-chain"). Filling these in is a real piece of pre-launch work.

---

### F9 — The size of the gap (high-level)

The spec implies the following major Aureum-owned contract groups, none of which exist in `aumm-deploy` today:

| Group | Purpose | Implies |
|---|---|---|
| **Token** | AuMM ERC-20 with 21M cap, halving math; AuMT tessera with time-weighting and withdrawal-reset | 2 contracts |
| **Emission distributor** | Per-block streaming, halving block boundary, F-0 piecewise bootstrap, F-1 equal split, F-3 linear blend, F-7 full sequence | 1-2 contracts plus epoch/month time math library |
| **CCB** | TVL EMA(60) per-pool (F-4), CCB score (F-5), CCB share normalization (F-6), CCB multiplier update (F-8) with clamp/dead-zone/step | 2-3 contracts |
| **Gauge system** | Gauge registry, eligibility checker (4626 Quality Gate, min TVL, volume percentile floor, efficiency tournament F-10, no self-referential tokens), graduated grace period, hysteresis buffer, Sandbox fast-track, 90-day gauge boost, gauge revocation | 4-5 contracts |
| **Governance** | AuMT-weighted voting, F-9 dampening (Era 0 fourth root → Era 1 cube root), 14-day qualification, 6-month on-ramp, withdrawal reset, 20% quorum floor, four proposal types, F-12 deposit math, on-chain-data-only proposal validation | 3-4 contracts |
| **Fee router** | Swap fee tokens to sUSDS/svZCHF; one-sided deposit into der Bodensee. Either inside the existing fee controller or as a separate contract (F1 / OQ-1) | 0-1 new contracts depending on F1 resolution |
| **Pool deployment** | der Bodensee Pool (three-token weighted, fixed 40/30/30, 0.75% fee); 28 Miliarium pools (mostly 52/16/32 with non-standard shapes in slots 01, 02, 05, 06, 07, 11) | Deployment scripts + per-pool config; the pools themselves are unmodified Balancer V3 weighted pools |
| **Registry** | Miliarium Aureum registry of 28 slots with status (Active / Warning / Disqualified / Composition-Challenge) | 1 contract |
| **Incendiary Boost** | F-2 priority skim, epoch-locked claims, 14-day duration, deposit-anything mechanic (also depends on swap-to-stablecoin from F1) | 1 contract |
| **Time / epoch math** | Block ranges for protocol months, bi-weekly epoch boundaries, halving block calculation | 1 library |

Appendix xxxvi's estimate of ~4,500 lines of new Solidity for audit scope is consistent with this list.

**The Stage B output (vault, authorizer, factory, fee controller minus the F1 gap) is the substrate this all sits on top of.** It's roughly 5% of the work by line count.

---

### F10 — `AureumAuthorizer` is the chokepoint for all governance enforcement, but the *governance system itself* doesn't exist yet

The spec's four governance proposal types (gauge proposal, gauge challenge, fee proposal, composition challenge) all assume a governance contract that submits proposals, runs the vote (with F-9 dampening, 20% quorum, AuMT-weighted), enforces the timelock, and — for fee proposals only — calls into the Vault via `vault.setStaticSwapFeePercentage(...)` after a successful vote, which routes through `AureumAuthorizer.canPerform()`. The other three proposal types (gauge proposal, gauge challenge, composition challenge) manipulate Aureum-owned registries directly and don't touch the Vault or the authorizer.

The Stage B `AureumAuthorizer` returns true only for `GOVERNANCE_MULTISIG`. The governance contract, when built, needs an authorizer path.

**Disposition (resolved 2026-04-15 via OQ-10):** B-strict with a 12-month multisig time-bomb. New `AureumGovernanceAuthorizer` deployed alongside the governance contract; multisig signs one `Vault.setAuthorizer(newAddr)` transaction at migration; from that block forward, the governance contract is the primary authorized account, and the multisig retains emergency-only authority (`pauseVault`, `enableRecoveryMode`, possibly `disableQuery`) for **`EMERGENCY_WINDOW_BLOCKS = 2,628,000` blocks** (12 protocol months). After that block, the multisig clause is permanently dead. See OQ-10 for the full design.

This isn't a flaw in Stage B — it's the consequence of building substrate before tokenomics. The Stage B authorizer ships as-is and gets migrated out cleanly when the governance stage lands.

---

### F11 — Spec assumes "Aequilibrium factory" with permissionless pool creation from block 0

`08_bootstrap.md` line 1390: *"Pool creation is permissionless from block 0. Anyone can deploy any pool with any composition at any time. The Aequilibrium factory is open."*

Aureum has a Vault and a one-shot Vault Factory (which creates the Vault itself, not the pools). What the spec calls "the Aequilibrium factory" is presumably Balancer V3's pool factory contracts — `WeightedPoolFactory`, `StablePoolFactory`, etc. — which are separate from the vault. `docs/balancer_v3_reference.md` notes these are "needed in future stages for der Bodensee Pool deployment and Miliarium Aureum pool creation."

So pool creation is unblocked once the Aureum Vault is deployed (Stage B got us this far) — anyone can call into the existing Balancer V3 pool factories pointing at Aureum's Vault. No new contract is needed *for permissionless pool creation*. What's needed is:

- Deployment scripts for der Bodensee Pool (one-time, into the Aureum Vault).
- Deployment scripts for the 28 Miliarium pools (one-time, into the Aureum Vault).
- Probably the gauge system (F9) which gates emissions but not pool creation.

Worth confirming: is there any reason to fork or replace the Balancer V3 pool factories themselves, or do we use them as-is? **OQ-14 below.**

---

### F12 — Aureum needs to interact with multiple external systems (Frankencoin, Sky, Aave V3 wrappers, Reserve Protocol DTF, Flux, Sky USDS) — all of which need to exist and function on whatever network we test/deploy to

The spec depends on real, mainnet-only token contracts:

- **svZCHF** — Frankencoin's savings vault, exists on mainnet
- **sUSDS** — Sky savings rate vault, exists on mainnet
- **ixEDEL** — Reserve Protocol DTF, exists on mainnet
- **GHO**, **scrvUSD**, **sfrxUSD**, **PYUSD** — major stables/ERC-4626 vaults on mainnet
- **waEth*** — Aave V3 stata token wrappers
- **fWSTETH**, **fWETH**, **fBRZ** — Flux Finance vaults
- All the `*on` tokenized ETFs and equities — depend on the issuer (Backed, etc.)

**On Holesky / Sepolia, none of these exist.** Testnet integration testing requires either:
- (a) Mock all of them. Loses the property that we're integration-testing against the real upstream behavior.
- (b) Deploy stub versions that mimic the relevant interfaces (ERC-4626 `totalAssets()` / `convertToShares()`, etc.). Substantial test-side scaffolding.
- (c) Find Holesky/Sepolia deployments where they exist (some may, most won't).
- (d) Use a mainnet fork as the testnet — Tenderly devnets, or local Anvil instances forked from mainnet at a stable block.

This isn't a finding so much as a constraint to plan around. The right answer probably involves a mix — **OQ-15 below.**

---

## Implied contracts inventory (summary)

To avoid bloating this document with line-by-line contract specs, here's the high-level summary. The detailed designs land in stage-specific design docs as we get to each stage.

| Existing | Folder (proposed) | Status |
|---|---|---|
| `AureumAuthorizer.sol` | `src/vault/` | EXISTS, may need replacement when governance contract ships (F10) |
| `AureumVaultFactory.sol` | `src/vault/` | EXISTS, complete for vault deployment |
| `AureumProtocolFeeController.sol` | `src/vault/` | EXISTS but incomplete: missing swap-and-deposit logic (F1) |

| To be built | Folder (proposed) | Major dependencies |
|---|---|---|
| AuMM (ERC-20, fixed cap, halving math) | `src/token/` | Time/epoch math |
| AuMT (LP tessera) | `src/token/` | Per-pool TVL reads |
| Time/epoch math library (months, epochs, halving block) | `src/lib/` | None — this is foundational |
| Emission distributor (F-0, F-1, F-3, F-7) | `src/emission/` | AuMM, time/epoch, gauge registry |
| CCB EMA + score + share + multiplier (F-4 through F-8) | `src/ccb/` | TVL reads from Vault, time/epoch |
| Gauge registry + eligibility (F-10, anti-gaming) | `src/gauge/` | Vault, time/epoch, AuMM emissions |
| Governance voting (F-9 dampening, 20% quorum, 14-day qualification, 6-month on-ramp) | `src/governance/` | AuMT, time/epoch, AuMM (for proposal deposits via fee router) |
| Fee router (swap-to-stablecoin + one-sided deposit) | `src/fee_router/` (new folder) | Vault, der Bodensee Pool, Aequilibrium routing |
| Incendiary Boost (F-2 priority skim, 14-day epoch lock) | `src/incendiary/` | Fee router (uses same swap path), emission distributor |
| Miliarium Aureum 28-slot registry | `src/registry/` | Gauge registry |
| der Bodensee Pool deployment (script + config) | `script/pools/` | Vault, AuMM, sUSDS, svZCHF |
| 28 Miliarium pool deployments (scripts + configs) | `script/pools/` | Vault, ixEDEL, svZCHF, theme tokens |
| Composition challenge / replacement-launch path | `src/governance/` | Gauge registry, registry, governance |
| Halving block boundary handler | inside emission distributor | None |

This is consistent with appendix §xxxvi's "~4,500 lines of new Solidity" estimate.

---

## Open questions

Numbered, with proposed options where I have them. Need human resolution before the corresponding stage can be planned.

### OQ-1 (RESOLVED): Fee routing architecture — Balancer V3 hook on `onAfterSwap`, atomic settlement

**Decision (2026-04-15, mechanics clarified 2026-04-19):** Swap fees on Miliarium and other gauged non-Bodensee pools route to der Bodensee via a Balancer V3 `IHooks` contract attached to every gauged pool. Each gauged pool registers with `protocolSwapFeePercentage = 50e16` — saturating the Vault's `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50%` cap — and that value is immutable at registration: no on-chain setter, no governance adjustment (the split is constitutional per CLAUDE.md §2). The hook fires on `onAfterSwap`, settles the Vault's accrued protocol-fee share (100% of what the cap allows; 50% of the swap's total fee) to der Bodensee via a swap-to-svZCHF-then-one-sided-add primitive (per OQ-2), atomically per swap. **No off-chain triggering, no LP "click to redeem" step.** The remaining 50% of the swap fee stays with the originating pool's LPs by Vault design — a consequence of the cap, not an Aureum allocation choice — which reconciles cleanly with Stage A decision #3 ("50% to Bodensee, 50% to LPs").

The precise framing: **100% of the protocol-extractable share, up to the Vault's 50% cap.** The hook saturates the cap; it does not bypass it.

ERC-4626 yield fees can't ride a swap hook — they accrue continuously through the underlying vault's `convertToAssets()` rate. The `AureumProtocolFeeController` collects aggregate yield fees via `collectAggregateFees()` to itself; the D4.6 governance-gated entry point (deferred — see **OQ-20**) approves the hook and calls `routeYieldFee`, using the same swap-and-one-sided-deposit primitive. Same for governance proposal deposits and Incendiary Boost deposits — they call the shared primitive directly.

**Three layers, one shared primitive:**

| Layer | Trigger | Mechanism |
|---|---|---|
| Swap-fee leg (Miliarium + gauged non-Bodensee pools) | Every `swap` on a hooked pool | `onAfterSwap` hook → settle the Vault's 50% protocol-fee share → swap to svZCHF → one-sided add to Bodensee, atomic |
| Yield-fee leg (ERC-4626 10% skim) | `collectAggregateFees(pool)` (callable by anyone) | Fee controller collects to itself (`src/vault/AureumProtocolFeeController.sol:334-341`); controller D4.6 entry point (deferred) approves hook + calls `routeYieldFee` → same swap-and-deposit primitive. See **OQ-20**. |
| Governance & Incendiary deposits | Explicit user call (proposal submission, Incendiary boost) | Direct call to the shared swap-and-deposit primitive |

**Why this is better than the originally-proposed Option B (separate `FeeRouter` invoked manually):**
- **Atomic.** Swap fees settle to der Bodensee in the same transaction that produced them. No accumulator, no settlement lag, no "anyone can call routePending()" UX issue.
- **Saturates the Vault's 50% protocol-fee cap at registration.** Each gauged pool registers with `protocolSwapFeePercentage = 50e16`, immutable thereafter. The hook then settles 100% of the Vault's protocol share to Bodensee on every swap. Consistent with Stage A decision #3 and with CLAUDE.md §2's "50% to Bodensee, 50% to LPs" hard rule — the split is encoded as an immutable Vault parameter, not as runtime logic.
- **Existing Stage B `AureumProtocolFeeController` work is preserved.** Stays as the yield-fee collection point, with B10 enforcement target updated from `DER_BODENSEE_POOL` to the hook/router address. Small modification, not a replacement.
- **Aureum-owned hook is "new tokenomics layer" code per `13_appendices.md` §xxxvi** — clean audit-scope boundary. Existing Balancer V3 hooks (StableSurge etc.) stay byte-identical.

**Concrete contract changes:**
- **New:** `AureumFeeRoutingHook.sol` (`src/fee_router/`) — implements `IHooks.onAfterSwap` plus the shared swap-and-one-sided-deposit primitive used by all three layers.
- **Modified:** `AureumProtocolFeeController.sol` — (a) B10 enforcement target renamed from `DER_BODENSEE_POOL` to the hook/router address (one immutable rename, one error-message update); (b) no public setter for `protocolSwapFeePercentage` — the value is fixed at 50e16 on every gauged pool at registration time and has no runtime adjustment surface (Stage K governance does not touch this split; it only tunes the per-pool swap-fee *rate* within OQ-11's band); (c) Stage D edits for the OQ-11 Bodensee fee band and the OQ-2 Bodensee yield-leg guard (D4). Everything else preserved.
- **Modified:** the 28 Miliarium pool deployment scripts — each pool's registration must point at `AureumFeeRoutingHook` and set `protocolSwapFeePercentage = 50e16`. der Bodensee Pool itself does **NOT** use this hook (it has its own 0.75% in-pool fee) and registers with `protocolSwapFeePercentage = 0` per OQ-2. External non-Miliarium pools opt in to the hook to be eligible for emissions — the hook is a soft requirement for gauge approval.

**Stage A decision #3 stands.** The "50% to Bodensee, 50% stays with LPs" framing in Stage A was correct in outcome; the OQ-1 hook provides the mechanism by (i) registering every gauged pool with `protocolSwapFeePercentage = 50e16` (saturating the Vault cap) and (ii) atomically settling that protocol share to Bodensee via `onAfterSwap`. The LP residual is the Vault's own design constant, not an Aureum allocation. No "supersedes" relationship; OQ-1 is the mechanical realization of Stage A decision #3.

**Open implementation concerns (move to design doc when this stage is planned):**
- **Gas cost on every swap.** The hook adds (a) protocol-fee settlement, (b) an internal swap to stablecoin, (c) a one-sided add to Bodensee — easily 200k+ extra gas per swap. May make small swaps uneconomic at the aggregator level. Worth modeling at design time.
- **Recursion guard.** Routing a fee swap *through* a Miliarium pool that itself has the hook attached re-triggers the hook. Either the hook special-cases its own internal swaps (e.g. trusted-router check on `params.router`), or fee swaps route directly through der Bodensee (only viable if the input/output tokens are present in Bodensee), or accept geometric-series overhead. Solvable; needs care. Tracked as D-D4.
- **Hook is on the audit hot path.** Every swap on every Miliarium pool runs through it. A bug in the hook is a protocol-wide bug. Higher audit attention than a separate occasional-call FeeRouter would have needed.

These are real concerns for the implementation stage but not architectural blockers. Settled here.

### OQ-1a (RESOLVED): LP fee residual on Miliarium pools — 50%, via BAL v3 split

**Decision (2026-04-15, mechanics clarified 2026-04-19):** Each swap fee on non-Bodensee gauged pools is split by the Vault: 50% to the protocol (routed to der Bodensee via the OQ-1 hook on `onAfterSwap`), 50% to the LPs of the originating pool. Miliarium LPs thus earn from (a) AuMM emissions, (b) ERC-4626 native vault yield on the yield-core component, and (c) the 50% swap-fee residual that the Vault holds back from the protocol cut. der Bodensee LPs also earn swap fees directly via the 0.75% in-pool tier on the AuMM/sUSDS/svZCHF three-token pool.

**Earlier framing (superseded 2026-04-19):** The original OQ-1a resolution claimed Miliarium LPs earn *"NOT from swap fees on their own pool"* on the premise that the OQ-1 hook captures 100% of every swap fee. The 2026-04-19 BAL v3 mechanics review confirmed that Aureum's hook operates within the Vault's protocol-fee accounting pipeline — it saturates the `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50%` cap, does not bypass it. The 50% LP residual is a Vault-imposed consequence of saturating the cap, not an explicit Aureum design choice. Miliarium LPs keep 50% of swap-fee volume on their own pool.

**Spec edits required in `aumm-site` (no code impact, pure doc-side):**

- **`13_appendices.md` xxxix LP Advantage table (line 1886):** *"Yield sources | Swap fees + vault yield + cross-pool arb fees + AuMM mining"* — "Swap fees" is correct for Miliarium LPs at the 50% residual rate; clarify in a footnote or parenthetical that the figure is 50% of the pool's swap fee (the other 50% routes to Bodensee via the OQ-1 hook). Der Bodensee LPs keep the full 0.75% in-pool tier on the AuMM/sUSDS/svZCHF three-token pool.
- **`02_mental_model.md` and/or `04_tokenomics.md` §x-a:** add a one-sentence clarification, e.g. *"Miliarium LP returns: AuMM emissions + ERC-4626 native yield + 50% residual of swap fees on the pool (the BAL v3 Vault's LP share; the other 50% routes to der Bodensee via the OQ-1 hook). Der Bodensee LPs additionally earn the full 0.75% in-pool swap-fee tier on the AuMM/sUSDS/svZCHF three-token pool."*
- **Any other place in the spec that previously said Miliarium LPs earn *zero* from swap fees** — sweep and correct to 50% residual.

**Knock-on:** the 0.01–0.30% per-pool swap-fee tier from OQ-11 is the **rate at which pools charge swaps**. The 50/50 protocol/LP split applies on top of that rate — governance can adjust the rate within OQ-11's band but cannot adjust the split.

**OQ-11 scope is unchanged:** the per-pool swap-fee *rate* is governable within bounds; the *destination* of the protocol share is immutable (always 100% of the 50% cap to Bodensee); the LP residual of 50% is a Vault invariant.

### OQ-2 (RESOLVED): Fee-routing swap target = svZCHF

**Decision (2026-04-15):** The OQ-1 fee-routing hook and the yield-fee collection path always swap fee tokens into **svZCHF** before the one-sided deposit into der Bodensee.

**Why svZCHF (and not "underweight-side" balancing as originally proposed):**

The der Bodensee 30/30 stablecoin composition does not need the hook to defend it. Der Bodensee is a standard Balancer V3 weighted pool with fixed 40/30/30 weights; when one-sided fees flow in as svZCHF, the svZCHF balance rises above its 30% target in *balance* terms, arbitrageurs detect that svZCHF is cheap inside the pool relative to market, they swap svZCHF out and (AuMM + sUSDS) in, pulling the pool back toward its 40/30/30 target. **Arbitrage preserves the composition; the hook doesn't need to.** This is exactly what weighted-pool math is designed for.

So the hook picks a swap target purely on other grounds:

1. **svZCHF is the protocol's primary routing anchor.** `02_mental_model.md` §iii calls it *"the deeper, primary routing rail"*. Routing fees to svZCHF reinforces that structural framing.
2. **Simpler hook code.** One target, no pool-balance reads, no branching. Saves gas on every swap.
3. **More routing volume flowing through svZCHF-holding pools.** The fee-routing swap itself passes through the constellation; svZCHF is in 26 of 28 Miliarium pools, so that routing volume spreads widely. sUSDS is in fewer pools (10 of 28 per `07a_tokens.md`) — concentrating fee-routing volume through svZCHF supports the larger svZCHF rail.

**Der Bodensee's self-yield mechanism — no hook, no yield skim on Bodensee itself.**

A key clarification from the OQ-2 discussion that the spec leaves implicit: der Bodensee's 60% ERC-4626 weight (svZCHF + sUSDS) generates yield continuously via the Rate Provider mechanism (Balancer V3 standard behavior for ERC-4626 tokens). That yield stays **inside** the pool — it accrues to Bodensee LPs via their BPT share, and it reprices AuMM upward via weighted-pool math acting on the rate-scaled balances. **No yield is skimmed from der Bodensee.** The self-reinforcing loop described in `04_tokenomics.md` §x-a line 610 is the full mechanism — yield compounds inside Bodensee without any skim step.

**The "10% yield fee skim routed to der Bodensee" in the spec targets only gauged pools *other than* Bodensee.** Every Miliarium pool and gauged non-Miliarium pool holds ERC-4626 tokens, generates yield on them, has 10% of that yield skimmed by `AureumProtocolFeeController.collectAggregateFees(pool)`, swapped to svZCHF, and one-sided-deposited into Bodensee. Bodensee itself is **excluded from the yield-fee collection mechanism** — its yield stays in-pool as part of the value-capture loop.

**Concrete contract behavior:**
- **Swap-fee leg (OQ-1 hook):** hook attaches to every gauged pool (Miliarium + gauged non-Miliarium). **Explicitly not attached to der Bodensee.** Fee destination: always svZCHF into Bodensee.
- **Yield-fee leg:** `collectAggregateFees(pool)` is callable on every gauged pool. **Must revert or no-op when called with der Bodensee's address** — the Aureum protocol fee percentage on der Bodensee is set to 0 at deployment, and ideally the fee controller itself enforces `pool != derBodenseePool` as an additional safety. Fee destination when collected from other pools: always svZCHF into Bodensee.
- **Der Bodensee itself:** standard Balancer V3 weighted pool with Rate Providers on svZCHF and sUSDS. No hook. No yield-fee collection. The 0.75% in-pool swap fee stays with Bodensee LPs per `10_constitution.md` §xxix.

**Spec edits required:**

The "Bodensee self-yield" mechanism is the structural heart of how AuMM accrues value. The current spec text in `04_tokenomics.md` §x-a is correct but understated — it lists the components (60% ERC-4626 weight, Rate Providers, 0.75% in-pool fee, weighted-pool math) without explaining how they compose into the value-capture loop. The spec should add the explicit four-step mechanism. **Proposed text for `04_tokenomics.md` §x-a, to be inserted as a new subsection between "Value capture" and "The Self-Reinforcing Loop":**

---

#### How yield accrues to AuMM without leaving the pool

Der Bodensee holds svZCHF and sUSDS — both ERC-4626 yield-bearing tokens — directly. Each is configured at pool registration with a Balancer V3 **Rate Provider** that reports `convertToAssets(1e18)`: the underlying-asset-per-share ratio. As Frankencoin and Sky earn yield on their respective reserves, those Rate Providers report progressively higher rates over time. Balancer V3's weighted-pool math uses **rate-adjusted balances** to compute swap outcomes and spot prices — so the pool natively understands that one svZCHF token today is worth more than one svZCHF token was yesterday.

The consequence runs through four steps:

1. **Yield accrues silently.** As time passes with no swap activity, the svZCHF and sUSDS Rate Providers report higher rates. The pool's accounted balances (in rate-scaled terms) rise on the stablecoin sides without any token movement.
2. **Weighted-pool invariant adjusts.** The pool's 40% AuMM / 30% sUSDS / 30% svZCHF target is enforced on rate-scaled balances. As the stablecoin sides grow in value while the AuMM side stays fixed (no AuMM enters via emission after Month 10), the implied AuMM price rises mechanically — there are now more rate-scaled stablecoins backing the same AuMM supply.
3. **No yield leaves the pool.** No wei of AuMM, svZCHF, or sUSDS is transferred out. The yield is fully embedded in the rising rate of the 4626 tokens, captured 100% by Bodensee LPs through their pro-rata BPT share of the growing pool value, and reflected in AuMM's price through the weighted-pool math acting on rate-adjusted balances.
4. **No skim, no buyback, no burn.** AuMM scarcity is enforced by the F-0 bootstrap channel (decaying then permanently zero at Month 10). Stablecoin depth grows from two independent sources: the continuous one-sided fee inflows from other pools (swap fees + 10% yield skim from non-Bodensee gauged pools), *and* the ongoing in-place yield on every stablecoin already sitting in der Bodensee. The pool feeds its own growth.

This mechanism is why the spec frames der Bodensee as *"a lake that only gets deeper"* and why no buyback / burn / market-purchase logic exists anywhere in the protocol. The pool math is the value-capture mechanism.

**One clarification on the protocol fee structure:** the "10% ERC-4626 yield fee" referenced in `10_constitution.md` §xxix and elsewhere applies to ERC-4626 tokens held inside **other gauged pools** (the 28 Miliarium pools and any non-Miliarium gauged pool), **not** to der Bodensee's own ERC-4626 holdings. Skimming yield from Bodensee and depositing it back into Bodensee would be a no-op that burns gas. The skim mechanism extracts 10% of yield from every other gauged pool's ERC-4626 component, swaps it to svZCHF via the Aequilibrium routing layer, and one-sided-deposits into Bodensee — adding to the stablecoin depth that already compounds in-place.

---

**Other spec edits required:**

- **`04_tokenomics.md` §x-a "Reserve Depth Growth" worked example (lines 616–622):** the `$100M TVL × 60% ERC-4626 × 2.5% yield × 10% skim = ~$150K/year` calculation needs explicit framing as "$100M *protocol-wide* TVL across the 28 Miliarium pools (excluding Bodensee)" — reading it as Bodensee's own TVL makes the skim circular per the new subsection above.
- **`10_constitution.md` §xxix:** add an explicit clarification that "ERC-4626 yield fee (10% skim)" applies to gauged pools *other than* der Bodensee. der Bodensee's yield-bearing composition compounds in-pool via the Rate Provider mechanism.
- **`11_formulas.md` F-11:** add a note under "Stablecoin inflows" that der Bodensee is not subject to the yield skim itself — it is only the *destination* of the skim. Cross-reference the new §x-a subsection.
- **`02_mental_model.md`** (optional but recommended): brief mention of the Rate Provider mechanism in the constellation routing or value-capture sections, so readers encounter the concept before reaching §x-a.
- The three-layer fee table in OQ-1 (above) is also updated to reflect the exclusion.

**Edge case at genesis:** both stablecoin sides of Bodensee start at zero. The first fee-routing event deposits one-sided svZCHF. Arb only kicks in once there's enough price divergence to be worth gas; this is fine, it just means the first few days of fee inflows sit lopsided. Over time the pool finds its equilibrium around 40/30/30 *in value terms*. No special handling needed.

### OQ-3 (RESOLVED): Protocol "month" = 219,000 blocks (aligned with halving math)

**Decision (2026-04-15):** A protocol month is **219,000 blocks** (≈30.4 days at 12 s/block). 12 months = **2,628,000 blocks** = exactly 1/4 of the 10,512,000-block halving period. Year 1 ends at the same block as "1/4 through Era 0," giving clean alignment between the bootstrap schedule (F-0 piecewise decay, the Month 6 unhide, Month 10 bootstrap end, Month 11–12 transition, Month 13 efficiency tournament) and the emission schedule.

A protocol month is ~12 hours longer than the average calendar month — invisible to LPs, irrelevant to UX. The spec's "month" is a contract-level time unit, not a calendar reference.

**Constants this pins:**
- `BLOCKS_PER_MONTH = 219_000`
- `BLOCKS_PER_YEAR = 2_628_000` (12 × `BLOCKS_PER_MONTH`)
- `MONTH_6_END_BLOCK = genesis_block + 6 × BLOCKS_PER_MONTH` (used in F-0 piecewise decay)
- `MONTH_10_END_BLOCK = genesis_block + 10 × BLOCKS_PER_MONTH` (used in F-0 piecewise decay; also the permanent zero-out of the bootstrap channel)
- `MONTH_11_START_BLOCK`, `YEAR_1_END_BLOCK`, `MONTH_13_START_BLOCK` etc. follow trivially.

**Spec edits required in `aumm-site`:**
- `09_transitions.md` §xxvi line 1624 — replace the abstract "fixed on-chain block ranges" with the concrete `BLOCKS_PER_MONTH = 219,000` constant.
- `10_constitution.md` §xxix — add `BLOCKS_PER_MONTH = 219,000` to the canonical immutable parameters list (per F3).
- `11_formulas.md` F-0 — update the `month_6_end_block` and `month_10_end_block` definitions to reference the constant.

### OQ-4 (RESOLVED): Bi-weekly epoch = 100,800 blocks (14 calendar days)

**Decision (2026-04-15):** A bi-weekly epoch is **100,800 blocks** (14 days × 7,200 blocks/day at 12 s/block).

Epoch and month cadences are deliberately independent rhythms: 26.07 epochs per protocol year, ~2.17 epochs per protocol month. Boundaries drift relative to month milestones, which is fine — months mark bootstrap-schedule events (F-0 piecewise transitions, the Month 6 unhide, Month 13 efficiency-tournament activation), epochs mark CCB-cycle events (multiplier updates, Incendiary Boost durations, efficiency-tournament smoothing windows). Two clocks, not one.

**Constants this pins:**
- `BLOCKS_PER_EPOCH = 100_800`
- `INCENDIARY_BOOST_DURATION_BLOCKS = BLOCKS_PER_EPOCH` (F-2)
- `CCB_MULTIPLIER_UPDATE_CADENCE_BLOCKS = BLOCKS_PER_EPOCH` (F-8)
- `EFFICIENCY_TOURNAMENT_SMOOTHING_EPOCHS = 3` (F-10, gives a 6-week / ~302,400-block moving average)
- `GAUGE_REVOCATION_THRESHOLD_EPOCHS = 4` (consecutive disqualified epochs → permanent gauge revocation per `08_bootstrap.md` §xxiii)
- `SANDBOX_FAST_TRACK_EPOCHS = 3` (top 10% efficiency for 3 consecutive epochs → automatic gauge approval per `08_bootstrap.md` §xxi)

**Spec edits required in `aumm-site`:**
- `10_constitution.md` §xxix — add `BLOCKS_PER_EPOCH = 100,800` to the canonical immutable parameters list (per F3).
- `08_bootstrap.md` §xxii — link the "1 epoch (14 days)" wording to the constant.
- `11_formulas.md` F-2, F-8, F-10 — link epoch references to the constant.

### OQ-5 (RESOLVED): Halving block = 10,512,000; block numbers are canonical, calendar terms are aliases

**Decision (2026-04-15):** Halving interval confirmed at **10,512,000 blocks** (4 × `BLOCKS_PER_YEAR` = 4 × 2,628,000). Math check: 10,512,000 × 12 s = 126,144,000 s = 1,460 days = 4 × 365 days exactly. Consistent with Stage A decision #7, B6 fork-test assertion, and OQ-3's protocol-year definition.

**Bigger rule (applies to all future spec reads and code):** from this point forward, **block numbers are the canonical time unit everywhere in the protocol**. Every calendar-time term in the spec (month, year, week, bi-weekly, day, epoch, "90 days," "14 days," "60-day EMA," etc.) is an **alias** for a block count. Calendar-time readings of any duration in the spec are approximations for human comprehension, not contractual commitments. The contracts only ever deal with block counts.

**The canonical time-constant table** (all immutable from block 0; belongs in `10_constitution.md` §xxix):

| Constant | Value (blocks) | Calendar alias (12 s/block) | Used in |
|---|---|---|---|
| `BLOCKS_PER_DAY` | 7,200 | 1 day | Daily TVL sampling for F-4 EMA, any per-day rate |
| `BLOCKS_PER_WEEK` | 50,400 | 7 days | — (not currently used; listed for completeness) |
| `BLOCKS_PER_EPOCH` | 100,800 | 14 days ("bi-weekly") | F-2 Incendiary Boost duration, F-8 CCB multiplier cadence, F-10 efficiency tournament smoothing unit |
| `BLOCKS_PER_MONTH` | 219,000 | ~30.4 days (1/12 year) | F-0 piecewise bootstrap decay boundaries, graduated grace period thresholds, Month 6 unhide, Month 10 bootstrap termination, Month 11–12 transition, Month 13 efficiency-tournament activation |
| `BLOCKS_PER_QUARTER` | 657,000 | ~91.25 days (3 months) | 90-day gauge boost duration (close enough; confirmed below) |
| `BLOCKS_PER_YEAR` | 2,628,000 | 365 days (exact) | Year 1 / transition-complete boundary, era-quarter boundary, F-9 governance dampening era boundaries |
| `BLOCKS_PER_ERA` | 10,512,000 | 1,460 days (4 × 365) | Halving interval; governance dampening transition (Era 0 → Era 1+) |

**Derived constants** (not primary, but worth pinning):

| Constant | Formula | Value (blocks) | Calendar alias | Used in |
|---|---|---|---|---|
| `MONTH_6_END_BLOCK` | `genesis + 6 × BLOCKS_PER_MONTH` | `genesis + 1,314,000` | End of Month 6 | F-0 first piecewise boundary (80%→50% bootstrap inflection); der Bodensee unhide |
| `MONTH_10_END_BLOCK` | `genesis + 10 × BLOCKS_PER_MONTH` | `genesis + 2,190,000` | End of Month 10 | F-0 second piecewise boundary (bootstrap → 0 permanent) |
| `YEAR_1_END_BLOCK` | `genesis + BLOCKS_PER_YEAR` | `genesis + 2,628,000` | End of Year 1 | F-3 transition endpoint (α = 1); efficiency-tournament-precursor window |
| `MONTH_13_START_BLOCK` | `genesis + 12 × BLOCKS_PER_MONTH + 1` | `genesis + 2,628,001` | Month 13 first block | Efficiency tournament activation (simultaneous with Year 1 end) |
| `FIRST_HALVING_BLOCK` | `genesis + BLOCKS_PER_ERA` | `genesis + 10,512,000` | End of Year 4 | Era 0 → Era 1 transition; F-9 governance dampening exponent changes permanently from ¼ to ⅓ |
| `EMERGENCY_WINDOW_END_BLOCK` | `migrationBlock + BLOCKS_PER_YEAR` | `migrationBlock + 2,628,000` | 12 months post governance migration | OQ-10 multisig time-bomb sunset |
| `INCENDIARY_BOOST_DURATION_BLOCKS` | `= BLOCKS_PER_EPOCH` | 100,800 | 14 days | F-2 duration |
| `GAUGE_BOOST_DURATION_BLOCKS` | — | 648,000 | 90 days exactly (7,200 × 90) | `08_bootstrap.md` §xxi 90-day gauge boost (see note below) |
| `EMA_HORIZON_DAYS` | — | (expressed as α = 2/61) | 60 days | F-4 EMA smoothing constant |

**Note on 90-day gauge boost:** `08_bootstrap.md` §xxi says the newly-approved gauge receives a 1.2× CCB multiplier "for 90 days." The clean interpretation is `GAUGE_BOOST_DURATION_BLOCKS = 90 × BLOCKS_PER_DAY = 648,000`. This is ~98.6% of `BLOCKS_PER_QUARTER` (657,000) — not identical. Picking 648,000 keeps the "exactly 90 days" framing and is independently verifiable; using a protocol-quarter constant would drift 1.25% longer. **Recommendation: `GAUGE_BOOST_DURATION_BLOCKS = 648,000`** (literal 90 days). If you'd rather go with `BLOCKS_PER_QUARTER` for cadence coherence with the protocol-month/year system, say so — otherwise I'll write 648,000.

**Note on "60-day EMA":** `11_formulas.md` F-4 expresses the EMA as `alpha = 2 / (60 + 1) ≈ 0.0328` with updates happening every block, not every day. The "60-day" label is a modeling description of the half-life (~21 days), not an update cadence. The EMA recomputes every block using block-to-block TVL deltas — no separate "daily sample" needed. This means `BLOCKS_PER_DAY` isn't actually used by F-4; it's only used if we want to sample TVL at a fixed daily cadence for alternative purposes. **Flagging for review:** is the intent that the EMA uses a per-block alpha of `2/(60 + 1)` with every block being a sample (mathematically equivalent to an extremely fast-updating EMA), or that TVL is sampled once per `BLOCKS_PER_DAY` with alpha `2/61` for a traditional 60-day EMA? These produce very different smoothing behavior. Probably an OQ in its own right — flagging as **OQ-5a below**.

**Spec edits required (all in `aumm-site`, no code impact yet):**

- **`10_constitution.md` §xxix:** add the canonical time-constant table above. Replaces the scattered narrative references with one authoritative list.
- **`12_aureum_glossary.md`:** new entry defining "protocol month / year / epoch" as block-count aliases. Small callout that calendar-time readings are approximate for human comprehension, block counts are binding.
- **Every file with calendar-time references** (`02_mental_model.md`, `04_tokenomics.md`, `08_bootstrap.md`, `09_transitions.md`, `11_formulas.md`, the 28 pool profiles): no wording changes required — the terms remain readable, they just resolve to block counts via the constitution's table. But where a specific block-boundary matters (e.g. `month_6_end_block` in F-0), the formula text should reference the named constant (e.g. `MONTH_6_END_BLOCK`) rather than just saying "end of Month 6."
- **`11_formulas.md` F-0:** update the piecewise definition to use `genesis_block + 6 × BLOCKS_PER_MONTH` and `genesis_block + 10 × BLOCKS_PER_MONTH` explicitly as the segment boundaries. Current text says `month_6_end_block = last_block_of_Month_6` which is circular.
- **Worked examples that quote calendar dollars-per-year (e.g. the `04_tokenomics.md` §x-a Reserve Depth Growth table):** the annualized revenue figures assume calendar-year conversion, not block-based. Those stay as-is because they're illustrative market economics, not on-chain computations. Add a footnote that economic scenarios use calendar-year conventions while contract computations use protocol-year blocks.

**Implementation implication:** every Aureum-owned contract that currently has a hardcoded calendar-time value (e.g. `block.timestamp + 4 years` in the Stage B fork test) should migrate to block-based comparisons. Stage B's pause-window assertion (*"`block.timestamp + 4 years`"* from STAGE_B_PLAN.md B6) is an inherited Balancer V3 check — that particular one stays timestamp-based because it's upstream's semantics, byte-identical, off-limits. But every Aureum-owned contract uses `block.number` against the immutable block constants above.

### OQ-5a (RESOLVED): EMA sampling cadence = per-day TWAP

**Decision (2026-04-15):** Per-day sampling with `alpha = 2/61` and an intra-day TWAP at the sample boundary (option **b+**).

**Mechanism:**
- Each pool maintains state: `lastEMAUpdateBlock`, `tvlEMA`, plus a small intra-day TWAP accumulator.
- Anyone can call `updateEMA(pool)` once `block.number >= lastEMAUpdateBlock + BLOCKS_PER_DAY`. Function is permissionless (deterministic math, no privileged input).
- The "spot TVL" used in the EMA update is not a single-block read but a **TWAP across the last `TWAP_WINDOW_BLOCKS` blocks before the sample boundary**. Recommended `TWAP_WINDOW_BLOCKS = 720` (1 hour at 12 s/block, 10% of a protocol day).
- EMA update: `tvlEMA_new = (2/61) × twapTVL + (59/61) × tvlEMA_old`.
- Half-life: ~21 days. Matches the spec's "60-day EMA" framing literally.

**Why (b+) over (b):**
- Per-day EMA without TWAP creates a small attack surface: an actor who briefly spikes TVL right at the sample block can bias that day's contribution to the EMA. The 60-day smoothing dampens this (~3.3% influence per day), but it's a non-zero attack vector for weeks.
- Adding a 1-hour TWAP at the sample boundary eliminates the attack vector at trivial gas cost. The CCB engine does ~720 storage reads at sample time (one per block in the TWAP window) — but those reads can be batched: store a running `cumulativeTVL` and `cumulativeBlock` per pool, and the TWAP is `(cumulativeTVL_now - cumulativeTVL_dayAgo) / (cumulativeBlock_now - cumulativeBlock_dayAgo)`. This is the same accumulator pattern Uniswap V2/V3 oracles use.

**Why (b+) over (a) and (c):**
- (a) per-block EMA writes — 28 pools × 1 write per block × ~7M blocks/year = unnecessary gas burn for no behavioral gain.
- (c) lazy-computed per-block — equivalent math at lower amortized gas, but adds the closed-form `(1-alpha)^n` decay calculation, which requires either a precomputed lookup table or a `pow` library. (b+) is conceptually simpler and the gas savings of (c) are marginal at one update per pool per day.

**Constants this pins:**
- `EMA_HORIZON_DAYS = 60` (informational; the actual constant is alpha)
- `EMA_ALPHA_NUMERATOR = 2`, `EMA_ALPHA_DENOMINATOR = 61` (use FixedPoint math: `alpha = 2e18 / 61`, then apply via `mulDown(alpha)` and `mulDown(1e18 - alpha)`)
- `TWAP_WINDOW_BLOCKS = 720` (1 hour)
- `BLOCKS_PER_DAY = 7,200` (already pinned in OQ-5)

**Gas profile:**
- Per pool per day: 1 EMA update call (~50k gas including TWAP read from accumulator) + ongoing accumulator update on each swap/liquidity event (negligible — single SSTORE).
- 28 Miliarium pools + N gauged non-Miliarium pools × 1 update/day = roughly N+28 updates per `BLOCKS_PER_DAY`. Permissionless trigger; can be invoked by any keeper or by the CCB scoring path itself (which depends on fresh EMAs).

**Spec edits required:**
- **`11_formulas.md` F-4:** rewrite the formula to make per-day-sample-with-TWAP explicit. Current text says `TVL_EMA_pool(today) = alpha × TVL_spot(today) + (1 − alpha) × TVL_EMA_pool(yesterday)` — replace with the per-day-update formula and add the `TWAP_WINDOW_BLOCKS` callout. The half-life and design rationale stay unchanged.
- **`10_constitution.md` §xxix:** add `EMA_HORIZON_DAYS = 60`, `TWAP_WINDOW_BLOCKS = 720`, and the alpha numerator/denominator to the immutable parameters table.
- **`03_theoretical_foundation.md` §vi-b:** small rewording — "today's TVL" can stay, but flag that "today" is a `BLOCKS_PER_DAY`-sized window with intra-day averaging at the boundary.

### OQ-6 (RESOLVED): der Bodensee "hidden Months 0–6" = frontend-only; pool address not shared with routers/aggregators

**Decision (2026-04-15):** Pure frontend convention with deliberate no-share-to-routers operational policy. The pool is fully on-chain, registered with the Aureum Vault, and tradeable from genesis. No on-chain pause, no hook on Bodensee, no swap-blocking mechanism — keeps OQ-2's clean "no hook on Bodensee, standard Balancer V3 weighted pool" architecture intact.

**The mechanism that actually keeps it quiet:** during Months 0–6 the pool is heavily lopsided by the F-0 bootstrap (80%→50% of every block's emission deposited one-sided as AuMM). Most aggregators (1inch, Paraswap, CoW, Uniswap routing, Balancer's own UI) require minimum-TVL or minimum-balanced-depth thresholds before they index a pool for routing. A pool accumulating one-sided AuMM with near-zero stablecoin depth on the other sides won't pass those thresholds — even if discovered, no rational router would route through it (slippage would be enormous on any non-trivial trade). **The pool effectively self-hides via its own composition during the bootstrap period.** Sophisticated on-chain actors who *do* find it can interact directly, and that's fine — early arb activity helps establish price discovery, just not via the official UI.

**Operational policy (no spec change, but worth recording):**
- The Aureum team does not announce, list, advertise, or publish der Bodensee's pool address during Months 0–6.
- The aumm.fi frontend does not render der Bodensee or include it in any swap/routing graph during Months 0–6.
- No partnerships with aggregators / routers / data indexers about der Bodensee until the unhide block.
- At `MONTH_6_END_BLOCK + 1` (the first block of Month 7), the team publishes the pool address, aumm.fi enables rendering and routing through der Bodensee, and outreach to aggregators/data indexers begins.

**What this is NOT:**
- It's not a censorship mechanism. Anyone can find the pool by reading the Vault's `PoolRegistered` events or by scanning for pools containing AuMM as a component.
- It's not a market-manipulation mechanism. The bootstrap inflows happen at known per-block rates (F-0 piecewise decay); the schedule is public; arbers who choose to participate during the bootstrap are doing so with full information.
- It's not a contract-level guarantee. If a third-party UI surfaces der Bodensee on day 1, that's their choice; nothing prevents them.

**Why this works:** the spec's "hidden" framing is about price-discovery hygiene, not about preventing trade. The bootstrap genuinely benefits from passive accumulation rather than active speculation, and a pure-frontend hide accomplishes most of that with zero contract risk. Trying to enforce "no trades" on-chain creates a fragile trust surface (what if the pause has a bug? what if arb is *needed*?) and contradicts the spec's "permissionless from block 0" framing in `08_bootstrap.md` §xxi.

**Spec edits required in `aumm-site` (no code impact, pure doc-side):**

- **`05_miliarium_aureum.md` §xii line 1089:** clarify "Hidden from UI Months 0–6" to "**Not surfaced in the official aumm.fi UI** during Months 0–6 (block 0 to `MONTH_6_END_BLOCK`); the pool is fully on-chain, tradeable, and visible to any block explorer or third-party aggregator from genesis. Official UI rendering, routing, and pool-address publication begin at `MONTH_6_END_BLOCK + 1`. Most aggregators will not route through the pool during the bootstrap period because its lopsided composition fails their minimum-depth thresholds — the pool effectively self-hides via its own state."
- **`04_tokenomics.md` §x-a, `09_transitions.md` §xxvi, `12_aureum_glossary.md`, `14_ux_ui.md` §xlvi:** mirror the same clarification (or cross-reference §xii). `14_ux_ui.md` §xlvi line 1955 already specifies the frontend gate; tighten to reference `MONTH_6_END_BLOCK` from the §xxix immutable parameters table.
- **`02_mental_model.md`** (optional): brief mention of the self-hide-by-composition mechanism in the der Bodensee discussion.

### OQ-7 (RESOLVED): Composition Challenge mechanics — gauge-revoked-only, hook stays, specified-pool model, no migration

**Decision (2026-04-15):** The composition challenge is a deprecate-and-replace mechanism with four concrete sub-rules:

**Q1 — what "deprecate" means: gauge revoked only.** The old pool persists on-chain as a Sandbox-style pool. It still exists, still accepts swaps, still earns ERC-4626 native yield for its LPs, still routes swap fees to der Bodensee through the still-attached OQ-1 hook (Q1.5). What it loses: AuMM emissions (gauge gone), CCB multiplier (Miliarium-only), and Miliarium Registry slot status. The pool is no longer "the slot 14 pool" — that slot now points to the replacement.

**Q1.5 — the OQ-1 fee-routing hook stays attached.** Balancer V3 doesn't easily support hook removal post-registration, and this is fine: the protocol still benefits from any residual trading activity on the deprecated pool, the LPs just don't earn AuMM for keeping it open. **The deprecated pool keeps generating revenue for der Bodensee for as long as anyone trades on it.** This is a structural property — once a pool is hooked at registration, it remains a fee source for life. The 28 founding pools and any subsequently-gauged pools are all "hook-permanent."

**Q2 — replacement deployment: specified-pool model.** The composition challenge proposal must reference the address of an already-deployed candidate pool. Anyone can deploy a pool with the proposed composition before submitting the proposal (deployment is permissionless from block 0 per `08_bootstrap.md` §xxi). The 2/3 supermajority vote is binary on that specific pool. On approval, the governance contract calls `MiliariumRegistry.replaceSlot(slotN, newPoolAddress)`; the replacement is automatically gauge-eligible (no separate gauge proposal needed — the supermajority vote provided stronger consent than the standard 20%-quorum gauge approval); the 90-day gauge boost (1.2× CCB multiplier per `08_bootstrap.md` §xxi) applies as usual.

The like-for-like rule (same sector, same risk profile, same template role per `10_constitution.md` §xxvii) is enforced two ways:
- **Programmatic checks** at the registry level for properties the contract can verify: token-type composition (e.g. "must contain ≥52% ERC-4626 by weight"), token-count limits, weight bounds.
- **Semantic checks** via the governance review itself: voters evaluate sector-fit, risk-equivalence, and template-role-fit. The 2/3 supermajority threshold reflects that this is a structural decision requiring strong consensus.

**Q3 — old-pool LPs: standard DeFi behavior, no migration assistance.** Old-pool LPs hold their existing AuMT (representing their pool position), can withdraw at will, and may choose to enter the new pool independently if they wish. No special migration mechanic. Reasoning: a token failure in one pool would have everyone withdrawing anyway — the market handles the migration for free. Adding a "migration credit" mechanism would create a privileged class of LPs and contradict the "permissionless from block 0" framing.

**The AuMT governance-weight clarification (important enough to call out separately):**

AuMT carries governance weight if and only if it represents an LP position in a **currently-gauged pool**, subject to F-9 dampening (Era 0 fourth root → Era 1+ cube root) and the time-in-pool / withdrawal-reset rules from `04_tokenomics.md` §ix. The moment a pool's gauge is revoked — whether by composition challenge, by gauge challenge, by 4-consecutive-disqualified-epoch automatic revocation, or by any other path — the AuMT for that pool drops to zero governance weight at that block. The LP's other entitlements continue: pool-share-of-tokens, ERC-4626 native yield, swap fees that hit the pool (now flowing entirely to der Bodensee via the still-attached hook). Only governance power is lost.

This is consistent with `08_bootstrap.md` §xxiii line 1457 (*"AuMT in pools that fail any eligibility criterion carries zero governance weight"*) and `04_tokenomics.md` §ix line 497 (*"AuMT in pools that fail any eligibility criterion carries zero governance weight"*) — but worth restating in the composition challenge context because the deprecated pool isn't "failing eligibility" so much as "no longer being a Miliarium slot." The mechanism is the same: governance weight follows the gauge.

**Concrete contract behavior (deferred to design-doc level):**

- **New contract: `MiliariumRegistry.sol`** — stores `slot → currentPoolAddress`. `replaceSlot(slotN, newPoolAddress)` is `onlyGovernanceContract`. Constructor seeds the 28 slots with their genesis pool addresses. Emits `SlotReplaced(slot, oldPool, newPool, blockNumber)` events.
- **`AureumGovernanceAuthorizer` interaction:** Composition challenges don't touch the Vault, so they don't need the authorizer. The governance contract calls `MiliariumRegistry.replaceSlot(...)` directly.
- **Gauge registry integration:** when `MiliariumRegistry.replaceSlot` fires, the gauge registry must (a) revoke the old pool's gauge and (b) auto-approve the new pool's gauge with the 90-day boost activated. Both happen atomically in the same transaction as the registry update.
- **Fee-routing hook:** stays attached to the deprecated pool. No-op from a contract perspective — the hook is at the pool level, not the gauge level.

**Spec edits required in `aumm-site`:**

- **`10_constitution.md` §xxvii Composition Challenge Rule:** add the four sub-rules above. Include the explicit statement that *"the proposal must reference an already-deployed candidate pool address"* and the deprecate-but-keep-hook clarification.
- **`08_bootstrap.md` §xxiv Composition Challenge worked example:** add a step-by-step walk-through using the cbBTC delisted → tBTC replacement scenario to illustrate. Show the candidate-pool deploy, the 2/3 supermajority vote, the registry update, the auto-gauge-approval with 90-day boost, and the deprecated pool's continued existence (LPs withdraw or stay; hook keeps routing fees; no AuMM emissions).
- **`12_aureum_glossary.md` §xxxv Governance entries:** add a clarification to the Composition Challenge entry that the deprecated pool's AuMT loses governance weight at the gauge-revocation block, while other entitlements continue.
- **`05_miliarium_aureum.md` §xv Status Tracking:** the `Active → Warning → Disqualified ⇄ Composition Challenge` flowchart is correct; add a note that "Composition Challenge" deprecation does not delete the old pool — it persists as a non-Miliarium, non-gauged pool with hook-permanent fee routing.

### OQ-8 (RESOLVED): F-12 gauge-challenge deposit — BTC as unit of account, paid in stablecoin

**Decision (2026-04-15):** Two clarifications that together resolve the question:

**1. The BTC denomination is a *unit of account*, not a payment currency.** The "10 BTC expressed in CHF" formulation in F-12 line 900 exists because BTC tracks purchasing power across cycles better than any USD-denominated figure. A "10-BTC-equivalent deposit" remains economically meaningful at $40K BTC and at $200K BTC — a flat USD floor would become trivial in a bull market and prohibitive in a bear market. BTC is the yardstick the deposit *size* is measured against; nothing about BTC actually changes hands.

**2. The price is a spot read averaged across all gauged pools holding any wrapped-BTC token.** Not hardcoded to a specific pool, not hardcoded to a specific BTC wrapper:

- The contract enumerates currently-gauged pools.
- For each, it checks whether the pool's token list contains any registered wrapped-BTC token (WBTC, cbBTC, tBTC, future wrappers).
- For each match, it computes the spot rate of that BTC-wrapper against svZCHF (or against sUSDS if svZCHF isn't in the pool, then converted via the constellation's natural arb relationships).
- The submission deposit calculation uses the **average** of those rates.
- If a wrapper deprecates (e.g. cbBTC delisted), it falls out of the average — no contract change required.
- If a new BTC wrapper enters the constellation via composition challenge or new gauge approval, it auto-joins.

**Why spot (not TWAP) is fine here:**

- **Averaging dilutes single-pool manipulation.** An attacker would need to push BTC/svZCHF down across all BTC-holding pools simultaneously, in the same block. As the constellation grows and more BTC pools are gauged, the cost of cross-pool manipulation rises faster than any deposit savings.
- **Arbitrage keeps cross-pool rates aligned.** WBTC/svZCHF in pool A and cbBTC/svZCHF in pool B can't drift far without arbers closing the gap. Spot reads end up roughly consistent.
- **The CHF floor in F-12's second formula backstops a low BTC reading.** F-12 takes the *greater* of (a) "10 BTC equivalent in CHF" and (b) "1,000,000 CHF × √((1−p_tvl)(1−p_eff))". If BTC manipulation drops the (a) calculation to near-zero, the (b) calculation — denominated directly in CHF — keeps the deposit meaningful. The two formulas backstop each other.
- **It's a one-time fee paid by the challenger's wallet, not a hot-path operation.** Gauge challenges are infrequent. Spending a few hundred thousand gas to enumerate pools + read spot prices + average is fine.

**3. The actual deposit transfer is in stablecoin (svZCHF or sUSDS, whichever is higher per F-12 line 900).** The challenger needs the stablecoin in their wallet at submission time. No BTC ever moves. The submission transaction:

1. Computes the deposit size in CHF using the averaged spot BTC/svZCHF rate (yardstick).
2. Computes the deposit size in CHF using the second formula (CHF-denominated minimum).
3. Takes the larger.
4. Converts to whichever of svZCHF or sUSDS the challenger holds (the contract reads the challenger's balance and accepts whichever covers the deposit; if both work, accepts svZCHF by default).
5. Transfers the stablecoin from challenger's wallet to the OQ-1 fee-routing primitive, which one-sided-deposits it into der Bodensee.

All atomic in the submission transaction. No multi-step process, no oracle dependency, no off-chain prices, no Chainlink, no TWAP-state-write overhead.

**Concrete contract sketch (deferred to implementation stage):**

```solidity
// Pseudocode — F-12 deposit calculation
function gaugeChallengeDeposit(address targetPool) public view returns (uint256 amount, address stablecoin) {
    uint256 btcChfPrice = _averageBtcChfFromGaugedPools();  // averages across all BTC-holding gauged pools
    uint256 tenBtcEquivalent = 10 * btcChfPrice;            // CHF amount equivalent to 10 BTC
    
    (uint256 pTvl, uint256 pEff) = _percentileRanks(targetPool);
    uint256 chfFloor = 1_000_000 * sqrt((1e18 - pTvl) * (1e18 - pEff)) / 1e18;
    
    uint256 chfAmount = max(tenBtcEquivalent, chfFloor);
    
    // Convert CHF amount to whichever stablecoin the caller can pay
    return _selectStablecoin(chfAmount, msg.sender);
}
```

The `_averageBtcChfFromGaugedPools()` helper enumerates the gauged-pool registry, filters for pools containing tokens in the `BTC_WRAPPERS` set, reads spot rates, averages. The `BTC_WRAPPERS` set is itself updatable through governance (via the same mechanism that adds new gauged pools or composition challenges) so new wrappers can join the calculation when they enter the ecosystem.

**Spec edits required in `aumm-site`:**

- **`11_formulas.md` F-12:** add the "BTC/CHF reference price source" subsection making explicit: (1) BTC is a unit of account, not a payment currency; (2) price = average spot rate from all gauged pools holding any registered wrapped-BTC token; (3) deposit is paid in svZCHF or sUSDS one-sided into der Bodensee; (4) two-formula max ensures the deposit stays meaningful under any BTC price regime.
- **`10_constitution.md` §xxix:** add `BTC_WRAPPERS` (the registered set) to the immutable parameters, with a note that the set is governance-extensible to accommodate future wrappers (a future composition challenge can add a new wrapper alongside the pool addition).
- **`12_aureum_glossary.md`:** brief glossary entry on the BTC reference mechanism — "BTC as unit of account, deposit paid in stablecoin, price averaged across all gauged BTC-holding pools."

### OQ-9 (RESOLVED): F-12 elite-tail rank/N — N includes all gauged pools, including the target

**Decision (2026-04-15):** N = total count of currently-gauged pools, including the 28 Miliarium pools and the target pool itself. The target's own rank contributes to its percentile calculation. The 10-BTC-equivalent floor (from F-12's max-of-two-formulas rule) prevents pathological zero-deposit cases at the elite tail.

This ratifies the spec's existing language at `11_formulas.md` line 902 (*"Among all gauged pools (including Miliarium), N = count of gauged pools"*). Including Miliarium pools as denominators ensures non-Miliarium pools are ranked relative to the entire gauged-pool population — a "top non-Miliarium" pool that's actually mid-tier protocol-wide gets a mid-tier deposit, not a near-zero one. That's the intended elite-tail-progressive behavior.

At genesis (28 Miliarium gauged, 0 non-Miliarium gauged), the first non-Miliarium gauge approval would have its rank computed against those 28. As the constellation expands, N grows. Functionally identical to the alternative reading (N excluding target) past N ≈ 30; the difference vanishes at any realistic gauged-pool count.

**Spec edits required in `aumm-site`:**
- **`11_formulas.md` F-12:** add a one-sentence clarification: *"N includes all currently-gauged pools — the 28 Miliarium pools, all gauged non-Miliarium pools, and the target pool itself. The target's own rank contributes to its percentile calculation. At small N, the 10-BTC-equivalent floor (from the max-of-two-formulas rule) prevents pathological zero-deposit cases."*

### OQ-10 (RESOLVED): Governance↔authorizer — B-strict with a 12-month multisig time-bomb

**Decision (2026-04-15):** When the on-chain governance contract ships, the Stage B authorizer is replaced by a new `AureumGovernanceAuthorizer` via a one-shot `Vault.setAuthorizer(newAuthorizer)` transaction signed by the Stage B multisig. After that single transaction, the governance contract is the primary authorized account; the multisig retains an emergency-only role for **12 months** from the migration block, after which the multisig clause dies permanently — the multisig has no authority anywhere, ever again.

**Why a 12-month time-bomb instead of riding the Vault's 4-year pause window or going fully strict:**
- A pure no-multisig design loses the safety net during the highest-risk operational window (the months immediately following governance launch, when audit-caught-or-not bugs would surface in production).
- Riding the Vault's full 4-year window keeps the multisig "alive" much longer than necessary. The audit + testnet stage are supposed to catch critical bugs before launch, and 12 months of post-launch coverage is well past the period where most critical-bug discovery happens.
- 12 months is a compromise: the constitution becomes literally true within the first protocol year (which is also when emission allocation transitions from equal → blend → CCB, so one full protocol year of "training wheels" coverage), then permanently true thereafter.

**The new authorizer's `canPerform`:**

```solidity
contract AureumGovernanceAuthorizer is IAuthorizer {
    address public immutable GOVERNANCE_CONTRACT;
    address public immutable EMERGENCY_MULTISIG;
    uint256 public immutable EMERGENCY_WINDOW_END_BLOCK;
    // EMERGENCY_ACTIONS: a small set of action IDs hardcoded as immutables,
    // limited to pauseVault, enableRecoveryMode, possibly disableQuery.
    // Everything else (fee setters, fee controller setter, etc.) is GOVERNANCE_CONTRACT-only.

    function canPerform(bytes32 actionId, address account, address /* target */)
        external view returns (bool)
    {
        if (account == GOVERNANCE_CONTRACT) {
            return true; // governance can do anything authorizer-gated
        }
        if (account == EMERGENCY_MULTISIG
            && _isEmergencyAction(actionId)
            && block.number < EMERGENCY_WINDOW_END_BLOCK)
        {
            return true; // narrow emergency clause, time-boxed
        }
        return false;
    }
}
```

**Constants this pins:**
- `EMERGENCY_WINDOW_BLOCKS = 12 × BLOCKS_PER_MONTH = 2_628_000` blocks (1 protocol year per OQ-3, ~365 calendar days)
- `EMERGENCY_WINDOW_END_BLOCK = migrationBlock + EMERGENCY_WINDOW_BLOCKS` (immutable, set in constructor)
- `EMERGENCY_ACTIONS` — small fixed set: `pauseVault`, `enableRecoveryMode`, `disableQuery` (TBD which exactly; design-doc detail at implementation time)

**Why the 12-month window starts at migration, not at vault-deploy:**
- If we keyed it off vault-deploy, the multisig might be alive for ~6 months before governance even ships, leaving a few months of post-governance coverage. Better to give a clean 12 months of post-governance coverage.
- Stage B's authorizer keeps its current shape until migration. Migration happens when the governance contract is deployed and tested.

**What this means for governance vote types — all four work cleanly under this design:**

| Proposal type | Mechanism after vote passes | Authorizer involved? |
|---|---|---|
| Gauge proposal (approve new gauge) | `governanceContract.executeApproveGauge(...)` calls `gaugeRegistry.approveGauge(pool)` — Aureum-internal, gauge registry has its own `onlyGovernanceContract` modifier | No |
| Gauge challenge (revoke gauge) | `governanceContract.executeRevokeGauge(...)` calls `gaugeRegistry.revokeGauge(pool)` — Aureum-internal | No |
| Composition challenge (replace Miliarium slot) | `governanceContract.executeCompositionChallenge(...)` calls `miliariumRegistry.replaceSlot(slotN, newPool)` — Aureum-internal | No |
| Fee parameter change | `governanceContract.executeFeeChange(...)` calls `Vault.setStaticSwapFeePercentage(pool, newFee)` — Vault asks authorizer "can `GOVERNANCE_CONTRACT` perform this?" → yes | **Yes** |

Three of the four proposal types never touch the Vault at all — they manipulate Aureum-owned registries, which gate themselves on `onlyGovernanceContract` directly. Only fee changes go through the authorizer, and the new authorizer recognizes the governance contract.

**Sandbox fast-track and gauge revocation after 4 disqualified epochs are also Aureum-internal** — they don't need any vote. The gauge registry watches the efficiency tournament results and triggers automatically. No authorizer, no governance contract.

**Spec/code edits required:**
- **New contract:** `AureumGovernanceAuthorizer.sol` (`src/governance/`).
- **Modified existing contract:** none — the Stage B `AureumAuthorizer.sol` stays in place until migration. Migration is a single `Vault.setAuthorizer(newAddr)` transaction signed by the existing multisig.
- **Constitution edit (`10_constitution.md` §xxvii and §xxix):** the "no multisig" clause needs a footnote acknowledging the bounded 12-month emergency window post-governance-migration. Same shape as F6 (the current Stage A 4-year carve-out), just with a different end-of-window date.
- **Spec edit (`02_mental_model.md`, `12_aureum_glossary.md` §xxxiv):** mention the bounded post-migration window so the "no multisig" framing isn't taken as literally always-true even before Year 1 ends.

**Migration-event sequencing (when this stage is planned):**
1. Governance contract is fully tested, audited, and deployed.
2. Multisig signs `Vault.setAuthorizer(newGovernanceAuthorizer)` — single transaction, executes the migration.
3. From that block forward, the new authorizer is live: governance contract is primary; multisig has emergency-only authority for the next 2,628,000 blocks (~12 months).
4. After block `EMERGENCY_WINDOW_END_BLOCK`, the multisig clause is permanently dead. The constitution becomes literally true.

**OQ-10 retires F10 as well** — F10 in the Findings section flagged the "authorizer is the chokepoint" issue. With B-strict-12mo, the chokepoint moves from the multisig to the governance contract, with a bounded fallback. F10 should be updated to reference this resolution.

### OQ-11 (RESOLVED): Per-pool swap fees — governable within pool-class bands, with cooldown

**Decision (2026-04-15):** Per-pool swap fees are governable within immutable bands. Three pool classes, three bands, with a `BLOCKS_PER_EPOCH` cooldown between fee changes on any given pool.

**The three pool classes and their fee rules:**

| Pool class | Band (min–max) | Genesis default | Set how |
|---|---|---|---|
| Miliarium pools (the 28) | **0.01% – 0.30%** | **0.03%** | Hardcoded default at deployment for all 28; adjustable via governance vote |
| Non-Miliarium gauged pools | **0.01% – 0.30%** | Set by the gauge-proposal vote at creation | Initial fee set by the same vote that approves the gauge; adjustable later via separate fee-change proposal |
| Der Bodensee | **0.10% – 1.00%** | **0.75%** | Hardcoded default at deployment; adjustable via governance vote within the band |

**The 0.01%–0.30% band** (Miliarium + non-Miliarium gauged) replaces my earlier recommendation of 0.01–0.05%. 0.30% is a meaningful upper bound — higher than stable-pair tiers like Curve's 0.04%, low enough that Miliarium pools remain competitive routing infrastructure. The wider band gives governance room to tune pools that are underperforming in the efficiency tournament (F-10) — a pool with heavy volume might cut its fee to boost routing share; a pool with low volume but deep TVL might raise its fee to capture more per-swap revenue.

**The 0.10%–1.00% band for Bodensee** preserves Bodensee's structural character as a deep-friction reserve. The 0.10% floor prevents governance from turning Bodensee into a cheap routing venue (which would defeat its "lake that only gets deeper" framing and potentially accelerate AuMM price discovery beyond intended levels). The 1.00% ceiling allows response to extreme conditions — governance could raise the fee during bootstrap periods or liquidity crises to slow withdrawal rate, or lower it during mature operation to improve capital efficiency.

**Miliarium pools participate in the F-10 efficiency tournament.** From `MONTH_13_START_BLOCK` onward, all gauged pools (Miliarium + non-Miliarium) are scored on efficiency and can adjust their fees strategically to improve rank. The Miliarium-vs-non-Miliarium distinction matters for gauge challenges (only non-Miliarium can be gauge-challenged per F-12) and for CCB multiplier adjustments (only Miliarium pools get multiplier updates per §vii) — but efficiency competition and fee-tuning flexibility apply to both.

**Cooldown:** `FEE_CHANGE_COOLDOWN_BLOCKS = BLOCKS_PER_EPOCH = 100,800` (~14 days). Each pool can have its fee changed at most once per epoch. Prevents rapid-fire manipulation, aligns with the bi-weekly CCB cadence, keeps LP behavior predictable. Reuses an existing canonical constant — no new time unit.

**Governance mechanics for fee changes:**

Standard governance proposal: 20% quorum, 50%+1 majority, per `08_bootstrap.md` §xxiii. Proposer identifies the target pool and the new fee (must fall within the pool's class band). Vote passes → the AureumGovernanceAuthorizer calls `Vault.setStaticSwapFeePercentage(pool, newFee)` once the cooldown check confirms the last change was ≥ `BLOCKS_PER_EPOCH` ago.

Non-Miliarium gauged pools' initial fee is set by the gauge-approval vote itself — the proposal specifies the fee as part of the gauge parameters (alongside composition, template role, etc.). No separate fee-change proposal is needed at creation; the gauge approval *is* the fee approval. Subsequent adjustments follow the standard fee-change proposal path.

**Concrete immutable parameters for §xxix:**

```
MILIARIUM_SWAP_FEE_MIN       = 0.0001e18   // 0.01%
MILIARIUM_SWAP_FEE_MAX       = 0.003e18    // 0.30%
MILIARIUM_SWAP_FEE_GENESIS   = 0.0003e18   // 0.03% — deployment default for all 28
BODENSEE_SWAP_FEE_MIN        = 0.001e18    // 0.10%
BODENSEE_SWAP_FEE_MAX        = 0.01e18     // 1.00%
BODENSEE_SWAP_FEE_GENESIS    = 0.0075e18   // 0.75% — deployment default
NON_MILIARIUM_SWAP_FEE_MIN   = 0.0001e18   // 0.01% (same as Miliarium)
NON_MILIARIUM_SWAP_FEE_MAX   = 0.003e18    // 0.30% (same as Miliarium)
FEE_CHANGE_COOLDOWN_BLOCKS   = 100_800     // = BLOCKS_PER_EPOCH
```

**Spec edits required in `aumm-site`:**

- **`10_constitution.md` §xxix:** add the immutable parameters table above. The band bounds and cooldown are immutable from block 0; the current fee of each individual pool is state that governance can adjust.
- **`08_bootstrap.md` §xxiii (governance scope):** add "per-pool swap fee adjustment within the immutable pool-class band, subject to `FEE_CHANGE_COOLDOWN_BLOCKS` cooldown" as a valid proposal type. Also note that non-Miliarium gauge proposals include the initial fee as one of the gauge parameters.
- **`13_appendices.md` xxxix LP Advantage table line 1884:** update the "0.01–0.05% per-pool swap fee" language to "0.01–0.30% per-pool swap fee (Miliarium genesis 0.03%, governance-adjustable within band with 14-day cooldown; Bodensee 0.10–1.00% band, genesis 0.75%)".
- **`04_tokenomics.md` §ix line 535 Governance Scope:** confirm that "Fee parameters (swap fee %, yield fee %)" includes per-pool swap-fee adjustment within the documented bands.
- **`11_formulas.md` F-10 efficiency tournament:** add a note that pool operators / governance can tune fees to improve efficiency rank — higher volume via lower fees, or higher per-swap revenue via higher fees, whichever optimizes the pool's efficiency score given its composition and user base.
- **Stage B `AureumProtocolFeeController` review:** the fee controller currently enforces Bodensee's 0.75% as an immutable constant in B8. This needs to be relaxed — Bodensee's fee becomes governance-adjustable within 0.10–1.00%, with 0.75% as the deployment default. The B10 enforcement target (feeRecipient) is still immutable; only the rate becomes adjustable. Minor refactor; worth noting for the Stage B2 / early C plan.

**Strategic note (not a spec edit):** allowing Bodensee's fee to be governance-adjustable is a genuine change from my earlier reading of §xxix as "0.75% immutable." This expands governance's surface of control over the reserve's behavior. The 0.10–1.00% band is wide enough to matter economically — governance could cut Bodensee's fee to 0.10% to boost AuMM price discovery in a bear market, or raise it to 1.00% to slow withdrawal in a panic. This is a real governance lever; worth being aware of it.

### OQ-12 (RESOLVED): Partner Stable in ixCambio = JPYC (+ tGBP replaces s-tGBP)

**Decision (2026-04-15):** Two token changes to ixCambio:

**1. Partner Stable slot = JPYC** at `0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29` (mainnet Ethereum). JPYC is a regulated Japanese-yen stablecoin issued by JPYC Inc. under Japan's Payment Services Act, backed 1:1 by domestic bank deposits and Japanese Government Bonds, with full PSA-compliant 1:1 redemption to JPY. Confirmed on the JPYC official GitHub organization (`github.com/jpycoin`) and Etherscan. Token type: **ERC-20** (not ERC-4626 — no sJPYC wrapper exists; JPYC Inc. funds operations from JGB interest, Circle-style).

**2. GBP slot = plain tGBP (not s-tGBP).** The spec's `07a_tokens.md` originally listed `s-tGBP` (staked tGBP). A search for an on-chain ERC-4626 wrapper on Morpho/Euler/Frax/Aave/other lending-market venues turned up nothing. ixCambio uses plain **tGBP** (token type **ERC-20**) instead. If a yield-bearing GBP wrapper appears later on mainnet, a composition challenge can swap it in.

**Strategic note:** JPYC is the first regulated Asian stable in the constellation. ixCambio's CHF/EUR/GBP/USD/JPY composition makes it a true global FX hub rather than a Western-only hub.

**Spec edits required:**
- `07a_tokens.md` — replace the `[Partner Stable] (reserved)` row with JPYC (ticker `JPYC`, type ERC-20, address `0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29`, notes "Regulated JPY stablecoin — JPYC Inc., Japan PSA-licensed; backed by JGBs and bank deposits"). Replace `s-tGBP` with `tGBP` (ticker `tGBP`, type ERC-20, notes "Tokenised GBP stablecoin"). Address for tGBP to be filled in at deployment time.
- `05_miliarium_aureum.md` Section xi Yield table — update the ixCambio row per the reweighted composition below (OQ-12a).
- `miliarium_profiles/07_ixCambio.md` — update Composition table per OQ-12a reweighting; update theme rationale to mention JPYC as first Asian-regulated stable.
- `miliarium_profiles/04_ixViatica.md` — update st-EURA classification to ERC-4626 (it's the same Angle Savings token, confirmed independently — this bumps ixViatica's ERC-4626 share from 52% to 68%, comfortable margin).

### OQ-12a (RESOLVED): ixCambio reweighted — 55% ERC-4626

**Decision (2026-04-15):** ixCambio is reweighted. The three ERC-20 tokens drop to 15% each; the three ERC-4626 tokens split the remaining 55% with svZCHF (the primary routing anchor) getting the extra point.

| Component | Token | Weight | Type | Role |
|---|---|---|---|---|
| Yield core / CHF anchor | **svZCHF** | **19%** | ERC-4626 | Frankencoin savings vault — primary routing rail |
| 4626 EUR yield core | **st-EURA** | **18%** | ERC-4626 | Angle Savings (EURA yield; implementation `SavingsNameable` extending OpenZeppelin `ERC4626Upgradeable`) |
| 4626 EUR yield core | **aEURS** | **18%** | ERC-4626 | Aave V3 stataToken wrapper for Stasis EURS |
| Routing anchor | **ixEDEL** | **15%** | ERC-20 (Reserve DTF) | Cross-pool routing — back to standard 15% connector weight (prior 20% was already non-standard) |
| GBP leg | **tGBP** | **15%** | ERC-20 | Tokenised GBP stablecoin (no 4626 wrapper available at deployment time) |
| JPY leg | **JPYC** | **15%** | ERC-20 | Regulated JPY stablecoin (JPYC Inc., Japan PSA) |

**Weight sum: 100%. ERC-4626 composition: 55%** (svZCHF 19% + st-EURA 18% + aEURS 18%). **Margin above the immutable 52% floor: 3 points.** Pool qualifies for gauge approval under the immutable Quality Gate without any constitutional carve-out.

**Why this shape:**
- Pure-even split of 55% across three 4626 tokens is 18.33% each — expressible in Solidity FixedPoint but ugly. Rounding with the extra point on svZCHF is cleanest. svZCHF gets the bump because it's the primary routing anchor per `02_mental_model.md`.
- ERC-20 legs (ixEDEL, tGBP, JPYC) all at 15% emphasizes they're peers — routing hub, GBP rail, JPY rail, equally important for the FX function.
- ixEDEL dropping from 20% to 15% is a small loss of routing depth in this specific pool but restores it to the standard connector weight seen in 24 of the 28 Miliarium pools. Net routing depth for ixEDEL across the constellation is unaffected (ixEdelweiss is the 46% primary hub; ixCambio was an outlier).

**All Balancer V3 weighted-pool constraints satisfied:**
- 6 tokens (max 8 per `docs/balancer_v3_reference.md`)
- All weights ≥ 1% (min per `_MIN_WEIGHT`) and ≤ 99%
- Sum to exactly 100% (no FixedPoint rounding errors needed — 19+18+18+15+15+15 = 100)

**Spec edits required:**
- `05_miliarium_aureum.md` Section xi Yield table, ixCambio row:
  - Old: `<td>ixEDEL 20%</td> ... <td>st-EURA 16%, aEURS 16%, s-tGBP 16%, [Partner Stable] 16%</td>` with svZCHF 16%
  - New: `<td>svZCHF 19%, st-EURA 18%, aEURS 18%</td> <td>ixEDEL 15%</td> <td>tGBP 15%, JPYC 15%</td>`
- `miliarium_profiles/07_ixCambio.md` Composition table — full rewrite per the table above. Template label changes from "Non-Standard (6-token FX hub)" to "Non-Standard (6-token FX hub, 4626-heavy)".
- Same profile, "ERC-4626 composition" line — update from "32% minimum (svZCHF + aEURS) — may require Partner Stable..." to **"55% (svZCHF + st-EURA + aEURS) — exceeds 52% threshold."**
- Same profile, Performance Discipline table — change "4626 Quality Gate | Monitoring required — 32% confirmed ERC-4626..." to **"4626 Quality Gate | ≥52% — met by svZCHF (19%) + st-EURA (18%) + aEURS (18%) = 55%"**.
- Same profile, Risk Profile — **remove** "4626 Quality Gate compliance requires monitoring (currently borderline)". Replace with "JPYC regulatory risk (PSA-licensed, Japan-specific compliance)".
- `07a_tokens.md` — change `st-EURA` row's "Token type" from ERC-20 to **ERC-4626** with note about Angle's `SavingsNameable`. Change `s-tGBP` entry to `tGBP` as ERC-20. Add JPYC row per OQ-12.
- `miliarium_profiles/04_ixViatica.md` — update st-EURA type to ERC-4626; update ERC-4626 composition from 52% to 68% (svZCHF 26% + GHO 26% + st-EURA 16%); raises ixViatica from "at the floor" to "comfortable margin."

**This resolution also updates F8a and F8b in the Findings section** — F8a is no longer HIGH severity; F8b's "borderline margin" note for ixCambio is inverted (now 3 points *above* floor, not 20 points below).

### OQ-13 (RESOLVED — subsumed by OQ-7): Composition challenge replacement-pool registry semantics

**Decision (2026-04-15):** Fully covered by OQ-7's resolution. Confirmed: the registry stores `slot → currentPoolAddress` (mutable mapping, not immutable). Updates are gated by `MiliariumRegistry.replaceSlot(slotN, newPoolAddress)`, which is `onlyGovernanceContract` and only callable after a successful 2/3-supermajority composition challenge vote. *"Slot is permanent, pool may change"* is exactly the contract semantic. See OQ-7 for the full design including the MiliariumRegistry contract sketch.

### OQ-14 (RESOLVED): Aequilibrium pool factories — use upstream Balancer V3 as-is, no fork

**Decision (2026-04-15):** Aureum uses upstream Balancer V3 pool factories directly. No `AureumWeightedPoolFactory` fork. Aureum-specific logic lives in the Vault's registration path and in deployment scripts, not in a forked factory.

**Minimal Aureum fork surface is preserved:**
- Stage B already forked `Vault.sol` → `AureumVault.sol` (22-line authorizer redirect).
- Stage B also forked `ProtocolFeeController.sol` → `AureumProtocolFeeController.sol` (~622 lines, since this contract needed substantive changes for the Bodensee-recipient-immutable property).
- `WeightedPoolFactory` (and any other pool factories) remain **bytecode-identical to upstream**. Aureum deploys fresh instances pointed at the Aureum Vault; factory code itself is unchanged.

**Where Aureum-specific constraints live:**

1. **Vault-level `registerPool` path** — the 52% ERC-4626 Quality Gate check for Miliarium pools, OQ-1 hook attachment for all non-Bodensee gauged pools, Rate Provider configuration for ERC-4626 tokens, and initial swap fee setting per pool class. These are natural `registerPool`-time checks; duplicating them in a factory fork would add audit surface without functional benefit.

2. **Deployment scripts** (`aumm-deploy/script/`) — one script per pool, driven by parameter files (composition, weights, theme tokens, template role). Orchestrates: standard `WeightedPoolFactory.create(...)` → `AureumVault.registerPool(...)` with the Aureum-specific parameters. 28 Miliarium pools at genesis plus der Bodensee plus whatever non-Miliarium gauged pools get approved later.

3. **`MiliariumRegistry.sol`** (from OQ-7) — tracks slot → current pool address, updated by governance on composition challenge. Separate from pool creation itself.

**Why upstream factories work cleanly here:**
- Audit inheritance: no new factory code to audit; full inherited Balancer V3 coverage.
- Flexibility: non-Miliarium gauged pools have different constraint rules than Miliarium pools (no automatic Quality Gate check at deployment since they're approved case-by-case by governance); using the standard factory with per-pool-type Vault-level rules is cleaner than maintaining two factory forks.
- Stage A precedent: matches the deliberate minimal-fork discipline that underlies the whole audit-inheritance strategy.

**Note on pool type coverage.** All 28 Miliarium pools per spec are weighted pools with custom weights. Der Bodensee is a weighted pool (40/30/30). So `WeightedPoolFactory` is sufficient for genesis. If a future gauge approval wants a different pool type (e.g. a stable-math pool), the corresponding upstream factory can be used as-is — again, no fork needed. The only scenario that would require a factory fork is one where Aureum wants pool *math* that doesn't exist in Balancer V3 — nothing in the spec calls for this.

**Spec edits required:**

- **None to user-facing specs.** This is purely an implementation-strategy decision.
- **`aumm-deploy/docs/STAGE_A_PLAN.md`** (when revisited in Stage C planning): add under "Minimal Aureum fork surface" that pool factories are not forked — only `Vault.sol` and `ProtocolFeeController.sol`. `WeightedPoolFactory` (and any other Balancer V3 factory Aureum uses) is deployed bytecode-identical to upstream.
- **Stage-C-or-later pool deployment plan**: use standard Balancer V3 `WeightedPoolFactory`; Aureum-specific configuration (weights, rate providers, hook, initial fee) happens via the Vault's `registerPool` path and deployment scripts.

### OQ-15 (RESOLVED): Testnet strategy = hybrid (stubs on Holesky + mainnet fork for integration)

**Decision (2026-04-15):** Option (c) — hybrid strategy.

- **Public testnet (Holesky):** deploy minimal stub versions of svZCHF, sUSDS, ixEDEL, and the major theme tokens (waEth wrappers, GHO, fBRZ, JPYC equivalents, the `*on` tokenized assets). Stubs implement the relevant interfaces (`IERC20`, `IERC4626 totalAssets/convertToShares/convertToAssets`, NAV-providing methods for ixEDEL) but are inert with respect to real-world value. Anyone can interact with this deployment to validate Aureum-owned logic in production-like conditions, including governance flows, gauge approvals, fee routing, the OQ-1 hook behavior, and CCB scoring.
- **Mainnet fork (local Anvil + Tenderly devnet):** for end-to-end integration testing against real Frankencoin / Aave V3 / Reserve Protocol DTF / Sky / Flux behavior. Used by the founding team and the audit firm during code review; not publicly accessible.

**Why hybrid:** the stubs let real users (including third-party gauge proposers, Sandbox-pool deployers, and the audit team) interact with Aureum's logic on a live public chain without waiting for mainnet integration partners. The mainnet fork validates that the integration story actually works against real upstream contracts. Neither alone covers both needs.

**Implementation note:** the stubs need to be deterministic and well-documented so anyone can independently verify behavior. They should *not* be upgradeable (otherwise they're another trust dependency for testnet users). A separate `aumm-deploy/test-stubs/` folder with one stub per real token, each ~50-100 lines of Solidity, kept under the same audit-inheritance discipline as the real contracts.

### OQ-16 (RESOLVED): Holesky now

**Decision (2026-04-15):** Holesky is the chosen public testnet. If/when Holesky is deprecated and replaced (Hoodi or whatever succeeds it), the stub deployments migrate. The choice is an operational one, not a constitutional one — the spec doesn't mention a specific testnet, and the Aureum-owned contracts are network-agnostic by design.

**Worth verifying at deployment time:** current Holesky status (it has been deprecated/sunset before in concept; check if it remains the live L1 testnet at the time the testnet stage is planned).

### OQ-17 (TBD — candidate firms enumerated): Audit firm and timing

**Status (2026-04-15):** Open. Selection deferred to the audit-stage planning conversation. Below is the candidate list to evaluate when that decision is made.

`13_appendices.md` xxxvi line 1811 estimates ~4,500 LOC of new Solidity audit scope. Realistic shape: 6-10 weeks calendar time, $150K–$500K budget depending on firm tier and review depth. No treasury exists to fund this (constitutional "no treasury" — see `10_constitution.md` §xxx), so funding is a separate question (founding team, grant from upstream protocols Aureum integrates with, donations, audit-firm contest model, or a structured pre-launch funding round).

**Candidate firms to evaluate:**

*Tier-1 traditional audit firms (multi-week engagements, deep reports):*
- **Trail of Bits** — long track record, formal-methods-friendly, expensive but thorough. Have audited Balancer V3 itself; would have prior context on the upstream code.
- **OpenZeppelin** — strong reputation, more product-engineering-focused than research-focused, common choice for protocol launches.
- **Spearbit** — collective of senior auditors, sometimes faster turnaround, strong for hooks-heavy designs and novel patterns (relevant to OQ-1 hook architecture).
- **Sigma Prime** — formal methods, long history with Ethereum core contracts.
- **Zellic** — newer top-tier firm, strong on DeFi mechanism design review (relevant to CCB / EMA / multiplier engine review).

*Contest / crowdsourced models:*
- **Cantina** — competitive contest model, broader auditor pool, often used as a complement to a tier-1 audit rather than a replacement.
- **Code4rena** — contest model, results-quality varies widely; useful as a pre-audit broad sweep.
- **Sherlock** — contest + insurance hybrid, contests pay-on-finding.

*AI-augmented continuous security platforms:*
- **Firepan** ([firepan.com](https://firepan.com/)) — AI-native continuous-security platform combining Hound (AI auditor), Slither (static analysis), Mythril (symbolic execution), and Echidna (fuzzing) under one orchestration. Pricing $239/mo Starter to $2,399/mo Enterprise for the platform; manual-audit add-ons quoted custom. Different model from the tier-1 firms: continuous monitoring of a deployed protocol rather than a one-shot pre-launch report. Relevant Aureum-specific connection: per user note, Garrit (former Curve ambassador, Leviathan News contributor) is involved with Firepan — potential warm intro if pursued. Worth evaluating both as a *complement* to a tier-1 audit (continuous monitoring layer) and potentially for the manual-audit service as a primary review.

**Practical considerations for the audit-stage decision:**
- **Combined approach is normal.** Tier-1 firm for the deep one-shot audit, plus a continuous-monitoring layer (Firepan or similar) for post-deployment, plus optionally a Cantina/Code4rena contest for broader coverage. Not "pick one."
- **Audit timing requires a code freeze** — testnet integration must be stable, and the protocol's full tokenomics layer must be code-complete before audit kickoff. Patches during audit are expensive and undermine the inheritance argument.
- **Specific scope split.** The Aureum-owned contracts (~4,500 LOC) need a full audit. The Balancer V3 substrate (Vault, pool factories, hooks framework, rate providers) inherits its existing Certora verification — see `13_appendices.md` xxxvi "What's Unchanged (Critical)" — and doesn't need re-auditing as long as Aureum's customizations stay within the documented extension points (`IAuthorizer`, `IProtocolFeeController`, `IHooks`).
- **The OQ-1 hook is on the audit hot path.** It runs on every swap on every gauged pool. Spend extra audit attention there. Probably worth a dedicated review pass on the hook itself separate from the broader review.

**Funding (separate decision, not part of audit-firm selection):**
- Founding team self-funds.
- Pre-launch contributions from Frankencoin / Reserve / Sky / similar protocols who benefit from Aureum's integration (analogous to how Yield Basis got crvUSD-backed support from Curve DAO).
- Grant from Ethereum Foundation, Optimism RetroPGF, or similar.
- Audit-firm sponsorship — some firms (e.g. Trail of Bits' Open Crypto Audit Project) do reduced-cost or pro-bono audits for genuinely public-good fair-launch protocols.
- Crowdfunding / donations from the eventual LP community (limited because pre-launch they have no AuMM stake).

**Decision deferred** — log the candidates here, revisit when the audit stage is being planned.

### OQ-18 (RESOLVED): Frontend = separate repo, separate plan, MVP required for testnet

**Decision (2026-04-15):** Three-part resolution:

**1. Separate repo: `aumm-app` (or similar name).** Frontend is its own codebase, not a subfolder of `aumm-deploy`. Different tooling stack (TypeScript + modern framework vs. Solidity + Foundry), different deployment cadence, different security model (frontend bugs mislead users; contract bugs lose funds — keeping them separate makes the distinction concrete in code ownership). The frontend consumes contract ABIs from `aumm-deploy` as a dependency but has its own lifecycle.

**2. Separate plan.** Frontend development gets its own stage plan, run in parallel with contract stages by a separate track of work (likely a separate team member once OQ-19 resolves). Frontend stages depend on contract ABIs being stable — meaning the frontend track lags the contract track by a meaningful amount (ABIs change substantially during Stage C/D; stabilize toward testnet; freeze at audit; no changes at mainnet). Practical implication: serious frontend engineering starts around the testnet-ready inflection point on the contract side.

**3. MVP is a testnet prerequisite.** The Holesky hybrid testnet (OQ-15) requires a usable frontend for validation — testing with Etherscan-only interactions doesn't validate UX, doesn't surface integration bugs that users would hit, and doesn't let third parties stress-test the protocol realistically. The MVP for testnet is the same MVP that ships at mainnet (polished between testnet and mainnet but not scope-expanded):

**MVP scope (testnet + mainnet launch):**
- Pool list — all 28 Miliarium pools + der Bodensee (unhidden post-Month 6) + any non-Miliarium gauged pools, each showing composition, current weights, template role, current CCB weight, current EMA TVL, current swap fee.
- LP deposit/withdraw interface — one-click add/remove liquidity for each gauged pool. Includes the one-sided-deposit path via the Aureum router for Incendiary Boost contributions to Bodensee.
- Swap interface — basic composite-swap via the constellation (for users who just want to trade). Could integrate with an aggregator (CoW, 1inch, Paraswap) rather than building routing from scratch — aggregators will naturally route through Aureum's pools once they're depth-thresholded.
- AuMT display — user's qualified AuMT per pool, pending AuMM emissions, time-in-pool status (14-day qualification progress, 6-month on-ramp progress for governance weight), governance-weight preview.
- Governance interface — list of active proposals (gauge proposals, gauge challenges, composition challenges, fee-change proposals), voting UI, proposal-submission UI for users who meet the deposit thresholds.
- Block-based time displays — halving countdown, Month 6 unhide countdown during the bootstrap, Era transition countdowns. All expressed as blocks with calendar-time aliases per OQ-5.

**Post-MVP (rolled out across subsequent protocol-months after launch):**
- TradingView-style AuMM price chart with historical CCB-weight overlays
- Efficiency tournament leaderboard with real-time rank updates
- Per-pool multiplier history visualization (bi-weekly cadence, so cheap to compute)
- Incendiary Boost dashboard (who's boosted what, current epoch's available boosts)
- Constellation visualization — the 28+N gauged pools as an interactive graph showing routing paths, TVL depth, CCB weights
- Detailed governance analytics (voter participation rates, proposal history, whale-watching)
- Mobile app (native or PWA)

**Out of scope (not currently planned):**
- Third-party integrations beyond a basic aggregator
- Advanced MEV tooling or MEV-protection wrappers on the user side
- Cross-chain UX (Aureum is Ethereum-mainnet-only per the spec)

**Staffing dependency:** frontend timeline is gated by OQ-19 (TBD founding team roles). With no frontend engineer hired, the frontend track doesn't start; with one hired, it runs in parallel with the contract track from their onboarding block. If frontend work gets delayed past the contracts' testnet-ready point, testnet validation stalls — the MVP isn't a nice-to-have, it's a path dependency for proper testnet coverage.

**Spec edits required in `aumm-site`:**
- **`14_ux_ui.md`** — split the 28+ items into "MVP (required for testnet and mainnet launch)" and "Post-MVP roadmap (rolled out over subsequent protocol-months)". The current document doesn't distinguish; a reader sees a single undifferentiated feature list. Making the MVP/post-MVP split explicit clarifies scope for frontend hiring and for third-party integrators looking to build on top.
- **`16_team.md`** — if the Frontend & UX role gets filled (per OQ-19 resolution), update accordingly. The frontend engineer's scope is `aumm-app` MVP for testnet + polish for mainnet + post-MVP roadmap execution.

**Implementation note (not a spec edit):** the MVP should be built against the Holesky stub deployment first, not against mainnet fork. Testing against stubs validates the UX flow without requiring real-asset integration risk. Once the UX is stable on Holesky, point the same frontend at a mainnet-fork devnet for integration validation. Finally, pre-launch, point at mainnet for production. One frontend codebase, three configurations.

### OQ-19 (DEFERRED): "TBD" founding team roles

**Status (2026-04-15):** Deferred, same treatment as OQ-17 (audit firm). Staffing decisions are outside the scope of this architectural gap-closing pass.

**Context captured for future reference:**
- `16_team.md` lines 2087–2088 list Smart Contracts and Frontend & UX as TBD.
- Stage C planning and everything downstream implicitly assumes *someone* is writing the contracts. If roles stay formally TBD, the work still happens — either by the existing person(s) driving the project, by paid contractors, or by grant-funded contributors — just without a named "founding team" title.
- **Cross-dependency with OQ-18:** testnet-stage frontend work is gated on the Frontend & UX role (or equivalent) existing in practice. If that role stays unfilled through the testnet-ready inflection point, testnet MVP validation stalls.
- **No code or spec changes required.** This is an organizational item, not a protocol item. `16_team.md` can be updated when/if the roles fill with names; until then the TBD markers are accurate.

**Not a blocker for FINDINGS closure.** Stage sequencing proceeds on the assumption that contract-implementation capacity exists; the formal team-page resolution can happen whenever it happens.

### OQ-20 — Yield-fee leg entry point: controller-initiated `routeYieldFee` call

**Status.** Resolved via D29 (structural) + D30 (harness gaps) as of 2026-04-22. Implementation deferred to **D4.6** (post-D7 controller entry-point sub-step).

**Context.** The ERC-4626 yield-fee leg is structurally distinct from the swap-fee leg:

- **Swap leg.** Vault takes fee → `AureumProtocolFeeController._receiveAggregateFees` saturates at `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE` per OQ-1; tokens route to hook via the B10 `withdrawProtocolFees` path.
- **Yield leg.** Vault accrues fees on `WITH_RATE` tokens (sUSDS, svZCHF per D11). `collectAggregateFees(pool)` is permissionless and routes tokens to the controller via `_vault.sendTo(token, address(this), ...)` at `src/vault/AureumProtocolFeeController.sol:334-341`. Tokens land on the controller — not the hook.

**Question.** How do yield-fee tokens reach `AureumFeeRoutingHook._swapFeeAndDeposit`?

**Options considered.**

- **Option A (resolved).** Controller exposes a governance-gated entry point that approves the hook for `amount` and calls `hook.routeYieldFee(pool, token, amount)`. The hook's `routeYieldFee` pulls via `safeTransferFrom(controller, hook, amount)` — preserving the structural invariant **`safeTransfer` (B10 withdraw path) ≠ `safeTransferFrom` (routeYieldFee path)**.
- **Option B (rejected).** Reuse `withdrawProtocolFees(pool, hook)` — the 2-arg B10 path already enforces `recipient == FEE_ROUTING_HOOK` via `InvalidRecipient` at `src/vault/AureumProtocolFeeController.sol:639-642`. Rejected because B10 is the swap-leg withdrawal path; collapsing the two paths obscures the `safeTransfer` vs `safeTransferFrom` asymmetry and conflates leg semantics.

**Resolution (Option A).** A new controller entry point — signature TBD at D4.6, likely `routeYieldFeeToHook(address pool, IERC20 token, uint256 amount) external authenticate` — authorized via `AureumAuthorizer` (governance multisig per `src/vault/AureumAuthorizer.sol:19-21`). The entry point approves the hook and calls `routeYieldFee`. Structural invariant preserved.

**Deferred to D4.6.** D7 fork tests cover the `routeYieldFee` primitive directly (hook-side, via `vm.prank(FEE_CONTROLLER)`) — not the controller entry point. The controller entry point lands at D4.6, after §D7 wiring is proven.

**Spec edits required (aumm-site, user-side).** `04_tokenomics.md` §ix yield-fee leg prose needs amendment to match Option A semantics (controller calls hook via `routeYieldFee`, not "withdraws to hook"). Flagged for user's spec-side update; not a repo edit.

---

## What this document does NOT decide

**FINDINGS has closed on all architectural / design / protocol-ambiguity questions.** What remains for subsequent conversations:

- **The stage sequence.** Stage C and beyond — letter assignments, ordering of the tokenomics / CCB / gauge / governance / fee-router / registry / pool-deployment stages. This is the next conversation, taking this document as input.
- **The folder layout for new code.** Proposed in the intro (`src/token/`, `src/emission/`, `src/ccb/`, `src/gauge/`, `src/governance/`, `src/registry/`, `src/pools/`, `src/incendiary/`, `src/fee_router/`) but not finalized. The stage-sequence conversation should formalize this.
- **The application of FINDINGS resolutions to the spec files.** Each resolved OQ has a "Spec edits required" subsection listing concrete edits to `aumm-site`. Applying them by hand in Cursor is the user's responsibility and happens outside this repo.
- **The application of FINDINGS resolutions to the Stage A / Stage B docs.** OQ-10 and OQ-11 in particular surface changes to `STAGE_A_PLAN.md` decision #3 and #4 / #7, and to the Stage B `AureumProtocolFeeController`'s current Bodensee-fee-immutability treatment. These update the historical stage plans in place.
- **Audit firm (OQ-17, deferred with candidate list).** Revisit when the audit stage is being planned.
- **Staffing (OQ-19, deferred).** Stays TBD in `16_team.md` until roles fill; cross-dep with OQ-18 for frontend timing.

Every other architectural decision is resolved. The protocol is now specified tightly enough to begin stage-by-stage implementation planning.

---

## Reference: source line counts

| File | Lines | Notes |
|---|---|---|
| `15_overview.md` | 95 | LP/builder track guides, file index |
| `02_mental_model.md` | 97 | Three layers, emission regimes, constellation routing, dual anchors |
| `10_constitution.md` | 108 | §xxvii control model + governance scope; §xxviii emission rules; §xxix immutable parameters; §xxx no treasury |
| `03_theoretical_foundation.md` | 113 | CCB narrative, EMA design, multiplier engine |
| `04_tokenomics.md` | 218 | Supply, halving, emission distribution, governance, fee routing, der Bodensee |
| `11_formulas.md` | 288 | F-0 through F-12 |
| `05_miliarium_aureum.md` | 184 | §xi 28-pool registry, §xii der Bodensee |
| `06_miliarium_manifest.md` | 71 | Master 28-pool table |
| `07_miliarium_sectors.md` | 128 | Sector taxonomy, correlation matrix |
| `07a_tokens.md` | 76 | 64-row token inventory |
| `08_bootstrap.md` | 233 | Cold-start, anti-gaming engine, governance gating |
| `09_transitions.md` | 71 | Month-by-month timeline |
| `12_aureum_glossary.md` | 82 | Term glossary |
| `13_appendices.md` | 164 | §xxxvi architecture provenance + audit scope; §xxxvii–xxxix competitive analysis |
| `14_ux_ui.md` | 146 | Frontend planning |
| `16_team.md` | 56 | Founding team, prior work, disclaimer |
| 28 pool profiles | ~55 each | Composition + sector + risk per slot |

Total spec corpus: 2190 lines (`aumm-specs.md`) + 1542 lines (`aumm-pools.md`) = 3732 lines.

