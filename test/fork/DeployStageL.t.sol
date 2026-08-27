// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { StageIIntegrationFixture } from "./StageIIntegration.t.sol";
import { DeployStageL } from "../../script/DeployStageL.s.sol";
import { IncendiaryRegistry } from "../../src/incendiary/IncendiaryRegistry.sol";
import { AureumTime } from "../../src/lib/AureumTime.sol";

/**
 * @title DeployStageLForkTest
 * @notice Integration test for `script/DeployStageL.s.sol`. Inherits
 *         `StageIIntegrationFixture` — real der Bodensee venue, donate channel,
 *         gauge registry, and emission distributor with `governance == address(this)`
 *         and `swapAndDeposit.donateAuthorizer() == address(this)`. setUp seeds
 *         founding gauge approval on the target pilot, populates the eight deploy
 *         env vars from fixture members, then runs `DeployStageL.deploy(address(this))`
 *         and asserts the deployed registry immutables plus both wiring gates.
 *
 * @dev Run with:
 *
 *        forge test --match-path "test/fork/DeployStageL.t.sol" \
 *          --fork-url $MAINNET_RPC_URL --threads 1 -vv
 *
 *      Per D35 split-form + D36 `--threads 1` belt.
 *
 * @dev L9.2 inherits StageI (not StageLIntegrationFixture) — the deploy script
 *      test exercises wiring only; EMA maturity and buyBoost smoke coverage land
 *      in L9.2b. Real channel + distributor state is required because the two
 *      post-deploy wiring calls external-call into them (L-D28 H13 forward-note).
 */
contract DeployStageLForkTest is StageIIntegrationFixture {
    DeployStageL internal deployScript;
    IncendiaryRegistry internal registry;

    function setUp() public override {
        super.setUp();

        gaugeRegistry.seedFoundingPool(pilotPools[0]);

        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("SWAP_AND_DEPOSIT", vm.toString(address(swapAndDeposit)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("EMISSION_DISTRIBUTOR", vm.toString(address(emissionDistributor)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("BODENSEE_POOL", vm.toString(bodenseePool));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("VAULT", vm.toString(address(vault)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("AUMM", vm.toString(address(aumm)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("SV_ZCHF", vm.toString(address(svZchf)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("SUSDS", vm.toString(address(susds)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("GAUGE_REGISTRY", vm.toString(address(gaugeRegistry)));

        deployScript = new DeployStageL();
        registry = deployScript.deploy(address(this));
        vm.roll(block.number + 1);
        deployScript.acceptRegistry(address(this));
    }

    function test_DeployStageL_wiringState() public view {
        assertEq(address(registry.BODENSEE_CHANNEL()), address(swapAndDeposit));
        assertEq(registry.BODENSEE_POOL(), bodenseePool);
        assertEq(address(registry.VAULT_EXPLORER()), address(vault));
        assertEq(address(registry.AUMM()), address(aumm));
        assertEq(address(registry.SVZCHF()), address(svZchf));
        assertEq(address(registry.SUSDS()), address(susds));
        assertEq(address(registry.GAUGE_REGISTRY()), address(gaugeRegistry));
        assertEq(registry.GENESIS_BLOCK(), aumm.GENESIS_BLOCK());
        assertTrue(swapAndDeposit.authorizedDonators(address(registry)), "script addAuthorizedDonator wired the registry");
        assertEq(emissionDistributor.incendiaryRegistry(), address(registry), "script propose-then-accept wired the registry");
    }

    function test_DeployStageL_buyBoost_smoke() public {
        address buyer = makeAddr("deployBoostBuyer");
        uint256 amount = 10e18;
        vm.roll(AureumTime.year1EndBlock(aumm.GENESIS_BLOCK()) + 1);
        registry.updateRailEMA(address(svZchf));
        vm.roll(block.number + registry.EMA_MATURITY_BLOCKS());
        registry.updateRailEMA(address(svZchf));
        deal(address(svZchf), buyer, amount);
        vm.startPrank(buyer);
        svZchf.approve(address(registry), amount);
        uint256 entitlement = registry.buyBoost(pilotPools[0], address(svZchf), amount);
        vm.stopPrank();
        assertGt(entitlement, 0, "buyBoost through the script-wired registry placed a nonzero entitlement");
    }

    function test_DeployStageL_failFast_wrongGovernor_reverts() public {
        address rando = makeAddr("deployRando");
        DeployStageL freshScript = new DeployStageL();
        // vm.expectRevert(bytes4) does not match an error carrying args in this Foundry build —
        // encode the full error (selector + the distributor.governance() arg the first L-D28 gate reports).
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployStageL.DistributorGovernanceNotMultisig.selector,
                emissionDistributor.governance()
            )
        );
        freshScript.deploy(rando);
    }
}
