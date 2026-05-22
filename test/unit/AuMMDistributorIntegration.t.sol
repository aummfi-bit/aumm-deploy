// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AuMM} from "../../src/token/AuMM.sol";
import {IAuMM} from "../../src/token/IAuMM.sol";
import {IEmissionDistributor} from "../../src/emission/IEmissionDistributor.sol";
import {IGaugeRegistry} from "../../src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "../../src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "../../src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "../../src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "../../src/gauge/IEfficiencyOracle.sol";
import {AureumTime} from "../../src/lib/AureumTime.sol";
import {EmissionDistributorHarness} from "./harness/EmissionDistributorHarness.sol";
import {
    MockGaugeRegistry,
    MockEMASampler,
    MockCCBMultiplier,
    MockEfficiencyOracle,
    MockMiliariumRegistry
} from "./EmissionDistributor.t.sol";

/// @notice Real-AuMM integration test family per H-D36 — 4-test cohort exercising mock/real setMinter parity + halving.
/// @dev C-D11 two-flag-lock wired via `new AuMM(GENESIS_BLOCK_, address(this))` so this contract is the constructor
///      `_minterAdmin`; mock contracts imported by name from EmissionDistributor.t.sol (no inline redefinition);
///      distributor slot typed EmissionDistributorHarness per H-D34.
contract AuMMDistributorIntegrationTest is Test {
    uint256 internal constant GENESIS_BLOCK_ = 1_000_000;
    address internal constant GOV      = address(0xC0FE);
    address internal constant AUMT_REC = address(0xA0DC);
    address internal constant POOL_A   = address(0xA1);
    address internal constant USER_1   = address(0xE1);
    address internal constant USER_2   = address(0xE2);

    AuMM internal aumm;
    MockGaugeRegistry internal gauges;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockEfficiencyOracle internal effOracle;
    MockMiliariumRegistry internal miliReg;
    EmissionDistributorHarness internal distributor;

    function setUp() public virtual {
        aumm = new AuMM(GENESIS_BLOCK_, address(this));
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
        distributor.setAuMTContract(AUMT_REC);
        vm.roll(GENESIS_BLOCK_);
    }

    /// @notice setMinter — first call by minter admin succeeds and emits MinterSet with new minter address.
    function test_SetMinterHandoff_EmitsMinterSet() public {
        AuMM fresh = new AuMM(GENESIS_BLOCK_, address(this));
        vm.expectEmit(true, false, false, false);
        emit IAuMM.MinterSet(address(distributor));
        fresh.setMinter(address(distributor));
        assertEq(fresh.minter(), address(distributor));
    }

    /// @notice setMinter — second call reverts NotMinterAdmin (C-D11: _minterAdmin zeroed on first success).
    function test_RevertWhen_SetMinterCalledTwice() public {
        vm.expectRevert(AuMM.NotMinterAdmin.selector);
        aumm.setMinter(address(0xBEEF));
    }

    /// @notice claim — real AuMM mint path executes end-to-end; USER_1 receives minted AuMM after single-pool deposit + advance.
    function test_ClaimMintsRealAuMM_SinglePool() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 1);
        vm.prank(USER_1);
        distributor.claim(POOL_A, USER_1);
        assertEq(aumm.balanceOf(USER_1), 1e18);
    }

    /// @notice claim — H-D30 era-boundary cursor walk: 20-block straddle of firstHalvingBlock yields 14.5e18 — not 20e18 flat-rate.
    function test_ClaimAcrossHalvingBoundary_UsesRealBlockEmissionRate() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        uint256 firstHalving = AureumTime.firstHalvingBlock(GENESIS_BLOCK_);
        vm.roll(firstHalving - 10);
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(firstHalving + 10);
        vm.prank(USER_1);
        distributor.claim(POOL_A, USER_1);
        assertEq(aumm.balanceOf(USER_1), 14.5e18);
    }
}
