# Aureum formal-methods bundle -- results index (PB2.12 / PB-D17)

Property -> status map for the four Aureum-owned formal surfaces: the
audit-handoff index for the Stage P-bis formal-methods bundle. Tier-1 is local
hevm symbolic proof against the compiled bytecode; Tier-2 is Act behavioural
specification authored as an artifact, with machine-checking attested
firm-side per PB-D17(ii) -- STAGES_OVERVIEW.md L411 contemplates the audit
firm commissioning Act properties, and the spec text is the negotiation
surface.

Status: PB2.12 exit BUILT per PB-D17. All four surfaces carry a
green-or-named-residual Tier-1 harness and an authored Tier-2 spec; the suite
stands at 52/52 PASS. Authored across commits 56a46dd (PB2.12a) through
1e6e6d4 (PB2.12f2) on branch stage-p-bis; this index lands at PB2.12g.
Date: 2026-07-16.

## 1. Toolchain provenance

- hevm 0.58.0 -- argotorg/hevm release/0.58.0, the native hevm-arm64-macos
  release asset (the Argot Collective repos moved off ethereum/*). Installed
  user-machine-local outside the repo tree per PB-D17(iv); no binary enters
  the repo.
- hevm version output: 0.58.0 [no git revision present]
- hevm binary sha256:
  4f6d5e0c8fc39b88c9f5edea05028b4d4ce31e399296da39d89c9cc68697b5d6
- SMT solvers: bitwuzla 0.9.1 (canonical for the suite); z3 4.15.4
  (machine-resident; ran the c-series S5 hook proofs; returns unknown on the
  P-E1-class division queries -- see the solver notes in section 2).
- Compiler: solc 0.8.26, optimizer 9999 runs, via_ir, EVM cancun -- the
  locked Vault-parity profile (CLAUDE.md section 2). The harnesses compile
  through the ordinary forge build; hevm discovers them from the forge
  artifacts.
- Act v0.2.0 -- argotorg/act, source-only upstream with zero binary release
  assets; not installed locally. The nine .act specs are authored artifacts
  grounded against the shipped v0.2.0 pass-tests: only witnessed dialect
  constructs are used, and everything outside the witnessed single-contract
  fragment routes to an explicit residual footer (section 7).

## 2. Canonical invocation and suite attestation

Run from the repo root after a forge build:

    hevm test --match prove_ --solver bitwuzla --smt-timeout 300 --max-iterations 10 --root .

Result: 52/52 PASS, zero FAIL, zero partial-exploration warnings -- 9 hook +
6 CCB + 30 emission + 7 authorizer. Attested at PB2.12f1 (commit 6eec86d).
Commits after that run (PB2.12f2 and this index) touch only formal/ -- zero
Solidity deltas -- so the attestation binds this tree's harness set
bit-for-bit.

Solver and flag notes:

- --max-iterations 10: raised at PB2.12e1. Multi-call proofs re-visit the
  target's entry pc across separate external calls; the default bound
  mis-reads that as unexplored branching.
- Per-file invoke lines that predate the bitwuzla canonicalization
  (FeeRoutingHookProofs.sol and fee_routing_hook.act name z3) record the
  historical c-series runs; the suite line above is canonical. Under z3 the
  P-E1-class division queries return unknown -- a solver-capability boundary,
  not a property failure.
- residual_score_identity (CCBEngineProofs.sol) deliberately carries no
  prove_ prefix: it is the P-S1 named-residual witness body, kept outside the
  suite match.

## 3. Layout (as-built)

- formal/act/ -- the nine Tier-2 Act specs.
- test/formal/ -- the four Tier-1 hevm harnesses. As-built amendment to the
  PB-D17(iv) sketch (a formal/hevm/ directory of runner scripts plus captured
  output): the harnesses live under test/ so the ordinary forge build
  compiles them and hevm test discovers them via --root .; the runner is the
  one-line canonical invocation above; captured output is superseded by this
  attested index.
- formal/RESULTS.md -- this file.

## 4. Status vocabulary (PB-D17(iv))

- PROVED -- hevm symbolic proof, PASS under the canonical invocation.
- BOUNDED-WITH-NAMED-RESIDUAL -- property stated and witnessed concretely;
  the general symbolic query exhausts both resident solvers; routed firm-side
  with the local pins named.
- FIRM-SIDE -- stated as a complete behavioural contract in an .act residual
  footer; outside the locally witnessed single-contract Act fragment;
  machine-checking commissioned with the audit firm (PB-D17(ii)).
- AUTHORED -- the Tier-2 .act artifact itself: complete, sentinel-clean,
  awaiting firm-side machine-check.

## 5. Tier-1 property tables

### 5.1 S5 fee-routing hook -- AureumFeeRoutingHook

Harness: test/formal/FeeRoutingHookProofs.sol (PB2.12c1/c3, 9 proofs).
Spec: formal/act/fee_routing_hook.act (PB2.12c4; operator reconciliation at
d4b).

| Property | Statement | hevm proofs | Status |
|---|---|---|---|
| P-H1 | each module lock is one-shot: the first bind seals the slot (governanceModule, incendiaryModule, emissionRecorder) | prove_governanceModule_setOnce, prove_incendiaryModule_setOnce, prove_emissionRecorder_setOnce | PROVED |
| P-H2 | pre-seal auth gate: only the module admin may bind; the admin burns on success | prove_setGovernanceModule_onlyAdmin, prove_setIncendiaryModule_onlyAdmin, prove_setEmissionRecorder_onlyAdmin | PROVED |
| P-H3 | zero-rejection on all three module setters | prove_modules_rejectZero | PROVED |
| P-H5 | lock independence: binding one module leaves the sibling locks live | prove_locks_independent | PROVED |
| P-H6 | persistent governance gate: only the bound governanceModule may call setTrustedRouter | prove_setTrustedRouter_gate | PROVED |
| P-H7 | onAfterSwap fee conservation (the OQ-1 50/50 seam): value routed to der Bodensee plus the LP residual equals the protocol fee taken; no diversion path | none -- cross-contract Vault seam | FIRM-SIDE |

P-H4 is unassigned: the ID is vacant in the roster; no proof or residual
carries it.

### 5.2 S7 CCB / EMA engine -- EMASampler + CCBMultiplier

Harness: test/formal/CCBEngineProofs.sol (PB2.12d1-d3, 6 proofs plus the
named-residual witness). Specs: formal/act/ema_sampler.act and
formal/act/ccb_multiplier.act (PB2.12d4).

| Property | Statement | hevm proofs | Status |
|---|---|---|---|
| P-E1 | convex hull: one smoothed updateEMA step keeps the EMA within [min(old, spot), max(old, spot)] | prove_ema_convexHull | PROVED (bitwuzla; z3 unknown) |
| P-E2 | seed bookkeeping: the cold-start update (last == 0) seeds the EMA from spot and stamps the cadence | prove_ema_seedPath | PROVED |
| P-E3 | cadence guard, two-phase: the guard holds inside the sampling cadence and releases past the boundary | prove_ema_cadenceGuard | PROVED |
| P-M1 | the F-D20 registry one-shot: the deployer's first set binds and seals; pre-seal auth gate; zero-rejection | prove_registry_setOnce, prove_setMiliariumRegistry_onlyDeployer, prove_registry_rejectZero | PROVED |
| P-S1 | the F-5 CCBScore identity | residual_score_identity (witness body outside the prove_ match) | BOUNDED-WITH-NAMED-RESIDUAL |
| P-S2 | score monotonicity / zero-absorption | folds into P-S1: the both-operands-symbolic form is strictly harder | BOUNDED-WITH-NAMED-RESIDUAL |

P-S1/P-S2 residual: the FixedPoint mulDown overflow-guard query exhausts both
z3 and bitwuzla. The arithmetic substrate is audited Balancer FixedPoint; the
identity is pinned concretely by the CCBScore unit tests.

### 5.3 Emission accrual -- AuMM + AuMMMinterRouter + EmissionDistributor + BodenseeBootstrapChannel

Harness: test/formal/EmissionProofs.sol (PB2.12e1-e3, 30 proofs;
multi-contract rig including the MockVaultForChannel getPoolTokens stub).
Specs: formal/act/aumm.act and formal/act/aumm_minter_router.act (PB2.12e4a);
formal/act/emission_distributor.act and
formal/act/bodensee_bootstrap_channel.act (PB2.12e4b).

| Property | Statement | hevm proofs | Status |
|---|---|---|---|
| P-A1 | the 21M cap: mints summing to at most the cap succeed; any overshoot reverts | prove_mint_withinCap, prove_mint_capExceeded | PROVED |
| P-A2 | the C-D11 setMinter lock: one-shot, admin-gated, zero-rejected | prove_setMinter_onlyAdmin, prove_setMinter_oneShot, prove_setMinter_rejectZero | PROVED |
| P-A3 | mint auth: only the bound minter mints; the unbound slot mints for no caller | prove_mint_requiresMinter, prove_mint_unboundReverts | PROVED |
| P-A4 | the emission curve: pre-genesis zero; exact era value; halving step at every era boundary; exhaustion from era 60 | prove_curve_preGenesisZero, prove_curve_eraValue, prove_curve_halvingStep, prove_curve_exhausts | PROVED |
| P-R1 | the router allowlist: mintFor reverts for every non-consumer; both consumers forward exact amounts | prove_router_allowlistGate, prove_router_bothConsumersMint | PROVED |
| P-R2 | the 21M cap survives composition through the router | prove_router_capHoldsThroughRouter | PROVED |
| P-ED1 | distributor setMintRouter: one-shot, governance-gated, zero-rejected | prove_distributor_setMintRouter_onlyGovernance, prove_distributor_mintRouter_setOnce, prove_distributor_setMintRouter_rejectZero | PROVED |
| P-ED2 | per-pool AuMT bind: one-shot per pool, pool-independent, zero-rejected | prove_distributor_auMT_setOncePerPool, prove_distributor_auMT_poolIndependence, prove_distributor_auMT_rejectZero | PROVED |
| P-ED3 | distributor governance rotation: two-phase, old authority locked out, new authority live | prove_distributor_governanceRotation | PROVED |
| P-ED4 | incendiary-registry gate plus the H-D29 zero-permitted deprecation valve | prove_distributor_setIncendiaryRegistry_gateAndClear | PROVED |
| P-BC1 | channel setMintRouter: one-shot, governance-gated, zero-rejected | prove_channel_setMintRouter_onlyGovernance, prove_channel_setMintRouter_setOnce, prove_channel_setMintRouter_rejectZero | PROVED |
| P-BC2 | channel governance rotation: two-phase, zero-rejected | prove_channel_governanceRotation, prove_channel_setGovernanceContract_rejectZero | PROVED |
| P-BC3 | accrue structural guards: same-block re-accrue is idempotent (empty interval); pre-genesis no-op; the post-window clamp collapses to the constant month10End | prove_channel_accrue_emptyIntervalIdempotent, prove_channel_accrue_preGenesisNoOp, prove_channel_accrue_postWindowClamp | PROVED |

The STAGES_OVERVIEW.md L411 candidate properties map onto this table: "21M
cap never exceeded" -> P-A1 + P-R2 + the aumm.act inductive invariant;
"era-boundary emission exactness" -> P-A4; "no admin-key redirect path" ->
P-ED1 (with P-BC1, P-A2, P-M1, and P-H1/P-H2 as the same lock class on the
other surfaces).

### 5.4 Authorizer window -- AureumGovernanceAuthorizer + AureumAuthorizer (legacy)

Harness: test/formal/AuthorizerProofs.sol (PB2.12f1, 7 proofs). Specs:
formal/act/aureum_governance_authorizer.act and
formal/act/aureum_authorizer.act (PB2.12f2).

| Property | Statement | hevm proofs | Status |
|---|---|---|---|
| P-W1 | governance authority is unconditional and window-independent | prove_gov_omnipotent | PROVED |
| P-W2 | the emergency time-bomb, three legs: both emergency actions live at every in-window block; dead at exactly the boundary and permanently after (strict <, immutable inputs, no revival path); scope is exactly the two action IDs | prove_emergency_inWindow, prove_emergency_deadFromBoundary, prove_emergency_scopeLimited | PROVED |
| P-W3 | every non-principal account is denied every action at every block | prove_stranger_nullity | PROVED |
| P-W4 | the two action-ID immutables match the Balancer Authentication.getActionId encoding and are distinct | prove_actionId_binding | PROVED |
| P-W5 | the legacy from-state ahead of the K7 setAuthorizer migration: single-principal equality gate, both directions | prove_legacy_authorizer_gate | PROVED |

## 6. Tier-2 spec roster (all AUTHORED; machine-check firm-side)

| Spec | Models (creates / invariants / transitions) | Residual footer(s) |
|---|---|---|
| fee_routing_hook.act | creates + invariants; setGovernanceModule, setIncendiaryModule, setEmissionRecorder, setTrustedRouter | P-H7 onAfterSwap fee conservation |
| ema_sampler.act | creates + the three per-pool view getters (tvlEMA, lastEMAUpdateBlock, emaSeedBlock) | updateEMA (oracle call + block-number read) |
| ccb_multiplier.act | creates; setMiliariumRegistry (the F-D20 lock), getMultiplier view | updateMultiplier (cross-contract) |
| aumm.act | creates + invariants (totalSupply at most 21_000_000e18, inductive; minter != 0 implies minterAdmin == 0); setMinter, mint | blockEmissionRate (dialect: the >> halving) |
| aumm_minter_router.act | constructor guard only -- no storage fragment | mintFor (two-principal allowlist + cross-contract forward) |
| emission_distributor.act | creates + invariants (governance != 0, lifetime); setGovernanceContract, setAuMTContractForPool, setIncendiaryRegistry, setMintRouter | the accrual/settle/score/claim engine, headline H-D26 |
| bodensee_bootstrap_channel.act | creates + invariants (governance != 0, lifetime); setGovernanceContract, setMintRouter | accrue(); distribute() (the H-D12 seam); constructor roster-lookup flag |
| aureum_governance_authorizer.act | constructor iff only; zero transitions | canPerform (environment read) |
| aureum_authorizer.act | creates; canPerform fully modelled | none |

## 7. Residual taxonomy -- the firm-side worklist

Three .act residual classes, plus the one Tier-1 named residual:

(a) Cross-contract fragment -- the body leaves the single-contract Act
fragment:

- P-H7 onAfterSwap fee conservation (fee_routing_hook.act). Pins: the hook
  unit suite; the PB2.4d2 mainnet-fork sandwich sim.
- updateEMA (ema_sampler.act) -- oracle call plus block-number cadence read.
  Pins: P-E1..P-E3 against bytecode; the EMASampler unit tests.
- updateMultiplier (ccb_multiplier.act). Pins: P-M1 against bytecode; the
  CCBMultiplier unit tests.
- mintFor (aumm_minter_router.act) -- allowlist plus forward into AuMM.
  Locally PROVED against bytecode as P-R1/P-R2; residual only as an Act
  fragment.
- The distributor engine (emission_distributor.act) -- recordScore,
  recordDeposit, recordWithdrawal, syncPosition, claim, pendingClaim and
  helpers. Headline sweep target: the H-D26 cross-contract conservation
  identity, LP integral + Bodensee apsum + Incendiary integral =
  blockEmissionRate x elapsed blocks. Pins: the P6.5 640k-call invariant
  harness; the H5.4 arithmetic-identity tests; the EmissionDistributor unit
  suite; the P-D18 sync forfeit-delta rule.
- accrue() and distribute() (bodensee_bootstrap_channel.act) -- distribute()
  is the H-D12 Vault-DONATION seam; accrue() is stated as a residual
  behavioural contract (clamp / rate / AP-sum / post, on the P-D19/F-18
  clamped-not-live basis); the constructor's getPoolTokens roster lookup is
  flagged for conjunction into the firm's constructor model. Pins: P-BC3
  against bytecode; the channel unit tests; the P6.5 harness.

(b) Dialect boundary -- single-contract content whose shape is unwitnessed in
the v0.2.0 pass-tests:

- blockEmissionRate (aumm.act) -- the GENESIS_RATE >> era geometric halving.
  Locally PROVED against bytecode as the P-A4 quartet.
- The distributor's nested two-key user mappings -- storage shape
  unwitnessed; the engine tier above is therefore doubly residual (dialect
  shape plus cross-contract bodies).

(c) Environment read -- no external call; the only non-witnessed element is a
block-number reference:

- canPerform (aureum_governance_authorizer.act). The residual footer states
  the complete behavioural contract; the firm may model it directly if its
  v0.2.0 grammar witnesses the block reference. Locally PROVED against
  bytecode as P-W1..P-W4.

(d) Tier-1 named residual -- solver exhaustion, not a modelling boundary:

- P-S1/P-S2 (CCBEngineProofs.sol) -- the FixedPoint mulDown overflow-guard
  query exhausts z3 and bitwuzla; executable witness body
  residual_score_identity. Substrate: audited Balancer FixedPoint. Pins: the
  CCBScore unit tests.

## 8. Scope exclusions

Vault.sol, VaultAdmin.sol, VaultExtension.sol and the wider Balancer V3
substrate are byte-identical to the audited mainnet deployment (CLAUDE.md
sections 1-2) and are not re-proven here; the K7 Vault.setAuthorizer dispatch
is that substrate. The OpenZeppelin ERC20 base is upstream-audited. The
Part-A unit suite (908 tests), the fork suites, the P6.5 invariant harness,
and the whitehat F-ledger are complementary evidence layers outside this
bundle, cross-referenced above as pins.
