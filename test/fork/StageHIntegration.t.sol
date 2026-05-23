// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
import { IBodenseeBootstrapChannel } from "../../src/emission/IBodenseeBootstrapChannel.sol";
import { EmissionDistributor } from "../../src/emission/EmissionDistributor.sol";
import { IEmissionDistributor } from "../../src/emission/IEmissionDistributor.sol";

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
        // H-D14 — transfer to multisig per H-D39 production-deploy semantics
        bootstrapChannel.setGovernanceContract(GOVERNANCE_MULTISIG);
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

    // H-D39 — happy-path distribute() arc: IVault.unlock → _distributeCallback → safeTransfer → settle → DONATION; asserts reserve delta + BPT supply + state mutations
    function test_Distribute_RealVaultDonationArc_MutatesReserveAndEmitsDistributed() public {
        uint256 g = aumm.GENESIS_BLOCK();
        vm.roll(g + 1_000);
        bootstrapChannel.accrue();
        uint256 expected = bootstrapChannel.pendingAccrual();
        uint256 bptSupplyPre = IERC20(bodenseePool).totalSupply();
        IERC20[] memory tokens = vault.getPoolTokens(bodenseePool);
        uint256 aummIdx = type(uint256).max;
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (address(tokens[i]) == address(aumm)) { aummIdx = i; break; }
        }
        require(aummIdx != type(uint256).max, "AuMM not in Bodensee roster");
        (, , uint256[] memory balancesPre, ) = vault.getPoolTokenInfo(bodenseePool);
        uint256 preReserve = balancesPre[aummIdx];
        vm.expectEmit(true, false, false, true);
        emit IBodenseeBootstrapChannel.Distributed(GOVERNANCE_MULTISIG, expected);
        vm.prank(GOVERNANCE_MULTISIG);
        bootstrapChannel.distribute();
        (, , uint256[] memory balancesPost, ) = vault.getPoolTokenInfo(bodenseePool);
        uint256 postReserve = balancesPost[aummIdx];
        assertEq(postReserve - preReserve, expected, "Bodensee AuMM reserve delta");
        assertEq(IERC20(bodenseePool).totalSupply(), bptSupplyPre, "BPT total supply unchanged on DONATION");
        assertEq(bootstrapChannel.pendingAccrual(), 0, "pendingAccrual cleared");
        assertEq(bootstrapChannel.totalDistributed(), expected, "totalDistributed");
    }

    // H-D39 — NotGovernance sad-path: non-governance caller is rejected even when pendingAccrual > 0
    function test_RevertWhen_DistributeCalledByNonGovernance() public {
        uint256 g = aumm.GENESIS_BLOCK();
        vm.roll(g + 1_000);
        bootstrapChannel.accrue();
        address attacker = address(uint160(uint256(keccak256("attacker"))));
        vm.expectRevert(abi.encodeWithSelector(BodenseeBootstrapChannel.NotGovernance.selector, attacker));
        vm.prank(attacker);
        bootstrapChannel.distribute();
    }

    // H-D39 — NoPendingAccrual sad-path: governance caller is rejected when pendingAccrual == 0
    function test_RevertWhen_DistributeWithNoPendingAccrual() public {
        vm.expectRevert(BodenseeBootstrapChannel.NoPendingAccrual.selector);
        vm.prank(GOVERNANCE_MULTISIG);
        bootstrapChannel.distribute();
    }
}

/**
 * @title StageHContinuousPhaseTest
 * @notice Fork-level exercise of the F-7 continuous-phase 3-pilot claim arc against real EmissionDistributor + real AuMM.
 *         Strategy A white-box state seed: `seedFoundingPool` for gauge approval (onlyGovernance founding-seed shortcut
 *         per G-D16b bypassing eligibility + anti-spam fee); `vm.store` for `emaSampler.tvlEMA[pilot]` slot 0
 *         (bypasses TVLOracle constellation + EMASampler.updateEMA — cross-stack swap-driven path reserved for H9.6).
 *         Zero-stub `incendiaryRegistry == address(0)` per H-D29 short-circuits F-7 Step 1 Incendiary skim, returning
 *         `rate × n` as the full continuous-leg output. Bounded conservation invariant
 *         `|Σ aumm.balanceOf(userN) − lpTrancheEmission(span)| ≤ N_gauged wei` with N_gauged = 3; chosen numerics
 *         (tvlEMA = 1e18, multiplier = 1e18 default, span = 300 blocks at Era 0 continuous) make every
 *         divDown / mulDown step exact so diff = 0 in practice.
 *         Anchors: H-D17, H-D20, H-D26, H-D29, H-D30, H-D31, H-D32, H-D33, H-D37, H-D38(2), F-7.
 */
contract StageHContinuousPhaseTest is StageHIntegrationFixture {
    function setUp() public override {
        super.setUp();
        aumm.setMinter(address(emissionDistributor));
        vm.roll(AureumTime.year1EndBlock(aumm.GENESIS_BLOCK()) + 1);
        gaugeRegistry.seedFoundingPool(pilotPools[0]);
        gaugeRegistry.seedFoundingPool(pilotPools[1]);
        gaugeRegistry.seedFoundingPool(pilotPools[2]);
        vm.store(address(emaSampler), keccak256(abi.encode(pilotPools[0], uint256(0))), bytes32(uint256(1e18)));
        vm.store(address(emaSampler), keccak256(abi.encode(pilotPools[1], uint256(0))), bytes32(uint256(1e18)));
        vm.store(address(emaSampler), keccak256(abi.encode(pilotPools[2], uint256(0))), bytes32(uint256(1e18)));
    }

    /// @notice F-7 continuous-phase 3-pilot claim arc: recordScore + recordDeposit drive per-pool LP share state; claim mints AuMM via real IAuMM.mint and the bounded Σ conservation invariant confirms no wei leak across 3 gauged pools.
    function test_Claim_F7Phase_ThreePilotsMint_BoundedConservation() public {
        address user0 = makeAddr("h94_user0");
        address user1 = makeAddr("h94_user1");
        address user2 = makeAddr("h94_user2");

        emissionDistributor.recordScore(pilotPools[0]);
        emissionDistributor.recordScore(pilotPools[1]);
        emissionDistributor.recordScore(pilotPools[2]);

        emissionDistributor.recordDeposit(pilotPools[0], user0, 100e18);
        emissionDistributor.recordDeposit(pilotPools[1], user1, 100e18);
        emissionDistributor.recordDeposit(pilotPools[2], user2, 100e18);

        uint256 span = 300;
        vm.roll(block.number + span);

        vm.expectEmit(true, true, true, true);
        emit IEmissionDistributor.Claimed(pilotPools[0], user0, user0, 100e18);
        vm.prank(user0);
        emissionDistributor.claim(pilotPools[0], user0);

        vm.expectEmit(true, true, true, true);
        emit IEmissionDistributor.Claimed(pilotPools[1], user1, user1, 100e18);
        vm.prank(user1);
        emissionDistributor.claim(pilotPools[1], user1);

        vm.expectEmit(true, true, true, true);
        emit IEmissionDistributor.Claimed(pilotPools[2], user2, user2, 100e18);
        vm.prank(user2);
        emissionDistributor.claim(pilotPools[2], user2);

        assertEq(aumm.balanceOf(user0), 100e18, "user0 mint");
        assertEq(aumm.balanceOf(user1), 100e18, "user1 mint");
        assertEq(aumm.balanceOf(user2), 100e18, "user2 mint");

        uint256 total = aumm.balanceOf(user0) + aumm.balanceOf(user1) + aumm.balanceOf(user2);
        uint256 expected = 300e18; // lpTrancheEmission(span) = rate × n = 1e18 × 300 in Era 0 continuous with zero-stub incendiary
        uint256 diff = expected > total ? expected - total : total - expected;
        assertLe(diff, 3, "bounded conservation N_gauged=3");
    }
}
