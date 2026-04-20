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

Context: the hook's `onAfterSwap` path calls `Vault.collectAggregateFees` (or equivalent) to route 50% of swap fees to der Bodensee. That collection path can itself trigger swap semantics against Bodensee, which would re-enter a gauged pool's hook and recurse.

Options under consideration:
- transient-storage reentrancy flag (EIP-1153, available under `cancun`)
- per-block guard keyed on `block.number`
- structural — route to a pull-based claim buffer, no inline Bodensee swap

Decision to be recorded at D1 design session.

### D11 — Rate Provider resolution for svZCHF and sUSDS

Resolves **D-D5** (left `D-D-open` at planning time).

Both tokens are yield-bearing vault shares whose on-chain exchange rate is authoritative. Bodensee is a weighted pool with Rate Providers per non-AuMM token. Need: canonical addresses of the Rate Provider contracts (or confirmation that the token itself exposes a Balancer-compatible `getRate()`).

Token addresses (per `/Users/janus/code/aumm-site/07a_tokens.md`):
- svZCHF — `0xE5F130253fF137f9917C0107659A4c5262abf6b0`
- sUSDS  — `0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD`

Decision to be recorded at D1 design session.

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

- Pool type: WeightedPool (Balancer V3 standard)
- Tokens / weights: AuMM 40% / sUSDS 30% / svZCHF 30%
- Genesis swap fee: `0.0075e18` (0.75%)
- Fee band: `[0.001e18, 0.01e18]` (0.10% – 1.00%), governance-adjustable per **OQ-11**
- Hook: **none** (Bodensee is the routing target, not a routed-from pool)
- Yield-fee collection on Bodensee: **disabled** per **D-D9** / OQ-2 — `collectAggregateFees(DER_BODENSEE_POOL)` reverts `BodenseeYieldCollectionDisabled()`
- Rate Providers: pending **D11**

---

## Findings log (append as Stage D progresses)

### D13 — Markdown-rendered blank-line collapse in Cursor prompts
Surfaced at **D0.5.2**. An OLD block containing an interior blank line (inside the `registerPool` body, between `_poolCreators[pool] = poolCreator;` and `// Set local storage…`) was byte-mismatched against disk after the blank collapsed during chat-to-clipboard paste. Cursor's atomic match rule returned STOP on that replacement; per **D14** the other four (matching) replacements in the same prompt also did not land. The terminal integrity check (§8e) caught the divergence — the post-paste `grep` for the expected new identifiers came back empty.
Fix forward: fenced code blocks in chat (not indented plain text) for OLD content preserve whitespace through paste; prefer surgical sub-blocks with no interior blanks where possible; explicit warning to the user when an OLD necessarily contains blanks so the rendered paste can be verified. Reinforces **§6** grep-and-confirm and **§8e** terminal-side read-back as the authoritative truth.

### D14 — Apply-all-or-nothing rule in Cursor multi-replacement prompts
Surfaced at **D0.5.2**. Cursor's match-then-apply is atomic across all OLD blocks in a single prompt: one mismatch → zero replacements applied, even for OLDs that matched. Recovery requires a fresh prompt for the mismatched OLD first, then a re-issue of the remaining (still-matching) OLDs in a follow-up prompt. Both rounds visible in the Stage D commit history (the R5 scalpel as 5A/5B/5C, then R1–R4 re-issued).
Implication for future Cursor prompts: prefer smaller independent rounds when the replacements are not truly co-landing. For truly coupled edits (cross-file rename, coordinated interface change), keep them batched; otherwise split. The smallest-safe-unit bounds the blast radius of a single OLD mismatch. This document's own Stage D wrap-up was composed under the new discipline — one OLD per Cursor round.
