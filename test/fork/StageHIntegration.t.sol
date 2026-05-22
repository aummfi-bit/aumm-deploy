// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";

import { StageGIntegrationFixture } from "./StageGIntegration.t.sol";
import { MockMiliariumRegistry } from "./mocks/CCBMocks.sol";
import { IAuMM } from "../../src/token/IAuMM.sol";
import { EMASampler } from "../../src/ccb/EMASampler.sol";
import { IEMASampler } from "../../src/ccb/IEMASampler.sol";
import { CCBMultiplier } from "../../src/ccb/CCBMultiplier.sol";
import { ICCBMultiplier } from "../../src/ccb/ICCBMultiplier.sol";
import { AureumTime } from "../../src/lib/AureumTime.sol";
import { TVLOracle } from "../../src/emission/TVLOracle.sol";
import { EfficiencyOracle } from "../../src/emission/EfficiencyOracle.sol";
import { BodenseeBootstrapChannel } from "../../src/emission/BodenseeBootstrapChannel.sol";
import { EmissionDistributor } from "../../src/emission/EmissionDistributor.sol";

/**
 * @title StageHIntegrationFixture
 * @notice Stage H cross-stack fork-test base wiring the H1—H6 emission stack against real Bodensee + Stage E pilots per H-D37.
 * @dev Inherits `StageGIntegrationFixture` (vault + factory + AuMM + Bodensee + pilots + GaugeRegistry /
 *      VaultClassRegistry / GaugeEligibility / SwapAndDepositToBodensee) and extends setUp with the Stage H
 *      production stack: TVLOracle + EMASampler + CCBMultiplier + EfficiencyOracle + BodenseeBootstrapChannel +
 *      EmissionDistributor + MockMiliariumRegistry. Post-construction wiring: H-D23
 *      `setEmissionsRecorder(address(emissionDistributor))` on efficiencyOracle + H6.3
 *      `setAuMTContract(address(this))` on emissionDistributor (test contract impersonates the Stage I AuMT
 *      recorder for `recordDeposit` / `recordWithdrawal` calls). `aumm.setMinter(...)` is deferred to each
 *      derived contract's setUp override per H-D37 amended at H9.0c (Option A — avoids Bodensee-pool AuMM
 *      token conflict: `StageHBootstrapPhaseTest` needs `bootstrapChannel` as minter for H-D39 DONATION
 *      callback, other tests need `emissionDistributor` as minter for H-D20 `claim` path; C-D11 one-shot
 *      `_minterAdmin` disallows fixture-level wiring). `incendiaryRegistry` stays `address(0)` per H-D29
 *      zero-stub (slot default — no setter call required; F-7 Step 1 Incendiary skim collapses to 0 per
 *      H5.1c continuous-leg short-circuit).
 *      Anchors: H-D37, H-D7 (OPEN), C-D11, H-D11, H-D20, H-D23, H-D29, H-D31, D35 + D36 + H-D40, E10.
 */
abstract contract StageHIntegrationFixture is StageGIntegrationFixture {
    TVLOracle internal tvlOracle;
    EMASampler internal emaSampler;
    CCBMultiplier internal ccbMultiplier;
    EfficiencyOracle internal efficiencyOracle;
    BodenseeBootstrapChannel internal bootstrapChannel;
    EmissionDistributor internal emissionDistributor;
    MockMiliariumRegistry internal miliariumRegistry;

    function setUp() public virtual override {
        super.setUp();

        address[3] memory miliariumPools;
        miliariumPools[0] = pilotPools[0];
        miliariumPools[1] = pilotPools[1];
        miliariumPools[2] = pilotPools[2];
        miliariumRegistry = new MockMiliariumRegistry(miliariumPools);

        tvlOracle = new TVLOracle(
            IVaultExplorer(address(vault)),
            bodenseePool,
            address(svZchf),
            address(this),
            new address[](0),
            new address[](0)
        );

        emaSampler = new EMASampler(tvlOracle);

        ccbMultiplier = new CCBMultiplier(miliariumRegistry, gaugeRegistry, IEMASampler(address(emaSampler)));

        efficiencyOracle = new EfficiencyOracle(
            tvlOracle,
            address(aumm),
            aumm.GENESIS_BLOCK(),
            address(this)
        );

        bootstrapChannel = new BodenseeBootstrapChannel(
            vault,
            bodenseePool,
            IAuMM(address(aumm)),
            aumm.GENESIS_BLOCK(),
            address(this)
        );

        emissionDistributor = new EmissionDistributor(
            IAuMM(address(aumm)),
            gaugeRegistry,
            IEMASampler(address(emaSampler)),
            ICCBMultiplier(address(ccbMultiplier)),
            efficiencyOracle,
            miliariumRegistry,
            aumm.GENESIS_BLOCK(),
            address(this)
        );

        efficiencyOracle.setEmissionsRecorder(address(emissionDistributor)); // H-D23 — distributor pushes recordEmissions; oracle must whitelist
        emissionDistributor.setAuMTContract(address(this)); // H6.3 — recorder impersonation; test contract drives recordDeposit/recordWithdrawal

        // aumm.setMinter(...) deferred to each derived contract's setUp override per H-D37 amended at H9.0c (Option A — Bodensee-pool AuMM token shared between bootstrapChannel and emissionDistributor minter paths; one-shot C-D11 _minterAdmin disallows fixture-level wiring)
        // incendiaryRegistry stays address(0) per H-D29 zero-stub (slot default — no setter call required; F-7 Step 1 Incendiary skim collapses to 0 per H5.1c continuous-leg short-circuit)
    }
}

/**
 * @title StageHBootstrapPhaseTest
 * @notice Fork-level exercise of BodenseeBootstrapChannel.accrue() against the real Bodensee + real AuMM stack.
 *         Covers: F-0/F-1 bootstrap arc; accrue() cadence across Bootstrap A (80→50%) + Bootstrap B (50→0%);
 *         H-D11 AP closed-form identity; pendingAccrual conservation invariant pre-distribute.
 *         Minter handoff: bootstrapChannel receives AuMM minting authority in setUp per H-D37 amended at H9.0c
 *         (Option A — C-D11 one-shot _minterAdmin consumed here; a later setMinter on the same AuMM instance
 *         would revert NotMinterAdmin, as expected). The distribute() arc + sad-path pair land separately at H9.3.
 *         Anchors: H-D11, H-D37, H-D38(1), C-D11.
 */
contract StageHBootstrapPhaseTest is StageHIntegrationFixture {
    function setUp() public override {
        super.setUp();
        aumm.setMinter(address(bootstrapChannel));
    }

    /// @notice Test-side mirror of BodenseeBootstrapChannel._apSum for expected-value assertions — bit-for-bit port of test/unit/BodenseeBootstrapChannel.t.sol L333-L348.
    function _expectedApSum(
        uint256 from,
        uint256 to,
        uint256 anchorStart,
        uint256 anchorEnd,
        uint256 startShare,
        uint256 dropShare,
        uint256 rate
    ) internal pure returns (uint256) {
        uint256 width = anchorEnd - anchorStart;
        uint256 first = startShare - (dropShare * (from - anchorStart)) / width;
        uint256 last = startShare - (dropShare * (to - anchorStart)) / width;
        uint256 n = to - from + 1;
        return ((first + last) * n * rate) / (2 * 1e18);
    }

    // H-D38(1) — Bootstrap A leg: AP closed-form identity, single accrue() call within Bootstrap A window
    function test_Accrue_BootstrapALeg_MatchesAPClosedForm() public {
        uint256 g = aumm.GENESIS_BLOCK();
        uint256 m6 = AureumTime.month6EndBlock(g);
        vm.roll(g + 1_000);
        uint256 expected = _expectedApSum(g + 1, g + 1_000, g, m6, 8e17, 3e17, 1e18);
        bootstrapChannel.accrue();
        assertEq(bootstrapChannel.pendingAccrual(), expected, "pendingAccrual");
        assertEq(bootstrapChannel.lastAccrualBlock(), g + 1_000, "lastAccrualBlock");
        assertEq(bootstrapChannel.totalDistributed(), 0, "totalDistributed pre-distribute");
    }

    // H-D38(1) — Bootstrap B leg: AP closed-form identity, accrue() called at m6 then again within Bootstrap B window
    function test_Accrue_BootstrapBLeg_MatchesAPClosedForm() public {
        uint256 g = aumm.GENESIS_BLOCK();
        uint256 m6 = AureumTime.month6EndBlock(g);
        uint256 m10 = AureumTime.month10EndBlock(g);
        vm.roll(m6);
        bootstrapChannel.accrue();
        uint256 aSum = bootstrapChannel.pendingAccrual();
        vm.roll(m6 + 1_000);
        uint256 expectedB = _expectedApSum(m6 + 1, m6 + 1_000, m6, m10, 5e17, 5e17, 1e18);
        bootstrapChannel.accrue();
        assertEq(bootstrapChannel.pendingAccrual(), aSum + expectedB, "pendingAccrual");
        assertEq(bootstrapChannel.lastAccrualBlock(), m6 + 1_000, "lastAccrualBlock");
    }

    // H-D38(1) — Boundary-spanning: single accrue() crossing m6 boundary correctly splits A + B legs
    function test_Accrue_BoundarySpanning_SplitsLegs() public {
        uint256 g = aumm.GENESIS_BLOCK();
        uint256 m6 = AureumTime.month6EndBlock(g);
        uint256 m10 = AureumTime.month10EndBlock(g);
        vm.roll(m6 + 1_000);
        uint256 aSum = _expectedApSum(g + 1, m6, g, m6, 8e17, 3e17, 1e18);
        uint256 bSum = _expectedApSum(m6 + 1, m6 + 1_000, m6, m10, 5e17, 5e17, 1e18);
        bootstrapChannel.accrue();
        assertEq(bootstrapChannel.pendingAccrual(), aSum + bSum, "pendingAccrual");
        assertEq(bootstrapChannel.lastAccrualBlock(), m6 + 1_000, "lastAccrualBlock");
    }

    // H-D38(1) — Conservation invariant: pendingAccrual equals Σ segment contributions; totalDistributed stays 0 throughout
    function test_Accrue_ConservationInvariant_PendingEqualsSumAccrued() public {
        uint256 g = aumm.GENESIS_BLOCK();
        uint256 m6 = AureumTime.month6EndBlock(g);

        uint256 prevTo = g;
        uint256 cumulative = 0;

        // step 1: g + 500
        vm.roll(g + 500);
        bootstrapChannel.accrue();
        cumulative += _expectedApSum(prevTo + 1, g + 500, g, m6, 8e17, 3e17, 1e18);
        prevTo = g + 500;
        assertEq(bootstrapChannel.pendingAccrual(), cumulative, "pendingAccrual step1");
        assertEq(bootstrapChannel.totalDistributed(), 0, "totalDistributed step1");

        // step 2: g + 1_500
        vm.roll(g + 1_500);
        bootstrapChannel.accrue();
        cumulative += _expectedApSum(prevTo + 1, g + 1_500, g, m6, 8e17, 3e17, 1e18);
        prevTo = g + 1_500;
        assertEq(bootstrapChannel.pendingAccrual(), cumulative, "pendingAccrual step2");
        assertEq(bootstrapChannel.totalDistributed(), 0, "totalDistributed step2");

        // step 3: g + 3_000
        vm.roll(g + 3_000);
        bootstrapChannel.accrue();
        cumulative += _expectedApSum(prevTo + 1, g + 3_000, g, m6, 8e17, 3e17, 1e18);
        assertEq(bootstrapChannel.pendingAccrual(), cumulative, "pendingAccrual step3");
        assertEq(bootstrapChannel.totalDistributed(), 0, "totalDistributed step3");
    }
}
