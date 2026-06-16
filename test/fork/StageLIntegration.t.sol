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

contract StageLEndToEndTest is StageLIntegrationFixture {
    /// @notice End-to-end L8.6 — buy a directed boost with real svZCHF, settle it through the L-D25 delivery leg on a claim, and mint to the LP via the K-D7 router; asserts deliverability, the L-D23 conservation bound, the cursor advance, and that the boost stream reaches the LP.
    function test_stageL_endToEnd_buyBoost_delivers_to_lp_via_claim_mint() public {
        address lp = makeAddr("boostLP");
        address buyer = makeAddr("boostBuyer");
        address pilot = pilotPools[0];
        uint256 amount = 10e18; // svZCHF — small relative to the der Bodensee reserve; smoke-test input.

        // 1. Establish the sole recorded LP in the gauged pilot (initialize-seed liquidity is not hook-recorded).
        uint256 bptOut = _depositOneSided(pilot, lp, 100); // 1% one-sided add
        assertEq(emissionDistributor.poolTotalLP(pilot), bptOut, "lp is the sole recorded depositor");
        uint256 cursorAfterDeposit = emissionDistributor.poolBoostCursor(pilot);
        assertEq(cursorAfterDeposit, block.number, "deposit settle advanced the boost cursor to the deposit block");

        // 2. Buy a directed boost for the pilot — real svZCHF, matured EMA, open L-D3 phase.
        uint256 eBuy = AureumTime.epochIndex(aumm.GENESIS_BLOCK(), block.number);
        deal(address(svZchf), buyer, amount);
        vm.startPrank(buyer);
        svZchf.approve(address(registry), amount);
        uint256 entitlement = registry.buyBoost(pilot, address(svZchf), amount);
        vm.stopPrank();
        assertGt(entitlement, 0, "buyBoost placed a nonzero entitlement");

        // 3. Roll into the boost epochs — placement starts at eBuy+1; cover the L-D7 walk-forward spill window.
        vm.roll(AureumTime.epochEndBlock(aumm.GENESIS_BLOCK(), eBuy + 12));

        // 4. Read the deliverable boost + skim window, then claim (settles L-D25, crystallizes pending, mints via K-D7).
        uint256 claimBlock = block.number;
        uint256 boostDelivered = registry.boostIntegral(pilot, cursorAfterDeposit + 1, claimBlock);
        uint256 skimWindow = registry.integratedSkim(cursorAfterDeposit + 1, claimBlock);
        uint256 lpBalBefore = aumm.balanceOf(lp);
        vm.prank(lp);
        emissionDistributor.claim(pilot, lp);
        uint256 lpBalAfter = aumm.balanceOf(lp);

        // 5. Producer -> consumer -> mint assertions.
        assertGt(boostDelivered, 0, "purchased boost is deliverable over the settle window");
        assertLe(boostDelivered, entitlement, "delivered boost cannot exceed the purchased entitlement");
        assertLe(boostDelivered, skimWindow, "L-D23 conservation: boostIntegral <= integratedSkim");
        assertEq(emissionDistributor.poolBoostCursor(pilot), claimBlock, "L-D25 cursor advanced to the claim block");
        assertGt(lpBalAfter, lpBalBefore, "claim minted AuMM to the lp via the K-D7 mint router");
        // mint = CCB allocation + boost; the boost-leg share alone is >= boostDelivered - (poolTotalLP - 1).
        assertGe(lpBalAfter + emissionDistributor.poolTotalLP(pilot), boostDelivered, "boost stream reached the lp within flooring dust");
    }
}
