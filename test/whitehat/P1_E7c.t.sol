// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {EmissionDistributorHarness} from "test/unit/harness/EmissionDistributorHarness.sol";

import {IAuMM} from "src/token/IAuMM.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";
import {IEmissionDistributor} from "src/emission/IEmissionDistributor.sol";

import {MockAuMM, MockBpt, MockEMASampler, MockCCBMultiplier, MockMiliariumRegistry} from "test/unit/EmissionDistributor.t.sol";
import {MockEfficiencyOracle} from "test/fork/mocks/StageGMocks.sol";
import {MockRegisteredVault} from "../mocks/MockRegisteredVault.sol";

/// @notice Minimal gauge-registry double for E.7c: only the two views `recordScore` reads.
contract CappedGaugeRegistry {
    mapping(address => bool) public approved;
    mapping(address => uint256) public capBps;

    function setApproved(address pool, bool flag) external {
        approved[pool] = flag;
    }

    function setCapBps(address pool, uint256 bps) external {
        capBps[pool] = bps;
    }

    function isGaugeApproved(address pool) external view returns (bool) {
        return approved[pool];
    }

    function poolEmissionCapBps(address pool) external view returns (uint256) {
        return capBps[pool];
    }
}

/// @notice Reproduction PoC for seam-1 root cause E.7c (Medium). The clamp at
///         `EmissionDistributor.sol` L495 multiplies by `totalScore` minus the pool's old
///         effective score as read in the caller's block, so the cap is solved against a
///         caller-chosen denominator and then latched. E.7a and E.7b are the other two F-16
///         faces and live on the tournament path rather than here.
contract P1_E7c_CapLatchedAgainstACallerChosenDenominatorTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant SCORE_BLOCK = GENESIS_BLOCK + 2_628_000 + 1;
    uint256 internal constant CAP_BPS = 100; // 1%
    uint256 internal constant CAP_FP = CAP_BPS * 1e14; // 1e16 in 1e18 fixed-point
    uint256 internal constant MOVER_TVL_LARGE = 10_000e18;
    uint256 internal constant MOVER_TVL_SMALL = 100e18;
    uint256 internal constant CAPPED_TVL = 1_000e18;

    address internal constant GOV = address(0x9011);
    address internal constant MOVER = address(0xA001);
    address internal constant CAPPED_A = address(0xA002);
    address internal constant CAPPED_B = address(0xA003);

    MockAuMM internal aumm;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockMiliariumRegistry internal miliReg;
    MockEfficiencyOracle internal effOracle;
    CappedGaugeRegistry internal gauges;
    EmissionDistributorHarness internal distributor;

    function setUp() public {
        aumm = new MockAuMM();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        miliReg = new MockMiliariumRegistry();
        effOracle = new MockEfficiencyOracle();
        gauges = new CappedGaugeRegistry();

        distributor = new EmissionDistributorHarness(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK,
            GOV,
            address(new MockRegisteredVault())
        );

        gauges.setApproved(MOVER, true);
        gauges.setApproved(CAPPED_A, true);
        gauges.setApproved(CAPPED_B, true);
        gauges.setCapBps(CAPPED_A, CAP_BPS);
        gauges.setCapBps(CAPPED_B, CAP_BPS);

        mult.setMultiplier(MOVER, 1e18);
        mult.setMultiplier(CAPPED_A, 1e18);
        mult.setMultiplier(CAPPED_B, 1e18);

        vm.roll(SCORE_BLOCK);
    }

    /// @notice INVERTED at PP4.13 per PP-D56 (v) as amended by (xix) and (xx). As a reproduction this
    ///         case showed a latched score drifting above its cap once `totalScore` fell, with the
    ///         capped pool never re-scored and nothing able to correct it. The settle-head clamp now
    ///         re-derives the limit against the live denominator, so the drift is corrected at that
    ///         pool's next settle. The three premise assertions are the reproduction's own in
    ///         substance: they establish that the latch sat at the cap, that the denominator then
    ///         fell, and that the stored share had drifted above the cap before anything settled.
    /// @dev The settle driver is `deregisterScore`, chosen over the `claim` the done-criteria case
    ///      uses because it reads NO token balance and so works against the bare address this fixture
    ///      declares, leaving `setUp` and the sibling reproduction untouched, and over `recordScore`
    ///      because re-scoring recomputes the score from its own inputs and would hide the clamp
    ///      behind a fresh write. It also covers the one settle site PP-D56 (v) calls wasted and fine,
    ///      which is worth proving rather than asserting.
    /// @dev THE ASSERTIONS READ THE EVENT'S DATA, NOT ITS MERE PRESENCE, and the reason is specific to
    ///      this driver: `deregisterScore` clears the score straight after settling, and its clearing
    ///      write composes with the clamp's paired write to leave `totalScore` and `poolScore`
    ///      IDENTICAL whether or not the clamp bound, so no post-call state discriminates the two
    ///      worlds and a presence-only check would rest on an event whose data went unread. The one
    ///      live discriminator is the event's own payload, so this case decodes it: `uncappedScore`
    ///      must equal the drifted latch, proving the clamp operated on that value and not another,
    ///      and `cappedScore` must be strictly lower, proving it reduced the score. Neither assertion
    ///      re-derives the cap formula, which is the same refusal `test_capEnforcedAtSettle` makes.
    ///      `EmissionCapApplied` identifies the settle clamp unambiguously because PP-D56 (xx) fixes
    ///      it as that clamp's complete emit set, while the retained record-time clamp emits
    ///      `ScoreUpdated` instead.
    function test_P1_E7c_theDriftedLatchIsRecappedAtTheNextSettle() public {
        ema.setTVLEMA(MOVER, MOVER_TVL_LARGE);
        distributor.recordScore(MOVER);

        ema.setTVLEMA(CAPPED_A, CAPPED_TVL);
        distributor.recordScore(CAPPED_A);

        uint256 latched = distributor.poolScore(CAPPED_A);
        assertApproxEqAbs(
            (latched * 1e18) / distributor.totalScore(),
            CAP_FP,
            10,
            "premise: at latch the realised share equals the cap"
        );

        ema.setTVLEMA(MOVER, MOVER_TVL_SMALL);
        distributor.recordScore(MOVER);

        assertEq(
            distributor.poolScore(CAPPED_A),
            latched,
            "premise: the capped pool was never re-scored"
        );
        assertGt(
            (latched * 1e18) / distributor.totalScore(),
            CAP_FP,
            "premise: the stored share has drifted above the cap"
        );

        gauges.setApproved(CAPPED_A, false);

        vm.recordLogs();
        distributor.deregisterScore(CAPPED_A);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool clampBound = false;
        uint256 clampedFrom;
        uint256 clampedTo;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics.length == 2 &&
                logs[i].topics[0] == keccak256("EmissionCapApplied(address,uint256,uint256)") &&
                address(uint160(uint256(logs[i].topics[1]))) == CAPPED_A
            ) {
                clampBound = true;
                (clampedFrom, clampedTo) = abi.decode(logs[i].data, (uint256, uint256));
            }
        }

        assertTrue(clampBound, "the settle clamp bound on the deregister path");
        assertEq(clampedFrom, latched, "it re-derived against the drifted latch, not another value");
        assertLt(clampedTo, latched, "and it reduced the score rather than leaving the drift in place");

        assertEq(distributor.poolScore(CAPPED_A), 0, "completion control: the deregistration still clears the pool");
    }

    /// @notice INVERTED at PP4.13 per PP-D56 (v) as amended by (xix) and (xx). As a reproduction this
    ///         case showed two identical capped pools latching DIFFERENT scores purely because
    ///         `recordScore` is permissionless and the caller chose when each was claimed, so the cap
    ///         bounded nothing on its own. The premise still holds and is asserted unchanged: the two
    ///         pools take identical cap, TVL and multiplier inputs, and the earlier claim still latches
    ///         the larger score. What no longer holds is that the latch DECIDES anything. The
    ///         settle-head clamp re-derives each pool's limit against the denominator live at that
    ///         pool's own next settle, so the advantage the early caller bought does not survive it.
    /// @dev THE ASSERTION IS A REVERSAL, not merely a reduction, and that is a consequence of the
    ///      arithmetic rather than a coincidence worth restating loosely. `CAPPED_A` latched against a
    ///      denominator carrying the large mover; `CAPPED_B` latched later against one carrying the
    ///      small mover PLUS `CAPPED_A`'s own inflated latch, which is what made `CAPPED_B`'s limit the
    ///      smaller of the two. When `CAPPED_A` is then settled, its limit is re-derived against a
    ///      denominator that no longer contains that inflation, so it lands BELOW `CAPPED_B`'s latch.
    ///      The ordering the caller purchased is therefore not just eroded but inverted.
    /// @dev Only `CAPPED_A` is settled here, deliberately. Settling `CAPPED_B` as well would change the
    ///      denominator the first settle was measured against, so the two cannot be compared at one
    ///      denominator and no convergence claim is made or implied. The driver is `deregisterScore`
    ///      for the reasons the sibling case states: it settles before it clears, reads no token
    ///      balance and so works against these bare-address constants, and does not re-score. The
    ///      assertions read the event's DATA rather than its presence, because this driver zeroes the
    ///      score immediately afterwards and leaves no post-call state that distinguishes a clamped
    ///      world from an unclamped one.
    function test_P1_E7c_theCallerChosenLatchDoesNotSurviveTheNextSettle() public {
        ema.setTVLEMA(MOVER, MOVER_TVL_LARGE);
        distributor.recordScore(MOVER);

        ema.setTVLEMA(CAPPED_A, CAPPED_TVL);
        distributor.recordScore(CAPPED_A);
        uint256 latchFirst = distributor.poolScore(CAPPED_A);

        ema.setTVLEMA(MOVER, MOVER_TVL_SMALL);
        distributor.recordScore(MOVER);

        ema.setTVLEMA(CAPPED_B, CAPPED_TVL);
        distributor.recordScore(CAPPED_B);
        uint256 latchSecond = distributor.poolScore(CAPPED_B);

        assertEq(gauges.poolEmissionCapBps(CAPPED_A), gauges.poolEmissionCapBps(CAPPED_B), "identical cap bps");
        assertEq(ema.tvlEMA(CAPPED_A), ema.tvlEMA(CAPPED_B), "identical TVL EMA inputs");
        assertEq(mult.getMultiplier(CAPPED_A), mult.getMultiplier(CAPPED_B), "identical multiplier inputs");

        assertGt(
            latchFirst,
            latchSecond,
            "premise: the earlier claim still latches the larger score at record time"
        );

        gauges.setApproved(CAPPED_A, false);

        vm.recordLogs();
        distributor.deregisterScore(CAPPED_A);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool clampBound = false;
        uint256 clampedFrom;
        uint256 clampedTo;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics.length == 2 &&
                logs[i].topics[0] == keccak256("EmissionCapApplied(address,uint256,uint256)") &&
                address(uint160(uint256(logs[i].topics[1]))) == CAPPED_A
            ) {
                clampBound = true;
                (clampedFrom, clampedTo) = abi.decode(logs[i].data, (uint256, uint256));
            }
        }

        assertTrue(clampBound, "the settle clamp re-derived the earlier claimant's latch");
        assertEq(clampedFrom, latchFirst, "it re-derived against that pool's own latch, not another value");
        assertLt(clampedTo, latchFirst, "the latch was corrected downward rather than honoured");
        assertLt(
            clampedTo,
            latchSecond,
            "and the ordering the caller purchased is inverted: the early claimant now holds less than the later one"
        );
    }

    /// @notice DONE-CRITERIA for E.7c per PP-D56 (v) as amended by (xviii), (xix) and (xx). The cap is
    ///         re-derived at the head of `_settlePool`, so a stored score that has drifted above its
    ///         limit is brought back to the limit on a path that does NOT re-score the pool, and
    ///         `EmissionCapApplied` is the only signal that it bound.
    /// @dev The settle driver is `claim`, chosen because it settles UNCONDITIONALLY at its head and then
    ///      returns at `amount == 0` before reaching the `MintRouterNotSet` guard, so a caller holding no
    ///      position settles the pool and exits cleanly. That matters for what this case proves: driving
    ///      the settle through `recordScore` would also fire the clamp, but the record-time clamp then
    ///      recomputes the score from its own inputs, leaving the settle clamp's effect invisible in the
    ///      final state and witnessed only by the event. Here the clamp's effect IS the final state.
    ///      `claim` reads `IERC20(pool).balanceOf`, so the capped pool is a real ERC20 rather than the
    ///      bare address the two reproduction cases above use; it is created locally so the shared
    ///      `setUp` is untouched and those two cases are unaffected. The expected limit is NOT re-derived
    ///      here: the assertion reads the realised SHARE back and compares it to the cap, which is the
    ///      exact inverse of the reproduction's `assertGt(shareAfterFall, CAP_FP)` a few lines above.
    function test_capEnforcedAtSettle() public {
        MockBpt cappedToken = new MockBpt();
        address cappedPool = address(cappedToken);
        gauges.setApproved(cappedPool, true);
        gauges.setCapBps(cappedPool, CAP_BPS);
        mult.setMultiplier(cappedPool, 1e18);

        ema.setTVLEMA(MOVER, MOVER_TVL_LARGE);
        distributor.recordScore(MOVER);

        ema.setTVLEMA(cappedPool, CAPPED_TVL);
        distributor.recordScore(cappedPool);

        uint256 latched = distributor.poolScore(cappedPool);
        uint256 shareAtLatch = (latched * 1e18) / distributor.totalScore();
        assertApproxEqAbs(shareAtLatch, CAP_FP, 10, "premise: at latch the realised share equals the cap");

        ema.setTVLEMA(MOVER, MOVER_TVL_SMALL);
        distributor.recordScore(MOVER);

        uint256 shareBeforeSettle = (latched * 1e18) / distributor.totalScore();
        assertGt(shareBeforeSettle, CAP_FP, "premise: the denominator fell and the stored share is over the cap");
        assertEq(distributor.poolScore(cappedPool), latched, "premise: the capped pool was never re-scored");

        vm.expectEmit(true, false, false, false, address(distributor));
        emit IEmissionDistributor.EmissionCapApplied(cappedPool, 0, 0);
        distributor.claim(cappedPool, address(this));

        uint256 clamped = distributor.poolScore(cappedPool);
        assertLt(clamped, latched, "the settle clamp reduced the stored score");

        uint256 shareAfterSettle = (clamped * 1e18) / distributor.totalScore();
        assertApproxEqAbs(shareAfterSettle, CAP_FP, 10, "the realised share is back at the cap after settle");

        distributor.claim(cappedPool, address(this));
        assertEq(distributor.poolScore(cappedPool), clamped, "idempotent: a second settle in the same interval writes nothing");
    }
}
