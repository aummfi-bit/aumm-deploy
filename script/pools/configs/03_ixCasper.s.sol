// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title IxCasperConfig
 * @notice Five-asset Standard pool — fWSTETH 26% + waEthwstETH 16% + fWETH 26% + ixEDEL 16% + svZCHF 16%.
 *         Sector: LST / Staking Derivatives.
 *
 * @dev Manifest row: `aumm-site/06_miliarium_manifest.md` (slot 03) — "ixCasper".
 *
 *      Composition lock: M-D5 Standard 26/26/16/16/16 template (fWSTETH 26% / fWETH 26% / ixEDEL 16% / waEthwstETH 16% / svZCHF 16%); the waEthwstETH leg is restored per PB-D8.
 *      Token addresses + Rate Providers: `aumm-site/07a_tokens.md` (E-D17 verified mainnet literals); the waEthwstETH RP is the Aureum-deployed composite per PB-D8 (env-injected, no mainnet address).
 *      Name / symbol: E-D18 (lower-camel `ixCasper` / uppercase `IXCASPER`).
 *      Sector label: E-D19 ("LST / Staking Derivatives" per manifest sector column).
 *      Salt: E-D20 (slot-derived `bytes32(uint256(3))`).
 *      Library shape: E-D21 (per-pool library + Bodensee-tier NatSpec).
 *      Initial swap fee: E-D22 (`0.0002e18` = 0.02%, governance-adjustable
 *      within OQ-11's revised 0.01%–0.30% band; per-pool `swapFeeManager` is `address(0)` — F-20/P-D40, defers to the Vault authorizer).
 *      Quality Gate: four ERC-4626 (`TokenType.WITH_RATE` + `convertToAssets`) tokens sum to an 84% numerator
 *      (fWSTETH 26 + fWETH 26 + waEthwstETH 16 + svZCHF 16 = 0.84e18); ixEDEL (16%, `TokenType.STANDARD`) does not
 *      count toward the numerator. Clears `MIN_ERC4626_WEIGHT = 52e16` with a +32pp margin.
 *      waEthwstETH binding: PB-D8 — the slot-03 16% theme leg restores the M-D8-canonical Aave V3 stataToken
 *      wrapper waEthwstETH (`0x322AA5F5Be95644d6c36544B6c5061F072D16DF5`), rated via an Aureum-deployed
 *      `CompositeRateProvider(IERC4626(waEthwstETH), IRateProvider(0x72D07D7DcA67b8A406aD1Ec34ce969c90bFEE768))` —
 *      hop 1 `previewRedeem(1e18)` (wrapper share → wstETH), hop 2 the canonical Balancer wstETH RP
 *      (`stEthPerToken`, wstETH → ETH); composed rate ≈ 1.2410e18 (fork-verified 2026-07-12). Supersedes the M-D11
 *      plain-wstETH stopgap (`0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0` + RP `0x72D07D…`), which amended M-D8
 *      when the direct Aave stataToken RP `0xe1D97bF61901B075E9626c8A2340a7De385861Ef` reverted on `getRate()`
 *      (the M-D7 Aave-static-wrapper anomaly class — still reverts as of PB-D8). The composite has no mainnet
 *      address, so it is injected as the `waEthwstEthCompositeRp` parameter (config stays `pure`) and resolved from
 *      the `WAETHWSTETH_COMPOSITE_RATE_PROVIDER` env var by `DeployIxCasper._config()` per N-D7; the N-D9 ysyBOLD
 *      composite stack is the pattern precedent. The leg stays `TokenType.WITH_RATE` + `paysYieldFees = true` —
 *      50%-to-Bodensee yield-skim over both the wstETH staking layer and the now-realizable Aave supply layer.
 *      Ascending-address sort applied at literal-write time per Balancer V3 registration convention:
 *      fWSTETH (`0x2411…`), waEthwstETH (`0x322A…`), fWETH (`0x9055…`), ixEDEL (`0xe4a1…`), svZCHF (`0xE5F1…`). No runtime sort.
 */
library IxCasperConfig {
    address internal constant FWSTETH      = 0x2411802D8BEA09be0aF8fD8D08314a63e706b29C;
    address internal constant WAETHWSTETH  = 0x322AA5F5Be95644d6c36544B6c5061F072D16DF5;
    address internal constant FWETH        = 0x90551c1795392094FE6D29B758EcCD233cFAa260;
    address internal constant IXEDEL       = 0xe4a10951f962e6cB93Cb843a4ef05d2F99DB1F94;
    address internal constant SVZCHF       = 0xE5F130253fF137f9917C0107659A4c5262abf6b0;

    address internal constant FWSTETH_RATE_PROVIDER = 0x8Be2e3D4b85d05cac2dBbAC6c42798fb342aef45;
    address internal constant FWETH_RATE_PROVIDER   = 0x8fC43e76874CaE40939eDeB90E5683258B63c508;
    address internal constant SVZCHF_RATE_PROVIDER  = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;

    function config(address waEthwstEthCompositeRp) internal pure returns (PoolConfig memory) {
        address[] memory tokens = new address[](5);
        tokens[0] = FWSTETH;
        tokens[1] = WAETHWSTETH;
        tokens[2] = FWETH;
        tokens[3] = IXEDEL;
        tokens[4] = SVZCHF;

        TokenType[] memory tokenTypes = new TokenType[](5);
        tokenTypes[0] = TokenType.WITH_RATE;    // fWSTETH
        tokenTypes[1] = TokenType.WITH_RATE;    // waEthwstETH
        tokenTypes[2] = TokenType.WITH_RATE;    // fWETH
        tokenTypes[3] = TokenType.STANDARD;     // ixEDEL
        tokenTypes[4] = TokenType.WITH_RATE;    // svZCHF

        IRateProvider[] memory rateProviders = new IRateProvider[](5);
        rateProviders[0] = IRateProvider(FWSTETH_RATE_PROVIDER);
        rateProviders[1] = IRateProvider(waEthwstEthCompositeRp);
        rateProviders[2] = IRateProvider(FWETH_RATE_PROVIDER);
        rateProviders[3] = IRateProvider(address(0));
        rateProviders[4] = IRateProvider(SVZCHF_RATE_PROVIDER);

        bool[] memory paysYieldFees = new bool[](5);
        paysYieldFees[0] = true;    // fWSTETH (WITH_RATE + RP)
        paysYieldFees[1] = true;    // waEthwstETH (WITH_RATE + RP)
        paysYieldFees[2] = true;    // fWETH (WITH_RATE + RP)
        paysYieldFees[3] = false;   // ixEDEL (STANDARD)
        paysYieldFees[4] = true;    // svZCHF (WITH_RATE + RP)

        uint256[] memory normalizedWeights = new uint256[](5);
        normalizedWeights[0] = 0.26e18;  // fWSTETH 26%
        normalizedWeights[1] = 0.16e18;  // waEthwstETH 16%
        normalizedWeights[2] = 0.26e18;  // fWETH 26%
        normalizedWeights[3] = 0.16e18;  // ixEDEL 16%
        normalizedWeights[4] = 0.16e18;  // svZCHF 16%

        return PoolConfig({
            name: "ixCasper",
            symbol: "IXCASPER",
            slot: 3,
            sectorLabel: "LST / Staking Derivatives",
            tokens: tokens,
            tokenTypes: tokenTypes,
            rateProviders: rateProviders,
            paysYieldFees: paysYieldFees,
            normalizedWeights: normalizedWeights,
            swapFeePercentage: 0.0002e18,
            salt: bytes32(uint256(3))
        });
    }
}
