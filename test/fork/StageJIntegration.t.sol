// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { CCBEngineFixture } from "./CCBEngine.t.sol";
import { MiliariumRegistry } from "../../src/registry/MiliariumRegistry.sol";

/**
 * @title StageJIntegrationFixture
 * @notice Stage J fork-integration base — the real `MiliariumRegistry` wired into the live
 *         `CCBMultiplier` dense-enumeration consumer.
 * @dev Inherits `CCBEngineFixture` (fork Vault + 3 pilot pools + `EMASampler` + `CCBMultiplier`
 *      wired to mock registries); deploys a real `MiliariumRegistry` seeded `[2, 3, 7]` with the
 *      3 pilots, governance = `address(this)` so J4.3 may `replaceSlot` without a prank; performs
 *      the F-D20 Stage J handoff `multiplier.setMiliariumRegistry(registry)`, re-pointing the live
 *      `CCBMultiplier` off `mockMiliarium` onto the real dense-enumeration source; the TVL leg stays
 *      mocked (`MockTVLOracle`) per J-D8. Anchors: J-D1 dual structure; J-D8 (TVL mock); F-D20
 *      one-shot handoff; H13 fixture-inheritance precedent.
 */
abstract contract StageJIntegrationFixture is CCBEngineFixture {
    MiliariumRegistry internal registry;

    function setUp() public virtual override {
        super.setUp();

        // 1-based slots [2, 3, 7] (der Bodensee pilots per 04_tokenomics.md §vii)
        uint256[] memory slotNumbers = new uint256[](3);
        slotNumbers[0] = 2;
        slotNumbers[1] = 3;
        slotNumbers[2] = 7;

        address[] memory pools = new address[](3);
        pools[0] = pilotPools[0];
        pools[1] = pilotPools[1];
        pools[2] = pilotPools[2];

        registry = new MiliariumRegistry(address(this), slotNumbers, pools);

        // F-D20 Stage J handoff
        multiplier.setMiliariumRegistry(registry);
    }
}
