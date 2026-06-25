// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title IxLibertasConfig
 * @notice Seven-asset Non-Standard pool — scrvUSD 15% + ysyBOLD 14% + USDC 14% + sUSDS 14% + PYUSD 15% + GHO 14% + USDT 14%.
 *         Sector: Routing Infrastructure.
 *
 * @dev Manifest row: `aumm-site/06_miliarium_manifest.md` (slot 06) — "ixLibertas".
 *
 *      Composition lock: N-D4 Non-Standard 7-token USD hub (no ixEDEL), amended by N-D9 (sfrxUSD → ysyBOLD).
 *      scrvUSD 15% / ysyBOLD 14% / USDC 14% / sUSDS 14% / PYUSD 15% / GHO 14% / USDT 14%.
 *      Token addresses + Rate Providers: `aumm-site/07a_tokens.md` (E-D17 verified mainnet literals); ysyBOLD
 *      per N-D9 (Frankencoin discussion #94), not yet in `07a_tokens.md` (aumm-site update user-side, deferred).
 *      RP threading (N-D7, amended N-D9): scrvUSD uses the Aureum-deployed `ERC4626RateProvider` (N3.1) — no
 *      mainnet address exists, so it is injected as the `scrvUsdRp` parameter (config stays `pure`) and resolved
 *      from the `SCRVUSD_RATE_PROVIDER` env var by `DeployIxLibertas._config()`. ysyBOLD's rate is a two-hop
 *      composite (ysyBOLD→yBOLD→BOLD) — the Aureum-deployed `CompositeRateProvider` (N3.2) wrapping ysyBOLD over
 *      an `ERC4626RateProvider(yBOLD)` — injected as the `ysyBoldRp` parameter and resolved from the
 *      `YSYBOLD_RATE_PROVIDER` env var. sUSDS and GHO use the verified mainnet RP literals below; USDC, USDT, and
 *      PYUSD are bare `TokenType.STANDARD` with no RP (N-D3 / N-D4 — the 07a USDC/USDT wrapper addresses are
 *      deliberately NOT used).
 *      Name / symbol: E-D18 (lower-camel `ixLibertas` / uppercase `IXLIBERTAS`).
 *      Sector label: E-D19 ("Routing Infrastructure" per manifest sector column).
 *      Salt: E-D20 (slot-derived `bytes32(uint256(6))`).
 *      Library shape: E-D21 (per-pool library + Bodensee-tier NatSpec).
 *      Initial swap fee: E-D22 (`0.0002e18` = 0.02%, governance-adjustable
 *      within OQ-11's revised 0.01%–0.30% band; per-pool `swapFeeManager` is `governanceMultisig`).
 *      Quality Gate: four admitted ERC-4626 (`TokenType.WITH_RATE`) yield cores — scrvUSD 15 + ysyBOLD 14 +
 *      sUSDS 14 + GHO 14 — sum to a 57% numerator (0.57e18); USDC, PYUSD, and USDT bind as bare
 *      `TokenType.STANDARD` ERC-20 legs with no RP (N-D3 / N-D4).
 *      Clears `MIN_ERC4626_WEIGHT = 52e16` with a +5pp margin.
 *      Ascending-address sort applied at literal-write time per Balancer V3 registration convention:
 *      scrvUSD (`0x0655…`), ysyBOLD (`0x2334…`), USDC (`0xA0b8…`), sUSDS (`0xa393…`), PYUSD (`0xb51E…`),
 *      GHO (`0xC71E…`), USDT (`0xdAC1…`). No runtime sort.
 */
library IxLibertasConfig {
    address internal constant SCRVUSD         = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;
    address internal constant YSYBOLD         = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
    address internal constant USDC            = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant SUSDS           = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address internal constant PYUSD           = 0xb51EDdDD8c47856D81C8681EA71404Cec93E92c6;
    address internal constant GHO             = 0xC71Ea051a5F82c67ADcF634c36FFE6334793D24C;
    address internal constant USDT            = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address internal constant SUSDS_RATE_PROVIDER = 0x1195BE91e78ab25494C855826FF595Eef784d47B;
    address internal constant GHO_RATE_PROVIDER   = 0x851b73c4BFd5275D47FFf082F9e8B4997dCCB253;

    function config(address scrvUsdRp, address ysyBoldRp) internal pure returns (PoolConfig memory) {
        address[] memory tokens = new address[](7);
        tokens[0] = SCRVUSD;
        tokens[1] = YSYBOLD;
        tokens[2] = USDC;
        tokens[3] = SUSDS;
        tokens[4] = PYUSD;
        tokens[5] = GHO;
        tokens[6] = USDT;

        TokenType[] memory tokenTypes = new TokenType[](7);
        tokenTypes[0] = TokenType.WITH_RATE;    // scrvUSD
        tokenTypes[1] = TokenType.WITH_RATE;    // ysyBOLD
        tokenTypes[2] = TokenType.STANDARD;     // USDC
        tokenTypes[3] = TokenType.WITH_RATE;    // sUSDS
        tokenTypes[4] = TokenType.STANDARD;     // PYUSD
        tokenTypes[5] = TokenType.WITH_RATE;    // GHO
        tokenTypes[6] = TokenType.STANDARD;     // USDT

        IRateProvider[] memory rateProviders = new IRateProvider[](7);
        rateProviders[0] = IRateProvider(scrvUsdRp);
        rateProviders[1] = IRateProvider(ysyBoldRp);
        rateProviders[2] = IRateProvider(address(0));
        rateProviders[3] = IRateProvider(SUSDS_RATE_PROVIDER);
        rateProviders[4] = IRateProvider(address(0));
        rateProviders[5] = IRateProvider(GHO_RATE_PROVIDER);
        rateProviders[6] = IRateProvider(address(0));

        bool[] memory paysYieldFees = new bool[](7);
        paysYieldFees[0] = true;    // scrvUSD (WITH_RATE + RP)
        paysYieldFees[1] = true;    // ysyBOLD (WITH_RATE + RP)
        paysYieldFees[2] = false;   // USDC (STANDARD)
        paysYieldFees[3] = true;    // sUSDS (WITH_RATE + RP)
        paysYieldFees[4] = false;   // PYUSD (STANDARD)
        paysYieldFees[5] = true;    // GHO (WITH_RATE + RP)
        paysYieldFees[6] = false;   // USDT (STANDARD)

        uint256[] memory normalizedWeights = new uint256[](7);
        normalizedWeights[0] = 0.15e18;  // scrvUSD 15%
        normalizedWeights[1] = 0.14e18;  // ysyBOLD 14%
        normalizedWeights[2] = 0.14e18;  // USDC 14%
        normalizedWeights[3] = 0.14e18;  // sUSDS 14%
        normalizedWeights[4] = 0.15e18;  // PYUSD 15%
        normalizedWeights[5] = 0.14e18;  // GHO 14%
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
