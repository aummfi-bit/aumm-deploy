// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { StageIIntegrationFixture } from "./StageIIntegration.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DeployStageN } from "../../script/DeployStageN.s.sol";
import { MiliariumRegistry } from "../../src/registry/MiliariumRegistry.sol";
import { ERC4626RateProvider } from "../../src/rate_provider/ERC4626RateProvider.sol";
import { CompositeRateProvider } from "../../src/rate_provider/CompositeRateProvider.sol";
import { GaugeEligibility } from "../../src/gauge/GaugeEligibility.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IxAetheronConfig } from "../../script/pools/configs/02_ixAetheron.s.sol";
import { IxLibertasConfig } from "../../script/pools/configs/06_ixLibertas.s.sol";
import { DeployIxAetheron } from "../../script/pools/DeployIxAetheron.s.sol";
import { DeployIxLibertas } from "../../script/pools/DeployIxLibertas.s.sol";
import { DeployIxStrata } from "../../script/pools/DeployIxStrata.s.sol";
import { DeployIxForum } from "../../script/pools/DeployIxForum.s.sol";
import { DeployIxRegistrum } from "../../script/pools/DeployIxRegistrum.s.sol";
import { DeployIxDebitum } from "../../script/pools/DeployIxDebitum.s.sol";
import { DeployIxEquitix } from "../../script/pools/DeployIxEquitix.s.sol";
import { DeployIxInnovix } from "../../script/pools/DeployIxInnovix.s.sol";
import { DeployIxGigantus } from "../../script/pools/DeployIxGigantus.s.sol";
import { DeployIxMagnix } from "../../script/pools/DeployIxMagnix.s.sol";
import { DeployIxNubix } from "../../script/pools/DeployIxNubix.s.sol";
import { DeployIxMoneta } from "../../script/pools/DeployIxMoneta.s.sol";
import { DeployIxColossix } from "../../script/pools/DeployIxColossix.s.sol";
import { DeployIxVitalix } from "../../script/pools/DeployIxVitalix.s.sol";
import { DeployIxMedicix } from "../../script/pools/DeployIxMedicix.s.sol";
import { DeployIxMercatura } from "../../script/pools/DeployIxMercatura.s.sol";
import { DeployIxAurix } from "../../script/pools/DeployIxAurix.s.sol";
import { DeployIxMetallum } from "../../script/pools/DeployIxMetallum.s.sol";
import { TokenInfo } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

/**
 * @title StageNIntegrationFixture
 * @notice Stage N fork-test base — inherits the H13-safe `StageIIntegrationFixture`
 *         (real vault + factory + AuMM + Bodensee + three pilots + hook + GaugeRegistry +
 *         EmissionDistributor), deploys a fresh real `MiliariumRegistry` seeded at manifest
 *         slots `[1, 5, 14]`, deploys the eighteen Stage N pools via their `DeployIx*.run()`
 *         wrappers, env-wires the `DeployStageN` inputs, and runs
 *         `DeployStageN.deploy(address(this))` to bind each pool as a founding pool.
 *
 * @dev Run with:
 *
 *        forge test --match-path "test/fork/StageNIntegration.t.sol" \
 *          --fork-url $MAINNET_RPC_URL --threads 1 -vv
 *
 *      Per D35 split-form + D36 `--threads 1` belt.
 *
 * @dev Fresh real registry — the inherited `miliariumRegistry` is a `MockMiliariumRegistry`
 *      (StageI L37) and `DeployStageN.replaceSlot` needs the real `MiliariumRegistry` with
 *      slots 02/06/12/13/15–28 empty. The `DeployStageK.t.sol:73-85` pattern: stand up
 *      `new MiliariumRegistry(address(this), [1,5,14], [pilots])` in setUp and pass that
 *      address as `MILIARIUM_REGISTRY` to the bind script.
 */
abstract contract StageNIntegrationFixture is StageIIntegrationFixture {
    // N-D9 RP-plumbing literals (verified mainnet). yBOLD is the two-hop intermediary only — never a
    // pool token; ysyBOLD is a pool constituent only via the 06/20/27 config libs, declared here for RP wiring.
    address internal constant YSYBOLD = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
    address internal constant YBOLD = 0x9F4330700a36B29952869fac9b33f45EEdd8A3d8;

    MiliariumRegistry internal realRegistry;
    DeployStageN internal deployStageNScript;
    uint256[18] internal stageNSlots;
    address[18] internal stageNPools;

    function setUp() public virtual override {
        super.setUp();

        // (1) Fresh real MiliariumRegistry — seeded at manifest slots [1, 5, 14] with the three
        //     pilots, governanceContract = address(this) so replaceSlot succeeds. Slots
        //     02/06/12/13/15–28 remain empty for the eighteen Stage N pools.
        uint256[] memory seedSlots = new uint256[](3);
        seedSlots[0] = 1;
        seedSlots[1] = 5;
        seedSlots[2] = 14;
        address[] memory seedPools = new address[](3);
        seedPools[0] = pilotPools[0];
        seedPools[1] = pilotPools[1];
        seedPools[2] = pilotPools[2];
        realRegistry = new MiliariumRegistry(address(this), seedSlots, seedPools);

        // (2) Deploy the four ERC4626RateProvider instances + the one N-D9 CompositeRateProvider, and
        //     env-wire their keys — must precede the 02/06/20/27 DeployIx*.run() calls (those configs
        //     read the env keys during .run()). The ysyBOLD core is a two-hop chain (N-D9): an inner
        //     ERC4626RateProvider(yBOLD) for the yBOLD-to-BOLD hop, wrapped by a CompositeRateProvider
        //     over ysyBOLD. Replaces the prior dead-rate sfrxUSD core per the N6 RP-watch.
        ERC4626RateProvider sfrxEthRp = new ERC4626RateProvider(IERC4626(IxAetheronConfig.SFRXETH));
        ERC4626RateProvider wOethRp = new ERC4626RateProvider(IERC4626(IxAetheronConfig.WOETH));
        ERC4626RateProvider scrvUsdRp = new ERC4626RateProvider(IERC4626(IxLibertasConfig.SCRVUSD));
        ERC4626RateProvider yBoldRp = new ERC4626RateProvider(IERC4626(YBOLD));
        CompositeRateProvider ysyBoldRp = new CompositeRateProvider(IERC4626(YSYBOLD), yBoldRp);
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("SFRXETH_RATE_PROVIDER", vm.toString(address(sfrxEthRp)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("WOETH_RATE_PROVIDER", vm.toString(address(wOethRp)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("SCRVUSD_RATE_PROVIDER", vm.toString(address(scrvUsdRp)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("YSYBOLD_RATE_PROVIDER", vm.toString(address(ysyBoldRp)));

        // (3) Canonical slot order for the eighteen Stage N pools (N-D0).
        stageNSlots[0] = 2;
        stageNSlots[1] = 6;
        stageNSlots[2] = 12;
        stageNSlots[3] = 13;
        stageNSlots[4] = 15;
        stageNSlots[5] = 16;
        stageNSlots[6] = 17;
        stageNSlots[7] = 18;
        stageNSlots[8] = 19;
        stageNSlots[9] = 20;
        stageNSlots[10] = 21;
        stageNSlots[11] = 22;
        stageNSlots[12] = 23;
        stageNSlots[13] = 24;
        stageNSlots[14] = 25;
        stageNSlots[15] = 26;
        stageNSlots[16] = 27;
        stageNSlots[17] = 28;

        // (4) Deploy the eighteen pools via DeployIx*.run() wrappers (default-sender pattern).
        stageNPools[0] = new DeployIxAetheron().run();
        stageNPools[1] = new DeployIxLibertas().run();
        stageNPools[2] = new DeployIxStrata().run();
        stageNPools[3] = new DeployIxForum().run();
        stageNPools[4] = new DeployIxRegistrum().run();
        stageNPools[5] = new DeployIxDebitum().run();
        stageNPools[6] = new DeployIxEquitix().run();
        stageNPools[7] = new DeployIxInnovix().run();
        stageNPools[8] = new DeployIxGigantus().run();
        stageNPools[9] = new DeployIxMagnix().run();
        stageNPools[10] = new DeployIxNubix().run();
        stageNPools[11] = new DeployIxMoneta().run();
        stageNPools[12] = new DeployIxColossix().run();
        stageNPools[13] = new DeployIxVitalix().run();
        stageNPools[14] = new DeployIxMedicix().run();
        stageNPools[15] = new DeployIxMercatura().run();
        stageNPools[16] = new DeployIxAurix().run();
        stageNPools[17] = new DeployIxMetallum().run();

        // (5) Env vars — the twenty-three bind-path vars DeployStageN._bind() reads.
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_REGISTRY", vm.toString(address(realRegistry)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("GAUGE_REGISTRY", vm.toString(address(gaugeRegistry)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("EMISSION_DISTRIBUTOR", vm.toString(address(emissionDistributor)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("FEE_ROUTING_HOOK", vm.toString(address(hook)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_02", vm.toString(stageNPools[0]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_06", vm.toString(stageNPools[1]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_12", vm.toString(stageNPools[2]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_13", vm.toString(stageNPools[3]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_15", vm.toString(stageNPools[4]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_16", vm.toString(stageNPools[5]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_17", vm.toString(stageNPools[6]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_18", vm.toString(stageNPools[7]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_19", vm.toString(stageNPools[8]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_20", vm.toString(stageNPools[9]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_21", vm.toString(stageNPools[10]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_22", vm.toString(stageNPools[11]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_23", vm.toString(stageNPools[12]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_24", vm.toString(stageNPools[13]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_25", vm.toString(stageNPools[14]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_26", vm.toString(stageNPools[15]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_27", vm.toString(stageNPools[16]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_28", vm.toString(stageNPools[17]));

        // (6) Bind the eighteen pools as founding pools; any revert reverts setUp.
        deployStageNScript = new DeployStageN();
        deployStageNScript.deploy(address(this));
    }
}

contract StageNWiringTest is StageNIntegrationFixture {
    function test_setUp_eighteenPoolsBoundToSlots() public view {
        for (uint256 i = 0; i < stageNPools.length; i++) {
            assertTrue(stageNPools[i] != address(0), "pool unset");
            assertEq(realRegistry.poolAtSlot(stageNSlots[i]), stageNPools[i], "slot not bound");
        }
    }
}

contract StageNBindingLivenessTest is StageNIntegrationFixture {
    function test_registryBindings_slotEnumAndMembership() public view {
        for (uint256 i = 0; i < stageNPools.length; i++) {
            assertEq(realRegistry.poolAtSlot(stageNSlots[i]), stageNPools[i], "slot not bound");
            assertEq(realRegistry.slotOf(stageNPools[i]), stageNSlots[i], "slotOf mismatch");
            assertTrue(realRegistry.isMiliarium(stageNPools[i]), "not enumerated");
        }
    }

    function test_gaugeFoundingSeed_allActive() public view {
        for (uint256 i = 0; i < stageNPools.length; i++) {
            assertTrue(gaugeRegistry.isGaugeApproved(stageNPools[i]), "gauge not founding-seeded");
        }
    }

    function test_distributorRecorder_boundToHook() public view {
        for (uint256 i = 0; i < stageNPools.length; i++) {
            assertEq(emissionDistributor.auMTContractByPool(stageNPools[i]), address(hook), "recorder not bound");
        }
    }

    function test_hookAttached_feeRoutingHook() public view {
        for (uint256 i = 0; i < stageNPools.length; i++) {
            assertEq(vault.getHooksConfig(stageNPools[i]).hooksContract, address(hook), "hook not attached");
        }
    }

    function test_rateProvidersResolve_nonzeroGetRate() public view {
        for (uint256 i = 0; i < stageNPools.length; i++) {
            (, TokenInfo[] memory ti, , ) = vault.getPoolTokenInfo(stageNPools[i]);
            for (uint256 j = 0; j < ti.length; j++) {
                if (address(ti[j].rateProvider) != address(0)) {
                    assertGt(ti[j].rateProvider.getRate(), 0, "rate provider did not resolve");
                }
            }
        }
    }

    function test_qualityGate_allEighteenEligible() public {
        // PB3.12e-pre: stageNPools[0] is real ixAetheron, rail-less; admit it here so the loop keeps testing the gate.
        gaugeEligibility.setRecoveryPathAdmitted(stageNPools[0], true);
        for (uint256 i = 0; i < stageNPools.length; i++) {
            _makePoolEligible(stageNPools[i], 50_000e18);
            assertTrue(gaugeEligibility.evaluateEligibility(stageNPools[i]), "QG not cleared");
            assertTrue(gaugeEligibility.isEligible(stageNPools[i]), "not eligible after evaluate");
        }
    }
}

/// @notice PB3.12e — the PB-D69 mainnet-fork witness over the REAL 02 ixAetheron, admitted and then revoked.
/// @dev The only place in the tree where the conjunct meets a genuinely rail-less pool produced by the real
///      AureumFeeRoutingHook.onRegister rather than by a mock. stageNPools[0] is ixAetheron by deploy order,
///      and it is the only one of the twenty-six pool configs carrying neither svZCHF nor sUSDS per PB-D69 (i).
contract StageNIxAetheronAdmissionTest is StageNIntegrationFixture {
    function test_ixAetheron_railLess_admitThenRevoke() public {
        address ixAetheron = stageNPools[0];
        address ixLibertas = stageNPools[1];

        // Premise, asserted first so a later pass means the conjunct moved and not the state: the real
        // onRegister left ixAetheron with no rail, while a sUSDS-carrying sibling got one.
        assertEq(hook.poolBodenseeDepositToken(ixAetheron), address(0), "ixAetheron must be rail-less");
        assertTrue(hook.poolBodenseeDepositToken(ixLibertas) != address(0), "control pool must carry a rail");

        _makePoolEligible(ixAetheron, 50_000e18);
        assertFalse(gaugeEligibility.recoveryPathAdmitted(ixAetheron));

        // Unadmitted: the ACTIVATION path rejects. The composition gate no longer evaluates the
        // conjunct — PP-D50 (x) moved that to AureumGovernance.proposeCompositionChallenge — so the
        // gate passes, and feeRailConjunctSatisfied is what now reports the pool's true state.
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.NoFeeRailAndNotAdmitted.selector, ixAetheron));
        gaugeEligibility.evaluateEligibility(ixAetheron);
        assertFalse(gaugeEligibility.feeRailConjunctSatisfied(ixAetheron), "false for the real rail-less pool");
        assertTrue(gaugeEligibility.meetsCompositionQualityGate(ixAetheron), "the gate itself no longer reads it");

        // Admitted: the ops attestation is the only thing that changed, and it is sufficient.
        gaugeEligibility.setRecoveryPathAdmitted(ixAetheron, true);
        assertTrue(gaugeEligibility.feeRailConjunctSatisfied(ixAetheron));
        assertTrue(gaugeEligibility.evaluateEligibility(ixAetheron));
        assertTrue(gaugeEligibility.isEligible(ixAetheron));
        assertTrue(gaugeRegistry.isGaugeApproved(ixAetheron), "premise - founding-seeded, so already Active");

        // Withdrawn: PP-D50 (xii) SCHEDULES rather than revokes, so nothing has changed yet.
        gaugeEligibility.setRecoveryPathAdmitted(ixAetheron, false);
        assertTrue(gaugeEligibility.feeRailConjunctSatisfied(ixAetheron), "scheduling alone leaves it true");

        // Finalized: the conjunct lapses and the activation path rejects again.
        vm.roll(gaugeEligibility.revocationEffectiveBlock(ixAetheron));
        gaugeEligibility.finalizeRecoveryPathRevocation(ixAetheron);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.NoFeeRailAndNotAdmitted.selector, ixAetheron));
        gaugeEligibility.evaluateEligibility(ixAetheron);
        assertTrue(gaugeEligibility.isEligible(ixAetheron), "the certificate latch still survives - that is D.7, its own row");

        // C.6 real-pool pin, INVERTED at PP4.8: the withdrawn attestation now demotes the gauge, on
        // the protocol's one genuinely rail-less pool. ixAetheron is founding-seeded via
        // seedFoundingPool and never went through evaluateEligibility, so this pins the demotion
        // half against real state rather than against a fixture.
        vm.prank(makeAddr("c6_hygiene_stageN"));
        gaugeRegistry.revokeGaugeIfIneligible(ixAetheron);
        assertFalse(gaugeRegistry.isGaugeApproved(ixAetheron), "C.6 - revocation now demotes the live gauge");
    }
}

/// @notice PB3.10d — the PB-D66 rung-d mainnet-fork witness: a stranded LST recovered
///         along the literal clause (vii) route, LST to ixEDEL on ixAetheron and ixEDEL
///         to svZCHF on ixEdelweiss, terminating in a donation to der Bodensee.
/// @dev `governanceModule` is already seated to `address(this)` at StageIIntegration
///      L102-L103, one-shot and inherited down the G-I-K-N chain, so this contract IS
///      the module and calls the entry directly with no prank and no second seating.
///      `stageNPools[0]` is ixAetheron by deploy order; StageN registers it but seeds
///      it in no fixture, so hop 1 is given depth here through the inherited
///      `_initializePool`, which uses the two-argument `deal` form per E10.
contract StageNStrandedFeeRecoveryTest is StageNIntegrationFixture {
    uint256 internal constant HOP_SEED = 1_000e18;

    uint256 internal constant STRAND = 10e18;

    /// @dev Mirrors the hook's private `_currentBodenseeReserve` read.
    function _bodenseeReserve(IERC20 token) internal view returns (uint256) {
        (, uint256 idx) = vault.getPoolTokenCountAndIndexOfToken(bodenseePool, token);
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(bodenseePool);
        return balancesRaw[idx];
    }

    function _seedIxAetheron() internal {
        IERC20[] memory tokens = vault.getPoolTokens(stageNPools[0]);
        uint256[] memory amts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            amts[i] = HOP_SEED;
        }
        _initializePool(stageNPools[0], tokens, amts);
    }

    function test_recoverStrandedFees_twoHopIxEdelRouteReachesBodensee() public {
        _seedIxAetheron();

        address ixAetheron = stageNPools[0];
        IERC20 sfrxEth = IERC20(IxAetheronConfig.SFRXETH);
        IERC20 ixEdel = IERC20(IxAetheronConfig.IXEDEL);

        // Premise, asserted before the act: ixAetheron genuinely carries no rail, so this
        // strand is unreachable by the hot path and only the recovery entry can clear it.
        assertEq(hook.poolBodenseeDepositToken(ixAetheron), address(0), "ixAetheron is rail-less");
        deal(address(sfrxEth), address(hook), STRAND);
        assertEq(sfrxEth.balanceOf(address(hook)), STRAND, "strand seeded on the hook");

        address[] memory pools = new address[](2);
        pools[0] = ixAetheron;
        pools[1] = pilotPools[1];
        IERC20[] memory outs = new IERC20[](2);
        outs[0] = ixEdel;
        outs[1] = svZchf;
        uint256[] memory mins = new uint256[](2);

        uint256 reserveBefore = _bodenseeReserve(svZchf);
        uint256 supplyBefore = IERC20(bodenseePool).totalSupply();

        hook.recoverStrandedFees(sfrxEth, svZchf, pools, outs, mins);

        assertEq(sfrxEth.balanceOf(address(hook)), 0, "strand fully spent");
        assertEq(IERC20(bodenseePool).totalSupply(), supplyBefore, "donation mints no BPT");
        assertGt(
            _bodenseeReserve(svZchf),
            reserveBefore,
            "PB-D68 (xvii) - reserve rose; exact delta is not a Vault guarantee for rate-bearing rails"
        );
    }
}

