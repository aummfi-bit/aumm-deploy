// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title IxMetallumConfig
 * @notice Five-asset Standard pool — waEthUSDT 26% + ixEDEL 16% + svZCHF 26% + SLVon 16% + URAon 16%.
 *         Sector: Silver & uranium (ETFs).
 *
 * @dev Manifest row: `aumm-site/06_miliarium_manifest.md` (slot 28) — "ixMetallum".
 *
 *      Composition lock: N-D0 build scope on the M-D5 Standard 26/26/16/16/16 template (svZCHF 26% / waEthUSDT 26% / ixEDEL 16% / SLVon 16% / URAon 16%).
 *      Token addresses + Rate Providers: `aumm-site/07a_tokens.md` (E-D17 verified mainnet literals).
 *      Name / symbol: E-D18 (lower-camel `ixMetallum` / uppercase `IXMETALLUM`).
 *      Sector label: E-D19 ("Silver & uranium (ETFs)" per manifest sector column).
 *      Salt: E-D20 (slot-derived `bytes32(uint256(28))`).
 *      Library shape: E-D21 (per-pool library + Bodensee-tier NatSpec).
 *      Initial swap fee: E-D22 (`0.0002e18` = 0.02%, governance-adjustable
 *      within OQ-11's revised 0.01%–0.30% band; per-pool `swapFeeManager` is `address(0)` — F-20/P-D40, defers to the Vault authorizer).
 *      Quality Gate: two ERC-4626 (`TokenType.WITH_RATE`) yield cores — svZCHF 26 + waEthUSDT 26 — sum to
 *      a 52% numerator (0.52e18); ixEDEL, SLVon, URAon are the three `TokenType.STANDARD` tokens at 16% each.
 *      Clears `MIN_ERC4626_WEIGHT = 52e16` exactly at the gate boundary (margin +0 pp); the boundary case relies
 *      on the `>=` comparator in `AureumWeightedPoolFactory.create()` per E-D11.
 *      Ascending-address sort applied at literal-write time per Balancer V3 registration convention:
 *      waEthUSDT (`0x7Bc3…`), ixEDEL (`0xe4a1…`), svZCHF (`0xE5F1…`), SLVon (`0xF3e4…`), URAon (`0xf98E…`). No runtime sort.
 */
library IxMetallumConfig {
    address internal constant WAETHUSDT       = 0x7Bc3485026Ac48b6cf9BaF0A377477Fff5703Af8;
    address internal constant IXEDEL          = 0xe4a10951f962e6cB93Cb843a4ef05d2F99DB1F94;
    address internal constant SVZCHF          = 0xE5F130253fF137f9917C0107659A4c5262abf6b0;
    address internal constant SLVON           = 0xF3e4872e6a4cF365888D93b6146a2bAA7348F1A4;
    address internal constant URAON           = 0xf98Ec282300892b3518B5cB996012b18d9B7D435;

    address internal constant WAETHUSDT_RATE_PROVIDER = 0xEdf63cce4bA70cbE74064b7687882E71ebB0e988;
    address internal constant SVZCHF_RATE_PROVIDER    = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;

    function config() internal pure returns (PoolConfig memory) {
        address[] memory tokens = new address[](5);
        tokens[0] = WAETHUSDT;
        tokens[1] = IXEDEL;
        tokens[2] = SVZCHF;
        tokens[3] = SLVON;
        tokens[4] = URAON;

        TokenType[] memory tokenTypes = new TokenType[](5);
        tokenTypes[0] = TokenType.WITH_RATE;    // waEthUSDT
        tokenTypes[1] = TokenType.STANDARD;     // ixEDEL
        tokenTypes[2] = TokenType.WITH_RATE;    // svZCHF
        tokenTypes[3] = TokenType.STANDARD;     // SLVon
        tokenTypes[4] = TokenType.STANDARD;     // URAon

        IRateProvider[] memory rateProviders = new IRateProvider[](5);
        rateProviders[0] = IRateProvider(WAETHUSDT_RATE_PROVIDER);
        rateProviders[1] = IRateProvider(address(0));
        rateProviders[2] = IRateProvider(SVZCHF_RATE_PROVIDER);
        rateProviders[3] = IRateProvider(address(0));
        rateProviders[4] = IRateProvider(address(0));

        bool[] memory paysYieldFees = new bool[](5);
        paysYieldFees[0] = true;    // waEthUSDT (WITH_RATE + RP)
        paysYieldFees[1] = false;   // ixEDEL (STANDARD)
        paysYieldFees[2] = true;    // svZCHF (WITH_RATE + RP)
        paysYieldFees[3] = false;   // SLVon (STANDARD)
        paysYieldFees[4] = false;   // URAon (STANDARD)

        uint256[] memory normalizedWeights = new uint256[](5);
        normalizedWeights[0] = 0.26e18;  // waEthUSDT 26%
        normalizedWeights[1] = 0.16e18;  // ixEDEL 16%
        normalizedWeights[2] = 0.26e18;  // svZCHF 26%
        normalizedWeights[3] = 0.16e18;  // SLVon 16%
        normalizedWeights[4] = 0.16e18;  // URAon 16%

        return PoolConfig({
            name: "ixMetallum",
            symbol: "IXMETALLUM",
            slot: 28,
            sectorLabel: "Silver & uranium (ETFs)",
            tokens: tokens,
            tokenTypes: tokenTypes,
            rateProviders: rateProviders,
            paysYieldFees: paysYieldFees,
            normalizedWeights: normalizedWeights,
            swapFeePercentage: 0.0002e18,
            salt: bytes32(uint256(28))
        });
    }
}
