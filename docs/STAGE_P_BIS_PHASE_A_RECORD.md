# Stage P-bis — phase A measurement record

**What this is.** A dated record of the phase A runs, per `docs/STAGE_P_BIS_SEPOLIA_RUNBOOK.md` section 8, both against Sepolia (chain 11155111). Two are recorded: the rung h run of 2026-07-26 in sections 1 through 6, and the PB3.5i8 re-run of 2026-07-29 in section 7. Section 7 is the live one. Sections 1 through 6 are retained as history — their counts still hold, their addresses do not.

**What this is not.** Not a procedure and not a specification. The procedure is section 8 of the runbook; this file records executions of it. The counts in section 2 are structural and durable per PB-D28 (ii), with the qualification section 7 adds: `c1` is the fresh-stub-deploy figure and is not an addend when a sequence resumes onto stubs already live. Addresses are never durable — section 4's were derived under the precondition in section 6, that precondition broke when the base layer died, and section 7 supersedes them; a fresh phase A would supersede section 7 the same way. No address in section 4 may be acted on, or copied into section 7's set.

## 1. Inputs

| Input | Value | Source |
| --- | --- | --- |
| Deployer / `GOVERNANCE_MULTISIG` | `0xA851478dbee97375E784e9b98c0D7D599662bF85` | PB3.1; runbook section 0 |
| Chain id | 11155111 | PB-D1 |
| `n0` (deployer nonce at A1) | 0 | measured, `cast nonce` |
| `SALT` | `0x0000000000000000000000000000000000000000000000000000000000000001` | runbook section 6 |
| `BODENSEE_SALT` | `0x0000000000000000000000000000000000000000000000000000000000000002` | runbook section 6, PB3.4 rehearsal parity |
| CREATE3 proxy init-code hash | `0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f` | `cast keccak 0x67363d3d37363d34f03d5260086018f3`, matches the published solmate constant |

## 2. Measured counts

Each count is the length of the `transactions` array in that step's `forge script` dry-run artifact, run with `--rpc-url sepolia --sender <deployer>` and no `--broadcast`.

| Step | Script | Count | Est. gas | Est. cost |
| --- | --- | --- | --- | --- |
| 1 | `DeployTestnetStubs` | 87 | 62,837,085 | 0.14172536183325147 ETH |
| 2 | `DeployAureumVault` | 4 | 26,099,545 | 0.05779254289151442 ETH |
| 3 | `DeployAureumWeightedPoolFactory` | 1 | 18,414,997 | — |
| 4 | `DeployAuMM` | 1 | 1,002,964 | — |

Measured gas price at the step-2 run: 2.214312276 gwei. Step 1's 87 transactions are all `CREATE`, confirmed by transaction-type breakdown; step 2's 4 are three `CREATE` plus one `CALL`.

Row 1 reconciles against the emitted maps: 3 CREATEs for each of 14 WITH_RATE tokens plus 1 for each of 45 STANDARD tokens gives 87, and the 67 `STUB_` pairs are those 14 plus 45 plus 8 distinct rate-provider literals, which record as aliases of an already-deployed provider rather than as fresh deploys.

## 3. Nonce ledger

| Nonce | Consumer |
| --- | --- |
| 0—86 | step 1, `DeployTestnetStubs`, 87 transactions |
| 87 | `AureumAuthorizer` CREATE |
| 88 | `AureumProtocolFeeController` CREATE |
| 89 | `AureumVaultFactory` CREATE |
| 90 | `factory.create()` CALL |
| 91 | weighted pool factory CREATE |
| 92 | AuMM CREATE |
| 93 | fee-routing hook CREATE |

Der Bodensee takes no nonce of its own: it is a CREATE3 from the weighted pool factory, so it is fixed once nonce 91 is fixed. This is the PB-D30 reorder working as intended — with the hook at step 5 the sum stops at step 4, and no der-Bodensee count enters any projection.

## 4. Projections

Derived from section 1 and section 3. Superseded by any fresh phase A.

| Key | Address | Derivation |
| --- | --- | --- |
| (authorizer, no env key) | `0x655efe2DD8728af106C933cD88A89646D2C7De02` | CREATE at nonce 87 |
| `FEE_CONTROLLER` | `0x985eA467837eE8C2598474E54395DB8B0822Ce1F` | CREATE at nonce 88 |
| (vault factory, no env key) | `0x6649f7A65b6937F6D2E46d4FB418fFb12079f560` | CREATE at nonce 89 |
| `VAULT` and `AUREUM_VAULT` | `0xD3c076a2B096A8b7B6744A078473C20b5E8a6c03` | CREATE3 from the vault factory, RAW `SALT` |
| `WEIGHTED_POOL_FACTORY` and `AUREUM_WEIGHTED_POOL_FACTORY` | `0xb424796989Ba0Baaaa879Db0C0d1FEf638fEa3ef` | CREATE at nonce 91; one address under two keys per PB-D27 (ix) |
| `DER_BODENSEE_POOL` | `0xbE98Bbd2856d8694b42A47585c5F65011f5FD0Bc` | CREATE3 from the weighted pool factory, SENDER-HASHED salt |
| `AUMM` | `0x0321Cc252D09C30E21D59B17f667c2e6e43f2855` | CREATE at nonce 92 |
| `FEE_ROUTING_HOOK` | `0x587229d7e7bDaD6dBbd628C64722d4Ab6b059549` | CREATE at nonce 93 |

All nine keys were written into `.env` and verified present exactly once each. `GENESIS_BLOCK` deliberately remains a placeholder and must be set to the PB-D19 value, Sepolia head plus 100,800, immediately before step 4 per runbook section 6.

## 5. Method validation

The derivation was checked against forge's own execution before any value was relied on. The step-2 dry-run artifact records what forge produced at `n0 = 0`; the same four `cast` commands were run at those nonces and reproduced it exactly.

| | forge's dry-run artifact | recomputed with `cast` |
| --- | --- | --- |
| nonce 0 | `0xcc72810e4a91d2bdba70b380c9c41327d0e63169` | `0xCc72810e4A91D2BDba70B380C9c41327D0E63169` |
| nonce 1 | `0x1aaaa43ae8fa57d9686b8fbb7944d2d22f4ff166` | `0x1AAaA43Ae8fa57d9686b8FbB7944d2d22f4Ff166` |
| nonce 2 | `0xe17791a546115ca7031131fb19ead83a58581c5c` | `0xe17791a546115cA7031131fB19EAD83A58581c5c` |
| Vault via CREATE3 | `0x4cc2bc033f98edc5cbcbbddb008eca53f81cc058` | `0x4cC2bc033f98edC5cBCBbDDb008EcA53F81Cc058` |

Case differs only because the artifact stores lowercase and `cast` returns checksummed. The Vault row is the load-bearing one: it validates the two-step CREATE3 chain — CREATE2 proxy from the creator, then CREATE from that proxy at nonce 1 — against a real execution rather than against a reading of `CREATE3.sol`. The artifact's `additionalContracts` corroborates the mechanism, listing three `CREATE2` entries (`0x723a6bbe759fe4d012fb0299ffb5cf6064a1c077`, `0x065bc03fd5badd210fedc34dfc4b42e6b3a5702f`, `0x4e7e5e273327ba590e586c28495d06eb2fd7c327`) plus the single final `CREATE`.

This narrows the residual recorded at the end of runbook section 8: the chain is no longer unvalidated, it is validated at nonce 0 and applied to nonces 87 through 93 by pure offset.

## 6. Invalidation conditions

Section 4's addresses are void, and phase A must be re-run in full, if any of the following becomes true before step 1 broadcasts:

- The deployer sends any transaction on Sepolia. Every projection assumes the deployer's next transaction is stub deploy number one at nonce 0; a single unrelated transaction shifts all eight.
- `SALT` or `BODENSEE_SALT` changes.
- Any of the four scripts in section 2 changes in a way that alters its transaction count.
- The deployer address changes.

Section 2's counts survive all of these except the third, being structural and invariant under both nonce and chain per PB-D28 (ii) and PB-D30 (v).

## 7. The 2026-07-29 re-run (PB3.5i8)

**Why there is a second run.** The base layer died between the two. `AureumVaultFactory` seals `keccak256(type(Vault).creationCode)` as a constructor immutable, so the factory deployed at nonce 89 is permanently bound to a `Vault` that overran EIP-170 and must be redeployed; that shifts every later nonce and carries der Bodensee's CREATE3 address with it. PB-D33 (ix) voided all eight of section 4's projections, and this run recomputes them. Governed by PB-D38.

**Inputs, against section 1.** `n0` is 90, measured at A1 with `cast nonce`, not 0. The deployer, the chain id, `SALT`, `BODENSEE_SALT` and the CREATE3 proxy init-code hash are unchanged.

**This is the resume branch.** The 87 stubs at nonces 0—86 are live from the first sequence and are reused from the committed `STUB_` map, so step 1 is NOT re-broadcast, effective `c1 = 0`, and every `c1` term drops out of the A3, A5 and A9 arithmetic. A2 became confirm-and-skip: verify the reused map has code at every address rather than re-measure it. Per PB-D38 (ii).

### Counts

| Step | Script | Count | Against section 2 |
| --- | --- | --- | --- |
| 2 | `DeployAureumVault` | 4 | agrees |
| 3 | `DeployAureumWeightedPoolFactory` | 1 | agrees |
| 4 | `DeployAuMM` | 1 | agrees |

Re-measured at this run rather than carried across, per the PB15 rule that an unverified reading is not a measurement. Section 2's `c1 = 87` remains the correct count for a fresh stub deploy and is not an addend here. This run measured counts, not gas: step 1 is not re-broadcast, so section 2's row 1 gas and cost do not apply to the resumed sequence.

A count is the length of the top-level `transactions` array and nothing else. The grep form runbook section 8 used to offer is WITHDRAWN as a double-counter — every entry inside a transaction's `additionalContracts` array carries the same type field, and at this run's step 2 it returned 8 against the authoritative 4, the four extras being VaultAdmin, VaultExtension, the CREATE3 proxy and the Vault, all deployed inside `factory.create()`. PB-D38 (iv).

### Nonce ledger

| Nonce | Consumer |
| --- | --- |
| 0—86 | the 87 stubs, live from the first sequence, reused; step 1 NOT re-broadcast |
| 87—89 | the dead base layer — authorizer, fee controller, vault factory — abandoned in place |
| 90 | `AureumAuthorizer` CREATE |
| 91 | `AureumProtocolFeeController` CREATE |
| 92 | `AureumVaultFactory` CREATE |
| 93 | `factory.create()` CALL |
| 94 | weighted pool factory CREATE |
| 95 | AuMM CREATE |
| 96 | fee-routing hook CREATE |

### Projections — CANONICAL

| Key | Address | Derivation |
| --- | --- | --- |
| (authorizer, no env key) | `0x21E5f855B45943d18Fa2A76635A06D024d1f0E3A` | CREATE at nonce 90 |
| `FEE_CONTROLLER` | `0xb424796989Ba0Baaaa879Db0C0d1FEf638fEa3ef` | CREATE at nonce 91 |
| (vault factory, no env key) | `0x0321Cc252D09C30E21D59B17f667c2e6e43f2855` | CREATE at nonce 92 |
| `VAULT` and `AUREUM_VAULT` | `0x9c7e8F56D12823609C28788d4b80a315CcC5fC80` | CREATE3 from the vault factory, RAW `SALT` |
| `WEIGHTED_POOL_FACTORY` and `AUREUM_WEIGHTED_POOL_FACTORY` | `0xC60E426294a06Fb95a6C1BB7A06219f794AAde8F` | CREATE at nonce 94; one address under two keys per PB-D27 (ix) |
| `DER_BODENSEE_POOL` | `0xD258d7670f2F7B86d4cAdcE20eC922FB2A908798` | CREATE3 from the weighted pool factory, SENDER-HASHED salt |
| `FEE_ROUTING_HOOK` | `0x954c972170eC131364570658D42F14e833A08588` | CREATE at nonce 96 |

Seven keys, written into `.env.sepolia` with `.env` refreshed from it per PB-D36 — exactly the set runbook A10 requires before step 2, and no more. Section 4 additionally projected `AUMM`; this run does not. AuMM's address is captured from step 4's own broadcast, and its only script consumers are `script/DeployFeeRoutingHook.s.sol` L68 and `script/DeployDerBodensee.s.sol` L68, which run at steps 5 and 6.

**The two sets overlap, and no pair may be copied forward.** Nonces 91, 92 and 93 carry addresses in both section 4 and here, under DIFFERENT keys each time: an address is a pure function of deployer and nonce, so the same value lands under a different role. Section 4 is history; this table is what `.env.sepolia` holds.

`GENESIS_BLOCK` stands provisional at 11475787 and is re-derived from Sepolia head plus 100,800 immediately before step 4 per PB-D19.

## 8. Related

- Procedure: `docs/STAGE_P_BIS_SEPOLIA_RUNBOOK.md` section 8.
- Count table: the same runbook, section 5, rows 1 through 4.
- Decisions: PB-D28 (ii) for the structural-versus-nonce-dependent split, PB-D29 for the two-phase shape, PB-D30 for the hook-before-Bodensee reorder, PB-D31 for the missing-broadcast defect the first run surfaced, PB-D33 (ix) for the voiding of section 4, and PB-D38 for the re-run recorded in section 7.
