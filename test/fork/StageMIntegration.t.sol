// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { StageIIntegrationFixture } from "./StageIIntegration.t.sol";
import { DeployStageM } from "../../script/DeployStageM.s.sol";
import { MiliariumRegistry } from "../../src/registry/MiliariumRegistry.sol";
import { DeployIxCasper } from "../../script/pools/DeployIxCasper.s.sol";
import { DeployIxBrevis } from "../../script/pools/DeployIxBrevis.s.sol";
import { DeployIxAltrix } from "../../script/pools/DeployIxAltrix.s.sol";
import { DeployIxMediox } from "../../script/pools/DeployIxMediox.s.sol";
import { DeployIxLongus } from "../../script/pools/DeployIxLongus.s.sol";
import { TokenInfo } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { CompositeRateProvider } from "../../src/rate_provider/CompositeRateProvider.sol";
import { IxCasperConfig } from "../../script/pools/configs/03_ixCasper.s.sol";

/**
 * @title StageMIntegrationFixture
 * @notice Stage M fork-test base — inherits the H13-safe `StageIIntegrationFixture`
 *         (real vault + factory + AuMM + Bodensee + three pilots + hook + GaugeRegistry +
 *         EmissionDistributor), deploys a fresh real `MiliariumRegistry` seeded at manifest
 *         slots `[1, 5, 14]`, deploys the five Stage M Majors via their M3 `DeployIx*.run()`
 *         wrappers, env-wires the `DeployStageM` inputs, and runs
 *         `DeployStageM.deploy(address(this))` to bind each Major as a founding pool.
 *
 * @dev Run with:
 *
 *        forge test --match-path "test/fork/StageMIntegration.t.sol" \
 *          --fork-url $MAINNET_RPC_URL --threads 1 -vv
 *
 *      Per D35 split-form + D36 `--threads 1` belt.
 *
 * @dev Fresh real registry — the inherited `miliariumRegistry` is a `MockMiliariumRegistry`
 *      (StageI L37) and `DeployStageM.replaceSlot` needs the real `MiliariumRegistry` with
 *      slots 03/08/09/10/11 empty. The `DeployStageK.t.sol:73-85` pattern: stand up
 *      `new MiliariumRegistry(address(this), [1,5,14], [pilots])` in setUp and pass that
 *      address as `MILIARIUM_REGISTRY` to the bind script.
 */
abstract contract StageMIntegrationFixture is StageIIntegrationFixture {
    MiliariumRegistry internal realRegistry;
    DeployStageM internal deployStageMScript;
    uint256[5] internal majorSlots;
    address[5] internal majorPools;
    /// @dev Canonical Balancer wstETH RP (`stEthPerToken`) — hop 2 of the PB-D8 waEthwstETH composite; fixture-local literal, RP-plumbing only, never a pool token.
    address internal constant WSTETH_RATE_PROVIDER = 0x72D07D7DcA67b8A406aD1Ec34ce969c90bFEE768;

    function setUp() public virtual override {
        super.setUp();

        // (1) Fresh real MiliariumRegistry — seeded at manifest slots [1, 5, 14] with the three
        //     pilots, governanceContract = address(this) so replaceSlot succeeds. Slots
        //     03/08/09/10/11 remain empty for the five Stage M Majors.
        uint256[] memory seedSlots = new uint256[](3);
        seedSlots[0] = 1;
        seedSlots[1] = 5;
        seedSlots[2] = 14;
        address[] memory seedPools = new address[](3);
        seedPools[0] = pilotPools[0];
        seedPools[1] = pilotPools[1];
        seedPools[2] = pilotPools[2];
        realRegistry = new MiliariumRegistry(address(this), seedSlots, seedPools);

        // (2) Canonical slot order for the five Stage M Majors (M-D7).
        majorSlots[0] = 3;
        majorSlots[1] = 8;
        majorSlots[2] = 9;
        majorSlots[3] = 10;
        majorSlots[4] = 11;

        // (3) PB-D8 waEthwstETH composite RP — must precede DeployIxCasper.run() (the config reads
        //     the env key during .run()). Chains waEthwstETH `previewRedeem` over the canonical
        //     Balancer wstETH RP — the N-D9 ysyBOLD stack pattern.
        CompositeRateProvider waEthwstEthRp = new CompositeRateProvider(IERC4626(IxCasperConfig.WAETHWSTETH), IRateProvider(WSTETH_RATE_PROVIDER));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("WAETHWSTETH_COMPOSITE_RATE_PROVIDER", vm.toString(address(waEthwstEthRp)));

        // (4) Deploy the five Majors via M3 wrappers (default-sender .run() pattern).
        majorPools[0] = new DeployIxCasper().run();
        majorPools[1] = new DeployIxBrevis().run();
        majorPools[2] = new DeployIxAltrix().run();
        majorPools[3] = new DeployIxMediox().run();
        majorPools[4] = new DeployIxLongus().run();

        // (5) Env vars — the nine bind-path vars DeployStageM._bind() reads.
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_REGISTRY", vm.toString(address(realRegistry)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("GAUGE_REGISTRY", vm.toString(address(gaugeRegistry)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("EMISSION_DISTRIBUTOR", vm.toString(address(emissionDistributor)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("FEE_ROUTING_HOOK", vm.toString(address(hook)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MAJOR_POOL_03", vm.toString(majorPools[0]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MAJOR_POOL_08", vm.toString(majorPools[1]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MAJOR_POOL_09", vm.toString(majorPools[2]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MAJOR_POOL_10", vm.toString(majorPools[3]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MAJOR_POOL_11", vm.toString(majorPools[4]));

        // (6) Bind the five Majors as founding pools; any revert reverts setUp.
        deployStageMScript = new DeployStageM();
        deployStageMScript.deploy(address(this));
    }
}

contract StageMWiringTest is StageMIntegrationFixture {
    function test_setUp_fiveMajorsBoundToSlots() public view {
        for (uint256 i = 0; i < majorPools.length; i++) {
            assertTrue(majorPools[i] != address(0), "major unset");
            assertEq(realRegistry.poolAtSlot(majorSlots[i]), majorPools[i], "slot not bound");
        }
    }
}

contract StageMBindingLivenessTest is StageMIntegrationFixture {
    function test_registryBindings_slotEnumAndMembership() public view {
        for (uint256 i = 0; i < majorPools.length; i++) {
            assertEq(realRegistry.poolAtSlot(majorSlots[i]), majorPools[i], "slot not bound");
            assertEq(realRegistry.slotOf(majorPools[i]), majorSlots[i], "slotOf mismatch");
            assertTrue(realRegistry.isMiliarium(majorPools[i]), "not enumerated");
        }
    }

    function test_gaugeFoundingSeed_allFiveActive() public view {
        for (uint256 i = 0; i < majorPools.length; i++) {
            assertTrue(gaugeRegistry.isGaugeApproved(majorPools[i]), "gauge not founding-seeded");
        }
    }

    function test_distributorRecorder_boundToHook() public view {
        for (uint256 i = 0; i < majorPools.length; i++) {
            assertEq(emissionDistributor.auMTContractByPool(majorPools[i]), address(hook), "recorder not bound");
        }
    }

    function test_hookAttached_feeRoutingHook() public view {
        for (uint256 i = 0; i < majorPools.length; i++) {
            assertEq(vault.getHooksConfig(majorPools[i]).hooksContract, address(hook), "hook not attached");
        }
    }

    function test_rateProvidersResolve_nonzeroGetRate() public view {
        for (uint256 i = 0; i < majorPools.length; i++) {
            (, TokenInfo[] memory ti, , ) = vault.getPoolTokenInfo(majorPools[i]);
            for (uint256 j = 0; j < ti.length; j++) {
                if (address(ti[j].rateProvider) != address(0)) {
                    assertGt(ti[j].rateProvider.getRate(), 0, "rate provider did not resolve");
                }
            }
        }
    }

    function test_qualityGate_allFiveMajorsEligible() public {
        for (uint256 i = 0; i < majorPools.length; i++) {
            _makePoolEligible(majorPools[i], 50_000e18);
            assertTrue(gaugeEligibility.evaluateEligibility(majorPools[i]), "QG not cleared");
            assertTrue(gaugeEligibility.isEligible(majorPools[i]), "not eligible after evaluate");
        }
    }
}
