# CLAUDE.md — Operational Context for Aureum (`aumm-deploy`)

> **Read this on every session start.** This file is the orientation layer for any Claude instance (Claude Code, Claude in chat, Claude in Chrome) that touches this repo. It captures what Aureum is, what's locked, the working discipline, and why the rules are shaped the way they are. The stage plans (`docs/STAGE_*_PLAN.md`) are the operational detail; this file is the framing.

---

## 1. What Aureum is

Aureum is an automated market maker built as a parallel instance of Balancer V3 with a redesigned tokenomic layer. Fair launch, no VCs, Bitcoin-inspired emission schedule. The short pitch: the best of Bitcoin (fixed cap, geometric halving, no pre-mine), Frankencoin (collateralised stable, permissionless pool integration), and Balancer V3 (custom hooks, weighted and stable pools, vault-centric architecture), combined.

Public site: <https://aumm.fi>. GitHub org: `aummfi-bit`. This repo: `aumm-deploy`.

### Design philosophy — audit inheritance

The Vault contracts (`Vault.sol`, `VaultAdmin.sol`, `VaultExtension.sol`) remain **byte-identical** to audited Balancer V3 code. All Aureum customisation is isolated to a small, reviewable surface:

- `AureumProtocolFeeController.sol` — the fee-routing contract. 50% of swap fees route to der Bodensee pool (the Vault's maximum possible allocation), 50% stay with LPs, **no creator fees, ever**.
- `AureumVaultFactory.sol` — a ~5-line diff fork of Balancer's `VaultFactory.sol` that accepts an external `IProtocolFeeController` via constructor (Option F2).
- `AureumAuthorizer.sol` — governance Safe multisig during Stages A–K, handed off to on-chain governance at Stage K.

Any change that would perturb the Vault bytecode is load-bearing and requires explicit chat-level discussion before it lands. If Claude Code finds itself editing anything under the Balancer submodule or suggesting a Vault modification, stop and ask.

### Token design

- **AuMM** (Aureum Market Maker) — ERC-20, 21M fixed cap, Bitcoin-style geometric halving on block-number era boundaries (`BLOCKS_PER_ERA = 10_512_000`). No treasury, no pre-mine, no owner. Emissions routed through a per-pool distributor that respects gauge eligibility and CCB (Compound Centrifugal Balance) scoring.
- **AuMT** (Aureum Market Tessera) — per-pool LP receipt. Used for governance weight (with qualification period and withdrawal-reset) and for claiming the pool's emission share.

---

## 2. Locked architectural decisions

These are settled. Do not re-litigate without explicit user direction.

| Subject | Decision |
|---|---|
| Factory pattern | Option F2 — `AureumVaultFactory.sol`, ~5-line diff fork of `VaultFactory.sol`, accepts external `IProtocolFeeController` via constructor |
| Authorizer | Governance Safe multisig for Stages A–K; migrates to on-chain governance at Stage K |
| Compiler | `solc 0.8.26`, optimizer `9999` runs, `via_ir = true`, EVM version `cancun` — **exact match to Balancer's mainnet deployment** |
| Balancer submodule | `aummfi-bit/balancer-v3-monorepo`, pinned to commit `68057fda` (Dec 3 2024), verified against Etherscan source at `0xAc27df81663d139072E615855eF9aB0Af3FBD281` |
| Balancer V3 Vault (mainnet) | `0xbA1333333333a1BA1108E8412f11850A5C319bA9` |
| OpenZeppelin | `openzeppelin-contracts v5.6.1` (ERC20 base only — **not** ERC20Burnable) |
| Foundry libs | `forge-std v1.15.0` |
| Slither | `0.11.4` (inside `.venv/`) |
| RPC for mainnet fork | Ankr |
| Fee routing | 50% to der Bodensee, 50% to LPs, 0% creator fees — hard rule |

**Beets (`docs.beets.fi`) is a minor reference only.** It's a Balancer V3 fork on Sonic, not Ethereum mainnet, not a source of truth. Don't cite Beets docs as authoritative.

**Fe and ethdebug are not relevant to this project.** If either surfaces in suggestions, skip.

---

## 3. Repository layout

```
aumm-deploy/
├── CLAUDE.md                     — this file
├── .cursorrules                  — Cursor editor conventions + lockdown rules (section 7)
├── foundry.toml                  — compiler config matching Balancer mainnet
├── foundry.lock                  — pinned dep versions for reproducibility
├── docs/
│   ├── STAGES_OVERVIEW.md        — master C-through-R stage sequence (424 lines)
│   ├── FINDINGS.md               — resolved + deferred open questions, OQ-1 through OQ-19 (1074 lines)
│   ├── STAGE_A_PLAN.md           — complete, tagged stage-a-complete
│   ├── STAGE_B_PLAN.md / _NOTES.md — complete, tagged stage-b-complete
│   ├── STAGE_C_PLAN.md / _NOTES.md — in progress (see section 11)
│   └── balancer_v3_reference.md  — working reference, Balancer V3 substrate notes
├── src/
│   ├── vault/                    — Stage B contracts (AureumVault, Factory, FeeController, Authorizer)
│   ├── lib/                      — Stage C onward; pure libraries (AureumTime, ...)
│   ├── token/                    — Stage C (AuMM) + Stage I (AuMT)
│   ├── fee_router/               — Stage D
│   ├── ccb/                      — Stage F
│   ├── gauge/                    — Stage G
│   ├── emission/                 — Stage H
│   ├── registry/                 — Stage J
│   ├── governance/               — Stage K + Stage O
│   └── incendiary/               — Stage L
├── test/
│   └── unit/                     — per-file unit tests; fork tests under fork/ when needed
├── script/                       — deployment scripts
├── lib/                          — foundry-managed submodules (balancer-v3-monorepo, openzeppelin-contracts, forge-std)
└── .venv/                        — Python virtualenv for Slither
```

A stage that doesn't yet exist has no directory under `src/` until its first file lands. Don't pre-create empty folders.

---

## 4. Canonical reference documents

### In-repo (Claude Code can read directly)

| File | Purpose |
|---|---|
| `docs/STAGES_OVERVIEW.md` | Master stage sequence, stage summaries, dependency graph, testing strategy per stage, tags |
| `docs/FINDINGS.md` | All 19 resolved Open Questions (OQ-1 through OQ-19) plus deferred items. Cross-referenced constantly from stage plans |
| `docs/STAGE_X_PLAN.md` | Per-stage detailed plan: numbered sub-steps, time estimates, commands, tests, completion log |
| `docs/STAGE_X_NOTES.md` | Per-stage living design-decision log + findings log |
| `docs/balancer_v3_reference.md` | Balancer V3 substrate working notes |
| `.cursorrules` | Cursor editor conventions + the "Cursor operation scope during active chat-directed work" lockdown |

### Project-knowledge-only (invisible to Claude Code)

These files exist in the `claude.ai` project sidebar but **are not in the repo**. Claude Code cannot read them directly.

- **`aumm-specs.md`** and the **18 numbered spec docs** (`01_intro.md`, `02_*.md`, ..., `18_*.md`), plus the **28 pool-profile documents**. These are the protocol's canonical specification: tokenomics (§ix in `04_tokenomics.md`), constitution (§xxix in `10_constitution.md`), formulas F-0 through F-10 (`11_formulas.md`), bootstrap rules (`08_bootstrap.md`), appendices (`13_appendices.md`).

When a stage plan says "read `11_formulas.md` F-7" or "per §xxix in `10_constitution.md`" — Claude Code does not have these files. The correct move is to **ask the user to paste the relevant section into chat**, not to guess or fabricate the content. FINDINGS.md often quotes or summarises the relevant spec passages; check there first.

---

## 5. Cross-reference conventions

The plan and notes files use short reference codes. Know them on sight.

- **`OQ-N`** — Open Question N from `docs/FINDINGS.md`. Example: `per OQ-5` means "see OQ-5 in FINDINGS.md" — typically a resolved canonical constant or a settled architectural choice.
- **`C-Dn`** — Planning-stage design decision n from `docs/STAGE_C_PLAN.md` (similarly `B-Dn` for Stage B, etc.). These are the *choices* made while writing the plan, before implementation. Example: `per C-D12` means "see decision C-D12 in STAGE_C_PLAN.md."
- **`Cn`** (two-digit, like `C10`, `C11`, `C14`) — Implementation-stage finding n from `docs/STAGE_C_NOTES.md`. Numbered from 10 to avoid collision with the `C-D*` planning codes. Example: `C14` is the Cursor autonomous execution incident (section 9).
- **`F-n`** — Formula n from `aumm-site/11_formulas.md` (project-knowledge-only). Example: `F-0 piecewise bootstrap emission decay`.
- **`§xxix`** — Section xxix in an `aumm-site` numbered spec. Project-knowledge-only.
- **Block-number constants** — canonical, defined in FINDINGS OQ-3/OQ-4/OQ-5. `BLOCKS_PER_DAY = 7_200`, `BLOCKS_PER_EPOCH = 100_800`, `BLOCKS_PER_MONTH = 219_000`, `BLOCKS_PER_QUARTER = 657_000`, `BLOCKS_PER_YEAR = 2_628_000`, `BLOCKS_PER_ERA = 10_512_000`. **Block numbers are canonical time units everywhere in the protocol.** Calendar terms ("month," "year," "14 days") are aliases.

---

## 6. Working discipline — the grep-and-confirm loop

This text is lifted verbatim from the project's working agreement. It is non-negotiable for Stage C and every subsequent stage.

> Sagix runs Cursor locally and Claude in a chat window. These are two separate AI sessions. The working loop is:
>
> 1. Claude (chat) directs one small step, citing the plan sub-step (e.g., "C3.2").
> 2. Sagix tells Cursor to execute that step.
> 3. Sagix runs a verification command — usually `grep`, `git status`, `git diff`, `forge build`, or `forge test` — and pastes the output back into chat.
> 4. Claude reads the grep/diff/build output and directs the next step, or flags a deviation.
>
> This loop is NON-NEGOTIABLE for Stage C and every subsequent stage. The reason: a drift of one import path, one pragma, one misnamed constant compounds silently across sub-steps. Catching drift at the next grep is cheap; catching it at C7 or C8 is expensive.
>
> **Concrete rules:**
>
> - Never chain sub-steps in a single direction ("do C3.2 and C3.3 and C3.4"). One sub-step per direction.
> - Never claim a command succeeded without seeing the output. If Sagix hasn't pasted the output, the step is not done.
> - After any `git commit`, ask for `git log --oneline -3` output to confirm the commit landed on the right branch with the right message.
> - After any file creation or edit, ask for a targeted `grep` or the output of `view` on the file — not "looks good, move on."
> - After any `forge build`, ask for the tail of the output even if Sagix says it's green. "Green" sometimes means "warnings only" or "compiled stale cached artifacts"; the output tells the truth.
>
> **Plan sub-steps that already contain explicit grep commands** (STAGE_C_PLAN.md C1.2, C1.3, C1.4, C1.5, etc.) are the minimum. Sub-steps that don't contain a grep still need a verification command — Claude picks the right one at direction time.
>
> **Exception:** the only sub-steps that can combine are purely mechanical pairs where the second is a direct continuation of the first with no decision surface (e.g., `mkdir -p src/vault` followed immediately by the four `git mv` commands in C1.1). Anything involving an import path, a pragma, a constant value, a test assertion, or a commit message is one-at-a-time.
>
> If Claude forgets this loop and starts directing multi-step batches, Sagix should say "grep discipline" and Claude reverts to one step at a time.

### Verification is never self-done by the writing tool

**Every file write, by any tool, must be followed by a read-back from the user's terminal in the same turn.** Not a tool-level self-check by the tool that did the writing, and not a "head and tail match" smell test. The authoritative verification is:

```
wc -l <path>
shasum -a 256 <path>
cat <path>       # or grep / targeted view on the relevant section
grep -c "—" <path>   # em-dash count as copy-paste-corruption sentinel
```

Run by the user from terminal, pasted back into the relevant chat. The reason this is a structural rule rather than a convention:

- Chat-visible drafts are not proof of disk content. Write tools can silently differ from displayed content via whitespace normalization, trailing-newline handling, encoding quirks, or internal buffer desync.
- The writer verifying its own output is the same class of circularity as a reviewer reviewing their own code. It catches nothing the writer wouldn't have caught before writing.
- The user's terminal is the single authoritative source of truth about what's on disk. Every grep-and-confirm checkpoint is built on that fact; source-tree writes are no exception.

This applies equally to Cursor saves and to any future tool added to the pipeline. Claude Code does not write source-tree files at all as of C7 (see section 8e), so the rule's primary enforcement surface is Cursor's output — but the principle survives any tooling change.

---

## 7. Cursor editor and its lockdown

Cursor is configured as a text editor only during active chat-directed work. Agentic modes (Auto-Run, Composer autonomous execution) are disabled.

**Full rules:** `.cursorrules` at the repo root, including the section "Cursor operation scope during active chat-directed work" added at commit `fcde1b0`.

**Summary:**

- Cursor edits and saves files when directed by the chat-side Claude or by Claude Code via the user. No autonomous edits, no autonomous "improvements."
- Cursor does **not** run `git`, `forge`, shell commands, or any action outside text editing. The user runs all of these in terminal.
- Cursor's role in the C7-onward pattern (section 8e) is executor-of-file-writes: receives content from Claude Code via the user, saves to the target path, no mutations beyond that.

---

## 8. Claude Code operational scope

Claude Code has tools that go beyond a chat window: it can read files, write files, run commands, call external services. This is useful and risky. The rules below bound that power to what's safe.

### 8a. Allowed without asking (non-mutating reads only)

Claude Code can execute these freely and report results:

- File reads: `view`, `cat`, `head`, `tail`, `wc`, `grep`, `find`, `ls`, `file`, `od`, `shasum`, `md5`, `diff`, `stat`
- Git state queries: `git status`, `git log`, `git diff`, `git show`, `git branch`, `git ls-files`, `git remote -v`, `git worktree list`
- Foundry read-only: `forge build`, `forge test`, `forge lint`, `forge fmt --check`, `forge config`, `forge tree`, `forge remappings`, `forge clean`
- Slither analysis: `slither .`, `slither <path>`, with any `--filter-paths` / `--exclude-*` flags
- Anything else that doesn't write to disk, doesn't hit the network, doesn't mutate git state

**`forge clean` is in 8a** because it only removes generated artifacts under `out/` and `cache/`; it cannot touch source-tree files. It's part of the standard verification toolkit.

**File writes are NOT in 8a**, under any circumstance or path. See section 8e.

### 8b. Requires explicit chat approval before each execution

Claude Code must present the planned action and wait for user approval — **every time**, not "once per session" — before:

- Any mutating git command: `git add`, `git commit`, `git push`, `git tag`, `git checkout -b`, `git merge`, `git rebase`, `git reset`, `git restore`, `git rm`, `git mv`, `git stash`, `git worktree add`, `git worktree remove`.
- Running anything that hits the network: `forge install`, `pip install`, `npm install`, `curl`, `wget`, `forge script --rpc-url`, `forge test --fork-url`.
- Any `forge script` run (even against a local anvil — the script itself is the contract being executed).
- Running commands as root / with `sudo`.
- Deleting files, even if untracked. The 2026-04-18 `STAGES_OVERVIEW.md` stub incident showed that untracked-file cleanup still deserves a chat beat before the `rm`.

**Note on the git-mutation rule in practice:** the established convention on this project is that **the user runs all `git add`/`commit`/`push`/`tag` in their own terminal**, not Claude Code. This gives the user a final eyes-on pass at `git status` before a commit lands. Claude Code's role around git mutations is to draft the exact command (including commit message) and confirm expected `git status` state before and after; the user executes in terminal. Claude Code asking for approval to run git mutations itself is technically allowed by 8b but practically never done.

**File writes are handled separately in section 8e**, not here. Earlier versions of this document placed "writing to any file" in 8b ("ask before each write"). The C6.2 episode showed that approval-to-write combined with write-and-self-verify by the writing tool leaves the verification gap 8a/b/c cannot close. Source-tree writes are now delegated per 8e.

### 8c. Banned — do not do these even with user approval in this session's chat

Some actions require a higher bar than a single chat line. If any of these come up, stop and escalate — don't execute, don't offer to execute, don't construct a plan that would execute them.

- Editing anything under `lib/balancer-v3-monorepo/` (the Balancer submodule). **Byte-identical to audited source is load-bearing.**
- Editing anything under `lib/openzeppelin-contracts/` or `lib/forge-std/`. Upstream code stays upstream.
- Pushing directly to `main` or force-pushing anywhere.
- Creating or deleting GitHub releases, tags, or branches on the remote.
- Running any transaction-broadcasting command against Ethereum mainnet (`--broadcast` flag on `forge script` with a mainnet RPC).
- Bumping dep versions (`forge install X@new-version`, editing `foundry.lock`, editing `package.json` if any). Dep bumps are a chat-level architectural discussion, not an operational step.
- Installing new dependencies without explicit chat-level approval and discussion of need. "Ask before adding a new dependency" is a standing rule.

### 8d. When uncertain

If Claude Code is uncertain whether an action falls in 8a, 8b, 8c, or 8e, treat it as 8b. Ask. The cost of asking when the answer is "yes, do it" is one round-trip. The cost of acting when the answer is "no" is a rollback, a debug session, or worse.

Never fabricate output. If a tool fails or returns something unexpected, say so. If Claude Code catches itself inferring what the user "probably" wants instead of asking, stop and ask.

### 8e. Execution delegation — Claude Code does not write files

**Claude Code does not use `Write`, `Edit`, `Create-File`, or any other file-mutating tool against this repo.** Not on source files, not on test files, not on docs, not on config, not on `CLAUDE.md`, not on scratch paths, not on `/tmp`. Zero file writes, period.

File writes by Claude Code were permitted under an earlier version of this document and were the proximate source of the C6.2 verification gap (section 9). The rule is now structural, not "ask each time."

The execution pattern for any change that would have been a file write:

1. **Claude Code drafts the full file content in chat.** Complete content in a single code block, end-to-end, no placeholders. For edits to an existing file, Claude Code presents either the full replacement content or a clearly-marked patch (with unambiguous `old_text` / `new_text` blocks).
2. **The user reviews the draft directly.** Chat Claude is not a default reviewer — user review is sufficient for the vast majority of sub-steps, and adding a chat-Claude round-trip per sub-step reintroduces the friction §8e was meant to reduce. Escalate to a chat-Claude session only when: Claude Code flags drift between its draft and the post-save file; `forge build` / `forge test` / `forge lint` fails unexpectedly; Claude Code's draft deviates from the C5 design, stage plan, or CLAUDE.md conventions; the user's own instinct flags something as off; or any §8b / §8c action surfaces. Default path: user reviews the draft in Claude Code's chat, pastes to Cursor, runs terminal integrity check, pastes output back to Claude Code — no third-party chat round-trip needed.
3. **The user pastes the approved content into Cursor**, which saves to the target path. Cursor is locked to text-editor-only (section 7), so "save" means "transcribe to disk verbatim" — no reformatting, no smart quotes, no line-ending conversions, no content changes.
4. **The user runs integrity checks in terminal** against the saved file:
   - `wc -l <path>` — line count matches Claude Code's stated line count
   - `shasum -a 256 <path>` — hash for the record (useful for future drift detection)
   - `cat <path>` — full file content, for user or chat-Claude to read against the approved draft
   - `grep -c "—" <path>` — em-dash count, as a copy-paste-corruption sentinel (this codebase uses em-dashes heavily; they're the most commonly mangled character)
5. **The user pastes the terminal output back to Claude Code.** Claude Code compares against its draft and either confirms byte-match or flags drift.

The user provides review (with chat-Claude as an escalation channel, not a default one); Cursor provides transcription; the terminal provides verification; Claude Code provides drafting and post-write confirmation. Four independent roles, each doing one thing, with escalation to chat-Claude reserved for the cases enumerated above.

**Rationale for the delegation split (beyond the verification gap):**

- **Token economics.** Cursor is a subscription-paid tool the user already owns; routing file writes through it avoids metered-API consumption on large file content. Claude Code's token budget is preserved for the work it's uniquely good at (planning, verification, multi-step reasoning).
- **Safety.** Claude Code's reasoning and Cursor's transcription are independent failure surfaces. If Claude Code drafts wrong content, the user catches it at review. If Cursor corrupts during paste-and-save, the terminal integrity check catches it. Either failure alone is visible; both would have to happen the same way at the same time to slip through.
- **Reviewability.** Every file change is visible as text in chat before it hits disk. `git diff` after the fact is not the first time the user sees the content.

**For commits, pushes, and tags** — also user-terminal, per the convention noted in 8b. The user runs git mutations in their own terminal with their own hands on the keyboard. Claude Code drafts commit messages and confirms expected `git status` state before and after; does not run git mutations itself.

---

## 9. Why the rules exist — the C14 lineage of incidents

### C14 — Cursor autonomous execution (2026-04-17)

Cursor was in Auto-Run Mode with a permissive command allowlist. During what should have been a chat-directed Stage C5 step (record AuMM design in `STAGE_C_NOTES.md`), Cursor executed the step autonomously — generating the notes content itself and committing without chat-level direction. The commit was reasonable content but the process was wrong: no chat instruction, no verification loop, no opportunity to check the content matched the C5 design spec.

Logged as **C14** in `docs/STAGE_C_NOTES.md`. Immediate fix: Cursor's Auto-Run set to "Ask Every Time," command allowlist emptied, added the "Cursor operation scope during active chat-directed work" section to `.cursorrules` at commit `fcde1b0`.

### Mini-incident — Cursor stub-invention (2026-04-18, earlier)

The user asked Cursor (text-editor-only mode) to edit `docs/STAGES_OVERVIEW.md` by adding three bullets at three specific anchors. Cursor found the file didn't exist in the repo (it had been living only in project knowledge), and instead of reporting "file not found, stopping," *created* a new file with a stub of the anchor context plus the three bullets. Wrong content, but caught at the next `git diff` because the lockdown prevented auto-commit. Fix: `rm` the stub, sync the real `STAGES_OVERVIEW.md` from project knowledge into the repo, apply the three bullets to the real file as a separate commit.

### Mini-incident — Claude Code self-verification gap (2026-04-18, later)

During C6.2, Claude Code wrote `src/token/AuMM.sol` via its `Write` tool. Claude Code's own follow-up was a `wc -l` line count plus a "head and tail match" claim, and it proposed proceeding directly to C6.3 without a full read-back. The user caught the gap and ran `cat src/token/AuMM.sol` from their own terminal against the approved draft — the file was byte-perfect, but the verification gap was the point. A self-check by the writing tool is not the same as an external read-back. Fix: section 6 now explicitly requires terminal-side read-back for every write; section 8e eliminates Claude Code writes entirely.

### The principle

**Autonomous helpfulness by AI tools is a failure mode in this repo.**

Agentic tools — Cursor Composer, Claude Code with loose allowlists, any "write file and move on" combined action — treat forward progress as the goal. They generate plausible next-steps ahead of direction. Most of the time those next-steps are correct-looking; occasionally they are wrong; the user cannot tell which without reading the diff. When the protocol will hold real money post-Stage R, "occasionally wrong" is not acceptable.

Three data points in three days, same underlying pattern: **AI tools default to self-verification even when given instructions to the contrary, and default to making progress when stopping-and-reporting would be the more disciplined move.** The cure is structural: separate the tool that acts from the tool that verifies. That is what sections 6, 7, and 8e now encode.

---

## 10. Writing register and commit-message conventions

### Prose register

Match the register of the existing stage plans. Characteristics:

- Dense, declarative, precise. No marketing voice, no hedging with "potentially" / "might" / "could possibly" where a direct statement fits.
- Em-dashes (`—`, Unicode U+2014), not double-hyphens, not hyphen-minus. The whole codebase uses em-dashes; stay consistent.
- No emojis. No decorative formatting. Lists when lists clarify, prose when prose clarifies.
- Code in backticks. File paths in backticks. Cross-references as `OQ-N` / `C-Dn` / `§xxix` (section 5).
- Assume the reader is a competent protocol engineer. Don't re-explain what a pool factory is or what `block.number` means. Do explain Aureum-specific decisions (why F2, why one-shot setter, why no `_update` override).

### Commit-message conventions

Two families:

**1. Plan sub-step commits.** Format: `<stage><step>: <specific change>`. The stage plan specifies the exact message for each numbered sub-step — use it verbatim. Examples:

- `C3: src/lib/AureumTime.sol`
- `C6.1: src/token/IAuMM.sol — interface for AuMM ERC-20 (per C5.2)`
- `C7: test/unit/AuMM.t.sol — cap, minter, halving, invariants`

When the plan specifies a message, it is canonical. Don't rephrase.

**2. Ad-hoc commits** (planning-doc edits, cursorrules updates, tooling). Format: `<category>: <change>`. Categories: `docs:`, `cursorrules:`, `foundry:`, `tooling:`. Examples:

- `docs: sync STAGES_OVERVIEW.md + FINDINGS.md into repo (verbatim from project knowledge)`
- `docs: add Argot Collective tooling to Stages P, Q, R (hevm, Act, Sourcify)`
- `cursorrules: add Cursor operation scope rule (text-editor only during chat-directed work)`

### Commit discipline

One logical change per commit. Don't sweep unrelated files into `-a`. Don't mix planning-doc edits with code changes. If in doubt, split — `git reset HEAD~ && git add -p` is cheap.

After every commit, verify with `git log --oneline -N` where N covers the commit plus enough prior commits to confirm the branch position. For non-trivial commits, also `git status -sb` to confirm no leftover staged or modified files.

---

## 11. Current state and how to resume

This section is the resumption anchor. Update at the end of every completed sub-step.

**Last update:** 2026-04-18, post-C7 (`test/unit/AuMM.t.sol` at `91c0bb5`, Completion Log filled through C7, ready for C8).

**Branch:** `stage-c` (ahead of `main`, fast-forward-mergeable on C9 completion).

**Latest commits on origin/stage-c:**

```
91c0bb5 C7: test/unit/AuMM.t.sol — cap, minter, halving, invariants
22f85b7 docs: §8e — chat-Claude is escalation, not default reviewer
60ad451 docs: log Stage C C0–C6 completion and advance CLAUDE.md §11 anchor to C7
6dd092a C6: src/token/AuMM.sol + IAuMM.sol — 21M-cap ERC-20 with halving schedule
fdaa07f docs: revise CLAUDE.md §6 §8 §9 §11 for Cursor-executor tooling split (C7 onward)
f8d6076 docs: add CLAUDE.md — operational context for Claude Code and future sessions
751f699 C6.1: src/token/IAuMM.sol — interface for AuMM ERC-20 (per C5.2)
1b39d35 docs: add Argot Collective tooling to Stages P, Q, R (hevm, Act, Sourcify)
a8ec19c docs: sync STAGES_OVERVIEW.md + FINDINGS.md into repo (verbatim from project knowledge)
fcde1b0 cursorrules: add Cursor operation scope rule (text-editor only during chat-directed work)
140107b C14: log Cursor autonomous execution finding; Stage C lockdown enacted
```

**Last completed tag:** `stage-b-complete` (commit `b627a92`, 2026-04-14).

**Stage C position:**
- C0 complete — branch + notes scaffold
- C1 complete — directory reorg to `src/vault/`
- C2 complete — canonical constants + AuMM emission schedule in notes
- C3 complete — `src/lib/AureumTime.sol`
- C4 complete — `test/unit/AureumTime.t.sol` (33/33 green)
- C5 complete — AuMM design in notes
- C6 complete — `src/token/IAuMM.sol` (C6.1 at `751f699`) + `src/token/AuMM.sol` (131 lines, 5 em-dashes, SHA `f81ef4de142be5814b9099f446da8963a8b79030f1cddf7c5e3dafa01ec3db3c`); umbrella commit `6dd092a` plan-verbatim; `fdaa07f` lands §6 / §8 / §9 / §11 revisions including section 8e (Cursor executor, Claude Code no writes)
- C7 complete — `test/unit/AuMM.t.sol` (`91c0bb5`; 297 lines; 28/28 green including `AuMMInvariantTest` + handler); doc chain includes `60ad451` (Completion Log + §11→C7) and `22f85b7` (§8e escalation note)
- **C8 next** — Slither triage gate: `source .venv/bin/activate`, `slither . --filter-paths "lib|test"`, per `STAGE_C_PLAN.md` C8.2–C8.3
- C9 — `stage-c-complete` tag after C8 is logged

**How to resume (C8):**
1. Read `docs/STAGE_C_PLAN.md` section C8 — activation, triage discipline, C8.4 commit pattern.
2. Run Slither (C8.1); capture full output; triage each finding per C8.2.
3. Re-run to verify clean (C8.3); record accepted residuals in `docs/STAGE_C_NOTES.md` under `## C8 — Slither triage` if needed.
4. Commit triage output per C8.4 — `git add` suppressions and notes, plan-verbatim commit message, `git push`, then log C8 in the Completion Log.

### Housekeeping notes

- `.cursorrules` was amended at `fcde1b0` with the "Cursor operation scope during active chat-directed work" section. This is the post-C14 lockdown. Respect it.
- Cursor is in text-editor-only mode with Auto-Run set to "Ask Every Time," Command Allowlist empty, Browser / MCP / File-Deletion / External-File Protection all on.
- **Claude Code does not write files as of `fdaa07f` (section 8e).** All file writes flow through Cursor. Claude Code's role is planning, drafting in chat, running non-mutating verifications (8a), and confirming results of user-run commands.
- Git mutations (`add`, `commit`, `push`, `tag`) are run by the user in terminal, not by Claude Code.
- Project-knowledge-only files (aumm-specs and friends, section 4) are invisible to Claude Code. If a plan or notes reference requires spec text, ask the user to paste the relevant section.

---

## 12. When uncertain, ask

This is the fallback rule that subsumes everything else. If any of the following is true, stop and ask in chat rather than proceeding:

- The plan is ambiguous about the current sub-step.
- An expected file or path doesn't exist.
- A command fails or returns unexpected output.
- An action seems like it might fall into section 8b, 8c, or 8e but you're not sure.
- The user said something that contradicts the plan.
- You're about to make an "obviously correct" decision that wasn't explicitly in the plan or the notes.

The cost of asking is a round-trip. The cost of guessing wrong is a rollback plus the time to figure out what was guessed wrong. The grep-and-confirm loop is built on the same principle at the micro-scale; this rule is the same principle at the macro-scale.
