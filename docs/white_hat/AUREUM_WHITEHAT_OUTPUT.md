# Aureum White-Hat Output — Findings Ledger

The single, append-only record of every white-hat finding across all passes.
One row per finding. Driven by `AUREUM_WHITEHAT_PROCESS.md`; every step's
attestation either adds rows here or records "no finding" in the coverage table
below.

Append-only: never delete a row. A finding that turns out to be a false
positive is marked `False-positive` in **Status**, with the reason in
**Explanation** — the row stays as a record that the surface was checked.

---

## Column legend

| Column | Meaning |
|---|---|
| **ID** | `F-NN`, monotonic across the whole project (never reused). |
| **Date** | ISO date the finding was raised (`YYYY-MM-DD`). |
| **Stage/Step** | The white-hat step that surfaced it, e.g. `WI.3`. "Stage that figured it out." |
| **File** | Contract path, e.g. `src/token/AuMM.sol`. |
| **Routine** | Function / modifier / library routine where the issue lives. |
| **Surface** | Catalog ID `S0`–`S12` (see process doc §7). |
| **Severity** | `Critical` / `High` / `Medium` / `Low` / `Info`. |
| **Confidence** | `Confirmed` (full PoC) / `Suspected` (needs PoC) / `Theoretical`. |
| **Issue** | One-line statement of the problem. |
| **Explanation** | The attack path / mechanism, and — once resolved — the resolution reasoning. |
| **Status** | `Open` / `Confirmed` / `Fixed` / `Accepted-risk` / `False-positive`. |
| **Fix** | Commit hash of the fix (or `—`), plus byte-identity note if the fix touches the substrate seam. |
| **PoC** | Path to the Foundry test that proves/kills it, e.g. `test/whitehat/F07_emaDonation.t.sol`. |

### Status lifecycle
```
Open ─▶ Confirmed ─▶ Fixed
  │          │
  └─▶ False-positive   └─▶ Accepted-risk (documented, no code change)
```
A `Suspected` finding stays **Open** until a PoC moves it to **Confirmed** or
**False-positive**. Nothing reaches **Fixed** without both a PoC and a fix
commit.

---

## Findings table

| ID | Date | Stage/Step | File | Routine | Surface | Sev | Conf | Issue | Explanation | Status | Fix | PoC |
|----|------|-----------|------|---------|---------|-----|------|-------|-------------|--------|-----|-----|
| F-01 | 2026-06-11 | WK.10 | `src/governance/AureumGovernance.sol` | `_voteSucceeded` / `_createProposal` / `castVote` | S9 | Medium | Confirmed | Quorum denominator is the propose-time `VOTING_WEIGHT.totalSupply()` snapshot (L201/L204→L289) while `forVotes`/`againstVotes` accrue at vote-time (`poke`+`governanceWeight`, L257-258); turnout can exceed 100% of snapshot, so the 20% quorum (`QUORUM_BPS`) gates against a stale, attacker-shrinkable base, not true eligible weight. | Root cause: `VotingWeight._totalQualifiedWeight` is a lazy poke-accumulator (VotingWeight L95-96/L115-120) excluding never-poked holders; the proposer is not poked in `_createProposal` (L196-206) but self-pokes in `castVote` (L257), so their weight is absent from the denominator yet present in the numerator. Effective quorum = 20% of poked weight; at `snapshot==0` it is vacuous. A single qualified holder unilaterally passes gauge revoke / fee change (simple majority) and composition swap (2/3). Bounded by the 14-day qualification cliff (VotingWeight L137, no flash weight), the non-refundable 1,000 svZCHF deposit, the ~16-day vote+timelock contest window (one larger honest against-vote defeats it), permissionless defensive poking, and the WK.8 bounded blast radius (no theft, reversible). Sharpest in early/thin-participation life. Fix: read the quorum denominator at tally-time `endBlock` (all self-poked voters then included → turnout ≤ 100%), or Governor-style historical weight checkpoints. Intent (I-D17 veto-denominator reuse) confirmed at WK.13. | Confirmed | — | `test/whitehat/F01_quorumSnapshotTiming.t.sol` |
|    |      |           |      |         |         |     |      |       |             |        |     |     |

> Add new rows at the bottom. Keep **ID** monotonic. Pad short tables with the
> empty template row so the columns stay readable in plain text.

---

## Coverage / attestation roll-up

One row per white-hat **pass** (per build stage). This is where "no finding"
lives — it records that a surface was checked and came back clean, so silence is
never mistaken for absence of review. Surfaces are `S0`–`S12`; mark each
`✓` (checked, clean), a finding ID (e.g. `F-07`), `n/a` (contract doesn't expose
it), or `—` (deferred — explain in Notes).

| Pass | Date | Scope (diff base) | Contracts | S1 | S2 | S3 | S4 | S5 | S6 | S7 | S8 | S9 | S10 | S11 | S12 | Notes |
|------|------|-------------------|-----------|----|----|----|----|----|----|----|----|----|-----|-----|-----|-------|
| WI | 2026-00-00 | `stage-H-complete..HEAD` | `AuMM.sol`, CCB engine | | | | n/a | n/a | | | | n/a | | n/a | | _[example — replace]_ |
|    |      |                   |           |    |    |    |    |    |    |    |    |    |     |     |     |       |

---

## WK pass — Stage K governance handoff · attestation log
> Per-step white-hat attestations for the WK pass (Stage K). Append one block per step as it closes. The coverage roll-up row above is filled at the WK.19 close-out per process §10/§12. A "no finding" step records an attestation here, not an `F-NN` row — the findings table gains a row only when a real finding lands.
- **Pass:** WK · **Scope:** `git diff stage-j-complete..HEAD` (`63471f9`, Stage K governance handoff) · **Opened:** 2026-06-11
- **Auditor model:** Fable 5 (`claude-fable-5`) — Aureum white-hat debug sprint
- **Status:** in progress (WK.1–WK.10 of WK.1–WK.19 closed; first finding F-01 raised + PoC-confirmed at WK.10)
**WK.1 · S1 supply/mint integrity · `src/token/AuMMMinterRouter.sol` — NO FINDING.**
- WK.1 S1: NO FINDING | checked: single mint path (`mintFor` L96-100); cap-not-circumvented (AuMM `mint` L114 ceiling runs on every forward; boundary-tested at cap / cap+1, test L75-87); INV-1 cumulative ceiling (no-burn confirmed AuMM L15); INV-6 two-layer minter gate (AuMM L113 + router L97); reentrancy (router has zero mutable state, AuMM has no transfer hooks); no era/overflow surface in router | could-not-assess: upstream `amount` computation (→WK.3 distributor, WK.5 channel); deploy-time `setMinter` handoff (→WK.17).
- Observation — the cap is an "ever-minted" ceiling only because AuMM has no burn path (no ERC20Burnable, AuMM L15); re-derive INV-1 if any future stage adds burn to AuMM.
- Observation — `mintFor` does not guard `recipient != address(0)`; relies on OZ `_mint` zero-receiver revert downstream (defense-in-depth, not a defect).
- Harness — `test/unit/AuMMMinterRouter.t.sol` 10/10 green.
**WK.2 · S8 access control & privilege · `src/token/AuMMMinterRouter.sol` — NO FINDING.**
- WK.2 S8: NO FINDING | checked: allowlist bypass (exact `msg.sender` equality on two immutables L97 — no `tx.origin`, no signature/permit); immutability (`AUMM`/`BOOTSTRAP_CHANNEL`/`EMISSION_DISTRIBUTOR` `immutable` L27/36/45, ctor-set + zero-checked L77-83, assigned nowhere else in repo); no escalation surface (`mintFor` is the sole function — no fallback/receive/delegatecall/selfdestruct/assembly/owner/admin/setter); governance cannot widen the allowlist or re-point mint (no governance-callable surface); permanent-minter lock (AuMM `_minterAdmin` zeroed L104, router has no re-delegation) | could-not-assess: deploy-baked consumer-address correctness (→WK.17 / S10); consumer-side `setMintRouter` binding (→WK.4 / WK.6).
- Observation (design property, accepted per locked architecture CLAUDE.md §1/§2) — the router is an irrevocable minter with no admin / pause / upgrade / kill-switch, consistent with the no-owner fair-launch design. Consequence: no runtime backstop halts emission if a consumer is later found exploitable, so consumer correctness (WK.3–WK.6) is load-bearing because nothing can revoke the router post-deploy. Not a finding; conscious risk-acceptance.
- Observation (scope boundary) — the router does not constrain `recipient`; recipient authority is fully delegated to the two consumers. Router S8 cleanliness does not extend to recipient-integrity (→WK.4 / WK.6).
**WK.3 · S1 supply/mint integrity · `src/emission/EmissionDistributor.sol` (`claim` mint path via router) — NO FINDING (K-diff surface).**
- WK.3 S1: NO FINDING (K-diff surface) | checked: sole mint site `claim` L535 `mintRouter.mintFor` → router → AuMM cap L114 (router-wiring faithful, cap preserved); CEI effects L532-533 precede interaction L535 (reentrant `claim` self-nullifies to amount=0 via the L528-529 zero-skip); `MintRouterNotSet` guard L534 strictly more restrictive than pre-K; `setMintRouter` one-shot + `onlyGovernance` L224-229 (mis-bind = liveness DoS, not inflation — bounded by AuMM's one-shot minter); differential INV-1/INV-6 preserved vs `stage-j-complete` | could-not-assess: INV-2 schedule conservation (see next line); deploy mintRouter/minter wiring order (→WK.17); hostile-router binding (→WK.4).
- Observation (highest-value carry-forward) — INV-2 (cumulative emission ≤ 21M by schedule construction) is UNAUDITED and UNIMPLEMENTED: no `ReferenceEmission` / `cumulativeAt` harness exists under `test/`, and the F-0/F-3/F-7 schedule math (`_accrueGlobal` L357, `_lpTrancheIntegral` L335, `_phaseAwareBody` L283, `blockEmissionRate`) is Stage-H code outside the K diff, never white-hatted. The 21M cap (AuMM L114) is a hard backstop on every mint, so the failure mode is a claims-revert liveness cliff (`SupplyCapExceeded` at cumulative 21M), not silent inflation. Recommend a dedicated back-fill WH-H pass (or the Stage P sweep) that builds the INV-2 independent reference-emission harness.
- Observation — AuMM.t.sol implements INV-1 (`invariant_totalSupply_neverExceedsCap` L265) and INV-6 (`invariant_mint_revertsFromNonMinter` L269) against `AuMM.mint` in isolation only — not through the distributor accrual flow.
- Harness — `test/unit/EmissionDistributor.t.sol` + `test/unit/AuMMDistributorIntegration.t.sol` 110/110 green (incl. 4 `setMintRouter` one-shot tests + zero-recipient revert).
**WK.4 · S8 access control & privilege · `src/emission/EmissionDistributor.sol` — NO FINDING (K-diff surface).**
- WK.4 S8: NO FINDING (K-diff surface) | checked: K-added `setMintRouter` onlyGovernance + one-shot + ZeroAddress L224-229 (locks mint-routing topology post-bind, adds no new privilege); `claim` permissionless but mints only caller's own accrued (user=msg.sender L526) — no force-mint to arbitrary recipient; `_accrueGlobal` permissionless poke advances accumulators only (no mint); recorder gate `onlyAuMTContract` L176-179 + one-shot governance binding `setAuMTContractForPool` L201-206; emission inflation needs bound recorder + independent gauge approval (`recordScore` L434) + 21M cap (defense-in-depth); uninitialized slots fail-safe to revert; one-shot `setMintRouter` / `setAuMTContractForPool` survive a later-compromised governance | could-not-assess: deploy binding correctness (→WK.17); cross-authority collusion (→Stage P).
- Observation (carry-forward — Stage-H/I, not K-touched, never white-hatted → WH-H/WH-I) — `setGovernanceContract` L188-193 is single-step mutable (no Ownable2Step); a wrong-address handoff bricks every `onlyGovernance` setter irreversibly (deploy-tested → WK.17; consider a two-step transfer).
- Observation (carry-forward) — `setIncendiaryRegistry` L213-217 is mutable + zero-permitted + no try/catch; a hostile or reverting registry DoSes accrual (deliberately conservative per H-D29, but a governance-mutable lever over emission liveness).
- Observation — recorder LP-inflation: the bound AuMT recorder can credit arbitrary `(user, amount)` LP (`recordDeposit` L462); bounded by gauge approval + 21M cap; the residual trust is the one-shot initial binding.
- Harness — S8 access-control tests green within the 110/110 distributor run (`setGovernanceContract` ×3, `setAuMTContractForPool` ×4, `setIncendiaryRegistry` ×3, `setMintRouter` ×4, recorder-gate ×2, `recordScore` gauge-gate ×2).
**WK.5 · S1 supply/mint integrity · `src/emission/BodenseeBootstrapChannel.sol` (bootstrap-flush mint via router) — NO FINDING (K-diff surface).**
- WK.5 S1: NO FINDING (K-diff surface) | checked: sole mint site `distribute` L267 `mintRouter.mintFor` → router → AuMM cap L114 (router-wiring faithful); conservation double-backstop (reserve-delta L307-308 + bptOut==0 L306 + residual balanceOf==0 L276-277 → no stranded mint; atomic rollback on callback failure); reentrancy double-belt (onlyGovernance L261 + CEI pendingAccrual=0 L264 → reentrant `distribute` reverts NoPendingAccrual L263 + `_EXECUTING_SLOT` transient guard L268); AP math bounded + underflow-safe L239-253; single rate snapshot exact (bootstrap window entirely within Era 0); differential INV-1/INV-6 preserved | could-not-assess: INV-2 cross-contract conservation (see observation); real-Vault `distribute` fork path (→WK.18); deploy wiring (→WK.17).
- Observation (highest-value carry-forward — sharper than WK.3) — INV-2 spans TWO mint sources: the channel and the distributor both mint against the same 21M budget, and H-D2 splits them (the distributor's `_lpTrancheIntegral` subtracts the F-0 bodensee share and hands that leg to this channel). Whether the hand-off conserves (no overlap → double-mint, no gap) is a CROSS-CONTRACT seam neither WK.3 nor WK.5 can settle in isolation. Still unaudited, no `ReferenceEmission` harness. The 21M cap bounds total emission (no infinite inflation); a split error would misallocate LP-vs-Bodensee emission against the F-0 spec. Recommend the WH-H back-fill / Stage P sweep build an INV-2 harness summing channel + distributor mints against an independent reference.
- Harness — `test/unit/BodenseeBootstrapChannel.t.sol` 34/34 green (incl. `setMintRouter` ×4, MintRouterNotSet, Reentrant, HelperBalanceNonZero, ReserveDeltaMismatch, BptMintedOnDonation, CallbackPayloadMismatch, NoPendingAccrual, happy-path, 8 accrue/AP tests).
**WK.6 · S2 fee/emission-routing conservation · `src/emission/BodenseeBootstrapChannel.sol` — NO FINDING (K-diff surface).**
- WK.6 S2: NO FINDING (K-diff surface) | checked: destination immutable (`BODENSEE_POOL` L28 + `_aummIndex` L34, ctor-set L137/L155, no setBodenseePool setter anywhere); single egress (only `safeTransfer` L292 → Vault; no other transfer/withdraw/sweep/rescue/call/selfdestruct); single donation target (`addLiquidity` pool=BODENSEE_POOL L298); 1:1 conservation chain pendingAccrual→mint→donate, reserve+=amount L308, no BPT skim L306, residual==0 L276-277 (INV-3 nothing-stuck holds); no creator fee (`totalDistributed` L55 view-only) | could-not-assess: real-Vault DONATION fork mechanics (→WK.18; asserts enforce conservation regardless); swap-fee routing (Stage D, not K-touched) → WH-D back-fill.
- Observation — WK.6 attests the emission-donation channel's conservation only; the protocol's primary S2 surface (the 50% swap-fee → Bodensee path in `AureumProtocolFeeController` / `AureumFeeRoutingHook`, Stage D) is not in the K diff and is a WH-D back-fill item.
- Harness — conservation tests green within the 34/34 channel run (HelperBalanceNonZero, ReserveDeltaMismatch, BptMintedOnDonation, Distribute happy-path).
**WK.7 · S8 access control & privilege · `src/governance/AureumGovernanceAuthorizer.sol` — NO FINDING.**
- WK.7 S8: NO FINDING | checked: canPerform routing (governance=all + NOT time-boxed L66-68; multisig = emergency-set ∩ window L69; default-deny L72); strict `<` window boundary L69 — no off-by-one (END=deploy+2_628_000 L58; `test_canPerform_windowBoundaryStrict` windowEnd-1 allow / windowEnd deny); emergency set {pauseVault, enableRecoveryMode} L75-77, actionIds `keccak256(abi.encodePacked(bytes32(uint160(vault)), selector))` MATCH Balancer `Authentication.sol:47-51` + `VaultAdmin.sol:77` disambiguator; B-strict containment (multisig can pause / enable-recovery but NOT unpause / disable / setAuthorizer / setFee — only governance reverses; worst case temporary DoS not theft; expires 12mo); 5 immutables, no setters, no widening path; ctor zero-checks L52-54; 12/12 tests green | could-not-assess (SILENT-FAILURE → WK.17): the actionId match holds only if deploy passes `vault_` == the real Vault VaultAdmin is bound to; ctor can only zero-check, not verify — a wrong `vault_` silently breaks the multisig's emergency powers with no deploy revert. WK.17 must assert `vault_` == real Vault + fork-test a multisig pauseVault round-trip through the installed authorizer.
- Observation — `where` is ignored in canPerform; acceptable since governance is where-agnostic by design and the multisig is tightly scoped by vault-specific actionIds.
**WK.8 · S8 access control & privilege · `src/governance/AureumGovernance.sol` — NO FINDING.**
- WK.8 S8: NO FINDING | checked: bounded blast radius — `_executeProposal` L337-350 performs ONLY 3 hardcoded param-validated actions (revokeGauge L339 / atomic slot-swap L341-344 / setStaticSwapFeePercentage-in-bounds L348); NO arbitrary-`(target,calldata)` execute (governance holds full Vault authority via the authorizer but its code only ever calls setStaticSwapFee — the rest is latent/inert); timelock unbypassable (eta set only in `queue` L311 = block+2d always future; execute requires Queued L325 + block>=eta L326; queue one-shot self-guarding L308; no eta setter); one-shot execute + CEI (`executed=true` L327 before `_executeProposal` L328 → ProposalAlreadyExecuted L322); entry points gated (propose×3 deposit-gated L198-199 + target-validated L214/225-227/239-240; castVote window + one-vote + CEI L254-257; queue Succeeded-gated); 5 immutables, no setters, no delegatecall/selfdestruct; 43/43 green | could-not-assess: REGISTRY ACCESS GATES — the vote+timelock is the sole path to revokeGauge / replaceSlot / registerGauge / setStaticSwapFee ONLY IF those callees gate to this governance contract; GaugeRegistry / MiliariumSlotRegistry are Stage G/J (not K-touched), so WK.17 must confirm their governance binding points here + a WH-G/WH-J back-fill must audit the gates.
- Observation — tally math → WK.9; reentrancy in execute external calls → WK.11; deposit economics → WK.10; weight integrity → WK.12-14.
**WK.9 · S3 rounding / invariant precision · `src/governance/AureumGovernance.sol` (vote tally, quorum, F-9 dampening) — NO FINDING on arithmetic; one SUSPECTED item raised.**
- WK.9 S3: NO FINDING on tally arithmetic (ZERO division in the entire contract → no rounding risk; quorum L289 / 2-of-3 supermajority L291 / simple majority L293 all cross-multiplied & integer-exact; deposit L179-183 constant lookup; no overflow for any plausible weight scale; F-9 dampening is upstream in `VOTING_WEIGHT.governanceWeight` L258 → WK.12) | SUSPECTED (first candidate finding of the pass; formal F-NN row deferred to WK.10 post-PoC): the quorum denominator is the propose-time snapshot `snapshotTotalSupply = VOTING_WEIGHT.totalSupply()` L201/L289, while vote-weight numerators accrue at vote-time (poke + governanceWeight L257-258) — diverges from the standard same-block Governor snapshot; permissive direction when global voting supply grows over the ~14d (BLOCKS_PER_EPOCH) window; bounded by VotingWeight's 14d qualification cliff (blocks flash-vote) + 6mo on-ramp slope; MAY be intended per I-D17 veto-denominator semantics.
- Routing — exploitability PoC at WK.10 (S9: a proposer picks a low-supply propose block + late-window high-weight vote; quantify the quorum-gaming gain within the cliff/on-ramp limits); intent/spec confirmation at WK.13 (VotingWeight `totalSupply` / I-D17). Resolves to Confirmed (Low-Med quorum-gaming) or Accepted-risk / False-positive.
- Harness — quorum/tally boundary tests green in the 43/43 run (`test_state_quorumBoundaryStrict`, `supermajorityExactPass`, `belowSupermajorityDefeated`, `gauge_tieDefeated`, `fee_simpleMajorityPass`).
**WK.10 · S9 economic/incentive · `src/governance/AureumGovernance.sol` (quorum-snapshot timing) — FINDING F-01 (Confirmed, Medium).**
- WK.10 S9: FINDING F-01 (resolves the WK.9 SUSPECTED item) | checked: propose-time snapshot `VOTING_WEIGHT.totalSupply()` L201 stored L204 vs vote-time numerator `poke`+`governanceWeight` L257-258 feeding quorum L289; proposer NOT poked in `_createProposal` L196-206 (absent from denominator) but self-pokes in `castVote` L257 (present in numerator) → turnout can exceed 100% of snapshot; root cause `VotingWeight._totalQualifiedWeight` lazy poke-accumulator L115-120 excludes never-poked qualified holders; PoC 4/4 green proves all three proposal types pass under a shrunken/zero snapshot | could-not-assess (→WK.13): whether the propose-time snapshot is intended per I-D17 veto-denominator semantics (`VotingWeight.totalSupply` was specced for `VaultClassRegistry.vetoProposal`, not as an AureumGovernance quorum base) — F-01 stands on behavior regardless; resolution (code fix vs Accepted-risk) follows WK.13.
- Quantified — effective quorum = 20% of poked weight, not eligible weight; leverage ρ = poked/eligible is attacker-influenceable down (don't poke honest holders; poke withdrawn holders down) and structurally excludes the attacker's own weight; at ρ→0 (early protocol) quorum is vacuous and a single 1e18 vote carries.
- Bounds (→ Medium, not High) — 14-day qualification cliff (no flash weight, VotingWeight L137); non-refundable 1,000 svZCHF / 1,250 sUSDS deposit; ~16-day vote+timelock public contest (one larger honest against-vote defeats simple majority, ≥half defeats the 2/3 composition); permissionless poking keeps the accumulator honest; WK.8 bounded blast radius (no theft, governance-reversible). Rises toward High under sustained thin participation.
- Fix direction (resolution commit, post-WK.13) — read the quorum denominator at tally-time `endBlock` so all self-poked voters are included (turnout ≤ 100%), or adopt Governor-style historical weight checkpoints.
- Harness — `test/whitehat/F01_quorumSnapshotTiming.t.sol` 4/4 green: turnoutCanExceedSnapshot (forVotes 10_000e18 > snapshot 100e18), minorityAttackerRevokesGauge (200e18 ≈ 0.4% of true weight revokes a gauge), vacuousQuorumWhenAccumulatorEmpty (snapshot 0), singleVoterClearsCompositionSupermajority (100e18 clears 2/3 + executes the slot swap).
---

## Commit discipline

Follows the project's two-commit pattern:
1. **Finding commit** — adds/updates the row(s) in this ledger.
2. **Resolution commit** — the fix in code, referenced by hash in the **Fix**
   column, plus the row's Status moved to `Fixed`.

The PoC test lands with the fix (a fix without a regression test does not close
a finding). At a stage boundary, the coverage roll-up row for that pass must be
complete before tagging `stage-X-complete`.
