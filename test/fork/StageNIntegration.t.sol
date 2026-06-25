// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { StageIIntegrationFixture } from "./StageIIntegration.t.sol";
import { DeployStageN } from "../../script/DeployStageN.s.sol";
import { MiliariumRegistry } from "../../src/registry/MiliariumRegistry.sol";
import { ERC4626RateProvider } from "../../src/rate_provider/ERC4626RateProvider.sol";
import { CompositeRateProvider } from "../../src/rate_provider/CompositeRateProvider.sol";
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
        for (uint256 i = 0; i < stageNPools.length; i++) {
            _makePoolEligible(stageNPools[i], 50_000e18);
            assertTrue(gaugeEligibility.evaluateEligibility(stageNPools[i]), "QG not cleared");
            assertTrue(gaugeEligibility.isEligible(stageNPools[i]), "not eligible after evaluate");
        }
    }
}
