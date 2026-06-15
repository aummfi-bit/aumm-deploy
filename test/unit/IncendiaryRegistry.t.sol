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
}
