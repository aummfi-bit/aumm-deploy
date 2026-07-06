// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CCBMultiplier} from "src/ccb/CCBMultiplier.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

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

    function isMiliarium(address pool) external view returns (bool) {
        return _isMiliarium[pool];
    }

    function miliariumPoolsCount() external view returns (uint256) {
        return _pools.length;
    }

    function miliariumPoolAt(uint256 i) external view returns (address) {
        return _pools[i];
    }
}

contract MockEMASampler is IEMASampler {
    mapping(address => uint256) private _tvl;
    mapping(address => uint256) private _lastBlock;
    mapping(address => uint256) public emaSeedBlock;

    function setTVLEMA(address pool, uint256 v) external {
        _tvl[pool] = v;
    }

    function setLastEMAUpdateBlock(address pool, uint256 b) external {
        _lastBlock[pool] = b;
    }

    function tvlEMA(address pool) external view returns (uint256) {
        return _tvl[pool];
    }

    function lastEMAUpdateBlock(address pool) external view returns (uint256) {
        return _lastBlock[pool];
    }
}

contract CCBMultiplierTest is Test {
    using SafeCast for uint256;
    using SafeCast for int256;

    CCBMultiplier internal multiplier;
    MockMiliariumRegistry internal registry;
    MockEMASampler internal ema;

    uint256 internal constant START_BLOCK = 200_000;
    address internal constant POOL_A = address(0xA1);
    address internal constant POOL_B = address(0xB2);
    address internal constant POOL_C = address(0xC3);

    uint256 constant STEP_SIZE = 5e16;
    int256 constant STEP_DELTA_I256 = 5e16;
    uint256 constant CLAMP_FLOOR = 0.75e18;
    uint256 constant CLAMP_CEILING = 1.25e18;
    uint256 constant INITIAL_MULTIPLIER = 1e18;
    uint256 constant DEAD_ZONE = 1e15;
    uint256 constant ONE = 1e18;

    function setUp() public {
        registry = new MockMiliariumRegistry();
        ema = new MockEMASampler();
        multiplier = new CCBMultiplier(registry, ema);
        vm.roll(START_BLOCK);
    }

    function _applySignedDelta(uint256 base, int256 delta) internal pure returns (uint256) {
        return (base.toInt256() + delta).toUint256();
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    function test_constructor_wiresEmaSampler() public view {
        assertEq(address(multiplier.emaSampler()), address(ema));
    }

    function test_constructor_wiresMiliariumRegistry() public view {
        assertEq(address(multiplier.miliariumRegistry()), address(registry));
    }

    function test_constructor_setsRegistrySetter() public view {
        assertEq(multiplier.registrySetter(), address(this));
    }

    function test_constructor_revertsZeroMiliariumRegistry() public {
        vm.expectRevert(CCBMultiplier.InvalidRegistry.selector);
        new CCBMultiplier(IMiliariumRegistry(address(0)), IEMASampler(address(ema)));
    }

    function test_constructor_revertsZeroEmaSampler() public {
        vm.expectRevert(CCBMultiplier.InvalidRegistry.selector);
        new CCBMultiplier(IMiliariumRegistry(address(registry)), IEMASampler(address(0)));
    }

    // -------------------------------------------------------------------------
    // setMiliariumRegistry
    // -------------------------------------------------------------------------

    function test_setMiliariumRegistry_success() public {
        MockMiliariumRegistry nextReg = new MockMiliariumRegistry();
        multiplier.setMiliariumRegistry(IMiliariumRegistry(address(nextReg)));
        assertEq(address(multiplier.miliariumRegistry()), address(nextReg));
    }

    function test_setMiliariumRegistry_zerosRegistrySetter() public {
        MockMiliariumRegistry nextReg = new MockMiliariumRegistry();
        multiplier.setMiliariumRegistry(IMiliariumRegistry(address(nextReg)));
        assertEq(multiplier.registrySetter(), address(0));
    }

    function test_setMiliariumRegistry_revertsNonSetter() public {
        MockMiliariumRegistry nextReg = new MockMiliariumRegistry();
        vm.prank(address(0xBEEF));
        vm.expectRevert(CCBMultiplier.OnlyRegistrySetter.selector);
        multiplier.setMiliariumRegistry(IMiliariumRegistry(address(nextReg)));
    }

    function test_setMiliariumRegistry_revertsZeroAddress() public {
        vm.expectRevert(CCBMultiplier.InvalidRegistry.selector);
        multiplier.setMiliariumRegistry(IMiliariumRegistry(address(0)));
    }

    function test_setMiliariumRegistry_revertsAfterSeal() public {
        MockMiliariumRegistry nextReg = new MockMiliariumRegistry();
        multiplier.setMiliariumRegistry(IMiliariumRegistry(address(nextReg)));
        MockMiliariumRegistry third = new MockMiliariumRegistry();
        vm.expectRevert(CCBMultiplier.OnlyRegistrySetter.selector);
        multiplier.setMiliariumRegistry(IMiliariumRegistry(address(third)));
    }

    // -------------------------------------------------------------------------
    // updateMultiplier
    // -------------------------------------------------------------------------

    function test_updateMultiplier_revertsNonMiliarium() public {
        vm.expectRevert(abi.encodeWithSelector(CCBMultiplier.NotMiliariumPool.selector, POOL_A));
        multiplier.updateMultiplier(POOL_A);
    }

    function test_updateMultiplier_revertsTooEarly() public {
        address[] memory pl = new address[](1);
        pl[0] = POOL_A;
        registry.setPoolList(pl);
        registry.setMiliarium(POOL_A, true);
        ema.setTVLEMA(POOL_A, 1000e18);
        multiplier.updateMultiplier(POOL_A);
        uint256 b = block.number + 1;
        vm.roll(b);
        uint256 nextEl = multiplier.lastMultiplierUpdateBlock(POOL_A) + AureumTime.BLOCKS_PER_EPOCH;
        vm.expectRevert(abi.encodeWithSelector(CCBMultiplier.TooEarly.selector, b, nextEl));
        multiplier.updateMultiplier(POOL_A);
    }

    function test_updateMultiplier_coldStart_deltaGlobalZero() public {
        address[] memory pl = new address[](1);
        pl[0] = POOL_A;
        registry.setPoolList(pl);
        registry.setMiliarium(POOL_A, true);
        ema.setTVLEMA(POOL_A, 1000e18);
        multiplier.updateMultiplier(POOL_A);
        assertEq(multiplier.lastProtocolAggregateEMA(), 1000e18);
        assertEq(multiplier.M_i(POOL_A), INITIAL_MULTIPLIER - STEP_SIZE);
    }

    function test_updateMultiplier_globalRising_decrement() public {
        address[] memory pl = new address[](3);
        pl[0] = POOL_A;
        pl[1] = POOL_B;
        pl[2] = POOL_C;
        registry.setPoolList(pl);
        registry.setMiliarium(POOL_A, true);
        registry.setMiliarium(POOL_B, true);
        registry.setMiliarium(POOL_C, true);
        uint256 unit = 28_000e18;
        ema.setTVLEMA(POOL_A, unit);
        ema.setTVLEMA(POOL_B, unit);
        ema.setTVLEMA(POOL_C, unit);
        uint256 firstEpochEnd = START_BLOCK + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(firstEpochEnd);
        multiplier.updateMultiplier(POOL_A);
        uint256 miAfterFirst = multiplier.M_i(POOL_A);
        uint256 inc = (unit * 110) / 100;
        ema.setTVLEMA(POOL_A, inc);
        ema.setTVLEMA(POOL_B, inc);
        ema.setTVLEMA(POOL_C, inc);
        uint256 secondEpochEnd = firstEpochEnd + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(secondEpochEnd);
        multiplier.updateMultiplier(POOL_A);
        assertEq(multiplier.M_i(POOL_A), miAfterFirst - 2 * STEP_SIZE);
    }

    function test_updateMultiplier_globalFalling_increment() public {
        address[] memory pl = new address[](28);
        pl[0] = POOL_A;
        for (uint256 i = 1; i < 28; ++i) {
            pl[i] = makeAddr(string.concat("pool", vm.toString(i)));
        }
        registry.setPoolList(pl);
        uint256 unit = 28_000e18;
        for (uint256 i = 0; i < 28; ++i) {
            registry.setMiliarium(pl[i], true);
            ema.setTVLEMA(pl[i], unit);
        }
        uint256 firstEpochEnd = START_BLOCK + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(firstEpochEnd);
        multiplier.updateMultiplier(POOL_A);
        uint256 miAfterFirst = multiplier.M_i(POOL_A);
        uint256 dec = (unit * 90) / 100;
        for (uint256 i = 0; i < 28; ++i) {
            ema.setTVLEMA(pl[i], dec);
        }
        uint256 secondEpochEnd = firstEpochEnd + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(secondEpochEnd);
        multiplier.updateMultiplier(POOL_A);
        assertEq(multiplier.M_i(POOL_A), miAfterFirst + STEP_SIZE);
    }

    function test_updateMultiplier_globalDeadZoneBoundary_neutral() public {
        address[] memory pl = new address[](3);
        pl[0] = POOL_A;
        pl[1] = POOL_B;
        pl[2] = POOL_C;
        registry.setPoolList(pl);
        registry.setMiliarium(POOL_A, true);
        registry.setMiliarium(POOL_B, true);
        registry.setMiliarium(POOL_C, true);
        uint256 u0 = 10_000e18;
        ema.setTVLEMA(POOL_A, u0);
        ema.setTVLEMA(POOL_B, u0);
        ema.setTVLEMA(POOL_C, u0);
        uint256 epoch1 = START_BLOCK + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(epoch1);
        multiplier.updateMultiplier(POOL_A);
        uint256 lastAgg = multiplier.lastProtocolAggregateEMA();
        uint256 targetSum = lastAgg * (ONE + DEAD_ZONE) / ONE;
        uint256 u1 = targetSum / 3;
        uint256 r1 = targetSum % 3;
        ema.setTVLEMA(POOL_A, u1 + r1);
        ema.setTVLEMA(POOL_B, u1);
        ema.setTVLEMA(POOL_C, u1);
        uint256 epoch2 = epoch1 + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(epoch2);
        uint256 miBeforeSecond = multiplier.M_i(POOL_A);
        multiplier.updateMultiplier(POOL_A);
        int256 deltaIntraOnly = -STEP_DELTA_I256;
        uint256 expected = _applySignedDelta(miBeforeSecond, deltaIntraOnly);
        assertEq(multiplier.M_i(POOL_A), expected);
    }

    function test_updateMultiplier_globalOneWeiAboveBoundary_decrement() public {
        address[] memory pl = new address[](3);
        pl[0] = POOL_A;
        pl[1] = POOL_B;
        pl[2] = POOL_C;
        registry.setPoolList(pl);
        registry.setMiliarium(POOL_A, true);
        registry.setMiliarium(POOL_B, true);
        registry.setMiliarium(POOL_C, true);
        uint256 u0 = 10_000e18;
        ema.setTVLEMA(POOL_A, u0);
        ema.setTVLEMA(POOL_B, u0);
        ema.setTVLEMA(POOL_C, u0);
        uint256 epoch1 = START_BLOCK + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(epoch1);
        multiplier.updateMultiplier(POOL_A);
        uint256 lastAgg = multiplier.lastProtocolAggregateEMA();
        uint256 baseSum = lastAgg * (ONE + DEAD_ZONE) / ONE + 1;
        uint256 t = baseSum / 3;
        uint256 r = baseSum % 3;
        ema.setTVLEMA(POOL_A, t + r);
        ema.setTVLEMA(POOL_B, t);
        ema.setTVLEMA(POOL_C, t);
        uint256 epoch2 = epoch1 + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(epoch2);
        uint256 miAfterFirst = multiplier.M_i(POOL_A);
        multiplier.updateMultiplier(POOL_A);
        assertEq(multiplier.M_i(POOL_A), miAfterFirst - 2 * STEP_SIZE);
    }

    function test_updateMultiplier_globalLowerBoundary_neutral() public {
        address[] memory pl = new address[](3);
        pl[0] = POOL_A;
        pl[1] = POOL_B;
        pl[2] = POOL_C;
        registry.setPoolList(pl);
        registry.setMiliarium(POOL_A, true);
        registry.setMiliarium(POOL_B, true);
        registry.setMiliarium(POOL_C, true);
        uint256 u0 = 10_000e18;
        ema.setTVLEMA(POOL_A, u0);
        ema.setTVLEMA(POOL_B, u0);
        ema.setTVLEMA(POOL_C, u0);
        uint256 epoch1 = START_BLOCK + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(epoch1);
        multiplier.updateMultiplier(POOL_A);
        uint256 lastAgg = multiplier.lastProtocolAggregateEMA();
        uint256 targetSum = lastAgg * (ONE - DEAD_ZONE) / ONE;
        uint256 u1 = targetSum / 3;
        uint256 r1 = targetSum % 3;
        ema.setTVLEMA(POOL_A, u1 + r1);
        ema.setTVLEMA(POOL_B, u1);
        ema.setTVLEMA(POOL_C, u1);
        uint256 epoch2 = epoch1 + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(epoch2);
        uint256 miBeforeSecond = multiplier.M_i(POOL_A);
        multiplier.updateMultiplier(POOL_A);
        int256 deltaIntraOnly = -STEP_DELTA_I256;
        uint256 expected = _applySignedDelta(miBeforeSecond, deltaIntraOnly);
        assertEq(multiplier.M_i(POOL_A), expected);
    }

    function test_updateMultiplier_globalOneWeiBelowBoundary_increment() public {
        address[] memory pl = new address[](3);
        pl[0] = POOL_A;
        pl[1] = POOL_B;
        pl[2] = POOL_C;
        registry.setPoolList(pl);
        registry.setMiliarium(POOL_A, true);
        registry.setMiliarium(POOL_B, true);
        registry.setMiliarium(POOL_C, true);
        uint256 u0 = 10_000e18;
        ema.setTVLEMA(POOL_A, u0);
        ema.setTVLEMA(POOL_B, u0);
        ema.setTVLEMA(POOL_C, u0);
        uint256 epoch1 = START_BLOCK + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(epoch1);
        multiplier.updateMultiplier(POOL_A);
        uint256 lastAgg = multiplier.lastProtocolAggregateEMA();
        uint256 baseSum = lastAgg * (ONE - DEAD_ZONE) / ONE - 1;
        uint256 tiny = 100e18;
        uint256 half = (baseSum - tiny) / 2;
        ema.setTVLEMA(POOL_A, tiny);
        ema.setTVLEMA(POOL_B, half);
        ema.setTVLEMA(POOL_C, half);
        uint256 epoch2 = epoch1 + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(epoch2);
        uint256 miAfterFirst = multiplier.M_i(POOL_A);
        multiplier.updateMultiplier(POOL_A);
        assertEq(multiplier.M_i(POOL_A), miAfterFirst + 2 * STEP_SIZE);
    }

    function test_updateMultiplier_intraAbove_decrement() public {
        address[] memory pl = new address[](2);
        pl[0] = POOL_A;
        pl[1] = POOL_B;
        registry.setPoolList(pl);
        registry.setMiliarium(POOL_A, true);
        registry.setMiliarium(POOL_B, true);
        ema.setTVLEMA(POOL_A, 1000e18);
        ema.setTVLEMA(POOL_B, 1000e18);
        uint256 epoch1 = START_BLOCK + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(epoch1);
        multiplier.updateMultiplier(POOL_A);
        ema.setTVLEMA(POOL_A, 1500e18);
        ema.setTVLEMA(POOL_B, 500e18);
        uint256 epoch2 = epoch1 + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(epoch2);
        uint256 miBefore = multiplier.M_i(POOL_A);
        multiplier.updateMultiplier(POOL_A);
        assertEq(multiplier.M_i(POOL_A), miBefore - STEP_SIZE);
    }

    function test_updateMultiplier_intraBelow_increment() public {
        address[] memory pl = new address[](28);
        pl[0] = POOL_A;
        pl[1] = POOL_B;
        for (uint256 i = 2; i < 28; ++i) {
            pl[i] = makeAddr(string.concat("pool", vm.toString(i)));
        }
        registry.setPoolList(pl);
        for (uint256 i = 0; i < 28; ++i) {
            registry.setMiliarium(pl[i], true);
            ema.setTVLEMA(pl[i], 1000e18);
        }
        uint256 epoch1 = START_BLOCK + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(epoch1);
        multiplier.updateMultiplier(POOL_A);
        ema.setTVLEMA(POOL_A, 500e18);
        ema.setTVLEMA(POOL_B, 1500e18);
        uint256 epoch2 = epoch1 + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(epoch2);
        uint256 miBefore = multiplier.M_i(POOL_A);
        multiplier.updateMultiplier(POOL_A);
        assertEq(multiplier.M_i(POOL_A), miBefore + STEP_SIZE);
    }

    function test_updateMultiplier_channelsReinforce() public {
        address[] memory pl = new address[](3);
        pl[0] = POOL_A;
        pl[1] = POOL_B;
        pl[2] = POOL_C;
        registry.setPoolList(pl);
        registry.setMiliarium(POOL_A, true);
        registry.setMiliarium(POOL_B, true);
        registry.setMiliarium(POOL_C, true);
        uint256 unit = 28_000e18;
        ema.setTVLEMA(POOL_A, unit);
        ema.setTVLEMA(POOL_B, unit);
        ema.setTVLEMA(POOL_C, unit);
        uint256 firstEpochEnd = START_BLOCK + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(firstEpochEnd);
        multiplier.updateMultiplier(POOL_A);
        uint256 miAfterFirst = multiplier.M_i(POOL_A);
        uint256 inc = (unit * 110) / 100;
        ema.setTVLEMA(POOL_A, inc);
        ema.setTVLEMA(POOL_B, inc);
        ema.setTVLEMA(POOL_C, inc);
        uint256 secondEpochEnd = firstEpochEnd + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(secondEpochEnd);
        multiplier.updateMultiplier(POOL_A);
        assertEq(multiplier.M_i(POOL_A), miAfterFirst - 2 * STEP_SIZE);
    }

    function test_updateMultiplier_channelsCancel() public {
        address[] memory pl = new address[](2);
        pl[0] = POOL_A;
        pl[1] = POOL_B;
        registry.setPoolList(pl);
        registry.setMiliarium(POOL_A, true);
        registry.setMiliarium(POOL_B, true);
        ema.setTVLEMA(POOL_A, 1000e18);
        ema.setTVLEMA(POOL_B, 1000e18);
        uint256 epoch1 = START_BLOCK + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(epoch1);
        multiplier.updateMultiplier(POOL_A);
        uint256 lastAgg = multiplier.lastProtocolAggregateEMA();
        uint256 targetSum = lastAgg * (ONE + DEAD_ZONE) / ONE + 1000e18;
        ema.setTVLEMA(POOL_A, 50e18);
        ema.setTVLEMA(POOL_B, targetSum - 50e18);
        uint256 epoch2 = epoch1 + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(epoch2);
        uint256 miBefore = multiplier.M_i(POOL_A);
        multiplier.updateMultiplier(POOL_A);
        assertEq(multiplier.M_i(POOL_A), miBefore);
    }

    function test_updateMultiplier_clampFloor() public {
        address[] memory pl = new address[](3);
        pl[0] = POOL_A;
        pl[1] = POOL_B;
        pl[2] = POOL_C;
        registry.setPoolList(pl);
        registry.setMiliarium(POOL_A, true);
        registry.setMiliarium(POOL_B, true);
        registry.setMiliarium(POOL_C, true);
        uint256 unit = 28_000e18;
        ema.setTVLEMA(POOL_A, unit);
        ema.setTVLEMA(POOL_B, unit);
        ema.setTVLEMA(POOL_C, unit);
        uint256 b = START_BLOCK + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(b);
        multiplier.updateMultiplier(POOL_A);
        uint256 inc = (unit * 110) / 100;
        for (uint256 k = 0; k < 3; ++k) {
            ema.setTVLEMA(POOL_A, inc);
            ema.setTVLEMA(POOL_B, inc);
            ema.setTVLEMA(POOL_C, inc);
            b = b + AureumTime.BLOCKS_PER_EPOCH;
            vm.roll(b);
            multiplier.updateMultiplier(POOL_A);
        }
        assertEq(multiplier.M_i(POOL_A), CLAMP_FLOOR);
    }

    function test_updateMultiplier_clampCeiling() public {
        address[] memory pl = new address[](3);
        pl[0] = POOL_A;
        pl[1] = POOL_B;
        pl[2] = POOL_C;
        registry.setPoolList(pl);
        registry.setMiliarium(POOL_A, true);
        registry.setMiliarium(POOL_B, true);
        registry.setMiliarium(POOL_C, true);
        uint256 u0 = 10_000e18;
        ema.setTVLEMA(POOL_A, u0);
        ema.setTVLEMA(POOL_B, u0);
        ema.setTVLEMA(POOL_C, u0);
        uint256 b = START_BLOCK + AureumTime.BLOCKS_PER_EPOCH;
        vm.roll(b);
        multiplier.updateMultiplier(POOL_A);
        uint256 sum = 29_000e18;
        for (uint256 k = 0; k < 4; ++k) {
            uint256 rest = sum - 100e18;
            ema.setTVLEMA(POOL_A, 100e18);
            ema.setTVLEMA(POOL_B, rest / 2);
            ema.setTVLEMA(POOL_C, rest / 2);
            b = b + AureumTime.BLOCKS_PER_EPOCH;
            vm.roll(b);
            multiplier.updateMultiplier(POOL_A);
            sum -= 1000e18;
        }
        assertEq(multiplier.M_i(POOL_A), CLAMP_CEILING);
    }

    function test_updateMultiplier_priorSentinel_Mi0() public {
        assertEq(multiplier.M_i(POOL_A), 0);
        address[] memory pl = new address[](1);
        pl[0] = POOL_A;
        registry.setPoolList(pl);
        registry.setMiliarium(POOL_A, true);
        ema.setTVLEMA(POOL_A, 1000e18);
        multiplier.updateMultiplier(POOL_A);
        uint256 m = multiplier.M_i(POOL_A);
        assertGe(m, CLAMP_FLOOR);
        assertLe(m, CLAMP_CEILING);
        assertTrue(m != 0);
    }

    function test_updateMultiplier_writesLastBlock() public {
        address[] memory pl = new address[](1);
        pl[0] = POOL_A;
        registry.setPoolList(pl);
        registry.setMiliarium(POOL_A, true);
        ema.setTVLEMA(POOL_A, 1000e18);
        uint256 currentBlock = block.number;
        multiplier.updateMultiplier(POOL_A);
        assertEq(multiplier.lastMultiplierUpdateBlock(POOL_A), currentBlock);
    }

    function test_updateMultiplier_updatesLastAgg() public {
        address[] memory pl = new address[](1);
        pl[0] = POOL_A;
        registry.setPoolList(pl);
        registry.setMiliarium(POOL_A, true);
        ema.setTVLEMA(POOL_A, 777e18);
        multiplier.updateMultiplier(POOL_A);
        assertEq(multiplier.lastProtocolAggregateEMA(), 777e18);
    }

    // -------------------------------------------------------------------------
    // getMultiplier
    // -------------------------------------------------------------------------

    function test_getMultiplier_nonMiliarium_returnsInitial() public view {
        assertEq(multiplier.getMultiplier(POOL_A), INITIAL_MULTIPLIER);
    }

    function test_getMultiplier_unwrittenMi_returnsInitial() public {
        registry.setMiliarium(POOL_A, true);
        assertEq(multiplier.M_i(POOL_A), 0);
        assertEq(multiplier.getMultiplier(POOL_A), INITIAL_MULTIPLIER);
    }

    function test_getMultiplier_writtenMi_returnsMi() public {
        address[] memory pl = new address[](1);
        pl[0] = POOL_A;
        registry.setPoolList(pl);
        registry.setMiliarium(POOL_A, true);
        ema.setTVLEMA(POOL_A, 1000e18);
        multiplier.updateMultiplier(POOL_A);
        assertEq(multiplier.getMultiplier(POOL_A), multiplier.M_i(POOL_A));
    }
}
