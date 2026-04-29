// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {EMASampler} from "src/ccb/EMASampler.sol";
import {ITVLOracle} from "src/ccb/ITVLOracle.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

contract EMASamplerTest is Test {
    EMASampler internal sampler;
    MockTVLOracle internal oracle;

    address internal constant POOL_A = address(0xA1);
    address internal constant POOL_B = address(0xB2);

    // BLOCKS_PER_DAY * 100 — well past the F-D15 cold-start sentinel.
    // First updateEMA with last == 0 requires block.number >= BLOCKS_PER_DAY
    // = 7_200; START_BLOCK gives ~3 months of cadence headroom for the
    // multi-call convergence and decay tests.
    uint256 internal constant START_BLOCK = 720_000;

    // Redeclared for vm.expectEmit (AuMM.t.sol L17-L18 convention).
    event EMAUpdated(
        address indexed pool,
        uint256 spotTVL,
        uint256 newEMA,
        uint256 blockNumber
    );

    function setUp() public {
        oracle = new MockTVLOracle();
        sampler = new EMASampler(oracle);
        vm.roll(START_BLOCK);
    }

    // --- constructor ---

    function test_constructor_setsTvlOracle() public view {
        assertEq(address(sampler.TVL_ORACLE()), address(oracle));
    }

    function test_constructor_revertsOnZeroOracle() public {
        vm.expectRevert(EMASampler.ZeroOracle.selector);
        new EMASampler(ITVLOracle(address(0)));
    }

    // --- updateEMA cold-start (F-D15) ---

    function test_updateEMA_firstCall_seedsTvlEma() public {
        // F-D15: first call seeds tvlEMA = spotTVL directly, bypassing
        // the F-4 formula. Without this, naive formula application with
        // tvlEMA_old == 0 would yield 2*spotTVL/61, ~3.28% of spot.
        oracle.setTvl(POOL_A, 100e18);
        sampler.updateEMA(POOL_A);
        assertEq(sampler.tvlEMA(POOL_A), 100e18);
    }

    function test_updateEMA_firstCall_setsLastUpdateBlock() public {
        oracle.setTvl(POOL_A, 100e18);
        sampler.updateEMA(POOL_A);
        assertEq(sampler.lastEMAUpdateBlock(POOL_A), START_BLOCK);
    }

    function test_updateEMA_firstCall_emitsEMAUpdatedEvent() public {
        oracle.setTvl(POOL_A, 100e18);
        vm.expectEmit(true, false, false, true);
        emit EMAUpdated(POOL_A, 100e18, 100e18, START_BLOCK);
        sampler.updateEMA(POOL_A);
    }

    function test_updateEMA_firstCall_returnsSpotTvl() public {
        oracle.setTvl(POOL_A, 100e18);
        uint256 newEMA = sampler.updateEMA(POOL_A);
        assertEq(newEMA, 100e18);
    }

    function test_updateEMA_firstCall_withZeroSpot_seedsZero() public {
        // F-D15 edge case: spotTVL == 0 at seed → tvlEMA stays 0.
        // Practical bound: pools shouldn't be sampled before they have
        // nonzero TVL; this test documents the edge-case behavior.
        sampler.updateEMA(POOL_A);
        assertEq(sampler.tvlEMA(POOL_A), 0);
        assertEq(sampler.lastEMAUpdateBlock(POOL_A), START_BLOCK);
    }

    function test_updateEMA_zeroSeedNoReseed() public {
        // F-D15 explicit non-design: no second-order "re-seed if tvlEMA == 0
        // and spotTVL > 0" sentinel. After zero seed, subsequent updates
        // apply the F-4 formula slow ramp with tvlEMA_old = 0.
        sampler.updateEMA(POOL_A); // seed at spot=0 → tvlEMA = 0
        assertEq(sampler.tvlEMA(POOL_A), 0);

        oracle.setTvl(POOL_A, 1000e18);
        vm.roll(block.number + AureumTime.BLOCKS_PER_DAY);
        sampler.updateEMA(POOL_A);

        // Expected: (2 * 1000e18 + 59 * 0) / 61 = ~32.78e18.
        // Crucially NOT 1000e18 (which would indicate a re-seed).
        uint256 expected = (uint256(2) * 1000e18) / 61;
        assertEq(sampler.tvlEMA(POOL_A), expected);
        assertLt(sampler.tvlEMA(POOL_A), 100e18); // far below new spot
    }

    // --- updateEMA F-4 formula ---

    function test_updateEMA_secondCall_steadyState() public {
        // F-4 has a fixed point at tvlEMA = spotTVL: if spot stays
        // constant, EMA stays at that constant exactly.
        oracle.setTvl(POOL_A, 100e18);
        sampler.updateEMA(POOL_A);
        vm.roll(block.number + AureumTime.BLOCKS_PER_DAY);
        sampler.updateEMA(POOL_A);
        assertEq(sampler.tvlEMA(POOL_A), 100e18);
    }

    function test_updateEMA_secondCall_decayWithZeroSpot() public {
        // Seed at 61e18; spot drops to 0; F-4 gives 59e18 EXACTLY —
        // seed value 61 chosen so 59 × 61 / 61 = 59 with no truncation,
        // isolating the formula coefficient (not rounding behavior).
        oracle.setTvl(POOL_A, 61e18);
        sampler.updateEMA(POOL_A);
        oracle.setTvl(POOL_A, 0);
        vm.roll(block.number + AureumTime.BLOCKS_PER_DAY);
        sampler.updateEMA(POOL_A);
        assertEq(sampler.tvlEMA(POOL_A), 59e18);
    }

    function test_updateEMA_secondCall_appliesF4Formula() public {
        // Spot 100e18 → 200e18 step. Expected: (2 * 200 + 59 * 100) / 61
        // = 6300 / 61 = 103.278688...e18 (truncated). Tests the formula
        // under non-clean integer division.
        oracle.setTvl(POOL_A, 100e18);
        sampler.updateEMA(POOL_A);
        oracle.setTvl(POOL_A, 200e18);
        vm.roll(block.number + AureumTime.BLOCKS_PER_DAY);
        uint256 newEMA = sampler.updateEMA(POOL_A);
        uint256 expected = (uint256(2) * 200e18 + uint256(59) * 100e18) / 61;
        assertEq(newEMA, expected);
        assertEq(sampler.tvlEMA(POOL_A), expected);
    }

    function test_updateEMA_convergesTowardSpot_overManyDays() public {
        // Seed at 100, then permanent step to 1000. EMA monotonically
        // rises and approaches but never reaches 1000 (asymptotic plus
        // integer truncation never overshoots a higher target from below).
        oracle.setTvl(POOL_A, 100e18);
        sampler.updateEMA(POOL_A);
        oracle.setTvl(POOL_A, 1000e18);

        uint256 prev = 100e18;
        for (uint256 i = 0; i < 60; i++) {
            vm.roll(block.number + AureumTime.BLOCKS_PER_DAY);
            uint256 newEMA = sampler.updateEMA(POOL_A);
            assertGe(newEMA, prev);
            prev = newEMA;
        }
        // After 60 days (~3 half-lives), theoretical convergence
        // = 1000 - 900 × (59/61)^60 ~ 878. Loose lower bound 800 absorbs
        // per-day truncation drift.
        assertGt(sampler.tvlEMA(POOL_A), 800e18);
        assertLt(sampler.tvlEMA(POOL_A), 1000e18);
    }

    // --- updateEMA cadence guard (F-D5 / OQ-5a-bis) ---

    function test_updateEMA_revertsBeforeCadence() public {
        oracle.setTvl(POOL_A, 100e18);
        sampler.updateEMA(POOL_A);

        // Calling immediately again — block.number unchanged, must revert.
        uint256 nextEligible = START_BLOCK + AureumTime.BLOCKS_PER_DAY;
        vm.expectRevert(abi.encodeWithSelector(
            EMASampler.TooEarly.selector, START_BLOCK, nextEligible
        ));
        sampler.updateEMA(POOL_A);
    }

    function test_updateEMA_revertsAtCadenceMinusOne() public {
        oracle.setTvl(POOL_A, 100e18);
        sampler.updateEMA(POOL_A);

        // block.number = last + BLOCKS_PER_DAY - 1 — strict-inequality
        // boundary. Must revert.
        uint256 nextEligible = START_BLOCK + AureumTime.BLOCKS_PER_DAY;
        vm.roll(nextEligible - 1);
        vm.expectRevert(abi.encodeWithSelector(
            EMASampler.TooEarly.selector, nextEligible - 1, nextEligible
        ));
        sampler.updateEMA(POOL_A);
    }

    function test_updateEMA_succeedsAtCadenceBoundary() public {
        oracle.setTvl(POOL_A, 100e18);
        sampler.updateEMA(POOL_A);

        // block.number = last + BLOCKS_PER_DAY exactly — succeeds.
        uint256 boundary = START_BLOCK + AureumTime.BLOCKS_PER_DAY;
        vm.roll(boundary);
        sampler.updateEMA(POOL_A);
        assertEq(sampler.lastEMAUpdateBlock(POOL_A), boundary);
    }

    function test_updateEMA_firstCall_revertsBelowBlocksPerDay() public {
        // Cold-start cadence edge: with last == 0, nextEligible
        // = 0 + BLOCKS_PER_DAY = 7_200. Calling at block 7_199 reverts.
        // (vm.roll backward from setUp's START_BLOCK is allowed.)
        vm.roll(AureumTime.BLOCKS_PER_DAY - 1);
        vm.expectRevert(abi.encodeWithSelector(
            EMASampler.TooEarly.selector,
            AureumTime.BLOCKS_PER_DAY - 1,
            AureumTime.BLOCKS_PER_DAY
        ));
        sampler.updateEMA(POOL_A);
    }

    // --- updateEMA per-pool isolation ---

    function test_updateEMA_perPool_isolatedState() public {
        oracle.setTvl(POOL_A, 100e18);
        oracle.setTvl(POOL_B, 200e18);

        sampler.updateEMA(POOL_A);
        // POOL_B untouched by POOL_A's update.
        assertEq(sampler.tvlEMA(POOL_B), 0);
        assertEq(sampler.lastEMAUpdateBlock(POOL_B), 0);

        // POOL_B can be sampled in the same block — cadence guard is
        // per-pool, not global.
        sampler.updateEMA(POOL_B);
        assertEq(sampler.tvlEMA(POOL_B), 200e18);
        assertEq(sampler.tvlEMA(POOL_A), 100e18); // POOL_A unchanged
    }

    // --- updateEMA permissionless (F-D5) ---

    function test_updateEMA_permissionless_anyCanCall() public {
        oracle.setTvl(POOL_A, 100e18);

        // First call from address(0xCAFE).
        vm.prank(address(0xCAFE));
        sampler.updateEMA(POOL_A);

        // Second call from address(0xBEEF) after cadence.
        vm.roll(block.number + AureumTime.BLOCKS_PER_DAY);
        vm.prank(address(0xBEEF));
        sampler.updateEMA(POOL_A);

        // Both succeed; state advances.
        assertEq(
            sampler.lastEMAUpdateBlock(POOL_A),
            START_BLOCK + AureumTime.BLOCKS_PER_DAY
        );
    }

    // --- constants ---

    function test_constants_alphaNumerator_is_2() public view {
        assertEq(sampler.EMA_ALPHA_NUMERATOR(), 2);
    }

    function test_constants_alphaDenominator_is_61() public view {
        assertEq(sampler.EMA_ALPHA_DENOMINATOR(), 61);
    }

    // --- fuzz ---

    function testFuzz_updateEMA_seedSetsTvlEma(uint128 spot) public {
        // F-D15 seed property: tvlEMA[pool] = spotTVL on first call for
        // any spotTVL in uint128 range.
        oracle.setTvl(POOL_A, spot);
        sampler.updateEMA(POOL_A);
        assertEq(sampler.tvlEMA(POOL_A), spot);
    }

    function testFuzz_updateEMA_secondCall_appliesF4Formula(
        uint128 spot1,
        uint128 spot2
    ) public {
        // F-4 formula property: tvlEMA_new = (2*spot2 + 59*spot1) / 61
        // for any uint128 inputs (no overflow at 61 × 2^128 < 2^134).
        oracle.setTvl(POOL_A, spot1);
        sampler.updateEMA(POOL_A);
        oracle.setTvl(POOL_A, spot2);
        vm.roll(block.number + AureumTime.BLOCKS_PER_DAY);
        uint256 newEMA = sampler.updateEMA(POOL_A);
        uint256 expected =
            (uint256(2) * uint256(spot2) + uint256(59) * uint256(spot1)) / 61;
        assertEq(newEMA, expected);
        assertEq(sampler.tvlEMA(POOL_A), expected);
    }

    function testFuzz_updateEMA_revertsBeforeCadence(
        uint256 earlyAdvanceRaw
    ) public {
        // For any advance in [0, BLOCKS_PER_DAY - 1] after the seed call,
        // updateEMA reverts TooEarly with (block.number, last + BLOCKS_PER_DAY).
        oracle.setTvl(POOL_A, 100e18);
        sampler.updateEMA(POOL_A);

        uint256 advance = bound(
            earlyAdvanceRaw, 0, AureumTime.BLOCKS_PER_DAY - 1
        );
        vm.roll(START_BLOCK + advance);

        uint256 nextEligible = START_BLOCK + AureumTime.BLOCKS_PER_DAY;
        vm.expectRevert(abi.encodeWithSelector(
            EMASampler.TooEarly.selector,
            START_BLOCK + advance,
            nextEligible
        ));
        sampler.updateEMA(POOL_A);
    }
}

// --- mock ---

/// @dev Minimal ITVLOracle implementation for unit tests. Per-pool spot TVL
///      is set via setTvl; the tvl() view returns the stored value.
contract MockTVLOracle is ITVLOracle {
    mapping(address => uint256) private _spotTvl;

    function setTvl(address pool, uint256 value) external {
        _spotTvl[pool] = value;
    }

    function tvl(address pool) external view override returns (uint256) {
        return _spotTvl[pool];
    }
}
