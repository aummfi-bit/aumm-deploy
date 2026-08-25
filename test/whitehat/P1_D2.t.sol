// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {EMASampler} from "src/ccb/EMASampler.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

import {MockTVLOracle} from "test/unit/EMASampler.t.sol";

/// @notice Reproduction PoC for seam-1 root cause D.2 (Medium). The row is a direct
///         refutation of the accepted-risk rationale recorded at `src/ccb/EMASampler.sol`
///         L15-L19. D.2's fix batches into the hook unit under PP-D12 because the remedy
///         is a hook-maintained cumulative accumulator read as a TWAP.
contract P1_D2_SamplingCadenceIsOwnedByWhoeverCallsFirstTest is Test {
    uint256 internal constant SEED_BLOCK = 720_000;
    uint256 internal constant BOT_DAY1_BLOCK = SEED_BLOCK + AureumTime.BLOCKS_PER_DAY;
    uint256 internal constant HONEST_TOO_EARLY_BLOCK = BOT_DAY1_BLOCK + 1;
    uint256 internal constant BOT_DAY2_BLOCK = BOT_DAY1_BLOCK + AureumTime.BLOCKS_PER_DAY;

    uint256 internal constant SPOT_SEED = 100e18;
    uint256 internal constant SPOT_HIGH = 1_000e18;
    uint256 internal constant SPOT_LOW = 10e18;

    address internal constant POOL = address(0xA1);
    address internal constant BOT = address(0xB07);
    address internal constant HONEST = address(0x501E57);

    EMASampler internal sampler;
    MockTVLOracle internal oracle;

    function setUp() public {
        oracle = new MockTVLOracle();
        sampler = new EMASampler(oracle);
        vm.roll(SEED_BLOCK);
    }

    /// @notice Whoever calls first each day keeps the slot by re-anchoring the window to their block.
    function test_P1_D2_theFirstCallerEachDayOwnsTheSlotAndReAnchorsTheWindowToTheirOwnBlock() public {
        // Verified: src/emission/TVLOracle.sol L359-L370 computes tvl as a bare sum over
        // balancesLiveScaled18 scaled by a constellation ratio, with no time weighting of any
        // kind, so any balance change moves it instantly. Out of scope: the row's further claim
        // that a proportional add through an UNTRUSTED router moves that sum without touching
        // poolTotalLP and without paying a fee is a property of the real Vault path and is NOT
        // reproduced here.
        oracle.setTvl(POOL, SPOT_SEED);
        sampler.updateEMA(POOL);
        assertEq(sampler.lastEMAUpdateBlock(POOL), SEED_BLOCK, "seed anchors lastEMAUpdateBlock");

        vm.roll(BOT_DAY1_BLOCK);
        vm.prank(BOT);
        sampler.updateEMA(POOL);
        assertEq(
            sampler.lastEMAUpdateBlock(POOL),
            BOT_DAY1_BLOCK,
            "window re-anchors to the caller's own block rather than to a fixed grid"
        );

        vm.roll(HONEST_TOO_EARLY_BLOCK);
        vm.expectRevert(
            abi.encodeWithSelector(
                EMASampler.TooEarly.selector,
                HONEST_TOO_EARLY_BLOCK,
                BOT_DAY1_BLOCK + AureumTime.BLOCKS_PER_DAY
            )
        );
        vm.prank(HONEST);
        sampler.updateEMA(POOL);

        vm.roll(BOT_DAY2_BLOCK);
        vm.prank(BOT);
        sampler.updateEMA(POOL);
        assertEq(
            sampler.lastEMAUpdateBlock(POOL),
            BOT_DAY2_BLOCK,
            "whoever calls first each day keeps the slot indefinitely by calling at the same offset"
        );

        assertTrue(
            sampler.lastEMAUpdateBlock(POOL) != HONEST_TOO_EARLY_BLOCK,
            "honest address never once recorded a sample; the day's only slot was already spent"
        );
        assertEq(
            sampler.lastEMAUpdateBlock(POOL),
            BOT_DAY2_BLOCK,
            "only the bot's blocks appear as lastEMAUpdateBlock after the seed"
        );
    }

    /// @notice The EMA input is a bare spot read at the caller's chosen instant; only the series is smoothed.
    function test_P1_D2_theSampledValueIsABareSpotReadTakenAtTheCallersChosenInstant() public {
        oracle.setTvl(POOL, SPOT_SEED);
        vm.prank(BOT);
        sampler.updateEMA(POOL);
        uint256 seeded = sampler.tvlEMA(POOL);
        assertEq(seeded, SPOT_SEED);

        oracle.setTvl(POOL, SPOT_HIGH);
        vm.roll(BOT_DAY1_BLOCK);
        vm.prank(BOT);
        sampler.updateEMA(POOL);
        uint256 afterHigh = sampler.tvlEMA(POOL);
        assertTrue(
            afterHigh > seeded,
            "first sample moved the EMA toward the high spot; the caller selects both the moment and therefore the value"
        );

        oracle.setTvl(POOL, SPOT_LOW);
        vm.roll(BOT_DAY2_BLOCK);
        vm.prank(BOT);
        sampler.updateEMA(POOL);
        uint256 afterLow = sampler.tvlEMA(POOL);
        assertTrue(
            afterLow < afterHigh,
            "second sample moved the EMA toward the low spot; no smoothing of the INPUT, only of the accumulated series"
        );
    }
}
