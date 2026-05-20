// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {EmissionDistributor} from "../../src/emission/EmissionDistributor.sol";
import {IEmissionDistributor} from "../../src/emission/IEmissionDistributor.sol";
import {IAuMM} from "../../src/token/IAuMM.sol";
import {IGaugeRegistry} from "../../src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "../../src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "../../src/ccb/ICCBMultiplier.sol";
import {IEfficiencyOracle} from "../../src/gauge/IEfficiencyOracle.sol";

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

/// @notice Unit tests for EmissionDistributor (concrete H-D15—H-D25 implementation landed at H4.1—H4.7c) — scaffold only at H4.8.1; test functions land at H4.8.2 onward.
contract EmissionDistributorTest is Test {
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
    EmissionDistributor internal distributor;

    function setUp() public virtual {
        aumm = new MockAuMM();
        gauges = new MockGaugeRegistry();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        effOracle = new MockEfficiencyOracle();
        distributor = new EmissionDistributor(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            GENESIS_BLOCK_,
            GOV
        );
        aumm.setMinter(address(distributor));
        effOracle.setEmissionsRecorder(address(distributor));
        vm.prank(GOV);
        distributor.setAuMTContract(AUMT_REC);
        vm.roll(GENESIS_BLOCK_);
    }

    function _addr(uint256 seed) internal returns (address) {
        return makeAddr(vm.toString(seed));
    }

    function _rollTo(uint256 blockNumber) internal {
        vm.roll(blockNumber);
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
            GENESIS_BLOCK_,
            address(0)
        );
    }

    /// @notice Asserts the setUp-deployed distributor wires all six immutables to the mock dependencies and genesis block constant.
    function test_Constructor_WiresImmutables() public {
        assertEq(address(distributor.AuMM()), address(aumm));
        assertEq(address(distributor._gaugeRegistry()), address(gauges));
        assertEq(address(distributor._emaSampler()), address(ema));
        assertEq(address(distributor._ccbMultiplier()), address(mult));
        assertEq(address(distributor._efficiencyOracle()), address(effOracle));
        assertEq(distributor.GENESIS_BLOCK(), GENESIS_BLOCK_);
    }

    /// @notice Asserts the setUp-deployed distributor initializes governance, lastAccrualBlock, and both global accumulators to their constructor defaults.
    function test_Constructor_InitsStorageSlots() public {
        assertEq(distributor.governance(), GOV);
        assertEq(distributor.lastAccrualBlock(), GENESIS_BLOCK_);
        assertEq(distributor.accRewardPerScoreUnit(), 0);
        assertEq(distributor.totalScore(), 0);
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

    /// @notice Rejects `setAuMTContract` when the caller is not the current governance address — confirms the setter is onlyGovernance-gated, not onlyAuMTContract-gated.
    function test_RevertWhen_SetAuMTContractCallerNotGovernance() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(IEmissionDistributor.NotGovernance.selector, address(0xBEEF)));
        distributor.setAuMTContract(address(0x1234));
    }

    /// @notice Confirms a freshly-constructed EmissionDistributor — before any `setAuMTContract` call — holds `auMTContract == address(0)`, the H-D16 pre-Stage-I default-zero posture.
    function test_Constructor_AuMTContractDefaultsZero() public {
        EmissionDistributor freshDistributor = new EmissionDistributor(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            GENESIS_BLOCK_,
            GOV
        );
        assertEq(freshDistributor.auMTContract(), address(0));
    }

    /// @notice Confirms `setAuMTContract(address(0))` is accepted — zero is the H-D16 deliberate deprecation safety valve, asymmetric to `setGovernanceContract`.
    function test_SetAuMTContract_AcceptsZeroAddress() public {
        vm.prank(GOV);
        distributor.setAuMTContract(address(0));
        assertEq(distributor.auMTContract(), address(0));
    }

    /// @notice Confirms `setAuMTContract` writes the new address to the auMTContract slot and emits `AuMTContractSet` with the setUp-wired old recorder and the new address as indexed topics.
    function test_SetAuMTContract_UpdatesSlotAndEmits() public {
        vm.expectEmit(true, true, false, false);
        emit IEmissionDistributor.AuMTContractSet(AUMT_REC, address(0xC0DE));
        vm.prank(GOV);
        distributor.setAuMTContract(address(0xC0DE));
        assertEq(distributor.auMTContract(), address(0xC0DE));
    }

    /* ---------- Score producer tests (H-D17 / H-D19) ---------- */

    /// @notice Reverts `NotApproved` when `recordScore` is called for a pool that has never been gauge-approved — guards the H-D17 (a) gate on initial state.
    function test_RevertWhen_RecordScoreGaugeNotApproved() public {
        vm.expectRevert(abi.encodeWithSelector(IEmissionDistributor.NotApproved.selector, POOL_A));
        distributor.recordScore(POOL_A);
    }

    /// @notice Reverts `NotApproved` when `recordScore` is called after gauge approval is revoked — confirms the H-D17 (a) gate fires on post-revoke attempts, not only on never-approved pools.
    function test_RevertWhen_RecordScoreRevokedGaugeAfterApproval() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        distributor.recordScore(POOL_A);
        gauges.setApproved(POOL_A, false);
        vm.expectRevert(abi.encodeWithSelector(IEmissionDistributor.NotApproved.selector, POOL_A));
        distributor.recordScore(POOL_A);
    }

    /// @notice Confirms the first `recordScore` call writes `poolScore`, sets `totalScore`, and emits `ScoreUpdated` with oldScore == 0 and newScore == tvlEMA — happy-path H-D17 state-and-event in one pass.
    function test_RecordScore_FirstWriteUpdatesStateAndEmits() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.expectEmit(true, false, false, true);
        emit IEmissionDistributor.ScoreUpdated(POOL_A, 0, 100e18);
        distributor.recordScore(POOL_A);
        assertEq(distributor.poolScore(POOL_A), 100e18);
        assertEq(distributor.totalScore(), 100e18);
    }

    /// @notice Confirms `recordScore` succeeds when called by an arbitrary non-governance address — verifies the H-D17 permissionless entry point.
    function test_RecordScore_PermissionlessCallerSucceeds() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        vm.prank(address(0xBADC0DE));
        distributor.recordScore(POOL_A);
        assertEq(distributor.poolScore(POOL_A), 100e18);
        assertEq(distributor.totalScore(), 100e18);
    }

    /// @notice Confirms a second `recordScore` call with a higher tvlEMA increases both `poolScore` and `totalScore` by the positive signed delta — H-D19 upward adjustment path.
    function test_RecordScore_SecondWriteIncreaseAdjustsTotalScoreUp() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        distributor.recordScore(POOL_A);
        ema.setTVLEMA(POOL_A, 150e18);
        distributor.recordScore(POOL_A);
        assertEq(distributor.poolScore(POOL_A), 150e18);
        assertEq(distributor.totalScore(), 150e18);
    }

    /// @notice Confirms a second `recordScore` call with a lower tvlEMA decreases both `poolScore` and `totalScore` by the negative signed delta — H-D19 downward adjustment path.
    function test_RecordScore_SecondWriteDecreaseAdjustsTotalScoreDown() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 150e18);
        mult.setMultiplier(POOL_A, 1e18);
        distributor.recordScore(POOL_A);
        ema.setTVLEMA(POOL_A, 30e18);
        distributor.recordScore(POOL_A);
        assertEq(distributor.poolScore(POOL_A), 30e18);
        assertEq(distributor.totalScore(), 30e18);
    }

    /// @notice Confirms a second `recordScore` call with an unchanged tvlEMA emits `ScoreUpdated` with equal oldScore and newScore and leaves `totalScore` unchanged — H-D19 no-op delta path.
    function test_RecordScore_NoOpEmitsEventWithEqualOldAndNew() public {
        gauges.setApproved(POOL_A, true);
        ema.setTVLEMA(POOL_A, 100e18);
        mult.setMultiplier(POOL_A, 1e18);
        distributor.recordScore(POOL_A);
        vm.expectEmit(true, false, false, true);
        emit IEmissionDistributor.ScoreUpdated(POOL_A, 100e18, 100e18);
        distributor.recordScore(POOL_A);
        assertEq(distributor.poolScore(POOL_A), 100e18);
        assertEq(distributor.totalScore(), 100e18);
    }

    /// @notice Confirms `recordScore` on two distinct pools accumulates both pool scores into `totalScore` independently — H-D19 multi-pool signed-delta aggregation.
    function test_RecordScore_TwoPoolsAccumulateInTotalScore() public {
        gauges.setApproved(POOL_A, true);
        gauges.setApproved(POOL_B, true);
        ema.setTVLEMA(POOL_A, 100e18);
        ema.setTVLEMA(POOL_B, 200e18);
        mult.setMultiplier(POOL_A, 1e18);
        mult.setMultiplier(POOL_B, 1e18);
        distributor.recordScore(POOL_A);
        distributor.recordScore(POOL_B);
        assertEq(distributor.poolScore(POOL_A), 100e18);
        assertEq(distributor.poolScore(POOL_B), 200e18);
        assertEq(distributor.totalScore(), 300e18);
    }

    /* ---------- recordDeposit tests (H-D16 / H-D21 / H-D25) ---------- */

    /// @notice Reverts `NotAuMTContract` when `recordDeposit` is called by an address other than the current `auMTContract` recorder — guards the H-D16 onlyAuMTContract gate.
    function test_RevertWhen_RecordDepositCallerNotAuMTContract() public {
        vm.prank(address(0xBADC0DE));
        vm.expectRevert(abi.encodeWithSelector(IEmissionDistributor.NotAuMTContract.selector, address(0xBADC0DE)));
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
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(GENESIS_BLOCK_ + 1);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 50e18);
        assertEq(distributor.userLP(POOL_A, USER_1), 150e18);
        assertEq(distributor.poolTotalLP(POOL_A), 150e18);
        assertEq(distributor.userRewardDebt(POOL_A, USER_1), 1e16);
        assertEq(distributor.pendingBalance(POOL_A, USER_1), 1e18);
    }

    /* ---------- recordWithdrawal tests (H-D16 / H-D21 / H-D25) ---------- */

    /// @notice Reverts `NotAuMTContract` when `recordWithdrawal` is called by an address other than the current `auMTContract` recorder — guards the H-D16 onlyAuMTContract gate, symmetric to `recordDeposit`.
    function test_RevertWhen_RecordWithdrawalCallerNotAuMTContract() public {
        vm.prank(address(0xBADC0DE));
        vm.expectRevert(abi.encodeWithSelector(IEmissionDistributor.NotAuMTContract.selector, address(0xBADC0DE)));
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
        distributor.recordScore(POOL_A);
        vm.prank(AUMT_REC);
        distributor.recordDeposit(POOL_A, USER_1, 100e18);
        vm.roll(GENESIS_BLOCK_ + 1);
        vm.prank(AUMT_REC);
        distributor.recordWithdrawal(POOL_A, USER_1, 30e18);
        assertEq(distributor.userLP(POOL_A, USER_1), 70e18);
        assertEq(distributor.poolTotalLP(POOL_A), 70e18);
        assertEq(distributor.userRewardDebt(POOL_A, USER_1), 1e16);
        assertEq(distributor.pendingBalance(POOL_A, USER_1), 1e18);
    }
}
