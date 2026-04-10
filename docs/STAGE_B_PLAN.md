# Stage B — Aureum Parallel Vault Deployment

> **Status:** Blocked. Stage B does not start until `STAGE_A_PLAN.md` shows the `stage-a-complete` tag pushed.
>
> **Audience:** Sagix, plus any future Claude session that needs to know what Stage B is and what it produces.
>
> **Why this file exists:** so the plan survives outside chat scrollback. When Stage A is done, this file is the entry point.

---

## Scope of Stage B

**Goal:** Write, fork-test, and document the four Solidity files and one deploy script needed to spin up the Aureum parallel Balancer V3 Vault instance on a mainnet fork. **No mainnet deployment in Stage B.** Mainnet deployment is Stage C.

**The four Solidity files Stage B produces:**

1. **`src/AureumAuthorizer.sol`** — implements `IAuthorizer`. Grants all action IDs to one address: a Safe multisig. ~30 lines.
2. **`src/AureumProtocolFeeController.sol`** — implements `IProtocolFeeController`. Routes 100% of the protocol-extractable swap fee share (capped at 50% by `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE`) and 100% of the protocol-extractable yield fee share to der Bodensee Pool. **No creator fees ever collected.** Withdraw functions, when called, send to der Bodensee. ~200-300 lines.
3. **`src/AureumVaultFactory.sol`** — forked from `pkg/vault/contracts/VaultFactory.sol` in the submodule. **The diff against upstream is constrained to ~5 lines:** add an `IProtocolFeeController _initialFeeController` parameter to the constructor, store it as immutable, and replace the `new ProtocolFeeController(IVault(vaultAddress))` line with passing the immutable in. **The rest of the file is byte-for-byte identical to upstream**, including all the `keccak256` bytecode hash checks that enforce the Vault is byte-identical. ~150 lines, of which ~145 are upstream.
4. **`script/DeployAureumVault.s.sol`** — Foundry deployment script. Wires it all together: deploys `AureumAuthorizer`, deploys `AureumProtocolFeeController` (which needs the future Vault address — there is a chicken-and-egg here, see Section "The address dependency loop" below), deploys `AureumVaultFactory` with the right constructor params, calls `factory.create(...)` with the Balancer V3 creation code, asserts the resulting Vault has the right authorizer and the right fee controller. ~150 lines.

**The fork tests Stage B produces:**

- `test/fork/DeployAureumVault.t.sol` — runs the deploy script against a mainnet fork; asserts (a) Vault deployed at predicted CREATE3 address, (b) `vault.getAuthorizer() == aureumAuthorizer`, (c) `vault.getProtocolFeeController() == aureumProtocolFeeController`, (d) `vault.getPauseWindowEndTime() ~= block.timestamp + 4 years`, (e) admin functions all revert when called from non-multisig addresses, (f) admin functions succeed when pranked from the multisig.
- `test/unit/AureumAuthorizer.t.sol` — unit test the authorizer. Asserts `canPerform` returns true for the multisig and false for everyone else, regardless of action ID.
- `test/unit/AureumProtocolFeeController.t.sol` — unit test the fee controller, mocking the Vault. Asserts withdraw functions revert if called by anyone other than the Vault, asserts pool creator fee setters revert (no creator fees allowed).

**What "done" looks like — the five checkpoints:**

1. All four Solidity files compile cleanly with `forge build`.
2. All three test files pass with `forge test`.
3. The fork test passes with `forge test --fork-url $MAINNET_RPC_URL --match-path test/fork/DeployAureumVault.t.sol -vv`.
4. `slither .` runs without high-severity findings on the Aureum-owned files. (Slither install is part of B0.)
5. The commit at which all four are true is tagged `stage-b-complete` and pushed.

---

## Pre-Stage-B reading

Before opening Cursor for Stage B, the operator (Sagix or a Claude session) must read these in order:

1. **`STAGE_A_PLAN.md` — the Completion Log.** Confirm A1 through A9 are checked off and the tag exists. If not, go back to Stage A.
2. **The architectural decisions table in `STAGE_A_PLAN.md`.** All 12 decisions still apply. Stage B does not relitigate them.
3. **`aumm-site/13_appendices.md` Section xxxvi (AMM Architecture: Aequilibrium).** This is the canonical "what's inherited, what's new" table. Stage B touches "what's new": fee controller, authorizer. It does not touch "what's unchanged": Vault, weighted pools, stable pools, hooks, rate providers, SOR.
4. **`aumm-site/10_constitution.md` Section xxix.** Immutable parameters. Anything Stage B writes that has a numeric constant must match this section. For Stage B specifically: pause window (4 years), buffer period (6 months), and the fee split (50/50).
5. **`aumm-site/04_tokenomics.md`.** The fee routing section. Stage B's fee controller implements the routing described here.
6. **The verified `VaultFactory.sol` source at <https://etherscan.io/address/0xAc27df81663d139072E615855eF9aB0Af3FBD281#code>.** Read it. The whole thing. It is ~170 lines. `AureumVaultFactory.sol` is going to be 95% this code.
7. **`pkg/vault/contracts/ProtocolFeeController.sol` from the pinned submodule.** This is the reference implementation Aureum's fee controller is replacing. Read it to understand which functions are required, what the Vault expects to call, and where Aureum's behavior differs.

If any of these reads surface a conflict with the architectural decisions in `STAGE_A_PLAN.md`, **stop** and update `STAGE_A_PLAN.md` first. Do not silently change the design in code.

---

## Architectural decisions specific to Stage B

These are in addition to the 12 decisions in `STAGE_A_PLAN.md`. They concern things Stage A did not need to resolve.

| # | Decision | Rationale |
|---|----------|-----------|
| B1 | **The governance multisig address is a constructor parameter to `AureumAuthorizer`**, not hardcoded. The address is supplied at deploy time from `.env`. For Stage B fork tests, a deterministic Foundry test address is used. For Stage C mainnet deployment, the real Safe multisig address is used. | Lets the same code path serve both fork tests and mainnet without source edits. |
| B2 | **`AureumAuthorizer` has no role-based gating.** It is binary: the multisig can do everything, no one else can do anything. There is no `grantRole`, no `revokeRole`, no `DEFAULT_ADMIN_ROLE`. `canPerform` is a single equality check. | Matches "no governance UI, no role administration" — governance happens off-chain via Snapshot, executes on-chain via the Safe transaction. The on-chain authorizer is dumb on purpose. |
| B3 | **`AureumProtocolFeeController` rejects all `setPoolCreator*` calls.** The interface requires the functions to exist; the implementation reverts. This makes "no creator fees" mechanically enforced, not just a default. | A creator fee of zero set by governance can be changed by governance. A creator fee that *cannot exist* cannot be changed. The Aureum brand needs the stronger guarantee. |
| B4 | **All withdrawn protocol fees go to one address: der Bodensee Pool.** That address is a constructor parameter to `AureumProtocolFeeController`, immutable after deploy. There is no `setRecipient`. | Same reasoning as B3: an immutable destination is stronger than a governance-settable one. |
| B5 | **Stage B deploys `AureumProtocolFeeController` with `derBodenseePool = address(0xDEAD)` as a placeholder for fork tests.** Stage C will deploy der Bodensee Pool first, then deploy the fee controller with the real address. Stage B does not block on der Bodensee being designed yet. | Stage B is about wiring the Vault deployment correctly. Der Bodensee Pool is its own design surface and gets its own stage. Using a placeholder lets Stage B finish without that dependency. |
| B6 | **The fork test asserts pause window equals exactly `block.timestamp + 4 years`** at the moment of deployment, with a tolerance of ±1 second for block timestamp drift. | Catches off-by-one errors in time math. 4 years means `4 * 365 days = 1460 days`, NOT `4 * 365.25 days`. Solidity has no fractional seconds. |
| B7 | **The deploy script uses `vm.startBroadcast()` / `vm.stopBroadcast()` for mainnet compatibility**, but the fork test uses plain calls. The script is structured so the same logic runs in both modes. | Foundry script convention. Same code, two run modes. |
| B8 | **No upgradability of any Aureum-owned contract.** No proxies, no UUPS, no Transparent. If a bug is found in `AureumProtocolFeeController` after deployment, the fix is: deploy a new fee controller, governance proposal to call `Vault.setProtocolFeeController(newController)`. | Matches "immutable contracts" in the constitution. Migration via re-deploy is acceptable; in-place upgrade is not. |
| B9 | **CREATE3 salt for Stage B fork tests: `bytes32(uint256(0xAEEC))`** (vanity-ish but trivial). Stage C will mine a longer vanity salt if desired, or use a clean random salt. | Distinguishes the Aureum Vault from any other CREATE3 deployment in the fork test logs. Easy to grep for. |

---

## The address dependency loop

There is a chicken-and-egg problem in deploying these four contracts and it is worth explaining once, here, before someone tries to write the deploy script and gets confused.

**The Vault needs the fee controller address at construction time.** From the upstream `VaultFactory.create()`:

```solidity
ProtocolFeeController protocolFeeController = new ProtocolFeeController(IVault(vaultAddress));
// ...
address deployedAddress = CREATE3.deploy(
    salt,
    abi.encodePacked(vaultCreationCode, abi.encode(vaultExtension, _authorizer, protocolFeeController)),
    0
);
```

The Vault's constructor takes `(vaultExtension, authorizer, protocolFeeController)` as arguments, which means the protocol fee controller must exist *before* the Vault is deployed.

**The fee controller needs the Vault address at construction time.** The stock `ProtocolFeeController(IVault(vaultAddress))` constructor takes the Vault address. Aureum's `AureumProtocolFeeController` will too — it needs to know which Vault it is collecting fees from, so it can call `vault.collectAggregateFees()`.

**Resolution: CREATE3 lets us know the Vault address before deploying the Vault.** `factory.getDeploymentAddress(salt)` returns the address the Vault *will* deploy to, deterministically. So the order is:

1. Compute predicted Vault address: `address futureVault = AureumVaultFactory(factoryAddr).getDeploymentAddress(salt);`
2. Deploy `AureumProtocolFeeController(futureVault, derBodenseePool)`. The fee controller now has the Vault address as an immutable, even though the Vault does not yet exist.
3. Call `factory.create(salt, futureVault, vaultCreationCode, vaultExtensionCreationCode, vaultAdminCreationCode)`. The factory deploys VaultAdmin, VaultExtension, and finally the Vault — passing the already-deployed `AureumProtocolFeeController` address into the Vault constructor.
4. Assertion: at the end, `vault == futureVault`, `vault.getProtocolFeeController() == aureumProtocolFeeController`, and `aureumProtocolFeeController.vault() == vault`.

**This is the key insight that makes Option F2 work cleanly.** The forked `AureumVaultFactory.sol` differs from upstream in exactly one substantive way: it does NOT call `new ProtocolFeeController(...)` itself, because the fee controller is already deployed before `create()` is called. Instead, the constructor takes an `IProtocolFeeController _initialFeeController` and `create()` passes that into `CREATE3.deploy(...)` as the third Vault constructor argument.

The deploy *script* is what handles the ordering:

```
1. Deploy AureumAuthorizer(governanceMultisig)
2. Deploy AureumVaultFactory(authorizer, pauseWindow, bufferPeriod, minTrade, minWrap,
                              vaultCreationCodeHash, vaultExtensionCreationCodeHash,
                              vaultAdminCreationCodeHash)  // does not deploy anything yet
3. Compute futureVault = factory.getDeploymentAddress(SALT)
4. Deploy AureumProtocolFeeController(futureVault, derBodenseePool)
5. Call factory.create(SALT, futureVault, vaultCreationCode, vaultExtensionCreationCode,
                       vaultAdminCreationCode, aureumProtocolFeeController)
   - The new constructor parameter on the forked factory accepts the controller here
6. Assert vault state
```

Step 5 is where the forked `AureumVaultFactory` differs from upstream — its `create()` signature has one extra parameter for the fee controller, OR the controller is passed via the constructor as immutable. Both designs work; the immutable-via-constructor variant is slightly cleaner because the factory state stays minimal.

**The exact factory diff will be designed in Stage B Step B3 with the actual upstream source open in front of Claude.** Do not pre-write it from this plan.

---

## Step-by-step Stage B (~3 to 5 sittings)

These are not minutes-long steps. Each one is a focused work session of 30-90 minutes, with a clean stopping point at the end.

### B0 — Branch and install Slither (15 min)

```bash
cd ~/code/aumm-deploy
git checkout main
git pull
git checkout -b stage-b
```

Install Slither (static analysis tool from Trail of Bits):

```bash
# Requires Python 3.8+
python3 -m venv .venv
source .venv/bin/activate
pip install slither-analyzer
slither --version
```

Add `.venv/` to `.gitignore` if it is not already there. Commit:

```bash
git add .gitignore
git commit -m "B0: ignore .venv, prepare for slither static analysis"
```

### B1 — Read the upstream `VaultFactory.sol` and `ProtocolFeeController.sol` (60 min)

Open these two files in Cursor:

- `lib/balancer-v3-monorepo/pkg/vault/contracts/VaultFactory.sol`
- `lib/balancer-v3-monorepo/pkg/vault/contracts/ProtocolFeeController.sol`

Read them top to bottom. **Make notes in `docs/STAGE_B_NOTES.md`** as you go. Specifically note:

- Every external function on `IProtocolFeeController` and what it does
- Which functions are `onlyOwner` / permissioned and which are not
- The exact constructor signature of `VaultFactory`
- Where `new ProtocolFeeController(...)` is called and what is passed to it
- The hash checks at the start of `create()` and what hashes they reference

End of B1 deliverable: a notes file with answers to "what does the upstream do" written in Sagix's own words. If you cannot write it in your own words, you have not read it carefully enough.

Commit:

```bash
git add docs/STAGE_B_NOTES.md
git commit -m "B1: notes from reading upstream VaultFactory and ProtocolFeeController"
```

### B2 — Write `AureumAuthorizer.sol` and its unit test (45 min)

Smallest contract first. Builds confidence and exercises the test infrastructure.

The contract:

```solidity
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";

contract AureumAuthorizer is IAuthorizer {
    address public immutable governanceMultisig;

    constructor(address _governanceMultisig) {
        require(_governanceMultisig != address(0), "AureumAuthorizer: zero multisig");
        governanceMultisig = _governanceMultisig;
    }

    function canPerform(bytes32, address account, address) external view returns (bool) {
        return account == governanceMultisig;
    }
}
```

That is the whole contract. The unit test asserts:
- Constructor reverts on zero address
- `canPerform` returns true for the multisig and any action ID and any target
- `canPerform` returns false for any other account
- `governanceMultisig` is publicly readable

Commit:

```bash
git add src/AureumAuthorizer.sol test/unit/AureumAuthorizer.t.sol
git commit -m "B2: AureumAuthorizer + unit tests"
```

### B3 — Write `AureumVaultFactory.sol` (90 min)

This is the high-stakes file because the diff against upstream must be small and audit-clear. Procedure:

1. Copy `lib/balancer-v3-monorepo/pkg/vault/contracts/VaultFactory.sol` into `src/AureumVaultFactory.sol`.
2. Rename the contract from `VaultFactory` to `AureumVaultFactory`.
3. Add `IProtocolFeeController _initialFeeController` to the constructor parameter list.
4. Add `IProtocolFeeController public immutable initialFeeController;` to the storage.
5. Initialize it in the constructor.
6. **Delete** the line `ProtocolFeeController protocolFeeController = new ProtocolFeeController(IVault(vaultAddress));`
7. **Delete** the line `deployedProtocolFeeControllers[vaultAddress] = protocolFeeController;` (and the mapping itself, since we no longer need it).
8. Replace `protocolFeeController` in the `CREATE3.deploy(...)` call with `initialFeeController`.

That should be it. Then run `git diff --no-index lib/balancer-v3-monorepo/pkg/vault/contracts/VaultFactory.sol src/AureumVaultFactory.sol` and verify the diff is small enough to read in 30 seconds. If it is not, you have done extra work that should not be there — revert and try again.

The fork test for this comes in B5; do not try to test the factory in isolation, it is hard.

Commit:

```bash
git add src/AureumVaultFactory.sol
git commit -m "B3: AureumVaultFactory (forked from upstream, IProtocolFeeController via constructor)"
```

### B4 — Write `AureumProtocolFeeController.sol` and its unit test (2-3 hours)

This is the largest contract. Approach:

1. Copy `lib/balancer-v3-monorepo/pkg/vault/contracts/ProtocolFeeController.sol` into `src/AureumProtocolFeeController.sol` as a starting point. Rename the contract.
2. Identify every function and decide: keep, modify, or revert-on-call.
3. **Keep:** `vault()`, `collectAggregateFees`, `getProtocolFeeAmounts`, `registerPool`, `computeAggregateFeePercentage`, the global setters (gated to onlyMultisig), the protocol fee getters.
4. **Modify:** `withdrawProtocolFees` and `withdrawProtocolFeesForToken` so the recipient is hardcoded to `derBodenseePool`, ignoring whatever recipient the caller passes. Or revert if recipient is non-zero. (Decide which is cleaner; reverting is more honest.)
5. **Revert-on-call:** all four `setPoolCreator*` and `withdrawPoolCreatorFees*` functions. They exist because the interface requires them. Their bodies are `revert("Aureum: no creator fees");`.
6. Add an immutable `address public immutable derBodenseePool` set in the constructor.
7. Set the global protocol swap fee to `50e16` (50%, 18-decimal FP) in the constructor, since that is the maximum the Vault permits. Set yield fee to `50e16` similarly. Or to the values from `aumm-site/04_tokenomics.md` if they are different — read that file before hardcoding numbers.

Unit test mocks the Vault (Foundry's `vm.mockCall`) and asserts:
- Constructor reverts on zero Vault address or zero Bodensee address
- `setPoolCreatorSwapFeePercentage` reverts with the right error
- `withdrawProtocolFees` sends to der Bodensee regardless of `recipient` argument
- Only the multisig can call permissioned functions
- `registerPool` returns the right initial aggregate percentages

Commit:

```bash
git add src/AureumProtocolFeeController.sol test/unit/AureumProtocolFeeController.t.sol
git commit -m "B4: AureumProtocolFeeController + unit tests"
```

### B5 — Write `script/DeployAureumVault.s.sol` and the integration fork test (90 min)

The script follows the order in "The address dependency loop" section above. The fork test uses the script.

The fork test does:

```solidity
function test_DeployAureumVault() public {
    DeployAureumVault deployer = new DeployAureumVault();
    AureumVaultFactory factory = deployer.run();

    // Find the deployed Vault
    address vaultAddr = factory.getDeploymentAddress(SALT);
    IVault vault = IVault(vaultAddr);

    // Assertions
    assertEq(address(vault.getAuthorizer()), address(deployer.aureumAuthorizer()));
    assertEq(address(vault.getProtocolFeeController()), address(deployer.aureumFeeController()));

    (uint32 pauseWindow, , ) = vault.getVaultPausedState();
    assertApproxEqAbs(uint256(pauseWindow), block.timestamp + 4 * 365 days, 1);

    // Admin functions revert from EOA
    vm.expectRevert();
    vault.pauseVault();

    // Admin functions succeed from multisig
    vm.prank(GOV_MULTISIG);
    vault.pauseVault();
    assertTrue(vault.isVaultPaused());
}
```

(The actual code will be more careful about types and imports; this is the shape.)

Run it:

```bash
source .env
forge test --fork-url $MAINNET_RPC_URL --match-path test/fork/DeployAureumVault.t.sol -vv
```

Commit:

```bash
git add script/DeployAureumVault.s.sol test/fork/DeployAureumVault.t.sol
git commit -m "B5: deploy script + integration fork test, all assertions pass"
```

### B6 — Run Slither and address findings (60 min)

```bash
source .venv/bin/activate
slither . --filter-paths "lib|test"
```

Read every finding. For each:
- **Suppress** with a comment if it is a false positive (and document why)
- **Fix** if it is real
- **Defer to Stage C** if it is real but not blocking (and document in `docs/STAGE_B_NOTES.md`)

The `--filter-paths "lib|test"` excludes the submodule and test files from analysis — those are not Aureum-owned and not in scope.

Commit any fixes:

```bash
git add -A
git commit -m "B6: Slither findings addressed (or suppressed with rationale)"
```

### B7 — Tag and PR (15 min)

```bash
git push origin stage-b
```

Open a PR on GitHub: `stage-b` → `main`. Self-review the diff. Merge when satisfied.

```bash
git checkout main
git pull
git tag stage-b-complete
git push origin stage-b-complete
```

Update the Completion Log in this file with the final commit hash and the date.

---

## Completion Log

Fill this in as you progress.

| Date | Step | Status | Commit | Notes |
|---|---|---|---|---|
| 2026-04-09 | B0 — branch + slither | ✅ | `1a7e44b` | slither 0.11.4, .venv already gitignored from Stage A, empty marker commit |
|  | B1 — read upstream |  |  | notes file: |
|  | B2 — Authorizer |  |  |  |
|  | B3 — Factory fork |  |  | diff line count: |
|  | B4 — FeeController |  |  |  |
|  | B5 — Deploy script + fork test |  |  |  |
|  | B6 — Slither |  |  | findings: |
|  | B7 — `stage-b-complete` tag |  |  |  |

When the last row is filled, Stage B is done. Stage C (mainnet deployment) will get its own plan file.

---

## What is explicitly NOT in Stage B

- Mainnet deployment of any contract (that is Stage C)
- Designing or deploying der Bodensee Pool (that is its own stage)
- Mining a vanity salt for the real Vault address (Stage C, optional)
- Etherscan verification of the deployed contracts (Stage C)
- Setting up a real Safe multisig with real signers (Stage C prerequisite)
- Writing the AuMM token, gauges, CCB engine, or any tokenomics layer code (separate `aumm-contracts` repo, not this one)
- Migrating any liquidity from anywhere to anywhere
- Front-end work
- Audit engagement (Stage D, after Stage C is on mainnet)

Stage B is "the parallel Vault deploys correctly on a mainnet fork, with Aureum's authorizer and fee controller wired in, and basic invariants hold." That is all.
