// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { StageNIntegrationFixture } from "./StageNIntegration.t.sol";
import { IEMASampler } from "../../src/ccb/IEMASampler.sol";
import { VotingWeight } from "../../src/governance/VotingWeight.sol";
import { AureumTime } from "../../src/lib/AureumTime.sol";
import {
    TokenConfig,
    TokenType,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

/**
 * @title WK18ThinVenuePumpSimFixture
 * @notice WK.18 thin-venue populated-roster fork sim — StageN roster base + VotingWeight + two USDC/svZChf constellation venues + real matured-EMA scored pilot (PB-D16).
 * @dev Venue pricing layer: both venues registered via `addConstellationPool` so `_directRatio(USDC)` is their mean. Scored pilot maps its first non-stable token to USDC, seeds gauge, takes a recorder position, and matures a real EMA (seed / roll 60d / refresh) — no `_mockPoolEma`. The three assertion faces land in later sub-steps.
 */
abstract contract WK18ThinVenuePumpSimFixture is StageNIntegrationFixture {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    bytes32 internal constant VENUE_A_SALT = bytes32(uint256(0xA11CE01));
    bytes32 internal constant VENUE_B_SALT = bytes32(uint256(0xA11CE02));

    VotingWeight internal votingWeight;
    address internal venueA;
    address internal venueB;
    address internal scoredPool;
    address internal scoredLp;
    address internal scoredMappedToken;

    function setUp() public virtual override {
        super.setUp();
        votingWeight = new VotingWeight(IEMASampler(address(emaSampler)), gaugeRegistry, emissionDistributor, realRegistry, aumm.GENESIS_BLOCK());
        tvlOracle.setTokenUnderlying(USDC, USDC);
        tvlOracle.setTokenUnderlying(address(svZchf), address(svZchf));
        venueA = _buildUsdcSvzchfVenue(VENUE_A_SALT);
        venueB = _buildUsdcSvzchfVenue(VENUE_B_SALT);
        tvlOracle.addConstellationPool(venueA);
        tvlOracle.addConstellationPool(venueB);

        scoredPool = pilotPools[0];
        scoredLp = makeAddr("wk18ScoredLp");
        IERC20[] memory sTokens = vault.getPoolTokens(scoredPool);
        for (uint256 i = 0; i < sTokens.length; i++) {
            if (address(sTokens[i]) != address(svZchf) && address(sTokens[i]) != USDC) {
                tvlOracle.setTokenUnderlying(address(sTokens[i]), USDC);
                scoredMappedToken = address(sTokens[i]);
                break;
            }
        }
        require(scoredMappedToken != address(0), "wk18: no mappable scored token");
        gaugeRegistry.seedFoundingPool(scoredPool);
        _depositOneSided(scoredPool, scoredLp, 100);
        emaSampler.updateEMA(scoredPool);
        vm.roll(block.number + 60 * AureumTime.BLOCKS_PER_DAY + 1);
        emaSampler.updateEMA(scoredPool);
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

contract WK18ScoredPoolTest is WK18ThinVenuePumpSimFixture {
    function test_scoredPool_realMaturedEmaConfersWeight() public {
        assertGt(emaSampler.tvlEMA(scoredPool), 0, "real EMA seeded from live TVLOracle pricing");
        votingWeight.poke(scoredLp);
        assertGt(votingWeight.governanceWeight(scoredLp), 0, "real matured+fresh EMA + qualified position confers weight (no _mockPoolEma)");
    }
}

/**
 * @notice PB-D16 face (1) — atomic venue pump moves spot `tvl(scoredPool)` but leaves `governanceWeight` byte-identical.
 * @dev Fork-grade proof that `_positionPower` reads the gated EMA, not spot. No `updateEMA` in this test.
 */
contract WK18Face1PositiveControlTest is WK18ThinVenuePumpSimFixture {
    function test_face1_atomicVenuePump_governanceWeightUnmovedWhileSpotMoves() public {
        votingWeight.poke(scoredLp);
        uint256 weightBefore = votingWeight.governanceWeight(scoredLp);
        assertGt(weightBefore, 0, "baseline weight from the real matured EMA");
        uint256 spotBefore = tvlOracle.tvl(scoredPool);
        _depositOneSided(venueA, makeAddr("wk18Face1Pumper"), 5_000);
        uint256 spotAfter = tvlOracle.tvl(scoredPool);
        assertTrue(spotAfter != spotBefore, "atomic venue pump moves spot tvl(scoredPool)");
        votingWeight.poke(scoredLp);
        uint256 weightAfter = votingWeight.governanceWeight(scoredLp);
        assertEq(weightAfter, weightBefore, "governanceWeight unmoved: _positionPower reads the gated EMA, not spot");
        emit log_named_uint("spot tvl before venue pump", spotBefore);
        emit log_named_uint("spot tvl after venue pump", spotAfter);
        emit log_named_uint("governanceWeight before", weightBefore);
        emit log_named_uint("governanceWeight after", weightAfter);
    }
}

/**
 * @notice PB-D16 face (2) — a single-venue pump dilutes to ~1/N of the cross-venue mean move.
 * @dev Populated roster strictly weakens the pump vector. Also carries the WH-P6 `addConstellationPool` double-append attestation — the venue roster is governance-controlled and mean-damped, not a code change. Spot-pricing only; no `updateEMA`.
 */
contract WK18Face2CrossVenueDilutionTest is WK18ThinVenuePumpSimFixture {
    function test_face2_singleVenuePumpDilutesToOneOverN() public {
        uint256 baseline = tvlOracle.quoteSvZCHF(USDC, 1e18);
        uint256 snap = vm.snapshotState();
        _depositOneSided(venueA, makeAddr("wk18Face2PumpA"), 5_000);
        uint256 qA = tvlOracle.quoteSvZCHF(USDC, 1e18);
        uint256 singleDelta = qA > baseline ? qA - baseline : baseline - qA;
        vm.revertToState(snap);
        _depositOneSided(venueA, makeAddr("wk18Face2PumpA"), 5_000);
        _depositOneSided(venueB, makeAddr("wk18Face2PumpB"), 5_000);
        uint256 qAB = tvlOracle.quoteSvZCHF(USDC, 1e18);
        uint256 bothDelta = qAB > baseline ? qAB - baseline : baseline - qAB;
        assertGt(singleDelta, 0, "single-venue pump moves the mean");
        assertGt(bothDelta, singleDelta, "both-venue pump moves the mean strictly more");
        assertApproxEqRel(singleDelta * 2, bothDelta, 0.02e18, "single-venue pump dilutes to ~1/N (N=2) of the cross-venue mean move");
        emit log_named_uint("baseline quoteSvZCHF(USDC,1e18)", baseline);
        emit log_named_uint("single-venue pump delta", singleDelta);
        emit log_named_uint("both-venue pump delta", bothDelta);
    }
}

/**
 * @notice PB-D16 face (3) — sustained skew capital across daily EMA samples buys a quartic-root-compressed, EMA-lagged, 1/N-mean-diluted weight gain; bounded fee-negative (the PB2.4d sandwich-sim shape).
 * @dev Final face: a large venue skew held across ~21 daily `updateEMA` samples is fee-negative vs the deliverable weight gain.
 */
contract WK18Face3SustainedPumpEconomicsTest is WK18ThinVenuePumpSimFixture {
    /// @dev Single-sided add of `fractionBps`/10_000 of the venue's current svZChf balance — raises the USDC price (`_venueRatio` is svZChf-per-USDC).
    function _pumpVenueSvzchf(address venue, uint256 fractionBps) internal {
        IERC20[] memory tokens = vault.getPoolTokens(venue);
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(venue);
        uint256[] memory amountsIn = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (address(tokens[i]) == address(svZchf)) {
                amountsIn[i] = balancesRaw[i] * fractionBps / 10_000;
                deal(address(svZchf), address(this), amountsIn[i]);
            }
        }
        vault.unlock(abi.encodeCall(this._depositCallback, (venue, amountsIn)));
    }

    function test_face3_sustainedPumpEconomicsAreFeeNegative() public {
        /// @dev Pre-roll past the 180-day AureumTime.ON_RAMP_PERIOD_BLOCKS cap (scoredLp opened ~60 days ago in setUp) so timeFactor is already pinned at its maximum before the sustain loop below — isolating the measured weight delta to the EMA/poolPower term, not on-ramp aging.
        vm.roll(block.number + 130 * AureumTime.BLOCKS_PER_DAY);
        emaSampler.updateEMA(scoredPool);
        votingWeight.poke(scoredLp);
        uint256 weightBaseline = votingWeight.governanceWeight(scoredLp);
        assertGt(weightBaseline, 0, "baseline weight from the real matured EMA");
        uint256 spotBaseline = tvlOracle.tvl(scoredPool);
        _pumpVenueSvzchf(venueA, 20_000);
        uint256 spotPumped = tvlOracle.tvl(scoredPool);
        assertGt(spotPumped, spotBaseline, "sustained pump inflates spot tvl(scoredPool)");
        votingWeight.poke(scoredLp);
        assertEq(votingWeight.governanceWeight(scoredLp), weightBaseline, "pre-sustain: the pump alone leaves weight unmoved (EMA not resampled)");
        uint256 K = 21;
        uint256 b = block.number;
        for (uint256 d = 0; d < K; d++) {
            b += AureumTime.BLOCKS_PER_DAY;
            vm.roll(b);
            emaSampler.updateEMA(scoredPool);
        }
        votingWeight.poke(scoredLp);
        uint256 weightAfter = votingWeight.governanceWeight(scoredLp);
        assertGt(weightAfter, weightBaseline, "sustaining the pump eventually moves weight (partial EMA absorption)");
        uint256 spotInflationBps = (spotPumped - spotBaseline) * 10_000 / spotBaseline;
        uint256 weightGainBps = (weightAfter - weightBaseline) * 10_000 / weightBaseline;
        assertLt(weightGainBps * 2, spotInflationBps, "weight gain is far under half the spot inflation fractionally (EMA lag + quartic root + 1/N dilution); sustained-pump attack fee-negative");
        emit log_named_uint("skew svZChf add fraction (bps)", 20_000);
        emit log_named_uint("days sustained", K);
        emit log_named_uint("spot inflation bps", spotInflationBps);
        emit log_named_uint("weight gain bps after sustain", weightGainBps);
        emit log_named_uint("weight baseline", weightBaseline);
        emit log_named_uint("weight after sustain", weightAfter);
    }
}
