// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

/**
 * @title ERC4626RateProvider
 * @notice Aureum-owned `IRateProvider` for an ERC-4626 yield vault. `getRate()` returns
 *         `wrappedToken.previewRedeem(FixedPoint.ONE)` — the assets returned for redeeming one full
 *         (1e18) share, an 18-decimal fixed-point rate that rounds down via the vault's `convertToAssets`.
 *
 * @dev N-D2 (`docs/STAGE_N_NOTES.md`): a faithful re-implementation of the Balancer submodule pattern
 *      `lib/balancer-v3-monorepo/pkg/vault/contracts/test/ERC4626RateProvider.sol`, re-authored under
 *      `src/` rather than edited in place — CLAUDE.md §8c keeps the Balancer tree byte-identical to
 *      audited source. Deployed for the ERC-4626 yield cores whose `07a_tokens.md` Rate-Provider column
 *      is absent: scrvUSD (ixLibertas 06, N-D2); sfrxETH + wOETH (ixAetheron 02, N-D8 — native
 *      ETH-staking 4626 cores); and yBOLD (the inner hop of the ysyBOLD `CompositeRateProvider`, shared
 *      across ixLibertas 06 / ixMagnix 20 / ixAurix 27, N-D9 — yBOLD → BOLD). The original N-D2 sfrxUSD
 *      leg was superseded by N-D9: sfrxUSD's mainnet `previewRedeem` returns zero post-Fraxtal migration,
 *      so ysyBOLD replaces it, rated via a `CompositeRateProvider` over this provider rather than directly.
 *      Each instance's address threads into the config libs + N6 fork fixture by env-var injection per N-D7.
 *
 *      F-11 (`docs/white_hat/AUREUM_WHITEHAT_OUTPUT.md`, WN whitehat pass): the constructor enforces
 *      18-decimal shares AND an 18-decimal underlying asset, failing closed otherwise. `getRate()` returns
 *      `previewRedeem(1e18)` with no decimal scaling — a faithful Balancer-pattern rate for an 18/18 vault,
 *      but a silent under- or over-statement for any other decimal pairing that would still clear the
 *      deploy-time `getRate() > 0` gate (the gate the N-D9 sfrxUSD zero-rate bug was caught by — it checks
 *      liveness, not scale). All five current consumers are 18/18; the guard is forward-looking
 *      defense-in-depth, not a fix to a live bug.
 *
 *      One immutable (`wrappedToken`), zero admin, zero storage, no upgrade path — the minimal reviewable
 *      surface (CLAUDE.md §1), WN whitehat-reviewed at N7 (N-D6). `previewRedeem` rounds DOWN per EIP-4626,
 *      so the reported rate is conservative (never over-stated), matching the submodule's rounding posture.
 */
contract ERC4626RateProvider is IRateProvider {
    /// @notice Thrown when the wrapped vault's share decimals are not 18 (F-11).
    error InvalidShareDecimals(uint8 actual);

    /// @notice Thrown when the wrapped vault's underlying asset decimals are not 18 (F-11).
    error InvalidAssetDecimals(uint8 actual);

    /// @notice The ERC-4626 vault whose one-share redemption value this provider reports.
    IERC4626 public immutable wrappedToken;

    /// @param wrappedToken_ The ERC-4626 yield vault (18-decimal shares + 18-decimal asset only, F-11;
    ///        e.g. scrvUSD, sfrxETH, wOETH, yBOLD).
    constructor(IERC4626 wrappedToken_) {
        uint8 shareDecimals = wrappedToken_.decimals();
        if (shareDecimals != 18) revert InvalidShareDecimals(shareDecimals);
        uint8 assetDecimals = IERC20Metadata(wrappedToken_.asset()).decimals();
        if (assetDecimals != 18) revert InvalidAssetDecimals(assetDecimals);
        wrappedToken = wrappedToken_;
    }

    /// @inheritdoc IRateProvider
    function getRate() external view override returns (uint256) {
        // `previewRedeem` calls `convertToAssets`, rounding down (EIP-4626).
        return wrappedToken.previewRedeem(FixedPoint.ONE);
    }
}
