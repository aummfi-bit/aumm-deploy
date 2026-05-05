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

## G-D8 — Canonical 52% numerator definition (OQ-G4 propagation)

The 52% Quality Gate numerator is class-gated against the **Vault-Class Registry** (`src/gauge/VaultClassRegistry.sol`, G1) per FINDINGS **OQ-G4** (resolved 2026-05-05). The canonical definition propagates verbatim from FINDINGS:

> The 52% quality-gate numerator equals the sum of pool weights assigned to ERC-4626 tokens whose class is admitted in the Vault-Class Registry. All other token weights — including ERC-4626 tokens whose class is not admitted — count toward the ≤48% complement.
>
> Eligibility is re-evaluated at each tournament epoch boundary against the current registry state; class admissions and revocations take effect at the next boundary.

This wording is **load-bearing** across `GaugeEligibility.sol` (G2 runtime check) and `STAGES_OVERVIEW.md` Stage G builds (overview prose). Any divergence from this two-paragraph block is a Stage G blocker.

**Implication for `GaugeEligibility`.** The 52% check reads each pool's normalized weights via `IBasePool.getNormalizedWeights()`, classifies each weighted token via the ERC-4626 detection method (**G-D10**), looks up admitted classes in `VaultClassRegistry`, and sums the weights of admitted-class 4626 tokens. If sum ≥ `0.52e18` (FixedPoint), the gate passes; otherwise the pool is ineligible.

**Boundary semantics.** Pool weights are immutable in Balancer V3 weighted pools — re-evaluation is **not** about weight drift. Re-evaluation is boundary-based because **qualification state can change** via class admissions and revocations in `VaultClassRegistry`, tournament metrics (TVL 7-day SMA per **OQ-G2**, `efficiency_ratio` rank cohort per **OQ-G1**, disqualification streak counter), and governance challenge outcomes — even when pool weights themselves are immutable. Eligibility is therefore **latched per epoch** and **recomputed at boundaries only**, not on every block.

**Frankencoin analogy.** A Frankencoin borrowing position can be **challenged** mid-life by a qualified holder, forcing a re-evaluation of its collateral basis. The Aureum analogue: an ERC-4626 token class admission can be **revoked** via `revokeVaultClass` (per **G-D9**); pools holding the now-revoked class lose numerator credit at the next boundary even though their pool composition has not changed. The challenge surface — who may revoke, under whatever governance policy `revokeVaultClass` encodes — is the governance scope of `revokeVaultClass` itself; OQ-G4 locks this as `onlyGovernanceContract`. (Permissionless-challenge variants — anyone may revoke with bond, mirroring Frankencoin's open-challenge model — are a post-Stage-G design question, not in current scope.)

---

## G-D9 — Vault-Class Registry: Frankencoin-inspired veto mechanism (OQ-G4)

`VaultClassRegistry.sol` (G1) implements class admission via a Frankencoin-inspired proposal-and-veto pattern. Mechanism is **locked** at this design freeze; numerical tunables (bond, veto threshold, window) defer to **G1.x**.

**Mechanism (locked):**

- **Proposal.** Any address calls `proposeVaultClass(admissionType, admissionValue, constraintsHash)` paying a non-refundable bond in svZCHF. The bond routes one-sided to der Bodensee via the **OQ-G3** swap-and-one-sided-deposit primitive (shared with anti-spam fee + governance proposal deposit). No burn, no treasury accumulation.
- **Veto window.** Bounded block range during which qualified AuMT holders may invoke `vetoProposal(id)` if cumulative AuMT-weighted veto support meets the veto threshold.
- **Auto-finalize.** Window expires without a successful veto → proposal auto-executes in a single transaction; class enters the registry. **No** explicit two-stage `finalize`-then-`execute` — single-tx state transition on window expiry, minimizing stuck-state surface.
- **Revocation.** Governance may invoke `revokeVaultClass(id)` to denounce a previously-admitted class. **Revocable-with-grandfather** is the locked policy. Revocation blocks new numerator credit at the next epoch boundary (per **G-D8** canonical definition); existing gauges are not force-revoked but face the standard graduated grace period from `08_bootstrap.md` §xxiii if they fall below 52% as a result.

**Admission fingerprints — three types, proposer-stated:**

A `VaultClassProposal` declares `admissionType` from:

- **`ImplementationAddress`** — admits a specific implementation behind a proxy. Trust delegated to the proxy admin's upgrade discipline.
- **`FactoryAddress`** — admits all current and future vaults from the factory. Trust delegated to the factory's deployment policy.
- **`BytecodeHash`** — admits exact bytecode match. Future-proof against impl rotation, but blocks legitimate upgrades.

Each fingerprint carries a different threat model. Proposal text must declare which type was selected and why it fits the class being admitted; the veto mechanism is the protocol's check on proposers' fingerprint judgement.

**Genesis seeding (Option a — constructor-hardcoded constants):**

The Miliarium-pool ERC-4626 vault classes (the exact set per the deployed Miliarium pools at Stages M / N — waEthUSDC, ixEDEL, sUSDS-class wrappers, and the remainder per per-pool profiles in `aummfi-bit/aumm-site/miliarium_profiles/`) are admitted at deploy via constructor-hardcoded constants in `VaultClassRegistry.sol`. **No** one-shot seeding admin entrypoint, **no** Authorizer-Safe self-call on `proposeVaultClass`. The genesis class set is bytecode-immutable; future classes enter via the `proposeVaultClass` + veto flow once on-chain governance is live (Stage K). Pre-Stage-K, the registry is frozen at its constructor-seeded set; pools using only genesis-admitted classes can be gauged permissionlessly through `activateGauge`.

**Tunables — deferred to G1.x with non-regressable constraints:**

- `proposalBond ≥ antiSpamFee` (anti-spam fee is **100 svZCHF/sUSDS** per **OQ-G3**; class-admission bond is higher-stakes governance and must not undercut the simpler permissionless-activation fee).
- `vetoThreshold ≤ governanceQuorumThreshold` (vetoes must be reachable at lower thresholds than full proposal quorum, so a vigilant minority can block a captured-quorum bad proposal).
- Veto window in blocks: minimum `≥ BLOCKS_PER_EPOCH` (governance reaction window); maximum `≤ 3 × BLOCKS_PER_EPOCH` (avoids stalling legitimate admissions).

Concrete bond, threshold, and window values lock at **G1.x**.

**Forward dependencies — placeholder + one-shot setter pattern (mirrors Stage F F-D20–F-D23):**

- `IAuMT` for veto vote weight — concrete contract ships at Stage I; Stage G uses placeholder address + one-shot setter.
- `governanceContract` for `revokeVaultClass` — concrete contract ships at Stage K; same placeholder + one-shot setter pattern.

Pre-Stage-I + pre-Stage-K, the veto path is **structurally unreachable** (placeholder `IAuMT` returns zero vote weight; placeholder governance address rejects all calls). Pools relying solely on genesis-seeded classes can still be gauged permissionlessly via `activateGauge`.

---

## G-D10 — ERC-4626 detection method (try/catch `IERC4626.asset()`)

`GaugeEligibility.sol` (G2) determines whether a pool token is an ERC-4626 candidate by calling `IERC4626(token).asset()` in a try/catch block:

- **Non-reverting return** → token is treated as **4626-claiming**. `GaugeEligibility` triggers a class-admission lookup against `VaultClassRegistry` (per **G-D8**):
  - **Admitted class** → token weight counts toward the 52% numerator.
  - **Not admitted** → token weight contributes 0 to numerator; weight falls into the ≤48% complement.
- **Revert** → token is treated as **plain ERC-20**. Token weight contributes to the ≤48% complement directly.

A token implementing `asset()` for any reason (legitimate or scam) is therefore detected as 4626-claiming and gated by registry admission. **There is no escape via interface omission** — a malicious token cannot avoid the gate by simply not implementing the ERC-4626 interface, because the only effect of implementing `asset()` is to subject the token to the (more restrictive) class-admission gate.

**Detection is interface-introspection, not registry preregistration.** The detection path is stateless on the registry side — `VaultClassRegistry` only stores class admissions; per-token classification is computed on-the-fly at each eligibility evaluation. This keeps the registry's state surface minimal.

**Test invariant tie-in.** **T-I3** (forbidden tokens AuMM, AuMT) is **independent** of this detection — AuMM and AuMT are blocked by direct address comparison regardless of their `asset()` interface, since they cannot appear as weighted pool tokens for activation by construction. The G-D10 detection method runs only after the T-I3 forbidden-token check passes.

---

## G-D11 — OQ-G3 swap-and-deposit primitive — Option A helper + α-via-DONATION (G-DP10 resolution)

`src/gauge/SwapAndDepositToBodensee.sol` (G1) implements the OQ-G3 anti-spam fee + `VaultClassRegistry` proposal-bond shared rail per **G-DP10 → Option A**. Stage D `AureumFeeRoutingHook` bytecode is **untouched** — the audit-inheritance anchor at `stage-d-complete` (commit `951c338`) is preserved. The helper's add-liquidity primitive is V3's **`AddLiquidityKind.DONATION`** (`Vault.sol` L623), which mints **zero BPT** — donated tokens enter Bodensee's reserves with no holder ever realizing an LP claim. Aligned with Aureum's no-team-treasury principle (CLAUDE.md §1: "no creator fees, ever").

**Effect on the pool.** Bodensee weights (40 / 30 / 30 AuMM / sUSDS / svZCHF) are immutable per V3 weighted-pool semantics. DONATION grows the donated-token reserve at constant weight, so the pool's invariant absorbs the new reserves at the next swap — the swap curve shifts, AuMM's spot price within Bodensee moves, and existing BPT now represents proportionally more total backing. No new holder, no protocol wallet, no LP-claim accumulation.

**Mechanism (locked):**

- **Helper contract.** Holds immutable references to `IVault`, `DER_BODENSEE`, `SV_ZCHF`, `S_USDS`. Single external entry point `swapAndDeposit(IERC20 payToken, uint256 amount)` — exact signature shape locks at G1.x.
- **DONATION path.** Inside `IVault.unlock` callback: pull `payToken` from caller via `safeTransferFrom`; transfer to Vault + `settle`; then `IVault.addLiquidity` with `AddLiquidityKind.DONATION` and a `maxAmountsIn` array sized to Bodensee's token count, the `payToken` slot set to the equivalence-derived amount and other slots zero. `bptAmountOut == 0` per V3 DONATION semantics — discarded. No `bptRecipient` parameter; no `to` field consumed.

**Pre-requisite — Bodensee config amendment (sub-step G1.1, ahead of `VaultClassRegistry.sol` Solidity):**

`script/DeployDerBodensee.s.sol` line 81 flips `enableDonation` from `false` to `true`. This is a **deploy-script change**, not a contract-bytecode change — Stage D's `stage-d-complete` tag covers `AureumFeeRoutingHook` + controller bytecode; Bodensee deploy is a script artifact regenerated at fork-test setUp + Stage R mainnet deploy. Bodensee is not on mainnet (Stage R is mainnet). The flag flip lands in the `stage-g` branch with matching test-fixture updates so Stage D's UNBALANCED fee-routing path and Stage G's DONATION anti-spam path coexist on a single Bodensee instance — V3 supports both add-liquidity kinds on a pool registered with `enableDonation = true` AND `disableUnbalancedLiquidity = false` (current setting at line 82, kept).

**Pay tokens — two-numéraire (svZCHF, sUSDS):**

Both stable-class tokens are already Bodensee pool tokens (30 / 30 weights), so DONATION accepts either directly with **no swap leg required**. AuMM is ineligible as pay token (OQ-G3 enumerates the stable pair only).

**Equivalence — Rate-Provider-derived, svZCHF-anchored (G-D11.eq):**

Canonical fee is **100 svZCHF** per OQ-22's svZCHF numéraire framing. The sUSDS-equivalent amount is derived via Bodensee's existing Rate Providers (registered at pool construction per Stage D D11), reading `IRateProvider.getRate()` for the svZCHF / sUSDS pair at fee-payment block. **No new oracle dependency** — the helper reuses Bodensee's pool-internal rate infrastructure already consumed for swap math. Single block-snapshot read, no TWAP. Round direction is **user-pays-more** (round up the equivalent sUSDS amount) to prevent fractional underpayment via Rate-Provider rounding. MEV exposure documented as a Stage Q audit item alongside `limitRaw == 0` and `minBptAmountOut == 0` per `STAGE_D_PLAN.md` L703.

**Caller surface — placeholder + one-shot setter pattern (mirrors F-D20–F-D23):**

`swapAndDeposit` is gated to two known Aureum callers: **`VaultClassRegistry`** (consumed by `proposeVaultClass` for the proposal bond) and **`GaugeRegistry`** (consumed by `activateGauge` for the anti-spam fee). Both ship as placeholder `address(0)` immutables → constructor `moduleAdmin` → one-shot setters that zero the admin slot atomically with the caller-set slot, per the C-D11 / D-D2 / F-D20 family. Pre-`setVaultClassRegistry` + pre-`setGaugeRegistry`, the helper is **structurally unreachable** — permissionless callers cannot invoke it. The setter-gated variant is preferred over a permissionless one to keep the helper's audit scope tight (only Aureum-internal callers); G1.x implementation may revisit if gating adds disproportionate complexity without commensurate safety gain.

**Tunables / sub-decisions deferred to G1.x:**

- `swapAndDeposit` exact signature shape (single `(payToken, amount)` vs richer form with optional caller-side deposit-credit verification).
- The 100-svZCHF canonical fee magnitude — held against OQ-G3's 100 svZCHF/sUSDS spec; revisits at G1.x in concert with **G-D9** tunables (proposal bond `≥` anti-spam fee).
- `ITVLOracle` precedent (Stage F F0.2) versus per-pair Rate-Provider lookup — both are pool-internal reads; G1.x picks based on call-site ergonomics.

**Forward references.** Consumed by `VaultClassRegistry.sol` (G1.2+) and `GaugeRegistry.sol` (G3.1+). Stage D `AureumFeeRoutingHook` + `AureumProtocolFeeController` are **not** modified.

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
