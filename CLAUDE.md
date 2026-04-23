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
│   ├── FINDINGS.md               — resolved + deferred open questions, OQ-1 through OQ-19
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
| `docs/FINDINGS.md` | All 19 resolved Open Questions (OQ-1 through OQ-19) plus deferred items. Cross-referenced constantly from stage plans |
| `docs/STAGE_X_PLAN.md` | Per-stage detailed plan: numbered sub-steps, time estimates, commands, tests, completion log |
| `docs/STAGE_X_NOTES.md` | Per-stage living design-decision log + findings log |
| `docs/balancer_v3_reference.md` | Balancer V3 substrate working notes |
| `.cursorrules` | Cursor editor conventions + the "Cursor operation scope — executor under Claude Code planning" rules |

### Project-knowledge-only (invisible to Claude Code)

These files exist in the `claude.ai` project sidebar but **are not in the repo**. Claude Code cannot read them directly.

* **`aumm-specs.md`** and the **18 numbered spec docs** (`01_intro.md`, `02_*.md`, ..., `18_*.md`), plus the **28 pool-profile documents**. These are the protocol's canonical specification: tokenomics (§ix in `04_tokenomics.md`), constitution (§xxix in `10_constitution.md`), formulas F-0 through F-10 (`11_formulas.md`), bootstrap rules (`08_bootstrap.md`), appendices (`13_appendices.md`).

When a stage plan says "read `11_formulas.md` F-7" or "per §xxix in `10_constitution.md`" — Claude Code does not have these files. The correct move is to **ask the user to paste the relevant section into chat**, not to guess or fabricate the content. FINDINGS.md often quotes or summarises the relevant spec passages; check there first.

---

## 5. Cross-reference conventions

The plan and notes files use short reference codes. Know them on sight.

* **`OQ-N`** — Open Question N from `docs/FINDINGS.md`. Example: `per OQ-5` means "see OQ-5 in FINDINGS.md" — typically a resolved canonical constant or a settled architectural choice.
* **`C-Dn`** — Planning-stage design decision n from `docs/STAGE_C_PLAN.md` (similarly `B-Dn` for Stage B, `D-Dn` for Stage D, etc.). These are the *choices* made while writing the plan, before implementation. Example: `per C-D12` means "see decision C-D12 in STAGE_C_PLAN.md."
* **`Cn`** (two-digit, like `C10`, `C11`, `C14`) — Implementation-stage finding n from `docs/STAGE_C_NOTES.md`. Numbered from 10 to avoid collision with the `C-D*` planning codes. Example: `C14` is the Cursor autonomous execution incident (section 9).
* **`F-n`** — Formula n from `aumm-site/11_formulas.md` (project-knowledge-only). Example: `F-0 piecewise bootstrap emission decay`.
* **`§xxix`** — Section xxix in an `aumm-site` numbered spec. Project-knowledge-only.
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
   * **✅ Proceed** — confirms the sub-step landed clean; drafts the commit message if the sub-step closes a plan-defined work unit when that is **Sonnet-scoped** housekeeping (see **§13 Sonnet beats**). **Does not** draft the *next* **§8e.1** prompt in **Sonnet**; **does not** run another verification round on the *same* already-verified save. **Who** drafts the next sub-step, commit flow, or paste-only work follows **§13 Beat handoffs**—not an extra `grep` loop on the same closed step.
   * **❌ Fix** — identifies what's wrong, drafts a fix-prompt for Cursor. The fix-prompt follows the same one-sub-step discipline; "fix A and B" chains and is not allowed.

4. **Model routing after audit:** The pasted output in step 2 is evaluated in the session’s current model. When the verdict is **✅** and the sub-step is **done** (any ❌/fix loop finished), the **up-hand** in **§13 (Sonnet → Opus)** applies unless the *only* next work is an **Opus → Sonnet** down-hand. Do not request redundant `wc` / `shasum` / `cat` for a save **already** closed with ✅; do not author the *next* Opus-scoped **§8e.1** in Sonnet.

### 8e.1 Sub-step prompt template (Claude Code → Cursor)

**Chat-safe formatting:** Sub-step headers (e.g. `D6.1 — Cursor prompt (**§8e.1**):`) and the filled template use **Markdown only** — `**…**` for emphasis, `§8e.1` in plain text or backticks as needed. **Do not** paste HTML from `CLAUDE.md` or the stage plan: chat UIs (and many paste targets) do not render `<span>`/`<b>` and will show raw tags.

Every Cursor-targeted execution prompt drafted by Claude Code uses the fixed
shape below. Cursor receives a filled template, not prose. If a field does
not apply, Claude Code writes `none` explicitly rather than omitting it.

```
Plan ref: <stage><step> e.g. D3.2
Plan lines: STAGE_D_PLAN.md:L<from>-L<to>
Goal: <one sentence, no tradeoffs, no alternatives>
Instruction: Do exactly this and only this.
Files: <path> (create | edit)
<path> (create | edit)
Must match: - <signature / import / pragma / constant / invariant>
- <...>
Out of scope: - <explicit exclusions; "while we're here" candidates>
- <adjacent edits the user or Cursor might be tempted to make>
Stop after: <exact final state; last file saved; no commit, no build>
Verify: $ wc -l <path>
$ shasum -a 256 <path>
$ cat <path>
$ grep -c "—" <path>
<plus any step-specific grep from the plan>
```

Rules governing the template:

* **One sub-step per prompt.** Chaining (`D3.2 and D3.3`) is the precise
  failure mode §6 outlaws; the template has one `Plan ref` field, singular.
* **`Instruction` is required and fixed text.** The line
  `Instruction: Do exactly this and only this.` must appear verbatim on every
  handoff — a scope checksum, not paraphrased. It complements `Out of scope` and
  `Stop after`; it does not replace them.
* **`Must match` is the contract.** Every bullet is a property Cursor can
  check against the saved file without interpretation. No soft guidance
  ("try to keep it short"), no style notes that aren't load-bearing.
* **`Out of scope` is not optional.** If Claude Code cannot name at least
  one plausible scope-creep risk, the sub-step is probably too large — split
  it in the plan before prompting.
* **`Stop after` ends at file-save.** Build, test, lint, slither, git are
  user-terminal actions per **§8a** / **§8b**, not Cursor actions per §7.
* **`Verify` commands are the literal strings the user will run.** Not a
  description, not a suggestion — the exact shell line, so the user can
  paste without editing.
* **`Must match` is grounded in branch state.** Draft those bullets from
  `git show <branch>:<path>` (e.g. `git show stage-d:src/fee_router/AureumFeeRoutingHook.sol`)
  or from a cwd confirmed to be the main checkout — not from a possibly stale
  worktree file, not from chat memory or a prior-session summary. See **D18** and
  **D21** in `docs/STAGE_D_NOTES.md`.

Claude Code does not add *ad-hoc* fields beyond this shape. The only
top-level fields are: `Plan ref`, `Plan lines`, `Goal`, `Instruction`, `Files`,
`Must match`, `Out of scope`, `Stop after`, and `Verify`. Extra fields invite
prose, and prose invites Cursor to plan.

### Why this division

* **Token economics.** Cursor is a subscription-paid tool the user already owns; routing content generation through it avoids metered-API consumption on large file content. Claude Code's token budget goes to planning and auditing, which is where its multi-step reasoning is most valuable.
* **Safety.** Cursor's generation and Claude Code's auditing are independent failure surfaces. If Cursor generates wrong content, Claude Code catches it at audit. If Claude Code's plan is wrong, Cursor's scope-stopping behavior (and the user) catches it before damage compounds. Either failure alone is visible; both would have to happen the same way at the same time to slip through.
* **Progress discipline.** The 2026-04-19 planning failure demonstrated that Claude Code in a pure-planning role without a forcing function chases its tail. The forcing function is Cursor's executor cycle: each prompt must be small enough for Cursor to execute in one pass, which forces Claude Code to commit to concrete next steps rather than re-scoping indefinitely.

### Git mutations

The user runs all `git add`, `git commit`, `git push`, `git tag` in their own terminal. Claude Code drafts the exact commands (including full commit message) and confirms expected `git status` state before and after. Neither Claude Code nor Cursor runs git mutations.

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

**Last update:** 2026-04-23, mid-Stage D, pre-D7 reconciliation complete; D7 next. Stage C remains complete at `stage-c-complete` (commit `5342126`). D0 → D6 landed on `stage-d`.

**Branch:** `stage-d` at `d65a576` (pre-D7 reconciliation complete: `3e6c1c1` reconciliation bundle + `2f80e0c` hash fixup + `d65a576` OQ-21 stub) on top of D6 commit `18f74b9`. `main` is at `e5ceb7a`, unchanged since `stage-d` branched from it at D0. Merge to `main` deferred to D9 per D-D14.

**Current tag:** `stage-c-complete` (commit `5342126`, 2026-04-18). Next expected tag: `stage-d-complete` at D9.

**Stage D position:**

- D0 through D4 — complete; see prior §11 states in git history for sub-step detail.
- D5 — complete (`5905a40` + `06df412`). `test/unit/AureumFeeRoutingHook.t.sol` + `test/unit/AureumProtocolFeeController.t.sol` extensions landed per plan D5.1–D5.3. Mock harness (`MockVault`, `MockRouter`, four `MockERC20`, `MockERC4626` as Bodensee); D5.2 added OQ-11 band constant tests + `FEE_ROUTING_HOOK` immutable assertions. Coverage reconciliation per plan L451–454 complete.
- D6 — complete (`18f74b9`). `script/DeployDerBodensee.s.sol` fork-only per D-D6; see D6 Completion Log for full parameter breakdown. `WEIGHTED_POOL_FACTORY` env is Aureum-bound WPF per D30 — not mainnet Balancer WPF.
- **Pre-D7 reconciliation — complete.** Three commits: `3e6c1c1` (D6 Completion Log + §11 + D29 + D30 + §D7.1 stub + OQ-20); `2f80e0c` (CLAUDE.md §11 hash + FINDINGS.md L368 yield-leg prose fixup); `d65a576` (FINDINGS.md OQ-21 stub — yield-leg routing cadence, `BLOCKS_PER_EPOCH` throttle pinned at D4.6).
- D7 — next. Fork test harness (`test/fork/BodenseeFeeRouting.t.sol` or path pinned at D7 kickoff). First D7 sub-step is `script/DeployAureumWeightedPoolFactory.s.sol` per D30, pending chat-level pins on `FACTORY_VERSION` / `POOL_VERSION` / `PAUSE_WINDOW_DURATION` before the §8e.1 prompt fires. Plan: STAGE_D_PLAN.md §D7.1 stub + D30.
- D8, D9 — not started.

**Open items flagged before D7 execution:**

- **D30 resolution requires new script.** `script/DeployAureumWeightedPoolFactory.s.sol` is named but not yet drafted; first D7 sub-step. Version strings + pause-window sourcing pinned in chat before authoring.
- **OQ-20 / D4.6 deferred.** Controller yield-fee entry point (governance-gated `routeYieldFeeToHook` or equivalent) lands post-D7. D7 tests exercise the hook primitive directly, not the controller entry point.
- **OQ-21 / D4.6 deferred.** Bi-weekly yield-routing cadence via `BLOCKS_PER_EPOCH` (100,800-block) throttle on the D4.6 entry point; per-pool vs. per-(pool, token) vs. mandated internal batch granularity pinned at D4.6 implementation. See FINDINGS.md OQ-21.
- **aumm-site spec edits flagged (user-side).** `04_tokenomics.md` §ix prose needs amendment per OQ-20 (controller collects to itself; hook called via `routeYieldFee`) + OQ-21 (bi-weekly cadence policy); not a repo edit.

**How to resume (Stage D — D7 fork tests):**

1. Confirm current tip: `git log --oneline -1` on `stage-d` matches `d65a576` in §11 (pre-D7 reconciliation complete; OQ-21 deferred to D4.6).
2. Read STAGE_D_PLAN.md §D7 + D7.1 stub, STAGE_D_NOTES.md D29 + D30, FINDINGS.md OQ-20 + OQ-21 + amended L375 row.
3. Claude Code authors the first D7 sub-step prompt — `script/DeployAureumWeightedPoolFactory.s.sol` per D30, under the §8e.1 template, paired with terminal audit commands.
4. Loop grep-and-confirm per §6 / §8e Audit cycle; all git mutations run in user's terminal; all forge / slither runs in user's terminal.

### Housekeeping notes

* `.cursorrules` was amended on 2026-04-19 to replace the "text-editor only" lockdown with the "Cursor operation scope — executor under Claude Code planning" section. Respect it.
* Cursor Auto-Run stays "Ask Every Time," Command Allowlist stays empty, Browser / MCP / File-Deletion / External-File Protection toggles stay on.
* **Claude Code does not write files.** All file writes flow through Cursor. Claude Code plans, authors prompts, audits Cursor's output, drafts commit messages and terminal commands for the user.
* Git mutations (`add`, `commit`, `push`, `tag`) are run by the user in terminal, not by Claude Code or Cursor.
* Project-knowledge-only files (aumm-specs and friends, section 4) are invisible to Claude Code. If a plan or notes reference requires spec text, ask the user to paste the relevant section.
* **Stage D — `IVault.unlock` inner callbacks** (`AureumFeeRoutingHook` and the same pattern elsewhere): when the outer caller uses `abi.decode(result, (uint256))`, the inner must `returns (uint256)`, not `returns (bytes memory)` with `abi.encode` — see **D22** in `docs/STAGE_D_NOTES.md`.
* **D24 — Cursor autonomous-scope expansion in D4.5** (`cc2623b`): during D4.5, Cursor Prompts A and D expanded scope beyond the planned `src/vault/AureumProtocolFeeController.sol` + test file to cover `script/DeployAureumVault.s.sol`, `test/fork/DeployAureumVault.t.sol`, and `.env.example` for the `FEE_ROUTING_HOOK` env wiring. The expansion was kept (the wiring was materially needed) but is logged as a **§8e.1** / Cursor-discipline warning for D5 onward — sub-step prompts must state the scope boundary explicitly, and Cursor audit output must be compared against that boundary.

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

Omitting (2) is a discipline failure: it reads as arbitrary model switching, not workflow logic.

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
