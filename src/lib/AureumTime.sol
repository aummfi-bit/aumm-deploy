// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/**
 * @title AureumTime
 * @notice Canonical block-number math for Aureum. Every calendar-time term in the
 *         protocol is an alias for a block count (FINDINGS.md OQ-5). Contracts
 *         only ever deal with block counts — calendar labels are for humans.
 * @dev Pure library, no state. All constants/functions internal; callers compile
 *      the math in via Solidity's library-internal-call inlining.
 */
library AureumTime {
    // constants

    /// @notice 1 day at 12 s/block. OQ-5 / §xxix.
    uint256 internal constant BLOCKS_PER_DAY      = 7_200;
    /// @notice 7 days. §xxix parity only; no current consumer.
    uint256 internal constant BLOCKS_PER_WEEK     = 50_400;
    /// @notice Bi-weekly epoch. OQ-4 / §xxix. Used by F-2, F-8, F-10.
    uint256 internal constant BLOCKS_PER_EPOCH    = 100_800;
    /// @notice Protocol month (1/12 year). OQ-3 / §xxix. Used by F-0 boundaries.
    uint256 internal constant BLOCKS_PER_MONTH    = 219_000;
    /// @notice Protocol quarter. §xxix general reference.
    uint256 internal constant BLOCKS_PER_QUARTER  = 657_000;
    /// @notice Protocol year = 365 calendar days exact. §xxix. F-3 transition endpoint.
    uint256 internal constant BLOCKS_PER_YEAR     = 2_628_000;
    /// @notice Halving interval = 4 × BLOCKS_PER_YEAR. OQ-5 / §xxix.
    uint256 internal constant BLOCKS_PER_ERA      = 10_512_000;

    // index helpers

    /// @notice Zero-indexed month since genesis. Month 0 is [genesis, genesis + BLOCKS_PER_MONTH).
    /// @dev Returns 0 for pre-genesis blocks (sentinel — caller decides whether to care).
    function monthIndex(uint256 genesisBlock, uint256 blockNumber) internal pure returns (uint256) {
        if (blockNumber < genesisBlock) return 0;
        return (blockNumber - genesisBlock) / BLOCKS_PER_MONTH;
    }

    /// @notice Zero-indexed epoch since genesis.
    function epochIndex(uint256 genesisBlock, uint256 blockNumber) internal pure returns (uint256) {
        if (blockNumber < genesisBlock) return 0;
        return (blockNumber - genesisBlock) / BLOCKS_PER_EPOCH;
    }

    /// @notice Zero-indexed era since genesis. Era 0 is [genesis, genesis + BLOCKS_PER_ERA).
    function eraIndex(uint256 genesisBlock, uint256 blockNumber) internal pure returns (uint256) {
        if (blockNumber < genesisBlock) return 0;
        return (blockNumber - genesisBlock) / BLOCKS_PER_ERA;
    }

    // boundary helpers

    /// @notice End of Month 6. F-0 first piecewise boundary (80%→50%); Bodensee UI unhide.
    function month6EndBlock(uint256 genesisBlock) internal pure returns (uint256) {
        return genesisBlock + 6 * BLOCKS_PER_MONTH;
    }

    /// @notice End of Month 10. F-0 second piecewise boundary (bootstrap permanently zero).
    function month10EndBlock(uint256 genesisBlock) internal pure returns (uint256) {
        return genesisBlock + 10 * BLOCKS_PER_MONTH;
    }

    /// @notice First block of Month 13. Efficiency-tournament activation (Stage G).
    /// @dev Equal to year1EndBlock(g) + 1 — both named because different consumers reference them.
    function month13StartBlock(uint256 genesisBlock) internal pure returns (uint256) {
        return genesisBlock + 12 * BLOCKS_PER_MONTH + 1;
    }

    /// @notice End of Year 1. F-3 transition endpoint (α = 1).
    function year1EndBlock(uint256 genesisBlock) internal pure returns (uint256) {
        return genesisBlock + BLOCKS_PER_YEAR;
    }

    /// @notice First halving block. Era 0 → Era 1.
    function firstHalvingBlock(uint256 genesisBlock) internal pure returns (uint256) {
        return genesisBlock + BLOCKS_PER_ERA;
    }

    /// @notice Nth halving block. Era n-1 → Era n. nthHalvingBlock(g, 1) == firstHalvingBlock(g).
    function nthHalvingBlock(uint256 genesisBlock, uint256 n) internal pure returns (uint256) {
        return genesisBlock + n * BLOCKS_PER_ERA;
    }
}
