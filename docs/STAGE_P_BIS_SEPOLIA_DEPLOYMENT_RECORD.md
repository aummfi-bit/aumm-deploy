# Stage P-bis — Sepolia live deployment record

Chain 11155111. Deployer `0xA851478dbee97375E784e9b98c0D7D599662bF85`, held in the forge keystore as account `aumm-sepolia`. Governed by PB-D27 (go-live architecture) and PB-D38 (the resume branch). The projections this record confirms are in `docs/STAGE_P_BIS_PHASE_A_RECORD.md` section 7; the operator procedure is `docs/STAGE_P_BIS_SEPOLIA_RUNBOOK.md`.

**Why this file exists.** `.gitignore` L6 excludes `broadcast/` and L15 excludes `.env.sepolia`, so forge's own run artifacts and the operator environment are both local-only and unversioned. Without this record a lost working tree would leave the chain as the sole source of truth, and the deployment would have to be reconstructed by forensics rather than read.

## 1. Base layer — nonces 87 to 97

| Nonce | Contract | Address | Block | Gas used | Transaction |
| --- | --- | --- | --- | --- | --- |
| 87 | `AureumAuthorizer` — ABANDONED | `0x655efe2dd8728af106c933cd88a89646d2c7de02` | 11365037 | 132,210 | `0x23e67e51408cad8606c56b0b5083487313f3df55d389db4fc0b5b72fcbf934d8` |
| 88 | `AureumProtocolFeeController` — ABANDONED | `0x985ea467837ee8c2598474e54395db8b0822ce1f` | 11365038 | 2,295,826 | `0xbca53bd1172c56020f5706fc3068483fe3bc5a86e4c04057f6c8f1397c39b9f8` |
| 89 | `AureumVaultFactory` — ABANDONED | `0x6649f7a65b6937f6d2e46d4fb418ffb12079f560` | 11365039 | 1,006,230 | `0x4e4d2d8ecd9d7ed8aa6e40a59ef33ad9e9cd99a007efaf8275e67c509b22531c` |
| 90 | `AureumAuthorizer` CREATE | `0x21E5f855B45943d18Fa2A76635A06D024d1f0E3A` | 11375957 | 132,210 | `0xde3c61da72b1012af344d3e5be22b95c7240163b0feca1502501c473ec61d792` |
| 91 | `AureumProtocolFeeController` CREATE | `0xb424796989Ba0Baaaa879Db0C0d1FEf638fEa3ef` | 11375957 | 2,295,826 | `0x617cb76ca8076c80492b0cbee89a1ff5f8cdbca54586cb307e61d3e54fdc5d3c` |
| 92 | `AureumVaultFactory` CREATE | `0x0321Cc252D09C30E21D59B17f667c2e6e43f2855` | 11375957 | 1,006,230 | `0x97afa217e5d61f3c468477f388e67a2deca7f8bc7671051efc01fbe093282913` |
| 93 | Vault, via `factory.create()` CALL | `0x9c7e8F56D12823609C28788d4b80a315CcC5fC80` | 11376748 | 12,707,749 | `0x999fce03f1105e0b0b9551540a0eb338441c272c2e935f16f3c9cc9948458af8` |
| 94 | `WeightedPoolFactory` CREATE, upstream per PB-D27 (ix) | `0xC60E426294a06Fb95a6C1BB7A06219f794AAde8F` | 11376787 | 14,165,611 | `0xbebc049d8c44ab18d78bb32e2db853e3050e7a3bc908b9535bf55c304d5c000a` |
| 95 | `AuMM` CREATE | `0xb8947f2fE2177d36f2f990300106f27c738DFC8D` | 11376849 | 771,499 | `0x4bf7d4cf5fa603cd3da00a10968fd29c76fd0633162815a5a0c7b61d26a8dd5e` |
| 96 | `AureumFeeRoutingHook` CREATE | `0x954c972170eC131364570658D42F14e833A08588` | 11376875 | 2,834,031 | `0x75f78cf76d477bdd9f435f25ce7b383194d9636a35d325155f7e036d61c019d7` |
| 97 | der Bodensee pool, via WPF `create()` CALL | `0xD258d7670f2F7B86d4cAdcE20eC922FB2A908798` | 11376924 | 4,807,026 | `0x63579432c28bbc5031507e0a1d6eabcede8f120a20eb144d3d13470c522e359b` |

**Nonces 87 to 89 are dead and abandoned in place.** They are the pre-EIP-170-fix base layer. `AureumVaultFactory` seals `keccak256(type(Vault).creationCode)` as a constructor immutable, and the Vault compiled at that revision overran the 24,576-byte limit, so the factory at nonce 89 is permanently bound to a Vault that cannot be deployed on any chain. PB-D32 through PB-D34 record the diagnosis and the scoped `[profile.vault]` fix. They are listed here because a block explorer shows them and a reader must be able to tell which set is live.

**Nonces 90, 91 and 92 share block 11375957** and consumed gas identical to 87, 88 and 89 — the same bytecode and the same constructor-argument shapes, differing only in the values sealed.

**Nonce 93 is a CALL, not a CREATE.** `factory.create()` deploys `VaultAdmin`, `VaultExtension`, the CREATE3 proxy and the Vault internally, which is why the Vault address is a CREATE3 of the factory and the raw `SALT` and does not depend on the deployer nonce. It was broadcast by `script/CreateAureumVault.s.sol` and not by `DeployAureumVault.s.sol`, because the latter had already landed nonces 90 to 92 when its fourth transaction was refused at submission; re-running it would have derived a fresh `predictedFactory` from the live nonce and stranded the sealed immutables of the first set.

## 2. Testnet stubs — nonces 0 to 86

87 stubs across blocks 11364670 to 11364812, deployed by `test-stubs/DeployTestnetStubs.s.sol` and REUSED unchanged by the resume branch: `StubERC20`, `StubERC4626` and `ERC4626RateProvider` instances, 576,878 to 844,555 gas each. Step 1 was NOT re-broadcast per PB-D38 (ii) — re-running it would mint a fresh roster from the live nonce upward, orphan the map every later step reads, and consume the nonces the base-layer projections derive from.

The live addresses are the `STUB_` block of `.env.sepolia`: 67 `STUB_<mainnet literal>=<sepolia stub>` pairs plus seven named keys. That file is gitignored, so those 87 addresses are presently unversioned. `test-stubs/sepolia-stubs.env` holds the FORK-SAMPLE map committed at PB3.2e3, which is a different value set and not a substitute. Closing that gap is an open item.

## 3. Related

- Projections confirmed by this record: `docs/STAGE_P_BIS_PHASE_A_RECORD.md` section 7.
- Operator procedure: `docs/STAGE_P_BIS_SEPOLIA_RUNBOOK.md` sections 6 and 8.
- Decisions: PB-D19 the genesis offset, PB-D26 the token sort, PB-D27 the go-live architecture, PB-D30 hook before der Bodensee, PB-D32 through PB-D34 the EIP-170 blocker, PB-D35 and PB-D36 environment isolation, PB-D38 the resume branch.
