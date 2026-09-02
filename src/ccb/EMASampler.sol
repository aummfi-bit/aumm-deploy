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

    /// @notice Minimum successful samples before a pool's EMA counts as mature (D.1 / PP-D52 (i)).
    /// @dev    60 = 432_000 / 7_200 — the 60-day maturity window already locked elsewhere, restated
    ///         in the sampler's own unit, so NO new constant is adjudicated per PP-D43's fifth
    ///         obligation. It is a LITERAL and not a read of `EMA_MATURITY_BLOCKS`, which is
    ///         `internal constant` on `EmissionDistributor` and `VotingWeight` and is therefore
    ///         unreachable through a contract type — PP-D50 (xiii)'s G10 miss, not repeated here.
    uint256 public constant MIN_SAMPLES = 60;

    /// @notice Ceiling on decay steps applied in a single update (D.3 / PP-D52 (iv)).
    /// @dev    Aligned to `MIN_SAMPLES` rather than adjudicated separately: a pool left unsampled
    ///         for longer than the maturity window decays by at most one window's worth per call,
    ///         which bounds the loop's gas on the folded path.
    uint256 public constant MAX_CATCHUP_PERIODS = 60;

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

    /// @notice Per-pool count of successful updates, the cold-start seed included (D.1 / PP-D52 (i)).
    /// @dev    Maturity measured in TIME cannot distinguish two samples sixty days apart from sixty
    ///         daily ones; this is the quantity that can. Consumers gate on `>= MIN_SAMPLES`.
    mapping(address => uint256) public sampleCount;

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
    /// @dev Permissionless per F-D5. Cadence guard at one update per BLOCKS_PER_DAY, enforced by
    ///      REVERT. This entry keeps its revert for the PP-D31 keeper set and for the callers that
    ///      assert `TooEarly` directly; the folded paths call `updateEMAIfDue` instead, which
    ///      no-ops rather than reverting, per PP-D52 (vii). Both share `_update`.
    /// @param pool The Balancer V3 pool address to sample.
    /// @return newEMA The post-update EMA value for the pool.
    function updateEMA(address pool) external returns (uint256 newEMA) {
        uint256 last = lastEMAUpdateBlock[pool];
        uint256 nextEligible = last + AureumTime.BLOCKS_PER_DAY;
        if (block.number < nextEligible) {
            revert TooEarly(block.number, nextEligible);
        }
        return _update(pool, last);
    }

    /// @notice Sample the pool's EMA if the daily cadence has elapsed; no-op otherwise.
    /// @dev PP-D52 (vii). This is the entry the economically motivated paths fold into,
    ///      `EmissionDistributor.recordScore` and `claim`, both permissionless and repeatable
    ///      within a day. A bare `updateEMA` there would revert the SECOND such call of any day on
    ///      that pool, a liveness regression worse than the staleness D.5 fixes. Callers may ignore
    ///      `updated`; a no-op leaves every mapping untouched.
    /// @param pool The Balancer V3 pool address to sample.
    /// @return updated True when a sample was taken, false when the cadence had not elapsed.
    /// @return newEMA The pool's EMA after the call, read from storage unchanged on a no-op.
    function updateEMAIfDue(address pool) external returns (bool updated, uint256 newEMA) {
        uint256 last = lastEMAUpdateBlock[pool];
        if (block.number < last + AureumTime.BLOCKS_PER_DAY) {
            return (false, tvlEMA[pool]);
        }
        return (true, _update(pool, last));
    }

    /// @dev Shared core for both entries; the cadence check belongs to the caller and has passed.
    ///      D.3 / PP-D52 (iv): the F-4 step is applied once per ELAPSED DAY rather than once per
    ///      CALL, bounded at `MAX_CATCHUP_PERIODS`. Before this, fortnightly sampling decayed a
    ///      drained pool fourteen times slower than daily sampling did, so a stale seed survived
    ///      far past its half-life while `lastEMAUpdateBlock` still read fresh. ONE spot read
    ///      serves every step: the loop replays the smoothing that should already have happened,
    ///      it does not re-read the oracle per day. `sampleCount` counts CALLS rather than
    ///      catch-up steps, and includes the cold-start seed.
    /// @param pool The pool being sampled.
    /// @param last The pool's previous `lastEMAUpdateBlock`; zero on cold start.
    /// @return newEMA The post-update EMA value for the pool.
    function _update(address pool, uint256 last) internal returns (uint256 newEMA) {
        uint256 spotTVL = TVL_ORACLE.tvl(pool);

        if (last == 0) {
            // F-D15 cold-start sentinel seed. Direct assign, no smoothing.
            newEMA = spotTVL;
            emaSeedBlock[pool] = block.number;
        } else {
            uint256 periods = (block.number - last) / AureumTime.BLOCKS_PER_DAY;
            if (periods > MAX_CATCHUP_PERIODS) periods = MAX_CATCHUP_PERIODS;

            newEMA = tvlEMA[pool];
            for (uint256 i = 0; i < periods; i++) {
                // F-4 update: alpha = 2/61, half-life ~21 days.
                newEMA = (
                    EMA_ALPHA_NUMERATOR * spotTVL +
                    (EMA_ALPHA_DENOMINATOR - EMA_ALPHA_NUMERATOR) * newEMA
                ) / EMA_ALPHA_DENOMINATOR;
            }
        }

        tvlEMA[pool] = newEMA;
        lastEMAUpdateBlock[pool] = block.number;
        sampleCount[pool] += 1;
        emit EMAUpdated(pool, spotTVL, newEMA, block.number);
    }
}
