# Stage K — Notes & Design Freeze

> **Status:** K2 pre-flight landed K-D4 LOCKED on `stage-k` — TVL-oracle binding for vote-weighting = reuse-direct (`ITVLOracle.tvl(pool)`; no new K2 contract). K1 complete: `AureumGovernanceAuthorizer` (`73ceaae`) + 12-green unit cohort (`e72104c`). K-D1—K-D3 LOCKED; K-D5—K-D9 forward-declared, each locking at its unit pre-flight. Companion to STAGE_K_PLAN.md.
>
> **Last update:** 2026-06-08 — K2.0a NOTES (this commit): K-D4 TVL-oracle binding LOCKED reuse-direct (`VotingWeight` takes an `ITVLOracle` immutable, calls `tvl(pool)`; single shared instance; K6 re-wire signature-stable); no K2 code surface.
>
> **Mode:** Opus per §13 — governance handoff, stay on Opus through Stage K. K2.0b PLAN mirror next, then K3 pre-flight (K-D5 `VotingWeight` value-curve).
>
> **Audience:** Sagix plus any future Claude session that needs the running log of decisions resolved during Stage K implementation and the incidents caught at audit.

---

## How this file is organized

- Design decisions — K-D1 + K-D2 LOCKED at K0.2; K-D3 onward forward-declared and each LOCKED at its named unit pre-flight (NOT wholesale at K0.2 — Stage K is the largest stage); matches the C-D* / D-D* / E-D* / F-D* / G-D* / H-D* / I-D* / J-D* convention.
- Findings (K10 onward) — implementation incidents, numbered from K10 to avoid collision with K-D* (matches C10 / D10 / … / J10).
- Cross-reference convention per CLAUDE.md §5: K-Dn = decision n; Kn (n ≥ 10) = finding n; OQ-N = FINDINGS open question; F-n = formula in `11_formulas.md`; §xxix = aumm-site numbered spec; J-Dn / I-Dn / H-Dn / … = prior-stage decisions; Jn / In / Hn / … = prior-stage findings.

---

## Design decisions

K-D1 + K-D2 carry the entry freeze locked at K0.2 from a pre-flight Opus beat; unlike Stage J (which locked J-D1—J-D7 wholesale because it was ~200 LOC), Stage K locks only scope + sequence at entry and defers each unit's deep design to its own Opus pre-flight as a new K-D entry (generalizing the J-D8-locks-at-J4.0 precedent).

| # | Status | Decision | Anchor | Locked at |
| --- | --- | --- | --- | --- |
| K-D1 | LOCKED | Stage K scope = tight governance handoff, seven dependency-ordered units K1—K7. D33 Aureum Router DEFERRED to Stage O; OQ-20 / OQ-21 controller yield-fee leg stays DEFERRED (user scope decision 2026-06-07). New contracts: `AureumGovernanceAuthorizer` (K1), `VotingWeight` (K3), `AureumGovernance` (K4). New scripts: `script/DeployAuMM.s.sol` (H-D42), `script/DeployStageK.s.sol` (K7). Fix-forward edit to tagged contract: `TVLOracle` roster re-wire (K6, J-D8, I13-class). `AuMM.setMinter` is a deploy-script call (K5, H-D41) — no AuMM contract edit. | STAGES_OVERVIEW Stage K; OQ-10; user scope decision 2026-06-07; H-D41 / H-D42 / J-D8 carry-forward | K0.2 |
| K-D2 | LOCKED | Dependency-ordered build sequence: K1 `AureumGovernanceAuthorizer` → K2 TVL-oracle binding → K3 `VotingWeight` → K4 `AureumGovernance` → K5 `setMinter` handoff → K6 `TVLOracle` re-wire → K7 deploy + migration. Each unit's deep design locks at its own Opus pre-flight as a new K-D entry (K-D3 onward), NOT at K0.2 — F-12 deposit math, F-9 dampening, the snapshot mechanism, and the `VotingWeight` value-curve each need a focused beat reading the canonical formulas. The §12 ambiguity-gate fires fresh at each unit pre-flight. | Stage K size vs Stage J; J-D8 precedent; §12 ambiguity-gate; §13 per-unit Opus pre-flight | K0.2 |
| K-D3 | LOCKED | `AureumGovernanceAuthorizer` per OQ-10 — `is IAuthorizer`, no new Aureum interface (external surface is `canPerform` + public-immutable getters). Constructor `(governanceContract_, emergencyMultisig_, vault_)` all zero-checked; immutables `GOVERNANCE_CONTRACT` / `EMERGENCY_MULTISIG` / `EMERGENCY_WINDOW_END_BLOCK` + two `bytes32` emergency action IDs; constant `EMERGENCY_WINDOW_BLOCKS = 2_628_000`. `EMERGENCY_WINDOW_END_BLOCK = block.number + EMERGENCY_WINDOW_BLOCKS` (from construction block). Emergency set = {`pauseVault`, `enableRecoveryMode`} (user 2026-06-07; `disableQuery` dropped — permanent defensive-config, not crisis-response). Action IDs computed locally H13-safe; disambiguator = Vault address (verified `Authentication.sol:51` + `VaultAdmin.sol:77`). `canPerform`: governance → true; multisig ∧ emergency ∧ `block.number < END_BLOCK` → true; else false. | OQ-10 (FINDINGS L722-794); `Authentication.sol:51` / `VaultAdmin.sol:77` encoding; `IVaultAdmin` selectors; Stage B `AureumAuthorizer.sol`; user decision 2026-06-07 | K1 |
| K-D4 | LOCKED | TVL-oracle binding for vote-weighting = **reuse-direct**. `ITVLOracle` already exposes `tvl(address pool) → uint256` (svZCHF, 18-dec; `ITVLOracle.sol` L14, implemented at `TVLOracle.sol` L211) — exactly the whole-pool valuation K3 `VotingWeight` multiplies by BPT share (`holderValue = tvl(pool) × balanceOf(holder) / totalSupply()`; BPT reads direct off the pool per I-D14). No adapter, no new K2 contract, no `IVotingWeight` change — `VotingWeight` takes an `ITVLOracle` immutable and calls `tvl(pool)`; injection lands at K3. Single shared `TVLOracle` instance (emission `EfficiencyOracle` + governance; one roster, one `setGovernanceContract` handoff); deploy ordering at K-D9. K6 `_constellationRatio` re-wire is signature-stable (does not touch `tvl` ABI). | OQ-22 (FINDINGS L1106); `src/ccb/ITVLOracle.sol` L14; `src/emission/TVLOracle.sol` L211; I-D14 (AuMT=BPT); K-D9 | K2 |
| K-D5 | forward-declared | `VotingWeight` value-weighted view — `(qualified_AuMT_value × time_in_pool_capped)^(1/4 → 1/3)` over the `EmissionDistributor` recorder clock; 14-day cliff, 6-month on-ramp, F-9 era root, gauged-only; `is IVotingWeight` (I9.1 stub). I-D17 `totalSupply()` denominator = total qualified voting weight (pre-flight recommendation), fixing the veto-bps semantic. | I-D15; I-D17; OQ-25; `src/governance/IVotingWeight.sol`; F-9 | K3 |
| K-D6 | forward-declared | `AureumGovernance` three proposal types (gauge challenge F-12 / composition challenge / fee proposal) + F-9 dampening + snapshot voting + timelock. Sub-splits K-D6a—K-D6f at K4 pre-flight: base proposal machinery, snapshot mechanism, F-9 era root, F-12 elite-tail deposit, per-type quorum/majority/deposit, timelock + execution routing. | STAGES_OVERVIEW Stage K L245-252; OQ-7 / OQ-8 / OQ-9 / OQ-11 / OQ-13; F-9 / F-12 | K4 |
| K-D7 | forward-declared | `AuMM.setMinter(EmissionDistributor)` handoff sequencing per H-D41 — deploy-script call, no AuMM contract edit; `distribute()` / `claim()` unblock from `NotMinter` at this call. | H-D41 (CLAUDE.md §11 deferred); `AuMM.setMinter` | K5 |
| K-D8 | forward-declared | `TVLOracle` H-D8 roster re-wire — re-point `_constellationRatio` to enumerate the live `MiliariumRegistry` dense view (`miliariumPoolsCount` / `miliariumPoolAt`); I13-class fix-forward on the tagged Stage H contract. | J-D8 (STAGE_J_NOTES.md); H-D8 roster; I13 blast-radius | K6 |
| K-D9 | forward-declared | Deploy + authorizer-migration sequencing — `script/DeployAuMM.s.sol` (H-D42, ~30 lines) + `script/DeployStageK.s.sol`: deploy governance stack, multisig one-shot `Vault.setAuthorizer(newAuthorizer)`, registry + gauge `setGovernanceContract` one-shots, `AuMM.setMinter`. | OQ-10 migration sequence (FINDINGS L788-792); H-D42; J-D5 / G-D16d `setGovernanceContract` | K7 |

### K-D1 — Stage K scope + contract roster — status LOCKED

Stage K ships the on-chain governance stack plus the authorizer migration that ends the Stage A—K multisig's general authority over the Vault and the protocol registries. The user scope decision (2026-06-07) narrows the stage to a tight governance handoff: D33 Aureum Router DEFERRED to Stage O; OQ-20 / OQ-21 controller yield-fee leg stays DEFERRED. Three new contracts land: `AureumGovernanceAuthorizer` (K1), `VotingWeight` (K3), `AureumGovernance` (K4). Two new scripts: `script/DeployAuMM.s.sol` (H-D42, ~30 lines) and `script/DeployStageK.s.sol` (K7). One fix-forward edit to a tagged contract: `TVLOracle` roster re-wire (K6, J-D8, I13-class). `AuMM.setMinter` is a deploy-script call (K5, H-D41) — no AuMM contract edit. Anchors: STAGES_OVERVIEW Stage K; OQ-10; user scope decision 2026-06-07; H-D41 / H-D42 / J-D8 carry-forward.

### K-D2 — Dependency-ordered build sequence + per-unit lock convention — status LOCKED

The build order is dependency-driven: K1 `AureumGovernanceAuthorizer` is self-contained and OQ-10-specified, so it lands first; K2 binds the TVL oracle that K3 `VotingWeight` needs for AuMT value reckoning; K4 `AureumGovernance` consumes `VotingWeight` plus `GaugeRegistry`, `MiliariumRegistry`, and the Vault; K5 `setMinter` unblocks emission; K6 `TVLOracle` re-wire tracks the live registry; K7 deploy + migration wires everything and executes the authorizer handoff last. Each unit's deep design locks at its own Opus pre-flight as a new K-D entry (K-D3 onward), NOT at K0.2 — Stage K is the largest stage in the sequence, and F-12 deposit math, F-9 dampening, the snapshot mechanism, and the `VotingWeight` value-curve each need a focused beat reading the canonical formulas. The §12 ambiguity-gate fires fresh at each unit pre-flight rather than wholesale at entry (generalizing the J-D8-locks-at-J4.0 precedent). Anchors: Stage K size vs Stage J; J-D8 precedent; §12 ambiguity-gate; §13 per-unit Opus pre-flight.

### K-D3 — `AureumGovernanceAuthorizer` design per OQ-10 — status LOCKED

Locked at the K1 pre-flight Opus beat (OQ-10 FINDINGS L722-794 + the Stage B `AureumAuthorizer` migration-target + Balancer `IAuthorizer` + a submodule probe of the action-ID encoding). The contract is the B-strict authorizer with a 12-month emergency window: after the Stage B multisig signs the one-shot `Vault.setAuthorizer`, `GOVERNANCE_CONTRACT` becomes primary and `EMERGENCY_MULTISIG` keeps a narrow, time-boxed emergency role that dies permanently at `EMERGENCY_WINDOW_END_BLOCK`.

**Shell + interface.** `contract AureumGovernanceAuthorizer is IAuthorizer` (`pragma ^0.8.26`, same `@balancer-labs/v3-interfaces` import as the Stage B `AureumAuthorizer`). No new Aureum interface file: the external surface is the single `IAuthorizer.canPerform` plus the auto-generated public-immutable getters, exactly as the interface-less Stage B authorizer. SCREAMING_CASE immutables carry the `slither-disable-next-line naming-convention` rationale comment from `AureumAuthorizer.sol`.

**State.** Three immutables — `GOVERNANCE_CONTRACT`, `EMERGENCY_MULTISIG`, `EMERGENCY_WINDOW_END_BLOCK` — plus two `bytes32` immutable emergency action IDs (`EMERGENCY_ACTION_PAUSE_VAULT`, `EMERGENCY_ACTION_ENABLE_RECOVERY_MODE`) and one constant `EMERGENCY_WINDOW_BLOCKS = 2_628_000` (= 12 × `BLOCKS_PER_MONTH` = `BLOCKS_PER_YEAR`; OQ-3 / OQ-10).

**Constructor `(address governanceContract_, address emergencyMultisig_, address vault_)`.** Reverts on a zero value for any of the three. Sets `EMERGENCY_WINDOW_END_BLOCK = block.number + EMERGENCY_WINDOW_BLOCKS` — the window is measured from the authorizer's own construction block, which is the migration block to within the deploy→`setAuthorizer` gap (immaterial against 2.6M blocks; OQ-10 steps 2-3). Computes the two action IDs locally with no external call (H13-safe, mirroring the J-D4 H13-safe constructor), importing `IVaultAdmin` for the selectors: `keccak256(abi.encodePacked(bytes32(uint256(uint160(vault_))), IVaultAdmin.pauseVault.selector))` and the same for `enableRecoveryMode`. `vault_` is a constructor argument rather than a hardcoded constant so unit tests can supply a test address and compute the expected IDs identically; the K7 deploy passes the locked mainnet Vault `0xbA1333333333a1BA1108E8412f11850A5C319bA9` and the K7 fork test confirms the real Vault's `getActionId` agrees.

**Action-ID encoding (submodule-verified).** Balancer's `Authentication.getActionId(selector) = keccak256(abi.encodePacked(_actionIdDisambiguator, selector))` (`Authentication.sol:51`), and `VaultAdmin` sets `_actionIdDisambiguator = bytes32(uint256(uint160(address(mainVault))))` (`VaultAdmin.sol:77`) — the disambiguator is the Vault address, not VaultAdmin's, so the authorizer needs `vault_` to reproduce the IDs. The `pauseVault()` and `enableRecoveryMode(address)` selectors live on `IVaultAdmin` (L136 / L241).

**Emergency-action set = {`pauseVault`, `enableRecoveryMode`}** (user decision 2026-06-07). The two direct damage-halting levers — global halt and per-pool safe-exit without a global pause. `disableQuery` (OQ-10's third candidate) is dropped: it is permanent defensive-config, not crisis-response, and keeping the deprecated multisig's residual surface minimal honors the constitutional "no multisig" framing. `_isEmergencyAction(actionId)` returns `actionId == EMERGENCY_ACTION_PAUSE_VAULT || actionId == EMERGENCY_ACTION_ENABLE_RECOVERY_MODE`.

**`canPerform(bytes32 actionId, address account, address /* where */)`.** `account == GOVERNANCE_CONTRACT` → `true` (governance does anything authorizer-gated); `account == EMERGENCY_MULTISIG && _isEmergencyAction(actionId) && block.number < EMERGENCY_WINDOW_END_BLOCK` → `true`; otherwise `false`. `where` is ignored (governance authority is global, matching OQ-10's `/* target */`). The window boundary is strict: at `block.number == EMERGENCY_WINDOW_END_BLOCK` the emergency clause is already dead.

**K1 sub-steps.** K1.0a (this NOTES lock) → K1.0b (PLAN K-D3 mirror flip + K1 sub-step detail) → K1.1 `src/governance/AureumGovernanceAuthorizer.sol` → K1.2 `test/unit/AureumGovernanceAuthorizer.t.sol` (governance all-access; emergency × in-window; emergency × post-window; non-emergency × in-window; random account; action-ID encoding matches `getActionId`; window boundary at `== END_BLOCK`; three zero-address constructor reverts).

### K-D4 — TVL-oracle binding for vote-weighting — status LOCKED

Locked at the K2 pre-flight Opus beat (reading `src/ccb/ITVLOracle.sol` + `src/emission/TVLOracle.sol`). The binding is **reuse-direct**: no new K2 contract and no adapter.

**What K3 needs.** Per I-D14, AuMT is the gauged pool's own Balancer V3 BPT, so a holder's "AuMT value" is the svZCHF value of their BPT position: `holderValue = tvl(pool) × balanceOf(holder) / totalSupply()`, where `balanceOf` / `totalSupply` are read directly off the pool/BPT (no oracle) and `tvl(pool)` is the only oracle dependency. The qualification gates (14-day cliff, 6-month on-ramp, gauged-only, the `^(1/4 → 1/3)` curve) are `VotingWeight`'s own logic per K-D5, layered on top of this raw value — out of scope for K-D4.

**Why reuse-direct.** `ITVLOracle` already exposes `tvl(address pool) external view returns (uint256)` (svZCHF, 18-dec; `src/ccb/ITVLOracle.sol` L14), and `TVLOracle` implements it (`src/emission/TVLOracle.sol` L211). That is precisely the whole-pool valuation `VotingWeight` multiplies by BPT share — so `VotingWeight` takes an `ITVLOracle` constructor immutable and calls `oracle.tvl(pool)`. No new interface, no adapter, no per-holder oracle method (share math is `VotingWeight`'s). `quoteSvZCHF` (the per-token H-stage entry) is not used by governance. K2 therefore produces **no code surface** — the oracle consumption folds into the K3 `VotingWeight` constructor.

**Single shared instance.** "Reuse" means the same deployed `TVLOracle` the emission `EfficiencyOracle` path reads — one constellation roster, one `tokenToUnderlying` map, one `setGovernanceContract` (H-D8) handoff migrating it to governance at Stage K. A separate governance-local oracle would double the roster-maintenance burden with no isolation benefit. The exact deploy ordering (deployed inside `DeployStageK.s.sol` vs. already-live and passed as a K7 Stage-input like AuMM per H-D42) is fixed at K-D9; K-D4 commits only to the single-instance design intent.

**K6 interaction is signature-stable.** K6 (K-D8) re-points `TVLOracle._constellationRatio` to enumerate the live `MiliariumRegistry` dense view — an internal valuation-accuracy change that does not alter `tvl`'s ABI. `VotingWeight`'s binding to `ITVLOracle.tvl` therefore survives the K6 re-wire unchanged; only the accuracy of the returned svZCHF figure improves as the roster densifies. Pre-K6, `tvl()` runs on the F-D9 placeholder roster (Bodensee + governance-added pools); gauged Miliarium pools value correctly once K6 lands.

**K2 sub-steps.** K2.0a (this NOTES lock) → K2.0b (PLAN K-D4 mirror flip + K2 roadmap marked documentation-only + Completion Log). No K2.1 / K2.2 — there is no K2 code surface; the `ITVLOracle` injection is a K3 (`VotingWeight` constructor) concern.

---

## Interfaces

### Produced by Stage K

- `src/governance/AureumGovernanceAuthorizer.sol` (NEW, K1) `is IAuthorizer`
- `src/governance/VotingWeight.sol` (NEW, K3) `is IVotingWeight`, concrete `governanceWeight(holder)` + `totalSupply()`
- `src/governance/AureumGovernance.sol` (NEW, K4) three proposal types (proposal / vote / execute API shapes lock at K4)
- `script/DeployAuMM.s.sol` (NEW, K7) + `script/DeployStageK.s.sol` (NEW, K7)

### Consumed — frozen by prior stages

- Exact signatures are verified at each unit's pre-flight, not here.
- `src/governance/IVotingWeight.sol` (Stage I, I9.1) — the forward stub `VotingWeight` implements
- `src/ccb/IGaugeRegistry.sol` (Stage F/G) — `revokeGauge` / `registerGaugeFromComposition` / `setGovernanceContract`
- `src/registry/IMiliariumSlotRegistry.sol` (Stage J) — `replaceSlot` / `setGovernanceContract`
- `src/emission/TVLOracle.sol` + `src/ccb/ITVLOracle.sol` (Stage F/H) — `tvl(pool)` svZCHF valuation (vote-weighting input + K6 re-wire target)
- `src/emission/IEmissionDistributor.sol` (Stage H) — recorder clock + `setMinter` target
- `AuMM` (Stage C/H) — `setMinter`
- Balancer Vault — `setAuthorizer` (migration) + `setStaticSwapFeePercentage` (fee proposals)
- `src/vault/AureumAuthorizer.sol` (Stage B) — outgoing authorizer, replaced at migration

### Forward-dependency stubs

- None new; `VotingWeight` (K3) closes the `IVotingWeight` zero-return stub from Stage I (I9.1) — until K3 lands the bound reader returns zero, vetoes structurally impossible, preserving Stage I behaviour.

---

## Findings queue

Empty at K0.2 entry; implementation incidents numbered K10 onward (matches C10 / D10 / … / J10).
