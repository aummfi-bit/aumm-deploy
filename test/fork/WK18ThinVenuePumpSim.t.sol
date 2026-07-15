// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { StageNIntegrationFixture } from "./StageNIntegration.t.sol";
import { IEMASampler } from "../../src/ccb/IEMASampler.sol";
import { VotingWeight } from "../../src/governance/VotingWeight.sol";

/**
 * @title WK18ThinVenuePumpSimFixture
 * @notice WK.18 thin-venue populated-roster fork sim — StageN roster base + VotingWeight only (PB-D16).
 * @dev Scaffold: wiring self-test only. Venues, EMA maturation, and the three assertion faces land in later sub-steps.
 */
abstract contract WK18ThinVenuePumpSimFixture is StageNIntegrationFixture {
    VotingWeight internal votingWeight;

    function setUp() public virtual override {
        super.setUp();
        votingWeight = new VotingWeight(IEMASampler(address(emaSampler)), gaugeRegistry, emissionDistributor, realRegistry, aumm.GENESIS_BLOCK());
    }
}

contract WK18SimWiringTest is WK18ThinVenuePumpSimFixture {
    function test_setUp_simWiring() public view {
        assertEq(address(votingWeight.EMA_SAMPLER()), address(emaSampler));
        assertEq(address(votingWeight.GAUGE_REGISTRY()), address(gaugeRegistry));
        assertEq(address(votingWeight.RECORDER()), address(emissionDistributor));
        assertEq(address(votingWeight.REGISTRY()), address(realRegistry));
        assertEq(votingWeight.GENESIS_BLOCK(), aumm.GENESIS_BLOCK());
        assertEq(realRegistry.miliariumPoolsCount(), 21);
    }
}
