# Aureum White-Hat Audit — Staged Process

Consolidates `AUREUM_ADVERSARIAL_AUDIT_PROMPT.md` (find by reading) and
`AUREUM_EXPLOIT_TEST_PLAYBOOK.md` (confirm by executing) into one reference,
restructured the way the rest of Aureum already works: **a reference layer read
once, and a lean operational layer run one small step at a time.**

This doc is the reference layer — the audit equivalent of `CLAUDE.md`. You do
not paste the whole thing into a working session. You generate a short,
diff-scoped step list per pass, and each step is a tiny prompt that *points*
here.

---

## Standard output table (the ledger)

Every finding from every pass is recorded in **`AUREUM_WHITEHAT_OUTPUT.md`** —
the single append-only ledger — using exactly this schema. No finding is
"done" until it has a row.

| ID | Date | Stage/Step | File | Routine | Surface | Sev | Conf | Issue | Explanation | Status | Fix | PoC |
|----|------|-----------|------|---------|---------|-----|------|-------|-------------|--------|-----|-----|

- **ID** `F-NN`, monotonic across the whole project · **Stage/Step** the white-hat
  step that found it (e.g. `WI.3`) — "the stage that figured it out" · **File** /
  **Routine** where it lives · **Surface** catalog ID `S0`–`S12` (§7) ·
  **Sev / Conf** per §8–§9 · **Issue** one line · **Explanation** the attack path
  and, once resolved, the resolution · **Status** `Open / Confirmed / Fixed /
  Accepted-risk / False-positive` · **Fix** commit hash · **PoC** the Foundry test.
- The per-finding block in §9 is the *long form* an audit step emits; this table
  is the *roll-up* it gets transcribed into. A companion **coverage roll-up**
  table in the ledger records "no finding" per surface per pass, so silence is
  never mistaken for absence of review.
- The full column legend, status lifecycle, and commit discipline live in
  `AUREUM_WHITEHAT_OUTPUT.md`.

---

## 0. The two-layer model

| Build side | Audit side |
|---|---|
| `CLAUDE.md` (standing reference) | **this document** |
| `STAGE_X_PLAN.md` (per-stage step list) | the diff-scoped step list you generate per pass |
| one sub-step per direction + grep-and-confirm | one surface per step + attestation checkpoint |

Same discipline, same failure mode avoided: a 568-line contract checked against
a dozen categories in one shot makes the AI batch, spread thin, and skip
checkpoints. One surface at a time fixes that.

---

## 1. The unit of work

**One exploit-surface × one contract = one white-hat step.** Each step does
three things and stops:

1. **Read-lens** — look at one surface in one contract, cite line numbers.
2. **Execute-confirm** — run the matching invariant/harness, or write the PoC.
3. **Attestation checkpoint** — emit findings *or* an explicit clean attestation,
   then halt for verification.

No chaining. Never "do S1 and S2 and S3." If the AI starts batching surfaces,
the recovery phrase is the same one you already use: **"grep discipline"** →
revert to one surface at a time.

---

## 2. When to launch a pass

**Cadence start — decided 2026-06-10.** The per-stage cadence below **begins at the Stage K close**. K is the governance handoff — authorizer migration, voting-weight math, proposal execution, timelock — the highest-value surface in the protocol, and the K boundary is the cheapest place to catch a governance-control bug, before Stages L and O build on top. The first pass fires when `stage-k` is green and K7 is done, before the `stage-k-complete` tag; then one diff-scoped pass at every boundary after — L and O substantive, M and N config-only and therefore thin (S10 deployment surface plus an explicit "no Solidity surface changed" attestation). The **full Stage P sweep is unchanged** and is **not** replaced by these passes: it inherits a floor the per-stage passes already raised, and spends its budget on the cross-contract and cross-stage seams a per-stage pass sees only in isolation. "Defer to Stage P" names that sweep — never an argument against running the per-stage cadence first.

- **At a build-stage boundary**, *after* revisions stabilize (branch builds
  green, tests pass) and before you tag `stage-X-complete`. Not mid-churn —
  half-built code produces findings that are artifacts of incompleteness.
- **Not per sub-step / commit.** That bleeds the auditor role into the planner
  role and creates alert fatigue.
- **A full sweep at Stage P (pre-audit)** across all contracts, where you also
  hammer cross-contract and cross-stage seams that per-stage passes saw only in
  isolation.

Revision-heavy stages (like a housekeeping stage) are *good* times to run a
pass: refactoring mutates surface that already passed once, and that's where
drift sneaks back in.

---

## 3. Scoping a pass (let git decide, not memory)

```bash
git diff <previous-stage-tag>..HEAD --stat
```

The touched contracts are your scope. This is authoritative and current —
unlike anyone's recollection of the stage layout. For revision stages, also run
the **differential** in §10 against the prior tag: the question isn't only "are
these safe" but "did a revision disturb a previously-clean invariant."

**Surfaces in scope = the master catalog (§7) filtered to what the touched
contracts actually expose.** A token contract exposes S1/S8/S10; it does not
expose the hook hot path. Skipped surfaces are attested explicitly ("S5 — not
applicable, contract has no hook surface"), never silently omitted.

---

## 4. Numbering & ordering

- Steps are `W{stage}.{n}` — e.g. `WI.1`, `WI.2` for a Stage-I pass.
- **Severity-ordered.** The catalog (§7) is already in priority order, so:
  - `*.1` is always **supply / mint integrity** if the contract can mint
    (the Orchard analog — the worst possible miss).
  - then conservation, then rounding, then the rest.
- One contract may span several steps (one per applicable surface); one surface
  may span several steps (one per contract that exposes it). Either way, one
  surface × one contract per step.

---

## 5. The per-step loop (the cadence)

```
1. You direct ONE step, naming: surface ID + contract + what is explicitly
   out of scope for this step.
2. AI runs the read-lens + the matching harness for that one surface only.
3. AI emits findings (output format §9) OR a clean attestation — with cited
   line numbers, and "Confirmed / Suspected / Theoretical" on every finding.
4. You verify: open the cited lines, or run the PoC the AI sketched.
5. Only then → the next step.
```

A "Suspected" finding is not done until a Foundry PoC confirms or kills it.
Silence on a surface is not a pass — only an explicit attestation is.

---

## 6. Reusable step prompt template (the tiny operational prompt)

```
You are running ONE white-hat step on Aureum, per AUREUM_WHITEHAT_PROCESS.md.

Step:      W{stage}.{n}
Surface:   {surface ID + name, e.g. "S1 — supply/mint integrity"}
Contract:  {paste full source of the ONE contract + interfaces of its callees}
Out of scope this step: everything except {surface}. Do not review other
surfaces; if you notice one, note it in one line under "Adjacent observations"
and move on — do not expand into it.

Do exactly this, then stop:
1. Read-lens for {surface} (see §7). Cite line numbers for every claim. Do not
   reason from function names or from memory of how Balancer does it.
2. Run / sketch the matching harness (see §7 + §10).
3. Emit findings in the §9 format, OR write "{surface} — no finding" with a
   one-line justification of what you checked.
End with the per-step attestation line. Do not proceed to another surface.
```

Keep this prompt short on purpose. The catalog and methodology live in the doc;
the step prompt only references them.

---

## 7. Master surface catalog (reference — priority order)

Each surface: **Lens** (what to read for) · **Harness** (how to confirm, by
invariant/test ID from §10) · **Checkpoint** (what you paste back to verify).

### S0 — Crown-jewel invariants (the properties every step ultimately protects)
- Supply integrity: total AuMM ever minted ≤ 21,000,000; each era emits exactly
  the scheduled amount.
- Minter authority: one-shot, un-front-runnable, unescalatable; no admin path
  redirects emissions.
- Fee conservation: every extracted fee reaches der Bodensee; none skimmed,
  stuck, or rerouted; creator fees truly disabled; destination truly immutable.
- Round-trip: add→remove and swap→reverse never profit the actor.

### S1 — Supply / mint integrity (the Orchard analog) — `*.1`
- **Lens:** cap-budget decrement on every mint path; halving-era boundary math
  (`BLOCKS_PER_ERA`) for off-by-one; reentrancy into mint/distribute; overflow
  in any era/multiplier term; a path that mints without charging the cap budget.
- **Harness:** INV-1, INV-2 (checked against an *independent* reference
  emission, never the contract's own getter); hevm proof of `totalSupply ≤ 21M`.
- **Checkpoint:** invariant run output + the cited mint lines.

### S2 — Fee-routing conservation
- **Lens:** every fee in reaches Bodensee; no third destination; creator-fee
  functions all revert; no post-deploy destination setter (incl. via authorizer/upgrade).
- **Harness:** INV-3 (fees collected == routed + in-flight; nothing stuck).
- **Checkpoint:** INV-3 output.

### S3 — Rounding / invariant precision (Balancer V2 $128M; forks inherited it)
- **Lens:** rounding direction on every division/conversion — does it favor the
  protocol; division-before-multiplication; any re-implemented invariant/weight
  math that diverges from the byte-identical Vault; dimensional analysis on each
  expression.
- **Harness:** INV-5 round-trip; stateless precision fuzz; differential vs upstream.
- **Checkpoint:** round-trip fuzz output + unit-annotated expression list.

### S4 — ERC-4626 inflation / donation / rate manipulation (live 2025–26 class)
- **Lens:** every external ERC-4626 / Rate-Provider read that's `balanceOf`-derived
  and not flash-loan-resistant; first-depositor inflation; 2026 baseline
  defenses where Aureum mints shares (virtual offset, internal tracking,
  zero-share revert); the 52% composition floor and Bodensee compounding reads.
- **Harness:** §5a donation PoC on a fork; assert no downstream consumer (CCB
  TVL, gauge eligibility, pool price) moves exploitably.
- **Checkpoint:** fork PoC result.

### S5 — Hook hot path (OQ-1 fee-routing hook)
- **Lens:** reentrancy via `Vault.unlock` + nested svZCHF swap + one-sided
  Bodensee add; recursion-guard bypass (second router, re-entrant token
  callback, cross-function); spoofed/malicious router; callback-ordering
  assumptions; MEV on the nested swap.
- **Harness:** §5b reentrancy/recursion PoCs.
- **Checkpoint:** the `expectRevert` PoC outputs.

### S6 — Reentrancy & read-only reentrancy
- **Lens:** cross-function/cross-contract reentrancy; read-only reentrancy where
  an attacker reads inconsistent pool/price/TVL mid-callback.
- **Harness:** attacker handler interleaved in the invariant run; targeted PoC.
- **Checkpoint:** invariant + Slither reentrancy report.

### S7 — TVL-EMA manipulation (CCB engine — most novel, least audit-covered)
- **Lens:** can timed/flash deposits skew the 60-day EMA; observation cadence;
  conversion of cheap transient capital into real emissions.
- **Harness:** §5c EMA-resistance sim across observation windows.
- **Checkpoint:** multiplier drift vs baseline over the sim.

### S8 — Access control & privilege
- **Lens:** authorizer all-or-nothing grant — any widening path; one-shot
  setters callable twice / front-runnable; missing `onlyVault`/`VaultGuard` on
  reachable callbacks; uninitialized deploy state; immutability claims a
  governance path violates.
- **Harness:** unit PoCs (§5e) + Slither.
- **Checkpoint:** PoC + Slither access findings.

### S9 — Economic / incentive (tournament & gauge gaming)
- **Lens:** wash-trading or flash liquidity to enter the top-15% band or trip a
  gauge floor (52% ERC-4626 + $10k TVL) on a snapshot; Miliarium Aureum Month-11
  capture.
- **Harness:** §6 multi-actor sim; output is attacker ROI. ROI > 0 with no real
  liquidity = finding even if nothing reverted.
- **Checkpoint:** sim ROI table.

### S10 — Deployment / CREATE3 / setMinter
- **Lens:** address-prediction assumptions; deploy-order front-running;
  `setMinter` front-run; immutables baked with a wrong/influenced address.
- **Harness:** §5e unit PoCs.
- **Checkpoint:** PoC outputs.

### S11 — Fork-diff divergence (`AureumVaultFactory`, ~25-line diff)
- **Lens:** line-by-line vs audited upstream; removed checks; storage-layout
  shift; the dropped `deployedProtocolFeeControllers` mapping; any divergence
  beyond the documented diff.
- **Harness:** §5d differential vs upstream on a fork.
- **Checkpoint:** differential output isolating the diff lines.

### S12 — General Solidity
- **Lens:** unchecked-block overflow; unchecked external-call returns; decimals
  mismatch (WBTC 8 / USDC 6 / 18); `tx.origin`; delegatecall to untrusted;
  permit/EIP-712 replay; Cancun transient-storage assumptions across nested calls.
- **Harness:** Slither + targeted fuzz.
- **Checkpoint:** Slither report (accepted findings documented inline).

---

## 8. Shared methodology (non-negotiable — mirrors CLAUDE.md §6)

- Read the actual code; **cite line numbers** for every claim. If you can't see
  a function body, say so and stop — never invent its behavior.
- Dimensional analysis on every arithmetic expression.
- Rounding must always favor the protocol; round-trip mentally.
- A finding is a numbered transaction sequence with state + profit/damage at
  each step. If you can't write the steps, label it **Suspected**, not asserted.
- **Confirmed** (full path) vs **Suspected** (needs PoC) vs **Theoretical** —
  never inflate confidence.
- An explicit attestation is the only acceptable form of "no finding."

---

## 9. Output format (per finding) + per-step attestation

```
[F-NN] <one-line title>
Severity:    Critical | High | Medium | Low | Informational
Confidence:  Confirmed | Suspected | Theoretical
Contract:    <file>:<line-range>
Invariant:   <which S0 property / surface is violated>
Attack path: 1. attacker does X (state: ...)  2. ...  3. profit/damage: <quantified>
PoC sketch:  <Foundry setUp + key assertions>
Fix:         <minimal change; note if it touches byte-identity>
Notes:       <assumptions; what could NOT be verified from code given>
```

Per-step attestation line (always last):
```
W{stage}.{n} {surface}: {FINDING(s) F-NN.. | NO FINDING} | checked: <lens items> | could-not-assess: <gaps>
```

Each `[F-NN]` block above is then transcribed as one row into the standard
ledger table (`AUREUM_WHITEHAT_OUTPUT.md`, schema shown at the top of this doc);
each attestation updates that pass's coverage roll-up row.

---

## 10. Test infrastructure reference (condensed)

`foundry.toml`:
```toml
[invariant]
runs = 512          # 5000+ for the pre-audit gate
depth = 100
fail_on_revert = false   # only after confirming handler reverts are legitimate
```

Invariants (full bodies in the prior playbook; IDs used above):
- **INV-1** `totalSupply ≤ 21M` and `== g_totalMinted` (ghost from events, not the contract).
- **INV-2** cumulative emission `≈` independent `ReferenceEmission.cumulativeAt(block)` — the non-circular check.
- **INV-3** `g_feesCollected == g_feesRoutedToBodensee + inFlight`; nothing stuck.
- **INV-4** vault solvency: real balances ≥ accounted balances.
- **INV-5** round-trip: every actor's net gain ≤ 0.
- **INV-6** only the minter mints.

Handler: bounds inputs with `bound()`, rotates actors, tracks ghosts
*independently* of the contracts under test; `advanceBlocks` with a wide bound
to cross halving boundaries. Attacker handler exposes adversarial primitives
(flash-loan deposit, ERC-4626 donation, reentrancy attempt, sandwich, malicious
router, gauge-floor gaming) and reproduces named incidents as regression tests.

Harness references used in §7:
- §5a ERC-4626 donation/inflation · §5b hook reentrancy/recursion · §5c EMA
  resistance · §5d rounding round-trip + factory differential · §5e
  deployment/setMinter · §6 economic simulation. (Skeletons in the prior
  playbook; port them as you instantiate each step.)

Gates at a stage boundary (before tagging `stage-X-complete`):
```
forge test --fork-url $RPC          # real-state integration
forge test --mt invariant_ -vvv     # runs >= 5000
forge coverage                       # confirm surfaces are REACHED (line coverage lies)
slither .                            # accepted findings documented inline
# Stage P/Q: hevm proofs + Act spec re-check
```

---

## 11. Worked example (illustrative — your real list comes from the diff)

Suppose `git diff stage-H-complete..HEAD --stat` for a Stage-I housekeeping pass
shows changes to `AuMM.sol` (constant rename) and the CCB engine (refactor). The
generated step list would be:

```
WI.1  S1  AuMM.sol            supply/mint integrity   (renamed constant — confirm cap budget intact)
WI.2  S3  AuMM.sol            rounding/precision      (any emission math touched)
WI.3  S7  CCB engine          TVL-EMA manipulation    (refactor — most novel surface)
WI.4  S3  CCB engine          rounding/precision      (multiplier math)
WI.5  S6  CCB engine          read-only reentrancy    (TVL read path)
WI.6  --  differential        INV-2/INV-5 vs stage-H-complete (did revision disturb a clean invariant)
```

S2/S4/S5/S8–S12 attested as out-of-scope for this pass (not touched by the
diff). **This list is illustrative.** Generate the real one from your actual
diff stat — I won't pre-invent it from a stale view of your stage layout.

---

## 12. Standing-context integration — deliberately none

This process is **self-contained in `docs/white_hat/`**. It is **subject to**
`CLAUDE.md` — grep-and-confirm (§6), execution delegation through Cursor (§8e),
one-surface-per-step discipline — but `CLAUDE.md` is **not** modified to
reference it. No audit hook in standing per-session context; no audit line in
`CLAUDE.md §11`. A build session should not carry an audit reminder on every
prompt — the audit is a stage-boundary event, not a per-prompt concern.

The trigger lives **here**, not in `CLAUDE.md`. At a stage boundary, once the
branch is green and before tagging `stage-X-complete`:

> Generate the white-hat step list from `git diff <prev-tag>..HEAD --stat`
> (§3), run one step at a time (§5), verify each attestation, and complete the
> pass's coverage roll-up row in `AUREUM_WHITEHAT_OUTPUT.md` before the tag.

The heavy reference — this doc — loads only inside a dedicated audit session. A
build session that reaches a stage boundary opens that session against this
folder; it does not need `CLAUDE.md` to remind it to.

---

## Closing principle

Orchard survived years of expert review and fell to a targeted adversarial pass.
Balancer V2 lost $128M to one rounding residual that forks inherited. Both were
invisible to happy-path testing and visible to "can an adversary make the numbers
drift" testing. Small steps, severity-ordered, one surface at a time, each
confirmed before the next — that is how you make a sweep that size actually get
done instead of skimmed.
