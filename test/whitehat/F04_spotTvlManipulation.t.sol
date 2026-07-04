// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {VotingWeight} from "src/governance/VotingWeight.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IEmissionDistributor} from "src/emission/IEmissionDistributor.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {MockEMASampler, MockGaugeRegistry, MockRecorder, MockMiliariumRegistry} from "test/unit/VotingWeight.t.sol";

/// @notice F-04 fix regression (S7) — `VotingWeight._positionPower` now reads the 60-day
///         `EMASampler.tvlEMA` (not spot `ORACLE.tvl`) behind a 60-day `EMA_MATURITY_BLOCKS`
///         seed-age gate, so an attacker cannot seed-or-pump a pool's EMA and vote in the same
///         window; a mature EMA remains F-9 quartically bounded.
contract F04_SpotTvlManipulationTest is Test {
    MockEMASampler emaSampler;
    MockGaugeRegistry gaugeReg;
    MockRecorder recorder;
    MockMiliariumRegistry registry;
    VotingWeight vw;

    uint256 constant GENESIS_BLOCK = 1_000_000;
    uint256 constant START_BLOCK = 2_000_000;
    uint256 constant EMA_MATURITY = 60 * AureumTime.BLOCKS_PER_DAY;
    address constant POOL = address(0xA1);
    address constant ATTACKER = address(0x1111);

    function setUp() public {
        emaSampler = new MockEMASampler();
        gaugeReg = new MockGaugeRegistry();
        recorder = new MockRecorder();
        registry = new MockMiliariumRegistry();
        vw = new VotingWeight(emaSampler, gaugeReg, recorder, registry, GENESIS_BLOCK);
        // F-17 / P-D18: POOL is a code-less test constant; large `balanceOf` no-ops the _positionPower read-cap.
        vm.mockCall(POOL, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(1e30)));
        vm.roll(START_BLOCK);
        address[] memory pools = new address[](1);
        pools[0] = POOL;
        registry.setPoolList(pools);
        gaugeReg.setApproved(POOL, true);
        recorder.setUserLP(POOL, ATTACKER, 1e18);
        recorder.setPoolTotalLP(POOL, 1e18);
        recorder.setEffectiveQualBlock(POOL, ATTACKER, START_BLOCK - AureumTime.ON_RAMP_PERIOD_BLOCKS);
        // F-05 freshness gate: stamp the EMA as updated now; per-test seed blocks still drive the maturity scenarios.
        emaSampler.setLastUpdateBlock(POOL, block.number);
    }

    function _pokeAndRead(uint256 emaValue) private returns (uint256) {
        emaSampler.setTvlEMA(POOL, emaValue);
        vw.poke(ATTACKER);
        return vw.governanceWeight(ATTACKER);
    }

    function test_F04_FreshlySeededEmaPump_ConfersZeroWeight() public {
        emaSampler.setSeedBlock(POOL, START_BLOCK);
        uint256 w = _pokeAndRead(1_000_000e18);
        assertEq(w, 0);
        assertEq(vw.totalSupply(), 0);
    }

    function test_F04_ImmatureEmaPump_ConfersZeroWeight() public {
        emaSampler.setSeedBlock(POOL, START_BLOCK - EMA_MATURITY + 1);
        assertEq(_pokeAndRead(1_000_000e18), 0);
    }

    function test_F04_MatureEmaFlowsAtBoundary() public {
        emaSampler.setSeedBlock(POOL, START_BLOCK - EMA_MATURITY);
        assertGt(_pokeAndRead(16_000e18), 0);
    }

    function test_F04_MatureEmaResidualStillQuarticallyBounded() public {
        emaSampler.setSeedBlock(POOL, START_BLOCK - EMA_MATURITY);
        uint256 w1 = _pokeAndRead(1_000e18);
        uint256 w16 = _pokeAndRead(16_000e18);
        assertApproxEqRel(w16, 2 * w1, 0.01e18);
        assertLt(w16, 3 * w1);
    }
}
