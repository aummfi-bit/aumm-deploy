// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaultExplorer} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TVLOracle} from "src/emission/TVLOracle.sol";
import {EMASampler} from "src/ccb/EMASampler.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {VotingWeight} from "src/governance/VotingWeight.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {MockVaultExplorer, MockBasePoolFactory, MockWeightedPool} from "test/fork/mocks/StageHMocks.sol";
import {MockGaugeRegistry, MockMiliariumRegistry, MockRecorder} from "test/unit/VotingWeight.t.sol";

/// @notice In production the throw originates in a third-party getRate() reached inside
///         the Vault's getPoolData; this double raises it from the sibling unguarded read
///         in TVLOracle.sol:328-330, which is the root cause the D.6 row names.
contract P1_D6_RevertingVenue {
    error RateProviderReverted();

    function getNormalizedWeights() external pure returns (uint256[] memory) {
        revert RateProviderReverted();
    }
}

/// @title P1 D.6 — one reverting venue bricks tvl() for every unrelated pool
/// @notice Reproduction PoC for seam-1 root cause D.6 (High). An unguarded
///         getNormalizedWeights read inside TVLOracle._venueRatio reverts through the
///         Leg 2 Miliarium roster walk, freezing the EMA stamp because the oracle read
///         at EMASampler.sol:136 precedes the write at :151, and zeroing the electorate
///         once the freshness window lapses.
contract P1_D6_RevertingVenueBricksTvlTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant START_BLOCK = 2_000_000;

    MockERC20 internal healthyPoolToken;
    MockERC20 internal pricedToken;
    MockERC20 internal svZchfToken;
    address internal pricedUnderlying;
    address internal bodensee;
    MockVaultExplorer internal explorer;
    MockBasePoolFactory internal factory;
    MockBasePoolFactory internal factoryAureum;
    MockWeightedPool internal goodVenue;
    address internal sickVenue;
    TVLOracle internal tvlOracle;
    EMASampler internal sampler;
    MockGaugeRegistry internal gaugeReg;
    MockMiliariumRegistry internal registry;
    MockRecorder internal recorder;
    VotingWeight internal vw;

    address internal holder;

    function setUp() public {
        vm.roll(START_BLOCK);

        healthyPoolToken = new MockERC20("Healthy BPT", "HBPT", 18);
        pricedToken = new MockERC20("Priced", "PRC", 18);
        svZchfToken = new MockERC20("svZCHF", "svZCHF", 18);
        pricedUnderlying = makeAddr("pricedUnderlying");
        bodensee = makeAddr("bodensee");
        explorer = new MockVaultExplorer();
        factory = new MockBasePoolFactory();
        factoryAureum = new MockBasePoolFactory();
        goodVenue = new MockWeightedPool();
        sickVenue = address(new P1_D6_RevertingVenue());
        gaugeReg = new MockGaugeRegistry();
        registry = new MockMiliariumRegistry();
        recorder = new MockRecorder();
        holder = makeAddr("p1_d6_holder");

        tvlOracle = new TVLOracle(
            IVaultExplorer(address(explorer)),
            bodensee,
            address(svZchfToken),
            address(factory),
            address(factoryAureum),
            address(this),
            new address[](0),
            new address[](0)
        );

        tvlOracle.setTokenUnderlying(address(pricedToken), pricedUnderlying);
        tvlOracle.setTokenUnderlying(address(svZchfToken), address(svZchfToken));
        tvlOracle.setMiliariumRegistry(IMiliariumRegistry(address(registry)));

        IERC20[] memory venueTokens = new IERC20[](2);
        venueTokens[0] = IERC20(address(pricedToken));
        venueTokens[1] = IERC20(address(svZchfToken));
        uint256[] memory venueBalances = new uint256[](2);
        venueBalances[0] = 1000e18;
        venueBalances[1] = 4000e18;
        explorer.setPool(address(goodVenue), venueTokens, venueBalances);
        explorer.setPool(sickVenue, venueTokens, venueBalances);

        IERC20[] memory healthyTokens = new IERC20[](1);
        healthyTokens[0] = IERC20(address(pricedToken));
        uint256[] memory healthyBalances = new uint256[](1);
        healthyBalances[0] = 100e18;
        explorer.setPool(address(healthyPoolToken), healthyTokens, healthyBalances);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;
        goodVenue.setWeights(weights);

        factoryAureum.setFromFactory(address(goodVenue), true);
        factoryAureum.setFromFactory(sickVenue, true);

        sampler = new EMASampler(tvlOracle);

        address healthy = address(healthyPoolToken);
        gaugeReg.setApproved(healthy, true);
        registry.setMiliarium(healthy, true);

        recorder.setEffectiveQualBlock(healthy, holder, 1);
        recorder.setUserLP(healthy, holder, 100e18);
        recorder.setPoolTotalLP(healthy, 100e18);
        healthyPoolToken.mint(holder, 100e18);

        vw = new VotingWeight(
            IEMASampler(address(sampler)),
            gaugeReg,
            recorder,
            registry,
            GENESIS_BLOCK
        );
    }

    /// @dev Defect case — one sick venue in the Leg 2 roster walk bricks tvl() for an unrelated pool.
    function test_P1_D6_oneRevertingVenueBricksTvlForEveryUnrelatedPool() public {
        address healthy = address(healthyPoolToken);
        address good = address(goodVenue);

        address[] memory roster = new address[](2);
        roster[0] = healthy;
        roster[1] = good;
        registry.setPoolList(roster);
        registry.setMiliarium(good, true);

        assertEq(tvlOracle.tvl(healthy), 400e18, "positive control before sick venue enters roster");

        address[] memory broken = new address[](3);
        broken[0] = healthy;
        broken[1] = good;
        broken[2] = sickVenue;
        registry.setPoolList(broken);
        registry.setMiliarium(sickVenue, true);

        vm.expectRevert(P1_D6_RevertingVenue.RateProviderReverted.selector);
        tvlOracle.tvl(healthy);
    }

    /// @dev Stamp freeze case — a reverting venue blocks refresh and the electorate goes to zero.
    function test_P1_D6_frozenStampZeroesTheElectorateAfterTheFreshnessWindow() public {
        address healthy = address(healthyPoolToken);
        address good = address(goodVenue);

        address[] memory roster = new address[](2);
        roster[0] = healthy;
        roster[1] = good;
        registry.setPoolList(roster);
        registry.setMiliarium(good, true);

        sampler.updateEMA(healthy);

        uint256 blockCounter = sampler.emaSeedBlock(healthy);
        for (uint256 i = 0; i < 61; ++i) {
            blockCounter += AureumTime.BLOCKS_PER_DAY;
            vm.roll(blockCounter);
            sampler.updateEMA(healthy);
        }

        vw.poke(holder);
        assertGt(vw.governanceWeight(holder), 0, "premise: healthy pool conferred governance power");

        address[] memory broken = new address[](3);
        broken[0] = healthy;
        broken[1] = good;
        broken[2] = sickVenue;
        registry.setPoolList(broken);
        registry.setMiliarium(sickVenue, true);

        uint256 frozenStamp = sampler.lastEMAUpdateBlock(healthy);
        blockCounter += AureumTime.BLOCKS_PER_DAY;
        vm.roll(blockCounter);
        vm.expectRevert(P1_D6_RevertingVenue.RateProviderReverted.selector);
        sampler.updateEMA(healthy);
        assertEq(
            sampler.lastEMAUpdateBlock(healthy),
            frozenStamp,
            "stamp unchanged because oracle read precedes the write"
        );

        vm.roll(frozenStamp + AureumTime.BLOCKS_PER_EPOCH + 1);
        vw.poke(holder);
        assertEq(vw.governanceWeight(holder), 0, "freshness lapsed while the venue still reverts");
    }
}
