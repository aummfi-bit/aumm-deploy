# Stage A — Foundry Environment Setup

> **Status:** Active. Do not move to Stage B until every step here is checked off and the `stage-a-complete` git tag is pushed.
> 
> **Audience:** Sagix, on a Mac, in Cursor, with limited prior Foundry experience.
> 
> **Why this file exists:** so the plan survives outside chat scrollback. If a Cursor session is reset, an LLM context is lost, or a tab is closed, this file is the source of truth for "what was Stage A and where am I in it."

---

## Scope of Stage A (read this twice)

**Goal:** A working Foundry environment, in Cursor, that can compile against the Aureum-owned fork of `balancer-v3-monorepo`, and can run a sanity test against a mainnet fork. **Nothing Aureum-specific is written in Stage A.** No `AureumVaultFactory.sol`, no `AureumProtocolFeeController.sol`, no `AureumAuthorizer.sol`, no deploy script. Those are all Stage B (see `STAGE_B_PLAN.md`).

**What "done" looks like — the four checkpoints:**

1. `forge build` succeeds, importing at least one type from `@balancer-labs/v3-interfaces/...` via the submodule.
2. `forge test --fork-url $MAINNET_RPC_URL -vv` runs `Sanity.t.sol`, which forks mainnet at a recent block, instantiates `IVault` against the live Balancer V3 Vault address, calls one safe view function, and the test passes.
3. The repo is pushed to `github.com/aummfi-bit/aumm-deploy`.
4. The commit at which both 1 and 2 are true is tagged `stage-a-complete` and the tag is pushed to the remote.

If any of these four are not true, **Stage A is not done** and Stage B does not start.

---

## Architectural decisions locked in (do not relitigate without writing it down here first)

| \\# | Decision                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Rationale                                                                                                                                                                                                                                                                                                                                                               |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Aureum deploys its own **parallel instance** of the Balancer V3 Vault using **byte-identical bytecode** for `Vault.sol`, `VaultAdmin.sol`, `VaultExtension.sol`. These three files are **never edited**.                                                                                                                                                                                                                                                                                                                          | Audit-inheritance argument from `aumm-site/13_appendices.md`: pool contracts, vault, SOR, hooks, and rate providers are byte-identical to the Certora-verified Balancer V3 code. The audit and formal verification apply directly. Only the tokenomics layer requires independent audit. The moment we edit any of those three files we owe an independent Vault audit. |
| 2   | Fee customization happens **only** in `AureumProtocolFeeController.sol`, an Aureum-owned contract that implements `IProtocolFeeController`. The Vault delegates to it via constructor parameter.                                                                                                                                                                                                                                                                                                                                  | `IProtocolFeeController` is the documented Vault extension point. Swapping it does not break byte-identity of the Vault.                                                                                                                                                                                                                                                |
| 3   | Fee split: **50% of swap fees** (the maximum the V3 Vault permits via `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE`) routes to der Bodensee. The other **50% stays in-pool with LPs**. **No creator fee. No treasury.** Yield fees: 100% of the protocol-extractable share routes to der Bodensee, subject to `MAX_PROTOCOL_YIELD_FEE_PERCENTAGE`.                                                                                                                                                                                           | User direction. Consistent with V3 Vault hard caps. The phrase "100% of the fees that v3 allows goes to der Bodensee" reduces to "the full protocol-extractable share, which is at most 50% for swaps and at most 50% for yield."                                                                                                                                       |
| 4   | The Vault's admin surface area (`pauseVault`, `enableRecoveryMode`, `setProtocolFeeController`, `setStaticSwapFeePercentage`, etc.) is gated by `AureumAuthorizer.sol`. The authorizer grants permissions to **a single Safe multisig address**. The multisig itself only acts on passed governance proposals (Snapshot to Safe transaction). On-chain, the authorizer just sees one privileged address.                                                                                                                          | Matches "no treasury, no wallet" in spirit while preserving the ability to pause/recover for the Balancer-default 4-year window. After the pause window expires, even the multisig cannot pause.                                                                                                                                                                        |
| 5   | **Option F2 chosen** for fee controller substitution: fork `VaultFactory.sol` into `AureumVaultFactory.sol` and modify the constructor + the `new ProtocolFeeController(...)` line so an Aureum-owned `IProtocolFeeController` is passed in at deploy time. **Only `VaultFactory.sol` is modified.** `Vault.sol`, `VaultAdmin.sol`, `VaultExtension.sol` remain byte-identical. The audit-inheritance argument is about the Vault contract, not the factory — the factory is a one-shot deployer that runs once and is abandoned. | Cleaner than F1 (deploy stock + swap). One transaction instead of two. No orphan stock fee controller. No 1-block window where the Vault points at a non-Aureum controller. The diff against Balancer's factory is small enough (\~5 lines) to read in 30 seconds during any audit.                                                                                     |
| 6   | **`AureumVaultFactory.sol` lives in `aummfi-bit/aumm-deploy/src/`**, NOT inside the `aummfi-bit/balancer-v3-monorepo` fork. The fork stays a pristine pinned reference of upstream Balancer code. The modification is a single new file in `aumm-deploy` that imports `VaultExtension`, `VaultAdmin`, `Vault` creation code from the submodule.                                                                                                                                                                                   | Keeps the fork's git history clean and easily diffable against upstream. Keeps Aureum-owned code in the Aureum-owned repo where audit scope lives.                                                                                                                                                                                                                      |
| 7   | Pause window: **4 years** (matching Balancer mainnet defaults). Buffer period: **6 months**. Both immutable, set in the `AureumVaultFactory` constructor. After 4 years from deployment, even the governance multisig can never pause the Vault again.                                                                                                                                                                                                                                                                            | Matches "the AMM you're depositing into is the same code" — Aureum uses the same operational safety net Balancer chose for itself. Strict immutability kicks in at year 4.                                                                                                                                                                                              |
| 8   | Solidity compiler **pinned to `0.8.26`**, EVM `cancun`, optimizer runs **9999**, `via_ir = true`.                                                                                                                                                                                                                                                                                                                                                                                                                                 | Matches Balancer V3 mainnet exactly (verified compiler from Etherscan: `v0.8.26+commit.8a97fa7a`, `cancun`, optimizer 9999). Maximizes confidence the bytecode we compile for the un-modified Vault contracts matches what Balancer themselves shipped.                                                                                                                 |
| 9   | The `aummfi-bit/balancer-v3-monorepo` submodule must be pinned to a **commit where `pkg/vault/contracts/VaultFactory.sol` matches the verified Etherscan source at address `0xAc27df81663d139072E615855eF9aB0Af3FBD281`** (the canonical Balancer V3 Vault Factory deployed Dec 4, 2024). Identifying that exact commit happens in Step A5.                                                                                                                                                                                       | Audit-inheritance only holds against the *exact* code Balancer audited and shipped.                                                                                                                                                                                                                                                                                     |
| 10  | Stage A's sanity test does **not** deploy a Vault. It only forks mainnet, instantiates `IVault` against the live Balancer Vault address, and calls one view function. The Aureum Vault deployment is Stage B.                                                                                                                                                                                                                                                                                                                     | Keeps Stage A small, scoped to "did the toolchain install correctly", and verifiable in one sitting.                                                                                                                                                                                                                                                                    |
| 11  | Salt for `CREATE3` deployment: **`bytes32(0)`** for Stage A planning. Vanity address mining (a salt that produces a Vault address starting with a chosen prefix) is a Stage B nice-to-have, not a blocker.                                                                                                                                                                                                                                                                                                                        | Don't block environment setup on cosmetics.                                                                                                                                                                                                                                                                                                                             |
| 12  | Beets docs (`docs.beets.fi`) are a **reference, not a source of truth**. Beets is a Balancer V3 fork on Sonic, not mainnet. When their docs talk about general Balancer V3 mechanics they may be useful as a sanity check. When they talk about Sonic-specific behavior, ignore.                                                                                                                                                                                                                                                  | Per user direction.                                                                                                                                                                                                                                                                                                                                                     |

---

## Key facts pulled from reading the actual `VaultFactory.sol` source

These are not assumptions. They come from reading the verified source at Etherscan address `0xAc27df81663d139072E615855eF9aB0Af3FBD281` (Dec 4, 2024 deployment).

1. **One `create()` call deploys FOUR contracts:** `ProtocolFeeController`, `VaultAdmin`, `VaultExtension`, then `Vault`. The factory orchestrates all four in a single transaction.

2. **The Vault uses `CREATE3` for its own deployment.** This means the Vault address is determined by `(deployer_address, salt)` only — *not* by the bytecode. CREATE3 is what allows Balancer to land its Vault at a known address regardless of constructor arguments. For Aureum: the Vault address depends on which address deploys `AureumVaultFactory` and what salt is passed to `create()`. Mining a vanity salt is possible later if desired.

3. **`VaultAdmin` and `VaultExtension` use plain `CREATE2`** with `(salt, encoded_creation_code + constructor_args)`. They depend on the Vault address, which is computed in advance via `getDeploymentAddress(salt)`.

4. **The factory enforces byte-identity at runtime.** Its constructor takes `vaultCreationCodeHash`, `vaultAdminCreationCodeHash`, `vaultExtensionCreationCodeHash` as immutables. Every `create()` call hashes the supplied creation bytecode and reverts with `InvalidBytecode("Vault")` etc. if it doesn't match. This is the *mechanical enforcement* of "byte-identical Vault deployment" — not just a claim. **Aureum's factory must replicate this same hash check** for the same three hashes, so we inherit the same guarantee.

5. **The factory is `Ownable2Step` and `create()` is `onlyOwner`.** Whoever deploys the factory is the only one who can call `create()`. The factory is single-use in practice (mappings prevent re-deploying to the same target address).

6. **Constructor immutables baked in at factory deploy time:**
	- `IAuthorizer authorizer`
	- `uint32 pauseWindowDuration`
	- `uint32 bufferPeriodDuration`
	- `uint256 minTradeAmount`
	- `uint256 minWrapAmount`
	- The three creation code hashes

   These are decided when the factory is deployed, not when `create()` is called. Implication: the design decisions for the Aureum Vault deployment (pause window, who the authorizer is, minimum trade amounts) get made at **factory deploy time**.

7. **Balancer's mainnet factory was deployed by `0x3877188e9e5da25b11fdb7f5e8d4fdddce2d2270`** in tx `0x49a4986a672bcc20eecf99a3603f0099b19ab663eebe5dd5fe04808c380147b4` at block `21332121`. We can use this address to look up the exact creation code hashes used in Balancer's own factory deployment if we want to verify them against the submodule code.

8. **License is `GPL-3.0-or-later`.** Aureum inherits this — anything that imports from the Balancer V3 monorepo is GPL. `aumm-deploy` will be GPL-3.0-or-later.

---

## Step-by-step setup (\~45 minutes total)

Time estimates assume nothing goes wrong. If something goes wrong, stop, copy the error, and ask Claude — do not proceed past a failing step.

### A0 — Pre-flight decisions checklist

Before opening Terminal, confirm in writing:

- [ ] Vault byte-identical, fee customization in `AureumProtocolFeeController` only (decision 1, 2)
- [ ] Authorizer is gov-multisig wrapper, NOT null (decision 4)
- [ ] Option F2 (forked `AureumVaultFactory.sol` in `aumm-deploy/src/`) (decisions 5, 6)
- [ ] Pause window 4 years, buffer 6 months (decision 7)
- [ ] Solc 0.8.26, optimizer 9999, via\_ir, cancun (decision 8)
- [ ] Brand new repo `aummfi-bit/aumm-deploy`, not reusing the prior chat's tarball

If any of these are still in doubt, resolve them before A1.

---

### A1 — Create the empty GitHub repo (2 min)

In a browser, go to [https://github.com/new][1] and fill in:

- **Owner:** `aummfi-bit`
- **Repository name:** `aumm-deploy`
- **Description:** `Aureum parallel Vault deployment — Foundry scripts and the two Aureum-owned contracts (Authorizer, ProtocolFeeController) plus a forked VaultFactory. Companion to aumm-site (specs).`
- **Visibility:** **Private** for now. Flip to public when Stage B is done and the deploy script is fork-tested.
- **Initialize this repository with:** leave all three checkboxes UNCHECKED. No README, no .gitignore, no license. We will push these from local.

Click **Create repository**. Leave the page open — you will need the SSH/HTTPS URL in step A4.

---

### A2 — Install Foundry on your Mac (5 min)

Open Terminal (Cmd-Space, type "Terminal"):

```bash
curl -L https://foundry.paradigm.xyz | bash
```

This installs `foundryup`, the version manager. It does NOT install `forge`/`cast`/`anvil` themselves yet.

**Close Terminal and reopen it.** (Or run `source ~/.zshenv` if you know what that means. The "close and reopen" is more reliable.)

Then:

```bash
foundryup
```

This downloads `forge`, `cast`, `anvil`, `chisel` and puts them in `~/.foundry/bin/`. Takes 30-60 seconds.

Verify:

```bash
forge --version
cast --version
anvil --version
```

All three should print a version line. If you get "command not found", your shell PATH was not updated by the installer. Tell Claude:
- which shell you use: `echo $SHELL`
- what's currently in your foundry bin: `ls ~/.foundry/bin/ 2>/dev/null`

and Claude will give you a one-line fix.

**On Apple Silicon (M1/M2/M3/M4):** the native ARM binary installs automatically. Nothing extra to do.

---

### A3 — Install Cursor + Solidity extension (5 min, skip if already installed)

1. Download Cursor: [https://cursor.com/download][2]
2. Open Cursor → Extensions panel (Cmd-Shift-X) → search "Solidity"
3. Install **"Solidity" by Juan Blanco** — this is the standard Solidity language server. There are several Solidity extensions; install Juan Blanco's, not the Hardhat-specific one and not Nomic Foundation's.
4. Cursor → Settings (Cmd-,) → search "codebase indexing" → make sure it is enabled. This is what lets Cursor's AI see your whole repo.

You do NOT need any Hardhat extensions, any Solidity formatter beyond what is bundled, or any web3 tooling. Foundry handles all of that.

---

### A4 — Clone the empty repo and drop in the Stage A skeleton (10 min)

In Terminal:

```bash
cd ~
mkdir -p code && cd code
git clone git@github.com:aummfi-bit/aumm-deploy.git
cd aumm-deploy
```

(If you do not have SSH set up with GitHub, use `git clone https://github.com/aummfi-bit/aumm-deploy.git` instead. SSH is better for daily use; ask Claude for the setup walkthrough if you want it.)

You should now be in an empty directory with a `.git/` folder. Verify:

```bash
ls -la
# Should show: .  ..  .git
```

Now the Stage A skeleton (foundry.toml, remappings.txt, .gitignore, README, etc.) gets dropped in. **This will be a tarball Claude produces in the next chat turn after A0 is confirmed.** Extract it on top:

```bash
tar -xzf ~/Downloads/aumm-deploy-stage-a.tar.gz --strip-components=1
ls -la
# Now should show: README.md LICENSE foundry.toml remappings.txt .gitignore .env.example .cursorrules src/ script/ test/ docs/
```

First commit:

```bash
git add -A
git status   # READ this output before committing — make sure nothing weird is staged
git commit -m "Stage A: Foundry skeleton, Cursor rules, planning docs"
```

---

### A5 — Add the Balancer fork as a submodule and pin it (10 min)

This is the step where we wire `aummfi-bit/balancer-v3-monorepo` into the project as `lib/balancer-v3-monorepo`.

```bash
git submodule add https://github.com/aummfi-bit/balancer-v3-monorepo.git lib/balancer-v3-monorepo
```

This clones the whole monorepo into `lib/balancer-v3-monorepo` and registers it in `.gitmodules`. Takes 1-2 minutes (it is a big repo).

**Now find the right pin.** We want a commit where `pkg/vault/contracts/VaultFactory.sol` matches the verified Etherscan source. Procedure:

```bash
cd lib/balancer-v3-monorepo
# List the most recent commits that touched VaultFactory.sol
git log --oneline -- pkg/vault/contracts/VaultFactory.sol | head -20
# Look for a commit dated around Dec 2024 (the mainnet deploy was Dec 4, 2024)
# Pick that commit hash
git checkout <commit-hash>
cd ../..
```

We will then verify by hand that the file matches the verified Etherscan source. Claude can help with this in the next chat turn — paste the commit hash and Claude will fetch both versions and diff them.

Once verified, commit the pin:

```bash
git add .gitmodules lib/balancer-v3-monorepo
git commit -m "Pin balancer-v3-monorepo submodule (matches verified mainnet deployment)"
```

---

### A6 — Install OpenZeppelin and forge-std as Forge libraries (3 min)

These are NOT submodules of the Balancer fork — Forge installs them separately under `lib/`.

```bash
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install foundry-rs/forge-std --no-commit
```

The `--no-commit` flag tells Forge not to auto-commit; we want to commit manually so the message is clean.

```bash
git add -A
git commit -m "Add openzeppelin-contracts and forge-std libraries"
```

---

### A7 — First compile (the moment of truth, 2 min)

```bash
forge build
```

Expected output: a list of compiled contracts ending with something like `Compiler run successful!` and zero errors.

The compiled contracts will include `Sanity.t.sol` (which the skeleton ships with), which imports `IVault` from the submodule. If that import resolves, the remappings are correct.

**If it errors**, the error will be one of three things, all fixable:

- **A remapping mismatch.** The submodule's actual `pkg/` layout does not match what `remappings.txt` expects. Copy the error and tell Claude — fix is editing one line in `remappings.txt`.
- **A solc version conflict.** Some submodule file uses a pragma incompatible with 0.8.26. Should not happen because the submodule is pinned to a Dec 2024 commit and the official release uses 0.8.26. If it does, copy the error.
- **A missing transitive dependency.** Some imported file references a package we do not have installed. Copy the error.

In all three cases: **stop, copy the error verbatim, paste it in chat. Do not try to fix it by guessing.**

---

### A8 — Configure RPC and run the sanity fork test (5 min)

```bash
cp .env.example .env
```

Open `.env` in Cursor and fill in `MAINNET_RPC_URL`. Free options:

- **Ankr:** `https://rpc.ankr.com/eth` (no API key required, rate-limited)
- **Alchemy:** sign up at [https://alchemy.com][3], create an Ethereum mainnet app, copy the HTTPS endpoint
- **Infura:** sign up at [https://infura.io][4], same flow

Ankr is fastest to set up. Alchemy is more reliable for repeated forks. Either is fine for Stage A.

Then in Terminal:

```bash
source .env
echo $MAINNET_RPC_URL   # Should print your URL — verifies the export worked
forge test --fork-url $MAINNET_RPC_URL -vv
```

The `Sanity.t.sol` test will fork mainnet at the latest block, instantiate `IVault` at the live Balancer V3 Vault address, call `getPauseWindowEndTime()` (a free view function), and assert it returns a non-zero `uint32`. If it passes, your environment is fully wired and you can talk to mainnet contracts from Forge tests. **This is the Stage A "everything works" milestone.**

---

### A9 — Push and tag (1 min)

```bash
git push -u origin main
git tag stage-a-complete
git push origin stage-a-complete
```

Now `stage-a-complete` is the known-good baseline. Stage B branches from there.

**Update this file:** at the bottom, add a "Completion Log" entry with the date, the commit hash that is tagged, and any notes about issues you hit. This makes Stage B's first action ("read STAGE\_A\_PLAN.md to confirm starting state") trivially correct.

---

## Files the Stage A skeleton ships with

When Claude produces the `aumm-deploy-stage-a.tar.gz` in the next turn, it will contain exactly:

```
aumm-deploy/
├── README.md                 — Top-level repo README, scope explanation, quick start
├── LICENSE                   — Full GPL-3.0-or-later text
├── .gitignore                — Foundry, Cursor, macOS ignores
├── .env.example              — MAINNET_RPC_URL, ETHERSCAN_API_KEY placeholders
├── .cursorrules              — Rules for Cursor's AI: read actual files, never guess
│                               Balancer V3 signatures, defer to aumm-site for canonical specs,
│                               byte-identity rules, "ask before assuming"
├── foundry.toml              — solc 0.8.26, optimizer 9999, via_ir, cancun, fuzz config
├── remappings.txt            — @balancer-labs/v3-* → lib/balancer-v3-monorepo/pkg/*
├── src/
│   └── .gitkeep              — Stage B fills this
├── script/
│   └── .gitkeep              — Stage B fills this
├── test/
│   ├── unit/
│   │   └── .gitkeep
│   └── fork/
│       └── Sanity.t.sol      — One test, the "is the toolchain wired correctly" check
└── docs/
    ├── STAGE_A_PLAN.md       — This file
    ├── STAGE_B_PLAN.md       — What comes next
    └── balancer_v3_reference.md  — Updated download manifest, link to Etherscan source
```

Stage A skeleton does NOT include any Aureum-owned Solidity. Anything beyond `Sanity.t.sol` is Stage B.

---

## What can go wrong and how to recover

**Foundry installer fails on Apple Silicon.** Almost never happens, but if it does: try `foundryup --branch master`. If that fails, ask Claude.

**`forge install` complains about an existing git directory.** This happens if you try to install something twice. Run `rm -rf lib/<package>` and try again.

**`forge build` complains about stack-too-deep.** Fix in `foundry.toml`: `via_ir = true` is already set in the skeleton, which should resolve this. If it persists, the stack-too-deep is in test code and the fix is to refactor the test. Stage A's `Sanity.t.sol` is small enough this should not happen.

**Mainnet fork test hangs forever.** Your RPC is rate-limited or blocked. Try a different provider (Alchemy is most reliable).

**Mainnet fork test reverts.** The Balancer V3 Vault address you are forking against is wrong, or the function you called is not a view function. Stage A's sanity test is hardcoded to a known-safe call, so this should not happen — if it does, paste the error.

**`git submodule add` fails with "already exists in index".** You ran it twice. Run `git submodule deinit -f lib/balancer-v3-monorepo && rm -rf .git/modules/lib/balancer-v3-monorepo lib/balancer-v3-monorepo` and try again.

**Cursor cannot see the submodule contents.** Cursor → Settings → search "files exclude" → make sure `**/lib` is NOT in the list. By default Cursor indexes everything; if you have customized this, the submodule might be hidden.

---

## What is explicitly NOT in Stage A

If you find yourself doing any of these, **stop** — they belong in Stage B:

- Writing `AureumVaultFactory.sol` (the forked factory)
- Writing `AureumProtocolFeeController.sol`
- Writing `AureumAuthorizer.sol`
- Writing `script/DeployAureumVault.s.sol`
- Computing the creation code hashes for the factory constructor
- Mining a vanity salt for the Vault address
- Fork-testing a full Aureum Vault deployment
- Deciding which Safe multisig address gets baked in as the authorizer's privileged account
- Anything involving der Bodensee Pool deployment

All of those are Stage B. They depend on Stage A being green, and they each deserve focused attention without the distraction of toolchain debugging.

---

## Completion Log

Fill this in as you progress.


| Date       | Step                               | Status | Commit    | Notes                                                                                                                                                              |
| ---------- | ---------------------------------- | ------ | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 2026-04-09 | A1 — Empty repo created            | ✅      |           | aummfi-bit/aumm-deploy, private                                                                                                                                    |
| 2026-04-09 | A2 — Foundry installed             | ✅      |           |                                                                                                                                                                    |
| 2026-04-09 | A3 — Cursor + extension            | ✅      |           |                                                                                                                                                                    |
| 2026-04-09 | A4 — Skeleton committed            | ✅      | `fb0216a` | extracted from tarball, pushed to origin/main                                                                                                                      |
| 2026-04-09 | A5 — Submodule pinned              | ✅      | `b60492f` | submodule at `68057fda` (Dec 3 2024, last pre-mainnet VaultFactory commit, visually diffed against Etherscan source at 0xAc27df81663d139072E615855eF9aB0Af3FBD281) |
|            | A6 — Libraries installed           |        |           |                                                                                                                                                                    |
|            | A7 — `forge build` green           |        |           |                                                                                                                                                                    |
|            | A8 — Sanity fork test passes       |        |           | RPC provider used:                                                                                                                                                 |
|            | A9 — `stage-a-complete` tag pushed |        |           |                                                                                                                                                                    |

When the last row is filled in, Stage A is done and Stage B starts.
When the last row is filled in, Stage A is done and Stage B starts.

[1]:	https://github.com/new
[2]:	https://cursor.com/download
[3]:	https://alchemy.com
[4]:	https://infura.io