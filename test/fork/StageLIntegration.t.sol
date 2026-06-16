// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { StageIIntegrationFixture } from "./StageIIntegration.t.sol";
import { IncendiaryRegistry } from "../../src/incendiary/IncendiaryRegistry.sol";
import { AuMMMinterRouter } from "../../src/token/AuMMMinterRouter.sol";
import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAuMM } from "../../src/token/IAuMM.sol";
import { AureumTime } from "../../src/lib/AureumTime.sol";

/**
 * @title StageLIntegrationFixture
 * @notice Stage L Incendiary-boost fork-test base — extends the Stage I emission stack with the live IncendiaryRegistry producer, the L-D25 boost-delivery leg armed on the EmissionDistributor, and the K-D7 claim → mint path, all against the real der Bodensee venue.
 * @dev Inherits StageIIntegrationFixture (vault + AuMM + der Bodensee + 3 pilots + hook + gaugeRegistry + emissionDistributor + bootstrapChannel + the _depositOneSided / _withdrawProportional helpers). StageK is deliberately NOT inherited — it hands gaugeRegistry governance to the on-chain Governance contract, but Stage L needs that governance to stay address(this) so the fixture can seedFoundingPool directly (L-D27). setUp adds, all authorised as address(this): seedFoundingPool(pilot) for the buyBoost L-D10 gate; the L-D16 8-arg IncendiaryRegistry deploy against the real venue; addAuthorizedDonator(registry) (L-D2 deposit tail); setIncendiaryRegistry(registry) (arms the L-D25 leg); and the K-D7 mint path — AuMMMinterRouter deploy + aumm.setMinter(router) one-shot + emissionDistributor.setMintRouter(router) (L8.6 is the first fork test to wire mint). EMA matured on the real venue per L-D18/L-D19: roll past Year 1, seed the svZCHF rail, roll past the 60-day EMA_MATURITY_BLOCKS so buyBoost's L-D3 phase gate and _maturePrice gate are both open. Anchors: L-D27, L-D2 / L-D10 / L-D16 / L-D25, K-D7, H13 (fixture-inheritance precedent).
 */
abstract contract StageLIntegrationFixture is StageIIntegrationFixture {
    IncendiaryRegistry internal registry;
    AuMMMinterRouter internal mintRouter;

    function setUp() public virtual override {
        super.setUp();

        // Gauge-approve the target pilot — buyBoost L-D10 gate. Founding-seed bypass; gaugeRegistry governance is address(this) (StageK NOT inherited per L-D27).
        gaugeRegistry.seedFoundingPool(pilotPools[0]);

        // Live IncendiaryRegistry against the real der Bodensee venue — L-D16 8-arg ctor.
        registry = new IncendiaryRegistry(
            swapAndDeposit,
            bodenseePool,
            IVaultExplorer(address(vault)),
            IAuMM(address(aumm)),
            svZchf,
            IERC20(address(susds)),
            gaugeRegistry,
            aumm.GENESIS_BLOCK()
        );

        // Admit the registry to the donate channel (L-D2 deposit tail) + arm the distributor's L-D25 delivery leg.
        swapAndDeposit.addAuthorizedDonator(address(registry));
        emissionDistributor.setIncendiaryRegistry(address(registry));

        // K-D7 mint path — L8.6 is the first fork test to exercise claim → mint.
        mintRouter = new AuMMMinterRouter(IAuMM(address(aumm)), address(bootstrapChannel), address(emissionDistributor));
        aumm.setMinter(address(mintRouter));
        emissionDistributor.setMintRouter(address(mintRouter));

        // EMA maturity on the real venue (L-D18/L-D19): roll past Year 1, seed the svZCHF rail, roll past the 60-day EMA_MATURITY_BLOCKS.
        vm.roll(AureumTime.year1EndBlock(aumm.GENESIS_BLOCK()) + 1);
        registry.updateRailEMA(address(svZchf));
        vm.roll(block.number + registry.EMA_MATURITY_BLOCKS());
    }
}

contract StageLWiringTest is StageLIntegrationFixture {
    /// @notice Asserts the full L8.6 wiring — registry immutables bound to the real components, the donate-channel authorization, the distributor's armed L-D25 + K-D7 slots, the mint path, and the Year-1-open phase gate.
    function test_stageL_wiring_registryImmutables_donatorAuth_distributorBindings_mintPath() public view {
        // IncendiaryRegistry immutables bound to the fixture's real components (L-D16).
        assertEq(address(registry.BODENSEE_CHANNEL()), address(swapAndDeposit));
        assertEq(registry.BODENSEE_POOL(), bodenseePool);
        assertEq(address(registry.VAULT_EXPLORER()), address(vault));
        assertEq(address(registry.AUMM()), address(aumm));
        assertEq(address(registry.SVZCHF()), address(svZchf));
        assertEq(address(registry.SUSDS()), address(susds));
        assertEq(address(registry.GAUGE_REGISTRY()), address(gaugeRegistry));
        assertEq(registry.GENESIS_BLOCK(), aumm.GENESIS_BLOCK());

        // Target pilot gauge-approved (buyBoost L-D10 gate).
        assertTrue(gaugeRegistry.isGaugeApproved(pilotPools[0]));

        // Donate channel admits the registry (L-D2 deposit tail).
        assertTrue(swapAndDeposit.authorizedDonators(address(registry)));

        // Distributor armed — L-D25 boost-delivery leg + K-D7 mint router.
        assertEq(emissionDistributor.incendiaryRegistry(), address(registry));
        assertEq(address(emissionDistributor.mintRouter()), address(mintRouter));

        // Mint path bound — router holds AuMM's one-shot minter slot; allowlist resolves to the two K-D7 consumers.
        assertEq(aumm.minter(), address(mintRouter));
        assertEq(address(mintRouter.AUMM()), address(aumm));
        assertEq(mintRouter.BOOTSTRAP_CHANNEL(), address(bootstrapChannel));
        assertEq(mintRouter.EMISSION_DISTRIBUTOR(), address(emissionDistributor));

        // setUp rolled past Year 1 — buyBoost's L-D3 phase gate is open and the svZCHF EMA has matured.
        assertGt(block.number, AureumTime.year1EndBlock(aumm.GENESIS_BLOCK()));
    }
}
