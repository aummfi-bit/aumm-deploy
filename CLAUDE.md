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

### How this applies to Claude Code specifically

Claude Code can run shell commands itself. That does not weaken the loop — it *accelerates* it. The loop becomes:

1. Claude Code reads the plan, identifies the next sub-step, reads relevant files.
2. Claude Code drafts the change (file edit, command to run, whatever the sub-step calls for).
3. **Before executing anything that mutates repo state**, Claude Code presents the planned change to the user and waits for approval (see section 8).
4. Claude Code runs the verification command itself, reads the output, reports result. If the result deviates from expectation, it stops and flags.
5. Next sub-step.

Approval is per-sub-step. Approval of C6.2 is not approval of C6.3. If the user says "proceed" once, that covers the one pending action, not a queue.

---

## 7. Cursor editor and its lockdown

Cursor is configured as a text editor only during active chat-directed work. Agentic modes (Auto-Run, Composer autonomous execution) are disabled.

**Full rules:** `.cursorrules` at the repo root, including the section "Cursor operation scope during active chat-directed work" added at commit `fcde1b0`.

**Summary:**

- Cursor edits and saves files when directed by the chat-side Claude. No autonomous edits, no autonomous "improvements."
- Cursor does **not** run `git`, `forge`, shell commands, or any action outside text editing. The user runs all of these in terminal.
- When Claude Code is active in the repo, Cursor's role shrinks further — it's a backup editor for manual inspection or for user-initiated edits that don't involve Claude at all.

---

## 8. Claude Code operational scope

Claude Code has tools that go beyond a chat window: it can read files, write files, run commands, call external services. This is useful and risky. The rules below bound that power to what's safe.

### 8a. Allowed without asking (non-mutating reads)

Claude Code can execute these freely and report results:

- File reads: `view`, `cat`, `head`, `tail`, `wc`, `grep`, `find`, `ls`, `file`, `od`
- Git state queries: `git status`, `git log`, `git diff`, `git show`, `git branch`, `git ls-files`, `git remote -v`
- Foundry read-only: `forge build`, `forge test`, `forge lint`, `forge fmt --check`, `forge config`, `forge tree`, `forge remappings`
- Slither analysis (non-installing): `slither .`, `slither <path>`, with any `--filter-paths` / `--exclude-*` flags
- Hashing / integrity checks: `shasum`, `md5`, `diff`
- Anything else that doesn't write to disk, doesn't hit the network, doesn't mutate git state

### 8b. Requires explicit chat approval before each execution

Claude Code must present the planned action and wait for user approval — **every time**, not "once per session" — before:

- Writing to any file (create, edit, delete). This includes files in `docs/`, `src/`, `test/`, `script/`, config files, and this `CLAUDE.md`.
- Any mutating git command: `git add`, `git commit`, `git push`, `git tag`, `git checkout -b`, `git merge`, `git rebase`, `git reset`, `git restore`, `git rm`, `git mv`, `git stash`.
- Running anything that hits the network: `forge install`, `pip install`, `npm install`, `curl`, `wget`, `forge script --rpc-url`, `forge test --fork-url`.
- Any `forge script` run (even against a local anvil — the script itself is the contract being executed).
- Running commands as root / with `sudo`.
- Deleting files, even if untracked. The 2026-04-18 `STAGES_OVERVIEW.md` stub incident (mini-C14) showed that untracked-file cleanup still deserves a chat beat before the `rm`.

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

If Claude Code is uncertain whether an action falls in 8a, 8b, or 8c, treat it as 8b. Ask. The cost of asking when the answer is "yes, do it" is one round-trip. The cost of acting when the answer is "no" is a rollback, a debug session, or worse.

Never fabricate output. If a tool fails or returns something unexpected, say so. If Claude Code catches itself inferring what the user "probably" wants instead of asking, stop and ask.

---

## 9. Why the rules exist — the C14 lesson

### The incident (2026-04-17)

Cursor was in Auto-Run Mode with a permissive command allowlist. During what should have been a chat-directed Stage C5 step (record AuMM design in `STAGE_C_NOTES.md`), Cursor executed the step autonomously — generating the notes content itself and committing without chat-level direction. The commit was reasonable content but the process was wrong: no chat instruction, no verification loop, no opportunity to check the content matched the C5 design spec.

The finding is logged as **C14** in `docs/STAGE_C_NOTES.md`. The immediate fix was turning Cursor's Auto-Run to "Ask Every Time," emptying the command allowlist, and adding the "Cursor operation scope during active chat-directed work" section to `.cursorrules` at commit `fcde1b0`.

### The principle

**In this repo, autonomous helpfulness by AI tools is a failure mode.**

Agentic tools (Cursor Composer, Claude Code with loose allowlists, any "write file and commit" combined action) treat forward progress as the goal. They generate plausible next-steps ahead of direction. Most of the time those next-steps are correct-looking; occasionally they are wrong; the user cannot tell which without reading the diff. When the protocol will hold real money post-Stage R, "occasionally wrong" is not acceptable.

The grep-and-confirm loop exists so that every mutating action passes through human attention before it lands. Slower by design. Cheaper than recovering from an unnoticed drift at C7 or C8.

### The mini-incident (2026-04-18, today)

During the setup for switching from the chat-only loop to Claude Code, the user asked Cursor (still in text-editor-only mode per the post-C14 rules) to edit `docs/STAGES_OVERVIEW.md` by adding three bullets at three specific anchors. Cursor found the file didn't exist in the repo (it had been living only in project knowledge), and rather than reporting "file not found, stopping," it *created* a new file with a stub of the anchor context plus the three bullets. The stub was wrong content, but — because the lockdown held — it was untracked, never committed, and caught at the next `git diff` grep.

Two lessons from this:

1. **The lockdown works.** A pre-lockdown Cursor would have committed the stub. The post-lockdown one couldn't, so the damage was reversible via one `rm`.
2. **AI tools still default to "make progress" over "stop and report."** Even a text-editor-only Cursor invented a stub file rather than surfacing the missing-file condition. Claude Code will have the same bias. The rules in section 8 exist to counter that bias.

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

**Last update:** 2026-04-18, post-C6.1.

**Branch:** `stage-c` (ahead of `main`, fast-forward-mergeable on C9 completion).

**Latest commits (origin/stage-c):**

```
751f699 C6.1: src/token/IAuMM.sol — interface for AuMM ERC-20 (per C5.2)
1b39d35 docs: add Argot Collective tooling to Stages P, Q, R (hevm, Act, Sourcify)
a8ec19c docs: sync STAGES_OVERVIEW.md + FINDINGS.md into repo (verbatim from project knowledge)
fcde1b0 cursorrules: add Cursor operation scope rule (text-editor only during chat-directed work)
```

**Last completed tag:** `stage-b-complete` (commit `b627a92`, 2026-04-14).

**Stage C position:**

- C0 complete — branch + notes scaffold
- C1 complete — directory reorg to `src/vault/`
- C2 complete — canonical constants + AuMM emission schedule in notes
- C3 complete — `src/lib/AureumTime.sol`
- C4 complete — `test/unit/AureumTime.t.sol` (33/33 green)
- C5 complete — AuMM design in notes
- **C6.1 complete** — `src/token/IAuMM.sol` committed at `751f699`, `forge build` green (10 files, solc 0.8.26)
- **C6.2 next** — implement `src/token/AuMM.sol` per the C5 design recorded in `STAGE_C_NOTES.md`
- C6.3 — `forge build` + `forge lint src/token/` both green
- C6.4 — commit with message `"C6: src/token/AuMM.sol + IAuMM.sol — 21M-cap ERC-20 with halving schedule"` (plan-verbatim; note this message covers both files even though IAuMM landed separately in C6.1)
- C7, C8, C9 — remaining

**How to resume at C6.2:**

1. Read `docs/STAGE_C_PLAN.md` section C6 in full — sub-step C6.2 is the C6 design text plus "full implementation per C5 design."
2. Read `docs/STAGE_C_NOTES.md` section C5 in full — this is the canonical AuMM design. Constructor signature, storage layout, state machine, `setMinter` flow, `mint` flow, `blockEmissionRate`, constants, errors, events — all specified.
3. Read `src/token/IAuMM.sol` (committed at C6.1) — AuMM must match this interface.
4. Read `src/lib/AureumTime.sol` — AuMM imports `BLOCKS_PER_ERA` from it.
5. Draft `src/token/AuMM.sol`. Present the full file in chat for approval before writing to disk (section 8b).

### Housekeeping notes for resuming

- `.cursorrules` was amended at `fcde1b0` with the "Cursor operation scope during active chat-directed work" section. This is the post-C14 lockdown. Respect it.
- Cursor is in text-editor-only mode with Auto-Run set to "Ask Every Time," Command Allowlist empty, Browser / MCP / File-Deletion / External-File Protection all on.
- Claude Code, when used, operates under section 8. Git mutations (`add`, `commit`, `push`, `tag`) are run by the user in terminal, not by Claude Code.
- Project-knowledge-only files (aumm-specs and friends, section 4) are invisible to Claude Code. If a plan or notes reference requires spec text, ask the user to paste the relevant section.

---

## 12. When uncertain, ask

This is the fallback rule that subsumes everything else. If any of the following is true, stop and ask in chat rather than proceeding:

- The plan is ambiguous about the current sub-step.
- An expected file or path doesn't exist.
- A command fails or returns unexpected output.
- An action seems like it might fall into section 8b or 8c but you're not sure.
- The user said something that contradicts the plan.
- You're about to make an "obviously correct" decision that wasn't explicitly in the plan or the notes.

The cost of asking is a round-trip. The cost of guessing wrong is a rollback plus the time to figure out what was guessed wrong. The grep-and-confirm loop is built on the same principle at the micro-scale; this rule is the same principle at the macro-scale.
