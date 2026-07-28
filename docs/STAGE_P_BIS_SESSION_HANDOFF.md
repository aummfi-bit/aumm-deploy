# Stage P-bis — session handoff, 2026-07-27

**Status: PB3.5 rung i is MID-SEQUENCE AND HALTED on live Sepolia.** Steps 1 and 2 of the base-layer broadcast are partially executed; step 2 failed on its final transaction. The cause is a build defect that blocks mainnet as well as Sepolia. Nothing further may be broadcast until it is adjudicated.

CLAUDE.md §11 is current through rung h and does NOT know about this blocker. Read this file alongside it.

## 1. The blocker — the Vault exceeds EIP-170

| | runtime bytes |
| --- | --- |
| Our compiled `Vault` | **28,304** |
| EIP-170 limit | 24,576 |
| Balancer's live mainnet Vault (`0xbA1333333333a1BA1108E8412f11850A5C319bA9`) | 24,538 |
| our `VaultExtension` | 23,247 (ok) |
| our `VaultAdmin` | 15,304 (ok) |

Balancer's deployed Vault — essentially the same source our submodule is pinned to — fits with 38 bytes to spare. Ours is 15% larger.

`AureumVaultFactory.create()` therefore reverts `INITIALIZATION_FAILED`: CREATE3's inner CREATE returns empty code when the runtime exceeds the limit, and CREATE3 reports that as an initialization failure. Confirmed via `eth_call` and `eth_estimateGas` against two independent RPCs at a 50M gas ceiling — not a gas problem and not a provider problem.

**Why no gate caught it.** `forge config` reports no `code_size_limit`, and forge does not enforce EIP-170 in simulation. Every fork test that "deployed the Vault" — the P10 close gate 13/13, the PB3.4 rehearsal 9/9, the whole Stage B–P vault surface — was validating an artifact no chain will accept.

**Root cause hypothesis, NOT yet confirmed.** CLAUDE.md §2 pins `optimizer_runs = 9999` as an "exact match to Balancer's mainnet deployment". That claim appears false for the vault package: higher optimizer runs inline more aggressively and grow code, and Balancer's vault package is size-constrained enough that a much lower value is likely. The submodule supplies SOURCE; we compile it ourselves, so our settings determine the bytecode. "Byte-identical source" was never "byte-identical artifact", and nothing in the pipeline checked the latter.

Confirmation probe, not yet run (writes only to `out-probe/`, touches no committed file):

    forge build --optimizer-runs 200 --out out-probe

then measure `.deployedBytecode.object` length in `out-probe/**/Vault.sol/Vault.json`.

## 2. Exact on-chain state (Sepolia, chain 11155111)

Deployer / `GOVERNANCE_MULTISIG`: `0xA851478dbee97375E784e9b98c0D7D599662bF85`. Nonce **90**. Balance roughly 5.94 SepETH. Key in forge keystore as account `aumm-sepolia`.

| Nonce | Contract | Address | State |
| --- | --- | --- | --- |
| 0—86 | 87 testnet stubs | see `.env` `STUB_` map | deployed |
| 87 | `AureumAuthorizer` | `0x655efe2DD8728af106C933cD88A89646D2C7De02` | deployed |
| 88 | `AureumProtocolFeeController` | `0x985eA467837eE8C2598474E54395DB8B0822Ce1F` | deployed |
| 89 | `AureumVaultFactory` | `0x6649f7A65b6937F6D2E46d4FB418fFb12079f560` | deployed |
| 90 | `factory.create()` | — | **NOT SENT — the failure point** |

Sealed immutables in the fee controller, read back on-chain and CORRECT:

- `DER_BODENSEE_POOL` = `0xbE98Bbd2856d8694b42A47585c5F65011f5FD0Bc`
- `FEE_ROUTING_HOOK` = `0x587229d7e7bDaD6dBbd628C64722d4Ab6b059549`

The irreversible portion of step 2 completed correctly. Nothing on chain is corrupted.

## 3. Hard constraint

**The deployer EOA must send NOTHING except the next step of this sequence.** Every remaining projection is an offset from nonce 90. A single unrelated transaction voids all of them and forces a full phase-A re-run per runbook section 8.

## 4. Why recovery is clean once the build is fixed

A CREATE3 address depends only on the creating factory and the salt — NOT on the deployed bytecode. A corrected Vault build therefore still lands at `0xD3c076a2B096A8b7B6744A078473C20b5E8a6c03`, `factory.create()` still belongs at nonce 90, and the entire projection ledger survives unchanged. No restart, no address churn, no redeploying the 87 stubs.

| Nonce | Key | Address |
| --- | --- | --- |
| 91 | `WEIGHTED_POOL_FACTORY` / `AUREUM_WEIGHTED_POOL_FACTORY` | `0xb424796989Ba0Baaaa879Db0C0d1FEf638fEa3ef` |
| 92 | `AUMM` | `0x0321Cc252D09C30E21D59B17f667c2e6e43f2855` |
| 93 | `FEE_ROUTING_HOOK` | `0x587229d7e7bDaD6dBbd628C64722d4Ab6b059549` |
| CREATE3 | `VAULT` / `AUREUM_VAULT` | `0xD3c076a2B096A8b7B6744A078473C20b5E8a6c03` |
| CREATE3 | `DER_BODENSEE_POOL` | `0xbE98Bbd2856d8694b42A47585c5F65011f5FD0Bc` |

Measured step counts: `c1 = 87`, `c2 = 4`, `c3 = 1`, `c4 = 1`. Full derivation and the forge-versus-cast method validation are in `docs/STAGE_P_BIS_PHASE_A_RECORD.md`.

`GENESIS_BLOCK` is deliberately a `999999999` placeholder — set it to Sepolia head plus 100,800 immediately before step 4 per PB-D19. The Etherscan API key is still absent.

`.env` is gitignored and holds the entire verified projection set plus the live 67-pair `STUB_` map. Losing that machine means re-running phase A.

## 5. The decision to make — chat-level, do not act unilaterally

Changing `optimizer_runs` alters the compiler configuration CLAUDE.md §2 locks, and under which every audit artifact was produced: the 928-test unit suite, the 55 hevm proofs, the nine `.act` specs, the whole `formal/` bundle. Per §8c and §12 this is an architectural decision requiring explicit user adjudication and a PB-D lock, not an operational step.

Open questions:

1. What settings did Balancer actually use, per package? Their hardhat config and the verified Etherscan source for the mainnet Vault are the sources of truth — not our assumption.
2. Does a per-package or per-contract optimizer setting fit `foundry.toml`, or does this require a profile split?
3. Does the change alter Aureum-owned contract bytecode, and what must be re-run — unit suite, fork suites, hevm proofs, Act specs?
4. Does CLAUDE.md §2's compiler row need correcting, and §11 the finding?
5. Should a deployed-bytecode-size assertion become a permanent gate so this cannot recur? Strong candidate for an RB register row; RB-008 was the last added.

## 6. First move for the next session

Run the section 1 confirmation probe. If the Vault comes in under 24,576 at lower optimizer runs, the diagnosis is confirmed and the section 5 decision is live. If it does not, the hypothesis is wrong and the next suspects are the pinned submodule commit `68057fda` diverging from what Balancer actually deployed, or `via_ir` interacting with the size.
