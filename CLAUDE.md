# CLAUDE.md — Operational Context for Aureum (`aumm-deploy`)

> **Read this on every session start.** This file is the orientation layer for Claude Code sessions that touch this repo. It captures what Aureum is, what's locked, the working discipline, and why the rules are shaped the way they are. The stage plans (`docs/STAGE_*_PLAN.md`) are the operational detail; this file is the framing.

---

## 1. What Aureum is

Aureum is an automated market maker built as a parallel instance of Balancer V3 with a redesigned tokenomic layer. Fair launch, no VCs, Bitcoin-inspired emission schedule. The short pitch: the best of Bitcoin (fixed cap, geometric halving, no pre-mine), Frankencoin (collateralised stable, permissionless pool integration), and Balancer V3 (custom hooks, weighted and stable pools, vault-centric architecture), combined.

Public site: <https://aumm.fi>. GitHub org: `aummfi-bit`. This repo: `aumm-deploy`.

### Design philosophy — audit inheritance

The Vault contracts (`Vault.sol`, `VaultAdmin.sol`, `VaultExtension.sol`) remain **byte-identical** to audited Balancer V3 code. All Aureum customisation is isolated to a small, reviewable surface:

* `AureumProtocolFeeController.sol` — the fee-routing contract. 50% of swap fees route to der Bodensee pool (the OQ-1 hook saturates BAL v3's `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50%` cap at pool registration; the split is Vault-imposed, not Aureum-chosen), 50% stay with LPs, **no creator fees, ever**.
* `AureumVaultFactory.sol` — a ~5-line diff fork of Balancer's `VaultFactory.sol` that accepts an external `IProtocolFeeController` via constructor (Option F2).
* `AureumAuthorizer.sol` — governance Safe multisig during Stages A–K, handed off to on-chain governance at Stage K.

Any change that would perturb the Vault bytecode is load-bearing and requires explicit chat-level discussion before it lands. If Claude Code finds itself editing anything under the Balancer submodule or suggesting a Vault modification, stop and ask.

### Token design

* **AuMM** (Aureum Market Maker) — ERC-20, 21M fixed cap, Bitcoin-style geometric halving on block-number era boundaries (`BLOCKS_PER_ERA = 10_512_000`). No treasury, no pre-mine, no owner. Emissions routed through a per-pool distributor that respects gauge eligibility and CCB (Compound Centrifugal Balance) scoring.
* **AuMT** (Aureum Market Tessera) — per-pool LP receipt. Used for governance weight (with qualification period and withdrawal-reset) and for claiming the pool's emission share.

---

## 2. Locked architectural decisions

These are settled. Do not re-litigate without explicit user direction.

| Subject | Decision |
| --- | --- |
| Factory pattern | Option F2 — `AureumVaultFactory.sol`, ~5-line diff fork of `VaultFactory.sol`, accepts external `IProtocolFeeController` via constructor |
| Authorizer | Governance Safe multisig for Stages A–K; migrates to on-chain governance at Stage K |
| Compiler | `solc 0.8.26`, optimizer `9999` runs, `via_ir = true`, EVM version `cancun` — **exact match to Balancer's mainnet deployment** |
| Balancer submodule | `aummfi-bit/balancer-v3-monorepo`, pinned to commit `68057fda` (Dec 3 2024), verified against Etherscan source at `0xAc27df81663d139072E615855eF9aB0Af3FBD281` |
| Balancer V3 Vault (mainnet) | `0xbA1333333333a1BA1108E8412f11850A5C319bA9` |
| OpenZeppelin | `openzeppelin-contracts v5.6.1` (ERC20 base only — **not** ERC20Burnable) |
| Foundry libs | `forge-std v1.15.0` |
| Slither | `0.11.4` (inside `.venv/`) |
| RPC for mainnet fork | Ankr |
| Fee routing | 50% to der Bodensee (Vault's 50% protocol-fee cap saturated via OQ-1 hook), 50% LP residual (Vault-imposed), 0% creator fees — hard rule |

**Beets (`docs.beets.fi`) is a minor reference only.** It's a Balancer V3 fork on Sonic, not Ethereum mainnet, not a source of truth. Don't cite Beets docs as authoritative.

**Fe and ethdebug are not relevant to this project.** If either surfaces in suggestions, skip.

---

## 3. Repository layout

```
aumm-deploy/
├── CLAUDE.md                     — this file
├── .cursorrules                  — Cursor editor conventions + executor-role rules (section 7)
├── foundry.toml                  — compiler config matching Balancer mainnet
├── foundry.lock                  — pinned dep versions for reproducibility
├── docs/
│   ├── STAGES_OVERVIEW.md        — master C-through-R stage sequence
│   ├── FINDINGS.md               — resolved + deferred open questions, OQ-1 through OQ-19 + Stage G OQ-G1–G4
│   ├── STAGE_G_PRECHECK_AUTO_GAUGE.md — Stage G pivot decision record (auto-gauge)
│   ├── STAGE_G_NOTES.md          — Stage G design freeze + test matrix (pre-`STAGE_G_PLAN.md`)
│   ├── STAGE_A_PLAN.md           — complete, tagged stage-a-complete
│   ├── STAGE_B_PLAN.md / _NOTES.md — complete, tagged stage-b-complete
│   ├── STAGE_C_PLAN.md / _NOTES.md — complete, tagged stage-c-complete
│   ├── STAGE_D_PLAN.md / _NOTES.md — in progress (see section 11)
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
| --- | --- |
| `docs/STAGES_OVERVIEW.md` | Master stage sequence, stage summaries, dependency graph, testing strategy per stage, tags |
| `docs/FINDINGS.md` | All resolved Open Questions (OQ-1 through OQ-19, OQ-G1–G4 Stage G addendum) plus deferred items. Cross-referenced constantly from stage plans |
| `docs/STAGE_G_PRECHECK_AUTO_GAUGE.md` | Stage G auto-gauge pivot — accepted propositions, side-by-side delta, conflicts |
| `docs/STAGE_G_NOTES.md` | Stage G design freeze (G-D*) + efficiency event schema + test matrix |
| `docs/STAGE_X_PLAN.md` | Per-stage detailed plan: numbered sub-steps, time estimates, commands, tests, completion log |
| `docs/STAGE_X_NOTES.md` | Per-stage living design-decision log + findings log |
| `docs/balancer_v3_reference.md` | Balancer V3 substrate working notes |
| `.cursorrules` | Cursor editor conventions + the "Cursor operation scope — executor under Claude Code planning" rules |

### External canonical spec — `aummfi-bit/aumm-site` (read via WebFetch)

The protocol's canonical specification lives in a separate public GitHub repo: <https://github.com/aummfi-bit/aumm-site> (default branch `main`). Claude Code reads from it directly via WebFetch on raw URLs of the form `https://raw.githubusercontent.com/aummfi-bit/aumm-site/main/<file>`.

Layout at the repo root:

* **Numbered spec docs** — `01_intro.json` through `16_team.md` (with `07a_tokens.md` as a sub-doc). Canonical sections referenced from this repo include tokenomics (§ix in `04_tokenomics.md`), constitution (§xxix in `10_constitution.md`), formulas F-0 through F-12 (`11_formulas.md`), bootstrap rules (`08_bootstrap.md`), appendices (`13_appendices.md`), CCB narrative + multiplier engine (`03_theoretical_foundation.md`).
* **Pool profiles** — `miliarium_profiles/` directory holds the 28 individual Miliarium pool documents.
* **Other prose** — `aureum_schedule.md`, `project_aureum_design_final.md`, `script.md`, `15_overview.md`.
* **AI-consumption versions** — `llms.txt` (curated index) and `llms-full.txt` (full corpus concatenation) at the repo root, for cases where a single round-trip read is preferred over per-doc fetches.

When a stage plan says "read `11_formulas.md` F-7" or "per §xxix in `10_constitution.md`" — fetch the doc directly: `WebFetch(url=https://raw.githubusercontent.com/aummfi-bit/aumm-site/main/11_formulas.md, prompt=...)`. **Do not fabricate spec content.** If WebFetch fails or the relevant section is ambiguous after fetch, ask the user to paste from their local clone or the GitHub web view. FINDINGS.md often quotes or summarises the relevant spec passages; checking there first can avoid an unneeded fetch.

---

## 5. Cross-reference conventions

The plan and notes files use short reference codes. Know them on sight.

* **`OQ-N`** — Open Question N from `docs/FINDINGS.md`. Example: `per OQ-5` means "see OQ-5 in FINDINGS.md" — typically a resolved canonical constant or a settled architectural choice. **`OQ-G1`–`OQ-G4`** — Stage G addendum (gauge pivot), resolved 2026-05-05.
* **`C-Dn`** — Planning-stage design decision n from `docs/STAGE_C_PLAN.md` (similarly `B-Dn` for Stage B, `D-Dn` for Stage D, etc.). These are the *choices* made while writing the plan, before implementation. Example: `per C-D12` means "see decision C-D12 in STAGE_C_PLAN.md."
* **`Cn`** (two-digit, like `C10`, `C11`, `C14`) — Implementation-stage finding n from `docs/STAGE_C_NOTES.md`. Numbered from 10 to avoid collision with the `C-D*` planning codes. Example: `C14` is the Cursor autonomous execution incident (section 9).
* **`G-Dn`** — Design freeze decision n from `docs/STAGE_G_NOTES.md` (Stage G pivot; pre-`STAGE_G_PLAN.md`).
* **`F-n`** — Formula n from `11_formulas.md` in `aummfi-bit/aumm-site` (see §4). Example: `F-0 piecewise bootstrap emission decay`.
* **`§xxix`** — Section xxix in an `aummfi-bit/aumm-site` numbered spec (see §4).
* **Block-number constants** — canonical, defined in FINDINGS OQ-3/OQ-4/OQ-5. `BLOCKS_PER_DAY = 7_200`, `BLOCKS_PER_EPOCH = 100_800`, `BLOCKS_PER_MONTH = 219_000`, `BLOCKS_PER_QUARTER = 657_000`, `BLOCKS_PER_YEAR = 2_628_000`, `BLOCKS_PER_ERA = 10_512_000`. **Block numbers are canonical time units everywhere in the protocol.** Calendar terms ("month," "year," "14 days") are aliases.

---

## 6. Working discipline — the grep-and-confirm loop

This text is lifted verbatim from the project's working agreement. It is non-negotiable for every implementation stage.

> Sagix runs Cursor and Claude Code as two independent AI sessions tied to the same repo. The working loop is:
>
> 1. Claude Code reads repo state and authors one small sub-step prompt for Cursor, citing the plan sub-step (e.g., "D1.3").
> 2. Sagix hands the prompt to Cursor. Cursor executes exactly that one sub-step — generates content, saves file(s), stops.
> 3. Sagix runs a verification command in terminal — usually `grep`, `git status`, `git diff`, `forge build`, `forge test`, or `slither` — and pastes the output back to Claude Code.
> 4. Claude Code reads the grep/diff/build/slither output, validates against the plan, and either authors the next sub-step prompt or authors a fix prompt.
>
> This loop is NON-NEGOTIABLE for every implementation stage. The reason: a drift of one import path, one pragma, one misnamed constant compounds silently across sub-steps. Catching drift at the next grep is cheap; catching it at the stage tag is expensive.
>
> **Concrete rules:**
>
> * Never chain sub-steps in a single prompt ("do D1.2 and D1.3 and D1.4"). One sub-step per prompt.
> * Never claim a command succeeded without seeing the output. If Sagix hasn't pasted the output, the step is not done.
> * After any `git commit` (run by the user in terminal), ask for `git log --oneline -3` output to confirm the commit landed on the right branch with the right message.
> * After any file creation or edit, ask for a targeted `grep` or the output of `cat` on the file — not "Cursor reported the save, move on."
> * After any `forge build`, ask for the tail of the output even if Sagix says it's green. "Green" sometimes means "warnings only" or "compiled stale cached artifacts"; the output tells the truth.
>
> **Plan sub-steps that already contain explicit grep commands** (STAGE_D_PLAN.md D1.1, D1.2, etc.) are the minimum. Sub-steps that don't contain a grep still need a verification command — Claude Code picks the right one at prompt-authoring time.
>
> **Exception:** the only sub-steps that can combine are purely mechanical pairs where the second is a direct continuation of the first with no decision surface (e.g., `mkdir -p src/fee_router` followed immediately by a single file creation inside that directory). Anything involving an import path, a pragma, a constant value, a test assertion, or a commit message is one-at-a-time.
>
> If Claude Code forgets this loop and starts authoring multi-step prompts, Sagix should say "grep discipline" and Claude Code reverts to one step at a time.

### Verification is never self-done by the writing tool

**Every file write, by Cursor, must be followed by a read-back from the user's terminal in the same turn.** Not a Cursor-level self-check, and not a "save reported, move on" smell test. The authoritative verification is:

```
wc -l <path>
shasum -a 256 <path>
cat <path>       # or grep / targeted view on the relevant section
grep -c "—" <path>   # em-dash count as copy-paste-corruption sentinel
```

Run by the user from terminal, pasted back to Claude Code. The reason this is a structural rule rather than a convention:

* Cursor-visible saves are not proof of disk content. Save operations can silently differ from generated content via whitespace normalization, trailing-newline handling, encoding quirks, or internal buffer desync.
* The writer verifying its own output is the same class of circularity as a reviewer reviewing their own code. It catches nothing the writer wouldn't have caught before writing.
* The user's terminal is the single authoritative source of truth about what's on disk. Every grep-and-confirm checkpoint is built on that fact; Cursor's saves are no exception.

This applies equally to Cursor saves and to any future tool added to the pipeline. Claude Code does not write source-tree files (see **section 8e**), so the rule's primary enforcement surface is Cursor's output — but the principle survives any tooling change.

**After a sub-step’s verification is closed** (verdict ready to move on), **which model** drafts the *next* move is **not** a second paste round by default—see **§13 Beat handoffs** (Sonnet ↔ Opus). The per-save read-back above still applies; the handoff is about the *next* author turn.

---

## 7. Cursor editor and its operating posture

Cursor is the **executor** in the project's current workflow: it receives a single baby-step sub-step prompt from Claude Code (via the user), generates and saves the content for that sub-step, and stops.

**Full rules:** `.cursorrules` at the repo root, including the "Cursor operation scope — executor under Claude Code planning" section. This replaces the earlier "text-editor only" lockdown effective 2026-04-19.

**Summary:**

* Cursor generates and saves file content for exactly one sub-step per prompt, then stops. Does not chain, does not advance, does not propose the next sub-step.
* Cursor does **not** run `git`, `forge`, `slither`, or any shell command outside text editing. The user runs all of these in terminal so output routes back to Claude Code for auditing.
* Cursor does not invent files. If a referenced file does not exist, Cursor stops and reports "file not found" — it does not create a stub in its place (this is the 2026-04-18 STAGES_OVERVIEW.md lesson; see §9).
* Auto-Run stays "Ask Every Time"; Command Allowlist stays empty; Browser / MCP / File-Deletion / External-File Protection toggles stay on.

---

## 8. Claude Code operational scope

Claude Code has tools that go beyond a chat window: it can read files, write files, run commands, call external services. This is useful and risky. The rules below bound that power to what's safe.

### 8a. Allowed without asking (non-mutating reads only)

Claude Code can execute these freely and report results:

* File reads: `view`, `cat`, `head`, `tail`, `wc`, `grep`, `find`, `ls`, `file`, `od`, `shasum`, `md5`, `diff`, `stat`
* Git state queries: `git status`, `git log`, `git diff`, `git show`, `git branch`, `git ls-files`, `git remote -v`, `git worktree list`
* Foundry read-only: `forge build`, `forge test`, `forge lint`, `forge fmt --check`, `forge config`, `forge tree`, `forge remappings`, `forge clean`
* Slither analysis: `slither .`, `slither <path>`, with any `--filter-paths` / `--exclude-*` flags
* Anything else that doesn't write to disk, doesn't hit the network, doesn't mutate git state

**Authoritative checkout for reads.** Planning and audit reads must target the same tree the user and Cursor edit — the **primary repo checkout** (on this machine, `/Users/janus/code/aumm-deploy`), not an auxiliary Git worktree under `.claude/worktrees/` or elsewhere. Secondary worktrees can lag the tip of `stage-d` (see **D18** in `docs/STAGE_D_NOTES.md`). If a session was opened from a worktree path, `cd` to the main checkout before treating file reads as ground truth for **§8e.1** drafting.

**`forge clean` is in 8a** because it only removes generated artifacts under `out/` and `cache/`; it cannot touch source-tree files. It's part of the standard verification toolkit.

**File writes are NOT in 8a**, under any circumstance or path. See **section 8e**.

### 8b. Requires explicit chat approval before each execution

Claude Code must present the planned action and wait for user approval — **every time**, not "once per session" — before:

* Any mutating git command: `git add`, `git commit`, `git push`, `git tag`, `git checkout -b`, `git merge`, `git rebase`, `git reset`, `git restore`, `git rm`, `git mv`, `git stash`, `git worktree add`, `git worktree remove`.
* Running anything that hits the network: `forge install`, `pip install`, `npm install`, `curl`, `wget`, `forge script --rpc-url`, `forge test --fork-url`.
* Any `forge script` run (even against a local anvil — the script itself is the contract being executed).
* Running commands as root / with `sudo`.
* Deleting files, even if untracked. The 2026-04-18 `STAGES_OVERVIEW.md` stub incident showed that untracked-file cleanup still deserves a chat beat before the `rm`.

**Note on the git-mutation rule in practice:** the established convention on this project is that **the user runs all `git add`/`commit`/`push`/`tag` in their own terminal**, not Claude Code. This gives the user a final eyes-on pass at `git status` before a commit lands. Claude Code's role around git mutations is to draft the exact command (including commit message) and confirm expected `git status` state before and after; the user executes in terminal. Claude Code asking for approval to run git mutations itself is technically allowed by **8b** but practically never done.

**File writes are handled separately in section 8e**, not here. Earlier versions of this document placed "writing to any file" in **8b** ("ask before each write"). The C6.2 episode showed that approval-to-write combined with write-and-self-verify by the writing tool leaves a verification gap that **8a**, **8b**, and **8c** do not close. Source-tree writes are now delegated per **8e**.

### 8c. Banned — do not do these even with user approval in this session's chat

Some actions require a higher bar than a single chat line. If any of these come up, stop and escalate — don't execute, don't offer to execute, don't construct a plan that would execute them.

* Editing anything under `lib/balancer-v3-monorepo/` (the Balancer submodule). **Byte-identical to audited source is load-bearing.**
* Editing anything under `lib/openzeppelin-contracts/` or `lib/forge-std/`. Upstream code stays upstream.
* Pushing directly to `main` or force-pushing anywhere.
* Creating or deleting GitHub releases, tags, or branches on the remote.
* Running any transaction-broadcasting command against Ethereum mainnet (`--broadcast` flag on `forge script` with a mainnet RPC).
* Bumping dep versions (`forge install X@new-version`, editing `foundry.lock`, editing `package.json` if any). Dep bumps are a chat-level architectural discussion, not an operational step.
* Installing new dependencies without explicit chat-level approval and discussion of need. "Ask before adding a new dependency" is a standing rule.

### 8d. When uncertain

If Claude Code is uncertain whether an action falls in **8a, 8b, 8c, or 8e**, treat it as **8b**. Ask. The cost of asking when the answer is "yes, do it" is one round-trip. The cost of acting when the answer is "no" is a rollback, a debug session, or worse.

Never fabricate output. If a tool fails or returns something unexpected, say so. If Claude Code catches itself inferring what the user "probably" wants instead of asking, stop and ask.

### 8e. Execution delegation — Claude Code plans and audits; Cursor executes

**Claude Code does not use `Write`, `Edit`, `Create-File`, or any other file-mutating tool against this repo.** Not on source files, not on test files, not on docs, not on config, not on `CLAUDE.md`, not on scratch paths, not on `/tmp`. Zero file writes, period.

This rule is structural. File writes by Claude Code were the proximate source of the C6.2 verification gap (section 9). The earlier replacement pattern — Claude Code drafts content, Cursor transcribes verbatim — worked mechanically but produced a different failure mode on 2026-04-19: Claude Code chasing its tail during planning, re-reading files, re-scoping, re-proposing, and burning tokens without producing executable prompts. The current model inverts that split.

### Roles

* **Claude Code — planner and auditor.** Reads repo state, authors one baby-step sub-step prompt at a time for Cursor, hands the prompt to the user. After Cursor executes, reads the result (via the user pasting `cat` / `grep` / `git diff` / `forge build` / `slither` output from terminal), validates against the stage plan, and either signs off and authors the next sub-step prompt or authors a fix prompt. Claude Code also drafts commit messages as part of sub-step prompts and drafts the exact terminal commands (git, forge, slither) the user needs to run for verification.
* **Cursor — executor.** Receives a single-sub-step prompt, generates the content, saves the target file(s), stops. Does not chain, does not commit, does not run forge or git. See `.cursorrules` "Cursor operation scope — executor under Claude Code planning" for the full executor rules.
* **User (Sagix) — conductor.** Passes prompts from Claude Code to Cursor and pastes Cursor's results plus terminal output back to Claude Code. Runs all git mutations (`add`, `commit`, `push`, `tag`), all forge commands, and all slither runs in their own terminal. Owns the final decision when Claude Code and Cursor disagree.

### Sub-step prompt authoring (Claude Code's job)

Every prompt Claude Code hands the user for Cursor must be:

1. **One baby-step sub-step.** Named by its plan code (e.g., D1.3). No "and then," no "after that," no chaining. If the plan sub-step is itself too large, Claude Code breaks it into `D1.3a`, `D1.3b`, etc. and hands one at a time.
2. **Scoped to a specific file or file set.** The prompt names the target path(s) explicitly.
3. **Self-contained.** Cursor should not need to ask clarifying questions. If the sub-step depends on a design decision that isn't yet recorded, Claude Code resolves the decision first (or asks the user) before authoring the prompt.
4. **Paired with explicit stop criteria.** The prompt ends with a clear "stop after saving the file(s); do not commit, do not run forge, do not advance."
5. **Followed in the same turn by the terminal commands the user will run for audit.** Claude Code drafts the `wc -l` / `shasum` / `cat` / `grep` / `forge build` / `slither` commands the user pastes into terminal after Cursor saves.
6. **The §8e.1 `Instruction` line.** Every prompt must include `Instruction: Do exactly this and only this.` verbatim — the fixed scope line from the **§8e.1** template, not a paraphrase.

### Audit cycle (Claude Code's job, after Cursor executes)

1. User pastes Cursor's report + terminal output back to Claude Code.
2. Claude Code validates: file path correct, line count plausible, em-dash count plausible, content matches the prompt, `forge build` green if run, `slither` clean if run, `git diff` shows only the intended changes.
3. Claude Code reports verdict in one of two forms:
   * **✅ Proceed** — confirms the sub-step landed clean; drafts the commit terminal block (full paste-ready code fence per §8e Git mutations, not the bare commit-message string) if the sub-step closes a plan-defined work unit when that is **Sonnet-scoped** housekeeping (see **§13 Sonnet beats**). **Does not** draft the *next* **§8e.1** prompt in **Sonnet**; **does not** run another verification round on the *same* already-verified save. **Who** drafts the next sub-step, commit flow, or paste-only work follows **§13 Beat handoffs**—not an extra `grep` loop on the same closed step.
   * **❌ Fix** — identifies what's wrong, drafts a fix-prompt for Cursor. The fix-prompt follows the same one-sub-step discipline; "fix A and B" chains and is not allowed.

4. **Model routing after audit:** The pasted output in step 2 is evaluated in the session’s current model. When the verdict is **✅** and the sub-step is **done** (any ❌/fix loop finished), the **up-hand** in **§13 (Sonnet → Opus)** applies unless the *only* next work is an **Opus → Sonnet** down-hand. Do not request redundant `wc` / `shasum` / `cat` for a save **already** closed with ✅; do not author the *next* Opus-scoped **§8e.1** in Sonnet.

### 8e.1 Sub-step prompt template (Claude Code → Cursor)

**Chat-safe formatting:** Sub-step headers (e.g. `D6.1 — Cursor prompt (**§8e.1**):`) and the filled template use **Markdown only** — `**…**` for emphasis, `§8e.1` in plain text or backticks as needed. **Do not** paste HTML from `CLAUDE.md` or the stage plan: chat UIs (and many paste targets) do not render `<span>`/`<b>` and will show raw tags. For a single copyable code block in the editor preview (e.g. one **CURSOR PROMPT** fence plus a separate **USER VERIFY** fence in `STAGE_D_*_PLAN.md` or a notes file), wrap each block in a contiguous ` ```text ` … ` ``` ` fence; use Markdown-style emphasis in chat, or the same `**…**` tokens as literal text inside the fence if the pasted file must show bold.

Every Cursor-targeted execution prompt drafted by Claude Code uses the two-block shape below. The blocks go to different destinations: the **CURSOR PROMPT** block is handed to Cursor verbatim; the **USER VERIFY** block is run by the user in their terminal *after* Cursor's save. Cursor never sees the USER VERIFY block. The divider between them is literal and required. If a field does not apply, Claude Code writes `none` explicitly rather than omitting it.

```
### CURSOR PROMPT — paste to Cursor verbatim; Cursor only

Plan ref: <stage><step> e.g. D3.2
Plan lines: STAGE_D_PLAN.md:L<from>-L<to>
Goal: <one sentence, no tradeoffs, no alternatives>
Instruction: Do exactly this and only this. Save the file(s) and stop.
             Do not run any shell command — no forge, no git, no slither,
             no bash. If a tool offers to run one, decline.
Files: <path> (create | edit)
<path> (create | edit)
Must match: - <signature / import / pragma / constant / invariant>
- <...>
Out of scope: - <explicit exclusions; "while we're here" candidates>
- <adjacent edits the user or Cursor might be tempted to make>
Stop after: <exact final state; last file saved; no commit, no build, no advance>

### USER VERIFY — run in the user's terminal after Cursor's save; not part of the Cursor prompt

clear
wc -l <path>
shasum -a 256 <path>
cat <path>
grep -c "—" <path>
<plus any step-specific grep from the plan>
```

Rules governing the template:

* **Two blocks, one divider.** The `### CURSOR PROMPT` and `### USER VERIFY` headers appear verbatim in every filled template. The divider keeps shell commands structurally outside the Cursor-facing payload — the fence in `Stop after` was being undercut when a wall of `$` lines sat three lines below it. See **D31** in `docs/STAGE_D_NOTES.md`.
* **One sub-step per prompt.** Chaining (`D3.2 and D3.3`) is the precise failure mode §6 outlaws; the template has one `Plan ref` field, singular.
* **`Instruction` is required and fixed text.** Both sentences must appear verbatim on every handoff — the `Do exactly this and only this. Save the file(s) and stop.` scope checksum *and* the `Do not run any shell command — no forge, no git, no slither, no bash. If a tool offers to run one, decline.` anti-action clause. Paraphrasing either weakens the forcing function. `Instruction` complements `Out of scope` and `Stop after`; it does not replace them.
* **`Must match` is the contract.** Every bullet is a property Cursor can check against the saved file without interpretation. No soft guidance ("try to keep it short"), no style notes that aren't load-bearing.
* **`Out of scope` is not optional.** If Claude Code cannot name at least one plausible scope-creep risk, the sub-step is probably too large — split it in the plan before prompting.
* **`Stop after` ends at file-save.** Build, test, lint, slither, git are user-terminal actions per **§8a** / **§8b**, not Cursor actions per §7.
* **`USER VERIFY` lines live outside the Cursor prompt.** They are the literal strings the user will run, under a header Cursor never reads. Not a description, not a suggestion — the exact shell line, paste-ready for zsh/bash, with no shell-prompt prefix (no leading `$`). Every USER VERIFY block begins with `clear` on its own line, so the terminal starts fresh and the pasted-back audit output is easy to isolate. Claude Code does not include `forge`, `slither`, or `git` mutations in this block unless the plan explicitly calls for them at this sub-step; verification defaults to read-only file inspection (`wc`, `shasum`, `cat`, `grep`, `git show`, `git diff`, `git status`).
* **`Must match` is grounded in branch state.** Draft those bullets from `git show <branch>:<path>` (e.g. `git show stage-d:src/fee_router/AureumFeeRoutingHook.sol`) or from a cwd confirmed to be the main checkout — not from a possibly stale worktree file, not from chat memory or a prior-session summary. See **D18** and **D21** in `docs/STAGE_D_NOTES.md`.

Claude Code does not add *ad-hoc* fields beyond this shape. The only top-level fields in the CURSOR PROMPT block are: `Plan ref`, `Plan lines`, `Goal`, `Instruction`, `Files`, `Must match`, `Out of scope`, and `Stop after`. `Verify` is no longer a field of the CURSOR PROMPT block; the verify commands live in the USER VERIFY block below the divider. Extra fields invite prose, and prose invites Cursor to plan.

### Why this division

* **Token economics.** Cursor is a subscription-paid tool the user already owns; routing content generation through it avoids metered-API consumption on large file content. Claude Code's token budget goes to planning and auditing, which is where its multi-step reasoning is most valuable.
* **Safety.** Cursor's generation and Claude Code's auditing are independent failure surfaces. If Cursor generates wrong content, Claude Code catches it at audit. If Claude Code's plan is wrong, Cursor's scope-stopping behavior (and the user) catches it before damage compounds. Either failure alone is visible; both would have to happen the same way at the same time to slip through.
* **Progress discipline.** The 2026-04-19 planning failure demonstrated that Claude Code in a pure-planning role without a forcing function chases its tail. The forcing function is Cursor's executor cycle: each prompt must be small enough for Cursor to execute in one pass, which forces Claude Code to commit to concrete next steps rather than re-scoping indefinitely.

### Git mutations

The user runs all `git add`, `git commit`, `git push`, `git tag` in their own terminal. Claude Code drafts the exact commands (including full commit message) and confirms expected `git status` state before and after. Neither Claude Code nor Cursor runs git mutations. All terminal command blocks that Claude Code drafts for the user — including git command sequences — begin with `clear` on its own line, for the same reason as USER VERIFY blocks: the terminal starts fresh and paste-back output is easy to isolate. When a ✅ audit verdict closes a sub-step that warrants a commit, Claude Code emits the commit as a single text-fenced code block containing the full paste-ready sequence — `clear`, then `git add <paths>`, then `git commit -m "<message>"`, then `git log --oneline -3`, then `git status -sb` — never as the bare commit-message string alone. The bare message forces the user to reconstruct the `git add` and verification lines from memory, undermining the same paste-and-go ergonomics that the USER VERIFY two-block rule was written to preserve.

---

## 9. Why the rules exist — the C14 lineage of incidents

### C14 — Cursor autonomous execution (2026-04-17)

Cursor was in Auto-Run Mode with a permissive command allowlist. During what should have been a chat-directed Stage C5 step (record AuMM design in `STAGE_C_NOTES.md`), Cursor executed the step autonomously — generating the notes content itself and committing without chat-level direction. The commit was reasonable content but the process was wrong: no chat instruction, no verification loop, no opportunity to check the content matched the C5 design spec.

Logged as **C14** in `docs/STAGE_C_NOTES.md`. Immediate fix: Cursor's Auto-Run set to "Ask Every Time," command allowlist emptied, added the "Cursor operation scope during active chat-directed work" section to `.cursorrules` at commit `fcde1b0`.

### Mini-incident — Cursor stub-invention (2026-04-18, earlier)

The user asked Cursor (text-editor-only mode) to edit `docs/STAGES_OVERVIEW.md` by adding three bullets at three specific anchors. Cursor found the file didn't exist in the repo (it had been living only in project knowledge), and instead of reporting "file not found, stopping," *created* a new file with a stub of the anchor context plus the three bullets. Wrong content, but caught at the next `git diff` because the lockdown prevented auto-commit. Fix: `rm` the stub, sync the real `STAGES_OVERVIEW.md` from project knowledge into the repo, apply the three bullets to the real file as a separate commit.

### Mini-incident — Claude Code self-verification gap (2026-04-18, later)

During C6.2, Claude Code wrote `src/token/AuMM.sol` via its `Write` tool. Claude Code's own follow-up was a `wc -l` line count plus a "head and tail match" claim, and it proposed proceeding directly to C6.3 without a full read-back. The user caught the gap and ran `cat src/token/AuMM.sol` from their own terminal against the approved draft — the file was byte-perfect, but the verification gap was the point. A self-check by the writing tool is not the same as an external read-back. Fix: section 6 now explicitly requires terminal-side read-back for every write; **section 8e** eliminates Claude Code writes entirely.

### The principle

**Autonomous helpfulness by AI tools is a failure mode in this repo.**

Agentic tools — Cursor Composer, Claude Code with loose allowlists, any "write file and move on" combined action — treat forward progress as the goal. They generate plausible next-steps ahead of direction. Most of the time those next-steps are correct-looking; occasionally they are wrong; the user cannot tell which without reading the diff. When the protocol will hold real money post-Stage R, "occasionally wrong" is not acceptable.

Three data points in three days, same underlying pattern: **AI tools default to self-verification even when given instructions to the contrary, and default to making progress when stopping-and-reporting would be the more disciplined move.** The cure is structural: separate the tool that acts from the tool that verifies. That is what sections 6, 7, and **8e** now encode.

---

## 10. Writing register and commit-message conventions

### Prose register

Match the register of the existing stage plans. Characteristics:

* Dense, declarative, precise. No marketing voice, no hedging with "potentially" / "might" / "could possibly" where a direct statement fits.
* Em-dashes (`—`, Unicode U+2014), not double-hyphens, not hyphen-minus. The whole codebase uses em-dashes; stay consistent.
* No emojis. No decorative formatting. Lists when lists clarify, prose when prose clarifies.
* Code in backticks. File paths in backticks. Cross-references as `OQ-N` / `C-Dn` / `§xxix` (section 5).
* Assume the reader is a competent protocol engineer. Don't re-explain what a pool factory is or what `block.number` means. Do explain Aureum-specific decisions (why F2, why one-shot setter, why no `_update` override).

### Commit-message conventions

Two families:

**1. Plan sub-step commits.** Format: `<stage><step>: <specific change>`. The stage plan specifies the exact message for each numbered sub-step — use it verbatim. Examples:

* `C3: src/lib/AureumTime.sol`
* `C6.1: src/token/IAuMM.sol — interface for AuMM ERC-20 (per C5.2)`
* `C7: test/unit/AuMM.t.sol — cap, minter, halving, invariants`

When the plan specifies a message, it is canonical. Don't rephrase.

**2. Ad-hoc commits** (planning-doc edits, cursorrules updates, tooling). Format: `<category>: <change>`. Categories: `docs:`, `cursorrules:`, `foundry:`, `tooling:`. Examples:

* `docs: sync STAGES_OVERVIEW.md + FINDINGS.md into repo (verbatim from project knowledge)`
* `docs: add Argot Collective tooling to Stages P, Q, R (hevm, Act, Sourcify)`
* `cursorrules: add Cursor operation scope rule (text-editor only during chat-directed work)`

### Commit discipline

One logical change per commit. Don't sweep unrelated files into `-a`. Don't mix planning-doc edits with code changes. If in doubt, split — `git reset HEAD~ && git add -p` is cheap.

After every commit, verify with `git log --oneline -N` where N covers the commit plus enough prior commits to confirm the branch position. For non-trivial commits, also `git status -sb` to confirm no leftover staged or modified files.

---

## 11. Current state and how to resume

This section is the resumption anchor. Update at the end of every completed sub-step.

**Last update:** 2026-05-05, **Stage F COMPLETE** at `stage-f-complete` (commit `9751378`, 2026-05-04). Stage F delivered the **CCB (Compound Centrifugal Balance) scoring engine** — four contracts under `src/ccb/` plus four interface files: **`EMASampler.sol`** (F-4 per-pool TVL EMA, alpha = 2/61, daily cadence per OQ-5a-bis, F-D15 cold-start sentinel); **`CCBScore.sol`** (F-5 pure-math `tvlEMA × multiplier / 1e18` via FixedPoint.mulDown); **`CCBShare.sol`** (F-6 pure-math share normalization to 1e18 via FixedPoint.divDown, EmptyScores / AllScoresZero reverts); **`CCBMultiplier.sol`** (F-8 stateful per-pool M_i engine, clamp `[0.75e18, 1.25e18]`, ±0.05 per-channel step, OQ-23 v.d boost-gate-and-pause composition, F-D24 activateBoost M_i reset, F-D25 arithmetic-base sentinel, parallel one-shot seal pattern via `IMiliariumRegistry` + `IGaugeRegistry` injection per F-D20–F-D23). Interfaces: **`ITVLOracle`** (TVL oracle injection per OQ-22), **`IMiliariumRegistry`** (Miliarium membership lookup per F-D9), **`IGaugeRegistry`** (gauge-approved caller gate per F-D17), **`IEMASampler`** (read-only EMA view per F-D22). Mocks: **`test/fork/mocks/CCBMocks.sol`** (`MockTVLOracle`, `MockMiliariumRegistry`, `MockGaugeRegistry`). Test suite: **263/263 green** on mainnet fork (247 unit + 16 fork) via D35 split-form invocation. Mid-stage OQ resolutions — **OQ-22** (TVL denomination = svZCHF, RP-aware unwrap + constellation-spot averaging; concrete oracle deferred), **OQ-5a-bis** (spot-per-day read, cumulative accumulator dropped, no `AureumFeeRoutingHook` modification), **OQ-23** (i.a per-channel ±0.05 discrete step; ii.c both-channel dead zone; iii.b sum-of-EMAs; iv.a simple-mean-28; v.d boost-gate-and-pause); F-D7 + F-D8 superseded by OQ-23 (v.d). Stage findings — **F10** (Solidity optimizer hoists `block.number` out of `vm.roll`-driven loops; counter-variable fix), **F11** (chat paste-rendering auto-links TLD-suffix tokens; shasum + null-grep authoritative), **F12** (int/uint type-discipline standard for signed delta-channel arithmetic). Vault bytecode untouched — zero edits to `lib/balancer-v3-monorepo/`. **Next: Stage G — gauge state machine (Opus high entry); plan to be authored.**

**Branch:** `main` at the F5.3 CLAUDE.md §11 refresh commit (HEAD) following FF merge from `stage-f`; `stage-f-complete` lightweight tag at `main` HEAD~2 = `9751378` (with F5.2 docs commit `81c2881` between). `stage-f` branch preserved on `origin` as a snapshot per the C0 / D0 / E-D8 convention.

Recent commit stack on `stage-f` through tag target `9751378` (the F5.2 + F5.3 close-docs commits on `main` HEAD sit above):

- `9751378` — F5.1: docs/STAGE_F_PLAN.md — Completion Log catch-up (F2.3 → F3.4-fix2, 29 rows; F4.4 verification closure)
- `7eea202` — F3.4-fix2: test/unit/CCBMultiplier.t.sol — 28-pool divisor fix for globalFalling/intraBelow tests + F-D27 (STAGE_F_NOTES.md)
- `cf8f7b4` — F4.3c: test/fork/CCBEngine.t.sol — CCBEngineCompositionTest (F-6 shares identity + F-D26 (f) deltaIntra direction)
- `be0e8c2` — F4.3a: test/fork/CCBEngine.t.sol — CCBEngineEMAPathTest (F-D15 cold-start sentinel + F-4 smoothing)
- `9bc712a` — F4.2b: test/fork/CCBEngine.t.sol — setUp + Bodensee/pilot helpers + CCB engine wiring (F-D23 seal, per F-D26 (a))
- `fb70676` — F4.2a: test/fork/CCBEngine.t.sol — CCBEngineFixture abstract base (constants, state, imports; per F-D11 / F-D26 (a))
- `c828daf` — F4.2-pre-fix: docs/STAGE_F_PLAN.md — three-arg CCBMultiplier constructor, placeholder + F-D23 seal wiring

Earlier Stage F commits (F0 scaffold + OQ-22 / OQ-5a-bis / OQ-23 resolutions, F1 EMASampler + interface + tests, F2 CCBScore/CCBShare libraries + tests, F3.1–F3.3 CCBMultiplier scaffold + constructor + activateBoost + updateMultiplier + getMultiplier with F-D15–F-D25 design decisions, F3.4-fix expanded unit tests, F4.0–F4.1 NOTES scaffolds + mocks; close-docs F5.2 + F5.3 above tag) live in `git log stage-f ^26178db` (branch point) up to F5.3 main HEAD. Full Completion Log in `docs/STAGE_F_PLAN.md`.

**Current tag:** `stage-f-complete` (commit `9751378`, 2026-05-04). Next expected tag: `stage-g-complete` at Stage G close. `stage-e-complete` (`41a7590`, 2026-04-28), `stage-d-complete` (`951c338`, 2026-04-25), `stage-c-complete` (`5342126`, 2026-04-18), `stage-b-complete`, and `stage-a-complete` remain in place upstream.

**Stage F position:** **COMPLETE.** Sub-step roll-up: F0 plan/notes scaffold + OQ-22 / OQ-5a-bis / OQ-23 resolutions → F1 EMASampler (interface + contract + tests + F10 fix) → F2 CCBScore + CCBShare (libraries + tests) → F3 CCBMultiplier (interfaces + scaffold + constructor + activateBoost + updateMultiplier + getMultiplier; F3.4-fix + F3.4-fix2 expanded unit-test coverage) → F4 fork integration test (mocks + fixture + EMA-path / boost-lifecycle / composition tests) → F5 docs (Completion Log catch-up, status header, STAGES_OVERVIEW row, this CLAUDE.md §11 refresh) → F9 close (FF merge to `main`, tag `stage-f-complete`, push). Per-sub-step detail in `docs/STAGE_F_PLAN.md` Decisions table (F-D1 through F-D14 entry-time + mid-stage F-D15 through F-D27) + `docs/STAGE_F_NOTES.md` F-D-numbered findings (notably **F-D15** EMASampler cold-start sentinel, **F-D17** boost re-entry / one-shot setter, **F-D19** anti-cyclical polarity, **F-D20–F-D23** parallel one-shot seal pattern, **F-D24** activateBoost M_i reset, **F-D25** updateMultiplier arithmetic-base sentinel, **F-D26** F4 harness scope + 3-pool divisor-28 fork artifact, **F-D27** 28-pool registry rule for delta-channel direction unit tests) and F-numbered findings (**F10** optimizer-hoist on `block.number`, **F11** TLD-suffix paste-rendering non-issue, **F12** int/uint signed-delta type discipline).

**Deferred (post-Stage F carry-forward):**

- **OQ-22 concrete oracle implementation.** `ITVLOracle` interface shape pinned at F0.2 (svZCHF numéraire, RP-aware unwrap + constellation-spot averaging); concrete oracle implementation deferred to OQ-22 resolution stage — likely Stage G or pre-Stage-H, before live emissions. Stage F integration tests use `MockTVLOracle` per F-D11.
- **OQ-20 / OQ-21.** Controller yield-fee entry point + bi-weekly cadence; per E-D10 not yet resolved. Per-token `paysYieldFees: true` flags in pilot configs are forward-compatible with the eventual controller entry point and cadence.
- **D33 — Aureum's own Router.** Re-entry at Stage K (governance handoff) or Stage O (integration). Full options list in `balancer_v3_reference.md` "Open architectural question — Aureum's own Router."
- **D36 permanent fix.** Env-key namespacing in `test/fork/DeployAureumVault.t.sol` (or eliminating `vm.setEnv` from fork tests entirely); Stage E + Stage F pilot tests are race-safe via E-D24 in-process pattern + same-value env-write convention; `--threads 1` cross-suite belt remains for legacy Stage D fork tests writing `FEE_ROUTING_HOOK` to conflicting addresses.
- **aumm-site spec edits (user-side).** `04_tokenomics.md` §ix prose amendments per OQ-20 + OQ-21; not a repo edit.

**Next stage: Stage G — gauge registry + eligibility.** **Auto-gauge pivot** locked in `docs/STAGE_G_PRECHECK_AUTO_GAUGE.md` + `docs/STAGE_G_NOTES.md`; OQ-G1–G4 in `docs/FINDINGS.md`. Stage G plan not yet authored — entry per §13 Stage-level defaults: **Opus high**.

Loop grep-and-confirm per §6 / §8e Audit cycle; all git mutations run in user's terminal; Cursor is executor-only per §7 + §8e.

### Housekeeping notes

* `.cursorrules` was amended on 2026-04-19 to replace the "text-editor only" lockdown with the "Cursor operation scope — executor under Claude Code planning" section. Respect it.
* Cursor Auto-Run stays "Ask Every Time," Command Allowlist stays empty, Browser / MCP / File-Deletion / External-File Protection toggles stay on.
* **Claude Code does not write files.** All file writes flow through Cursor. Claude Code plans, authors prompts, audits Cursor's output, drafts commit messages and terminal commands for the user.
* Git mutations (`add`, `commit`, `push`, `tag`) are run by the user in terminal, not by Claude Code or Cursor.
* External canonical spec lives at `https://github.com/aummfi-bit/aumm-site` (default branch `main`). Claude Code reads it directly via WebFetch on raw URLs (e.g. `https://raw.githubusercontent.com/aummfi-bit/aumm-site/main/11_formulas.md`). When a plan or notes reference requires spec text, fetch directly; ask the user to paste only if WebFetch fails or the section is ambiguous. See §4 for the full layout.
* **§8e.1 template is two blocks.** Every filled §8e.1 has a `### CURSOR PROMPT — paste to Cursor verbatim; Cursor only` block and a separate `### USER VERIFY — run in the user's terminal after Cursor's save; not part of the Cursor prompt` block. Cursor never sees USER VERIFY. USER VERIFY and all terminal command blocks (including git sequences) begin with `clear` on their own line. **When Claude Code emits a filled §8e.1 in chat, the two blocks must be in two physically separate ` ```text ``` ` code fences — never a single combined fence — so the user's paste to Cursor cannot accidentally include the USER VERIFY shell commands.** When the same template is pasted into a stage-plan or notes file for editor-preview rendering (per the §8e.1 chat-safe-formatting paragraph hardened at `8197aaa`), each block is also wrapped in its own contiguous ` ```text ``` ` fence so the preview keeps each block as a single copyable unit. See §8e.1 + D31.
* **`.cursorrules` USER VERIFY hard-stop (`5f3b4fc`).** Defense-in-depth on top of the §8e.1 two-block split: if any prompt passed to Cursor contains the literal text `### USER VERIFY`, Cursor must treat everything from that header to end-of-message as out of scope, report "USER VERIFY section detected — treating as out of scope per .cursorrules", and proceed only on the content above. Catches paste accidents where the user copies past the divider.
* **§13 Sonnet dispatch is not session-scoped.** Every filled §8e.1 turn must close with the Sonnet dispatch line per §13's "Relay after a §8e.1 draft" — across sessions, resumes, and compactions. If Claude Code forgets, user says "mode?" and Claude Code emits the dispatch.
* **Cursor backtick-stripping in plan-doc rewrites.** At D32 follow-up §D7.1e plan rewrite (2026-04-24, `fbdef2f`), Cursor stripped all backtick characters from the replacement paragraph when given a code-block-delimited replacement text. Fix required explicit "backtick characters are literal; do not strip" in the Instruction plus spot-check grep of backtick-wrapped strings in Must match. Watch for this pattern when rewriting paragraphs with many inline code references.
* **Stage D — `IVault.unlock` inner callbacks** (`AureumFeeRoutingHook` and the same pattern elsewhere): when the outer caller uses `abi.decode(result, (uint256))`, the inner must `returns (uint256)`, not `returns (bytes memory)` with `abi.encode` — see **D22** in `docs/STAGE_D_NOTES.md`.
* **D24 — Cursor autonomous-scope expansion in D4.5** (`cc2623b`): sub-step prompts must state the scope boundary explicitly, and Cursor audit output must be compared against that boundary.
* **D31 — Cursor autonomous-action expansion in D7.0** (structural resolution in `60a1d03` + `f898946` + `348d038`): Cursor ran `forge build` against four scope fences; structural fix was the §8e.1 two-block split removing shell-command priming from the Cursor payload. See **D31** in `docs/STAGE_D_NOTES.md`.
* **D32 — Router single-vault immutable binding + Permit2 chain** (2026-04-24, `715cd93` + `fbdef2f`): mainnet Balancer V3 Router is bound to mainnet Vault, cannot call Aureum pools; Permit2 is a two-step approval chain, not plain ERC-20 approve. Fork init uses (β) pattern `Vault.unlock` + `IVault.initialize` + per-token `transfer` + `settle`, no Router, no Permit2. See **D32** in `docs/STAGE_D_NOTES.md` and `balancer_v3_reference.md` §1.
* **D34 — D4 execution gap (β1 controller-side per D17 L170 missed at D4)** (2026-04-24, `4a37c36` + `2d5bcdc` + `a1c358a` + `5f4e1db` + `7a296c1`): hook-side β1 (D3 scope) landed cleanly; controller-side β1 (D4 scope at L170 — `collectSwapAggregateFeesForHook` selector) was missed; surfaced at D7.2 first attempt as `unrecognized function selector 0x9992fceb`; closed via §D4.7 corrective sub-step. Pattern: D17-class architecture specs that enumerate paired surfaces (hook + controller) need cross-side selector / interface assertions in unit tests, not just behavioural assertions. See **D34** in `docs/STAGE_D_NOTES.md`.
* **D35 — Ankr RPC rate-limit hang on global `--fork-url`** (2026-04-25, `b225ba5`): `forge test --fork-url $URL` without `--match-path` filter applies fork context to all 200+ tests; on Ankr free-tier the resulting rate-limit hits cause indefinite hang (no test output for 25+ min observed). Split-form (`--no-match-path "test/fork/**"` for unit + `--match-path "test/fork/**" --fork-url $URL` for fork) is the correct invocation pattern; combined wall ~23s for 160/160 tests. See **D35** in `docs/STAGE_D_NOTES.md`.
* **D36 — vm.setEnv race condition between parallel fork test contracts** (2026-04-25, `19d9eda`): `test/fork/AureumFeeRoutingHook.t.sol` L108 and `test/fork/DeployAureumVault.t.sol` L79 both write the shared `FEE_ROUTING_HOOK` env key under default Foundry parallelism; the latter's write occasionally clobbers the former between `vm.computeCreateAddress` and `vaultScript.deploy(...)`'s `vm.envAddress` read at `script/DeployAureumVault.s.sol` L128, causing `aureumFeeController.FEE_ROUTING_HOOK` immutable to receive `0xF86D…3a77` (= `keccak256("feeRoutingHook")` truncated) instead of the test's `hookAddr` and the β1 swap-leg `OnlyFeeRoutingHook` access-control gate to revert. Workaround: `--threads 1` on the Part B fork run, paired with D35's split-form pattern (`forge test --match-path "test/fork/**" --fork-url $MAINNET_RPC_URL -vv --threads 1` confirmed 9/9 green). Permanent fix — env-key namespacing in `test/fork/DeployAureumVault.t.sol` (e.g. `FEE_ROUTING_HOOK_DEPLOY_TEST`) or eliminating `vm.setEnv` from fork tests entirely — deferred to Stage E entry or a pending-findings stub. See **D36** in `docs/STAGE_D_NOTES.md`.
* **E10 — forge-std `deal(adjust=true)` incompatible with Reserve-DTF dynamic-supply tokens (ixEDEL)** (2026-04-27, `393cea0` NOTES + `fd554c1` corrective code): forge-std `deal()` third-argument `adjust=true` writes both holder balance slot and `totalSupply()` slot via heuristic; for tokens with dynamic `totalSupply()` like Reserve DTFs (ixEDEL — fee-decay accrual), no canonical supply slot exists, the supply-adjust path arithmetic-wraps and reverts panic 0x11. Fix: drop the third argument (`deal(token, holder, amount)`) — writes holder balance only, leaves `totalSupply()` untouched; Vault/WeightedPool init reads raw transferred balances, not ERC20 `totalSupply()`. Amends E-D24 (`MiliariumPilotPoolBase._initializePool` mint loop at `test/fork/PilotPools.t.sol` L302) and E-D25 (uniform `INIT_SEED` literals replaced with per-token `1_000 × 10^decimals(token)` for mixed-decimal pilots — ixEdelweiss 6/6/18/18; ixAurebit 18/18/18/8/8 ahead). Same rule applies to any future `_performSwap` with DTF-as-`tokenIn`; current `_performSwap` L324 retains `adjust=true` because the deployed E2 vector (waEthUSDC, 6-dec wrapped stablecoin) is not a DTF. See **E10** in `docs/STAGE_E_NOTES.md` L205+.
* **F10 — Solidity optimizer hoists `block.number` out of `vm.roll`-driven loops** (2026-04-29, `c59422b` NOTES + `7e47283` corrective code at `test/unit/EMASampler.t.sol`): Foundry `vm.roll(target)` updates `block.number`, but Solidity's optimizer at `runs=9999` + `via_ir=true` may treat `block.number` as loop-invariant and hoist its read out of `for`/`while` bodies that conditionally re-read it, producing infinite-loop or stale-cadence behavior in convergence-style tests. Fix: thread an explicit `uint256 currentBlock` counter through the iteration, advance via `vm.roll(currentBlock += BLOCKS_PER_DAY)`, and key loop conditions on the local counter rather than `block.number` directly — the local cannot be hoisted. Default rule for Stage F+ unit tests using `vm.roll` in loops: never key loop iteration on raw `block.number` reads; thread an explicit counter. See **F10** in `docs/STAGE_F_NOTES.md`.
* **F11 — Chat paste-rendering auto-links TLD-suffix tokens** (2026-04-30, surfaced at F2.3-fix non-issue): chat clients auto-link `.ONE` / `.fi` / `.io` / `.md` TLD-suffix identifiers in pasted terminal output — `FixedPoint.ONE` renders as `[FixedPoint.ONE](http://FixedPoint.ONE)` in `grep -n` / `cat` paste-back, but the markdown link **is not in the source file**. Visible text of pasted `grep -n` / `cat` is untrusted; rendering-immune signals are authoritative: `shasum -a 256` (unchanged across a "fix" attempt ⇒ Cursor wrote nothing ⇒ file is correct), `grep -c "http"` (0 ⇒ no link substring in source), `grep -c "\["` (matches the legitimate array-syntax count expected from the file). When Cursor reports "no edit needed" with unchanged shasum, the file is correct — STOP, do not re-prompt. F2.3-fix burned 2 round-trips on a non-issue before the unchanged-shasum + `grep -c "http" = 0` signals were read correctly. Default §8e.1 USER VERIFY for any file containing TLD-suffix tokens: emit `grep -c "http"` as a null-result sentinel alongside `grep -c "\["` — both should match the file's true state, not the rendered text. See **F11** in `docs/STAGE_F_NOTES.md`.
* **F12 — int/uint type discipline in signed delta-channel arithmetic** (2026-05-04, `51e5fab` NOTES + landed code at `src/ccb/CCBMultiplier.sol`): F-8 `delta_global` and `delta_intra_i` are signed quantities (sign indicates direction relative to dead-zone bands), but the `M_i(t-1) + delta_global + delta_intra_i` clamp arithmetic is unsigned `uint256` — naive `M_i + int256(delta)` casting underflows when `delta` is negative. Standard pattern: compute deltas as `int256`, accumulate via an explicit signed-add helper that branches on sign, cast back to `uint256` only after the clamp band has been re-applied. Closes the F3.3d-fix verify-gap thread. The standard applies project-wide to any stateful FixedPoint accumulator with signed deltas (Stage H emission accumulators ahead). See **F12** in `docs/STAGE_F_NOTES.md`.

---

## 12. When uncertain, ask

This is the fallback rule that subsumes everything else. If any of the following is true, stop and ask in chat rather than proceeding:

* The plan is ambiguous about the current sub-step.
* An expected file or path doesn't exist.
* A command fails or returns unexpected output.
* An action seems like it might fall into **section 8b, 8c, or 8e** but you're not sure.
* The user said something that contradicts the plan.
* You're about to make an "obviously correct" decision that wasn't explicitly in the plan or the notes.

The cost of asking is a round-trip. The cost of guessing wrong is a rollback plus the time to figure out what was guessed wrong. The grep-and-confirm loop is built on the same principle at the micro-scale; this rule is the same principle at the macro-scale.

## 13. Model governance

### Core principle

Claude Code announces the mode for the next beat. The user flips the switch. No gates, no permission blocks — the announcement *is* the instruction.

Claude Code's job on this project per **§8e** is planning and auditing. That is Opus-high work. Sonnet is for narrow housekeeping windows between Opus beats, not a general default.

### The dispatcher lines (pair)

At every natural transition between **Opus** and **Sonnet**, Claude Code emits **exactly one** of the two lines below, then **stops**—so the user can flip the model before the *next* kind of work. Claude Code does not ask "ready?" and does not chain another dispatch in the same turn.

*Emit the handoff as **plain Markdown in chat** — **never** wrap it in HTML. One line: a leading `✅`, then the **bold** dispatcher sentence as in the bullets (no surrounding `"` / `'` characters — they read as noise in chat). Fill `[X]` / `[Y]` with the label for the next beat (e.g. `A2 (plan §D6 rewrite, replacing L558–L569)`).*

- ✅ **Switch to Opus high — next beat is [X].** — The **up-hand** (see **Beat handoffs**): terminal audits in **Sonnet** for the current sub-step are **closed** with ✅; **X** is the next work unit that requires Opus (next **§8e.1**, non-trivial audit, design, §11 resume update, *etc.*). **Do not** request another `grep`/`cat`/`shasum` for the *same* already-verified save, and **do not** draft the *next* **§8e.1** in Sonnet in that handoff turn.

- ✅ **Switch to Sonnet — housekeeping: [Y].** — The **down-hand** (see **Beat handoffs**): the session is in **Opus** but the **very next** action is **only** a **Sonnet beat** (read-back verdict, commit message text, Completion Log line, mechanical continuation, branch-tip `git show`/`shasum` check, *etc.*). **Y** is a short label for that work. **Do not** perform that housekeeping in Opus—burn the cheap model for paste-and-compare and mechanical drafting.

**[X]** and **[Y]** are always tied to a concrete `Plan ref` (e.g. D5.1) or concrete housekeeping label—not vague filler.

If Claude Code forgets to announce, the user says **"mode?"** and Claude Code answers with one of the two lines.

### Relay after a §8e.1 draft (before audit paste)

When Claude Code’s previous turn was a filled **§8e.1** (or the user is about to hand that prompt to Cursor) and the *immediate* next step is *only* **Cursor** + the template **Verify** block in the user’s terminal — not new design, not a new file draft in chat — the instruction to do that **must** appear in the **same** message as all of the following, not as a follow-up after the user asks “Sonnet or Opus?”:

1. **Model:** **Sonnet** for the user’s next replies until the full verify output is pasted back (or the down-hand to Sonnet was already emitted on the previous turn, in which case this is a one-line confirmation).
2. **Why (one sentence, mandatory):** The next **Opus-high** beat is the **audit** of what Cursor saved; that beat does not start until `Verify` output exists, so the interval is user/executor time — not Opus work. Sonnet holds the channel for the cheap relay. After the paste, **Opus** runs the non-trivial audit (or **Sonnet** only if the sub-step is explicitly Sonnet-scoped per the **Sonnet beats** list and **Opus-high beats**).

Omitting (2) is a discipline failure: it reads as arbitrary model switching, not workflow logic. This rule is not session-scoped — it is a structural process step that must appear verbatim in the same turn as every §8e.1 draft, regardless of how the session was started, resumed, or compacted.

### Beat handoffs (universal, every sub-step)

These rules apply at **any** stage; they are not tied to a single milestone.

- **Sonnet → Opus (up-hand, green light for the next "blast"):** The user **keeps pasting** terminal output in **Sonnet** until the sub-step is **✅** (per **§8e** Audit cycle). **After** that verification pass is **complete** (no further paste needed for *this* sub-step), **Sonnet** replies in **one** turn: brief **✅** summary; if the sub-step closes a work unit, include the plan-prescribed **commit message draft** here (Sonnet beat). Then emit **exactly** ✅ **Switch to Opus high — next beat is [X].** with `[X]` replaced by the real next-beat label, then **stop** (plain Markdown only — no HTML). The *next* **§8e.1** for Cursor, or any judgement-heavy audit, is **[X] on Opus** after the user switches. **❌/fix** rounds stay in Sonnet until the save is actually fixed and re-verified.

- **Opus → Sonnet (down-hand, stop sign back to cheap model):** If **Opus** has finished a planning, authoring, or hard-audit turn and the **next** natural action matches **only** the **Sonnet beats** list below—**no** new design, **no** first line of a new contract/harness, **no** new `D-D*`, **no** non-obvious debugging—**Opus** does **not** do that work. Emit exactly ✅ **Switch to Sonnet — housekeeping: [Y].** and **stop** (plain Markdown only — no HTML). If the next move *would* need judgement, it stays **Opus**; use the **Opus-high beats** list to tell the difference. When in doubt, **Opus** (see **§12**).

- **Redundant verification:** A **✅** on a sub-step is **not** an invitation to request **another** full read-back of the *same* save. Further terminal output in Sonnet is for **new** saves, **❌** fixes, or a **new** sub-step's verify block—not endless re-confirmation of a closed step.

### Opus-high beats (Claude Code calls this before)

- Drafting any sub-step prompt where a design decision is live (any `D-D*` or `OQ-N` unresolved, any interface shape, any new file's first implementation).
- Auditing Cursor's output on a non-trivial save — new contract, interface, hook callback, test file with new harness, anything touching settlement or fee routing.
- Resolving an OQ or authoring a `D-D*` decision.
- Pre-flight on a new stage (reading the plan for the stage, surveying dependencies, drafting the first sub-step).
- Debugging — any failing build or test where the cause is not obvious from the first glance at the output.
- Writing or updating CLAUDE.md §11 resume anchors.
- Stage-level integration points — fork tests, cross-contract wiring, Router/Vault interactions.
- Any point where Claude Code would otherwise guess. If the next move requires judgement beyond mechanical transcription, it is Opus.

### Sonnet beats (Claude Code calls this before)

- **Relay** after a **§8e.1** handoff: receiving the user’s “run Cursor, then paste **Verify**” return — and stating **Sonnet + why** in the *same* message as the handoff, per **Relay after a §8e.1 draft** above.
- Read-back verdict on a clearly-correct Cursor save — `cat` output matches the prompt, em-dash count matches, `forge build` green. Emit ✅ and draft the commit message.
- Drafting commit messages for a sub-step that already has its ✅.
- Updating the `STAGE_X_PLAN.md` Completion Log line after a commit lands.
- Drafting a sub-step prompt that is a mechanical continuation — next named test case in an already-designed test file, next import line, next `D-D*` that was already resolved in a prior beat.
- Reading file state to confirm it matches a branch tip (`git show` / `wc -l` / `shasum` reconciliation).
- Mechanical grep / log output reports where the answer is a paste, not an interpretation.

### Extra-high effort (Opus only, rare)

Claude Code calls for this explicitly: ✅ **Switch to Opus extra-high — [specific hard problem].** (plain Markdown only — no HTML). Used for:

- Pre-flight on a novel stage (F kickoff, H halving math review, K governance handoff design).
- Debugging a failure where Opus-high already tried and did not crack it.
- Writing formal specs at P/Q/R.

One message, then Claude Code calls the drop back to Opus-high or Sonnet.

### Stage-level defaults (entry mode at stage start)

| Stage | Entry mode | Drops to Sonnet for |
| --- | --- | --- |
| D (current — post-architecture) | Opus high | Read-backs on mock saves, commit drafts |
| E | Opus high entry, then mostly Sonnet | Scaffolding, config |
| F (CCB) | Opus extra-high entry, then Opus high | Test harness boilerplate only |
| G | Opus high | Gauge-weight test writing |
| H (emission) | Opus extra-high entry, then Opus high | N/A — stay on Opus through halving logic |
| I (AuMT) | Opus high | LP-receipt test writing |
| J (registry) | Sonnet entry, Opus for interface design | Most of stage |
| K (governance handoff) | Opus extra-high | Nothing — stay on Opus |
| L (incendiary) | Opus high | Test writing after design is set |
| O (governance modules) | Opus high | Scaffolding |
| P / Q / R (formal verification) | Opus extra-high | Nothing — stay on Opus |

Stages A, B, C are complete. From Stage D onward, Claude Code announces mode at entry and at each natural beat within the stage.

### Token discipline (real levers, not ceremony)

- Read line ranges, not whole files, once the region is known.
- Do not re-read a file already in context this session.
- For "where is X referenced" across more than three files, spawn Explore — its context stays out of the main thread.
- Trust CLAUDE.md §11 as the resumption anchor. Do not re-read full plan + full NOTES on session start; read the named sub-step + the named file regions.
- The **§8e.1** template is the forcing function against re-scoping. Use it verbatim.
