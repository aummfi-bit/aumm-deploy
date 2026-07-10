// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title IxEdelweissConfig
 * @notice Four-asset routing-hub pool — waEthUSDT 18% + waEthUSDC 18% + ixEDEL 46% + svZCHF 18%.
 *         Sector: Routing Infrastructure.
 *
 * @dev Manifest row: `aumm-site/06_miliarium_manifest.md` §xiii — "ixEdelweiss".
 *
 *      Composition lock: `docs/STAGE_E_PLAN.md` E-D4 (waEthUSDT 18% / waEthUSDC 18% / ixEDEL 46% / svZCHF 18%).
 *      Token addresses + Rate Providers: `docs/STAGE_E_NOTES.md` E-D17 (mainnet vault literals).
 *      Name / symbol: `docs/STAGE_E_NOTES.md` E-D18 (lower-camel `ixEdelweiss` / uppercase `IXEDELWEISS`).
 *      Sector label: `docs/STAGE_E_NOTES.md` E-D19 ("Routing Infrastructure" per manifest §xiii column "Sector").
 *      Salt: `docs/STAGE_E_NOTES.md` E-D20 (slot-derived `bytes32(uint256(5))`).
 *      Library shape: `docs/STAGE_E_NOTES.md` E-D21 (per-pool library + Bodensee-tier NatSpec).
 *      Initial swap fee: `docs/STAGE_E_NOTES.md` E-D22 (`0.0002e18` = 0.02%, governance-adjustable
 *      within OQ-11's revised 0.01%–0.30% band; per-pool `swapFeeManager` is `address(0)` — F-20/P-D40, defers to the Vault authorizer).
 *
 *      Quality Gate: 54% ERC-4626 — three of four tokens (waEthUSDT, waEthUSDC, svZCHF) are `TokenType.WITH_RATE`
 *      with non-zero Rate Providers at 0.18 each (sum = 0.54e18); ixEDEL is `TokenType.STANDARD` with no Rate
 *      Provider at 0.46. Clears `MIN_ERC4626_WEIGHT = 52e16` with margin +2 pp.
 *
 *      Ascending-address sort applied at literal-write time per Balancer V3 registration convention:
 *      waEthUSDT (`0x7Bc3…`), waEthUSDC (`0xD4fa…`), ixEDEL (`0xe4a1…`), svZCHF (`0xE5F1…`). No runtime sort.
 */
library IxEdelweissConfig {
    address internal constant WAETHUSDT = 0x7Bc3485026Ac48b6cf9BaF0A377477Fff5703Af8;
    address internal constant WAETHUSDC = 0xD4fa2D31b7968E448877f69A96DE69f5de8cD23E;
    address internal constant IXEDEL    = 0xe4a10951f962e6cB93Cb843a4ef05d2F99DB1F94;
    address internal constant SVZCHF    = 0xE5F130253fF137f9917C0107659A4c5262abf6b0;

    address internal constant WAETHUSDT_RATE_PROVIDER = 0xEdf63cce4bA70cbE74064b7687882E71ebB0e988;
    address internal constant WAETHUSDC_RATE_PROVIDER = 0x8f4E8439b970363648421C692dd897Fb9c0Bd1D9;
    address internal constant SVZCHF_RATE_PROVIDER    = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;

    function config() internal pure returns (PoolConfig memory) {
        address[] memory tokens = new address[](4);
        tokens[0] = WAETHUSDT;
        tokens[1] = WAETHUSDC;
        tokens[2] = IXEDEL;
        tokens[3] = SVZCHF;

        TokenType[] memory tokenTypes = new TokenType[](4);
        tokenTypes[0] = TokenType.WITH_RATE;
        tokenTypes[1] = TokenType.WITH_RATE;
        tokenTypes[2] = TokenType.STANDARD;
        tokenTypes[3] = TokenType.WITH_RATE;

        IRateProvider[] memory rateProviders = new IRateProvider[](4);
        rateProviders[0] = IRateProvider(WAETHUSDT_RATE_PROVIDER);
        rateProviders[1] = IRateProvider(WAETHUSDC_RATE_PROVIDER);
        rateProviders[2] = IRateProvider(address(0));
        rateProviders[3] = IRateProvider(SVZCHF_RATE_PROVIDER);

        bool[] memory paysYieldFees = new bool[](4);
        paysYieldFees[0] = true;
        paysYieldFees[1] = true;
        paysYieldFees[2] = false;
        paysYieldFees[3] = true;

        uint256[] memory normalizedWeights = new uint256[](4);
        normalizedWeights[0] = 0.18e18;  // waEthUSDT 18%
        normalizedWeights[1] = 0.18e18;  // waEthUSDC 18%
        normalizedWeights[2] = 0.46e18;  // ixEDEL 46%
        normalizedWeights[3] = 0.18e18;  // svZCHF 18%

        return PoolConfig({
            name: "ixEdelweiss",
            symbol: "IXEDELWEISS",
            slot: 5,
            sectorLabel: "Routing Infrastructure",
            tokens: tokens,
            tokenTypes: tokenTypes,
            rateProviders: rateProviders,
            paysYieldFees: paysYieldFees,
            normalizedWeights: normalizedWeights,
            swapFeePercentage: 0.0002e18,
            salt: bytes32(uint256(5))
        });
    }
}
