// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { StageIIntegrationFixture } from "./StageIIntegration.t.sol";
import { MiliariumRegistry } from "../../src/registry/MiliariumRegistry.sol";
import { VotingWeight } from "../../src/governance/VotingWeight.sol";
import { AureumGovernance } from "../../src/governance/AureumGovernance.sol";

/**
 * @title StageKIntegrationFixture
 * @notice Stage K fork-test base — inherits the Stage I recorder-clock stack (real `EmissionDistributor`
 *         bound to the `AureumFeeRoutingHook` one-shot `emissionRecorder`, per-pool recorder gate admitting
 *         `address(hook)`, real `TVLOracle`, real `GaugeRegistry`, AuMM / Bodensee / 3 pilots, and the
 *         `_depositOneSided` / `_withdrawProportional` / `getSender()` IRouterSender-shim helpers).
 * @dev Deploys a fresh real `MiliariumRegistry` serving BOTH `VotingWeight.REGISTRY` and
 *      `AureumGovernance.SLOT_REGISTRY` per J-D2 dual-interface, seeded at manifest slots [1, 5, 14].
 *      Seeds the 3 pilot gauges via `seedFoundingPool` (governance bypass) before the irreversible
 *      governance handoffs. Anchor: K4.7 design (STAGE_K_NOTES.md).
 */
abstract contract StageKIntegrationFixture is StageIIntegrationFixture {
    MiliariumRegistry internal realRegistry;
    VotingWeight internal votingWeight;
    AureumGovernance internal gov;

    function setUp() public virtual override {
        super.setUp();

        gaugeRegistry.seedFoundingPool(pilotPools[0]);
        gaugeRegistry.seedFoundingPool(pilotPools[1]);
        gaugeRegistry.seedFoundingPool(pilotPools[2]);

        uint256[] memory slots = new uint256[](3);
        slots[0] = 1;
        slots[1] = 5;
        slots[2] = 14;
        address[] memory pools = new address[](3);
        pools[0] = pilotPools[0];
        pools[1] = pilotPools[1];
        pools[2] = pilotPools[2];
        realRegistry = new MiliariumRegistry(address(this), slots, pools);

        votingWeight = new VotingWeight(tvlOracle, gaugeRegistry, emissionDistributor, realRegistry, aumm.GENESIS_BLOCK());

        gov = new AureumGovernance(
            votingWeight,
            gaugeRegistry,
            realRegistry,
            vault,
            swapAndDeposit,
            svZchf,
            IERC20(address(susds)),
            bodenseePool
        );

        swapAndDeposit.addAuthorizedDonator(address(gov));

        gaugeRegistry.setGovernanceContract(address(gov));
        realRegistry.setGovernanceContract(address(gov));
    }
}

contract StageKWiringTest is StageKIntegrationFixture {
    function test_setUp_stageKWiring() public view {
        assertEq(address(gov.VOTING_WEIGHT()), address(votingWeight));
        assertEq(address(gov.SLOT_REGISTRY()), address(realRegistry));
        assertEq(address(gov.GAUGE_REGISTRY()), address(gaugeRegistry));
        assertEq(address(gov.VAULT()), address(vault));
        assertEq(address(gov.BODENSEE_CHANNEL()), address(swapAndDeposit));
        assertEq(address(gov.SVZCHF()), address(svZchf));
        assertEq(address(gov.SUSDS()), address(susds));
        assertEq(gov.BODENSEE_POOL(), bodenseePool);

        assertEq(address(votingWeight.ORACLE()), address(tvlOracle));
        assertEq(address(votingWeight.GAUGE_REGISTRY()), address(gaugeRegistry));
        assertEq(address(votingWeight.RECORDER()), address(emissionDistributor));
        assertEq(address(votingWeight.REGISTRY()), address(realRegistry));
        assertEq(votingWeight.GENESIS_BLOCK(), aumm.GENESIS_BLOCK());

        assertTrue(gaugeRegistry.isGaugeApproved(pilotPools[0]));
        assertTrue(gaugeRegistry.isGaugeApproved(pilotPools[1]));
        assertTrue(gaugeRegistry.isGaugeApproved(pilotPools[2]));

        assertEq(realRegistry.poolAtSlot(1), pilotPools[0]);
        assertEq(realRegistry.poolAtSlot(5), pilotPools[1]);
        assertEq(realRegistry.poolAtSlot(14), pilotPools[2]);
        assertEq(realRegistry.miliariumPoolsCount(), 3);

        assertEq(realRegistry.governanceContract(), address(gov));
        assertTrue(swapAndDeposit.authorizedDonators(address(gov)));
    }
}
