// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {GaugeRegistry} from "src/gauge/GaugeRegistry.sol";
import {GaugeEligibility} from "src/gauge/GaugeEligibility.sol";
import {EmissionDistributorHarness} from "test/unit/harness/EmissionDistributorHarness.sol";

import {IAuMM} from "src/token/IAuMM.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";

import {MockAuMM, MockBpt, MockEMASampler, MockCCBMultiplier, MockMiliariumRegistry} from "test/unit/EmissionDistributor.t.sol";
import {MockEfficiencyOracle} from "test/fork/mocks/StageGMocks.sol";
import {MockRegisteredVault} from "../mocks/MockRegisteredVault.sol";

import {IncendiaryRegistry} from "src/incendiary/IncendiaryRegistry.sol";
import {MockBodenseeExplorer, MockWeightedVenue, MockBodenseeChannel, MockAuMMRate} from "test/fork/mocks/StageLMocks.sol";
import {MockGaugeRegistry} from "test/fork/mocks/CCBMocks.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {SwapAndDepositToBodensee} from "src/gauge/SwapAndDepositToBodensee.sol";
import {IVaultExplorer} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Honest boost counterparty: returns rate * inclusive window width, so a longer window
///         bills proportionally more. The over-mint under E.8 arises against this honest shape,
///         not a malicious constant return.
contract LinearBoostRegistry {
    uint256 public immutable ratePerBlock;

    constructor(uint256 ratePerBlock_) {
        ratePerBlock = ratePerBlock_;
    }

    /// @notice Returns `ratePerBlock * (to - from + 1)` when `to >= from`, else zero.
    function boostIntegral(address, uint256 from, uint256 to) external view returns (uint256) {
        if (to < from) return 0;
        return ratePerBlock * (to - from + 1);
    }

    /// @notice `EmissionDistributor._phaseAwareBody` calls this un-caught on the accrual path
    ///         whenever a registry is bound in the continuous phase, so an honest counterparty
    ///         must answer it. Returning the same linear shape as boostIntegral satisfies the
    ///         L-D23 conservation direction boostIntegral <= integratedSkim with equality.
    function integratedSkim(uint256 from, uint256 to) external view returns (uint256) {
        if (to < from) return 0;
        return ratePerBlock * (to - from + 1);
    }
}

/// @notice Reproduction PoC for seam-1 root cause E.8 (Medium). The cursor assignment at
///         `EmissionDistributor.sol` L413 sits inside the non-zero-registry guard, so unbinding
///         freezes `poolBoostCursor` while settles continue, and a later rebind bills the whole
///         unbound window as one backlog. E.8's other face — `buyBoost` holding no distributor
///         reference, so purchases continue while unbound — lives in the registry contract and is
///         reproduced separately.
contract P1_E8_UnbindingFreezesTheBoostCursorTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant SCORE_BLOCK = GENESIS_BLOCK + 2_628_000 + 1;
    uint256 internal constant SETUP_SETTLE_BLOCK = SCORE_BLOCK + 10;
    uint256 internal constant UNBOUND_MID_BLOCK = SETUP_SETTLE_BLOCK + 5_000;
    uint256 internal constant UNBOUND_END_BLOCK = SETUP_SETTLE_BLOCK + 10_000;
    uint256 internal constant BOOST_RATE = 1e15; // must stay well below the AuMM mock's 1e18-per-block emission rate, because `_phaseAwareBody` computes `rate * n - skim` and underflows if the skim exceeds the tranche
    uint256 internal constant LP_AMOUNT = 100e18;

    address internal constant GOV = address(0x9011);
    address internal constant PLACEHOLDER = address(0xDEAD);
    address internal constant AUMT = address(0xAB01);
    address internal constant LP_USER = address(0xCD01);

    MockAuMM internal aumm;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockMiliariumRegistry internal miliReg;
    MockEfficiencyOracle internal effOracle;
    GaugeEligibility internal gaugeElig;
    GaugeRegistry internal gaugeRegistry;
    EmissionDistributorHarness internal distributor;
    LinearBoostRegistry internal boostRegistry;

    address internal pool;

    function setUp() public {
        aumm = new MockAuMM();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        miliReg = new MockMiliariumRegistry();
        effOracle = new MockEfficiencyOracle();

        gaugeElig = new GaugeEligibility(
            PLACEHOLDER,
            PLACEHOLDER,
            PLACEHOLDER,
            PLACEHOLDER,
            PLACEHOLDER,
            address(this),
            address(effOracle),
            PLACEHOLDER,
            PLACEHOLDER
        );
        gaugeRegistry = new GaugeRegistry(
            GOV,
            address(gaugeElig),
            PLACEHOLDER,
            PLACEHOLDER,
            GENESIS_BLOCK
        );
        gaugeElig.setGaugeRegistry(address(gaugeRegistry));

        distributor = new EmissionDistributorHarness(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gaugeRegistry)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK,
            GOV,
            address(new MockRegisteredVault())
        );

        boostRegistry = new LinearBoostRegistry(BOOST_RATE);
        pool = address(new MockBpt());

        address[] memory pools = new address[](1);
        pools[0] = pool;
        vm.prank(GOV);
        gaugeRegistry.seedFoundingPools(pools);

        vm.roll(GENESIS_BLOCK);
    }

    function _establishLiveBoostState() internal {
        vm.prank(GOV);
        distributor.proposeIncendiaryRegistry(address(boostRegistry));
        vm.roll(block.number + 1);
        vm.prank(GOV);
        distributor.acceptIncendiaryRegistry();

        ema.setTVLEMA(pool, 100e18);
        mult.setMultiplier(pool, 1e18);
        vm.roll(SCORE_BLOCK);
        distributor.recordScore(pool);

        vm.prank(GOV);
        distributor.setAuMTContractForPool(pool, AUMT);
        MockBpt(pool).mint(LP_USER, LP_AMOUNT);
        vm.prank(AUMT);
        distributor.recordDeposit(pool, LP_USER, LP_AMOUNT);

        vm.roll(SETUP_SETTLE_BLOCK);
        vm.prank(AUMT);
        distributor.recordDeposit(pool, LP_USER, 0);
    }

    /// @notice While unbound, settles keep running but poolBoostCursor stays frozen because its
    ///         write sits inside the non-zero-registry branch.
    function test_P1_E8_unbindingFreezesTheBoostCursorWhileSettlesContinue() public {
        _establishLiveBoostState();

        uint256 cursorWhileBound = distributor.poolBoostCursor(pool);
        assertGt(cursorWhileBound, 0, "precondition: cursor is known-current while bound");

        vm.prank(GOV);
        distributor.proposeIncendiaryRegistry(address(0));
        vm.roll(block.number + 1);
        vm.prank(GOV);
        distributor.acceptIncendiaryRegistry();
        assertEq(distributor.incendiaryRegistry(), address(0), "incendiary registry is unbound");

        vm.roll(UNBOUND_MID_BLOCK);
        vm.prank(AUMT);
        distributor.recordDeposit(pool, LP_USER, 0);

        vm.roll(UNBOUND_END_BLOCK);
        vm.prank(AUMT);
        distributor.recordDeposit(pool, LP_USER, 0);

        assertEq(
            distributor.poolBoostCursor(pool),
            cursorWhileBound,
            "poolBoostCursor is frozen across unbound settles"
        );
        assertEq(distributor.incendiaryRegistry(), address(0), "registry remains unbound after settles");
    }

    /// @notice Rebinding the same honest registry bills boostIntegral over the frozen cursor's
    ///         whole unbound window in one settle, exceeding a single-block tranche.
    function test_P1_E8_rebindingBillsTheWholeUnboundWindowAsOneBacklog() public {
        _establishLiveBoostState();

        uint256 frozenCursor = distributor.poolBoostCursor(pool);
        assertGt(frozenCursor, 0, "precondition: cursor is known-current while bound");

        vm.prank(GOV);
        distributor.proposeIncendiaryRegistry(address(0));
        vm.roll(block.number + 1);
        vm.prank(GOV);
        distributor.acceptIncendiaryRegistry();

        vm.roll(UNBOUND_END_BLOCK - 1);

        vm.prank(GOV);
        distributor.proposeIncendiaryRegistry(address(boostRegistry));
        vm.roll(UNBOUND_END_BLOCK);
        vm.prank(GOV);
        distributor.acceptIncendiaryRegistry();

        uint256 accBefore = distributor.poolAccRewardPerLP(pool);
        vm.prank(AUMT);
        distributor.recordDeposit(pool, LP_USER, 0);
        uint256 increase = distributor.poolAccRewardPerLP(pool) - accBefore;

        uint256 windowBoost = boostRegistry.boostIntegral(pool, frozenCursor + 1, UNBOUND_END_BLOCK);
        uint256 oneBlockBoost = boostRegistry.boostIntegral(pool, UNBOUND_END_BLOCK, UNBOUND_END_BLOCK);
        uint256 totalLP = distributor.poolTotalLP(pool);
        uint256 windowBoostCredit = (windowBoost * 1e18) / totalLP;
        uint256 oneBlockBoostCredit = (oneBlockBoost * 1e18) / totalLP;

        assertEq(
            windowBoost,
            BOOST_RATE * (UNBOUND_END_BLOCK - frozenCursor),
            "honest registry bills the inclusive unbound window from the frozen cursor"
        );
        assertGe(
            increase,
            windowBoostCredit,
            "observed credit is consistent with the unbound-window boost backlog"
        );
        assertGt(
            windowBoostCredit,
            oneBlockBoostCredit,
            "backlog billed on top of the rebind block's own tranche"
        );
        assertGt(
            increase,
            oneBlockBoostCredit,
            "backlog billed on top of the rebind block's own tranche"
        );
    }
}

/// @notice Regression for the registry-side face of seam-1 root cause E.8, per PP-D56 (vi) and (xvii):
///         `buyBoost` now reverts `NotBoundToDistributor` unless the distributor's live binding names
///         this registry, so a purchase after the distributor unbinds or rebinds it through its real
///         two-step takes nothing from the buyer. The PoC is inverted beside the done-criteria case on
///         the F.1 precedent. The distributor stands on placeholder collaborators, since its constructor
///         makes no external call and the two-step touches only storage and the proposed registry's
///         code size.
contract P1_E8_BuyBoostRequiresLiveBindingTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant BAL_AUMM = 1_000_000e18;
    uint256 internal constant BAL_SVZCHF = 750_000e18;
    uint256 internal constant BAL_SUSDS = 600_000e18;

    /// @dev The first block past Year 1, as a constant per F15, in this file's literal style.
    uint256 internal constant BOOSTS_OPEN_BLOCK = GENESIS_BLOCK + 2_628_000 + 1;

    address internal constant GOV = address(0x9011);
    address internal constant PLACEHOLDER = address(0xDEAD);

    IncendiaryRegistry internal registry;
    MockBodenseeExplorer internal explorer;
    MockWeightedVenue internal venue;
    MockBodenseeChannel internal channel;
    MockAuMMRate internal aumm;
    MockGaugeRegistry internal gauges;
    MockERC20 internal svzchf;
    MockERC20 internal susds;
    EmissionDistributorHarness internal distributor;

    function setUp() public {
        vm.roll(GENESIS_BLOCK);

        distributor = new EmissionDistributorHarness(
            IAuMM(PLACEHOLDER),
            IGaugeRegistry(PLACEHOLDER),
            IEMASampler(PLACEHOLDER),
            ICCBMultiplier(PLACEHOLDER),
            IEfficiencyOracle(PLACEHOLDER),
            IMiliariumRegistry(PLACEHOLDER),
            GENESIS_BLOCK,
            GOV,
            PLACEHOLDER
        );

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

        registry = new IncendiaryRegistry(
            SwapAndDepositToBodensee(address(channel)),
            address(venue),
            IVaultExplorer(address(explorer)),
            IAuMM(address(aumm)),
            IERC20(address(svzchf)),
            IERC20(address(susds)),
            IGaugeRegistry(address(gauges)),
            GENESIS_BLOCK,
            address(distributor)
        );
    }

    /// @notice The registry-side face of E.8, inverted per PP-D56 (xvii): once the distributor unbinds
    ///         the registry through its real two-step, a purchase reverts naming the zero address and
    ///         the buyer keeps the funds, where before the guard it paid in full for nothing delivered.
    function test_P1_E8_buyBoostStopsSellingOnceTheDistributorUnbinds() public {
        address buyer = makeAddr("boostBuyer");
        uint256 amount = 1000e18;

        registry.updateRailEMA(address(svzchf));
        vm.prank(GOV);
        distributor.proposeIncendiaryRegistry(address(registry));
        vm.roll(GENESIS_BLOCK + 1);
        vm.prank(GOV);
        distributor.acceptIncendiaryRegistry();
        assertEq(distributor.incendiaryRegistry(), address(registry));

        vm.roll(BOOSTS_OPEN_BLOCK);
        registry.updateRailEMA(address(svzchf));
        vm.prank(GOV);
        distributor.proposeIncendiaryRegistry(address(0));
        vm.roll(BOOSTS_OPEN_BLOCK + 1);
        vm.prank(GOV);
        distributor.acceptIncendiaryRegistry();
        assertEq(distributor.incendiaryRegistry(), address(0));

        aumm.setRate(1e18);
        gauges.setApproved(address(venue), true);
        svzchf.mint(buyer, amount);
        vm.prank(buyer);
        svzchf.approve(address(registry), amount);

        vm.expectRevert(abi.encodeWithSelector(IncendiaryRegistry.NotBoundToDistributor.selector, address(0)));
        vm.prank(buyer);
        registry.buyBoost(address(venue), address(svzchf), amount);

        assertEq(svzchf.balanceOf(buyer), amount);
        assertEq(channel.lastAmount(), 0);
    }

    /// @notice The done-criteria case for the registry-side face of E.8 per PP-D56 (xvii): a purchase
    ///         succeeds while the distributor binding names this registry, and once the distributor
    ///         rebinds to a different registry the next purchase reverts naming that registry.
    function test_buyBoostRequiresLiveBinding() public {
        address buyer = makeAddr("boostBuyer");
        uint256 amount = 1000e18;
        address otherRegistry = address(new LinearBoostRegistry(1));

        registry.updateRailEMA(address(svzchf));
        vm.prank(GOV);
        distributor.proposeIncendiaryRegistry(address(registry));
        vm.roll(GENESIS_BLOCK + 1);
        vm.prank(GOV);
        distributor.acceptIncendiaryRegistry();
        assertEq(distributor.incendiaryRegistry(), address(registry));

        vm.roll(BOOSTS_OPEN_BLOCK);
        registry.updateRailEMA(address(svzchf));
        aumm.setRate(1e18);
        gauges.setApproved(address(venue), true);
        svzchf.mint(buyer, 2 * amount);
        vm.prank(buyer);
        svzchf.approve(address(registry), 2 * amount);

        vm.prank(buyer);
        assertGt(registry.buyBoost(address(venue), address(svzchf), amount), 0);
        assertEq(channel.lastAmount(), amount);

        vm.prank(GOV);
        distributor.proposeIncendiaryRegistry(otherRegistry);
        vm.roll(BOOSTS_OPEN_BLOCK + 1);
        vm.prank(GOV);
        distributor.acceptIncendiaryRegistry();
        assertEq(distributor.incendiaryRegistry(), otherRegistry);

        vm.expectRevert(abi.encodeWithSelector(IncendiaryRegistry.NotBoundToDistributor.selector, otherRegistry));
        vm.prank(buyer);
        registry.buyBoost(address(venue), address(svzchf), amount);

        assertEq(svzchf.balanceOf(buyer), amount);
    }
}
