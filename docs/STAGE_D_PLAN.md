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
   - **B10 retarget (two-immutables shape, per D-D7 reconciled and STAGE_D_NOTES D23).** Add a new `address public immutable FEE_ROUTING_HOOK` (the hook contract's address) as the B10 enforcement target for `withdrawProtocolFees` / `withdrawProtocolFeesForToken`. The existing `DER_BODENSEE_POOL` immutable is **retained unchanged** — post-D4 it serves the D-D9 pool-identity check in `collectAggregateFees`, not B10 withdrawal enforcement. Constructor gains a second address parameter (`feeRoutingHook_`) alongside the existing `derBodenseePool_`. Every B10 recipient-check and every `InvalidRecipient(...)` error argument that formerly named `DER_BODENSEE_POOL` is rewritten to `FEE_ROUTING_HOOK`; sites that refer to the Bodensee pool identity keep `DER_BODENSEE_POOL`. Two immutables, one new constructor parameter, B10-recipient-site rewrite.
   - **OQ-11 Bodensee fee band relaxation.** The existing B8 immutability on Bodensee's 0.75% is relaxed. Replace any pinned single value with three band constants: `BODENSEE_SWAP_FEE_MIN = 0.001e18`, `BODENSEE_SWAP_FEE_MAX = 0.01e18`, `BODENSEE_SWAP_FEE_GENESIS = 0.0075e18`. Genesis default is unchanged at 0.75%; adjustability within the 0.10%–1.00% band is a Stage K concern (the governance call path), but the band constants land here so the rate ceases to be pinned at construction time.
   - **OQ-2 Bodensee yield-fee exclusion.** Add a revert in `collectAggregateFees(pool)` when `pool == DER_BODENSEE_POOL`. Bodensee's ERC-4626 composition compounds in-pool via Rate Providers; there is no yield to skim.

4. **`script/DeployDerBodensee.s.sol`** — Foundry deployment script. Wraps the standard Balancer V3 `WeightedPoolFactory.create(...)` → `AureumVault.registerPool(...)` sequence for the 40/30/30 AuMM/sUSDS/svZCHF three-token pool. Genesis 0.75% swap fee. Rate Providers on svZCHF and sUSDS (shape decided at D1 per D-D5). **No hook attached** (per OQ-2: Bodensee is excluded from the fee-routing mechanism). `AureumProtocolFeeController`'s Bodensee protocol-fee percentage set to 0 at registration (per OQ-2: the yield-leg explicitly excludes Bodensee). Parameterized by addresses (AuMM, svZCHF, sUSDS, Vault, Factory, FeeController) read from env or from a Stage C / Stage R deployment manifest. **Used for Stage D fork tests only.** Mainnet Bodensee deployment is deferred to Stage R.

**The tests Stage D produces:**

- **`test/unit/AureumFeeRoutingHook.t.sol`** — mock-backed unit tests. Mock `IVault` + mock `IRouter` + mock ERC-20 fee tokens + mock ERC-4626 Bodensee. Cover: constructor argument validation, `onAfterSwap` happy path (fee extracted, svZCHF received, one-sided add executes), recursion-guard behavior (per D-D4 resolution), caller-gated external primitive entry points (yield / governance / Incendiary), revert on unauthorized caller, event emission, custom-error paths.

- **`test/unit/AureumProtocolFeeController.t.sol`** — extend the existing Stage B file. Add tests for (a) B10 retarget to the hook address, (b) Bodensee fee band constants and that construction no longer pins 0.75%, (c) `collectAggregateFees(DER_BODENSEE_POOL)` reverts with the expected custom error. Existing Stage B tests must still pass unchanged (after the retarget rename is propagated through test code).

- **`test/fork/AureumFeeRoutingHook.t.sol`** — mainnet-fork integration. Deploys Option F2 Vault (via `DeployAureumVault.s.sol`), deploys Bodensee (via new `DeployDerBodensee.s.sol`), deploys a minimal 2-token weighted test pool (AuMM / svZCHF, 50/50) with the hook attached, executes swaps through the test pool via Balancer's `BatchRouter`, verifies (a) fee calc matches the expected percentage, (b) the hook's internal swap to svZCHF clears against real mainnet liquidity, (c) the one-sided add lands in Bodensee and increases Bodensee's BPT total supply by the expected delta. **Not a real Miliarium pool composition** (per D-D13 and STAGES_OVERVIEW "not as thorough as real Miliarium pools but sufficient to validate the core primitive").

**The directory additions Stage D performs:**

- Create `src/fee_router/` for the hook + interface.
- Add `script/DeployDerBodensee.s.sol` alongside existing `script/DeployAureumVault.s.sol`.
- Add `test/fork/AureumFeeRoutingHook.t.sol` alongside the existing Stage B `test/fork/DeployAureumVault.t.sol` and `test/fork/Sanity.t.sol`.

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
| **D-D7** | **B10 retarget approach (two immutables — reconciled with STAGE_D_NOTES D4 / D23; supersedes the original single-rename framing).** `AureumProtocolFeeController` ends D4 with **two** address-immutables: `FEE_ROUTING_HOOK` (new — the B10 withdrawal-recipient enforcement target, set to the hook contract's address) and `DER_BODENSEE_POOL` (retained from Stage B — now serves the D-D9 `collectAggregateFees` pool-identity check rather than B10 enforcement). Both coexist because B10's withdrawal recipient and D-D9's pool-address check reference different addresses. Constructor takes both (`feeRoutingHook_`, `derBodenseePool_`). Every B10 recipient-check and every `InvalidRecipient(...)` argument that formerly named `DER_BODENSEE_POOL` is updated to `FEE_ROUTING_HOOK`; sites that refer to the Bodensee pool identity keep `DER_BODENSEE_POOL`. See STAGE_D_NOTES D23 for the plan-vs-notes reconciliation record. |
| **D-D8** | **OQ-11 Bodensee fee band relaxation in `AureumProtocolFeeController`:** replace any single-value `BODENSEE_SWAP_FEE_PERCENTAGE = 0.0075e18` constant (if present) with three: `BODENSEE_SWAP_FEE_MIN = 0.001e18`, `BODENSEE_SWAP_FEE_MAX = 0.01e18`, `BODENSEE_SWAP_FEE_GENESIS = 0.0075e18`. The fee controller's responsibility at genesis is unchanged — Bodensee registers with 0.75%. The fee controller **does not** enforce the band at runtime during Stage D; band enforcement is the governance path's responsibility at Stage K. The band constants land here because they are immutable from block zero and the constitution pins them at Stage D (pinning at Stage K would delay the audit-visible surface by 5+ stages). |
| **D-D9** | **OQ-2 Bodensee yield-leg exclusion:** `collectAggregateFees(address pool)` reverts with a custom error `BodenseeYieldCollectionDisabled()` when `pool == DER_BODENSEE_POOL`. The pool's protocol-fee percentage is already set to zero at registration time in `DeployDerBodensee.s.sol`, but the explicit revert is belt-and-suspenders: guards against a future misconfiguration where Bodensee's fee percentage is non-zero and `collectAggregateFees(bodensee)` would otherwise produce a no-op that wastes gas. |
| **D-D10** | **No new dependencies.** Balancer V3 `IHooks` / `IVault` / `IRouter` / `BatchRouter` / weighted-pool factory — all live in the existing submodule `lib/balancer-v3-monorepo` pinned at commit `68057fda`, importable via the existing `@balancer-labs/...` remapping. OpenZeppelin `IERC20` / `IERC4626` from existing `openzeppelin-contracts v5.6.1`. `forge-std v1.15.0` for tests. No new `forge install` calls. No new `.venv` packages. Per cursorrules "Ask before adding a new dependency" — none are being added. |
| **D-D11** | **`STAGE_D_NOTES.md` scaffolded at D0** as the living design-decision log, mirroring `STAGE_B_NOTES.md` and `STAGE_C_NOTES.md`. Decisions made during D1–D9 implementation drop there, numbered `D10, D11, ...` to avoid collision with the `D-D*` planning decisions above. Per cross-reference convention in CLAUDE.md §5. |
| **D-D12** | **Unit tests use the real VaultMock stack + Aureum-specific mocks; fork tests use real mainnet addresses.** D5 unit tests never touch a mainnet fork — they inherit `BaseVaultTest` from `@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol` for byte-identical Vault semantics (`VaultMock`, `VaultExtensionMock`, `VaultAdminMock`, `PoolFactoryMock`, `PoolMock`, `RouterMock`, `BasicAuthorizerMock`) and layer Aureum-proximate fixtures on top: `test/mocks/MockERC20.sol` (fee-token fixtures), `test/mocks/MockERC4626.sol` (svZCHF over ZCHF — Balancer ships no ERC-4626 fixture), `test/mocks/MockFeeController.sol` (per-pool `setForward` schedule, isolates hook from Stage B controller logic). D7 fork tests deploy the real Stage B Vault + real Bodensee + a minimal 2-token hooked test pool against a mainnet fork. Unit and fork are independent test surfaces: unit catches logic bugs against byte-identical Vault semantics, fork catches integration drift against production addresses. Hand-rolled MockVault considered and rejected — see **D-D17** / **STAGE_D_NOTES D26**. |
| **D-D13** | **D7 minimal hooked test pool** = 2-token weighted pool, 50/50 AuMM / svZCHF, hooked. Not a real Miliarium composition. Sufficient to exercise: fee extraction on a hooked pool, internal-swap recursion path (svZCHF is the target, so the fee swap into svZCHF when the fee token is AuMM reaches the test pool itself — the natural stress case for D-D4's recursion guard), one-sided add to Bodensee. Real Miliarium pool compositions with 4+ tokens and Rate Providers are Stage E. |
| **D-D14** | **Branch model:** Stage D continues the "direct tag on main" pattern seeded in Stage B and preserved in Stage C. `stage-d` is a working branch (already created from `main` at `e5ceb7a`, pushed to origin 2026-04-19); fast-forwards to `main` at D9; `stage-d-complete` lightweight tag applied on `main` at the tip. No PR workflow. Preserve `stage-d` on origin as a snapshot marker per the C0 convention. |
| **D-D15** | **`protocolSwapFeePercentage` is immutable at pool registration, no on-chain setter.** Per the 2026-04-19 BAL v3 mechanics clarification (see amended OQ-1 / OQ-1a in `docs/FINDINGS.md`): each gauged pool registers with `protocolSwapFeePercentage = 50e16` (saturating the Vault's `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50%` cap); that value does not change at runtime. `AureumProtocolFeeController` exposes no runtime setter for this field — the 50/50 split is constitutional per CLAUDE.md §2 "hard rule" and encoded as an immutable Vault parameter at registration. Stage K governance adjusts per-pool swap-fee *rate* within OQ-11's band but does not touch this split. Stage B's `AureumProtocolFeeController` inherits an upstream setter from Balancer V3; the retrofit to override or suppress that setter lands at D0.5 before D1 design work begins. der Bodensee registers with `protocolSwapFeePercentage = 0` per OQ-2 — immutable at that value too. |
| **D-D17** | **D5.1 test harness: Balancer VaultMock via BaseVaultTest, not hand-rolled MockVault.** Three constraints settle the design. (i) **§1** doctrine — re-implementing ~250 lines of audited Vault semantics on the test surface is exactly the drift-risk class that byte-identical Vault is meant to prevent. (ii) The Stage B `vm.mockCall`-per-selector pattern does not transfer: the hook's phase-2 path reads `SV_ZCHF.balanceOf(address(this))` after `_vault.sendTo(...)`, and `vm.mockCall` cannot simulate the token-transfer side effect. (iii) Balancer V3 ships `VaultMock.sol` (byte-identical to real `Vault` + test helpers) and `BaseVaultTest.sol` explicitly for this; **§8c** forbids editing under `lib/balancer-v3-monorepo/`, not importing. Custom setUp required because the `DER_BODENSEE` immutable forces Bodensee-pool-before-hook-construction (inverting `BaseVaultTest`'s default hook-then-pool order), and `onRegister` L251–262 rejects Bodensee as a hooked pool (must register with `poolHooksContract = address(0)`). Full rationale and 7-step setUp flow in **STAGE_D_NOTES D26**. D-D16 left free per the deferred β1-custody reservation in `STAGE_D_NOTES.md` L185. |
| **D-D18** | **D5.1 harness supersession: `vm.mockCall` + `makeAddr("vault")`, not `BaseVaultTest`.** Surfaced 2026-04-22 post-**D-D17** commit: five targeted searches (`find lib/balancer-v3-monorepo -name "IPermit2.sol"`, `find lib/balancer-v3-monorepo -name "permit2" -type d`, `find . -name "IPermit2.sol"`, `ls lib/balancer-v3-monorepo/lib/`, `grep permit2 foundry.toml remappings.txt`) all empty. `BaseVaultTest` inherits `Permit2Helpers`, whose constructor deploys Permit2 and whose imports reach `permit2/src/interfaces/IPermit2.sol` — no file, no directory, no remapping in this repo. Adding a `permit2` submodule falls under CLAUDE.md §8b "ask before adding a new dependency" and §8c's stricter bar; rejected in favour of a unit-scope approach with no new dependencies. Revised harness: `vault = makeAddr("vault")` (no-code); `vm.prank(vault)` clears `VaultGuard.onlyVault` on all three hook callback surfaces; `vm.mockCall` stubs the three phase-2 vault functions the hook reaches (`IVault.getPoolTokenCountAndIndexOfToken`, `IVault.addLiquidity`, `IVault.settle`); real `MockERC20` / `MockERC4626` / `MockFeeController`. D-D17's reasoning for rejecting a hand-rolled `MockVault.sol` (§1 byte-identical doctrine) still stands; what changes is the replacement. Scope boundary: branches A (svZCHF fee, no-op phase 1) and B (ZCHF fee, real ERC-4626 deposit phase 1) of `onAfterSwap` fully unit-covered; branch C (non-ZCHF-family fee → nested `_vault.swap` → `_vault.sendTo`) deferred to D7 (real `sendTo` transfer required); `routeYieldFee` / `routeGovernanceDeposit` / `routeIncendiaryDeposit` success paths deferred to D7 (real `_vault.unlock` callback required); `UnsupportedFeeToken` internal revert deferred to D7 (only reachable inside a routeX callback). Full narrative and discipline fold-in in **STAGE_D_NOTES D27**. |
| **D-D19** | **Fork-test harness path: test/fork/AureumFeeRoutingHook.t.sol.** Pinned at D7 entry (Gate 2 pin 1 per CLAUDE.md §11 kickoff). Reconciles §D7's original plan text (six pre-reconciliation sites: L35, L41, L623, L632, L633, L758 — line numbers at pre-reconciliation) to match (i) the source file namesrc/fee_router/AureumFeeRoutingHook.sol, (ii) the D5 unit-test name test/unit/AureumFeeRoutingHook.t.sol, and (iii) the Stage B fork-test precedent test/fork/DeployAureumVault.t.solwhich preserves theAureumprefix. Same bare filename acrosstest/unit/andtest/fork/ is not a collision — Foundry disambiguates on path; the established repo convention is source-name symmetry (<Contract>.sol→<Contract>.t.solin unit + fork directories). D-D16 remains reserved for the deferred β1-custody backfill fromSTAGE_D_NOTES.md L185. |
| **D-D20** | **Real AuMM deploy in fork-test setUp; deal for account funding.** Pinned at D7 entry (Gate 2 pin 2 per CLAUDE.md §11 kickoff); resolves D30 Gap (ii) from STAGE_D_NOTES.md L295. The fork harness constructs `AuMM aumm = new AuMM(block.number, address(this))` in `setUp` — the second constructor argument is `minterAdmin_` (one-shot `setMinter` authority per `src/token/AuMM.sol:82-88`), not the minter itself. `setMinter` is **intentionally never called** and `mint()` is **intentionally never invoked** in D7 fork `setUp` or the five provisional tests; account funding uses Foundry's `deal(address(aumm), user, amount, true)` cheat from `forge-std`'s `StdCheats` (fourth-arg `true` updates `totalSupply` for Balancer weighted-pool-init invariants). Note: `deal` unprefixed is the token-balance cheat; `vm.deal` is the distinct native-ETH cheat — not interchangeable. This decouples the D7 harness from Stage H's emission / distributor path while keeping the `AUMM` immutable stamped with a real `AuMM` address. Matches the fork-test doctrine already established by Stage B's `test/fork/DeployAureumVault.t.sol` (real Aureum contracts over mainnet externals) and satisfies CLAUDE.md §1's audit-inheritance signal that the fork surface verifies real bytecode, not mocks. Rejected the `MockERC20` alternative (option A): the D5 MockERC20-as-AuMM choice was forced by **D-D18**'s `vm.mockCall` + `makeAddr("vault")` harness where no real Vault was available; D7 deploys real Vault, real Bodensee, real Aureum-bound `WeightedPoolFactory` per D6 + D7.0, so the D5 constraint does not transfer. None of the five provisional §D7.1 tests (test_Fork_SwapRoutesFeeToBodensee, test_Fork_BodenseeYieldCollectionReverts, test_Fork_RecursionGuard, test_Fork_RouteYieldFeePrimitive, test_Fork_WithdrawProtocolFeesRecipientCheck) exercise AuMM emission, halving, or burn paths; the two-arg constructor call is the full integration cost. |
| **D-D21** | **Full pre-compute pattern for hook + Bodensee CREATE-address prediction.** Pinned at D7 entry (Gate 2 pin 3 per CLAUDE.md §11 kickoff); same idiom as `DeployAureumVault.s.sol`'s internal nonce-arithmetic at L159–L171. The hook/controller immutable circularity (hook ctor needs `feeController_`; `AureumProtocolFeeController` ctor needs `feeRoutingHook_` + `derBodenseePool_`) eliminates option (b) — post-hoc address reads cannot retrofit immutables baked at `DeployAureumVault.deploy()` time. **Option (a) selected:** all addresses predicted before any `new …`, each deploy verified against its prediction with a defensive `assert`. **Prediction chain (`setUp` prologue):** `startNonce = vm.getNonce(address(this))`; `vaultScriptAddr = vm.computeCreateAddress(address(this), startNonce + 0)`; `wpfAddr = vm.computeCreateAddress(address(this), startNonce + 1)` — WPF inline, see below; `auMMAddr = vm.computeCreateAddress(address(this), startNonce + 2)` — per D-D20; `hookAddr = vm.computeCreateAddress(address(this), startNonce + 3)`; `predictedFactory = vm.computeCreateAddress(vaultScriptAddr, 3)` — script's EIP-161 fresh-contract nonce = 1, Factory at nonce 1 + 2 = 3; `predictedVault = CREATE3.getDeployed(VAULT_SALT, predictedFactory)` — two-arg `internal pure` form, exact mirror of `DeployAureumVault.s.sol:L171`; `predictedBodensee = CREATE3.getDeployed(keccak256(abi.encode(address(this), block.chainid, BODENSEE_SALT)), wpfAddr)` — `BasePoolFactory._computeFinalSalt` uses `msg.sender`, and the test contract is `msg.sender` for `wpf.create()`, so prediction equals actual. **Deploy + assert sequence** (after env: `DER_BODENSEE_POOL = predictedBodensee`, `FEE_ROUTING_HOOK = hookAddr`, plus the seven env vars read by the vault script): `new DeployAureumVault()` → assert `address(vaultScript) == vaultScriptAddr`; `vaultScript.deploy(vaultScriptAddr)` → assert `address(vault) == predictedVault`; `new WeightedPoolFactory(IVault(address(vault)), PAUSE_WINDOW_DURATION, FACTORY_VERSION, POOL_VERSION)` inline → assert `address(wpf) == wpfAddr`; `new AuMM(block.number, address(this))` → assert `address(aumm) == auMMAddr`; `wpf.create(…, BODENSEE_SALT)` → assert returned pool `== predictedBodensee`; `new AureumFeeRoutingHook(address(vault), predictedBodensee, SV_ZCHF, IERC20(address(aumm)), address(controller), GOVERNANCE_MULTISIG)` → assert `address(hook) == hookAddr`. Each `assert` fails fast on nonce-shift; catches the C14-class drift-risk at its source. **Inline WPF rationale:** the structural argument is `msg.sender` symmetry — `wpf.getDeploymentAddress(BODENSEE_SALT)` (pre-creation cross-check) and the subsequent `wpf.create(…, BODENSEE_SALT)` must both run with the same `msg.sender` to resolve `BasePoolFactory._computeFinalSalt` to the same final-salt; inline construction keeps `msg.sender = address(this)` throughout setUp, whereas routing through `DeployAureumWeightedPoolFactory.run()` splits WPF creation into the script's frame. Script constants (`PAUSE_WINDOW_DURATION = 4 * 365 days`; `FACTORY_VERSION` / `POOL_VERSION` JSON strings) are replicated inline; they do NOT enter the CREATE3 salt (only `msg.sender`, `block.chainid`, `BODENSEE_SALT` do via `_computeFinalSalt`), so version-string drift between script and test cannot affect pool addresses. `DeployAureumWeightedPoolFactory.s.sol` and `DeployDerBodensee.s.sol` remain CLI-exercised; hook fork-test `setUp` prioritises predictability and minimal nonce footprint over script coverage. **Hooked trading pool** (for `test_Fork_SwapRoutesFeeToBodensee` / `test_Fork_RecursionGuard`; composition finalised at Gate 2 pin 4 — likely AuMM/svZCHF 50/50): deployed inline via `wpf.create(…, TRADING_POOL_SALT)` with `TRADING_POOL_SALT` distinct from `BODENSEE_SALT`; address predicted before creation via `wpf.getDeploymentAddress(TRADING_POOL_SALT)` (same `msg.sender = address(this)`). **CREATE3 import:** `@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol` — covered by existing remapping `@balancer-labs/v3-solidity-utils/=lib/balancer-v3-monorepo/pkg/solidity-utils/`; no new dependency. |


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
2. **One-sided add svZCHF → Bodensee** via `IVault.addLiquidity` with `AddLiquidityParams(pool: DER_BODENSEE, to: address(this), maxAmountsIn: svZCHFBalance at svZchfIndex and 0 at all other Bodensee token indices, minBptAmountOut: 0, kind: AddLiquidityKind.UNBALANCED, userData: bytes(""))`. `minBptAmountOut = 0` is acceptable only because this is protocol-internal routing — slippage tolerance on the fee leg is a protocol-design trade-off, not a user-funds safety concern. Document the `minBptAmountOut = 0` decision inline with a load-bearing `@dev` block. Resolution recorded at D20 in `docs/STAGE_D_NOTES.md` (Router → direct Vault; nested-Vault-from-hook precedent: `ExitFeeHookExample.sol:160`).

> **Landed in D3.4a** (not a separate D3.3.4 commit) — phase-2 helper `_addLiquidityOneSidedToBodenseeViaVault` introduction was bundled into the D3.4a recipient-threading refactor. See STAGE_D_NOTES.md D21.

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

### D4.2 — Apply D-D7 retarget (add `FEE_ROUTING_HOOK`, keep `DER_BODENSEE_POOL`, two immutables)

Full-file draft in chat (two-immutables shape, per D-D7 reconciled / STAGE_D_NOTES D23):

- Add a new `address public immutable FEE_ROUTING_HOOK` alongside the retained `DER_BODENSEE_POOL`.
- Add a second constructor parameter `feeRoutingHook_` alongside the retained `derBodenseePool_`; assign both.
- In every B10 withdrawal-recipient check and every `InvalidRecipient(...)` argument that formerly named `DER_BODENSEE_POOL`, substitute `FEE_ROUTING_HOOK`; leave the D-D9 pool-identity sites (to be added at D4.4) untouched.

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

### D5.1 — `test/unit/AureumFeeRoutingHook.t.sol` + `test/mocks/*`

Four files, bottom-up dependency order; each drafted in chat, pasted via Cursor, terminal-integrity-checked per §8e, and committed as its own logical unit per the C6-pattern. `forge build` after every mock; `forge test --match-contract AureumFeeRoutingHookTest -vv` once the test file lands.

**Mock files** (new, under `test/mocks/`):

- `MockERC20.sol` — minimal OZ `ERC20` with public `mint`/`burn` helpers and constructor-configurable `decimals()`. ~30 lines.
- `MockERC4626.sol` — 1:1 share token over a `MockERC20` underlying; `asset()`, `deposit(assets, receiver)`, `redeem(shares, receiver, owner)`. ~50 lines.
- `MockFeeController.sol` — stub of `IAureumProtocolFeeControllerHookExtension`: configurable per-pool via `setForward(pool, tokens, amounts)`; `collectSwapAggregateFeesForHook` transfers the scheduled token amounts from itself to `msg.sender` (matching production custody — the real controller also hands tokens to the hook) and returns the arrays; drains-on-read like the real controller. ~65 lines.
No `VaultMock` / `BaseVaultTest` either — **permit2 is absent from the repo** (five targeted searches 2026-04-22: no `IPermit2.sol`, no `permit2` directory, no `permit2/` remapping; `lib/balancer-v3-monorepo/lib/` itself absent or empty), which blocks the D-D17 harness since `BaseVaultTest` transitively needs `permit2`. Adding the submodule falls under CLAUDE.md §8b/§8c. Revised per **D-D18** / **STAGE_D_NOTES D27**: `vault = makeAddr("vault")`, `vm.prank(vault)` on hook callback surfaces, `vm.mockCall` stubs for `IVault.{getPoolTokenCountAndIndexOfToken,addLiquidity,settle}`. Real tokens, real `MockERC4626`, real `MockFeeController`. Branch C (nested `_vault.swap` + `sendTo`) and routeX success paths deferred to D7 (real Vault required). D-D17 retained on record for the `MockVault` refusal; D-D18 supersedes only the harness-choice axis.

**Sub-step commits** (per-file, C6-pattern):

- `D5.1.a: test/mocks/MockERC20.sol`
- `D5.1.b: test/mocks/MockERC4626.sol`
- `D5.1.c: test/mocks/MockFeeController.sol`
- `D5.1: test/unit/AureumFeeRoutingHook.t.sol — cap, onAfterSwap, route*, one-shot, events, invariants`

Structure of the test file:

- `setUp()` — no harness inheritance; `Test` only. (1) `vault = makeAddr("vault")`; `bodensee`, `poolAB`, `poolC`, `admin` via `makeAddr` too — no real pool code needed at unit layer (the hook reads only pool *identity*, not pool state, on its unit-tested paths). (2) Deploy `MockERC20` for ZCHF, AuMM, tokenY; `MockERC4626` for svZCHF over the ZCHF `MockERC20` (so `IERC4626(svZchf_).asset()` returns ZCHF at hook construction); `MockFeeController`. (3) Construct `AureumFeeRoutingHook(vault, bodensee, IERC20(svZchf), IERC20(aumm), address(feeController), admin)`. (4) `vm.mockCall` base stubs: `IVault.getPoolTokenCountAndIndexOfToken(bodensee, svZchf)` → `abi.encode(uint256(2), uint256(1))`; `IVault.settle.selector` → `abi.encode(uint256(0))`. The `addLiquidity` stub is per-test because its return tuple `(uint256[] amountsIn, uint256 bptOut, bytes returnData)` depends on the amount in flight — configured by a helper `_mockAddLiquidity(uint256 svZchfAmount, uint256 bptOut)`. See **D-D18** / **STAGE_D_NOTES D27**.
- Named tests, organised by group (~50 total, target file length ~550 lines; Stage C precedent density):
  - **Constructor (8)** — `test_constructor_immutables` verifying all six immutables plus the cached ZCHF via `svZchf.asset()`; six zero-address reverts (vault, bodensee, svZchf, aumm, feeController, moduleAdmin); one non-ERC-4626 revert (`svZchf_` is a `MockERC20` lacking `asset()`).
  - **`getHookFlags` (1)** — `test_getHookFlags_shouldCallAfterSwapOnly` asserts all ten `HookFlags` fields individually (`shouldCallAfterSwap == true`, the other nine `== false`).
  - **`onRegister` (6)** — `notVault` revert, Bodensee-as-pool returns false, Bodensee-in-`tokenConfig` at index 0 and at the last index (exercises the loop head and tail separately) both return false, empty `tokenConfig` returns true, normal pool returns true.
  - **Module setters (12)** — six tests each for `setGovernanceModule` and `setIncendiaryModule`: (a) success + admin zeroed + event emitted, (b) `NotGovernanceAdmin`/`NotIncendiaryAdmin` revert from non-admin, (c) `ZeroAddress` revert on `module == 0`, (d) second call from the original admin reverts with `NotGovernanceAdmin`/`NotIncendiaryAdmin` (not `AlreadySet` — Gate 1 catches it because `_xxxAdmin` was zeroed atomically), (e) defensive `GovernanceModuleAlreadySet`/`IncendiaryModuleAlreadySet` via `vm.store`-crafted state (admin-non-zero + module-non-zero simultaneously; Gate 2 fires), (f) lock independence — setting governance must not mutate incendiary state and vice versa.
  - **`onAfterSwap` (10)** — `notVault` revert, recursion guard early-return (`params.router == address(hook)` returns `(true, amountCalculatedRaw)` without calling the fee controller), branch A (svZCHF fee, no-op phase 1, phase 2 mocked; asserts svZCHF transferred to vault, hook balance == 0 post-call, `SwapFeeRouted` event), branch B (ZCHF fee, real `forceApprove` + `MockERC4626.deposit`, phase 2 mocked; same assertions), zero forwarded amount no-op, multi-token iteration (`[ZCHF, svZCHF]` both non-zero, two phase-2 cycles, two events), mixed zero and non-zero amounts in the same call (skip-vs-execute correctness), **balance-sweep** (pre-mint dust svZCHF to hook, then onAfterSwap — phase 2 sweeps `dust + fresh`; the D3.3.4 Q1 / Option X documented design invariant), branch C deferred-shape (`[tokenY]` non-zero + valid pool → revert shape consistent with unmocked `_vault.swap`; guards against unplanned scope expansion), `returnsAmountCalculatedRaw` (verifies the second return value explicitly across branch A).
  - **`routeYieldFee` reverts (4)** — `UnauthorizedCaller`, `ZeroAddress` (pool), `InvalidPool` (pool == Bodensee), `ZeroAmount`. Each precondition satisfies all earlier gates (e.g., `ZeroAmount` test calls from `FEE_CONTROLLER` with a valid non-Bodensee pool). Success path deferred to D7 per **D-D18**.
  - **`routeGovernanceDeposit` reverts (3)** — `ModuleNotSet`, `UnauthorizedCaller` (module set, wrong sender), `ZeroAmount`. Success path deferred to D7.
  - **`routeIncendiaryDeposit` reverts (3)** — same shape.
  - **Fuzz (2)** — `testFuzz_onAfterSwap_branchA_amount(uint256 amount)` and `testFuzz_onAfterSwap_branchB_amount(uint256 amount)`, both bounded to `[1, 1e27]` to avoid ERC-20 overflow while exercising the full numeric range. Per-run `vm.mockCall` for `addLiquidity` returning the fuzzed amount.
- Invariant fuzz tests deferred to D7: both `invariant_BodenseeBalanceMonotonic` and `invariant_HookHoldsNoTokens` require real Vault accounting across randomised call sequences, which `vm.mockCall` cannot express. The per-test `hook balance == 0 post-call` assertion embedded in branch A / B provides the second invariant's coverage at the unit layer.

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
- Imports: forge-std `Script`; Balancer V3 `IVault`, `IWeightedPoolFactory`, `IRateProvider`; Balancer V3 `TokenConfig`, `TokenType`, `PoolRoleAccounts` from `@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol`; OZ `IERC20`.
- `run()` reads env vars: `WEIGHTED_POOL_FACTORY`, `AUMM`, `SV_ZCHF`, `SUSDS`, `GOVERNANCE_MULTISIG`, `BODENSEE_SALT`. `GOVERNANCE_MULTISIG` serves both `pauseManager` and `swapFeeManager` roles per NOTES L103 / L106. The factory's Vault is bound at the factory's own deploy-time — no `AUREUM_VAULT` env read needed. No `FEE_CONTROLLER` env read — see below.
- Builds ascending-address-sorted `TokenConfig[]`: AuMM (`STANDARD`, `rateProvider = IRateProvider(address(0))`, `paysYieldFees = false`); sUSDS (`WITH_RATE`, `rateProvider = IRateProvider(0x1195be91e78ab25494c855826ff595eef784d47b)`, `paysYieldFees = true`); svZCHF (`WITH_RATE`, `rateProvider = IRateProvider(0xf32dc0ee2cc78dca2160bb4a9b614108f28b176c)`, `paysYieldFees = true`). Rate Provider addresses per **D11** (existing mainnet deployments). `paysYieldFees` for the two `WITH_RATE` tokens is cosmetic — D-D9 guard blocks Bodensee yield collection at the controller level regardless.
- Builds `normalizedWeights[]` parallel to sorted `tokens[]`: AuMM `4e17` (40%), sUSDS `3e17` (30%), svZCHF `3e17` (30%); sum = `1e18 = FixedPoint.ONE`.
- Builds `PoolRoleAccounts = { pauseManager: GOVERNANCE_MULTISIG, swapFeeManager: GOVERNANCE_MULTISIG, poolCreator: address(0) }`. `poolCreator` MUST be zero — `WeightedPoolFactory.create` at `lib/balancer-v3-monorepo/pkg/pool-weighted/contracts/WeightedPoolFactory.sol:67-L69` reverts `StandardPoolWithCreator()` otherwise; enforces the `aumm-specs` §xxix no-creator-fees rule.
- Calls `IWeightedPoolFactory(WEIGHTED_POOL_FACTORY).create("der-Bodensee", "BODENSEE", tokens, normalizedWeights, roleAccounts, 0.0075e18, address(0), false, false, BODENSEE_SALT)` and captures the returned `address pool`. The 10 args in order: `name`, `symbol`, `TokenConfig[]`, `normalizedWeights[]`, `PoolRoleAccounts`, `swapFeePercentage`, `poolHooksContract`, `enableDonation`, `disableUnbalancedLiquidity`, `salt`.
- No separate `Vault.registerPool` call — `WeightedPoolFactory.create` calls `_registerPoolWithVault` internally at `WeightedPoolFactory.sol:90`.
- No `AureumProtocolFeeController` calls. OQ-2 (Bodensee fee-exclusion) is enforced structurally, not at registration: setters revert `SplitIsImmutable` post-D0.5 retrofit (`e5dc936`); swap-aggregate pinned to `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50e16` at `registerPool` regardless of inputs; yield collection blocked by the D-D9 `BodenseeYieldCollectionDisabled` guard in `collectAggregateFees`. See **D28** in `STAGE_D_NOTES.md` for the full reconciliation.
- Logs the deployed pool address via `console2.log`.
- Pool-parameter source of truth: `docs/STAGE_D_NOTES.md` "Der Bodensee deployment parameters" block (L88–L109) — any drift between this §D6.1 structure and that block is a bug in this section.

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

### §D7.1 — Fork test harness setUp + test enumeration (stub)

**Status.** Stub. Full enumeration finalizes at D7 entry per **D30** resolution.

**Dependency chain (D30).**

1. `script/DeployAureumVault.s.sol` — deploys `AureumAuthorizer`, `AureumProtocolFeeController`, `AureumVaultFactory`; CREATE3-predicted `AUREUM_VAULT`; placeholder immutables (`FEE_ROUTING_HOOK`, `DER_BODENSEE_POOL`) replaced by predicted real addresses via `vm.computeCreateAddress(deployer, nonce)` and CREATE2 factory+salt.
2. `script/DeployAureumWeightedPoolFactory.s.sol` (new per D30) — deploys Balancer's unchanged `WeightedPoolFactory` bytecode with `IVault = AUREUM_VAULT`. Sets `WEIGHTED_POOL_FACTORY` env.
3. AuMM deploy (or `MockERC20` stand-in per D30; choice pinned at D7 entry) — sets `AUMM` env.
4. `script/DeployDerBodensee.s.sol` — creates der Bodensee pool via the Aureum-bound WPF.
5. `AureumFeeRoutingHook` deploys at the predicted CREATE address from step 1's nonce arithmetic.

**Authorizer.** `AureumAuthorizer.canPerform` grants all actions to `GOVERNANCE_MULTISIG` only (`src/vault/AureumAuthorizer.sol:19-21`). Tests calling `authenticate`-gated functions (e.g., `withdrawProtocolFees(address pool, address recipient)` — 2-arg per `src/vault/AureumProtocolFeeController.sol:639-650`) prank as `governanceMultisig`.

**Provisional test list (finalized at D7 entry).**

- `test_Fork_SwapRoutesFeeToBodensee` — swap-leg happy path; swap fee routes Vault → hook → Bodensee.
- `test_Fork_BodenseeYieldCollectionReverts` — D-D9 / OQ-2 structural guard at `collectAggregateFees(DER_BODENSEE_POOL)`.
- `test_Fork_RecursionGuard` — trusted-router early-return on `params.router == address(this)` per D10.
- `test_Fork_RouteYieldFeePrimitive` — direct hook-side `routeYieldFee` (prank as `FEE_CONTROLLER`); confirms `safeTransferFrom` structural invariant. Controller entry-point integration deferred to D4.6 per OQ-20.
- `test_Fork_WithdrawProtocolFeesRecipientCheck` — B10 `InvalidRecipient` guard (`src/vault/AureumProtocolFeeController.sol:639-642`); prank as `governanceMultisig`; confirms 2-arg `(pool, recipient)` signature.

### D7.2 — Run fork tests

```
forge test --match-path "test/fork/AureumFeeRoutingHook.t.sol" --fork-url $MAINNET_RPC_URL -vv
forge test --fork-url $MAINNET_RPC_URL -vv
```

Paste full output of the second invocation. Full baseline + Stage D fork additions all green.

**Commit:**

```
git add test/fork/AureumFeeRoutingHook.t.sol
git commit -m "D7: test/fork/AureumFeeRoutingHook.t.sol — end-to-end fee routing on mainnet fork"
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

**`minBptAmountOut = 0` on the one-sided Bodensee add gets sandwiched.** A MEV bot front-runs the hook's `IVault.addLiquidity` call on der-Bodensee (phase 2 of `_swapFeeAndDeposit`), mints dust BPT for the hook by depositing a tiny amount, then back-runs with a swap that profits from price dislocation. Stage D uses `minBptAmountOut = 0` because the protocol internalizes this risk (it's the protocol's own fee, not user funds). Stage Q audit will revisit; if the audit flags this as a real loss vector, the mitigation is a trusted-caller check on the Bodensee add or a dynamic `minBptAmountOut` computed from the current svZCHF/BPT ratio. Document in `STAGE_D_NOTES.md` as a known audit surface.

**D4 two-immutables shape breaks existing Stage B tests in non-obvious ways (per D-D7 reconciled / STAGE_D_NOTES D23).** `DER_BODENSEE_POOL` persists post-D4 — it serves the D-D9 `collectAggregateFees` pool-identity guard — but every B10 withdrawal-recipient assertion shifts to `FEE_ROUTING_HOOK`. Existing Stage B tests that asserted `controller.DER_BODENSEE_POOL()` as the B10 recipient must split: (a) B10-recipient assertions and the withdraw-recipient test-harness constants migrate to `controller.FEE_ROUTING_HOOK()`; (b) Bodensee-pool-identity assertions (the D-D9 test and the surviving "getter returns the constructor arg" test for the retained immutable) stay on `controller.DER_BODENSEE_POOL()`. Recovery sweep: `grep -rn 'DER_BODENSEE_POOL' src/ test/ script/` post-D4 should return **only** the immutable declaration, the constructor assignment, the D-D9 guard site, the D-D9 test, and the one "getter returns the constructor arg" test; **any occurrence inside a withdrawal-recipient check, an `InvalidRecipient(...)` error argument, or a B10 assertion is stale** and must be updated to `FEE_ROUTING_HOOK`. Fix and recommit as a D4 follow-up (or squash into D4 before pushing).

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
    ├── mocks/
    │   ├── MockERC20.sol                     — minimal OZ ERC-20 + mint/burn helpers (new)
    │   ├── MockERC4626.sol                   — share token over underlying; asset(), deposit, redeem (new)
    │   ├── MockFeeController.sol             — IAureumProtocolFeeControllerHookExtension stub (new)
    └── fork/
        └── AureumFeeRoutingHook.t.sol              — mainnet-fork integration (new)
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
| 2026-04-21 | D3 — `src/fee_router/AureumFeeRoutingHook.sol` | ✅ | `ed4ec75` | **D3.3.3** `a341e44` introduced `AureumFeeRoutingHook.sol` as a 373-line initial scaffold — constructor + immutables + caller-gate storage, `BaseHooks` / `IAureumFeeRoutingHook` / `VaultGuard` inheritance, `onAfterSwap` with trusted-router early-return per **D10**, and `_swapFeeAndDeposit` phase-1 body (svZCHF skip / ZCHF wrap / nested `_vault.swap`); covers D3.1 + D3.2 + D3.3 skeleton in a single commit. **D3.3.1** `bc920a0` added `src/fee_router/IAureumProtocolFeeControllerHookExtension.sol` (62 lines) — hook-extension interface the fee controller will implement for the yield-leg wiring at D4 / D5. **D3.3.4** phase-2 one-sided-add helper `_addLiquidityOneSidedToBodenseeViaVault` folded into **D3.4a** `3802003` per **D21** (WT-vs-HEAD drift surfaced at prompt-drafting time); helper uses direct `_vault.addLiquidity` + `safeTransfer` + `_vault.settle` shape per **D20** (Router→Vault mechanism drift: Balancer's `ExitFeeHookExample` precedent, not Router's wrapped path). D3.4 external primitive entry points landed one pair per commit: **D3.4a** `3802003` thread BPT recipient through routing helpers; **D3.4b** `7b91a1a` `routeYieldFee` + `_routeYieldFeeUnlocked`; **D3.4c** `478cbf7` `routeGovernanceDeposit` + `_routeGovernanceDepositUnlocked` + `IAureumFeeRoutingHook.ModuleNotSet()` added on the interface (Q7 validation order `ModuleNotSet` → `UnauthorizedCaller` → `ZeroAmount`); **D3.4d** `ed4ec75` `routeIncendiaryDeposit` + `_routeIncendiaryDepositUnlocked` + drop `RoutingNotYetImplemented` (last user of the error; declaration removed in the same edit). Each inner unlock callback returns `uint256` directly per **D22** (mirror of Balancer Router's `swapSingleTokenHook`; not `bytes memory` + `abi.encode`). **D3.5** `forge lint src/fee_router/` clean — zero findings. Design anchors: **D10** recursion-guard via trusted-router early return; **D16** three-primitive external shape per D-D2 Option A; **D17** β1 custody + fast-path-only `swapPool == address(0)` contract for governance / Incendiary; **D20** direct-Vault one-sided-add mechanism; **D21** authoritative reads from `git show stage-d:<path>` at prompt-drafting time (§8e.1); **D22** `IVault.unlock` inner callbacks return `uint256` directly. Surface at D3 tip: `AureumFeeRoutingHook.sol` 531 lines, shasum `504c30f206fbd60ed70cf384d47c3a2dd487b00c24f2a16d8c4f91603a49e816`, 22 em-dashes; `IAureumFeeRoutingHook.sol` 199 lines; `IAureumProtocolFeeControllerHookExtension.sol` 62 lines (792 lines total under `src/fee_router/`). `forge build` green; no tests at D3 (unit tests land at D5). |
| 2026-04-21 | D4 — `AureumProtocolFeeController` modifications | ✅ | `004aa51` | **D4.2** applied **D-D7** B10 retarget in two-immutables shape per **D23** (pre-implementation reconciliation at `47b94f4`): new `FEE_ROUTING_HOOK` immutable added as the B10 withdrawal-recipient target; `DER_BODENSEE_POOL` retained to serve the D-D9 pool-identity check only. Constructor signature grew to `(IVault, derBodenseePool, feeRoutingHook)` with zero-address checks split across the two address arguments. **D4.3** added `BODENSEE_SWAP_FEE_MIN` / `_MAX` / `_GENESIS` band constants per **D-D8** / **OQ-11** (0.10% / 1.00% / 0.75%). **D4.4** added `BodenseeYieldCollectionDisabled` revert at the entry of `collectAggregateFees(address pool)` when `pool == DER_BODENSEE_POOL` per **D-D9** / **OQ-2**. **D4.5** test updates landed in the same commit per plan L407: `test/unit/AureumProtocolFeeController.t.sol` gained a `FEE_ROUTING_HOOK_PLACEHOLDER` sentinel (`0xBEEF`), three-arg constructor in `setUp`, split zero-check tests (Bodensee / Hook variants), `FEE_ROUTING_HOOK()` getter assertion, retargeted B10 fuzz recipients and invariant 4, and `test_collectAggregateFees_revertsOnBodenseePool` for D-D9. Scope expanded per **D24** (Cursor autonomous scope expansion in D4.5 Prompts A and D) beyond the plan's D4 surface to thread the new env var through `test/fork/DeployAureumVault.t.sol` (`FEE_ROUTING_HOOK` constant + `vm.setEnv` wiring), `script/DeployAureumVault.s.sol` (env read + third ctor arg + inlined `keccak256(type(X).creationCode)` hashes releasing three stack slots to keep `_deploy` within the IR optimiser's stack-depth budget after the added argument), and `.env.example` (documented). Post-D4 test-harness fix **`2fec725`**: `test/fork/Sanity.t.sol` self-forks from `MAINNET_RPC_URL` and skips when unset (+31 / −8), resolving a residual brittleness surfaced during D4.5. Surface at D4 tip: `AureumProtocolFeeController.sol` 765 lines, shasum `3f3f27c18f3a10dceeb9963f646952a60de95cd905053979aab7a3c39dbcd42f`, 9 em-dashes; `AureumProtocolFeeController.t.sol` 685 lines. Commit message deviated from the plan's prescribed `D4: AureumProtocolFeeController — B10 retarget + OQ-11 band + OQ-2 Bodensee guard`; no re-do. `forge build` green. |
| 2026-04-21 | D3 fix — `onAfterSwap` emits `SwapFeeRouted` | ✅ | `3e3db4b` | Surfaced at **D5.1** authoritative-read time: `IAureumFeeRoutingHook` declares `SwapFeeRouted(address indexed pool, address indexed feeToken, uint256 feeAmount, uint256 bptMinted)` but the on-branch impl at `ed4ec75` never emitted it (`grep -n "emit SwapFeeRouted" src/fee_router/AureumFeeRoutingHook.sol` against `stage-d` returned zero hits; `test_Event_SwapFeeRouted` per L503 below would have failed). Patched `onAfterSwap`'s loop body in a single edit: capture `uint256 bptMinted = _swapFeeAndDeposit(tokens[i], forwardedAmounts[i], params.pool, address(this))`, then `emit SwapFeeRouted(params.pool, address(tokens[i]), forwardedAmounts[i], bptMinted)`. Per `STAGE_D_NOTES.md` L163, the outer `if (forwardedAmounts[i] == 0) continue;` already excludes the recovery-mode short-circuit case from the emit, so no additional guard is needed. Net diff `+12 / −1`; `AureumFeeRoutingHook.sol` 531 → 542 lines; em-dash count unchanged at 22; new shasum `e15fc3032de1cb9d170e587043ec867b22d8401eedd2cff49122fdea5f19efd6`. `forge build` clean; `forge test` 98/98 green (no existing test asserts on `SwapFeeRouted` — **D5.1** will be the first). **D25** logged in `STAGE_D_NOTES.md` (`bd6e891`) with discovery context plus a `grep -c "emit <EventName>"` discipline fold-in at impl sub-step close. The D3 row above is retained unchanged as a historical snapshot at `ed4ec75`; current metrics are in this row. |
| 2026-04-22 | D5 — unit tests | ✅ | D5.1 `5905a40`, D5.2 `06df412` | D5.1: `test/unit/AureumFeeRoutingHook.t.sol` (850 lines, 49 named + 2 fuzz). Harness per **D-D18** / **D27**: `makeAddr("vault")` + `vm.mockCall` stubs — no `BaseVaultTest` / permit2 dependency. Constructor (8), `getHookFlags` (1), `onRegister` (6), module-setter two-flag lock with defensive `vm.store` AlreadySet path (12), `onAfterSwap` branches A + B + C-deferred-shape + balance-sweep (10), `routeX` gate reverts (10), fuzz (2). Branch C success paths, routeX-via-unlock success, and invariant fuzz deferred to D7 per D-D18 scope boundary. D5.2: `test/unit/AureumProtocolFeeController.t.sol` +18 lines — `test_B10_TargetIsHookAddress` + `test_BodenseeBand_Constants`; other D4 additions already in the 685-line D4.5 file. D5.3: 146/146 across 6 unit suites green, 0 failed. Both commits pushed to `origin/stage-d`. |
| 2026-04-22 | D6 — `script/DeployDerBodensee.s.sol` (fork-only, 40/30/30 WeightedPool: AuMM / sUSDS / svZCHF; runtime ascending token sort; D11 Rate Providers — sUSDS `0x1195BE91e78ab25494C855826FF595Eef784d47B`, svZCHF `0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c`, AuMM identity `address(0)`; pauseManager = swapFeeManager = governance Safe, poolCreator = `address(0)`; swap fee 0.75% (0.0075e18); `poolHooksContract = address(0)`; `enableDonation = false`, `disableUnbalancedLiquidity = false`; OQ-2 Bodensee yield collection structurally disabled at controller per D-D9 — no fee-controller setters at registration; **`WEIGHTED_POOL_FACTORY` env is the Aureum-bound WPF deployed by `DeployAureumWeightedPoolFactory.s.sol` per D30 — not mainnet Balancer WPF**) | ✅ | `18f74b9` | D-D6 fork-only; D11 Rate Providers; D28 pre-flight reconciliation; D30 Aureum-bound WPF sourcing |
|  | D7 — fork tests | ⏳ |  |  |
|  | D8 — Slither triage | ⏳ |  |  |
|  | D9 — `stage-d-complete` tag pushed | ⏳ |  |  |
