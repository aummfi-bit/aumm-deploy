// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IncendiaryRegistry} from "src/incendiary/IncendiaryRegistry.sol";
import {IncendiaryRegistryHarness} from "test/unit/harness/IncendiaryRegistryHarness.sol";
import {MockBodenseeExplorer, MockWeightedVenue, MockBodenseeChannel, MockAuMMRate} from "test/fork/mocks/StageLMocks.sol";
import {MockGaugeRegistry} from "test/fork/mocks/CCBMocks.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {SwapAndDepositToBodensee} from "src/gauge/SwapAndDepositToBodensee.sol";
import {IVaultExplorer} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import {IAuMM} from "src/token/IAuMM.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";

/// @notice F-07 fix regression (WL pass) — `_maturePrice` now also requires the der-Bodensee price-EMA rail to be fresh — a mature seed whose `lastSampleBlock` is older than `EMA_STALENESS_BLOCKS` (one epoch / 14 days) reverts `EMAStale`; the 60-day maturity gate guards seed AGE, this gate guards FRESHNESS, mirroring the F-05 VotingWeight fix.
contract F07_EmaStalePricingTest is Test {
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

    /// @notice Core F-07 fix: a mature seed last sampled at seed time (EMA_MATURITY_BLOCKS ago, deeply stale) reverts EMAStale.
    function test_F07_deeplyStaleMatureEma_revertsEMAStale() public {
        registry.updateRailEMA(address(svzchf));
        vm.roll(GENESIS_BLOCK + registry.EMA_MATURITY_BLOCKS());
        vm.expectRevert(
            abi.encodeWithSelector(
                IncendiaryRegistry.EMAStale.selector,
                address(svzchf),
                registry.EMA_MATURITY_BLOCKS(),
                registry.EMA_STALENESS_BLOCKS()
            )
        );
        registry.extMaturePrice(address(svzchf));
    }

    /// @notice A mature seed re-sampled at the matured block prices — the freshness gate blocks only stale EMAs.
    function test_F07_freshMatureEma_pricesPurchase() public {
        registry.updateRailEMA(address(svzchf));
        vm.roll(GENESIS_BLOCK + registry.EMA_MATURITY_BLOCKS());
        registry.updateRailEMA(address(svzchf));
        assertEq(registry.extMaturePrice(address(svzchf)), 1e18);
    }

    /// @notice Boundary (strict >): staleness exactly equal to EMA_STALENESS_BLOCKS still prices.
    function test_F07_stalenessBoundaryFresh_atExactEpoch() public {
        registry.updateRailEMA(address(svzchf));
        vm.roll(GENESIS_BLOCK + registry.EMA_MATURITY_BLOCKS() - registry.EMA_STALENESS_BLOCKS());
        registry.updateRailEMA(address(svzchf));
        vm.roll(GENESIS_BLOCK + registry.EMA_MATURITY_BLOCKS());
        assertEq(registry.extMaturePrice(address(svzchf)), 1e18);
    }

    /// @notice Boundary (strict >): one block past EMA_STALENESS_BLOCKS is stale and reverts EMAStale.
    function test_F07_stalenessBoundaryStale_oneBlockPast() public {
        registry.updateRailEMA(address(svzchf));
        vm.roll(GENESIS_BLOCK + registry.EMA_MATURITY_BLOCKS() - registry.EMA_STALENESS_BLOCKS());
        registry.updateRailEMA(address(svzchf));
        vm.roll(GENESIS_BLOCK + registry.EMA_MATURITY_BLOCKS() + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IncendiaryRegistry.EMAStale.selector,
                address(svzchf),
                registry.EMA_STALENESS_BLOCKS() + 1,
                registry.EMA_STALENESS_BLOCKS()
            )
        );
        registry.extMaturePrice(address(svzchf));
    }
}
