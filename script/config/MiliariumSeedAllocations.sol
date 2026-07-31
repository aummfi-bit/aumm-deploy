// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

/**
 * @title MiliariumSeedAllocations
 * @notice The PB-D41 (vi) seed-allocation table — $1,000,000 of accounting TVL spread across the 26
 *         seeded Miliarium slots by six-band compression of real-world theme market capitalization.
 *
 * @dev SEEDING INPUT, NOT AN ORACLE CLAIM: the stubs carry no live USD feed and nothing on chain
 *      asserts these figures (PB-D41 (vi)). Allocations are whole US dollars, and every token is
 *      notionally worth one dollar — PB-D41 (vii) names no price step because there is none, which
 *      is self-consistent since each leg's balance over its weight is then the same allocation.
 *
 * @dev A leg's raw amount is `allocation * 10**decimals * weight / 1e18`, with the multiplications
 *      ordered BEFORE the division to preserve sub-dollar precision and to avoid the
 *      divide-before-multiply lint. Weights and token order come from the Vault's registered pool
 *      data, never from a config library, per the PB-D26 lockstep lesson.
 *
 * @dev Rows appear in the PB-D41 (vi) table's own order — descending band rather than ascending
 *      slot — so this library stays a row-for-row transcription of `docs/STAGE_P_BIS_NOTES.md`
 *      L618-L643 and remains diff-checkable against it, the PB-D44 (iii) principle applied to an
 *      authored source rather than a derived one.
 *
 * @dev Slots 04 `ixViatica` and 07 `ixCambio` are absent, deferred at M-D7 and left deferred by
 *      PB-D8. Slot 01 `ixHelvetia` is deliberately floored one band above its theme market cap, both
 *      as the protocol's own CHF reference pool and because slot 06 prices through it. Slot 02
 *      `ixAetheron` keeps its full band allocation despite being unpriced by design per PB-D41 (v).
 *
 * @dev The gate here is arithmetic rather than derivational: the consuming script asserts the rows
 *      sum to `TOTAL_USD` before spending anything (PB-D46 (v)).
 */
library MiliariumSeedAllocations {
    /// @notice Seeded Miliarium slots — 28 less the two M-D7 deferrals.
    uint256 internal constant SLOT_COUNT = 26;

    /// @notice The accounting-TVL universe in whole US dollars; the rows must sum to exactly this.
    uint256 internal constant TOTAL_USD = 1_000_000;

    /**
     * @notice Seed allocations, index-aligned, both of length `SLOT_COUNT`.
     * @return slot Miliarium slot numbers, in PB-D41 (vi) table order.
     * @return usd Whole-dollar allocation for the slot at the same index.
     */
    function allocations() internal pure returns (uint256[] memory slot, uint256[] memory usd) {
        slot = new uint256[](SLOT_COUNT);
        usd = new uint256[](SLOT_COUNT);

        slot[0] = 17; usd[0] = 70_000;
        slot[1] = 10; usd[1] = 70_000;
        slot[2] = 11; usd[2] = 70_000;
        slot[3] = 18; usd[3] = 70_000;
        slot[4] = 27; usd[4] = 70_000;
        slot[5] = 22; usd[5] = 47_000;
        slot[6] = 24; usd[6] = 47_000;
        slot[7] = 8; usd[7] = 47_000;
        slot[8] = 19; usd[8] = 47_000;
        slot[9] = 20; usd[9] = 47_000;
        slot[10] = 25; usd[10] = 47_000;
        slot[11] = 21; usd[11] = 47_000;
        slot[12] = 23; usd[12] = 47_000;
        slot[13] = 14; usd[13] = 32_000;
        slot[14] = 28; usd[14] = 32_000;
        slot[15] = 26; usd[15] = 32_000;
        slot[16] = 9; usd[16] = 32_000;
        slot[17] = 6; usd[17] = 27_000;
        slot[18] = 5; usd[18] = 27_000;
        slot[19] = 15; usd[19] = 13_000;
        slot[20] = 3; usd[20] = 13_000;
        slot[21] = 2; usd[21] = 13_000;
        slot[22] = 12; usd[22] = 13_000;
        slot[23] = 13; usd[23] = 13_000;
        slot[24] = 16; usd[24] = 13_000;
        slot[25] = 1; usd[25] = 14_000;
    }
}
