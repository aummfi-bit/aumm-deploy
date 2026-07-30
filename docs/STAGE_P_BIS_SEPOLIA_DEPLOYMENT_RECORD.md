# Stage P-bis — Sepolia live deployment record

Chain 11155111. Deployer `0xA851478dbee97375E784e9b98c0D7D599662bF85`, held in the forge keystore as account `aumm-sepolia`. Governed by PB-D27 (go-live architecture) and PB-D38 (the resume branch). The projections this record confirms are in `docs/STAGE_P_BIS_PHASE_A_RECORD.md` section 7; the operator procedure is `docs/STAGE_P_BIS_SEPOLIA_RUNBOOK.md`.

**Why this file exists.** `.gitignore` L6 excludes `broadcast/` and L15 excludes `.env.sepolia`, so forge's own run artifacts and the operator environment are both local-only and unversioned. Without this record a lost working tree would leave the chain as the sole source of truth, and the deployment would have to be reconstructed by forensics rather than read.

## 1. Base layer — nonces 87 to 98

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
| 98 | `Router`, canonical Balancer V3, CREATE | `0xF0495705D3AFeC43A658D8451971c464df2CdF8a` | 11377215 | 5,024,459 | `0x00c940aee024fa0b0f216b6f87d2a228168a625f9845e8f253bd870f3f16a5b8` |

**Nonces 87 to 89 are dead and abandoned in place.** They are the pre-EIP-170-fix base layer. `AureumVaultFactory` seals `keccak256(type(Vault).creationCode)` as a constructor immutable, and the Vault compiled at that revision overran the 24,576-byte limit, so the factory at nonce 89 is permanently bound to a Vault that cannot be deployed on any chain. PB-D32 through PB-D34 record the diagnosis and the scoped `[profile.vault]` fix. They are listed here because a block explorer shows them and a reader must be able to tell which set is live.

**Nonces 90, 91 and 92 share block 11375957** and consumed gas identical to 87, 88 and 89 — the same bytecode and the same constructor-argument shapes, differing only in the values sealed.

**Nonce 93 is a CALL, not a CREATE.** `factory.create()` deploys `VaultAdmin`, `VaultExtension`, the CREATE3 proxy and the Vault internally, which is why the Vault address is a CREATE3 of the factory and the raw `SALT` and does not depend on the deployer nonce. It was broadcast by `script/CreateAureumVault.s.sol` and not by `DeployAureumVault.s.sol`, because the latter had already landed nonces 90 to 92 when its fourth transaction was refused at submission; re-running it would have derived a fresh `predictedFactory` from the live nonce and stranded the sealed immutables of the first set.

## 2. Testnet stubs — nonces 0 to 86

87 stubs across blocks 11364670 to 11364812, deployed by `test-stubs/DeployTestnetStubs.s.sol` and REUSED unchanged by the resume branch: `StubERC20`, `StubERC4626` and `ERC4626RateProvider` instances, 576,878 to 844,555 gas each. Step 1 was NOT re-broadcast per PB-D38 (ii) — re-running it would mint a fresh roster from the live nonce upward, orphan the map every later step reads, and consume the nonces the base-layer projections derive from.

The live addresses are the `STUB_` block of `.env.sepolia`: 67 `STUB_<mainnet literal>=<sepolia stub>` pairs plus seven named keys. That file is gitignored, so those 87 addresses are presently unversioned. `test-stubs/sepolia-stubs.env` holds the FORK-SAMPLE map committed at PB3.2e3, which is a different value set and not a substitute. Closing that gap is an open item.

## 3. Gas limits and the provider ceiling

`forge script` sets each transaction's gas limit to the raw estimate scaled by `--gas-estimate-multiplier`, default 130. The figure it prints as `Estimated total gas used for script` IS that limit, not the raw estimate — confirmed by publicnode reporting `tx: 17552577` against a printed 17,552,577.

**Four providers refused the Vault transaction at its default-multiplier limit of 17,552,577.**

| Endpoint | Response | Cap disclosed |
| --- | --- | --- |
| Alchemy, the configured `SEPOLIA_RPC_URL` | `-32003` gas limit too high | none |
| `ethereum-sepolia-rpc.publicnode.com` | `-32000` gas limit too high | **16,777,216**, exactly 2^24 |
| `sepolia.drpc.org` | `-32000` INTERNAL_ERROR: gas limit is too high | none |
| `1rpc.io/sepolia` | could not serve the head block it had just reported | not reached |

The Sepolia block gas limit is 60,000,000, so every refusal is provider policy rather than chain capacity. `1rpc.io` failed differently and is unusable for `forge script` at all: a lagging or non-archive replica that answered `failed to get block number: 11376730; latest block number: 11376730`, so its ceiling was never learned.

**`sepolia.drpc.org` is unreliable in a second, independent way.** Later in the same session it began answering `eth_blockNumber` and `eth_getCode` with `-32601 method does not exist/is not available` behind a Cloudflare front, while continuing to serve `eth_getTransactionCount` and `eth_getTransactionReceipt` normally. Partial method availability rather than an outage — so an endpoint that answers one verification call is not thereby proven able to answer the next, and a two-endpoint check must confirm that both endpoints actually answered.

**The resolution is to lower the multiplier, never the estimate.** A refused submission is free and consumes no nonce; a mined out-of-gas consumes the nonce and, at nonce 93, was unrecoverable for the reason section 4 gives. So the limit is set as high as the provider ceiling allows rather than as low as seems safe: too high costs a round trip, too low costs the deployment.

| Nonce | Transaction | Multiplier | Limit sent | Gas used | Limit used |
| --- | --- | --- | --- | --- | --- |
| 93 | Vault, CALL | 123 | 16,607,439 | 12,707,749 | 76.5% |
| 94 | weighted pool factory, CREATE | 117 | 16,573,764 | 14,165,611 | 85.5% |
| 95 | AuMM, CREATE | 130 | 1,002,948 | 771,499 | 76.9% |
| 96 | fee-routing hook, CREATE | 130 | 3,684,240 | 2,834,031 | 76.9% |
| 97 | der Bodensee, CALL | 130 | 7,030,275 | 4,807,026 | 68.4% |
| 98 | Router, CREATE | 130 | 6,531,796 | 5,024,459 | 76.9% |

**A direct CREATE consumes its estimate exactly; a CALL does not.** At the default multiplier the two direct deployments each used precisely 1/1.30 of their limit — AuMM and the fee-routing hook both at 76.9% — and the weighted pool factory used precisely 1/1.17 of its trimmed limit. In all three the estimate equalled actual consumption to the gas. The two CALL transactions ran well under: the Vault by 5.9% and der Bodensee by 11.1%, slack the 63/64 rule builds in when a call deploys contracts internally.

The operational consequence is that on a direct CREATE the multiplier is the entire safety margin, with no estimator conservatism beneath it. A trim must therefore be justified against the provider ceiling, not against a belief that the estimate runs high.

**The Vault's own limit was 91.6% arithmetic.** Its 56,867 bytes of deployed code fix 11,373,400 gas of deposit cost at 200 gas per byte, plus roughly 970,192 for 60,637 bytes of init code carried as calldata and about 24,790 of intrinsic and EIP-3860 word cost — a floor near 12,368,382 against an estimate of roughly 13.5M. That ratio, not a tolerance for risk, is what made the trim to 123 defensible.

## 4. The nonce-93 recovery

`DeployAureumVault` was broadcast as one four-transaction sequence. The first three landed at nonces 90, 91 and 92 in block 11375957. The fourth, `factory.create()`, was refused at submission for exceeding the provider gas ceiling. Because a refusal never reaches the chain, nonce 93 remained unconsumed and every downstream projection stayed valid.

**Re-running the script would have been destructive.** `_deploy` derives `predictedFactory` from the LIVE deployer nonce, so a second `run()` deploys a second authorizer, fee controller and vault factory at nonces 93, 94 and 95 and strands the sealed immutables of the first set.

`script/CreateAureumVault.s.sol`, committed at `4d0157d`, is the create-only tail: it calls `create()` on the already-deployed factory, contains no new-expression, consumes exactly one nonce, and asserts twice before `startBroadcast` — that `getDeploymentAddress(salt)` equals the projected Vault, and that the Vault is not already deployed. Both asserts sit above the broadcast window, so a mismatch aborts before anything is signed.

**Why burning nonce 93 would have been unrecoverable.** The fee controller at nonce 91 seals `DER_BODENSEE_POOL` and `FEE_ROUTING_HOOK` as constructor immutables, and those addresses derive from nonces 94 and 96. A consumed nonce 93 shifts the weighted pool factory to 95 and the hook to 97, making both sealed values wrong. Correcting them requires a new fee controller, whose address is itself sealed into the factory at nonce 92, which requires a new factory. The cascade is a full base-layer restart in which only the 87 stubs survive — the accepted failure mode PB-D27 (iv) records.

## 5. On-chain verification evidence

Every step was confirmed at a second endpoint and at a later block than inclusion, because a load-balanced provider served stale nonce and code for at least one block after the refused broadcast, and a single post-broadcast read wrongly reported that nothing had been sent when three contracts had landed.

* **Option F2 confirmed live.** `Vault.getProtocolFeeController()` returns `0xb424796989Ba0Baaaa879Db0C0d1FEf638fEa3ef`, the nonce-91 controller — the external `IProtocolFeeController` injection the `AureumVaultFactory` fork exists to permit, working outside a fork test for the first time.
* **Mutual immutables closed.** `hook.FEE_CONTROLLER()` returns the controller and `controller.FEE_ROUTING_HOOK()` returns the hook: two immutables sealed six transactions apart, each naming the other.
* **Genesis sealed as intended.** `AuMM.GENESIS_BLOCK()` returns 11477620, set from live head 11376820 plus exactly 100,800 per PB-D19. `MAX_SUPPLY` reads 21e24, `totalSupply` reads 0 and `minter` reads the zero address — the fair-launch claim made checkable by anyone, with the minter slot awaiting the Stage K handoff.
* **PB-D26 validated live.** `getPoolTokens` on der Bodensee returns sUSDS, svZCHF, AuMM in ascending address order, which is the runtime sort proving itself on the exact defect that reverted ixAurebit in the PB3.4 rehearsal.
* **Deployed sizes match the artifacts.** The Vault reads 24,393 bytes on chain, the figure `test/unit/BytecodeSize.t.sol` gates at 183 bytes under the EIP-170 limit.
* **The Router exposes only `version()`.** Its `_vault`, `_weth` and `_permit2` immutables have no getters, so the vault binding cannot be read back from chain. `version()` returns `Aureum V3 Router v1 (Balancer V3 Router, pinned 68057fda)`, which proves the right code at the right address but says nothing about what it is bound to. Functional proof of the binding comes at the trusted-router seat with a credited add, the pattern `test/fork/RouterIntegration.t.sol` established.
* **WETH provenance established by measurement, not convention.** `WETH_ADDRESS` is pinned to `0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14`, whose runtime code is 3,124 bytes and whose leading 6,000 hex characters are identical to mainnet WETH9 at `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`. The two keccaks differ only because the trailing CBOR metadata differs. It is canonical WETH9's source recompiled rather than a reimplementation — the audit-inheritance standard CLAUDE.md section 1 applies to the Vault, applied to the one external dependency the Router seals as an immutable. A second candidate at `0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9` is a functionally correct but structurally different WETH9 of 1,786 bytes, and was rejected on that basis. No Aureum pool references WETH; the value governs only the Router's native-ETH wrapping path.
* **A verification form that can lie, and must not be reused.** `cast code <address> | wc -c` prints `0` when the RPC call FAILS, because the pipe discards the exit status and no output reaches `wc`. That `0` is indistinguishable at a glance from a real measurement, and reads as less than the value 3 a genuinely codeless address returns — so a failed call looks like a stronger emptiness result than emptiness itself. Capture the output and branch on the command's success instead: `C=$(cast code ...) && echo "len=${#C}" || echo "RPC ERROR"`. On mainnet a misread empty-code answer could trigger an unnecessary and destructive redeploy of a contract that already exists.

## 6. Related

- Projections confirmed by this record: `docs/STAGE_P_BIS_PHASE_A_RECORD.md` section 7.
- Operator procedure: `docs/STAGE_P_BIS_SEPOLIA_RUNBOOK.md` sections 6 and 8.
- Decisions: PB-D19 the genesis offset, PB-D26 the token sort, PB-D27 the go-live architecture, PB-D30 hook before der Bodensee, PB-D32 through PB-D34 the EIP-170 blocker, PB-D35 and PB-D36 environment isolation, PB-D38 the resume branch.

## 7. Miliarium Aureum pools — nonces 99 to 123

Twenty-five of the twenty-six Miliarium Aureum pools are live. Slot 14 `ixAurebit` landed alone at nonce 99 in block 11377740; the remaining twenty-four went out as one sequence at nonces 100 through 123, blocks 11383588 to 11383898. Each is a CREATE3 deployment performed by the weighted-pool factory at `0xC60E426294a06Fb95a6C1BB7A06219f794AAde8F` under the pool's slot-derived salt per E-D20, so the transaction recorded below is the factory `create` CALL sent by the deployer rather than a contract-creation transaction, and the pool address appears in forge's `additionalContracts` rather than in `contractAddress`.

**Every address was fixed before the sequence ran and confirmed after it.** The twenty-five addresses are the projections already committed to `.env.sepolia`, derived through `getDeploymentAddress` against that factory; no address in this table was learned by reading stdout. Each broadcast was followed by a code-presence check at that pool's own projection before the next broadcast began, so a divergence would have halted the sequence at the pool that caused it instead of surfacing later at reconciliation. All twenty-five matched. That per-pool check is the condition under which the pools may be driven in a loop at all: the twenty-six scripts emit an identical `Miliarium pool deployed at:` line carrying nothing that identifies which pool produced it, so stdout cannot tell them apart and the capture must key off something else.

**Batched rather than one row per broadcast, per PB-D39 (vii).** Section 8f requires a committed row per broadcast; these twenty-five land in a single section instead, on the ground that every Miliarium address is re-derivable from data already committed — the slot-derived salt in the pool's config library, through the factory — so a lost working tree costs only the block, gas and hash, each recoverable from any explorer given the address. The base layer has no such property, its addresses deriving from nonces that shift under any deviation, which is why section 1 is recorded transaction by transaction.

| Nonce | Contract | Address | Block | Gas used | Transaction |
| --- | --- | --- | --- | --- | --- |
| 99 | `ixAurebit`, slot 14 | `0x7e7df0d96d8eb360bC973D6c68cDf42a051A2583` | 11377740 | 4,913,019 | `0xbb5c5c9238b75e7b2b2ec2bfaf1e30a48daf681a16d9de0ef020a861ac5f9758` |
| 100 | `ixHelvetia`, slot 01 | `0xCFEDD49F254291aA67cFD725691Cd1C1Ecfe175f` | 11383588 | 4,807,977 | `0x53987f139e0a7fce13ffc345cb1de79b133b233edc6abd7adee89ab072730373` |
| 101 | `ixCasper`, slot 03 | `0xad0e87A433700F299Ee41fFd04D1e038521514e0` | 11383626 | 4,953,607 | `0xce91b9c421bbee739bfcf56ae9ddc06cdbe786d8269032c5298649ed2638ce86` |
| 102 | `ixEdelweiss`, slot 05 | `0x2163d0668383759fa7CF6Da176ECC412c708CbF1` | 11383638 | 4,898,303 | `0x541554b14919b87ed99cec00e7d89eaa4776ceffd7ee9164bde2a776e5d6e608` |
| 103 | `ixLibertas`, slot 06 | `0x78D54464715C7f77f084023918737DC6BfC0E204` | 11383649 | 5,024,015 | `0x170f2b5edb8c6df492ad67eec35b9713d0784d77ab356f1eda37a2ba263881fd` |
| 104 | `ixBrevis`, slot 08 | `0x6b3419CD3794A43c503be60ed58535C3cFeF3F51` | 11383660 | 4,913,007 | `0x78da60f36c2566f2cee3e648ef3db44ec7ecf4657f6f5d86962b4c1fc6e1cadd` |
| 105 | `ixAltrix`, slot 09 | `0x378f2563A1731F89F32C05398fB8fDF71bfb451B` | 11383671 | 4,913,007 | `0x962c19e377563b0f84ff542d1536dca5c49736e74bbb6ed601e7e1888de166f6` |
| 106 | `ixMediox`, slot 10 | `0xc8921e3f691Af718D77339475B4a0AbA25a43eA6` | 11383682 | 4,913,007 | `0x891ea5a9db532f0742cbda1701cec6c767ec35e50866d0656773dcce6ffaf9c4` |
| 107 | `ixLongus`, slot 11 | `0x2fe687F042432446988E67295E0fbbBA98d4C45E` | 11383692 | 4,877,937 | `0x44cd52c5ecb805563dff30eec95607b6b8389e7255983d41394aa8b1c98086ad` |
| 108 | `ixStrata`, slot 12 | `0x79e01791024173C534a1b286d9680864c5E75655` | 11383708 | 4,913,007 | `0xcd23c4fd456dba67c664dbc50f30bd8072454ee684328f369fefa0832af8ce6e` |
| 109 | `ixForum`, slot 13 | `0xfc438921AA48b3BEA513e2bc8e119E820E72C0E8` | 11383722 | 4,912,971 | `0x0690170a17ed28db6cbc4d2600fe389f0c46f3754f5c9e7d494392792aec106b` |
| 110 | `ixRegistrum`, slot 15 | `0x93871abd6bD3e0625AF82a536B8B2A1E7FbA4f26` | 11383734 | 4,913,137 | `0xf8ffa34e16d62cec6c9c61d52d5d9b8ee993098641d457fa1f29dd7d00e8f78c` |
| 111 | `ixDebitum`, slot 16 | `0x6358045D14df6792902266d4BB8E2e567663fD84` | 11383748 | 4,913,089 | `0xfe5533e27326f84ba902ae9ea642ba69e83fda12f71bbfdd3297cb95e1a73129` |
| 112 | `ixEquitix`, slot 17 | `0x891F3D4cEA1A8975071c61229076C8De2205a429` | 11383761 | 4,913,089 | `0x3065ffd81baab9a1bdfe7fde9b1c5c429c6d77053263d5cf9dcf0ec94af6ed6b` |
| 113 | `ixInnovix`, slot 18 | `0x4f2E5bF8d91cD64c7FcbC092887AF5D7c9A5eb8e` | 11383772 | 4,913,031 | `0x2590b5d792c0426ad5638cf4f5765f4af4102afe384414d43e13d3f56aa8cade` |
| 114 | `ixGigantus`, slot 19 | `0x97385c238b2E20ED8882553838FCf01F8ddd1fd8` | 11383782 | 4,913,043 | `0x045a6511d6776d7e73ca524d91b3e2f4d33a97ac23fe431c7d9eaceb17177c23` |
| 115 | `ixMagnix`, slot 20 | `0xD5dA48b648687F297863cB7eAad20bC25C9f9afc` | 11383794 | 4,913,007 | `0x5b021317487f18f9618a68a1569ac4bf68cfe6f9fd2a7f83e7ce7d0276b0ccfe` |
| 116 | `ixNubix`, slot 21 | `0x5cFAc5FD417081F72596d3A99c2D1a17412667b5` | 11383808 | 4,913,041 | `0xee4d0e2953815c5383249567f6e46abccdadc77ce56b9a841d9d1ceb94133455` |
| 117 | `ixMoneta`, slot 22 | `0xF5e338FaEE83096fcD375DBfaD33a42C654830d1` | 11383821 | 4,912,995 | `0x7ef7c95a8963b10b09f6a595656590cf498c15b5a16f723fc53bee6a15d69b35` |
| 118 | `ixColossix`, slot 23 | `0x8BBe0A1Fe73CdE710a2Db2E069b040EE888bcE62` | 11383834 | 4,913,113 | `0x089f48c9204f5b12cb2d0b39477268633daddaa782d7d86b58ec6dff62aabfb4` |
| 119 | `ixVitalix`, slot 24 | `0x74A63e807EF64B0C1a5A3BA0Da2508E499f77920` | 11383847 | 4,913,077 | `0x40f9477db5a47f3464f91afcf8998f8280060a7104513bbf197d271f724bbf33` |
| 120 | `ixMedicix`, slot 25 | `0xDE37541c154af244A3F90b669876d3cA194E830a` | 11383858 | 4,913,089 | `0xe80887e4e5f576cab58353d02263814449d61c6b55af62a751788abfe231739c` |
| 121 | `ixMercatura`, slot 26 | `0x1657b73834113aA0f09971ada1B7f3A5f5521DaD` | 11383871 | 4,913,137 | `0x104664e3fa548385789e8c22ce56e053db5d90c2fdfb860fdd93e763d58d4cb0` |
| 122 | `ixAurix`, slot 27 | `0x91748a5Fa6F79d0CCCbB62BF4796e2956AB1977E` | 11383886 | 4,912,971 | `0xf15d75ee68f6fdd3b6f36c6a4f431d4885f9fb13ff09402a37634aba80c8fbfb` |
| 123 | `ixMetallum`, slot 28 | `0xcEbf3dCa8C20FAe8F57836FCB3EC073c17478faD` | 11383898 | 4,913,043 | `0xe10d57cec8363dde39f0513bef1dff52341f0dc7f63d52dd627debcab69b3c5b` |

**Slot 02 `ixAetheron` is absent and is not a missed deployment.** Its slot-derived salt collides with `BODENSEE_SALT` in the factory's sender-scoped CREATE3 namespace, so it broadcasts from a second EOA per PB-D39; its address is not reproducible from the deployer named at the head of this record, and its row therefore lands with its own receipt rather than inside this batch. Slots 04 and 07 are absent by design, descoped to the Stage-O composition-challenge path at PB-D8, so the constellation launches twenty-six of twenty-eight.

**Gas.** 122,822,719 gas across the twenty-five, ranging from 4,807,977 to 5,024,015 per pool, at an effective 1.00 to 1.12 gwei. The twenty-four-pool sequence cost approximately 0.126 SepETH against a balance of 5.88. No manual gas limit was set for any of them and no submission was refused: forge's own 130 percent multiplier held throughout, unlike the base-layer ceiling section 3 describes.

**Verification is outstanding for all twenty-five.** None was submitted with `--verify`, because `ETHERSCAN_API_KEY` was still unprovisioned when they were broadcast. Each is a phase-6 obligation and is submitted against the pool address using the factory's pool creation code, not against a deployer transaction.
