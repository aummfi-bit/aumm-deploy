# Stage P-bis — session handoff, 2026-07-27

**Status: PB3.5 rung i is MID-SEQUENCE AND HALTED on live Sepolia.** Steps 1 and 2 of the base-layer broadcast are partially executed; step 2 failed on its final transaction. The cause is a build defect that blocks mainnet as well as Sepolia. Nothing further may be broadcast until it is adjudicated.

CLAUDE.md §11 is current through rung h and does NOT know about this blocker. Read this file alongside it.

**Superseded in part by PB-D32** (`docs/STAGE_P_BIS_NOTES.md`, 2026-07-27). Sections 1, 3, 4, 5 and 6 are revised to match that lock. Section 2's on-chain facts stand exactly as recorded, but all three contracts it lists are now dead — see section 4.

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

**Root cause — confirmed in part, and larger than first supposed.** Two independent divergences, both established 2026-07-27.

*Per-contract optimizer runs.* Balancer's deployed artifacts come from hardhat via `pvt/common/hardhat-base-config.ts`, which overrides `Vault.sol` and `VaultExtension.sol` to `runs: 500` against a package base of 9999. Measured on our toolchain: 28,304 bytes at 9999, 25,161 at 500, 24,918 at 200. Matching their runs is necessary and not sufficient — no value tested clears 24,576. The 9999 figure recorded in `foundry.toml` L6 was read from the verified Etherscan source of `VaultFactory`, which hardhat does not override, so that reading was correct for that contract and wrong only in being generalised to the whole package.

*The OpenZeppelin pin.* `yarn.lock` L1317 resolves `@openzeppelin/contracts` to 5.0.0; we build against 5.6.1. `Vault.sol` L5—L10 imports six symbols from it, and the `solidity-utils` tree beneath imports more. After netting our metadata-free output against mainnet's CBOR tail, roughly 676 bytes remain unexplained by optimizer runs alone, and the OpenZeppelin pin is the only remaining identified source-level difference. It is not yet quantified — rung i1 exists to settle exactly that.

The submodule supplies SOURCE; we compile it ourselves, so our settings and our dependency graph together determine the bytecode. Byte-identical source was never byte-identical artifact, and nothing in the pipeline checked the latter. Stated plainly: our Vault has never been the audited Vault at the bytecode level, on any branch, at any stage.

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

**The deployer EOA must send nothing until the new phase A has been run.** The projections that were offsets from nonce 90 are already void, for the reason section 4 gives, so a stray transaction no longer destroys them. What still holds is narrower and just as strict: phase A must be re-derived from whatever nonce is live once the corrected build exists, and that derivation is valid only if the nonce holds still from the moment it is read until step 1 is broadcast. Per runbook section 8.

## 4. Recovery — the base layer is dead from nonce 87

A CREATE3 address depends only on the creating factory and the salt, not on the deployed bytecode. That premise is true. The conclusion previously drawn from it here — that a corrected build lands at the same addresses and the whole projection ledger carries over — does not follow, and is withdrawn.

`AureumVaultFactory` seals `keccak256(type(Vault).creationCode)` as a constructor immutable, computed at `script/DeployAureumVault.s.sol` L144—L146 and passed at L211—L213, and `create()` verifies it. The factory at nonce 89 is therefore permanently bound to the oversized creation code and will reject any corrected build. It must be redeployed.

Redeploying it shifts every later nonce. `WEIGHTED_POOL_FACTORY` moves, and it is the CREATE3 creator for der Bodensee per PB-D29 (vi), so `DER_BODENSEE_POOL` moves with it — and that address is sealed as an immutable in the `AureumProtocolFeeController` at nonce 88, the contract section 2 verified on-chain as correct. The two die together.

- **Survives:** the 87 stubs at nonces 0—86. Nothing on-chain seals their addresses, and they are reused from the committed `STUB_` map in `.env`.
- **Dead:** nonces 87, 88 and 89 — `AureumAuthorizer`, `AureumProtocolFeeController`, `AureumVaultFactory`. Abandoned in place on Sepolia.
- **Void:** all eight address projections. Phase A re-runs in full from the live nonce per PB-D29 (iv).

The measured step counts survive, being invariant under both nonce and chain per PB-D28 (ii) and PB-D29 (v): `c1 = 87`, `c2 = 4`, `c3 = 1`, `c4 = 1`. Full derivation and the forge-versus-cast method validation are in `docs/STAGE_P_BIS_PHASE_A_RECORD.md`.

The projections below are retained only as the record of what phase A computed. **They are void. Do not act on them.**

| Nonce | Key | Address — VOID |
| --- | --- | --- |
| 91 | `WEIGHTED_POOL_FACTORY` / `AUREUM_WEIGHTED_POOL_FACTORY` | `0xb424796989Ba0Baaaa879Db0C0d1FEf638fEa3ef` |
| 92 | `AUMM` | `0x0321Cc252D09C30E21D59B17f667c2e6e43f2855` |
| 93 | `FEE_ROUTING_HOOK` | `0x587229d7e7bDaD6dBbd628C64722d4Ab6b059549` |
| CREATE3 | `VAULT` / `AUREUM_VAULT` | `0xD3c076a2B096A8b7B6744A078473C20b5E8a6c03` |
| CREATE3 | `DER_BODENSEE_POOL` | `0xbE98Bbd2856d8694b42A47585c5F65011f5FD0Bc` |

`GENESIS_BLOCK` is deliberately a `999999999` placeholder — set it to Sepolia head plus 100,800 immediately before step 4 per PB-D19. The Etherscan API key is still absent.

`.env` is gitignored. Its projection set is now void; its live 67-pair `STUB_` map is the part that still matters, and losing that machine means redeploying the stubs as well as re-running phase A.

## 5. The decision to make — chat-level, do not act unilaterally

**Adjudicated 2026-07-27 as PB-D32.** What follows is retained as the record of what was weighed; every question below is answered in that lock. Do not re-adjudicate from this section.

Changing `optimizer_runs` alters the compiler configuration CLAUDE.md §2 locks, and under which every audit artifact was produced: the 928-test unit suite, the 55 hevm proofs, the nine `.act` specs, the whole `formal/` bundle. Per §8c and §12 this is an architectural decision requiring explicit user adjudication and a PB-D lock, not an operational step.

Open questions:

1. What settings did Balancer actually use, per package? Their hardhat config and the verified Etherscan source for the mainnet Vault are the sources of truth — not our assumption.
2. Does a per-package or per-contract optimizer setting fit `foundry.toml`, or does this require a profile split?
3. Does the change alter Aureum-owned contract bytecode, and what must be re-run — unit suite, fork suites, hevm proofs, Act specs?
4. Does CLAUDE.md §2's compiler row need correcting, and §11 the finding?
5. Should a deployed-bytecode-size assertion become a permanent gate so this cannot recur? Strong candidate for an RB register row; RB-008 was the last added.

## 6. First move for the next session

Read PB-D32 in `docs/STAGE_P_BIS_NOTES.md`, then run rung i1 — the gate on every rung after it.

i1 compiles the Balancer vault package in isolation against OpenZeppelin 5.0.0 at `runs = 500`, into a scratch out directory, with no Aureum source participating and no committed file touched. Isolation is what keeps it cheap: because no Aureum file takes part, the two-OpenZeppelin-version type conflict cannot arise, and the single run answers both open questions at once — whether the OpenZeppelin pin is the remaining delta, and whether parity is reachable from source at all.

Judge the result against the deployed mainnet runtime, not against the size limit. Truncate the deployed runtime by its own trailing CBOR length, which is encoded in its last two bytes; mask both sides at the offsets given by the artifact's `deployedBytecode.immutableReferences`, since the deployed copy has constructor immutables baked in where a fresh artifact carries zeroed placeholders; compare lengths first, then the masked bytes.

A match authorises the PB-D32 (vii) mechanism. A miss voids it and reopens the lock, with the Yul `optimizerSteps` sequence and the pinned submodule commit `68057fda` as the next suspects. Do not change the OpenZeppelin pin before i1 matches.
