# Robustness Backport Register

> **Scope.** Tracks candidate hardening items for completed Stage B–F surfaces (and Stage G surfaces that have already landed at file scope). Each row is a focused, self-contained robustness improvement — no architecture re-litigation, no behavior changes beyond closing an attack / error class. Items are ranked by `Exploitability × inverse(Cost)` and worked in small "robustness packets" (interface / type locks → state / admin slot cleanup → revert-surface + negative tests → cross-stage docs reconciliation) so completed stages stay shippable while safety compounds.
>
> **Process.** Items enter at status `Open` via audit (planned or opportunistic); move to `Scoped` once the §8e.1-shape change is sized; `In-flight` once a sub-step is authored; `Closed` once the commit lands. Closure rows record the commit hash + a one-line delta describing what attack / error class was removed.
>
> **Out of scope.** Architecture decisions (fee split, factory pattern, authorizer model, vault isolation), spec-level token / pool selections, and emission-curve constants. These are sealed at their respective stage decisions and only reopen via explicit chat-level discussion.

## Register

| ID | Stage | Surface | Class | Description | Exploitability | Cost | Priority | Status | Resolution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RB-001 | F | `test/fork/mocks/CCBMocks.sol::MockGaugeRegistry` | Cross-stage interface | Stage F mock must mirror `IGaugeRegistry` methods added at G3.1 (extend-in-place per G-D16a Option B); silent drift surfaces as ABI mismatch on mock recompile. Already flagged in `docs/STAGE_G_PLAN.md` G4.4 body. | Medium | Low | Mid | Scoped | — |
| RB-002 | F | `src/ccb/CCBMultiplier.sol::emaSampler` | Storage-class hardening | `IEMASampler public emaSampler` assigned in constructor (L155), never reassigned; promote to `public immutable`. Eliminates storage-write attack surface and saves one SLOAD per `getMultiplier` / `updateMultiplier` call. Single-line diff; Stage F unit + fork suites are the regression. | Low | Low | High | Closed | `2fe6ef8` — `emaSampler` slot promoted to `immutable`; storage-write surface eliminated; Stage F regression 263/263 green. |
| RB-003 | E | `src/factory/AureumWeightedPoolFactory.sol::_poolVersion` | Storage-class hardening | `string private _poolVersion` assigned in constructor (L46); Solidity 0.8.21+ supports `string immutable`, so eligible at our `^0.8.26` pragma. Tradeoff: code-size growth vs SLOAD elimination + write-surface removal. Alternative `bytes32 immutable` migration changes the `getPoolVersion()` return type (ABI break). Defer pending design-check on string-immutable code-size impact and call-site read frequency. | Low | Medium | Low | Open | — |
| RB-004 | D / E / F | `test/fork/AureumFeeRoutingHook.t.sol`, `test/fork/PilotPools.t.sol`, `test/unit/CCBMultiplier.t.sol` | External-call & type-cast safety | 21 `forge-lint` warnings across three test files (2× `erc20-unchecked-transfer`, 19× `unsafe-typecast`). Fix at source: migrate bare `transfer` calls to `SafeERC20.safeTransfer` (fork hook test L382, pilot pools test L348); replace `uint256(STEP_SIZE)` / `uint256(CLAMP_FLOOR)` / `uint256(CLAMP_CEILING)` repeated casts with typed constants (one `uint256` for assertions, one `int256` for signed delta arithmetic); replace `uint256(int256(uint256(x)) + delta)` chains with an `_applySignedDelta(uint256, int256)` helper (extends F12 to test code); replace `address(uint160(0xC0FE0000 + i))` synthetic pool addresses with labeled `makeAddr(string.concat("pool", vm.toString(i)))`. Zero lint suppressions. | Low | Low | Mid | Closed | 8bc8e6e–7bdfbcc — 2x bare transfer to SafeERC20.safeTransfer; 19x unsafe-typecast to SafeCast typed-constant + _applySignedDelta helper (F12 extended to test code) + makeAddr synthetic-address migration; forge-lint 0/21; F13/F14 in docs/STAGE_F_NOTES.md (d2cd966); 263/263 green. |
| RB-005 | G / H | `test/unit/GaugeEligibility.t.sol`, `test/unit/EfficiencyOracle.t.sol`, `test/unit/TVLOracle.t.sol` | External-call & type-cast safety | 8 `forge-lint` `unsafe-typecast` warnings across three test files (6× `GaugeEligibility.t.sol` L717 + L736 + L756 — `address(uint160(0x10000 + uint160(i)))` synthetic-pool generator regressed against the RB-004 standard; 1× `EfficiencyOracle.t.sol` L51; 1× `TVLOracle.t.sol` L32 — same anti-pattern inherited at H2a / H2b). Fix per RB-004 canonical: replace `address(uint160(0x10000 + uint160(i)))` with labeled `makeAddr(string.concat("pool", vm.toString(i)))`. Zero `forge-lint: disable-next-line` suppressions in test code. Sequence at Stage H close-of-stage docs sweep alongside §11 / Completion Log catch-up. | Low | Low | Mid | Closed | 19c0177 — 8x forge-lint unsafe-typecast warnings closed: 6x GaugeEligibility.t.sol L717/L736/L756 address(uint160(0xN+uint160(i))) → makeAddr(string.concat("pool",vm.toString(i))) per RB-004 canonical; 2x _addr helpers in EfficiencyOracle.t.sol L51 + TVLOracle.t.sol L32 repurposed to makeAddr(vm.toString(seed)) dropping pure; forge-lint 0/8; 370/370 unit suite green at H3.8.1 close. |

## Hardening classes

- **Input-domain hardening** — replace loose params with enums / value objects; restrict accepted shapes at the public surface.
- **Allowlist hardening** — explicit accepted-token / accepted-type domains; fail closed, never best-effort.
- **Strict-equality vs tolerance audit** — enforce exactness where exact is safer (anti-spam fees, fee splits, immutable invariants); reject "epsilon" tolerance unless physically required.
- **Admin-path hardening** — one-shot setters, burn-after-init, no lingering privileged slots; admin slot zeroed atomically with module-set.
- **Storage-class hardening** — promote storage variables to `immutable` / `constant` when never reassigned after construction; locks slot type at deploy, removes storage-write attack surface, eliminates one SLOAD per read. Eligible for value types and (since Solidity 0.8.21) reference types like `string` / `bytes`.
- **Epoch / boundary determinism** — no mid-interval state surprises; epoch transitions read-once, written-once.
- **Error taxonomy** — custom errors mapped 1:1 to guard classes; no `require(string)`, no plain `revert()`.
- **Invariant tests** — unauthorized caller, invalid type / token, under / overpay, reentrancy, stale callbacks, malformed payloads — every guard has at least one failing-path test.
- **Cross-stage interface** — when an interface is extended in-place across stages, dependent mocks / tests must mirror the change in the same commit; never silent drift.
- **External-call & type-cast safety** — wrap external ERC20 movements in `SafeERC20.safeTransfer` / `safeTransferFrom`; replace narrowing typecasts (`uint256(int256_var)`, `int256(uint256_var)`, `address(uint160(...))`) with typed constants, signed-add helpers, and labeled `makeAddr` synthetic addresses. Fix `forge-lint` warnings at source — zero `forge-lint: disable-next-line` suppressions in production or test code.

## Delivery packets

- **Packet A** — interface / type locks (entry-time hardening; cheap, sets the scaffold for everything else).
- **Packet B** — state / admin slot cleanup (single-slot burn patterns, removed redundant mirrors, transient-vs-storage decisions).
- **Packet C** — revert-surface + negative tests (one failing-path test per guard; revert-coverage ≥ 1.0 over guard count).
- **Packet D** — cross-stage docs reconciliation (NOTES wording fixes that block the next §8e.1 per CLAUDE.md §12 ambiguity-gate).

## KPI dashboard (per stage rollup)

- Ambiguities found pre-implementation.
- Guard-condition tests added.
- Revert-surface coverage count.
- Dead / redundant state avoided.
- Cross-stage interface breaks avoided.

## Cross-references

- **CLAUDE.md §12 — Ambiguity-gate for typed domain and state semantics** (commit `27bc91d`). This register is downstream of that gate; rows entered here are the artifacts left by ambiguities the gate caught + opportunistic hardening items surfaced during stage audits.
- **Stage `_NOTES.md` files** (per stage). Register cites stage notes for design context; stage notes do not duplicate register rows. Closure deltas in the `Resolution` column reference the originating stage NOTES finding when applicable (e.g. `F12 → RB-NNN closed at <hash>`).
