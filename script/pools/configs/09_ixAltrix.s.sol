// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title IxAltrixConfig
 * @notice Five-asset Standard pool — FLHYon 16% + waEthUSDC 26% + ixEDEL 16% + svZCHF 26% + HYGon 16%.
 *         Sector: US Fixed Income (high yield).
 *
 * @dev Manifest row: `aumm-site/06_miliarium_manifest.md` (slot 09) — "ixAltrix".
 *
 *      Composition lock: M-D5 Standard 26/26/16/16/16 template (svZCHF 26% / waEthUSDC 26% / ixEDEL 16% / HYGon 16% / FLHYon 16%).
 *      Token addresses + Rate Providers: `aumm-site/07a_tokens.md` (E-D17 verified mainnet literals).
 *      Name / symbol: E-D18 (lower-camel `ixAltrix` / uppercase `IXALTRIX`).
 *      Sector label: E-D19 ("US Fixed Income (high yield)" per manifest sector column).
 *      Salt: E-D20 (slot-derived `bytes32(uint256(9))`).
 *      Library shape: E-D21 (per-pool library + Bodensee-tier NatSpec).
 *      Initial swap fee: E-D22 (`0.0002e18` = 0.02%, governance-adjustable
 *      within OQ-11's revised 0.01%–0.30% band; per-pool `swapFeeManager` is `address(0)` — F-20/P-D40, defers to the Vault authorizer).
 *      Quality Gate: two ERC-4626 (`TokenType.WITH_RATE`) yield cores — svZCHF 26 + waEthUSDC 26 — sum to
 *      a 52% numerator (0.52e18); ixEDEL, HYGon, FLHYon are the three `TokenType.STANDARD` tokens at 16% each.
 *      Clears `MIN_ERC4626_WEIGHT = 52e16` exactly at the gate boundary (margin +0 pp); the boundary case relies
 *      on the `>=` comparator in `AureumWeightedPoolFactory.create()` per E-D11.
 *      Ascending-address sort applied at literal-write time per Balancer V3 registration convention:
 *      FLHYon (`0x54C1…`), waEthUSDC (`0xD4fa…`), ixEDEL (`0xe4a1…`), svZCHF (`0xE5F1…`), HYGon (`0xeD36…`) —
 *      note ixEDEL/svZCHF/HYGon all share the 0xe leading nibble, ordered 0xe4 < 0xE5 < 0xeD. No runtime sort.
 */
library IxAltrixConfig {
    address internal constant FLHYON        = 0x54C1Ff361b402f66c13107421E6A431C3375EF24;
    address internal constant WAETHUSDC     = 0xD4fa2D31b7968E448877f69A96DE69f5de8cD23E;
    address internal constant IXEDEL         = 0xe4a10951f962e6cB93Cb843a4ef05d2F99DB1F94;
    address internal constant SVZCHF         = 0xE5F130253fF137f9917C0107659A4c5262abf6b0;
    address internal constant HYGON          = 0xeD3618Bb8778F8eBBe2f241Da532227591771D04;

    address internal constant WAETHUSDC_RATE_PROVIDER = 0x8f4E8439b970363648421C692dd897Fb9c0Bd1D9;
    address internal constant SVZCHF_RATE_PROVIDER         = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;

    function config() internal pure returns (PoolConfig memory) {
        address[] memory tokens = new address[](5);
        tokens[0] = FLHYON;
        tokens[1] = WAETHUSDC;
        tokens[2] = IXEDEL;
        tokens[3] = SVZCHF;
        tokens[4] = HYGON;

        TokenType[] memory tokenTypes = new TokenType[](5);
        tokenTypes[0] = TokenType.STANDARD;     // FLHYon
        tokenTypes[1] = TokenType.WITH_RATE;    // waEthUSDC
        tokenTypes[2] = TokenType.STANDARD;     // ixEDEL
        tokenTypes[3] = TokenType.WITH_RATE;    // svZCHF
        tokenTypes[4] = TokenType.STANDARD;     // HYGon

        IRateProvider[] memory rateProviders = new IRateProvider[](5);
        rateProviders[0] = IRateProvider(address(0));
        rateProviders[1] = IRateProvider(WAETHUSDC_RATE_PROVIDER);
        rateProviders[2] = IRateProvider(address(0));
        rateProviders[3] = IRateProvider(SVZCHF_RATE_PROVIDER);
        rateProviders[4] = IRateProvider(address(0));

        bool[] memory paysYieldFees = new bool[](5);
        paysYieldFees[0] = false;   // FLHYon (STANDARD)
        paysYieldFees[1] = true;    // waEthUSDC (WITH_RATE + RP)
        paysYieldFees[2] = false;   // ixEDEL (STANDARD)
        paysYieldFees[3] = true;    // svZCHF (WITH_RATE + RP)
        paysYieldFees[4] = false;   // HYGon (STANDARD)

        uint256[] memory normalizedWeights = new uint256[](5);
        normalizedWeights[0] = 0.16e18;  // FLHYon 16%
        normalizedWeights[1] = 0.26e18;  // waEthUSDC 26%
        normalizedWeights[2] = 0.16e18;  // ixEDEL 16%
        normalizedWeights[3] = 0.26e18;  // svZCHF 26%
        normalizedWeights[4] = 0.16e18;  // HYGon 16%

        return PoolConfig({
            name: "ixAltrix",
            symbol: "IXALTRIX",
            slot: 9,
            sectorLabel: "US Fixed Income (high yield)",
            tokens: tokens,
            tokenTypes: tokenTypes,
            rateProviders: rateProviders,
            paysYieldFees: paysYieldFees,
            normalizedWeights: normalizedWeights,
            swapFeePercentage: 0.0002e18,
            salt: bytes32(uint256(9))
        });
    }
}
