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
        distributor.setIncendiaryRegistry(address(boostRegistry));

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
        distributor.setIncendiaryRegistry(address(0));
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
        distributor.setIncendiaryRegistry(address(0));

        vm.roll(UNBOUND_END_BLOCK);

        vm.prank(GOV);
        distributor.setIncendiaryRegistry(address(boostRegistry));

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
