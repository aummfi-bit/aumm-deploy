// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

contract AureumTimeTest is Test {
    uint256 constant GENESIS = 20_000_000; // arbitrary non-zero starting block

    // constant-value tests

    function test_blocksPerDay_equals_7200() public pure {
        assertEq(AureumTime.BLOCKS_PER_DAY, 7_200);
    }

    function test_blocksPerWeek_equals_50400() public pure {
        assertEq(AureumTime.BLOCKS_PER_WEEK, 50_400);
    }

    function test_blocksPerEpoch_equals_100800() public pure {
        assertEq(AureumTime.BLOCKS_PER_EPOCH, 100_800);
    }

    function test_blocksPerMonth_equals_219000() public pure {
        assertEq(AureumTime.BLOCKS_PER_MONTH, 219_000);
    }

    function test_blocksPerQuarter_equals_657000() public pure {
        assertEq(AureumTime.BLOCKS_PER_QUARTER, 657_000);
    }

    function test_blocksPerYear_equals_2628000() public pure {
        assertEq(AureumTime.BLOCKS_PER_YEAR, 2_628_000);
    }

    function test_blocksPerEra_equals_10512000() public pure {
        assertEq(AureumTime.BLOCKS_PER_ERA, 10_512_000);
    }

    // index tests at boundaries

    // --- monthIndex ---

    function test_monthIndex_preGenesis_returnsZero() public pure {
        assertEq(AureumTime.monthIndex(GENESIS, GENESIS - 1), 0);
    }

    function test_monthIndex_atGenesis_returnsZero() public pure {
        assertEq(AureumTime.monthIndex(GENESIS, GENESIS), 0);
    }

    function test_monthIndex_lastBlockOfMonth0_returnsZero() public pure {
        assertEq(AureumTime.monthIndex(GENESIS, GENESIS + AureumTime.BLOCKS_PER_MONTH - 1), 0);
    }

    function test_monthIndex_firstBlockOfMonth1_returnsOne() public pure {
        assertEq(AureumTime.monthIndex(GENESIS, GENESIS + AureumTime.BLOCKS_PER_MONTH), 1);
    }

    function test_monthIndex_midMonth7_returnsSeven() public pure {
        uint256 blk = GENESIS + 7 * AureumTime.BLOCKS_PER_MONTH + (AureumTime.BLOCKS_PER_MONTH / 2);
        assertEq(AureumTime.monthIndex(GENESIS, blk), 7);
    }

    // --- epochIndex ---

    function test_epochIndex_preGenesis_returnsZero() public pure {
        assertEq(AureumTime.epochIndex(GENESIS, GENESIS - 1), 0);
    }

    function test_epochIndex_atGenesis_returnsZero() public pure {
        assertEq(AureumTime.epochIndex(GENESIS, GENESIS), 0);
    }

    function test_epochIndex_lastBlockOfEpoch0_returnsZero() public pure {
        assertEq(AureumTime.epochIndex(GENESIS, GENESIS + AureumTime.BLOCKS_PER_EPOCH - 1), 0);
    }

    function test_epochIndex_firstBlockOfEpoch1_returnsOne() public pure {
        assertEq(AureumTime.epochIndex(GENESIS, GENESIS + AureumTime.BLOCKS_PER_EPOCH), 1);
    }

    function test_epochIndex_midEpoch13_returnsThirteen() public pure {
        uint256 blk = GENESIS + 13 * AureumTime.BLOCKS_PER_EPOCH + (AureumTime.BLOCKS_PER_EPOCH / 2);
        assertEq(AureumTime.epochIndex(GENESIS, blk), 13);
    }

    // --- eraIndex ---

    function test_eraIndex_preGenesis_returnsZero() public pure {
        assertEq(AureumTime.eraIndex(GENESIS, GENESIS - 1), 0);
    }

    function test_eraIndex_atGenesis_returnsZero() public pure {
        assertEq(AureumTime.eraIndex(GENESIS, GENESIS), 0);
    }

    function test_eraIndex_lastBlockOfEra0_returnsZero() public pure {
        assertEq(AureumTime.eraIndex(GENESIS, GENESIS + AureumTime.BLOCKS_PER_ERA - 1), 0);
    }

    function test_eraIndex_firstBlockOfEra1_returnsOne() public pure {
        assertEq(AureumTime.eraIndex(GENESIS, GENESIS + AureumTime.BLOCKS_PER_ERA), 1);
    }

    function test_eraIndex_midEra3_returnsThree() public pure {
        uint256 blk = GENESIS + 3 * AureumTime.BLOCKS_PER_ERA + (AureumTime.BLOCKS_PER_ERA / 2);
        assertEq(AureumTime.eraIndex(GENESIS, blk), 3);
    }

    // boundary-helper tests

    function test_month6EndBlock_equalsGenesisPlus1_314_000() public pure {
        assertEq(AureumTime.month6EndBlock(GENESIS), GENESIS + 1_314_000);
    }

    function test_month10EndBlock_equalsGenesisPlus2_190_000() public pure {
        assertEq(AureumTime.month10EndBlock(GENESIS), GENESIS + 2_190_000);
    }

    function test_month13StartBlock_equalsYear1EndBlockPlus1() public pure {
        assertEq(
            AureumTime.month13StartBlock(GENESIS),
            AureumTime.year1EndBlock(GENESIS) + 1
        );
    }

    function test_year1EndBlock_equalsGenesisPlus2_628_000() public pure {
        assertEq(AureumTime.year1EndBlock(GENESIS), GENESIS + 2_628_000);
    }

    function test_firstHalvingBlock_equalsGenesisPlus10_512_000() public pure {
        assertEq(AureumTime.firstHalvingBlock(GENESIS), GENESIS + 10_512_000);
    }

    function test_nthHalvingBlock_n1_equalsFirstHalvingBlock() public pure {
        assertEq(
            AureumTime.nthHalvingBlock(GENESIS, 1),
            AureumTime.firstHalvingBlock(GENESIS)
        );
    }

    function test_nthHalvingBlock_n5_isFiveErasIn() public pure {
        assertEq(
            AureumTime.nthHalvingBlock(GENESIS, 5),
            GENESIS + 5 * AureumTime.BLOCKS_PER_ERA
        );
    }

    // fuzz tests

    function testFuzz_monthIndex_nonDecreasing(uint256 delta) public pure {
        vm.assume(delta < type(uint128).max);
        uint256 b1 = GENESIS + delta;
        uint256 b2 = b1 + 1;
        assertLe(AureumTime.monthIndex(GENESIS, b1), AureumTime.monthIndex(GENESIS, b2));
    }

    function testFuzz_epochIndex_nonDecreasing(uint256 delta) public pure {
        vm.assume(delta < type(uint128).max);
        uint256 b1 = GENESIS + delta;
        uint256 b2 = b1 + 1;
        assertLe(AureumTime.epochIndex(GENESIS, b1), AureumTime.epochIndex(GENESIS, b2));
    }

    function testFuzz_eraIndex_nonDecreasing(uint256 delta) public pure {
        vm.assume(delta < type(uint128).max);
        uint256 b1 = GENESIS + delta;
        uint256 b2 = b1 + 1;
        assertLe(AureumTime.eraIndex(GENESIS, b1), AureumTime.eraIndex(GENESIS, b2));
    }

    function testFuzz_eraIndex_matchesFloorDivision(uint256 delta) public pure {
        vm.assume(delta < 20 * AureumTime.BLOCKS_PER_ERA);
        uint256 expected = delta / AureumTime.BLOCKS_PER_ERA;
        assertEq(AureumTime.eraIndex(GENESIS, GENESIS + delta), expected);
    }
}
