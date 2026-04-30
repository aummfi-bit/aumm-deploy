// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FixedPoint} from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import {CCBShare} from "src/ccb/CCBShare.sol";

contract CCBShareTest is Test {
    using FixedPoint for uint256;

    // --- internal-pure call boundary ---
    //
    // CCBShare.shares is `internal pure` per F-D10; internal calls inline into
    // the caller, so vm.expectRevert cannot catch reverts at the test-function
    // depth. Routing revert tests through this external wrapper creates the
    // call frame the cheatcode needs.
    function _sharesExt(uint256[] memory scores) external pure returns (uint256[] memory) {
        return CCBShare.shares(scores);
    }

    // --- reverts ---

    function test_shares_emptyArray_reverts() public {
        uint256[] memory empty = new uint256[](0);
        vm.expectRevert(CCBShare.EmptyScores.selector);
        this._sharesExt(empty);
    }

    function test_shares_allZeroScores_reverts() public {
        uint256[] memory zeros = new uint256[](3);
        vm.expectRevert(CCBShare.AllScoresZero.selector);
        this._sharesExt(zeros);
    }

    // --- identity / basic ---

    function test_shares_singleNonZero_returnsFixedPointOne() public pure {
        uint256[] memory scores = new uint256[](1);
        scores[0] = 1234e18;
        uint256[] memory result = CCBShare.shares(scores);
        assertEq(result.length, 1);
        assertEq(result[0], FixedPoint.ONE);
    }

    function test_shares_twoEqualScores_returnsHalfHalf() public pure {
        uint256[] memory scores = new uint256[](2);
        scores[0] = 100e18;
        scores[1] = 100e18;
        uint256[] memory result = CCBShare.shares(scores);
        // Even total: exact half each (0.5e18 per entry).
        assertEq(result[0], FixedPoint.ONE / 2);
        assertEq(result[1], FixedPoint.ONE / 2);
    }

    function test_shares_oneNonZero_othersZero_concentratedShare() public pure {
        uint256[] memory scores = new uint256[](3);
        scores[1] = 100e18;
        uint256[] memory result = CCBShare.shares(scores);
        assertEq(result[0], 0);
        assertEq(result[1], FixedPoint.ONE);
        assertEq(result[2], 0);
    }

    function test_shares_asymmetric_proportional() public pure {
        uint256[] memory scores = new uint256[](2);
        scores[0] = 1;
        scores[1] = 2;
        uint256[] memory result = CCBShare.shares(scores);
        assertEq(result[0], uint256(1).divDown(3));
        assertEq(result[1], uint256(2).divDown(3));
        assertEq(result[0] + result[1], FixedPoint.ONE - 1);
    }

    // --- divDown rounding (sum residual) ---

    function test_shares_sumLessOrEqualOne_threeEqual() public pure {
        uint256[] memory scores = new uint256[](3);
        scores[0] = 1;
        scores[1] = 1;
        scores[2] = 1;
        uint256[] memory result = CCBShare.shares(scores);
        uint256 oneThird = uint256(1).divDown(3);
        assertEq(result[0], oneThird);
        assertEq(result[1], oneThird);
        assertEq(result[2], oneThird);
        uint256 sum = result[0] + result[1] + result[2];
        assertLe(sum, FixedPoint.ONE);
        assertEq(sum, FixedPoint.ONE - 1);
    }

    // --- fuzz ---

    function testFuzz_shares_sumWithinOneWeiPerEntry(uint128[8] memory raw) public pure {
        uint256[] memory scores = new uint256[](8);
        uint256 total = 0;
        for (uint256 i = 0; i < 8; ++i) {
            scores[i] = uint256(raw[i]);
            total += scores[i];
        }
        if (total == 0) {
            return;
        }
        uint256[] memory result = CCBShare.shares(scores);
        uint256 sum = 0;
        for (uint256 j = 0; j < result.length; ++j) {
            sum += result[j];
        }
        assertLe(sum, FixedPoint.ONE);
        assertGe(sum + 8, FixedPoint.ONE);
    }
}
