// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {FixedPoint} from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

/**
 * @title CCBScore — F-5 pure fixed-point score helper
 * @notice F-5: compound centrifugal balance score as tvlEMA × multiplier / FixedPoint.ONE.
 * @dev Per F-5 (`11_formulas.md`), OQ-22, F-4, F-8, and F-D2 (`STAGE_F_PLAN.md`).
 *      The fixed-point product divides by FixedPoint.ONE — so the score stays
 *      svZCHF-denominated at 18 decimals.
 */
library CCBScore {
    using FixedPoint for uint256;

    /**
     * @notice Computes the F-5 CCB score from TVL EMA and multiplier.
     * @dev Uses FixedPoint.mulDown — Balancer fixed-point multiply with floor rounding.
     * @param tvlEMA Per F-4 / OQ-22 — pool TVL exponential moving average (scaled units).
     * @param multiplier Per F-8 — protocol multiplier input (fixed-point scaled).
     * @return The score after `tvlEMA.mulDown(multiplier)` scaling.
     */
    function score(uint256 tvlEMA, uint256 multiplier) internal pure returns (uint256) {
        return tvlEMA.mulDown(multiplier);
    }
}
