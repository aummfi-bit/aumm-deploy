// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title IxHelvetiaConfig
 * @notice Per-pool config library for ixHelvetia (Miliarium slot 01).
 *         Two-asset 100% ERC-4626 yield pool — svZCHF 80% + sUSDS 20%.
 *         Sector: Frankencoin MMA.
 *
 * @dev Manifest row: `aumm-site/06_miliarium_manifest.md` §xiii — "ixHelvetia".
 *
 *      Composition lock: `docs/STAGE_E_PLAN.md` E-D4 (svZCHF 80% / sUSDS 20%, 100% ERC-4626).
 *      Token addresses + Rate Providers: `docs/STAGE_E_NOTES.md` E-D17 (mainnet vault literals).
 *      Name / symbol: `docs/STAGE_E_NOTES.md` E-D18 (lower-camel `ixHelvetia` / uppercase `IXHELVETIA`).
 *      Sector label: `docs/STAGE_E_NOTES.md` E-D19 ("Frankencoin MMA" per manifest §xiii column "Sector").
 *      Salt: `docs/STAGE_E_NOTES.md` E-D20 (slot-derived `bytes32(uint256(1))`).
 *      Library shape: `docs/STAGE_E_NOTES.md` E-D21 (per-pool library + Bodensee-tier NatSpec).
 *      Initial swap fee: `docs/STAGE_E_NOTES.md` E-D22 (`0.0002e18` = 0.02%, governance-adjustable
 *      within OQ-11's revised 0.01%–0.30% band; per-pool `swapFeeManager` is `address(0)` — F-20/P-D40, defers to the Vault authorizer).
 *
 *      Quality Gate: 100% ERC-4626 — both tokens are `TokenType.WITH_RATE` with non-zero Rate Providers,
 *      so the QG sum is `1e18` and clears `MIN_ERC4626_WEIGHT = 52e16` with margin +48 pp.
 *
 *      Ascending-address sort applied at literal-write time per Balancer V3 registration convention:
 *      sUSDS (`0xa393…`) precedes svZCHF (`0xE5F1…`), so index 0 = sUSDS, index 1 = svZCHF. No runtime sort.
 */
library IxHelvetiaConfig {
    address internal constant SUSDS  = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address internal constant SVZCHF = 0xE5F130253fF137f9917C0107659A4c5262abf6b0;

    address internal constant SUSDS_RATE_PROVIDER  = 0x1195BE91e78ab25494C855826FF595Eef784d47B;
    address internal constant SVZCHF_RATE_PROVIDER = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;

    function config() internal pure returns (PoolConfig memory) {
        address[] memory tokens = new address[](2);
        tokens[0] = SUSDS;
        tokens[1] = SVZCHF;

        TokenType[] memory tokenTypes = new TokenType[](2);
        tokenTypes[0] = TokenType.WITH_RATE;
        tokenTypes[1] = TokenType.WITH_RATE;

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[0] = IRateProvider(SUSDS_RATE_PROVIDER);
        rateProviders[1] = IRateProvider(SVZCHF_RATE_PROVIDER);

        bool[] memory paysYieldFees = new bool[](2);
        paysYieldFees[0] = true;
        paysYieldFees[1] = true;

        uint256[] memory normalizedWeights = new uint256[](2);
        normalizedWeights[0] = 0.2e18;  // sUSDS 20%
        normalizedWeights[1] = 0.8e18;  // svZCHF 80%

        return PoolConfig({
            name: "ixHelvetia",
            symbol: "IXHELVETIA",
            slot: 1,
            sectorLabel: "Frankencoin MMA",
            tokens: tokens,
            tokenTypes: tokenTypes,
            rateProviders: rateProviders,
            paysYieldFees: paysYieldFees,
            normalizedWeights: normalizedWeights,
            swapFeePercentage: 0.0002e18,
            salt: bytes32(uint256(1))
        });
    }
}
