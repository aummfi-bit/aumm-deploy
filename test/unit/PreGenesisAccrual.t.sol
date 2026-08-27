// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { AureumTime } from "../../src/lib/AureumTime.sol";
import { IAuMM } from "../../src/token/IAuMM.sol";
import { IGaugeRegistry } from "../../src/ccb/IGaugeRegistry.sol";
import { IEMASampler } from "../../src/ccb/IEMASampler.sol";
import { ICCBMultiplier } from "../../src/ccb/ICCBMultiplier.sol";
import { IEfficiencyOracle } from "../../src/gauge/IEfficiencyOracle.sol";
import { IMiliariumRegistry } from "../../src/ccb/IMiliariumRegistry.sol";
import { EmissionDistributorHarness } from "./harness/EmissionDistributorHarness.sol";
import {
    MockAuMM,
    MockGaugeRegistry,
    MockEMASampler,
    MockCCBMultiplier,
    MockEfficiencyOracle,
    MockMiliariumRegistry
} from "./EmissionDistributor.t.sol";
import {MockRegisteredVault} from "../mocks/MockRegisteredVault.sol";

/// @title  PreGenesisAccrualHarness
/// @notice Adds a mutating exposer for `_accrueGlobal` on top of the H-D34 view-only harness.
/// @dev    Declared here rather than on the shared harness so the fixture the Part-A unit suite
///         depends on stays byte-identical. Constructor is a pure pass-through; no new state.
contract PreGenesisAccrualHarness is EmissionDistributorHarness {
    constructor(
        IAuMM aumm_,
        IGaugeRegistry gaugeRegistry_,
        IEMASampler emaSampler_,
        ICCBMultiplier ccbMultiplier_,
        IEfficiencyOracle efficiencyOracle_,
        IMiliariumRegistry miliariumRegistry_,
        uint256 genesisBlock_,
        address initialGovernance_,
        address vault_
    )
        EmissionDistributorHarness(
            aumm_,
            gaugeRegistry_,
            emaSampler_,
            ccbMultiplier_,
            efficiencyOracle_,
            miliariumRegistry_,
            genesisBlock_,
            initialGovernance_,
            vault_
        )
    {}

    /// @notice Delegates to the parent's `_accrueGlobal()` lazy-tick so a pre-genesis touch is directly observable.
    function extAccrueGlobal() external {
        _accrueGlobal();
    }
}

/// @title  PreGenesisAccrualTest
/// @notice PB3.4e (PB-D19 (v)) — the two evidence pins for the future-genesis posture, on the one path
///         the P10 harness never ran: its fixture rolled to genesis, so block.number was never inside
///         the pad. Here the distributor is constructed at DEPLOY_BLOCK with genesis one epoch ahead,
///         exactly the PB3.5 broadcast configuration, and the fixture never leaves the pad.
/// @dev    Unit-scoped, zero src change. Run with the Part-A split-form invocation per D35.
contract PreGenesisAccrualTest is Test {
    uint256 internal constant DEPLOY_BLOCK = 1_000_000;
    // PB-D19 (i) — the locked pad: one epoch between broadcast and genesis.
    uint256 internal constant GENESIS_OFFSET = 100_800;
    uint256 internal constant GENESIS_BLOCK_ = DEPLOY_BLOCK + GENESIS_OFFSET;
    address internal constant GOV = address(0xC0FE);

    PreGenesisAccrualHarness internal distributor;

    function setUp() public {
        vm.roll(DEPLOY_BLOCK);
        distributor = new PreGenesisAccrualHarness(
            IAuMM(address(new MockAuMM())),
            IGaugeRegistry(address(new MockGaugeRegistry())),
            IEMASampler(address(new MockEMASampler())),
            ICCBMultiplier(address(new MockCCBMultiplier())),
            IEfficiencyOracle(address(new MockEfficiencyOracle())),
            IMiliariumRegistry(address(new MockMiliariumRegistry())),
            GENESIS_BLOCK_,
            GOV,
            address(new MockRegisteredVault())
        );
    }

    /// @notice The premise pin (PB-D19 (iii)): the constructor anchors lastAccrualBlock at genesis, so
    ///         under the future offset the anchor sits AHEAD of the deploy block and the accrual window
    ///         is inverted for the whole pad. Nothing may hand that window to the integral.
    function test_preGenesis_anchorSitsAheadOfCurrentBlock() public view {
        assertEq(distributor.lastAccrualBlock(), GENESIS_BLOCK_, "anchor is not seeded to genesis");
        assertGt(distributor.lastAccrualBlock(), block.number, "anchor is not ahead of the deploy block");
        assertEq(distributor.totalScore(), 0, "totalScore is not zero at deploy");
    }

    /// @notice PB-D19 (v) pin (1): a pre-genesis `_accrueGlobal` touch takes the H-D15 empty-totalScore
    ///         short-circuit — it snaps lastAccrualBlock to the current block and accrues nothing, so
    ///         the inverted window is never evaluated and no schedule time is burned inside the pad.
    function test_preGenesis_accrueGlobalIsNoOpAndResetsAnchor() public {
        vm.roll(DEPLOY_BLOCK + GENESIS_OFFSET / 2);
        assertLt(block.number, GENESIS_BLOCK_, "roll escaped the pre-genesis pad");

        distributor.extAccrueGlobal();

        assertEq(distributor.lastAccrualBlock(), block.number, "anchor did not snap to the current block");
        assertLt(distributor.lastAccrualBlock(), GENESIS_BLOCK_, "anchor is still ahead of genesis");
        assertEq(distributor.accRewardPerScoreUnit(), 0, "emission accrued before genesis");
    }

    /// @notice PB-D19 (v) pin (2): the pad cannot mature a TVL EMA, which is what makes pin (1)'s
    ///         short-circuit unconditional rather than incidental — no seed placed at deploy can confer
    ///         score before genesis, so totalScore is necessarily zero throughout the pad.
    ///         F10_emaScoreGate.t.sol owns the gate mechanism; this pins the constant relation PB-D19
    ///         rests on, so moving either the pad or the maturity window fails here.
    function test_preGenesis_padIsShorterThanEmaMaturityGate() public pure {
        assertEq(GENESIS_OFFSET, AureumTime.BLOCKS_PER_EPOCH, "pad is not one epoch");
        assertLt(GENESIS_OFFSET, 60 * AureumTime.BLOCKS_PER_DAY, "pad is not shorter than EMA maturity");
    }
}
