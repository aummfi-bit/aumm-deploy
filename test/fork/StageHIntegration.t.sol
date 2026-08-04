// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { StageGIntegrationFixture } from "./StageGIntegration.t.sol";
import { MockMiliariumRegistry, MockGaugeRegistry } from "./mocks/CCBMocks.sol";
import { IAuMM } from "../../src/token/IAuMM.sol";
import { AuMMMinterRouter } from "../../src/token/AuMMMinterRouter.sol";
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
import {
    TokenConfig,
    TokenType,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

/**
 * @title StageHIntegrationFixture
 * @notice Stage H cross-stack fork-test base wiring the H1—H6 emission stack against real Bodensee + Stage E pilots per H-D37.
 * @dev Inherits `StageGIntegrationFixture` (vault + factory + AuMM + Bodensee + pilots + GaugeRegistry /
 *      VaultClassRegistry / GaugeEligibility / SwapAndDepositToBodensee) and extends setUp with the Stage H
 *      production stack: TVLOracle + EMASampler + CCBMultiplier + EfficiencyOracle + BodenseeBootstrapChannel +
 *      EmissionDistributor + MockMiliariumRegistry. Post-construction wiring: H-D23
 *      `setEmissionsRecorder(address(emissionDistributor))` on efficiencyOracle + H6.3
 *      `setAuMTContractForPool(pilotPools[0..2], address(this))` on emissionDistributor (test contract impersonates the Stage I AuMT
 *      recorder for `recordDeposit` / `recordWithdrawal` calls). Minter wiring per K7.4b (K-D7): one
 *      `AuMMMinterRouter` holds AuMM's C-D11 one-shot `_minterAdmin` slot via
 *      `aumm.setMinter(address(minterRouter))` and forwards `mintFor` for both allowlisted consumers —
 *      `bootstrapChannel` (H-D39 DONATION callback) and `emissionDistributor` (H-D20 `claim` path); both
 *      `setMintRouter` one-shots land at fixture level while channel/distributor governance is still
 *      `address(this)`, superseding the H-D37/H9.0c Option A per-derived deferral that the one-shot
 *      `_minterAdmin` previously forced. `incendiaryRegistry` stays `address(0)` per H-D29
 *      zero-stub (slot default — no setter call required; F-7 Step 1 Incendiary skim collapses to 0 per
 *      H5.1c continuous-leg short-circuit).
 *      Anchors: H-D37, K-D7, C-D11, H-D11, H-D20, H-D23, H-D29, H-D31, D35 + D36 + H-D40, E10.
 */
abstract contract StageHIntegrationFixture is StageGIntegrationFixture {
    TVLOracle internal tvlOracle;
    EMASampler internal emaSampler;
    CCBMultiplier internal ccbMultiplier;
    EfficiencyOracle internal efficiencyOracle;
    BodenseeBootstrapChannel internal bootstrapChannel;
    EmissionDistributor internal emissionDistributor;
    AuMMMinterRouter internal minterRouter;
    MockMiliariumRegistry internal miliariumRegistry;
    MockGaugeRegistry internal mockGaugeRegistry;

    function setUp() public virtual override {
        super.setUp();

        address[3] memory miliariumPools;
        miliariumPools[0] = pilotPools[0];
        miliariumPools[1] = pilotPools[1];
        miliariumPools[2] = pilotPools[2];
        miliariumRegistry = new MockMiliariumRegistry(miliariumPools);
        mockGaugeRegistry = new MockGaugeRegistry();

        tvlOracle = new TVLOracle(
            IVaultExplorer(address(vault)),
            bodenseePool,
            address(svZchf),
            address(awpf),
            address(this),
            new address[](0),
            new address[](0)
        );

        emaSampler = new EMASampler(tvlOracle);

        ccbMultiplier = new CCBMultiplier(miliariumRegistry, IEMASampler(address(emaSampler)), mockGaugeRegistry);

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
        emissionDistributor.setAuMTContractForPool(pilotPools[0], address(this)); // H6.3 + I-D9 — recorder impersonation; test contract drives recordDeposit/recordWithdrawal across all 3 pilot pools
        emissionDistributor.setAuMTContractForPool(pilotPools[1], address(this));
        emissionDistributor.setAuMTContractForPool(pilotPools[2], address(this));

        // K7.4b (K-D7) router unification — one AuMMMinterRouter holds AuMM's C-D11 one-shot minter slot; both consumers allowlisted via setMintRouter while governance is still address(this), before any setGovernanceContract handoff
        minterRouter = new AuMMMinterRouter(IAuMM(address(aumm)), address(bootstrapChannel), address(emissionDistributor));
        aumm.setMinter(address(minterRouter));
        bootstrapChannel.setMintRouter(address(minterRouter));
        emissionDistributor.setMintRouter(address(minterRouter));
        // incendiaryRegistry stays address(0) per H-D29 zero-stub (slot default — no setter call required; F-7 Step 1 Incendiary skim collapses to 0 per H5.1c continuous-leg short-circuit)
    }
}

/**
 * @title StageHBootstrapPhaseTest
 * @notice Fork-level exercise of BodenseeBootstrapChannel.accrue() against the real Bodensee + real AuMM stack.
 *         Covers: F-0/F-1 bootstrap arc; accrue() cadence across Bootstrap A (80→50%) + Bootstrap B (50→0%);
 *         H-D11 AP closed-form identity; pendingAccrual conservation invariant pre-distribute.
 *         Minter wiring: AuMM's sole minter is the fixture's `AuMMMinterRouter` (bound in `super.setUp` per
 *         K7.4b/K-D7) — `bootstrapChannel` mints via `mintRouter.mintFor` as an allowlisted consumer.
 *         `setGovernanceContract(GOVERNANCE_MULTISIG)` runs after the fixture's `setMintRouter` wiring,
 *         preserving the K-D7 wire-before-handoff order. The distribute() arc + sad-path pair land separately at H9.3.
 *         Anchors: H-D11, H-D37, H-D38(1), C-D11.
 */
contract StageHBootstrapPhaseTest is StageHIntegrationFixture {
    function setUp() public override {
        super.setUp();
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
        vm.roll(AureumTime.year1EndBlock(aumm.GENESIS_BLOCK()) + 1);
        gaugeRegistry.seedFoundingPool(pilotPools[0]);
        gaugeRegistry.seedFoundingPool(pilotPools[1]);
        gaugeRegistry.seedFoundingPool(pilotPools[2]);
        vm.store(address(emaSampler), keccak256(abi.encode(pilotPools[0], uint256(0))), bytes32(uint256(1e18)));
        vm.store(address(emaSampler), keccak256(abi.encode(pilotPools[1], uint256(0))), bytes32(uint256(1e18)));
        vm.store(address(emaSampler), keccak256(abi.encode(pilotPools[2], uint256(0))), bytes32(uint256(1e18)));
        // F-10 gate: emaSeedBlock=1 (slot 2, ancient → mature) + lastEMAUpdateBlock=block.number (slot 1, fresh) so recordScore's _gatedTvlEMA passes
        vm.store(address(emaSampler), keccak256(abi.encode(pilotPools[0], uint256(2))), bytes32(uint256(1)));
        vm.store(address(emaSampler), keccak256(abi.encode(pilotPools[1], uint256(2))), bytes32(uint256(1)));
        vm.store(address(emaSampler), keccak256(abi.encode(pilotPools[2], uint256(2))), bytes32(uint256(1)));
        vm.store(address(emaSampler), keccak256(abi.encode(pilotPools[0], uint256(1))), bytes32(block.number));
        vm.store(address(emaSampler), keccak256(abi.encode(pilotPools[1], uint256(1))), bytes32(block.number));
        vm.store(address(emaSampler), keccak256(abi.encode(pilotPools[2], uint256(1))), bytes32(block.number));
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

/**
 * @title StageHHalvingBoundaryTest
 * @notice Fork-level 20-block straddle of `AureumTime.firstHalvingBlock` exercising the H-D30 era cursor walk
 *         against real AuMM `blockEmissionRate` halved-rate response + real `_lpTrancheIntegral`. Single pilot
 *         (pilotPools[0]) / single user / 100% LP share so all 14.5e18 wei flow to one address — mirrors the
 *         H6.3c unit-test arithmetic `9 × 1e18 + 11 × 5e17 = 14.5e18` exact against the production
 *         EmissionDistributor stack. Zero-stub `incendiaryRegistry == address(0)` per H-D29 short-circuits F-7
 *         Step 1 Incendiary skim so `_lpTrancheIntegral` returns `rate × n` per era sub-interval — `9 × 1e18`
 *         from Era 0 sub-interval `[firstHalving-9, firstHalving-1]` plus `11 × 5e17` from Era 1 sub-interval
 *         `[firstHalving, firstHalving+10]` = `14.5e18` exact. Strategy A white-box state seed: `seedFoundingPool`
 *         for gauge approval; `vm.store` for `emaSampler.tvlEMA[pilot]` slot 0.
 *         Anchors: H-D17, H-D20, H-D26, H-D29, H-D30, H-D31, H-D32, H-D33, H-D37, H-D38(3), H6.3c, F-7, OQ-5.
 */
contract StageHHalvingBoundaryTest is StageHIntegrationFixture {
    function setUp() public override {
        super.setUp();
        gaugeRegistry.seedFoundingPool(pilotPools[0]);
        vm.store(address(emaSampler), keccak256(abi.encode(pilotPools[0], uint256(0))), bytes32(uint256(1e18)));
        // F-10 gate: emaSeedBlock=1 (slot 2, ancient → mature); freshness is stamped in the test after the roll to firstHalving-10
        vm.store(address(emaSampler), keccak256(abi.encode(pilotPools[0], uint256(2))), bytes32(uint256(1)));
    }

    /// @notice H-D30 era cursor walk across firstHalvingBlock: `_lpTrancheIntegral` splits into Era 0 sub-interval (9 blocks × 1e18) + Era 1 sub-interval (11 blocks × 5e17) = 14.5e18; real AuMM `blockEmissionRate` halved-rate sanity asserts confirm OQ-5 piecewise-constant schedule.
    function test_ClaimAcrossHalvingBoundary_UsesRealBlockEmissionRate() public {
        uint256 firstHalving = AureumTime.firstHalvingBlock(aumm.GENESIS_BLOCK());
        assertEq(aumm.blockEmissionRate(firstHalving - 1), 1e18, "pre-halving Era 0 rate");
        assertEq(aumm.blockEmissionRate(firstHalving), 5e17, "post-halving Era 1 rate");
        vm.roll(firstHalving - 10);
        // F-10 gate: stamp lastEMAUpdateBlock=block.number (slot 1, fresh) at the recordScore block firstHalving-10
        vm.store(address(emaSampler), keccak256(abi.encode(pilotPools[0], uint256(1))), bytes32(block.number));
        address user = makeAddr("h95_user");
        emissionDistributor.recordScore(pilotPools[0]);
        emissionDistributor.recordDeposit(pilotPools[0], user, 100e18);
        vm.roll(firstHalving + 10);
        vm.expectEmit(true, true, true, true);
        emit IEmissionDistributor.Claimed(pilotPools[0], user, user, 14.5e18);
        vm.prank(user);
        emissionDistributor.claim(pilotPools[0], user);
        assertEq(aumm.balanceOf(user), 14.5e18, "halving boundary mint = 9 x 1e18 + 11 x 5e17");
    }
}

/**
 * @title StageHCrossStackTest
 * @notice End-to-end cross-stack validation per H-D38(4): real gauge approval chain (VaultClassRegistry /
 *         GaugeEligibility / GaugeRegistry) → real TVLOracle / EMASampler push → continuous-phase
 *         recordScore / recordDeposit / claim → aumm.balanceOf(user) > 0.
 * @dev Strategy B TVL seed — `setTokenUnderlying` self-maps each pilot token to svZCHF in setUp so the
 *      _constellationRatio identity yields tvl(pilot) = sum of balancesLiveScaled18. Side-effect-only
 *      SwapAndDepositToBodensee invocation via `_approveAndActivate` ANTI_SPAM_FEE routing from the
 *      inherited StageGIntegrationFixture helper. F-D15 EMASampler cold-start seed via `emaSampler.updateEMA`
 *      (no vm.store bypass). Alpha = 1e18 continuous regime via vm.roll past year1EndBlock. Binary
 *      positive-balance assertion — not a numeric identity per H-D38(4).
 *      Anchors: H-D29, H-D33, H-D37, H-D38(4), F-D15.
 */
contract StageHCrossStackTest is StageHIntegrationFixture {
    function setUp() public override {
        super.setUp();
        IERC20[] memory ptokens = vault.getPoolTokens(pilotPools[0]);
        for (uint256 i = 0; i < ptokens.length; ++i) {
            tvlOracle.setTokenUnderlying(address(ptokens[i]), address(svZchf));
        }
    }

    /// @notice H-D38(4) cross-stack: real gauge approval chain → F-D15 EMASampler cold-start seed → continuous-phase claim → binary positive-balance assertion confirms end-to-end emission flow without numeric identity pinning.
    function test_CrossStack_GaugeApprovalToClaim_MintsAuMM() public {
        _makePoolEligible(pilotPools[0], 50_000e18);
        address[] memory pools = new address[](1);
        pools[0] = pilotPools[0];
        _warmupTournament(pools);
        _approveAndActivate(address(this), pilotPools[0], gaugeRegistry.ANTI_SPAM_FEE());
        assertTrue(gaugeRegistry.isGaugeApproved(pilotPools[0]), "gauge approved post-activate");

        emaSampler.updateEMA(pilotPools[0]);
        assertGt(emaSampler.tvlEMA(pilotPools[0]), 0, "tvlEMA seeded > 0 from real TVLOracle");

        vm.roll(AureumTime.year1EndBlock(aumm.GENESIS_BLOCK()) + 1);
        // F-10 gate: a second real updateEMA refreshes lastEMAUpdateBlock to the post-roll block (fresh); the early first seed keeps emaSeedBlock mature — no vm.store, stays on the real path per H-D38(4)
        emaSampler.updateEMA(pilotPools[0]);

        address user = makeAddr("h96_user");
        emissionDistributor.recordScore(pilotPools[0]);
        emissionDistributor.recordDeposit(pilotPools[0], user, 100e18);
        vm.roll(block.number + 300);
        vm.prank(user);
        emissionDistributor.claim(pilotPools[0], user);

        assertGt(aumm.balanceOf(user), 0, "cross-stack mint > 0");
    }
}

/**
 * @title StageHTwoHopFallbackTest
 * @notice PB-D7 / OQ-22 Phase 2 fork witness — real-stack USDC pricing via USDS hop with Bodensee as hop-2 venue.
 * @dev H-D38(4) binary-assertion posture: arithmetic exactness lives in test/unit/TVLOracle.t.sol; this witness
 *      proves real-stack wiring — mainnet-fork Vault, real USDC, real sUSDS with `susds.asset()` as the USDS hop key,
 *      Bodensee as the hop-2 venue, EMASampler propagation.
 */
contract StageHTwoHopFallbackTest is StageHIntegrationFixture {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    bytes32 internal constant HOP_VENUE_SALT = bytes32(uint256(0x2207));

    address internal hopVenue;
    address internal usds;

    function setUp() public override {
        super.setUp();

        usds = susds.asset();

        tvlOracle.setTokenUnderlying(address(svZchf), address(svZchf));
        tvlOracle.setTokenUnderlying(address(susds), usds);
        tvlOracle.setTokenUnderlying(USDC, USDC);

        address[2] memory addrs;
        addrs[0] = USDC;
        addrs[1] = address(susds);
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

        hopVenue = wpf.create(
            "usdc-susds-hop-venue",
            "HOPV",
            configs,
            weights,
            PoolRoleAccounts({pauseManager: GOVERNANCE_MULTISIG, swapFeeManager: address(0), poolCreator: address(0)}),
            0.003e18,
            address(0),
            true,
            false,
            HOP_VENUE_SALT
        );

        IERC20[] memory vTokens = vault.getPoolTokens(hopVenue);
        uint256[] memory amts = new uint256[](2);
        for (uint256 i = 0; i < vTokens.length; i++) {
            amts[i] = address(vTokens[i]) == USDC ? 1_000e6 : 1_000e18;
        }
        _initializePool(hopVenue, vTokens, amts);

        tvlOracle.addConstellationPool(hopVenue);
        tvlOracle.addConstellationPool(bodenseePool);
    }

    function test_Fork_TwoHop_UsdcPricesViaUsdsHop_PropagatesToEMA() public {
        assertEq(tvlOracle.quoteSvZCHF(USDC, 1_000e18), 0, "Phase-1 direct-miss: USDC unpriced pre-seed");
        uint256 tvlBefore = tvlOracle.tvl(hopVenue);
        assertGt(tvlBefore, 0, "sUSDS leg prices direct via Bodensee pre-seed");
        tvlOracle.addHopUnderlying(usds);
        assertGt(tvlOracle.quoteSvZCHF(USDC, 1_000e18), 0, "USDC priced via USDS hop post-seed");
        uint256 tvlAfter = tvlOracle.tvl(hopVenue);
        assertGt(tvlAfter, tvlBefore, "venue TVL gains the hopped USDC leg");
        emaSampler.updateEMA(hopVenue);
        assertGt(emaSampler.tvlEMA(hopVenue), tvlBefore, "F-D15 cold-start EMA carries the hop-inclusive spot");
    }

    function test_Fork_TwoHop_AddHopUnderlyingAuthGate() public {
        address stranger = makeAddr("hop_stranger");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TVLOracle.NotGovernance.selector, stranger));
        tvlOracle.addHopUnderlying(usds);
    }
}
