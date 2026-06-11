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

/// @notice White-hat finding F-02 (S9): proves the F-9 concave power curve `base.powDown(0.25e18)`
///         (VotingWeight L152) is subadditive, so splitting one LP position across N addresses multiplies
///         summed governanceWeight by ~N^(3/4) in Era 0 — defeating anti-plutocracy dampening.
contract F02_ConcaveSplitSybilTest is Test {
    MockTVLOracle internal oracle;
    MockGaugeRegistry internal gaugeReg;
    MockRecorder internal recorder;
    MockMiliariumRegistry internal registry;
    VotingWeight internal vw;

    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant START_BLOCK = 2_000_000;
    address internal constant POOL = address(0xA1);
    uint256 internal constant TVL = 1_000_000e18;
    uint256 internal constant POOL_TOTAL_LP = 1_000e18;
    uint256 internal constant EQB_FULL_ONRAMP = START_BLOCK - AureumTime.ON_RAMP_PERIOD_BLOCKS;

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
        registry.setMiliarium(POOL, true);
        gaugeReg.setApproved(POOL, true);
        oracle.setTvl(POOL, TVL);
        recorder.setPoolTotalLP(POOL, POOL_TOTAL_LP);
    }

    function _weightOfSplit(uint256 n, uint256 totalLP) internal returns (uint256 sumWeight) {
        for (uint256 i = 0; i < n; ++i) {
            address a = address(uint160(uint256(keccak256(abi.encodePacked("split", n, i)))));
            recorder.setUserLP(POOL, a, totalLP / n);
            recorder.setEffectiveQualBlock(POOL, a, EQB_FULL_ONRAMP);
            vw.poke(a);
            sumWeight += vw.governanceWeight(a);
        }
    }

    function test_singleConsolidatedPositionWeight() public {
        // Single and split addresses are independent — the mock does not enforce Σ userLP == poolTotalLP,
        // so the comparison isolates the formula's subadditive splitting gain at identical total value.
        address holder = address(0xDEAD);
        recorder.setUserLP(POOL, holder, POOL_TOTAL_LP);
        recorder.setEffectiveQualBlock(POOL, holder, EQB_FULL_ONRAMP);
        vw.poke(holder);
        uint256 wSingle = vw.governanceWeight(holder);
        assertGt(wSingle, 0);
    }

    function test_split16xGivesApprox8xWeight() public {
        // Single and split addresses are independent — the mock does not enforce Σ userLP == poolTotalLP,
        // so the comparison isolates the formula's subadditive splitting gain at identical total value.
        uint256 wSingle = _weightOfSplit(1, POOL_TOTAL_LP);
        uint256 wSplit16 = _weightOfSplit(16, POOL_TOTAL_LP);
        assertGt(wSplit16, wSingle);
        assertGt(wSplit16, wSingle * 7);
        assertLt(wSplit16, wSingle * 9);
    }

    function test_split81xGivesApprox27xWeight() public {
        // Single and split addresses are independent — the mock does not enforce Σ userLP == poolTotalLP,
        // so the comparison isolates the formula's subadditive splitting gain at identical total value.
        uint256 wSingle = _weightOfSplit(1, POOL_TOTAL_LP);
        uint256 wSplit81 = _weightOfSplit(81, POOL_TOTAL_LP);
        assertGt(wSplit81, wSingle);
        assertGt(wSplit81, wSingle * 24);
        assertLt(wSplit81, wSingle * 30);
    }
}
