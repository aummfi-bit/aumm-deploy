// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {EfficiencyOracle} from "../../src/emission/EfficiencyOracle.sol";
import {ITVLOracle} from "../../src/ccb/ITVLOracle.sol";
import {AureumTime} from "../../src/lib/AureumTime.sol";

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
}
