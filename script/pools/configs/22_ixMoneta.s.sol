// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title IxMonetaConfig
 * @notice Five-asset Standard pool — JPMon 16% + Aave Prime GHO 26% + GSon 16% + ixEDEL 16% + svZCHF 26%.
 *         Sector: Banking / Financials.
 *
 * @dev Manifest row: `aumm-site/06_miliarium_manifest.md` (slot 22) — "ixMoneta".
 *
 *      Composition lock: N-D0 build scope on the M-D5 Standard 26/26/16/16/16 template (svZCHF 26% / Aave Prime GHO 26% / ixEDEL 16% / JPMon 16% / GSon 16%).
 *      Token addresses + Rate Providers: `aumm-site/07a_tokens.md` (E-D17 verified mainnet literals).
 *      Aave Prime GHO binds the Aave GHO ERC-4626 vault `0xC71Ea051…` + RP `0x851b73…` (not bare GHO ERC-20 `0x40D16F…`; per E11 / 07a GHO row, mirrors ixAurebit slot 14).
 *      Name / symbol: E-D18 (lower-camel `ixMoneta` / uppercase `IXMONETA`).
 *      Sector label: E-D19 ("Banking / Financials" per manifest sector column).
 *      Salt: E-D20 (slot-derived `bytes32(uint256(22))`).
 *      Library shape: E-D21 (per-pool library + Bodensee-tier NatSpec).
 *      Initial swap fee: E-D22 (`0.0002e18` = 0.02%, governance-adjustable
 *      within OQ-11's revised 0.01%–0.30% band; per-pool `swapFeeManager` is `address(0)` — F-20/P-D40, defers to the Vault authorizer).
 *      Quality Gate: two ERC-4626 (`TokenType.WITH_RATE`) yield cores — svZCHF 26 + Aave Prime GHO 26 — sum to
 *      a 52% numerator (0.52e18); JPMon, GSon, ixEDEL are the three `TokenType.STANDARD` tokens at 16% each.
 *      Clears `MIN_ERC4626_WEIGHT = 52e16` exactly at the gate boundary (margin +0 pp); the boundary case relies
 *      on the `>=` comparator in `AureumWeightedPoolFactory.create()` per E-D11.
 *      Ascending-address sort applied at literal-write time per Balancer V3 registration convention:
 *      JPMon (`0x03C1…`), Aave Prime GHO (`0xC71E…`), GSon (`0xdB57…`), ixEDEL (`0xe4a1…`), svZCHF (`0xE5F1…`). No runtime sort.
 */
library IxMonetaConfig {
    address internal constant JPMON           = 0x03C1EC4CA9DBb168E6Db0DeF827c085999CBffaF;
    address internal constant AAVE_PRIME_GHO  = 0xC71Ea051a5F82c67ADcF634c36FFE6334793D24C;
    address internal constant GSON            = 0xdB57d9C14e357Fc01E49035a808779Df41E9B4e2;
    address internal constant IXEDEL          = 0xe4a10951f962e6cB93Cb843a4ef05d2F99DB1F94;
    address internal constant SVZCHF          = 0xE5F130253fF137f9917C0107659A4c5262abf6b0;

    address internal constant AAVE_PRIME_GHO_RATE_PROVIDER = 0x851b73c4BFd5275D47FFf082F9e8B4997dCCB253;
    address internal constant SVZCHF_RATE_PROVIDER = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;

    function config() internal pure returns (PoolConfig memory) {
        address[] memory tokens = new address[](5);
        tokens[0] = JPMON;
        tokens[1] = AAVE_PRIME_GHO;
        tokens[2] = GSON;
        tokens[3] = IXEDEL;
        tokens[4] = SVZCHF;

        TokenType[] memory tokenTypes = new TokenType[](5);
        tokenTypes[0] = TokenType.STANDARD;     // JPMon
        tokenTypes[1] = TokenType.WITH_RATE;    // Aave Prime GHO
        tokenTypes[2] = TokenType.STANDARD;     // GSon
        tokenTypes[3] = TokenType.STANDARD;     // ixEDEL
        tokenTypes[4] = TokenType.WITH_RATE;    // svZCHF

        IRateProvider[] memory rateProviders = new IRateProvider[](5);
        rateProviders[0] = IRateProvider(address(0));
        rateProviders[1] = IRateProvider(AAVE_PRIME_GHO_RATE_PROVIDER);
        rateProviders[2] = IRateProvider(address(0));
        rateProviders[3] = IRateProvider(address(0));
        rateProviders[4] = IRateProvider(SVZCHF_RATE_PROVIDER);

        bool[] memory paysYieldFees = new bool[](5);
        paysYieldFees[0] = false;   // JPMon (STANDARD)
        paysYieldFees[1] = true;    // Aave Prime GHO (WITH_RATE + RP)
        paysYieldFees[2] = false;   // GSon (STANDARD)
        paysYieldFees[3] = false;   // ixEDEL (STANDARD)
        paysYieldFees[4] = true;    // svZCHF (WITH_RATE + RP)

        uint256[] memory normalizedWeights = new uint256[](5);
        normalizedWeights[0] = 0.16e18;  // JPMon 16%
        normalizedWeights[1] = 0.26e18;  // Aave Prime GHO 26%
        normalizedWeights[2] = 0.16e18;  // GSon 16%
        normalizedWeights[3] = 0.16e18;  // ixEDEL 16%
        normalizedWeights[4] = 0.26e18;  // svZCHF 26%

        return PoolConfig({
            name: "ixMoneta",
            symbol: "IXMONETA",
            slot: 22,
            sectorLabel: "Banking / Financials",
            tokens: tokens,
            tokenTypes: tokenTypes,
            rateProviders: rateProviders,
            paysYieldFees: paysYieldFees,
            normalizedWeights: normalizedWeights,
            swapFeePercentage: 0.0002e18,
            salt: bytes32(uint256(22))
        });
    }
}
