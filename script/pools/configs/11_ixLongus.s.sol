// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title IxLongusConfig
 * @notice Four-asset Non-Standard pool — TLTon 32% + waEthUSDC 26% + ixEDEL 16% + svZCHF 26%.
 *         Sector: US Fixed Income (long Treasury).
 *
 * @dev Manifest row: `aumm-site/06_miliarium_manifest.md` (slot 11) — "ixLongus".
 *
 *      Composition lock: M-D5 Non-Standard — single theme (TLTon) at 32% replacing the usual two 16% themes,
 *      yielding a FOUR-token pool (not the five-token Standard shape).
 *      Token addresses + Rate Providers: `aumm-site/07a_tokens.md` (E-D17 verified mainnet literals).
 *      Name / symbol: E-D18 (lower-camel `ixLongus` / uppercase `IXLONGUS`).
 *      Sector label: E-D19 ("US Fixed Income (long Treasury)" per manifest sector column).
 *      Salt: E-D20 (slot-derived `bytes32(uint256(11))`).
 *      Library shape: E-D21 (per-pool library + Bodensee-tier NatSpec).
 *      Initial swap fee: E-D22 (`0.0002e18` = 0.02%, governance-adjustable
 *      within OQ-11's revised 0.01%–0.30% band; per-pool `swapFeeManager` is `address(0)` — F-20/P-D40, defers to the Vault authorizer).
 *      Quality Gate: two ERC-4626 (`TokenType.WITH_RATE`) yield cores — svZCHF 26 + waEthUSDC 26 — sum to
 *      a 52% numerator (0.52e18); ixEDEL (16%) and TLTon (32%) are the two `TokenType.STANDARD` tokens.
 *      Clears `MIN_ERC4626_WEIGHT = 52e16` exactly at the gate boundary (margin +0 pp); the boundary case relies
 *      on the `>=` comparator in `AureumWeightedPoolFactory.create()` per E-D11.
 *      Ascending-address sort applied at literal-write time per Balancer V3 registration convention:
 *      TLTon (`0x9926…`), waEthUSDC (`0xD4fa…`), ixEDEL (`0xe4a1…`), svZCHF (`0xE5F1…`). No runtime sort.
 */
library IxLongusConfig {
    address internal constant TLTON         = 0x992651BFeB9A0DCC4457610E284ba66D86489d4d;
    address internal constant WAETHUSDC     = 0xD4fa2D31b7968E448877f69A96DE69f5de8cD23E;
    address internal constant IXEDEL         = 0xe4a10951f962e6cB93Cb843a4ef05d2F99DB1F94;
    address internal constant SVZCHF         = 0xE5F130253fF137f9917C0107659A4c5262abf6b0;

    address internal constant WAETHUSDC_RATE_PROVIDER = 0x8f4E8439b970363648421C692dd897Fb9c0Bd1D9;
    address internal constant SVZCHF_RATE_PROVIDER         = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;

    function config() internal pure returns (PoolConfig memory) {
        address[] memory tokens = new address[](4);
        tokens[0] = TLTON;
        tokens[1] = WAETHUSDC;
        tokens[2] = IXEDEL;
        tokens[3] = SVZCHF;

        TokenType[] memory tokenTypes = new TokenType[](4);
        tokenTypes[0] = TokenType.STANDARD;     // TLTon
        tokenTypes[1] = TokenType.WITH_RATE;    // waEthUSDC
        tokenTypes[2] = TokenType.STANDARD;     // ixEDEL
        tokenTypes[3] = TokenType.WITH_RATE;    // svZCHF

        IRateProvider[] memory rateProviders = new IRateProvider[](4);
        rateProviders[0] = IRateProvider(address(0));
        rateProviders[1] = IRateProvider(WAETHUSDC_RATE_PROVIDER);
        rateProviders[2] = IRateProvider(address(0));
        rateProviders[3] = IRateProvider(SVZCHF_RATE_PROVIDER);

        bool[] memory paysYieldFees = new bool[](4);
        paysYieldFees[0] = false;   // TLTon (STANDARD)
        paysYieldFees[1] = true;    // waEthUSDC (WITH_RATE + RP)
        paysYieldFees[2] = false;   // ixEDEL (STANDARD)
        paysYieldFees[3] = true;    // svZCHF (WITH_RATE + RP)

        uint256[] memory normalizedWeights = new uint256[](4);
        normalizedWeights[0] = 0.32e18;  // TLTon 32%
        normalizedWeights[1] = 0.26e18;  // waEthUSDC 26%
        normalizedWeights[2] = 0.16e18;  // ixEDEL 16%
        normalizedWeights[3] = 0.26e18;  // svZCHF 26%

        return PoolConfig({
            name: "ixLongus",
            symbol: "IXLONGUS",
            slot: 11,
            sectorLabel: "US Fixed Income (long Treasury)",
            tokens: tokens,
            tokenTypes: tokenTypes,
            rateProviders: rateProviders,
            paysYieldFees: paysYieldFees,
            normalizedWeights: normalizedWeights,
            swapFeePercentage: 0.0002e18,
            salt: bytes32(uint256(11))
        });
    }
}
