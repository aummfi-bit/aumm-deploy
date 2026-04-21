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

### D17 — β1 custody transfer for swap-leg fee routing

Emerged at **D3.3** design time; amends the **D3**/**D4** scope split. No prior `D-D*` was open for this specific question — `docs/STAGE_D_PLAN.md` L371-378 specified the two phases inside `_swapFeeAndDeposit` but left the custody transfer from Vault to hook implicit. Logged here for auditor discoverability; a one-line pointer is tracked for the decisions table of `docs/STAGE_D_PLAN.md` at the next PLAN amendment round (see "Deferred corrections" below).

Context: OQ-1's three-layer fee architecture prescribes that the hook's `onAfterSwap` receives swap-leg protocol fees, swaps them to svZCHF (per **OQ-2**), and adds them one-sided into der-Bodensee — all within the triggering swap's unlock scope. For that routing to fire, the hook needs tokens on its own balance at the moment `_swapFeeAndDeposit` executes. Balancer V3 does not expose a hook-callable drain: `Vault.collectAggregateFees` is `onlyProtocolFeeController` (`VaultAdmin.sol` L55–60 / L271–278). The hook cannot pull accrued aggregate fees from the Vault directly; mediation through `AureumProtocolFeeController` is structurally required.

Options considered:

- **β1 — dedicated hook-only forward.** `AureumProtocolFeeController` exposes a new external function (working name `collectSwapAggregateFeesForHook(address pool)`, `onlyFeeRoutingHook`-gated) that wraps `_vault.collectAggregateFees(pool)` and splits at the receive stage: swap leg → `sendTo(FEE_ROUTING_HOOK)` + new Aureum event `SwapLegFeeForwarded(pool, token, amount)`, no `_protocolFeeAmounts` credit; yield leg → unchanged `_receiveAggregateFees(pool, YIELD, yieldFeeAmounts)`. Two explicit paths: keeper-triggered `collectAggregateFees` (unchanged, credits both slots to ledger) and hook-triggered forward (swap → through-flow, yield → ledger).
- **β2 — unified callback.** One drain path. `collectAggregateFees` always invokes the hook post-drain regardless of who triggered it. Collapses keeper and hook semantics; requires re-entry pattern and an accounting reconciliation to avoid crediting `_protocolFeeAmounts` for forwarded amounts.
- **β3 — orchestrator with typed enum.** Single `routeFee(FeeKind kind, address pool, IERC20 token, uint256 amount)` hook method replacing `routeYieldFee`; FeeController branches internally on `kind`. Minimum surface on the hook at the cost of parameterized dispatch and enum-driven branching.

**Decision (2026-04-20 at D3.3 design time): β1.** Rationale resolves along one axis — whether permissionless `collectAggregateFees` must behave identically when called from the hook vs. from a keeper. It should not. The two paths serve structurally different obligations: keeper drains into the governance-gated ledger (yield fees plus residual swap accruals on idle pools); hook drains as through-flow into Bodensee reinvestment. Forcing symmetry (β2 / β3) would either stage the reinvestment loop behind `withdrawProtocolFees` (governance-gated) or credit `_protocolFeeAmounts` and re-debit it — both distortions of the intended accounting. β1's explicit asymmetry is the honest model: two gated entry points, disjoint event streams, disjoint ledger effects.

**Accounting invariants (β1):**

1. Forwarded swap amounts **never** credit `_protocolFeeAmounts`. The hook is a through-flow sink; funds are fully expended into Bodensee within the triggering transaction.
2. Yield leg always credits `_protocolFeeAmounts` via unchanged `_receiveAggregateFees(pool, YIELD, ...)`, regardless of which path drained it.
3. Once the hook is live on a pool, the keeper's `collectAggregateFees(pool)` is partially vestigial — per-swap hook-triggered forwards drain both slots, leaving zero accruals for the keeper most of the time. The keeper path remains the yield-only fallback for **idle pools** (no swaps between yield-fee events).
4. Event streams disjoint by design. `SwapFeeRouted` (hook-side, emitted from `onAfterSwap` after `_swapFeeAndDeposit` completes) and `SwapLegFeeForwarded` (controller-side, emitted inside the forward) are the Aureum events. `ProtocolYieldFeeCollected` (upstream) continues to fire via unchanged yield-leg handling. `ProtocolSwapFeeCollected` is **not** emitted on the forward path — one explicit Aureum event per forwarded swap leg, no upstream-event duplication.
5. Recovery-mode semantics: if `totalSwapFees[i] == 0` at drain time (pool in recovery when the fees accrued), the forward is a zero-amount `sendTo`, `_swapFeeAndDeposit` short-circuits, `SwapFeeRouted` is not emitted. The yield leg proceeds unaffected.

**Gas footprint acknowledgement:** β1 places the yield-slot iteration on the per-swap critical path (the forward always invokes `_vault.collectAggregateFees(pool)`, which enumerates both slots). For N-token pools with high swap frequency this is a real per-swap cost component — not prohibitive (Vault's loop no-ops on zero accruals), but documented here and flagged for D5 test coverage: gas-cost fork tests on representative Miliarium pools to quantify the envelope relative to OQ-1's 200k-per-swap budget.

**D3 vs D4 scope split under β1:**

- **D3** (this session): hook-side only. Declare a thin `IAureumProtocolFeeControllerHookExtension` interface (in `src/fee_router/`) covering the one new function `collectSwapAggregateFeesForHook(address pool)`. The hook imports the interface, calls it from `onAfterSwap` after the **D10** trusted-router guard, implements `_swapFeeAndDeposit`, emits `SwapFeeRouted`. `forge build` passes at D3.5 without a concrete controller resolution.
- **D4**: controller-side. `AureumProtocolFeeController` implements the interface, adds a `FEE_ROUTING_HOOK` immutable (distinct from the `derBodenseePool` immutable used by the **D-D7** / **D-D9** yield-fee guard — both must coexist; re-verify no conflation at D4 entry), adds a new `collectAggregateFeesHookSwapForward` Vault callback mirroring the existing `collectAggregateFeesHook` pattern at `ProtocolFeeController.sol` L221-223, adds `_receiveAggregateFeesSwapForward` with the β1 split behavior, emits `SwapLegFeeForwarded`.

Deploy circularity (hook's constructor needs `feeController_`; controller's constructor needs `feeRoutingHook_`) is resolved at **D9** via CREATE2 / nonce prediction — same pattern as `script/DeployAureumVault.s.sol`. One-shot setters on either side are **explicitly rejected** for this: adding permanent mutability surface to solve a one-time deploy ordering concern is the wrong trade.

**Scope reduction for Stage D — fast-path only.** The hook's `_swapFeeAndDeposit` supports two `tokenIn` cases:

- `tokenIn == SV_ZCHF` — skip phase 1 entirely, proceed to one-sided Bodensee add.
- `tokenIn` is a token in some registered pool that also contains svZCHF — phase 1 is a one-hop swap through that pool, triggering the **D10** trusted-router guard on the re-entrant `onAfterSwap`.

For any other `tokenIn`, the hook reverts with `UnsupportedFeeToken(IERC20 tokenIn)`. Multi-hop routing for exotic fee tokens (route table, failure semantics, keeper fallback) is **deferred to Stage K** alongside on-chain governance, since the route surface is itself a governance concern. D4 pool registration may optionally pre-check `tokenIn` coverage and refuse unsupported pools; otherwise the runtime revert is the enforcement point.

**Deferred corrections (tracked as D17-a, landing at D3-wrap amendment round):**

- `docs/STAGE_D_PLAN.md` L369 ("fee in the output token") is incorrect vs. `Vault.sol` L443. Balancer V3 charges aggregate swap fees on `tokenIn`, not `tokenOut`. Fix-forward to "fee in the input token (`tokenIn`)."
- `docs/FINDINGS.md` L374 ("atomic") is true for fast path only. Soften to "fast-path atomic; multi-hop routing deferred to Stage K per D17."
- `docs/STAGE_D_PLAN.md` decisions table — add `D-D16` one-line pointer: "β1 custody transfer for swap-leg fee routing; resolved at D3.3 design time; see STAGE_D_NOTES D17."

### D18 — Worktree divergence: authoritative reads are on-branch, not in worktree

Surfaced at **D3.3.1 → D3.3.2 transition** (2026-04-20). Prompt A (docs fix to strip stale chat-Claude references from CLAUDE.md) contained four find/replace edits. Cursor applied Edit 1 (single-line opening blockquote) and correctly declined Edits 2, 3, 4 under the **D14** atomic apply-all-or-nothing rule because those OLD blocks did not exist in the file on disk. Investigation: the Claude Code worktree at `.claude/worktrees/compassionate-khorana-cce609/CLAUDE.md` was 394 lines; `stage-d` tip (post-`b15b8d0`) CLAUDE.md was 442 lines. The §8e restructure into `### Roles` / `### Sub-step prompt authoring` / `### Audit cycle` subsections had landed on `stage-d` after the worktree's branch point — Edits 2, 3, 4 targeted prose from the pre-restructure shape that no longer existed.

**Root cause:** Claude Code operates in an isolation-mode worktree (`isolation: "worktree"`) on a dedicated branch (`claude/compassionate-khorana-cce609`). The worktree does not auto-track the stage-d branch tip, and its checkout at branch-creation time is an indirectly-dated snapshot. Every file Claude Code reads from the worktree path is the state at that snapshot — not the state Cursor sees when it edits the same path in the main repo checkout at `/Users/janus/code/aumm-deploy/`.

**Fix-forward:** for audit purposes during chat-directed sub-step execution on an active branch (stage-d in this case), Claude Code reads via `git show <branch>:<path>` — e.g. `git show stage-d:CLAUDE.md`, `git show stage-d:docs/STAGE_D_PLAN.md`. This resolves to the branch's current tip (shared git object DB across worktrees), not the worktree's possibly-stale copy. The worktree copy remains useful for scratch operations that don't need to reflect stage-d state, but it is not authoritative for state Cursor is actively editing.

**Implication for §8e.1 drafting:** the `Must match` bullets in a Cursor prompt are predicates on the file-as-Cursor-will-see-it. Claude Code must draft them against the on-branch state, not the worktree state. When the two diverge, Cursor correctly rejects the prompt under **D14**, and the recovery is a re-draft against authoritative state — not a "Cursor is wrong" posture.

**Discipline fold-in:** before drafting any sub-step prompt that edits an existing file, Claude Code runs `git show stage-d:<path>` (or equivalent for the active branch) to ground the OLD-block text in authoritative disk state. This is a one-line cost per sub-step, well within the grep-and-confirm envelope of **§6**.

### D20 — D3.3.4 plan-prose drift: Router → direct Vault for phase-2 add

**Finding.** `STAGE_D_PLAN.md:L375–L376` (D3.3 phase-2 bullet) specifies the one-sided add via `IRouter.addLiquiditySingleTokenExactIn(pool, SV_ZCHF, amount, 0)`. During D3.3.4 lookup, two structural concerns surfaced against Router use from inside `onAfterSwap`: (a) no upstream Balancer pool-hook performs a nested Router call from a hook callback (same gap that forced the phase-1 resolution in D3.3.3); (b) Router adds a constructor immutable and Permit2/WETH-handling surface the hook does not need.

**Precedent.** `lib/balancer-v3-monorepo/pkg/pool-hooks/contracts/ExitFeeHookExample.sol:160` calls `_vault.addLiquidity(AddLiquidityParams{...})` directly from inside `onAfterRemoveLiquidity` — an upstream Balancer example of nested Vault `addLiquidity` from within an already-open `unlock()` session, with the hook custodying deltas. (The hook callback differs from our `onAfterSwap` context, but the structural property — nested Vault call from a hook already inside an open unlock, hook as delta-owner — is identical.)

**Resolution.** Phase-2 uses `IVault.addLiquidity` with `AddLiquidityParams(pool: DER_BODENSEE, to: address(this), maxAmountsIn: length equal to the Bodensee pool's token count with svZchfAmount at svZchfIndex and 0 at all other indices, minBptAmountOut: 0, kind: AddLiquidityKind.UNBALANCED, userData: "")`. `minBptAmountOut = 0` is preserved from the original plan: this is protocol-internal routing, slippage tolerance on the fee leg is a protocol-design trade-off not a user-funds safety concern, and the rationale is captured inline as a load-bearing `@dev` block on the phase-2 helper. Hook settles the SV_ZCHF debit via the existing `_settleFeeTokenDebit` / `_sendTo` helpers — same "hook owns deltas, Vault pulls from hook credit" pattern as D3.3.3's `_swapExactInFeeTokenToSvZchfViaVault`. No new constructor immutable; one mental model for reviewers across both phase-1 and phase-2.

**Plan edit.** `STAGE_D_PLAN.md:L375–L376` (D3.3 phase-2 bullet) updated in a separate edit: Router → direct Vault call with `AddLiquidityParams(..., kind: UNBALANCED, minBptAmountOut: 0, ...)`. The `minBptAmountOut = 0` / protocol-internal-routing / `@dev`-block argument is preserved verbatim — D20 narrows the mechanism (Vault instead of Router), not the slippage-floor rationale.

### D21 — D3.3.4 phase-2 helper folded into D3.4a commit (WT-vs-HEAD drift at prompt-drafting time)

**Context.** Session resumed with a prompt stating "D3.3.4 landed and validated, 4 commits ahead of origin/stage-d." HEAD at `bc920a0` carried D3.3.1 and D3.3.3 only; D3.3.4 (`_addLiquidityOneSidedToBodenseeViaVault` phase-2 helper, per D20) was present in the working tree but uncommitted. No `D3.3.4: …` commit exists on the branch.

**Mechanism.** Claude Code's D3.4a §8e.1 prompt drafted its `Must match` bullets against the working-tree state (helper present) rather than the HEAD state (helper absent). Cursor correctly synthesized against WT — the prompt and the tree agreed — so D3.4a's atomic apply-all-or-nothing save produced a diff that bundles both the D3.3.4 helper introduction *and* the D3.4a recipient-threading refactor into a single change.

**Disposition.** Shipped as one commit with the D3.4a message, per §8 Option (C). The commit is honestly narrow in *intent* (D3.4a's goal — thread BPT recipient), but its *diff* also contains D20's phase-2 landing. This entry is the load-bearing record; the PLAN D3.3.4 block carries a one-line pointer to it.

**Lesson.** §8e.1 prompts MUST be drafted against HEAD, not WT. Before drafting any `Must match` that references an existing helper or signature, run `git show <branch>:<path>` — not `cat <path>` on the worktree copy — to read the authoritative state. This mirrors the D18 worktree-divergence discipline but at prompt-drafting scope rather than session-orientation scope. Adding to the standing session checklist.

### D22 — `IVault.unlock` inner callback must return `uint256`, not `bytes memory`

Surfaced at **D3.4b** (2026-04-20). The stack pattern is: an external entry point pulls custody / prepares state, then calls `_vault.unlock(abi.encodeCall(this._fooUnlocked, (...)))`, captures the return bytes, and decodes `abi.decode(unlockReturn, (uint256))` (e.g. BPT minted on a fee-routing deposit).

If `_fooUnlocked` is mistakenly declared `returns (bytes memory)` and `return abi.encode(bptMinted);`, the returndata layout is ABI dynamic-bytes encoding (offset, length, payload). The first word of returndata is the offset to the payload (typically `0x20`), not the scalar amount. `abi.decode(result, (uint256))` then yields `32` (or another garbage value), not `bptMinted` — wrong result or hard-to-debug mis-settlement.

**Rule:** follow Balancer Router-style hooks (e.g. `swapSingleTokenHook`): inner callbacks invoked via `unlock` that feed a scalar decode must be `external onlyVault returns (uint256)` with a direct scalar return or named return assignment — **not** `returns (bytes memory)` wrapping `abi.encode(...)`.

**Cross-reference:** §8e.1 `Must match` drafting still uses **D18** / **D21** discipline so the signatures Claude Code asks Cursor to implement match HEAD-shaped branch state.
