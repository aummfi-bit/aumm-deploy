# Stage G — Notes & Design Freeze (Auto-Gauge Pivot)

**Status:** Scaffold + **design freeze for G1.1 planning** — 2026-05-05.  
**Precheck:** [STAGE_G_PRECHECK_AUTO_GAUGE.md](STAGE_G_PRECHECK_AUTO_GAUGE.md).

---

## G-D1 — Auto-gauge vs governance-only paths

- **Permissionless activation:** Any caller may invoke **`activateGauge(pool)`** (exact name at implementation time) when `GaugeEligibility` reports all immutable criteria satisfied and **anti-spam fee** (100 svZCHF/sUSDS equivalent per [FINDINGS](FINDINGS.md) OQ-G3) has been credited via the shared swap-and-deposit path to der Bodensee. No governance signature.
- **Governance composition path:** After a **composition challenge** executes, **`onlyGovernanceContract`** exposes a restricted entry (e.g. `registerGaugeFromComposition(pool)`) that marks the replacement pool gauged **and applies the 90-day boost** atomically — this is **not** a fourth vote type; it is execution of an already-approved composition proposal.
- **Gauge challenge:** Unchanged narrative — governance may revoke non-Miliarium gauges per existing F-12 / constitution rules.

---

## G-D2 — Deprecated: Sandbox fast-track

- **Must not appear** as callable logic on `GaugeRegistry` / `GaugeEligibility`.
- Bootstrap §xxi *fast-track* row is **obsolete** relative to repo truth until `aumm-site` is amended.

---

## G-D3 — Efficiency tournament semantics (tie to FINDINGS OQ-G1)

- **(i) Ranking direction.** Sort **descending** by `efficiency_ratio` — **rank 1** is the pool with the **highest** `efficiency_ratio`. Eligibility scope and numerator/denominator for `efficiency_ratio` follow **`11_formulas.md` F-10**, evaluated against **eligible pools only** at the **epoch snapshot** (**FINDINGS OQ-G2**).
- **(ii) Cohorts.** The **favored cohort** is ranks **`1 ≤ rank ≤ ceil(0.15 × N)`** (top **15%** by ranking). The **remainder** is the bottom **85%** (ranks **`ceil(0.15 × N) + 1` … N**).
- **(iii) Option A — top efficiency rewarded.** Emission/CCB precedence favors the **top cohort**; pools in the **bottom cohort** receive **residual CCB flow only**. **Bottom cohorts are constrained relative to top; never vice versa.**
- **(iv) Caps clause.** Numeric caps referenced in **`11_formulas.md` F-10** (15/10/5 → 1%/0.5%/0.1%) are **anti-concentration controls WITHIN** the favored cohort — they cap top performers, not substitutes for cohort assignment. **Caps are never a mechanism to privilege low-efficiency pools.** Whether to retain, drop, or replace caps is **deferred** to Stage G **`G1.x`** sub-steps — only cohort direction is locked here.
- **Spam-defense corollary.** Pools with effectively **zero tournament revenue** place at the bottom of the `efficiency_ratio` ladder by construction and therefore receive **only** bottom-cohort residual flow alongside other bottom-cohort pools.

---

## G-D4 — Growth-signal doctrine (FINDINGS framing)

- A Miliarium pool losing top-tier tournament standing after Month 11+ is **expected competitive dynamics**, not a bug.
- External capital may restore eligibility and emissions; **`GaugeEfficiencyDropped`** (events below) feeds bot/aggregator surfaces.

---

## G-D5 — Threshold transition events (design-freeze ABI)

Emit **exactly once** per pool per boundary crossing per epoch resolution (single authority — avoid duplicate emits from registry + checker).

```solidity
/// @notice Emitted when a pool crosses from top-tier-eligible to below the top-tier cutoff
/// @param pool             Pool address
/// @param epoch            Epoch index at which eligibility was finalized
/// @param tvlSma             Pool TVL as 7-day SMA, **svZCHF-denominated 18-decimal fixed point** (align `ITVLOracle` / OQ-22)
/// @param efficiencyRatio   `efficiency_ratio` from **`11_formulas.md` F-10**, **scaled 1e18** after OQ-G1 smoothing
event GaugeEfficiencyDropped(
    address indexed pool,
    uint256 indexed epoch,
    uint256 tvlSma,
    uint256 efficiencyRatio
);

/// @notice Emitted when a pool crosses from below into the top-tier cutoff
event GaugeEfficiencyRising(
    address indexed pool,
    uint256 indexed epoch,
    uint256 tvlSma,
    uint256 efficiencyRatio
);
```

**Note:** Snapshot uses **epoch** indexing consistent with `BLOCKS_PER_EPOCH`. **`tvlSma`** matches **svZCHF numéraire (OQ-22)**; **`efficiencyRatio`** matches **OQ-G1** — Natspec on the Solidity file must repeat these units at contract lock.

---

## G-D6 — Pool-type whitelist (P-4 / P-5 “Aequilibrium-only”)

- At activation, pool **factory-derived type** must be in **allowed set** — exact enum (e.g. Weighted vs Stable vs custom Balancer factories) locks at G1.x when staged against deployed factories. **Fails closed** until allowlist verified.

---

## G-D7 — Three activation paths and per-path boost policy (RT-01 + RT-04)

Three distinct entry points produce a registered gauge; **boost policy differs per path** and must be unambiguous at contract-lock time. Boost asymmetry is enforced structurally — the boost-application code path is **unreachable** from `activateGauge`.

- **(i) Permissionless — `activateGauge(pool)`.** Per **G-D1**, callable by any address once `GaugeEligibility` reports all immutable criteria satisfied and the **OQ-G3** anti-spam fee has been credited via swap-and-deposit to der Bodensee. **No boost.** The pool enters tournament accounting at base `M_i = 1.0` per **F-8** and competes for emission share through the **F-10** efficiency tournament from the next epoch boundary onward.
- **(ii) Composition — `registerGaugeFromComposition(pool)`.** Per **G-D1**, restricted to `onlyGovernanceContract`, invoked as the execution leg of an approved composition challenge. **Applies the 90-day boost atomically** with gauge registration: per `aumm-site` `08_bootstrap.md` §xxi, `M_i` is held at 1.0 across the boost window with effective `CCB_mult = 1.2`; at day 91 the boost expires and `M_i` resumes per-epoch F-8 evolution.
- **(iii) Founding-pool seeding — `seedFoundingPool(pool, seedAmount)`.** Restricted to `onlyGovernanceContract` (Authorizer Safe through Stage K, on-chain governance thereafter per CLAUDE.md §1). Necessary because founding pools are deployed at zero TVL and would fail the **OQ-G2** `$10K` 7-day-SMA floor at any first eligibility check; the permissionless `activateGauge` path is therefore structurally unreachable for founding pools at deploy time. **Applies the 90-day boost** per the founding-pool privilege established in `aumm-site` `08_bootstrap`. This entry point is the contract-spec realisation of test invariant **T-R1** — "governance-free via deploy shim" in T-R1 is shorthand for "no public-vote / proposal cycle"; the seeding call itself is governance-restricted (Authorizer Safe), **not** access-free.

| Path | Caller | Eligibility-gate path | Anti-spam fee | Boost applied |
| --- | --- | --- | --- | --- |
| `activateGauge(pool)` | any address | full `GaugeEligibility` (all immutable criteria) | yes — OQ-G3 (100 svZCHF/sUSDS) | **no** |
| `registerGaugeFromComposition(pool)` | governance contract | composition-criteria subset (full enumeration at RT-03 sub-step) | no | **yes — 90-day** |
| `seedFoundingPool(pool, seedAmount)` | governance contract | bypassed (zero-TVL deploy shim) | no | **yes — 90-day** |

**Boost asymmetry rationale.** The 90-day boost is a competitive cold-start accommodation, not an entitlement of any gauge entry. Permissionless activation by construction occurs only after a pool has cleared all eligibility gates including the **OQ-G2** TVL floor — by that point the pool already holds external capital and does not require a launch window. Composition and founding-seeding both produce gauges for pools that have **not** demonstrated independent market traction (composition replaces an underperformer governance has decided to retire; seeding starts a founding pool from zero), so the 90-day window provides the cold-start interval during which the **F-10** tournament cannot meaningfully rank them.

**`seedFoundingPool` shape — Stage G reservation only.** The `seedAmount` parameter is denominated to match the pool's initial-deposit shape (token-weighted basket per founding-pool profile in `miliarium_profiles/`). The exact tuple — single-token seed vs. full basket vs. reference to an external initial-liquidity contract — locks at **G1.x** when staged against the founding-pool deploy scripts. Stage G's design freeze reserves only the **entry-point name** and the **access-control gate**; the parameter shape is a downstream sub-step decision.

---

## Test matrix — must pass before Stage G closure

### Invariants (unit / fuzz)

| ID | Invariant |
| --- | --- |
| T-I1 | No pool becomes gauged without **all** criteria `true` in one transaction boundary |
| T-I2 | Anti-spam fee **never** refunds; failed partial checks still consume fee (per product spec) |
| T-I3 | **Forbidden tokens** — AuMM, AuMT cannot appear as weighted pool tokens for activation |
| T-I4 | **Fast-track selector** absent — bytecode / interface has no Sandbox fast-track entry |
| T-I5 | **Epoch snapshot** determinism — two calls at same block see same eligibility set |

### Transition tests

| ID | Scenario |
| --- | --- |
| T-T1 | Pool crosses **into** top tier → emits `GaugeEfficiencyRising` once |
| T-T2 | Pool crosses **out** → emits `GaugeEfficiencyDropped` once |
| T-T3 | Tie-break for rank (if spec requires address ordering) stable across sorting |
| T-T4 | Composition execution → new pool gauged + boost clock starts; old pool revoked per O |

### Regression

| ID | Scenario |
| --- | --- |
| T-R1 | Founding pools can be seeded **governance-free** via deploy shim (Stage M/N alignment) |

---

## Findings queue (reserved)

(Numbered Stage G findings `G10+` appended here as implementation proceeds — analogous to Stage F NOTES.)
