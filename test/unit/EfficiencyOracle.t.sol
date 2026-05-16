// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {EfficiencyOracle} from "../../src/emission/EfficiencyOracle.sol";
import {ITVLOracle} from "../../src/ccb/ITVLOracle.sol";
import {AureumTime} from "../../src/lib/AureumTime.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Test-only ITVLOracle stub for EfficiencyOracle unit tests — linear `quoteSvZCHF` via settable per-token `rate` map; `tvl()` stubbed to 0 (unused by EfficiencyOracle per H-D10).
contract MockEfficiencyTVLOracle is ITVLOracle {
    mapping(address => uint256) public rate;

    function setRate(address token, uint256 rate18) external {
        rate[token] = rate18;
    }

    function quoteSvZCHF(address token, uint256 amountScaled18) external view override returns (uint256) {
        return (amountScaled18 * rate[token]) / 1e18;
    }

    function tvl(address) external pure override returns (uint256) {
        return 0;
    }
}

/// @notice Unit tests for EfficiencyOracle (concrete H-D10 implementation landed at H2b.1—H2b.5) — scaffold only at H2b.6a; test functions land at H2b.6b onward.
contract EfficiencyOracleTest is Test {
    address internal constant AUMM = address(0xA0);
    address internal constant GOV = address(0xC1);
    address internal constant FEE_REC = address(0xFE);
    address internal constant EMIT_REC = address(0xE7);
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant BLOCKS_PER_EPOCH = 100_800; // OQ-4 / FINDINGS L501

    EfficiencyOracle internal oracle;
    MockEfficiencyTVLOracle internal tvlMock;

    function setUp() public virtual {
        tvlMock = new MockEfficiencyTVLOracle();
        oracle = new EfficiencyOracle(tvlMock, AUMM, GENESIS_BLOCK, GOV);
        vm.startPrank(GOV);
        oracle.setFeeRecorder(FEE_REC);
        oracle.setEmissionsRecorder(EMIT_REC);
        vm.stopPrank();
        vm.roll(GENESIS_BLOCK);
    }

    function _addr(uint256 seed) internal pure returns (address) {
        return address(uint160(seed));
    }

    function _setRate(address token, uint256 rate18) internal {
        tvlMock.setRate(token, rate18);
    }

    function _rollToEpoch(uint256 epochIndex_) internal {
        vm.roll(GENESIS_BLOCK + epochIndex_ * BLOCKS_PER_EPOCH);
    }

    function _recordFees(address pool, address token, uint256 amountScaled18) internal {
        vm.prank(FEE_REC);
        oracle.recordFees(pool, token, amountScaled18);
    }

    function _recordEmissions(address pool, uint256 aummAmountScaled18) internal {
        vm.prank(EMIT_REC);
        oracle.recordEmissions(pool, aummAmountScaled18);
    }

    /* ---------- Constructor tests ---------- */

    function test_constructor_revertsOnZeroTvlOracle() public {
        vm.expectRevert(EfficiencyOracle.ZeroAddress.selector);
        new EfficiencyOracle(ITVLOracle(address(0)), AUMM, GENESIS_BLOCK, GOV);
    }

    function test_constructor_revertsOnZeroAuMM() public {
        vm.expectRevert(EfficiencyOracle.ZeroAddress.selector);
        new EfficiencyOracle(tvlMock, address(0), GENESIS_BLOCK, GOV);
    }

    function test_constructor_revertsOnZeroInitialGovernance() public {
        vm.expectRevert(EfficiencyOracle.ZeroAddress.selector);
        new EfficiencyOracle(tvlMock, AUMM, GENESIS_BLOCK, address(0));
    }

    function test_constructor_acceptsZeroGenesisBlock() public {
        EfficiencyOracle fresh = new EfficiencyOracle(tvlMock, AUMM, 0, GOV);
        assertEq(fresh.GENESIS_BLOCK(), 0);
    }

    function test_constructor_wiresImmutablesGovernanceAndDefaultsRecordersToZero() public {
        EfficiencyOracle fresh = new EfficiencyOracle(tvlMock, AUMM, GENESIS_BLOCK, GOV);
        assertEq(address(fresh.tvlOracle()), address(tvlMock));
        assertEq(fresh.AuMM(), AUMM);
        assertEq(fresh.GENESIS_BLOCK(), GENESIS_BLOCK);
        assertEq(fresh.governance(), GOV);
        assertEq(fresh.feeRecorder(), address(0));
        assertEq(fresh.emissionsRecorder(), address(0));
    }

    /* ---------- setGovernanceContract tests ---------- */

    function test_setGovernanceContract_happyPath_emitsAndUpdatesSlot() public {
        address newGov = _addr(0xBEEF);
        vm.expectEmit(true, true, false, true);
        emit EfficiencyOracle.GovernanceTransferred(GOV, newGov);
        vm.prank(GOV);
        oracle.setGovernanceContract(newGov);
        assertEq(oracle.governance(), newGov);
    }

    function test_setGovernanceContract_revertsOnZeroAddress() public {
        vm.prank(GOV);
        vm.expectRevert(EfficiencyOracle.ZeroAddress.selector);
        oracle.setGovernanceContract(address(0));
    }

    function test_setGovernanceContract_revertsOnNonGovernance() public {
        address rando = _addr(0xDEAD);
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(EfficiencyOracle.NotGovernance.selector, rando));
        oracle.setGovernanceContract(_addr(0xBEEF));
    }

    function test_setGovernanceContract_postHandoffShiftsAccess() public {
        address newGov = _addr(0xBEEF);
        vm.prank(GOV);
        oracle.setGovernanceContract(newGov);

        address newFeeRec = _addr(0xF1);
        vm.prank(newGov);
        oracle.setFeeRecorder(newFeeRec);
        assertEq(oracle.feeRecorder(), newFeeRec);

        vm.prank(GOV);
        vm.expectRevert(abi.encodeWithSelector(EfficiencyOracle.NotGovernance.selector, GOV));
        oracle.setFeeRecorder(_addr(0xF2));
    }

    /* ---------- setFeeRecorder + setEmissionsRecorder tests ---------- */

    function test_setFeeRecorder_happyPath_emitsAndUpdatesSlot() public {
        address newRec = _addr(0xF2);
        vm.expectEmit(true, true, true, true, address(oracle));
        emit EfficiencyOracle.FeeRecorderSet(FEE_REC, newRec);
        vm.prank(GOV);
        oracle.setFeeRecorder(newRec);
        assertEq(oracle.feeRecorder(), newRec);
    }

    function test_setFeeRecorder_acceptsZeroAddress() public {
        vm.expectEmit(true, true, true, true, address(oracle));
        emit EfficiencyOracle.FeeRecorderSet(FEE_REC, address(0));
        vm.prank(GOV);
        oracle.setFeeRecorder(address(0));
        assertEq(oracle.feeRecorder(), address(0));
    }

    function test_setFeeRecorder_revertsOnNonGovernance() public {
        address nonGov = _addr(0xDE);
        vm.expectRevert(abi.encodeWithSelector(EfficiencyOracle.NotGovernance.selector, nonGov));
        vm.prank(nonGov);
        oracle.setFeeRecorder(FEE_REC);
    }

    function test_setEmissionsRecorder_happyPath_emitsAndUpdatesSlot() public {
        address newRec = _addr(0xE8);
        vm.expectEmit(true, true, true, true, address(oracle));
        emit EfficiencyOracle.EmissionsRecorderSet(EMIT_REC, newRec);
        vm.prank(GOV);
        oracle.setEmissionsRecorder(newRec);
        assertEq(oracle.emissionsRecorder(), newRec);
    }

    function test_setEmissionsRecorder_acceptsZeroAddress() public {
        vm.expectEmit(true, true, true, true, address(oracle));
        emit EfficiencyOracle.EmissionsRecorderSet(EMIT_REC, address(0));
        vm.prank(GOV);
        oracle.setEmissionsRecorder(address(0));
        assertEq(oracle.emissionsRecorder(), address(0));
    }

    function test_setEmissionsRecorder_revertsOnNonGovernance() public {
        address nonGov = _addr(0xDE);
        vm.expectRevert(abi.encodeWithSelector(EfficiencyOracle.NotGovernance.selector, nonGov));
        vm.prank(nonGov);
        oracle.setEmissionsRecorder(EMIT_REC);
    }

    /* ---------- onlyFeeRecorder + onlyEmissionsRecorder access-control tests ---------- */

    function test_recordFees_revertsOnRandomCaller() public {
        address randomCaller = _addr(0xBAD);
        vm.expectRevert(abi.encodeWithSelector(EfficiencyOracle.NotFeeRecorder.selector, randomCaller));
        vm.prank(randomCaller);
        oracle.recordFees(_addr(0xCAFE), _addr(0xBEEF), 1_000e18);
    }

    function test_recordFees_revertsOnGovernanceCaller() public {
        vm.expectRevert(abi.encodeWithSelector(EfficiencyOracle.NotFeeRecorder.selector, GOV));
        vm.prank(GOV);
        oracle.recordFees(_addr(0xCAFE), _addr(0xBEEF), 1_000e18);
    }

    function test_recordFees_revertsAfterFeeRecorderDeprecation() public {
        vm.prank(GOV);
        oracle.setFeeRecorder(address(0));
        vm.expectRevert(abi.encodeWithSelector(EfficiencyOracle.NotFeeRecorder.selector, FEE_REC));
        vm.prank(FEE_REC);
        oracle.recordFees(_addr(0xCAFE), _addr(0xBEEF), 1_000e18);
    }

    function test_recordEmissions_revertsOnRandomCaller() public {
        address randomCaller = _addr(0xBAD);
        vm.expectRevert(abi.encodeWithSelector(EfficiencyOracle.NotEmissionsRecorder.selector, randomCaller));
        vm.prank(randomCaller);
        oracle.recordEmissions(_addr(0xCAFE), 1_000e18);
    }

    function test_recordEmissions_revertsOnGovernanceCaller() public {
        vm.expectRevert(abi.encodeWithSelector(EfficiencyOracle.NotEmissionsRecorder.selector, GOV));
        vm.prank(GOV);
        oracle.recordEmissions(_addr(0xCAFE), 1_000e18);
    }

    function test_recordEmissions_revertsAfterEmissionsRecorderDeprecation() public {
        vm.prank(GOV);
        oracle.setEmissionsRecorder(address(0));
        vm.expectRevert(abi.encodeWithSelector(EfficiencyOracle.NotEmissionsRecorder.selector, EMIT_REC));
        vm.prank(EMIT_REC);
        oracle.recordEmissions(_addr(0xCAFE), 1_000e18);
    }

    /* ---------- recordFees + recordEmissions mechanics tests ---------- */

    function test_recordFees_happyPath_emitsFeesRecordedWithCorrectConversion() public {
        address pool = _addr(0xCAFE);
        address token = _addr(0x7010);
        _setRate(token, 2e18);
        uint256 amount = 5e18;
        uint256 expectedSvZCHF = (amount * 2e18) / 1e18;
        vm.expectEmit(true, true, true, true, address(oracle));
        emit EfficiencyOracle.FeesRecorded(pool, token, amount, expectedSvZCHF);
        _recordFees(pool, token, amount);
    }

    function test_recordFees_unmappedToken_emitsZeroSvZCHF() public {
        address pool = _addr(0xCAFE);
        address unmappedToken = _addr(0xBEEF);
        uint256 amount = 5e18;
        vm.expectEmit(true, true, true, true, address(oracle));
        emit EfficiencyOracle.FeesRecorded(pool, unmappedToken, amount, 0);
        _recordFees(pool, unmappedToken, amount);
    }

    function test_recordFees_zeroAmount_emitsZeroSvZCHF() public {
        address pool = _addr(0xCAFE);
        address token = _addr(0x7010);
        _setRate(token, 2e18);
        vm.expectEmit(true, true, true, true, address(oracle));
        emit EfficiencyOracle.FeesRecorded(pool, token, 0, 0);
        _recordFees(pool, token, 0);
    }

    function test_recordEmissions_happyPath_emitsEmissionsRecordedWithCorrectConversion() public {
        address pool = _addr(0xCAFE);
        _setRate(AUMM, 3e18);
        uint256 aummAmount = 10e18;
        uint256 expectedSvZCHF = (aummAmount * 3e18) / 1e18;
        vm.expectEmit(true, true, true, true, address(oracle));
        emit EfficiencyOracle.EmissionsRecorded(pool, aummAmount, expectedSvZCHF);
        _recordEmissions(pool, aummAmount);
    }

    function test_recordEmissions_unmappedAuMM_emitsZeroSvZCHF() public {
        address pool = _addr(0xCAFE);
        uint256 aummAmount = 10e18;
        vm.expectEmit(true, true, true, true, address(oracle));
        emit EfficiencyOracle.EmissionsRecorded(pool, aummAmount, 0);
        _recordEmissions(pool, aummAmount);
    }

    function test_recordEmissions_zeroAmount_emitsZeroSvZCHF() public {
        address pool = _addr(0xCAFE);
        _setRate(AUMM, 3e18);
        vm.expectEmit(true, true, true, true, address(oracle));
        emit EfficiencyOracle.EmissionsRecorded(pool, 0, 0);
        _recordEmissions(pool, 0);
    }

    /* ---------- _ensureCurrentEpoch rollover + ring slot tests ---------- */

    function test_ensureCurrentEpoch_sameEpoch_accumulatorPreservesAcrossCalls() public {
        address pool = _addr(0xCAFE);
        address token = _addr(0x7010);
        _setRate(token, 1e18);
        _recordFees(pool, token, 100e18);
        _recordFees(pool, token, 100e18);
        _rollToEpoch(1);
        vm.expectEmit(true, true, true, true, address(oracle));
        emit EfficiencyOracle.EpochFinalized(pool, 0, 200e18, 0);
        _recordFees(pool, token, 0);
    }

    function test_ensureCurrentEpoch_postFlushAccumulatorResets() public {
        address pool = _addr(0xCAFE);
        address token = _addr(0x7010);
        _setRate(token, 1e18);
        _recordFees(pool, token, 100e18);
        _rollToEpoch(1);
        _recordFees(pool, token, 50e18);
        _rollToEpoch(2);
        vm.expectEmit(true, true, true, true, address(oracle));
        emit EfficiencyOracle.EpochFinalized(pool, 1, 50e18, 0);
        _recordFees(pool, token, 0);
    }

    function test_ensureCurrentEpoch_multiEpochJump_singleFlushForPriorAccEpoch() public {
        address pool = _addr(0xCAFE);
        address token = _addr(0x7010);
        _setRate(token, 1e18);
        _recordFees(pool, token, 100e18);
        _rollToEpoch(5);
        vm.recordLogs();
        _recordFees(pool, token, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("EpochFinalized(address,uint256,uint256,uint256)");
        uint256 count;
        Vm.Log memory matchingLog;
        bool foundMatch;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
                count++;
                matchingLog = logs[i];
                foundMatch = true;
            }
        }
        assertEq(count, 1);
        assertTrue(foundMatch);
        address logPool = address(uint160(uint256(matchingLog.topics[1])));
        uint256 logEpoch = uint256(matchingLog.topics[2]);
        assertEq(logPool, pool);
        assertEq(logEpoch, 0);
        (uint256 num, uint256 denom) = abi.decode(matchingLog.data, (uint256, uint256));
        assertEq(num, 100e18);
        assertEq(denom, 0);
    }

    function test_ensureCurrentEpoch_phantomEntry_firstActivationAtNonZeroEpoch() public {
        address freshPool = _addr(0xCAFE);
        address token = _addr(0x7010);
        _setRate(token, 1e18);
        _rollToEpoch(5);
        vm.expectEmit(true, true, true, true, address(oracle));
        emit EfficiencyOracle.EpochFinalized(freshPool, 0, 0, 0);
        vm.expectEmit(true, true, true, true, address(oracle));
        emit EfficiencyOracle.FeesRecorded(freshPool, token, 100e18, 100e18);
        _recordFees(freshPool, token, 100e18);
    }

    function test_ensureCurrentEpoch_perPoolIsolation() public {
        address poolA = _addr(0xA);
        address poolB = _addr(0xB);
        address token = _addr(0x7010);
        _setRate(token, 1e18);
        _recordFees(poolA, token, 100e18);
        _recordFees(poolB, token, 50e18);
        _rollToEpoch(1);
        vm.expectEmit(true, true, true, true, address(oracle));
        emit EfficiencyOracle.EpochFinalized(poolA, 0, 100e18, 0);
        _recordFees(poolA, token, 0);
        vm.expectEmit(true, true, true, true, address(oracle));
        emit EfficiencyOracle.EpochFinalized(poolB, 0, 50e18, 0);
        _recordFees(poolB, token, 0);
    }
}
