# Stage P-bis — phase A measurement record

**What this is.** A dated record of the phase A runs, all against Sepolia (chain 11155111). THREE are recorded across TWO deployment generations: the rung h run of 2026-07-26 in sections 1 through 6 and the PB3.5i8 re-run of 2026-07-29 in section 7, both executed under `docs/STAGE_P_BIS_SEPOLIA_RUNBOOK.md` section 8 and both belonging to generation 1; and the PB3.13h refresh run of 2026-08-13 in sections 8 and 9, executed under `docs/STAGE_P_BIS_SEPOLIA_REFRESH_RUNBOOK.md` section 8 and belonging to generation 2. Sections 8 and 9 are the LIVE set. Sections 1 through 7 are retained as history — their counts still hold, their addresses do not, and generation 1 is itself abandoned on chain per PB-D70 (i).

**What this is not.** Not a procedure and not a specification. The procedure is section 8 of the runbook governing each run; this file records executions of them. The counts in section 2 are structural and durable per PB-D28 (ii), with the qualification section 7 adds and section 8 inherits: `c1` is the fresh-stub-deploy figure and is not an addend when a sequence resumes onto stubs already live, which both later runs do. Addresses are never durable — section 4's were derived under the precondition in section 6, that precondition broke when the base layer died, section 7 superseded them, and the generation-2 run superseded section 7 in turn. Section 7's supersession was foreseen in this paragraph before it happened, as section 4's was foreseen in section 6, and a fourth run would supersede sections 8 and 9 the same way. No address outside sections 8 and 9 may be acted on or copied into their set, and the recurrence of one value under different roles across runs is expected rather than suspicious, an address being a pure function of deployer and nonce.

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

## 8. The 2026-08-13 generation-2 run (PB3.13h)

**Why there is a third run.** The entire generation-1 constellation is abandoned. `AureumFeeRoutingHook` carries the F-23 fix, the Vault seals `_hooksContracts` at pool registration and `FEE_ROUTING_HOOK` is immutable on the fee controller, so a corrected hook cannot be swapped under live pools and everything pointing at it redeploys — a cascade that reaches AuMM, whose `setMinter` is one-shot and has burned its admin. PB-D70 batches five proven corrections into that forced redeployment and abandons all 53 live protocol contracts along with the emission clock; only the 87 stubs at nonces 0 to 86 survive. Sections 4 and 7 are both history from here. Governed by PB-D70, clause (v) for the projection model this run executes.

**Inputs, against sections 1 and 7.** `n0` is 692, measured at A1 with `cast nonce`. The deployer, the chain id, `SALT` and the CREATE3 proxy init-code hash are unchanged from both earlier runs. `BODENSEE_SALT` is not: it becomes `0xe8adfe84affa1498e12af213d44eb960718a5223d3c3d4c7e1af1dbc1e56c25e`, reproducible by `cast keccak "aureum.derBodensee"`, which moves der Bodensee out of the 1-to-28 Miliarium slot space per PB-D70 (vi) and (xvii). That retires the CREATE3 collision which cost generation 1 a second and then a third sender EOA, so all 26 pools and der Bodensee now broadcast from the single deployer in one contiguous run.

**This is the refresh branch, a resume in the same sense section 7 was.** The 87 stubs are live and reused, step 1 is not broadcast, and every `c1` term is absent from the arithmetic rather than set to zero. Their code and their vault-to-underlying relations were verified against the chain at PB3.13e, and the stub templates carry no `selfdestruct`, no `delegatecall`, no `assembly` and no proxy pattern, which makes both properties structurally permanent rather than merely observed. PB-D70 (xix) therefore moves the pre-broadcast probe to the rung i pre-flight instead of repeating it here.

**Chain state at A1, and the one premise that moved under it.** The deployer stood at nonce 692 holding 5782928979297694346 wei, both figures reproducing PB-D70 (xvi)'s readings of 2026-08-11 and 2026-08-12 to the wei, so the zero-wei reconciliation against the deployment record's four recorded broadcast costs now holds across three readings on three days. Sepolia head read 11482005, which is 4,385 blocks PAST generation 1's `GENESIS_BLOCK` of 11477620, read from the deployed AuMM rather than from any env file. That clock has started and nothing accrued: the balance is wei-identical across the crossing, which is positive evidence for PB-D70 (xvi)'s claim that accrual becomes possible but never automatic, every state change needing a caller and there being none. F-23 exposure stays zero on the independent ground that der Bodensee is registered and never initialised.

**The nine projection keys were DELETED before any write.** A2 cleared `VAULT`, `AUREUM_VAULT`, `FEE_CONTROLLER`, `WEIGHTED_POOL_FACTORY`, `AUREUM_WEIGHTED_POOL_FACTORY`, `DER_BODENSEE_POOL`, `FEE_ROUTING_HOOK`, `AUMM` and `GENESIS_BLOCK` from `.env.sepolia`, every one of which arrived holding generation 1's live value. Without that clear the phase's own completeness check could not fail, and four of the nine bind with no assertion anywhere on the deploy path. Per PB-D70 (xviii).

### Counts

| Step | Script | Count | Against sections 2 and 7 |
| --- | --- | --- | --- |
| 2 | `DeployAureumVault` | 4 | agrees |
| 3 | `DeployAureumWeightedPoolFactory` | 1 | agrees |
| 4 | `DeployAuMM` | 1 | agrees |

Re-derived live at this run as a CROSS-CHECK rather than as a source. Unlike both earlier runs, the refresh runbook's section 5 ships complete from generation 1's finished broadcast, so a disagreement here would have been a stop rather than a measurement. All three agree.

Estimated gas at the three simulations, recorded because no other artifact carries them: step 2 at 22,016,530 gas and 2.108504922 gwei for 0.04642196187036066 ETH; step 3 at 18,415,294 gas and 1.904160758 gwei for 0.035065680181832852 ETH; step 4 at 1,002,948 gas and 1.955988 gwei for 0.001961754252624 ETH. Steps 3 and 4 differ from section 2's readings by 297 and 16 gas, both from changed constructor arguments rather than from changed code.

### Nonce ledger

| Nonce | Consumer |
| --- | --- |
| 0—86 | the 87 stubs, live since generation 1, reused; step 1 NOT re-broadcast |
| 87—89 | the pre-EIP-170 base layer, abandoned in place since PB-D33 |
| 90—691 | the whole generation-1 deployment — base layer, 26 pools, phase 4, oracle wiring, seeding, Router seat — ABANDONED per PB-D70 (i) |
| 692 | `AureumAuthorizer` CREATE |
| 693 | `AureumProtocolFeeController` CREATE |
| 694 | `AureumVaultFactory` CREATE |
| 695 | `factory.create()` CALL |
| 696 | weighted pool factory CREATE |
| 697 | AuMM CREATE |
| 698 | fee-routing hook CREATE |

Der Bodensee again takes no nonce of its own, being a CREATE3 from the weighted pool factory and therefore fixed once nonce 696 is fixed. The PB-D30 reorder holds: with the hook at step 5 the projection sum stops at step 4.

### Projections — CANONICAL

| Key | Address | Derivation |
| --- | --- | --- |
| (authorizer, no env key) | `0x76Feb973836a2fb90203d2bdbFB9Fc85E6502376` | CREATE at nonce 692 |
| `FEE_CONTROLLER` | `0x9822070EC9aBB40b1bEA6526D9807053574Bd864` | CREATE at nonce 693 |
| `AUREUM_VAULT_FACTORY` | `0x118C7286fA9dB3F81dCBD329b1efDB97d131fA10` | CREATE at nonce 694 |
| `VAULT` and `AUREUM_VAULT` | `0xFd235D859f816511627A8Df495628b35267c8279` | CREATE3 from the vault factory, RAW `SALT` |
| `WEIGHTED_POOL_FACTORY` and `AUREUM_WEIGHTED_POOL_FACTORY` | `0x58fCdbE48C0e4c448864F75804AE788FAa6B5884` | CREATE at nonce 696; one address under two keys per PB-D27 (ix) |
| `DER_BODENSEE_POOL` | `0x581F0D2E819221B17A4CEC20CBe460b08207684a` | CREATE3 from the weighted pool factory, SENDER-HASHED salt |
| `FEE_ROUTING_HOOK` | `0x99F65d18c254B9805Af80635B45D420414212B4a` | CREATE at nonce 698 |

Eight keys carrying seven addresses, written into `.env.sepolia` with `.env` refreshed from it per PB-D36. Section 7 wrote seven keys; this run adds `AUREUM_VAULT_FACTORY`, which PB-D70 (xix) found holding generation 1's nonce-92 value and which `script/CreateAureumVault.s.sol` L41 reads — the recovery path generation 1 actually took when step 2's fourth transaction was refused at submission. It is written rather than gated because that script already fails closed on a stale value, comparing `factory.getDeploymentAddress(salt)` against `AUREUM_VAULT`.

`AUMM` is deliberately NOT projected, as in section 7. Its address is captured from step 4's own broadcast, and its consumers are `script/DeployFeeRoutingHook.s.sol` L68 and `script/DeployDerBodensee.s.sol` L68 at steps 5 and 6.

`GENESIS_BLOCK` stands PROVISIONAL at 11582895, the head of 11482095 read at A8 plus 100,800. PB-D19 requires re-derivation from a fresh head immediately before the step 4 broadcast; a value carried forward does not fail but silently shortens the fourteen-day pad by the elapsed time, since `script/DeployAuMM.s.sol` L33 reads it with no `block.number` clamp.

**The A10 gate discriminated rather than counted.** Each of the seven keys above was grepped against the committed `docs/STAGE_P_BIS_SEPOLIA_DEPLOYMENT_RECORD.md` and returned zero hits — a source-diff against the artifact rather than against a transcription of it, and broader than PB-D70 (xviii) requires, since it catches a value transposed between two keys as well as one inherited into its own. The check is not vacuous: all five generation-1 base-layer addresses return two to four hits against that same file. `GENESIS_BLOCK` passed its own predicate, differing from the abandoned 11477620 and exceeding the head read at A1.

**Three sets now overlap and no address may be copied between them.** An address is a pure function of deployer and nonce, so the same value recurs across runs under different roles: section 4's `AUMM` and section 7's vault factory are both `0x0321Cc252D09C30E21D59B17f667c2e6e43f2855`. Sections 4 and 7 are history; this table is what `.env.sepolia` holds and the only set that may be acted on.

## 9. Method validation at generation 2

The CREATE3 derivation was re-validated at this run's own nonce rather than inherited from section 5. Step 2's dry-run artifact records what forge produced at `n0 = 692`, and the `cast` commands of refresh-runbook section 8 were run against the same inputs and reproduced it exactly.

| | forge's dry-run artifact | recomputed with `cast` |
| --- | --- | --- |
| nonce 692 | `0x76feb973836a2fb90203d2bdbfb9fc85e6502376` | `0x76Feb973836a2fb90203d2bdbFB9Fc85E6502376` |
| nonce 693 | `0x9822070ec9abb40b1bea6526d9807053574bd864` | `0x9822070EC9aBB40b1bEA6526D9807053574Bd864` |
| nonce 694 | `0x118c7286fa9db3f81dcbd329b1efdb97d131fa10` | `0x118C7286fA9dB3F81dCBD329b1efDB97d131fA10` |
| CREATE3 proxy | `0x85165620ce6eabfa3a54058486723a204f240c42` | `0x85165620CE6EaBfA3a54058486723A204F240c42` |
| Vault via CREATE3 | `0xfd235d859f816511627a8df495628b35267c8279` | `0xFd235D859f816511627A8Df495628b35267c8279` |

Case differs only because the artifact stores lowercase and `cast` returns checksummed, as at section 5.

**One row is new in kind rather than merely in value.** Section 5 corroborated the two-step mechanism by observing that `additionalContracts` held three CREATE2 entries plus a final CREATE, without matching any individual proxy against a computed one. Here the third CREATE2 entry is `0x85165620ce6eabfa3a54058486723a204f240c42`, exactly the intermediate `cast create2` produced before `cast compute-address` was applied to it at nonce 1. The chain is therefore confirmed at BOTH steps rather than only at its result, which excludes a compensating pair of errors — a wrong proxy that still yields the right Vault — rather than leaving it merely improbable.

**The two remaining CREATE2 entries are recorded here rather than rediscovered later.** They are `0xa4521c41233e8b30616af0e2b6abfc8c365e8997` and `0xbb052a2930ed5560dca05b835a9cabe4873d7f09`, and per PB-D38 (iv) the four contracts `factory.create()` deploys internally are `VaultAdmin`, `VaultExtension`, the CREATE3 proxy and the Vault. Which of the two is which is not determined by the artifact and is left unassigned until the broadcast. Generation 1 recorded neither, and PB3.5i's explorer verification had to identify them from the chain because no committed artifact had ever named them; writing them down at projection time removes that step.

**What this retires, and what it does not.** The residual at the end of runbook section 8, restated at `docs/STAGE_P_BIS_SEPOLIA_REFRESH_RUNBOOK.md` L305, is that the derivation was validated at nonce 0 and applied elsewhere by pure offset, so a count wrong by one would shift every projection downstream with nothing to catch it. For the three plain CREATEs and the Vault's CREATE3 that residual is CLOSED: the validation was performed at 692, 693 and 694 themselves, and forge reproduced the Vault at the same nonce in the same run. What is NOT closed is the offset arithmetic past step 2. The weighted pool factory at nonce 696 and the hook at nonce 698 are still reached by adding measured counts to `n0`, and der Bodensee's CREATE3 is computed from a factory address that has no code yet. Those counts are stronger evidence than generation 1 had — measurements from a completed broadcast, each re-derived live at A4, A6 and A8, each agreeing — but they remain the load-bearing assumption, and the first on-chain confirmation of der Bodensee is still `BodenseeAddressMismatch` at step 6, after the vault has sealed its immutables.

**What would void this validation, against section 6.** Section 8's projections die and phase A re-runs in full if the deployer sends any transaction on Sepolia before step 2 broadcasts, if `SALT` or `BODENSEE_SALT` changes again, if the deployer address changes, or if any of the three simulated scripts changes in a way that alters its transaction count. Section 6's list is otherwise unchanged and still governs; only its first condition needed restating, since it now reads against `n0 = 692` rather than against a deployer whose next transaction was stub deploy number one.

## 10. Related

- Procedure: `docs/STAGE_P_BIS_SEPOLIA_RUNBOOK.md` section 8 for the generation-1 runs of sections 1 through 7; `docs/STAGE_P_BIS_SEPOLIA_REFRESH_RUNBOOK.md` section 8 for the generation-2 run of sections 8 and 9.
- Count table: the same runbooks, section 5 — rows 1 through 4 of the first, rows 2 through 4 of the second, which ships complete from generation 1's broadcast.
- Decisions: PB-D28 (ii) for the structural-versus-nonce-dependent split, PB-D29 for the two-phase shape, PB-D30 for the hook-before-Bodensee reorder, PB-D31 for the missing-broadcast defect the first run surfaced, PB-D33 (ix) for the voiding of section 4, PB-D38 for the re-run recorded in section 7, and PB-D70 for the generation-2 refresh recorded in sections 8 and 9 — clause (v) for the projection model, (vi) and (xvii) for the salt, (xviii) for the delete-then-discriminate gate and (xix) for the twenty-nine non-projection keys.
