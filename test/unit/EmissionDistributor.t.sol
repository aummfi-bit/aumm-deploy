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
}
