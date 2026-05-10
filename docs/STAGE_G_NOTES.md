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

- **Proposal.** Any address calls `proposeVaultClass(admissionType, admissionValue, constraintsHash)` paying a non-refundable bond in svZCHF. The bond routes one-sided to der Bodensee via `helper.donate(svZCHF, PROPOSAL_BOND_SVZCHF)` per **G-D21** variable-amount entry point — registry pre-pushes svZCHF to the helper (G-D12 caller-pre-push pattern), then calls `donate`; helper validates authorization + token allowlist + non-zero amount but does NOT validate magnitude (per G-D21 trust boundary; bond math is enforced upstream by the `PROPOSAL_BOND_SVZCHF` constant in `VaultClassRegistry`). Sibling path to anti-spam fee (path #1, strict-equality `swapAndDeposit`) and governance proposal deposits (paths #3 / #4 / #5, also via `donate` once Stage K lands). No burn, no treasury accumulation.
- **Veto window.** Bounded block range during which qualified AuMT holders may invoke `vetoProposal(id)` if cumulative AuMT-weighted veto support meets the veto threshold.
- **Auto-finalize.** Window expires without a successful veto → proposal auto-executes in a single transaction; class enters the registry. **No** explicit two-stage `finalize`-then-`execute` — single-tx state transition on window expiry, minimizing stuck-state surface.
- **Revocation.** Governance may invoke `revokeVaultClass(id)` to denounce a previously-admitted class. **Revocable-with-grandfather** is the locked policy. Revocation blocks new numerator credit at the next epoch boundary (per **G-D8** canonical definition); existing gauges are not force-revoked but face the standard graduated grace period from `08_bootstrap.md` §xxiii if they fall below 52% as a result.

**Admission fingerprints — three types, proposer-stated:**

A `VaultClassProposal` declares `admissionType` from:

- **`ImplementationAddress`** — admits a specific implementation behind a proxy. Trust delegated to the proxy admin's upgrade discipline.
- **`FactoryAddress`** — admits all current and future vaults from the factory. Trust delegated to the factory's deployment policy.
- **`BytecodeHash`** — admits exact bytecode match. Future-proof against impl rotation, but blocks legitimate upgrades. **On-chain admission semantics deferred at G1.13-pre-B (Option A)** — see "Bytecode-hash deferral lock" below.

Each fingerprint carries a different threat model. Proposal text must declare which type was selected and why it fits the class being admitted; the veto mechanism is the protocol's check on proposers' fingerprint judgement.

**Bytecode-hash deferral lock (Option A — Stage G scope).** On-chain admission semantics for `AdmissionType.BytecodeHash` are **deferred** at G1.13-pre-B. The `admittedClasses` mapping is address-keyed (`mapping(address => bool)`), so a fingerprint comparison against `keccak256(token.code)` has no storage path under the G1.11 / G1.12 scaffold. Two enforcement sites close every admission route until bytes32-keyed storage and `isAdmittedClass(token)` resolution discipline lock together (likely the G2.x `GaugeEligibility` integration beat): (1) `proposeVaultClass` runtime guard — reverts `BytecodeHashAdmissionDeferred()` when `admissionType == BytecodeHash`; lands at G1.13. (2) Constructor genesis guard (deferral with teeth) — the genesis loop reverts `BytecodeHashAdmissionDeferred()` if any `genesisTypes[i] == BytecodeHash`; prevents a deploy-time end-run around the runtime guard; lands as G-D20 validation step 6 (this commit) and G1.13 source change. The enum variant remains in `IVaultClassRegistry.AdmissionType` to avoid ABI / docs churn for integrators who already enumerate three types — `BytecodeHash` is **reserved enum territory** until on-chain storage shape lands. Rejected alternatives: (a) bytes32 parallel storage at G1.13 — bigger blast radius without `isAdmittedClass` resolution discipline; (b) derived non-zero address sentinel from `constraintsHash` — 96-bit truncation collision surface unsuitable for a permissioned admission gate; (c) struct/storage rework to fingerprint-keyed mapping — cleaner if designed day-one but expensive against shipped G1.11 / G1.12 surface. Deferral with teeth — reject at every entrypoint until the storage story lands — preserves all four options for the eventual implementation beat.

**Cross-references.** G-D20 step 6 (constructor genesis guard, this commit). G-D20 "Subsequent surface added at G1.13" paragraph (this commit). G-D21 (helper two-entry-point split — `proposeVaultClass` bond routing path, this commit). PLAN G1.12 + G1.13 (paragraph amendments at G1.13-pre-C; G1.13 paragraph further amended at G1.13-pre-D for the `helper.donate` routing). G2.x / `GaugeEligibility` (`isAdmittedClass(token)` discipline + bytecode-hash storage rework, deferred). G5.x (`BytecodeHashAdmissionDeferred` cleanup if `BytecodeHash` admission gets implemented before then; otherwise stays declared and reachable).

**Genesis seeding (Option a-prime — constructor-injected genesis arrays):**

The Miliarium-pool ERC-4626 vault classes (the exact set per the deployed Miliarium pools at Stages M / N — waEthUSDC, ixEDEL, sUSDS-class wrappers, and the remainder per per-pool profiles in `aummfi-bit/aumm-site/miliarium_profiles/`) are admitted at deploy via constructor-injected `memory` arrays — `address[] memory genesisTokens, AdmissionType[] memory genesisTypes` — passed by the deploy script. **No** one-shot seeding admin entrypoint, **no** Authorizer-Safe self-call on `proposeVaultClass`. The genesis class set is **deploy-time-immutable** (bound at the moment of construction; no post-deploy admission entrypoint exists at Stage G scope); future classes enter via the `proposeVaultClass` + veto flow once on-chain governance is live (Stage K). Pre-Stage-K, the registry is frozen at its constructor-seeded set; pools using only genesis-admitted classes can be gauged permissionlessly through `activateGauge`. Concrete genesis set, validation discipline (length cap, zero-address rejection, deduplication), and per-class event surface lock at **G-D20** below.

**Tunables — deferred to G1.x with non-regressable constraints:**

- `proposalBond ≥ antiSpamFee` (anti-spam fee is **100 svZCHF or 125 sUSDS** per **G-D12** spec lock — strict per-token constants; `proposalBond` is svZCHF-denominated per the G-D9 mechanism above, so the binding constraint is `proposalBond ≥ FEE_SVZCHF` (100e18); class-admission bond is higher-stakes governance and must not undercut the simpler permissionless-activation fee).
- `vetoThreshold ≤ governanceQuorumThreshold` (vetoes must be reachable at lower thresholds than full proposal quorum, so a vigilant minority can block a captured-quorum bad proposal).
- Veto window in blocks: minimum `≥ BLOCKS_PER_EPOCH` (governance reaction window); maximum `≤ 3 × BLOCKS_PER_EPOCH` (avoids stalling legitimate admissions).

Concrete bond, threshold, and window values lock at **G1.x**.

**Forward dependencies — placeholder + one-shot setter pattern (mirrors Stage F F-D20–F-D23):**

- `IAuMT` for veto vote weight — concrete contract ships at Stage I; Stage G uses placeholder address + one-shot setter.
- `governanceContract` for `revokeVaultClass` — concrete contract ships at Stage K; same placeholder + one-shot setter pattern.

Pre-Stage-I + pre-Stage-K, the veto path is **structurally unreachable** (placeholder `IAuMT` returns zero vote weight; placeholder governance address rejects all calls). Pools relying solely on genesis-seeded classes can still be gauged permissionlessly via `activateGauge`.

**Setter implementation lock (per F-D23 precedent in `src/ccb/CCBMultiplier.sol`).** The two setters use named gate-revert errors `OnlyAuMTSetter()` and `OnlyGovernanceSetter()`, paralleling F-D23's `OnlyRegistrySetter()` / `OnlyGaugeRegistrySetter()`. Distinct from the existing `OnlyGovernance(address caller)` error in the G1.11 scaffold, which gates `revokeVaultClass` once `governanceContract` is wired post-setter — readers must not conflate the two: `OnlyGovernanceSetter()` fires on a wrong-caller miss against `governanceSetter` during the setter's one-shot window; `OnlyGovernance(caller)` fires on a wrong-caller miss against `governanceContract` after the setter has zeroed `governanceSetter`. Body shape (locked, mirrors F-D20 / F-D23): caller-gate first (`if (msg.sender != auMTSetter) revert OnlyAuMTSetter();`), then zero-address check on the new binding (`if (address(auMT_) == address(0)) revert ZeroAddress();`), then assign (`auMT = IAuMT(auMT_);`), then clear setter slot (`auMTSetter = address(0);`). Symmetric for `setGovernanceContract`. The `auMTSetter = address(0);` clear at end of body is the structural seal — any subsequent call hits the gate (since `auMTSetter == address(0)` post-clear and no real caller is `address(0)`) and reverts `OnlyAuMTSetter()`. The `SetterAlreadyCalled` error declared in the G1.11 scaffold is **not** the one-shot seal revert under this pattern; structurally unreachable in `setAuMT` / `setGovernanceContract`, declared-but-unused, removal deferred to a G5.x cleanup pass.

**Enum-bound discipline (locked — parallels G-D20 step 5).** `proposeVaultClass(AdmissionType admissionType, ...)` does not include an explicit `revert InvalidAdmissionType()` guard in its function body. Solidity 0.8.26's ABI decoding enforces enum validity for constructor arguments and external function calls alike — entries outside the three-variant range revert with `Panic(0x21)` at decode time, before any user code runs. An explicit body-level enum check is structurally unreachable by the same mechanism, and sits in the same category as `SetterAlreadyCalled` (G1.12-pre-D resolution): both are declared in `VaultClassRegistry.sol`, neither reachable from any caller; joint cleanup deferred to **G5.x**. (Wording note: G-D20 step 5 uses "calldata decode" / "before the constructor body runs" — that framing is constructor-scoped; this paragraph generalises the rationale to ABI decoding at any external or public function entry, covering constructor args and external calls alike.)

**Cross-references.** G-D20 step 5 (NOTES L519 — constructor-side rationale). G1.12-pre-D (`SetterAlreadyCalled` declared-but-unused disposition). G5.x (joint cleanup pass for `InvalidAdmissionType` + `SetterAlreadyCalled`). PLAN G1.13 (G1.13-pre-A drops the explicit `InvalidAdmissionType` validation step from L227 and appends the ABI-decode cross-reference).

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
- The fee magnitude — held against OQ-G3's symmetric framing at G-D11 time; **resolved at G-D12** as strict per-token constants (`FEE_SVZCHF = 100e18`, `FEE_SUSDS = 125e18`); **G-D9** tunables (proposal bond `≥` anti-spam fee) reframe accordingly per the G-D9 amendment in this commit.
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
3. Snapshot `preReserve` via `IVault.getPoolTokenInfo(_bodensee)` — destructure the third tuple element (`uint256[] memory balancesRaw`) and read `balancesRaw[index]`, where `index` is the constructor-cached `_svZchfIndex` or `_sUsdsIndex` per the G-D12 token-index lock; selector lock + rejected-candidate rationale at **G-D18** below. The same selector MUST be used for the `postReserve` read in step 8 — no mixed-source drift between pre and post.
4. `payToken.safeTransfer(address(_vault), amount); _vault.settle(payToken, amount);`.
5. Build `maxAmountsIn[3]` using the token-index lock (next paragraph) — `payToken` slot = `amount`; other slots = 0.
6. `(, uint256 bptOut, ) = _vault.addLiquidity(AddLiquidityParams({pool: BODENSEE, to: address(this), kind: AddLiquidityKind.DONATION, maxAmountsIn: maxAmountsIn, minBptAmountOut: 0, userData: ""}));`.
7. `if (bptOut != 0) revert BptMintedOnDonation(bptOut);` — defensive; V3 spec guarantees zero, this catches future regression.
8. `postReserve` via the same canonical V3 read used in step 3; `if (postReserve != preReserve + amount) revert ReserveDeltaMismatch(preReserve + amount, postReserve);` — catches any fee-on-transfer / rebasing token that slips past the allowlist.
9. `emit FeeRoutedToBodensee(_originalCaller, payToken, amount);` — caller identity sourced from cached outer caller, never from callback `msg.sender` (which is the Vault and is informationally useless to event consumers).

V3's `Vault.unlock` enforces a single-unlock invariant globally; the helper's own `_executing` flag is defense-in-depth at the helper level. Negligible gas, eliminates a class of state-confusion bugs.

**Token index resolution (locked).** Constructor reads Bodensee's canonical token list via `_vault.getPoolTokens(_bodensee)`, locates `_svZchf` and `_sUsds` indices, and stores them as `uint8 _svZchfIndex` / `uint8 _sUsdsIndex` immutables. Reverts `TokenNotInPool(token)` at deploy if either is absent. Index resolution is one-shot at deploy; the runtime callback uses cached indices only. No runtime re-derivation, no re-reading of pool tokens at call time. The `maxAmountsIn` array is built as length-3 with the `payToken` slot set to `amount` and other slots defaulting to zero — the third pool token (AuMM) is implicitly zero, so no separate `_aummIndex` is needed.

**CEI discipline (locked).** After `_executing = true`, the only permitted external calls inside the callback are:

- `_vault.*` (settle, addLiquidity, the canonical reserve read).
- `payToken.safeTransfer(address(_vault), amount)` — the pre-settle push.

No external calls to Rate Providers (those are not used in rev2; should this lock be amended in a future revision to re-introduce RP reads, those reads MUST happen in `requiredAmount` view, BEFORE `_executing`). No external calls to any contract other than the Vault and the already-validated `payToken`. CEI is documented policy at G-D12 and asserted by code-review at G1.6 (CEI applies to the callback body, which lands at G1.6 — the G1.4 scaffold has no external-call surface).

**Custom errors (locked — every guard typed; no `require(string)`, no plain `revert()`):**

Fourteen errors with full parameter signatures locked at G1.4-pre-A:

| Error | Signature | Diagnostic role |
| --- | --- | --- |
| `OnlyAuthorizedCaller` | `error OnlyAuthorizedCaller(address caller);` | outer entry caller-gate miss |
| `OnlyVault` | `error OnlyVault(address caller);` | callback entry sender-strict miss |
| `OnlyModuleAdmin` | `error OnlyModuleAdmin(address caller);` | one-shot setter caller-gate miss |
| `SetterAlreadyCalled` | `error SetterAlreadyCalled();` | second call to `setVaultClassRegistry` or `setGaugeRegistry` |
| `ZeroAddress` | `error ZeroAddress();` | constructor input or setter arg is `address(0)` |
| `InvalidPayToken` | `error InvalidPayToken(IERC20 payToken);` | pay-token allowlist miss |
| `ZeroAmount` | `error ZeroAmount();` | `swapAndDeposit(_, 0)` |
| `IncorrectAmount` | `error IncorrectAmount(uint256 provided, uint256 required);` | strict-equality fee miss |
| `BptMintedOnDonation` | `error BptMintedOnDonation(uint256 bptOut);` | defensive — V3 spec guarantees zero |
| `ReserveDeltaMismatch` | `error ReserveDeltaMismatch(uint256 expected, uint256 actual);` | `postReserve != preReserve + amount` |
| `HelperBalanceNonZero` | `error HelperBalanceNonZero(uint256 residual);` | helper balance != 0 after callback (resolves the `HelperBalanceNonZero(...)` ellipsis above) |
| `ReentrancyGuard` | `error ReentrancyGuard();` | nested re-entry attempt |
| `TokenNotInPool` | `error TokenNotInPool(IERC20 token);` | constructor-time `getPoolTokens` miss |
| `CallbackPayloadMismatch` | `error CallbackPayloadMismatch();` | callback args drift from cached payload |

Mirrored in the **§8e.1 Must match** when G1.4 lands the source file; mirrored again as revert assertions in G1.7 unit tests.

**Events (locked):**

Three events, signatures locked at G1.5-pre-B:

| Event | Signature | Emit point |
| --- | --- | --- |
| `FeeRoutedToBodensee` | `event FeeRoutedToBodensee(address indexed originalCaller, IERC20 indexed payToken, uint256 amount);` | last step of `_swapAndDepositCallback` (G-D12 callback step 9), after the `ReserveDeltaMismatch` check; `originalCaller` sourced from cached outer `msg.sender`, never from callback `msg.sender` |
| `VaultClassRegistrySet` | `event VaultClassRegistrySet(address indexed registry);` | inside `setVaultClassRegistry`, after the slot is written and any atomic admin-burn |
| `GaugeRegistrySet` | `event GaugeRegistrySet(address indexed registry);` | inside `setGaugeRegistry`, after the slot is written and any atomic admin-burn |

Setter events follow the Stage D one-shot setter precedent (`AureumFeeRoutingHook.GovernanceModuleSet` / `IncendiaryModuleSet` at `src/fee_router/AureumFeeRoutingHook.sol` L151+L156, emitted at L221+L237) — single `address indexed registry` field for off-chain monitoring of registry deployment and the atomic-burn milestone (the second emit's transaction is the one in which `moduleAdmin` transitions to `address(0)`; both emits taken together pin the module's activation window without requiring storage reads).

G1.4 source-file scaffold (commit `2e100cb`) declared only `FeeRoutedToBodensee` — that is correct for G1.4's scope (no setters present). The two setter events land at G1.5 alongside the setters that emit them: the events block in `src/gauge/SwapAndDepositToBodensee.sol` grows from 1 to 3 declarations at G1.5 §8e.1.

Mirrored in the **§8e.1 Must match** when G1.4 (`FeeRoutedToBodensee` surface) and G1.5 (setter event declarations + emits) land the source file; mirrored as `vm.expectEmit` assertions in G1.7 unit tests (one assertion per event per relevant invariant).

**Immutables (locked — constructor parameters):**

`IVault _vault`, `address _bodensee`, `IERC20 _svZchf`, `IERC20 _sUsds`, `address _moduleAdmin`, `uint8 _svZchfIndex`, `uint8 _sUsdsIndex`. Six are stored as `immutable` (`_vault`, `_bodensee`, `_svZchf`, `_sUsds`, `_svZchfIndex`, `_sUsdsIndex`); `_moduleAdmin` is **not** an immutable — it is the constructor input that initializes the public storage slot `moduleAdmin` (declared in the storage block at line 256), the single burnable operational slot zeroed at the second setter call per the C-D11 / D-D2 / F-D20 family. No immutable mirror; one-slot burn pattern matches Stage D's `_governanceAdmin` / `_incendiaryAdmin` analog at `src/fee_router/AureumFeeRoutingHook.sol` L114-L118. Zero-address checks revert `ZeroAddress`. `_moduleAdmin == address(0)` may be rejected unconditionally or accepted only in test-harness mode — TBD at G1.4 against deploy-script ergonomics.

**Constants (locked):**

```
uint256 internal constant FEE_SVZCHF = 100e18;
uint256 internal constant FEE_SUSDS  = 125e18;
```

**Test invariants targeted (G1.5 unit + G1.6 fork).**

Unit (G1.5): unauthorized caller reverts `OnlyAuthorizedCaller`; pre-setter helper unreachable from any caller; partial-activation correctness (only-registry-set call path; only-gauge-set call path); post-both-set both callers allowed; second-set reverts `SetterAlreadyCalled`; admin burn after second set verified; invalid pay token reverts `InvalidPayToken`; zero amount reverts `ZeroAmount`; svZCHF underpay/overpay reverts `IncorrectAmount`; sUSDS underpay/overpay reverts `IncorrectAmount`; reentrancy guard fires on nested call attempt; callback sender = non-Vault reverts `OnlyVault`; callback payload mismatch reverts `CallbackPayloadMismatch`; constructor reverts `TokenNotInPool` when given a Bodensee that does not contain svZCHF or sUSDS.

Fork (G1.6): real Bodensee on mainnet fork with `enableDonation = true`; svZCHF and sUSDS happy paths each at exactly the canonical fee; verify `bptOut == 0`; verify `postReserve - preReserve == amount` for the pay token; verify helper post-balance == 0; verify `FeeRoutedToBodensee(originalCaller, payToken, amount)` emit binds the correct cached caller identity (not the Vault); counterfactual: synthetic fee-on-transfer behaviour injected via `vm.mockCall` on `_vault.getPoolTokenInfo` (freezing pre-state for both pre and post snapshot reads in the callback) reverts `ReserveDeltaMismatch` — see **G13** below.

**Out of scope at G1.2 (deferred to G1.4 implementation):**

OZ-`ReentrancyGuard`-vs-inline choice (style only); storage slot ordering (gas optimization); function visibility internal-vs-private (style). The transient-storage-vs-storage choice for `_executing` / `_pendingPayToken` / `_pendingAmount` / `_originalCaller` is **resolved at G-D14** (all four locked as `transient` per Solidity 0.8.26 + EVM Cancun).

**Forward references.**

`vaultClassRegistry` setter wired at G1.9 (deploy of `VaultClassRegistry.sol`). `gaugeRegistry` setter wired at G3.x (deploy of `GaugeRegistry.sol`). Until both setters are called, only the set caller can reach the helper; before either is called, the helper is structurally unreachable.

**Two-entry-point split lock at G-D21 (G1.13 typed-domain unblock).** The strict-equality discipline locked above applies to `swapAndDeposit(IERC20, uint256)` only — path #1 (anti-spam fee) per the original G-D12 design intent. A sibling entry point `donate(IERC20, uint256)` was added at **G-D21** for variable-amount deposits from trusted upstream contracts (paths #2 / #3 / #4 / #5 — vault-class admission bond, F-12 gauge challenge, composition challenge, fee proposal); it shares the same internal `_swapAndDepositCallback` + four transient slots (`_EXECUTING_SLOT` / `_PENDING_PAY_TOKEN_SLOT` / `_PENDING_AMOUNT_SLOT` / `_ORIGINAL_CALLER_SLOT`) + reserve-read selector lock per G-D14 + G-D18, but does NOT enforce magnitude equality. The strict-equality lock above remains binding for `swapAndDeposit` and is structurally untouched by G-D21 — source identity for the deployed-and-audited #1 path is preserved (the helper's overall artifact bytecode does change at G-D21 due to the new function + storage + errors / events, but the strict-equality entry's source text and audit lineage carry forward unchanged). See G-D21 below for the full two-entry-point design including authorization model, trust boundary, and deploy playbook.

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

## G-D14 — Transient-storage lock for unlock-callback ephemera (G1.4 resolution of G-D12 deferral)

Resolves the "transient-storage-vs-storage" deferral at G-D12 line 351. The four slots used by the `IVault.unlock` + `_swapAndDepositCallback` flow — the reentrancy flag `_executing` and the cached payload triple `_pendingPayToken` / `_pendingAmount` / `_originalCaller` — are all locked to **EIP-1153 transient storage** (`TLOAD` / `TSTORE` opcodes) under Solidity 0.8.26 + EVM Cancun, accessed via `bytes32` slot identifiers + assembly-helper wrappers per the Balancer V3 audit-precedent.

**Implementation pattern.** Each slot is declared as a `bytes32 internal immutable` derived via `TransientStorageHelpers.calculateSlot("aureum.swapAndDepositToBodensee", "<varName>")` — the same `calculateSlot` discipline Balancer V3's Vault uses for `_isUnlocked()` and the V3 transient-balance accounting. Reads / writes go through typed-slot extension wrappers from `@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol`: `asBoolean` / `asAddress` / `asUint256` cast the `bytes32` slot constant to a typed wrapper (`BooleanSlotType` / `AddressSlotType` / `Uint256SlotType`), and the same library's `tload()` / `tstore(value)` overloads operate on those typed wrappers directly — both the cast leg and the transient-read/write leg are defined in `StorageSlotExtension.sol`. The enabling `using` directive in the consuming contract is `using StorageSlotExtension for *;` — NOT `for bytes32;`, because the chain's second leg (`.tload()` / `.tstore()`) operates on the typed wrapper types (`BooleanSlotType`, `AddressSlotType`, `Uint256SlotType`), not on `bytes32`; `for bytes32;` attaches the first leg but leaves the second unresolved, causing a compile error; see **G12** below. `TransientStorageHelpers.sol` is used only for `calculateSlot` at slot-identifier derivation time; it is not the source of `tload()` / `tstore`. One slot per role:

- `_EXECUTING_SLOT` → boolean (reentrancy flag)
- `_PENDING_PAY_TOKEN_SLOT` → address (cached `IERC20 payToken`)
- `_PENDING_AMOUNT_SLOT` → uint256 (cached `amount`)
- `_ORIGINAL_CALLER_SLOT` → address (cached outer `msg.sender`)

Concrete slot-string identifiers (the second `varName` argument to `calculateSlot`) lock at the G1.4 source-file landing; the four `_*_SLOT` constants are part of the G1.4 Must match.

**Toolchain provenance.** Solidity 0.8.26 (our pinned compiler per `foundry.toml` and CLAUDE.md §2's "exact match to Balancer mainnet deployment" rule) provides EIP-1153 OPCODE support (`TLOAD` / `TSTORE`) but does NOT provide the `transient` keyword for state-variable storage location — parser support landed in 0.8.27, full code generation in 0.8.28 (October 2024). The high-level keyword approach (state variables declared with the `transient` storage-location specifier) is therefore unavailable and out-of-scope for this codebase until either solc 0.8.28 is adopted repo-wide (a chat-level architectural decision per CLAUDE.md §8c, deferred indefinitely while the Vault toolchain match is preserved) or a per-package solc-override is approved. Balancer V3 itself uses the assembly-helper pattern under the same compiler — `lib/balancer-v3-monorepo/pkg/vault/contracts/Vault.sol` L96–117's `transient()` modifier (note: `transient` here is a custom Solidity modifier *name*, not the language keyword) and `_isUnlocked()` slot accessor are the audit-precedent. `TransientStorageHelpers.sol`'s own header acknowledges the temporal gap: "When Solidity catches up and puts direct support for transient storage in the language, we should be able to get rid of this altogether." Reusing `TransientStorageHelpers` + `StorageSlotExtension` (already in our remappings as `@balancer-labs/v3-solidity-utils`) preserves auditor familiarity at zero re-derivation cost. The G10 finding at this NOTES tail captures the compile-probe rule that surfaced this correction.

**Rationale.**

1. **Lifecycle fit.** All four slots are pure unlock-scope ephemera: set at the outer `swapAndDeposit` entry (G-D12 callback step 6), read in `_swapAndDepositCallback` (steps 1–2 sender / payload checks and step 9 emit), cleared at the outer exit (step 8 — "transient teardown"). Nothing in the helper, the Vault, or any caller reads them across transactions. EIP-1153's clear-at-tx-end semantic is exactly this lifecycle and provides defense-in-depth on the explicit step-8 clears: even if a future refactor accidentally drops a clear, the next tx starts with zero slots structurally.

2. **Audit-surface reduction.** Persistent storage for these slots would create a state-residue surface — a revert mid-callback (after step 6 set, before step 8 clear) could leave non-zero slots until the next successful invocation clears them; static-analysis tools and reviewers must then reason about whether residue is observable through any future code path. Under transient storage, the residue surface is structurally absent: the next tx never observes them at all, regardless of what reverted in the previous tx.

3. **Gas.** `TLOAD` / `TSTORE` opcodes are materially cheaper than `SLOAD` / `SSTORE` per the Cancun gas schedule, especially for cold and zero-to-non-zero transitions; the assembly-helper indirection (`tload()` / `tstore()` extension calls) inlines under `via_ir = true`. The four slots see one write + one read + one clear per `swapAndDeposit` invocation; persistent storage would charge persistent-storage gas for slots the caller can never read across txs anyway. Direction is clear; specific magnitudes are scenario-dependent (warm vs cold, slot-zero state) — no per-helper benchmark is pinned at this lock, and none is needed since the choice is correctness-driven first.

4. **No downside.** No cross-tx invariant binds these slots; nothing reads them after `swapAndDeposit` returns. Persistent storage would carry observability the caller cannot use, gas the caller cannot save, and a residue surface the auditor must reason about — three costs against zero benefit.

**Effect on G-D12.** G-D12's callback narrative at lines 281–283 already describes these slots as "transient" prose-level; G-D14 lifts that from prose to a load-bearing implementation commitment via the EIP-1153 OPCODE-based assembly-helper pattern (slot constants + `tload` / `tstore`). G-D12's "Out of scope at G1.2 (deferred to G1.4 implementation)" paragraph at line 351 is amended in the same edit to drop the transient-vs-storage bullet (now resolved here) — the OZ-`ReentrancyGuard`-vs-inline / storage-slot-ordering / function-visibility deferrals remain open at G1.4.

**Effect on G1.4 §8e.1.** The Must match for the G1.4 scaffold lands four `bytes32 internal immutable _*_SLOT` declarations (`_EXECUTING_SLOT`, `_PENDING_PAY_TOKEN_SLOT`, `_PENDING_AMOUNT_SLOT`, `_ORIGINAL_CALLER_SLOT`), each derived via `TransientStorageHelpers.calculateSlot("aureum.swapAndDepositToBodensee", "<varName>")`. NO `bool transient _executing;`-style state-variable declarations — those would not compile under solc 0.8.26 per the Toolchain provenance subsection above. The actual `tload()` / `tstore()` calls land at G1.6 with the callback body; G1.4 lands only the slot-identifier surface plus the `TransientStorageHelpers` import (and `StorageSlotExtension` if the typed-slot extension wrappers are referenced at G1.4 — TBD at G1.4 §8e.1 drafting against minimal-import discipline).

**Forward references.** G1.5 (constructor refactor + one-shot setters + `onlyAuthorizedCaller` modifier) — no transient-storage interaction. G1.6 (`swapAndDeposit` entry point + `_swapAndDepositCallback`) — uses all four transient slots per G-D12 callback steps 1–9 via the `_*_SLOT` constants + `tload()` / `tstore()` calls; G-D14 closes the prior open question before that source-file work begins.

---

## G-D15 — GaugeEligibility tunables lock (G2.0 resolution)

Locks the three Stage-G-scope tunables for `GaugeEligibility` before G2.3+ source implementation. Resolution at G2.0 entry in Opus; sub-decisions G-D15a–G-D15c.

**G-D15a — `approvedFactory` immutable, no setter.** The Balancer pool factory address accepted for `getPool(pool)` validation SHALL be exposed as `address public immutable approvedFactory` set once in the constructor. Invariant: no setter for `approvedFactory` exists or will exist in this deployment of `GaugeEligibility` — migration to a different factory is a redeploy concern, not an admin knob.

**G-D15b — F-10 emission-share caps deferred to Stage H.** Per-pool emission share caps implied by formula F-10 (constitution / distributor layer) are **not** enforced inside `GaugeEligibility` in Stage G. Eligibility answers factory + class + TVL floor + pilot/bypass gates only; emission-weight capping is **deferred to Stage H emission distributor** where F-10 arithmetic belongs. `STAGE_G_PLAN.md` G2.5 L311 currently says any planner text that bound F-10 caps to `GaugeEligibility` — that plan language is **superseded by this entry**; G2.0-post plan alignment edits are out of scope for the G2.0 NOTES landing.

**G-D15c — `TVL_FLOOR_SVZCHF` encoding.** The TVL floor gate uses a named constant in native oracle units (svZCHF, 18 decimals):

- `uint256 public constant TVL_FLOOR_SVZCHF = 10_000e18;`

Eligibility rejects (or treats as ineligible per the G2.x revert / branch contract) when `tvl(pool) < TVL_FLOOR_SVZCHF`, where `tvl(pool)` is the svZCHF-denominated TVL read the eligibility module uses for the floor check. Natspec on the constant SHALL describe intent as a **Coarse anti-spam gate, not oracle-precise USD** — the floor is a deployment-tunable order-of-magnitude screen, not a claim of mark-to-market accuracy.

**Cross-references.** PLAN G2.0 (pre–G2.3 lock); G2.5 / G2.4 plan lines pending G2.0-post supersession for F-10 / TVL wording consistency. Stage H distributor consumes eligibility outputs and owns F-10 caps per this deferral.

---

## G-D17 — Revoked is terminal at Stage G; no permissionless reactivation

Locks the anti-backdoor invariant whose tactical guards already exist at G3.3 / G3.4 / G3.5 per `STAGE_G_PLAN.md` L337 / L343 / L355, and whose negative tests are enumerated at G3.6 + G4.4.

**Invariant.** Once `GaugeRegistry._gaugeStatus[pool] == GaugeStatus.Revoked`, the pool cannot return to `GaugeStatus.Active` through any Stage G entrypoint. The three activation paths in **G-D7** — permissionless `activateGauge(pool)`, governance `registerGaugeFromComposition(pool)`, governance `seedFoundingPool(pool)` — each revert `AlreadyRevoked(pool)` against a Revoked status. `revokeGauge(address) onlyGovernance` is the only state-mutating operation that writes `Revoked`, and Stage G ships **no entrypoint** that writes `Revoked → Active`. Silent reactivation is therefore structurally impossible — not a runtime guard but a missing-selector property of the contract surface.

**Recovery policy at Stage G.** No recovery entrypoint exists. `Revoked` is terminal at the contract layer for Stage G scope. The G3.5 rationale that "re-seeding a revoked founding pool is a governance amendment out of scope for Stage G — silent overwrite must not occur" is hereby elevated from a sub-step note to a Stage-G-level decision binding all three activation entrypoints, not just `seedFoundingPool`.

**Forward rule for any future stage.** If a future stage introduces a recovery entrypoint that performs `Revoked → Active`, it MUST be (i) gated to `onlyGovernanceContract`, never permissionless; (ii) on a **different selector** from `activateGauge`, `registerGaugeFromComposition`, or `seedFoundingPool` — extending any of those three to accept a Revoked status is a back-door variant and is forbidden; (iii) accompanied by a parallel update to the test matrix that retires the `Revoked → revert` expectation only for the new entrypoint and preserves it for the three existing ones. This forward rule binds future-stage authors; it does not commit the protocol to ever shipping such an entrypoint.

**Recovery shape (if ever added).** A future-stage recovery entrypoint requires a governance proposal under AuMT-weighted voting plus timelock execution — i.e. the Stage K+ on-chain governance posture per CLAUDE.md §1, not pre-Stage-K Authorizer Safe fiat. `activateGauge(pool)` remains permanently non-recovery: the back-door rule is selector-bound to the existing three activation entrypoints under any era.

**Out of scope for G-D17.** The class-layer revocation surface in **G-D9** — `revokeVaultClass(token) onlyGovernance` flipping `admittedClasses[token] = false` in `VaultClassRegistry` — is **not** terminal-at-contract: re-admission via the standard `proposeVaultClass(...)` → veto-window-skip → `finalizeProposal(id)` cycle is documented G-D9 behaviour and is the intended governance recovery path for class admission. G-D17 binds the **gauge-state** machine in `GaugeRegistry` only; the class-state machine in `VaultClassRegistry` retains its G-D9 propose/finalize re-admission semantics by design. The two surfaces compose correctly: a pool whose class is re-admitted under G-D9 still cannot itself re-enter `GaugeStatus.Active` if it was revoked under G-D17 — class-layer re-admission does not cascade to gauge-layer reactivation.

**Test binding.** Test-matrix row **T-I6** (added below) names this invariant; G3.6 unit + G4.4 fork tests at `STAGE_G_PLAN.md` L363 and L399 already enumerate the three negative-revert cases. Stage G closure requires T-I6 green.

---

## G-D18 — V3 reserve-read selector lock for `_swapAndDepositCallback` pre/post snapshots (G1.6 resolution of G-D12 deferral)

Resolves the "exact selector locked at G1.6 against `lib/balancer-v3-monorepo` source" deferral on G-D12 callback step 3 (and the matching step 8) — which canonical V3 read returns the (Bodensee, payToken) reserve in the form needed for the strict-equality `postReserve == preReserve + amount` invariant at step 8. The selector is locked to **`IVault.getPoolTokenInfo(_bodensee)` followed by `balancesRaw[index]`**, where `index` is the constructor-cached `_svZchfIndex` or `_sUsdsIndex` per the G-D12 token-index lock.

**Locked read pattern.** At step 3: call `_vault.getPoolTokenInfo(_bodensee)`, destructure the third tuple return as `uint256[] memory balancesRaw`, read `preReserve = balancesRaw[payToken == _svZchf ? _svZchfIndex : _sUsdsIndex]`. At step 8: identical call, reading `postReserve` from the same `balancesRaw[index]` slot. Both reads MUST go through `IVault.getPoolTokenInfo` — no source drift between pre and post.

**Rejected candidates.** (1) `Vault.getReservesOf(IERC20 token) returns (uint256 reserveAmount)` at `lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVaultExtension.sol` L68 — REJECTED. Returns the **Vault-global reserve** for `token` across all pools, not the (pool, token) specific balance. The donation increments only the Bodensee slot; reading the Vault-global reserve would conflate Bodensee accounting with every other pool that holds the same payToken (any other pool registered with svZCHF or sUSDS as a token). The strict-equality invariant `postReserve == preReserve + amount` would fail on any concurrent settle activity in another pool — including ordinary swap traffic unrelated to this helper. (2) `IVault.getCurrentLiveBalances(address pool) returns (uint256[] memory balancesLiveScaled18)` at `IVaultExtension.sol` L216 — REJECTED. Returns balances **scaled to 18 decimals with rate-provider application**. For sUSDS (rebasing-yield wrapper) and any future rate-bearing svZCHF variant, the scaled-18 reading differs from the raw-decimal donation `amount` by both the decimal scaling factor AND any rate-provider drift between the two snapshots. Strict equality cannot hold between a raw-decimal `amount` and a rate-scaled live balance; closing that gap would require a rate-aware delta computation that re-introduces the very drift the equality is meant to detect. (3) `IVaultMain.getPoolTokenCountAndIndexOfToken(address pool, IERC20 token) returns (uint256 tokenCount, uint256 index)` at `IVaultMain.sol` L128–L131 — NOT a reserve read. Considered only for completeness of the V3 selector survey: this is a constructor-time index-derivation alternative to the `getPoolTokens` walk locked at G-D12, not a runtime balance snapshot. Out of scope at G1.6.

**Selected candidate — `IVault.getPoolTokenInfo(address pool) returns (IERC20[] memory tokens, TokenInfo[] memory tokenInfo, uint256[] memory balancesRaw, uint256[] memory lastBalancesLiveScaled18)`**, at `IVaultExtension.sol` L197–L207. The third return tuple element `balancesRaw` is the array of **native-decimal raw balances** for each token in the pool's index order — exactly matching the raw-decimal `amount` argument the outer entry receives from the caller. The fourth return element `lastBalancesLiveScaled18` is the same scaled-18 quantity rejected in candidate (2) and is unused; standard tuple-destructuring drops it. Pool-specific (resolves the candidate-1 conflation), raw-decimal (resolves the candidate-2 scaling drift), single call returns the full token array — clean fit.

**Index resolution discipline.** The `index` argument into `balancesRaw[index]` is sourced from the constructor-immutable `_svZchfIndex` / `_sUsdsIndex` — NOT re-derived from `getPoolTokenCountAndIndexOfToken` and NOT recomputed by walking the returned `IERC20[] memory tokens` array on each callback. The G-D12 token-index lock is binding: any drift between constructor-cached index and runtime token order would surface as a test failure at G1.7 / G1.8, not as silent index reuse against re-ordered tokens. Bodensee is a fixed-membership weighted pool; tokens cannot be added or removed post-registration without redeployment, so the cached index is structurally stable.

**Forward references.** G1.6 source-file landing at `src/gauge/SwapAndDepositToBodensee.sol` — `swapAndDeposit` outer + `_swapAndDepositCallback` Must match includes the `getPoolTokenInfo` + `balancesRaw[index]` pattern at both step 3 (`preReserve`) and step 8 (`postReserve`) per G-D12 callback discipline. G1.7 unit invariants — the `postReserve == preReserve + amount` strict-equality assertion is the runtime check this selector lock makes correct.

---

## G-D19 — `VaultClassRegistry` tunables lock (G1.9 resolution of G-D9 "tunables deferred to G1.x" residual)

Locks the three economic + governance tunables consumed by the `VaultClassRegistry.sol` propose-veto-finalize-revoke flow. Values pinned at this NOTES decision; the constants block in `VaultClassRegistry.sol` at G1.11 + G1.12 reads them verbatim. G-D code G-D19 is the next available number after G-D18 (G-D15 + G-D16 reserved by PLAN G2.0 + G3.0 forward-claims; G-D14 is the transient-storage lock; G-D17 is the Revoked-terminal lock).

**Tunable 1 — `PROPOSAL_BOND_SVZCHF`.** Value **`1_000e18`** (= 1,000 svZCHF, 10× `FEE_SVZCHF`). Constraint per G-D9 + G-D12: `proposalBond ≥ FEE_SVZCHF (= 100e18)`. Class-admission is higher-stakes governance than per-pool permissionless activation — an admitted class spawns gauge-eligible pools across the protocol lifetime, so the proposer must signal serious intent at proposal time. 10× the `activateGauge` anti-spam fee gives a clear premium without imposing a punitive barrier; 1,000 svZCHF (≈ 1,000 CHF at parity) is non-trivial but reachable by a single competent proposer without coordinating a multisig. Bond lifecycle per G-D9 propose-veto-finalize-revoke flow: non-refundable at proposal time — the `PROPOSAL_BOND_SVZCHF` svZCHF routes to Bodensee via `helper.donate(svZCHF, PROPOSAL_BOND_SVZCHF)` per **G-D21** variable-amount entry point (G-D12 caller-pre-push pattern; magnitude validation is upstream in the registry per G-D21 trust boundary, not in the helper) when `proposeVaultClass` executes; never held in escrow by the registry. On `finalize()` (no successful veto), the bond is already in Bodensee and the proposer receives nothing back. On successful veto, no second transfer is needed — the bond was already donated; the veto resolves by setting `proposal.finalized = true; proposal.revoked = true;` and emitting the event. Consistent with G-D9: "paying a non-refundable bond in svZCHF. The bond routes one-sided to der Bodensee via the OQ-G3 swap-and-one-sided-deposit primitive... No burn, no treasury accumulation." Higher anchors (5,000 / 10,000 svZCHF) considered but rejected: per-class admission events are rare enough that a 10× anchor leaves Stage K governance latitude to revise upward via the `setTunables` surface (out-of-scope at G1.9 — Stage K extension) if attack patterns warrant. Lower anchors (≤ 500 svZCHF) rejected as too close to the per-pool activation fee, eroding the higher-stakes signal.

**Tunable 2 — `VETO_THRESHOLD_BPS`.** Value **`1000`** (= 10.00% AuMT-weighted vote-share). Constraint per G-D9: `vetoThreshold ≤ governanceQuorumThreshold`; governance quorum locks at Stage K against the conservative ≤ 20% upper bound on `aumm-site` `10_constitution.md` §xxix. 10% AuMT-weighted vote-share sits well under that ceiling, leaving Stage K governance latitude to raise (or lower) it later via the same `setTunables` surface. Rationale: class admission has long-term protocol-wide consequences; AuMT holders need an effective objection path that does not require galvanizing a full governance majority — a registry-specific lower fraction (per the PLAN L194 phrasing) is the correct posture, not the quorum ceiling. 5% considered and rejected as too easy to grief — a small AuMT coalition could veto every legitimate class proposal. 15% considered and rejected as too close to the 20% governance quorum, eroding the registry-specific lower-bar posture. Encoding follows the `VETO_THRESHOLD_BPS` placeholder name in PLAN G1.11 — basis points (BPS) where 10_000 = 100%, so 1000 = 10.00%. The runtime check at `VaultClassRegistry.veto()` is `(vetoSupport * 10_000) / totalAuMTSupply >= VETO_THRESHOLD_BPS`; the cast to BPS preserves precision under typical AuMT supply scales without introducing rounding asymmetry.

**Tunable 3 — `VETO_WINDOW_BLOCKS`.** Value **`201_600`** (= 2 × `BLOCKS_PER_EPOCH` ≈ 28 days). Constraint per G-D9: bounded `[BLOCKS_PER_EPOCH, 3 × BLOCKS_PER_EPOCH] = [100_800, 302_400]`. Floor (`BLOCKS_PER_EPOCH = 100_800` ≈ 14 days per CLAUDE.md §5 + OQ-4) gives a minimum governance reaction window; ceiling (`3 × BLOCKS_PER_EPOCH ≈ 42 days`) avoids stalling legitimate admissions. 2 epochs (≈ 28 days) sits in the middle of the band: enough time for AuMT holders to notice the proposal, evaluate the class's technical and economic implications, and coordinate a veto if warranted, without imposing a 6-week stall on every admission. Two-epoch alignment also lets the proposed class be observed against at least one full CCB tournament cycle (per G-D3 + F-D11 epoch-snapshot cadence) if pools of that class are deployed during the veto window — providing an empirical signal alongside the governance signal. Block-number canonicality follows CLAUDE.md §5: `BLOCKS_PER_EPOCH = 100_800` is the canonical 14-day epoch unit per OQ-4 / OQ-5; `2 × BLOCKS_PER_EPOCH = 201_600` is deterministically derived. Floor (1 epoch) considered and rejected as marginal — a 14-day window is tight for AuMT holders to coordinate against a sophisticated proposer who deliberately publishes mid-holiday or mid-conference. Ceiling (3 epochs / 42 days) considered and rejected as throughput-prohibitive — one veto window per quarter would constrain the protocol's ability to admit new classes at a healthy cadence as the ecosystem evolves.

**Encoding in `VaultClassRegistry.sol` (per PLAN G1.11 storage scaffold):**

- `uint256 public constant PROPOSAL_BOND_SVZCHF = 1_000e18;`
- `uint256 public constant VETO_THRESHOLD_BPS = 1000;`
- `uint256 public constant VETO_WINDOW_BLOCKS = 201_600;`

Three literal constants; not configurable post-deploy in Stage G scope. Stage K governance handoff per G-D9 may add a `setTunables(uint256 bond, uint256 thresholdBps, uint256 windowBlocks) external onlyGovernanceContract` surface for future revisions; that's an out-of-scope amendment for G1.9 + G1.11 + G1.12 — Stage G ships the constants form, not the configurable form. The Stage K extension is recorded as a deferred item in CLAUDE.md §11 at Stage G closure (G5.x).

**Cross-references.** G-D9 (`VaultClassRegistry` design including the "tunables deferred to G1.x" residual closed here). G-D12 (anti-spam fee anchor at `FEE_SVZCHF = 100e18`, lower bound for `proposalBond`). PLAN G1.11 (`src/gauge/VaultClassRegistry.sol` storage / constants scaffold) consumes the three constants verbatim. PLAN G1.12 (`propose` / `veto` / `finalize` / `revoke` function bodies) reads the values per G-D9 flow logic. CLAUDE.md §5 (`BLOCKS_PER_EPOCH = 100_800` canonical block-number constant). `aumm-site` `10_constitution.md` §xxix (Stage K governance quorum upper-bound that frames the veto threshold ceiling).

---

## G-D20 — Genesis class set lock: constructor-injected genesis arrays (G-D9 Option a-prime resolution)

Resolves the **G-D9** "Option a-prime" genesis-seeding pattern by pinning the constructor signature, validation discipline, length cap, and event surface for the deploy-time class admission flow. Closes the gap between G-D9's abstract "no post-deploy admin entrypoint" stance and `VaultClassRegistry.sol`'s concrete constructor at G1.12.

**Pattern (locked) — constructor-injected genesis arrays.**

```solidity
constructor(
    IERC20 svZCHF_,
    SwapAndDepositToBodensee helper_,
    address auMTSetter_,
    address governanceSetter_,
    address[] memory genesisTokens,
    AdmissionType[] memory genesisTypes
) { ... }
```

The deploy script passes the genesis class set verbatim from the canonical Miliarium-pool profile manifest (`aummfi-bit/aumm-site/miliarium_profiles/`). Data location is `memory`: solc 0.8.26 rejects `calldata` for constructor parameters with `Error (6651)` regardless of `via_ir` — constructor parameter data flows from deployment init-code into runtime, with no `CALLDATA` region in the EVM's deployment-init calling convention. The memory-copy overhead is bounded by `MAX_GENESIS_CLASSES = 32` and the constructor reads each entry once.

**Rationale — three angles, each load-bearing.**

1. **Deploy-time flexibility without post-deploy mutability.** Hardcoded constants couple the registry's bytecode to the exact deploy-time class set. If the Stage M / N pilot set changes between contract authoring and deploy — a routine occurrence as the Miliarium profile manifest evolves at `aumm-site` — the contract must be re-authored, re-audited, re-deployed. Genesis arrays decouple bytecode from values: the contract source is invariant; the deploy script reads the latest manifest and passes the resulting arrays. The end-state security property is identical (deploy-time-immutable; no post-deploy admin entrypoint), so the flexibility is gained without any weakening of the trust model.

2. **Audit-equivalent to hardcoded constants.** From a security-review standpoint, both forms produce the same end-state at construction return: a populated `admittedClasses` mapping with no later-stage entrypoint to mutate it (modulo `proposeVaultClass + veto` once `auMT` and `governanceContract` setters fire — but those flows go through the standard G-D9 mechanism, not a "genesis admin" backdoor). The deploy-script artifact pins the set as authoritatively as the contract source would.

3. **Re-deploy ergonomics for fork tests + production.** Stage G fork tests need a smaller pilot-class genesis set (Stage E waEthUSDC + ixEDEL); Stage R mainnet deploy needs the full Stage M / N production set. Genesis arrays let a single `VaultClassRegistry.sol` bytecode serve both cases. Hardcoded constants would force either two contract variants (audit / maintenance burden) or a Stage-R-only contract that's untested in fork.

**Validation discipline (constructor-time; all reverts fire before any state mutation).**

1. **Array-length agreement.** `if (genesisTokens.length != genesisTypes.length) revert GenesisLengthMismatch(genesisTokens.length, genesisTypes.length);` — catches the most common deploy-script bug.
2. **Length cap.** `if (genesisTokens.length > MAX_GENESIS_CLASSES) revert GenesisOverflow(genesisTokens.length, MAX_GENESIS_CLASSES);` where `MAX_GENESIS_CLASSES = 32`. Rationale: 32 is well above the projected Miliarium-pool class count (~10–15 distinct ERC-4626 wrappers across the 28 pools per `miliarium_profiles/`), leaving headroom for protocol evolution; an upper bound prevents pathological deploy gas / loop-bound surprises and pins the constructor's worst-case gas at audit time.
3. **Per-token zero-address rejection.** Per-iteration `if (genesisTokens[i] == address(0)) revert ZeroAddress();` — uses the existing `ZeroAddress` error already declared in the G1.11 scaffold; no new error needed.
4. **Per-token deduplication.** Per-iteration `if (admittedClasses[genesisTokens[i]]) revert DuplicateGenesisToken(genesisTokens[i]);` — checked BEFORE the `admittedClasses[token] = true` assignment, so within-array duplication or any ordering anomaly fires the revert at the second occurrence. Cheaper than a separate dedup pre-pass.
5. **`AdmissionType` enum bound.** Solidity enforces enum-validity at calldata decode (entries outside the three-variant range revert before the constructor body runs); no explicit guard needed in source. Documented for completeness.
6. **`AdmissionType.BytecodeHash` rejection (deferral with teeth).** Per-iteration `if (genesisTypes[i] == AdmissionType.BytecodeHash) revert BytecodeHashAdmissionDeferred();` — closes the deploy-time end-run around the G1.13 runtime `proposeVaultClass` guard. See "Bytecode-hash deferral lock" in G-D9 above.

**Event surface — `GenesisClassAdmitted` (separate from `VaultClassFinalized`).**

```solidity
event GenesisClassAdmitted(address indexed token, AdmissionType admissionType);
```

Emitted once per genesis class inside the constructor loop, after the `admittedClasses[token] = true; admissionTypes[token] = admissionType;` writes. Why a separate event from `VaultClassFinalized(uint256 indexed proposalId, address indexed admissionValue)`: the standard finalization event carries `proposalId` indexing into the `proposals` mapping; genesis classes have no proposal record (they bypass the propose-veto flow by design). Reusing `VaultClassFinalized` would force a sentinel `proposalId` (zero, max, or `keccak("genesis")`) that off-chain indexers must specifically interpret. The separate `GenesisClassAdmitted` event removes that ambiguity: indexers consuming `VaultClassFinalized` learn about post-deploy admissions via the standard governance flow; indexers consuming `GenesisClassAdmitted` learn about the deploy-time set. Both are unambiguous; neither requires a synthetic proposalId.

**New surface added to `VaultClassRegistry.sol` (lands at G1.12-pre-C scaffold supplement).**

The G1.11 scaffold (commit `061d967`) declared four events (`VaultClassProposed`, `VaultClassVetoed`, `VaultClassFinalized`, `VaultClassRevoked`) and ten errors (`OnlyGovernance` … `SetterAlreadyCalled`). G-D20 lock requires the scaffold to be supplemented at G1.12-pre-C with:

- One additional event: `GenesisClassAdmitted(address indexed token, AdmissionType admissionType)`.
- Three additional errors: `GenesisLengthMismatch(uint256 tokensLen, uint256 typesLen)`, `GenesisOverflow(uint256 provided, uint256 cap)`, `DuplicateGenesisToken(address token)`.
- One additional constant: `uint256 public constant MAX_GENESIS_CLASSES = 32;`.

These five items land as a Sonnet-tier mechanical scaffold supplement at G1.12-pre-C, ahead of G1.12's constructor body landing.

**Subsequent surface added at G1.13 (per G-D9 Bytecode-hash deferral lock, this commit's amendment).** One additional error: `BytecodeHashAdmissionDeferred()` (parameterless; reused at the constructor genesis-loop step 6 guard and the runtime `proposeVaultClass` guard). Constructor genesis-loop step 6 (the per-iteration `BytecodeHash` rejection above; lands inside the existing loop, between the zero-address check and the deduplication check). L57 struct Natspec correction: drop the "sentinel/zero for BytecodeHash (constraints-only path)" claim that misrepresents implementation under deferral; replace with a "reserved for future use under BytecodeHash (deferred at G1.13-pre-B)" form. All three land at G1.13 source change together with the new `proposeVaultClass` function. Forge-build green is the joint audit checkpoint. The new error joins `SetterAlreadyCalled` and `InvalidAdmissionType` as declared-but-(currently)-unused **only if** `BytecodeHash` admission gets implemented before the G5.x cleanup pass; otherwise it stays declared and reachable.

**Constructor body shape (G1.12 scope).**

After zero-address checks on the four scalar parameters (`svZCHF_`, `helper_`, `auMTSetter_`, `governanceSetter_`) and assignment to the immutables / setter slots, the constructor runs the genesis loop:

1. Validate array-length agreement (revert `GenesisLengthMismatch` on miss).
2. Validate length cap (revert `GenesisOverflow` on miss).
3. Loop `i = 0 .. genesisTokens.length - 1`:
   a. Revert `ZeroAddress` if `genesisTokens[i] == address(0)`.
   b. Revert `BytecodeHashAdmissionDeferred()` if `genesisTypes[i] == AdmissionType.BytecodeHash` (per G-D20 step 6 / G-D9 Bytecode-hash deferral lock).
   c. Revert `DuplicateGenesisToken(genesisTokens[i])` if `admittedClasses[genesisTokens[i]]` already true.
   d. Set `admittedClasses[genesisTokens[i]] = true`.
   e. Set `admissionTypes[genesisTokens[i]] = genesisTypes[i]`.
   f. Emit `GenesisClassAdmitted(genesisTokens[i], genesisTypes[i])`.

Each step's revert before any state mutation means a partial-genesis-loop failure leaves the registry empty (constructor reverts; deployment fails; no state pollution).

**Test invariants (G1.16 unit scope).**

- Constructor with valid arrays: each genesis token reads `isAdmittedClass(token) == true`; each reads `admissionType(token) == expectedType`; each emit captured in order.
- Constructor with `genesisTokens.length != genesisTypes.length`: reverts `GenesisLengthMismatch` with the exact lengths.
- Constructor with `genesisTokens.length == 33`: reverts `GenesisOverflow(33, 32)`.
- Constructor with `genesisTokens.length == 32`: succeeds (cap is inclusive on the equals side; revert is `>` not `>=`).
- Constructor with `address(0)` at any position: reverts `ZeroAddress` at that iteration; prior assignments not observable (constructor fully reverts).
- Constructor with two identical tokens: reverts `DuplicateGenesisToken` at the second occurrence; prior assignment not observable.
- Constructor with empty arrays: succeeds; `admittedClasses` mapping empty; no `GenesisClassAdmitted` emits.
- Constructor with `genesisTypes[i] == AdmissionType.BytecodeHash` at any position: reverts `BytecodeHashAdmissionDeferred()`; prior assignments not observable (per G-D20 step 6 / G-D9 Bytecode-hash deferral lock).

**Cross-references.** G-D9 (genesis-seeding Option a-prime amendment, original commit; G1.13-pre-B Bytecode-hash deferral lock paragraph cross-references this section's step 6 and "Subsequent surface added at G1.13"). G1.11 (storage scaffold at `061d967` — supplemented at G1.12-pre-C with the five items above). G1.12 (constructor body consumes the genesis arrays per the locked discipline). G1.12-pre-C (mechanical scaffold supplement landing the five items). G1.13 (constructor genesis-loop step 6 guard + new `BytecodeHashAdmissionDeferred()` error declaration + L57 struct Natspec correction land here per G-D9 Bytecode-hash deferral lock). G1.16 (unit-test invariants targeting each constructor revert path, including the BytecodeHash genesis rejection invariant added at G1.13-pre-B).

---

## G-D21 — `SwapAndDepositToBodensee` two-entry-point split: strict-equality `swapAndDeposit` + variable-amount `donate` (G1.13 typed-domain unblock)

Resolves the typed-domain ambiguity surfaced at G1.13 between G-D12's strict-equality `swapAndDeposit(IERC20, uint256)` (locked at the per-token fee constants `FEE_SVZCHF = 100e18` / `FEE_SUSDS = 125e18` for the anti-spam fee path #1) and G-D9 / G-D19's `PROPOSAL_BOND_SVZCHF = 1_000e18` (10× anchor; vault-class admission bond, path #2). A direct `helper.swapAndDeposit(svZCHF, PROPOSAL_BOND_SVZCHF)` call from `VaultClassRegistry` would revert `IncorrectAmount(1_000e18, 100e18)` against the strict-equality check at `src/gauge/SwapAndDepositToBodensee.sol:252-255`. The lock generalizes to three additional Stage K / Stage O deposit paths (#3 F-12 gauge challenge variable formula per OQ-8, #4 composition challenge `1_000e18` per Constitution §xxvii, #5 fee proposal `1_000e18` per same) which would each hit the same wall — one helper amendment serves all four non-anti-spam paths.

**Five deposit purposes, three value levels.** All five route to der Bodensee via DONATION; no burn, no treasury, no LP residual.

| # | Purpose | Stage | Trigger | Magnitude | Currency |
|---|---|---|---|---|---|
| 1 | `activateGauge` anti-spam fee | G | permissionless per pool | `FEE_SVZCHF` (100e18) / `FEE_SUSDS` (125e18) | svZCHF or sUSDS (G-D12 strict pair) |
| 2 | `proposeVaultClass` admission bond | G | permissionless per ERC-4626 class | `PROPOSAL_BOND_SVZCHF` (1_000e18, 10× #1 per G-D19) | svZCHF only (G-D9 lock) |
| 3 | F-12 gauge challenge deposit | K | governance proposal vs. existing gauge | variable: `max(10-BTC-CHF, 1M CHF × √((1−p_tvl)(1−p_eff)))` per OQ-8 | svZCHF or sUSDS (challenger choice per OQ-8) |
| 4 | Composition challenge deposit | K/O | governance proposal vs. Miliarium slot | `1_000e18` per Constitution §xxvii | svZCHF or sUSDS |
| 5 | Fee proposal deposit | K | governance proposal vs. swap-fee setting | `1_000e18` per Constitution §xxvii | svZCHF or sUSDS |

Path #1 is permissionless (Stage G public on-ramp); paths #2–#5 are gated by upstream contract logic — registry's bond constant for #2, governance's vote-and-deposit logic for #3 / #4 / #5.

**Locked pattern — two outer entry points on `SwapAndDepositToBodensee`, one shared internal callback.**

The helper exposes two outer entry points sharing the same internal `_swapAndDepositCallback` and the same four transient slots (`_EXECUTING_SLOT`, `_PENDING_PAY_TOKEN_SLOT`, `_PENDING_AMOUNT_SLOT`, `_ORIGINAL_CALLER_SLOT`). The split is purely at the validation layer:

- `swapAndDeposit(IERC20 payToken, uint256 amount)` — **unchanged from G-D12 spec lock**. `onlyAuthorizedCaller` gate against the existing `vaultClassRegistry` / `gaugeRegistry` storage slots per F-D23 pattern; strict equality `amount == _requiredAmount(payToken)` at `FEE_SVZCHF` / `FEE_SUSDS`; serves path #1 only. Audit story preserved verbatim — source-level identity for this entry point is structurally stable across the G-D21 amendment, and the strict-equality path's audit lineage carries forward unchanged. The helper's overall deployed artifact does change at G-D21 (new `donate` function, new storage slots, new errors and events) — the continuity claim is scoped to the source text and review trail of `swapAndDeposit` itself, not to whole-contract bytecode.
- `donate(IERC20 payToken, uint256 amount)` — **new entry point added at G-D21**. `onlyAuthorizedDonator` gate against the new `donateAuthorizer` + `authorizedDonators` storage (see Authorization model below); pay-token allowlist enforced (`payToken == _svZchf || payToken == _sUsds`, else revert `InvalidPayToken`); `amount > 0` check (revert `ZeroAmount` on miss); reentrancy guard via shared `_EXECUTING_SLOT`; **no magnitude validation**. Variable `amount` flows directly into `_PENDING_AMOUNT_SLOT` and reaches the callback unchecked at the helper layer. Serves paths #2–#5.

Both entry points fan into the same callback, which executes the locked 9-step DONATION flow per G-D12 callback narrative + G-D14 transient-storage discipline + G-D18 reserve-read selector lock. The post-callback `postReserve == preReserve + amount` invariant holds identically for both entry points — DONATION accepts arbitrary `amount` from the caller's pre-pushed balance, and the strict-equality vs variable-amount distinction is upstream of the callback's reserve-delta math.

**Authorization model.**

The `donate` path's gate uses a separate authorization surface from `swapAndDeposit`'s. The model **diverges from F-D23 / G-D9 G1.12-pre-D one-shot setter pattern by design** — Stage K must be able to add `AureumGovernance` to the donator list and rotate authorizer rights from the multisig to governance without a helper redeploy. One-shot would block legitimate rotation.

Storage:
- `address public donateAuthorizer` — set at construction to the deploy multisig (Stages A–K Authorizer Safe per OQ-10); mutated post-deploy via `setDonateAuthorizer(newAuthorizer)` gated to current authorizer. **Multi-shot, not one-shot** — real-to-real authorizer rotation has the same gravity as OQ-10's Authorizer migration.
- `mapping(address => bool) public authorizedDonators` — runtime-mutable allowlist of contracts that may call `donate`. Empty at construction; populated post-deploy via `addAuthorizedDonator(donator)`. EOA exclusion is operational discipline owed by the authorizer (review duty on each addition), not an on-chain check — donator should be a contract that enforces its own bond math upstream, and the audit story for variable-amount routing rests on the authorizer's review of each addition rather than a `code.length` guard. The matching `addAuthorizedDonator` mutator below deliberately omits a `code.length > 0` check; the consistency of these two statements is load-bearing.

Mutators (gated to `donateAuthorizer`; revert `OnlyDonateAuthorizer()` on caller miss):
- `setDonateAuthorizer(address newAuthorizer) external` — transfers authorizer rights. Body: gate, `ZeroAddress()` check on the new binding, assign, emit `DonateAuthorizerSet(previous, current)`. Used at Stage K when the multisig hands off to `AureumGovernance`.
- `addAuthorizedDonator(address donator) external` — adds `donator` to the allowlist. Body: gate, `ZeroAddress()` check, `DonatorAlreadyAuthorized(donator)` check, set mapping `true`, emit `AuthorizedDonatorAdded(donator)`. **Does not** verify that `donator` is a contract (no `code.length > 0` check) — the authorizer takes responsibility for review, mirroring how `vaultClassRegistry` / `gaugeRegistry` slots are populated without on-chain bytecode verification.
- `removeAuthorizedDonator(address donator) external` — removes from allowlist. Body: gate, `DonatorNotAuthorized(donator)` check, clear mapping, emit `AuthorizedDonatorRemoved(donator)`. Used to revoke rights from a compromised or deprecated donator (e.g., a registry being replaced at Stage R).

Genesis donator (`VaultClassRegistry` for path #2) is added via a single `addAuthorizedDonator(registryAddress)` call from the multisig **after** the registry is deployed. One extra deploy-script line; accepted cost vs. maintaining a constructor-genesis-array shortcut alongside the runtime mutator (two onboarding paths is more reviewer load than one).

Stage K wiring sequence: deploy `AureumGovernance` → multisig calls `helper.addAuthorizedDonator(governanceAddress)` (governance gets `donate` rights while multisig is still authorizer) → multisig calls `helper.setDonateAuthorizer(governanceAddress)` (multisig retires; governance becomes authorizer). Order matters: governance must have `donate` rights before paths #3 / #4 / #5 can land their first deposits, and the multisig must remain authorizer until that wiring completes. Documented in the Stage K deploy playbook (forward reference at Stage K plan).

**Trust boundary — load-bearing.**

The `donate` path **trusts the upstream caller's bond math entirely**. The helper validates only: (a) `msg.sender ∈ authorizedDonators`, (b) `payToken ∈ {_svZchf, _sUsds}`, (c) `amount > 0`, (d) reentrancy guard not active. **No magnitude check.** If a buggy or compromised authorized donator passes a wrong `amount`, the helper donates that amount; the protocol-layer mistake is on the upstream, not the helper.

This is structurally identical to how the existing `swapAndDeposit` path "trusts" the Vault to handle settle / DONATION correctly — narrow, well-audited boundary, defense-in-depth via the post-callback reserve-delta invariant. The helper's responsibility ends at "the right amount of `payToken` was donated to Bodensee"; whether that amount was the *correct* amount per protocol semantics is the caller's responsibility.

The audit story for `donate` therefore reduces to two checks: (1) the authorization surface is sound — only contracts whose bond math has been audited may sit on `authorizedDonators` (Stage G adds `VaultClassRegistry`; Stage K adds `AureumGovernance`); (2) the 9-step callback flow is correct — already audited at G1.6, untouched at G-D21. The authorization grant is therefore the load-bearing review surface; the absence of magnitude validation in `donate` is intentional and correct.

**Reuse of the 9-step callback — outer-only amendment, no callback change.**

`_swapAndDepositCallback(IERC20 payToken, uint256 amount)` reads `amount` from its argument (G-D12 callback step 1: payload sender / payload contents check), which is sourced from `_PENDING_AMOUNT_SLOT`. The callback is blind to whether the slot was populated by `swapAndDeposit`'s strict-equality validator or by `donate`'s pass-through. The four transient slots are populated identically before `_vault.unlock` regardless of entry point; the reentrancy guard fires across entry points (a `donate` call cannot re-enter `swapAndDeposit` mid-flight, and vice versa); the post-callback reserve-delta strict equality `postReserve == preReserve + amount` holds for any `amount > 0`.

Implication: G-D21 is an **outer-only** amendment to the helper. The internal callback, the four transient slots, the Bodensee accounting story (G-D14 transient lock + G-D18 reserve selector), and the V3 unlock-and-DONATION flow are untouched. `forge build` against the existing helper test suite must remain green for `swapAndDeposit`-path tests; new `donate`-path tests land at the helper test amendment beat (G1.7-bis, forward reference).

**Deploy playbook (one paragraph; mainnet + fork-test setUp).**

Mainnet sequence: (1) Deploy `SwapAndDepositToBodensee` with `donateAuthorizer` set to the Stage A–K multisig per OQ-10. (2) Deploy `VaultClassRegistry` (G1.13 source). (3) Multisig calls `helper.addAuthorizedDonator(registryAddress)` before any `proposeVaultClass` call lands on the registry. Steps (2) and (3) are sequenced — the registry exists but cannot route bonds until step (3) completes, and any pre-step-(3) `proposeVaultClass` call reverts at the helper's `OnlyAuthorizedDonator` gate. Stage K extension: deploy `AureumGovernance`; multisig calls `addAuthorizedDonator(governanceAddress)`; multisig calls `setDonateAuthorizer(governanceAddress)`; multisig retires from this surface. Fork-test setUp follows the same sequence — `MockSwapAndDepositToBodensee` substitutes for the helper at unit-test scope; full mainnet helper at fork-test scope with the multisig role played by the test contract.

**Rejected alternatives.**

(A) Loop-N-calls inside `proposeVaultClass`: registry calls `helper.swapAndDeposit(svZCHF, FEE_SVZCHF)` ten times in a `for` loop. Honors all G-D12 + G-D19 locks but local to path #2 only — does not generalize to path #3 (F-12 variable formula has no integer-multiple decomposition against `FEE_SVZCHF`). 10× the unlock+settle+DONATION gas cost (~1.6M gas just for bond routing); rejected as gas-prohibitive at protocol level.

(D) Collapse `PROPOSAL_BOND_SVZCHF` to `FEE_SVZCHF = 100e18`: drops the G-D19 Tunable 1 10× anchor. Cleanest helper-compatibility but undermines the "class admission is higher-stakes than per-pool activation" rationale at G-D19 / NOTES L476. Rejected as design-rationale regression; also still does not solve paths #3 / #4 / #5.

(E1) Helper variant with strict-equality bypass branch on the existing `swapAndDeposit`: adds `if (msg.sender ∈ trustedCallers) skip equality check; else enforce` to the existing function. Rejected because it widens the audit surface of the deployed-and-audited #1 path; reviewers must now reason about both branches in the same function. The two-entry-point split (G-D21) keeps `swapAndDeposit` source-identical (its audit lineage carries forward) and isolates the new validation discipline to a separate function.

(E2) `donate` accepts arbitrary `payToken`: no allowlist. Rejected because the svZCHF / sUSDS allowlist is part of the helper's audit story (closes fee-on-transfer / rebasing-token / malicious-token surface to zero per G-D12); the `donate` path inherits the same allowlist for the same reason. Variable `amount` does not imply variable `payToken`.

**Cross-references.** G-D9 (vault-class proposal bond — mechanism narrative + cross-references amended at this commit to specify `helper.donate(svZCHF, PROPOSAL_BOND_SVZCHF)` routing). G-D12 (anti-spam fee strict-equality lock — section closure amended at this commit with the two-entry-point split note). G-D14 (transient-storage discipline — applies identically to both entry points). G-D18 (reserve-read selector — applies identically to both entry points). G-D19 Tunable 1 (`PROPOSAL_BOND_SVZCHF = 1_000e18` routing-path clarification amended at this commit). PLAN G1.13 (`proposeVaultClass` body — amended at this commit to call `helper.donate` directly, single call, no loop). PLAN G1.6-bis / G1.7-bis (helper source + test amendments, next two §8e.1 beats — adds `donate` + authorization mutators + new errors / events; covers `donate`-path invariants). FINDINGS OQ-8 (F-12 gauge challenge variable formula — Stage K consumer of `donate` path #3). Constitution §xxvii (composition / fee proposal deposits at 1_000e18 — Stage K / O consumers of `donate` paths #4 / #5). OQ-10 (governance Safe ↔ Authorizer migration — `donateAuthorizer` follows the same migration pattern at Stage K).

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
| T-I6 | **Revoked is terminal** — `activateGauge(pool)`, `registerGaugeFromComposition(pool)`, `seedFoundingPool(pool)` each revert `AlreadyRevoked` against a Revoked status; no Stage G entrypoint writes `Revoked → Active` (per **G-D17**) |

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

### G10 — Compile-probe typed-domain syntax assumptions before §12 lock

**Surfaced 2026-05-07 at G1.4-pre-E (ahead of the G1.4 §8e.1 scaffold).** G-D14 originally locked transient storage via `bool transient _executing;` etc. — state-variable declarations using the Solidity `transient` storage location keyword. That keyword landed in Solidity 0.8.27/0.8.28 (parser support in 0.8.27; full code generation in 0.8.28, October 2024). Our pinned compiler is **0.8.26** per `foundry.toml` (CLAUDE.md §2: "exact match to Balancer mainnet deployment"), which provides only the EIP-1153 OPCODE primitives (`TLOAD` / `TSTORE`) accessible via inline assembly or library helpers — NOT the high-level keyword. `forge build` against the locked syntax would have failed at the G1.4 verify step.

**Detection path.** Caught at G1.4 §8e.1 drafting time via review of Balancer V3's transient-storage usage pattern: `lib/balancer-v3-monorepo/pkg/vault/contracts/Vault.sol` L96–117 uses `transient` only as a custom Solidity *modifier name* (not the storage-location keyword), and actual transient reads / writes route through `TransientStorageHelpers.sol` + `StorageSlotExtension.sol` — slot-constant + assembly-wrapper pattern (`bytes32` slot derived via `calculateSlot`, `tload()` / `tstore()` extension methods). The `TransientStorageHelpers.sol` file header even acknowledges the temporal gap explicitly: "When Solidity catches up and puts direct support for transient storage in the language, we should be able to get rid of this altogether." The detection was NOT structural — the Balancer survey happened to surface it in time; a more direct detection route is the rule below.

**Default rule for §12 closures involving language-feature claims.** When a NOTES decision (G-D / D-D / E-D / F-D / G-D entry, or any §12 ambiguity-gate amendment) commits the project to a specific Solidity language feature — keyword, type modifier, storage location, contract-level qualifier, opcode, optimizer pragma, EVM-version flag — author a 5–10 line probe contract that exercises the exact syntax under proposal at the project's exact `pragma`, `via_ir`, `optimizer-runs`, and `evm_version` config, and run `forge build` against it BEFORE the §12 amendment closes. The probe lives outside the source tree (e.g. `src/scratch/_probe.sol` gitignored, or written ad-hoc and discarded after compile-test); its sole purpose is to surface compile-time language-feature mismatches before they propagate into NOTES locks and §8e.1 Must-match lines.

**Repair landed at G1.4-pre-E.** G-D14 amended to lock the Balancer assembly-helper pattern (slot constants + `tload()` / `tstore()` via `TransientStorageHelpers` + `StorageSlotExtension`); PLAN L161 + L175 wordings from G1.4-pre-D corrected to match. CLAUDE.md §11 housekeeping bullet G10 lands at G1.4-pre-E2 (a follow-up sub-step) so the bullet can reference G1.4-pre-E1's commit hash. Applies project-wide to any future §12 closure involving Solidity language features.

### G11

`constant` vs `immutable` for slot-derivation identifiers under solc 0.8.26 — surfaced 2026-05-08 at the G1.4 §8e.1 audit (Cursor's keyword divergence from Must match) and corrected at G1.5-pre-A (this sub-step).

**The discrepancy.** G-D14's first lock (commit `161c109`) at L383 + L406 and STAGE_G_PLAN.md L161 specified `bytes32 internal constant _*_SLOT = TransientStorageHelpers.calculateSlot("aureum.swapAndDepositToBodensee", "<varName>")` for the four transient-storage slot identifiers. Solidity 0.8.26 forbids function calls in `constant` initializers — the language reserves `constant` for compile-time-evaluable expressions, and `calculateSlot(string memory, string memory)` is a `pure` function call with `memory` arguments, neither of which is compile-time-evaluable. The only valid keyword for slot IDs derived via this helper is `internal immutable`, which Cursor correctly used at G1.4 source-file landing (commit `2e100cb`). The discrepancy was caught at audit (`grep -cE "^    bytes32 internal constant _[A-Z_]+_SLOT"` returned 0 against an expected 4) and confirmed by `forge build` succeeding under `immutable` — `constant` would have been a compile error.

**Pairing with G10.** G10 captured the same class at a different syntactic site: a NOTES claim that `bool transient _executing;` was a valid state-variable declaration under 0.8.26 (it is not — parser support landed in 0.8.27, codegen in 0.8.28). G11 captures the parallel claim that a `calculateSlot(...)` initializer is a valid `constant` initializer (it is not — `constant` requires compile-time-evaluable expressions, function calls excluded). Both are NOTES claims about Solidity language behavior that would not compile; G10 was caught pre-execution by reading Balancer V3's actual `Vault.sol` pattern, G11 was caught at audit by Cursor's correct keyword choice + `forge build` succeeding under the right keyword.

**Default rule (extends G10).** §12 NOTES claims that pair a Solidity keyword with an initializer expression (`constant <T> X = <expr>`, `immutable <T> X = <expr>`, `<storage-loc> <T> X;`) need the keyword + initializer pair to be checked against the language's constant-expression rules before the amendment closes. The cheapest check is the same compile-probe G10 specifies — a 5–10 line probe contract at the project's exact solc / `via_ir` / optimizer-runs / `evm_version` config and `forge build` before the amendment closes. Audit-time corollary: when a source file lands and Cursor's keyword choice diverges from the §8e.1 Must match, treat the divergence as a soft signal that the Must match was wrong (not the file) and verify against the `forge build` result before flagging — the keyword Cursor chose is often the only one that compiles. Corrective action at this sub-step (G1.5-pre-A): align G-D14 NOTES L383 + L406 and STAGE_G_PLAN.md L161 wording to `bytes32 internal immutable _*_SLOT` so the documented pattern matches the compilable code at `2e100cb`. No CLAUDE.md §11 housekeeping bullet at this commit — G11 is local to Stage G NOTES; cross-stage escalation only if this class repeats at a later stage.

### G12 — `using StorageSlotExtension for *;` required to enable typed-slot chain; `for bytes32;` fails at the second leg

**Surfaced 2026-05-08 at G1.6 audit.** The G1.6 §8e.1 specified `using StorageSlotExtension for bytes32;` as the `using` directive enabling the typed-slot access chain (`_EXECUTING_SLOT.asBoolean().tload()` etc.). Cursor instead wrote `using StorageSlotExtension for *;`. `forge build` succeeded with Cursor's form; `for bytes32;` would have failed at compile time on every `.tload()` / `.tstore()` call in the callback body.

**Root cause.** `StorageSlotExtension.sol` defines two categories of functions: (a) `asBoolean(bytes32) → BooleanSlotType`, `asAddress(bytes32) → AddressSlotType`, `asUint256(bytes32) → Uint256SlotType` — these are attached to `bytes32` (the cast leg); and (b) `tload(BooleanSlotType) → bool`, `tstore(BooleanSlotType, bool)`, `tload(AddressSlotType) → address`, etc. — these are attached to the **typed wrappers**, not to `bytes32`. `using StorageSlotExtension for bytes32;` attaches only category (a). The chain `_SLOT.asBoolean().tload()` first calls `asBoolean()` on `bytes32` (category a, attached ✅) and then calls `.tload()` on `BooleanSlotType` (category b, not attached under `for bytes32;` ❌). `for *;` attaches all library functions to all types — both legs work. The `for bytes32;` form is the spec author's error; Cursor's `for *;` correction compiled correctly and passed audit.

**Default rule.** Any `using LibraryName for T;` directive that enables a **chained** library call — where the first call returns type `R` that is not `T`, and the second call must also be library-enabled on `R` — requires either `for *;` or a separate `using LibraryName for R;`. `for T;` alone only attaches functions whose first argument type is `T`; intermediate return types in the chain are left unresolved. When drafting a §8e.1 `Must match` bullet that specifies a `using` directive for a chained-library-call pattern, check every type in the chain — if any intermediate type is not `T`, the directive must be `for *;` or extended. This check applies to all future `using` directives involving `StorageSlotExtension` or any library whose functions return custom user-defined types.

**Repair.** G-D14 Implementation pattern paragraph amended at G1.6-post-A (this sub-step) to reflect the `for *;` form and correct the `tload`/`tstore` source-attribution. No source-tree change needed — `src/gauge/SwapAndDepositToBodensee.sol` commit `342c057` already carries the correct `using StorageSlotExtension for *;`.

### G13 — Foundry `vm.expectRevert(bytes4)` strict-match for parametric custom errors + in-fork synthetic FoT via `vm.mockCall` on `_vault.getPoolTokenInfo` (G1.8 audit corrections)

**Surfaced 2026-05-08 at G1.8 fork-test audit.** Two lessons surfaced together; both are post-mortem captures against just-verified compile-and-test-truth at commit `75f466c`.

**Lesson A — `vm.expectRevert(bytes4)` strict-matches the full revert data, not just the selector.** The G1.8 §8e.1 originally specified `vm.expectRevert(SwapAndDepositToBodensee.ReserveDeltaMismatch.selector)` for the FoT counterfactual test. Cursor followed the spec literally. The test FAILED with `Error != expected error: ReserveDeltaMismatch(1100000000000000000000 [1.1e21], 1000000000000000000000 [1e21]) != custom error 0xcf1857c4` — the actual revert is exactly the expected `ReserveDeltaMismatch(expected, actual)` with correct param values, but Foundry's `vm.expectRevert(bytes4 selector)` form requires the revert data to be EXACTLY 4 bytes (the bare selector); the actual revert data is 4-byte selector + 64-byte abi-encoded params (`uint256 expected, uint256 actual`), so the comparison fails. Fix at G1.8-fix1: `vm.expectRevert(abi.encodeWithSelector(SwapAndDepositToBodensee.ReserveDeltaMismatch.selector, INIT_SEED + FEE_SVZCHF, INIT_SEED));` — full encoded form including param values matches exact revert data.

**Default rule.** When drafting `vm.expectRevert` for a custom error declared as `error Name(T1, T2, ...)`, use `vm.expectRevert(abi.encodeWithSelector(ContractName.Name.selector, expectedT1, expectedT2, ...))` — NOT `vm.expectRevert(ContractName.Name.selector)` alone. The bare-selector form is correct ONLY for parameterless custom errors (e.g. `ReentrancyGuard()`, `ZeroAmount()`, `SetterAlreadyCalled()`). When drafting §8e.1 `vm.expectRevert` lines for any error with parameters, the §8e.1 author MUST compute or pin the expected param values up-front (constants, or pre-snapshot reads from the test contract) so the `abi.encodeWithSelector` arguments are known at audit time. The exact-match form is preferred over `vm.expectPartialRevert(bytes4)` (selector-only) because it pins the param values, providing stronger evidence the revert path exercises the correct invariant.

**Lesson B — In-fork synthetic FoT counterfactual via `vm.mockCall` on `_vault.getPoolTokenInfo` is cleaner than mocking `payToken.transfer`.** PLAN L185 + NOTES L363 originally specified the FoT counterfactual as "synthetic FoT behaviour injected via `vm.mockCall` on `payToken.transfer` reverts `ReserveDeltaMismatch`". This wording is misleading: mocking `payToken.transfer` to be a no-op (returns `true`, transfers nothing) causes the helper's downstream `_vault.settle(payToken, amount)` call to fail at the Vault layer — `settle` per `IVaultMain.sol` reverts when `hint > actual reserve difference`, so a no-op transfer makes `settle` revert with a Vault-internal error, NOT with the helper's defensive `ReserveDeltaMismatch`. The cleaner approach (implemented at G1.8 commit `75f466c`): install `vm.mockCall(address(vault), abi.encodeWithSelector(IVault.getPoolTokenInfo.selector, bodenseePool), abi.encode(tokens, tokenInfo, balancesRaw, balancesScaled18))` BEFORE the swap, so the Vault's view (as seen by the helper) is FROZEN at the pre-state for BOTH the pre and post snapshot reads inside the callback. The actual `transfer` + `settle` + `addLiquidity` execute against the real Vault unchanged; only the helper's `getPoolTokenInfo` reads are intercepted. The helper's view: `preReserve == postReserve == frozen value`; the helper's expected: `preReserve + amount`; mismatch fires `ReserveDeltaMismatch(preReserve + amount, preReserve)` cleanly.

**Default rule.** In-fork tests of helper-side defensive invariants ("post-state must equal pre-state plus delta") are best exercised by mocking the read the helper uses to verify the invariant — NOT by mocking a downstream side-effect the helper does not directly observe. The frozen-pre-state mock pattern (mock the read to return frozen pre-state; let actual on-chain state move forward; the helper's view diverges from reality; the helper's defensive check fires) is the canonical fork-test approach for any "X equals Y plus delta" invariant. Apply to future helper-defensive fork tests.

**Repair.** PLAN L185 wording and NOTES L363 wording amended at G1.8-post-A (this sub-step) to align with the implemented pattern. Both lessons are local to Stage G NOTES; no CLAUDE.md §11 housekeeping bullet at this commit — cross-stage escalation only if either class repeats at a later stage.

### G14 — solc 0.8.26 rejects `calldata` for constructor parameters; `memory` is the binding location (G1.12 fix-loop)

**Surfaced 2026-05-09 at G1.12 fix-loop.** G-D20 (locked at G1.12-pre-B, commit `1f570fa`) and PLAN G1.12 (rewritten at the same commit) specified `address[] calldata genesisTokens, AdmissionType[] calldata genesisTypes` for the constructor parameter data location, with the L501 rationale ("Calldata location is binding — `memory` would impose extra ABI-decode work without any benefit; the constructor reads each entry once."). The first G1.12 Cursor save (commit `dc5fec2`) used `memory` — Cursor's correct keyword choice diverging from the Must match (same audit-time signal pattern as G11). The G1.12-fix prompt forced `calldata` per the Must-match spec; `forge build` failed with `Error (6651): Data location must be "storage" or "memory" for constructor parameter, but "calldata" was given.` G1.12-fix2 reverted both parameters to `memory` and the build went green. Final file state at `dc5fec2` is identical to what Cursor originally saved.

**Root cause.** Solidity 0.8.x permits `calldata` as a parameter data location ONLY for `external` (and certain `internal` / `public`) function parameters — NOT for constructor parameters. The restriction holds across the supported version range; `via_ir = true` does not unlock it. Constructor parameter data flows from the deployment init-code into the running contract's runtime — there is no `CALLDATA` region in the EVM's deployment-init calling convention. The compiler enforces this with Error 6651.

**Default rule (extends G10 + G11).** The G10 compile-probe rule covered language-feature claims (`transient` keyword in G10, `constant` initializers with function-call expressions in G11). G14 extends the rule to **parameter data location** for constructor signatures: any §12 NOTES closure that asserts `calldata`, `memory`, or `storage` on a constructor parameter must compile-probe the exact signature at the project's pinned solc / `via_ir` / optimizer-runs / `evm_version` config before the amendment closes. For constructor parameters specifically, the answer is fixed across all supported configs: **always `memory`** (never `calldata`).

**Audit-time corollary (extends G11).** When Cursor's keyword choice diverges from the §8e.1 Must match AND `forge build` succeeds with Cursor's choice, the divergence is a soft signal that the Must match was wrong, not the file. G11 captured the `constant` → `immutable` divergence at G1.5-pre-A; G14 captures the `calldata` → `memory` divergence at G1.12-fix-loop. Pattern: **the keyword Cursor chose is often the only one that compiles** — verify against `forge build` before issuing a fix prompt.

**Repair landed at G1.12-post-A (this sub-step).** G-D9 L135 + L137, G-D20 L488 + L490-L499 + L501 + L505 + L509, and PLAN L221 amended to use `memory` everywhere a constructor parameter data location is asserted; rationale paragraph at NOTES L501 rewritten to acknowledge the solc constraint; prose mentions of "calldata arrays" updated to "genesis arrays" for consistency. CLAUDE.md §11 housekeeping bullet G14 lands at G1.12-post-B (a Sonnet-tier follow-up sub-step) so the bullet can reference G1.12-post-A's commit hash.

### G15 — Scaffold NatSpec interface-promise drift: `is IVaultClassRegistry` + view bridges promised at G1.12+ but unlanded through G1.15 (G1.16 ambiguity-gate)

**Surfaced 2026-05-10 at G1.16 design pre-flight (this Opus beat).** The G1.11 scaffold's top-of-contract NatSpec at `src/gauge/VaultClassRegistry.sol` L13–L15 says: "Constructor body, propose / veto / finalize / revoke functions, setters, and `IVaultClassRegistry` inheritance + view bridges land at G1.12+; this scaffold ships only types / state / immutables / constants / errors / events surface per G-D9 + G-D19 (G1.9 tunables lock)." G1.12 (constructor + setters), G1.13 (`proposeVaultClass`), G1.14 (`vetoProposal` + `finalizeProposal`), and G1.15 (`onlyGovernance` modifier + `revokeVaultClass`) each landed their named scope cleanly — but **none added `is IVaultClassRegistry` to the contract declaration, and none added explicit `isAdmittedClass(address)` / `admissionType(address)` view bridges**. Only the auto-generated public mapping getters `admittedClasses(address) → bool` and `admissionTypes(address) → AdmissionType` exist, with **different ABI names** from the published interface.

**Why it matters.** PLAN G1.16 at L257 explicitly uses `isAdmittedClass(genesisToken)` for the genesis-seed assertion; PLAN G2.3 at L293 hard-requires the typed call `IVaultClassRegistry(vaultClassRegistry).isAdmittedClass(...)` from `GaugeEligibility._compute52PctNumerator` — a typed-interface call that fails to compile against a concrete contract that does not implement the interface. Without inheritance + bridges, Stage G does not compile end-to-end at G2.3 entry; G1.16 tests would also need to use mapping-getter names that drift from the published interface, fragmenting the surface the auditor walks.

**Root cause.** Scaffold "X lands at sub-step N+k" NatSpec is a forward promise without a forcing function. Each G1.x §8e.1 Must match was scoped to its named function or modifier, not to the cumulative scaffold promise. The interface inheritance + view bridges fell into the gap between "promised at G1.12+" and "explicitly named in any G1.x sub-step." — PLAN sub-row layout at L127 says "G1.10–G1.16 deliver the registry (interface + scaffold + constructor + propose / veto / revoke + unit tests)" — view bridges are not enumerated, so no sub-step claimed them; the promise survived four sub-step audits unhit.

**Default rule (extends §12 ambiguity-gate; mechanical addition to the audit cycle).** Scaffold NatSpec lines of the form "X / Y / Z land at sub-step N+k" are a checklist, not prose. At the §8e.1 prompt for the close-of-family sub-step (G1.16 here), the `Must match` block treats the scaffold-promise items as part of the contract surface to verify against the file, not as comment text to ignore. A scaffold-promise that survives multiple sub-steps without a hit is a soft signal that the promise needs a dedicated landing sub-step before close-of-family. The cure: enumerate scaffold promises explicitly in the close-of-family `Must match`; if any item has no implementing surface in the file at audit time, escalate to a `*-post` source-only sub-step before the close-of-family lands.

**Repair landed at G1.15-post (this NOTES amendment + a source-only sub-step + a PLAN amendment).** G1.15-post-A (this entry) records the gap and the rule. G1.15-post-B inserts a one-paragraph sub-step row in `STAGE_G_PLAN.md` between G1.15 and G1.16. G1.15-post (the source change) adds `is IVaultClassRegistry` to the contract declaration, two thin view bridges (`function isAdmittedClass(address token) external view returns (bool) { return admittedClasses[token]; }` and `function admissionType(address token) external view returns (IVaultClassRegistry.AdmissionType) { return admissionTypes[token]; }`), and a NatSpec correction at L13–15 acknowledging that inheritance + bridges have now landed (no longer "land at G1.12+"). `CLAUDE.md` §11 housekeeping bullet G15 lands as a Sonnet-tier follow-up after the source change so the bullet can reference the commit hash.
