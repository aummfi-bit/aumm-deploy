// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AuMM} from "../../src/token/AuMM.sol";
import {IAuMM} from "../../src/token/IAuMM.sol";
import {EmissionDistributor} from "../../src/emission/EmissionDistributor.sol";
import {IGaugeRegistry} from "../../src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "../../src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "../../src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "../../src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "../../src/gauge/IEfficiencyOracle.sol";
import {
    MockGaugeRegistry,
    MockEMASampler,
    MockCCBMultiplier,
    MockEfficiencyOracle,
    MockMiliariumRegistry
} from "../unit/EmissionDistributor.t.sol";
import {MockRegisteredVault} from "../mocks/MockRegisteredVault.sol";

/// @notice PP3.2 reproduction PoC for root cause E.6 — `_accrueGlobal`'s `totalScore == 0` branch
///         advances `lastAccrualBlock` WITHOUT integrating, so any window in which every pool's
///         score has self-cleared destroys that window's entire LP emission tranche. One
///         permissionless `claim` triggers it; `lastAccrualBlock` is monotonic, so nothing recovers.
/// @dev Unit-scoped deliberately: the defect is pure accounting inside `EmissionDistributor` and
///      touches no Vault path. Real distributor, real AuMM; the five peripheral mocks are the
///      already-neutralized ones from the unit suite. PP-D33 orders the prefix-sum before the
///      cursor fix, so this PoC pins the pre-fix behaviour both rungs are measured against.
contract P1_E6_Test is Test {
    uint256 internal constant GENESIS_BLOCK_ = 1_000_000;
    address internal constant GOV = address(0xC0FE);
    address internal constant POOL = address(0xA1);
    address internal constant MALLORY = address(0xBAD);

    AuMM internal aumm;
    MockGaugeRegistry internal gauges;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockEfficiencyOracle internal effOracle;
    MockMiliariumRegistry internal miliReg;
    EmissionDistributor internal distributor;

    function setUp() public {
        aumm = new AuMM(GENESIS_BLOCK_, address(this));
        gauges = new MockGaugeRegistry();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        effOracle = new MockEfficiencyOracle();
        miliReg = new MockMiliariumRegistry();

        distributor = new EmissionDistributor(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK_,
            GOV,
            address(new MockRegisteredVault())
        );

        effOracle.setEmissionsRecorder(address(distributor));
        gauges.setApproved(POOL, true);
        miliReg.setMiliarium(POOL, true);
        mult.setMultiplier(POOL, 1e18);
        vm.mockCall(POOL, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(0)));
        vm.roll(GENESIS_BLOCK_);
    }

    /// @notice The fix (PP-D47 / E.6): with every score self-cleared AFTER a completed accrual, a
    ///         permissionless `claim` no longer advances the cursor. The window stays PENDING and the next
    ///         accrual carrying live scores integrates it in full, so nothing is forfeited and no caller can
    ///         book the loss at a moment of their choosing. The recovery leg deliberately takes TWO
    ///         `recordScore` calls, which is not incidental: `_accrueGlobal` runs at step 2 and the score
    ///         write at step 10, so the score-restoring call still observes `totalScore == 0` and holds,
    ///         and the drain lands on the call after it. That ordering is why PP-D47 forks on cold start.
    function test_zeroTotalScoreWindowDoesNotForfeit() public {
        ema.setTVLEMA(POOL, 1_000e18);
        distributor.recordScore(POOL);
        assertGt(distributor.totalScore(), 0, "precondition: a scored pool exists");
        vm.roll(block.number + 1_000);
        distributor.recordScore(POOL);
        uint256 accAfterHealthyAccrual = distributor.accRewardPerScoreUnit();
        assertGt(accAfterHealthyAccrual, 0, "control: accrual integrates while totalScore > 0");
        ema.setTVLEMA(POOL, 0);
        distributor.recordScore(POOL);
        assertEq(distributor.totalScore(), 0, "score self-cleared to zero");
        uint256 cursorBefore = distributor.lastAccrualBlock();

        vm.roll(block.number + 10_000);
        vm.prank(MALLORY);
        distributor.claim(POOL, MALLORY);

        assertEq(distributor.lastAccrualBlock(), cursorBefore, "cursor moved across the pending window");
        assertLt(distributor.lastAccrualBlock(), block.number, "cursor was not held behind the current block");
        assertEq(distributor.accRewardPerScoreUnit(), accAfterHealthyAccrual, "accumulator moved with no live score");

        ema.setTVLEMA(POOL, 1_000e18);
        distributor.recordScore(POOL);
        assertEq(distributor.lastAccrualBlock(), cursorBefore, "the score-restoring call drained early");

        distributor.recordScore(POOL);
        assertEq(distributor.lastAccrualBlock(), block.number, "cursor did not catch up once scores returned");
        assertGt(distributor.accRewardPerScoreUnit(), accAfterHealthyAccrual, "the pending window was never integrated");
    }
}
