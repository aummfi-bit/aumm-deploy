# Stage P-bis — session handoff, 2026-07-27

**Status: the EIP-170 blocker is CLOSED; the Sepolia sequence remains MID-SEQUENCE AND HALTED.** The build defect that stopped rung i is fixed — `Vault` now compiles to 24,393 bytes, inside the 24,576 limit, via a scoped compiler profile landed at `4268e50`. What has not changed: steps 1 and 2 of the base-layer broadcast were partially executed on live Sepolia, and the base layer is dead from nonce 87. No further broadcast may occur until phase A re-runs against the corrected build and the deployer is funded.

CLAUDE.md §11 is current only through rung h and knows nothing of PB-D32 through PB-D35 or of the fix. Read this file alongside it; where they disagree, the NOTES locks are authoritative.

**Superseded in part by PB-D32 through PB-D35** (`docs/STAGE_P_BIS_NOTES.md`, 2026-07-27 and 2026-07-28). Sections 1, 3, 4, 5 and 6 are revised to match those locks. Section 2's on-chain facts stand exactly as recorded, but all three contracts it lists are now dead — see section 4.

## 1. The EIP-170 blocker — CLOSED

| | runtime bytes |
| --- | --- |
| `Vault` as now built | **24,393** |
| EIP-170 limit | 24,576 |
| `Vault` as built before the fix | 28,304 |
| Balancer's live mainnet Vault (`0xbA1333333333a1BA1108E8412f11850A5C319bA9`) | 24,538 total, 24,485 stripped |
| `VaultExtension` / `VaultAdmin` as now built | 20,069 / 12,405 |

**The cause was one missing compiler setting.** Balancer compiled their mainnet Vault with an explicit Yul optimizer step sequence, `yulDetails.optimizerSteps`. Omitting it costs 782 bytes on `Vault` — the entire overrun. Proven by reproducing the deployed artifact's exact length from Sourcify's `exact_match` standard-json input through solc directly, then ablating that input one field at a time: deleting the step sequence alone, everything else held constant, moves 24,538 to 25,320. Full evidence in PB-D33.

**What was ruled out, with measurements.** The OpenZeppelin pin, 5.0.0 against our 5.6.1, is worth 31 bytes and is NOT being changed. The compiler version is worth 2 bytes. Optimizer runs — 9999 against Balancer's 500 — is worth 3,143 bytes and was necessary but nowhere near sufficient. Submodule source drift is real but is not the size cause.

**The fix is a scoped compiler profile.** `foundry.toml` gains a `[profile.vault]` named profile carrying Balancer's settings, built on demand with `FOUNDRY_PROFILE=vault forge build` into `out-vault`. `[profile.default]` is untouched, so no Aureum contract changed compilation — measured at three artifacts moved out of 470, all downstream of the one script that changed. `script/DeployAureumVault.s.sol` reads the three creation codes from those artifacts via `vm.getCode`. Gates: 947 unit tests, and the P10 mainnet-fork close gate 13/13 driving the script against a real `create()`. Landed at `4268e50`; mechanism and measurements in PB-D34.

**Why no gate caught the original defect.** forge does not enforce EIP-170 in simulation and `forge config` reports no `code_size_limit`, so every fork test that "deployed the Vault" — the P10 close gate, the PB3.4 rehearsal, the whole Stage B–P vault surface — was validating an artifact no chain would accept. A permanent deployed-size assertion is rung i6.

**This build is NOT byte parity with the audited artifact and does not claim to be.** Ours is 24,393; the deployed Vault's stripped code is 24,485. The gap is submodule source drift — our pin predates two 2024-12-04 commits whose changes are semantic, not cosmetic. Adjudicated: Sepolia requires EIP-170 fit only, and parity together with the pin bump is a Stage-R gate. PB-D34 (viii) and (ix) carry both the reasoning and the price.

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

**The deployer EOA must send nothing between the phase A nonce read and the step 2 broadcast.** Phase A re-ran on 2026-07-29 and its output is live: `n0 = 90` was read at A1, and all seven keys in section 4's canonical table derive from it. Any transaction sent from the deployer before step 2 is broadcast shifts the nonce and voids every one of them, forcing phase A to restart from a fresh `n0`. Note that on this resume step 1 is NOT re-broadcast — the 87 stubs are reused per PB-D38 (ii) — so step 2, `DeployAureumVault`, is the first broadcast of the sequence and the point at which the projected nonce range begins to be consumed. Per runbook section 8.

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

**Superseded by the PB3.5i8 re-run.** The table above is history. Phase A re-ran on 2026-07-29 from the live nonce `n0 = 90` with `c1` omitted per PB-D38 (ii), because the 87 stubs at nonces 0—86 are reused rather than redeployed. The set below is CANONICAL and is what `.env.sepolia` now holds. Note the overlap: nonces 91, 92 and 93 appear in BOTH tables carrying DIFFERENT keys, because an address is a pure function of deployer and nonce — no pair may be copied from the void table.

| Nonce | Key | Address — CANONICAL |
| --- | --- | --- |
| 90 | *(authorizer, no env key)* | `0x21E5f855B45943d18Fa2A76635A06D024d1f0E3A` |
| 91 | `FEE_CONTROLLER` | `0xb424796989Ba0Baaaa879Db0C0d1FEf638fEa3ef` |
| 92 | *(vault factory, no env key)* | `0x0321Cc252D09C30E21D59B17f667c2e6e43f2855` |
| 94 | `WEIGHTED_POOL_FACTORY` / `AUREUM_WEIGHTED_POOL_FACTORY` | `0xC60E426294a06Fb95a6C1BB7A06219f794AAde8F` |
| 96 | `FEE_ROUTING_HOOK` | `0x954c972170eC131364570658D42F14e833A08588` |
| CREATE3 | `VAULT` / `AUREUM_VAULT` | `0x9c7e8F56D12823609C28788d4b80a315CcC5fC80` |
| CREATE3 | `DER_BODENSEE_POOL` | `0xD258d7670f2F7B86d4cAdcE20eC922FB2A908798` |

`GENESIS_BLOCK` is deliberately a `999999999` placeholder — set it to Sepolia head plus 100,800 immediately before step 4 per PB-D19. The Etherscan API key is still absent.

`.env` is gitignored. Its projection set is now void; its live 67-pair `STUB_` map is the part that still matters, and losing that machine means redeploying the stubs as well as re-running phase A.

## 5. The decision to make — chat-level, do not act unilaterally

**Adjudicated 2026-07-27 as PB-D32, then superseded by PB-D33, PB-D34 and PB-D35.** What follows is retained as the record of what was weighed; every question below is answered across those four locks, and PB-D32's own answers were themselves corrected twice. Do not re-adjudicate from this section.

Changing `optimizer_runs` alters the compiler configuration CLAUDE.md §2 locks, and under which every audit artifact was produced: the 928-test unit suite, the 55 hevm proofs, the nine `.act` specs, the whole `formal/` bundle. Per §8c and §12 this is an architectural decision requiring explicit user adjudication and a PB-D lock, not an operational step.

Open questions:

1. What settings did Balancer actually use, per package? Their hardhat config and the verified Etherscan source for the mainnet Vault are the sources of truth — not our assumption.
2. Does a per-package or per-contract optimizer setting fit `foundry.toml`, or does this require a profile split?
3. Does the change alter Aureum-owned contract bytecode, and what must be re-run — unit suite, fork suites, hevm proofs, Act specs?
4. Does CLAUDE.md §2's compiler row need correcting, and §11 the finding?
5. Should a deployed-bytecode-size assertion become a permanent gate so this cannot recur? Strong candidate for an RB register row; RB-008 was the last added.

## 6. First move for the next session

The EIP-170 investigation is CLOSED. Do not reopen it, and do not run the OpenZeppelin probe this document previously pointed at — that hypothesis was disproven, at 31 bytes against the several hundred needed, and the real cause is settled in PB-D33.

Read PB-D34 and PB-D35 in `docs/STAGE_P_BIS_NOTES.md`. Branch tip at handoff: `6a8fbad`.

Next is rung **i5c** — the `.env` split per PB-D35: rename the preserved overlay to `.env.sepolia`, amend `docs/STAGE_P_BIS_SEPOLIA_RUNBOOK.md` section 6 so its capture instructions write there rather than to `.env`, add a `set -a; source .env.sepolia; set +a` preamble to each broadcast command, and add a pre-run check that `grep -c "^STUB_" .env` returns zero. Its trigger is hard: i5c must land BEFORE phase A repopulates any Sepolia key, or the contamination recurs immediately.

Then, in order: **i6** the permanent deployed-bytecode-size gate plus its RB register row; **i7** the CLAUDE.md §2 compiler-row correction, the §11 advance and the PB15 lesson entry; **i8** the phase A re-run from the live nonce per PB-D33 (ix); **i9** the broadcast resumes.

**The hard gate on i8 and i9 is funding, not engineering.** The deployer holds roughly 0.05 SepETH against a 1.0—1.5 target. Nothing downstream of i7 can proceed until that is met, and the deployer EOA must send nothing else in the meantime.
