// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IncendiaryRegistry} from "../../src/incendiary/IncendiaryRegistry.sol";
import {IncendiaryRegistryHarness} from "./harness/IncendiaryRegistryHarness.sol";
import {MockBodenseeExplorer, MockWeightedVenue, MockBodenseeChannel, MockAuMMRate} from "../fork/mocks/StageLMocks.sol";
import {MockGaugeRegistry} from "../fork/mocks/CCBMocks.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {SwapAndDepositToBodensee} from "../../src/gauge/SwapAndDepositToBodensee.sol";
import {IVaultExplorer} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import {IAuMM} from "../../src/token/IAuMM.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGaugeRegistry} from "../../src/ccb/IGaugeRegistry.sol";
import {AureumTime} from "../../src/lib/AureumTime.sol";

contract IncendiaryRegistryTest is Test {
    IncendiaryRegistryHarness internal registry;
    MockBodenseeExplorer internal explorer;
    MockWeightedVenue internal venue;
    MockBodenseeChannel internal channel;
    MockAuMMRate internal aumm;
    MockGaugeRegistry internal gauges;
    MockERC20 internal svzchf;
    MockERC20 internal susds;

    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant BAL_AUMM = 1_000_000e18;
    uint256 internal constant BAL_SVZCHF = 750_000e18;
    uint256 internal constant BAL_SUSDS = 600_000e18;

    function setUp() public {
        vm.roll(GENESIS_BLOCK);

        explorer = new MockBodenseeExplorer();
        venue = new MockWeightedVenue();
        channel = new MockBodenseeChannel();
        aumm = new MockAuMMRate();
        gauges = new MockGaugeRegistry();
        svzchf = new MockERC20("Savings ZCHF", "svZCHF", 18);
        susds = new MockERC20("Savings USDS", "sUSDS", 18);

        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = IERC20(address(aumm));
        tokens[1] = IERC20(address(svzchf));
        tokens[2] = IERC20(address(susds));

        uint256[] memory balances = new uint256[](3);
        balances[0] = BAL_AUMM;
        balances[1] = BAL_SVZCHF;
        balances[2] = BAL_SUSDS;

        uint256[] memory rates = new uint256[](3);
        rates[0] = 1e18;
        rates[1] = 1e18;
        rates[2] = 1e18;

        uint256[] memory scaling = new uint256[](3);
        scaling[0] = 1;
        scaling[1] = 1;
        scaling[2] = 1;

        explorer.setPoolData(address(venue), tokens, balances, rates, scaling);

        uint256[] memory weights = new uint256[](3);
        weights[0] = 4e17;
        weights[1] = 3e17;
        weights[2] = 3e17;
        venue.setWeights(weights);

        registry = new IncendiaryRegistryHarness(
            SwapAndDepositToBodensee(address(channel)),
            address(venue),
            IVaultExplorer(address(explorer)),
            IAuMM(address(aumm)),
            IERC20(address(svzchf)),
            IERC20(address(susds)),
            IGaugeRegistry(address(gauges)),
            GENESIS_BLOCK
        );
    }

    function test_extSpotRate_svzchf() public view {
        // 750_000·0.4 / (1_000_000·0.3) = 1.0 — svZCHF-per-AuMM spot at the fixture weights
        assertEq(registry.extSpotRate(address(svzchf)), 1e18);
    }

    function test_extSpotRate_susds() public view {
        // 600_000·0.4 / (1_000_000·0.3) = 0.8 — sUSDS-per-AuMM spot at the fixture weights
        assertEq(registry.extSpotRate(address(susds)), 8e17);
    }

    function test_updateRailEMA_seed_svzchf() public {
        assertEq(registry.updateRailEMA(address(svzchf)), 1e18);
        (uint256 ema, uint256 lastSampleBlock, uint256 seedBlock) = registry.railEMA(address(svzchf));
        assertEq(ema, 1e18);
        assertEq(lastSampleBlock, GENESIS_BLOCK);
        assertEq(seedBlock, GENESIS_BLOCK);
    }

    function test_updateRailEMA_smooth_svzchf() public {
        assertEq(registry.updateRailEMA(address(svzchf)), 1e18);

        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = IERC20(address(aumm));
        tokens[1] = IERC20(address(svzchf));
        tokens[2] = IERC20(address(susds));

        uint256[] memory balances2 = new uint256[](3);
        balances2[0] = BAL_AUMM;
        balances2[1] = 1_500_000e18;
        balances2[2] = BAL_SUSDS;

        uint256[] memory rates = new uint256[](3);
        rates[0] = 1e18;
        rates[1] = 1e18;
        rates[2] = 1e18;

        uint256[] memory scaling = new uint256[](3);
        scaling[0] = 1;
        scaling[1] = 1;
        scaling[2] = 1;

        explorer.setPoolData(address(venue), tokens, balances2, rates, scaling);

        vm.roll(GENESIS_BLOCK + 7_200);
        uint256 newSpot = 2e18;
        uint256 seededEMA = 1e18;
        uint256 expectedEMA = (2 * newSpot + 59 * seededEMA) / 61;
        assertEq(registry.updateRailEMA(address(svzchf)), expectedEMA);
    }

    function test_updateRailEMA_revert_tooEarly() public {
        registry.updateRailEMA(address(svzchf));
        vm.expectRevert(abi.encodeWithSelector(IncendiaryRegistry.TooEarly.selector, GENESIS_BLOCK, GENESIS_BLOCK + 7_200));
        registry.updateRailEMA(address(svzchf));
    }

    function test_updateRailEMA_revert_unknownRail() public {
        address fake = makeAddr("fake");
        vm.expectRevert(abi.encodeWithSelector(IncendiaryRegistry.UnknownRail.selector, fake));
        registry.updateRailEMA(fake);
    }

    function test_updateRailEMA_event() public {
        vm.expectEmit(true, false, false, true);
        emit IncendiaryRegistry.RailEMAUpdated(address(svzchf), 1e18, 1e18, GENESIS_BLOCK);
        registry.updateRailEMA(address(svzchf));
    }

    function test_extMaturePrice_revert_unseeded() public {
        vm.expectRevert(abi.encodeWithSelector(IncendiaryRegistry.EMANotMature.selector, address(svzchf), 0, 432_000));
        registry.extMaturePrice(address(svzchf));
    }

    function test_extMaturePrice_revert_immature() public {
        registry.updateRailEMA(address(svzchf));
        vm.roll(GENESIS_BLOCK + 7_200);
        vm.expectRevert(abi.encodeWithSelector(IncendiaryRegistry.EMANotMature.selector, address(svzchf), 7_200, 432_000));
        registry.extMaturePrice(address(svzchf));
    }

    function test_extMaturePrice_mature() public {
        registry.updateRailEMA(address(svzchf));
        vm.roll(GENESIS_BLOCK + 432_000);
        assertEq(registry.extMaturePrice(address(svzchf)), 1e18);
    }

    function test_updateRailEMA_seed_susds() public {
        assertEq(registry.updateRailEMA(address(susds)), 8e17);
        (uint256 ema,, uint256 seedBlock) = registry.railEMA(address(susds));
        assertEq(ema, 8e17);
        assertEq(seedBlock, GENESIS_BLOCK);
    }

    function _seedAndMature(address rail) internal {
        registry.updateRailEMA(rail);
        vm.roll(block.number + 432_000);
    }

    function test_extValueInAuMM_svzchf() public {
        _seedAndMature(address(svzchf));
        // ema 1e18, scaling 1, rate 1e18 — value equals amount
        assertEq(registry.extValueInAuMM(address(svzchf), 1000e18), 1000e18);
    }

    function test_extValueInAuMM_susds() public {
        _seedAndMature(address(susds));
        // ema 8e17 — 1000e18·1e18 / 8e17 = 1250e18 AuMM-wei
        assertEq(registry.extValueInAuMM(address(susds), 1000e18), 1250e18);
    }

    function test_extValueInAuMM_revert_immatureEMA() public {
        registry.updateRailEMA(address(svzchf));
        vm.roll(GENESIS_BLOCK + 7_200);
        vm.expectRevert(abi.encodeWithSelector(IncendiaryRegistry.EMANotMature.selector, address(svzchf), 7_200, 432_000));
        registry.extValueInAuMM(address(svzchf), 1000e18);
    }

    function test_buyBoost_revert_notOpen() public {
        vm.expectRevert(
            abi.encodeWithSelector(IncendiaryRegistry.BoostsNotOpen.selector, GENESIS_BLOCK, AureumTime.year1EndBlock(GENESIS_BLOCK))
        );
        registry.buyBoost(address(venue), address(svzchf), 1000e18);
    }

    function test_buyBoost_revert_unknownRail() public {
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK) + 1);
        vm.expectRevert(abi.encodeWithSelector(IncendiaryRegistry.UnknownRail.selector, address(0xBAD)));
        registry.buyBoost(address(venue), address(0xBAD), 1000e18);
    }

    function test_buyBoost_revert_notGauged() public {
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK) + 1);
        vm.expectRevert(abi.encodeWithSelector(IncendiaryRegistry.PoolNotGauged.selector, address(venue)));
        registry.buyBoost(address(venue), address(svzchf), 1000e18);
    }

    function test_buyBoost_revert_zeroAmount() public {
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK) + 1);
        gauges.setApproved(address(venue), true);
        vm.expectRevert(IncendiaryRegistry.ZeroAmount.selector);
        registry.buyBoost(address(venue), address(svzchf), 0);
    }

    function test_buyBoost_happyPath_svzchf() public {
        address buyer = makeAddr("boostBuyer");
        uint256 amount = 1000e18;

        registry.updateRailEMA(address(svzchf));
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK) + 1);
        aumm.setRate(1e18);
        gauges.setApproved(address(venue), true);
        svzchf.mint(buyer, amount);
        vm.prank(buyer);
        svzchf.approve(address(registry), amount);

        uint256 expectedEntitlement = (amount * (10_000 - 500)) / 10_000;

        vm.expectEmit(true, true, true, true, address(registry));
        emit IncendiaryRegistry.BoostPurchased(buyer, address(venue), address(svzchf), amount, expectedEntitlement);
        vm.prank(buyer);
        uint256 entitlement = registry.buyBoost(address(venue), address(svzchf), amount);

        assertEq(entitlement, expectedEntitlement);
        assertEq(address(channel.lastPayToken()), address(svzchf));
        assertEq(channel.lastAmount(), amount);
        assertEq(svzchf.balanceOf(buyer), 0);
        assertEq(svzchf.balanceOf(address(channel)), amount);
    }

    function test_extEpochEmissionIntegral_flat() public {
        uint256 rate = 1e18;
        aumm.setRate(rate);
        // epoch 5 is wholly inside era 0 — single flat-rate slice over BLOCKS_PER_EPOCH
        assertEq(registry.extEpochEmissionIntegral(5), rate * 100_800);
    }

    function test_extEpochCap_flat() public {
        uint256 rate = 1e18;
        aumm.setRate(rate);
        uint256 integral = rate * 100_800;
        uint256 expectedCap = (integral * 1_500) / 10_000;
        assertEq(registry.extEpochCap(5), expectedCap);
    }

    function test_extEpochCap_zeroWhenRateZero() public {
        // default MockAuMMRate rate is zero — zero cap (would hang _placeBoost without L8.2b setRate)
        assertEq(registry.extEpochCap(5), 0);
    }

    function test_extPlaceBoost_singleEpoch() public {
        aumm.setRate(1e18);
        registry.extPlaceBoost(address(venue), 1_000e18);
        assertEq(registry.epochSkimAllocated(1), 1_000e18);
        assertEq(registry.epochPoolSkim(1, address(venue)), 1_000e18);
        assertEq(registry.epochSkimAllocated(2), 0);
    }

    function test_extPlaceBoost_spillsAcrossEpochs() public {
        uint256 rate = 1e18;
        aumm.setRate(rate);
        uint256 cap = (rate * 100_800 * 1_500) / 10_000;
        uint256 entitlement = 2 * cap + 1_000e18;
        registry.extPlaceBoost(address(venue), entitlement);
        assertEq(registry.epochSkimAllocated(1), cap);
        assertEq(registry.epochSkimAllocated(2), cap);
        assertEq(registry.epochSkimAllocated(3), 1_000e18);
        assertEq(registry.epochPoolSkim(3, address(venue)), 1_000e18);
        assertEq(registry.epochSkimAllocated(4), 0);
    }

    function test_extPlaceBoost_stacking() public {
        aumm.setRate(1e18);
        registry.extPlaceBoost(address(venue), 1_000e18);
        registry.extPlaceBoost(address(venue), 2_000e18);
        // per-(epoch,pool) bucket is additive — L-D9 stacking
        assertEq(registry.epochSkimAllocated(1), 3_000e18);
        assertEq(registry.epochPoolSkim(1, address(venue)), 3_000e18);
    }

    function test_extPlaceBoost_capSharedAcrossPools() public {
        uint256 rate = 1e18;
        aumm.setRate(rate);
        uint256 cap = (rate * 100_800 * 1_500) / 10_000;
        address poolB = makeAddr("poolB");
        registry.extPlaceBoost(address(venue), cap);
        registry.extPlaceBoost(poolB, 1_000e18);
        assertEq(registry.epochSkimAllocated(1), cap);
        assertEq(registry.epochPoolSkim(1, address(venue)), cap);
        assertEq(registry.epochPoolSkim(1, poolB), 0);
        assertEq(registry.epochSkimAllocated(2), 1_000e18);
        assertEq(registry.epochPoolSkim(2, poolB), 1_000e18);
    }

    function test_extEpochOverlapBlocks_fullEpoch() public {
        uint256 eStart = AureumTime.epochStartBlock(GENESIS_BLOCK, 1);
        uint256 eEnd = AureumTime.epochEndBlock(GENESIS_BLOCK, 1);
        // query spans the entire epoch — overlap is BLOCKS_PER_EPOCH
        assertEq(registry.extEpochOverlapBlocks(1, eStart, eEnd), 100_800);
    }

    function test_extEpochOverlapBlocks_partial() public {
        uint256 eStart = AureumTime.epochStartBlock(GENESIS_BLOCK, 1);
        // inclusive [eStart, eStart + 49_999] is 50_000 blocks inside epoch 1
        assertEq(registry.extEpochOverlapBlocks(1, eStart, eStart + 49_999), 50_000);
    }

    function test_extEpochOverlapBlocks_disjoint() public {
        uint256 e2Start = AureumTime.epochStartBlock(GENESIS_BLOCK, 2);
        // query window sits entirely in epoch 2 — no overlap with epoch 1
        assertEq(registry.extEpochOverlapBlocks(1, e2Start, e2Start + 100), 0);
    }

    function test_integratedSkim_fullEpoch() public {
        aumm.setRate(1e18);
        registry.extPlaceBoost(address(venue), 100_800);
        uint256 eStart = AureumTime.epochStartBlock(GENESIS_BLOCK, 1);
        uint256 eEnd = AureumTime.epochEndBlock(GENESIS_BLOCK, 1);
        // per-block rate 1 × 100_800 overlap — whole bucket, no flooring dust
        assertEq(registry.integratedSkim(eStart, eEnd), 100_800);
    }

    function test_integratedSkim_partialWindow() public {
        aumm.setRate(1e18);
        registry.extPlaceBoost(address(venue), 100_800);
        uint256 eStart = AureumTime.epochStartBlock(GENESIS_BLOCK, 1);
        // per-block rate 1 × 50_000 overlap
        assertEq(registry.integratedSkim(eStart, eStart + 49_999), 50_000);
    }

    function test_integratedSkim_emptyInterval() public {
        // from > to returns 0 before any bucket read
        assertEq(registry.integratedSkim(2_000_000, 1_000_000), 0);
    }

    function test_boostIntegral_perPoolAndUnknown() public {
        aumm.setRate(1e18);
        registry.extPlaceBoost(address(venue), 100_800);
        uint256 eStart = AureumTime.epochStartBlock(GENESIS_BLOCK, 1);
        uint256 eEnd = AureumTime.epochEndBlock(GENESIS_BLOCK, 1);
        assertEq(registry.boostIntegral(address(venue), eStart, eEnd), 100_800);
        // unknown pool — zero bucket ⇒ 0
        assertEq(registry.boostIntegral(makeAddr("unknownPool"), eStart, eEnd), 0);
    }

    function test_conservation_exactWhenDivisible() public {
        aumm.setRate(1e18);
        address poolB = makeAddr("poolB");
        registry.extPlaceBoost(address(venue), 100_800);
        registry.extPlaceBoost(poolB, 201_600);
        uint256 eStart = AureumTime.epochStartBlock(GENESIS_BLOCK, 1);
        uint256 eEnd = AureumTime.epochEndBlock(GENESIS_BLOCK, 1);
        uint256 global = registry.integratedSkim(eStart, eEnd);
        uint256 a = registry.boostIntegral(address(venue), eStart, eEnd);
        uint256 b = registry.boostIntegral(poolB, eStart, eEnd);
        assertLe(a + b, global);
        // both buckets divide BLOCKS_PER_EPOCH cleanly — exact tiling
        assertEq(a + b, global);
    }

    function test_conservation_strictWithFlooringDust() public {
        aumm.setRate(1e18);
        address poolB = makeAddr("poolB");
        registry.extPlaceBoost(address(venue), 151_200);
        registry.extPlaceBoost(poolB, 151_200);
        uint256 eStart = AureumTime.epochStartBlock(GENESIS_BLOCK, 1);
        uint256 eEnd = AureumTime.epochEndBlock(GENESIS_BLOCK, 1);
        uint256 global = registry.integratedSkim(eStart, eEnd);
        uint256 a = registry.boostIntegral(address(venue), eStart, eEnd);
        uint256 b = registry.boostIntegral(poolB, eStart, eEnd);
        // per-pool flooring — L-D23 invariant is ≤, not ==
        assertLt(a + b, global);
    }
}
