// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {ITVLOracle} from "src/ccb/ITVLOracle.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

/**
 * @title EMASampler — Aureum CCB per-pool TVL EMA sampler
 * @notice Maintains per-pool 60-day exponential moving averages of TVL.
 *         Reads spot TVL from an injectable ITVLOracle once per
 *         BLOCKS_PER_DAY and applies the F-4 smoothing formula
 *         tvlEMA_new = (2 * spotTVL + 59 * tvlEMA_old) / 61, alpha = 2/61.
 *         Permissionless updateEMA — anyone can call once cadence permits.
 * @dev Per OQ-5a-bis (FINDINGS L1152-L1198): per-day spot read, no
 *      cumulative accumulator, no Stage D AureumFeeRoutingHook hook
 *      callback. The single-block-spike attack surface is accepted and
 *      defended in depth by F-10 efficiency-tournament tier caps + 6-week
 *      smoothing window + Year-1 buffer; not at the EMASampler layer.
 *
 *      Per OQ-22 (FINDINGS L1104-L1150): TVL_ORACLE returns
 *      svZCHF-denominated pool TVL at 18 decimals, computed as RP-aware
 *      unwrap to underlying then constellation-spot averaging to svZCHF.
 *      Concrete oracle ships at the OQ-22 resolution stage (post-Stage F);
 *      EMASampler holds an injectable interface so the EMA infrastructure
 *      does not block on the oracle ship.
 *
 *      Per F-D15 (STAGE_F_NOTES.md): first updateEMA(pool) call —
 *      detected by lastEMAUpdateBlock[pool] == 0 — seeds tvlEMA[pool] =
 *      spotTVL directly, bypassing the F-4 formula. Avoids the ~63-day
 *      cold-start ramp the formula would otherwise impose on newly gauged
 *      pools.
 *
 *      Per F-D5 (STAGE_F_PLAN.md): updateEMA is permissionless. Cadence
 *      guard reverts TooEarly when called before
 *      lastEMAUpdateBlock[pool] + BLOCKS_PER_DAY.
 */
contract EMASampler {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice EMA smoothing factor numerator (alpha = 2/61).
    uint256 public constant EMA_ALPHA_NUMERATOR = 2;

    /// @notice EMA smoothing factor denominator (alpha = 2/61).
    ///         Half-life ~21 days; 60-day horizon framing per OQ-5a.
    uint256 public constant EMA_ALPHA_DENOMINATOR = 61;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice Injected TVL oracle returning svZCHF-denominated pool TVL at
    ///         18 decimals per OQ-22. Set at construction; never changes.
    // Aureum-wide naming: immutable set at construction, UPPER_SNAKE_CASE.
    // slither-disable-next-line naming-convention
    ITVLOracle public immutable TVL_ORACLE;

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    /// @notice Per-pool current EMA of TVL (svZCHF, 18 decimals). Zero before
    ///         the pool's first updateEMA call.
    mapping(address => uint256) public tvlEMA;

    /// @notice Per-pool block number of the last successful updateEMA call.
    ///         Zero indicates "never sampled" — F-D15 cold-start sentinel.
    mapping(address => uint256) public lastEMAUpdateBlock;

    /// @notice Per-pool block number of the first updateEMA seed per F-D15.
    ///         Zero indicates "never sampled". Written exactly once.
    mapping(address => uint256) public emaSeedBlock;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted on every successful updateEMA call (both seed and
    ///         smoothed update paths).
    /// @param pool        The pool whose EMA was updated.
    /// @param spotTVL     The spot TVL read from the oracle for this update.
    /// @param newEMA      The post-update EMA value (= spotTVL on seed path).
    /// @param blockNumber block.number at the update.
    event EMAUpdated(
        address indexed pool,
        uint256 spotTVL,
        uint256 newEMA,
        uint256 blockNumber
    );

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Reverts the constructor when a zero ITVLOracle is supplied.
    error ZeroOracle();

    /// @notice Reverts updateEMA when called before
    ///         lastEMAUpdateBlock[pool] + BLOCKS_PER_DAY.
    /// @param currentBlock      block.number at the failed call.
    /// @param nextEligibleBlock The first block at which updateEMA(pool) is callable.
    error TooEarly(uint256 currentBlock, uint256 nextEligibleBlock);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @notice Bind EMASampler to an ITVLOracle implementation.
    /// @dev Reverts ZeroOracle if tvlOracle_ is the zero address —
    ///      EMASampler cannot recover from a missing oracle.
    /// @param tvlOracle_ The TVL oracle contract per OQ-22.
    constructor(ITVLOracle tvlOracle_) {
        if (address(tvlOracle_) == address(0)) revert ZeroOracle();
        TVL_ORACLE = tvlOracle_;
    }

    // -------------------------------------------------------------------------
    // State-changing
    // -------------------------------------------------------------------------

    /// @notice Sample the pool's spot TVL and update its EMA per F-4 / OQ-5a-bis.
    /// @dev Permissionless per F-D5. Cadence guard at one update per
    ///      BLOCKS_PER_DAY. First call (lastEMAUpdateBlock[pool] == 0) seeds
    ///      tvlEMA[pool] = spotTVL per F-D15 cold-start sentinel; subsequent
    ///      calls apply tvlEMA_new = (2 * spotTVL + 59 * tvlEMA_old) / 61.
    /// @param pool The Balancer V3 pool address to sample.
    /// @return newEMA The post-update EMA value for the pool.
    function updateEMA(address pool) external returns (uint256 newEMA) {
        uint256 last = lastEMAUpdateBlock[pool];
        uint256 nextEligible = last + AureumTime.BLOCKS_PER_DAY;
        if (block.number < nextEligible) {
            revert TooEarly(block.number, nextEligible);
        }

        uint256 spotTVL = TVL_ORACLE.tvl(pool);

        if (last == 0) {
            // F-D15 cold-start sentinel seed. Direct assign, no smoothing.
            newEMA = spotTVL;
            emaSeedBlock[pool] = block.number;
        } else {
            // F-4 update: alpha = 2/61, half-life ~21 days.
            newEMA = (
                EMA_ALPHA_NUMERATOR * spotTVL +
                (EMA_ALPHA_DENOMINATOR - EMA_ALPHA_NUMERATOR) * tvlEMA[pool]
            ) / EMA_ALPHA_DENOMINATOR;
        }

        tvlEMA[pool] = newEMA;
        lastEMAUpdateBlock[pool] = block.number;

        emit EMAUpdated(pool, spotTVL, newEMA, block.number);
    }
}
