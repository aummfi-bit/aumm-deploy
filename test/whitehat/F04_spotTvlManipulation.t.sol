// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {VotingWeight} from "src/governance/VotingWeight.sol";
import {ITVLOracle} from "src/ccb/ITVLOracle.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IEmissionDistributor} from "src/emission/IEmissionDistributor.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {MockTVLOracle, MockGaugeRegistry, MockRecorder, MockMiliariumRegistry} from "test/unit/VotingWeight.t.sol";

/// @notice F-04 (S7) — `VotingWeight._positionPower` consumes `ORACLE.tvl(pool)` as an atomic spot read (VotingWeight L142), so a spot-tvl pump inflates `governanceWeight` with no change to the recorder position (structurally manipulable); the F-9 power root (`0.25e18` Era0 / `ONE/3` Era1+, L149-152) caps the gain at the 4th/3rd root of the pump, self-limiting it.
contract F04_SpotTvlManipulationTest is Test {
    MockTVLOracle oracle;
    MockGaugeRegistry gaugeReg;
    MockRecorder recorder;
    MockMiliariumRegistry registry;
    VotingWeight vw;

    uint256 constant GENESIS_BLOCK = 1_000_000;
    uint256 constant START_BLOCK = 2_000_000;
    address constant POOL = address(0xA1);
    address constant ATTACKER = address(0x1111);

    function setUp() public {
        oracle = new MockTVLOracle();
        gaugeReg = new MockGaugeRegistry();
        recorder = new MockRecorder();
        registry = new MockMiliariumRegistry();
        vw = new VotingWeight(oracle, gaugeReg, recorder, registry, GENESIS_BLOCK);
        vm.roll(START_BLOCK);
        address[] memory pools = new address[](1);
        pools[0] = POOL;
        registry.setPoolList(pools);
        gaugeReg.setApproved(POOL, true);
        recorder.setUserLP(POOL, ATTACKER, 1e18);
        recorder.setPoolTotalLP(POOL, 1e18);
        recorder.setEffectiveQualBlock(POOL, ATTACKER, START_BLOCK - AureumTime.ON_RAMP_PERIOD_BLOCKS);
    }

    function _pokeAndRead(uint256 spotTvl) private returns (uint256) {
        oracle.setTvl(POOL, spotTvl);
        vw.poke(ATTACKER);
        return vw.governanceWeight(ATTACKER);
    }

    function test_SpotTvlPump_MovesWeight_QuarticDampedEra0() public {
        uint256 w1 = _pokeAndRead(1_000e18);
        uint256 w16 = _pokeAndRead(16_000e18);
        assertGt(w16, w1);
        assertApproxEqRel(w16, 2 * w1, 0.01e18);
        assertLt(w16, 3 * w1);
    }

    function test_SpotTvlPump_CubeRootDampedEra1Plus() public {
        vm.roll(AureumTime.firstHalvingBlock(GENESIS_BLOCK) + 500_000);
        recorder.setEffectiveQualBlock(POOL, ATTACKER, block.number - AureumTime.ON_RAMP_PERIOD_BLOCKS);
        uint256 w1 = _pokeAndRead(1_000e18);
        uint256 w8 = _pokeAndRead(8_000e18);
        assertApproxEqRel(w8, 2 * w1, 0.01e18);
        assertLt(w8, 3 * w1);
    }

    function test_ExtremeSpotTvlPump_YieldsBoundedWeight_Era0() public {
        uint256 w1 = _pokeAndRead(1e18);
        uint256 wHuge = _pokeAndRead(10_000e18);
        assertApproxEqRel(wHuge, 10 * w1, 0.01e18);
        assertLt(wHuge, 11 * w1);
    }
}
