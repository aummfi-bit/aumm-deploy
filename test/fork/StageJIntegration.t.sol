// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { MiliariumRegistry } from "../../src/registry/MiliariumRegistry.sol";
import { EMASampler } from "../../src/ccb/EMASampler.sol";
import { CCBMultiplier } from "../../src/ccb/CCBMultiplier.sol";
import { IEMASampler } from "../../src/ccb/IEMASampler.sol";
import { AureumTime } from "../../src/lib/AureumTime.sol";
import { MockTVLOracle, MockMiliariumRegistry, MockGaugeRegistry } from "./mocks/CCBMocks.sol";

/**
 * @title StageJIntegrationFixture
 * @notice Stage J integration base — the real `MiliariumRegistry` wired into the live
 *         `CCBMultiplier` dense-enumeration consumer, CCB stack stood up directly (no fork pool deployment).
 * @dev Self-contained CCB stack — `MockTVLOracle` (the J-D8 mocked TVL leg) feeds a real `EMASampler`; a real
 *      `MiliariumRegistry` genesis-seeded at 1-based slots `[1, 5, 14]` with three synthetic pool addresses
 *      (governance = `address(this)` so J4.3 may `replaceSlot` without a prank); a `MockMiliariumRegistry`
 *      placeholder satisfies the `CCBMultiplier` constructor; a `MockGaugeRegistry` seeded with the same three
 *      pilots is the PB-D18 (ii) `delta_global` universe — Miliarium slot swaps never mutate it, so the
 *      aggregate and the intra mean are decoupled witnesses (PB-D18 (iii)); then the F-D20
 *      `setMiliariumRegistry` handoff re-points the live `CCBMultiplier` onto the real registry. Synthetic pool
 *      addresses suffice for the J-D1 dense-enumeration proof — the registry makes no calls into pools
 *      (H13-safe) and the TVL leg is mocked (J-D8) — isolating exactly the registry-to-`CCBMultiplier` surface.
 *      Anchors: J-D1 dual structure; J-D8 (mocked TVL); F-D20 one-shot handoff; PB-D18 (ii)/(iii) roster split.
 */
abstract contract StageJIntegrationFixture is Test {
    MiliariumRegistry internal registry;
    MockTVLOracle internal mockOracle;
    MockMiliariumRegistry internal mockMiliarium;
    MockGaugeRegistry internal mockGauge;
    EMASampler internal sampler;
    CCBMultiplier internal multiplier;
    address[3] internal pilotPools;

    function setUp() public virtual {
        pilotPools[0] = makeAddr("pilot01");
        pilotPools[1] = makeAddr("pilot05");
        pilotPools[2] = makeAddr("pilot14");
        registry = _deployRegistry();
        mockOracle = new MockTVLOracle();
        mockMiliarium = new MockMiliariumRegistry(pilotPools);
        mockGauge = new MockGaugeRegistry();
        // PB-D18 (ii) — the delta_global universe: the gauge roster mirrors the three pilots. Seeded once;
        // replaceSlot never touches it (gauge membership is orthogonal to Miliarium slots per PB-D18 (iii)).
        address[] memory gaugeList = new address[](3);
        gaugeList[0] = pilotPools[0];
        gaugeList[1] = pilotPools[1];
        gaugeList[2] = pilotPools[2];
        mockGauge.setGaugeList(gaugeList);
        sampler = new EMASampler(mockOracle);
        multiplier = new CCBMultiplier(mockMiliarium, IEMASampler(address(sampler)), mockGauge);
        // F-D20 Stage J handoff
        multiplier.setMiliariumRegistry(registry);
    }

    function _deployRegistry() private returns (MiliariumRegistry) {
        // 1-based slots [1, 5, 14] (der Bodensee pilots per 04_tokenomics.md §vii)
        uint256[] memory slotNumbers = new uint256[](3);
        slotNumbers[0] = 1;
        slotNumbers[1] = 5;
        slotNumbers[2] = 14;
        address[] memory pools = new address[](3);
        pools[0] = pilotPools[0];
        pools[1] = pilotPools[1];
        pools[2] = pilotPools[2];
        return new MiliariumRegistry(address(this), slotNumbers, pools);
    }
}

contract StageJDenseEnumerationTest is StageJIntegrationFixture {
    uint256 internal constant UNIFORM_TVL = 1_000e18;
    uint256 internal constant EXPECTED_POST_STEP_M = 95e16;

    function test_StageJ_DenseEnumeration_RealRegistryThreePoolsNoZero() external {
        assertEq(registry.miliariumPoolsCount(), 3, "dense count = 3 real pools");
        for (uint256 i = 0; i < 3; ++i) {
            address p = registry.miliariumPoolAt(i);
            assertTrue(p != address(0), "no address(0) in dense enumeration");
            assertEq(p, pilotPools[i], "dense[i] = pilot i");
        }
    }

    function test_StageJ_DenseEnumeration_MultiplierBoundToRealRegistry() external {
        assertEq(address(multiplier.miliariumRegistry()), address(registry), "F-D20 handoff bound the real registry");
    }

    function test_StageJ_DenseEnumeration_UpdateMultiplierSumsRealRegistry() external {
        // Non-fork block.number starts at 1 — advance past the F-D6 epoch cadence so updateMultiplier is eligible.
        vm.roll(block.number + AureumTime.BLOCKS_PER_EPOCH);
        for (uint256 i = 0; i < 3; ++i) {
            mockOracle.set(pilotPools[i], UNIFORM_TVL);
            sampler.updateEMA(pilotPools[i]);
        }

        multiplier.updateMultiplier(pilotPools[0]);

        // deltaGlobal = 0 (F-D18 cold-start sentinel: lastProtocolAggregateEMA == 0); poolEMA (1_000e18) far exceeds miliariumAgg/28, so deltaIntra = -STEP_SIZE; M_i = 1.0 - 0.05 = 0.95.
        assertEq(multiplier.M_i(pilotPools[0]), EXPECTED_POST_STEP_M, "F-8 step from real-registry aggregate (deltaIntra = -STEP)");
        assertEq(multiplier.lastProtocolAggregateEMA(), 3 * UNIFORM_TVL, "aggregate = gauge-roster sum (mirrors the 3 pilots per PB-D18 (ii))");
    }

    function test_StageJ_ReplaceSlot_ReEnumerates() external {
        address newPool = makeAddr("newPilotSlot1");
        assertTrue(registry.isMiliarium(pilotPools[0]), "pilot0 member pre-replace");
        assertEq(registry.poolAtSlot(1), pilotPools[0], "slot 1 holds pilot0 pre-replace");
        // Test contract == governance (registry constructed with address(this)); call directly.
        registry.replaceSlot(1, newPool);
        assertEq(registry.miliariumPoolsCount(), 3, "dense count unchanged after replace");
        assertFalse(registry.isMiliarium(pilotPools[0]), "pilot0 dropped from membership");
        assertTrue(registry.isMiliarium(newPool), "newPool added to membership");
        assertEq(registry.poolAtSlot(1), newPool, "slot 1 now holds newPool");
        assertEq(registry.slotOf(pilotPools[0]), 0, "pilot0 slotOf reset to 0 sentinel");
        assertEq(registry.slotOf(newPool), 1, "newPool slotOf = 1");
        bool sawOld;
        bool sawNew;
        for (uint256 i = 0; i < 3; ++i) {
            address p = registry.miliariumPoolAt(i);
            assertTrue(p != address(0), "no address(0) in dense enumeration after replace");
            if (p == pilotPools[0]) sawOld = true;
            if (p == newPool) sawNew = true;
        }
        assertFalse(sawOld, "dropped pilot0 absent from dense enumeration");
        assertTrue(sawNew, "newPool present in dense enumeration");
    }

    function test_StageJ_ReplaceSlot_CCBAggregateDecoupledFromSwap() external {
        // Non-fork block.number starts at 1 — advance past the F-D6 epoch cadence.
        vm.roll(block.number + AureumTime.BLOCKS_PER_EPOCH);
        address newPool = makeAddr("newPilotSlot1");
        // The dropped pilot0 carries a distinctive large TVL. Post-PB-D18 it MUST survive in the aggregate
        // (pilot0 stays gauged; replaceSlot moves only the Miliarium slot) and must NOT survive in the intra mean.
        mockOracle.set(pilotPools[0], 9_000e18);
        mockOracle.set(pilotPools[1], UNIFORM_TVL);
        mockOracle.set(pilotPools[2], UNIFORM_TVL);
        sampler.updateEMA(pilotPools[0]);
        sampler.updateEMA(pilotPools[1]);
        sampler.updateEMA(pilotPools[2]);
        registry.replaceSlot(1, newPool);
        mockOracle.set(newPool, UNIFORM_TVL);
        sampler.updateEMA(newPool);
        multiplier.updateMultiplier(newPool);
        // PB-D18 (ii)/(iii) decoupling — the aggregate walks the UNMOVED gauge roster {pilot0, pilot1, pilot2}
        // = 9_000e18 + 2 × UNIFORM_TVL: pilot0's distinctive TVL survives, newPool is absent. The Miliarium
        // universe followed the swap: updateMultiplier(newPool) passes the isMiliarium gate (post-swap member)
        // and its intra mean is the post-swap sum {newPool, pilot1, pilot2}/28, far below newPool's EMA.
        assertEq(multiplier.lastProtocolAggregateEMA(), 9_000e18 + 2 * UNIFORM_TVL, "aggregate decoupled from swap - dropped pilot0 survives in gauge sum, newPool absent");
        assertEq(multiplier.M_i(newPool), EXPECTED_POST_STEP_M, "F-8 step on post-swap newPool (deltaIntra = -STEP from the post-swap Miliarium mean)");
    }
}
