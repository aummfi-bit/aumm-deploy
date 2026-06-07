# Stage K — Notes & Design Freeze

> **Status:** K0.2 NOTES design freeze landed on `stage-k` — K-D1 + K-D2 LOCKED from the Stage K pre-flight Opus beat (STAGES_OVERVIEW.md Stage K row + FINDINGS.md OQ-8 / OQ-9 / OQ-10 / OQ-11 / OQ-22 / OQ-25 survey + the `IVotingWeight` stub + the `GaugeRegistry` / `MiliariumRegistry` `setGovernanceContract` precedent). K-D3—K-D9 forward-declared, each locking at its unit pre-flight. No code surface landed yet. Companion to STAGE_K_PLAN.md (lands at K0.3).
>
> **Last update:** 2026-06-07 — K0.2 NOTES design freeze (this commit): K-D1 scope + contract roster, K-D2 dependency-ordered build sequence + per-unit lock convention; K-D3—K-D9 forward-declared.
>
> **Mode:** Opus extra-high entry per §13 stage-level defaults — governance handoff, stay on Opus through the stage. K0.3 PLAN sub-step skeleton next.
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
| K-D3 | forward-declared | `AureumGovernanceAuthorizer` full design per OQ-10 — `is IAuthorizer`; immutables `GOVERNANCE_CONTRACT` / `EMERGENCY_MULTISIG` / `EMERGENCY_WINDOW_END_BLOCK`; `EMERGENCY_WINDOW_BLOCKS = 2_628_000` (12 protocol months); `canPerform` routing (governance = all authorizer-gated; multisig = emergency-action-set ∧ `block.number < EMERGENCY_WINDOW_END_BLOCK`); exact emergency-action-ID set (`pauseVault` / `enableRecoveryMode` / `disableQuery`?) resolved at K1 pre-flight from Vault action IDs. | OQ-10 (FINDINGS L722-794); FINDINGS L537 `EMERGENCY_WINDOW_END_BLOCK` | K1 |
| K-D4 | forward-declared | TVL oracle binding for vote-weighting — reuse `src/emission/TVLOracle.sol` (OQ-22 svZCHF valuation, already concrete) vs a governance-local oracle. Pre-flight recommendation: reuse. | OQ-22 (FINDINGS L1106); `src/emission/TVLOracle.sol`; `src/ccb/ITVLOracle.sol` | K2 |
| K-D5 | forward-declared | `VotingWeight` value-weighted view — `(qualified_AuMT_value × time_in_pool_capped)^(1/4 → 1/3)` over the `EmissionDistributor` recorder clock; 14-day cliff, 6-month on-ramp, F-9 era root, gauged-only; `is IVotingWeight` (I9.1 stub). I-D17 `totalSupply()` denominator = total qualified voting weight (pre-flight recommendation), fixing the veto-bps semantic. | I-D15; I-D17; OQ-25; `src/governance/IVotingWeight.sol`; F-9 | K3 |
| K-D6 | forward-declared | `AureumGovernance` three proposal types (gauge challenge F-12 / composition challenge / fee proposal) + F-9 dampening + snapshot voting + timelock. Sub-splits K-D6a—K-D6f at K4 pre-flight: base proposal machinery, snapshot mechanism, F-9 era root, F-12 elite-tail deposit, per-type quorum/majority/deposit, timelock + execution routing. | STAGES_OVERVIEW Stage K L245-252; OQ-7 / OQ-8 / OQ-9 / OQ-11 / OQ-13; F-9 / F-12 | K4 |
| K-D7 | forward-declared | `AuMM.setMinter(EmissionDistributor)` handoff sequencing per H-D41 — deploy-script call, no AuMM contract edit; `distribute()` / `claim()` unblock from `NotMinter` at this call. | H-D41 (CLAUDE.md §11 deferred); `AuMM.setMinter` | K5 |
| K-D8 | forward-declared | `TVLOracle` H-D8 roster re-wire — re-point `_constellationRatio` to enumerate the live `MiliariumRegistry` dense view (`miliariumPoolsCount` / `miliariumPoolAt`); I13-class fix-forward on the tagged Stage H contract. | J-D8 (STAGE_J_NOTES.md); H-D8 roster; I13 blast-radius | K6 |
| K-D9 | forward-declared | Deploy + authorizer-migration sequencing — `script/DeployAuMM.s.sol` (H-D42, ~30 lines) + `script/DeployStageK.s.sol`: deploy governance stack, multisig one-shot `Vault.setAuthorizer(newAuthorizer)`, registry + gauge `setGovernanceContract` one-shots, `AuMM.setMinter`. | OQ-10 migration sequence (FINDINGS L788-792); H-D42; J-D5 / G-D16d `setGovernanceContract` | K7 |

### K-D1 — Stage K scope + contract roster — status LOCKED

Stage K ships the on-chain governance stack plus the authorizer migration that ends the Stage A—K multisig's general authority over the Vault and the protocol registries. The user scope decision (2026-06-07) narrows the stage to a tight governance handoff: D33 Aureum Router DEFERRED to Stage O; OQ-20 / OQ-21 controller yield-fee leg stays DEFERRED. Three new contracts land: `AureumGovernanceAuthorizer` (K1), `VotingWeight` (K3), `AureumGovernance` (K4). Two new scripts: `script/DeployAuMM.s.sol` (H-D42, ~30 lines) and `script/DeployStageK.s.sol` (K7). One fix-forward edit to a tagged contract: `TVLOracle` roster re-wire (K6, J-D8, I13-class). `AuMM.setMinter` is a deploy-script call (K5, H-D41) — no AuMM contract edit. Anchors: STAGES_OVERVIEW Stage K; OQ-10; user scope decision 2026-06-07; H-D41 / H-D42 / J-D8 carry-forward.

### K-D2 — Dependency-ordered build sequence + per-unit lock convention — status LOCKED

The build order is dependency-driven: K1 `AureumGovernanceAuthorizer` is self-contained and OQ-10-specified, so it lands first; K2 binds the TVL oracle that K3 `VotingWeight` needs for AuMT value reckoning; K4 `AureumGovernance` consumes `VotingWeight` plus `GaugeRegistry`, `MiliariumRegistry`, and the Vault; K5 `setMinter` unblocks emission; K6 `TVLOracle` re-wire tracks the live registry; K7 deploy + migration wires everything and executes the authorizer handoff last. Each unit's deep design locks at its own Opus pre-flight as a new K-D entry (K-D3 onward), NOT at K0.2 — Stage K is the largest stage in the sequence, and F-12 deposit math, F-9 dampening, the snapshot mechanism, and the `VotingWeight` value-curve each need a focused beat reading the canonical formulas. The §12 ambiguity-gate fires fresh at each unit pre-flight rather than wholesale at entry (generalizing the J-D8-locks-at-J4.0 precedent). Anchors: Stage K size vs Stage J; J-D8 precedent; §12 ambiguity-gate; §13 per-unit Opus pre-flight.

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
