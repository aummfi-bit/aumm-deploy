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
| **C13** | **C4.6b log-completion commit landed with non-plan-conformant message.** **Commit:** `5f336fe` on `stage-c`, pushed 2026-04-17. **Plan convention** (plan line 1038 and mirror patterns at C0/C1/C2/C3): commit message format is `"C<N>: log completion in Stage C plan"`. **Actual message landed:** `"log-completion: Stage C plan — C4 AureumTime.t.sol row"`. **Cause:** Cursor's agent loop performed the file edit, `git add`, `git commit`, and `git push` autonomously during the C4.6b direction. The commit's own message template did not match the plan's template. The subsequent manual `git add` / `git commit` directed in chat was a no-op (Cursor had already staged, committed, and pushed — working tree was clean). **Commit content:** correct. The C4 row in STAGE_C_PLAN.md was filled with the content directed in chat (long-form version), matching `d3979b7` as the referenced C4 work commit. No row-content drift. **Resolution:** history not rewritten — `5f336fe` is already on origin, and amend-then-force-push would rewrite shared history for cosmetic cleanup only. Message drift is documented here instead of erased. Future log-completion commits (C5 through C9) should go through the terminal so their output routes through the chat verification loop, per grep discipline. Cursor's autonomous git operations are to be suppressed for the remainder of Stage C. |
| **C14** | **Cursor agent-loop executed C5 autonomously without per-action directing.** During the C13 documentation turn (2026-04-17), Cursor's agent loop — configured at the time with Auto-Run Mode = `Auto-Run in Sandbox` and `cd`/`git status`/`git add`/`git commit`/`git push`/`git pull` in the Command Allowlist — performed the following without corresponding directing from the chat session: (1) appended the C13 row to this table, (2) appended the complete `## C5 — AuMM design` section (lines 72-186) copying plan C5.1 + C5.2 templates byte-verbatim, (3) committed as `d6099b2` with plan-verbatim C5.3 message, (4) appended the C5 Completion Log row to `STAGE_C_PLAN.md`, (5) committed as `5940b74` with plan-verbatim log-completion message, (6) pushed both to `origin/stage-c`. **Content verification:** C5 notes section verified byte-for-byte identical to plan templates; both commit messages verified plan-conformant; no design drift, no content loss. **Violation is procedural, not material** — grep discipline requires one-at-a-time directing + verification, which this sequence bypassed even though the outcome is correct. **Lockdown enacted 2026-04-17 before any C6 work:** Auto-Run Mode → `Ask Every Time`, full Command Allowlist cleared, Browser / MCP / File-Deletion / External-File Protection toggles all enabled. Directing pattern for C6 onward: every direction explicitly states "Cursor: edit file and save only; do not stage/commit/push/forge/test — Sagix runs these in the terminal". Cursor treated as text-editor-only for remainder of Stage C. |
| **C15** | **Slither `slither-disable-next-line` directive requires immediately-preceding position.** During C8.2 triage on `stage-c` post-C7 (`d5db5cf`), inline suppression of `naming-convention` findings on AuMM's UPPER_SNAKE_CASE constants/immutables initially failed when the directive sat above a rationale comment (i.e., with one `// <rationale>` line between the directive and the target declaration). Swapping to `// <rationale>` first, then `// slither-disable-next-line naming-convention` immediately above the declaration, suppressed all 4 findings. `STAGE_C_PLAN.md` C8.2's worked example has them in the failing order — carry the corrected format (rationale above directive, directive immediately above declaration) into Stage D onward. Unrelated: the `naming-convention` detector in Slither 0.11.4 does NOT share the `unindexed-event-address` parser bug (B6 / C8 residual); it respects inline disable when placement is correct. |

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

## C8 — Slither triage
Run: `slither . --filter-paths "lib|test"` with Slither 0.11.4 (Stage B pin), 100 detectors, 85 contracts analyzed. Initial run at `stage-c` post-C7 (`d5db5cf`) returned 5 findings across 2 detectors.
### Findings and dispositions
| # | Detector | Site | Disposition |
|---|---|---|---|
| 1 | naming-convention | `src/token/AuMM.sol:37` — `GENESIS_BLOCK` immutable | Inline-suppressed |
| 2 | naming-convention | `src/token/IAuMM.sol:24` — `GENESIS_BLOCK()` getter | Inline-suppressed |
| 3 | naming-convention | `src/token/IAuMM.sol:30` — `MAX_SUPPLY()` getter | Inline-suppressed |
| 4 | naming-convention | `src/token/IAuMM.sol:36` — `GENESIS_RATE()` getter | Inline-suppressed |
| 5 | unindexed-event-address | `src/vault/AureumVaultFactory.sol:54` — `VaultCreated(address)` | Accepted residual |
**Findings 1–4 (naming-convention).** Aureum-wide naming for constants and immutables is UPPER_SNAKE_CASE (Bitcoin-and-Balancer-aligned). Interface getters mirror those names exactly — forced by the public-constant ABI pattern, where Solidity auto-generates the getter at the same case as the state variable. Each finding suppressed with a two-line comment block directly above the declaration: `// <rationale>` line, then `// slither-disable-next-line naming-convention` line. See C15 re: directive ordering; the plan's C8.2 example had the directive above the rationale, which does not suppress.
**Finding 5 (unindexed-event-address).** `VaultCreated(address)` in `AureumVaultFactory.sol` is carried verbatim from `lib/balancer-v3-monorepo/pkg/vault/contracts/VaultFactory.sol`; the Option-F2 ~5-line-diff fork did not alter this event. The in-source rationale comment at lines 49–53 already documents: (a) upstream-verbatim origin, (b) Slither 0.11.4 parser bug that makes this finding unsuppressable inline (empty `elements` bypasses `slither-disable-next-line`), (c) accepted-residual status per `STAGE_B_NOTES.md` B6. Re-surfaces in Stage C because C1 moved the file from `src/` to `src/vault/` — path change, not content change. No action required beyond this cross-reference.
### Post-triage verification
`slither . --filter-paths "lib|test"` re-run after inline suppressions: **1 result(s) found** — the single accepted residual. Stage C source surface is clean modulo the Stage B carryover.
