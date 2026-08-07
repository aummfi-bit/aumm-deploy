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
| Compiler | Two profiles (PB-D33 / PB-D34). `[profile.default]` — `solc 0.8.26`, optimizer `9999` runs, `via_ir = true`, EVM `cancun` — all Aureum source, into `out/`. `[profile.vault]` — `solc 0.8.30`, optimizer `500` runs, plus an explicit `optimizer_details` / `yulDetails.optimizerSteps` block — the Balancer vault package only, into `out-vault/`, because `Vault.sol` overruns EIP-170 under the default settings. **Not byte parity** with Balancer's deployed Vault — the prior toolchain-parity claim on this row is WITHDRAWN per PB-D33 / PB-D34; Sepolia needs EIP-170 fit only, and parity rides to the Stage-R submodule-pin bump. Deployed sizes gated by `test/unit/BytecodeSize.t.sol` (PB-D37). |
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
│   ├── STAGES_OVERVIEW.md        — master stage sequence, C through R + the Stage P-bis insert
│   ├── FINDINGS.md               — OQ ledger: OQ-1 through OQ-25 + Stage G addendum OQ-G1–G4
│   ├── ROBUSTNESS_BACKPORT_REGISTER.md — RB-* deferred robustness-backport queue
│   ├── STAGE_X_PLAN.md / _NOTES.md — per-stage plans + notes; Stages A–P complete (current status: §11)
│   ├── STAGE_G_PRECHECK_AUTO_GAUGE.md — Stage G pivot decision record (auto-gauge)
│   ├── balancer_v3_reference.md  — working reference, Balancer V3 substrate notes
│   └── white_hat/                — AUREUM_WHITEHAT_OUTPUT.md (F-nn findings ledger) + AUREUM_WHITEHAT_PROCESS.md
├── src/
│   ├── vault/                    — Stage B (AureumVaultFactory F2, AureumProtocolFeeController, AureumAuthorizer)
│   ├── factory/                  — AureumWeightedPoolFactory (Aureum-owned weighted-pool factory)
│   ├── lib/                      — pure libraries (AureumTime)
│   ├── token/                    — Stage C (AuMM) + Stage I (AuMT)
│   ├── fee_router/               — Stage D
│   ├── ccb/                      — Stage F
│   ├── gauge/                    — Stage G
│   ├── emission/                 — Stage H
│   ├── registry/                 — Stage J
│   ├── governance/               — Stage K + Stage O
│   ├── incendiary/               — Stage L
│   └── rate_provider/            — Stage N (ERC4626RateProvider, CompositeRateProvider)
├── test/
│   ├── unit/                     — per-file unit tests
│   ├── fork/                     — mainnet-fork integration tests (split-form invocation per D35)
│   ├── whitehat/                 — F-nn PoC suites from the white-hat passes
│   ├── invariant/                — P6.5 invariant harness (emission conservation)
│   ├── formal/                   — PB2.12 hevm symbolic-proof harnesses (test/formal/*Proofs.sol)
│   └── mocks/                    — shared mocks
├── formal/                       — PB2.12 formal-methods bundle: act/ (.act specs) + RESULTS.md (property → status index)
├── script/                       — deployment scripts (granular per-contract + DeployStageX orchestrators)
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
| `docs/FINDINGS.md` | All resolved Open Questions (OQ-1 through OQ-25, plus the Stage G addendum OQ-G1–G4) and deferred items. Cross-referenced constantly from stage plans |
| `docs/STAGE_G_PRECHECK_AUTO_GAUGE.md` | Stage G auto-gauge pivot — accepted propositions, side-by-side delta, conflicts |
| `docs/STAGE_G_NOTES.md` | Stage G design freeze (G-D*) + efficiency event schema + test matrix |
| `docs/STAGE_X_PLAN.md` | Per-stage detailed plan: numbered sub-steps, time estimates, commands, tests, completion log |
| `docs/STAGE_X_NOTES.md` | Per-stage living design-decision log + findings log |
| `docs/balancer_v3_reference.md` | Balancer V3 substrate working notes |
| `.cursorrules` | Cursor editor conventions + the "Cursor operation scope — executor under Claude Code planning" rules |

### External canonical spec — `aummfi-bit/aumm-site` (local clone at `/Users/janus/code/aumm-site/`)

The protocol's canonical specification lives in a separate public GitHub repo: <https://github.com/aummfi-bit/aumm-site> (default branch `main`), cloned locally at `/Users/janus/code/aumm-site/`. Claude Code reads the local clone directly — plain §8a file reads (`cat`, `grep`, `sed -n`). Do not read spec content via WebFetch on raw GitHub URLs: that path has confabulated spec literals in past sessions; the on-disk clone is authoritative. If clone freshness is in doubt (a spec edit may have landed upstream), ask the user to run the pull — fetching is a network action and stays user-run.

Layout at the repo root:

* **Numbered spec docs** — `01_intro.json` through `16_team.md` (with `07a_tokens.md` as a sub-doc). Canonical sections referenced from this repo include tokenomics (§ix in `04_tokenomics.md`), constitution (§xxix in `10_constitution.md`), formulas F-0 through F-12 (`11_formulas.md`), bootstrap rules (`08_bootstrap.md`), appendices (`13_appendices.md`), CCB narrative + multiplier engine (`03_theoretical_foundation.md`).
* **Pool profiles** — `miliarium_profiles/` directory holds the 28 individual Miliarium pool documents.
* **Other prose** — `aureum_schedule.md`, `project_aureum_design_final.md`, `script.md`, `15_overview.md`.
* **AI-consumption versions** — `llms.txt` (curated index) and `llms-full.txt` (full corpus concatenation) at the repo root, for cases where a single round-trip read is preferred over per-doc fetches.

When a stage plan says "read `11_formulas.md` F-7" or "per §xxix in `10_constitution.md`" — read the file from the clone, e.g. `grep -n` / `sed -n` on `/Users/janus/code/aumm-site/11_formulas.md`. **Do not fabricate spec content.** If the clone is missing or the relevant section is ambiguous after reading, ask the user to paste from the GitHub web view. FINDINGS.md often quotes or summarises the relevant spec passages; checking there first can avoid an unneeded read.

---

## 5. Cross-reference conventions

The plan and notes files use short reference codes. Know them on sight.

* **`OQ-N`** — Open Question N from `docs/FINDINGS.md`. Example: `per OQ-5` means "see OQ-5 in FINDINGS.md" — typically a resolved canonical constant or a settled architectural choice. **`OQ-G1`–`OQ-G4`** — Stage G addendum (gauge pivot), resolved 2026-05-05.
* **`C-Dn`** — Planning-stage design decision n from `docs/STAGE_C_PLAN.md` (similarly `B-Dn`, `D-Dn`, … `P-Dn`, and the two-letter `PB-Dn` for Stage P-bis). These are the *choices* made while writing the plan, before implementation. Example: `per C-D12` means "see decision C-D12 in STAGE_C_PLAN.md."
* **`Xn`** (stage letter + two-digit ≥ 10, no hyphen — e.g. `C14`, `D36`, `E10`, `F12`, `G16`, `H13`, `I13`) — Implementation-stage finding n from `docs/STAGE_X_NOTES.md`, numbered from 10 to avoid collision with the `X-D*` planning codes. Example: `C14` is the Cursor autonomous-execution incident (§9); the §11 engineering-lesson index is the roster of these codes.
* **`G-Dn`** — Design freeze decision n from `docs/STAGE_G_NOTES.md` (Stage G pivot; pre-`STAGE_G_PLAN.md`).
* **The `F` reference namespace is overloaded across three sources — disambiguate by form:**
  - **`F-0`…`F-12`** (hyphen, not zero-padded) — Formula n from `11_formulas.md` in `aummfi-bit/aumm-site` (see §4). Example: `F-0` piecewise bootstrap emission decay; `F-8` the CCB multiplier.
  - **`F-01`…`F-20`** (hyphen, zero-padded to two digits) — white-hat finding n from `docs/white_hat/AUREUM_WHITEHAT_OUTPUT.md`. Example: `F-04` the seed-AGE maturity gate; `F-08` veto stacking.
  - **`F10`…`F14`** (no hyphen) — Stage-F implementation finding from `docs/STAGE_F_NOTES.md` (the `Xn` form above). The padding/hyphenation is the whole disambiguator: `F-8` (formula) ≠ `F-08` (finding) ≠ `F14` (Stage-F note).
* **`W*` / `WH-*`** — white-hat audit-pass codes; the finding ledger and per-pass detail live in `docs/white_hat/AUREUM_WHITEHAT_OUTPUT.md`. Forms: the Stage-K pass, `WK-R` (rolling post-K re-audit), `WL`/`WM`/`WN`/`WO` (per-stage spot reviews), and `WH-D`/`WH-G`/…/`WH-P6` (the Stage-P back-fill per-stage passes + cross-seam synthesis). Distinct from the `F-nn` findings those passes produce.
* **`RB-*`** — Robustness Backport Register entry from `docs/ROBUSTNESS_BACKPORT_REGISTER.md` (deferred hardening items; e.g. `RB-004.0b`, referenced in the `F13` lesson).
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

### USER VERIFY — plan ref: <stage><step>; run in the user's terminal after Cursor's save; not part of the Cursor prompt

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
* **`USER VERIFY` lines live outside the Cursor prompt.** They are the literal strings the user will run, under a header Cursor never reads. Not a description, not a suggestion — the exact shell line, paste-ready for zsh/bash, with no shell-prompt prefix (no leading `$`). Every USER VERIFY block opens with the header `### USER VERIFY — plan ref: <stage><step>` and then `clear` on its own line, so the terminal starts fresh, the pasted-back output is easy to isolate, and the sub-step it belongs to is legible at a glance when several rungs land in one session. The `### USER VERIFY` token is UPPERCASE and literal because the `.cursorrules` hard stop matches that exact string; lowercasing or omitting it silently disables that defense-in-depth, which is how the header decayed unnoticed over a long session until the user caught it on 2026-08-07. Interactive zsh does not treat `#` as a comment, so the header reports `command not found` and is skipped — cosmetic, and the price of keeping the literal token where a stray paste to Cursor would carry it. Commit blocks take NO header: they never reach Cursor, so there is no hard stop to preserve and the noise buys nothing. Claude Code does not include `forge`, `slither`, or `git` mutations in this block unless the plan explicitly calls for them at this sub-step; verification defaults to read-only file inspection (`wc`, `shasum`, `cat`, `grep`, `git show`, `git diff`, `git status`).
* **`Must match` is grounded in branch state.** Draft those bullets from `git show <branch>:<path>` (e.g. `git show stage-d:src/fee_router/AureumFeeRoutingHook.sol`) or from a cwd confirmed to be the main checkout — not from a possibly stale worktree file, not from chat memory or a prior-session summary. See **D18** and **D21** in `docs/STAGE_D_NOTES.md`.
* **A transcription sub-step's USER VERIFY diffs the saved file against the cited local source, never a Claude-authored expected-file.** When a sub-step copies content that already exists on disk (helper transcription, config mirror, a roster block or env-key mapping that mirrors a sibling fixture), the audit line is `diff <(sed -n '<from>,<to>p' <saved>) <(sed -n '<from>,<to>p' <the cited source>)` (or `git show <branch>:<path>`) — the comparison target is the real source tree, run in the user's terminal. Never diff against a scratchpad `expected_*.txt` that Claude typed from its own reading: that re-introduces the chat-memory oracle the bullet above bans, and a green diff then proves only that Cursor matched Claude's memory, not the ground truth on disk. Net-new authored content (a fresh contract, a new NOTES lock) has no on-disk source and is legitimately verified against the approved draft; the moment content is copied or mirrored from an existing file, the diff target is that file. Surfaced at P10.1b (2026-07-08), where a scratchpad-oracle byte-diff read green while the source-diff against `StageG`/`StageM`/`StageN` was the check that actually mattered.
* **Zero inner fenced code blocks.** Each filled §8e.1 block is itself wrapped in a fenced `text` block in chat; a nested triple-backtick fence inside the CURSOR PROMPT or USER VERIFY body closes that wrapper early, and the Claude Code CLI renderer then mangles everything after it — at any nesting depth. So a §8e.1 prompt carries no fenced code samples: instead of embedding a fenced Solidity block, reference the canonical source by path and line range (per §5, e.g. a `Must match` bullet reading "signature matches `git show stage-x:<path>` L40–L52"). Inline single-backtick spans are fine; multi-backtick fences are not. **D31** governs shell commands *outside* the payload and the two-block rule governs the two *outer* fences; this bans fences *inside* a block.
* **Verify non-existence before a "create" sub-step.** Before authoring a §8e.1 whose `Files` line says `(create)`, confirm the target does not already exist — `git ls-files <path>` plus `git show HEAD:<path>` for the tracked case, or `test -e <path>` to catch an untracked on-disk file. §11 resume anchors and stage-plan text lag branch HEAD, so "this file doesn't exist yet" from memory or a prior-session summary is not evidence; a stale `(create)` silently clobbers a file that landed in a later commit — e.g. a `(create)` for `docs/STAGE_M_NOTES.md` while §11/plan text still treats it as not-yet-landed. If the file exists, the sub-step is an `edit`, not a `create` — re-scope before prompting.
* **Every number in a USER VERIFY block is MEASURED, never derived.** Before writing an expected value, run the exact command that will check it — the same string, the same flags, against the current file — and copy the number it prints. Not arithmetic on an earlier measurement, not the count of a similar-looking string, not a value reasoned out from the payload. Where a value genuinely cannot be measured in advance, such as a file total that only exists after the edit, label it derived in the chat text so a mismatch reads as "the edit was not pure" rather than as a save defect, and pair it with the `git diff --stat` insertion and deletion counts, which check purity independently. The failure this prevents is not carelessness but confidence: deriving feels like understanding, so the command gets skipped precisely when the answer seems obvious. It recurred five times in the 2026-08-07 session — an em-dash tally read off the payload, a `wc -c` prediction that ignored multi-byte characters, a `grep -c` line count asserted as an occurrence count, a substring count asserted for a different substring than the one measured, and a file total whose delta double-counted — and each was patched as its own special case while the habit survived intact. PB18 in the §11 index records the unit half of this; this bullet is the general rule, and it is the one that binds when drafting.

Claude Code does not add *ad-hoc* fields beyond this shape. The only top-level fields in the CURSOR PROMPT block are: `Plan ref`, `Plan lines`, `Goal`, `Instruction`, `Files`, `Must match`, `Out of scope`, and `Stop after`. `Verify` is no longer a field of the CURSOR PROMPT block; the verify commands live in the USER VERIFY block below the divider. Extra fields invite prose, and prose invites Cursor to plan.

### Why this division

* **Token economics.** Cursor is a subscription-paid tool the user already owns; routing content generation through it avoids metered-API consumption on large file content. Claude Code's token budget goes to planning and auditing, which is where its multi-step reasoning is most valuable.
* **Safety.** Cursor's generation and Claude Code's auditing are independent failure surfaces. If Cursor generates wrong content, Claude Code catches it at audit. If Claude Code's plan is wrong, Cursor's scope-stopping behavior (and the user) catches it before damage compounds. Either failure alone is visible; both would have to happen the same way at the same time to slip through.
* **Progress discipline.** The 2026-04-19 planning failure demonstrated that Claude Code in a pure-planning role without a forcing function chases its tail. The forcing function is Cursor's executor cycle: each prompt must be small enough for Cursor to execute in one pass, which forces Claude Code to commit to concrete next steps rather than re-scoping indefinitely.

### Git mutations

The user runs all `git add`, `git commit`, `git push`, `git tag` in their own terminal. Claude Code drafts the exact commands (including full commit message) and confirms expected `git status` state before and after. Neither Claude Code nor Cursor runs git mutations. All terminal command blocks that Claude Code drafts for the user — including git command sequences — begin with `clear` on its own line, for the same reason as USER VERIFY blocks: the terminal starts fresh and paste-back output is easy to isolate. When a ✅ audit verdict closes a sub-step that warrants a commit, Claude Code emits the commit as a single text-fenced code block containing the full paste-ready sequence — `clear`, then `git add <paths>`, then `git commit -m "<message>"`, then `git log --oneline -3`, then `git status -sb` — never as the bare commit-message string alone. The bare message forces the user to reconstruct the `git add` and verification lines from memory, undermining the same paste-and-go ergonomics that the USER VERIFY two-block rule was written to preserve.

### 8f. Broadcast recording

**Every transaction broadcast to a live chain gets a committed row in that chain's deployment record.** Not at the end of the stage and not from memory — the row lands while the receipt is still on screen, and the record is a tracked file under `docs/`.

The reason is structural rather than clerical. `.gitignore` excludes `broadcast/` and the canonical `.env` files, so forge's own run artifacts and the operator environment are local-only and unversioned: a lost working tree leaves the chain as the sole source of truth. A partially-failed run leaves gaps even locally — a `forge script` that aborts mid-sequence writes its `transactions` array with no `receipts`, so the transactions that DID land carry hashes but no block, no gas, and no status. That case is not hypothetical; it is how nonces 90 to 92 of the Sepolia base layer came to be recorded only after a manual chain read.

Per-chain records:

* **Sepolia** — `docs/STAGE_P_BIS_SEPOLIA_DEPLOYMENT_RECORD.md`.
* **Mainnet** — `docs/STAGE_R_MAINNET_DEPLOYMENT_RECORD.md`, created at Stage R before the first broadcast, not after it.

Each row carries nonce, contract, address, block, gas used, and transaction hash. Abandoned or superseded deployments stay in the table under an explicit label rather than being deleted — a block explorer shows them regardless, and a reader must be able to tell which set is live.

**The narrative is part of the record, not commentary on it.** Gas-limit decisions and the arithmetic behind them, RPC-provider refusals, every deviation from the runbook, and every recovery from a partial failure get written down. These are the first things an auditor asks about, and they exist in no artifact — forge records what was sent, never why.

**Verification is a source-diff, never a self-check.** The USER VERIFY block greps every hash and address in the saved record against `broadcast/`, so the comparison target is forge's own artifact rather than a transcription of what the record was believed to say. Per §8e.1's transcription rule, an expected-file typed from a prior reading is not evidence.

**Mainnet is stricter.** Stage R execution is one-shot per the Testing-strategy note in `docs/STAGES_OVERVIEW.md`: the record is written transaction by transaction as receipts arrive, never batched at the end of a sequence, because there is no second run in which to reconstruct a missed row.

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

This section is the resumption anchor — a thin pointer, not a ledger. Per-sub-step commit detail lives in git and the `STAGE_*_PLAN.md` Completion logs; §11 holds only what a cold session needs to resume. Update at the end of every completed sub-step.

**Last update:** 2026-08-06 — **Stage P COMPLETE** (`stage-p-complete`, tagged at the P11-backfill commit and ff-merged to `main`). The stage ran two workstreams per P-D0 on branch `stage-p` (cut from `main` @ f50b4cd = `stage-o-complete`): **(A)** the white-hat back-fill sweep — the WH-D/G/H/I/J/L per-stage passes + the WH-P6 cross-seam synthesis + the P6.5 INV-1/2/6 invariant harness; **(B)** full-system deployment — the P9 granular deploy scripts + the `DeployStageP` thin orchestrator + the P10 mainnet-fork integration validation against REAL mainnet literals (P-D0b, the primary close gate). Full detail in the Stage P bullet below.
**Next: Stage P-bis (open-issue close-out + testnet go-live + frontend)** — inserted between P and Q by the 2026-07-11 restructure; full scope in the `STAGES_OVERVIEW.md` Stage P-bis section. Three sequenced workstreams: **(A)** open-issue close-out — every live carry-forward below plus the ex-Stage-Q queued inputs (the P-D9 hevm/Act formal-methods bundle, the F-13/F-15 Accepted-risk dispositions, the P-D42 coverage-tooling re-eval, the F-D11 env-key-namespacing carry-forward, the WK.18 thin-venue populated-roster fork sim), each item exiting Fixed, Built, or Explicitly-descoped-with-rationale; **(B)** testnet deployment — the P8 token stubs + the production Router/`setTrustedRouter` binds + the live testnet broadcast (P-D23/P-D26) + the F-14 ops/fee-custody item; **(C)** the `aumm-app` frontend against the live testnet. `stage-p-bis-complete` is the frozen audit candidate; **Stage Q narrows to the audit engagement only**, Stage R unchanged.
Stage-entry freeze LOCKED 2026-07-11 and committed at PB1.1/PB1.1a (`docs/STAGE_P_BIS_NOTES.md`, PB-D1—PB-D5; branch `stage-p-bis` cut from `main` @ f72b309 = the CM-series tip, base amended same-day from b5f4b8b per the PB1.1a amendment to PB-D3): testnet = Sepolia (PB-D1, 12s-block parity), the multisig §xxix gap closes via the wiring step with no constitutional amendment (PB-D2). PB1 complete (plan `9446cbd`).
PB2.1 (OQ-20/OQ-21) BUILT and closed per PB-D6 — `routeYieldFeeToHook(pool, token, amount)` + the per-pool `BLOCKS_PER_EPOCH` throttle live on `AureumProtocolFeeController` (`88c453d`…`516fa68`, 42 unit + 8 fork).
PB2.2 (OQ-22) BUILT and closed per PB-D7 — the 2-hop TVLOracle valuation fallback (`_directRatio` extraction + `_twoHopRatio` + governance-append-only hop roster seeded ZCHF + USDS at wiring; direct venues win, no transitive hops; the pre-freeze "fee-routing" label was wording drift; ixAetheron venue-wall residual explicitly dispositioned in PB-D7) (`28c653b`…`76c6be2`, 55 unit + 12 fork).
PB2.3 (pool restoration) adjudicated per PB-D8 — ixCasper's waEthwstETH 16% theme leg RESTORED via an Aureum `CompositeRateProvider(waEthwstETH, wstETH RP)` env-injected per N-D7 (QG 68%→84%, both composite hops fork-verified live 2026-07-12); 04 ixViatica / 07 ixCambio DESCOPED to the Stage-O composition-challenge path (fBRZ / aEURS re-probed absent — browser Flux-docs + bgd-labs address-book); OQ-I10 CLOSED with zero remainder (`1f07d4a`…`50aa0e3`, StageM 7/7 + StageP 13/13 fork).
PB2.4 (F-13) adjudicated per PB-D9 — F-13 exits SPLIT: the PB2.1 `routeYieldFee`/`routeYieldFeeToHook` path FIXED via caller-supplied `minDepositTokenOut` + `minBptAmountOut` threaded to Vault-native `SwapLimit`/`BptAmountOutBelowMin` (onAfterSwap keeps `0`/`0`, hot path behavior-identical), the two dormant deposit entries threaded + attested dormant, and onAfterSwap stays Accepted-risk at S5 Low with the PB2.4d2 mainnet-fork sandwich sim as quantifying evidence (feeRider 0.375% of a 50e18 swap; skew round-trip 12× the fee-rider prize) (`6fc8416`…`5fa40db`, 901 unit + 14 fork).
PB2.5 (F-15) adjudicated per PB-D10 and closed — F-15 exits Accepted-risk (S9 Low, standalone): the `VaultClassRegistry.vetoProposal` live denominator is bounded by the poke invariant — `governanceWeight` returns the poked checkpoint `_holderWeight[holder]` and `poke` maintains `_totalQualifiedWeight` == the sum of `_holderWeight[*]`, so any weight enterable into the veto numerator is already a denominator summand; defender inflation is capped at fully-poked truth, and a coalition at or above 10% of true qualified weight cannot be suppressed by any poke strategy. Both snapshot fixes rejected as regression-bearing; live reads retained by design, no code change (`34e4c27`…`4e438ed`, evidence sim 6/6 + 907 unit). The PB-D5 workstream-A adjudication queue (PB2.1—PB2.5) is now empty; the whitehat ledger carried zero open findings at that point.
PB2.6 (the PB-D2 wiring build per the PB-D11 + PB-D12 amendments) BUILT and closed — `script/DissolutionGovernanceHandoff.s.sol` (the five dissolution-time rotations: four emission-layer `setGovernanceContract` + `SwapAndDepositToBodensee.setDonateAuthorizer`; `VaultClassRegistry` excluded per PB-D11, one-shot-sealed and rerouted to the PB3.4 production bind) + `test/fork/DissolutionGovernanceHandoff.t.sol` (the P-D36-style fork witness — pre-rotation premise, rotation lands all five, multisig locked out of the rotated setters, the PB-D12(ii) load-bearing operational-wiring family reverts under `AureumGovernance` v1, the `pauseManager` inert-non-exclusive-pointer attestation; 5/5 fork-green) + the `STAGES_OVERVIEW.md` L381 rotation-roster reconciliation (`84a859d`…`a0357ff`). PB10 lesson logged (a chained getter under `vm.expectRevert` / `vm.prank` consumes the cheatcode — cache the handle first).
PB2.7 (the D36 permanent fix) DESCOPED and closed per PB-D13 — the one-file plan scope was stale by an order of magnitude (224 `vm.setEnv` sites / 16 fork files / 48 test contracts; the race lives inside single-file runs too), the real fix re-opens the P10-validated deploy plumbing pre-audit, and the parallel-green exit gate is unevidenceable on Ankr free-tier (D35); `--threads 1` promoted from F-D11 workaround to permanent canonical fork-invocation posture; the D36 branch-(b) parameterization recorded as RB-006 (new Test-fixture isolation hardening class); Decisions table back-filled PB-D6—PB-D13 (`fc09269`…`65276df`).
PB2.8 (the direct `ReentrancyGuard.selector` witness) BUILT and closed per PB-D14 — `vm.transientStore` is absent from the pinned forge-std v1.15.0, so the witness lands via roll-plus-accrue mock reentry through `MockVault.settle` (the `getPoolTokenInfo` vector is a STATICCALL where the inner state writes exceptionally halt before reaching the guard); `test_Distribute_RevertWhen_Reentrant_DirectGuard` on `BodenseeBootstrapChannel.distribute()`, RB-007 created Closed, the H3.7e bubble-up test retained as the stale-accrual pin (`02536d5`…`d11f542`, 35/35 file-scoped + 908/908 Part A).
PB2.9 (the P-D42 coverage re-eval) RE-AFFIRMED and closed per PB-D15 — the confirmatory re-probe reproduces the P-D42 Yul stack-too-deep byte-identically on the byte-identical toolchain (forge `f83bad91` / solc 0.8.26; tree grown 316 → 319 coverage-compile files), the execution-evidence waiver re-affirms (Part-A 908 unit + the PB2.x suites), coverage re-eval rides to the post-audit / newer-toolchain gate with the hevm/Act bundle; `STAGES_OVERVIEW.md` L386 P-D42 clause closed (`c04b00e`…`38a68f9`).
PB2.11 (the WK.18 thin-venue populated-roster fork sim) BUILT and closed per PB-D16 — F-04's spot-`tvl()` atomic surface is already Fixed (the 60-day EMA maturity + freshness gate on `VotingWeight._positionPower`, `3d80ac8`), so the sim exits as a populated-roster positive-control + sustained-pump economics quantifier, not a bug hunt; `test/fork/WK18ThinVenuePumpSim.t.sol` (6/6 fork-green on the StageN 21-pool roster + two constellation venues + a real 60-day-matured-EMA scored pilot) closes the R1-blocked WK.18 could-not-assess across three faces — an atomic venue pump leaves `governanceWeight` byte-identical (EMA-not-spot), a single-venue pump dilutes the `_directRatio` cross-venue mean 1/N (wei-exact, N=2), and a sustained 200%-of-depth pump is bounded fee-negative (+99.6% spot vs +10.69% weight over 21 daily EMA samples); F-04 stays Fixed, no findings-table change (`505e538`…`1ced206`). The PB2.1—PB2.11 workstream-A fix roster is complete.
PB2.12 (the P-D9 hevm/Act formal-methods bundle) BUILT and closed per PB-D17 — hevm `0.58.0` local symbolic proofs across all four Aureum-owned surfaces (fee-routing hook, CCB/EMA engine, emission accrual, authorizer window): 52/52 `prove_` PASS under bitwuzla 0.9.1, nine `.act` Tier-2 specs authored as audit-handoff artifacts (machine-check firm-side per PB-D17(ii)), and `formal/RESULTS.md` the property → status index; new top-level `formal/` + the four `test/formal/*Proofs.sol` harnesses (`56a46dd` onward).
**Workstream A CLOSED at PB2.13** — the OQ-23 reopening BUILT and closed per PB-D18 (`f614f0e` onward; two same-day 2026-07-16 directives adjudicated in the lock): `delta_global` re-keys from the Miliarium-only OQ-23 (iii.b) aggregate to the all-Active-gauge aggregate — `gaugeCount()`/`gaugeAt()` enumeration (P-D13), raw ungated sum, `lastProtocolAggregateEMA` re-keyed with F-D18 cold-start semantics (zero sentinel → neutral) — and the initially-proposed third `delta_basket` channel is WITHDRAWN: the Miliarium-vs-non-Miliarium damping is already inherent in F-5/F-6 one-denominator proportionality, so F-8 stays two-channel, constants stay untouched per PB-D18 (iv) (the g3b "likely clamp/step revisit" evaporated), the spec needs zero edits, and the OQ-23 F-8/§vii items briefly queued into PB2.10 drop. `delta_intra` decoupled-unchanged (miliariumAgg/28, OQ-23 (iv.a)); `updateMultiplier` walks two rosters per call and stays Miliarium-gated; `getMultiplier` + EmissionDistributor/GaugeRegistry/EMASampler/ICCBMultiplier zero-change. Family: lock + plan insert + FINDINGS reopen (`f614f0e`/`e24b746`/`005fbf5`); the `CCBMultiplier` rebuild — ctor 2→3-arg restoring the P-D22-removed gauge-registry slot + the F-D20-mirror one-shot `setGaugeRegistry` seal, `IGaugeRegistry` additive `gaugeCount()`/`gaugeAt()` (`c6a7c79`/`3bac2ef`); the 12-site ctor ripple (e1 the 3 unit sites + MockGaugeRegistry, f1 the remaining 9; `8529390`/`72785ea`) + the five e2 decoupling tests proving the gauge and Miliarium universes genuinely independent (the disjoint-roster 777e18-vs-1000e18 discriminator; file 44/44, Part-A 921; `bb39704`) + the f2 post-G-stack orchestrator seal (`sealAuthority`/`sealGaugeRegistry` forwarder on `DeployStageF`, `GAUGE_REGISTRY_PLACEHOLDER` env, DeployStageP post-condition (4); `2b619ce`) + the f3 StageJ fork retarget to genuine decoupled witnesses (file-scoped 5/5; `b4132a1`); the CCB formal leg re-specced/re-attested — the g1 P-M2 gauge-registry mirror trio (CCB proofs 6→9), the g2 `ccb_multiplier.act` 3-arg rewrite + two-aggregate residual footer, the g3 55/55 hevm re-attest (at `9c109b1`; the `--ast` artifact prerequisite recorded), the g4 `formal/RESULTS.md` re-anchor (`413aee7`/`9c109b1`/`6ba6455`); the PB-D18 (vi) zero-TVL disposition closed as-designed-with-evidence — `ZeroTvlDisposition.t.sol` 7/7 pins the F-8 clamp-ceiling resurrect-proof (unseeded/stale EMA scores zero under a 1.25e18 multiplier), the (59/61)^n drain half-life (49–51% of seed by 21 daily samples, under 5% by 90), poolScore persistence + permissionless `recordScore` self-clear both edges, and wei-exact dust capture bounded to exactly the (a)+(b) tail; (d) equal-regime carve-out note-only per §xxviii/H-D6; no-fork-escalation rationale recorded at (viii) (`6a749c0`/`59c7298`/`6df0999`). Close-gate verified 2026-07-17: the full Part-A unit suite 928/928 green (D35 split-form; 921 at e2 + the 7 h-series pins). The PB-D5 queue is empty, the whitehat ledger carried zero open findings at that point, and every PB2.1—PB2.13 item exited Fixed, Built, or Explicitly-descoped-with-rationale.
**Workstream B OPEN — PB3.1 (Sepolia environment verify pass) done 2026-07-17.** Sepolia RPC live (`SEPOLIA_RPC_URL` configured; chain 11155111, 12s parity per PB-D1); canonical Permit2 present at the cross-chain address (the PB3.3 Router constructor dependency); deployer `0xA851478dbee97375E784e9b98c0D7D599662bF85` funded 0.05 SepETH via the Google Cloud Web3 faucet (private key held off-repo, never committed). Two non-blocking carries: the Etherscan API key is absent → create before the PB3.5 `forge verify-contract` (the API endpoint itself is reachable); the full deploy + 28-pool-seed gas budget defers to the PB3.4 fork rehearsal per PB-D19 (0.05 is a starter tranche — accumulate toward ~1–2 SepETH via the pk910 PoW faucet; testnet LP is gas-only, the P8 stubs are minted not capitalized). Landed ahead of sequence: PB3.4-pre/pre-b, the PB-D19 genesis-offset lock (`cded9c7`/`343b33a`) — production `GENESIS_BLOCK = broadcast_block + 100_800` (one epoch / 14 days) decouples the emission clock from deploy time at zero code change (env-only: `DeployAuMM.s.sol` L33 reads it with no `block.number` clamp, the P-D14 four-way genesis assertion is cross-contract, the deploy path fires no schedule-clock call), the PB3.4 rehearsal runs the future-offset env, two optional pre-genesis evidence pins PB3.4-scoped.
**PB3.2 (P8 testnet token stubs) COMPLETE 2026-07-17** — locked as PB-D20 (base-level `vm.envOr` STUB_ override architecture) + PB-D21 (the iterate-the-real-configs stub-deploy script), both user-adjudicated. On the a–f build ladder: two `test-stubs/` templates (`StubERC20` ctor-set decimals + permissionless mint; `StubERC4626` fixed-1:1-NAV over an 18-dec underlying, deliberately not `is IERC4626` to dodge the mint-signature collision) with 16/16 unit tests including both F-11 `ERC4626RateProvider` cases (`860bd2f`…`49fe65d`); the base-level override resolver in `deploy-miliarium-pool.s.sol` (`_resolveStub` via `vm.envOr(STUB_+vm.toString(literal), literal)` passthrough-default + `_resolveRateProvider` WITH_RATE-non-zero-RP-to-zero fail-fast, QG loop reading pre-override cfg.* untouched; `b7bc0f7`), proven byte-identical by the no-STUB_-env P10 fork suite 13/13 green; and `test-stubs/DeployTestnetStubs.s.sol` — iterates all 26 config libraries on a mainnet fork, deploys the deduped stub roster (WITH_RATE → 18-dec StubERC20 underlying + StubERC4626 + real RP; STANDARD → StubERC20 at real fork decimals), console2.log-emits the map behind a coverage `require` gate, fork-validated at 67 STUB_ pairs + 7 named keys with zero passthrough leaks (`dd0f179`…`db7c23f`); the fork-sample map committed to `test-stubs/sepolia-stubs.env` (`a867254`, byte-verified via an independent determinism re-run). Address model (PB-D21 (v), user-adjudicated): plain CREATE, fork-sample values now, live Sepolia addresses regenerated at PB3.5.
**PB3.3 (canonical Router redeploy + F-09 trusted-router seat) COMPLETE 2026-07-17** — locked as PB-D22 on the a–e build ladder: permit2 installed at Balancer's toolbox pin `cc56ad0` (PB3.3a `0a35646`, interfaces-only — the canonical cross-chain instance is the runtime dependency, G10-class compile-probe green); the PB-D22 NOTES lock + plan-side reconciliation (PB3.3b1/b2 `d914d9b`/`9b1bd28`); `script/DeployRouter.s.sol` — the P9-granular deploy script, three explicit `vm.envAddress` reads (AUREUM_VAULT / WETH_ADDRESS / PERMIT2_ADDRESS, no defaults) + the Aureum-branded `ROUTER_VERSION` constant + one `new Router(...)` against the byte-unmodified canonical submodule, H13-audited storage-only ctor chain, clean-cache compile green (PB3.3c `e85466d`); and `test/fork/RouterIntegration.t.sol` — the PB-D22 (v) mainnet-fork witness realizing the P-D26 (3) production-router leg, 5/5 fork-green (`--fork-url mainnet --threads 1`): the version pin, the F-09 fail-closed negative (a REAL unseated-Router add mints BPT but records nothing), the governor's one-shot module-aim-at-self + `setTrustedRouter` seat, and the d2 symmetric F-17 pair — post-seat a REAL add credits `userLP` to the true LP for the exact BPT minted, and a REAL `removeLiquidityProportional` (BPT allowance to the Router per Vault L1009) debits `userLP` in exact lockstep with live BPT (PB3.3d1/d2 `5e57280`/`15599c3`).
**PB3.4 (production `run()` un-defer + the PB-D19 future-genesis rehearsal) COMPLETE 2026-07-25** — locked as PB-D23 (the composition model), amended by PB-D24 (composed-`run()` handle capture), PB-D25 (the rehearsal-harness architecture) and PB-D26 (the stub-ordering fix the rehearsal itself surfaced). On the a–f ladder: the PB-D23 lock + plan row (`02d4454`/`bad3c26`); the F/G/H run-entry normalization off bare `startBroadcast()` to the env-governor convention (`64bab0c`); the PB-D24 lock, the J/K/L public-storage handle exposure, the post-K `VaultClassRegistry` bind reorder in the `deploy()` spine, and the `run()` un-defer itself replacing the `ProductionOrchestrationDeferredToPbis` guard with the composed production flow (`72ad01a`…`ecf4fcb`); the G10-class depth-2 broadcast-nesting probe, fork-green first run (`4bfb6ee`); the PB-D25 lock + plan amendment (`5da02b3`/`e55d91b`); and the d2 rehearsal harness (`c099785`…`501ed98`) — `test/fork/StagePRunRehearsal.t.sol`, standalone by design (NOT a `StagePIntegrationFixture` subclass, so the P10 close gate stays byte-identical and is never re-run as a regression surface), replaying `DeployTestnetStubs` in-process via the additive `envPairCount`/`envPairAt` getter, building the base layer under a real-EOA governor at `GENESIS_BLOCK = block.number + 100_800`, deploying all 26 pools, driving `DeployStageP.run()` (the production spine, never `deploy()`), re-asserting the four post-conditions test-side, and seating the Router with a live credited add; 9/9 fork-green. **PB-D26 is a production-path defect the rehearsal caught, not a harness artifact** — `deploy-miliarium-pool.s.sol` assembled `TokenConfig[]` in raw config order with no sort and passed `normalizedWeights` unpermuted, so the ascending-address ordering Vault registration requires survived only by luck once `_resolveStub` substituted freshly-CREATEd stubs: ixAurebit reverted `TokensNotSorted()`, all 26 pools were exposed, and the same script drives the PB3.5 Sepolia broadcast, where it would have failed mid-broadcast against a funded deployer. Fixed by an unconditional ascending sort with lockstep weight permutation immediately before `create()` — lockstep because sorting tokens alone would seat a leg's weight on the wrong token, a mispriced pool that registers cleanly; mainnet invariance checked rather than asserted by re-running the P10 close gate 13/13 unchanged (`dcc5142`…`2536e9e`, `115819c`). PB3.4e landed the two PB-D19 (v) pre-genesis pins in `test/unit/PreGenesisAccrual.t.sol`, the one path P10 never ran (its fixture always rolled to genesis): a pre-genesis `_accrueGlobal` touch takes the H-D15 empty-`totalScore` short-circuit and accrues nothing, so the inverted `[last + 1, block.number]` window is never handed to the integral, and the 100,800-block pad is provably shorter than the 432,000-block EMA maturity gate — the constant relation that makes that short-circuit unconditional rather than incidental; 3/3 unit-green (`159eddb`).
**PB3.5 (live Sepolia broadcast) IN FLIGHT — rungs a1 through h COMPLETE 2026-07-27; rung i opened and split into an i1—i9 sub-ladder by the EIP-170 blocker, with i1 through i7 COMPLETE 2026-07-28 and i8—i9 BLOCKED on gas.**
Locked as PB-D27 (go-live architecture: a committed `DECIMALS_` table read fail-fast, a multi-broadcast runbook threading addresses through `.env` rather than `vm.setEnv`, EOA-scoped prediction of the four-deep base-layer address cycle, the `DeployDerBodensee` stub-RP adaptation, and Sepolia keeping the UPSTREAM `WeightedPoolFactory` with the real Aureum factory a named Stage-R gate; build ladder a1–j at (x)), then amended four times as execution surfaced what the lock could not foresee.
PB-D28: the per-step EOA transaction counts defer from rung e to rung h, the runbook landing with a structurally complete count table reading `PENDING-h`, because a source-read number is one an operator could act on.
PB-D29: the pre-broadcast dry run is TWO-PHASE — one upfront full-sequence run is not executable, since simulation never advances the deployer nonce and every step past the vault reads a live predecessor, so phase A computes projections analytically and phase B re-simulates each step immediately before its own broadcast inside rung i; `forge script` simulation was chosen over a fork-test harness, whose CREATE-only nonce advancement would undercount every call-making step.
PB-D30: the fee-routing hook deploys BEFORE der Bodensee, steps 5 and 6 swapped — they are independent in both directions (the hook's constructor only stores `derBodensee_`; `DeployDerBodensee` reads no `FEE_ROUTING_HOOK`), which reduces phase A to four Sepolia-standalone counts and retires PB-D29 (v)'s mainnet-simulation clause, whose rationale was false for an Aureum-bound factory that exists on no chain.
PB-D31: `DeployTestnetStubs` carried NO broadcast wrapper — its four CREATEs ran in simulation context only, so a live `--broadcast` would have sent nothing while still emitting a full 67-pair `STUB_` map of codeless addresses, silent through step 4 and fatal at step 5's hook constructor AFTER step 2 sealed its immutables; the same PB-D26 pattern, hidden because `StagePRunRehearsal` replays the roster in-process through the `envPairCount`/`envPairAt` getters and never drives the broadcast path.
Ladder as executed: e the operator runbook `docs/STAGE_P_BIS_SEPOLIA_RUNBOOK.md`; f the gas measurement — 367,079,280 gas for the full spine, nine identical fork readings confirming determinism (`584b632`/`ffb20d3`); g the RB-008 register row plus a new Contract-identity verification hardening class (`8db2e48`); h the two-phase dry run itself (`731af0b`…`6b12916`) — the PB-D29/PB-D30 locks and plan rows, the four-location hook-before-Bodensee reorder, runbook section 8 (the phase A/B procedure with the four-command CREATE3 derivation), the PB-D31 lock/fix/gate (the `StagePRunRehearsal` re-run 9/9 with every stub address moved, proving the wrapper took effect, and the Stage-F stack plus vault addresses unmoved, proving the blast radius), and phase A executed live: `n0 = 0`, counts 87/4/1/1, all eight projections computed and written to `.env`, and the CREATE3 derivation VALIDATED against forge's own dry-run artifact at nonce 0 — three plain CREATEs plus the CREATE3 Vault reproduced exactly by `cast`. Evidence at `docs/STAGE_P_BIS_PHASE_A_RECORD.md`; runbook section 5 carries rows 1—4, rows 5—10 stay `PENDING-h` since no projection reads them.
**Rung i opened 2026-07-27 and immediately surfaced a second, harder blocker: the compiled Vault overran EIP-170 and could not be deployed to any chain.**
Locked as PB-D32, amended three times. The artifact stood at 28,304 bytes against the 24,576 limit, so the Sepolia base layer is dead from nonce 87 — the factory's sealed creation-code hash forces a redeploy that cascades through der Bodensee's CREATE3 address, and phase A must re-run in full.
PB-D33 isolated the cause by ablation against the Sourcify `exact_match` `stdJsonInput` for the deployed mainnet Vault: one missing compiler setting, `yulDetails.optimizerSteps`, worth 782 of the 676 bytes needed, with the OpenZeppelin-pin hypothesis withdrawn at 31 bytes — a value reading exactly like solc's documented default proved to be the whole answer, the PB15 lesson.
PB-D34 landed the fix as a scoped `[profile.vault]` rather than project-wide settings, since only full profiles carry their own `optimizer_details` and the project-wide form breaks the test tree with an unattributable Yul stack-too-deep; solc pins to 0.8.30 there because 0.8.26 ICEs on our submodule revision at Balancer's own settings, and Vault lands at 24,393, 183 bytes under. Blast radius measured rather than predicted: 3 artifacts changed against a 470-artifact baseline, all downstream of `DeployAureumVault.s.sol`, zero Aureum protocol contracts touched, gated at 947 unit + 13/13 P10 fork green. User-adjudicated that this Vault is explicitly NOT byte parity with the deployed artifact — Sepolia needs EIP-170 fit only, and true parity rides to the Stage-R submodule-pin bump, which would also restore 0.8.26.
**A second defect surfaced alongside it and closed at i5 (PB-D35, amended by PB-D36):** phase A had written the Sepolia overlay into `.env`, and because PB-D20's stub resolver activates on key existence alone through `vm.envOr`, every mainnet fork suite had been silently redirecting its mainnet literals to codeless Sepolia addresses since 2026-07-26, invisible for two days because the unit suites bind no mainnet literals and `.env` is gitignored. The fix is a three-file copy-and-refresh model — `.env.mainnet` and `.env.sepolia` are complete, independently-maintained canonical sets and `.env` is a derived working copy of whichever is active, so no precedence rule survives and no key can inherit the other chain's value; an `AUMM_ENV_CHAIN` marker failing CLOSED on absence is asserted before every run.
**i6 (PB-D37) built the permanent gate PB-D32 (x) demanded:** `test/unit/BytecodeSize.t.sol`, 4/4 green, asserting deployed size for the three vault artifacts by explicit `out-vault/` path and all 27 Aureum contracts by full source path, plus a `vm.readDir` completeness check so a contract added later fails the gate instead of escaping the roster. Named-artifact assertion is forced rather than preferred: neither profile can pass an unscoped `forge build --sizes`, the vault profile carrying `VaultMock` at 42,408 bytes and the default profile twenty over-limit test and script artifacts. RB-009 and RB-010 record the two general traps under new Deployment-limit verification and Environment-scope isolation hardening classes. i7 corrected the §2 compiler row (the toolchain-parity claim withdrawn), landed the PB15 lesson, and made this advance; i7b2 is queued for the matching stale claim in `foundry.toml`'s own header comment.
**PB3.5 COMPLETE.** Rungs i8 and i9 executed and the base layer is live: the deployer now holds 5.85 SepETH, and `docs/STAGE_P_BIS_SEPOLIA_DEPLOYMENT_RECORD.md` records nonces 87 to 98 in section 1 (authorizer, fee controller, vault factory, the Vault via CREATE3 `factory.create()` at nonce 93, the upstream `WeightedPoolFactory`, AuMM, the fee-routing hook, der Bodensee, the canonical Router), the 87 stub nonces in section 2, the twenty-five Miliarium pools at nonces 99 to 123 in section 7, and slot 02 `ixAetheron` from a second EOA in section 8 under the `BODENSEE_SALT` CREATE3 collision. `GENESIS_BLOCK` is no longer a placeholder — it is sealed in the deployed AuMM at 11477620, roughly 78,000 blocks and about eleven days beyond the 2026-08-01 head, so PB3.9 opens on a real clock.
**PB3.6 (the F-22 fix per PB-D63 / PB-D64) is COMPLETE — detailed in the F-22 block at the end of this section. PB3.7 (the deployed-addresses artifact) is COMPLETE per PB-D65 — `deployments/11155111.json` carries 53 live protocol contracts and 59 stub tokens, generated by `tools/generate_deployment_json.py` from the committed deployment record and the new 87-row stub topology ledger, and RB-014 closed in full along the way. PB3.9, and PB3.10 (F-14 ops and fee-custody rails, renumbered out of PB3.6 at PB3.6d-f3 and f4), are not started.**
**PB3.8 (pool seeding and oracle population) IN FLIGHT** — locked as PB-D41 and amended by PB-D42 through PB-D48; rungs a through g complete (the `TVLOracle` L12 NatSpec correction, the `script/config/SepoliaTokenUnderlyings.sol` derived map, `script/WireTVLOracleSepolia.s.sol`, `script/SeedMiliariumPoolsSepolia.s.sol`), rung h being the live-Sepolia dry run that PB-D47 re-scoped from a fork rehearsal. **PB-D47:** rung h seeded 21 of 26 in simulation then reverted at slot 02, which had registered the weETH stub as its own rate provider because `DeployTestnetStubs` keyed tokens and providers into one `STUB_` namespace and weETH is self-providing on mainnet; `VaultExtension` seals `TokenInfo` at registration with no setter anywhere in the Vault, so the pool was unrecoverable in place. Closed across h1 to h8 — provider keys split into a disjoint `STUB_RP_` namespace with a legacy `STUB_` fallback plus an unconditional `getRate()` probe in `_resolveRateProvider`; the provider recovered by nonce arithmetic rather than redeployed at `0x4a4EA25a6359852d4e47031Fc1316F3aE13de0a3`, identified by `wrappedToken()` matching the registered stub; slot 02 redeployed from a THIRD EOA `0x87969483c553fC350684cB76007ef114105C8eDc`, salt 2 being consumed in both the deployer's and the second sender's CREATE3 namespaces, landing `0x45014C1C6720DaD745F2a791521a6723d102aDD8` at block 11399372 for 4,933,856 gas, recorded in section 10 and verified in sealed state by `getPoolTokenInfo`; and the seeding dry run re-run clean at 26 of 26 and 47,941,303 gas, exercising slots 01, 12, 13 and 16 for the first time. **PB-D48 (rung h9):** the first live-Sepolia dry run of phase 4 reverted at `DeployStageP.s.sol` L178, which seeded `GAUGE_REGISTRY_PLACEHOLDER` from `address(this)`, rejected by `forge script` because a script contract is ephemeral under `--broadcast` — the third instance of the test-versus-script class after PB-D31 and PB-D46, invisible to `StagePRunRehearsal` 9/9 each time because a test contract has a real address. Fixed to the in-scope governor at `2590d85`; the run now completes at 114 transactions, 16 CREATEs covering the full F-through-L set, and 36,934,592 gas, answering runbook section 5 row 9.
**PHASE 4 IS BROADCAST — the Stage F through K stack is live on Sepolia.** The h9g broadcast ran 2026-08-02 in a single invocation under `--slow`: 114 transactions at nonces 125 to 238 contiguous, 114 receipts every one successful, 16 CREATEs, blocks 11403323 to 11403470, 27,666,605 gas for 0.029383870046196392 ETH against a 5.85 SepETH balance, with actual gas running about a third under the 36,934,592 estimate on forge's buffer. `docs/STAGE_P_BIS_SEPOLIA_DEPLOYMENT_RECORD.md` section 11 carries the sixteen deployed contracts and the narrative, and `docs/STAGE_P_BIS_PHASE_4_LEDGER.md` is the full 114-row per-transaction ledger, generated from forge's own artifact rather than transcribed because `broadcast/` is gitignored and is therefore not a durable record. The four post-conditions passed in simulation and were then re-read on chain rather than inherited: the Vault's authorizer is now `AureumGovernanceAuthorizer` at `0xd25f8510fbbc7fe0daebca3bb995b907211068b7`, seated by nonce 237's `setAuthorizer` against the Vault and the single most consequential transaction of the sequence; `GENESIS_BLOCK` reads 11477620 on `GaugeRegistry`, `EfficiencyOracle` and `EmissionDistributor` alike; the CCB gauge-registry seal points at the `GaugeRegistry` at nonce 134; slot 01 is gauged; and the deployer's nonce reads 239, which is 125 plus 114 exactly. The PB-D49 resume path was provisioned before the send and never needed. Runbook section 4's phases 5 (the F-09 Router seat, two governor-signed transactions, structurally absent from the orchestrator per P-D26 (4)) and 6 (explorer verification) remain outstanding. `TVL_ORACLE` now EXISTS at nonce 126, so PB3.8 rung f, which had never executed even in simulation, is unblocked for the first time, and rung i — the live governance and seeding broadcast per PB-D41 (xi) — sits behind it. One archaeology finding closed alongside: deployer nonce 124 was an unrecorded 0.05 SepETH transfer funding the PB-D47 third sender, exposed by phase 4's own nonce arithmetic and now recorded in deployment-record section 10.
**Rung f and the seeding are BROADCAST — the constellation is capitalised and the oracle is populated.** Rung f ran `WireTVLOracleSepolia` on 2026-08-02 as 62 transactions at nonces 239 to 300, blocks 11404897 to 11404966, 3,264,803 gas for 0.00341643207547946 ETH: sixty `setTokenUnderlying` writes, then `addConstellationPool` seating der Bodensee and `addHopUnderlying` seeding the PB-D43 (vi) intermediate, in that order because PB-D45 requires the whole map to precede the roster call, and the 252,390 gas that call consumed against roughly 48,676 for a map write is itself the evidence the ordering mattered. Rung i2 then ran `SeedMiliariumPoolsSepolia` as 389 transactions at nonces 301 to 689, blocks 11405061 to 11405532, 33,643,685 gas for 0.035700732881202711 ETH, capitalising all 26 Miliarium pools across 177 approve, 127 mint, 59 deposit and 26 initialize with every receipt successful. The deployer's nonce reads 690 and its balance is roughly 5.72 SepETH. Deployment-record sections 12 and 13 carry the narratives, and `docs/STAGE_P_BIS_TVL_WIRING_LEDGER.md` and `docs/STAGE_P_BIS_POOL_SEEDING_LEDGER.md` carry all 62 and all 389 rows, generated from forge's own artifacts rather than transcribed because `broadcast/` is gitignored.
**Two design findings came out of the seeded state and drove the PB3.8i2—i9j chain that closed them.** PB-D50 (`docs/STAGE_P_BIS_NOTES.md` L811, Decisions row at `docs/STAGE_P_BIS_PLAN.md` L101) disposes as FIX with an H-D9 amendment: `TVLOracle._venueRatio` returns a bare balance ratio carrying no weight term, which H-D9 specifies verbatim and justifies as exact at AMM parity, and that lemma is false wherever quote and base weights differ, which is every venue in the constellation. With 26 pools seeded and no swap executed `tvl()` sums to 1,271,468 svZCHF against roughly 987,000 accounting; ixHelvetia closes the arithmetic without remainder through nine venues at ratios 4 and 1 for an unweighted mean of 4/3; and slots 11 and 17 read 33.75 percent apart at identical 70,000-dollar allocations, firing H-D9's own materially-wrong-F-7-rankings escape clause pre-mainnet. The fix is the minimal weight term and explicitly not StableMath, and its clause (ix) provenance question — normalized weights are pool-self-reported rather than Vault-authoritative, the same F-12 caveat `GaugeEligibility` already carries — is a typed-domain blocker to settle in notes before any code lands. PB-D51 (L835, plan row at L102) records the independent seeding-side finding as a Stage-R gate with no Sepolia remediation: Balancer normalized weights are value weights, so mainnet must fund `weight_i * V / P_i` against a price source named in advance, and `TVLOracle` is disqualified as that source while PB-D50 is open because funding legs through the same biased estimator is self-concealing. Neither finding explains the other's Sepolia face and they close independently.
**That chain is COMPLETE and every gate is green; the `_venueRatio` rebuild is BUILT, but live Sepolia is deliberately NOT re-broadcast.** H-D9 gained its v2 amendment at `docs/STAGE_H_NOTES.md` L61, withdrawing only the exact-at-AMM-parity lemma and leaving balance-ratio averaging intact. PB-D52 resolved PB-D50's clause (ix) as a factory-provenance gate ordered BEFORE the weight read and SKIPPING rather than reverting (a pricing mean fails local where an admission check fails loud), then priced the fix's true cost as a ten-contract Sepolia cascade and DECLINED it: the corrected oracle is proven on a Sepolia fork and live Sepolia keeps the biased oracle until Stage R. RB-015 files PB-D51 under a new Degenerate-parameter scoping hardening class; RB-016 files the `GaugeEligibility` weights-before-provenance ordering wart under the existing Contract-identity verification class. PB-D53 settled the four typed-domain questions the build needed: the weight term AGGREGATES in lockstep with the balance sums, since a summed balance carries the summed weight of exactly the legs that produced it; both new guards SKIP; the return is `(balQuote * wBase * 1e18) / (balBase * wQuote)`; and the factory enters as a constructor immutable. PB-D54 recorded a pre-flight finding that reshaped the ripple — the unit suite priced venues that DO NOT EXIST, codeless `makeAddr` addresses answered for by `MockVaultExplorer`, so venues became real contracts through the tree's first `vm.etch`, justified by assertion freeze rather than convenience, at equal weights that preserve the existing expectations. PB-D56 measured the unit re-gate green at 957 and corrected PB-D54 (iv) to eighteen-preserved-one-corrected, the sole mover being `test_tvl_venueMultiTokenSummingPerUnderlying` from `100e18` to `200e18`; that correction is POSITIVE evidence, because a single-leg implementation would have left it unchanged and passed silently. PB-D57 then closed a defect only the mainnet-fork suite could see: the gate was too narrow by one factory, since a constellation venue is a PRICING SOURCE rather than an Aureum-owned asset and the two-hop fixture's `hopVenue` is created by the canonical upstream `wpf` — so trust became DISJUNCTIVE across `WEIGHTED_POOL_FACTORY` and `AUREUM_WEIGHTED_POOL_FACTORY` held as two constructor immutables, and PB-D55's `BODENSEE_POOL` exemption RETIRED into that general rule. PB-D58 is the closing measurement: 959 unit across 57 suites, `StageHIntegration` 12 of 12 with the two-hop test passing, `StageIIntegration` 4 of 4, and the P10 close gate 13 of 13 unmoved. `src/emission/TVLOracle.sol` now runs 382 lines behind an eight-argument constructor, and the eleven-site construction ripple ran twice.
**PB-D52 (viii) and (ix) are both DISCHARGED, and the fix now has its evidence.** `test/fork/PB52SepoliaOracleEvidence.t.sol` passes 3 of 3 against live Sepolia state per PB-D59: forked at block 11410000, above the 11405532 that closed the rung-i2 seeding, a corrected `TVLOracle` is stood up in process with only its own governance state re-bound and no pool re-capitalised, the live oracle still returns `14933333333333333332400` for ixHelvetia while the corrected one returns exactly `14_000e18` at the same block against the same balances, and the 26-pool corrected sum falls far below the biased 1,271,468 total. The premise assertion runs first deliberately, so a passing 14,000 is the estimator changing rather than the state differing. This is the tree's ONLY Sepolia-fork test, so the fork gate is now TWO PASSES with `cp .env.sepolia .env` and `cp .env.mainnet .env` between them, always canonical to working copy and never the reverse, and `.env` must be returned to mainnet afterwards or every mainnet fixture silently resolves its literals to codeless addresses, which is PB-D35 exactly. PB3.7a landed `script/config/SepoliaPhase4Addresses.sol`, the committed named-constant library for the sixteen phase-4 addresses, which unblocked the registry bind and discharges RB-014 for that set; no slot-keyed pool table was needed after all, because the concrete `MiliariumRegistry` also implements `IMiliariumSlotRegistry` and the test resolves ixHelvetia through `poolAtSlot(1)` on chain rather than from a transcribed table. Deployment-record section 13 now states plainly that the live `TVLOracle` at `0xBf78A49b1AB86247198f6660Bf5a0491007E6A64`, phase-4 nonce 126, remains pre-fix BY DECISION rather than by omission, per the ten-contract cascade PB-D52 (vii) priced and PB-D52 (viii) declined, so every `tvl()` figure in that record is the biased estimator's output and not the protocol's valuation of those pools.
**F-21 surfaced and closed 2026-08-05 across PB3.8p—u, the first whitehat finding raised since the Stage-P sweep.** `AureumGovernance._voteSucceeded` made its quorum test vacuous at a zero `getPastTotalSupply(snapshotBlock)`, after which the `CompositionChallenge` branch's non-strict `forVotes * 3 >= totalVotes * 2` returned true at `0 >= 0` and a composition challenge Succeeded with no vote cast by anyone, capturing a Miliarium slot through permissionless queue and execute. That denominator is zero for the first 60 days of EVERY chain, not as an edge case but as the launch condition — `VotingWeight._positionPower` short-circuits below the 432,000-block EMA maturity so `poke` never pushes a checkpoint — and the same invariant zeroes every possible against-vote, so F-01's one-honest-vote mitigation cannot fire and no defense exists inside the window. Capture costs a 1,000 svZCHF deposit, no voting weight and 122,400 blocks, across all 26 filled slots in parallel, with no administrative remedy since `DeployStageK` L159 bound `MiliariumRegistry` governance to `AureumGovernance` and both `replaceSlot` and `setGovernanceContract` are `onlyGovernance` there. Adjudicated High / FIX as PB-D62 (`docs/STAGE_P_BIS_NOTES.md` L1004, Decisions row at `docs/STAGE_P_BIS_PLAN.md` L108) and closed by a zero-supply guard at the denominator (`1fc0c66`), with the PoC inverted to regression (`ccccc19`) and the ledger row at `docs/white_hat/AUREUM_WHITEHAT_OUTPUT.md` L68. The F-06 carry test that had recorded this exact condition as open since Stage L inverted alongside the two PoC tests, three rather than the two the first blast-radius sizing predicted. Part-A gate 961/961 green across 57 suites. The `formal/` bundle needs NO re-gate for this — its four surfaces are the fee-routing hook, the CCB/EMA engine, emission accrual and the authorizer window, and none asserts anything about `_voteSucceeded` or the quorum tally; checked rather than assumed.
**Next: the F-22 ladder is complete, so workstream B resumes at phase 6 explorer verification — still blocked, though the block is narrower than it has been recorded: `ETHERSCAN_API_KEY` now exists as a provisioned but EMPTY slot in all three of `.env`, `.env.sepolia` and `.env.mainnet`, so an operator supplies a value rather than adding a line, and until that lands the base layer, all twenty-six pools and the sixteen phase-4 contracts stay unverified on the explorer. Then PB3.9 (der Bodensee dust initialization and the first F-0 distribute, gated on the sealed `GENESIS_BLOCK` 11477620) and PB3.10 (F-14 ops and fee-custody rails) carry zero commits and are not started. Also open: one question surfaced at PB3.6d-d and deliberately left unanswered there: whether ANY caller can reach `pausePool` / `unpausePool` after the dissolution handoff. The corrected `DissolutionGovernanceHandoff.t.sol` attestation establishes only that `AureumGovernance` cannot — it holds the permission through the non-exclusive `pauseManager` fallback but has no code path emitting the call — while the per-pool `pauseManager` itself and `EMERGENCY_MULTISIG` were never run down; if pause proves reachable and unpause does not, that is F-22's signature failure reproduced at pool scope, and it wants an answer before Stage R. CLOSED since this sentence was first written, and recorded here so the next reader does not redo any of them: the `formal/` re-gate is DONE at 55 of 55 with zero rework per PB-D60 (PB3.8i12), because no hevm or Act surface asserts the venue ratio PB-D50 changed — the proofs stub `tvl()` and `ema_sampler.act` records `updateEMA` as RESIDUAL; runbook phase 5's Router seat is BROADCAST at nonces 690 and 691 per PB3.8n, in deployment-record section 14, carrying the PB-D61 `governanceModule` disqualification forward as the RB-017 Stage-R gate; the `STAGE_P_BIS_PLAN.md` Decisions table is COMPLETE at PB-D1 through PB-D64 with no gap, the PB-D57 through PB-D61 backfill landing at PB3.6d-h1; the `STAGE_P_BIS_PLAN.md` Completion Log is CURRENT through PB3.7h1; the PB3.6-versus-PB3.10 renumber is DONE at PB3.6d-f3 and f4, so PB3.6 now names the F-22 fix step in both the Surfaces table and the roadmap while F-14 moves to PB3.10; and this section 11 paragraph itself is no longer one 49,992-character line but 45 ordinary lines per PB3.6d-g1, the reflow proven byte-identical by rejoin-and-hash, so the two approved Python exceptions the F-22 close needed (PB3.6d-doc1, PB3.6d-f7) should not recur.**
The resume-posture question PB-D48 (viii) left UNVERIFIED is CLOSED as PB-D49 (`docs/STAGE_P_BIS_NOTES.md` L789, Decisions row at `docs/STAGE_P_BIS_PLAN.md` L100, operator procedure at runbook section 9's R1 through R6): `forge script --help` states that `--resume` does not re-simulate and expects nonces to have remained the same, which retires the `vm.setEnv` threading hazard outright, since no re-execution means the threaded in-process handles are never re-derived and the frozen artifact replays correctly because a CREATE address is a pure function of sender and nonce. `--slow` is locked as the other half of the pair rather than optional seasoning, being what gives a stalled run a clean confirmed-versus-unsent boundary; nonce reconciliation before any resume is MANDATORY rather than advisory, because section 8f's no-receipts artifact is precisely what produces the mismatch that makes a resume fail; and the nine-way decomposition through the sub-scripts' own `run()` entries is REJECTED on PB-D13's ground now that replay is confirmed. Zero code changed by any of it. A runbook defect surfaced during the h9g pre-flight and was fixed at h9f4: nine commands passed the RPC URL as `$SEPOLIA_RPC_URL`, which the shell expands to an empty string before foundry ever launches because the shell never reads `.env`, so every one of them failed on a missing-value error; they now use the `foundry.toml` L103 `sepolia` alias, except the resume invocation, which lifts the literal value out of `.env` by command substitution because foundry issue 4346 reports `--resume` not resolving aliases. Carries: the Etherscan API key remains absent, so the base layer, all twenty-six pools and the sixteen phase-4 contracts stay unverified on the explorer as a phase-6 obligation; two operator-environment hazards are unlocked — a shell that EXPORTS `STUB_` keys silently overrides `.env` through `vm.envOr` and defeats PB-D36 by a channel PB-D36 never covered, so `env | grep -cE "^(STUB_|SUSDS=|SV_ZCHF=)"` must read 0 before any mainnet fork run, and the fork suite must be invoked file-scoped because a whole-tree `--match-path "test/fork/**"` run fails on D36's sequential face even under `--threads 1`; and two stale citations want correcting, `test/fork/DissolutionGovernanceHandoff.t.sol` L139 pointing at `deploy-miliarium-pool.s.sol` L75 when the `pauseManager` assignment now sits at L132, and this file's own §2 RPC row reading Ankr when both env files resolve to Alchemy.
PB2.10 (the aumm-site spec edits, `STAGE_P_BIS_PLAN.md:89`) remains the user-side parallel track — restored to its pre-OQ-23 roster per PB-D18 (i) — gated to match the code before PB5.
**F-22 is FIXED — the most severe finding raised on this project at Critical, and with it the whitehat ledger carries no open findings.** `AureumGovernanceAuthorizer.canPerform` granted the governance contract every actionId unconditionally, but `AureumGovernance.execute()` dispatched over a fixed proposal-type enumeration carrying no target field and no calldata field, so nine of the Vault's eleven `authenticate`-gated admin entries were permitted to governance and reachable by no caller at all. The two survivors, `pauseVault` and `enableRecoveryMode`, are both ENTRIES whose inverses sat among the nine, so every emergency lever was a door that opens only inward: an unpausable pause lifts only at the Vault's buffer-period end, roughly four and a half years out, and recovery mode never self-clears and is therefore permanent. `enableRecoveryMode` also skips authentication entirely once anything is paused, so any anonymous address may then place any pool into permanent recovery mode. Severity Critical because the trigger is CORRECT USE rather than misuse — a responder doing exactly what the mechanism exists for is what arms it — while custody stays intact throughout, since pools in recovery mode still permit proportional exit. Adjudicated across PB-D63 (`docs/STAGE_P_BIS_NOTES.md` L1034, the finding and the two-layer fix shape) and PB-D64 (L1058, the build shape, amending PB-D63 (ix) from one proposal type to three, plus clause (x) at f1 naming the `AuthorizerNotContract(address newAuthorizer)` guard error); disposition FIX-in-source-for-Stage-R, Sepolia NOT remediated by decision exactly as PB-D52 (viii) left the live oracle, and the CircuitBreaker architecture DESCOPED to its own track so it cannot gate Stage R. All six rungs of the PB-D64 (ix) ladder are DONE. **a** (`5bef424`) widened the authorizer emergency set from two actions to four, pairing each entry with its inverse, unit suite 12 to 14 tests with the fuzz-exclusion assume set repaired to all four. **b** landed in two commits: `4e15d3c` for declarations, the three appended `ProposalType` values plus the `IAuthorizer` import and the `AuthorizerNotContract` error, then `a8cfa8b` for expressibility, the fourteenth `Proposal` member `newAuthorizer`, the seventh `_createProposal` parameter, the `VaultAuthorizerChange` join to the two-thirds branch in `_voteSucceeded`, and an `_executeProposal` whose trailing bare `else` — silently bound to `FeeChange`, the exact fallthrough shape F-22 itself diagnoses — became an explicit six-branch else-if chain with no catch-all, without which all three new types would have called `setStaticSwapFeePercentage` on a zero pool. **c** (`957ec73`) added twelve reachability unit tests plus the mainnet-fork keystone witness driving `setAuthorizer` through a genuine propose/vote/queue/execute cycle, and reframed the PoC from proof-of-defect to attestation-of-accepted-residual. **d** (`0c6024c`) landed the three stale-artifact corrections PB-D63 (vii) names. **e** (`8d394a0`) added the F-22 ledger row at Status Fixed, surface S8, confidence Confirmed. **f** (`e3521e1` onward) closed the bookkeeping: the NOTES clause (x), the PB-D63 and PB-D64 Decisions rows, the PB3.6-to-PB3.10 renumber across the Surfaces table and the roadmap, the Completion Log family, and this update. Part-A gate 975/975 across 57 suites; fork suites file-scoped 14/14 (`StagePIntegration.t.sol`) and 3/3 (the PoC). The ACCEPTED RESIDUAL is load-bearing and must not be read as an oversight: `setProtocolFeeController` and the other non-exit entries stay unreachable BY DESIGN, because PB-D63 (xi) scopes F-22 to the exits plus the keystone and nothing more, which is why the PoC stays green rather than inverting. Closing that residual is the CircuitBreaker track's job and is explicitly not a reopening of this finding.

**Completed-stage ledger** — one line per stage; full detail in each stage's `_PLAN.md` Completion log + `_NOTES.md`, whitehat detail in `docs/white_hat/AUREUM_WHITEHAT_OUTPUT.md`:

- **K** — governance handoff: `AureumGovernance` (three proposal types) + `VotingWeight` + `AureumGovernanceAuthorizer` (OQ-10 12-month time-bomb); Vault authorizer migrated via `setAuthorizer` CALL, Vault bytecode untouched. Tag `stage-k-complete`.
- **L** — Incendiary Boost: `IncendiaryRegistry.buyBoost` (five gates, 60-day EMA pricing, L-D6 15%-of-epoch cap, der-Bodensee deposit tail) + the L-D25 `poolBoostCursor` delivery leg in `EmissionDistributor`. Tag `stage-l-complete`.
- **M** — Miliarium Sector-2 Majors: five yield-core pools (03/08/09/10/11) deployed + bound via bind-only `DeployStageM` (M-D9 preconditions); gaps 02/04/06/07 deferred (M-D7). Tag `stage-m-complete`.
- **N** — Sector-3 tranche: 18 pools (16 Standard slots + ex-M Majors 02/06); first Aureum-owned `src/rate_provider/` surface (N-D2 ERC4626 + N-D9 composite, F-11 guard); 04/07 still deferred. Tag `stage-n-complete`.
- **O** — OQ-7 composition-fitness gate: `GaugeEligibility.meetsCompositionQualityGate` delegated through `GaugeRegistry`, gating `AureumGovernance` composition challenges (supersedes K-D6e per O-D2/O-D7). Tag `stage-o-complete`.
- **P** — white-hat back-fill sweep (WH-D/G/H/I/J/L + WH-P6 synthesis + P6.5 invariant harness; surfaced F-13…F-20) + full-system deploy validation (P9 granular scripts + `DeployStageP` orchestrator + P10 mainnet-fork validation on the P-D36 7-leg roster; P-D40 `swapFeeManager` fix, P-D42 coverage waiver). 877 unit / 136 fork green. Tag `stage-p-complete`.
- **Whitehat passes** — K-pass F-01…F-04 (`stage-k-whitehat-complete`); WK-R F-05/F-06; WL F-07; WM F-08/F-09/F-10; WN F-11; WO F-12; Stage-P sweep F-13…F-20. All fix-forward, no re-tags.

**Branch / tag state:** `stage-p-complete` tagged (at the P11-backfill commit) and ff-merged to `main` — no divergence; Stage P ran on a fresh `stage-p` branch off `main` @ f50b4cd (P-D4). Tags `stage-a-complete` … `stage-o-complete` + `stage-p-complete` + `stage-k-whitehat-complete` all in place. Whitehat ledger carries ZERO open findings — F-01…F-22 = 20 Fixed (F-22 the newest and the most severe raised on this project, Critical, the post-Stage-K Vault admin surface permitted to governance and reachable by no caller, closed across PB3.6a—PB3.6d-f8 per PB-D63 / PB-D64; the exits and the keystone are restored, while the remaining non-exit entries stay unreachable BY DESIGN per PB-D63 (xi), which is why its PoC stays green rather than inverting) + F-13 SPLIT (routeYieldFee path Fixed via caller-supplied bounds / onAfterSwap Accepted-risk S5 Low — PB2.4 / PB-D9) + F-15 Accepted-risk (S9 Low, closed standalone per PB-D10 / PB2.5 — poke-invariant truth ceiling, live reads retained by design, evidence sim 6/6; the last P-bis workstream-A whitehat adjudication).

**Deferred carry-forward** (live obligations — Stage P-bis workstream A owns every item below, plus the ex-Stage-Q queued inputs named in the Last-update paragraph):
- **aumm-site spec edits (user-side)** — `04_tokenomics.md` §viii/§ix per OQ-20/21 + the I-reframe (I-D14—I-D17); §xxi sandbox row (G-D2); `11_formulas.md` F-2 Incendiary amendments per Stage L + the FINDINGS Incendiary-scope corrections (L269/L348/L369/L377); the PB-D8 (iv) items — `03_ixCasper.md` Fluid-vs-"Flux Finance" mislabel, `04_ixViatica.md` "Flux Finance BRZ" wording, `07a_tokens.md` slot-03 waEthwstETH-RP row (M-D11 "unresolvable" → the PB-D8 Aureum-composite restoration).

Dropped as CLOSED: D33 (no custom Router, O-D5 — the Router redeploy/bind is owned by P-bis workstream B); the whitehat back-fill queue (ran at Stage P; see the Stage P line + the ledger); the pool-restoration set — Majors 04 ixViatica / 07 ixCambio + ixCasper waEthwstETH + the OQ-I10 remainder (PB2.3 / PB-D8: ixCasper BUILT, 04/07 DESCOPED to the Stage-O challenge path, OQ-I10 closed); the multisig-dissolution gap (PB2.6 / PB-D2 + PB-D11 + PB-D12: the dissolution-time rotation script + fork witness BUILT, 5/5 fork-green; §xxix unamended); the D36 permanent fix (PB2.7 / PB-D13: DESCOPED — `--threads 1` permanent canonical posture, the branch-(b) parameterization → RB-006); and the direct `ReentrancyGuard.selector` test (PB2.8 / PB-D14: BUILT — `test_Distribute_RevertWhen_Reentrant_DirectGuard` via roll-plus-accrue mock reentry through `MockVault.settle`, RB-007 created Closed; the H3.7e bubble-up test retained as the stale-accrual pin); and the WK.18 thin-venue economic-exploit could-not-assess (PB2.11 / PB-D16: BUILT — `test/fork/WK18ThinVenuePumpSim.t.sol` 6/6 fork-green, the populated-roster positive-control + sustained-pump economics quantifier closing the R1-blocked could-not-assess; F-04 stays Fixed via the 60-day EMA gate, no findings-table change).

Loop grep-and-confirm per §6 / §8e; all git mutations in user's terminal; Cursor executor-only per §7 + §8e.

### Housekeeping notes

* `.cursorrules` was amended on 2026-04-19 to replace the "text-editor only" lockdown with the "Cursor operation scope — executor under Claude Code planning" section. Respect it.
* Cursor Auto-Run stays "Ask Every Time," Command Allowlist stays empty, Browser / MCP / File-Deletion / External-File Protection toggles stay on.
* **Claude Code does not write files.** All file writes flow through Cursor. Claude Code plans, authors prompts, audits Cursor's output, drafts commit messages and terminal commands for the user.
* Git mutations (`add`, `commit`, `push`, `tag`) are run by the user in terminal, not by Claude Code or Cursor.
* External canonical spec lives at `https://github.com/aummfi-bit/aumm-site` (default branch `main`), cloned locally at `/Users/janus/code/aumm-site/`. Claude Code reads the clone directly (§8a file reads, e.g. `sed -n` on `/Users/janus/code/aumm-site/11_formulas.md`) — never via WebFetch on raw URLs, which has confabulated spec literals. Ask the user to paste only if the clone is missing or the section is ambiguous. See §4 for the full layout.
* **§8e.1 template is two blocks.** Every filled §8e.1 has a `### CURSOR PROMPT — paste to Cursor verbatim; Cursor only` block and a separate `### USER VERIFY — plan ref: <stage><step>; run in the user's terminal after Cursor's save; not part of the Cursor prompt` block. Cursor never sees USER VERIFY. A USER VERIFY block opens with its header line and then `clear`; commit blocks and every other terminal sequence take no header and begin with `clear` directly. **When Claude Code emits a filled §8e.1 in chat, the two blocks must be in two physically separate ` ```text ``` ` code fences — never a single combined fence — so the user's paste to Cursor cannot accidentally include the USER VERIFY shell commands.** When the same template is pasted into a stage-plan or notes file for editor-preview rendering (per the §8e.1 chat-safe-formatting paragraph hardened at `8197aaa`), each block is also wrapped in its own contiguous ` ```text ``` ` fence so the preview keeps each block as a single copyable unit. See §8e.1 + D31.
* **`.cursorrules` USER VERIFY hard-stop (`5f3b4fc`).** Defense-in-depth on top of the §8e.1 two-block split: if any prompt passed to Cursor contains the literal text `### USER VERIFY`, Cursor must treat everything from that header to end-of-message as out of scope, report "USER VERIFY section detected — treating as out of scope per .cursorrules", and proceed only on the content above. Catches paste accidents where the user copies past the divider.
* **§13 Sonnet dispatch is not session-scoped.** Every filled §8e.1 turn must close with the Sonnet dispatch line per §13's "Relay after a §8e.1 draft" — across sessions, resumes, and compactions. If Claude Code forgets, user says "mode?" and Claude Code emits the dispatch.
* **Cursor backtick-stripping in plan-doc rewrites.** At D32 follow-up §D7.1e plan rewrite (2026-04-24, `fbdef2f`), Cursor stripped all backtick characters from the replacement paragraph when given a code-block-delimited replacement text. Fix required explicit "backtick characters are literal; do not strip" in the Instruction plus spot-check grep of backtick-wrapped strings in Must match. Watch for this pattern when rewriting paragraphs with many inline code references.
* **Engineering-lesson index** — incident-derived drafting rules, one line each; the full recipe lives in the stage NOTES file the code's letter names (§5). When a trigger matches the work at hand, grep that NOTES entry before drafting:
  - **D22** — `IVault.unlock` inner callbacks: outer `abi.decode(result, (uint256))` needs inner `returns (uint256)`, not encoded `bytes`.
  - **D24** — sub-step prompts state the scope boundary explicitly; audit Cursor's output against that boundary.
  - **D31** — no shell commands inside the Cursor payload; the §8e.1 two-block split is the structural fix.
  - **D32** — mainnet Router is Vault-bound; fork init = (β) `Vault.unlock` + `IVault.initialize` + per-token `transfer`/`settle`, no Router, no Permit2. Also `balancer_v3_reference.md` §1.
  - **D34** — paired-surface specs (hook + controller) need cross-side selector/interface assertions in unit tests.
  - **D35** — never `forge test --fork-url` unfiltered (rate-limit hang); split-form: `--no-match-path "test/fork/**"` for unit, `--match-path "test/fork/**"` for fork.
  - **D36** — `vm.setEnv` races between parallel fork-test contracts; run fork suites with `--threads 1` (permanent posture per PB-D13; RB-006 holds the deferred parameterization).
  - **E10** — forge-std `deal(adjust=true)` reverts on dynamic-supply tokens (Reserve DTFs); drop the third argument.
  - **F10** — the optimizer hoists `block.number` out of `vm.roll` loops; thread an explicit local counter.
  - **F11** — pasted terminal output auto-links TLD-suffix tokens; trust `shasum` / `grep -c "http"` over rendered text; unchanged shasum + "no edit needed" means stop.
  - **F12/F13** — signed-delta arithmetic: compute `int256`, explicit signed-add helper, clamp before casting back to `uint256`; applies to test-side chains too (SafeCast + `_applySignedDelta`).
  - **F14** — after a structural test-file rewrite, "compilation skipped" + a contract missing from `forge test --list` means `forge clean && forge build`.
  - **G10/G14** — compile-probe any solc language-feature or data-location claim at the pinned config before a NOTES closure lands; constructor params are always `memory`.
  - **G15** — close-of-family Must match enumerates all scaffold NatSpec promises; an unlanded "X lands at N+k" promise is a blocker.
  - **G16** — interface-touching fix scope: `grep -rn "is I<InterfaceName>" src/ test/ script/` first; name every inheritor.
  - **H13** — before a deploy-script fork-test prompt, audit each consumed constructor for external calls; keccak env placeholders only satisfy ZeroAddress-checked slots.
  - **I10** — rename sub-steps: grep the whole file for the old symbol first; Must match asserts zero stale hits, NatSpec included.
  - **I11** — `--match-test` is Rust regex (bare `|` alternation; `\|` is a literal pipe); prefer `--match-path` for single-file test additions.
  - **I12** — before locking a container shape (immutable set / struct / tuple), grep prior D-numbered bodies for member consumers.
  - **I13** — a fail-fast gate in a shared evaluator intercepts the whole path: size the test blast radius at pre-flight; land fix-forward on the current branch, no re-tag.
  - **PB10** — a chained `orchestrator.X()` getter is a distinct EVM call that `vm.expectRevert` / single-shot `vm.prank` latch onto instead of the intended setter; cache the handle in a local first (recurrence of P-D38, extended to `expectRevert`).
  - **PB11** — an em-dash (U+2014) inside a Solidity string literal is a solc parse error (invalid-character-in-string-literal, seen as Error 8936); §10's em-dash house style is comments / NatSpec only — `require` / `assert` / `revert` reasons and forge assertion messages must be ASCII.
  - **PB12** — a fork sim that rolls `block.number` to mature an EMA also ramps `timeFactor` (`min(timeInPool, ON_RAMP_PERIOD_BLOCKS)/ON_RAMP_PERIOD_BLOCKS`, 180-day cap); pre-roll past the cap to pin it at 1.0 before measuring, or the observed delta conflates the on-ramp with the term under test.
  - **PB13** — net-new prose for Cursor to insert goes INSIDE the CURSOR PROMPT between explicit begin-insert / end-insert banners, never a separate review fence (else Cursor gets the instruction with an empty payload and stops).
  - **PB14** — a file's zero-hit grep sentinel runs against the drafted §8e.1 payload before handoff, not only the saved file after; a payload that names the banned token (even to say it was removed) defeats the file's invariant on faithful transcription — name it, don't quote it. Full recipe: `docs/STAGE_P_BIS_NOTES.md` PB14.
  - **PB15** — a compiler-configuration surface is unverified until a build artifact confirms it: foundry drops wrong-case `optimizer_details` keys SILENTLY (they are camelCase, not snake_case), and a value that reads like a tool's documented default can still be load-bearing — `forge build --build-info` writes the literal standard-json handed to solc and is the diagnostic. Full recipe: `docs/STAGE_P_BIS_NOTES.md` PB15.
  - **PB16** — a source file outside foundry's configured compile roots (`src`, `test`, `script`) is never offered to the compiler, so `forge build` returns green without having read it and proves nothing about it; `test-stubs/` files carry artifacts only via transitive import from a configured root. An artifact directory under `out/` is the only positive proof a file compiled — gate a file outside the roots with `forge build --contracts <dir>` plus `ls out/<File>.sol/`. Full recipe: `docs/STAGE_P_BIS_NOTES.md` PB16.
  - **PB17** — a tool that reads `.env` for its own configuration does not make `$VAR` work on the command line invoking it: the shell expands the line before the tool launches and has never read that file, so `--rpc-url $SEPOLIA_RPC_URL` dies on a missing-value error while `--rpc-url sepolia`, the `foundry.toml` `[rpc_endpoints]` alias, works. A loud failure an operator routes around by hand leaves the document wrong for the next reader — a command form is unverified until run verbatim from a clean shell. Full recipe: `docs/STAGE_P_BIS_NOTES.md` PB17.
  - **PB18** — a count quoted in a §8e.1 `Must match` or USER VERIFY line is a prediction until a tool produces it: an em-dash tally read off a drafted payload by eye missed four times in one session, each miss spending a fix round on a save that was in fact correct. Count the payload mechanically before handoff — pipe the exact text through `grep -o` and `wc -l` — so the sentinel measures the save rather than the drafter's arithmetic. Extends PB14, which fixes when the sentinel runs but not who counts.

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

### Ambiguity-gate for typed domain and state semantics

Any ambiguity in **typed domain** (accepted token set, enum, immutable-vs-storage slot layout, error parameter shape, pool-class enum, fee-token whitelist) or **state semantics** (one-shot vs idempotent setter, burn-vs-keep admin slot, transient vs persistent storage, single-slot vs dual-slot mirror) is a hard blocker on the next §8e.1 execution prompt. Resolve in notes — amend the offending wording, lock the decision in a `G-D` / `D-D` / `E-D` / `F-D` entry, or update the relevant FINDINGS row — before Cursor materializes the slot layout in code.

"Fix it later" after a scaffold lands carries (a) re-reading already-saved code to spot the divergence, (b) editing it, (c) updating tests that now assume the wrong shape — strictly more cost than fixing the wording first. The grep-and-confirm loop catches misexecution; the ambiguity-gate catches misdirection. Both are required.

The ambiguity-gate fires whether the ambiguity is in the canonical spec (`aummfi-bit/aumm-site`), in a stage `_NOTES.md` decision, in a stage `_PLAN.md` body, or in `FINDINGS.md`. The cure is always the same: notes first, code after.

### Blocker classification — fewer, sharper blockers

Extends the ambiguity-gate above — not every audit or pre-flight concern is ambiguity-gate severity. Before flagging something as blocking the next §8e.1, classify it:

* **Blocks contract-spec lock** — changes a typed-domain or state-semantics decision (the ambiguity-gate above) that Cursor is about to materialize in code. A true hard blocker: resolve in notes first.
* **Pre-mainnet gate** — must be resolved before Stage R broadcast but does not change the current sub-step's slot layout or signature (a deferred robustness backport / `RB-*` row, an ops-custody item like F-14, a coverage-tooling gap like P-D42). Record it in the §11 carry-forward or the `RB-*` register and proceed.
* **Implementation detail** — a naming, comment, or local-structure preference with no spec or downstream consequence. Note it inline at most; do not block.

Default to fewer, sharper blockers: a long list of mixed-severity "blockers" trains the reader to skim past the one that actually blocks. Unsure between the first two classes → treat as a spec-lock blocker (the §12 default). Unsure between the last two → implementation detail, do not block.

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

- **One actionable per turn.** A chat turn carries at most one thing the user must act on — a commit block *or* a §8e.1 prompt *or* a dispatcher line — never a commit block stacked with the next §8e.1. The two are separated by the user's execution of the commit and, per the up-hand, a model switch; stacking them makes the user interleave a git commit and a Cursor paste in one turn and tangles the paste-back. When a **✅** closes a commit-worthy sub-step, that turn ends at the commit block plus the up-hand dispatcher; the next **§8e.1** is the following Opus turn. This does not conflict with **Relay after a §8e.1 draft** — that bundles one §8e.1 with its Sonnet-relay line, a single user action (the paste to Cursor).

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
| P-bis (current — open-issue close-out + testnet go-live + frontend) | Opus high | Read-backs, commit drafts, deploy-script scaffolding |
| Q (external audit engagement) | Opus extra-high | Nothing — stay on Opus |
| R (mainnet deployment) | Opus extra-high | Nothing — stay on Opus |

Stages A through P are complete; their entry-mode rows live in git history. From Stage P-bis onward, Claude Code announces mode at entry and at each natural beat within the stage.

### Token discipline (real levers, not ceremony)

- Read line ranges, not whole files, once the region is known.
- Do not re-read a file already in context this session.
- For "where is X referenced" across more than three files, spawn Explore — its context stays out of the main thread.
- Trust CLAUDE.md §11 as the resumption anchor. Do not re-read full plan + full NOTES on session start; read the named sub-step + the named file regions.
- The **§8e.1** template is the forcing function against re-scoping. Use it verbatim.
