// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;
import { Test } from "forge-std/Test.sol";
import { VotingWeight } from "src/governance/VotingWeight.sol";
import { ITVLOracle } from "src/ccb/ITVLOracle.sol";
import { IGaugeRegistry } from "src/ccb/IGaugeRegistry.sol";
import { IMiliariumRegistry } from "src/ccb/IMiliariumRegistry.sol";
import { IEmissionDistributor } from "src/emission/IEmissionDistributor.sol";
import { AureumTime } from "src/lib/AureumTime.sol";
/// @notice Test-only mock for `ITVLOracle` — settable svZCHF TVL per pool.
contract MockTVLOracle is ITVLOracle {
    mapping(address => uint256) private _tvl;
    function setTvl(address pool, uint256 value) external {
        _tvl[pool] = value;
    }
    function tvl(address pool) external view override returns (uint256) {
        return _tvl[pool];
    }
    function quoteSvZCHF(address, uint256) external pure override returns (uint256) {
        return 0;
    }
}
/// @notice Test-only mock for `IGaugeRegistry` — settable approval; all other surface stubbed per G-D24 backfill.
contract MockGaugeRegistry is IGaugeRegistry {
    mapping(address => bool) private _approved;
    function setApproved(address gauge, bool approved) external {
        _approved[gauge] = approved;
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
/// @notice Test-only mock for `IMiliariumRegistry` — settable dense pool list.
contract MockMiliariumRegistry is IMiliariumRegistry {
    mapping(address => bool) private _isMiliarium;
    address[] private _pools;
    function setMiliarium(address pool, bool flag) external {
        _isMiliarium[pool] = flag;
    }
    function setPoolList(address[] memory pools) external {
        delete _pools;
        for (uint256 i = 0; i < pools.length; ++i) {
            _pools.push(pools[i]);
        }
    }
    function isMiliarium(address pool) external view override returns (bool) {
        return _isMiliarium[pool];
    }
    function miliariumPoolsCount() external view override returns (uint256) {
        return _pools.length;
    }
    function miliariumPoolAt(uint256 index) external view override returns (address) {
        return _pools[index];
    }
}
/// @notice Test-only mock for `IEmissionDistributor` (the recorder clock) — only the three members `VotingWeight`
///         reads (`effectiveQualBlock` / `userLP` / `poolTotalLP`) carry state + setters; the rest is empty-stubbed per G-D24.
contract MockRecorder is IEmissionDistributor {
    mapping(address => mapping(address => uint256)) private _eqb;
    mapping(address => mapping(address => uint256)) private _userLP;
    mapping(address => uint256) private _poolTotalLP;
    function setEffectiveQualBlock(address pool, address user, uint256 blockNumber) external {
        _eqb[pool][user] = blockNumber;
    }
    function setUserLP(address pool, address user, uint256 amount) external {
        _userLP[pool][user] = amount;
    }
    function setPoolTotalLP(address pool, uint256 amount) external {
        _poolTotalLP[pool] = amount;
    }
    function effectiveQualBlock(address pool, address user) external view override returns (uint256) {
        return _eqb[pool][user];
    }
    function userLP(address pool, address user) external view override returns (uint256) {
        return _userLP[pool][user];
    }
    function poolTotalLP(address pool) external view override returns (uint256) {
        return _poolTotalLP[pool];
    }
    function recordScore(address) external override {}
    function recordDeposit(address, address, uint256) external override {}
    function recordWithdrawal(address, address, uint256) external override {}
    function claim(address, address) external override {}
    function setGovernanceContract(address) external override {}
    function setAuMTContractForPool(address, address) external override {}
    function accRewardPerScoreUnit() external view override returns (uint256) {}
    function totalScore() external view override returns (uint256) {}
    function lastAccrualBlock() external view override returns (uint256) {}
    function poolScore(address) external view override returns (uint256) {}
    function poolAccDebt(address) external view override returns (uint256) {}
    function poolAccRewardPerLP(address) external view override returns (uint256) {}
    function userRewardDebt(address, address) external view override returns (uint256) {}
    function pendingBalance(address, address) external view override returns (uint256) {}
    function pendingClaim(address, address) external view override returns (uint256) {}
    function governance() external view override returns (address) {}
    function auMTContractByPool(address) external view override returns (address) {}
}
contract VotingWeightTest is Test {
    VotingWeight internal vw;
    MockTVLOracle internal oracle;
    MockGaugeRegistry internal gaugeReg;
    MockRecorder internal recorder;
    MockMiliariumRegistry internal registry;
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant START_BLOCK = 2_000_000;
    address internal constant HOLDER = address(0x1111);
    address internal constant HOLDER_B = address(0x2222);
    address internal constant POOL_A = address(0xA1);
    address internal constant POOL_B = address(0xB2);
    address internal constant POOL_C = address(0xC3);
    address internal constant POKER = address(0xBEEF);
    function setUp() public {
        oracle = new MockTVLOracle();
        gaugeReg = new MockGaugeRegistry();
        recorder = new MockRecorder();
        registry = new MockMiliariumRegistry();
        vw = new VotingWeight(oracle, gaugeReg, recorder, registry, GENESIS_BLOCK);
        vm.roll(START_BLOCK);
    }
    // --- constructor zero-checks ---
    function test_Constructor_RevertWhen_ZeroOracle() public {
        vm.expectRevert(VotingWeight.ZeroAddress.selector);
        new VotingWeight(ITVLOracle(address(0)), gaugeReg, recorder, registry, GENESIS_BLOCK);
    }
    function test_Constructor_RevertWhen_ZeroGaugeRegistry() public {
        vm.expectRevert(VotingWeight.ZeroAddress.selector);
        new VotingWeight(oracle, IGaugeRegistry(address(0)), recorder, registry, GENESIS_BLOCK);
    }
    function test_Constructor_RevertWhen_ZeroRecorder() public {
        vm.expectRevert(VotingWeight.ZeroAddress.selector);
        new VotingWeight(oracle, gaugeReg, IEmissionDistributor(address(0)), registry, GENESIS_BLOCK);
    }
    function test_Constructor_RevertWhen_ZeroRegistry() public {
        vm.expectRevert(VotingWeight.ZeroAddress.selector);
        new VotingWeight(oracle, gaugeReg, recorder, IMiliariumRegistry(address(0)), GENESIS_BLOCK);
    }
    function test_Constructor_RevertWhen_ZeroGenesisBlock() public {
        vm.expectRevert(VotingWeight.ZeroGenesisBlock.selector);
        new VotingWeight(oracle, gaugeReg, recorder, registry, 0);
    }
    function test_Constructor_SetsImmutables() public view {
        assertEq(address(vw.ORACLE()), address(oracle));
        assertEq(address(vw.GAUGE_REGISTRY()), address(gaugeReg));
        assertEq(address(vw.RECORDER()), address(recorder));
        assertEq(address(vw.REGISTRY()), address(registry));
        assertEq(vw.GENESIS_BLOCK(), GENESIS_BLOCK);
    }
    function test_InitialWeightsAreZero() public view {
        assertEq(vw.governanceWeight(HOLDER), 0);
        assertEq(vw.totalSupply(), 0);
    }
    uint256 internal constant ON_RAMP = AureumTime.ON_RAMP_PERIOD_BLOCKS;
    uint256 internal constant CLIFF = AureumTime.QUALIFICATION_PERIOD_BLOCKS;
    // --- helpers ---
    function _setSinglePool(address pool) internal {
        address[] memory pools = new address[](1);
        pools[0] = pool;
        registry.setPoolList(pools);
    }
    function _configurePosition(
        address pool,
        address holder,
        bool gaugeApproved,
        uint256 tvlValue,
        uint256 lp,
        uint256 totalLP,
        uint256 eqb
    ) internal {
        gaugeReg.setApproved(pool, gaugeApproved);
        oracle.setTvl(pool, tvlValue);
        recorder.setUserLP(pool, holder, lp);
        recorder.setPoolTotalLP(pool, totalLP);
        recorder.setEffectiveQualBlock(pool, holder, eqb);
    }
    // --- single-position power: math + per-position guards ---
    function test_Poke_SingleQualifiedPosition_Era0() public {
        _setSinglePool(POOL_A);
        // full ownership (share 1.0), fully-capped on-ramp (timeFrac 1.0) -> base = tvl = 16e18
        _configurePosition(POOL_A, HOLDER, true, 16e18, 100e18, 100e18, START_BLOCK - ON_RAMP);
        vw.poke(HOLDER);
        // Era 0 exponent 1/4: 16^(1/4) = 2.0
        assertApproxEqAbs(vw.governanceWeight(HOLDER), 2e18, 1e8);
        assertEq(vw.totalSupply(), vw.governanceWeight(HOLDER));
    }
    function test_Poke_SingleQualifiedPosition_Era1() public {
        uint256 era1Block = AureumTime.firstHalvingBlock(GENESIS_BLOCK) + 500_000;
        vm.roll(era1Block);
        _setSinglePool(POOL_A);
        // base = 8e18
        _configurePosition(POOL_A, HOLDER, true, 8e18, 100e18, 100e18, era1Block - ON_RAMP);
        vw.poke(HOLDER);
        // Era 1+ exponent 1/3: 8^(1/3) = 2.0
        assertApproxEqAbs(vw.governanceWeight(HOLDER), 2e18, 1e8);
    }
    function test_Poke_BaseOne_YieldsOne() public {
        _setSinglePool(POOL_A);
        // base = 1e18 -> 1^x = 1 in any era
        _configurePosition(POOL_A, HOLDER, true, 1e18, 100e18, 100e18, START_BLOCK - ON_RAMP);
        vw.poke(HOLDER);
        assertApproxEqAbs(vw.governanceWeight(HOLDER), 1e18, 1e6);
    }
    function test_Poke_PartialOnRamp_ScalesValue() public {
        _setSinglePool(POOL_A);
        // timeInPool = ON_RAMP/2 -> timeFrac 0.5; value 2e18 -> base 1e18
        _configurePosition(POOL_A, HOLDER, true, 2e18, 100e18, 100e18, START_BLOCK - (ON_RAMP / 2));
        vw.poke(HOLDER);
        assertApproxEqAbs(vw.governanceWeight(HOLDER), 1e18, 1e6);
    }
    function test_Poke_PartialOwnership_SharesValue() public {
        _setSinglePool(POOL_A);
        // share 0.5, tvl 32e18 -> value 16e18; fully-capped -> base 16e18
        _configurePosition(POOL_A, HOLDER, true, 32e18, 50e18, 100e18, START_BLOCK - ON_RAMP);
        vw.poke(HOLDER);
        assertApproxEqAbs(vw.governanceWeight(HOLDER), 2e18, 1e8);
    }
    function test_Poke_GaugeNotApproved_ContributesZero() public {
        _setSinglePool(POOL_A);
        _configurePosition(POOL_A, HOLDER, false, 16e18, 100e18, 100e18, START_BLOCK - ON_RAMP);
        vw.poke(HOLDER);
        assertEq(vw.governanceWeight(HOLDER), 0);
        assertEq(vw.totalSupply(), 0);
    }
    function test_Poke_NoPosition_ContributesZero() public {
        _setSinglePool(POOL_A);
        // eqb = 0 -> no qualified position
        _configurePosition(POOL_A, HOLDER, true, 16e18, 100e18, 100e18, 0);
        vw.poke(HOLDER);
        assertEq(vw.governanceWeight(HOLDER), 0);
    }
    function test_Poke_SubCliff_ContributesZero() public {
        _setSinglePool(POOL_A);
        // timeInPool = CLIFF - 1 -> below the 14-day cliff
        _configurePosition(POOL_A, HOLDER, true, 16e18, 100e18, 100e18, START_BLOCK - (CLIFF - 1));
        vw.poke(HOLDER);
        assertEq(vw.governanceWeight(HOLDER), 0);
    }
    function test_Poke_AtCliffBoundary_Qualifies() public {
        _setSinglePool(POOL_A);
        // timeInPool = CLIFF exactly -> NOT below cliff, qualifies
        _configurePosition(POOL_A, HOLDER, true, 16e18, 100e18, 100e18, START_BLOCK - CLIFF);
        vw.poke(HOLDER);
        assertGt(vw.governanceWeight(HOLDER), 0);
    }
    function test_Poke_ZeroPoolTotalLP_ContributesZero() public {
        _setSinglePool(POOL_A);
        // totalLP = 0 -> div-by-zero guard returns 0 (no revert)
        _configurePosition(POOL_A, HOLDER, true, 16e18, 100e18, 0, START_BLOCK - ON_RAMP);
        vw.poke(HOLDER);
        assertEq(vw.governanceWeight(HOLDER), 0);
    }
    function test_Poke_ZeroUserLP_ContributesZero() public {
        _setSinglePool(POOL_A);
        _configurePosition(POOL_A, HOLDER, true, 16e18, 0, 100e18, START_BLOCK - ON_RAMP);
        vw.poke(HOLDER);
        assertEq(vw.governanceWeight(HOLDER), 0);
    }
    function test_Poke_ZeroTvl_ContributesZero() public {
        _setSinglePool(POOL_A);
        // tvl = 0 -> value = 0 guard
        _configurePosition(POOL_A, HOLDER, true, 0, 100e18, 100e18, START_BLOCK - ON_RAMP);
        vw.poke(HOLDER);
        assertEq(vw.governanceWeight(HOLDER), 0);
    }
    function test_Poke_OnRampCap_ClampsTime() public {
        _setSinglePool(POOL_A);
        // at cap: timeInPool = ON_RAMP
        _configurePosition(POOL_A, HOLDER, true, 16e18, 100e18, 100e18, START_BLOCK - ON_RAMP);
        vw.poke(HOLDER);
        uint256 atCap = vw.governanceWeight(HOLDER);
        // past cap: timeInPool = ON_RAMP + 200_000 -> clamps to the same timeFrac 1.0
        _configurePosition(POOL_A, HOLDER_B, true, 16e18, 100e18, 100e18, START_BLOCK - (ON_RAMP + 200_000));
        vw.poke(HOLDER_B);
        uint256 pastCap = vw.governanceWeight(HOLDER_B);
        assertEq(atCap, pastCap);
        assertGt(atCap, 0);
    }
}
