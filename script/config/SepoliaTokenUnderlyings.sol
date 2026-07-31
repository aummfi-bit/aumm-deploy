// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

/**
 * @title SepoliaTokenUnderlyings
 * @notice Live-Sepolia `TVLOracle.tokenToUnderlying` seed map — 60 pairs derived at PB3.8e2.
 *
 * @dev SEPOLIA ONLY per PB-D44 (iv) / RB-010. Every address is a Sepolia stub or Sepolia-deployed
 *      contract and holds no code on mainnet; rung f asserts chain identity before it writes any
 *      entry. Derived against live Sepolia by `test-stubs/DeriveTokenUnderlyings.s.sol` at commit
 *      `d763273` and transcribed verbatim from `test-stubs/pb38e2-derived.log`.
 *
 *      No named constants, unlike the sibling `script/config/GaugeGenesisManifest.sol`: these are
 *      freshly CREATEd stubs whose only identity is the address itself, so any name would be
 *      invented at transcription time (PB-D44 (ii)). The array locals are `t` and `u` so the
 *      assignment block remains a whitespace-only diff against the derivation log (PB-D44 (iii)).
 *
 *      Mapping convention per PB-D42: svZCHF self-maps so it equals the `SVZCHF` immutable (iii);
 *      other WITH_RATE wrappers map share to underlying through a live `asset()` read (iv);
 *      STANDARD and AuMM self-map. 47 entries self-map, 13 resolve away, those 13 pairwise
 *      distinct. Index 0's underlying is the single `addHopUnderlying` seed of PB-D43 (vi).
 */
library SepoliaTokenUnderlyings {
    /// @notice Number of token-to-underlying pairs in the derived map.
    uint256 internal constant PAIR_COUNT = 60;

    /**
     * @notice The derived pairs, index-aligned, both of length `PAIR_COUNT`.
     * @return t Pool token addresses — the `token` argument to `TVLOracle.setTokenUnderlying`.
     * @return u Resolved underlyings — the `underlying` argument, index-aligned with `t`.
     */
    function pairs() internal pure returns (address[] memory t, address[] memory u) {
        t = new address[](PAIR_COUNT);
        u = new address[](PAIR_COUNT);

        // Transcribed verbatim from test-stubs/pb38e2-derived.log lines 7-126.
        t[0] = 0x1AAaA43Ae8fa57d9686b8FbB7944d2d22f4Ff166;
        u[0] = 0xCc72810e4A91D2BDba70B380C9c41327D0E63169;
        t[1] = 0x290a0E1dDc7de7e8588Aa1c15974FBd771c82700;
        u[1] = 0x290a0E1dDc7de7e8588Aa1c15974FBd771c82700;
        t[2] = 0x323A0Dfbf09602daC3cd02118DdeB4E0d5bD94cB;
        u[2] = 0x6Cc4b8dd6FB04EA16A0f760D426B8912a5357584;
        t[3] = 0x3294eB8582279311D4900D18fa88726Abc9aa5E2;
        u[3] = 0x0d140Fe8fEd35c83c937A91aBF280476285700DF;
        t[4] = 0xc2050f1C047702279c48bF3460cAd55B6083D0aE;
        u[4] = 0x9af2B048050f4d299BB1C0e1366185E93bE15681;
        t[5] = 0xEB74e39714a0357cb81a63E94Fb8B9E2Bc495508;
        u[5] = 0xc90402484292C55C4389eaaE27BCc6411c24C8d0;
        t[6] = 0xff277C20152269C00b58261DC8b849DD813F5D2A;
        u[6] = 0xff277C20152269C00b58261DC8b849DD813F5D2A;
        t[7] = 0xb95e2B38C627d7fA9261f768BFFCd569F1351ff5;
        u[7] = 0xdB5BB6D92624b58Bafd98AF32fE29caf240942C1;
        t[8] = 0xf41cC074Dfd5B933788781600eb9BDEAb80fC85e;
        u[8] = 0xaCb9EeE028C665547673FD6b705d2fd68602D0E2;
        t[9] = 0xF60Ad24d6C182CF97E0f08C4DbDaac4907C67eC8;
        u[9] = 0xfb56419728242bAa8989c09B3B630C894B2DbA0d;
        t[10] = 0x0eABBa593D0459a551507443BD6e367940aDECAB;
        u[10] = 0xf2dd907869FF4FB926fCf19b653a65C7500358C8;
        t[11] = 0xB4018b72FaC7b3C9d8cDc52500D22c9d07A5A1ab;
        u[11] = 0x3249FfB98dE511837C61cf4952f8b85AF7F6fa3f;
        t[12] = 0x1302A75E54B693BD8AC9bc680f5D18406Dc31a4d;
        u[12] = 0x1ba19f0f46359d8C90EF5D5BEA98970a1e7942BF;
        t[13] = 0x48678ecB4130b103A0e9519F07C7057D5c49cc01;
        u[13] = 0x48678ecB4130b103A0e9519F07C7057D5c49cc01;
        t[14] = 0xaB6f66D0BFE01C0C40098B8405466D5b42893e33;
        u[14] = 0xaB6f66D0BFE01C0C40098B8405466D5b42893e33;
        t[15] = 0xE4Cd794A7Fa89d55F68727B3Ed2e9D338BC375D6;
        u[15] = 0xE3d7124bd56b2333ee16C3fb1d576FFd26977681;
        t[16] = 0xFa7C24f4aCF2F4900CDF1Dddd653B0fB43e1283F;
        u[16] = 0x5C4E8Ca3C414F16278683aF27889447D4aecf4D4;
        t[17] = 0xfaE8A69519da66aD8966AE20dA215f38bC8509Fe;
        u[17] = 0xfaE8A69519da66aD8966AE20dA215f38bC8509Fe;
        t[18] = 0x0a624148547cB62b53cf91f538e61b173D094447;
        u[18] = 0x0a624148547cB62b53cf91f538e61b173D094447;
        t[19] = 0x3cb36aF55A116aEE86979e025bFE7db185ffE339;
        u[19] = 0x3cb36aF55A116aEE86979e025bFE7db185ffE339;
        t[20] = 0x0ccA6Cd7d2BC2E6E08fBa0572A8B2D692BD21687;
        u[20] = 0x0ccA6Cd7d2BC2E6E08fBa0572A8B2D692BD21687;
        t[21] = 0xe1bCB81ef414617FA5e34ed3bbf8860392856C20;
        u[21] = 0xe1bCB81ef414617FA5e34ed3bbf8860392856C20;
        t[22] = 0x108fEb99Ca109E3065ecF03470a20Da1BCFF41C3;
        u[22] = 0x108fEb99Ca109E3065ecF03470a20Da1BCFF41C3;
        t[23] = 0x1383c458D5e3E1B65598246aecBBcb3328215242;
        u[23] = 0x1383c458D5e3E1B65598246aecBBcb3328215242;
        t[24] = 0x0f06E676121b14bbcb0E5F16Ba2a4208d47B97f3;
        u[24] = 0x0f06E676121b14bbcb0E5F16Ba2a4208d47B97f3;
        t[25] = 0x26a8AAb1f51BB12CA80bb86B333EcA51eAcf972e;
        u[25] = 0x26a8AAb1f51BB12CA80bb86B333EcA51eAcf972e;
        t[26] = 0xD627Bb8e31E89e0d83569927452Ce886e12CBeFF;
        u[26] = 0xD627Bb8e31E89e0d83569927452Ce886e12CBeFF;
        t[27] = 0x1A5d9380f8a97e8D9E743b160C3886a197b61279;
        u[27] = 0x1A5d9380f8a97e8D9E743b160C3886a197b61279;
        t[28] = 0x95b0869275a2e0bEf6cd27Fe6578523c966F83aC;
        u[28] = 0x95b0869275a2e0bEf6cd27Fe6578523c966F83aC;
        t[29] = 0x660318e2230fcD9a7fF22E92558E98674f8Fbbad;
        u[29] = 0x660318e2230fcD9a7fF22E92558E98674f8Fbbad;
        t[30] = 0xA5B3A60A515c4a3429c76098addEb02e570Bf4C0;
        u[30] = 0xA5B3A60A515c4a3429c76098addEb02e570Bf4C0;
        t[31] = 0x237B5D430D15A32AE852d239Bdb043deFB480284;
        u[31] = 0x237B5D430D15A32AE852d239Bdb043deFB480284;
        t[32] = 0x9d132436BF2dD5E1648103E36C96e8102994D191;
        u[32] = 0x9d132436BF2dD5E1648103E36C96e8102994D191;
        t[33] = 0x15ed6445CD0182eaFfc412e7655c5EC949d60ED3;
        u[33] = 0x15ed6445CD0182eaFfc412e7655c5EC949d60ED3;
        t[34] = 0x85617e59e8C214331fB4547705307a25fD93ce06;
        u[34] = 0x85617e59e8C214331fB4547705307a25fD93ce06;
        t[35] = 0x228cEde6A4cA0B70e433559D3468dE5c8EBc5fdD;
        u[35] = 0x228cEde6A4cA0B70e433559D3468dE5c8EBc5fdD;
        t[36] = 0xC3e17579Ff651c650BBcDA92bFd204A9A3698C9b;
        u[36] = 0xC3e17579Ff651c650BBcDA92bFd204A9A3698C9b;
        t[37] = 0x92671935b0Fd8C9bf341B9796715594D7EA910C8;
        u[37] = 0x92671935b0Fd8C9bf341B9796715594D7EA910C8;
        t[38] = 0xFD219f9d6e0306e7F02d207b303Aa0F029b1CC87;
        u[38] = 0xFD219f9d6e0306e7F02d207b303Aa0F029b1CC87;
        t[39] = 0x2e1D08cbb257587FC98DCc0458d957e30A235b55;
        u[39] = 0x2e1D08cbb257587FC98DCc0458d957e30A235b55;
        t[40] = 0xC3a3a96433d627AAdcbdBcA2F4D924cDa780170d;
        u[40] = 0xC3a3a96433d627AAdcbdBcA2F4D924cDa780170d;
        t[41] = 0x140282Be5CEaFD9752a85d05894f95B02a0c977E;
        u[41] = 0x140282Be5CEaFD9752a85d05894f95B02a0c977E;
        t[42] = 0x9AE516b934727De33a43C43297762B11Ad16Aa99;
        u[42] = 0x9AE516b934727De33a43C43297762B11Ad16Aa99;
        t[43] = 0x85E762022a47F3d48D56bAABC20a690C362bf082;
        u[43] = 0x85E762022a47F3d48D56bAABC20a690C362bf082;
        t[44] = 0xF09E5B7E73eBcd5197e84e8Cf8ddE8Ce0223Fa56;
        u[44] = 0xF09E5B7E73eBcd5197e84e8Cf8ddE8Ce0223Fa56;
        t[45] = 0x7A9325b2f8810DeDD20C16c653596DaAc99cdDC5;
        u[45] = 0x7A9325b2f8810DeDD20C16c653596DaAc99cdDC5;
        t[46] = 0xba7C38C1D4F1CF4693eAc7e0E1E171EB7f5Ff2BE;
        u[46] = 0xba7C38C1D4F1CF4693eAc7e0E1E171EB7f5Ff2BE;
        t[47] = 0x19675CCC69dB3846aCcB35E9c4975B6482DD3448;
        u[47] = 0x19675CCC69dB3846aCcB35E9c4975B6482DD3448;
        t[48] = 0x499431d73E7f66B04f721640eF5Cf57616fdC681;
        u[48] = 0x499431d73E7f66B04f721640eF5Cf57616fdC681;
        t[49] = 0x6C00022B5991Dee4a6571e4102501eeee091A995;
        u[49] = 0x6C00022B5991Dee4a6571e4102501eeee091A995;
        t[50] = 0x7077Aac787CB1A9E9d3253E0701A2a1ceaB3F6a5;
        u[50] = 0x7077Aac787CB1A9E9d3253E0701A2a1ceaB3F6a5;
        t[51] = 0x426b2dc999e65ec62e2151359227DCCA135A9DD3;
        u[51] = 0x426b2dc999e65ec62e2151359227DCCA135A9DD3;
        t[52] = 0xB5BA09fEF747cb85c2c5e9e50daEe9f83E796Cc4;
        u[52] = 0xB5BA09fEF747cb85c2c5e9e50daEe9f83E796Cc4;
        t[53] = 0x97072e4e6E222C7071fb8d3dEF0EbBfB0DfAd073;
        u[53] = 0x97072e4e6E222C7071fb8d3dEF0EbBfB0DfAd073;
        t[54] = 0xA53A473b7b6d947f6a91d9F64306CCa939A7A778;
        u[54] = 0xA53A473b7b6d947f6a91d9F64306CCa939A7A778;
        t[55] = 0x1bB40cCEB3355162A40519Cf92753b8EFB8f51d4;
        u[55] = 0x1bB40cCEB3355162A40519Cf92753b8EFB8f51d4;
        t[56] = 0x931C2aCd2972e1482fe9903485d69D79847A4200;
        u[56] = 0x931C2aCd2972e1482fe9903485d69D79847A4200;
        t[57] = 0x843a146d1Efdb82A154354f042380A07Bd3A944A;
        u[57] = 0x843a146d1Efdb82A154354f042380A07Bd3A944A;
        t[58] = 0x8De8a94A21120296597552145BA28F81c99A9A5c;
        u[58] = 0x8De8a94A21120296597552145BA28F81c99A9A5c;
        t[59] = 0xb8947f2fE2177d36f2f990300106f27c738DFC8D;
        u[59] = 0xb8947f2fE2177d36f2f990300106f27c738DFC8D;
    }
}
