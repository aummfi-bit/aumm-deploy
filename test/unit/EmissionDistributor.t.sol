// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {EmissionDistributor} from "../../src/emission/EmissionDistributor.sol";
import {AuMMMinterRouter} from "../../src/token/AuMMMinterRouter.sol";
import {IEmissionDistributor} from "../../src/emission/IEmissionDistributor.sol";
import {IAuMM} from "../../src/token/IAuMM.sol";
import {IGaugeRegistry} from "../../src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "../../src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "../../src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "../../src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "../../src/gauge/IEfficiencyOracle.sol";
import {IIncendiaryRegistry} from "../../src/incendiary/IIncendiaryRegistry.sol";
import {AureumTime} from "../../src/lib/AureumTime.sol";
import {EmissionDistributorHarness} from "./harness/EmissionDistributorHarness.sol";

contract MockAuMM is ERC20, IAuMM {
    address private _minter;
    uint256 public rate;

    constructor() ERC20("AuMM", "AUMM") {
        rate = 1e18;
    }

    function setRate(uint256 rate_) external {
        rate = rate_;
    }

    function GENESIS_BLOCK() external pure override returns (uint256) {
        return 1_000_000;
    }

    function MAX_SUPPLY() external pure override returns (uint256) {
        return 21_000_000 * 1e18;
    }

    function GENESIS_RATE() external pure override returns (uint256) {
        return 1e18;
    }

    function blockEmissionRate(uint256) external view override returns (uint256) {
        return rate;
    }

    function minter() external view override returns (address) {
        return _minter;
    }

    function mint(address to, uint256 amount) external override {
        require(msg.sender == _minter, "MockAuMM: not minter");
        _mint(to, amount);
    }

    function setMinter(address newMinter) external override {
        _minter = newMinter;
        emit MinterSet(newMinter);
    }
}

contract MockGaugeRegistry is IGaugeRegistry {
    mapping(address => bool) private _approved;

    function setApproved(address gauge, bool flag) external {
        _approved[gauge] = flag;
    }

    function isGaugeApproved(address gauge) external view override returns (bool) {
        return _approved[gauge];
    }

    function gaugeStatus(address) external view override returns (GaugeStatus status) {}

    function activateGauge(address) external override {}

    function registerGaugeFromComposition(address) external override {}

    function seedFoundingPool(address) external override {}

    function seedFoundingPools(address[] calldata) external override {}

    function revokeGauge(address) external override {}

    function setGovernanceContract(address) external override {}
}

contract MockEMASampler is IEMASampler {
    mapping(address => uint256) private _tvl;

    function setTVLEMA(address pool, uint256 v) external {
        _tvl[pool] = v;
    }

    function tvlEMA(address pool) external view override returns (uint256) {
        return _tvl[pool];
    }

    function lastEMAUpdateBlock(address) external pure override returns (uint256) {
        return 0;
    }
}

contract MockCCBMultiplier is ICCBMultiplier {
    mapping(address => uint256) private _mult;

    function setMultiplier(address pool, uint256 m) external {
        _mult[pool] = m;
    }

    function getMultiplier(address pool) external view override returns (uint256) {
        return _mult[pool];
    }
}

contract MockEfficiencyOracle is IEfficiencyOracle {
    address public emissionsRecorder;
    bool public revertOnRecord;

    struct Call {
        address pool;
        uint256 amount;
    }

    Call[] public calls;

    function setEmissionsRecorder(address newRecorder) external {
        emissionsRecorder = newRecorder;
    }

    function setRevertOnRecord(bool flag) external {
        revertOnRecord = flag;
    }

    function recordEmissions(address pool, uint256 aummAmountScaled18) external override {
        if (revertOnRecord) revert("MockEfficiencyOracle: revert toggle");
        require(msg.sender == emissionsRecorder, "MockEfficiencyOracle: not recorder");
        calls.push(Call(pool, aummAmountScaled18));
    }

    function efficiencyInputs(address) external pure override returns (uint256, uint256) {
        return (0, 0);
    }

    function callsLength() external view returns (uint256) {
        return calls.length;
    }

    function callAt(uint256 i) external view returns (address pool_, uint256 amount_) {
        return (calls[i].pool, calls[i].amount);
    }
}

contract MockMiliariumRegistry is IMiliariumRegistry {
    mapping(address => bool) public miliariumFlag;
    address[] internal _miliariumPools;

    function setMiliarium(address pool, bool flag) external {
        if (flag && !miliariumFlag[pool]) { _miliariumPools.push(pool); }
        miliariumFlag[pool] = flag;
    }

    function isMiliarium(address pool) external view override returns (bool) {
        return miliariumFlag[pool];
    }

    function miliariumPoolsCount() external view override returns (uint256) {
        return _miliariumPools.length;
    }

    function miliariumPoolAt(uint256 index) external view override returns (address) {
        return _miliariumPools[index];
    }
}

/// @notice Unit tests for EmissionDistributor (concrete H-D15—H-D25 implementation landed at H4.1—H4.7c) — scaffold only at H4.8.1; test functions land at H4.8.2 onward.
contract EmissionDistributorTest is Test {
    uint256 internal constant GENESIS_BLOCK_ = 1_000_000;
    address internal constant GOV = address(0xC0FE);
    address internal constant AUMT_REC = address(0xA0DC);
    address internal constant POOL_A = address(0xA1);
    address internal constant POOL_B = address(0xB2);
    address internal constant USER_1 = address(0xE1);
    address internal constant USER_2 = address(0xE2);
    address internal constant DUMMY_CHANNEL = address(0xC4A9);

    MockAuMM internal aumm;
    MockGaugeRegistry internal gauges;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockEfficiencyOracle internal effOracle;
    MockMiliariumRegistry internal miliReg;
    EmissionDistributorHarness internal distributor;
    AuMMMinterRouter internal router;

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
        router = new AuMMMinterRouter(IAuMM(address(aumm)), DUMMY_CHANNEL, address(distributor));
        aumm.setMinter(address(router));
        vm.prank(GOV);
        distributor.setMintRouter(address(router));
        effOracle.setEmissionsRecorder(address(distributor));
        vm.prank(GOV);
        distributor.setAuMTContractForPool(POOL_A, AUMT_REC);
        vm.roll(GENESIS_BLOCK_);
    }

    function _addr(uint256 seed) internal returns (address) {
        return makeAddr(vm.toString(seed));
    }

    function _rollTo(uint256 blockNumber) internal {
        vm.roll(blockNumber);
    }

    function _freshUnboundDistributor() internal returns (EmissionDistributor) {
        return new EmissionDistributor(IAuMM(address(aumm)), IGaugeRegistry(address(gauges)), IEMASampler(address(ema)), ICCBMultiplier(address(mult)), IEfficiencyOracle(address(effOracle)), IMiliariumRegistry(address(miliReg)), GENESIS_BLOCK_, GOV);
    }

    /* ---------- Constructor tests (H-D14 / H-D16 / H-D21 / H-D22) ---------- */

    /// @notice Reverts `ZeroAddress` when the AuMM constructor parameter is zero.
    function test_RevertWhen_ConstructedWithZeroAuMM() public {
        vm.expectRevert(IEmissionDistributor.ZeroAddress.selector);
        new EmissionDistributor(
            IAuMM(address(0)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK_,
            GOV
        );
    }

    /// @notice Reverts `ZeroAddress` when the gauge registry constructor parameter is zero.
    function test_RevertWhen_ConstructedWithZeroGaugeRegistry() public {
        vm.expectRevert(IEmissionDistributor.ZeroAddress.selector);
        new EmissionDistributor(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(0)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK_,
            GOV
        );
    }

    /// @notice Reverts `ZeroAddress` when the EMA sampler constructor parameter is zero.
    function test_RevertWhen_ConstructedWithZeroEMASampler() public {
        vm.expectRevert(IEmissionDistributor.ZeroAddress.selector);
        new EmissionDistributor(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(0)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK_,
            GOV
        );
    }

    /// @notice Reverts `ZeroAddress` when the CCB multiplier constructor parameter is zero.
    function test_RevertWhen_ConstructedWithZeroCCBMultiplier() public {
        vm.expectRevert(IEmissionDistributor.ZeroAddress.selector);
        new EmissionDistributor(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(0)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK_,
            GOV
        );
    }

    /// @notice Reverts `ZeroAddress` when the efficiency oracle constructor parameter is zero.
    function test_RevertWhen_ConstructedWithZeroEfficiencyOracle() public {
        vm.expectRevert(IEmissionDistributor.ZeroAddress.selector);
        new EmissionDistributor(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(0)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK_,
            GOV
        );
    }

    /// @notice Reverts `ZeroAddress` when the Miliarium registry constructor parameter is zero.
    function test_RevertWhen_ConstructedWithZeroMiliariumRegistry() public {
        vm.expectRevert(IEmissionDistributor.ZeroAddress.selector);
        new EmissionDistributor(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(0)),
            GENESIS_BLOCK_,
            GOV
        );
    }

    /// @notice Reverts `ZeroAddress` when the initial governance constructor parameter is zero.
    function test_RevertWhen_ConstructedWithZeroInitialGovernance() public {
        vm.expectRevert(IEmissionDistributor.ZeroAddress.selector);
        new EmissionDistributor(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK_,
            address(0)
        );
    }

    /// @notice Asserts the setUp-deployed distributor wires all seven immutables to the mock dependencies and genesis block constant.
    function test_Constructor_WiresImmutables() public {
        assertEq(address(distributor.AuMM()), address(aumm));
        assertEq(address(distributor._gaugeRegistry()), address(gauges));
        assertEq(address(distributor._emaSampler()), address(ema));
        assertEq(address(distributor._ccbMultiplier()), address(mult));
        assertEq(address(distributor._efficiencyOracle()), address(effOracle));
        assertEq(address(distributor._miliariumRegistry()), address(miliReg));
        assertEq(distributor.GENESIS_BLOCK(), GENESIS_BLOCK_);
    }

    /// @notice Asserts the setUp-deployed distributor initializes governance, lastAccrualBlock, and all three global accumulators to their constructor defaults.
    function test_Constructor_InitsStorageSlots() public {
        assertEq(distributor.governance(), GOV);
        assertEq(distributor.lastAccrualBlock(), GENESIS_BLOCK_);
        assertEq(distributor.accRewardPerScoreUnit(), 0);
        assertEq(distributor.totalScore(), 0);
        assertEq(distributor.f5Total(), 0);
    }

    /* ---------- Governance setter tests (H-D14 / H-D16) ---------- */

    /// @notice Rejects `setGovernanceContract` when the caller is not the current governance address — guards the onlyGovernance modifier.
    function test_RevertWhen_SetGovernanceContractCallerNotGovernance() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(IEmissionDistributor.NotGovernance.selector, address(0xBEEF)));
        distributor.setGovernanceContract(address(0x1234));
    }

    /// @notice Rejects `setGovernanceContract(address(0))` — new governance must be non-zero per H-D14 invariant.
    function test_RevertWhen_SetGovernanceContractZeroAddress() public {
        vm.prank(GOV);
        vm.expectRevert(IEmissionDistributor.ZeroAddress.selector);
        distributor.setGovernanceContract(address(0));
    }

    /// @notice Confirms `setGovernanceContract` writes the new address to the governance storage slot.
    function test_SetGovernanceContract_UpdatesSlot() public {
        vm.prank(GOV);
        distributor.setGovernanceContract(address(0xC0DE));
        assertEq(distributor.governance(), address(0xC0DE));
    }

    /// @notice Confirms `setGovernanceContract` emits `GovernanceTransferred` with the correct old and new governance indexed topics.
    function test_SetGovernanceContract_EmitsGovernanceTransferred() public {
        vm.expectEmit(true, true, false, false);
        emit IEmissionDistributor.GovernanceTransferred(GOV, address(0xC0DE));
        vm.prank(GOV);
        distributor.setGovernanceContract(address(0xC0DE));
    }

    /// @notice Rejects `setAuMTContractForPool` when the caller is not the current governance address — confirms the setter is onlyGovernance-gated, not onlyAuMTContract-gated.
    function test_RevertWhen_SetAuMTContractForPoolCallerNotGovernance() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(IEmissionDistributor.NotGovernance.selector, address(0xBEEF)));
        distributor.setAuMTContractForPool(POOL_A, address(0x1234));
    }

    /// @notice Confirms a freshly-constructed EmissionDistributor — before any `setAuMTContractForPool` call — holds `auMTContractByPool[POOL_A] == address(0)`, the I-D9 pre-binding default-zero posture.
    function test_Constructor_AuMTContractByPoolDefaultsZero() public {
        EmissionDistributor freshDistributor = new EmissionDistributor(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK_,
            GOV
        );
        assertEq(freshDistributor.auMTContractByPool(POOL_A), address(0));
    }

    /// @notice Reverts ZeroAddress when setAuMTContractForPool is called with newAuMTContract == address(0) — confirms I-D9 removed the H-D16 zero-address safety valve in favor of mandatory-non-zero binding (mirrors setGovernanceContract H-D14).
    function test_RevertWhen_SetAuMTContractForPoolZeroAuMT() public {
        vm.prank(GOV);
        vm.expectRevert(IEmissionDistributor.ZeroAddress.selector);
        distributor.setAuMTContractForPool(POOL_A, address(0));
    }

    /// @notice Confirms `setAuMTContractForPool` writes the new address to the auMTContractByPool[pool] slot and emits `AuMTContractBound` with the pool and newAuMTContract addresses as indexed topics. Uses POOL_B (unbound in setUp) since POOL_A is one-shot-locked to AUMT_REC.
    function test_SetAuMTContractForPool_BindsSlotAndEmits() public {
        vm.expectEmit(true, true, false, false);
        emit IEmissionDistributor.AuMTContractBound(POOL_B, address(0xC0DE));
        vm.prank(GOV);
        distributor.setAuMTContractForPool(POOL_B, address(0xC0DE));
        assertEq(distributor.auMTContractByPool(POOL_B), address(0xC0DE));
    }

    /// @notice Reverts AuMTAlreadyBound when setAuMTContractForPool is called for a pool that already has a non-zero auMTContractByPool[pool] binding — guards the I-D9 one-shot semantic (mirrors H-D5 hook setAuMTForPool one-shot per I-D5).
    function test_RevertWhen_SetAuMTContractForPoolAlreadyBound() public {
        vm.prank(GOV);
        vm.expectRevert(abi.encodeWithSelector(IEmissionDistributor.AuMTAlreadyBound.selector, POOL_A));
        distributor.setAuMTContractForPool(POOL_A, address(0xC0DE));
    }

    /* ---------- Score producer tests (H-D17 / H-D19) ---------- */

    /// @notice Reverts `NotApproved` when `recordScore` is called for a pool that has never been gauge-approved — guards the H-D17 (a) gate on initial state.
    function test_RevertWhen_RecordScoreGaugeNotApproved() public {
        vm.expectRevert(abi.encodeWithSelector(IEmissionDistributor.NotApproved.selector, POOL_A));
        distributor.recordScore(POOL_A);
    }

    /// @notice Reverts `NotApproved` when `recordScore` is called after gauge approval is revoked — confirms the H-D17 / H-D31 (a) gate fires on post-revoke attempts, not only on never-approved pools; vm.roll past year1EndBlock — enters α=1e18 continuous regime per H-D32 / H-D33.
    function test_RevertWhen_RecordScoreRevokedGaugeAfterApproval() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        gauges.setApproved(POOL_A, false);
        vm.expectRevert(abi.encodeWithSelector(IEmissionDistributor.NotApproved.selector, POOL_A));
        distributor.recordScore(POOL_A);
    }

    /// @notice Confirms the first `recordScore` call writes `poolScore`, sets `totalScore`, and emits `ScoreUpdated` with oldScore == 0 and newScore == tvlEMA — happy-path H-D17 / H-D31 state-and-event in one pass; vm.roll past year1EndBlock — enters α=1e18 continuous regime per H-D32 / H-D33.
    function test_RecordScore_FirstWriteUpdatesStateAndEmits() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        vm.expectEmit(true, false, false, true);
        emit IEmissionDistributor.ScoreUpdated(POOL_A, 0, 100e18);
        distributor.recordScore(POOL_A);
        assertEq(distributor.poolScore(POOL_A), 100e18);
        assertEq(distributor.totalScore(), 100e18);
        assertEq(distributor.f5Score(POOL_A), 100e18);
        assertEq(distributor.f5Total(), 100e18);
    }

    /// @notice Confirms `recordScore` succeeds when called by an arbitrary non-governance address — verifies the H-D17 / H-D31 permissionless entry point; vm.roll past year1EndBlock — enters α=1e18 continuous regime per H-D32 / H-D33.
    function test_RecordScore_PermissionlessCallerSucceeds() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        vm.prank(address(0xBADC0DE));
        distributor.recordScore(POOL_A);
        assertEq(distributor.poolScore(POOL_A), 100e18);
        assertEq(distributor.totalScore(), 100e18);
        assertEq(distributor.f5Score(POOL_A), 100e18);
        assertEq(distributor.f5Total(), 100e18);
    }

    /// @notice Confirms a second `recordScore` call with a higher tvlEMA increases both `poolScore` and `totalScore` by the positive signed delta — H-D19 / H-D31 upward adjustment path; vm.roll past year1EndBlock — enters α=1e18 continuous regime per H-D32 / H-D33.
    function test_RecordScore_SecondWriteIncreaseAdjustsTotalScoreUp() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        ema.setTVLEMA(POOL_A, 150e18);
        distributor.recordScore(POOL_A);
        assertEq(distributor.poolScore(POOL_A), 150e18);
        assertEq(distributor.totalScore(), 150e18);
        assertEq(distributor.f5Score(POOL_A), 150e18);
        assertEq(distributor.f5Total(), 150e18);
    }

    /// @notice Confirms a second `recordScore` call with a lower tvlEMA decreases both `poolScore` and `totalScore` by the negative signed delta — H-D19 / H-D31 downward adjustment path; vm.roll past year1EndBlock — enters α=1e18 continuous regime per H-D32 / H-D33.
    function test_RecordScore_SecondWriteDecreaseAdjustsTotalScoreDown() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 150e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        ema.setTVLEMA(POOL_A, 30e18);
        distributor.recordScore(POOL_A);
        assertEq(distributor.poolScore(POOL_A), 30e18);
        assertEq(distributor.totalScore(), 30e18);
        assertEq(distributor.f5Score(POOL_A), 30e18);
        assertEq(distributor.f5Total(), 30e18);
    }

    /// @notice Confirms a second `recordScore` call with an unchanged tvlEMA emits `ScoreUpdated` with equal oldScore and newScore and leaves `totalScore` unchanged — H-D19 / H-D31 no-op delta path; vm.roll past year1EndBlock — enters α=1e18 continuous regime per H-D32 / H-D33.
    function test_RecordScore_NoOpEmitsEventWithEqualOldAndNew() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        vm.expectEmit(true, false, false, true);
        emit IEmissionDistributor.ScoreUpdated(POOL_A, 100e18, 100e18);
        distributor.recordScore(POOL_A);
        assertEq(distributor.poolScore(POOL_A), 100e18);
        assertEq(distributor.totalScore(), 100e18);
        assertEq(distributor.f5Score(POOL_A), 100e18);
        assertEq(distributor.f5Total(), 100e18);
    }

    /// @notice Confirms `recordScore` on two distinct pools accumulates both pool scores into `totalScore` independently — H-D19 / H-D31 multi-pool signed-delta aggregation; vm.roll past year1EndBlock — enters α=1e18 continuous regime per H-D32 / H-D33.
    function test_RecordScore_TwoPoolsAccumulateInTotalScore() public {
        gauges.setApproved(POOL_A, true);
        gauges.setApproved(POOL_B, true);
        ema.setTVLEMA(POOL_A, 100e18);
        ema.setTVLEMA(POOL_B, 200e18);
        mult.setMultiplier(POOL_A, 1e18);
        mult.setMultiplier(POOL_B, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        distributor.recordScore(POOL_B);
        assertEq(distributor.poolScore(POOL_A), 100e18);
        assertEq(distributor.poolScore(POOL_B), 200e18);
        assertEq(distributor.totalScore(), 300e18);
        assertEq(distributor.f5Score(POOL_A), 100e18);
        assertEq(distributor.f5Score(POOL_B), 200e18);
        assertEq(distributor.f5Total(), 300e18);
    }

    /// @notice Confirms the H-D33 Miliarium branch at α=0 (default block ≤ month10EndBlock) reshapes effective to `f5Total / 28` per H-D6 1/28 literal supply-deflationary share — canonical F-1 equal-split baseline.
    function test_RecordScore_BootstrapAlphaZeroMiliarium_EffectiveEqualsF5TotalOver28() public {
        miliReg.setMiliarium(POOL_A, true);
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.expectEmit(true, false, false, true);
        emit IEmissionDistributor.ScoreUpdated(POOL_A, 0, uint256(100e18) / 28);
        distributor.recordScore(POOL_A);
        assertEq(distributor.f5Score(POOL_A), 100e18);
        assertEq(distributor.f5Total(), 100e18);
        assertEq(distributor.poolScore(POOL_A), uint256(100e18) / 28);
        assertEq(distributor.totalScore(), uint256(100e18) / 28);
    }

    /// @notice Confirms the H-D33 non-Miliarium Option A branch at α=0 (default block ≤ month10EndBlock) reshapes effective to 0 per `10_constitution.md §xxviii` — non-Miliarium pools carry zero weight during F-1 bootstrap regime.
    function test_RecordScore_BootstrapAlphaZeroNonMiliarium_EffectiveEqualsZero() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.expectEmit(true, false, false, true);
        emit IEmissionDistributor.ScoreUpdated(POOL_A, 0, 0);
        distributor.recordScore(POOL_A);
        assertEq(distributor.f5Score(POOL_A), 100e18);
        assertEq(distributor.f5Total(), 100e18);
        assertEq(distributor.poolScore(POOL_A), 0);
        assertEq(distributor.totalScore(), 0);
    }

    /* ---------- recordDeposit tests (H-D16 / H-D21 / H-D25) ---------- */

    /// @notice Reverts `NotAuMTContract` when `recordDeposit` is called by an address other than the current `auMTContractByPool[pool]` recorder — guards the I-D9 onlyAuMTContract(pool) gate.
    function test_RevertWhen_RecordDepositCallerNotAuMTContract() public {
        vm.prank(address(0xBADC0DE));
        vm.expectRevert(abi.encodeWithSelector(IEmissionDistributor.NotAuMTContract.selector, POOL_A, address(0xBADC0DE)));
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
    }

    /// @notice Confirms the first `recordDeposit` call writes `userLP` and `poolTotalLP` to the deposited amount — H-D16 stake-increment path with no prior state.
    function test_RecordDeposit_FirstDepositUpdatesUserLPAndPoolTotalLP() public {
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        assertEq(distributor.userLP(POOL_A, USER_1), 100e18);
        assertEq(distributor.poolTotalLP(POOL_A), 100e18);
    }

    /// @notice Confirms the first `recordDeposit` call leaves `pendingBalance` at zero — no prior accrual means no crystallization at the H-D25 settle boundary.
    function test_RecordDeposit_FirstDepositLeavesPendingBalanceZero() public {
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        assertEq(distributor.pendingBalance(POOL_A, USER_1), 0);
    }

    /// @notice Confirms the first `recordDeposit` rebases `userRewardDebt` to the current `poolAccRewardPerLP` — H-D16 single-snapshot MasterChef rebase at zero accumulator.
    function test_RecordDeposit_FirstDepositRebasesUserRewardDebtToAcc() public {
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        assertEq(distributor.userRewardDebt(POOL_A, USER_1), distributor.poolAccRewardPerLP(POOL_A));
        assertEq(distributor.userRewardDebt(POOL_A, USER_1), 0);
    }

    /// @notice Confirms `recordDeposit` emits `DepositRecorded` with the correct pool, user, and amount — H-D16 event obligation on positive deposit.
    function test_RecordDeposit_EmitsDepositRecorded() public {
        vm.expectEmit(true, true, false, true);
        emit IEmissionDistributor.DepositRecorded(POOL_A, USER_1, 100e18);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
    }

    /// @notice Confirms `recordDeposit` with amount zero is permitted — emits `DepositRecorded` and leaves all state at zero, documenting the deliberate no-guard posture on zero amounts.
    function test_RecordDeposit_ZeroAmountPermittedAndEmits() public {
        vm.expectEmit(true, true, false, true);
        emit IEmissionDistributor.DepositRecorded(POOL_A, USER_1, 0);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 0);
        assertEq(distributor.userLP(POOL_A, USER_1), 0);
        assertEq(distributor.poolTotalLP(POOL_A), 0);
        assertEq(distributor.pendingBalance(POOL_A, USER_1), 0);
    }

    /// @notice Confirms deposits from two distinct users accumulate into `poolTotalLP` independently — H-D16 per-user map plus pool-aggregate invariant.
    function test_RecordDeposit_MultiUserPoolTotalLPAggregates() public {
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_2, 200e18);
        assertEq(distributor.userLP(POOL_A, USER_1), 100e18);
        assertEq(distributor.userLP(POOL_A, USER_2), 200e18);
        assertEq(distributor.poolTotalLP(POOL_A), 300e18);
    }

    /// @notice Confirms a second `recordDeposit` after a one-block accrual crystallizes the pending reward into `pendingBalance` and rebases `userRewardDebt` — H-D25 MasterChef settle-then-increment pattern.
    function test_RecordDeposit_SecondDepositCrystallizesPending() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 1);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 50e18);
        assertEq(distributor.userLP(POOL_A, USER_1), 150e18);
        assertEq(distributor.poolTotalLP(POOL_A), 150e18);
        assertEq(distributor.userRewardDebt(POOL_A, USER_1), 1e16);
        assertEq(distributor.pendingBalance(POOL_A, USER_1), 1e18);
    }

    /* ---------- recordWithdrawal tests (H-D16 / H-D21 / H-D25) ---------- */

    /// @notice Reverts `NotAuMTContract` when `recordWithdrawal` is called by an address other than the current `auMTContractByPool[pool]` recorder — guards the I-D9 onlyAuMTContract(pool) gate, symmetric to `recordDeposit`.
    function test_RevertWhen_RecordWithdrawalCallerNotAuMTContract() public {
        vm.prank(address(0xBADC0DE));
        vm.expectRevert(abi.encodeWithSelector(IEmissionDistributor.NotAuMTContract.selector, POOL_A, address(0xBADC0DE)));
        distributor.recordWithdrawal(POOL_A, USER_1, 100e18);
    }

    /// @notice Reverts with arithmetic underflow (Panic 0x11) when `recordWithdrawal` is called with an amount exceeding the user's recorded stake — H-D16 trust-the-recorder posture; no typed error declared.
    function test_RevertWhen_RecordWithdrawalUnderflowOnOverWithdrawal() public {
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.prank(AUMT_REC);
        vm.expectRevert();
        distributor.recordWithdrawal(POOL_A, USER_1, 150e18);
    }

    /// @notice Reverts with arithmetic underflow (Panic 0x11) when `recordWithdrawal` is called for a user with no prior deposit — H-D16 trust-the-recorder posture; no typed error declared.
    function test_RevertWhen_RecordWithdrawalUnderflowOnNoPriorDeposit() public {
        vm.prank(AUMT_REC);
        vm.expectRevert();
        distributor.recordWithdrawal(POOL_A, USER_1, 1);
    }

    /// @notice Confirms a partial `recordWithdrawal` decrements `userLP` and `poolTotalLP` by the withdrawn amount — H-D16 stake-decrement path leaving a residual stake.
    function test_RecordWithdrawal_PartialWithdrawalUpdatesUserLPAndPoolTotalLP() public {
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.prank(AUMT_REC);
        distributor.recordWithdrawal(POOL_A, USER_1, 30e18);
        assertEq(distributor.userLP(POOL_A, USER_1), 70e18);
        assertEq(distributor.poolTotalLP(POOL_A), 70e18);
    }

    /// @notice Confirms a full `recordWithdrawal` zeroes both `userLP` and `poolTotalLP` — H-D16 complete-exit path.
    function test_RecordWithdrawal_FullWithdrawalZerosUserLPAndPoolTotalLP() public {
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.prank(AUMT_REC);
        distributor.recordWithdrawal(POOL_A, USER_1, 100e18);
        assertEq(distributor.userLP(POOL_A, USER_1), 0);
        assertEq(distributor.poolTotalLP(POOL_A), 0);
    }

    /// @notice Confirms `recordWithdrawal` emits `WithdrawalRecorded` with the correct pool, user, and amount — H-D16 event obligation on positive withdrawal.
    function test_RecordWithdrawal_EmitsWithdrawalRecorded() public {
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.expectEmit(true, true, false, true);
        emit IEmissionDistributor.WithdrawalRecorded(POOL_A, USER_1, 30e18);
        vm.prank(AUMT_REC);
        distributor.recordWithdrawal(POOL_A, USER_1, 30e18);
    }

    /// @notice Confirms `recordWithdrawal` with amount zero is permitted — emits `WithdrawalRecorded` and leaves all state at zero, documenting the deliberate no-guard posture on zero amounts.
    function test_RecordWithdrawal_ZeroAmountPermittedAndEmits() public {
        vm.expectEmit(true, true, false, true);
        emit IEmissionDistributor.WithdrawalRecorded(POOL_A, USER_1, 0);
        vm.prank(AUMT_REC);
        distributor.recordWithdrawal(POOL_A, USER_1, 0);
        assertEq(distributor.userLP(POOL_A, USER_1), 0);
        assertEq(distributor.poolTotalLP(POOL_A), 0);
        assertEq(distributor.pendingBalance(POOL_A, USER_1), 0);
    }

    /// @notice Confirms `recordWithdrawal` after a one-block accrual crystallizes the pending reward into `pendingBalance` and rebases `userRewardDebt` — H-D25 MasterChef settle-then-decrement pattern, symmetric to the deposit crystallization path.
    function test_RecordWithdrawal_CrystallizesPendingOnTouch() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 1);
        vm.prank(AUMT_REC);
        distributor.recordWithdrawal(POOL_A, USER_1, 30e18);
        assertEq(distributor.userLP(POOL_A, USER_1), 70e18);
        assertEq(distributor.poolTotalLP(POOL_A), 70e18);
        assertEq(distributor.userRewardDebt(POOL_A, USER_1), 1e16);
        assertEq(distributor.pendingBalance(POOL_A, USER_1), 1e18);
    }

    /* ---------- claim tests (H-D20 / H-D21 / H-D25) ---------- */

    /// @notice Confirms `claim` returns early when the caller has neither LP stake nor pending balance — H-D25 zero-amount short-circuit: (0 - 0).mulDown(0) = 0, pendingBalance = 0, amount = 0 → immediate return with no mint.
    function test_Claim_ZeroAmountShortCircuitsOnEmptyUser() public {
        vm.prank(USER_1);
        distributor.claim(POOL_A, USER_1);
        assertEq(aumm.balanceOf(USER_1), 0);
    }

    /// @notice Confirms `claim` returns early when the caller has LP stake but no blocks have elapsed since deposit — H-D21 empty-interval guard fires in `_accrueGlobal`, `accRewardPerScoreUnit` does not advance; amount = 0, no mint.
    function test_Claim_ZeroAmountShortCircuitsOnLPNoAccrual() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.prank(USER_1);
        distributor.claim(POOL_A, USER_1);
        assertEq(aumm.balanceOf(USER_1), 0);
    }

    /// @notice Happy-path `claim` after one-block accrual — H-D15/H-D25 math: accRewardPerScoreUnit = 1e16, poolAccRewardPerLP = 1e16, amount = (1e16 - 0).mulDown(100e18) = 1e18; H-D20 `AuMM.mint` fires exactly once; `pendingBalance` zeroed and `userRewardDebt` rebased to 1e16.
    function test_Claim_HappyPathMintsToCallerAndUpdatesState() public {
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
        assertEq(distributor.pendingBalance(POOL_A, USER_1), 0);
        assertEq(distributor.userRewardDebt(POOL_A, USER_1), 1e16);
    }

    /// @notice Confirms `claim` mints to the `to` parameter rather than `msg.sender` — H-D20 delegated claim: USER_1 is the stake holder, USER_2 receives the 1e18 AuMM mint; USER_1 balance stays zero.
    function test_Claim_DelegatedRecipientMintsToTo() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 1);
        vm.prank(USER_1);
        distributor.claim(POOL_A, USER_2);
        assertEq(aumm.balanceOf(USER_2), 1e18);
        assertEq(aumm.balanceOf(USER_1), 0);
    }

    /// @notice Confirms `claim` drains crystallized `pendingBalance` from a prior `recordWithdrawal` — H-D25 additive form: pending = 1e18 (crystallized at withdrawal), live delta = 0 (same-block claim); total amount = 1e18, `pendingBalance` zeroed after claim.
    function test_Claim_DrainsPendingBalanceAndRebasesDebt() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 1);
        vm.prank(AUMT_REC);
        distributor.recordWithdrawal(POOL_A, USER_1, 30e18);
        vm.prank(USER_1);
        distributor.claim(POOL_A, USER_1);
        assertEq(aumm.balanceOf(USER_1), 1e18);
        assertEq(distributor.pendingBalance(POOL_A, USER_1), 0);
    }

    /// @notice Confirms `claim` emits `Claimed` with all four indexed/data fields correct — IEmissionDistributor L54: three indexed (pool, claimer, to) + one data field (amount); vm.expectEmit(true,true,true,true) asserts all four.
    function test_Claim_EmitsClaimedWithCorrectTopics() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 1);
        vm.expectEmit(true, true, true, true);
        emit IEmissionDistributor.Claimed(POOL_A, USER_1, USER_1, 1e18);
        vm.prank(USER_1);
        distributor.claim(POOL_A, USER_1);
    }

    /// @notice Confirms a second `claim` in the same block is a no-op — H-D21 + H-D25: empty-interval guard fires, no accrual, `(acc - userRewardDebt).mulDown(userLP) = 0`, `pendingBalance = 0`; amount = 0 → early return, balance unchanged.
    function test_Claim_SecondClaimSameBlockIsNoOp() public {
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
        vm.prank(USER_1);
        distributor.claim(POOL_A, USER_1);
        assertEq(aumm.balanceOf(USER_1), 1e18);
    }

    /// @notice Confirms `claim` with `to == address(0)` reverts when amount is non-zero — H-D20 closing prose: no explicit Aureum guard; revert propagates from OpenZeppelin ERC-20 `_mint` zero-address check; bare `vm.expectRevert()` per project convention.
    function test_RevertWhen_ClaimToZeroAddressWithPositiveAmount() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 1);
        vm.prank(USER_1);
        vm.expectRevert();
        distributor.claim(POOL_A, address(0));
    }

    /* ---------- pendingClaim view tests (H-D25) ---------- */

    /// @notice Confirms `pendingClaim` returns 0 for a completely empty state — H-D25: pendingBalance = 0, userRewardDebt = 0, userLP = 0, poolAccRewardPerLP = 0 → 0 + (0 - 0).mulDown(0) = 0.
    function test_PendingClaim_ZeroUserReturnsZero() public view {
        assertEq(distributor.pendingClaim(POOL_A, USER_1), 0);
    }

    /// @notice Confirms `pendingClaim` returns 0 immediately after a first deposit — H-D25 first-deposit baseline: pendingBalance = 0 (crystallization no-op against pre-deposit userLP = 0), userRewardDebt rebased to current acc; (acc - acc).mulDown(userLP) = 0.
    function test_PendingClaim_PostDepositReturnsZero() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        assertEq(distributor.pendingClaim(POOL_A, USER_1), 0);
    }

    /// @notice Confirms `pendingClaim` returns the crystallized `pendingBalance` alone when no live-delta exists — H-D25 additive form with second component zero: post-withdrawal pendingBalance = 1e18, userRewardDebt = poolAccRewardPerLP = 1e16, (acc - debt).mulDown(userLP) = 0.
    function test_PendingClaim_ReflectsCrystallizedPendingOnly() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 1);
        vm.prank(AUMT_REC);
        distributor.recordWithdrawal(POOL_A, USER_1, 30e18);
        assertEq(distributor.pendingClaim(POOL_A, USER_1), 1e18);
    }

    /// @notice Confirms `pendingClaim` does NOT live-simulate against `block.number` — uses the STORED `poolAccRewardPerLP` only per H-D25 NatSpec; after recordDeposit at GEN and vm.roll(+1) WITHOUT a mutating touch, the view still returns 0 because the stored accumulator has not advanced.
    function test_PendingClaim_StaleSnapshotDoesNotSimulateLiveAccrual() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(GENESIS_BLOCK_ + 1);
        assertEq(distributor.pendingClaim(POOL_A, USER_1), 0);
    }

    /// @notice Confirms `pendingClaim` returns a fresh value after any mutating entry advances the stored accumulator — H-D17/H-D25: recordScore at +1 advances accRewardPerScoreUnit by 1e16 + settles POOL_A pushing poolAccRewardPerLP to 1e16; view = (1e16 - 0).mulDown(100e18) = 1e18.
    function test_PendingClaim_FreshAfterRecordScoreTouch() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 1);
        distributor.recordScore(POOL_A);
        assertEq(distributor.pendingClaim(POOL_A, USER_1), 1e18);
    }

    /// @notice Confirms `pendingClaim` returns 0 after a successful `claim` — H-D20/H-D25 post-claim invariant: claim zeroes `pendingBalance` and rebases `userRewardDebt = poolAccRewardPerLP`, so both additive components evaluate to 0.
    function test_PendingClaim_DropsToZeroAfterClaim() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(GENESIS_BLOCK_ + 1);
        vm.prank(USER_1);
        distributor.claim(POOL_A, USER_1);
        assertEq(distributor.pendingClaim(POOL_A, USER_1), 0);
    }

    /// @notice Confirms `pendingClaim` correctly sums BOTH H-D25 additive components — sequence: deposit 100e18 at GEN, roll +1, withdraw 90e18 (crystallizes 1e18 into pendingBalance, leaves userLP = 10e18, debt = 1e16, poolAccRewardPerLP = 1e16), roll +1, recordScore (advances poolAccRewardPerLP by 1e18/10e18 = 1e17, total = 1.1e17). View = 1e18 + (1.1e17 - 1e16).mulDown(10e18) = 1e18 + 1e18 = 2e18.
    function test_PendingClaim_AdditiveFormBothComponentsNonZero() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 1);
        vm.prank(AUMT_REC);
        distributor.recordWithdrawal(POOL_A, USER_1, 90e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 2);
        distributor.recordScore(POOL_A);
        assertEq(distributor.pendingClaim(POOL_A, USER_1), 2e18);
    }

    /// @notice Confirms `pendingClaim(POOL_B, USER_1)` is unaffected by POOL_A state — H-D22 per-pool storage isolation: all POOL_B accumulators remain at zero even after substantial POOL_A accrual.
    function test_PendingClaim_DifferentPoolsIsolated() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(GENESIS_BLOCK_ + 1);
        distributor.recordScore(POOL_A);
        assertEq(distributor.pendingClaim(POOL_B, USER_1), 0);
    }

    /* ---------- accrual + settle math tests (H-D15 / H-D21 / H-D23 / H-D24) ---------- */

    /// @notice Confirms `_accrueGlobal` advances `accRewardPerScoreUnit` by `(rate × Δblocks).divDown(totalScore)` over a multi-block interval — H-D15: rate=1e18, Δ=5, totalScore=100e18 → accumulator += 5e16; `lastAccrualBlock` rewrites to current block.number.
    function test_Accrual_MultiBlockAdvancesAccumulator() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 5);
        distributor.recordScore(POOL_A);
        assertEq(distributor.accRewardPerScoreUnit(), 5e16);
        assertEq(distributor.lastAccrualBlock(), AureumTime.year1EndBlock(GENESIS_BLOCK_) + 5);
    }

    /// @notice Confirms the H-D15 empty-totalScore guard in `_accrueGlobal` — when `totalScore == 0` and a mutator triggers accrual after several blocks, `lastAccrualBlock` advances to the current block but `accRewardPerScoreUnit` stays at zero (no divide-by-zero, no scaled emission accrued pre-Stage-J).
    function test_Accrual_EmptyTotalScoreGuardAdvancesBlockOnly() public {
        vm.roll(GENESIS_BLOCK_ + 5);
        vm.prank(USER_1);
        distributor.claim(POOL_A, USER_1);
        assertEq(distributor.accRewardPerScoreUnit(), 0);
        assertEq(distributor.lastAccrualBlock(), GENESIS_BLOCK_ + 5);
        assertEq(distributor.totalScore(), 0);
    }

    /// @notice Confirms the H-D21 empty-interval guard in `_accrueGlobal` — a second mutating call at the same block returns immediately without re-reading rate or re-writing the accumulator; `accRewardPerScoreUnit` does not double-charge.
    function test_Accrual_EmptyIntervalGuardShortCircuits() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        distributor.recordScore(POOL_A);
        distributor.recordScore(POOL_A);
        assertEq(distributor.accRewardPerScoreUnit(), 0);
        assertEq(distributor.lastAccrualBlock(), GENESIS_BLOCK_);
    }

    /// @notice Confirms `_settlePool` pushes `(pool, poolAllocation)` to `_efficiencyOracle.recordEmissions` when allocation > 0 — H-D23 push: callsLength increments by exactly one, payload equals `(POOL_A, 1e18)` for the (1e16 - 0).mulDown(100e18) allocation.
    function test_Settle_PushesAllocationToEfficiencyOracle() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        uint256 priorCalls = effOracle.callsLength();
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 1);
        distributor.recordScore(POOL_A);
        assertEq(effOracle.callsLength(), priorCalls + 1);
        (address poolPushed, uint256 amountPushed) = effOracle.callAt(effOracle.callsLength() - 1);
        assertEq(poolPushed, POOL_A);
        assertEq(amountPushed, 1e18);
    }

    /// @notice Confirms `_settlePool` zero-skip path (H-D23) — when `poolAllocation == 0` (first settle, same-block re-settle), the `recordEmissions` external push is elided; cumulative `callsLength` stays at zero across recordScore + recordDeposit + recordScore at the same block.
    function test_Settle_ZeroAllocationSkipsPushToEfficiencyOracle() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        distributor.recordScore(POOL_A);
        assertEq(effOracle.callsLength(), 0);
    }

    /// @notice Confirms `_settlePool` increments `poolAccRewardPerLP[pool]` by `poolAllocation.divDown(poolTotalLP[pool])` — H-D24 per-LP-unit accumulator: 1e18 allocation over 100e18 LP yields 1e16 per-LP-unit increment.
    function test_Settle_PerLPUnitAccrualMatchesAllocationDivLP() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 1);
        distributor.recordScore(POOL_A);
        assertEq(distributor.poolAccRewardPerLP(POOL_A), 1e16);
    }

    /// @notice Confirms `_settlePool` rebases `poolAccDebt[pool]` to the current `accRewardPerScoreUnit` snapshot — H-D15: subsequent settles compute incremental allocation against the rebased debt baseline, preventing double-allocation.
    function test_Settle_PoolAccDebtRebasesToCurrentAcc() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 1);
        distributor.recordScore(POOL_A);
        assertEq(distributor.poolAccDebt(POOL_A), 1e16);
    }

    /// @notice Confirms H-D24 zero-LP stranded path — `poolScore > 0` AND `poolTotalLP == 0`: the allocation still pushes to EfficiencyOracle (F-10 denominator obligation), but `poolAccRewardPerLP` stays at zero because there are no LP holders to distribute to. Stranded allocation matches standard MasterChef semantic.
    function test_Settle_ZeroLPStrandedAllocationStillPushesToEffOracle() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        distributor.recordScore(POOL_A);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 1);
        distributor.recordScore(POOL_A);
        assertEq(effOracle.callsLength(), 1);
        (address poolPushed, uint256 amountPushed) = effOracle.callAt(0);
        assertEq(poolPushed, POOL_A);
        assertEq(amountPushed, 1e18);
        assertEq(distributor.poolAccRewardPerLP(POOL_A), 0);
    }

    /* ---------- LP tranche integral observation tests (H5 / H-D34 / H-D27) ---------- */

    /// @notice Closed-form AP fixture mirroring _bootstrapApSum at src/emission/EmissionDistributor.sol L239-L243 — integer arithmetic identity per H-D27; used to compute expected Bodensee deduction for extLpTrancheIntegral assertions.
    function _apSumFixture(
        uint256 from_,
        uint256 to_,
        uint256 anchorStart,
        uint256 anchorEnd,
        uint256 startShare,
        uint256 dropShare,
        uint256 rate
    ) internal pure returns (uint256) {
        uint256 width = anchorEnd - anchorStart;
        uint256 first = startShare - (dropShare * (from_ - anchorStart)) / width;
        uint256 last = startShare - (dropShare * (to_ - anchorStart)) / width;
        uint256 n = to_ - from_ + 1;
        return ((first + last) * n * rate) / (2 * 1e18);
    }

    /// @notice Asserts extLpTrancheIntegral over an interior A-leg range matches naive block-by-block AP deduction per H-D27 identity.
    function test_LpTrancheIntegral_ALegInterior_MatchesNaiveApSum() public {
        aumm.setRate(1e18);
        uint256 m6 = AureumTime.month6EndBlock(GENESIS_BLOCK_);
        uint256 from_ = GENESIS_BLOCK_ + 1;
        uint256 to_ = GENESIS_BLOCK_ + 10;
        uint256 expected = (to_ - from_ + 1) * 1e18 - _apSumFixture(from_, to_, GENESIS_BLOCK_, m6, 8e17, 3e17, 1e18);
        assertEq(distributor.extLpTrancheIntegral(from_, to_), expected);
    }

    /// @notice Asserts extLpTrancheIntegral at the A-leg anchor-start boundary (genesis block) matches naive AP deduction per H-D27 identity.
    function test_LpTrancheIntegral_ALegAnchorStart_MatchesNaiveApSum() public {
        aumm.setRate(1e18);
        uint256 m6 = AureumTime.month6EndBlock(GENESIS_BLOCK_);
        uint256 from_ = GENESIS_BLOCK_;
        uint256 to_ = GENESIS_BLOCK_ + 100;
        uint256 expected = (to_ - from_ + 1) * 1e18 - _apSumFixture(from_, to_, GENESIS_BLOCK_, m6, 8e17, 3e17, 1e18);
        assertEq(distributor.extLpTrancheIntegral(from_, to_), expected);
    }

    /// @notice Asserts extLpTrancheIntegral at the A-leg anchor-end boundary (month6EndBlock) matches naive AP deduction per H-D27 identity.
    function test_LpTrancheIntegral_ALegAnchorEnd_MatchesNaiveApSum() public {
        aumm.setRate(1e18);
        uint256 m6 = AureumTime.month6EndBlock(GENESIS_BLOCK_);
        uint256 from_ = m6 - 100;
        uint256 to_ = m6;
        uint256 expected = (to_ - from_ + 1) * 1e18 - _apSumFixture(from_, to_, GENESIS_BLOCK_, m6, 8e17, 3e17, 1e18);
        assertEq(distributor.extLpTrancheIntegral(from_, to_), expected);
    }

    /// @notice Asserts extLpTrancheIntegral over an interior B-leg range matches naive block-by-block AP deduction per H-D27 identity.
    function test_LpTrancheIntegral_BLegInterior_MatchesNaiveApSum() public {
        aumm.setRate(1e18);
        uint256 m6 = AureumTime.month6EndBlock(GENESIS_BLOCK_);
        uint256 m10 = AureumTime.month10EndBlock(GENESIS_BLOCK_);
        uint256 from_ = m6 + 100;
        uint256 to_ = m6 + 200;
        uint256 expected = (to_ - from_ + 1) * 1e18 - _apSumFixture(from_, to_, m6, m10, 5e17, 5e17, 1e18);
        assertEq(distributor.extLpTrancheIntegral(from_, to_), expected);
    }

    /// @notice Asserts extLpTrancheIntegral at the B-leg anchor-start boundary (month6EndBlock + 1) matches naive AP deduction per H-D27 identity.
    function test_LpTrancheIntegral_BLegAnchorStart_MatchesNaiveApSum() public {
        aumm.setRate(1e18);
        uint256 m6 = AureumTime.month6EndBlock(GENESIS_BLOCK_);
        uint256 m10 = AureumTime.month10EndBlock(GENESIS_BLOCK_);
        uint256 from_ = m6 + 1;
        uint256 to_ = m6 + 100;
        uint256 expected = (to_ - from_ + 1) * 1e18 - _apSumFixture(from_, to_, m6, m10, 5e17, 5e17, 1e18);
        assertEq(distributor.extLpTrancheIntegral(from_, to_), expected);
    }

    /// @notice Asserts extLpTrancheIntegral at the B-leg anchor-end boundary (month10EndBlock) matches naive AP deduction per H-D27 identity.
    function test_LpTrancheIntegral_BLegAnchorEnd_MatchesNaiveApSum() public {
        aumm.setRate(1e18);
        uint256 m6 = AureumTime.month6EndBlock(GENESIS_BLOCK_);
        uint256 m10 = AureumTime.month10EndBlock(GENESIS_BLOCK_);
        uint256 from_ = m10 - 100;
        uint256 to_ = m10;
        uint256 expected = (to_ - from_ + 1) * 1e18 - _apSumFixture(from_, to_, m6, m10, 5e17, 5e17, 1e18);
        assertEq(distributor.extLpTrancheIntegral(from_, to_), expected);
    }

    /* ---------- Era-boundary cursor walk tests (H5 / H-D30) ---------- */

    /// @notice Asserts extLpTrancheIntegral over a 10-block continuous-phase range within Era 0 equals rate times block count — single-iteration cursor walk, no boundary.
    function test_LpTrancheIntegral_Era0ContinuousNoBoundary_MatchesRateTimesN() public {
        aumm.setRate(1e18);
        uint256 from_ = 5_000_000;
        uint256 to_ = 5_000_009;
        assertEq(distributor.extLpTrancheIntegral(from_, to_), 10 * 1e18);
    }

    /// @notice Asserts extLpTrancheIntegral straddling the Era 0 → Era 1 boundary with constant rate equals rate times total block count — two-iteration cursor walk, boundary split, no rate change.
    function test_LpTrancheIntegral_StraddleEra0End_ConstantRate_MatchesRateTimesN() public {
        aumm.setRate(1e18);
        uint256 era1Start = AureumTime.nthHalvingBlock(GENESIS_BLOCK_, 1);
        uint256 era0End = era1Start - 1;
        uint256 from_ = era0End - 4;
        uint256 to_ = era1Start + 5;
        assertEq(distributor.extLpTrancheIntegral(from_, to_), 11 * 1e18);
    }

    /// @notice Asserts extLpTrancheIntegral straddling the Era 0 → Era 1 boundary with halved rate in Era 1 splits contributions correctly at the era boundary per H-D30 snapshot-once semantics.
    function test_LpTrancheIntegral_StraddleEra0End_HalvedRate_SplitsAtBoundary() public {
        uint256 era1Start = AureumTime.nthHalvingBlock(GENESIS_BLOCK_, 1);
        uint256 era0End = era1Start - 1;
        uint256 from_ = era0End - 4;
        uint256 to_ = era1Start + 5;
        vm.mockCall(address(aumm), abi.encodeWithSelector(IAuMM.blockEmissionRate.selector, from_), abi.encode(uint256(1e18)));
        vm.mockCall(address(aumm), abi.encodeWithSelector(IAuMM.blockEmissionRate.selector, era1Start), abi.encode(uint256(5e17)));
        assertEq(distributor.extLpTrancheIntegral(from_, to_), 5 * 1e18 + 6 * 5e17);
    }

    /// @notice Asserts extLpTrancheIntegral over a range whose upper bound equals the Era 0 end block clamps subTo correctly and produces a single-iteration result.
    function test_LpTrancheIntegral_ExactAtEra0End_SingleIteration() public {
        aumm.setRate(1e18);
        uint256 era0End = AureumTime.nthHalvingBlock(GENESIS_BLOCK_, 1) - 1;
        uint256 from_ = era0End - 9;
        uint256 to_ = era0End;
        assertEq(distributor.extLpTrancheIntegral(from_, to_), 10 * 1e18);
    }

    /// @notice Asserts extLpTrancheIntegral starting exactly at Era 1 start produces a single-iteration result using Era 1 rate snapshot per H-D30.
    function test_LpTrancheIntegral_StartsAtEra1_SingleIteration() public {
        aumm.setRate(1e18);
        uint256 era1Start = AureumTime.nthHalvingBlock(GENESIS_BLOCK_, 1);
        uint256 from_ = era1Start;
        uint256 to_ = era1Start + 9;
        assertEq(distributor.extLpTrancheIntegral(from_, to_), 10 * 1e18);
    }

    /// @notice Asserts extLpTrancheIntegral spanning three eras with distinct halved rates aggregates per-era contributions independently per H-D30 cursor walk.
    function test_LpTrancheIntegral_ThreeErasWithHalving_AggregatesPerEra() public {
        uint256 era1Start = AureumTime.nthHalvingBlock(GENESIS_BLOCK_, 1);
        uint256 era1End = AureumTime.nthHalvingBlock(GENESIS_BLOCK_, 2) - 1;
        uint256 era2Start = AureumTime.nthHalvingBlock(GENESIS_BLOCK_, 2);
        uint256 era0End = era1Start - 1;
        uint256 from_ = era0End - 4;
        uint256 to_ = era2Start + 4;
        vm.mockCall(address(aumm), abi.encodeWithSelector(IAuMM.blockEmissionRate.selector, from_), abi.encode(uint256(1e18)));
        vm.mockCall(address(aumm), abi.encodeWithSelector(IAuMM.blockEmissionRate.selector, era1Start), abi.encode(uint256(5e17)));
        vm.mockCall(address(aumm), abi.encodeWithSelector(IAuMM.blockEmissionRate.selector, era2Start), abi.encode(uint256(25e16)));
        uint256 expected = 5 * 1e18 + (era1End - era1Start + 1) * 5e17 + 5 * 25e16;
        assertEq(distributor.extLpTrancheIntegral(from_, to_), expected);
    }

    /* ---------- Phase-boundary nesting tests (H5 / H-D27 / H-D28 / H-D29) ---------- */

    /// @notice Asserts extLpTrancheIntegral crossing the A-leg to B-leg boundary at m6 aggregates both leg contributions independently per H-D27.
    function test_LpTrancheIntegral_CrossM6_ALegToBLeg_AggregatesBothLegs() public {
        aumm.setRate(1e18);
        uint256 m6 = AureumTime.month6EndBlock(GENESIS_BLOCK_);
        uint256 m10 = AureumTime.month10EndBlock(GENESIS_BLOCK_);
        uint256 from_ = m6 - 4;
        uint256 to_ = m6 + 5;
        uint256 aLegContribution = 1e18 * 5 - _apSumFixture(m6 - 4, m6, GENESIS_BLOCK_, m6, 8e17, 3e17, 1e18);
        uint256 bLegContribution = 1e18 * 5 - _apSumFixture(m6 + 1, m6 + 5, m6, m10, 5e17, 5e17, 1e18);
        uint256 expected = aLegContribution + bLegContribution;
        assertEq(distributor.extLpTrancheIntegral(from_, to_), expected);
    }

    /// @notice Asserts extLpTrancheIntegral crossing the B-leg to transition boundary at m10 adds the B-leg AP deduction plus full-rate transition blocks per H-D28.
    function test_LpTrancheIntegral_CrossM10_BLegToTransition_AddsBLegPlusRateTimesN() public {
        aumm.setRate(1e18);
        uint256 m6 = AureumTime.month6EndBlock(GENESIS_BLOCK_);
        uint256 m10 = AureumTime.month10EndBlock(GENESIS_BLOCK_);
        uint256 from_ = m10 - 4;
        uint256 to_ = m10 + 5;
        uint256 bLegContribution = 1e18 * 5 - _apSumFixture(m10 - 4, m10, m6, m10, 5e17, 5e17, 1e18);
        uint256 transitionContribution = 1e18 * 5;
        uint256 expected = bLegContribution + transitionContribution;
        assertEq(distributor.extLpTrancheIntegral(from_, to_), expected);
    }

    /// @notice Asserts extLpTrancheIntegral crossing the transition to continuous boundary at y1 yields full rate for both phases — no AP deduction, no Incendiary skim at default address(0) registry per H-D29.
    function test_LpTrancheIntegral_CrossY1_TransitionToContinuous_AddsRateTimesN() public {
        aumm.setRate(1e18);
        uint256 y1 = AureumTime.year1EndBlock(GENESIS_BLOCK_);
        uint256 from_ = y1 - 4;
        uint256 to_ = y1 + 5;
        uint256 expected = 1e18 * 10;
        assertEq(distributor.extLpTrancheIntegral(from_, to_), expected);
    }

    /// @notice Asserts extLpTrancheIntegral crossing A-leg, B-leg, and transition (three phases within Era 0) aggregates each phase independently per H-D27 + H-D28.
    function test_LpTrancheIntegral_CrossM6AndM10_ALegToTransition_ThreePhases() public {
        aumm.setRate(1e18);
        uint256 m6 = AureumTime.month6EndBlock(GENESIS_BLOCK_);
        uint256 m10 = AureumTime.month10EndBlock(GENESIS_BLOCK_);
        uint256 from_ = m6 - 4;
        uint256 to_ = m10 + 5;
        uint256 aLegContribution = 1e18 * 5 - _apSumFixture(m6 - 4, m6, GENESIS_BLOCK_, m6, 8e17, 3e17, 1e18);
        uint256 bLegContribution = 1e18 * (m10 - m6) - _apSumFixture(m6 + 1, m10, m6, m10, 5e17, 5e17, 1e18);
        uint256 transitionContribution = 1e18 * 5;
        uint256 expected = aLegContribution + bLegContribution + transitionContribution;
        assertEq(distributor.extLpTrancheIntegral(from_, to_), expected);
    }

    /// @notice Asserts extLpTrancheIntegral crossing B-leg, transition, and continuous (three phases within Era 0) aggregates each phase independently per H-D28 + H-D29.
    function test_LpTrancheIntegral_CrossM10AndY1_BLegToContinuous_ThreePhases() public {
        aumm.setRate(1e18);
        uint256 m6 = AureumTime.month6EndBlock(GENESIS_BLOCK_);
        uint256 m10 = AureumTime.month10EndBlock(GENESIS_BLOCK_);
        uint256 y1 = AureumTime.year1EndBlock(GENESIS_BLOCK_);
        uint256 from_ = m10 - 4;
        uint256 to_ = y1 + 5;
        uint256 bLegContribution = 1e18 * 5 - _apSumFixture(m10 - 4, m10, m6, m10, 5e17, 5e17, 1e18);
        uint256 transitionContribution = 1e18 * (y1 - m10);
        uint256 continuousContribution = 1e18 * 5;
        uint256 expected = bLegContribution + transitionContribution + continuousContribution;
        assertEq(distributor.extLpTrancheIntegral(from_, to_), expected);
    }

    /// @notice Asserts extLpTrancheIntegral spanning all four phases (A-leg, B-leg, transition, continuous) within Era 0 aggregates per-phase contributions independently per H-D27 + H-D28 + H-D29.
    function test_LpTrancheIntegral_FullSweep_AllFourPhases() public {
        aumm.setRate(1e18);
        uint256 m6 = AureumTime.month6EndBlock(GENESIS_BLOCK_);
        uint256 m10 = AureumTime.month10EndBlock(GENESIS_BLOCK_);
        uint256 y1 = AureumTime.year1EndBlock(GENESIS_BLOCK_);
        uint256 from_ = m6 - 4;
        uint256 to_ = y1 + 5;
        uint256 aLegContribution = 1e18 * 5 - _apSumFixture(m6 - 4, m6, GENESIS_BLOCK_, m6, 8e17, 3e17, 1e18);
        uint256 bLegContribution = 1e18 * (m10 - m6) - _apSumFixture(m6 + 1, m10, m6, m10, 5e17, 5e17, 1e18);
        uint256 transitionContribution = 1e18 * (y1 - m10);
        uint256 continuousContribution = 1e18 * 5;
        uint256 expected = aLegContribution + bLegContribution + transitionContribution + continuousContribution;
        assertEq(distributor.extLpTrancheIntegral(from_, to_), expected);
    }

    /* ---------- Continuous-phase Incendiary skim tests (H5 / H-D29) ---------- */

    function test_ExtLpTrancheIntegral_DefaultRegistry_NoCall_RateTimesN() public {
        // incendiaryRegistry == address(0) — no external call, result is rate * n
        aumm.setRate(1e18);
        uint256 from_ = 5_000_000;
        uint256 to_   = 5_000_009;
        uint256 n     = to_ - from_ + 1; // 10
        assertEq(distributor.extLpTrancheIntegral(from_, to_), 1e18 * n);
    }

    function test_ExtLpTrancheIntegral_NonZeroRegistry_ZeroSkim_RateTimesN() public {
        // registry deployed but returns 0 skim — result still rate * n
        aumm.setRate(1e18);
        uint256 from_    = 5_000_000;
        uint256 to_      = 5_000_009;
        uint256 n        = to_ - from_ + 1;
        address registry = address(0xBEEF);
        vm.prank(GOV);
        distributor.setIncendiaryRegistry(registry);
        vm.mockCall(
            registry,
            abi.encodeWithSelector(IIncendiaryRegistry.integratedSkim.selector, from_, to_),
            abi.encode(uint256(0))
        );
        assertEq(distributor.extLpTrancheIntegral(from_, to_), 1e18 * n);
    }

    function test_ExtLpTrancheIntegral_NonZeroRegistry_PositiveSkim_Subtracts() public {
        // registry returns a positive skim — result is rate * n - skim
        aumm.setRate(1e18);
        uint256 from_    = 5_000_000;
        uint256 to_      = 5_000_009;
        uint256 n        = to_ - from_ + 1;
        uint256 skim     = 3e17;
        address registry = address(0xBEEF);
        vm.prank(GOV);
        distributor.setIncendiaryRegistry(registry);
        vm.mockCall(
            registry,
            abi.encodeWithSelector(IIncendiaryRegistry.integratedSkim.selector, from_, to_),
            abi.encode(skim)
        );
        assertEq(distributor.extLpTrancheIntegral(from_, to_), 1e18 * n - skim);
    }

    function test_ExtLpTrancheIntegral_RevertWhen_IncendiaryRegistryReverts() public {
        // registry call reverts — distributor must propagate (no try/catch per H-D29)
        aumm.setRate(1e18);
        uint256 from_    = 5_000_000;
        uint256 to_      = 5_000_009;
        address registry = address(0xBEEF);
        vm.prank(GOV);
        distributor.setIncendiaryRegistry(registry);
        vm.mockCallRevert(
            registry,
            abi.encodeWithSelector(IIncendiaryRegistry.integratedSkim.selector, from_, to_),
            abi.encodeWithSignature("Error(string)", "skim_unavailable")
        );
        vm.expectRevert();
        distributor.extLpTrancheIntegral(from_, to_);
    }

    function test_ExtLpTrancheIntegral_RegistryRebindToZero_DeprecationValve() public {
        // set registry then rebind to address(0) — falls back to rate * n (no external call)
        aumm.setRate(1e18);
        uint256 from_ = 5_000_000;
        uint256 to_   = 5_000_009;
        uint256 n     = to_ - from_ + 1;
        vm.startPrank(GOV);
        distributor.setIncendiaryRegistry(address(0xBEEF));
        distributor.setIncendiaryRegistry(address(0));
        vm.stopPrank();
        assertEq(distributor.extLpTrancheIntegral(from_, to_), 1e18 * n);
    }

    /* ---------- Conservation invariant (H-D26): LP + bootstrap_sum + skim = rate × n ---------- */

    function test_Conservation_ALegInterior_LPPlusBootstrapEqualsTotal() public {
        // Within A-leg: LP_integral + bootstrap_ap_sum_A = rate × n
        aumm.setRate(1e18);
        uint256 m6    = AureumTime.month6EndBlock(GENESIS_BLOCK_);
        uint256 from_ = GENESIS_BLOCK_ + 1000;
        uint256 to_   = GENESIS_BLOCK_ + 2000;
        uint256 n     = to_ - from_ + 1;
        uint256 lpIntegral   = distributor.extLpTrancheIntegral(from_, to_);
        uint256 bootstrapSum = _apSumFixture(from_, to_, GENESIS_BLOCK_, m6, 8e17, 3e17, 1e18);
        assertEq(lpIntegral + bootstrapSum, 1e18 * n);
    }

    function test_Conservation_BLegInterior_LPPlusBootstrapEqualsTotal() public {
        // Within B-leg: LP_integral + bootstrap_ap_sum_B = rate × n
        aumm.setRate(1e18);
        uint256 m6    = AureumTime.month6EndBlock(GENESIS_BLOCK_);
        uint256 m10   = AureumTime.month10EndBlock(GENESIS_BLOCK_);
        uint256 from_ = m6 + 100;
        uint256 to_   = m6 + 1000;
        uint256 n     = to_ - from_ + 1;
        uint256 lpIntegral   = distributor.extLpTrancheIntegral(from_, to_);
        uint256 bootstrapSum = _apSumFixture(from_, to_, m6, m10, 5e17, 5e17, 1e18);
        assertEq(lpIntegral + bootstrapSum, 1e18 * n);
    }

    function test_Conservation_TransitionInterior_LPEqualsTotal() public {
        // Within transition phase: LP_integral = rate × n (no subtractions)
        aumm.setRate(1e18);
        uint256 m10   = AureumTime.month10EndBlock(GENESIS_BLOCK_);
        uint256 from_ = m10 + 100;
        uint256 to_   = m10 + 1000;
        uint256 n     = to_ - from_ + 1;
        assertEq(distributor.extLpTrancheIntegral(from_, to_), 1e18 * n);
    }

    function test_Conservation_ContinuousDefaultRegistry_LPEqualsTotal() public {
        // Continuous phase with default registry (skim = 0): LP_integral = rate × n
        aumm.setRate(1e18);
        uint256 y1    = AureumTime.year1EndBlock(GENESIS_BLOCK_);
        uint256 from_ = y1 + 100;
        uint256 to_   = y1 + 1000;
        uint256 n     = to_ - from_ + 1;
        assertEq(distributor.extLpTrancheIntegral(from_, to_), 1e18 * n);
    }

    function test_Conservation_ContinuousWithSkim_LPPlusSkimEqualsTotal() public {
        // Continuous phase with non-zero skim: LP_integral + skim = rate × n
        aumm.setRate(1e18);
        uint256 y1    = AureumTime.year1EndBlock(GENESIS_BLOCK_);
        uint256 from_ = y1 + 100;
        uint256 to_   = y1 + 1000;
        uint256 n     = to_ - from_ + 1;
        uint256 skim  = 2e17;
        address registry = address(0xBEEF);
        vm.prank(GOV);
        distributor.setIncendiaryRegistry(registry);
        vm.mockCall(
            registry,
            abi.encodeWithSelector(IIncendiaryRegistry.integratedSkim.selector, from_, to_),
            abi.encode(skim)
        );
        uint256 lpIntegral = distributor.extLpTrancheIntegral(from_, to_);
        assertEq(lpIntegral + skim, 1e18 * n);
    }

    function test_Conservation_FullSweep_LPPlusBootstrapsEqualsTotal() public {
        // Full sweep across all 4 phases with default registry (skim = 0):
        // LP_integral + bootstrap_A + bootstrap_B = rate × n
        aumm.setRate(1e18);
        uint256 m6    = AureumTime.month6EndBlock(GENESIS_BLOCK_);
        uint256 m10   = AureumTime.month10EndBlock(GENESIS_BLOCK_);
        uint256 y1    = AureumTime.year1EndBlock(GENESIS_BLOCK_);
        uint256 from_ = GENESIS_BLOCK_ + 1000;
        uint256 to_   = y1 + 1000;
        uint256 n     = to_ - from_ + 1;
        uint256 aLegSum     = _apSumFixture(from_, m6, GENESIS_BLOCK_, m6, 8e17, 3e17, 1e18);
        uint256 bLegSum     = _apSumFixture(m6 + 1, m10, m6, m10, 5e17, 5e17, 1e18);
        uint256 lpIntegral  = distributor.extLpTrancheIntegral(from_, to_);
        assertEq(lpIntegral + aLegSum + bLegSum, 1e18 * n);
    }

    /* ---------- setIncendiaryRegistry governance setter tests (H5 / H-D29) ---------- */

    /// @notice Reverts `NotGovernance` when `setIncendiaryRegistry` is called by a non-governance address — confirms the setter is onlyGovernance-gated.
    function test_RevertWhen_SetIncendiaryRegistryCallerNotGovernance() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(IEmissionDistributor.NotGovernance.selector, address(0xBEEF)));
        distributor.setIncendiaryRegistry(address(0x1234));
    }

    /// @notice Confirms `setIncendiaryRegistry(address(0))` is accepted — zero is the H-D29 deliberate deprecation safety valve, asymmetric to `setGovernanceContract`.
    function test_SetIncendiaryRegistry_AcceptsZeroAddress() public {
        vm.prank(GOV);
        distributor.setIncendiaryRegistry(address(0));
        assertEq(distributor.incendiaryRegistry(), address(0));
    }

    /// @notice Confirms `setIncendiaryRegistry` writes the new address to the incendiaryRegistry slot.
    function test_SetIncendiaryRegistry_UpdatesSlot() public {
        vm.prank(GOV);
        distributor.setIncendiaryRegistry(address(0xBEEF));
        assertEq(distributor.incendiaryRegistry(), address(0xBEEF));
    }

    /// @notice Confirms `setIncendiaryRegistry` emits `IncendiaryRegistrySet` with old and new address as indexed topics.
    function test_SetIncendiaryRegistry_EmitsIncendiaryRegistrySet() public {
        vm.expectEmit(true, true, false, false);
        emit IEmissionDistributor.IncendiaryRegistrySet(address(0), address(0xBEEF));
        vm.prank(GOV);
        distributor.setIncendiaryRegistry(address(0xBEEF));
    }

    /* ---------- setMintRouter one-shot + claim MintRouterNotSet guard (K-D7) ---------- */

    /// @notice Confirms setMintRouter binds the router address and emits MintRouterBound.
    function test_SetMintRouter_HappyPath_EmitsAndBinds() public {
        EmissionDistributor fresh = _freshUnboundDistributor();
        vm.expectEmit(true, false, false, true);
        emit IEmissionDistributor.MintRouterBound(address(0xF00D));
        vm.prank(GOV);
        fresh.setMintRouter(address(0xF00D));
        assertEq(address(fresh.mintRouter()), address(0xF00D), "mintRouter bound");
    }

    /// @notice Reverts ZeroAddress when setMintRouter is called with address(0).
    function test_SetMintRouter_RevertWhen_RouterZero() public {
        EmissionDistributor fresh = _freshUnboundDistributor();
        vm.prank(GOV);
        vm.expectRevert(IEmissionDistributor.ZeroAddress.selector);
        fresh.setMintRouter(address(0));
    }

    /// @notice Reverts MintRouterAlreadySet when setMintRouter is called on a distributor that already has a router bound.
    function test_SetMintRouter_RevertWhen_AlreadySet() public {
        vm.prank(GOV);
        vm.expectRevert(IEmissionDistributor.MintRouterAlreadySet.selector);
        distributor.setMintRouter(address(0xF00D));
    }

    /// @notice Reverts NotGovernance when setMintRouter is called by a non-governance address.
    function test_SetMintRouter_RevertWhen_CallerNotGovernance() public {
        EmissionDistributor fresh = _freshUnboundDistributor();
        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(IEmissionDistributor.NotGovernance.selector, address(0xBEEF)));
        fresh.setMintRouter(address(0xF00D));
    }

    /// @notice Reverts MintRouterNotSet when claim is called on a distributor with no router bound.
    function test_Claim_RevertWhen_MintRouterNotSet() public {
        EmissionDistributor fresh = _freshUnboundDistributor();
        effOracle.setEmissionsRecorder(address(fresh));
        vm.prank(GOV);
        fresh.setAuMTContractForPool(POOL_A, AUMT_REC);
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_));
        fresh.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        fresh.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK_) + 1);
        vm.prank(USER_1);
        vm.expectRevert(IEmissionDistributor.MintRouterNotSet.selector);
        fresh.claim(POOL_A, USER_1);
    }
}
