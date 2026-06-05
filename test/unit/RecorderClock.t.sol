// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IAuMM} from "../../src/token/IAuMM.sol";
import {IGaugeRegistry} from "../../src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "../../src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "../../src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "../../src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "../../src/gauge/IEfficiencyOracle.sol";
import {EmissionDistributorHarness} from "./harness/EmissionDistributorHarness.sol";
import {
    MockAuMM,
    MockGaugeRegistry,
    MockEMASampler,
    MockCCBMultiplier,
    MockEfficiencyOracle,
    MockMiliariumRegistry
} from "./EmissionDistributor.t.sol";

/// @notice Unit tests for the EmissionDistributor `effectiveQualBlock` qualification clock (I4.3 / I-D14) — fresh-start on first deposit, deposit-weighted-average top-up, reset on any withdrawal, and the per-pool recorder hook-gate (I-D9). Reuses the `EmissionDistributor.t.sol` mock harness; `setUp` mirrors `EmissionDistributorTest` with `POOL_A` bound to `AUMT_REC`.
contract RecorderClockTest is Test {
    uint256 internal constant GENESIS_BLOCK_ = 1_000_000;
    address internal constant GOV = address(0xC0FE);
    address internal constant AUMT_REC = address(0xA0DC);
    address internal constant POOL_A = address(0xA1);
    address internal constant POOL_B = address(0xB2);
    address internal constant USER_1 = address(0xE1);
    address internal constant USER_2 = address(0xE2);

    MockAuMM internal aumm;
    MockGaugeRegistry internal gauges;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockEfficiencyOracle internal effOracle;
    MockMiliariumRegistry internal miliReg;
    EmissionDistributorHarness internal distributor;

    function setUp() public virtual {
        aumm = new MockAuMM();
        gauges = new MockGaugeRegistry();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        effOracle = new MockEfficiencyOracle();
        miliReg = new MockMiliariumRegistry();
        distributor = new EmissionDistributorHarness(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK_,
            GOV
        );
        aumm.setMinter(address(distributor));
        effOracle.setEmissionsRecorder(address(distributor));
        vm.prank(GOV);
        distributor.setAuMTContractForPool(POOL_A, AUMT_REC);
        vm.roll(GENESIS_BLOCK_);
    }

    /// @notice First `recordDeposit` for a (pool, user) whose `effectiveQualBlock` is zero fresh-starts the qualification clock to `block.number` (I4.3 / I-D14 fresh-start branch) and accrues `userLP`. Proven against a non-genesis block so the clock is shown to track the live block, not a constant.
    function test_RecordDeposit_FirstDepositFreshStartsEffectiveQualBlock() public {
        uint256 depositBlock = GENESIS_BLOCK_ + 5_000;
        vm.roll(depositBlock);
        assertEq(distributor.effectiveQualBlock(POOL_A, USER_1), 0);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        assertEq(distributor.effectiveQualBlock(POOL_A, USER_1), depositBlock);
        assertEq(distributor.userLP(POOL_A, USER_1), 100e18);
    }

    /// @notice A second `recordDeposit` (`effectiveQualBlock != 0`) blends the qualification clock by the deposit-weighted average per I4.3 / I-D14 — a top-up advances the clock proportionally toward the later block, it does not reset. With 100e18 at block G and 300e18 at block G+4000, the 3:1 weighting blends to (100·G + 300·(G+4000)) / 400 = G+3000 exactly (no truncation).
    function test_RecordDeposit_TopUpBlendsEffectiveQualBlockByWeightedAverage() public {
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        assertEq(distributor.effectiveQualBlock(POOL_A, USER_1), GENESIS_BLOCK_);

        vm.roll(GENESIS_BLOCK_ + 4_000);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 300e18);

        assertEq(distributor.effectiveQualBlock(POOL_A, USER_1), GENESIS_BLOCK_ + 3_000);
        assertEq(distributor.userLP(POOL_A, USER_1), 400e18);
    }

    /// @notice `recordWithdrawal` of any nonzero amount — even a partial 1% withdrawal that leaves `userLP > 0` — resets `effectiveQualBlock` to 0 per §viii / I-D14 ("remove any amount, even 1%, drops to zero"). The 99e18 remaining stake is un-qualified until a fresh deposit restarts the clock.
    function test_RecordWithdrawal_PartialResetsEffectiveQualBlockToZero() public {
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        assertEq(distributor.effectiveQualBlock(POOL_A, USER_1), GENESIS_BLOCK_);

        vm.roll(GENESIS_BLOCK_ + 50_000);
        vm.prank(AUMT_REC);
        distributor.recordWithdrawal(POOL_A, USER_1, 1e18);

        assertEq(distributor.effectiveQualBlock(POOL_A, USER_1), 0);
        assertEq(distributor.userLP(POOL_A, USER_1), 99e18);
    }

    /// @notice After a partial withdrawal has reset `effectiveQualBlock` to 0 while `userLP` stays positive, the next `recordDeposit` takes the FRESH-START branch — keyed on `effectiveQualBlock == 0`, NOT `oldAmount == 0` — and restarts the clock at `block.number`. This is the I4.3-pre over-qualification vector (PLAN L128): had the branch keyed on `oldAmount`, the re-deposit would compute a near-zero weighted average `(99e18 * 0 + 50e18 * redepositBlock) / 149e18` (~0.336 * redepositBlock, a block far in the past) that would instantly over-qualify the un-aged remaining capital. The fresh-start keeps the position correctly un-aged (`block.number - effectiveQualBlock == 0`).
    function test_RecordDeposit_AfterPartialWithdrawalFreshStartsNotBlends() public {
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);

        vm.roll(GENESIS_BLOCK_ + 50_000);
        vm.prank(AUMT_REC);
        distributor.recordWithdrawal(POOL_A, USER_1, 1e18);
        assertEq(distributor.effectiveQualBlock(POOL_A, USER_1), 0);
        assertEq(distributor.userLP(POOL_A, USER_1), 99e18);

        uint256 redepositBlock = GENESIS_BLOCK_ + 60_000;
        vm.roll(redepositBlock);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 50e18);

        assertEq(distributor.effectiveQualBlock(POOL_A, USER_1), redepositBlock);
        assertEq(distributor.userLP(POOL_A, USER_1), 149e18);
        assertEq(block.number - distributor.effectiveQualBlock(POOL_A, USER_1), 0);
    }
}
