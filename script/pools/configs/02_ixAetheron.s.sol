// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title IxAetheronConfig
 * @notice Five-asset Non-Standard pool — sfrxETH 28% + rETH 14% + weETH 14% + wOETH 28% + ixEDEL 16%.
 *         Sector: ETH Staking.
 *
 * @dev Manifest row: `aumm-site/06_miliarium_manifest.md` (slot 02) — "ixAetheron".
 *
 *      Composition lock: N-D8 native-4626 non-Lido ETH-staking basket (supersedes N-D1 composite leg).
 *      sfrxETH 28% / wOETH 28% / ixEDEL 16% / rETH 14% / weETH 14%.
 *      Token addresses + Rate Providers: `aumm-site/07a_tokens.md` (E-D17 verified mainnet literals).
 *      RP threading (N-D7): sfrxETH and wOETH yield cores use the Aureum-deployed `ERC4626RateProvider` (N3.1) —
 *      no mainnet address exists for either, so they are injected as the `sfrxEthRp` / `wOethRp` parameters
 *      (config stays `pure`) and resolved from the `SFRXETH_RATE_PROVIDER` / `WOETH_RATE_PROVIDER` env vars by
 *      `DeployIxAetheron._config()`. rETH's RP is the verified mainnet literal below; weETH is its own rate provider.
 *      Name / symbol: E-D18 (lower-camel `ixAetheron` / uppercase `IXAETHERON`).
 *      Sector label: E-D19 ("ETH Staking" per manifest sector column).
 *      Salt: E-D20 (slot-derived `bytes32(uint256(2))`).
 *      Library shape: E-D21 (per-pool library + Bodensee-tier NatSpec).
 *      Initial swap fee: E-D22 (`0.0002e18` = 0.02%, governance-adjustable
 *      within OQ-11's revised 0.01%–0.30% band; per-pool `swapFeeManager` is `address(0)` — F-20/P-D40, defers to the Vault authorizer).
 *      Quality Gate: two admitted ERC-4626 (`TokenType.WITH_RATE`) yield cores — sfrxETH 28 + wOETH 28 — sum to
 *      a 56% numerator (0.56e18); rETH and weETH bind as `TokenType.WITH_RATE` plain ERC-20 LST legs (oracle-free
 *      RPs but non-ERC-4626 → 0 to the numerator); ixEDEL is `TokenType.STANDARD` at 16%.
 *      Clears `MIN_ERC4626_WEIGHT = 52e16` with a +4pp margin.
 *      Ascending-address sort applied at literal-write time per Balancer V3 registration convention:
 *      sfrxETH (`0xac3E…`), rETH (`0xae78…`), weETH (`0xCd5f…`), wOETH (`0xDcEe…`), ixEDEL (`0xe4a1…`). No runtime sort.
 */
library IxAetheronConfig {
    address internal constant SFRXETH         = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address internal constant RETH            = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address internal constant WEETH           = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant WOETH           = 0xDcEe70654261AF21C44c093C300eD3Bb97b78192;
    address internal constant IXEDEL          = 0xe4a10951f962e6cB93Cb843a4ef05d2F99DB1F94;

    address internal constant RETH_RATE_PROVIDER  = 0x1a8F81c256aee9C640e14bB0453ce247ea0DFE6F;
    address internal constant WEETH_RATE_PROVIDER = WEETH;

    function config(address sfrxEthRp, address wOethRp) internal pure returns (PoolConfig memory) {
        address[] memory tokens = new address[](5);
        tokens[0] = SFRXETH;
        tokens[1] = RETH;
        tokens[2] = WEETH;
        tokens[3] = WOETH;
        tokens[4] = IXEDEL;

        TokenType[] memory tokenTypes = new TokenType[](5);
        tokenTypes[0] = TokenType.WITH_RATE;    // sfrxETH
        tokenTypes[1] = TokenType.WITH_RATE;    // rETH
        tokenTypes[2] = TokenType.WITH_RATE;    // weETH
        tokenTypes[3] = TokenType.WITH_RATE;    // wOETH
        tokenTypes[4] = TokenType.STANDARD;     // ixEDEL

        IRateProvider[] memory rateProviders = new IRateProvider[](5);
        rateProviders[0] = IRateProvider(sfrxEthRp);
        rateProviders[1] = IRateProvider(RETH_RATE_PROVIDER);
        rateProviders[2] = IRateProvider(WEETH_RATE_PROVIDER);
        rateProviders[3] = IRateProvider(wOethRp);
        rateProviders[4] = IRateProvider(address(0));

        bool[] memory paysYieldFees = new bool[](5);
        paysYieldFees[0] = true;    // sfrxETH (WITH_RATE + RP)
        paysYieldFees[1] = true;    // rETH (WITH_RATE + RP)
        paysYieldFees[2] = true;    // weETH (WITH_RATE + RP)
        paysYieldFees[3] = true;    // wOETH (WITH_RATE + RP)
        paysYieldFees[4] = false;   // ixEDEL (STANDARD)

        uint256[] memory normalizedWeights = new uint256[](5);
        normalizedWeights[0] = 0.28e18;  // sfrxETH 28%
        normalizedWeights[1] = 0.14e18;  // rETH 14%
        normalizedWeights[2] = 0.14e18;  // weETH 14%
        normalizedWeights[3] = 0.28e18;  // wOETH 28%
        normalizedWeights[4] = 0.16e18;  // ixEDEL 16%

        return PoolConfig({
            name: "ixAetheron",
            symbol: "IXAETHERON",
            slot: 2,
            sectorLabel: "ETH Staking",
            tokens: tokens,
            tokenTypes: tokenTypes,
            rateProviders: rateProviders,
            paysYieldFees: paysYieldFees,
            normalizedWeights: normalizedWeights,
            swapFeePercentage: 0.0002e18,
            salt: bytes32(uint256(2))
        });
    }
}
