# Stage G Pre-Check — Auto-Gauge & Efficiency Tournament (Locked for G1.1)

**Status:** Accepted in `aumm-deploy` as of 2026-05-05 — execution truth for Stage G planning until superseded by explicit amend.  
**Canonical spec:** Structural tokenomics remain in `aummfi-bit/aumm-site`; this file records **repo-side** decisions and deltas. Spec prose updates (constitution, tokenomics, glossary) are tracked as follow-up in `aumm-site`, not duplicated here.  
**Related:** [STAGES_OVERVIEW.md](STAGES_OVERVIEW.md) Stage G/K; [FINDINGS.md](FINDINGS.md) OQ-G1–G3; [STAGE_G_NOTES.md](STAGE_G_NOTES.md) design freeze + test matrix.

---

## 1. Side-by-side delta (previous repo baseline vs locked pivot)

| Topic | Previous baseline (pre-2026-05-05) | Locked pivot |
| --- | --- | --- |
| Gauge admission | Governance **gauge proposal** → `approveGauge(pool)` after vote | **Immutable criteria gate**: permissionless activation when all checks pass + anti-spam fee; **no approval vote** |
| Vote types (Stage K) | Four: gauge approval, gauge challenge, composition challenge, fee | **Three**: gauge challenge, composition challenge, fee |
| Sandbox fast-track | Top 10% efficiency 3 epochs → automatic gauge approval (`SANDBOX_FAST_TRACK_EPOCHS` in FINDINGS) | **Deprecated** — redundant under auto-gauge; must not ship as dead code |
| Anti-spam / deposit | Framed as gauge-proposal **vote bond** (forfeit on rejection) | **Anti-spam fee** — same magnitude (100 svZCHF/sUSDS equivalent), **non-refundable** on any failed check and on success; terminology only in spec; routing per OQ-G3 |
| Efficiency tournament cutoff | Percentile bands (15/10/5 → caps) already in STAGES_OVERVIEW | **Confirmed percentage-based** denominator: eligible set = pools meeting **$10K TVL (7-day SMA)** and other eligibility rules at **epoch snapshot**; ranks from F-10 `efficiency_ratio`; top 15% semantics = **not** in bottom 85% by rank |
| Miliarium Month 11+ | Implied competition | **Design principle:** losing top-tier emissions is an **intended growth signal** (undefended yield narrative); not a protocol failure state |
| Threshold visibility | Relies on indexers polling state | **Structured events** on top-tier boundary cross (see STAGE_G_NOTES.md) |

---

## 2. Conflicts to resolve first (cross-document)

| ID | Conflict | Resolution |
| --- | --- | --- |
| C-1 | FINDINGS OQ-11 table: non-Miliarium genesis fee *"Set by gauge-proposal vote"* | **Replace** with fee at **first successful gauge activation** or first **fee proposal** after activation — no approval vote |
| C-2 | FINDINGS OQ-10 table lists **four** proposal types including gauge approval | **Updated** to three types; gauge activation removed from governance surface |
| C-3 | FINDINGS F3 **Sandbox fast-track** row cites bootstrap immutability | **Superseded** in repo: fast-track **deprecated**; `aumm-site` §xxi table must be amended to remove or mark deprecated (spec-side task) |
| C-4 | Stage M/N text: *gauge approvals* via governance | **Founding Miliarium pools** — gauge-active status **seeded at deploy** (no vote); wording updated in STAGES_OVERVIEW |
| C-5 | Stage P: *four proposal types* / *gauge approval workflow* | **Three types**; substitute **permissionless gauge activation** test path for non-Miliarium pools |
| C-6 | User pre-check draft cited **F-11** for efficiency | **Wrong formula id** — canonical efficiency tournament is **`11_formulas.md` F-10**; F-11 is der Bodensee composition |

---

## 3. Dependency map (accepted)

```
P-1 auto-gauge
  ├── P-5 Sandbox fast-track deprecation (no dead code in Stage G)
  └── P-6 fee reclassification (docs + FINDINGS; aumm-site glossary follow-up)

P-2 percentage cutoff confirmation
  └── P-3 Miliarium emission-loss framing (comms / design principle)
        └── P-4 on-chain threshold events (ABI in STAGE_G_NOTES.md)

OQ-G1, OQ-G2, OQ-G3 — RESOLVED in FINDINGS.md before G1.1 contract lock
```

---

## 4. Out of scope for this pre-check

- Solidity under `src/gauge/` until Stage G plan sub-steps authorize it.
- Any edit under `lib/balancer-v3-monorepo/`.
- Amending `foundry.toml`, `remappings.txt`, or new dependencies.

---

## 5. Proposition acceptance (record)

| Prop | Disposition |
| --- | --- |
| P-1 Replace vote with criteria gate | **Accept** |
| P-2 Percentage-based cutoff | **Accept** (consistent with F-10 rank > 85th percentile = bottom 15%) |
| P-3 Growth-signal framing | **Accept** (documentation / comms principle) |
| P-4 Threshold events | **Accept** (schema in STAGE_G_NOTES.md) |
| P-5 Deprecate Sandbox fast-track | **Accept** |
| P-6 Anti-spam fee reclassification | **Accept** (FINDINGS + overview; aumm-site wording follow-up) |
