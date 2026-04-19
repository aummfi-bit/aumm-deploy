# Stage C — Time Library + AuMM Token

> **Status:** Ready to start. Stage B is complete at `stage-b-complete` (commit `b627a92`, 2026-04-14).
>
> **Audience:** Sagix, plus any future Claude session that needs to know what Stage C is and what it produces.
>
> **Why this file exists:** so the plan survives outside chat scrollback. This file is the entry point for Stage C work.

---

## Scope of Stage C

**Goal:** ship the two deepest primitives every other contract in the protocol depends on — the canonical block-number math library and the AuMM ERC-20 token with its immutable halving schedule. Also reorganise the existing Stage B contracts into `src/vault/` to match the folder layout pinned in `docs/STAGES_OVERVIEW.md`.

**The Solidity files Stage C produces:**

1. **`src/lib/AureumTime.sol`** — pure library. Block-number math: the canonical time constants pinned by `FINDINGS.md` OQ-3/OQ-4/OQ-5 (`BLOCKS_PER_DAY = 7_200`, `BLOCKS_PER_WEEK = 50_400`, `BLOCKS_PER_EPOCH = 100_800`, `BLOCKS_PER_MONTH = 219_000`, `BLOCKS_PER_QUARTER = 657_000`, `BLOCKS_PER_YEAR = 2_628_000`, `BLOCKS_PER_ERA = 10_512_000`), plus `monthIndex(genesis, block)`, `epochIndex(genesis, block)`, `eraIndex(genesis, block)` and named boundary helpers (`month6EndBlock(genesis)`, `month10EndBlock(genesis)`, `month13StartBlock(genesis)`, `year1EndBlock(genesis)`, `firstHalvingBlock(genesis)`, `nthHalvingBlock(genesis, n)`). No state. ~150 LOC.

2. **`src/token/AuMM.sol`** — ERC-20 with:
   - 21,000,000 AuMM fixed cap (`MAX_SUPPLY = 21_000_000e18`).
   - Immutable `GENESIS_BLOCK` set in constructor.
   - Geometric halving schedule: `blockEmissionRate(uint256 blockNumber)` pure-view returns the per-block emission rate for that block's era, computed via right-shift (`GENESIS_RATE >> eraIndex`) until integer underflow naturally drives it to zero.
   - One-shot `setMinter(address newMinter)` callable exactly once by the deployer address set in the constructor; sets the `minter` public state and self-locks the admin slot. After that block, `mint` is gated by `minter` and the setter can never be called again. **Stage C pioneers this placeholder + one-shot-setter pattern** that Stage G's `GaugeRegistry`, Stage J's `MiliariumRegistry`, and Stage K's authorizer migration will later mirror (per `STAGES_OVERVIEW.md`). Simpler than CREATE3 address-preimage gymnastics for the AuMM → distributor hand-off.
   - `mint(address to, uint256 amount)` gated by `msg.sender == minter`, with a hard `totalSupply() + amount <= MAX_SUPPLY` backstop even if the halving schedule's era accounting somehow overshoots. No burn interface — OpenZeppelin's `ERC20` base exposes no public `burn`, and the spec (§ix) treats 21M as a supply cap, not an inflation ceiling post-burn. **`ERC20Burnable` is deliberately not used.**
   - No treasury, no pre-mint, no owner, no upgradability. Constructor does not mint any AuMM.
   - Custom errors, not revert strings.

   ~200 LOC.

3. **`src/token/IAuMM.sol`** — thin interface. Declares `mint`, `setMinter`, `minter()`, `MAX_SUPPLY`, `GENESIS_BLOCK`, `GENESIS_RATE`, `blockEmissionRate`. Stage H's emission distributor imports this to decouple compile-time dependency shape from implementation. Matches the Stage B pattern of `AureumVaultFactory` taking `IProtocolFeeController` in its constructor. ~40 LOC.

**The unit tests Stage C produces:**

- `test/unit/AureumTime.t.sol` — named tests for every constant, every helper, every boundary (genesis block, `MONTH_6_END_BLOCK`, `MONTH_10_END_BLOCK`, `MONTH_13_START_BLOCK`, `YEAR_1_END_BLOCK`, `FIRST_HALVING_BLOCK`, nth-halving for `n ∈ {1, 2, 5, 10}`, era `N` for `N ∈ {0, 1, 2, 5, 10}`). Fuzz tests over `uint256` block ranges. Property tests: `monthIndex` / `epochIndex` / `eraIndex` monotonic non-decreasing, transitions are exactly on boundaries, index math is consistent with the canonical constant table.

- `test/unit/AuMM.t.sol` — named tests for cap enforcement, minter gate, `setMinter` one-shot lock, halving rate at each era boundary, rate strictly non-increasing across boundaries, `Transfer` event on mint. Invariant tests for: (a) `totalSupply() <= MAX_SUPPLY` across any sequence of mints, (b) `mint` reverts from any address except the one `setMinter` was called with.

**The directory reorganisation Stage C performs:**

Move existing Stage B Solidity from `src/*.sol` to `src/vault/*.sol`:

- `src/AureumVaultFactory.sol` → `src/vault/AureumVaultFactory.sol`
- `src/AureumProtocolFeeController.sol` → `src/vault/AureumProtocolFeeController.sol`
- `src/AureumAuthorizer.sol` → `src/vault/AureumAuthorizer.sol`

Update `script/DeployAureumVault.s.sol` import paths. Update `test/unit/AureumAuthorizer.t.sol`, `test/unit/AureumProtocolFeeController.t.sol`, and `test/fork/DeployAureumVault.t.sol` import paths. Update `foundry.toml` lint-ignore path for both `AureumVaultFactory.sol` and `AureumProtocolFeeController.sol`. Update `README.md` "Repository layout" section. `remappings.txt` unchanged (remappings point at `lib/`, not `src/`) but verified during C1.

---

## Pragma note (Stage B vs Stage C)

Stage B's `AureumVaultFactory.sol` and `AureumProtocolFeeController.sol` use `pragma solidity ^0.8.24` inherited verbatim from upstream Balancer V3 — deliberate byte-identity. Stage B's `AureumAuthorizer.sol` uses `pragma solidity ^0.8.26`. Stage C files (`AureumTime.sol`, `AuMM.sol`, `IAuMM.sol`) are Aureum-authored and use `pragma solidity ^0.8.26` per cursorrules rule 4. Both pragmas coexist in the compilation set — `solc 0.8.26` satisfies both carets. If any Stage C-executing Claude proposes "fixing" the Stage B pragma mismatch, refuse: byte-identity with upstream is the audit-inheritance foundation.

---

## Import-path convention note

Stage B used remapped paths for externals (`@openzeppelin/...`, `@balancer-labs/...`) and had no cross-subfolder sibling imports because everything was flat in `src/`. Stage C splits into `src/vault/`, `src/lib/`, and `src/token/`, which introduces Aureum-to-Aureum sibling imports. Convention: use `src/`-rooted paths (e.g., `import {AureumTime} from "src/lib/AureumTime.sol";`), not relative (`../lib/`) and not re-remapped. Foundry resolves these correctly because `foundry.toml` has `src = "src"`. Cursorrules rule 4's "never relative paths across package boundaries" applies to external deps, not intra-Aureum imports.

---

## Decisions locked in before Stage C starts

These are the answers to the planning-stage questions resolved before this file was written. They are recorded here so implementation doesn't re-litigate them.

| ID | Decision |
|----|----------|
| **C-D1** | **Stage C scope:** AuMM only. AuMT is Stage I (`STAGES_OVERVIEW.md` row I). Do not write AuMT in Stage C even though `FINDINGS.md` groups both under `src/token/`. |
| **C-D2** | **Minter authorization = one-shot setter pattern.** AuMM ships with `setMinter(address)` callable exactly once by the constructor-set deployer/admin address. First call locks `minter` permanently and zeroes the admin slot. Stage H's distributor deployment calls this once. **Stage C pioneers this pattern** — Stage G's `GaugeRegistry` (`onlyGovernanceContract` gated by a placeholder replaced in Stage K), Stage J's `MiliariumRegistry` (same shape), and Stage K's authorizer migration (`Vault.setAuthorizer` one-shot) all adopt the same shape afterward. Simpler than CREATE3 address-preimage gymnastics. Aligned with cursorrules "no admin keys" because the setter self-destructs after single use. |
| **C-D3** | **Halving math lives in AuMM.** `blockEmissionRate(uint256 blockNumber)` pure-view on the token. Distributor in Stage H is a consumer, not an owner, of the schedule. Rationale: §xxix declares halving immutable; it belongs with the token. |
| **C-D4** | **C1 is a pure `git mv` commit** with zero behavioural change. `forge build` green and all Stage B unit + fork tests pass unchanged before any new code lands. Keeps the reorganisation diff reviewable. |
| **C-D5** | **Unit tests only in Stage C.** No fork tests — AuMM and `AureumTime` are pure logic with no Vault dependency. Fork tests return in Stage D when the fee-routing hook wires AuMM and the Vault together. |
| **C-D6** | **Slither triage gate before the tag.** Same B6-style invocation (`slither . --filter-paths "lib|test"`), same inline-suppress-with-rationale discipline, findings logged in `STAGE_C_NOTES.md`. |
| **C-D7** | **Era ≥ 6 underflow behaviour:** integer-division halving in `blockEmissionRate` naturally underflows to zero when the right-shift exceeds `log2(GENESIS_RATE / 1 wei)` (~60 eras for 18-decimal AuMM, well past the point where `totalSupply` is within epsilon of `MAX_SUPPLY`). A hard `totalSupply() + amount <= MAX_SUPPLY` check in `mint` is the constitutional backstop even if the schedule's arithmetic somehow produces an unexpected amount. Coverage point lands as an invariant in C7. |
| **C-D8** | **`IAuMM.sol` interface ships in Stage C.** Stage H imports it. Matches `AureumVaultFactory`'s Stage B pattern of consuming `IProtocolFeeController`. |
| **C-D9** | **`STAGE_C_NOTES.md` scaffolded at C0** as the living design-decision log, mirroring `STAGE_B_NOTES.md`. Decisions made during C2-C8 implementation drop there, numbered `C10, C11, ...` to avoid collision with the `C-D*` planning decisions above. |
| **C-D10** | **No new dependencies.** `openzeppelin-contracts` v5.6.1 (already installed — `ERC20` base only, NOT `ERC20Burnable`) and `forge-std` v1.15.0 (already installed, for `Test` base). No new `forge install` calls. Per cursorrules "Ask before adding a new dependency" — none are being added. |
| **C-D11** | **`minter` is `public`, not `private`.** Storage is `address public minter` — OpenZeppelin's auto-generated getter matches `IAuMM.minter()` exactly, saves one explicit function. The admin slot is `address private _minterAdmin`, zeroed post-setMinter to signal self-destruction of that authority. Two-flag state machine is intentional belt-and-suspenders: `_minterAdmin == address(0)` AND `minter != address(0)` are independent locks; either alone is sufficient but both together make the "already set" condition trivially greppable. |
| **C-D12** | **Constructor validates `minterAdmin_ != address(0)`** with a `ZeroAddress()` revert. A zero minter admin permanently bricks emissions (the setter can never be called). Genesis block is NOT validated against `block.number` — the deployment script is responsible for passing a sane value, same discipline as Stage B's `AureumAuthorizer` accepting any multisig address without validating its type. Documented here so the Stage C-executing Claude doesn't add defensive validation that's out of scope. |
| **C-D13** | **`W_BLOCKS_PER_WEEK` is included in the library for parity with constitution §xxix**, even though no stage currently uses it. Zero orphan cost (one `constant` inlined at compile time); high parity value when future stages cross-reference the constitution's canonical table. |

---

## What is explicitly NOT in Stage C

- AuMT token — Stage I.
- Emission distributor (F-0 piecewise bootstrap, F-1 equal split, F-3 blend, F-7 full sequence) — Stage H.
- CCB engine (F-4 EMA, F-5 score, F-6 share, F-8 multiplier) — Stage F.
- Gauge registry — Stage G.
- Fee-routing hook — Stage D.
- Der Bodensee pool deployment — Stage D.
- Any pool deployments, any pool configs — Stage E onward.
- Governance contract — Stage K.
- Any mainnet deployment — Stage R.
- Wiring AuMM's minter to a real distributor — Stage H's deployment script.
- Calling `setMinter` — Stage H's deployment script.
- Testnet deployment — Stage P.
- ERC20Burnable / any user-facing burn — never (not a planned feature).

Stage C is "the time math library and the AuMM ERC-20 compile, pass unit + invariant tests, pass Slither, pass `forge lint`, and live in the right folders." That is all.

---

## Prerequisites check (do this before C0)

```bash
git status                    # must be clean on `main`
git log --oneline -1          # must match stage-b-complete tag commit b627a92
git tag | grep stage-b        # must show stage-b-complete
forge --version               # must be installed
forge build                   # must be green on Stage B baseline
source .env
forge test --fork-url $MAINNET_RPC_URL -vv  # all Stage B tests must pass
```

If anything here is not green, stop and fix it. Starting Stage C from a non-green baseline makes the C1 directory-move diff impossible to evaluate.

---

## C0 — Branch, scaffold notes, verify baseline (15 min)

```bash
git checkout main
git pull
git checkout -b stage-c
touch docs/STAGE_C_NOTES.md
```

Seed `docs/STAGE_C_NOTES.md` with this header and the thirteen planning-stage decisions from the table above:

```markdown
# Stage C Notes

Design decisions, grep-verified findings, and implementation notes made during Stage C.

Planning-stage decisions (C-D1 through C-D13) live in `STAGE_C_PLAN.md`. Implementation-stage decisions land here, numbered from C10 onward.

## Branch model

Same as Stage B per `STAGE_B_NOTES.md` "Branch model deviation" (2026-04-09): tag directly on main without a PR; `stage-c` branch on origin preserved as a snapshot marker. No PR-gated review for solo work.

## Open Stage C decisions

| ID | Decision |
|----|----------|

(populated as implementation surfaces questions)
```

Commit and push:

```bash
git add docs/STAGE_C_NOTES.md
git commit -m "C0: stage-c branch opened, STAGE_C_NOTES.md scaffolded"
git push -u origin stage-c
```

**Log C0** in the Completion Log at the bottom of this file (date, commit hash, "baseline green, branch opened").

---

## C1 — Directory reorganisation (45 min)

**Goal:** move every Stage B Solidity file from `src/` to `src/vault/`, update all referring paths, single clean commit with zero behavioural change.

### C1.1 — Move the files

```bash
mkdir -p src/vault
git mv src/AureumVaultFactory.sol src/vault/AureumVaultFactory.sol
git mv src/AureumProtocolFeeController.sol src/vault/AureumProtocolFeeController.sol
git mv src/AureumAuthorizer.sol src/vault/AureumAuthorizer.sol
```

### C1.2 — Update imports in moved files

For each moved file, check whether it imports any sibling Aureum file using a relative path. If any do, rewrite those imports to use the new path. Most likely candidates:

- `AureumProtocolFeeController.sol` and `AureumAuthorizer.sol` — pure leaves, unlikely to import siblings.

Grep to confirm:

```bash
grep -rn 'import' src/vault/
```

Every import line should resolve via remapped paths (`@balancer-labs/...`, `@openzeppelin/...`) or relative paths that still work (`./SiblingInSameFolder.sol`). If anything points at `src/` without going through a remapping, fix it.

### C1.3 — Update `script/DeployAureumVault.s.sol` imports

Open the file. Change every `import "src/Aureum*.sol"` (or `"../src/..."`) to `"src/vault/Aureum*.sol"` (or `"../src/vault/..."`). Grep to verify:

```bash
grep -n 'src/Aureum\|src/vault/Aureum' script/DeployAureumVault.s.sol
```

Only `src/vault/` paths should remain.

### C1.4 — Update test import paths

Two greps, belt-and-suspenders. The first catches `src/Aureum` prefix anywhere in a path (including `../../src/Aureum...`); the second catches any bare-name reference that might slip through if a file is imported by name only:

```bash
grep -rn 'src/Aureum' test/
grep -rnE 'Aureum(Vault|VaultFactory|ProtocolFeeController|Authorizer)\.sol' test/
```

For every match, rewrite to `src/vault/Aureum*.sol` (or the relative equivalent). Files expected to touch:

- `test/unit/AureumAuthorizer.t.sol`
- `test/unit/AureumProtocolFeeController.t.sol`
- `test/fork/DeployAureumVault.t.sol`

Verify no residual `src/Aureum` references remain:

```bash
grep -rn 'src/Aureum' .
```

Expected output: zero matches outside documentation. If `docs/STAGE_B_NOTES.md` or `README.md` reference the old paths, leave them — those are historical records. Only code / build-config paths change.

### C1.5 — Update `foundry.toml` lint-ignore paths

```bash
grep -n 'Aureum' foundry.toml
```

The Stage B3/B4 lint ignores reference `src/AureumVaultFactory.sol` and `src/AureumProtocolFeeController.sol`. Update both to `src/vault/AureumVaultFactory.sol` and `src/vault/AureumProtocolFeeController.sol`. If any other Aureum paths exist in `foundry.toml`, update them the same way.

### C1.6 — Update `README.md` repository layout section

Open `README.md`, find the directory-tree diagram in the "Repository layout" section. Replace:

```
src/
├── AureumVaultFactory.sol
├── AureumProtocolFeeController.sol
└── AureumAuthorizer.sol
```

with:

```
src/
├── vault/                    # Stage B
│   ├── AureumVaultFactory.sol
│   ├── AureumProtocolFeeController.sol
│   └── AureumAuthorizer.sol
├── lib/                      # Stage C
│   └── AureumTime.sol
└── token/                    # Stage C
    ├── AuMM.sol
    └── IAuMM.sol
```

### C1.7 — Verify build and tests are green

```bash
forge build
```

Expected: green. If anything fails, the directory move broke an import path — grep harder, fix, retry.

```bash
source .env
forge test --fork-url $MAINNET_RPC_URL -vv
```

Expected: same pass count as Stage B baseline. **Do not proceed to C2 until this is green.**

### C1.8 — Single commit

```bash
git add -A
git status                    # review diff; should be pure moves + path updates
git commit -m "C1: move Stage B contracts to src/vault/, update paths"
git push
```

The diff should be almost entirely `rename` operations plus path-string replacements in 3-5 non-Solidity files. Zero Solidity logic changes.

**Log C1** in the Completion Log.

---

## C2 — Read spec, dump block-math decisions into notes (30 min)

**Goal:** before writing a single line of `AureumTime.sol`, read the canonical sources end-to-end and record in `STAGE_C_NOTES.md` exactly which constants and formulas are being implemented.

### C2.1 — Read sources

Primary source is `aumm-specs.md` attached to project knowledge. Read in full:

- §ix in `04_tokenomics.md` — Token Design: AuMM. Supply rules, emission schedule table, emission distribution.
- §xxix in `10_constitution.md` — Immutable Parameters. Full list including the canonical time-constant table and derived time boundaries.
- F-0 in `11_formulas.md` — der Bodensee bootstrap emission decay. Piecewise boundaries at `MONTH_6_END_BLOCK` and `MONTH_10_END_BLOCK`.
- F-7 in `11_formulas.md` — Full Emission Sequence post-Year 1.

Also read in `FINDINGS.md`:

- OQ-3 — `BLOCKS_PER_MONTH = 219_000`.
- OQ-4 — `BLOCKS_PER_EPOCH = 100_800`.
- OQ-5 — `BLOCKS_PER_ERA = 10_512_000` plus the canonical time-constant table and the "block numbers are canonical" rule.
- OQ-5a — per-day EMA sampling (informational; EMA itself is Stage F, not C).

(If `aumm-site` is attached as a project knowledge source in a given session, the same content is in its originating files. `aumm-specs.md` is authoritative for Stage C.)

### C2.2 — Record constants in notes

Append to `STAGE_C_NOTES.md`:

```markdown
## C2 — Canonical time constants (from OQ-5 / §xxix)

| Constant | Value | Calendar alias (12 s/block) | First use |
|---|---|---|---|
| BLOCKS_PER_DAY | 7_200 | 1 day | F-4 EMA sampling (Stage F) |
| BLOCKS_PER_WEEK | 50_400 | 7 days | not currently used; included for §xxix parity |
| BLOCKS_PER_EPOCH | 100_800 | 14 days ("bi-weekly") | F-2 Incendiary duration (Stage L), F-8 CCB multiplier cadence (Stage F) |
| BLOCKS_PER_MONTH | 219_000 | ~30.4 days (1/12 year) | F-0 piecewise decay boundaries (Stage H) |
| BLOCKS_PER_QUARTER | 657_000 | ~91.25 days | general reference |
| BLOCKS_PER_YEAR | 2_628_000 | 365 days exact | F-3 transition endpoint, governance era boundary |
| BLOCKS_PER_ERA | 10_512_000 | 1_460 days (4 × 365) | halving interval (AuMM, this stage) |

Derived constants exposed as pure functions of a `genesisBlock` parameter:

- month6EndBlock(genesis)    = genesis + 6 * BLOCKS_PER_MONTH     // F-0 first piecewise boundary
- month10EndBlock(genesis)   = genesis + 10 * BLOCKS_PER_MONTH    // F-0 second piecewise boundary
- month13StartBlock(genesis) = genesis + 12 * BLOCKS_PER_MONTH + 1 // efficiency tournament activation (Stage G)
- year1EndBlock(genesis)     = genesis + BLOCKS_PER_YEAR          // F-3 transition endpoint
- firstHalvingBlock(genesis) = genesis + BLOCKS_PER_ERA           // Era 0 → Era 1
- nthHalvingBlock(genesis,n) = genesis + n * BLOCKS_PER_ERA       // Era n-1 → Era n

Note: year1EndBlock and month13StartBlock are adjacent blocks — year1End is block B, month13Start is block B+1. Both named separately because F-3 uses year1End and Stage G's efficiency tournament uses month13Start; different semantics, same boundary.
```

### C2.3 — Record AuMM emission schedule decisions

Append to `STAGE_C_NOTES.md`:

```markdown
## C2 — AuMM emission schedule (from §ix table)

| Era | Block range (from genesis) | Block emission rate (AuMM) | Wei per block (18 decimals) |
|---|---|---|---|
| 0 | [genesis, genesis + 10_512_000) | 1.00      | 1_000_000_000_000_000_000 |
| 1 | [... + 10_512_000, ... + 21_024_000) | 0.50   | 500_000_000_000_000_000 |
| 2 | [... + 21_024_000, ... + 31_536_000) | 0.25   | 250_000_000_000_000_000 |
| 3 | [... + 31_536_000, ... + 42_048_000) | 0.125  | 125_000_000_000_000_000 |
| 4 | [... + 42_048_000, ... + 52_560_000) | 0.0625 | 62_500_000_000_000_000 |
| 5 | [... + 52_560_000, ... + 63_072_000) | 0.03125| 31_250_000_000_000_000 |
| N >= 6 | ...                              | 1e18 >> N | right-shift until underflow to 0 |

Implementation:
    GENESIS_RATE = 1e18 (1 AuMM per block)
    eraIdx = (block - genesis) / BLOCKS_PER_ERA       // pre-genesis math handled separately
    blockEmissionRate(block) = GENESIS_RATE >> eraIdx  // natural integer-division halving

Pre-genesis behaviour: blockEmissionRate(block) returns 0 for any block < GENESIS_BLOCK.
Rationale: AuMM is not emitting before its own genesis, and the caller (Stage H) should never query pre-genesis blocks.

Overflow safety: eraIdx can in principle exceed 255 for block.number >> GENESIS_BLOCK, which would make >> undefined.
Clamp eraIdx to 255 as a defensive ceiling; at eraIdx = 60 the rate is already zero,
so clamping at 255 is purely defensive.

21M cap: MAX_SUPPLY = 21_000_000e18. Enforced at mint() regardless of what blockEmissionRate says —
this is the constitutional backstop.
```

### C2.4 — Commit notes

```bash
git add docs/STAGE_C_NOTES.md
git commit -m "C2: canonical time constants + AuMM emission schedule recorded in notes"
git push
```

**Log C2** in the Completion Log.

---

## C3 — Build `src/lib/AureumTime.sol` (1.5 hr)

**Goal:** implement the pure library with all constants + all named helpers, compile-clean, lint-clean.

### C3.1 — File skeleton

Create `src/lib/AureumTime.sol`. Pragma is `^0.8.26` — this is the first Aureum-authored Stage C file, and cursorrules rule 4 pins `^0.8.26` for Aureum-authored code:

```solidity
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/**
 * @title AureumTime
 * @notice Canonical block-number math for Aureum. Every calendar-time term in the
 *         protocol is an alias for a block count (FINDINGS.md OQ-5). Contracts
 *         only ever deal with block counts — calendar labels are for humans.
 * @dev Pure library, no state. All constants/functions internal; callers compile
 *      the math in via Solidity's library-internal-call inlining.
 */
library AureumTime {
    // constants
    // ...

    // index helpers
    // ...

    // boundary helpers
    // ...
}
```

### C3.2 — Fill in constants

All seven canonical constants. `internal constant` values are inlined at every call site by the compiler, so they're accessible from any file that imports the library (confirmed behaviour: Solidity docs on library internal calling convention):

```solidity
/// @notice 1 day at 12 s/block. OQ-5 / §xxix.
uint256 internal constant BLOCKS_PER_DAY      = 7_200;
/// @notice 7 days. §xxix parity only; no current consumer.
uint256 internal constant BLOCKS_PER_WEEK     = 50_400;
/// @notice Bi-weekly epoch. OQ-4 / §xxix. Used by F-2, F-8, F-10.
uint256 internal constant BLOCKS_PER_EPOCH    = 100_800;
/// @notice Protocol month (1/12 year). OQ-3 / §xxix. Used by F-0 boundaries.
uint256 internal constant BLOCKS_PER_MONTH    = 219_000;
/// @notice Protocol quarter. §xxix general reference.
uint256 internal constant BLOCKS_PER_QUARTER  = 657_000;
/// @notice Protocol year = 365 calendar days exact. §xxix. F-3 transition endpoint.
uint256 internal constant BLOCKS_PER_YEAR     = 2_628_000;
/// @notice Halving interval = 4 × BLOCKS_PER_YEAR. OQ-5 / §xxix.
uint256 internal constant BLOCKS_PER_ERA      = 10_512_000;
```

### C3.3 — Fill in index helpers

```solidity
/// @notice Zero-indexed month since genesis. Month 0 is [genesis, genesis + BLOCKS_PER_MONTH).
/// @dev Returns 0 for pre-genesis blocks (sentinel — caller decides whether to care).
function monthIndex(uint256 genesisBlock, uint256 blockNumber) internal pure returns (uint256) {
    if (blockNumber < genesisBlock) return 0;
    return (blockNumber - genesisBlock) / BLOCKS_PER_MONTH;
}

/// @notice Zero-indexed epoch since genesis.
function epochIndex(uint256 genesisBlock, uint256 blockNumber) internal pure returns (uint256) {
    if (blockNumber < genesisBlock) return 0;
    return (blockNumber - genesisBlock) / BLOCKS_PER_EPOCH;
}

/// @notice Zero-indexed era since genesis. Era 0 is [genesis, genesis + BLOCKS_PER_ERA).
function eraIndex(uint256 genesisBlock, uint256 blockNumber) internal pure returns (uint256) {
    if (blockNumber < genesisBlock) return 0;
    return (blockNumber - genesisBlock) / BLOCKS_PER_ERA;
}
```

### C3.4 — Fill in boundary helpers

```solidity
/// @notice End of Month 6. F-0 first piecewise boundary (80%→50%); Bodensee UI unhide.
function month6EndBlock(uint256 genesisBlock) internal pure returns (uint256) {
    return genesisBlock + 6 * BLOCKS_PER_MONTH;
}

/// @notice End of Month 10. F-0 second piecewise boundary (bootstrap permanently zero).
function month10EndBlock(uint256 genesisBlock) internal pure returns (uint256) {
    return genesisBlock + 10 * BLOCKS_PER_MONTH;
}

/// @notice First block of Month 13. Efficiency-tournament activation (Stage G).
/// @dev Equal to year1EndBlock(g) + 1 — both named because different consumers reference them.
function month13StartBlock(uint256 genesisBlock) internal pure returns (uint256) {
    return genesisBlock + 12 * BLOCKS_PER_MONTH + 1;
}

/// @notice End of Year 1. F-3 transition endpoint (α = 1).
function year1EndBlock(uint256 genesisBlock) internal pure returns (uint256) {
    return genesisBlock + BLOCKS_PER_YEAR;
}

/// @notice First halving block. Era 0 → Era 1.
function firstHalvingBlock(uint256 genesisBlock) internal pure returns (uint256) {
    return genesisBlock + BLOCKS_PER_ERA;
}

/// @notice Nth halving block. Era n-1 → Era n. nthHalvingBlock(g, 1) == firstHalvingBlock(g).
function nthHalvingBlock(uint256 genesisBlock, uint256 n) internal pure returns (uint256) {
    return genesisBlock + n * BLOCKS_PER_ERA;
}
```

Natspec on every function. Every function marked `pure`.

### C3.5 — Verify compile and lint

```bash
forge build
forge lint src/lib/
```

Expected: both green. If `forge lint` whines about `screaming-snake-case-immutable`, note that these are `constant` not `immutable` — the rule targets immutables specifically. If any lint warning surfaces, fix at source rather than adding suppressions (Stage C is Aureum-authored, no audit-inheritance-byte-identity justification for suppressions).

If `forge build` whines about "library has no body to deploy" — that's fine, internal-only libraries inline at callsites and don't deploy as separate runtime code.

### C3.6 — Commit

```bash
git add src/lib/AureumTime.sol
git commit -m "C3: src/lib/AureumTime.sol — canonical block-number math library"
git push
```

**Log C3** in the Completion Log.

---

## C4 — Unit + fuzz tests for `AureumTime` (1.5 hr)

**Goal:** test every constant, every helper, every boundary, across both named block inputs and fuzz ranges.

### C4.1 — Create test file

`test/unit/AureumTime.t.sol`:

```solidity
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

contract AureumTimeTest is Test {
    uint256 constant GENESIS = 20_000_000;  // arbitrary non-zero starting block

    // constant-value tests
    // index tests at boundaries
    // boundary-helper tests
    // fuzz tests
    // property tests
}
```

### C4.2 — Constant-value tests

One test per constant. Example:

```solidity
function test_blocksPerMonth_equals_219000() public pure {
    assertEq(AureumTime.BLOCKS_PER_MONTH, 219_000);
}
```

Do this for all seven constants (`BLOCKS_PER_DAY`, `BLOCKS_PER_WEEK`, `BLOCKS_PER_EPOCH`, `BLOCKS_PER_MONTH`, `BLOCKS_PER_QUARTER`, `BLOCKS_PER_YEAR`, `BLOCKS_PER_ERA`).

### C4.3 — Index helper boundary tests

For each of `monthIndex`, `epochIndex`, `eraIndex`, test:

- Pre-genesis block returns 0
- Genesis block returns 0 (start of index 0)
- Last block of index 0 returns 0
- First block of index 1 returns 1
- Mid-range sample returns expected index

### C4.4 — Boundary helper tests

Named test per helper, including the new `month13StartBlock` and `nthHalvingBlock`:

- `test_month6EndBlock_equalsGenesisPlus1_314_000`
- `test_month10EndBlock_equalsGenesisPlus2_190_000`
- `test_month13StartBlock_equalsYear1EndBlockPlus1`
- `test_year1EndBlock_equalsGenesisPlus2_628_000`
- `test_firstHalvingBlock_equalsGenesisPlus10_512_000`
- `test_nthHalvingBlock_n1_equalsFirstHalvingBlock`
- `test_nthHalvingBlock_n5_isFiveErasIn`

### C4.5 — Fuzz + property tests

```solidity
function testFuzz_monthIndex_nonDecreasing(uint256 delta) public pure {
    vm.assume(delta < type(uint128).max);
    uint256 b1 = GENESIS + delta;
    uint256 b2 = b1 + 1;
    assertLe(AureumTime.monthIndex(GENESIS, b1), AureumTime.monthIndex(GENESIS, b2));
}

// Repeat the monotonic-non-decreasing fuzz for epochIndex and eraIndex.

function testFuzz_eraIndex_matchesFloorDivision(uint256 delta) public pure {
    vm.assume(delta < 20 * AureumTime.BLOCKS_PER_ERA);
    uint256 expected = delta / AureumTime.BLOCKS_PER_ERA;
    assertEq(AureumTime.eraIndex(GENESIS, GENESIS + delta), expected);
}
```

Default `fuzz = { runs = 1024 }` from Stage B's `foundry.toml` is adequate for pure-arithmetic properties.

### C4.6 — Run and commit

```bash
forge test --match-path test/unit/AureumTime.t.sol -vv
```

Expected: all named + fuzz tests pass.

```bash
git add test/unit/AureumTime.t.sol
git commit -m "C4: test/unit/AureumTime.t.sol — unit + fuzz coverage"
git push
```

**Log C4** in the Completion Log.

---

## C5 — Design AuMM: constructor, minter flow, halving math (1 hr)

**Goal:** lock in the AuMM contract's surface and internal arithmetic in `STAGE_C_NOTES.md` before writing Solidity.

### C5.1 — Constructor signature

Append to `STAGE_C_NOTES.md`:

```markdown
## C5 — AuMM design

### Constructor

constructor(
    uint256 genesisBlock_,
    address minterAdmin_
)
    ERC20("Aureum Market Maker", "AuMM")
{
    if (minterAdmin_ == address(0)) revert ZeroAddress();  // per C-D12
    GENESIS_BLOCK = genesisBlock_;
    _minterAdmin = minterAdmin_;  // address authorised to call setMinter() exactly once
}

- genesisBlock_: can be the future block at which AuMM emission begins. Typically passed in
  by the Stage R deployment script at mainnet launch. For Stage C unit tests and Stage H
  fork tests, any non-zero block number works. Not validated against block.number — the
  deployment script is responsible for sanity (per C-D12).
- minterAdmin_: the one-shot setter principal. Typically the deployer EOA or the Stage K
  governance multisig. After setMinter() is called, this address has no further authority.
  Zero address reverts at construction (permanent brick prevention, per C-D12).
- Constructor does not mint any tokens. No pre-mine. No treasury allocation.

### Storage

address public  minter;         // zero until setMinter called; set-once via one-shot setter
address private _minterAdmin;   // zero'd out after setMinter called (self-destruct the authority)

### State machine

State 0 (post-deploy):    minter == address(0), _minterAdmin != address(0). mint() reverts.
State 1 (post-setMinter): minter == distributorAddress, _minterAdmin == address(0).
                          mint() gated by minter. setMinter() reverts on either check.

Transition 0 → 1: setMinter(address), callable only by _minterAdmin when minter == address(0).

### setMinter flow

function setMinter(address newMinter) external {
    if (msg.sender != _minterAdmin) revert NotMinterAdmin();
    if (minter != address(0))       revert MinterAlreadySet();
    if (newMinter == address(0))    revert ZeroAddress();

    minter = newMinter;
    _minterAdmin = address(0);   // self-lock; no second caller can ever reach this function
    emit MinterSet(newMinter);
}

Two-flag locking (per C-D11): both `minter != address(0)` and `_minterAdmin == address(0)`
independently prevent a second call. Either alone is sufficient; together they make the
"already set" condition trivially greppable and defence-in-depth.

### mint flow

function mint(address to, uint256 amount) external {
    if (msg.sender != minter)                revert NotMinter();
    if (totalSupply() + amount > MAX_SUPPLY) revert SupplyCapExceeded();
    _mint(to, amount);  // emits Transfer(address(0), to, amount) via OZ ERC20
}

No _update override. The cap check lives in mint(), not in the _update hook — avoids
accidentally blocking transfers in any future extension.

### blockEmissionRate

function blockEmissionRate(uint256 blockNumber) external view returns (uint256) {
    if (blockNumber < GENESIS_BLOCK) return 0;
    uint256 era = (blockNumber - GENESIS_BLOCK) / AureumTime.BLOCKS_PER_ERA;
    if (era >= 256) return 0;   // defensive; rate is zero long before this
    return GENESIS_RATE >> era;
}

### Constants

uint256 public constant MAX_SUPPLY   = 21_000_000e18;
uint256 public constant GENESIS_RATE = 1e18;   // 1 AuMM per block in Era 0

### Errors

error NotMinterAdmin();
error NotMinter();
error MinterAlreadySet();
error ZeroAddress();
error SupplyCapExceeded();

### Events

event MinterSet(address indexed minter);
// Transfer is inherited from ERC20; mint() auto-emits Transfer(address(0), to, amount).
```

### C5.2 — IAuMM interface design

Append to `STAGE_C_NOTES.md`:

```markdown
### IAuMM.sol

interface IAuMM is IERC20 {
    // immutable / constant getters
    function GENESIS_BLOCK() external view returns (uint256);
    function MAX_SUPPLY() external view returns (uint256);
    function GENESIS_RATE() external view returns (uint256);

    // emission schedule
    function blockEmissionRate(uint256 blockNumber) external view returns (uint256);

    // minter state
    function minter() external view returns (address);   // matches auto-generated getter for `address public minter`

    // state-changing
    function mint(address to, uint256 amount) external;
    function setMinter(address newMinter) external;

    // events (declared for interface parity; implementations inherit from ERC20 + declare MinterSet)
    event MinterSet(address indexed minter);
}

Purpose: Stage H's distributor imports IAuMM instead of the concrete AuMM contract. Matches the
Stage B pattern where AureumVaultFactory took IProtocolFeeController.
```

### C5.3 — Commit notes

```bash
git add docs/STAGE_C_NOTES.md
git commit -m "C5: AuMM design recorded in notes (constructor, minter flow, halving math, IAuMM)"
git push
```

**Log C5** in the Completion Log.

---

## C6 — Build `src/token/AuMM.sol` + `src/token/IAuMM.sol` (2 hr)

**Goal:** implement per the C5 design. Single pass, compile-clean, lint-clean, no short-cuts.

### C6.1 — Create `src/token/IAuMM.sol`

```solidity
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IAuMM
/// @notice Interface for the AuMM ERC-20. Consumed by Stage H's emission distributor
///         and by any off-chain tool that needs a stable shape to compile against.
interface IAuMM is IERC20 {
    // ...per C5.2 design...
}
```

Natspec on every function.

### C6.2 — Create `src/token/AuMM.sol`

```solidity
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAuMM} from "src/token/IAuMM.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

/**
 * @title AuMM — Aureum Market Maker
 * @notice 21,000,000-cap ERC-20 with Bitcoin-style geometric halving.
 *         One-shot minter authorisation: constructor sets a minter admin,
 *         who calls setMinter() exactly once to hand off to the Stage H
 *         emission distributor. After that call, no entity has setter authority.
 * @dev Immutable schedule — blockEmissionRate is pure-view, computable without state.
 *      Does NOT extend ERC20Burnable — cap is a ceiling, not an inflation limit post-burn.
 */
contract AuMM is ERC20, IAuMM {
    // ...full implementation per C5 design...
}
```

Natspec on all externals. Custom errors. No revert strings. No admin roles. No upgradability path. No `ERC20Burnable` import, no burn surface, no `_update` override.

### C6.3 — Build and lint

```bash
forge build
forge lint src/token/
```

Expected: both green, two new compilation units compile, no lint findings. If anything errors, grep, fix, retry. Do not move to C7 until both are green.

### C6.4 — Commit

```bash
git add src/token/AuMM.sol src/token/IAuMM.sol
git commit -m "C6: src/token/AuMM.sol + IAuMM.sol — 21M-cap ERC-20 with halving schedule"
git push
```

**Log C6** in the Completion Log.

---

## C7 — Unit + invariant tests for AuMM (2 hr)

**Goal:** prove the cap, the minter gate, the one-shot lock, and the halving schedule. Cover enough surface that C-D7 (era ≥ 6 underflow) and C-D2 (one-shot setter) are locked in by machine-checkable tests.

### C7.1 — Create `test/unit/AuMM.t.sol`

```solidity
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AuMM} from "src/token/AuMM.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

contract AuMMTest is Test {
    AuMM aumm;
    address minterAdmin = address(0xA1);
    address minter      = address(0xB2);
    uint256 constant GENESIS = 20_000_000;

    // ERC20 Transfer event, redeclared for vm.expectEmit
    event Transfer(address indexed from, address indexed to, uint256 value);
    event MinterSet(address indexed minter);

    function setUp() public {
        aumm = new AuMM(GENESIS, minterAdmin);
    }

    // tests follow
}
```

### C7.2 — Named tests

Minimum named test list:

- `test_constructor_setsGenesis`
- `test_constructor_setsMinterAdmin`
- `test_constructor_doesNotMint`
- `test_constructor_revertsOnZeroMinterAdmin`  *(per C-D12)*
- `test_setMinter_onlyMinterAdmin_canCall`
- `test_setMinter_revertsIfMinterAlreadySet`
- `test_setMinter_revertsOnZeroAddress`
- `test_setMinter_selfLocksAdmin`
- `test_setMinter_emitsMinterSetEvent`
- `test_mint_revertsBeforeMinterSet`
- `test_mint_onlyMinter_canCall`
- `test_mint_revertsIfExceedsCap`
- `test_mint_succeedsUpToCap`
- `test_mint_emitsTransferEvent`  *(vm.expectEmit Transfer(address(0), to, amount))*
- `test_blockEmissionRate_preGenesis_isZero`
- `test_blockEmissionRate_atGenesis_isGenesisRate`
- `test_blockEmissionRate_atFirstHalving_isHalfGenesisRate`
- `test_blockEmissionRate_era2_isQuarter`
- `test_blockEmissionRate_era5_is_1_over_32`
- `test_blockEmissionRate_era10_is_very_small_but_positive`
- `test_blockEmissionRate_era60_plus_isZero`
- `test_blockEmissionRate_nonIncreasing_acrossBoundary`  *(covers monotonicity as a named property test; pairs of specific blocks, not an invariant)*
- `test_maxSupply_is_21M`
- `test_genesisRate_is_1e18`

### C7.3 — Invariant test + handler

The handler **must inherit `Test`** to access `bound()` (which lives in `StdUtils`, pulled in by `Test`). Without `is Test`, the handler fails to compile with a missing-symbol error.

```solidity
contract AuMMInvariantTest is Test {
    AuMM aumm;
    AuMMHandler handler;
    uint256 constant GENESIS = 20_000_000;

    function setUp() public {
        aumm = new AuMM(GENESIS, address(this));
        handler = new AuMMHandler(aumm);
        aumm.setMinter(address(handler));

        // Pin the invariant fuzzer to the handler — without this, Foundry targets
        // every contract deployed in setUp (including aumm itself), which dilutes
        // real handler calls with wasted reverts.
        targetContract(address(handler));
    }

    function invariant_totalSupply_neverExceedsCap() public view {
        assertLe(aumm.totalSupply(), aumm.MAX_SUPPLY());
    }

    function invariant_mint_revertsFromNonMinter() public {
        // If anyone except the handler could mint, the cap invariant would eventually
        // break. This invariant checks the inverse — any direct mint attempt from
        // this test contract (not the handler) must revert.
        vm.expectRevert(AuMM.NotMinter.selector);
        aumm.mint(address(0xBEEF), 1);
    }
}

/// @dev AuMMHandler MUST inherit Test to access bound() — bound() lives in StdUtils
///      which Test pulls in. A bare contract without `is Test` fails to compile.
contract AuMMHandler is Test {
    AuMM public aumm;
    constructor(AuMM a) { aumm = a; }

    function mint(address to, uint256 amount) external {
        // Never mint more than remaining cap headroom — lets invariant runs continue
        // past the point where totalSupply approaches MAX_SUPPLY.
        uint256 remaining = aumm.MAX_SUPPLY() - aumm.totalSupply();
        if (remaining == 0) return;
        amount = bound(amount, 1, remaining);
        if (to == address(0)) to = address(0x1234);
        aumm.mint(to, amount);
    }
}
```

Note: `invariant_blockEmissionRate_monotonicNonIncreasing` is deliberately NOT an invariant — monotonicity of a pure view function doesn't depend on handler state, so it's covered by the named test `test_blockEmissionRate_nonIncreasing_acrossBoundary` in C7.2.

Default invariant run config is inherited from Stage B's `foundry.toml`: `invariant = { runs = 256, depth = 128, fail_on_revert = false }`.

### C7.4 — Fuzz tests

```solidity
function testFuzz_blockEmissionRate_eraIndexCorrect(uint64 blockOffset) public view {
    vm.assume(blockOffset < 50 * AureumTime.BLOCKS_PER_ERA);
    uint256 blk = GENESIS + uint256(blockOffset);
    uint256 era = uint256(blockOffset) / AureumTime.BLOCKS_PER_ERA;
    uint256 expected = era >= 256 ? 0 : aumm.GENESIS_RATE() >> era;
    assertEq(aumm.blockEmissionRate(blk), expected);
}

function testFuzz_mint_respectsCap(uint256 amount) public {
    aumm.setMinter(address(this));
    amount = bound(amount, 1, aumm.MAX_SUPPLY() * 2);
    if (amount > aumm.MAX_SUPPLY()) {
        vm.expectRevert(AuMM.SupplyCapExceeded.selector);
        aumm.mint(address(0xBEEF), amount);
    } else {
        aumm.mint(address(0xBEEF), amount);
        assertEq(aumm.totalSupply(), amount);
    }
}
```

Note: `testFuzz_mint_respectsCap` calls `setMinter` at the top of the test, which is fine because the `AuMMTest` contract deploys a fresh AuMM per test via `setUp()` — the minter hand-off happens in-test. This is deliberately separate from the invariant-test contract which pre-binds the handler in its own `setUp()`.

### C7.5 — Run and commit

```bash
forge test --match-path test/unit/AuMM.t.sol -vv
```

Expected: all named + fuzz + invariant tests pass. Invariant run takes ~10-15 s at default config.

```bash
git add test/unit/AuMM.t.sol
git commit -m "C7: test/unit/AuMM.t.sol — cap, minter, halving, invariants"
git push
```

**Log C7** in the Completion Log.

---

## C8 — Slither triage gate (1 hr)

**Goal:** same B6-style discipline. Run Slither across `src/`, triage findings, suppress inline with site-local rationale or accept and document in `STAGE_C_NOTES.md`.

### C8.1 — Activate virtualenv and run

```bash
source .venv/bin/activate
slither --version   # should be 0.11.4 from Stage B
slither . --filter-paths "lib|test"
```

Capture output. Stage B triaged 32 findings across 11 detectors against the vault-substrate contracts. Stage C adds ~400 LOC of pure-logic code — expected count is much lower, likely 0-10 findings, most of which will be informational-severity naming-convention or immutable-style notes.

### C8.2 — Triage each finding

For each finding, decide:

- **Genuine bug?** Fix. (Unlikely — C3/C6 were reviewed at write-time.)
- **False positive / informational?** Add an inline suppression comment with site-local rationale. Example format from Stage B:

  ```solidity
  // slither-disable-next-line naming-convention
  // Aureum-wide naming: immutable set at construction, uppercase-snake_case
  uint256 public immutable GENESIS_BLOCK;
  ```

- **Unsuppressable parser bug?** Document in `STAGE_C_NOTES.md` as an accepted residual, mirroring how B6 handled the `unindexed-event-address` bug in Slither 0.11.4.

Note: Stage C files are Aureum-authored, NOT forked-from-upstream. The audit-inheritance-byte-identity rationale that justified many of Stage B's suppressions doesn't apply here. Prefer fixing at source over suppressing.

### C8.3 — Verify clean

```bash
slither . --filter-paths "lib|test"
```

Expected result: either zero findings, or only accepted residuals that are pre-documented in notes. Record the final count and any residuals in `STAGE_C_NOTES.md` under a `## C8 — Slither triage` heading.

### C8.4 — Commit

```bash
git add -A    # suppressions are inline source comments + notes updates
git commit -m "C8: Slither findings triaged (or suppressed with rationale)"
git push
```

**Log C8** in the Completion Log.

---

## C9 — Tag and update cross-doc completion logs (10 min)

### C9.1 — Merge to main (or direct tag per Stage B branch-model deviation)

Per `STAGE_B_NOTES.md` "Branch model deviation" (2026-04-09): Stage B adopted the pattern of tagging directly on `main` without a PR. Stage C continues that pattern (seeded in C0's notes scaffold).

```bash
git checkout main
git pull
git merge --ff-only stage-c     # fast-forward only; fails if main has moved
git push origin main
git tag stage-c-complete
git push origin stage-c-complete
```

If `--ff-only` refuses (because something else landed on `main` in parallel), stop and reconcile before tagging. Options:

- `git rebase origin/main` on the `stage-c` branch, then retry the fast-forward merge.
- If the parallel commit is your own unrelated work, consider whether it should be part of Stage C.

The tag must point at a known-clean Stage C tip.

### C9.2 — Update Completion Log in this file

Fill in the final row of the table at the bottom of this file with the tagged commit hash and date.

### C9.3 — Update Completion Log in `STAGES_OVERVIEW.md`

Open `docs/STAGES_OVERVIEW.md`, find the master Completion Log table near the bottom, fill in the Stage C row:

| Stage | Tag | Date | Commit | Notes |
|---|---|---|---|---|
| C | `stage-c-complete` | YYYY-MM-DD | `<hash>` | AureumTime lib + AuMM token, directory reorg to `src/vault/`, `src/lib/`, `src/token/` |

```bash
git add docs/STAGE_C_PLAN.md docs/STAGES_OVERVIEW.md
git commit -m "C9: log stage-c-complete in plan + overview"
git push
```

**Log C9** in the Completion Log.

---

## Four things that could go wrong and how to recover

**Directory-move breaks an import that only shows up at test time.** The C1 grep should catch all `src/Aureum` references, but an edge case is a `forge script` invocation that uses a path argument. If `forge test --fork-url $MAINNET_RPC_URL` passes but a subsequent `forge script` fails, grep the scripts folder with wider net (`grep -rn 'Aureum' script/`) and fix any stragglers.

**OpenZeppelin ERC20 version mismatch on `_update`.** OpenZeppelin v5 changed `_beforeTokenTransfer` / `_afterTokenTransfer` into a unified `_update` hook. Stage A installed `openzeppelin-contracts v5.6.1`, so `_update` is the hook AuMM *would* override if it needed any mint/burn instrumentation. In the C6 design it doesn't — the cap check lives in the `mint` external function, not in `_update`, so this is a non-issue unless the implementation drifts. If a compile error surfaces about missing hook signatures, the answer is "AuMM does not override `_update`; the cap check is in `mint`." Do not add an `_update` override just because the compiler suggests it.

**Slither hangs or crashes on the new files.** Slither 0.11.4 has a known parser bug on certain event signatures (`STAGE_B_NOTES.md` B6 triage notes). If Slither hangs, try `--filter-paths "lib|test|src/vault"` first to isolate the new Stage C files, then run full after. If it crashes, upgrade Slither and re-triage — or, if the crash is on an AuMM-specific construct, simplify the construct rather than silencing the analyser.

**Main has moved between `git checkout main; git pull` and `git merge --ff-only stage-c` at C9.1.** Unusual for solo work but possible if an unrelated hotfix landed. Recovery: `git checkout stage-c && git rebase origin/main`, verify `forge build` and all tests still green, then retry the fast-forward merge. Do not merge-commit — the completion log linearity depends on a clean fast-forward.

---

## Files Stage C produces

```
aumm-deploy/
├── docs/
│   ├── STAGE_C_PLAN.md           — this file (new)
│   └── STAGE_C_NOTES.md          — living design-decision log (new)
├── src/
│   ├── vault/                    — Stage B contracts, moved here
│   │   ├── AureumVaultFactory.sol
│   │   ├── AureumProtocolFeeController.sol
│   │   └── AureumAuthorizer.sol
│   ├── lib/
│   │   └── AureumTime.sol        — block-number math library (new)
│   └── token/
│       ├── AuMM.sol              — ERC-20 with 21M cap + halving (new)
│       └── IAuMM.sol             — interface (new)
└── test/
    └── unit/
        ├── AureumTime.t.sol      — unit + fuzz + properties (new)
        └── AuMM.t.sol            — unit + fuzz + invariants (new)
```

Plus path updates in `foundry.toml`, `script/DeployAureumVault.s.sol`, `README.md`, and existing `test/` files.

---

## Completion Log

Fill this in as you progress.

| Date | Step | Status | Commit | Notes |
|---|---|---|---|---|
| 2026-04-16 | C0 — branch + notes scaffold | ✅ | `15e7b29` | stage-c branched from main; `docs/STAGE_C_NOTES.md` scaffolded with C-D1..C-D13 planning codes; branch-model deviation noted (direct-tag-on-main, matching Stage B pattern) |
| 2026-04-16 | C1 — directory reorg to `src/vault/` | ✅ | `9cb3d8e` | `git mv` of the four Stage B contracts (`AureumVault.sol`, `AureumVaultFactory.sol`, `AureumProtocolFeeController.sol`, `AureumAuthorizer.sol`) into `src/vault/`; path updates across `foundry.toml`, `script/DeployAureumVault.s.sol`, `test/`, README follow-up at `c4aa836`; `forge build` green, Stage B fork test still green against mainnet; C12 ghost-file finding logged |
| 2026-04-17 | C2 — spec read + constants recorded in notes | ✅ | `5615487` | canonical time constants (`BLOCKS_PER_DAY = 7_200` through `BLOCKS_PER_ERA = 10_512_000`) and AuMM emission schedule table recorded in `STAGE_C_NOTES.md`; cross-referenced to FINDINGS OQ-3/OQ-4/OQ-5 |
| 2026-04-17 | C3 — `src/lib/AureumTime.sol` | ✅ | `fce8cce` | canonical block-number math library; constants + `monthIndex` / `epochIndex` / `eraIndex` + named boundary helpers; pure library, no state; `forge build` green |
| 2026-04-17 | C4 — `test/unit/AureumTime.t.sol` | ✅ | `d3979b7` | unit + fuzz coverage, 33/33 green; no separate log-completion commit (see C13 in `STAGE_C_NOTES.md` re: C4.6b log-completion drift; backfilled today as part of the C6 log-update commit) |
| 2026-04-17 | C5 — AuMM design in notes | ✅ | `d6099b2` | constructor signature, two-flag minter state machine, `setMinter` / `mint` flows, `blockEmissionRate` math, constants, errors, events, IAuMM interface design all recorded in `STAGE_C_NOTES.md`; plan-verbatim commit message |
| 2026-04-18 | C6 — `src/token/AuMM.sol` + `IAuMM.sol` | ✅ | `6dd092a` | C6.1 interface at `751f699`; C6.2 contract at `6dd092a` (131 lines, 5 em-dashes, SHA `f81ef4de...`); immutable GENESIS_BLOCK, inherit MinterSet from IAuMM (no redeclare), `ERC20, IAuMM` linearisation order, three load-bearing `@dev` blocks (C-D7 cap-in-mint, C-D11 two-flag lock, pure-function property). C6.3 `forge build` green across 115 files, `forge clean && forge lint src/token/` zero findings. Commit chain also includes `f8d6076` (add CLAUDE.md) and `fdaa07f` (revise CLAUDE.md §6 §8 §9 §11 for §8e Cursor-executor pattern — activated from C7 onward) |
| 2026-04-18 | C7 — `test/unit/AuMM.t.sol` | ✅ | `91c0bb5` | Plan C7.2–C7.4: constructor / `setMinter` / `mint` / `blockEmissionRate` / era-boundary coverage; `AuMMInvariantTest` + handler; 28/28 green (2 invariants × 256 runs). Doc lead-ins `60ad451` (Completion Log + §11→C7), `22f85b7` (§8e escalation); umbrella test commit `91c0bb5` |
|  | C8 — Slither triage |  |  |  |
|  | C9 — `stage-c-complete` tag pushed |  |  |  |

When the last row is filled, Stage C is done. Stage D (fee-routing hook + der Bodensee) gets its own plan file.
