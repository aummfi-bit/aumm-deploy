# Stage C Notes

Design decisions, grep-verified findings, and implementation notes made during Stage C.

Planning-stage decisions (C-D1 through C-D13) live in `STAGE_C_PLAN.md`. Implementation-stage decisions land here, numbered from C10 onward.

## Branch model

Same as Stage B per `STAGE_B_NOTES.md` "Branch model deviation" (2026-04-09): tag directly on main without a PR; `stage-c` branch on origin preserved as a snapshot marker. No PR-gated review for solo work.

## Open Stage C decisions

| ID | Decision |
|----|----------|
| **C10** | **Baseline deviation from plan's recorded tip.** `STAGE_C_PLAN.md` prerequisites section says `git log --oneline -1` must match `b627a92`. At Stage C kickoff on 2026-04-16, `main`'s actual tip was `6a1be15` — three commits past `b627a92`: `96d1d1c` (B7 Completion Log fill, 1 line), `42543fd` (docs upload of root-level `STAGE_C_PLAN.md` via GitHub web UI), `324a4ed` (docs upload of `docs/STAGE_C_PLAN.md` via GitHub web UI), then `6a1be15` (housekeeping: removed the stray root-level duplicate). All four are docs-only, zero Solidity/config/test changes. `stage-b-complete` tag unchanged at `b627a92`. Stage B baseline therefore remained correctly green; Stage C branches from `6a1be15`. |
| **C11** | **Prerequisites check invocation corrected post hoc.** `STAGE_C_PLAN.md` line 114 reads `forge test --fork-url $MAINNET_RPC_URL -vv` as a single invocation. On forge 1.5.1-stable against Alchemy mainnet, that one-liner routes the local-only `AureumProtocolFeeController` handler-based invariant runs through RPC, inflating wall time from ~14s (local, no RPC) to 2+ minutes. Split invocation reproduces Stage B timings: `forge test --no-match-path 'test/fork/**' -vv` for local unit tests (~14s, 28 tests), then `forge test --match-path 'test/fork/**' --fork-url $MAINNET_RPC_URL -vv` for fork tests (~3s, 3 tests). Total 31 tests passed, 0 failed at Stage C kickoff. Carry this split-invocation pattern into Stage D-onward prerequisites checks. The plan file itself is not edited mid-stage; this note serves as the correction of record. |
| **C12** | **STAGE_C_PLAN.md inaccurately lists `src/AureumVault.sol` as a Stage B artifact to move.** `git ls-tree -r main \| grep '^src/'` at Stage C kickoff returned three files: `AureumAuthorizer.sol`, `AureumProtocolFeeController.sol`, `AureumVaultFactory.sol`. No `AureumVault.sol` has ever existed in this repo (`git log --all --oneline -- src/AureumVault.sol` empty). The error appears in three places in the plan: scope (line 42), C1.1 `git mv` list (line 171), and "Files Stage C produces" block (line 1113). Root cause: `AureumVault.sol` is the *Balancer* vault in `lib/balancer-v3-monorepo/pkg/vault/contracts/Vault.sol`, which is byte-identical-deployed-unforked per cursorrules rule 1 — the plan's author appears to have conflated the Balancer vault with a nonexistent Aureum fork of it. Resolution: C1 moves three files, not four. The three ghost-file references in STAGE_C_PLAN.md (line 42 scope list, line 171 git mv block, line 1113 'Files Stage C produces' tree) are corrected in-place in the C1 work commit. README.md repo layout is updated in C1.6 to list three. This note documents the plan-authoring error; the plan itself is also edited to prevent future readers from tripping on the same ghost. Also: `STAGES_OVERVIEW.md`'s Scope section says "Stage B built the substrate — forked `AureumVault.sol` with 22-line authorizer redirect" — that phrase is equally wrong (the 22-line authorizer redirect is in `AureumVaultFactory.sol`) but the overview fix is deferred out of Stage C scope. |

(populated further as implementation surfaces questions)

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
