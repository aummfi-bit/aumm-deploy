# Stage G — Notes & Design Freeze (Auto-Gauge Pivot)

**Status:** Scaffold + **design freeze for G1.1 planning** — 2026-05-05.  
**Precheck:** [STAGE_G_PRECHECK_AUTO_GAUGE.md](STAGE_G_PRECHECK_AUTO_GAUGE.md).

---

## G-D1 — Auto-gauge vs governance-only paths

- **Permissionless activation:** Any caller may invoke **`activateGauge(pool)`** (exact name at implementation time) when `GaugeEligibility` reports all immutable criteria satisfied and **anti-spam fee** (100 svZCHF or 125 sUSDS per **G-D12** spec lock) has been credited via the shared swap-and-deposit path to der Bodensee. No governance signature.
- **Governance composition path:** After a **composition challenge** executes, **`onlyGovernanceContract`** exposes a restricted entry (e.g. `registerGaugeFromComposition(pool)`) that marks the replacement pool gauged — this is **not** a fourth vote type; it is execution of an already-approved composition proposal. **No boost** at registration per **G-D13**; the replacement gauge enters at base `M_i = 1.0` and competes from the next epoch boundary.
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

Three distinct entry points produce a registered gauge. **No boost is applied at registration on any path** per **G-D13** — cold-start emission lift, if any, is funded out-of-band via Incendiary Boost (Stage L), opt-in by AuMM holders to any already-gauged pool.

- **(i) Permissionless — `activateGauge(pool)`.** Per **G-D1**, callable by any address once `GaugeEligibility` reports all immutable criteria satisfied and the **OQ-G3** anti-spam fee has been credited via swap-and-deposit to der Bodensee. **No boost.** The pool enters tournament accounting at base `M_i = 1.0` per **F-8** and competes for emission share through the **F-10** efficiency tournament from the next epoch boundary onward.
- **(ii) Composition — `registerGaugeFromComposition(pool)`.** Per **G-D1**, restricted to `onlyGovernanceContract`, invoked as the execution leg of an approved composition challenge. **No boost** per **G-D13** — the replacement gauge enters tournament accounting at base `M_i = 1.0` (per **F-8**) and competes from the next epoch boundary.
- **(iii) Founding-pool seeding — `seedFoundingPool(pool, seedAmount)`.** Restricted to `onlyGovernanceContract` (Authorizer Safe through Stage K, on-chain governance thereafter per CLAUDE.md §1). Necessary because founding pools are deployed at zero TVL and would fail the **OQ-G2** `$10K` 7-day-SMA floor at any first eligibility check; the permissionless `activateGauge` path is therefore structurally unreachable for founding pools at deploy time. **No boost** per **G-D13** — founding pools enter at base `M_i = 1.0` and rely on the **OQ-G2** TVL floor exemption to bridge the cold-start window. This entry point is the contract-spec realisation of test invariant **T-R1** — "governance-free via deploy shim" in T-R1 is shorthand for "no public-vote / proposal cycle"; the seeding call itself is governance-restricted (Authorizer Safe), **not** access-free.

| Path | Caller | Eligibility-gate path | Anti-spam fee | Boost applied |
| --- | --- | --- | --- | --- |
| `activateGauge(pool)` | any address | full `GaugeEligibility` (all immutable criteria) | yes — 100 svZCHF or 125 sUSDS (per **G-D12**) | **no** |
| `registerGaugeFromComposition(pool)` | governance contract | composition-criteria subset (full enumeration at RT-03 sub-step) | no | **no** (per **G-D13**) |
| `seedFoundingPool(pool, seedAmount)` | governance contract | bypassed (zero-TVL deploy shim) | no | **no** (per **G-D13**) |

**Per-path symmetry — no boost on any path** (per **G-D13**). Cold-start emission lift, if any, is funded out-of-band via Incendiary Boost (Stage L), opt-in by AuMM holders to any already-gauged pool. The earlier per-path boost asymmetry — boost on (ii) and (iii), no boost on (i) — is withdrawn at G-D13: Incendiary Boost subsumes the cold-start use case, externalizing lift to user-conviction rather than protocol entitlement.

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

**Equivalence — superseded by G-D12 (G1.2 spec lock):**

Fee magnitudes and equality rules are locked at G-D12 as strict per-token constants (`FEE_SVZCHF = 100e18`, `FEE_SUSDS = 125e18`) with no Rate-Provider read. The earlier RP-derived equivalence framing is withdrawn; rationale for the asymmetric ~25% magnitude is at G-D12's "Rationale" subsection.

**Caller surface — placeholder + one-shot setter pattern (mirrors F-D20–F-D23):**

`swapAndDeposit` is gated to two known Aureum callers: **`VaultClassRegistry`** (consumed by `proposeVaultClass` for the proposal bond) and **`GaugeRegistry`** (consumed by `activateGauge` for the anti-spam fee). Both ship as placeholder `address(0)` immutables → constructor `moduleAdmin` → one-shot setters that zero the admin slot atomically with the caller-set slot, per the C-D11 / D-D2 / F-D20 family. Pre-`setVaultClassRegistry` + pre-`setGaugeRegistry`, the helper is **structurally unreachable** — permissionless callers cannot invoke it. The setter-gated variant is preferred over a permissionless one to keep the helper's audit scope tight (only Aureum-internal callers); G1.x implementation may revisit if gating adds disproportionate complexity without commensurate safety gain.

**Tunables / sub-decisions deferred to G1.x:**

- `swapAndDeposit` exact signature shape (single `(payToken, amount)` vs richer form with optional caller-side deposit-credit verification).
- The 100-svZCHF canonical fee magnitude — held against OQ-G3's 100 svZCHF/sUSDS spec; revisits at G1.x in concert with **G-D9** tunables (proposal bond `≥` anti-spam fee).
- `ITVLOracle` precedent (Stage F F0.2) versus per-pair Rate-Provider lookup — both are pool-internal reads; G1.x picks based on call-site ergonomics.

**Forward references.** Consumed by `VaultClassRegistry.sol` (G1.2+) and `GaugeRegistry.sol` (G3.1+). Stage D `AureumFeeRoutingHook` + `AureumProtocolFeeController` are **not** modified.

---

## G-D12 — `SwapAndDepositToBodensee` helper: full spec lock (G1.2)

Resolves the G-D11 "Tunables / sub-decisions deferred to G1.x" residual. Locks the helper's complete contract spec — signature, pay-token allowlist, fee policy, caller-gate model, callback discipline, token index resolution, CEI discipline, custom errors. Audit surface fully enumerated for G1.5 (unit) + G1.6 (fork) + Stage Q (formal).

**Signature (locked).**

```solidity
function swapAndDeposit(IERC20 payToken, uint256 amount) external;
function requiredAmount(IERC20 payToken) external view returns (uint256);
```

Single external entry. No `to` field, no `bptRecipient`, no caller-supplied `maxAmountsIn` array — DONATION's recipient is implicit (Bodensee), it mints zero BPT regardless, and the helper builds the amounts array internally from the token-index lock below. Companion view `requiredAmount` returns the canonical fee constant for the given pay token; callers SHOULD read this in the same call path / same execution context where feasible (contract-to-contract call paths read-and-pay atomically; EOA-driven calls require a wrapper contract to read-and-pay in a single call).

**Payment pattern (locked).** Caller pre-pushes `payToken` to the helper before invoking `swapAndDeposit`:

1. proposer's prior `payToken.approve(registry, amount)`;
2. registry's `payToken.safeTransferFrom(proposer, address(registry), amount)`;
3. registry's `payToken.safeTransfer(address(helper), amount)`;
4. registry's `helper.swapAndDeposit(payToken, amount)`;
5. helper's callback transfers OWN balance (`payToken.safeTransfer(address(_vault), amount)`) + `_vault.settle` + `_vault.addLiquidity({kind: DONATION, ...})`;
6. helper post-callback assertion: `payToken.balanceOf(address(this)) == 0`.

This refines G-D11's "pull `payToken` from caller via `safeTransferFrom`" wording — the helper does not pull via approval; the caller pre-pushes. Removes the registry→helper approval chain entirely; tightens the audit surface to a single transient-balance window inside one atomic transaction.

**Pay-token allowlist (locked).** Hard allowlist enforced at entry:

| `payToken`    | Status   | Required amount               |
| ------------- | -------- | ----------------------------- |
| `SV_ZCHF`     | accepted | `FEE_SVZCHF` (= 100e18)       |
| `S_USDS`      | accepted | `FEE_SUSDS`  (= 125e18)       |
| anything else | revert `InvalidPayToken(payToken)` | —                |

Both stables are 30%-weight Bodensee tokens, so DONATION accepts them with no swap leg. AuMM is the third pool token but is ineligible per OQ-G3 (stable pair only). All other ERC-20s are rejected — closes the fee-on-transfer / rebasing-token / malicious-token surface to zero.

**Fee policy (locked).** Both pay tokens accept a single canonical constant fee, with strict equality:

- `payToken == SV_ZCHF` → `amount == FEE_SVZCHF` (100e18); revert `IncorrectAmount(amount, FEE_SVZCHF)` on miss.
- `payToken == S_USDS`  → `amount == FEE_SUSDS`  (125e18); revert `IncorrectAmount(amount, FEE_SUSDS)` on miss.

Strict equality both directions, both tokens. No surplus tolerance, no underpay window, no Rate Provider read.

**Rationale.** The fee is an anti-spam gate, not a precise economic toll. Both stables appreciate over time at slightly different yield rates (svZCHF inherits Frankencoin's CHF-anchored yield; sUSDS inherits Sky's USDS-anchored yield); the cheaper pay-token in any given block floats with that differential, and proposers self-select. The protocol receives ~$100–$135 USD-equivalent in either case at any reasonable horizon. Locking two constants instead of an RP-derived equivalence eliminates an entire class of attack surface (RP malfunction, RP drift, RP-skew MEV, RP zero / out-of-bound returns) and removes the corresponding guard code from the helper's audit surface. The 125 sUSDS magnitude reflects the ~25% nominal premium of svZCHF over sUSDS at deploy (CHF/USD parity × yield-wrapper appreciation differential). If at deploy the differential is materially different, G1.x revisits the magnitude — but only the magnitude, not the strict-equality structure.

**Caller-gate model (locked) — one-shot setters with irreversible admin burn.**

```solidity
address public moduleAdmin;            // set in constructor; cleared at second setter call
address public vaultClassRegistry;     // address(0) at deploy; settable once
address public gaugeRegistry;          // address(0) at deploy; settable once

modifier onlyAuthorizedCaller() {
    if (msg.sender != vaultClassRegistry && msg.sender != gaugeRegistry) {
        revert OnlyAuthorizedCaller(msg.sender);
    }
    _;
}
// setVaultClassRegistry / setGaugeRegistry: gated to moduleAdmin, one-shot,
// burns moduleAdmin atomically when whichever is the SECOND set fires.
```

**Partial activation is intentional.** Each caller becomes authorized the moment its setter fires; the helper does NOT require both setters to be set before allowing any call. Rationale: `VaultClassRegistry` deploys at G1.9 and `GaugeRegistry` at G3.x — between those points, the registry needs the helper for proposal bonds; gating helper-callability on both being set creates a deploy-ordering coupling without security gain. The address(0) slot for the not-yet-set caller never matches any real `msg.sender`, so partial-activation is structurally equivalent to "only the set caller is authorized." Locking explicitly to remove ambiguity.

`moduleAdmin` is cleared atomically at whichever setter is called second. Once cleared, no further setter call is possible (admin == address(0) ≠ msg.sender for any real EOA or contract). This eliminates lingering admin privilege after setup completes.

**Callback discipline (locked).** Outer `swapAndDeposit`:

1. `onlyAuthorizedCaller` modifier.
2. `if (payToken != SV_ZCHF && payToken != S_USDS) revert InvalidPayToken(payToken);`.
3. `if (amount == 0) revert ZeroAmount();`.
4. Compute `required = _requiredAmount(payToken)`; `if (amount != required) revert IncorrectAmount(amount, required);`.
5. Reentrancy: `if (_executing) revert ReentrancyGuard(); _executing = true;`.
6. Callback payload binding: cache `_pendingPayToken = payToken; _pendingAmount = amount; _originalCaller = msg.sender;` (transient storage in unlock scope).
7. `_vault.unlock(abi.encodeCall(this._swapAndDepositCallback, (payToken, amount)));`.
8. Clear `_executing`, `_pendingPayToken`, `_pendingAmount`, `_originalCaller` (transient teardown).
9. Post-assert: `if (payToken.balanceOf(address(this)) != 0) revert HelperBalanceNonZero(...);`.

Callback `_swapAndDepositCallback(IERC20 payToken, uint256 amount) external`:

1. `if (msg.sender != address(_vault)) revert OnlyVault(msg.sender);` — strict; this function MUST NOT be callable by anyone except the Vault re-entering after `unlock`.
2. Payload cross-check: `if (payToken != _pendingPayToken || amount != _pendingAmount) revert CallbackPayloadMismatch();`. Defends against any state-confusion where the Vault's callback args drift from the outer-cached values.
3. Snapshot `preReserve` using the canonical V3 reserve / balance read for the (Bodensee, payToken) pair — exact selector locked at G1.4 against `lib/balancer-v3-monorepo` source (candidates include `Vault.getReservesOf`, `IVault.getPoolTokenInfo`, `IVault.getCurrentLiveBalances`; verified at implementation against submodule HEAD). The same selector MUST be used for the `postReserve` read in step 8 — no mixed-source drift between pre and post.
4. `payToken.safeTransfer(address(_vault), amount); _vault.settle(payToken, amount);`.
5. Build `maxAmountsIn[3]` using the token-index lock (next paragraph) — `payToken` slot = `amount`; other slots = 0.
6. `(, uint256 bptOut, ) = _vault.addLiquidity(AddLiquidityParams({pool: BODENSEE, kind: AddLiquidityKind.DONATION, maxAmountsIn: maxAmountsIn, minBptAmountOut: 0, userData: ""}));`.
7. `if (bptOut != 0) revert BptMintedOnDonation(bptOut);` — defensive; V3 spec guarantees zero, this catches future regression.
8. `postReserve` via the same canonical V3 read used in step 3; `if (postReserve != preReserve + amount) revert ReserveDeltaMismatch(preReserve + amount, postReserve);` — catches any fee-on-transfer / rebasing token that slips past the allowlist.
9. `emit FeeRoutedToBodensee(_originalCaller, payToken, amount);` — caller identity sourced from cached outer caller, never from callback `msg.sender` (which is the Vault and is informationally useless to event consumers).

V3's `Vault.unlock` enforces a single-unlock invariant globally; the helper's own `_executing` flag is defense-in-depth at the helper level. Negligible gas, eliminates a class of state-confusion bugs.

**Token index resolution (locked).** Constructor reads Bodensee's canonical token list via `_vault.getPoolTokens(_bodensee)`, locates `_svZchf` and `_sUsds` indices, and stores them as `uint8 _svZchfIndex` / `uint8 _sUsdsIndex` immutables. Reverts `TokenNotInPool(token)` at deploy if either is absent. Index resolution is one-shot at deploy; the runtime callback uses cached indices only. No runtime re-derivation, no re-reading of pool tokens at call time. The `maxAmountsIn` array is built as length-3 with the `payToken` slot set to `amount` and other slots defaulting to zero — the third pool token (AuMM) is implicitly zero, so no separate `_aummIndex` is needed.

**CEI discipline (locked).** After `_executing = true`, the only permitted external calls inside the callback are:

- `_vault.*` (settle, addLiquidity, the canonical reserve read).
- `payToken.safeTransfer(address(_vault), amount)` — the pre-settle push.

No external calls to Rate Providers (those are not used in rev2; should this lock be amended in a future revision to re-introduce RP reads, those reads MUST happen in `requiredAmount` view, BEFORE `_executing`). No external calls to any contract other than the Vault and the already-validated `payToken`. CEI is documented policy at G-D12 and asserted by code-review at G1.4.

**Custom errors (locked — every guard typed; no `require(string)`, no plain `revert()`):**

`OnlyAuthorizedCaller`, `OnlyVault`, `OnlyModuleAdmin`, `SetterAlreadyCalled`, `ZeroAddress`, `InvalidPayToken`, `ZeroAmount`, `IncorrectAmount`, `BptMintedOnDonation`, `ReserveDeltaMismatch`, `HelperBalanceNonZero`, `ReentrancyGuard`, `TokenNotInPool`, `CallbackPayloadMismatch`.

**Immutables (locked — constructor parameters):**

`IVault _vault`, `address _bodensee`, `IERC20 _svZchf`, `IERC20 _sUsds`, `address _moduleAdmin`, `uint8 _svZchfIndex`, `uint8 _sUsdsIndex`. All stored `immutable`. Zero-address checks revert `ZeroAddress`. `_moduleAdmin == address(0)` may be rejected unconditionally or accepted only in test-harness mode — TBD at G1.4 against deploy-script ergonomics.

**Constants (locked):**

```
uint256 internal constant FEE_SVZCHF = 100e18;
uint256 internal constant FEE_SUSDS  = 125e18;
```

**Test invariants targeted (G1.5 unit + G1.6 fork).**

Unit (G1.5): unauthorized caller reverts `OnlyAuthorizedCaller`; pre-setter helper unreachable from any caller; partial-activation correctness (only-registry-set call path; only-gauge-set call path); post-both-set both callers allowed; second-set reverts `SetterAlreadyCalled`; admin burn after second set verified; invalid pay token reverts `InvalidPayToken`; zero amount reverts `ZeroAmount`; svZCHF underpay/overpay reverts `IncorrectAmount`; sUSDS underpay/overpay reverts `IncorrectAmount`; reentrancy guard fires on nested call attempt; callback sender = non-Vault reverts `OnlyVault`; callback payload mismatch reverts `CallbackPayloadMismatch`; constructor reverts `TokenNotInPool` when given a Bodensee that does not contain svZCHF or sUSDS.

Fork (G1.6): real Bodensee on mainnet fork with `enableDonation = true`; svZCHF and sUSDS happy paths each at exactly the canonical fee; verify `bptOut == 0`; verify `postReserve - preReserve == amount` for the pay token; verify helper post-balance == 0; verify `FeeRoutedToBodensee(originalCaller, payToken, amount)` emit binds the correct cached caller identity (not the Vault); counterfactual: synthetic fee-on-transfer behaviour injected via `vm.mockCall` on `payToken.transfer` reverts `ReserveDeltaMismatch`.

**Out of scope at G1.2 (deferred to G1.4 implementation):**

OZ-`ReentrancyGuard`-vs-inline choice (style only); storage slot ordering (gas optimization); function visibility internal-vs-private (style); transient-storage-vs-storage for `_pendingPayToken` / `_pendingAmount` / `_originalCaller` (Solidity 0.8.26 supports the `transient` keyword — pick at G1.4 against gas benchmark and against the `_executing` reentrancy flag's own storage choice).

**Forward references.**

`vaultClassRegistry` setter wired at G1.9 (deploy of `VaultClassRegistry.sol`). `gaugeRegistry` setter wired at G3.x (deploy of `GaugeRegistry.sol`). Until both setters are called, only the set caller can reach the helper; before either is called, the helper is structurally unreachable.

---

## G-D13 — 90-day boost deprecation (G-D7 supersession)

Supersedes the per-path 90-day boost policy locked at **G-D7**: the 90-day boost is **deprecated entirely** across all three activation paths. Cold-start emission lift, if any, is funded out-of-band via **Incendiary Boost** (Stage L) — opt-in, user-funded, applicable to any already-gauged pool — not as an entry-time entitlement of any registration path. **G-D13 locks only the non-existence of registration-time boost; Incendiary Boost mechanics lock at Stage L and `aumm-site`.**

**Effect on G-D7 paths.**

- **(i) `activateGauge(pool)`** — unchanged. Already locked at G-D7 with no boost.
- **(ii) `registerGaugeFromComposition(pool)`** — was "applies 90-day boost atomically"; now **no boost** at registration. The replacement gauge enters tournament accounting at base `M_i = 1.0` (per **F-8**) and competes from the next epoch boundary.
- **(iii) `seedFoundingPool(pool, seedAmount)`** — was "applies 90-day boost"; now **no boost** at seeding. Founding pools enter at base `M_i = 1.0` and rely on the **OQ-G2** TVL floor exemption already locked at G-D7 to bridge the cold-start window.

**Rationale.** Three distinct angles, each load-bearing:

1. **Redundancy / subsumption.** The 90-day per-path window was originally a cold-start accommodation for paths (ii)/(iii) — pools entering without demonstrated independent traction. Incendiary Boost (Stage L) provides equivalent cold-start lift opt-in to any already-gauged pool regardless of activation path. The carve-out is no longer needed; the general mechanism subsumes it.
2. **Opt-in conviction signal, not protocol entitlement.** User-funded Incendiary Boost forces external skin-in-the-game; self-selection by AuMM holders is a higher-quality cold-start signal than constitutional fiat. (Path-dependent automatic boost also creates unequal rights between activation paths even under well-behaved governance.)
3. **Reduces audit surface at registration.** **MUST NOT:** `registerGaugeFromComposition(pool)` and `seedFoundingPool(pool, seedAmount)` SHALL NOT call `activateBoost` (or any boost-window-opening function) as part of registration. Verified via ABI assertion + unit tests on those entry points. `CCBMultiplier.sol` boost machinery (OQ-23 `activateBoost`, M_i clamp, F-D24 reset) is **unaffected** — Incendiary Boost (Stage L) reuses it. The simplification is at the registration paths, not in the multiplier.

**Cross-references.** G-D7 inline amendment (boost columns flipped to **no**, "Boost asymmetry rationale" rewritten as "Per-path symmetry"). G-D1 inline amendment (composition-path bullet drops boost language). T-T4 inline amendment (test-matrix scenario drops "boost clock starts"). Companion spec sweep landed at `aumm-site` `08_bootstrap.md`, `09_transitions.md`, `04_tokenomics.md`, `05_miliarium_aureum.md`, `06_miliarium_manifest.md`, `12_aureum_glossary.md`, `14_ux_ui.md`, `17_faq.md` (receipt commit `055d89f`, "SG.AMEND-1").

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
| T-T4 | Composition execution → new pool gauged at base `M_i = 1.0`; old pool revoked per O |

### Regression

| ID | Scenario |
| --- | --- |
| T-R1 | Founding pools can be seeded **governance-free** via deploy shim (Stage M/N alignment) |

---

## Findings queue (reserved)

(Numbered Stage G findings `G10+` appended here as implementation proceeds — analogous to Stage F NOTES.)
