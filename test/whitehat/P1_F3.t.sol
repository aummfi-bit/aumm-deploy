// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {AuMM} from "src/token/AuMM.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

/// @title P1 F.3 — schedule integral exceeds the supply cap
/// @notice Reproduction PoC for seam-1 root cause F.3 (Info, downgraded from Low because the
///         cliff is unreachable). `MAX_SUPPLY` at AuMM.sol L23 and the era sum over
///         `AureumTime.BLOCKS_PER_ERA` at L28 are two literals encoding one quantity and
///         disagree. PP-D36 is OPEN and chooses at PP4 between moving `BLOCKS_PER_ERA` to
///         10_500_000 and moving `MAX_SUPPLY` to 21_024_000e18 — this reproduction is
///         invariant to that choice and deliberately takes no position on it.
/// @dev PLAN L295 carves F.3 out of the on-chain-exploit-path requirement: pure arithmetic,
///      no attack sequence.
contract P1_F3_ScheduleIntegralExceedsTheSupplyCapTest is Test {
    /// @dev Source: docs/STAGE_P_PRIME_PLAN.md L136 — E.1's stranded upper bound of 1,073,100 AuMM.
    uint256 internal constant E1_STRANDED_UPPER = 1_073_100e18;

    uint256 internal constant GENESIS_BLOCK = 1_000_000;

    AuMM internal aumm;

    function setUp() public {
        aumm = new AuMM(GENESIS_BLOCK, address(this));
    }

    /// @dev Closed-form era sum: Σ_n (GENESIS_RATE >> n) × BLOCKS_PER_ERA while the shifted
    ///      rate remains strictly positive. Neither the sum nor the era length is restated.
    function _scheduleIntegral() internal pure returns (uint256 total) {
        for (uint256 n = 0; ; n++) {
            uint256 eraRate = uint256(1e18) >> n;
            if (eraRate == 0) break;
            total += eraRate * AureumTime.BLOCKS_PER_ERA;
        }
    }

    /// @notice The two literals disagree; overshoot is derived, not restated, and bounded by E.1.
    function test_P1_F3_theScheduleIntegralExceedsTheCapTheyBothEncode() public {
        uint256 schedule = _scheduleIntegral();
        uint256 cap = aumm.MAX_SUPPLY();
        assertGt(schedule, cap, "schedule integral exceeds the cap both literals encode");

        uint256 overshoot = schedule - cap;
        emit log_named_uint("schedule integral (wei)", schedule);
        emit log_named_uint("MAX_SUPPLY (wei)", cap);
        emit log_named_uint("overshoot (wei)", overshoot);

        // Integer truncation in the shifted sum loses on the order of BLOCKS_PER_ERA times sixty
        // wei and is therefore negligible against an overshoot of 2.4e22.
        assertApproxEqAbs(
            overshoot,
            24_000e18,
            1e15,
            "overshoot is approximately 24000 AuMM"
        );

        // Plan prose rounds the E.1 ratio to 45x, but the exact ratio is 44.7125, so a 45 floor
        // would be unsatisfiable — the figure is measured here rather than taken from the
        // rounding. This bound is CONTINGENT on E.1 remaining unrepaired; it is a capability and
        // magnitude bound drawn from another root cause rather than any assumption about operator
        // conduct. E.1's own brick path is deliberately NOT re-executed here because doing so
        // would couple the fixtures and claim more than F.3 owns.
        assertGt(
            E1_STRANDED_UPPER,
            overshoot * 44,
            "E.1 stranded upper bound alone exceeds forty-four times the schedule overshoot"
        );
        emit log_named_uint("E1_STRANDED_UPPER / overshoot * 100", (E1_STRANDED_UPPER * 100) / overshoot);
    }

    /// @notice The existing cap invariant only sees realised supply; it cannot see schedule > cap.
    function test_P1_F3_theExistingCapInvariantCannotSeeTheDisagreement() public {
        // The audit filing's claim that INV-2 is unimplemented is STALE, because P6 built the
        // harness and INV-2 lives at test/invariant/EmissionConservation.t.sol L189; the real
        // gap is the absent schedule-versus-cap assertion, not an absent invariant.
        uint256 supply = aumm.totalSupply();
        uint256 cap = aumm.MAX_SUPPLY();
        assertEq(supply, 0, "fresh AuMM has zero supply");
        assertLe(
            supply,
            cap,
            "invariant_totalSupplyNeverExceedsCap content holds: realised supply vs cap"
        );

        uint256 schedule = _scheduleIntegral();
        assertGt(
            schedule,
            cap,
            "missing schedule-versus-cap assertion: schedule exceeds cap while realised-supply check holds"
        );
    }
}
