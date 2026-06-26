// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

/**
 * @title CompositeRateProvider
 * @notice Aureum-owned `IRateProvider` for an ERC-4626 wrapper over a rate-bearing underlying (a two-hop
 *         exchange rate). `getRate()` returns
 *         `wrapper.previewRedeem(FixedPoint.ONE).mulDown(underlyingRateProvider.getRate())` — composing the
 *         wrapper-share→underlying rate (round-down `convertToAssets`, EIP-4626) with the underlying's own
 *         rate, both 18-decimal fixed point, into a single composed wrapper-share rate.
 *
 * @dev N-D9 (`docs/STAGE_N_NOTES.md`): the live consumer — the ysyBOLD yield core shared by ixLibertas (06),
 *      ixMagnix (20) and ixAurix (27). Deployed as `CompositeRateProvider(ysyBOLD, ERC4626RateProvider(yBOLD))`:
 *      hop 1 is ysyBOLD-share → yBOLD (this contract's `wrapper.previewRedeem`, the Yearn staked-yBOLD
 *      `convertToAssets`); hop 2 is yBOLD → BOLD (the inner `ERC4626RateProvider`'s `previewRedeem`). The
 *      composite replaces the dead-rate `ERC4626RateProvider(sfrxUSD)`, whose mainnet `previewRedeem` returns
 *      zero post-Fraxtal migration (the N6 RP-watch). Its address threads into the 06/20/27 config libs + the
 *      N6 fork fixture by env-var injection per N-D7.
 *
 *      N-D1 (the M-D11 composite-RP restoration for ixAetheron slot 02 — waEthrETH / waEthweETH stataToken
 *      wrappers over LSTs, reconstructed as wrapper-shares → underlying-LST → ETH) was the original motivating
 *      design but was superseded before deployment: ixAetheron now resolves sfrxETH / wOETH via plain
 *      `ERC4626RateProvider` instances, so N-D9 is this contract's first real consumer. The fWSTETH composite
 *      precedent (`03_ixCasper.s.sol`, `0x8Be2` × `0x72D07D`) still stands as the pattern reference.
 *      Re-authored under `src/`, never a submodule edit (CLAUDE.md §8c).
 *
 *      Two immutables (`wrapper`, `underlyingRateProvider`), zero admin, zero storage, no upgrade path — the
 *      minimal reviewable surface (CLAUDE.md §1), WN whitehat-reviewed at N7 (N-D6). Both hops round DOWN
 *      (`previewRedeem`'s `convertToAssets` + `mulDown`), so the composed rate is conservative
 *      (never over-stated); a zero or reverting `underlyingRateProvider.getRate()` propagates (zero rate or
 *      revert), never silently substitutes a default.
 */
contract CompositeRateProvider is IRateProvider {
    using FixedPoint for uint256;

    /// @notice The ERC-4626 wrapper whose one-share redemption value is the first hop.
    IERC4626 public immutable wrapper;

    /// @notice The rate provider for the wrapper's underlying asset (underlying → ETH), the second hop.
    IRateProvider public immutable underlyingRateProvider;

    /// @param wrapper_ The ERC-4626 wrapper (e.g. waEthrETH, waEthweETH).
    /// @param underlyingRateProvider_ The underlying asset's rate provider (e.g. Rocket Pool rETH RP, Aave weETH oracle).
    constructor(IERC4626 wrapper_, IRateProvider underlyingRateProvider_) {
        wrapper = wrapper_;
        underlyingRateProvider = underlyingRateProvider_;
    }

    /// @inheritdoc IRateProvider
    function getRate() external view override returns (uint256) {
        // First hop: wrapper share → underlying (previewRedeem → convertToAssets, rounds down, EIP-4626).
        // Second hop: underlying → ETH (underlyingRateProvider.getRate()). Composed via FixedPoint mulDown.
        return wrapper.previewRedeem(FixedPoint.ONE).mulDown(underlyingRateProvider.getRate());
    }
}
