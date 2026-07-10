// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title IxGigantusConfig
 * @notice Five-asset Standard pool — NVDAon 16% + waEthUSDT 26% + ixEDEL 16% + svZCHF 26% + TSLAon 16%.
 *         Sector: US Equities (Mega Cap Tech).
 *
 * @dev Manifest row: `aumm-site/06_miliarium_manifest.md` (slot 19) — "ixGigantus".
 *
 *      Composition lock: N-D0 build scope on the M-D5 Standard 26/26/16/16/16 template (svZCHF 26% / waEthUSDT 26% / ixEDEL 16% / NVDAon 16% / TSLAon 16%).
 *      Token addresses + Rate Providers: `aumm-site/07a_tokens.md` (E-D17 verified mainnet literals).
 *      Name / symbol: E-D18 (lower-camel `ixGigantus` / uppercase `IXGIGANTUS`).
 *      Sector label: E-D19 ("US Equities (Mega Cap Tech)" per manifest sector column).
 *      Salt: E-D20 (slot-derived `bytes32(uint256(19))`).
 *      Library shape: E-D21 (per-pool library + Bodensee-tier NatSpec).
 *      Initial swap fee: E-D22 (`0.0002e18` = 0.02%, governance-adjustable
 *      within OQ-11's revised 0.01%–0.30% band; per-pool `swapFeeManager` is `address(0)` — F-20/P-D40, defers to the Vault authorizer).
 *      Quality Gate: two ERC-4626 (`TokenType.WITH_RATE`) yield cores — svZCHF 26 + waEthUSDT 26 — sum to
 *      a 52% numerator (0.52e18); NVDAon, ixEDEL, TSLAon are the three `TokenType.STANDARD` tokens at 16% each.
 *      Clears `MIN_ERC4626_WEIGHT = 52e16` exactly at the gate boundary (margin +0 pp); the boundary case relies
 *      on the `>=` comparator in `AureumWeightedPoolFactory.create()` per E-D11.
 *      Ascending-address sort applied at literal-write time per Balancer V3 registration convention:
 *      NVDAon (`0x2D1F…`), waEthUSDT (`0x7Bc3…`), ixEDEL (`0xe4a1…`), svZCHF (`0xE5F1…`), TSLAon (`0xf6b1…`). No runtime sort.
 */
library IxGigantusConfig {
    address internal constant NVDAON          = 0x2D1F7226Bd1F780AF6B9A49DCC0aE00E8Df4bDEE;
    address internal constant WAETHUSDT       = 0x7Bc3485026Ac48b6cf9BaF0A377477Fff5703Af8;
    address internal constant IXEDEL          = 0xe4a10951f962e6cB93Cb843a4ef05d2F99DB1F94;
    address internal constant SVZCHF          = 0xE5F130253fF137f9917C0107659A4c5262abf6b0;
    address internal constant TSLAON          = 0xf6b1117ec07684D3958caD8BEb1b302bfD21103f;

    address internal constant WAETHUSDT_RATE_PROVIDER = 0xEdf63cce4bA70cbE74064b7687882E71ebB0e988;
    address internal constant SVZCHF_RATE_PROVIDER    = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;

    function config() internal pure returns (PoolConfig memory) {
        address[] memory tokens = new address[](5);
        tokens[0] = NVDAON;
        tokens[1] = WAETHUSDT;
        tokens[2] = IXEDEL;
        tokens[3] = SVZCHF;
        tokens[4] = TSLAON;

        TokenType[] memory tokenTypes = new TokenType[](5);
        tokenTypes[0] = TokenType.STANDARD;     // NVDAon
        tokenTypes[1] = TokenType.WITH_RATE;    // waEthUSDT
        tokenTypes[2] = TokenType.STANDARD;     // ixEDEL
        tokenTypes[3] = TokenType.WITH_RATE;    // svZCHF
        tokenTypes[4] = TokenType.STANDARD;     // TSLAon

        IRateProvider[] memory rateProviders = new IRateProvider[](5);
        rateProviders[0] = IRateProvider(address(0));
        rateProviders[1] = IRateProvider(WAETHUSDT_RATE_PROVIDER);
        rateProviders[2] = IRateProvider(address(0));
        rateProviders[3] = IRateProvider(SVZCHF_RATE_PROVIDER);
        rateProviders[4] = IRateProvider(address(0));

        bool[] memory paysYieldFees = new bool[](5);
        paysYieldFees[0] = false;   // NVDAon (STANDARD)
        paysYieldFees[1] = true;    // waEthUSDT (WITH_RATE + RP)
        paysYieldFees[2] = false;   // ixEDEL (STANDARD)
        paysYieldFees[3] = true;    // svZCHF (WITH_RATE + RP)
        paysYieldFees[4] = false;   // TSLAon (STANDARD)

        uint256[] memory normalizedWeights = new uint256[](5);
        normalizedWeights[0] = 0.16e18;  // NVDAon 16%
        normalizedWeights[1] = 0.26e18;  // waEthUSDT 26%
        normalizedWeights[2] = 0.16e18;  // ixEDEL 16%
        normalizedWeights[3] = 0.26e18;  // svZCHF 26%
        normalizedWeights[4] = 0.16e18;  // TSLAon 16%

        return PoolConfig({
            name: "ixGigantus",
            symbol: "IXGIGANTUS",
            slot: 19,
            sectorLabel: "US Equities (Mega Cap Tech)",
            tokens: tokens,
            tokenTypes: tokenTypes,
            rateProviders: rateProviders,
            paysYieldFees: paysYieldFees,
            normalizedWeights: normalizedWeights,
            swapFeePercentage: 0.0002e18,
            salt: bytes32(uint256(19))
        });
    }
}
