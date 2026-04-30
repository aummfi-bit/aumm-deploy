// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FixedPoint} from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import {CCBScore} from "src/ccb/CCBScore.sol";

contract CCBScoreTest is Test {
    using FixedPoint for uint256;

    // --- F-5 identity ---

    function test_score_identity_fixedPointOne() public pure {
        // F-5: score(tvlEMA, FixedPoint.ONE) == tvlEMA.
        // mulDown(ONE) = tvlEMA * ONE / ONE = tvlEMA exactly.
        uint256 tvlEMA = 500e18;
        assertEq(CCBScore.score(tvlEMA, FixedPoint.ONE), tvlEMA);
    }

    // --- zero inputs ---

    function test_score_zeroMultiplier_returnsZero() public pure {
        // score(tvlEMA, 0) == 0 for any nonzero tvlEMA.
        assertEq(CCBScore.score(1000e18, 0), 0);
    }

    function test_score_zeroTvlEMA_returnsZero() public pure {
        // score(0, multiplier) == 0 for any multiplier.
        assertEq(CCBScore.score(0, FixedPoint.ONE), 0);
    }

    // --- mulDown rounding ---

    function test_score_mulDownTruncates() public pure {
        // mulDown floors: score(3, ONE + 1) = floor(3 * (1e18 + 1) / 1e18)
        // = floor(3 + 3/1e18) = 3. Confirms floor, not ceil.
        assertEq(CCBScore.score(3, FixedPoint.ONE + 1), 3);
    }

    // --- fuzz ---

    function testFuzz_score_matchesFixedPointMulDown(
        uint128 tvlEMA,
        uint128 multiplier
    ) public pure {
        // F-5 property: score == tvlEMA.mulDown(multiplier) for any uint128
        // inputs. uint128 bounds prevent overflow: uint128 * uint128 < 2^256.
        uint256 expected = uint256(tvlEMA).mulDown(uint256(multiplier));
        assertEq(CCBScore.score(tvlEMA, multiplier), expected);
    }
}
