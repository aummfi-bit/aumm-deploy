// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { MiliariumRegistry } from "../../src/registry/MiliariumRegistry.sol";
import { EMASampler } from "../../src/ccb/EMASampler.sol";
import { CCBMultiplier } from "../../src/ccb/CCBMultiplier.sol";
import { IEMASampler } from "../../src/ccb/IEMASampler.sol";
import { MockTVLOracle, MockMiliariumRegistry, MockGaugeRegistry } from "./mocks/CCBMocks.sol";

/**
 * @title StageJIntegrationFixture
 * @notice Stage J integration base — the real `MiliariumRegistry` wired into the live
 *         `CCBMultiplier` dense-enumeration consumer, CCB stack stood up directly (no fork pool deployment).
 * @dev Self-contained CCB stack — `MockTVLOracle` (the J-D8 mocked TVL leg) feeds a real `EMASampler`; a real
 *      `MiliariumRegistry` genesis-seeded at 1-based slots `[2, 3, 7]` with three synthetic pool addresses
 *      (governance = `address(this)` so J4.3 may `replaceSlot` without a prank); a `MockMiliariumRegistry`
 *      placeholder and `MockGaugeRegistry` satisfy the `CCBMultiplier` constructor; then the F-D20
 *      `setMiliariumRegistry` handoff re-points the live `CCBMultiplier` onto the real registry. Synthetic pool
 *      addresses suffice for the J-D1 dense-enumeration proof — the registry makes no calls into pools
 *      (H13-safe) and the TVL leg is mocked (J-D8) — isolating exactly the registry-to-`CCBMultiplier` surface.
 *      Anchors: J-D1 dual structure; J-D8 (mocked TVL); F-D20 one-shot handoff.
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
        pilotPools[0] = makeAddr("pilot02");
        pilotPools[1] = makeAddr("pilot03");
        pilotPools[2] = makeAddr("pilot07");
        registry = _deployRegistry();
        mockOracle = new MockTVLOracle();
        mockMiliarium = new MockMiliariumRegistry(pilotPools);
        mockGauge = new MockGaugeRegistry();
        sampler = new EMASampler(mockOracle);
        multiplier = new CCBMultiplier(mockMiliarium, mockGauge, IEMASampler(address(sampler)));
        // F-D20 Stage J handoff
        multiplier.setMiliariumRegistry(registry);
    }

    function _deployRegistry() private returns (MiliariumRegistry) {
        // 1-based slots [2, 3, 7] (der Bodensee pilots per 04_tokenomics.md §vii)
        uint256[] memory slotNumbers = new uint256[](3);
        slotNumbers[0] = 2;
        slotNumbers[1] = 3;
        slotNumbers[2] = 7;
        address[] memory pools = new address[](3);
        pools[0] = pilotPools[0];
        pools[1] = pilotPools[1];
        pools[2] = pilotPools[2];
        return new MiliariumRegistry(address(this), slotNumbers, pools);
    }
}
