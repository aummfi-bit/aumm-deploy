// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AuMM} from "../../src/token/AuMM.sol";
import {IAuMM} from "../../src/token/IAuMM.sol";
import {IEmissionDistributor} from "../../src/emission/IEmissionDistributor.sol";
import {IGaugeRegistry} from "../../src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "../../src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "../../src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "../../src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "../../src/gauge/IEfficiencyOracle.sol";
import {AureumTime} from "../../src/lib/AureumTime.sol";
import {EmissionDistributorHarness} from "./harness/EmissionDistributorHarness.sol";
import {
    MockGaugeRegistry,
    MockEMASampler,
    MockCCBMultiplier,
    MockEfficiencyOracle,
    MockMiliariumRegistry
} from "./EmissionDistributor.t.sol";

/// @notice Real-AuMM integration test family per H-D36 — 4-test cohort exercising mock/real setMinter parity + halving.
/// @dev C-D11 two-flag-lock wired via `new AuMM(GENESIS_BLOCK_, address(this))` so this contract is the constructor
///      `_minterAdmin`; mock contracts imported by name from EmissionDistributor.t.sol (no inline redefinition);
///      distributor slot typed EmissionDistributorHarness per H-D34.
contract AuMMDistributorIntegrationTest is Test {
    uint256 internal constant GENESIS_BLOCK_ = 1_000_000;
    address internal constant GOV      = address(0xC0FE);
    address internal constant AUMT_REC = address(0xA0DC);
    address internal constant POOL_A   = address(0xA1);
    address internal constant USER_1   = address(0xE1);
    address internal constant USER_2   = address(0xE2);

    AuMM internal aumm;
    MockGaugeRegistry internal gauges;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockEfficiencyOracle internal effOracle;
    MockMiliariumRegistry internal miliReg;
    EmissionDistributorHarness internal distributor;

    function setUp() public virtual {
        aumm = new AuMM(GENESIS_BLOCK_, address(this));
        gauges = new MockGaugeRegistry();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        effOracle = new MockEfficiencyOracle();
        miliReg = new MockMiliariumRegistry();
        distributor = new EmissionDistributorHarness(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK_,
            GOV
        );
        aumm.setMinter(address(distributor));
        effOracle.setEmissionsRecorder(address(distributor));
        vm.prank(GOV);
        distributor.setAuMTContract(AUMT_REC);
        vm.roll(GENESIS_BLOCK_);
    }
}
