# Stage D — Fee-routing hook + der Bodensee

> **Status:** Ready to start. Stage C is complete at `stage-c-complete` (commit `5342126`, 2026-04-18). Prerequisites checked and green on 2026-04-19: 92/92 tests green on mainnet fork (89 unit + 3 fork).
>
> **Audience:** Sagix, plus any future Claude session that needs to know what Stage D is and what it produces.
>
> **Why this file exists:** so the plan survives outside chat scrollback. This file is the entry point for Stage D work.

---

## Scope of Stage D

**Goal:** close the F1 architectural gap. Ship the OQ-1 fee-routing hook, the der Bodensee deployment script (fork-only at this stage; mainnet deploy is Stage R), and the three corresponding modifications to `AureumProtocolFeeController` that OQ-1 / OQ-2 / OQ-11 require.

**The Solidity files Stage D produces:**

1. **`src/fee_router/AureumFeeRoutingHook.sol`** — Aureum-authored Balancer V3 hook contract. Implements `IHooks.onAfterSwap` and houses the shared **swap-and-one-sided-deposit primitive** used by all three fee layers (swap-fee leg, ERC-4626 yield-fee leg, governance/Incendiary deposits) per the OQ-1 table. Primitive: take the incoming fee token, swap it to svZCHF via Balancer V3's Vault router (per OQ-2), then one-sided-add the svZCHF into der Bodensee. Constructor takes immutable Vault / Bodensee / svZCHF / AuMM addresses plus the protocol-fee-controller address (for the yield-leg caller gate). Custom errors, not revert strings. No upgradability. No admin keys. ~250 LOC (larger than a pure library because it wires Vault callbacks + internal swap orchestration + three caller-gated entry points).

2. **`src/fee_router/IAureumFeeRoutingHook.sol`** — thin interface. Declares the external primitive entry points (shape decided at D2 per D-D2 — either three separate functions `routeYieldFee` / `routeGovernanceDeposit` / `routeIncendiaryDeposit`, or a single `routeExternalDeposit(CallerType, token, amount)`), plus the events, the constants, and the getters for the immutable addresses. Stage D's `AureumProtocolFeeController` (modified) imports this. Later stages (K governance, L Incendiary) will import it too. Matches Stage B's `IProtocolFeeController` and Stage C's `IAuMM` patterns. ~60 LOC.

3. **Modifications to `src/vault/AureumProtocolFeeController.sol`** — one pre-flight edit in D0.5 (per D-D15) plus three targeted edits in D4 (per D-D7 / D-D8 / D-D9):
   - **D0.5 — upstream setter retrofit (per D-D15).** Remove / override the inherited public setter for `protocolSwapFeePercentage`; the 50/50 split is immutable at pool registration per CLAUDE.md §2 "hard rule". Any runtime call to the setter reverts `SplitIsImmutable` (or equivalent custom error finalised at D0.5.2 draft time). Lands before D1 so D4 edits build on a clean base.
   - **B10 retarget.** The immutable enforcement target (currently named `DER_BODENSEE_POOL` or similar — exact identifier confirmed at D4.1) is renamed / retargeted to the hook contract's address. B10's check stays in place; it just points at the hook rather than at Bodensee directly. One immutable rename, one error-message update, one constructor-parameter name change.
   - **OQ-11 Bodensee fee band relaxation.** The existing B8 immutability on Bodensee's 0.75% is relaxed. Replace any pinned single value with three band constants: `BODENSEE_SWAP_FEE_MIN = 0.001e18`, `BODENSEE_SWAP_FEE_MAX = 0.01e18`, `BODENSEE_SWAP_FEE_GENESIS = 0.0075e18`. Genesis default is unchanged at 0.75%; adjustability within the 0.10%–1.00% band is a Stage K concern (the governance call path), but the band constants land here so the rate ceases to be pinned at construction time.
   - **OQ-2 Bodensee yield-fee exclusion.** Add a revert in `collectAggregateFees(pool)` when `pool == DER_BODENSEE_POOL`. Bodensee's ERC-4626 composition compounds in-pool via Rate Providers; there is no yield to skim.

4. **`script/DeployDerBodensee.s.sol`** — Foundry deployment script. Wraps the standard Balancer V3 `WeightedPoolFactory.create(...)` → `AureumVault.registerPool(...)` sequence for the 40/30/30 AuMM/sUSDS/svZCHF three-token pool. Genesis 0.75% swap fee. Rate Providers on svZCHF and sUSDS (shape decided at D1 per D-D5). **No hook attached** (per OQ-2: Bodensee is excluded from the fee-routing mechanism). `AureumProtocolFeeController`'s Bodensee protocol-fee percentage set to 0 at registration (per OQ-2: the yield-leg explicitly excludes Bodensee). Parameterized by addresses (AuMM, svZCHF, sUSDS, Vault, Factory, FeeController) read from env or from a Stage C / Stage R deployment manifest. **Used for Stage D fork tests only.** Mainnet Bodensee deployment is deferred to Stage R.

**The tests Stage D produces:**

- **`test/unit/AureumFeeRoutingHook.t.sol`** — mock-backed unit tests. Mock `IVault` + mock `IRouter` + mock ERC-20 fee tokens + mock ERC-4626 Bodensee. Cover: constructor argument validation, `onAfterSwap` happy path (fee extracted, svZCHF received, one-sided add executes), recursion-guard behavior (per D-D4 resolution), caller-gated external primitive entry points (yield / governance / Incendiary), revert on unauthorized caller, event emission, custom-error paths.

- **`test/unit/AureumProtocolFeeController.t.sol`** — extend the existing Stage B file. Add tests for (a) B10 retarget to the hook address, (b) Bodensee fee band constants and that construction no longer pins 0.75%, (c) `collectAggregateFees(DER_BODENSEE_POOL)` reverts with the expected custom error. Existing Stage B tests must still pass unchanged (after the retarget rename is propagated through test code).

- **`test/fork/FeeRoutingHook.t.sol`** — mainnet-fork integration. Deploys Option F2 Vault (via `DeployAureumVault.s.sol`), deploys Bodensee (via new `DeployDerBodensee.s.sol`), deploys a minimal 2-token weighted test pool (AuMM / svZCHF, 50/50) with the hook attached, executes swaps through the test pool via Balancer's `BatchRouter`, verifies (a) fee calc matches the expected percentage, (b) the hook's internal swap to svZCHF clears against real mainnet liquidity, (c) the one-sided add lands in Bodensee and increases Bodensee's BPT total supply by the expected delta. **Not a real Miliarium pool composition** (per D-D13 and STAGES_OVERVIEW "not as thorough as real Miliarium pools but sufficient to validate the core primitive").

**The directory additions Stage D performs:**

- Create `src/fee_router/` for the hook + interface.
- Add `script/DeployDerBodensee.s.sol` alongside existing `script/DeployAureumVault.s.sol`.
- Add `test/fork/FeeRoutingHook.t.sol` alongside the existing Stage B `test/fork/DeployAureumVault.t.sol` and `test/fork/Sanity.t.sol`.

No directory reorganization at Stage D — Stage C already pinned the `src/vault/` / `src/lib/` / `src/token/` layout.

---

## Pragma note (Stage B vs Stage C vs Stage D)

Stage B's `AureumVaultFactory.sol` and `AureumProtocolFeeController.sol` use `pragma solidity ^0.8.24` — upstream Balancer V3 inheritance, deliberate byte-identity with audited source. Stage B's `AureumAuthorizer.sol` uses `^0.8.26`. Stage C's `AureumTime.sol`, `AuMM.sol`, `IAuMM.sol` use `^0.8.26` per cursorrules rule 4.

**Stage D files are `^0.8.26`** (Aureum-authored: `AureumFeeRoutingHook.sol`, `IAureumFeeRoutingHook.sol`). The modification to `AureumProtocolFeeController.sol` **preserves its existing `^0.8.24` pragma** — the three D4 edits (retarget rename, band constants, Bodensee guard) do not touch the pragma line. If any D-executing Claude proposes "upgrading" the fee controller to `^0.8.26` "for consistency," refuse: byte-identity with upstream's pragma regime is the audit-inheritance foundation for every Aureum contract that mirrors an upstream type.

Both pragmas coexist in the compilation set — `solc 0.8.26` satisfies both carets.

---

## Import-path convention note

Stage C pinned `src/`-rooted paths for intra-Aureum sibling imports (e.g. `import {AureumTime} from "src/lib/AureumTime.sol";`). Stage D follows the same convention:

- `import {IAureumFeeRoutingHook} from "src/fee_router/IAureumFeeRoutingHook.sol";`
- `import {AureumProtocolFeeController} from "src/vault/AureumProtocolFeeController.sol";`
- `import {AureumTime} from "src/lib/AureumTime.sol";` (if used, e.g. for `FEE_CHANGE_COOLDOWN_BLOCKS` cross-reference — actual enforcement lives in Stage K)

External imports continue to use the remapped forms:

- `import {IHooks} from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";`
- `import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";`
- `import {IRouter} from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";`
- `import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";`
- `import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";`

Exact paths under `@balancer-labs/v3-interfaces/` are verified against the submodule at D1 (pinned at commit `68057fda`, section 2 of CLAUDE.md). If a path doesn't exist where expected, the submodule layout wins — stop and grep `lib/balancer-v3-monorepo/pkg/interfaces/` rather than guessing.

---

## Decisions locked in before Stage D starts

These are the answers to the planning-stage questions resolved before this file was written. They are recorded here so implementation doesn't re-litigate them.

| ID | Decision |
|----|----------|
| **D-D1** | **Stage D scope:** fee-routing hook + Bodensee deployment *script* + `AureumProtocolFeeController` modifications. **Not in scope:** attaching the hook to any real Miliarium pool (Stage E); mainnet Bodensee deployment (Stage R); governance-path fee adjustment wiring (Stage K); the OQ-11 `FEE_CHANGE_COOLDOWN_BLOCKS` cooldown enforcement (Stage K). Stage D lands the primitive and the Bodensee destination; Stage E wires the first pools to it; Stage K adds the governance adjustment path. |
| **D-D2** | **Hook architecture:** single contract (`AureumFeeRoutingHook.sol`) implements `IHooks.onAfterSwap` and houses the shared swap-and-one-sided-deposit primitive. The primitive is callable by three classes of external caller gated at the function level: (a) the hook's own `onAfterSwap` path (internal, hot path), (b) `AureumProtocolFeeController.collectAggregateFees` for the ERC-4626 yield leg (external, caller gate = fee controller address), (c) governance and Incendiary modules for direct deposits (external, caller gate = authorized module set, populated via one-shot setters at each module's deployment time). The three-layer fee table in OQ-1 is the structural map. Exact external-function shape (three separate entry points vs. one parameterized `routeExternalDeposit`) is decided at D2 draft time based on which form produces clearer call-sites in the fee controller and the future Stage K / L modules. |
| **D-D3** | **Swap target = svZCHF, immutable at construction.** Per OQ-2. The hook constructor takes `address _svZCHF` and stores it as `address public immutable SV_ZCHF`. No balance reads on Bodensee, no branching on underweight-side, no dynamic target selection. Arbitrage preserves Bodensee composition; the hook does not need to. Gas savings on every swap justify the simplicity. |
| **D-D4** | **Recursion guard — D-D-open.** OQ-1 flagged three options: (a) trusted-router check on `params.router` (the hook ignores callbacks from its own internal swap router), (b) route fee swaps directly through Bodensee (constraint: input or output token must be in the Bodensee triplet), (c) accept geometric-series overhead. **Resolved at D1 design session**, recorded as D10-series finding (or a new D-D15+ if the decision surface proves non-trivial). Draft implementation in D3 assumes option (a) pending that resolution; D1 may revise. |
| **D-D5** | **Rate Provider resolution for svZCHF / sUSDS — D-D-open.** Both tokens list themselves as their Rate Provider in `aumm-site/07a_tokens.md` — i.e. svZCHF's entry points `0xE5F130253fF137f9917C0107659A4c5262abf6b0` (the token contract) as its own Rate Provider; same shape for sUSDS at `0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD`. Balancer V3 Rate Providers must implement `IRateProvider.getRate() returns (uint256)`. ERC-4626 exposes `convertToAssets(uint256)`, which is semantically equivalent but a different signature. **Resolved at D1**: either (i) verify that svZCHF and sUSDS expose `getRate()` directly (some ERC-4626 vaults do, to support Balancer V3 integrations), or (ii) deploy thin `ERC4626RateProvider` wrapper contracts (one per token) that call `vault.convertToAssets(1e18)`. Balancer V3 monorepo includes such a wrapper; verify availability and fit at D1. If option (ii), the wrappers are one-line deployments in `DeployDerBodensee.s.sol` — not a new Stage D contract. |
| **D-D6** | **D7 is fork-only.** Bodensee deploys to Anvil against a mainnet fork for the fork tests. **No mainnet deployment at Stage D.** Mainnet Bodensee deployment is part of Stage R (the production deploy stage). This is the same discipline as Stage B: Stage B wrote `DeployAureumVault.s.sol` and exercised it on fork, but mainnet Vault deployment is Stage R. |
| **D-D7** | **B10 retarget approach:** rename the immutable enforcement target in `AureumProtocolFeeController.sol`. Current name (pinned in Stage B — confirm exact identifier at D4.1 against the Stage B source) is retargeted to the hook contract's address. Rename to `FEE_ROUTING_TARGET` (or a name chosen at D4 that reflects "hook address, which in turn forwards to Bodensee"). Keep `immutable`. Update the single error message that names the old identifier. Update the constructor parameter name. **One conceptual change, three line edits** — reviewable in under a minute. |
| **D-D8** | **OQ-11 Bodensee fee band relaxation in `AureumProtocolFeeController`:** replace any single-value `BODENSEE_SWAP_FEE_PERCENTAGE = 0.0075e18` constant (if present) with three: `BODENSEE_SWAP_FEE_MIN = 0.001e18`, `BODENSEE_SWAP_FEE_MAX = 0.01e18`, `BODENSEE_SWAP_FEE_GENESIS = 0.0075e18`. The fee controller's responsibility at genesis is unchanged — Bodensee registers with 0.75%. The fee controller **does not** enforce the band at runtime during Stage D; band enforcement is the governance path's responsibility at Stage K. The band constants land here because they are immutable from block zero and the constitution pins them at Stage D (pinning at Stage K would delay the audit-visible surface by 5+ stages). |
| **D-D9** | **OQ-2 Bodensee yield-leg exclusion:** `collectAggregateFees(address pool)` reverts with a custom error `BodenseeYieldCollectionDisabled()` when `pool == DER_BODENSEE_POOL`. The pool's protocol-fee percentage is already set to zero at registration time in `DeployDerBodensee.s.sol`, but the explicit revert is belt-and-suspenders: guards against a future misconfiguration where Bodensee's fee percentage is non-zero and `collectAggregateFees(bodensee)` would otherwise produce a no-op that wastes gas. |
| **D-D10** | **No new dependencies.** Balancer V3 `IHooks` / `IVault` / `IRouter` / `BatchRouter` / weighted-pool factory — all live in the existing submodule `lib/balancer-v3-monorepo` pinned at commit `68057fda`, importable via the existing `@balancer-labs/...` remapping. OpenZeppelin `IERC20` / `IERC4626` from existing `openzeppelin-contracts v5.6.1`. `forge-std v1.15.0` for tests. No new `forge install` calls. No new `.venv` packages. Per cursorrules "Ask before adding a new dependency" — none are being added. |
| **D-D11** | **`STAGE_D_NOTES.md` scaffolded at D0** as the living design-decision log, mirroring `STAGE_B_NOTES.md` and `STAGE_C_NOTES.md`. Decisions made during D1–D9 implementation drop there, numbered `D10, D11, ...` to avoid collision with the `D-D*` planning decisions above. Per cross-reference convention in CLAUDE.md §5. |
| **D-D12** | **Unit tests use mocks; fork tests use real addresses.** D5 unit tests never touch a fork — they exercise the hook and the fee controller against `MockVault`, `MockRouter`, `MockERC20`, `MockERC4626` stubs (using forge-std `Mock*` helpers where available, otherwise minimal local mocks). D7 fork tests deploy the real Stage B Vault + real Bodensee + a minimal 2-token hooked test pool against a mainnet fork. Unit and fork are independent test surfaces: unit catches logic bugs, fork catches integration drift. |
| **D-D13** | **D7 minimal hooked test pool** = 2-token weighted pool, 50/50 AuMM / svZCHF, hooked. Not a real Miliarium composition. Sufficient to exercise: fee extraction on a hooked pool, internal-swap recursion path (svZCHF is the target, so the fee swap into svZCHF when the fee token is AuMM reaches the test pool itself — the natural stress case for D-D4's recursion guard), one-sided add to Bodensee. Real Miliarium pool compositions with 4+ tokens and Rate Providers are Stage E. |
| **D-D14** | **Branch model:** Stage D continues the "direct tag on main" pattern seeded in Stage B and preserved in Stage C. `stage-d` is a working branch (already created from `main` at `e5ceb7a`, pushed to origin 2026-04-19); fast-forwards to `main` at D9; `stage-d-complete` lightweight tag applied on `main` at the tip. No PR workflow. Preserve `stage-d` on origin as a snapshot marker per the C0 convention. |
| **D-D15** | **`protocolSwapFeePercentage` is immutable at pool registration, no on-chain setter.** Per the 2026-04-19 BAL v3 mechanics clarification (see amended OQ-1 / OQ-1a in `docs/FINDINGS.md`): each gauged pool registers with `protocolSwapFeePercentage = 50e16` (saturating the Vault's `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50%` cap); that value does not change at runtime. `AureumProtocolFeeController` exposes no runtime setter for this field — the 50/50 split is constitutional per CLAUDE.md §2 "hard rule" and encoded as an immutable Vault parameter at registration. Stage K governance adjusts per-pool swap-fee *rate* within OQ-11's band but does not touch this split. Stage B's `AureumProtocolFeeController` inherits an upstream setter from Balancer V3; the retrofit to override or suppress that setter lands at D0.5 before D1 design work begins. der Bodensee registers with `protocolSwapFeePercentage = 0` per OQ-2 — immutable at that value too. |

---

## What is explicitly NOT in Stage D

- AuMT token — Stage I.
- Emission distributor — Stage H.
- CCB engine — Stage F.
- Gauge registry, gauge eligibility, efficiency tournament — Stage G.
- Pool-deployment framework for the 28 Miliarium pools — Stage E.
- The first three pilot pools (ixHelvetia, ixEdelweiss, ixCambio) — Stage E.
- Governance-path wiring for fee changes (`setStaticSwapFeePercentage` via governance authorizer, cooldown enforcement, proposal flow) — Stage K.
- Incendiary Boost module — Stage L.
- `MiliariumRegistry` — Stage J.
- Any mainnet deployment — Stage R.
- Any Bodensee deployment to mainnet — Stage R (Stage D only exercises the script on fork).
- Any real Miliarium pool with the hook attached — Stage E. D7 uses a synthetic 2-token test pool.
- Attaching the hook to existing non-Aureum pools (external gauge opt-in) — Stage G / post-launch governance.
- Any change to `AureumVault.sol`, `AureumVaultFactory.sol`, or `AureumAuthorizer.sol` — Stage D touches only `AureumProtocolFeeController.sol` among the Stage B surface.
- Any change under `lib/balancer-v3-monorepo/`, `lib/openzeppelin-contracts/`, or `lib/forge-std/` — banned per CLAUDE.md §8c.

Stage D is "the fee-routing hook and der Bodensee's deployment-script + three fee-controller modifications compile, pass unit + fork tests, pass Slither, pass `forge lint`, and live in the right folders." That is all.

---

## Prerequisites check

Baseline verified clean at `e5ceb7a` on `stage-d` on **2026-04-19**:

- `git status` clean.
- `git log --oneline -1` → `e5ceb7a C9: log stage-c-complete across plan, overview, and CLAUDE.md §11`.
- `git tag --list stage-c-complete` → present.
- `forge --version` → 1.5.1-stable.
- `forge build` → Compiler run successful, 30 files.
- `forge test --fork-url $MAINNET_RPC_URL` → **92/92 green** (89 unit tests across 5 suites, 3 fork tests across 2 suites). Runtime ~46 minutes driven by Ankr RPC latency.

If any of the above drifts red before Stage D work begins, stop and fix before continuing. Starting Stage D from a non-green baseline makes the D3 hook-wiring diff impossible to evaluate.

---

## D0 — Branch, scaffold notes, confirm baseline (15 min)

### D0.1 — Confirm on `stage-d` branch

```
git branch --show-current
git log --oneline -3
git status -sb
```

Expected: on `stage-d`, HEAD at `e5ceb7a`, clean tree, tracking `origin/stage-d`. If not on `stage-d`: `git checkout stage-d`.

### D0.2 — Scaffold `STAGE_D_NOTES.md`

Create `docs/STAGE_D_NOTES.md` with the D-D1..D-D14 planning codes cross-referenced (full text stays in this file; the notes file holds the implementation-finding log from D10 onward). Content drafted separately and paired with this plan's creation commit.

Per CLAUDE.md §8e: Claude Code drafts, user pastes to Cursor, terminal integrity check (`wc -l`, `shasum -a 256`, `cat`, `grep -c "—"`), output pasted back to Claude Code for byte-match confirmation, then commit.

**Commit (user runs in terminal):**

```
git add docs/STAGE_D_PLAN.md docs/STAGE_D_NOTES.md
git commit -m "docs: add STAGE_D_PLAN.md and STAGE_D_NOTES.md scaffold"
git push
git log --oneline -3
```

### D0.3 — Re-confirm Stage C baseline still green

Re-running the full `forge test --fork-url $MAINNET_RPC_URL` is expensive (~46 minutes). At D0.3, a quick `forge build` is sufficient — if the plan and notes files are the only additions, the Solidity surface is unchanged and the baseline green from the prereqs check carries forward.

```
forge build
```

Paste full tail output.

**Log D0** in the Completion Log.

---

## D0.5 — Retrofit `AureumProtocolFeeController`: remove upstream setter (per D-D15) (45 min)

Pre-flight fix landing before D1 design work. Stage B's `AureumProtocolFeeController` inherits Balancer V3's `ProtocolFeeController` behavior, which exposes a public setter allowing the protocol owner to adjust `protocolSwapFeePercentage` on any registered pool at runtime. Per D-D15 and CLAUDE.md §2 "hard rule", Aureum's 50/50 split is constitutional — the value is fixed at `50e16` on every gauged pool at registration (or `0` on der Bodensee per OQ-2) and has no runtime adjustment surface.

**Why D0.5 rather than a retroactive Stage B patch.** `stage-b-complete` is already tagged at `b627a92` as a clean snapshot. Re-cutting or shadowing that tag is costlier than carrying the retrofit as a narrow Stage D pre-flight step. `stage-b-complete` stays pure; `stage-d-complete` becomes the first tag that reflects the immutable-setter posture.

**Why before D1.** D4's edits (B10 retarget, OQ-11 Bodensee band, OQ-2 Bodensee yield-leg guard) touch the same contract. Landing the setter retrofit first gives D4 a clean base and avoids mixing two unrelated conceptual changes in the same commit.

### D0.5.1 — Grep the current Stage B setter surface

```
grep -n "setProtocolSwapFeePercentage\|setGlobalProtocolSwapFeePercentage\|protocolSwapFeePercentage" src/vault/AureumProtocolFeeController.sol
grep -n "setProtocolSwapFeePercentage\|setGlobalProtocolSwapFeePercentage\|protocolSwapFeePercentage" lib/balancer-v3-monorepo/pkg/vault/contracts/ProtocolFeeController.sol
```

Paste output. Grounds D0.5.2 in the actual upstream identifiers — the retrofit keys on whatever the Stage B source actually exposes, not on assumed names.

### D0.5.2 — Draft the retrofit

Resolved at draft time against D0.5.1's output. Two shapes under consideration, tracked as **D12** in `docs/STAGE_D_NOTES.md`:

- **R1 — override-and-revert.** Override each public setter inherited from `ProtocolFeeController`; each override reverts with a custom error `SplitIsImmutable()` (or equivalent, named at draft time). Upstream interface preserved; runtime behavior disables mutation. Smallest diff; clearest audit story ("every call path that could mutate the split reverts").
- **R2 — non-inheritance.** Inherit from a narrower base, or compose only the needed behavior, dropping the setter surface entirely. Larger diff; changes audit-inheritance shape.

**Default to R1 unless D0.5.1 forces R2.** Per CLAUDE.md §8e: full-file draft in chat, user pastes to Cursor, terminal integrity check.

### D0.5.3 — Extend `test/unit/AureumProtocolFeeController.t.sol`

Add at minimum:

- **`test_SetProtocolSwapFeePercentage_AlwaysReverts`** — whatever entry points D0.5.1 surfaces, calling them with any value (0, 25e16, 50e16, 50e16 + 1) reverts `SplitIsImmutable` (or the equivalent custom error named at D0.5.2).
- **A read-back invariant test** — after registration completes for any gauged pool, the protocol fee percentage reads back as `50e16`; for der Bodensee, reads back as `0` (per OQ-2). Exact test-harness shape decided at D0.5.3 draft time against the existing Stage B test-file structure.

Update any existing Stage B test that exercised the setter (per D0.5.1 grep surface): replace "call setter → assert new value" with "call setter → assert revert".

### D0.5.4 — `forge build` and re-run Stage B suites

```
forge build
forge test --match-path "test/unit/AureumProtocolFeeController.t.sol" -vv
forge test --match-path "test/fork/DeployAureumVault.t.sol" --fork-url $MAINNET_RPC_URL -vv
```

Paste full tail output of each. Build green; both suites stay green (existing Stage B tests are the baseline; the new revert tests are additive).

**Commit (user runs in terminal):**

```
git add src/vault/AureumProtocolFeeController.sol test/unit/AureumProtocolFeeController.t.sol
git commit -m "D0.5: AureumProtocolFeeController — remove upstream setter, split immutable (per D-D15)"
git push
git log --oneline -3
```

**Log D0.5** in the Completion Log.

---

## D1 — Design hook architecture + Bodensee deployment params (1 hr)

Design-only sub-step. No Solidity lands. Outputs: decisions recorded in `STAGE_D_NOTES.md` as D10-series findings.

### D1.1 — Read the OQ-1 and OQ-2 sections of `FINDINGS.md`

```
grep -n "^### OQ-1" docs/FINDINGS.md
grep -n "^### OQ-2" docs/FINDINGS.md
grep -n "^### OQ-11" docs/FINDINGS.md
```

Read each section in full. Cross-reference against the three-layer fee table in OQ-1 and the Bodensee self-yield mechanism in OQ-2.

### D1.2 — Verify Balancer V3 IHooks surface

```
find lib/balancer-v3-monorepo/pkg/interfaces -name "IHooks.sol"
```

Read the located file in full. Record in `STAGE_D_NOTES.md`:
- The exact `HookFlags` struct shape — which flags this hook must enable (`shouldCallAfterSwap = true` at minimum; `shouldCallBeforeSwap`, `shouldCallBeforeAddLiquidity`, etc. stay false).
- The `onAfterSwap` signature and the `AfterSwapParams` struct layout.
- The `onRegister` lifecycle callback — what it receives, what the hook must validate (pool token list matches the hook's expectations, etc.).

### D1.3 — Resolve D-D4 (recursion guard)

Discuss options (a) / (b) / (c) from OQ-1 in chat with Claude (chat session). Record the resolution as **D10** in `STAGE_D_NOTES.md`. If option (a) is chosen, identify the trusted-router address (the hook's own internal caller) — this is the hook contract itself when it calls `Vault.swap` during fee routing, so the check is `params.router == address(this)`. If option (b) is chosen, document the token constraint and the fallback for fee tokens outside the Bodensee triplet. If option (c) is chosen, document the gas-overhead bound.

### D1.4 — Resolve D-D5 (Rate Provider resolution)

```
find lib/balancer-v3-monorepo -name "*RateProvider*.sol"
find lib/balancer-v3-monorepo -name "IRateProvider.sol"
```

Read the `IRateProvider` interface and any `ERC4626RateProvider` implementation in the submodule. Check whether svZCHF (`0xE5F130253fF137f9917C0107659A4c5262abf6b0`) and sUSDS (`0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD`) expose `getRate()` directly:

```
cast call 0xE5F130253fF137f9917C0107659A4c5262abf6b0 "getRate()(uint256)" --rpc-url $MAINNET_RPC_URL
cast call 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD "getRate()(uint256)" --rpc-url $MAINNET_RPC_URL
```

If both calls succeed: Rate Providers are the token contracts themselves. If either reverts: need an `ERC4626RateProvider` wrapper. Record the resolution as **D11** in `STAGE_D_NOTES.md`.

### D1.5 — Record the Bodensee deployment parameter block

In `STAGE_D_NOTES.md`, record a single "Bodensee deployment parameters" block with:

- Pool name: `der Bodensee`
- Pool symbol: TBD at D6 (suggested `dBDN` or similar — confirm with user)
- Tokens (ordered): AuMM, sUSDS, svZCHF
- Weights: 40% / 30% / 30% (encoded per Balancer V3's normalized-weight convention; verify exact shape at D6 against `WeightedPoolFactory.create` signature)
- Genesis swap fee: 0.75% (`0.0075e18`)
- Rate Providers: resolved per D-D5 above
- Protocol fee percentage: 0 (Bodensee is excluded from yield skimming per OQ-2)
- Hook: `address(0)` (Bodensee has no hook per OQ-2)
- Pause manager: governance Safe (Stage K placeholder; same address as Stage B `AureumAuthorizer`)
- Pool creator: `address(0)` (no creator fees, per the hard rule in CLAUDE.md §2)

**Commit:**

```
git add docs/STAGE_D_NOTES.md
git commit -m "D1: record hook architecture + Bodensee deployment params (D10, D11)"
git push
git log --oneline -3
```

**Log D1** in the Completion Log.

---

## D2 — Build `src/fee_router/IAureumFeeRoutingHook.sol` (45 min)

### D2.1 — Draft the interface

Per CLAUDE.md §8e: Claude Code drafts the full file content in chat; user pastes to Cursor; terminal integrity check; paste output back.

Interface contents (final content produced in chat at direction time):

- `pragma solidity ^0.8.26;`
- SPDX header matching Stage C convention.
- Events: `YieldFeeRouted(...)`, `GovernanceDepositRouted(...)`, `IncendiaryDepositRouted(...)`, `SwapFeeRouted(...)`. Exact parameter sets decided at draft time against the caller-gate shape resolved in D-D2.
- Custom errors: `UnauthorizedCaller(address caller)`, `ZeroAddress()`, `ZeroAmount()`, `InvalidPool(address pool)`, `SvZCHFSwapFailed()`, `BodenseeDepositFailed()`, `RecursiveHookCall()` (or similar per D-D4 resolution).
- External functions: primitive entry points — shape per D-D2 resolution (three separate functions vs. single parameterized).
- External view getters: `SV_ZCHF()`, `DER_BODENSEE()`, `AUREUM_VAULT()`, `FEE_CONTROLLER()`, `AUMM()` — all immutable; getters auto-generated if stored as `public immutable`.

### D2.2 — `forge build`

```
forge build
```

Paste full output (not just exit code). Must be green.

**Commit:**

```
git add src/fee_router/IAureumFeeRoutingHook.sol
git commit -m "D2: src/fee_router/IAureumFeeRoutingHook.sol — interface per D-D2 / D-D3"
git push
```

**Log D2** in the Completion Log.

---

## D3 — Build `src/fee_router/AureumFeeRoutingHook.sol` (2.5 hr)

The central Stage D contract. Drafted in chat, pasted via Cursor per §8e. This sub-step breaks into four phases, each a separate paste-and-verify cycle.

### D3.1 — Constructor + immutables + caller-gate storage

```solidity
address public immutable AUREUM_VAULT;
address public immutable DER_BODENSEE;
address public immutable SV_ZCHF;
address public immutable AUMM;
address public immutable FEE_CONTROLLER;
address public governanceModule;   // one-shot-settable; address(0) at construction if Stage K not yet deployed
address public incendiaryModule;   // one-shot-settable; address(0) at construction if Stage L not yet deployed
```

Mirror of Stage C's `setMinter` one-shot-setter pattern for `governanceModule` and `incendiaryModule`: address stays `address(0)` at construction, one-shot-settable exactly once by a constructor-set deployer address, which self-destructs after use. Per CLAUDE.md §2 and Stage C decision C-D2.

Constructor validates all strictly-required addresses (Vault, Bodensee, svZCHF, AuMM, fee controller, deployer) are non-zero. Governance and Incendiary modules are set post-construction; their constructor-arg slot is the deployer/setter address, not the module itself.

### D3.2 — `IHooks` surface implementation

- `onRegister(...)` — validates the registering pool's token set is what this hook expects (must not include Bodensee itself). Returns `true` for authorized pools, `false` otherwise.
- `getHookFlags()` — returns `HookFlags` with `shouldCallAfterSwap = true`, all others `false`.
- `onAfterSwap(AfterSwapParams params)` — the hot path. Computes the fee in the output token, calls the internal `_swapFeeAndDeposit` primitive, emits `SwapFeeRouted`. Returns the post-hook `amountCalculatedRaw`.

### D3.3 — Internal `_swapFeeAndDeposit` primitive

Two-phase:

1. **Swap fee token → svZCHF** via `IVault.swap` (or `BatchRouter.swapExactIn` if multi-hop is needed). If the fee token is already svZCHF: skip phase 1.
2. **One-sided add svZCHF → Bodensee** via `IRouter.addLiquiditySingleTokenExactIn(pool = DER_BODENSEE, tokenIn = SV_ZCHF, exactAmountIn = svZCHFBalance, minBptOut = 0)`. `minBptOut = 0` is acceptable only because this is protocol-internal routing — slippage tolerance on the fee leg is a protocol-design trade-off, not a user-funds safety concern. Document the `minBptOut = 0` decision inline with a load-bearing `@dev` block.

Recursion guard per D-D4 resolution: if option (a), early-return / skip the hook when `params.router == address(this)` (the hook's own internal swap triggered the callback).

### D3.4 — External primitive entry points

Implement per the shape resolved at D-D2 (three separate functions OR one parameterized). Each entry point:

- Pulls the named token from the caller (using `IERC20.transferFrom` or equivalent).
- Calls the internal `_swapFeeAndDeposit` primitive with the pulled tokens.
- Emits the appropriate event.
- Caller gates: fee controller for yield leg, governance module for governance deposits, Incendiary module for Incendiary deposits. Each gate reverts `UnauthorizedCaller(msg.sender)` on mismatch, and reverts with a clear "module not yet set" condition when the governance or Incendiary module address is still `address(0)`.

### D3.5 — `forge build` and `forge lint`

```
forge build
```

```
forge clean && forge lint src/fee_router/
```

Must be green on both. Paste output.

**Commit:**

```
git add src/fee_router/AureumFeeRoutingHook.sol
git commit -m "D3: src/fee_router/AureumFeeRoutingHook.sol — hook + shared primitive per OQ-1 / OQ-2"
git push
```

**Log D3** (and any D10+ findings) in `STAGE_D_NOTES.md` and the Completion Log here.

---

## D4 — Modify `src/vault/AureumProtocolFeeController.sol` (1 hr)

Three targeted edits per D-D7 / D-D8 / D-D9. Pragma preserved at `^0.8.24`.

### D4.1 — Read current state of the fee controller

```
wc -l src/vault/AureumProtocolFeeController.sol
grep -n "DER_BODENSEE\|BODENSEE\|0.0075e18\|0_0075\|immutable" src/vault/AureumProtocolFeeController.sol
grep -n "collectAggregateFees" src/vault/AureumProtocolFeeController.sol
```

Paste output. This grounds D4's edits in the actual Stage B identifiers — D-D7's rename depends on the exact current name.

### D4.2 — Apply D-D7 retarget (B10 rename)

Full-file draft in chat with the three line edits:

- Rename the immutable target variable.
- Update the constructor parameter name.
- Update the error-message identifier where the old name appears.

Paste to Cursor, save, terminal integrity check.

### D4.3 — Apply D-D8 band constants

Add the three band constants:

```solidity
uint256 public constant BODENSEE_SWAP_FEE_MIN     = 0.001e18;   // 0.10%
uint256 public constant BODENSEE_SWAP_FEE_MAX     = 0.01e18;    // 1.00%
uint256 public constant BODENSEE_SWAP_FEE_GENESIS = 0.0075e18;  // 0.75%
```

Remove any pre-existing single-value `BODENSEE_SWAP_FEE_PERCENTAGE` constant and any `require` / `revert` that pinned Bodensee's fee to exactly 0.75%. The genesis value is consumed by `DeployDerBodensee.s.sol` at D6; the band constants are read by the Stage K governance path.

### D4.4 — Apply D-D9 Bodensee yield-leg guard

In `collectAggregateFees(address pool)`:

```solidity
if (pool == DER_BODENSEE_POOL) revert BodenseeYieldCollectionDisabled();
```

Add the custom error declaration to the contract.

### D4.5 — `forge build`, run existing Stage B tests

```
forge build
forge test --match-path "test/unit/AureumProtocolFeeController.t.sol" -vv
forge test --match-path "test/fork/DeployAureumVault.t.sol" --fork-url $MAINNET_RPC_URL -vv
```

Existing tests will need updates for the renamed identifier (D-D7) and the removed single constant (D-D8); update them in the same commit. Paste full output.

**Commit:**

```
git add src/vault/AureumProtocolFeeController.sol test/unit/AureumProtocolFeeController.t.sol
git commit -m "D4: AureumProtocolFeeController — B10 retarget + OQ-11 band + OQ-2 Bodensee guard"
git push
```

**Log D4** in the Completion Log.

---

## D5 — Unit tests (2 hr)

Cover: hook unit tests against mocks, extended fee-controller tests. Written as forge-std `Test` contracts.

### D5.1 — `test/unit/AureumFeeRoutingHook.t.sol`

Draft in chat, paste via Cursor. Structure:

- `setUp()` — deploy `MockVault`, `MockRouter`, four `MockERC20` fee tokens (one representing svZCHF, one AuMM, two arbitrary), a `MockERC4626` as Bodensee. Deploy `AureumFeeRoutingHook` with the mock addresses.
- Named tests:
  - `test_Constructor_SetsImmutables` — verify all immutable getters return the constructor arguments.
  - `test_Constructor_RevertsOnZeroAddress` — for each required non-zero address.
  - `test_OnAfterSwap_ExtractsFeeAndRoutes` — simulate a swap through the mock vault, verify fee amount, svZCHF balance delta, Bodensee BPT mint delta.
  - `test_OnAfterSwap_SvZCHFFeeSkipsPhase1` — fee token is already svZCHF; phase 1 is skipped; phase 2 proceeds.
  - `test_OnAfterSwap_RecursionGuard` — per D-D4 resolution, verify the guarded path behaves correctly.
  - `test_RouteYieldFee_OnlyFeeController` — caller gate check; reverts from arbitrary sender.
  - `test_RouteGovernanceDeposit_RevertsBeforeGovernanceSet` — while `governanceModule == address(0)`.
  - `test_RouteIncendiaryDeposit_RevertsBeforeIncendiarySet` — while `incendiaryModule == address(0)`.
  - `test_SetGovernanceModule_OneShot` — can be called once by deployer; reverts on second call; reverts from non-deployer.
  - `test_SetIncendiaryModule_OneShot` — same shape.
  - `test_Event_SwapFeeRouted` — event emission + values.
  - `test_Event_YieldFeeRouted` — event emission + values.
- Fuzz / invariant tests:
  - `invariant_BodenseeBalanceMonotonic` — across any sequence of hook calls, Bodensee's svZCHF balance is non-decreasing. (True as long as no one calls `removeLiquidity` on Bodensee via the hook — which nothing in Stage D does.)
  - `invariant_HookHoldsNoTokens` — post-operation, the hook contract's balance of every tracked token is zero (all tokens either swapped or deposited in the same call).

### D5.2 — Extend `test/unit/AureumProtocolFeeController.t.sol`

Add tests for the three D4 modifications:

- `test_B10_TargetIsHookAddress` — the renamed immutable points at the hook.
- `test_BodenseeBand_Constants` — the three band constants are 0.10% / 1.00% / 0.75%.
- `test_CollectAggregateFees_RevertsOnBodensee` — `pool == DER_BODENSEE_POOL` reverts with `BodenseeYieldCollectionDisabled`.
- Pre-existing tests updated for the renamed identifier; no behavioral change expected.

### D5.3 — Run all unit tests

```
forge test --match-path "test/unit/AureumFeeRoutingHook.t.sol" -vv
forge test --match-path "test/unit/AureumProtocolFeeController.t.sol" -vv
forge test -vv
```

Paste full output of the third invocation. 89 pre-existing unit tests + Stage D additions all expected green.

**Commit:**

```
git add test/unit/AureumFeeRoutingHook.t.sol test/unit/AureumProtocolFeeController.t.sol
git commit -m "D5: unit tests for hook + fee-controller modifications"
git push
```

**Log D5** in the Completion Log.

---

## D6 — `script/DeployDerBodensee.s.sol` (1.5 hr)

Deployment script, exercised on fork only.

### D6.1 — Draft the script in chat

Structure:

- `pragma solidity ^0.8.26;`
- Imports: forge-std `Script`, Balancer V3 `IWeightedPoolFactory`, `IVault`, local `AureumVault`, `AureumProtocolFeeController`.
- `run()` reads env vars for: `AUREUM_VAULT`, `WEIGHTED_POOL_FACTORY`, `AUMM`, `SV_ZCHF`, `SUSDS`, `FEE_CONTROLLER`, `PAUSE_MANAGER`.
- Deploys Rate Provider wrappers if D-D5 resolved to option (ii); otherwise passes the token addresses directly as Rate Providers.
- Calls `WeightedPoolFactory.create(name, symbol, tokens, weights, rateProviders, swapFee, ...)` to get the pool address.
- Calls `AureumVault.registerPool(pool, tokens, ...)` with hook `address(0)`, `shouldCallComputeDynamicSwapFee = false`, etc.
- Calls `AureumProtocolFeeController.setPoolProtocolSwapFeePercentage(pool, 0)` and `setPoolProtocolYieldFeePercentage(pool, 0)` to zero Bodensee's fees per OQ-2.
- Logs the deployed pool address.

### D6.2 — `forge build`

```
forge build
```

Paste output. Script must compile without running.

**Commit:**

```
git add script/DeployDerBodensee.s.sol
git commit -m "D6: script/DeployDerBodensee.s.sol — fork-only deployment per D-D6"
git push
```

**Log D6** in the Completion Log.

---

## D7 — Fork tests end-to-end (2.5 hr)

Mainnet-fork integration. Exercises the full chain: Vault deploy → Bodensee deploy → hooked test pool deploy → swap → hook fires → fee routes to Bodensee.

### D7.1 — Draft `test/fork/FeeRoutingHook.t.sol`

- `setUp()` — spin up Anvil fork, run `DeployAureumVault.s.sol`, run `DeployDerBodensee.s.sol`, deploy the hook via `new AureumFeeRoutingHook(...)`, deploy a minimal 2-token (AuMM / svZCHF, 50/50) weighted test pool via `WeightedPoolFactory.create` with the hook attached, register it via `AureumVault.registerPool`.
- `test_Fork_SwapRoutesFeeToBodensee`:
  - Seed the test pool with initial liquidity (user-funded).
  - Execute a swap through `BatchRouter.swapExactIn` on the test pool.
  - Assert: Bodensee's BPT supply increased, the hook holds zero tokens post-swap, the emitted `SwapFeeRouted` event matches the calculated fee.
- `test_Fork_YieldFeeRoutesToBodensee`:
  - On any non-Bodensee gauged pool (use a synthetic test pool deployed in `setUp`), call `AureumProtocolFeeController.collectAggregateFees(pool)` after accruing some protocol fees.
  - Assert: the hook's `routeYieldFee` was invoked, Bodensee received svZCHF, no tokens stranded.
- `test_Fork_BodenseeYieldCollectionReverts`:
  - Call `collectAggregateFees(DER_BODENSEE_POOL)`.
  - Assert: reverts with `BodenseeYieldCollectionDisabled`.
- `test_Fork_RecursionGuard`:
  - Per D-D4 resolution, exercise the recursion path. If option (a), trigger a swap whose fee token requires a routing hop through the hooked test pool itself; assert the hook's guard bypasses the fee-extraction logic on the internal swap.

### D7.2 — Run fork tests

```
forge test --match-path "test/fork/FeeRoutingHook.t.sol" --fork-url $MAINNET_RPC_URL -vv
forge test --fork-url $MAINNET_RPC_URL -vv
```

Paste full output of the second invocation. Full baseline + Stage D fork additions all green.

**Commit:**

```
git add test/fork/FeeRoutingHook.t.sol
git commit -m "D7: test/fork/FeeRoutingHook.t.sol — end-to-end fee routing on mainnet fork"
git push
```

**Log D7** in the Completion Log.

---

## D8 — Slither triage gate (1 hr)

Same B6 / C8 discipline. Inline-suppress with rationale; `slither-disable-next-line` directive must be the immediately-preceding comment line (per C15 — the directive-placement finding from Stage C).

### D8.1 — First-pass run

```
source .venv/bin/activate
slither . --filter-paths "lib|test"
```

Paste full output. Expect findings on the new Stage D surface (hook contract, fee-controller edits).

### D8.2 — Triage each finding

For each:
- **Accept + inline-suppress** if rationale is clear (e.g. `naming-convention` on constitutional constants, `unindexed-event-address` on events mirroring Balancer V3 patterns).
- **Fix** if the finding is real.
- **Document** in `STAGE_D_NOTES.md` under a new `## D8 — Slither triage` section, one entry per finding with (severity, file:line, detector, disposition, rationale).

### D8.3 — Re-run

```
slither . --filter-paths "lib|test"
```

Paste output. Should show only the Stage B residual `unindexed-event-address` on `AureumVaultFactory.VaultCreated` (per C8's accepted residual), plus any Stage D accepted suppressions.

**Commit:**

```
git add src/fee_router/ src/vault/AureumProtocolFeeController.sol docs/STAGE_D_NOTES.md
git commit -m "D8: Slither findings triaged (or suppressed with rationale)"
git push
```

**Log D8** (and any D10+ findings) in `STAGE_D_NOTES.md` and the Completion Log.

---

## D9 — Tag and update cross-doc completion logs (10 min)

### D9.1 — Fast-forward `stage-d` → `main` and tag

```
git checkout main
git pull
git merge --ff-only stage-d
git push origin main
git tag stage-d-complete
git push origin stage-d-complete
```

If `--ff-only` refuses, reconcile before tagging (rebase `stage-d` onto `origin/main`; retry). The tag must point at a known-clean Stage D tip.

### D9.2 — Update Completion Log in this file

Fill in the final row of the Completion Log table at the bottom.

### D9.3 — Update Completion Log in `STAGES_OVERVIEW.md`

Open `docs/STAGES_OVERVIEW.md`; find the master Completion Log; fill in the Stage D row:

| Stage | Tag | Date | Commit | Notes |
|---|---|---|---|---|
| D | `stage-d-complete` | YYYY-MM-DD | `<hash>` | Fee-routing hook, Bodensee deployment script (fork-only), fee-controller modifications (B10 retarget, OQ-11 band, OQ-2 Bodensee guard) |

### D9.4 — Update CLAUDE.md §11 resumption anchor

Advance §11 from "Stage D — Fee-routing hook + der Bodensee (ready to start)" to "Stage D complete" and pin the next-stage pointer to Stage E.

```
git add docs/STAGE_D_PLAN.md docs/STAGES_OVERVIEW.md CLAUDE.md
git commit -m "D9: log stage-d-complete across plan, overview, and CLAUDE.md §11"
git push
```

**Log D9** in the Completion Log.

---

## Four things that could go wrong and how to recover

**Balancer V3 hook registration rejects the hook.** `onRegister` returns `false` or the Vault reverts during `registerPool`. Usually a `HookFlags` mismatch (the hook advertises a callback it doesn't implement, or fails to advertise one it does). Recovery: grep the submodule `IHooks.sol` and `HookFlags` struct, verify the flags the hook returns match the callbacks it implements. If the mismatch is in the pool's expectations (`onRegister` rejects because of an unexpected token set), the test pool's token list needs adjustment — not the hook.

**Internal swap-and-deposit reverts because the routing layer can't find a path.** The hook swaps fee token → svZCHF. If the fee token is an obscure Miliarium token, the path through mainnet Balancer V3 pools may not exist at Stage D (those pools are deployed in Stage E). Mitigation at Stage D: fork-test with fee tokens that DO have mainnet Balancer V3 routes (AuMM is the test-pool token; svZCHF passes through trivially; other fee tokens in D7 tests should be chosen to have live paths). Real Miliarium fee tokens become testable in Stage E when those pools come up.

**`minBptOut = 0` on the one-sided Bodensee add gets sandwiched.** A MEV bot front-runs the hook's `addLiquiditySingleTokenExactIn`, mints dust BPT for the hook by depositing a tiny amount, then back-runs with a swap that profits from price dislocation. Stage D uses `minBptOut = 0` because the protocol internalizes this risk (it's the protocol's own fee, not user funds). Stage Q audit will revisit; if the audit flags this as a real loss vector, the mitigation is a trusted-caller check on the Bodensee add or a dynamic `minBptOut` computed from the current svZCHF/BPT ratio. Document in `STAGE_D_NOTES.md` as a known audit surface.

**D4 rename breaks existing Stage B tests in non-obvious ways.** The D-D7 retarget is three line edits in the source plus a matching rename in tests, but a grep miss can leave one test-file reference stale and the test fails with an unclear error. Recovery: `grep -rn 'DER_BODENSEE_POOL' src/ test/ script/` (using the OLD name) should return zero hits post-D4; if it returns anything, that's the stale reference. Fix and recommit as a D4 follow-up (or squash into D4 before pushing).

---

## Files Stage D produces

```
aumm-deploy/
├── docs/
│   ├── STAGE_D_PLAN.md           — this file (new)
│   └── STAGE_D_NOTES.md          — living design-decision log (new)
├── src/
│   ├── fee_router/
│   │   ├── AureumFeeRoutingHook.sol     — hook + shared primitive (new)
│   │   └── IAureumFeeRoutingHook.sol    — interface (new)
│   └── vault/
│       └── AureumProtocolFeeController.sol  — modified (B10 retarget + OQ-11 band + OQ-2 guard)
├── script/
│   └── DeployDerBodensee.s.sol   — fork-only deployment script (new)
└── test/
    ├── unit/
    │   ├── AureumFeeRoutingHook.t.sol        — unit + fuzz + invariants (new)
    │   └── AureumProtocolFeeController.t.sol — extended with D4 coverage (modified)
    └── fork/
        └── FeeRoutingHook.t.sol   — mainnet-fork integration (new)
```

No changes to `foundry.toml`, `remappings.txt`, or `README.md` unless a D8 lint-ignore path emerges.

---

## Completion Log

Fill this in as you progress.

| Date | Step | Status | Commit | Notes |
|---|---|---|---|---|
| 2026-04-19 | D0 — branch + notes scaffold + baseline | ✅ | `b08abdb` | `stage-d` preserved on origin as working branch per D-D14 (branched from `main` at `e5ceb7a`). D0.2: `STAGE_D_PLAN.md` (691 lines) + `STAGE_D_NOTES.md` (67 lines, D-D1..D-D14 planning codes cross-referenced) scaffolded and landed together at `b08abdb`. D0.3: baseline `forge build` cache-hit (`No files changed, compilation skipped`) — Solidity surface byte-identical to the 30-file / 92-test prereq baseline at `e5ceb7a` |
| 2026-04-20 | D0.5 — retrofit `AureumProtocolFeeController` (remove upstream setter per D-D15) | ✅ | `e5dc936` | D0.5.1 grep against Stage B confirmed R1 structurally compatible (no force to R2; see D12 resolution in NOTES). D0.5.2 applied R1 plus scope extension: constructor pins `_globalProtocolSwapFeePercentage` at `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50e16` (saturates the Vault cap, realises the 50/50 split); `SplitIsImmutable` reverts both setters; `registerPool` pins swap-side aggregate regardless of `protocolFeeExempt` (closes factory-level bypass). D0.5.3 added Group D with 6 D-D15 coverage tests. D0.5.4: `forge build` clean, `forge test` 28/28 green including 4 invariants (256 runs × 32768 calls, 0 reverts, 0 discards). See D13 + D14 in NOTES for Cursor-interaction findings surfaced during this sub-step. |
| 2026-04-20 | D1 — design decisions (D10, D11, D15) | ✅ | `a0513c0` | D1.1 cross-read FINDINGS OQ-1 / OQ-2 / OQ-11. D1.2 inspected Balancer V3 `IHooks` + `VaultTypes.HookFlags` / `AfterSwapParams`. D1.3 resolved **D-D4** → option (a) trusted-router check on `params.router == address(this)` (upstream-idiomatic per `StableSurgeHook`); recorded as **D10**. D1.4 resolved **D-D5** via live `cast call getRate()` probes against mainnet: svZCHF Rate Provider = `0xf32dc0ee2cc78dca2160bb4a9b614108f28b176c` (post `aumm-site fc3f587` spec fix); sUSDS Rate Provider = `0x1195be91e78ab25494c855826ff595eef784d47b` (post `aumm-site 528ea35` spec fix); both existing mainnet deployments, zero audit surface added; recorded as **D11**. D1.5 expanded "Der Bodensee deployment parameters" block (17 top-level + 3 sub-bullets: pool name `"der-Bodensee"`, symbol `"BODENSEE"`, Rate Providers per D11, pause manager = governance Safe, pool creator = `address(0)`, unbalanced-liquidity enabled, `protocolSwapFeePercentage` override cosmetic per D-D15). D1.6 logged **D15**: two new D13 failure modes observed 2026-04-20 (NEW-side 8-blank collapse at D1.4; OLD-side 1-blank rejection at D1.5), refined fix-forward (blank-free OLD/NEW; awk/sed restoration; heredoc append). NOTES only, no Solidity this sub-step. |
| 2026-04-20 | D2 — `src/fee_router/IAureumFeeRoutingHook.sol` | ✅ | `6aab7ac` | D2.1 drafted thin interface (pure-signature, does **not** inherit Balancer V3 `IHooks` — the implementation contract inherits `BaseHooks` separately at D3; callers integrate against this interface, the Vault integrates against `IHooks` on the implementation). Imports only OZ `IERC20`; zero Balancer-import surface at the interface layer. **4 events** (`SwapFeeRouted`, `YieldFeeRouted`, `GovernanceDepositRouted`, `IncendiaryDepositRouted`), **6 errors** (`UnauthorizedCaller`, `ZeroAddress`, `ZeroAmount`, `InvalidPool`, `SvZCHFSwapFailed`, `BodenseeDepositFailed`), **3 external primitives** per **D16** / D-D2 Option A (`routeYieldFee(pool, feeToken, feeAmount)`, `routeGovernanceDeposit(token, amount)`, `routeIncendiaryDeposit(token, amount)` — each gated to a single sanctioned caller), **5 immutable view getters** (`SV_ZCHF`, `DER_BODENSEE`, `AUREUM_VAULT`, `FEE_CONTROLLER`, `AUMM`). Plan L304-340 prescribed "7 errors or similar per D-D4"; landed 6 — `RecursiveHookCall` omitted because D10 / D-D4 Option (a) resolves re-entrancy by trusted-router early-return (`params.router == address(this)`) rather than revert, leaving no reachable error to declare. **D16** (D-D2 Option A resolution) logged in NOTES and committed alongside the interface in this same commit. D2.2 `forge build` green (1 file compiled, 27.82ms — interface-only, no cascade recompile). Post-Cursor-save integrity byte-matched chat draft: 191 lines, shasum `8cebbb84fa25f257ee13acf63e1dead4d8729a350b0d409d61d91351d7367e82`, 9 em-dashes. |
|  | D3 — `src/fee_router/AureumFeeRoutingHook.sol` | ⏳ |  |  |
|  | D4 — `AureumProtocolFeeController` modifications | ⏳ |  |  |
|  | D5 — unit tests | ⏳ |  |  |
|  | D6 — `script/DeployDerBodensee.s.sol` | ⏳ |  |  |
|  | D7 — fork tests | ⏳ |  |  |
|  | D8 — Slither triage | ⏳ |  |  |
|  | D9 — `stage-d-complete` tag pushed | ⏳ |  |  |
