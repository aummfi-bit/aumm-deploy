// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {FixedPoint} from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

/**
 * @title CCBShare — F-6 pure fixed-point share normalizer
 * @notice F-6 normalizes per-pool scores to fractional shares summing to FixedPoint.ONE.
 * @dev Per F-6 (`11_formulas.md`) and F-D10 (`STAGE_F_PLAN.md`). The sum of returned
 *      shares may be marginally below FixedPoint.ONE due to divDown floor rounding per index.
 */
library CCBShare {
    using FixedPoint for uint256;

    error EmptyScores();
    error AllScoresZero();

    /**
     * @notice Converts a score vector into fixed-point shares that partition unity.
     * @dev Reverts `EmptyScores()` if `scores.length == 0`. Reverts `AllScoresZero()` if the
     *      sum of scores is zero.
     * @param scores Per-pool compound centrifugal balance scores (same unit as F-5 output).
     * @return result Share per index; each entry is `scores[i].divDown(total)` where `total` is the sum of `scores`.
     */
    function shares(uint256[] memory scores) internal pure returns (uint256[] memory result) {
        uint256 len = scores.length;
        if (len == 0) {
            revert EmptyScores();
        }

        uint256 total = 0;
        for (uint256 i = 0; i < len; ++i) {
            total += scores[i];
        }
        if (total == 0) {
            revert AllScoresZero();
        }

        result = new uint256[](len);
        for (uint256 j = 0; j < len; ++j) {
            result[j] = scores[j].divDown(total);
        }
    }
}
