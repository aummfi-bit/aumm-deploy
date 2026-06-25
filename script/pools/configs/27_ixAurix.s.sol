// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title IxAurixConfig
 * @notice Five-asset Standard pool — ysyBOLD 26% + PAXG 16% + XAUt 16% + ixEDEL 16% + svZCHF 26%.
 *         Sector: Gold / Commodities.
 *
 * @dev Manifest row: `aumm-site/06_miliarium_manifest.md` (slot 27) — "ixAurix".
 *
 *      Composition lock: N-D0 build scope on the M-D5 Standard 26/26/16/16/16 template, amended by N-D9 (sfrxUSD → ysyBOLD): svZCHF 26% / ysyBOLD 26% / ixEDEL 16% / PAXG 16% / XAUt 16%.
 *      Token addresses + Rate Providers: `aumm-site/07a_tokens.md` (E-D17 verified mainnet literals); ysyBOLD per N-D9 (Frankencoin discussion #94), not yet in `07a_tokens.md` (aumm-site update user-side, deferred).
 *      RP threading (N-D7, amended N-D9): the ysyBOLD yield core's Rate Provider is the Aureum-deployed `CompositeRateProvider` (N3.2) chaining ysyBOLD over `ERC4626RateProvider(yBOLD)` —
 *      no mainnet address exists, so it is injected as the `ysyBoldRp` parameter (config stays `pure`) and resolved from the
 *      `YSYBOLD_RATE_PROVIDER` env var by `DeployIxAurix._config()`. svZCHF's RP is the verified mainnet literal below.
 *      Name / symbol: E-D18 (lower-camel `ixAurix` / uppercase `IXAURIX`).
 *      Sector label: E-D19 ("Gold / Commodities" per manifest sector column).
 *      Salt: E-D20 (slot-derived `bytes32(uint256(27))`).
 *      Library shape: E-D21 (per-pool library + Bodensee-tier NatSpec).
 *      Initial swap fee: E-D22 (`0.0002e18` = 0.02%, governance-adjustable
 *      within OQ-11's revised 0.01%–0.30% band; per-pool `swapFeeManager` is `governanceMultisig`).
 *      Quality Gate: two ERC-4626 (`TokenType.WITH_RATE`) yield cores — svZCHF 26 + ysyBOLD 26 — sum to
 *      a 52% numerator (0.52e18); PAXG, XAUt, ixEDEL are the three `TokenType.STANDARD` tokens at 16% each.
 *      Clears `MIN_ERC4626_WEIGHT = 52e16` exactly at the gate boundary (margin +0 pp); the boundary case relies
 *      on the `>=` comparator in `AureumWeightedPoolFactory.create()` per E-D11.
 *      Ascending-address sort applied at literal-write time per Balancer V3 registration convention:
 *      ysyBOLD (`0x2334…`), PAXG (`0x4580…`), XAUt (`0x6874…`), ixEDEL (`0xe4a1…`), svZCHF (`0xE5F1…`). No runtime sort.
 */
library IxAurixConfig {
    address internal constant YSYBOLD         = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
    address internal constant PAXG            = 0x45804880De22913dAFE09f4980848ECE6EcbAf78;
    address internal constant XAUT            = 0x68749665FF8D2d112Fa859AA293F07A622782F38;
    address internal constant IXEDEL          = 0xe4a10951f962e6cB93Cb843a4ef05d2F99DB1F94;
    address internal constant SVZCHF          = 0xE5F130253fF137f9917C0107659A4c5262abf6b0;

    address internal constant SVZCHF_RATE_PROVIDER = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;

    function config(address ysyBoldRp) internal pure returns (PoolConfig memory) {
        address[] memory tokens = new address[](5);
        tokens[0] = YSYBOLD;
        tokens[1] = PAXG;
        tokens[2] = XAUT;
        tokens[3] = IXEDEL;
        tokens[4] = SVZCHF;

        TokenType[] memory tokenTypes = new TokenType[](5);
        tokenTypes[0] = TokenType.WITH_RATE;    // ysyBOLD
        tokenTypes[1] = TokenType.STANDARD;     // PAXG
        tokenTypes[2] = TokenType.STANDARD;     // XAUt
        tokenTypes[3] = TokenType.STANDARD;     // ixEDEL
        tokenTypes[4] = TokenType.WITH_RATE;    // svZCHF

        IRateProvider[] memory rateProviders = new IRateProvider[](5);
        rateProviders[0] = IRateProvider(ysyBoldRp);
        rateProviders[1] = IRateProvider(address(0));
        rateProviders[2] = IRateProvider(address(0));
        rateProviders[3] = IRateProvider(address(0));
        rateProviders[4] = IRateProvider(SVZCHF_RATE_PROVIDER);

        bool[] memory paysYieldFees = new bool[](5);
        paysYieldFees[0] = true;    // ysyBOLD (WITH_RATE + RP)
        paysYieldFees[1] = false;   // PAXG (STANDARD)
        paysYieldFees[2] = false;   // XAUt (STANDARD)
        paysYieldFees[3] = false;   // ixEDEL (STANDARD)
        paysYieldFees[4] = true;    // svZCHF (WITH_RATE + RP)

        uint256[] memory normalizedWeights = new uint256[](5);
        normalizedWeights[0] = 0.26e18;  // ysyBOLD 26%
        normalizedWeights[1] = 0.16e18;  // PAXG 16%
        normalizedWeights[2] = 0.16e18;  // XAUt 16%
        normalizedWeights[3] = 0.16e18;  // ixEDEL 16%
        normalizedWeights[4] = 0.26e18;  // svZCHF 26%

        return PoolConfig({
            name: "ixAurix",
            symbol: "IXAURIX",
            slot: 27,
            sectorLabel: "Gold / Commodities",
            tokens: tokens,
            tokenTypes: tokenTypes,
            rateProviders: rateProviders,
            paysYieldFees: paysYieldFees,
            normalizedWeights: normalizedWeights,
            swapFeePercentage: 0.0002e18,
            salt: bytes32(uint256(27))
        });
    }
}
