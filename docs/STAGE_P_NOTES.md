# STAGE_P_NOTES.md — Stage P Design Freeze + Findings Log

**Stage:** P — Full-System Integration Deployment + White-Hat Back-Fill Sweep.
**Status:** Design freeze. Locked 2026-06-30 on branch `stage-p` (cut from `main` @ f50b4cd = `stage-o-complete`). Execution truth until superseded by explicit amend. No code lands until this freeze locks (§12 ambiguity-gate).
**Canonical spec:** testnet strategy `FINDINGS.md` OQ-15 / OQ-16 (hybrid: testnet stubs + mainnet fork); frontend `FINDINGS.md` OQ-18 (separate repo `aumm-app`); audit firm OQ-17 (deferred). White-hat methodology `docs/white_hat/AUREUM_WHITEHAT_PROCESS.md` (S0–S12 surfaces, INV-1…INV-6, the one-surface-per-step cadence). This file records repo-side decisions; canonical-spec prose edits are user-owned follow-up.
**Related:** `STAGES_OVERVIEW.md` Stage P (L340–363); `docs/white_hat/AUREUM_WHITEHAT_PROCESS.md` (process) + `AUREUM_WHITEHAT_OUTPUT.md` (F-01…F-12 ledger, zero open); `STAGE_O_NOTES.md` O-D4 (orphaned `CCBMultiplier.activateBoost`) + O-D5 (Router, D33 closed); `STAGE_I_NOTES.md` / `STAGE_I_PLAN.md` I-D14 (AuMT = BPT, no `AuMT.sol`); prior whitehat passes WK / WK-R / WM / WN / WO.

**Framing.** Stage P is the first stage where the whole stack runs as one system — the integration boundary every prior stage built toward. Two workstreams: **(A)** the white-hat back-fill sweep that *opens* the stage (the per-stage audit cadence began at the Stage K close, so Stages D / G / H / I / J / L were never audited in isolation), and **(B)** full-system deployment (testnet stubs + network-parameterised deploy scripts + dual integration validation). Both feed one goal: pre-audit hardening before Stage Q's external audit + code freeze. The live testnet broadcast and the `aumm-app` frontend wiring are a gated sub-phase **P-bis**, deferred out of Stage P proper (§8c — no live-network broadcast). Stage P closes on the audit sweep + a Foundry invariant harness + Tenderly mainnet-fork e2e validation; the `STAGES_OVERVIEW.md` "2–3 weeks" estimate predates this two-workstream split.

---

## P-D0 — Scope: two workstreams (A white-hat sweep opens; B deployment), gated P-bis.

Stage P has two workstreams. **(A) White-hat back-fill sweep** — runs first (P-D5 / P-D6), one surface × one contract per step per `AUREUM_WHITEHAT_PROCESS.md`. **(B) Full-system deployment** — testnet token stubs (P-D2), network-parameterised deploy scripts (P-D1), a full-stack orchestrator, and the Balancer V3 substrate redeploy (P-D6 workstream-B items). The live Hoodi broadcast + the `aumm-app` frontend wiring (OQ-18, external repo) is a gated sub-phase **P-bis**, deferred — no live-network or mainnet broadcast within Stage P proper (§8b / §8c). **P-D0b dual validation:** Tenderly mainnet-fork e2e against REAL mainnet token literals is the primary `stage-p-complete` gate; the Hoodi-with-stubs deployment is P-bis. Sweep-before-deploy ordering is deliberate — the deploy scripts wire contracts the sweep may patch fix-forward, so auditing first avoids re-deploying around a finding.

## P-D1 — Testnet posture: network-agnostic; live target deferred to P-bis (supersedes OQ-16 Holesky).

OQ-16 chose Holesky (2026-04-15); Holesky was sunset September 2025. The replacement is **Hoodi** — the latest Ethereum Foundation L1 testnet, runway ~2028; Sepolia sunsets September 2026, so Hoodi is the durable choice. OQ-16 itself anticipated exactly this ("If/when Holesky is deprecated and replaced (Hoodi or whatever succeeds it), the stub deployments migrate … an operational choice, not a constitutional one"). Deploy scripts are **network-parameterised** (RPC URL + chain-id read from env), so Sepolia is a drop-in fallback and no script is hard-coded to one testnet. This operationally supersedes the named Holesky in OQ-15 / OQ-16. **P-D1b:** amend the OQ-15 / OQ-16 Holesky→Hoodi references in `FINDINGS.md` (and the `STAGES_OVERVIEW.md` Stage P heading + body) in a dedicated docs sub-step — same class as O-D3's stale-doc strikes. Canonical aumm-site names no testnet, so no spec edit is required.

**Amended (testnet reconciliation — 2026-07-01).** As first locked, P-D1 named Hoodi as *the* testnet. A cross-check against current EF-testnet guidance sharpened the picture: **Sepolia** stays the app-dev / dApp / frontend default — the strongest faucet, wallet, indexer, and Tenderly tooling, the layer that matters for the OQ-18 frontend MVP — with a planned EOL ~Sep 2026; **Hoodi** is the durable Holesky successor (permissionless validator set, no announced sunset) but is staking / protocol-oriented with thinner app tooling. Neither hosts any Aureum-referenced token, so both need the P-D2 stubs regardless — Sepolia's ecosystem edge accrues only to the frontend layer, not the contract-integration layer. The original one-liner over-weighted runway and undersold Sepolia's app-dev fit. **Reframe:** the deploy scripts stay network-agnostic (RPC + chain-id from env — already the design); the primary Stage-P validation is the mainnet fork (P-D0b); the live public-testnet target is a **P-bis decision made on the then-current calendar** — Sepolia if the frontend / validation window closes before its ~Sep 2026 EOL (its tooling wins, and the EOL is moot with mainnet as the terminal stage), Hoodi if that window slips past it (avoiding a repeat of the OQ-16 Holesky-shutdown migration). Hoodi stays the concrete env example for durability; the choice is not re-committed to one named testnet. **P-D1b accordingly strikes the stale "Holesky" toward this network-agnostic framing, not a blind "Hoodi" substitution.** This supersedes the "Hoodi, full stop" reading of the paragraph above; OQ-16's "Holesky now" is operationally retired either way.

## P-D2 — Testnet token stubs, tiered. The OQ-15 named list is an anchor, not the inventory.

OQ-15 names svZCHF, sUSDS, ixEDEL, and "the major theme tokens" as stub targets. That list is an **anchor, not the full inventory**: the 26 deployable Miliarium pools (Stage M + N constellation, on-disk `script/pools/configs/`) reference a far wider token set — wstETH / fWSTETH / fWETH / sfrxETH / wOETH / rETH / weETH; USDC / USDT / PYUSD / GHO / scrvUSD / ysyBOLD; WBTC / cbBTC; LINK / AAVE / SKY / MORPHO; the `*on` tokenised equities (QQQX / ETHPLUS / BACON / BLKON); and more. The stub strategy is **tiered** so the population is covered without one bespoke stub per token:

- **Tier A — protocol anchors.** Named, spec-faithful, hand-written stubs that reproduce the real token's interface contract and value-shape: svZCHF, sUSDS, ixEDEL (NAV / DTF shape). Under the same audit-inheritance discipline as the real contracts (OQ-15 implementation note: deterministic, non-upgradeable, well-documented).
- **Tier B — generic ERC-4626.** One `StubERC4626` template (plus an optional waEth-style wrapper variant), instantiated N times via deterministic salts / names. Covers the yield-bearing-wrapper population.
- **Tier C — generic ERC-20.** One `StubERC20` template covering the `*on` equities, the BTC wrappers, the plain stables, and the JPYC / tGBP / fBRZ stand-ins.
- **Tier D — wiring.** `test-stubs/TestnetTokenRegistry.sol` (or a JSON env-map) maps each pool config's literal token slot → its deployed stub address, mirroring the mainnet env-injection convention already used in `DeployIxAetheron`.

**Explicit non-stubs.** **AuMM** deploys as REAL protocol code on testnet (it is the token, never a stub). The Aureum-owned Rate Providers — `ERC4626RateProvider`, `CompositeRateProvider` (`src/rate_provider/`, Stage N) — deploy REAL (not stubs); their `getRate()` reads simply point at the Tier-A / Tier-B stubs. **04 ixViatica / 07 ixCambio stay deferred** (fBRZ / aEURS / JPYC / tGBP stubs are optional, non-blocking for the 26-pool constellation; the E-D17 verified-literal bar is a mainnet concern, not a testnet one). The **Balancer V3 substrate on Hoodi** — Vault + factories + the Router redeploy (D33 / O-D5) — is a workstream-B prerequisite, **not** implied by the stub set; it is the substrate the stubs and the Aureum contracts deploy *onto*.

## P-D3 — Broadcast-gated execution.

Stage P delivers deploy scripts + Tenderly mainnet-fork e2e validation. The `--broadcast` flag against any live network (Hoodi or mainnet) is **not** run within Stage P (§8b network-action approval; §8c mainnet-broadcast ban). The integration surface inside Stage P is the Tenderly-fork devnet. The live Hoodi broadcast + the frontend wire-up is P-bis (P-D0).

## P-D4 — Branch posture: fresh `stage-p` off `main`; two-commit PENDING_P close.

Stage P proceeds on `stage-p`, cut from `main` @ f50b4cd (= `stage-o-complete`), per the canonical per-stage branch convention (O-D8 precedent). Close: tag `stage-p-complete`, ff-merge to `main`. The close uses the **two-commit PENDING_P convention**: the close commit writes a literal `PENDING_P` placeholder wherever the close-commit hash will go (the `STAGES_OVERVIEW.md` master row + the `STAGE_P_PLAN.md` completion log; CLAUDE.md §11 stays hash-free), then a separate `*-backfill` commit substitutes the real hash, and the `stage-p-complete` tag sits at the **backfill** commit. Mirrors Stage N (a760421 → ef8cf54) and Stage O (e69252f → f50b4cd).

## P-D5 — White-hat methodology = the process doc; Stage-P-sweep scope = back-fill + cross-seam.

The sweep runs per `docs/white_hat/AUREUM_WHITEHAT_PROCESS.md`: **one exploit-surface × one contract = one step** (§1), the S0–S12 master catalog (§7) filtered to what each contract exposes, no chaining, an attestation checkpoint per step (§5). Every finding becomes a row in `AUREUM_WHITEHAT_OUTPUT.md` (schema §0) and every step updates the pass's coverage roll-up. The **Stage-P sweep** is the two things the process doc names (§2): **(a) back-fill** — the per-stage audit cadence began at the Stage K close (process-doc §2, decided 2026-06-10), so Stages D / G / H / I / J / L were never audited in isolation; Stage P runs those passes now. **(b) cross-seam** — the cross-contract / cross-stage seams a per-stage pass sees only in isolation (process-doc §2: "spends its budget on … cross-contract and cross-stage seams"). Fixes land **fix-forward / I13-class** — a patch to a tagged-complete stage's contract lands on `stage-p`, no re-tag (I-D13 / O-D7 precedent).

## P-D6 — Pass ordering + the named cross-seam catalog.

**Back-fill passes** (ledger-named, severity-ordered per process-doc §4), with the contracts each pass scopes:

- **WH-D** — `AureumFeeRoutingHook` + `AureumProtocolFeeController` (Stage D fee-routing surface: S2 conservation, S5 hook hot path, S6 reentrancy).
- **WH-G** — `VaultClassRegistry`, `SwapAndDepositToBodensee`, `GaugeEligibility`, `GaugeRegistry` (Stage G gauge surface: S8 access, S9 gauge-gaming, S4 the 52% composition floor).
- **WH-H** — `BodenseeBootstrapChannel`, `EmissionDistributor`, `AuMMMinterRouter`, plus the Stage-F CCB engine carried into the emission path (`EMASampler`, `EfficiencyOracle`, `TVLOracle`, `CCBMultiplier`, `CCBScore`, `CCBShare`): S1 supply / mint, S7 TVL-EMA.
- **WH-I** — the **AuMT governance-spine surface**. Per OQ-25 / I-D14 there is **no `AuMT.sol`** — AuMT is the pool's own Balancer V3 BPT; the spine is the recorder clock (`EmissionDistributor.recordDeposit` / `recordWithdrawal`, `effectiveQualBlock`), the `AureumFeeRoutingHook` liquidity-callback dispatch (the F-09 recorder-attribution surface), the `VotingWeight` gauged-only qualification reader, and the `setGovernanceContract` / recorder-binding gates. Lens is S9 attribution-integrity + S8 recorder gate — **not** a re-audit of the host contracts' S1 / S2 surfaces (covered by WH-H / WH-D).
- **WH-J** — `MiliariumRegistry` (Stage J registry surface: S8 slot-mutation access, S9 roster gaming).
- **WH-L** — `IncendiaryRegistry` + the `EmissionDistributor` boost leg (L-D25). The earlier WL pass was a SPOT-only review that surfaced F-07; the formal WL pass was explicitly deferred to Stage P.

SKIP the already-completed WK / WK-R / WM / WN / WO passes unless a fix-forward diff reopens their surface (P-D11).

**Ordering:** WH-D → WH-G → WH-H → WH-I → WH-J → WH-L → cross-seam → INV-2 harness → O-D4 fix (P-D8) → hevm (optional, P-D9).

**Named cross-seams** (enumerated so the PLAN matrix is mechanical):

- **(a) Channel ↔ distributor mint split** — `BodenseeBootstrapChannel` ↔ `EmissionDistributor` (INV-2 / H-D2): the LP + bootstrap + boost legs must sum to the scheduled emission, no double-mint.
- **(b) Hook ↔ AuMT recorder attribution** — `AureumFeeRoutingHook` ↔ `EmissionDistributor` recorder, post-F-09 deploy binding (the `trustedRouter` allowlist must seat the true LP identity).
- **(c) Governance ↔ registry `onlyGovernance` gates** — `AureumGovernance` ↔ `GaugeRegistry` / `MiliariumRegistry` / `VaultClassRegistry` (WK.8 carry-forward).
- **(d) Miliarium roster ↔ TVLOracle dedup** — `MiliariumRegistry` ↔ `TVLOracle` (WK.15 → WH-J): no slot counted twice in the protocol-wide TVL aggregate.

**Workstream-B items** (run alongside / after the sweep): the full-stack orchestrator (`DeployStageP.s.sol` or a chained `DeployStage*` sequence), the Balancer V3 Router redeploy bound to the Aureum Vault (D33 / O-D5), and the Tenderly mainnet-fork e2e (real mainnet literals, not stubs).

## P-D7 — Invariant harness IDs (per process-doc §10).

The Stage P Foundry invariant harness encodes these process-doc invariants:

- **INV-1 + INV-6** — total AuMM ever minted ≤ 21,000,000, never exceeded across **all** mint paths (LP emission, bootstrap channel, boost leg); only the one-shot minter mints. The crown-jewel S0 supply property.
- **INV-2** — emission conservation against an **independent** `ReferenceEmission.cumulativeAt(block)`: LP + bootstrap + boost = total, checked against a reference re-implementation, never the contract's own getter (the non-circular check, process-doc §10).
- **INV-3 / S0** — fee-split conservation: the 50/50 split is immutable, the creator fee is zero, every extracted fee reaches der Bodensee (none skimmed, stuck, or rerouted).
- **INV-4 (optional)** — vault solvency (real balances ≥ accounted balances), added only if the Tenderly e2e harness touches real Balancer pools.

**Removed: governance-weight monotonicity is NOT an invariant.** It is not an S0 / INV property — F-02 surfaced that an AuMT (BPT) position split *raises* the summed governance weight by design: the value-weighting raises `(value × time)` to a power below 1 (the F-9 quarter-to-third exponent), which is sub-additive, so splitting one position into two raises the sum. Monotonicity-under-split would therefore be a false invariant; it is not in the §10 catalog and is not harnessed. The **INV-2 harness lands after WH-H** (ideally after the cross-seam pass) — it encodes the channel ↔ distributor split (cross-seam (a)) that the white-hat pass must first characterise, so the harness is written against a characterised surface, not a guessed one.

## P-D8 — `CCBMultiplier.activateBoost`: deprecate-and-remove (decision split from implementation).

**Decision (locked at this freeze).** Default to **deprecate-and-remove** `activateBoost` and its boost machinery (`BOOST_FACTOR = 12e17`, `GAUGE_BOOST_DURATION_BLOCKS = 648_000`, the `boostExpiryBlock` mapping, the `BoostAlreadyActive` revert). Rationale (O-D4 carried forward): O-D3 / G-D13 plus the Incendiary path make it dead product surface — there is no boost at gauge activation; cold-start support is the user-funded Incendiary Boost (Stage L). `activateBoost` has zero production callers (only tests exercise it); externally-reachable, unused code on a tagged stage is unnecessary attack surface.

**Implementation (deferred, not at this freeze).** The removal is executed **after the WH-H attestation clears `CCBMultiplier`** — `activateBoost` is CCB / Stage-F surface, not hook surface, so the removal follows WH-H, not WH-D — and is slotted in the P-D6 ordering after the INV-2 harness. Controlling phrasing: *"presumed deprecate per O-D3 unless WH-H surfaces a re-wire requirement."* The removal is **not** a one-liner: `boostExpiryBlock` is read on the multiplier hot path (the `BOOST_FACTOR` return branch in the multiplier read + the early-return in the cadence guard), so excising the writer requires retiring those read branches in the same change — an I13-class blast-radius sized at the removal sub-step's pre-flight. `CCBMultiplier` is `stage-f-complete`-tagged → the removal lands **fix-forward on `stage-p`, no Stage-F re-tag**.

## P-D9 — hevm symbolic-execution pass: optional pre-audit shakeout, not a close gate.

Target surfaces (`STAGES_OVERVIEW.md` Stage P symbolic-pass bullet): **S5** (the OQ-1 fee-routing hook), **S7** (the CCB multiplier / EMA engine), and **S8 relabelled for Stage P** to the `AureumGovernanceAuthorizer` timelock / emergency-window invariants + the `Vault.setAuthorizer` one-shot migration window — **not** generic S8 access-control. **hevm install is a §8b dependency decision deferred to the P7 sub-step** (not pre-committed at this freeze). hevm is an **optional** pre-audit shakeout, **not** a `stage-p-complete` gate — Stage Q owns the formal-verification budget. Keep hevm (Stage P, optional) and Act (Stage Q) **separate** in NOTES and PLAN. If the install is blocked at P7, attest "hevm deferred to Q" and still close Stage P on the white-hat sweep + the invariant harness + Tenderly e2e.

## P-D10 — Test strategy.

- **White-hat** — audit read-lens (cite line numbers, never reason from function names per process-doc §8) + Foundry PoCs in `test/whitehat/`, mirroring the F-01…F-12 convention.
- **Invariants** — a Foundry invariant harness (P-D7), `runs >= 5000` for the pre-audit gate (process-doc §10).
- **Deployment** — Tenderly mainnet-fork e2e against real mainnet token literals (P-D0b).
- **Regression** — split-form after each landing: `forge test --no-match-path "test/fork/**"` for unit + `forge test --match-path "test/fork/**" --fork-url $MAINNET_RPC_URL --threads 1` for fork (D35 / D36); `forge clean && forge build` after any structural test-file rewrite (F14).

## P-D11 — Back-fill scope: not a re-audit of K–O.

The per-stage cadence (process-doc §2) began at the Stage K close; the WK / WK-R / WM / WN / WO passes already raised F-01…F-12, all **Fixed**, zero open (`AUREUM_WHITEHAT_OUTPUT.md`). The Stage-P white-hat passes are **back-fill of the never-audited pre-K stages** (D / G / H / I / J / L), **not** a re-audit of the K / L / M / N / O fixes — unless a fix-forward diff reopens a surface (e.g. O-D2 / F-12 touched `GaugeEligibility`, so a WH-G finding there could re-expose K-era wiring). The sweep inherits the floor the per-stage passes raised (process-doc §2) and spends its budget on the back-fill + the named cross-seams (P-D6).
