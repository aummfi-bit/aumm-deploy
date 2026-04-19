# Stage D — Notes (implementation findings log)

> Scaffold. Findings land as Stage D sub-steps execute. Numbered from **D10** to avoid collision with planning-stage design codes (`D-D1` … `D-D14` in `docs/STAGE_D_PLAN.md`).

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

_(D10 onward land here with full write-up once resolved.)_
