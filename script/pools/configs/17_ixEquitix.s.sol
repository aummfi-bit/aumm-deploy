// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title IxEquitixConfig
 * @notice Five-asset Standard pool — IVVon 16% + sUSDS 26% + ixEDEL 16% + svZCHF 26% + SPYon 16%.
 *         Sector: US Equities (Large Cap).
 *
 * @dev Manifest row: `aumm-site/06_miliarium_manifest.md` (slot 17) — "ixEquitix".
 *
 *      Composition lock: N-D0 build scope on the M-D5 Standard 26/26/16/16/16 template (svZCHF 26% / sUSDS 26% / ixEDEL 16% / SPYon 16% / IVVon 16%).
 *      Token addresses + Rate Providers: `aumm-site/07a_tokens.md` (E-D17 verified mainnet literals).
 *      Name / symbol: E-D18 (lower-camel `ixEquitix` / uppercase `IXEQUITIX`).
 *      Sector label: E-D19 ("US Equities (Large Cap)" per manifest sector column).
 *      Salt: E-D20 (slot-derived `bytes32(uint256(17))`).
 *      Library shape: E-D21 (per-pool library + Bodensee-tier NatSpec).
 *      Initial swap fee: E-D22 (`0.0002e18` = 0.02%, governance-adjustable
 *      within OQ-11's revised 0.01%–0.30% band; per-pool `swapFeeManager` is `governanceMultisig`).
 *      Quality Gate: two ERC-4626 (`TokenType.WITH_RATE`) yield cores — svZCHF 26 + sUSDS 26 — sum to
 *      a 52% numerator (0.52e18); IVVon, ixEDEL, SPYon are the three `TokenType.STANDARD` tokens at 16% each.
 *      Clears `MIN_ERC4626_WEIGHT = 52e16` exactly at the gate boundary (margin +0 pp); the boundary case relies
 *      on the `>=` comparator in `AureumWeightedPoolFactory.create()` per E-D11.
 *      Ascending-address sort applied at literal-write time per Balancer V3 registration convention:
 *      IVVon (`0x62cA…`), sUSDS (`0xa393…`), ixEDEL (`0xe4a1…`), svZCHF (`0xE5F1…`), SPYon (`0xFeDC…`). No runtime sort.
 */
library IxEquitixConfig {
    address internal constant IVVON           = 0x62cA254a363dc3c748e7E955c20447aB5bF06fF7;
    address internal constant SUSDS           = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address internal constant IXEDEL          = 0xe4a10951f962e6cB93Cb843a4ef05d2F99DB1F94;
    address internal constant SVZCHF          = 0xE5F130253fF137f9917C0107659A4c5262abf6b0;
    address internal constant SPYON           = 0xFeDC5f4a6c38211c1338aa411018DFAf26612c08;

    address internal constant SUSDS_RATE_PROVIDER  = 0x1195BE91e78ab25494C855826FF595Eef784d47B;
    address internal constant SVZCHF_RATE_PROVIDER = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;

    function config() internal pure returns (PoolConfig memory) {
        address[] memory tokens = new address[](5);
        tokens[0] = IVVON;
        tokens[1] = SUSDS;
        tokens[2] = IXEDEL;
        tokens[3] = SVZCHF;
        tokens[4] = SPYON;

        TokenType[] memory tokenTypes = new TokenType[](5);
        tokenTypes[0] = TokenType.STANDARD;     // IVVon
        tokenTypes[1] = TokenType.WITH_RATE;    // sUSDS
        tokenTypes[2] = TokenType.STANDARD;     // ixEDEL
        tokenTypes[3] = TokenType.WITH_RATE;    // svZCHF
        tokenTypes[4] = TokenType.STANDARD;     // SPYon

        IRateProvider[] memory rateProviders = new IRateProvider[](5);
        rateProviders[0] = IRateProvider(address(0));
        rateProviders[1] = IRateProvider(SUSDS_RATE_PROVIDER);
        rateProviders[2] = IRateProvider(address(0));
        rateProviders[3] = IRateProvider(SVZCHF_RATE_PROVIDER);
        rateProviders[4] = IRateProvider(address(0));

        bool[] memory paysYieldFees = new bool[](5);
        paysYieldFees[0] = false;   // IVVon (STANDARD)
        paysYieldFees[1] = true;    // sUSDS (WITH_RATE + RP)
        paysYieldFees[2] = false;   // ixEDEL (STANDARD)
        paysYieldFees[3] = true;    // svZCHF (WITH_RATE + RP)
        paysYieldFees[4] = false;   // SPYon (STANDARD)

        uint256[] memory normalizedWeights = new uint256[](5);
        normalizedWeights[0] = 0.16e18;  // IVVon 16%
        normalizedWeights[1] = 0.26e18;  // sUSDS 26%
        normalizedWeights[2] = 0.16e18;  // ixEDEL 16%
        normalizedWeights[3] = 0.26e18;  // svZCHF 26%
        normalizedWeights[4] = 0.16e18;  // SPYon 16%

        return PoolConfig({
            name: "ixEquitix",
            symbol: "IXEQUITIX",
            slot: 17,
            sectorLabel: "US Equities (Large Cap)",
            tokens: tokens,
            tokenTypes: tokenTypes,
            rateProviders: rateProviders,
            paysYieldFees: paysYieldFees,
            normalizedWeights: normalizedWeights,
            swapFeePercentage: 0.0002e18,
            salt: bytes32(uint256(17))
        });
    }
}
