# Stage P-bis — phase 4 transaction ledger

Chain 11155111. Deployer `0xA851478dbee97375E784e9b98c0D7D599662bF85`.

The complete per-transaction ledger for phase 4, the `DeployStageP` Stage F through K orchestration, across both deployments this chain carries. Each section is generated from `broadcast/DeployStageP.s.sol/11155111/run-latest.json` at the time of its own broadcast rather than transcribed. `broadcast/` is gitignored and holds only the most recent run per script, so this file is the committed record of what that artifact held for generation 1 and holds for generation 2. Deployed addresses, aggregate figures and narrative are in `docs/STAGE_P_BIS_SEPOLIA_DEPLOYMENT_RECORD.md`, section 11 for generation 1 and section 17 for generation 2.

## GENERATION 1 — ABANDONED

Abandoned at PB3.13 per PB-D70 along with every other generation-1 contract, and retained as the record of what was sent. These rows can no longer be regenerated: forge keeps one artifact per script and generation 2 has overwritten it, which is precisely why this file exists.

Transactions 114, receipts 114, every one successful. Nonces 125 to 238, contiguous. Blocks 11403323 to 11403470. Total gas 27,666,605.

| Nonce | Type | Contract | Function | To / deployed address | Block | Gas used | Transaction |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 125 | CREATE | `MiliariumRegistry` | — | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403323 | 841,260 | `0x171b7efbb9f8812246ec4129ca9f51ef19355cf7103ac122e6da32ad9cbc9137` |
| 126 | CREATE | `TVLOracle` | — | `0xbf78a49b1ab86247198f6660bf5a0491007e6a64` | 11403324 | 1,253,194 | `0x54fd52209c0b6bb61f0a25e1cf3109670192dd2483cc51c936e64a11f67dbdcd` |
| 127 | CREATE | `EfficiencyOracle` | — | `0x1e70661c3f1844c01be204e9df032b12d04110b3` | 11403326 | 750,861 | `0x502a06f181b8e7c3a563260e1f3aac6a79dfc71cc60cfdd12227b648ce3dae94` |
| 128 | CREATE | `EMASampler` | — | `0x51f8d9e771e5ec3a33555c15032110d034891b3a` | 11403327 | 302,413 | `0xa103b60ad0ec6191da7acb34df7372aa5965a8cc148b9ae73727bdce0c5aeb75` |
| 129 | CREATE | `CCBMultiplier` | — | `0xdbb357259be8dfb17fcbf0503d9bab01e976f735` | 11403328 | 939,805 | `0xa267e61639f8aef2722246a823caa9e86721e080ae4b39919b730ac7746b557e` |
| 130 | CALL | `EfficiencyOracle` | `setGovernanceContract(address)` | `0x1e70661c3f1844c01be204e9df032b12d04110b3` | 11403329 | 25,450 | `0x0bb5277bae86c4d9bf13e9e575420eb7efd913fafba1928284270af784d95723` |
| 131 | CREATE | `SwapAndDepositToBodensee` | — | `0x5f716bd785d2990c6d42750091b0f2914c557f25` | 11403330 | 1,542,160 | `0x2c0ea7d15d9bfbde533dbe245397ea933c52026d5aea4564c5cd365982d30903` |
| 132 | CREATE | `VaultClassRegistry` | — | `0xf6d7a7e633a1bc8b8896b7849bbfa53001854af7` | 11403332 | 1,432,037 | `0x92f63d1f88fc676f2f76b504987ebadff5e0f31ae08f3557ef722df7e2ef4a08` |
| 133 | CREATE | `GaugeEligibility` | — | `0x9b9304deb0230cab7780a66b184897d30f26cd78` | 11403333 | 1,522,144 | `0x83b5fa0fcd9da250968a0200576fa7964fc98f3d09985b779f4df63409239d7c` |
| 134 | CREATE | `GaugeRegistry` | — | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403335 | 1,268,012 | `0x21dc8d37a752239481641188d74c378ea399c6a979173e41521f2d5a62401b4a` |
| 135 | CALL | `SwapAndDepositToBodensee` | `setVaultClassRegistry(address)` | `0x5f716bd785d2990c6d42750091b0f2914c557f25` | 11403336 | 49,233 | `0xec6751a26d335eecbe329af84e330fc772f227e1abc19df1003a86a462e8bff1` |
| 136 | CALL | `SwapAndDepositToBodensee` | `setGaugeRegistry(address)` | `0x5f716bd785d2990c6d42750091b0f2914c557f25` | 11403338 | 47,378 | `0xfe216a5afebaa125e7091fd08e71905c3b56faa7e791d641ec1b595ab9b6901e` |
| 137 | CALL | `GaugeEligibility` | `setGaugeRegistry(address)` | `0x9b9304deb0230cab7780a66b184897d30f26cd78` | 11403339 | 44,134 | `0xe39ae7c5902d5c6e6a229f57e3830af108f7ca16e39c4a0a0fc6110530f8a4d3` |
| 138 | CALL | `SwapAndDepositToBodensee` | `addAuthorizedDonator(address)` | `0x5f716bd785d2990c6d42750091b0f2914c557f25` | 11403340 | 47,309 | `0x878e12e887ad2e4f6c848051b849dea84414fed81d1066a038f9b07012490584` |
| 139 | CALL | `SwapAndDepositToBodensee` | `setDonateAuthorizer(address)` | `0x5f716bd785d2990c6d42750091b0f2914c557f25` | 11403341 | 25,619 | `0xce428be90ffb8128f8b9eec080b3cf948ae89de805279c3d6afaef537a156913` |
| 140 | CALL | `CCBMultiplier` | `setGaugeRegistry(address)` | `0xdbb357259be8dfb17fcbf0503d9bab01e976f735` | 11403342 | 27,034 | `0xe1b61c2f2240875894e5336fb5fefad3ae5c9479fe274569c270def42831a1c5` |
| 141 | CREATE | `BodenseeBootstrapChannel` | — | `0x2325a6238ff80e5a4e8d8071ff1e949dcbcfb7cb` | 11403343 | 1,354,141 | `0x27f0971bf44dafbef8019728c26e26f542b95bb99b4bd8def7c07fe9ec5ee0e0` |
| 142 | CREATE | `EmissionDistributor` | — | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403345 | 2,366,627 | `0xc6e394e3026e79d5f12de0192dfd9cd4df216145377c6c798a42cfb61fd1a4e5` |
| 143 | CALL | `BodenseeBootstrapChannel` | `setGovernanceContract(address)` | `0x2325a6238ff80e5a4e8d8071ff1e949dcbcfb7cb` | 11403346 | 25,405 | `0xa3cde5de3e9f9363eb084538b97dfe982d91779934857e6289ce34a3cc4d765b` |
| 144 | CALL | `EmissionDistributor` | `setGovernanceContract(address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403347 | 25,493 | `0x1561869a1291dd7f7127d8146a84bbe030cd3d44a5df434f311a21925130ec8e` |
| 145 | CALL | `EfficiencyOracle` | `setEmissionsRecorder(address)` | `0x1e70661c3f1844c01be204e9df032b12d04110b3` | 11403348 | 47,442 | `0x0fd4e9bef4983bfa05ebd7f854bd7dee07cfa7fa1903c45778d2883f4b217b5d` |
| 146 | CALL | — | `setEmissionRecorder(address)` | `0x954c972170ec131364570658d42f14e833a08588` | 11403350 | 45,514 | `0x231f35c4ea7cd3c7a523fd51b608c4a8011f72e0d0b89d0be4810e0a7baee4f8` |
| 147 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403351 | 48,576 | `0xb181680fa7463d14b30850d5b92647513bf18de8599a926df45451cf78c44935` |
| 148 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403352 | 48,576 | `0x37d80a4b401d3736d337c69995ae492a6f35b4abc9dc0a52a158d7f4b2f2ce6b` |
| 149 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403353 | 48,576 | `0xb02c31353ceaf05129cfc33168e94dd9159ee256104fe0221b75206958ceda31` |
| 150 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403355 | 142,259 | `0x06c8110730a9a2ad70dbd04d3136d4af92e799c8b1e5fe9d212300a60e30580b` |
| 151 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403357 | 114,882 | `0xaa236129afcdc2f48ce0b3e89215b121fab9a68ab5b8fe28733d275d2c370719` |
| 152 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403358 | 48,576 | `0xdbdc5a4bfa7ac47b3e785949beabf3bfae09e2672517a7b3ce6715252aa703eb` |
| 153 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403359 | 142,259 | `0x162a35f7bfba8c48df897091143a1075aa4ebff66c3f6fb36daa887d7b54b129` |
| 154 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403360 | 97,782 | `0x44b1d998ff140037d6182780c00f70e87fa7d3eda8ccfa84d4997e7d26af1284` |
| 155 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403362 | 48,576 | `0xe315a20d30c0527469268631c31de65556630f962654a9e304f0098f5d9f45d9` |
| 156 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403363 | 142,259 | `0x605923ec3a822602140ad977fd70b37d5a7721933063cb75dfb6494fa8698b1d` |
| 157 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403365 | 97,782 | `0x216ab20433cdd9c8781b80b876a2430933cb33e4739ae26c352345033e6162a8` |
| 158 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403366 | 48,576 | `0x54c3323443dd2e255e4032fc4a44be514c6a9024262f491650c18d2904611a78` |
| 159 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403368 | 142,259 | `0xe8fdd576f8d2e6702ed858a49d1e31b1032ae698dd4bf376ab7e07b79343ba0f` |
| 160 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403369 | 97,782 | `0x922345c566107be1faf1e325691fb649da16b81741bf569f63d0b737e7d97d47` |
| 161 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403370 | 48,576 | `0x163e6a8dd69328aba978a83643fd26bbed4bc291fd831403383733069c99045c` |
| 162 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403371 | 142,259 | `0x375a77d670df41c4522ee83feba2121681a6b83e82d8e7566db17d86f198fa4d` |
| 163 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403372 | 97,782 | `0x81dce604f00e7da6353373426274904dbf1eba5fffd5e1a2092b781a6430c077` |
| 164 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403373 | 48,576 | `0x5c5d1b34467f7399096a87e5765abbdac2986bb665662b17431ccd32e1e1580b` |
| 165 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403374 | 142,259 | `0x33515e045821e3ddbe6257cc0fc6f5d6ad6ae6d797f8460e68b28f9ef8a8559f` |
| 166 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403375 | 97,782 | `0x5609fda9648ed14643835c2745c83413b1c811ee567cbcadd1a05f811d959908` |
| 167 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403376 | 48,576 | `0x93e57c7355029bd138cdad2a8d5ffa684e55827b3a5768b666dc651fbe2692a0` |
| 168 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403377 | 142,259 | `0x29900fbea099e8204d7591e893acec1ba6bfe9f2dd83aceb6257db7eb50579db` |
| 169 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403378 | 97,782 | `0xe36345088ef355c681acce9ff9965d162655f6cdbd585245620c0b63a41d672e` |
| 170 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403379 | 48,576 | `0x2c83c4f9a1ca3e9692e24c600420f582afaf3aab2656c1523796ea09e89e4fc2` |
| 171 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403380 | 142,259 | `0xc1cad0a1d1b06fc939cb59b6ac269e99a39af9958806006a337a305b38e64c79` |
| 172 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403382 | 97,782 | `0x7a6c441d02fa470144dfdd394a19fabd176ac060f9c0ed9a9a36953c699b4c15` |
| 173 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403383 | 48,576 | `0x60a6b0ee5f3c2cc1926395f6e2cdc5d340be3e3b9cad6e0f1a72b77fc7877221` |
| 174 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403385 | 142,259 | `0x8a4f2e41940fa929059b0f1b9a65fae842ab5c8a398ab5df66f51e37ebb6b04f` |
| 175 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403386 | 97,782 | `0xd9edcfaf2227746852fd8971603d64a761b1833724d2c88446e4b46533956648` |
| 176 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403388 | 48,576 | `0xd97261991ff371d2d1676ff81359ffa839f32628ef7735fe231921b7e7533c80` |
| 177 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403389 | 142,259 | `0x115ebe240163f97e8fb59a6c3b4a2c2a8f13496ed5c3215f132147274722136b` |
| 178 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403391 | 97,782 | `0xc3682fa76a69823eb8cec1ed0d51b59c9b3c284499517de5746b1ba65c137b04` |
| 179 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403392 | 48,576 | `0xc868c20a02286e79be2fc3d1c2b4a2f8f04da10d137c46dfb5d3c347c2d43e8d` |
| 180 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403394 | 142,259 | `0xc29319b5bec3ec7a20e1fe1dd97e0ee523e47bf45f2342bdee8ba2deb29eed79` |
| 181 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403395 | 97,782 | `0x772cc4a5127d5d8849b3cfcafdd046c79b653e48ac08c796b3bed418471e9a73` |
| 182 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403397 | 48,576 | `0x52e9a6af1dd09b86075e018c6920f1bd826fd8b764d29d2a7ea7eecd609d6ce1` |
| 183 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403398 | 142,259 | `0x73e2d830b11540ffe3bf3216b69cfe3b08d4f86838f1ec88870fd4f7496c910c` |
| 184 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403400 | 97,782 | `0x40651a60ca62cde538074fef6de219edbdffac20a07d902f7f1d26f807735eb4` |
| 185 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403401 | 48,576 | `0xfb81314072b52511f9fe0e9f6c2f71e1a3d0abe2507013256210aac6b82ff0f3` |
| 186 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403402 | 142,259 | `0xfa4e536ee74a84181995b431bdce027738960f2babce9bf87d45ea388173a738` |
| 187 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403404 | 97,782 | `0x0d758c605c274daea925e6d3594d3ca79ecb3d4093c6f992e5e8c43c32db84bc` |
| 188 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403405 | 48,576 | `0x6837a2ac59eeeaf416ccc135a8efad92d63c43c398a506236a6f32b1a38469c0` |
| 189 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403407 | 142,259 | `0x070ebad7dd1c9a3e1025917a0ef96259e3fe4dc2e273367b16b36dddaab32869` |
| 190 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403408 | 97,782 | `0xb674f7a0b544fb88c3f118273e19953cb2cb24a4028866771178afd6c33e4852` |
| 191 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403410 | 48,576 | `0xe96a109b66786c54ecd2878721ea946fe09866b19b0f253c4f37deccdda78e45` |
| 192 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403411 | 142,259 | `0x68e0a8e5268fa43ee2d7468b0045c17d70234c248dc18c7afaeffd5aa456147a` |
| 193 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403412 | 97,782 | `0x198f5ab50ecd36f2b79d186af05d7c08861acc30b26e990769eb7d3908b09ce1` |
| 194 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403413 | 48,576 | `0x8baa65470db540d07da033ff5ed61761b514a63f1110558698d87ea3c81f7fee` |
| 195 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403415 | 142,259 | `0xb45257bef6b6e4097760abd0cb50c9a3feb97ea9c0454e4cca79acbf5e86b5d0` |
| 196 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403416 | 97,782 | `0x754d67c39f978423f5ae27349fe7580428149b66a1ddd75707efa45fc125ad86` |
| 197 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403417 | 48,576 | `0x4992073bdef93f5649f6679bf0748bc023531c7b598dfb752502a9019ab86e81` |
| 198 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403418 | 142,259 | `0xe1eadcdc3aa619b262d95bdc6aa1f9d4e68912a9f61b6d36b0dd6c3ac6bd801f` |
| 199 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403419 | 97,782 | `0xf2c90ea13a70192f91fbb480c2c5a2c9190fd48d0a614d76a6d8c36d4f75c351` |
| 200 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403421 | 48,576 | `0x8d245c64620b8420af82a0e26da448988505b18ec70fb0dad397c00d194ebaa8` |
| 201 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403422 | 142,259 | `0x2484562ae9f0af0a59b8ccc7ce44debe3561232a637ed88f30c515bb6d57138d` |
| 202 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403424 | 97,782 | `0x18cd5146ad9c151a02c2d86970bbb1f0fa8ca690d1acc425efb663565e6cc062` |
| 203 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403425 | 48,576 | `0x7f369730cb55fc2ca4804af43f9d880085a436f27951762af9d0c49a57a79904` |
| 204 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403426 | 142,259 | `0x6998a872c5b7e6be39240ab1089ae44a46279756ab4c7a54c97f4aa6e92bce65` |
| 205 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403427 | 97,782 | `0xc2ea49c3d1d3cd97f75b907203097a7248fecbb99703580ec9fefc1f9e8a54c1` |
| 206 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403429 | 48,576 | `0x0e42ffa0ec61a45d5f92f2b8a81e22caac0e3f9408274cf8f78a00b664a17c2c` |
| 207 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403430 | 142,259 | `0x74a2449233196feefdfc494615f0cfbdb32196eda6dc0d1a558c966a60b57d81` |
| 208 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403432 | 97,782 | `0xefb6ba4f335167d301d337476cd4080e583fa40783be2d4196dfe08750e3bbe8` |
| 209 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403433 | 48,576 | `0xa3a5a588ca12b91f12d7b438b13f2ebc94796b857414ea77f163782e78f81b71` |
| 210 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403435 | 142,259 | `0x5b78a8c61ada077d6a066fe413155c60c31fdb8dbe3f8b6b6e1e9767d73a1d8b` |
| 211 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403436 | 97,782 | `0x1ac5bc97aa878f7f6c42f33594569b60e073038724307ae916a4bc9ca48bc000` |
| 212 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403437 | 48,576 | `0x43a1025c453a907c60504e07d8ac81dddef72ed5be61857904a34be38e1729ed` |
| 213 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403439 | 142,259 | `0x7d01899be518028ebe2937bb16e8e0f0f95b9730ffccae775e843a142cf29057` |
| 214 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403440 | 97,782 | `0xf72a22a466d9877b392343f27ecd418fdb5932a90bdfc8d4d6fa2ccbaa42bacc` |
| 215 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403441 | 48,576 | `0xcffec74220fd46636a619fa2148605a610d0e3ec442a34d5214a86d2c568dde9` |
| 216 | CALL | `MiliariumRegistry` | `replaceSlot(uint256,address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403442 | 142,259 | `0x328d6b67cdbdecbab0f2e566275a7f47f2520b78ce000840c681f09633919346` |
| 217 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403444 | 97,782 | `0x91ba01f79f3e6863545c395fe8e38a163026f9edb750cd93ef25aa517ff04105` |
| 218 | CALL | `EmissionDistributor` | `setAuMTContractForPool(address,address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403445 | 48,576 | `0xe6e5d359b165657dc0966105bcdcc022bdc11b28a160a136b13ad654cd1dc8e1` |
| 219 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403446 | 97,782 | `0x04de0deffce20228c715a81220c1ce2adf0a18970d3d3db98d109768fe1c43be` |
| 220 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403448 | 97,782 | `0x924946ba2df1964cf1363f2650dca9ba8c69ebe387728fef98a9c52a7148caf3` |
| 221 | CALL | `GaugeRegistry` | `seedFoundingPool(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403449 | 97,782 | `0x6402eba2f65527442f6508b2987de90e6b0c0d0eb85e7129cb27d2102cd162fc` |
| 222 | CREATE | `IncendiaryRegistry` | — | `0xe1304f04c7f9138f8932b71a18be7a7447cc93c1` | 11403451 | 1,585,860 | `0xecdde8762da72efb426c0f5054fab07ff4c6d650278c783f7348bde3043e077f` |
| 223 | CALL | `SwapAndDepositToBodensee` | `addAuthorizedDonator(address)` | `0x5f716bd785d2990c6d42750091b0f2914c557f25` | 11403452 | 47,309 | `0x1b0b447a4154107e480425fd675b0db451eedf5d9bb497dbf054db69967dbcf8` |
| 224 | CALL | `EmissionDistributor` | `setIncendiaryRegistry(address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403454 | 47,719 | `0x5dabf0ceaeb2757605f8e9c3301d831dd3db5855220b1cf990abbe339a7e4102` |
| 225 | CREATE | `VotingWeight` | — | `0x2d2678488e3483f905930571c1b01d5e3a138674` | 11403455 | 1,838,117 | `0xa57bc3f9d8b257a4c294ea9e26f0b05b30de9426b65d776fb8887e12f0fe76f3` |
| 226 | CREATE | `AureumGovernance` | — | `0x2c5fc5953c42b7e0bf1a5062632fcccbc97f0a69` | 11403457 | 2,143,679 | `0xb29aadb1609590f709c79d76c7688bd324a8993a8d369cfeca89745a81937eb4` |
| 227 | CREATE | `AureumGovernanceAuthorizer` | — | `0xd25f8510fbbc7fe0daebca3bb995b907211068b7` | 11403458 | 255,415 | `0x0c45f4d456ebbf988c95f2ed4168ad9ff18d393884bbb35285dd4743b1940f0d` |
| 228 | CREATE | `AuMMMinterRouter` | — | `0x71166f782df23a8f0af8769241c757c08d4998a8` | 11403459 | 255,892 | `0x9b33745b28b31eab21590db09c3d3c74e94ee7dbe9b13cc15060956b5bdc055e` |
| 229 | CALL | `VaultClassRegistry` | `setVotingWeight(address)` | `0xf6d7a7e633a1bc8b8896b7849bbfa53001854af7` | 11403460 | 44,219 | `0x15f57bb977f8033f64ad630ee40fba71c3a8af93dea473cd3d1487adb9241bec` |
| 230 | CALL | `SwapAndDepositToBodensee` | `addAuthorizedDonator(address)` | `0x5f716bd785d2990c6d42750091b0f2914c557f25` | 11403462 | 47,309 | `0xf8f0536dc22632e19a4ccb9ca0de35c1829b23e28ff524ec75b4a6ca74bee2f9` |
| 231 | CALL | `BodenseeBootstrapChannel` | `setMintRouter(address)` | `0x2325a6238ff80e5a4e8d8071ff1e949dcbcfb7cb` | 11403463 | 47,088 | `0x86f66a59c42dc5dc7ab97c30f5217182342f00bca8d5f53bc429510691a2c912` |
| 232 | CALL | `EmissionDistributor` | `setMintRouter(address)` | `0x2933bc72f2ea002ece4a2270c7985b72cfd0a695` | 11403464 | 47,294 | `0x041cff37d122e233186595e1156072e203df5ea20c1bfa6119a19fa23e7694c4` |
| 233 | CALL | — | `setMinter(address)` | `0xb8947f2fe2177d36f2f990300106f27c738dfc8d` | 11403465 | 45,499 | `0xed0d3a71da00bb98f8c30436d611daad56fe1e1bfc66896165991a508fa444a6` |
| 234 | CALL | `GaugeRegistry` | `setGovernanceContract(address)` | `0xd6eee04ca4e27a3e2e395538f907b1dff523d987` | 11403466 | 28,254 | `0x5e8bf9f9ea16d5cc5606c20688ae39193366654b9804c91f777448cdd81bff6c` |
| 235 | CALL | `MiliariumRegistry` | `setGovernanceContract(address)` | `0xfbe5e161955fb75fa99010dcfc71bbbe6405a511` | 11403467 | 28,227 | `0x308168d4f9a16b58319c9d77ffc6edbec6469b494bf2c63ea705bfd7faee0d0f` |
| 236 | CALL | `TVLOracle` | `setMiliariumRegistry(address)` | `0xbf78a49b1ab86247198f6660bf5a0491007e6a64` | 11403468 | 45,377 | `0xaa63b1394eabd50a637397cd5192d02877f85d3ac537670344480a79c3fc7c74` |
| 237 | CALL | — | `setAuthorizer(address)` | `0x9c7e8f56d12823609c28788d4b80a315ccc5fc80` | 11403469 | 38,274 | `0x6271e3ee61ed091b2aad8c3be1682ab5c802d8faf3260a7cdbdcb5e285f180e0` |
| 238 | CALL | `VaultClassRegistry` | `setGovernanceContract(address)` | `0xf6d7a7e633a1bc8b8896b7849bbfa53001854af7` | 11403470 | 44,043 | `0xcae94c9dafefac6f8515276093d81d8a3fd9574eac876071107cce1259d0a962` |
