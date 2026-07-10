// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title IxColossixConfig
 * @notice Five-asset Standard pool — BACon 16% + BLKon 16% + sUSDS 26% + ixEDEL 16% + svZCHF 26%.
 *         Sector: Financials.
 *
 * @dev Manifest row: `aumm-site/06_miliarium_manifest.md` (slot 23) — "ixColossix".
 *
 *      Composition lock: N-D0 build scope on the M-D5 Standard 26/26/16/16/16 template (svZCHF 26% / sUSDS 26% / ixEDEL 16% / BLKon 16% / BACon 16%).
 *      Token addresses + Rate Providers: `aumm-site/07a_tokens.md` (E-D17 verified mainnet literals).
 *      Name / symbol: E-D18 (lower-camel `ixColossix` / uppercase `IXCOLOSSIX`).
 *      Sector label: E-D19 ("Financials" per manifest sector column).
 *      Salt: E-D20 (slot-derived `bytes32(uint256(23))`).
 *      Library shape: E-D21 (per-pool library + Bodensee-tier NatSpec).
 *      Initial swap fee: E-D22 (`0.0002e18` = 0.02%, governance-adjustable
 *      within OQ-11's revised 0.01%–0.30% band; per-pool `swapFeeManager` is `address(0)` — F-20/P-D40, defers to the Vault authorizer).
 *      Quality Gate: two ERC-4626 (`TokenType.WITH_RATE`) yield cores — svZCHF 26 + sUSDS 26 — sum to
 *      a 52% numerator (0.52e18); BACon, BLKon, ixEDEL are the three `TokenType.STANDARD` tokens at 16% each.
 *      Clears `MIN_ERC4626_WEIGHT = 52e16` exactly at the gate boundary (margin +0 pp); the boundary case relies
 *      on the `>=` comparator in `AureumWeightedPoolFactory.create()` per E-D11.
 *      Ascending-address sort applied at literal-write time per Balancer V3 registration convention:
 *      BACon (`0x576E…`), BLKon (`0x7a0F…`), sUSDS (`0xa393…`), ixEDEL (`0xe4a1…`), svZCHF (`0xE5F1…`). No runtime sort.
 */
library IxColossixConfig {
    address internal constant BACON           = 0x576E9CA70e3a040c00d8139b0665a2b7b7B64844;
    address internal constant BLKON           = 0x7a0F89c1606f71499950AA2590d547c3975B728E;
    address internal constant SUSDS           = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address internal constant IXEDEL          = 0xe4a10951f962e6cB93Cb843a4ef05d2F99DB1F94;
    address internal constant SVZCHF          = 0xE5F130253fF137f9917C0107659A4c5262abf6b0;

    address internal constant SUSDS_RATE_PROVIDER  = 0x1195BE91e78ab25494C855826FF595Eef784d47B;
    address internal constant SVZCHF_RATE_PROVIDER = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;

    function config() internal pure returns (PoolConfig memory) {
        address[] memory tokens = new address[](5);
        tokens[0] = BACON;
        tokens[1] = BLKON;
        tokens[2] = SUSDS;
        tokens[3] = IXEDEL;
        tokens[4] = SVZCHF;

        TokenType[] memory tokenTypes = new TokenType[](5);
        tokenTypes[0] = TokenType.STANDARD;     // BACon
        tokenTypes[1] = TokenType.STANDARD;     // BLKon
        tokenTypes[2] = TokenType.WITH_RATE;    // sUSDS
        tokenTypes[3] = TokenType.STANDARD;     // ixEDEL
        tokenTypes[4] = TokenType.WITH_RATE;    // svZCHF

        IRateProvider[] memory rateProviders = new IRateProvider[](5);
        rateProviders[0] = IRateProvider(address(0));
        rateProviders[1] = IRateProvider(address(0));
        rateProviders[2] = IRateProvider(SUSDS_RATE_PROVIDER);
        rateProviders[3] = IRateProvider(address(0));
        rateProviders[4] = IRateProvider(SVZCHF_RATE_PROVIDER);

        bool[] memory paysYieldFees = new bool[](5);
        paysYieldFees[0] = false;   // BACon (STANDARD)
        paysYieldFees[1] = false;   // BLKon (STANDARD)
        paysYieldFees[2] = true;    // sUSDS (WITH_RATE + RP)
        paysYieldFees[3] = false;   // ixEDEL (STANDARD)
        paysYieldFees[4] = true;    // svZCHF (WITH_RATE + RP)

        uint256[] memory normalizedWeights = new uint256[](5);
        normalizedWeights[0] = 0.16e18;  // BACon 16%
        normalizedWeights[1] = 0.16e18;  // BLKon 16%
        normalizedWeights[2] = 0.26e18;  // sUSDS 26%
        normalizedWeights[3] = 0.16e18;  // ixEDEL 16%
        normalizedWeights[4] = 0.26e18;  // svZCHF 26%

        return PoolConfig({
            name: "ixColossix",
            symbol: "IXCOLOSSIX",
            slot: 23,
            sectorLabel: "Financials",
            tokens: tokens,
            tokenTypes: tokenTypes,
            rateProviders: rateProviders,
            paysYieldFees: paysYieldFees,
            normalizedWeights: normalizedWeights,
            swapFeePercentage: 0.0002e18,
            salt: bytes32(uint256(23))
        });
    }
}
