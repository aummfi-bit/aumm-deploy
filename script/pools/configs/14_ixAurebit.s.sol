// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title IxAurebitConfig
 * @notice Five-asset Standard pool — svZCHF 26% + Aave Prime GHO 26% + ixEDEL 16% + WBTC 16% + cbBTC 16%.
 *         Sector: Digital Gold / Bitcoin.
 *
 * @dev Manifest row: `aumm-site/06_miliarium_manifest.md` (slot 14) — "ixAurebit".
 *
 *      Composition lock: `docs/STAGE_E_PLAN.md` E-D4 (svZCHF 26% / Aave Prime GHO 26% / ixEDEL 16% / WBTC 16% / cbBTC 16%).
 *      Token addresses + Rate Providers: `docs/STAGE_E_PLAN.md` E-D4 (mainnet vault literals).
 *      Name / symbol: `docs/STAGE_E_NOTES.md` E-D18 (lower-camel `ixAurebit` / uppercase `IXAUREBIT`).
 *      Sector label: `docs/STAGE_E_NOTES.md` E-D19 ("Digital Gold / Bitcoin" per manifest sector column).
 *      Salt: `docs/STAGE_E_NOTES.md` E-D20 (slot-derived `bytes32(uint256(14))`).
 *      Library shape: `docs/STAGE_E_NOTES.md` E-D21 (per-pool library + Bodensee-tier NatSpec).
 *      Initial swap fee: `docs/STAGE_E_NOTES.md` E-D22 (`0.0002e18` = 0.02%, governance-adjustable
 *      within OQ-11's revised 0.01%–0.30% band; per-pool `swapFeeManager` is `address(0)` — F-20/P-D40, defers to the Vault authorizer).
 *      Aave Prime GHO naming convention: `docs/STAGE_E_NOTES.md` §E11 (Aave Prime GHO is the Aave-issued ERC-4626 vault wrapping bare GHO; bare GHO ERC-20 `0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f` is not a pilot component).
 *      Quality Gate: 52% ERC-4626 — two of five tokens (Aave Prime GHO, svZCHF) are `TokenType.WITH_RATE`
 *      with non-zero Rate Providers at 0.26 each (sum = 0.52e18); ixEDEL, WBTC, cbBTC are `TokenType.STANDARD`
 *      with no Rate Provider at 0.16 each. Clears `MIN_ERC4626_WEIGHT = 52e16` at the gate boundary (margin +0 pp);
 *      the boundary case relies on the `>=` comparator in `AureumWeightedPoolFactory.create()` per E-D11.
 *      Mixed decimals: WBTC + cbBTC are 8-decimal; Aave Prime GHO + ixEDEL + svZCHF are 18-decimal. Decimals are read
 *      at registration time by the Vault from each token contract; per-token seed amounts in the fork-test override
 *      (`IxAurebitPilotTest._seedAmounts()` at E3.3) follow the per-decimal `1_000 * 10**decimals(token)` rule per E-D25
 *      amendment (E10).
 *      Ascending-address sort applied at literal-write time per Balancer V3 registration convention:
 *      WBTC (`0x2260…`), Aave Prime GHO (`0xC71E…`), cbBTC (`0xcbB7…`), ixEDEL (`0xe4a1…`), svZCHF (`0xE5F1…`). No runtime sort.
 */
library IxAurebitConfig {
    address internal constant WBTC           = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant AAVE_PRIME_GHO = 0xC71Ea051a5F82c67ADcF634c36FFE6334793D24C;
    address internal constant CBBTC          = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address internal constant IXEDEL         = 0xe4a10951f962e6cB93Cb843a4ef05d2F99DB1F94;
    address internal constant SVZCHF         = 0xE5F130253fF137f9917C0107659A4c5262abf6b0;

    address internal constant AAVE_PRIME_GHO_RATE_PROVIDER = 0x851b73c4BFd5275D47FFf082F9e8B4997dCCB253;
    address internal constant SVZCHF_RATE_PROVIDER         = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;

    function config() internal pure returns (PoolConfig memory) {
        address[] memory tokens = new address[](5);
        tokens[0] = WBTC;
        tokens[1] = AAVE_PRIME_GHO;
        tokens[2] = CBBTC;
        tokens[3] = IXEDEL;
        tokens[4] = SVZCHF;

        TokenType[] memory tokenTypes = new TokenType[](5);
        tokenTypes[0] = TokenType.STANDARD;     // WBTC
        tokenTypes[1] = TokenType.WITH_RATE;    // Aave Prime GHO
        tokenTypes[2] = TokenType.STANDARD;     // cbBTC
        tokenTypes[3] = TokenType.STANDARD;     // ixEDEL
        tokenTypes[4] = TokenType.WITH_RATE;    // svZCHF

        IRateProvider[] memory rateProviders = new IRateProvider[](5);
        rateProviders[0] = IRateProvider(address(0));
        rateProviders[1] = IRateProvider(AAVE_PRIME_GHO_RATE_PROVIDER);
        rateProviders[2] = IRateProvider(address(0));
        rateProviders[3] = IRateProvider(address(0));
        rateProviders[4] = IRateProvider(SVZCHF_RATE_PROVIDER);

        bool[] memory paysYieldFees = new bool[](5);
        paysYieldFees[0] = false;   // WBTC (STANDARD)
        paysYieldFees[1] = true;    // Aave Prime GHO (WITH_RATE + RP)
        paysYieldFees[2] = false;   // cbBTC (STANDARD)
        paysYieldFees[3] = false;   // ixEDEL (STANDARD)
        paysYieldFees[4] = true;    // svZCHF (WITH_RATE + RP)

        uint256[] memory normalizedWeights = new uint256[](5);
        normalizedWeights[0] = 0.16e18;  // WBTC 16%
        normalizedWeights[1] = 0.26e18;  // Aave Prime GHO 26%
        normalizedWeights[2] = 0.16e18;  // cbBTC 16%
        normalizedWeights[3] = 0.16e18;  // ixEDEL 16%
        normalizedWeights[4] = 0.26e18;  // svZCHF 26%

        return PoolConfig({
            name: "ixAurebit",
            symbol: "IXAUREBIT",
            slot: 14,
            sectorLabel: "Digital Gold / Bitcoin",
            tokens: tokens,
            tokenTypes: tokenTypes,
            rateProviders: rateProviders,
            paysYieldFees: paysYieldFees,
            normalizedWeights: normalizedWeights,
            swapFeePercentage: 0.0002e18,
            salt: bytes32(uint256(14))
        });
    }
}
