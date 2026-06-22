// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title IxDebitumConfig
 * @notice Five-asset Standard pool — Morpho 16% + sUSDS 26% + SPK 16% + ixEDEL 16% + svZCHF 26%.
 *         Sector: DeFi Lending Infra.
 *
 * @dev Manifest row: `aumm-site/06_miliarium_manifest.md` (slot 16) — "ixDebitum".
 *
 *      Composition lock: N-D0 build scope on the M-D5 Standard 26/26/16/16/16 template (svZCHF 26% / sUSDS 26% / ixEDEL 16% / Morpho 16% / SPK 16%).
 *      Token addresses + Rate Providers: `aumm-site/07a_tokens.md` (E-D17 verified mainnet literals).
 *      Name / symbol: E-D18 (lower-camel `ixDebitum` / uppercase `IXDEBITUM`).
 *      Sector label: E-D19 ("DeFi Lending Infra" per manifest sector column).
 *      Salt: E-D20 (slot-derived `bytes32(uint256(16))`).
 *      Library shape: E-D21 (per-pool library + Bodensee-tier NatSpec).
 *      Initial swap fee: E-D22 (`0.0002e18` = 0.02%, governance-adjustable
 *      within OQ-11's revised 0.01%–0.30% band; per-pool `swapFeeManager` is `governanceMultisig`).
 *      Quality Gate: two ERC-4626 (`TokenType.WITH_RATE`) yield cores — svZCHF 26 + sUSDS 26 — sum to
 *      a 52% numerator (0.52e18); Morpho, SPK, ixEDEL are the three `TokenType.STANDARD` tokens at 16% each.
 *      Clears `MIN_ERC4626_WEIGHT = 52e16` exactly at the gate boundary (margin +0 pp); the boundary case relies
 *      on the `>=` comparator in `AureumWeightedPoolFactory.create()` per E-D11.
 *      Ascending-address sort applied at literal-write time per Balancer V3 registration convention:
 *      Morpho (`0x58D9…`), sUSDS (`0xa393…`), SPK (`0xc200…`), ixEDEL (`0xe4a1…`), svZCHF (`0xE5F1…`). No runtime sort.
 */
library IxDebitumConfig {
    address internal constant MORPHO          = 0x58D97B57BB95320F9a05dC918Aef65434969c2B2;
    address internal constant SUSDS           = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address internal constant SPK             = 0xc20059e0317DE91738d13af027DfC4a50781b066;
    address internal constant IXEDEL          = 0xe4a10951f962e6cB93Cb843a4ef05d2F99DB1F94;
    address internal constant SVZCHF          = 0xE5F130253fF137f9917C0107659A4c5262abf6b0;

    address internal constant SUSDS_RATE_PROVIDER  = 0x1195BE91e78ab25494C855826FF595Eef784d47B;
    address internal constant SVZCHF_RATE_PROVIDER = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;

    function config() internal pure returns (PoolConfig memory) {
        address[] memory tokens = new address[](5);
        tokens[0] = MORPHO;
        tokens[1] = SUSDS;
        tokens[2] = SPK;
        tokens[3] = IXEDEL;
        tokens[4] = SVZCHF;

        TokenType[] memory tokenTypes = new TokenType[](5);
        tokenTypes[0] = TokenType.STANDARD;     // Morpho
        tokenTypes[1] = TokenType.WITH_RATE;    // sUSDS
        tokenTypes[2] = TokenType.STANDARD;     // SPK
        tokenTypes[3] = TokenType.STANDARD;     // ixEDEL
        tokenTypes[4] = TokenType.WITH_RATE;    // svZCHF

        IRateProvider[] memory rateProviders = new IRateProvider[](5);
        rateProviders[0] = IRateProvider(address(0));
        rateProviders[1] = IRateProvider(SUSDS_RATE_PROVIDER);
        rateProviders[2] = IRateProvider(address(0));
        rateProviders[3] = IRateProvider(address(0));
        rateProviders[4] = IRateProvider(SVZCHF_RATE_PROVIDER);

        bool[] memory paysYieldFees = new bool[](5);
        paysYieldFees[0] = false;   // Morpho (STANDARD)
        paysYieldFees[1] = true;    // sUSDS (WITH_RATE + RP)
        paysYieldFees[2] = false;   // SPK (STANDARD)
        paysYieldFees[3] = false;   // ixEDEL (STANDARD)
        paysYieldFees[4] = true;    // svZCHF (WITH_RATE + RP)

        uint256[] memory normalizedWeights = new uint256[](5);
        normalizedWeights[0] = 0.16e18;  // Morpho 16%
        normalizedWeights[1] = 0.26e18;  // sUSDS 26%
        normalizedWeights[2] = 0.16e18;  // SPK 16%
        normalizedWeights[3] = 0.16e18;  // ixEDEL 16%
        normalizedWeights[4] = 0.26e18;  // svZCHF 26%

        return PoolConfig({
            name: "ixDebitum",
            symbol: "IXDEBITUM",
            slot: 16,
            sectorLabel: "DeFi Lending Infra",
            tokens: tokens,
            tokenTypes: tokenTypes,
            rateProviders: rateProviders,
            paysYieldFees: paysYieldFees,
            normalizedWeights: normalizedWeights,
            swapFeePercentage: 0.0002e18,
            salt: bytes32(uint256(16))
        });
    }
}
