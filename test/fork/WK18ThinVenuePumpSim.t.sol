// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { StageNIntegrationFixture } from "./StageNIntegration.t.sol";
import { IEMASampler } from "../../src/ccb/IEMASampler.sol";
import { VotingWeight } from "../../src/governance/VotingWeight.sol";
import {
    TokenConfig,
    TokenType,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

/**
 * @title WK18ThinVenuePumpSimFixture
 * @notice WK.18 thin-venue populated-roster fork sim — StageN roster base + VotingWeight + two USDC/svZChf constellation venues (PB-D16).
 * @dev Venue pricing layer: both venues registered via `addConstellationPool` so `_directRatio(USDC)` is their mean. EMA maturation and the three assertion faces land in later sub-steps.
 */
abstract contract WK18ThinVenuePumpSimFixture is StageNIntegrationFixture {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    bytes32 internal constant VENUE_A_SALT = bytes32(uint256(0xA11CE01));
    bytes32 internal constant VENUE_B_SALT = bytes32(uint256(0xA11CE02));

    VotingWeight internal votingWeight;
    address internal venueA;
    address internal venueB;

    function setUp() public virtual override {
        super.setUp();
        votingWeight = new VotingWeight(IEMASampler(address(emaSampler)), gaugeRegistry, emissionDistributor, realRegistry, aumm.GENESIS_BLOCK());
        tvlOracle.setTokenUnderlying(USDC, USDC);
        tvlOracle.setTokenUnderlying(address(svZchf), address(svZchf));
        venueA = _buildUsdcSvzchfVenue(VENUE_A_SALT);
        venueB = _buildUsdcSvzchfVenue(VENUE_B_SALT);
        tvlOracle.addConstellationPool(venueA);
        tvlOracle.addConstellationPool(venueB);
    }

    /// @dev Hookless USDC/svZChf weighted venue — StageHIntegration.t.sol L465-506 shape, distinct salt per call.
    function _buildUsdcSvzchfVenue(bytes32 salt) internal returns (address venue) {
        address[2] memory addrs;
        addrs[0] = USDC;
        addrs[1] = address(svZchf);
        if (addrs[0] > addrs[1]) (addrs[0], addrs[1]) = (addrs[1], addrs[0]);

        TokenConfig[] memory configs = new TokenConfig[](2);
        configs[0] = TokenConfig({
            token: IERC20(addrs[0]),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });
        configs[1] = TokenConfig({
            token: IERC20(addrs[1]),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });

        uint256[] memory weights = new uint256[](2);
        weights[0] = 5e17;
        weights[1] = 5e17;

        venue = wpf.create(
            "wk18-usdc-svzchf-venue",
            "WK18V",
            configs,
            weights,
            PoolRoleAccounts({pauseManager: GOVERNANCE_MULTISIG, swapFeeManager: address(0), poolCreator: address(0)}),
            0.003e18,
            address(0),
            true,
            false,
            salt
        );

        IERC20[] memory vTokens = vault.getPoolTokens(venue);
        uint256[] memory amts = new uint256[](2);
        for (uint256 i = 0; i < vTokens.length; i++) {
            amts[i] = address(vTokens[i]) == USDC ? 1_000e6 : 1_000e18;
        }
        _initializePool(venue, vTokens, amts);
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

contract WK18VenueLayerTest is WK18ThinVenuePumpSimFixture {
    function test_venueLayer_pricesUsdcAndRespondsToPump() public {
        assertGt(tvlOracle.quoteSvZCHF(USDC, 1e18), 0, "USDC priced via the venue mean");
        uint256 pre = tvlOracle.quoteSvZCHF(USDC, 1e18);
        _depositOneSided(venueA, makeAddr("wk18Pumper"), 5_000);
        uint256 post = tvlOracle.quoteSvZCHF(USDC, 1e18);
        assertTrue(post != pre, "venue pump moves the USDC constellation price");
    }
}
