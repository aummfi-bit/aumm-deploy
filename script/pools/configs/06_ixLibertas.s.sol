// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title IxLibertasConfig
 * @notice Seven-asset Non-Standard pool — scrvUSD 15% + USDC 14% + sUSDS 14% + PYUSD 15% + GHO 14% + sfrxUSD 14% + USDT 14%.
 *         Sector: Routing Infrastructure.
 *
 * @dev Manifest row: `aumm-site/06_miliarium_manifest.md` (slot 06) — "ixLibertas".
 *
 *      Composition lock: N-D4 Non-Standard 7-token USD hub (no ixEDEL).
 *      scrvUSD 15% / USDC 14% / sUSDS 14% / PYUSD 15% / GHO 14% / sfrxUSD 14% / USDT 14%.
 *      Token addresses + Rate Providers: `aumm-site/07a_tokens.md` (E-D17 verified mainnet literals).
 *      RP threading (N-D7): scrvUSD and sfrxUSD yield cores use the Aureum-deployed `ERC4626RateProvider` (N3.1) —
 *      no mainnet address exists for either, so they are injected as the `scrvUsdRp` / `sfrxUsdRp` parameters
 *      (config stays `pure`) and resolved from the `SCRVUSD_RATE_PROVIDER` / `SFRXUSD_RATE_PROVIDER` env vars by
 *      `DeployIxLibertas._config()`. sUSDS and GHO use the verified mainnet RP literals below; USDC, USDT, and PYUSD
 *      are bare `TokenType.STANDARD` with no RP (N-D3 / N-D4 — the 07a USDC/USDT wrapper addresses are deliberately NOT used).
 *      Name / symbol: E-D18 (lower-camel `ixLibertas` / uppercase `IXLIBERTAS`).
 *      Sector label: E-D19 ("Routing Infrastructure" per manifest sector column).
 *      Salt: E-D20 (slot-derived `bytes32(uint256(6))`).
 *      Library shape: E-D21 (per-pool library + Bodensee-tier NatSpec).
 *      Initial swap fee: E-D22 (`0.0002e18` = 0.02%, governance-adjustable
 *      within OQ-11's revised 0.01%–0.30% band; per-pool `swapFeeManager` is `governanceMultisig`).
 *      Quality Gate: four admitted ERC-4626 (`TokenType.WITH_RATE`) yield cores — scrvUSD 15 + sUSDS 14 + GHO 14 +
 *      sfrxUSD 14 — sum to a 57% numerator (0.57e18); USDC, PYUSD, and USDT bind as bare `TokenType.STANDARD`
 *      ERC-20 legs with no RP (N-D3 / N-D4).
 *      Clears `MIN_ERC4626_WEIGHT = 52e16` with a +5pp margin.
 *      Ascending-address sort applied at literal-write time per Balancer V3 registration convention:
 *      scrvUSD (`0x0655…`), USDC (`0xA0b8…`), sUSDS (`0xa393…`), PYUSD (`0xb51E…`), GHO (`0xC71E…`), sfrxUSD (`0xcf62…`), USDT (`0xdAC1…`). No runtime sort.
 */
library IxLibertasConfig {
    address internal constant SCRVUSD         = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;
    address internal constant USDC            = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant SUSDS           = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address internal constant PYUSD           = 0xb51EDdDD8c47856D81C8681EA71404Cec93E92c6;
    address internal constant GHO             = 0xC71Ea051a5F82c67ADcF634c36FFE6334793D24C;
    address internal constant SFRXUSD         = 0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6;
    address internal constant USDT            = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address internal constant SUSDS_RATE_PROVIDER = 0x1195BE91e78ab25494C855826FF595Eef784d47B;
    address internal constant GHO_RATE_PROVIDER   = 0x851b73c4BFd5275D47FFf082F9e8B4997dCCB253;

    function config(address scrvUsdRp, address sfrxUsdRp) internal pure returns (PoolConfig memory) {
        address[] memory tokens = new address[](7);
        tokens[0] = SCRVUSD;
        tokens[1] = USDC;
        tokens[2] = SUSDS;
        tokens[3] = PYUSD;
        tokens[4] = GHO;
        tokens[5] = SFRXUSD;
        tokens[6] = USDT;

        TokenType[] memory tokenTypes = new TokenType[](7);
        tokenTypes[0] = TokenType.WITH_RATE;    // scrvUSD
        tokenTypes[1] = TokenType.STANDARD;     // USDC
        tokenTypes[2] = TokenType.WITH_RATE;    // sUSDS
        tokenTypes[3] = TokenType.STANDARD;     // PYUSD
        tokenTypes[4] = TokenType.WITH_RATE;    // GHO
        tokenTypes[5] = TokenType.WITH_RATE;    // sfrxUSD
        tokenTypes[6] = TokenType.STANDARD;     // USDT

        IRateProvider[] memory rateProviders = new IRateProvider[](7);
        rateProviders[0] = IRateProvider(scrvUsdRp);
        rateProviders[1] = IRateProvider(address(0));
        rateProviders[2] = IRateProvider(SUSDS_RATE_PROVIDER);
        rateProviders[3] = IRateProvider(address(0));
        rateProviders[4] = IRateProvider(GHO_RATE_PROVIDER);
        rateProviders[5] = IRateProvider(sfrxUsdRp);
        rateProviders[6] = IRateProvider(address(0));

        bool[] memory paysYieldFees = new bool[](7);
        paysYieldFees[0] = true;    // scrvUSD (WITH_RATE + RP)
        paysYieldFees[1] = false;   // USDC (STANDARD)
        paysYieldFees[2] = true;    // sUSDS (WITH_RATE + RP)
        paysYieldFees[3] = false;   // PYUSD (STANDARD)
        paysYieldFees[4] = true;    // GHO (WITH_RATE + RP)
        paysYieldFees[5] = true;    // sfrxUSD (WITH_RATE + RP)
        paysYieldFees[6] = false;   // USDT (STANDARD)

        uint256[] memory normalizedWeights = new uint256[](7);
        normalizedWeights[0] = 0.15e18;  // scrvUSD 15%
        normalizedWeights[1] = 0.14e18;  // USDC 14%
        normalizedWeights[2] = 0.14e18;  // sUSDS 14%
        normalizedWeights[3] = 0.15e18;  // PYUSD 15%
        normalizedWeights[4] = 0.14e18;  // GHO 14%
        normalizedWeights[5] = 0.14e18;  // sfrxUSD 14%
        normalizedWeights[6] = 0.14e18;  // USDT 14%

        return PoolConfig({
            name: "ixLibertas",
            symbol: "IXLIBERTAS",
            slot: 6,
            sectorLabel: "Routing Infrastructure",
            tokens: tokens,
            tokenTypes: tokenTypes,
            rateProviders: rateProviders,
            paysYieldFees: paysYieldFees,
            normalizedWeights: normalizedWeights,
            swapFeePercentage: 0.0002e18,
            salt: bytes32(uint256(6))
        });
    }
}
