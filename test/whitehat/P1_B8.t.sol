// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {VotingWeight} from "src/governance/VotingWeight.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {MockEMASampler, MockGaugeRegistry, MockMiliariumRegistry, MockRecorder} from "test/unit/VotingWeight.t.sol";

/// @title P1 B.8 — era exponent applied only inside poke and stored
/// @notice Reproduction PoC for seam-1 root cause B.8 (Low). After firstHalvingBlock the
///         electorate sums a mix of Era-0 and Era-1+ scaled weights until every holder
///         individually re-pokes — the exponent at VotingWeight.sol:191-194 is read only
///         on the poke write path, never on the governanceWeight view.
contract P1_B8_LazyEraExponentTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant TVL_EMA = 1_000_000e18;
    /// @dev 1_000_000^(1/12) in 1e18 fixed point — ema^(1/3)/ema^(1/4); independent of powDown.
    uint256 internal constant ERA_GAIN_1E6 = 3162277660168379300;

    MockEMASampler internal emaSampler;
    MockGaugeRegistry internal gaugeReg;
    MockMiliariumRegistry internal registry;
    MockRecorder internal recorder;
    VotingWeight internal vw;

    address internal poolA;
    address internal poolB;
    address internal twinA;
    address internal twinB;

    function setUp() public {
        uint256 startBlock = GENESIS_BLOCK + AureumTime.ON_RAMP_PERIOD_BLOCKS + 1;
        vm.roll(startBlock);

        emaSampler = new MockEMASampler();
        gaugeReg = new MockGaugeRegistry();
        registry = new MockMiliariumRegistry();
        recorder = new MockRecorder();
        vw = new VotingWeight(emaSampler, gaugeReg, recorder, registry, GENESIS_BLOCK);

        poolA = makeAddr("poolA");
        poolB = makeAddr("poolB");
        twinA = makeAddr("twinA");
        twinB = makeAddr("twinB");

        gaugeReg.setApproved(poolA, true);
        gaugeReg.setApproved(poolB, true);
        registry.setMiliarium(poolA, true);
        registry.setMiliarium(poolB, true);

        address[] memory pools = new address[](2);
        pools[0] = poolA;
        pools[1] = poolB;
        registry.setPoolList(pools);

        vm.mockCall(poolA, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(1e30)));
        vm.mockCall(poolB, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(1e30)));

        uint256 eqb = startBlock - AureumTime.ON_RAMP_PERIOD_BLOCKS;
        _configureIdenticalPosition(poolA, twinA, eqb);
        _configureIdenticalPosition(poolB, twinB, eqb);
    }

    function _configureIdenticalPosition(address pool, address holder, uint256 eqb) internal {
        emaSampler.setTvlEMA(pool, TVL_EMA);
        emaSampler.setSeedBlock(pool, 1);
        emaSampler.setLastUpdateBlock(pool, block.number);
        recorder.setUserLP(pool, holder, 100e18);
        recorder.setPoolTotalLP(pool, 100e18);
        recorder.setEffectiveQualBlock(pool, holder, eqb);
    }

    /// @dev Pins the mixed-scale electorate: unpoked twinA stays at Era-0 while twinB re-pokes into Era-1+.
    function test_P1_B8_unpokedHolderStaysAtTheEra0ExponentPastTheHalving() public {
        uint256 startBlock = GENESIS_BLOCK + AureumTime.ON_RAMP_PERIOD_BLOCKS + 1;

        vw.poke(twinA);
        vw.poke(twinB);

        uint256 weightAEra0 = vw.governanceWeight(twinA);
        uint256 weightBEra0 = vw.governanceWeight(twinB);
        assertEq(weightAEra0, weightBEra0, "twins are identical while still in Era 0");

        uint256 halvingBlock = AureumTime.firstHalvingBlock(GENESIS_BLOCK);
        vm.roll(halvingBlock);
        // Refresh freshness so the post-halving poke is not zeroed by the F-05 staleness gate.
        emaSampler.setLastUpdateBlock(poolA, block.number);
        emaSampler.setLastUpdateBlock(poolB, block.number);

        vw.poke(twinB);

        assertEq(vw.governanceWeight(twinA), weightAEra0, "unpoked checkpoint does not move at the era boundary");
        assertGt(vw.governanceWeight(twinB), vw.governanceWeight(twinA), "re-poked twin picks up the Era-1+ exponent");
        assertApproxEqRel(
            vw.governanceWeight(twinB) * 1e18 / vw.governanceWeight(twinA),
            ERA_GAIN_1E6,
            1e15
        );

        uint256 mixedSupply = vw.governanceWeight(twinA) + vw.governanceWeight(twinB);
        vm.roll(halvingBlock + 1);

        assertEq(vw.getPastTotalSupply(startBlock), weightAEra0 * 2, "pre-halving snapshot is both Era-0 weights");
        assertEq(
            vw.getPastTotalSupply(halvingBlock),
            mixedSupply,
            "live electorate mixes Era-0 and Era-1+ scales until twinA re-pokes"
        );
    }

    /// @dev Pins the self-heal: a second poke brings twinA onto the same Era-1+ scale as twinB.
    function test_P1_B8_rePokingSelfHealsToTheEra1PlusExponent() public {
        vw.poke(twinA);
        vw.poke(twinB);

        uint256 halvingBlock = AureumTime.firstHalvingBlock(GENESIS_BLOCK);
        vm.roll(halvingBlock);
        emaSampler.setLastUpdateBlock(poolA, block.number);
        emaSampler.setLastUpdateBlock(poolB, block.number);

        vw.poke(twinB);
        vw.poke(twinA);

        assertApproxEqRel(vw.governanceWeight(twinA), vw.governanceWeight(twinB), 1e15);
    }
}
