// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {VotingWeight} from "src/governance/VotingWeight.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IEmissionDistributor} from "src/emission/IEmissionDistributor.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {MockEMASampler, MockGaugeRegistry, MockRecorder, MockMiliariumRegistry} from "test/unit/VotingWeight.t.sol";

/// @notice White-hat finding F-02 regression (S9, Fixed): proves the pool-aggregate F-9 root
///         (`tvlEMA^e × share × timeFactor`, linear holder leg) is split-invariant — splitting one
///         LP position across N addresses never increases summed governanceWeight; rounding-down
///         means the split sums to the consolidated weight minus dust, closing the Sybil-split gain.
contract F02_ConcaveSplitSybilTest is Test {
    MockEMASampler internal emaSampler;
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
        emaSampler = new MockEMASampler();
        gaugeReg = new MockGaugeRegistry();
        recorder = new MockRecorder();
        registry = new MockMiliariumRegistry();
        vw = new VotingWeight(emaSampler, gaugeReg, recorder, registry, GENESIS_BLOCK);
        vm.roll(START_BLOCK);
        address[] memory pools = new address[](1);
        pools[0] = POOL;
        registry.setPoolList(pools);
        registry.setMiliarium(POOL, true);
        gaugeReg.setApproved(POOL, true);
        emaSampler.setTvlEMA(POOL, TVL);
        emaSampler.setSeedBlock(POOL, 1);
        // F-05 freshness gate: stamp the EMA as updated now so the mature seed (block 1) confers weight.
        emaSampler.setLastUpdateBlock(POOL, block.number);
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

    function test_F02_SingleConsolidatedPosition_NonzeroBaseline() public {
        // Single and split addresses are independent — the mock does not enforce Σ userLP == poolTotalLP,
        // so the comparison isolates the formula's subadditive splitting gain at identical total value.
        address holder = address(0xDEAD);
        recorder.setUserLP(POOL, holder, POOL_TOTAL_LP);
        recorder.setEffectiveQualBlock(POOL, holder, EQB_FULL_ONRAMP);
        vw.poke(holder);
        uint256 wSingle = vw.governanceWeight(holder);
        assertGt(wSingle, 0);
    }

    function test_F02_Split16_WeightInvariant_NeverGains() public {
        // Single and split addresses are independent — the mock does not enforce Σ userLP == poolTotalLP,
        // so the comparison isolates split behavior at identical total value — the linear holder leg makes the split sum to ≤ the consolidated weight (rounding dust only).
        uint256 wSingle = _weightOfSplit(1, POOL_TOTAL_LP);
        uint256 wSplit16 = _weightOfSplit(16, POOL_TOTAL_LP);
        assertLe(wSplit16, wSingle);
        assertApproxEqRel(wSplit16, wSingle, 1e12);
    }

    function test_F02_Split81_WeightInvariant_NeverGains() public {
        // Single and split addresses are independent — the mock does not enforce Σ userLP == poolTotalLP,
        // so the comparison isolates split behavior at identical total value — the linear holder leg makes the split sum to ≤ the consolidated weight (rounding dust only).
        uint256 wSingle = _weightOfSplit(1, POOL_TOTAL_LP);
        uint256 wSplit81 = _weightOfSplit(81, POOL_TOTAL_LP);
        assertLe(wSplit81, wSingle);
        assertApproxEqRel(wSplit81, wSingle, 1e12);
    }
}
