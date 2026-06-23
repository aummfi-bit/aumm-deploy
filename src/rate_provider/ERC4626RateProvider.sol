// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

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
 *      audited source. Deployed for the two QG-critical ERC-4626 yield cores whose `07a_tokens.md`
 *      Rate-Provider column is absent: scrvUSD (ixLibertas 06) and sfrxUSD (ixLibertas 06 + ixMagnix 20
 *      + ixAurix 27, one shared instance per N-D2). Its address threads into the config libs + N6 fork
 *      fixture by env-var injection per N-D7.
 *
 *      One immutable (`wrappedToken`), zero admin, zero storage, no upgrade path — the minimal reviewable
 *      surface (CLAUDE.md §1), WN whitehat-reviewed at N7 (N-D6). `previewRedeem` rounds DOWN per EIP-4626,
 *      so the reported rate is conservative (never over-stated), matching the submodule's rounding posture.
 */
contract ERC4626RateProvider is IRateProvider {
    /// @notice The ERC-4626 vault whose one-share redemption value this provider reports.
    IERC4626 public immutable wrappedToken;

    /// @param wrappedToken_ The ERC-4626 yield vault (e.g. scrvUSD, sfrxUSD).
    constructor(IERC4626 wrappedToken_) {
        wrappedToken = wrappedToken_;
    }

    /// @inheritdoc IRateProvider
    function getRate() external view override returns (uint256) {
        // `previewRedeem` calls `convertToAssets`, rounding down (EIP-4626).
        return wrappedToken.previewRedeem(FixedPoint.ONE);
    }
}
