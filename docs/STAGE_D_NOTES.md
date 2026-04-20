# Stage D — Notes (implementation findings log)

> Scaffold. Findings land as Stage D sub-steps execute. Numbered from **D10** to avoid collision with planning-stage design codes (`D-D1` … `D-D15` in `docs/STAGE_D_PLAN.md`).

---

## Cross-reference key

- `D-Dn` — planning-stage design decision n, see `docs/STAGE_D_PLAN.md` decisions table.
- `Dn` (two-digit, starting at D10) — implementation-stage finding recorded here.
- `OQ-N` — open question N in `docs/FINDINGS.md`.
- `Cn`, `B-Dn` — prior-stage references (Stage C notes, Stage B plan).

---

## Pending findings (stubs)

### D10 — Recursion guard for `onAfterSwap` fee-collection callback

Resolves **D-D4** (left `D-D-open` at planning time).

Context: the OQ-1 hook fires on `onAfterSwap` for every swap on a gauged Miliarium pool. Inside the hook, after the Vault has credited its `protocolSwapFeePercentage = 50e16` protocol-fee share, the hook issues its own internal `Vault.swap` to convert the accrued fee token to svZCHF (per OQ-2), then a one-sided `addLiquidity` into der Bodensee. If that internal swap routes through another gauged pool — the same hook is attached to all 28 Miliarium pools plus any gauged non-Miliarium pool — `onAfterSwap` fires again, recursing.

Options considered (per OQ-1):
- **(a) Trusted-router check.** Early-return when `params.router == address(this)`. Upstream-idiomatic; 1-line check; ~200 gas per swap; recursion terminates at depth 1.
- **(b) Direct-route-through-Bodensee.** Constrain fee routing to swap only through Bodensee (hookless, so no recursion). Fails in the general case — Miliarium pools whose fee token sits outside {AuMM, sUSDS, svZCHF} need a fee-token → svZCHF hop through some other pool, and that hop can re-enter the hook.
- **(c) Geometric-series acceptance.** Let recursion happen, accept the gas blow-up (~200k extra per level). Ruled out for user-facing swaps on Miliarium.

**Decision (2026-04-20 at D1.3): option (a) — trusted-router check on `params.router == address(this)`.** At the top of `AureumFeeRoutingHook.onAfterSwap`, the guard is `if (params.router == address(this)) return (true, params.amountCalculatedRaw);`. When the hook issues its own internal `Vault.swap`, the Vault sets `params.router = msg.sender = address(this)` in the re-entrant `onAfterSwap` fire; the guard short-circuits before any settlement logic re-runs. External callers cannot spoof the router (the Vault assigns it from `msg.sender`), so the guard is safe.

**Upstream precedent:** same trusted-router pattern used by Balancer V3's `StableSurgeHook` and other in-house hooks that initiate their own Vault operations. No new mechanism; no transient-storage guard needed.

**Gas envelope:** one immutable-compare on every swap; negligible relative to the 200k+ envelope OQ-1 already flagged for the non-recursive fee-routing path. `enableHookAdjustedAmounts = false` on this hook (per D1.2), so the second return value (`hookAdjustedAmountCalculatedRaw`) is ignored by the Vault — passing `params.amountCalculatedRaw` unchanged is the upstream-idiomatic no-op per `BaseHooks`.

### D11 — Rate Provider resolution for svZCHF and sUSDS

Resolves **D-D5** (left `D-D-open` at planning time).

Context: der Bodensee is a Balancer V3 WeightedPool registered with a Rate Provider per non-AuMM token. Rate Providers must implement `IRateProvider.getRate() external view returns (uint256)` — 18-decimal fixed-point, legacy interface (no rounding direction, no error return; see `lib/balancer-v3-monorepo/pkg/interfaces/contracts/solidity-utils/helpers/IRateProvider.sol`). Both non-AuMM Bodensee tokens are ERC-4626 vault shares whose on-chain exchange rate is authoritative — but ERC-4626's `convertToAssets` is not the same entry point as `IRateProvider.getRate()`, so a separate Rate Provider contract is needed unless the vault happens to also expose `getRate()`.

Probe methodology (at D1.4): `cast call <addr> "getRate()(uint256)" --rpc-url $MAINNET_RPC_URL` against each candidate. Success with an 18-decimal return → self-Rate-Provider. Revert → need an external Rate Provider contract.

**Probe results (2026-04-20):**

| Token | ERC-4626 vault | vault `getRate()` | External Rate Provider | RP `getRate()` |
|---|---|---|---|---|
| svZCHF | `0xE5F130253fF137f9917C0107659A4c5262abf6b0` | reverts | `0xf32dc0ee2cc78dca2160bb4a9b614108f28b176c` | `1009995744722991034` (~1.010e18) |
| sUSDS  | `0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD` | reverts | `0x1195be91e78ab25494c855826ff595eef784d47b` | `1093862763241753131` (~1.094e18) |

Both vaults revert on `getRate()`, as expected for plain ERC-4626 implementations. The external Rate Providers return sane 18-decimal rates consistent with expected accruals (svZCHF ~1.01 ZCHF per share; sUSDS ~1.09 USDS per share reflecting Sky Savings Rate accrual since vault deployment).

**Decision (2026-04-20 at D1.4):**
- svZCHF Rate Provider: `0xf32dc0ee2cc78dca2160bb4a9b614108f28b176c`
- sUSDS Rate Provider: `0x1195be91e78ab25494c855826ff595eef784d47b`

Both are existing mainnet-deployed contracts, used by existing Balancer V3 pools. **No wrapper vendored into Aureum's `src/` tree, zero new audit surface.** The `ERC4626RateProvider.sol` contract in the Balancer submodule is test-only (`lib/balancer-v3-monorepo/pkg/vault/contracts/test/ERC4626RateProvider.sol`); had either probe reverted without an existing deployed alternative, vendoring that test contract into `src/vault/` — and owning its audit — would have been the fallback.

**Provenance:**
- svZCHF Rate Provider: sourced from `aumm-site/07a_tokens.md` row after the `fc3f587` spec fix that replaced the prior stale link (which pointed at the vault address instead of the Rate Provider).
- sUSDS Rate Provider: sourced via Etherscan from an existing Balancer V3 mainnet pool's `TokenConfig.rateProvider` for the sUSDS token slot, after local grep in the submodule returned no matches for sUSDS (expected — submodule pinned at Dec 2024, sUSDS pools post-date it). `aumm-site/07a_tokens.md` sUSDS row subsequently corrected at `528ea35` with the same fix shape as `fc3f587` for svZCHF.

**Downstream use:** both addresses are consumed by the "Der Bodensee deployment parameters" block below (Rate Providers field, currently marked `pending **D11**` — will be filled at D1.5) and by the Bodensee deployment script under `script/` at Stage D5.

### D12 — Retrofit approach for `AureumProtocolFeeController` upstream setter

Resolves the R1 vs R2 choice at **D0.5.2** (per **D-D15**).

Context: Stage B inherits Balancer V3's `ProtocolFeeController`, which exposes a public setter for `protocolSwapFeePercentage`. D-D15 pins the split as immutable; the inherited setter must be disabled on Aureum's fee-controller.

Options:
- **R1 — override-and-revert.** Override each inherited setter to revert with a custom error (`SplitIsImmutable()` or equivalent). Upstream interface preserved; smallest diff; clearest audit story.
- **R2 — non-inheritance.** Inherit from a narrower base (or compose the needed behavior) rather than inheriting the full `ProtocolFeeController`. Larger diff; changes the audit-inheritance shape.

Planning default is R1 per D-D15's "smallest diff, clearest audit story" preference. D0.5.1's grep of the Stage B source may force R2 if the inherited setter surface is structurally incompatible with simple override.

**Decision (2026-04-20 at D0.5 implementation time): R1 applied**, landed at `e5dc936`. Both setters (`setGlobalProtocolSwapFeePercentage`, `setProtocolSwapFeePercentage`) are now `external pure` stubs reverting `SplitIsImmutable()`. Scope extended beyond R1-as-stated: the constructor pins `_globalProtocolSwapFeePercentage` at `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50e16` (saturate-not-bypass framing per amended OQ-1 / OQ-1a), and `registerPool` unconditionally assigns the swap-side aggregate to the pinned global regardless of `protocolFeeExempt` — this closes a factory-level bypass where a pool registering with `protocolFeeExempt = true` would have zeroed its swap fee. D0.5.1's grep against Stage B confirmed R1 was structurally compatible (simple override, no forcing move to R2).

---

## D8 — Slither triage (placeholder)

| Detector | Location | Disposition | Rationale |
|---|---|---|---|
| _(filled at D8)_ | | | |

---

## Der Bodensee deployment parameters (for D7 fork test)

- **Pool name:** `"der-Bodensee"`
- **Pool symbol:** `"BODENSEE"`
- **Pool type:** WeightedPool (Balancer V3 standard; `lib/balancer-v3-monorepo/pkg/pool-weighted/contracts/WeightedPool.sol`)
- **Tokens / weights:** AuMM 40% / sUSDS 30% / svZCHF 30%
- **Token order at registration:** sorted ascending by address per Balancer V3 convention (concrete order fixed at Stage D5 deployment-script time against the actual deployed AuMM address)
- **Rate Providers** (per **D11**):
    - AuMM: `address(0)` (not yield-bearing; identity rate)
    - sUSDS: `0x1195be91e78ab25494c855826ff595eef784d47b`
    - svZCHF: `0xf32dc0ee2cc78dca2160bb4a9b614108f28b176c`
- **yieldFeeExempt flags:** AuMM = true; sUSDS = false; svZCHF = false. Note per **D-D9** / **OQ-2**: yield-fee collection on Bodensee is disabled at the controller level regardless — these flags are cosmetic in the Aureum setup.
- **Hook:** `address(0)` (Bodensee is the routing *target*, not a routed-from pool)
- **Genesis swap fee:** `0.0075e18` (0.75%)
- **Swap-fee band:** `[0.001e18, 0.01e18]` (0.10% – 1.00%), governance-adjustable per **OQ-11** (Bodensee-class band)
- **Swap-fee manager:** governance Safe multisig (same as Authorizer per CLAUDE.md §2)
- **`protocolSwapFeePercentage` override at registration:** `0` (cosmetic — `AureumProtocolFeeController.registerPool` pins the swap-side aggregate to `_globalProtocolSwapFeePercentage = MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50e16` regardless of this field, per the D0.5 retrofit at `e5dc936` and **D-D15** saturate-not-bypass).
- **Yield-fee collection on Bodensee:** **disabled** per **D-D9** / **OQ-2** — `collectAggregateFees(DER_BODENSEE_POOL)` reverts `BodenseeYieldCollectionDisabled()`.
- **Pause manager:** governance Safe multisig (same as Authorizer per CLAUDE.md §2).
- **Pool creator:** `address(0)` — no creator fees, ever (per **D-D15** and `aumm-specs` §xxix no-creator-fees constitutional rule).
- **Unbalanced-liquidity operations:** **enabled** (fee-routing deposits into Bodensee are one-sided `addLiquidity` in svZCHF per **OQ-2**; disabling would break the fee router).
- **Swap-enabled at registration:** true (default).

---

## Findings log (append as Stage D progresses)

### D13 — Markdown-rendered blank-line collapse in Cursor prompts
Surfaced at **D0.5.2**. An OLD block containing an interior blank line (inside the `registerPool` body, between `_poolCreators[pool] = poolCreator;` and `// Set local storage…`) was byte-mismatched against disk after the blank collapsed during chat-to-clipboard paste. Cursor's atomic match rule returned STOP on that replacement; per **D14** the other four (matching) replacements in the same prompt also did not land. The terminal integrity check (§8e) caught the divergence — the post-paste `grep` for the expected new identifiers came back empty.
Fix forward: fenced code blocks in chat (not indented plain text) for OLD content preserve whitespace through paste; prefer surgical sub-blocks with no interior blanks where possible; explicit warning to the user when an OLD necessarily contains blanks so the rendered paste can be verified. Reinforces **§6** grep-and-confirm and **§8e** terminal-side read-back as the authoritative truth.

### D14 — Apply-all-or-nothing rule in Cursor multi-replacement prompts
Surfaced at **D0.5.2**. Cursor's match-then-apply is atomic across all OLD blocks in a single prompt: one mismatch → zero replacements applied, even for OLDs that matched. Recovery requires a fresh prompt for the mismatched OLD first, then a re-issue of the remaining (still-matching) OLDs in a follow-up prompt. Both rounds visible in the Stage D commit history (the R5 scalpel as 5A/5B/5C, then R1–R4 re-issued).
Implication for future Cursor prompts: prefer smaller independent rounds when the replacements are not truly co-landing. For truly coupled edits (cross-file rename, coordinated interface change), keep them batched; otherwise split. The smallest-safe-unit bounds the blast radius of a single OLD mismatch. This document's own Stage D wrap-up was composed under the new discipline — one OLD per Cursor round.

### D15 — D13 recurrence: fenced-code-block mitigation is insufficient for blank lines
Surfaced at **D1.4** (NEW-side) and **D1.5** (OLD-side). D13's original fix-forward ("fenced code blocks in chat preserve whitespace through paste") proved insufficient in two new failure modes observed 2026-04-20. (i) **NEW block with many interior blanks.** At D1.4, a 16-line NEW block with 8 interior blank lines (D11 rewrite) landed content-correct but with all 8 blanks collapsed in transit; the fenced code block did not protect. Recovered via a single `awk` pass anchored on content patterns: `awk '/^<anchor>/ { print ""; print; next } { print }' file > file.tmp && mv file.tmp file` — repeated for each collapsed blank, or combined into one awk script with multiple patterns.
(ii) **OLD block with any interior blank.** At D1.5, a single interior blank in an OLD block (between `## Der Bodensee` heading and its first bullet) collapsed in transit, causing Cursor to correctly reject the entire replacement under the **D14** atomic rule (byte-mismatch). The D14 rule held — Cursor refused the whole prompt, no partial application — but the collision-surface lesson is that *any* interior blank in OLD is a rejection risk, not just in NEW.
**Refined fix-forward:** scope OLD and NEW to contiguous blank-free ranges. If a change necessarily spans blanks, options are: (a) split into per-paragraph sub-rounds with no interior blanks in any single OLD/NEW; (b) accept the collapsed paste and restore blanks via terminal `awk` / `sed` anchored on content patterns; (c) for append-only additions at end-of-section, use a `cat >> file << 'EOF' … EOF` heredoc — deterministic, D13-immune, shell-only, no chat-rendering in the path. This D15 entry itself is being appended via option (c).
Fenced code blocks in chat remain preferable to indented plain text for preserving *characters* (the paste is otherwise byte-perfect), but they do not protect *blank lines* through the browser → clipboard → Cursor pipeline. The authoritative truth remains the terminal integrity check per **§8e**.

### D16 — Caller-gate shape for external primitive entry points

Resolves **D-D2** (left `D-D-open` at planning time; explicitly "decided at D2 draft time" per `docs/STAGE_D_PLAN.md` L84).

Context: Aureum's fee-routing hook exposes three non-IHooks entry points beyond the on-chain hot path (`onAfterSwap`): (a) yield-fee leg called by `AureumProtocolFeeController`, (b) governance deposits called by the Stage K governance module, (c) Incendiary deposits called by the Stage L Incendiary module. Per OQ-1's three-layer fee table, each has a distinct caller gate. D-D2 left the external-function shape open between "three separate functions" and "one parameterized `routeExternalDeposit(CallerType, …)`."

Options considered:
- **(A) Three separate functions.** `routeYieldFee`, `routeGovernanceDeposit`, `routeIncendiaryDeposit`, each with a dedicated caller gate (`msg.sender == FEE_CONTROLLER` / `== governanceModule` / `== incendiaryModule`). Call-sites self-document. Three distinct events (already prescribed in D2.1 spec). Each function is a focused audit unit.
- **(B) Single parameterized function.** `routeExternalDeposit(CallerType callerType, address token, uint256 amount)` with enum-branching inside. The caller self-declares `callerType`, the hook checks that `msg.sender` matches the expected address for that `callerType`. One audit unit with internal branching.

**Decision (2026-04-20 at D2.1): option (A) — three separate functions.** Rationale: (i) **call-site clarity** — the explicit D-D2 decision criterion. `controller.collectAggregateFees` → `hook.routeYieldFee(token, amount)` reads unambiguously; option B's `hook.routeExternalDeposit(CallerType.YieldFee, token, amount)` requires readers to resolve the enum. (ii) **No redundant self-declaration** — option B has caller passing `callerType` AND hook checking `msg.sender`; these are each other's redundant check, and divergence is either a revert (safe) or a latent bug (unsafe). Option A has just the `msg.sender` check, single source of truth. (iii) **Audit surface** — three focused functions, each with one caller gate and one event, matches Balancer V3's upstream idiom for controller-style contracts better than a parameterized dispatch. (iv) **Aureum's fee layers are fixed** at three per OQ-1; no new layer foreseen, so option B's enum-extensibility is not a real benefit. (v) **Gas** — option A: direct dispatch. Option B: enum branching plus either a CallerType→address mapping sload or an if-else chain on every call.

**Downstream shape (D2.1 interface, D3.4 impl):** three external functions declared on `IAureumFeeRoutingHook`: `routeYieldFee(address token, uint256 amount)`, `routeGovernanceDeposit(address token, uint256 amount)`, `routeIncendiaryDeposit(address token, uint256 amount)`. Each emits a distinct event (`YieldFeeRouted`, `GovernanceDepositRouted`, `IncendiaryDepositRouted`). `UnauthorizedCaller(address caller)` is the shared error for caller-gate failure across all three. The hot-path `SwapFeeRouted` event is emitted from the IHooks `onAfterSwap` callback on the impl (not declared externally as an entry point on the interface).
