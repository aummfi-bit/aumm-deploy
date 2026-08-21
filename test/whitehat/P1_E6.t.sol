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
            GOV
        );

        effOracle.setEmissionsRecorder(address(distributor));
        gauges.setApproved(POOL, true);
        miliReg.setMiliarium(POOL, true);
        mult.setMultiplier(POOL, 1e18);
        vm.mockCall(POOL, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(0)));
        vm.roll(GENESIS_BLOCK_);
    }

    /// @notice The forfeiture: with every score self-cleared, a permissionless `claim` advances the
    ///         accrual cursor across an un-integrated window and the accumulator never moves.
    function test_E6_zeroTotalScoreWindowIsBurnedByOneClaim() public {
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
        assertEq(distributor.lastAccrualBlock(), block.number, "cursor advanced across the window");
        assertGt(distributor.lastAccrualBlock(), cursorBefore + 9_999, "cursor skipped 10,000 blocks");
        assertEq(distributor.accRewardPerScoreUnit(), accAfterHealthyAccrual, "nothing was integrated");
    }
}
