// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AuMM} from "../../src/token/AuMM.sol";
import {IAuMM} from "../../src/token/IAuMM.sol";
import {AuMMMinterRouter} from "../../src/token/AuMMMinterRouter.sol";
import {EmissionDistributor} from "../../src/emission/EmissionDistributor.sol";
import {IEmissionDistributor} from "../../src/emission/IEmissionDistributor.sol";
import {IGaugeRegistry} from "../../src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "../../src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "../../src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "../../src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "../../src/gauge/IEfficiencyOracle.sol";
import {
    MockGaugeRegistry,
    MockEMASampler,
    MockCCBMultiplier,
    MockEfficiencyOracle,
    MockMiliariumRegistry
} from "../unit/EmissionDistributor.t.sol";
import {MockRegisteredVault} from "../mocks/MockRegisteredVault.sol";

/// @notice The three-faced attacker contract from the F.1 audit issue
///         (`setincendiaryregistry-is-an-unbounded-mint-oracle`). Its `boostIntegral`
///         face returns an unbounded constant that `EmissionDistributor._settlePool:406`
///         reads wholesale into `poolAccRewardPerLP`; its `balanceOf` face returns `1e18`
///         so `_syncDown` short-circuits at `:520`; its `integratedSkim` face returns 0
///         for the Year-2+ continuous phase. Stateless and pure by design.
contract EvilRegistry {
    uint256 internal immutable HUGE;

    constructor(uint256 huge_) {
        HUGE = huge_;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 1e18;
    }

    function boostIntegral(address, uint256, uint256) external view returns (uint256) {
        return HUGE;
    }

    function integratedSkim(uint256, uint256) external pure returns (uint256) {
        return 0;
    }
}

/// @notice PP3.2 reproduction PoC for root cause F.1 — `EmissionDistributor.setIncendiaryRegistry`
///         is an unbounded, freely-rebindable mint oracle: the pre-dissolution governance key
///         mints the entire remaining AuMM supply to itself in four transactions with zero capital.
/// @dev Uses the REAL `AuMM`, `AuMMMinterRouter` and `EmissionDistributor` (not `MockAuMM`, not the
///      harness) so the mint against `MAX_SUPPLY` is genuine. Peripheral reads (`GaugeRegistry`,
///      `EMASampler`, `CCBMultiplier`, `EfficiencyOracle`, `MiliariumRegistry`) are mocked because
///      the F.1 path never touches them: `poolAllocation == 0` skips the oracle push at `:396`.
///      Inverted into F.1's regression at PP4.1 (rung 1 of the fix-sequencing order).
contract P1_F1_Test is Test {
    uint256 internal constant GENESIS_BLOCK_ = 1_000_000;
    address internal constant GOV      = address(0xC0FE); // pre-dissolution GOVERNANCE_MULTISIG
    address internal constant ATTACKER = address(0xBAD);
    address internal constant DUMMY_CHANNEL = address(0xC4A9);

    AuMM internal aumm;
    MockGaugeRegistry internal gauges;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockEfficiencyOracle internal effOracle;
    MockMiliariumRegistry internal miliReg;
    EmissionDistributor internal distributor;
    AuMMMinterRouter internal router;

    function setUp() public {
        aumm = new AuMM(GENESIS_BLOCK_, address(this));
        gauges = new MockGaugeRegistry();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        effOracle = new MockEfficiencyOracle();
        miliReg = new MockMiliariumRegistry();

        distributor = new EmissionDistributor(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK_,
            GOV,
            address(new MockRegisteredVault())
        );
        router = new AuMMMinterRouter(IAuMM(address(aumm)), DUMMY_CHANNEL, address(distributor));

        aumm.setMinter(address(router));
        vm.prank(GOV);
        distributor.setMintRouter(address(router));

        effOracle.setEmissionsRecorder(address(distributor));
        vm.roll(GENESIS_BLOCK_);
    }

    /// @notice REGRESSION (PP-D44 / F.1). The audit's four-call sequence still executes, but the
    ///         clamp bounds what it can deliver: the governance key can no longer mint the remaining
    ///         supply, with an empty emitting window or a real one.
    /// @dev    Inverted from the PP3.2 reproduction per the part-4 gate. All four calls still SUCCEED
    ///         — the seating controls that would refuse them are separate remedies on their own rungs
    ///         — so what this pins is the consumer-side clamp alone: `boostDue` bounded by
    ///         `BOOST_CAP_BPS` of `_lpTrancheIntegral` over the same interval, per
    ///         `10_constitution.md` §xxix L135. Phase 1 claims at `GENESIS_BLOCK_` itself, where the
    ///         cap window is empty and nothing is admitted; phase 2 rolls forward so the window is
    ///         real, proving the bound comes from the CAP and not merely from zero elapsed blocks.
    function test_F1_governanceKeyCannotMintRemainingSupplyWithZeroCapital() public {
        uint256 huge = aumm.MAX_SUPPLY() - aumm.totalSupply();
        assertGt(huge, 0, "precondition: headroom under the cap exists");
        assertEq(aumm.balanceOf(ATTACKER), 0, "precondition: attacker holds nothing");
        EvilRegistry evil = new EvilRegistry(huge);

        // 1. seat the attacker as the recorder for the fake pool `evil` (pool arg unvalidated)
        vm.prank(GOV);
        distributor.setAuMTContractForPool(address(evil), ATTACKER);

        // 2. record a 1e18 position as that recorder — no capital, no BPT
        vm.prank(ATTACKER);
        distributor.recordDeposit(address(evil), ATTACKER, 1e18);

        // 3. repoint the boost oracle at the attacker's own contract
        vm.prank(GOV);
        distributor.setIncendiaryRegistry(address(evil));

        // 4. the attacker claims: claim() credits msg.sender's position and mints to `to`,
        //    so the attacker must be the caller (the position was seated under ATTACKER in step 2)
        vm.prank(ATTACKER);
        distributor.claim(address(evil), ATTACKER);

        // Phase 1. setUp rolls to GENESIS_BLOCK_ exactly, so the cap window [GENESIS_BLOCK_ + 1,
        // block.number] is empty, `_lpTrancheIntegral` returns 0 and the clamp admits nothing.
        assertEq(aumm.balanceOf(ATTACKER), 0, "empty cap window admits nothing");

        // Phase 2. With a real emitting window the stream is admitted but BOUNDED, which is the
        // property the clamp exists for. The bound is asserted as a coarse fraction rather than a
        // wei-exact figure so it cannot break on F-0 bootstrap interpolation.
        vm.roll(GENESIS_BLOCK_ + 100);
        vm.prank(ATTACKER);
        distributor.claim(address(evil), ATTACKER);

        uint256 minted = aumm.balanceOf(ATTACKER);
        assertLt(minted, huge / 1_000, "clamped far below the remaining supply");
        assertLt(aumm.totalSupply(), aumm.MAX_SUPPLY(), "supply is never pinned at the cap");
    }
}
