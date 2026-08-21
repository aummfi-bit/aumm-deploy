# CORRECTIONS.md — carried findings a re-run must not re-derive

**What this is.** The seam-1 run of 2026-08-19—21 (auditician `22aa9851caf68f13c9439bd145ef7594f217df5c` against aumm-deploy `9ec513d99a68fb454a8a54271b34b884f40f2088`) established the facts below by re-deriving them from source, and in several cases by one agent disproving an earlier agent's claim. They are recorded here so a later run spends its budget on what is unknown rather than on what has already been settled, and so a claim that was retracted once is not re-filed.

**How to use it, and the one rule that overrides everything here.** Every entry names the source lines it rests on. **If the code at those lines has changed since `9ec513d`, the entry is void and the question is open again — re-derive it.** This is not a formality: the run that produced these corrections fed a remediation stage whose whole purpose is to change several of the exact regions cited below, so treating an entry as settled without checking its provenance would be inheriting a conclusion about code that no longer exists. Check `git diff 9ec513d..HEAD -- <path>` for each entry you intend to rely on. Nothing here is a verdict to defer to; each is a finding with a citation, and a citation is checkable.

**What this file is not.** It is not a list of things that are safe, and it is not a scope restriction. An entry saying "X was refuted" means X was refuted *by the stated argument at the stated lines*, not that the surrounding area is clean.

---

## 1. The first run, in numbers

82 confirmed findings, 11 invalid, 0 unvalidated: 2 Critical, 17 High, 32 Medium, 14 Low, 17 Info. `audit-state/PROGRESS.md`'s own QUALITY CONTROL block closes at 78 / 2 / 21 / 28 / 14 / 13 — that is the pre-review state and it is superseded. An independent review of the first report returned four High findings to Medium (`efficiencyoracle-emissionsrecorder-…`, `composite-composition-challenge-…-ratchet`, `sleeper-de-escalation-…`, `propose-path-is-welded-…`) and four `README`-versus-`CLAUDE.md` Info findings were filed afterwards, giving the 82. Where a validator note records a severity *raise* that the review later reversed, the reversal binds.

Coverage: 28 files audited individually, 42 global focus areas, 18 global write-ups. 22 of the 42 focus areas were worked inline by the coordinating agent after a dispatched fleet failed on a session limit; six confirmed findings came from that stretch and were validated by their own author. They are named in §7.

## 2. Corrections — an earlier claim disproved by a later agent

Each was recorded in `PROGRESS.md` under "CORRECTIONS that must propagate before the report". The corrected version is the one that binds.

**2.1 The `AureumVaultFactory` owner is INERT, not a live standing authority.** `create()` is unreachable-to-success forever: the new Vault's constructor requires `protocolFeeController.vault() == address(this)` (`lib/…/Vault.sol:65-67`), `INITIAL_FEE_CONTROLLER` is immutable and pinned to the canonical Vault, whose `isDeployed` is already true, so the owner cannot deploy even one additional Vault. The residual is real but small — a never-renounced admin slot against a "no admin keys" claim, with zero test coverage — and is Info, not High. This corrects `SURVEY.md` §3.1D and the `THREATMODEL.md` §9 "never expires" table. Provenance: `lib/…/Vault.sol:65-67`, `src/vault/AureumVaultFactory.sol:106-113`.

**2.2 Emergency action-ID cross-contract collision is impossible.** `SingletonAuthentication` disambiguates by the contract's own address, not the Vault's, so the emergency grant cannot reach `AureumProtocolFeeController` or either factory. This corrects `SURVEY.md` §2.2. Provenance: `src/governance/AureumGovernanceAuthorizer.sol:78-82`.

**2.3 `AureumProtocolFeeController` followed the Stage-K authorizer swap correctly.** It resolves `getVault().getAuthorizer()` live. The only cached `IAuthorizer` in `src/` is `AureumVaultFactory._authorizer` (`src/vault/AureumVaultFactory.sol:39`), used only inside the unreachable `create()`. The Stage-B `AureumAuthorizer` is therefore genuinely inert today; its risk is that it remains permanently *installable* via `VaultAuthorizerChange`, not that it is live.

**2.4 The F-17 read-cap is one-directional.** `VotingWeight.sol:180-181` (`if (held < lp) lp = held;`) genuinely defeats voting-weight INFLATION — a credited `userLP` for an address holding no BPT confers zero — and does NOT constrain SUBTRACTION. Any finding claiming weight inflation via recorder manipulation should be checked against this cap and is probably wrong; findings in the subtractive direction are unconstrained by it and stand. **This is the single most load-bearing entry in this file and the one most likely to be void:** the cap and its denominator are a named remediation target, so check `VotingWeight.sol:163-195` against `9ec513d` before relying on it.

## 3. Corrections from the composite-attack analysis (G36)

**3.1 Pausing der Bodensee does NOT open recovery mode protocol-wide.** `lib/…/VaultAdmin.sol:350` reads the **target pool's** pause bit or the Vault's: `pausePool(derBodensee)` makes `enableRecoveryMode` permissionless on der Bodensee only; `pauseVault()` opens it on all 27. Any chain built on "one pool pause implies protocol-wide recovery mode" is invalid. The other half stands — `pausePool(derBodensee)` does kill every `propose*`.

**3.2 There is NO mint-to-governance link. Do not chain those findings.** `VotingWeight.poke` enumerates Miliarium pools only, AuMM lives in der Bodensee, and the mint chain's synthetic pool address is never in that enumeration, so minted AuMM confers zero voting weight by any in-protocol route. The only conversion is the ordinary market route, available to anyone with money. Combining the mint finding with any governance finding adds nothing.

**3.3 Two "permanently locked funds" findings are mis-framed as stranded.** Under a successful `VaultAuthorizerChange` those balances are the attacker's *payload*, not burnt value. Frame them as "unreachable to governance, reachable to a successful authorizer-change attacker".

**3.4 The F-22 accepted residual is a latch, not a residual.** Every `authenticate`-gated Vault entry recorded as reachable-by-nobody un-freezes the instant `setAuthorizer` executes — including `setProtocolFeeController`, whose holder is the sole caller `collectAggregateFees` permits.

**3.5 One asymmetry worth carrying:** `VaultAuthorizerChange` is the only proposal type nobody can grief into `Expired`. Every de-escalation and fee type can be nullified after the vote with the bond already burnt.

## 4. Refuted hypotheses — do not re-file

**4.1 A slotted Miliarium pool cannot be gauge-challenged.** The propose-time `slotOf(targetPool_) == 0` gate is sufficient, because the only reachable `replaceSlot` caller immediately calls `registerGaugeFromComposition`, which rejects an `Active` pool. **CONDITIONAL, and the condition is live:** this holds only through that undocumented cross-contract coupling. A fix that makes the composition branch tolerate an already-`Active` candidate falsifies it and turns this into a live High. If `src/governance/AureumGovernance.sol:426-433` or `src/gauge/GaugeRegistry.sol:168-171` has changed, **re-test this first.**

**4.2 Emergency action-ID collision is impossible** — see 2.2.

**4.3 Block-time drift on the 12-month window is a false positive.**

**4.4 `queue` cannot be double-called** — the state transition is genuinely self-guarding and the NatSpec claim is correct.

**4.5 `PoolRoleAccounts` is immutable after registration** — written only at `lib/…/VaultExtension.sol:252`, no setter anywhere in the Vault. The propose-time-check-is-sufficient reasoning that rests on it is sound.

**4.6 No denominator-INFLATION attack exists against `AureumGovernance`.** `poke` pushes the holder trace and the total trace in the same transaction at the same block key (`src/governance/VotingWeight.sol:150-151`), so an actor cannot enlarge the denominator without enfranchising exactly that weight for the whole voting window. The exposure is entirely in the subtractive direction. **Void if the denominator's writer or its invariant changed** — a denominator maintained by the protocol rather than by opt-in pokes breaks the premise by construction, and the refutation must then be re-run against the replacement invariant.

**4.7 `poke` cannot revert**, so the electorate cannot be frozen: every read in the `_positionPower` chain is a plain storage getter or an unguarded view, and `balanceOf` carries no pause or recovery guard. A Vault pause, a pool pause and recovery mode all leave it intact.

**4.8 `TVLOracle.tvl` cannot be made to revert** by a pause, recovery mode, deregistration (which does not exist in Balancer V3) or gas growth. The only reachable revert is a third-party `IRateProvider.getRate()`, which is a confirmed finding in its own right.

## 5. Retractions — claims this audit made about its own work and withdrew

**5.1 "`recoverStrandedFees` has zero test coverage" was WRONG.** It rested on a truncated grep. The function has 20 references across two files and 8 negative tests. The narrower gap that survives is real and is the one to state: no test drives an adversarial *route* — nothing exercises hops that leave a zero terminal balance and therefore skip the delivery guard.

**5.2 A recommendation was withdrawn for introducing a worse defect.** The proposed one-line fix to the zero-`totalScore` accrual window — return without advancing the cursor — rested on `_lpTrancheIntegral` being O(1) in the interval. It is not: in the continuous phase it calls `IIncendiaryRegistry.integratedSkim`, which loops once per 14-day epoch spanned, has no cursor of its own and carries no `try`/`catch`. The fix would have traded a value forfeiture for an unbounded catch-up cost borne by whichever user triggered it. **The general lesson the run drew from this: check every recommendation, not only every claim.**

## 6. Filenames that must never be cited

Two candidate findings were deleted by their own authors during the run and exist in no directory. Earlier notes still reference them; a report or issue that cites either is citing nothing.

- `quorum-denominator-has-no-absolute-floor.md` — merged; its content lives in `quorum-denominator-counts-only-ever-poked-holders.md`.
- `vault-authorizer-change-renews-12-month-emergency-window.md` — deleted as a triplicate; its unique argument was folded into `emergency-window-recreatable-via-vaultauthorizerchange.md`.

Eleven further filings are in `issues/invalid/`. Read them for their refutations; do not re-file them. Two bound the threat model and are recorded above as 4.6 and the merge in 2.3's family.

## 7. Known limits of the first run

**7.1 Six findings were authored and validated by the same agent** after a dispatched fleet failed on a session limit, all Medium or Low: the CCB 26-versus-28 divisor, the revoked-pool score weld, the zero-`totalScore` forfeiture, the donate exact-reserve-delta assertion, the swap-fee-band divergence, and the admission-only TVL floor. Each issue file records the refutation attempts made against it. **Check the attempts, not only the verdicts.**

**7.2 The self-validation missed two duplicates** that a mechanical title-and-severity extract caught at report-assembly time. A single agent performing discovery, de-duplication and validation missed findings that already existed in its own issue set.

**7.3 No on-chain state was read.** Every statement about the live deployment — who holds a slot, whether a one-shot has fired, whether a tally is zero — is derived from the repository's scripts and its committed deployment record.

**7.4 Two severity boundaries are genuinely arguable** and a reviewer may reasonably move them: the composition-victim finding (held at Medium) and the eligibility-floor finding (borderline Low/Info, defensibly split in two).

## 8. Severity calibration that binds a family

The same EMA manipulation buys `pump^(1/4)` of governance weight and `pump^1` of emission share: `VotingWeight._positionPower` damps quartically (`src/governance/VotingWeight.sol:194`) while `CCBScore.score` is linear (`src/ccb/CCBScore.sol:23-25`). Every EMA finding in the first run was initially scored against the governance consumer alone and re-scored with **emissions as the primary victim**. Emission-side decay is correspondingly faster: the EMA halves in roughly 21 daily samples, not 83.
