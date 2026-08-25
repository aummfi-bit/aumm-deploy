// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { ForkEnvGuard } from "./ForkEnvGuard.sol";
import { EmissionDistributor } from "../../src/emission/EmissionDistributor.sol";
import { CCBMultiplier } from "../../src/ccb/CCBMultiplier.sol";
import { AureumGovernance } from "../../src/governance/AureumGovernance.sol";
import { AureumGovernanceAuthorizer } from "../../src/governance/AureumGovernanceAuthorizer.sol";
import { VotingWeight } from "../../src/governance/VotingWeight.sol";
import { GaugeRegistry } from "../../src/gauge/GaugeRegistry.sol";
import { GaugeEligibility } from "../../src/gauge/GaugeEligibility.sol";
import { IGaugeRegistry } from "../../src/ccb/IGaugeRegistry.sol";
import { AureumTime } from "../../src/lib/AureumTime.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import {
    TokenConfig,
    TokenType,
    PoolRoleAccounts,
    AddLiquidityParams,
    AddLiquidityKind,
    PoolConfig,
    SwapKind,
    VaultSwapParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

import { AuMM } from "../../src/token/AuMM.sol";
import { AureumFeeRoutingHook } from "../../src/fee_router/AureumFeeRoutingHook.sol";
import { AureumProtocolFeeController } from "../../src/vault/AureumProtocolFeeController.sol";
import { AureumWeightedPoolFactory } from "../../src/factory/AureumWeightedPoolFactory.sol";
import { DeployAureumVault } from "../../script/DeployAureumVault.s.sol";
import { DeployStageP } from "../../script/DeployStageP.s.sol";
import { DeployFeeRoutingHook } from "../../script/DeployFeeRoutingHook.s.sol";
import { DeployAuMM } from "../../script/DeployAuMM.s.sol";
import { DeployAureumWeightedPoolFactory } from "../../script/DeployAureumWeightedPoolFactory.s.sol";
import { ERC4626RateProvider } from "../../src/rate_provider/ERC4626RateProvider.sol";
import { CompositeRateProvider } from "../../src/rate_provider/CompositeRateProvider.sol";
import { IxAetheronConfig } from "../../script/pools/configs/02_ixAetheron.s.sol";
import { IxLibertasConfig } from "../../script/pools/configs/06_ixLibertas.s.sol";
import { IxCasperConfig } from "../../script/pools/configs/03_ixCasper.s.sol";
import { DeployIxHelvetia } from "../../script/pools/DeployIxHelvetia.s.sol";
import { DeployIxEdelweiss } from "../../script/pools/DeployIxEdelweiss.s.sol";
import { DeployIxAurebit } from "../../script/pools/DeployIxAurebit.s.sol";
import { DeployIxCasper } from "../../script/pools/DeployIxCasper.s.sol";
import { DeployIxBrevis } from "../../script/pools/DeployIxBrevis.s.sol";
import { DeployIxAltrix } from "../../script/pools/DeployIxAltrix.s.sol";
import { DeployIxMediox } from "../../script/pools/DeployIxMediox.s.sol";
import { DeployIxLongus } from "../../script/pools/DeployIxLongus.s.sol";
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

/**
 * @title StagePIntegrationFixture
 * @notice P10 base-layer-only fixture per P-D34 — deploys the base layer with
 *         GOVERNANCE_MULTISIG = address(orchestrator) and NO Stage F/G/H/I/J/L/K
 *         contract, NO wiring, NO MiliariumRegistry (those are DeployStageP's job).
 * @dev P-D34 locked ordering; D-D21/D36 hook pre-compute; H13 two-layer consumers
 *      (`StagePWiringTest` + `StagePEndToEndTest`); D35/D36 split-form + `--threads 1`.
 */
abstract contract StagePIntegrationFixture is Test {
    bytes32 internal constant VAULT_SALT = bytes32(uint256(1));
    bytes32 internal constant BODENSEE_SALT = bytes32(uint256(2));
    uint32 internal constant PAUSE_WINDOW_DURATION = uint32(4 * 365 days);
    uint256 internal constant BUFFER_PERIOD_DURATION = 90 days;
    uint256 internal constant MIN_TRADE_AMOUNT = 1_000_000;
    uint256 internal constant MIN_WRAP_AMOUNT = 1_000;
    string internal constant FACTORY_VERSION = '{"name":"AureumWeightedPoolFactory","version":1,"deployment":"20260708-fork-stage-p"}';
    string internal constant POOL_VERSION = '{"name":"AureumWeightedPool","version":1,"deployment":"20260708-fork-stage-p"}';
    address internal constant SUSDS_RATE_PROVIDER = 0x1195BE91e78ab25494C855826FF595Eef784d47B;
    address internal constant SV_ZCHF_RATE_PROVIDER = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;
    uint256 internal constant INIT_SEED = 1_000e18;
    address internal constant EMERGENCY_MULTISIG = address(uint160(uint256(keccak256("emergencyMultisig"))));
    // N-D9 RP-plumbing literals (verified mainnet). yBOLD is the two-hop intermediary only — never a pool token.
    address internal constant YSYBOLD = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
    address internal constant YBOLD = 0x9F4330700a36B29952869fac9b33f45EEdd8A3d8;
    /// @dev Canonical Balancer wstETH RP (`stEthPerToken`) — hop 2 of the PB-D8 waEthwstETH composite; fixture-local literal, RP-plumbing only, never a pool token.
    address internal constant WSTETH_RATE_PROVIDER = 0x72D07D7DcA67b8A406aD1Ec34ce969c90bFEE768;

    DeployStageP internal orchestrator;
    DeployFeeRoutingHook internal hookScript;
    DeployAureumVault internal vaultScript;
    WeightedPoolFactory internal wpf;
    AureumWeightedPoolFactory internal awpf;
    AuMM internal aumm;
    AureumFeeRoutingHook internal hook;
    AureumProtocolFeeController internal controller;
    IVault internal vault;
    address internal bodenseePool;
    IERC20 internal svZchf;
    IERC4626 internal susds;
    // Populated at P10.1b.
    address[3] internal pilotPools;
    // Populated at P10.1b.
    address[5] internal majorPools;
    // Populated at P10.1b.
    address[18] internal stageNPools;

    function setUp() public virtual {
        svZchf = IERC20(vm.envAddress("SV_ZCHF"));
        susds = IERC4626(vm.envAddress("SUSDS"));
        string[] memory forkEnvKeys = new string[](2);
        forkEnvKeys[0] = "SUSDS";
        forkEnvKeys[1] = "SV_ZCHF";
        ForkEnvGuard.assertMainnetEnv(forkEnvKeys);

        orchestrator = new DeployStageP();

        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("GOVERNANCE_MULTISIG", vm.toString(address(orchestrator)));

        hookScript = new DeployFeeRoutingHook();
        address predictedHook = vm.computeCreateAddress(address(hookScript), 1);

        vaultScript = new DeployAureumVault();
        // The fixture's NEXT own CREATE is the wpf; Bodensee CREATE3 salt is creator-scoped (P-D34: why DeployDerBodensee.run() is not fixture-driven).
        address wpfAddr = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        address predictedBodensee = CREATE3.getDeployed(
            keccak256(abi.encode(address(this), block.chainid, BODENSEE_SALT)),
            wpfAddr
        );

        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("FEE_ROUTING_HOOK", vm.toString(predictedHook));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("DER_BODENSEE_POOL", vm.toString(predictedBodensee));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("SALT", vm.toString(VAULT_SALT));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("PAUSE_WINDOW_DURATION", vm.toString(uint256(PAUSE_WINDOW_DURATION)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("BUFFER_PERIOD_DURATION", vm.toString(BUFFER_PERIOD_DURATION));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MIN_TRADE_AMOUNT", vm.toString(MIN_TRADE_AMOUNT));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MIN_WRAP_AMOUNT", vm.toString(MIN_WRAP_AMOUNT));

        vaultScript.deploy(address(vaultScript));
        vault = vaultScript.vault();
        controller = vaultScript.aureumFeeController();

        wpf = new WeightedPoolFactory(IVault(address(vault)), PAUSE_WINDOW_DURATION, FACTORY_VERSION, POOL_VERSION);
        assert(address(wpf) == wpfAddr);

        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("GENESIS_BLOCK", vm.toString(block.number));
        // minterAdmin_ = GOVERNANCE_MULTISIG env = the orchestrator, sentinel slot (2) of the P-D34 triple.
        aumm = AuMM(new DeployAuMM().run());

        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("AUMM", vm.toString(address(aumm)));

        bodenseePool = wpf.create(
            "der-Bodensee",
            "BODENSEE",
            _bodenseeTokenConfigs(),
            _bodenseeWeights(),
            PoolRoleAccounts({
                pauseManager: address(orchestrator),
                swapFeeManager: address(0),
                poolCreator: address(0)
            }),
            0.0075e18,
            address(0),
            true,
            false,
            BODENSEE_SALT
        );
        assert(bodenseePool == predictedBodensee);

        // moduleAdmin_ = orchestrator, sentinel slot (3).
        hook = hookScript.deploy(
            address(vault),
            bodenseePool,
            svZchf,
            IERC20(address(susds)),
            IERC20(address(aumm)),
            address(controller),
            address(orchestrator)
        );
        assert(address(hook) == predictedHook);
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("FEE_ROUTING_HOOK", vm.toString(address(hook)));

        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("AUREUM_VAULT", vm.toString(address(vault)));
        awpf = AureumWeightedPoolFactory(new DeployAureumWeightedPoolFactory().run());

        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("AUREUM_WEIGHTED_POOL_FACTORY", vm.toString(address(awpf)));

        _initializeBodensee();
        // --- Pilots (initialized — G parity, E10/E-D25 per-token seed amounts) ---
        pilotPools[0] = new DeployIxHelvetia().run();
        IERC20[] memory tokens0 = vault.getPoolTokens(pilotPools[0]);
        uint256[] memory amts0 = new uint256[](2);
        amts0[0] = INIT_SEED;
        amts0[1] = INIT_SEED;
        _initializePool(pilotPools[0], tokens0, amts0);

        pilotPools[1] = new DeployIxEdelweiss().run();
        IERC20[] memory tokens1 = vault.getPoolTokens(pilotPools[1]);
        uint256[] memory amts1 = new uint256[](4);
        amts1[0] = 1_000e6;
        amts1[1] = 1_000e6;
        amts1[2] = 1_000e18;
        amts1[3] = 1_000e18;
        _initializePool(pilotPools[1], tokens1, amts1);

        pilotPools[2] = new DeployIxAurebit().run();
        IERC20[] memory tokens2 = vault.getPoolTokens(pilotPools[2]);
        uint256[] memory amts2 = new uint256[](5);
        amts2[0] = 1_000e8;
        amts2[1] = 1_000e18;
        amts2[2] = 1_000e8;
        amts2[3] = 1_000e18;
        amts2[4] = 1_000e18;
        _initializePool(pilotPools[2], tokens2, amts2);

        // --- PB-D8 waEthwstETH composite RP — MUST precede DeployIxCasper.run() (the config reads the env key during .run()) ---
        CompositeRateProvider waEthwstEthRp = new CompositeRateProvider(IERC4626(IxCasperConfig.WAETHWSTETH), IRateProvider(WSTETH_RATE_PROVIDER));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("WAETHWSTETH_COMPOSITE_RATE_PROVIDER", vm.toString(address(waEthwstEthRp)));

        // --- Majors (bind-only, uninitialized — M parity) ---
        majorPools[0] = new DeployIxCasper().run();
        majorPools[1] = new DeployIxBrevis().run();
        majorPools[2] = new DeployIxAltrix().run();
        majorPools[3] = new DeployIxMediox().run();
        majorPools[4] = new DeployIxLongus().run();

        // --- Rate providers — MUST precede the 02/06/20/27 Sector-3 deploys (N-D9; the configs read these env keys during .run()) ---
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

        // --- Sector-3 (bind-only, uninitialized — N parity, N-D0 canonical slot order) ---
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

        // --- Env wire: base-layer scalars + the 26-pool roster (P-D34; WEIGHTED_POOL_FACTORY = awpf is the F-12 provenance binding) ---
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("VAULT", vm.toString(address(vault)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("BODENSEE_POOL", vm.toString(bodenseePool));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("WEIGHTED_POOL_FACTORY", vm.toString(address(awpf)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("EMERGENCY_MULTISIG", vm.toString(EMERGENCY_MULTISIG));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_01", vm.toString(pilotPools[0]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_05", vm.toString(pilotPools[1]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_14", vm.toString(pilotPools[2]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_03", vm.toString(majorPools[0]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_08", vm.toString(majorPools[1]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_09", vm.toString(majorPools[2]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_10", vm.toString(majorPools[3]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MILIARIUM_POOL_11", vm.toString(majorPools[4]));
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

        // --- Orchestrate: DeployStageP runs J→F→G→H→setEmissionsRecorder→I→M→N→(seedFoundingPool×3 + setGovernanceContract)→L→K, then asserts the four post-conditions in-run ---
        orchestrator.deploy();
    }

    // Bodensee helpers — parity with test/fork/AureumFeeRoutingHook.t.sol
    function _bodenseeTokenConfigs() private view returns (TokenConfig[] memory) {
        address[3] memory addrs;
        addrs[0] = address(aumm);
        addrs[1] = address(susds);
        addrs[2] = address(svZchf);
        if (addrs[0] > addrs[1]) (addrs[0], addrs[1]) = (addrs[1], addrs[0]);
        if (addrs[1] > addrs[2]) (addrs[1], addrs[2]) = (addrs[2], addrs[1]);
        if (addrs[0] > addrs[1]) (addrs[0], addrs[1]) = (addrs[1], addrs[0]);

        TokenConfig[] memory tokens = new TokenConfig[](3);
        tokens[0] = addrs[0] == address(aumm)
            ? TokenConfig({
                token: IERC20(addrs[0]),
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            })
            : addrs[0] == address(susds)
                ? TokenConfig({
                    token: IERC20(addrs[0]),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SUSDS_RATE_PROVIDER),
                    paysYieldFees: true
                })
                : TokenConfig({
                    token: IERC20(addrs[0]),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SV_ZCHF_RATE_PROVIDER),
                    paysYieldFees: true
                });
        tokens[1] = addrs[1] == address(aumm)
            ? TokenConfig({
                token: IERC20(addrs[1]),
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            })
            : addrs[1] == address(susds)
                ? TokenConfig({
                    token: IERC20(addrs[1]),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SUSDS_RATE_PROVIDER),
                    paysYieldFees: true
                })
                : TokenConfig({
                    token: IERC20(addrs[1]),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SV_ZCHF_RATE_PROVIDER),
                    paysYieldFees: true
                });
        tokens[2] = addrs[2] == address(aumm)
            ? TokenConfig({
                token: IERC20(addrs[2]),
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            })
            : addrs[2] == address(susds)
                ? TokenConfig({
                    token: IERC20(addrs[2]),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SUSDS_RATE_PROVIDER),
                    paysYieldFees: true
                })
                : TokenConfig({
                    token: IERC20(addrs[2]),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SV_ZCHF_RATE_PROVIDER),
                    paysYieldFees: true
                });
        return tokens;
    }

    function _bodenseeWeights() private view returns (uint256[] memory) {
        address[3] memory addrs;
        addrs[0] = address(aumm);
        addrs[1] = address(susds);
        addrs[2] = address(svZchf);
        if (addrs[0] > addrs[1]) (addrs[0], addrs[1]) = (addrs[1], addrs[0]);
        if (addrs[1] > addrs[2]) (addrs[1], addrs[2]) = (addrs[2], addrs[1]);
        if (addrs[0] > addrs[1]) (addrs[0], addrs[1]) = (addrs[1], addrs[0]);

        uint256[] memory weights = new uint256[](3);
        weights[0] = addrs[0] == address(aumm) ? 4e17 : 3e17;
        weights[1] = addrs[1] == address(aumm) ? 4e17 : 3e17;
        weights[2] = addrs[2] == address(aumm) ? 4e17 : 3e17;
        return weights;
    }

    function _initializeBodensee() private returns (uint256 bptOut) {
        deal(address(aumm), address(this), INIT_SEED, true);
        deal(address(susds), address(this), INIT_SEED, true);
        deal(address(svZchf), address(this), INIT_SEED, true);

        bytes memory result = vault.unlock(abi.encodeCall(this._initializeBodenseeCallback, ()));
        bptOut = abi.decode(result, (uint256));
    }

    function _initializeBodenseeCallback() external returns (uint256 bptOut) {
        require(msg.sender == address(vault), "onlyVault");

        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = IERC20(address(aumm));
        tokens[1] = IERC20(address(susds));
        tokens[2] = IERC20(address(svZchf));
        if (address(tokens[0]) > address(tokens[1])) (tokens[0], tokens[1]) = (tokens[1], tokens[0]);
        if (address(tokens[1]) > address(tokens[2])) (tokens[1], tokens[2]) = (tokens[2], tokens[1]);
        if (address(tokens[0]) > address(tokens[1])) (tokens[0], tokens[1]) = (tokens[1], tokens[0]);

        uint256[] memory amountsIn = new uint256[](3);
        amountsIn[0] = INIT_SEED;
        amountsIn[1] = INIT_SEED;
        amountsIn[2] = INIT_SEED;

        bptOut = vault.initialize(bodenseePool, address(this), tokens, amountsIn, 0, "");
        for (uint256 i = 0; i <= 2; ++i) {
            tokens[i].transfer(address(vault), amountsIn[i]);
            vault.settle(tokens[i], amountsIn[i]);
        }
    }

    // Pilot pool β-pattern helpers — generalized from D7 fork test
    function _initializePool(address pool, IERC20[] memory tokens, uint256[] memory amountsIn)
        internal
        returns (uint256 bptOut)
    {
        for (uint256 i = 0; i < tokens.length; ++i) {
            deal(address(tokens[i]), address(this), amountsIn[i]);
        }
        bytes memory result = vault.unlock(abi.encodeCall(this._initializePoolCallback, (pool, tokens, amountsIn)));
        bptOut = abi.decode(result, (uint256));
    }

    function _initializePoolCallback(address pool, IERC20[] memory tokens, uint256[] memory amountsIn)
        external
        returns (uint256 bptOut)
    {
        require(msg.sender == address(vault), "onlyVault");
        bptOut = vault.initialize(pool, address(this), tokens, amountsIn, 0, "");
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokens[i].transfer(address(vault), amountsIn[i]);
            vault.settle(tokens[i], amountsIn[i]);
        }
    }

    /// @dev der Bodensee's raw reserve for `token` — the pre/post pair every
    ///      post-F-23 assertion compares. Supply-unchanged alone cannot
    ///      distinguish a donation from a silently skipped route, since both
    ///      leave BPT supply flat; the reserve delta is what separates them.
    ///      Mirrors the hook's own `_currentBodenseeReserve` read.
    function _bodenseeReserve(IERC20 token) internal view returns (uint256) {
        (, uint256 idx) = vault.getPoolTokenCountAndIndexOfToken(bodenseePool, token);
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(bodenseePool);
        return balancesRaw[idx];
    }

    /// @dev Recorded LP for the next liquidity op. The hook resolves the LP via
    ///      IRouterSender(router).getSender(); this fixture IS the router (it
    ///      calls Vault.addLiquidity directly inside unlock), so getSender()
    ///      returns _lpSender. Decoupled from the BPT recipient (address(this)).
    address internal _lpSender;

    /// @notice IRouterSender shim — the hook calls this on every add/remove.
    function getSender() external view returns (address) {
        return _lpSender;
    }

    /// @dev One-sided UNBALANCED add of `fractionBps`/10000 of token[0]'s current
    ///      pool balance, recording the deposit for `lp`. Mirrors StageG
    ///      _initializePool (deal -> unlock -> settle) with addLiquidity in place
    ///      of initialize.
    function _depositOneSided(address pool, address lp, uint256 fractionBps)
        internal
        returns (uint256 bptOut)
    {
        _lpSender = lp;
        IERC20[] memory tokens = vault.getPoolTokens(pool);
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(pool);
        uint256[] memory amountsIn = new uint256[](tokens.length);
        amountsIn[0] = (balancesRaw[0] * fractionBps) / 10_000;
        deal(address(tokens[0]), address(this), amountsIn[0]);
        bytes memory result = vault.unlock(abi.encodeCall(this._depositCallback, (pool, amountsIn)));
        bptOut = abi.decode(result, (uint256));
    }

    function _depositCallback(address pool, uint256[] memory amountsIn)
        external
        returns (uint256 bptOut)
    {
        require(msg.sender == address(vault), "onlyVault");
        IERC20[] memory tokens = vault.getPoolTokens(pool);
        (, bptOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: amountsIn,
                minBptAmountOut: 0,
                kind: AddLiquidityKind.UNBALANCED,
                userData: ""
            })
        );
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (amountsIn[i] > 0) {
                tokens[i].transfer(address(vault), amountsIn[i]);
                vault.settle(tokens[i], amountsIn[i]);
            }
        }
    }

    function _matureStack(address lp) internal returns (uint256 bptOut) {
        // P-D36 (4) governance token-map seed
        vm.startPrank(address(orchestrator));
        orchestrator.tvlOracle().setTokenUnderlying(address(svZchf), address(svZchf));
        orchestrator.tvlOracle().setTokenUnderlying(address(susds), address(susds));
        vm.stopPrank();
        // StageKIntegration L172 pattern — balanceOf(lp) == userLP for F-17
        bptOut = _depositOneSided(pilotPools[0], lp, 100);
        IERC20(pilotPools[0]).transfer(lp, bptOut);
        // EMA seed
        orchestrator.emaSampler().updateEMA(pilotPools[0]);
        // EMA_MATURITY_BLOCKS (60 days, F-04)
        vm.roll(block.number + 432_000);
        // freshness refresh (F-05)
        orchestrator.emaSampler().updateEMA(pilotPools[0]);
        // F-5 score > 0 in bootstrap via the Miliarium f5Total/28 branch
        orchestrator.emissionDistributor().recordScore(pilotPools[0]);
    }

    /// @dev K-D6d proposal bond, shared by Legs C1/C2/C3 (AureumGovernance.PROPOSAL_DEPOSIT_SVZCHF is internal, so re-declared here).
    uint256 internal constant PROPOSAL_DEPOSIT = 1_000e18;

    /// @dev P-D39 voter seating — the REAL _matureStack (no StageO _qualifyVoter mock), then an
    ///      immediate poke while the EMA is fresh (F-05): the checkpoint written here is what
    ///      castVote's getPastVotes(snapshotBlock) read finds later (F-06 freeze survives the
    ///      proposal roll). Chained getter is safe here — poke is permissionless, no prank in
    ///      flight (P-D38 concerns pranked calls only).
    function _seatVoter(address voter) internal {
        _matureStack(voter);
        orchestrator.votingWeight().poke(voter);
    }

    /// @dev P-D39 shared proposal lifecycle UP TO the executable block — the StageO
    ///      _voteQueueReachEta shape de-mocked: roll past the F-06 snapshot, vote FOR (single
    ///      poked voter, so quorum and any supermajority are trivially met), roll past endBlock,
    ///      queue, roll to eta. Stops WITHOUT executing, so a case can mutate state inside the
    ///      grace window before `execute` — C.6's veto leg flips `recoveryPathAdmitted` here, and
    ///      G.2 holds a second challenge in flight on the same slot. The eta roll stays INSIDE
    ///      this helper, so the composed `_runProposal` below keeps its pre-split timing exactly.
    ///      gov handle cached BEFORE the prank (P-D38).
    function _runProposalToQueued(uint256 id, address voter) internal {
        AureumGovernance gov = orchestrator.governance();
        AureumGovernance.Proposal memory pv = gov.getProposal(id);
        vm.roll(pv.snapshotBlock + 1);
        vm.prank(voter);
        gov.castVote(id, true);
        vm.roll(pv.endBlock + 1);
        gov.queue(id);
        AureumGovernance.Proposal memory pq = gov.getProposal(id);
        vm.roll(pq.eta);
    }

    /// @dev P-D39 full lifecycle, unchanged in behaviour: `_runProposalToQueued` plus `execute`.
    ///      Same rolls in the same order, same block on entry to `execute`, so all five existing
    ///      call sites are untouched. gov handle cached BEFORE the inner prank (P-D38).
    function _runProposal(uint256 id, address voter) internal {
        AureumGovernance gov = orchestrator.governance();
        _runProposalToQueued(id, voter);
        gov.execute(id);
    }
}

/**
 * @title StagePWiringTest
 * @notice P-D34 two-layer split wiring layer (H13) — the independent external witness of the
 *         orchestrator's wiring. The four in-run post-conditions already reverted inside
 *         `deploy()`; this contract re-asserts the key binds from outside.
 * @dev Reads the fixture's own pool arrays and typed handles (`orchestrator`, `hook`, `vault`,
 *      `aumm`, `bodenseePool`) — never `vm.env`, so the env oracle the orchestrator's
 *      `_rosterPools()` consulted is not re-used. No harness seat (`setGovernanceModule` /
 *      `setTrustedRouter`) — those live only in `StagePEndToEndTest` per P-D34 L459.
 */
contract StagePWiringTest is StagePIntegrationFixture {
    function test_handles_all15NonZero() public view {
        assertNotEq(address(orchestrator.miliariumRegistry()), address(0));
        assertNotEq(address(orchestrator.tvlOracle()), address(0));
        assertNotEq(address(orchestrator.efficiencyOracle()), address(0));
        assertNotEq(address(orchestrator.emaSampler()), address(0));
        assertNotEq(address(orchestrator.ccbMultiplier()), address(0));
        assertNotEq(address(orchestrator.swapAndDeposit()), address(0));
        assertNotEq(address(orchestrator.vaultClassRegistry()), address(0));
        assertNotEq(address(orchestrator.gaugeRegistry()), address(0));
        assertNotEq(address(orchestrator.emissionDistributor()), address(0));
        assertNotEq(address(orchestrator.bodenseeBootstrapChannel()), address(0));
        assertNotEq(address(orchestrator.incendiaryRegistry()), address(0));
        assertNotEq(address(orchestrator.votingWeight()), address(0));
        assertNotEq(address(orchestrator.governance()), address(0));
        assertNotEq(address(orchestrator.authorizer()), address(0));
        assertNotEq(address(orchestrator.minterRouter()), address(0));
    }

    function test_genesisBlock_uniformAcrossStack() public view {
        uint256 gb = aumm.GENESIS_BLOCK();
        assertEq(orchestrator.gaugeRegistry().GENESIS_BLOCK(), gb);
        assertEq(orchestrator.efficiencyOracle().GENESIS_BLOCK(), gb);
        assertEq(orchestrator.emissionDistributor().GENESIS_BLOCK(), gb);
    }

    function test_roster26_gaugedAndRecorderBound() public view {
        for (uint256 i = 0; i < pilotPools.length; ++i) {
            address p = pilotPools[i];
            assertTrue(orchestrator.gaugeRegistry().isGaugeApproved(p));
            assertEq(orchestrator.emissionDistributor().auMTContractByPool(p), address(hook));
        }
        for (uint256 i = 0; i < majorPools.length; ++i) {
            address p = majorPools[i];
            assertTrue(orchestrator.gaugeRegistry().isGaugeApproved(p));
            assertEq(orchestrator.emissionDistributor().auMTContractByPool(p), address(hook));
        }
        for (uint256 i = 0; i < stageNPools.length; ++i) {
            address p = stageNPools[i];
            assertTrue(orchestrator.gaugeRegistry().isGaugeApproved(p));
            assertEq(orchestrator.emissionDistributor().auMTContractByPool(p), address(hook));
        }
        assertFalse(orchestrator.gaugeRegistry().isGaugeApproved(bodenseePool));
    }

    function test_wires_stageHandoffsComplete() public view {
        assertEq(hook.emissionRecorder(), address(orchestrator.emissionDistributor())); // I-D16 hook recorder seat
        assertEq(orchestrator.efficiencyOracle().emissionsRecorder(), address(orchestrator.emissionDistributor())); // P-D28
        assertTrue(orchestrator.swapAndDeposit().authorizedDonators(address(orchestrator.incendiaryRegistry()))); // L-D2 deposit tail
        assertEq(orchestrator.emissionDistributor().incendiaryRegistry(), address(orchestrator.incendiaryRegistry())); // L-D25 boost leg
        assertEq(address(orchestrator.vaultClassRegistry().votingWeight()), address(orchestrator.votingWeight())); // K wire (1)
        assertTrue(orchestrator.swapAndDeposit().authorizedDonators(address(orchestrator.governance()))); // K wire (2)
        assertEq(address(orchestrator.bodenseeBootstrapChannel().mintRouter()), address(orchestrator.minterRouter())); // K wire (3)
        assertEq(address(orchestrator.emissionDistributor().mintRouter()), address(orchestrator.minterRouter())); // K wire (4)
        assertEq(aumm.minter(), address(orchestrator.minterRouter())); // K wire (5), C-D11 one-shot
        assertEq(orchestrator.gaugeRegistry().governanceContract(), address(orchestrator.governance())); // K wire (6)
        assertEq(orchestrator.miliariumRegistry().governanceContract(), address(orchestrator.governance())); // K wire (7)
        assertEq(address(orchestrator.tvlOracle().miliariumRegistry()), address(orchestrator.miliariumRegistry())); // K wire (8), F-03/K-D8
        assertEq(address(vault.getAuthorizer()), address(orchestrator.authorizer())); // K wire (9) / post-condition (4)
        assertEq(orchestrator.vaultClassRegistry().governanceContract(), address(orchestrator.governance())); // PB-D11 (iii) / PB-D23 (iii): the VaultClassRegistry governance one-shot now binds post-K to AureumGovernance
    }

    function test_atRest_moduleUnsetNoTrustedRouter() public view {
        assertEq(hook.governanceModule(), address(0)); // structurally proves the trustedRouter allowlist is empty — setTrustedRouter is governanceModule-gated, so no call can ever have succeeded
        assertFalse(hook.trustedRouter(address(orchestrator)));
        assertFalse(hook.trustedRouter(address(orchestrator.governance())));
        assertFalse(hook.trustedRouter(address(this)));
    }
}

/**
 * @title StagePEndToEndTest
 * @notice The P-D36 behavioral layer of the H13 two-layer split — 7 legs as test functions
 *         on the orchestrator-deployed stack.
 * @dev This contract IS the trusted router (P-D26 seat) and the LP attributor via getSender();
 *      NO vm.mockCall / vm.store shims anywhere (P-D36 policy); BPT receipts are handed to the
 *      recorded LP so the F-17 receipt cap is exercised faithfully.
 */
contract StagePEndToEndTest is StagePIntegrationFixture {
    function setUp() public override {
        super.setUp();
        vm.prank(address(orchestrator));
        hook.setGovernanceModule(address(this));
        hook.setTrustedRouter(address(this), true);
    }

    // Transcribed from PilotPools.t.sol L325-L355 per P-D36/CLAUDE.md L330 — two-arg deal per E10; plain transfer, no SafeERC20.
    function _performSwap(address pool, IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        deal(address(tokenIn), address(this), amountIn);
        bytes memory result =
            vault.unlock(abi.encodeCall(this._performSwapCallback, (pool, tokenIn, tokenOut, amountIn)));
        amountOut = abi.decode(result, (uint256));
    }

    function _performSwapCallback(address pool, IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn)
        external
        returns (uint256 amountOut)
    {
        require(msg.sender == address(vault), "onlyVault");
        (, uint256 inUsed, uint256 outRcvd) = vault.swap(
            VaultSwapParams({
                kind: SwapKind.EXACT_IN,
                pool: pool,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountGivenRaw: amountIn,
                limitRaw: 0,
                userData: ""
            })
        );
        tokenIn.transfer(address(vault), inUsed);
        vault.settle(tokenIn, inUsed);
        vault.sendTo(tokenOut, address(this), outRcvd);
        amountOut = outRcvd;
    }

    function test_setUp_harnessSeated() public view {
        assertEq(hook.governanceModule(), address(this));
        assertTrue(hook.trustedRouter(address(this)));
    }

    function test_legA_claimMintsThroughFullRecorderChain() public {
        address lp = makeAddr("p10_legA_lp");
        uint256 bptOut = _matureStack(lp);
        assertGt(bptOut, 0);
        // F-09 dispatch witness
        EmissionDistributor d = orchestrator.emissionDistributor();
        assertEq(d.userLP(pilotPools[0], lp), bptOut);
        // one epoch accrual window
        vm.roll(block.number + 100_800);
        // Handle cached above — vm.prank must be followed DIRECTLY by claim: a chained
        // orchestrator.emissionDistributor() auto-getter staticcall consumes the prank,
        // leaving claim's msg.sender = this test contract (zero stake, amount == 0 early return).
        vm.prank(lp);
        d.claim(pilotPools[0], lp);
        // K-D7/I-D16 chain witness: hook dispatch → recorder → score → accrual → mintRouter.mintFor → AuMM mint
        assertGt(aumm.balanceOf(lp), 0);
        // crystallized pending fully paid
        assertEq(d.pendingClaim(pilotPools[0], lp), 0);
    }

    /// @notice P-D36 Leg B — the D-D21 hook↔controller bake dynamic: onAfterSwap → collectSwapAggregateFeesForHook → convert → one-sided Bodensee DONATION per PB-D68 (v).
    function test_legB_swapFeeSweepGrowsBodensee() public {
        uint256 bodenseeSupplyBefore = IERC20(bodenseePool).totalSupply();
        uint256 bodenseeReserveBefore = _bodenseeReserve(svZchf);
        uint256 amountOut = _performSwap(pilotPools[0], IERC20(address(susds)), svZchf, 1e18);
        assertGt(amountOut, 0);
        // Bodensee-depth witness: donated, not minted
        assertEq(IERC20(bodenseePool).totalSupply(), bodenseeSupplyBefore, "F-23 - BPT supply unchanged by a donation");
        assertGt(_bodenseeReserve(svZchf), bodenseeReserveBefore, "PB-D68 (v) - depth donated, not silently skipped");
        // zero hook residue
        assertLt(svZchf.balanceOf(address(hook)), 1_000_000, "PB-D68 (xix) - dust only, swept by the next route");
        assertLt(susds.balanceOf(address(hook)), 1_000_000, "PB-D68 (xix) - dust only, swept by the next route");
    }

    /// @notice P-D36 Leg D — CCB month-walk: updateMultiplier's BLOCKS_PER_EPOCH cadence + F-8
    ///         anti-cyclical evolution on the orchestrator-deployed engine reading the K-wire-(8)-bound
    ///         registry. Only pilot 01 is EMA-matured (via _matureStack), so poolEMA >> currentAgg/28 and
    ///         the intra channel steps M_i down -STEP_SIZE each epoch off INITIAL_MULTIPLIER. No prank —
    ///         updateMultiplier is permissionless (the P-D38 handle-cache is kept for uniformity).
    function test_legD_ccbMonthWalkEvolvesMultiplier() public {
        address lp = makeAddr("p10_legD_lp");
        _matureStack(lp);
        CCBMultiplier ccb = orchestrator.ccbMultiplier();
        uint256 initial = ccb.INITIAL_MULTIPLIER();
        // fresh pool → INITIAL_MULTIPLIER (M_i unwritten)
        assertEq(ccb.getMultiplier(pilotPools[0]), initial);
        // epoch 1 — cadence trivially met on the fork (block >> BLOCKS_PER_EPOCH); intra step fires down
        ccb.updateMultiplier(pilotPools[0]);
        uint256 afterFirst = ccb.getMultiplier(pilotPools[0]);
        assertLt(afterFirst, initial);
        // cadence gate — immediate re-call reverts TooEarly(current, current + BLOCKS_PER_EPOCH);
        // full encoding per the CCBMultiplier.t.sol L174 precedent (arg-carrying error — bare-selector exact-match fails).
        vm.expectRevert(
            abi.encodeWithSelector(CCBMultiplier.TooEarly.selector, block.number, block.number + 100_800)
        );
        ccb.updateMultiplier(pilotPools[0]);
        // epoch 2 — advance one BLOCKS_PER_EPOCH; the walk continues to evolve M_i
        vm.roll(block.number + 100_800);
        ccb.updateMultiplier(pilotPools[0]);
        assertLt(ccb.getMultiplier(pilotPools[0]), afterFirst);
    }

    // --- P10.3c (P-D39): the three AureumGovernance proposal-type legs ---

    /// @dev Leg C3 target fee — inside [SWAP_FEE_MIN 1e14, SWAP_FEE_MAX 3e15] and != pilot 01's 2e14 create fee (E-D22), so the change is observable.
    uint256 internal constant NEW_FEE = 2e15;

    /// @notice P-D39 Leg C3 — fee change propose → vote → queue → execute: the DYNAMIC
    ///         authorizer-migration witness. _executeProposal routes VAULT.setStaticSwapFeePercentage
    ///         with msg.sender = governance, permitted only because the migrated
    ///         AureumGovernanceAuthorizer grants GOVERNANCE_CONTRACT full authority (K wire 9);
    ///         P10.2 wire (13) asserted only the static getAuthorizer() half. Cooldown is clear:
    ///         lastFeeChangeBlock == 0 and the fork block height far exceeds FEE_CHANGE_COOLDOWN_BLOCKS.
    function test_legC3_feeChangeExecutesThroughMigratedAuthorizer() public {
        address voter = makeAddr("p10_legC3_voter");
        _seatVoter(voter);
        AureumGovernance gov = orchestrator.governance();
        uint256 feeBefore = vault.getStaticSwapFeePercentage(pilotPools[0]);
        assertNotEq(feeBefore, NEW_FEE);
        deal(address(svZchf), voter, PROPOSAL_DEPOSIT);
        vm.startPrank(voter);
        svZchf.approve(address(gov), PROPOSAL_DEPOSIT);
        uint256 id = gov.proposeFeeChange(pilotPools[0], NEW_FEE, svZchf);
        vm.stopPrank();
        // bond pulled proposer → channel → donate (K wire 2, dynamically witnessed)
        assertEq(svZchf.balanceOf(voter), 0);
        _runProposal(id, voter);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Executed));
        assertEq(vault.getStaticSwapFeePercentage(pilotPools[0]), NEW_FEE);
    }

    /// @notice P-D39 Leg C2 — gauge challenge propose → vote → queue → execute: the
    ///         K-wire-6 revoke witness. All 26 roster pools are slotted, so none clears
    ///         proposeGaugeChallenge's `gaugeStatus == Active && slotOf == 0` gate; the
    ///         precondition manufactures an unslotted Active gauge via a governance
    ///         seedFoundingPool (bypasses eligibility + the anti-spam fee, does NOT slot).
    ///         Execute routes _executeProposal → GAUGE_REGISTRY.revokeGauge, flipping the
    ///         target Active → Revoked (terminal per G-D17).
    function test_legC2_gaugeChallengeRevokesThroughGovernance() public {
        address voter = makeAddr("p10_legC2_voter");
        _seatVoter(voter);
        GaugeRegistry gr = orchestrator.gaugeRegistry();
        AureumGovernance gov = orchestrator.governance();
        // Precondition — manufacture an unslotted Active gauge. gr cached BEFORE the prank
        // (P-D38): a chained orchestrator.gaugeRegistry() staticcall would consume the
        // single-shot prank, leaving seedFoundingPool to run as the test contract →
        // onlyGovernance revert. seedFoundingPool takes any address and does NOT slot it.
        address c2Target = makeAddr("p10_legC2_target");
        vm.prank(address(gov));
        gr.seedFoundingPool(c2Target);
        assertEq(uint256(gr.gaugeStatus(c2Target)), uint256(IGaugeRegistry.GaugeStatus.Active));
        // Propose — deposit pulled proposer → BODENSEE_CHANNEL → donate (K wire 2).
        deal(address(svZchf), voter, PROPOSAL_DEPOSIT);
        vm.startPrank(voter);
        svZchf.approve(address(gov), PROPOSAL_DEPOSIT);
        uint256 id = gov.proposeGaugeChallenge(c2Target, svZchf);
        vm.stopPrank();
        assertEq(svZchf.balanceOf(voter), 0);
        _runProposal(id, voter);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Executed));
        // K-wire-6 revoke witness: Active → Revoked (terminal, G-D17).
        assertEq(uint256(gr.gaugeStatus(c2Target)), uint256(IGaugeRegistry.GaugeStatus.Revoked));
    }

    /// @notice F-22 / PB-D64 — the keystone reachability witness. Propose → vote → queue → execute
    ///         drives VAULT.setAuthorizer on the REAL Vault, the lever F-22 found permitted to
    ///         governance and reachable by no caller at all (PB-D63 (viii): the one lever that
    ///         redefines every other permission decision). Scoped to setAuthorizer alone —
    ///         VaultUnpause and VaultRecoveryDisable share identical propose/vote/queue/execute
    ///         plumbing and are already dispatch-witnessed against a recording mock at the unit
    ///         level (test/unit/AureumGovernance.t.sol); this fork leg exists specifically because
    ///         setAuthorizer is the one PB-D63 (viii) ranks first and names the keystone.
    /// @dev The candidate need only carry code per the propose-time AuthorizerNotContract guard
    ///      (PB-D64 (vi)); orchestrator is a convenient already-deployed stand-in, not a
    ///      functioning authorizer — no further authenticated call is routed through it after
    ///      migration, so this witnesses reachability, not the candidate's own behavior.
    function test_F22_authorizerChangeExecutesEndToEnd() public {
        address voter = makeAddr("f22_authorizerChange_voter");
        _seatVoter(voter);
        AureumGovernance gov = orchestrator.governance();
        address candidate = address(orchestrator);
        assertNotEq(address(vault.getAuthorizer()), candidate);
        deal(address(svZchf), voter, PROPOSAL_DEPOSIT);
        vm.startPrank(voter);
        svZchf.approve(address(gov), PROPOSAL_DEPOSIT);
        uint256 id = gov.proposeVaultAuthorizerChange(candidate, svZchf);
        vm.stopPrank();
        assertEq(svZchf.balanceOf(voter), 0);
        _runProposal(id, voter);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Executed));
        assertEq(address(vault.getAuthorizer()), candidate);
    }

    /// @dev P-D39 Leg C1 candidate builder — a REAL uninitialized awpf pool
    ///      [susds 0.6 WITH_RATE, svZchf 0.4 WITH_RATE], no vm.mockCall (P-D36). Clears BOTH
    ///      gates: awpf.create's MIN_ERC4626_WEIGHT (both WITH_RATE-with-rate-provider, sum
    ///      100% ≥ 52%) and meetsCompositionQualityGate's ≥0.52e18 admitted-4626 numerator
    ///      (susds is a GaugeGenesisManifest-admitted class at 0.6, carrying it alone). Carries
    ///      the canonical hook (onRegister returns true — neither token is der Bodensee) and awpf
    ///      provenance (F-12). susds (0xa393…) < svZchf (0xE5F1…) on mainnet, so susds is the
    ///      sorted tokens[0] holding the 0.6 majority; a wrong order reverts TokensNotSorted.
    function _buildCompositionCandidate() internal returns (address candidate) {
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0] = TokenConfig({
            token: IERC20(address(susds)),
            tokenType: TokenType.WITH_RATE,
            rateProvider: IRateProvider(SUSDS_RATE_PROVIDER),
            paysYieldFees: true
        });
        tokens[1] = TokenConfig({
            token: svZchf,
            tokenType: TokenType.WITH_RATE,
            rateProvider: IRateProvider(SV_ZCHF_RATE_PROVIDER),
            paysYieldFees: true
        });
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.6e18;
        weights[1] = 0.4e18;
        candidate = awpf.create(
            "P10 C1 Candidate",
            "C1CAND",
            tokens,
            weights,
            PoolRoleAccounts({ pauseManager: address(0), swapFeeManager: address(0), poolCreator: address(0) }),
            0.0075e18,
            address(hook),
            false,
            false,
            keccak256("p10_legC1_candidate")
        );
    }

    /// @notice P-D39 Leg C1 — composition challenge propose → vote → queue → execute: the
    ///         REAL-candidate dual-gate + slot-replace witness. proposeCompositionChallenge
    ///         gates on meetsCompositionQualityGate at propose; _executeProposal re-checks it,
    ///         then atomically revokeGauge(old) → replaceSlot(5, candidate) →
    ///         registerGaugeFromComposition(candidate). Slot 5 = pilot 05 (StageO precedent),
    ///         so the voter's pilot-01 stack is untouched; the 2/3 supermajority is single-voter
    ///         trivial. The candidate is uninitialized — the composition gate omits the TVL
    ///         floor, and F-19/P-D37 backstops any registry read against the slotted candidate.
    function test_legC1_compositionChallengeReplacesSlotThroughGovernance() public {
        address voter = makeAddr("p10_legC1_voter");
        _seatVoter(voter);
        GaugeRegistry gr = orchestrator.gaugeRegistry();
        AureumGovernance gov = orchestrator.governance();
        // Dual-gate candidate (built via awpf.create, so its MIN_ERC4626_WEIGHT gate already passed).
        address candidate = _buildCompositionCandidate();
        assertTrue(gr.meetsCompositionQualityGate(candidate));
        address oldPool = orchestrator.miliariumRegistry().poolAtSlot(5);
        assertTrue(oldPool != address(0));
        // Propose — deposit pulled proposer → BODENSEE_CHANNEL → donate (K wire 2).
        deal(address(svZchf), voter, PROPOSAL_DEPOSIT);
        vm.startPrank(voter);
        svZchf.approve(address(gov), PROPOSAL_DEPOSIT);
        uint256 id = gov.proposeCompositionChallenge(5, candidate, svZchf);
        vm.stopPrank();
        assertEq(svZchf.balanceOf(voter), 0);
        _runProposal(id, voter);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Executed));
        // Atomic slot replace: candidate takes slot 5, gauged from composition; old pool revoked.
        assertEq(orchestrator.miliariumRegistry().poolAtSlot(5), candidate);
        assertEq(uint256(gr.gaugeStatus(candidate)), uint256(IGaugeRegistry.GaugeStatus.Active));
        assertEq(uint256(gr.gaugeStatus(oldPool)), uint256(IGaugeRegistry.GaugeStatus.Revoked));
    }

    /// @notice P-D41 Leg E — the halving-boundary witness, closing the P-D36 7-leg roster.
    ///         Part 1: the orchestrator-deployed AuMM halves at the exact era edge
    ///         (GENESIS_RATE / >>1 / >>2 at the last-Era-0 / first-Era-1 / Era-2 blocks — the
    ///         AuMM.t.sol idiom against the DEPLOYED instance) and the distributor shares the
    ///         halving root. Part 2: a claim straddling GENESIS + BLOCKS_PER_ERA fires
    ///         _accrueGlobal's era-walk tiling (H-D30 — Era-0 blocks at 1e18, Era-1 at 5e17) and
    ///         still mints; asserted nonzero, not exact-ratio (P-D41 — the magnitude is Part 1's job).
    function test_legE_halvingBoundaryTilesEmissionAcrossEra() public {
        // Part 1 — exact era-edge rate witness on the orchestrator-deployed AuMM.
        uint256 genesis = aumm.GENESIS_BLOCK();
        uint256 era = AureumTime.BLOCKS_PER_ERA;
        uint256 genesisRate = aumm.GENESIS_RATE();
        assertEq(aumm.blockEmissionRate(genesis + era - 1), genesisRate); // last Era-0 block: full rate (edge exclusive)
        assertEq(aumm.blockEmissionRate(genesis + era), genesisRate >> 1); // first Era-1 block: halved
        assertEq(aumm.blockEmissionRate(genesis + 2 * era), genesisRate >> 2); // Era 2: quartered
        assertEq(orchestrator.emissionDistributor().GENESIS_BLOCK(), genesis); // accrual shares the halving root

        // Part 2 — a claim straddling the era boundary still mints (the _accrueGlobal era-walk).
        address lp = makeAddr("p10_legE_lp");
        _matureStack(lp); // accrual cursor lands in Era 0 (bootstrap)
        EmissionDistributor d = orchestrator.emissionDistributor();
        vm.roll(genesis + era + 100_800); // one epoch into Era 1
        orchestrator.emaSampler().updateEMA(pilotPools[0]); // F-05 freshness at the Era-1 block
        d.recordScore(pilotPools[0]); // _accrueGlobal walks the Era-0 → Era-1 boundary
        // P-D38 handle cache: d set above, vm.prank directly followed by d.claim (no chained getter).
        vm.prank(lp);
        d.claim(pilotPools[0], lp);
        assertGt(aumm.balanceOf(lp), 0); // mint survives the halving-boundary straddle
    }

    /// @notice P1 C.4 — the 12-month emergency window binds one authorizer INSTANCE, not the
    ///         protocol. A 2/3 vote installs a freshly-constructed `AureumGovernanceAuthorizer`
    ///         carrying its own new `EMERGENCY_WINDOW_END_BLOCK` and an arbitrary emergency
    ///         address, because `_executeProposal` performs NO execute-time sanity check on the
    ///         candidate — the only gate is a propose-time `code.length != 0`. Repeatable before
    ///         each window closes, so "no authority thereafter, ever" is false from step 7 on.
    function test_P1_C4_voteInstallsFreshEmergencyWindowForArbitraryAddress() public {
        address voter = makeAddr("p1_c4_voter");
        _seatVoter(voter);
        AureumGovernance gov = orchestrator.governance();
        address attackerEOA = makeAddr("p1_c4_attackerEOA");
        AureumGovernanceAuthorizer attacker =
            new AureumGovernanceAuthorizer(address(gov), attackerEOA, address(vault));
        assertGt(attacker.EMERGENCY_WINDOW_END_BLOCK(), block.number, "candidate carries a live window");
        assertNotEq(address(vault.getAuthorizer()), address(attacker), "premise: not already seated");
        deal(address(svZchf), voter, PROPOSAL_DEPOSIT);
        vm.startPrank(voter);
        svZchf.approve(address(gov), PROPOSAL_DEPOSIT);
        uint256 id = gov.proposeVaultAuthorizerChange(address(attacker), svZchf);
        vm.stopPrank();
        _runProposal(id, voter);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Executed), "executed");
        assertEq(address(vault.getAuthorizer()), address(attacker), "arbitrary authorizer installed by vote");
        assertEq(attacker.EMERGENCY_MULTISIG(), attackerEOA, "arbitrary emergency address now seated");
    }

    /**
     * @notice E.2 — post-K, the controller's `withdrawProtocolFees` /
     *         `withdrawProtocolFeesForToken` are `authenticate`-gated to the
     *         Vault's migrated authorizer, which grants the action only to
     *         `AureumGovernance` (the contract) and a narrow, time-boxed
     *         emergency role. No external account can withdraw, and the sole
     *         authorized principal — governance — has no `propose*` entrypoint
     *         and no `_executeProposal` arm that emits a controller call, so the
     *         swept protocol-fee ledger has no designed drain while the
     *         permissionless `collectAggregateFees` keeps filling it.
     * @dev Reproduction PoC for seam-1 root cause E.2 (Medium; High → M per G36
     *      correction 3 — unreachable to governance, reachable only as a
     *      `VaultAuthorizerChange` payload, which is C.4 and is reproduced
     *      separately, NOT re-driven here). The swap-leg FILL the finding names
     *      is the rail-less ixAetheron skip (`AureumFeeRoutingHook.sol:375`),
     *      not a railed pilot swap: `onAfterSwap` forwards the swap leg to the
     *      hook and never credits `_protocolFeeAmounts` (D17 invariant 1), and
     *      ixAetheron is bind-only uninitialized in this fixture, so this rung
     *      asserts unreachability plus permissionless collect rather than a
     *      manufactured `> 0`. Governance is live (see
     *      `test_legC3_feeChangeExecutesThroughMigratedAuthorizer`); it simply
     *      has no arm for the controller.
     */
    function test_P1_E2_protocolFeeWithdrawalUnreachablePostHandoff() public {
        AureumGovernance gov = orchestrator.governance();
        address pool = pilotPools[0];
        address attacker = makeAddr("e2_attacker");

        bytes32 withdrawActionId =
            controller.getActionId(AureumProtocolFeeController.withdrawProtocolFees.selector);

        // (1) No external account is the authority. authenticate runs before
        //     the recipient pin, so a well-formed recipient cannot mask the
        //     gate; each principal reverts SenderNotAllowed.
        address[3] memory blocked = [attacker, address(orchestrator), EMERGENCY_MULTISIG];
        for (uint256 i = 0; i < blocked.length; ++i) {
            vm.prank(blocked[i]);
            vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
            controller.withdrawProtocolFees(pool, address(hook));
        }

        // (2) The barrier is NOT the authorizer: governance holds the action.
        bool govAllowed = AureumGovernanceAuthorizer(address(vault.getAuthorizer()))
            .canPerform(withdrawActionId, address(gov), address(controller));
        assertTrue(govAllowed, "E.2 - governance is authorized; the barrier is the missing path");

        // (3) ... yet governance has no path to fire it. Its six proposal types
        //     (GaugeChallenge, CompositionChallenge, FeeChange, VaultAuthorizer-
        //     Change, VaultUnpause, VaultRecoveryDisable) and their six
        //     _executeProposal arms touch the Vault and pools only; none
        //     constructs a controller call, so (2)'s authorization is
        //     unreachable in production. Structural, per the NatSpec above; not
        //     driven by a prank, which would be a non-existent path.

        // (4, lean) The credit side stays permissionless: any EOA sweeps fees
        //     into the ledger that (1)-(3) prove undrainable.
        vm.prank(attacker);
        controller.collectAggregateFees(pool);
    }

    /**
     * @notice E.3 — the constitution's 10% ERC-4626 yield skim is 0% in code.
     *         `_globalProtocolYieldFeePercentage` (`:105`) has no constructor
     *         write and no script write anywhere in the repo; its sole write
     *         site is the `authenticate`-gated setter at `:645`, which post-K is
     *         authorized only to `AureumGovernance` — a contract with no
     *         `propose*` arm that reaches the controller, per
     *         `test_P1_E2_protocolFeeWithdrawalUnreachablePostHandoff`. Every
     *         pool is therefore stamped 0% aggregate yield at registration.
     * @dev Reproduction PoC for seam-1 root cause E.3 (Medium). The ASYMMETRY is
     *      the finding: the swap global is pinned to
     *      `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE` in the constructor
     *      (`AureumProtocolFeeController.sol:259`) and its setter is `pure`,
     *      reverting `SplitIsImmutable` (`:638`), while the yield global is
     *      written nowhere and its setter is merely gated. This case does NOT
     *      switch the skim on: PP-D13 requires A.3's strict rise and E.4's debit
     *      before any non-zero yield fee, and enabling it here would brick the
     *      donation path rather than evidence E.3. The probe value is `10e16`,
     *      the constitution's own figure — chosen because `withValidYieldFee`
     *      runs BEFORE `authenticate`, so an out-of-range value would revert on
     *      precision and never reach the gate this case is asserting.
     */
    function test_P1_E3_globalYieldFeeIsZeroAndItsOnlyWriteSiteIsUnreachable() public {
        AureumGovernance gov = orchestrator.governance();
        address attacker = makeAddr("e3_attacker");
        uint256 constitutionalSkim = 10e16;

        // (1) Never initialised.
        assertEq(controller.getGlobalProtocolYieldFeePercentage(), 0, "E.3 - yield global is zero");

        // (2) The contrast: the swap global IS constructor-pinned, so (1) is an
        //     omission, not a protocol-wide fees-off posture.
        assertEq(
            controller.getGlobalProtocolSwapFeePercentage(),
            50e16,
            "E.3 - swap global pinned at construction"
        );

        // (3) Consequence: every live pool carries a zero aggregate yield fee.
        for (uint256 i = 0; i < pilotPools.length; ++i) {
            PoolConfig memory cfg = vault.getPoolConfig(pilotPools[i]);
            assertEq(cfg.aggregateYieldFeePercentage, 0, "E.3 - pool stamped 0% aggregate yield");
        }

        // (4) The sole write site is unreachable. 10e16 clears withValidYieldFee
        //     so the revert proves the authenticate gate, not the range check.
        address[3] memory blocked = [attacker, address(orchestrator), EMERGENCY_MULTISIG];
        for (uint256 i = 0; i < blocked.length; ++i) {
            vm.prank(blocked[i]);
            vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
            controller.setGlobalProtocolYieldFeePercentage(constitutionalSkim);
        }

        // ... and governance holds the action yet has no arm that emits it.
        bool govAllowed = AureumGovernanceAuthorizer(address(vault.getAuthorizer())).canPerform(
            controller.getActionId(
                AureumProtocolFeeController.setGlobalProtocolYieldFeePercentage.selector
            ),
            address(gov),
            address(controller)
        );
        assertTrue(govAllowed, "E.3 - governance authorized; the barrier is the missing path");
        assertEq(controller.getGlobalProtocolYieldFeePercentage(), 0, "E.3 - still zero after every attempt");
    }

    /// @dev C.6 veto-leg candidate — RAIL-LESS by construction: [sfrxETH 0.6, wOETH 0.4], neither
    ///      svZCHF nor sUSDS, so AureumFeeRoutingHook.onRegister writes poolBodenseeDepositToken
    ///      = address(0) and the PB-D69 conjunct stays live for the flag to move. Both are
    ///      GaugeGenesisManifest-admitted classes (indices 6 and 7), so the CQG's 0.52e18
    ///      admitted-4626 numerator is met at 100%; both carry a rate provider, so awpf's
    ///      MIN_ERC4626_WEIGHT (52e16) is met at 100%. Those are different predicates and this
    ///      pair clears each independently. sfrxETH (0xac3E) < wOETH (0xDcEe) on mainnet, so that
    ///      order is the sorted one; swapping them reverts TokensNotSorted. Rate providers are
    ///      constructed here rather than recovered from env: setUp's instances are locals, and a
    ///      test must not write the process env (RB-023).
    function _buildRailLessCandidate() internal returns (address candidate) {
        ERC4626RateProvider sfrxEthRp = new ERC4626RateProvider(IERC4626(IxAetheronConfig.SFRXETH));
        ERC4626RateProvider wOethRp = new ERC4626RateProvider(IERC4626(IxAetheronConfig.WOETH));
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0] = TokenConfig({
            token: IERC20(IxAetheronConfig.SFRXETH),
            tokenType: TokenType.WITH_RATE,
            rateProvider: IRateProvider(address(sfrxEthRp)),
            paysYieldFees: true
        });
        tokens[1] = TokenConfig({
            token: IERC20(IxAetheronConfig.WOETH),
            tokenType: TokenType.WITH_RATE,
            rateProvider: IRateProvider(address(wOethRp)),
            paysYieldFees: true
        });
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.6e18;
        weights[1] = 0.4e18;
        candidate = awpf.create(
            "P1 C6 Rail-less Candidate",
            "C6CAND",
            tokens,
            weights,
            PoolRoleAccounts({ pauseManager: address(0), swapFeeManager: address(0), poolCreator: address(0) }),
            0.0075e18,
            address(hook),
            false,
            false,
            keccak256("p1_c6_railless_candidate")
        );
    }

    /// @notice P1 C.6 veto leg — `admissionAuthority` annuls a CompositionChallenge that already
    ///         passed, and the proposer's non-refundable bond is burned.
    /// @dev Reproduction PoC for C.6's THIRD audit file,
    ///      `admission-authority-vetoes-passed-composition-proposal` (M), completing rung 8
    ///      alongside the StageG grant and rotation legs. `recoveryPathAdmitted` is the ONLY
    ///      input to the composition gate a third party can falsify between propose and execute;
    ///      every other input is immutable or written once at pool registration. The revert at
    ///      beat 4 is the INNER `NoFeeRailAndNotAdmitted`, not `CompositionQualityGateFailed`:
    ///      `GaugeRegistry.meetsCompositionQualityGate` is a bare pass-through (`:244-246`) with
    ///      no try/catch, so eligibility's revert propagates and governance's
    ///      `if (!...) revert CompositionQualityGateFailed` at `:429` never evaluates. That outer
    ///      error is the sub-0.52 return-false path, which this candidate never takes.
    ///      `_seatVoter` runs BEFORE propose: seating after would snapshot ahead of the poke and
    ///      `getPastVotes(snapshotBlock)` would read zero.
    function test_P1_C6_admissionAuthorityAnnulsPassedCompositionChallenge() public {
        address voter = makeAddr("p1_c6_veto_voter");
        _seatVoter(voter);
        GaugeRegistry gr = orchestrator.gaugeRegistry();
        AureumGovernance gov = orchestrator.governance();
        GaugeEligibility elig = GaugeEligibility(gr.gaugeEligibility());
        address oldPool = orchestrator.miliariumRegistry().poolAtSlot(5);

        // (1) A rail-less candidate: the conjunct is live, so the flag is load-bearing.
        address candidate = _buildRailLessCandidate();
        assertEq(hook.poolBodenseeDepositToken(candidate), address(0), "premise - candidate is rail-less");

        // (2) The attestation is the ONLY thing that lets it clear the gate.
        vm.prank(address(orchestrator));
        elig.setRecoveryPathAdmitted(candidate, true);
        assertTrue(gr.meetsCompositionQualityGate(candidate), "admitted - gate passes at propose time");

        // (3) Propose slot 5, carry the vote to the executable block, stop BEFORE execute.
        deal(address(svZchf), voter, PROPOSAL_DEPOSIT);
        vm.startPrank(voter);
        svZchf.approve(address(gov), PROPOSAL_DEPOSIT);
        uint256 id = gov.proposeCompositionChallenge(5, candidate, svZchf);
        vm.stopPrank();
        assertEq(svZchf.balanceOf(voter), 0, "bond pulled and donated before the proposal record exists");
        _runProposalToQueued(id, voter);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Queued), "passed 2/3 and queued");

        // (4) One untimelocked call by a non-participant annuls the passed vote.
        vm.prank(address(orchestrator));
        elig.setRecoveryPathAdmitted(candidate, false);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.NoFeeRailAndNotAdmitted.selector, candidate));
        gov.execute(id);
        assertEq(
            uint256(gov.state(id)),
            uint256(AureumGovernance.ProposalState.Queued),
            "C.6 - execute reverted, the executed flag rolled back, proposal still Queued and retryable"
        );

        // (5) Invisible until execute, terminal once the grace window closes.
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        vm.roll(p.eta + AureumTime.BLOCKS_PER_EPOCH);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Expired), "C.6 - grace expired, no path back");
        vm.expectRevert(abi.encodeWithSelector(AureumGovernance.GracePeriodExpired.selector, id));
        gov.execute(id);
        assertEq(svZchf.balanceOf(voter), 0, "C.6 - bond gone, no refund path in AureumGovernance");
        assertEq(orchestrator.miliariumRegistry().poolAtSlot(5), oldPool, "C.6 - slot unchanged; the passed vote was annulled");
    }

    /// @notice P1 G.3 — a candidate is pre-poisoned by a permissionless `activateGauge`, and the
    ///         poisoning is permanent because no writer returns a gauge status to `None`.
    /// @dev Reproduction PoC for seam-1 root cause G.3 (High), fix-sequence rung 9.
    ///      `GaugeRegistry.activateGauge` is permissionless for the 100 svZCHF anti-spam fee,
    ///      `proposeCompositionChallenge` never reads the candidate's gauge status (`:239-245`
    ///      checks only the composition quality gate), and `registerGaugeFromComposition` reverts
    ///      `AlreadyGauged` on an `Active` pool (`GaugeRegistry.sol:168-171`). So any credible
    ///      candidate becomes permanently unseatable the moment it carries the hook and clears
    ///      the TVL floor, possibly years before anyone proposes it. The poisoning is driven
    ///      BEFORE the proposal here because that is the finding's shape: propose-blindness is
    ///      the first half, the execute revert the second. PP-D9 ties a `GaugeChallenge`
    ///      execute-time `slotOf == 0` re-check to G.3's FIX; that is a fix constraint and does
    ///      not bind this reproduction. The candidate is the railed C1 shape, initialized so the
    ///      real TVLOracle values it: `_constellationRatio(svZCHF)` returns 1e18, so the svZCHF
    ///      leg alone clears `TVL_FLOOR_SVZCHF` even if sUSDS resolves no venue.
    function test_P1_G3_permissionlessActivationPermanentlyBricksCompositionChallenge() public {
        address voter = makeAddr("p1_g3_voter");
        _seatVoter(voter);
        GaugeRegistry gr = orchestrator.gaugeRegistry();
        AureumGovernance gov = orchestrator.governance();
        GaugeEligibility elig = GaugeEligibility(gr.gaugeEligibility());
        address oldPool = orchestrator.miliariumRegistry().poolAtSlot(5);

        // A credible candidate: railed, CQG-clean, funded past the eligibility TVL floor that
        // activateGauge enforces and the composition gate omits.
        address candidate = _buildCompositionCandidate();
        IERC20[] memory tokens = vault.getPoolTokens(candidate);
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = 30_000e18;
        amountsIn[1] = 20_000e18;
        _initializePool(candidate, tokens, amountsIn);
        assertGe(
            orchestrator.tvlOracle().tvl(candidate),
            elig.TVL_FLOOR_SVZCHF(),
            "premise - candidate clears the eligibility TVL floor"
        );
        assertTrue(gr.meetsCompositionQualityGate(candidate), "premise - composition gate passes");
        assertTrue(gr.gaugeStatus(candidate) == IGaugeRegistry.GaugeStatus.None, "premise - not yet gauged");

        // (1) The poisoning. Anyone, for the anti-spam fee: no governance, no admission, no vote.
        address attacker = makeAddr("p1_g3_attacker");
        uint256 fee = gr.ANTI_SPAM_FEE();
        deal(address(svZchf), attacker, fee);
        vm.startPrank(attacker);
        svZchf.approve(address(gr), fee);
        gr.activateGauge(candidate);
        vm.stopPrank();
        assertTrue(
            gr.gaugeStatus(candidate) == IGaugeRegistry.GaugeStatus.Active,
            "G.3 - candidate pre-poisoned by one permissionless 100 svZCHF call"
        );

        // (2) Propose is blind to gauge status, so the challenge is accepted and the bond burns.
        deal(address(svZchf), voter, PROPOSAL_DEPOSIT);
        vm.startPrank(voter);
        svZchf.approve(address(gov), PROPOSAL_DEPOSIT);
        uint256 id = gov.proposeCompositionChallenge(5, candidate, svZchf);
        vm.stopPrank();
        assertEq(svZchf.balanceOf(voter), 0, "G.3 - bond donated at propose; no cancel and no refund path");

        // (3) The vote passes, and execute reverts on the poisoning.
        _runProposalToQueued(id, voter);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Queued), "passed 2/3 and queued");
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.AlreadyGauged.selector, candidate));
        gov.execute(id);

        // (4) Permanent: no writer returns a status to None, so every retry hits the same revert
        //     and the proposal ages out of its grace window.
        assertTrue(
            gr.gaugeStatus(candidate) == IGaugeRegistry.GaugeStatus.Active,
            "G.3 - still Active; nothing returns a gauge to None"
        );
        AureumGovernance.Proposal memory p = gov.getProposal(id);
        vm.roll(p.eta + AureumTime.BLOCKS_PER_EPOCH);
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Expired), "G.3 - grace expired");
        assertEq(
            orchestrator.miliariumRegistry().poolAtSlot(5),
            oldPool,
            "G.3 - slot unchanged; a passed 2/3 supermajority defeated for 100 svZCHF"
        );
    }

    /// @dev G.2 second candidate — identical shape to `_buildCompositionCandidate`, distinct salt
    ///      and symbol so both can exist in one test. Railed and CQG-clean; no initialization is
    ///      needed because `registerGaugeFromComposition` is onlyGovernance and never runs
    ///      `evaluateEligibility`, and the composition gate omits the TVL floor.
    function _buildCompositionCandidateB() internal returns (address candidate) {
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0] = TokenConfig({
            token: IERC20(address(susds)),
            tokenType: TokenType.WITH_RATE,
            rateProvider: IRateProvider(SUSDS_RATE_PROVIDER),
            paysYieldFees: true
        });
        tokens[1] = TokenConfig({
            token: svZchf,
            tokenType: TokenType.WITH_RATE,
            rateProvider: IRateProvider(SV_ZCHF_RATE_PROVIDER),
            paysYieldFees: true
        });
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.6e18;
        weights[1] = 0.4e18;
        candidate = awpf.create(
            "P1 G2 Candidate B",
            "G2CANDB",
            tokens,
            weights,
            PoolRoleAccounts({ pauseManager: address(0), swapFeeManager: address(0), poolCreator: address(0) }),
            0.0075e18,
            address(hook),
            false,
            false,
            keccak256("p1_g2_candidate_b")
        );
    }

    /// @notice P1 G.2 — a composition challenge is a mandate against a SLOT, not against the pool
    ///         the electorate voted to remove, so the second of two concurrent challenges revokes
    ///         the winner of the first.
    /// @dev Reproduction PoC for seam-1 root cause G.2 (Medium), fix-sequence rung 9.
    ///      `proposeCompositionChallenge` stores the slot index and passes `address(0)` as
    ///      `targetPool`, so nothing records which occupant the vote was against; `_executeProposal`
    ///      then re-resolves `SLOT_REGISTRY.poolAtSlot(p.slot)` at EXECUTE time and terminally
    ///      revokes whoever is sitting there (`AureumGovernance.sol:428-433`). `_createProposal`
    ///      has no per-slot dedup, so two challenges on one slot both open. Both are proposed
    ///      here against the SAME incumbent and both pass; executing them in order seats A and
    ///      then revokes A on behalf of voters who never saw A on the ballot. The plan records
    ///      the realistic path as an honest double-proposal accident, not an attack, which is why
    ///      both proposals are honest and neither proposer is adversarial. Driven inline rather
    ///      than through `_runProposalToQueued`: both proposals share one schedule, so a second
    ///      call would roll backward to a snapshot already passed.
    function test_P1_G2_secondSlotChallengeRevokesTheWinnerOfTheFirst() public {
        address voter = makeAddr("p1_g2_voter");
        _seatVoter(voter);
        GaugeRegistry gr = orchestrator.gaugeRegistry();
        AureumGovernance gov = orchestrator.governance();
        address incumbent = orchestrator.miliariumRegistry().poolAtSlot(5);
        assertTrue(incumbent != address(0), "premise - slot 5 is occupied");

        address candidateA = _buildCompositionCandidate();
        address candidateB = _buildCompositionCandidateB();
        assertTrue(candidateA != candidateB, "premise - two distinct candidates");
        assertTrue(gr.meetsCompositionQualityGate(candidateA), "premise - A clears the gate");
        assertTrue(gr.meetsCompositionQualityGate(candidateB), "premise - B clears the gate");

        // Two honest challenges on the SAME slot, opened in the same block against the SAME
        // incumbent. Nothing dedups them, and neither records the occupant it targets.
        deal(address(svZchf), voter, PROPOSAL_DEPOSIT * 2);
        vm.startPrank(voter);
        svZchf.approve(address(gov), PROPOSAL_DEPOSIT * 2);
        uint256 idA = gov.proposeCompositionChallenge(5, candidateA, svZchf);
        uint256 idB = gov.proposeCompositionChallenge(5, candidateB, svZchf);
        vm.stopPrank();
        assertTrue(idA != idB, "two live proposals on one slot");

        // One shared schedule: vote both, queue both, then execute in order.
        AureumGovernance.Proposal memory pa = gov.getProposal(idA);
        vm.roll(pa.snapshotBlock + 1);
        vm.startPrank(voter);
        gov.castVote(idA, true);
        gov.castVote(idB, true);
        vm.stopPrank();
        vm.roll(pa.endBlock + 1);
        gov.queue(idA);
        gov.queue(idB);
        AureumGovernance.Proposal memory qa = gov.getProposal(idA);
        vm.roll(qa.eta);

        // First challenge executes as its voters intended: the incumbent is replaced by A.
        gov.execute(idA);
        assertEq(orchestrator.miliariumRegistry().poolAtSlot(5), candidateA, "A seated by its own challenge");
        assertTrue(gr.gaugeStatus(incumbent) == IGaugeRegistry.GaugeStatus.Revoked, "incumbent revoked as voted");
        assertTrue(gr.gaugeStatus(candidateA) == IGaugeRegistry.GaugeStatus.Active, "A gauged from composition");

        // Second challenge re-resolves the victim at execute and takes A instead of the incumbent.
        gov.execute(idB);
        assertEq(orchestrator.miliariumRegistry().poolAtSlot(5), candidateB, "B seated");
        assertTrue(
            gr.gaugeStatus(candidateA) == IGaugeRegistry.GaugeStatus.Revoked,
            "G.2 - A was terminally revoked by a mandate its voters cast against the incumbent"
        );
    }

    /// @notice P1 D.5 — an unfunded `updateEMA` outage lets anyone ratchet the electorate to zero,
    ///         and the kill is permanent per proposal even after live state recovers.
    /// @dev Reproduction PoC for seam-1 root cause D.5 (Medium), fix-sequence rung 10.
    ///      `VotingWeight._positionPower` returns 0 once `block.number - lastEMAUpdateBlock`
    ///      exceeds `EMA_STALENESS_BLOCKS` (`AureumTime.BLOCKS_PER_EPOCH`, 100_800, ~14 days), and
    ///      `poke` is unconditionally permissionless: it recomputes weight across every Miliarium
    ///      pool, writes the zero to `_holderWeight`, subtracts it from `_totalQualifiedWeight`,
    ///      and PUSHES BOTH TO CHECKPOINT HISTORY. That push is the ratchet. `getPastTotalSupply`
    ///      reads history, so `AureumGovernance._voteSucceeded` hits its F-21 guard at `:367`
    ///      (`snapshotSupply == 0` returns false) for any proposal whose snapshot fell in the
    ///      zeroed window, and `state()` at `:339` derives `Defeated` permanently.
    ///      ORDERING IS LOAD-BEARING: the zeroing `poke` must precede the propose. Proposing first
    ///      puts `snapshotBlock` at `start + VOTING_DELAY_BLOCKS`, which a later recovery poke can
    ///      heal, and the case would silently fail to reproduce.
    ///      `Defeated` is NOT reachable at `snapshotBlock + 1`: `state()` returns `Active` while
    ///      `block.number <= endBlock` and only then evaluates `_voteSucceeded`, so the kill is
    ///      latent until the vote closes. Both readings are asserted.
    ///      The `VotingWeight` handle is cached BEFORE the prank per P-D38: a chained
    ///      `orchestrator.votingWeight().poke(...)` would spend the prank on the getter, so `poke`
    ///      would run as this contract and the third-party claim would be false.
    ///      POST-FIX TARGET, not asserted here: PP-D31 locks the keeper model as (c), folding
    ///      `updateEMA` into the first `recordScore`/`claim` of the day. Once that lands an outage
    ///      narrows to an idle-and-keeper-only freeze because active pools self-heal. This case
    ///      runs against PRE-FOLD code, where nothing self-heals, so it reproduces the
    ///      unconditional zero-write and its ratchet. Freeze-not-zero is the fix intent, not the
    ///      finding.
    function test_P1_D5_staleEmaLetsAnyonePermanentlyRatchetTheElectorateToZero() public {
        address voter = makeAddr("p1_d5_voter");
        _seatVoter(voter);
        AureumGovernance gov = orchestrator.governance();
        VotingWeight vw = orchestrator.votingWeight();

        // Premise: a matured, fresh position confers real governance weight.
        assertGt(vw.governanceWeight(voter), 0, "premise - voter carries weight while the EMA is fresh");
        assertGt(vw.totalSupply(), 0, "premise - the electorate is non-empty");

        // (1) The outage: no updateEMA for longer than the staleness window.
        vm.roll(block.number + AureumTime.BLOCKS_PER_EPOCH + 1);

        // (2) The ratchet. poke is permissionless and carries no staleness guard of its own, so an
        //     arbitrary third party writes the zero and checkpoints it.
        address rando = makeAddr("p1_d5_rando");
        vm.prank(rando);
        vw.poke(voter);
        assertEq(vw.governanceWeight(voter), 0, "D.5 - a third party zeroed the holder's weight");
        assertEq(vw.totalSupply(), 0, "D.5 - the quorum denominator is now zero");

        // (3) A proposal opened after the zeroing takes its snapshot inside the zeroed window.
        deal(address(svZchf), voter, PROPOSAL_DEPOSIT);
        vm.startPrank(voter);
        svZchf.approve(address(gov), PROPOSAL_DEPOSIT);
        uint256 id = gov.proposeVaultUnpause(svZchf);
        vm.stopPrank();
        AureumGovernance.Proposal memory p = gov.getProposal(id);

        // (4) Latent, then terminal: Active while the window is open, Defeated once it closes.
        vm.roll(p.snapshotBlock + 1);
        assertEq(vw.getPastTotalSupply(p.snapshotBlock), 0, "D.5 - the snapshotted denominator is zero");
        assertEq(uint256(gov.state(id)), uint256(AureumGovernance.ProposalState.Active), "still Active mid-window");
        vm.roll(p.endBlock + 1);
        assertEq(
            uint256(gov.state(id)),
            uint256(AureumGovernance.ProposalState.Defeated),
            "D.5 - F-21 defeats it on a zero denominator"
        );

        // (5) The coda, and the reason this is Medium: live state recovers, the proposal does not.
        orchestrator.emaSampler().updateEMA(pilotPools[0]);
        vw.poke(voter);
        assertGt(vw.governanceWeight(voter), 0, "D.5 - live weight recovers for gas, by anyone");
        assertEq(
            uint256(gov.state(id)),
            uint256(AureumGovernance.ProposalState.Defeated),
            "D.5 - the kill is permanent per proposal; recovery heals only future snapshots"
        );
    }

    // -------------------------------------------------------------------------
    // C.5 — permanent self-service protocol-fee exemption (High face)
    // -------------------------------------------------------------------------

    /// @notice Reproduction of seam-1 root cause C.5's HIGH face: pauseManager pauses, anyone
    ///         enables recovery mode while paused, unpause clears the pause but not the bit, swaps
    ///         continue and the protocol's half of the swap-fee split never accrues. Faces NOT
    ///         reproduced: the pauseVault() variant handing any address 27 permanent bits whose
    ///         exit grant dies with the entry grant at twelve months, and the Low-downgraded
    ///         pool-role-accounts face where no admission gate reads getPoolRoleAccounts so an
    ///         outsider-created pool can carry a permanent swapFeeManager. The row's yield-fee
    ///         angle is MOOT for Aureum — PoolDataLib L49-L51 gates yield fees on recovery mode
    ///         but E.3 established the aggregate yield fee is permanently zero, so the swap-fee
    ///         gate at Vault.sol L1061 carries the whole High face.
    function test_P1_C5_threeCallsOptAPoolOutOfTheProtocolFeeSplitPermanently() public {
        address pool = pilotPools[0];

        // Control: healthy pool donates the protocol half into der Bodensee (mirrors L783-L793).
        uint256 reserveBeforeControl = _bodenseeReserve(svZchf);
        uint256 amountOutControl = _performSwap(pool, IERC20(address(susds)), svZchf, 1e18);
        assertGt(amountOutControl, 0, "control swap produced output");
        assertGt(
            _bodenseeReserve(svZchf),
            reserveBeforeControl,
            "control - protocol half reaches der Bodensee on a healthy pool"
        );
        uint256 controlDelta = _bodenseeReserve(svZchf) - reserveBeforeControl;

        // Three-call sequence: pause (pauseManager) -> enableRecoveryMode (permissionless while
        // paused per VaultAdmin L349-L352) -> unpause (pauseManager). The bit survives unpause.
        vm.prank(address(orchestrator));
        vault.pausePool(pool);
        vault.enableRecoveryMode(pool);
        vm.prank(address(orchestrator));
        vault.unpausePool(pool);

        // Second swap: still trades, but aggregate swap fees are not charged in recovery mode
        // (Vault.sol L1059-L1061) while the total swap fee is still computed for off-chain
        // reporting, so the exemption is invisible to anything reading reported fees.
        uint256 reserveBeforeExempt = _bodenseeReserve(svZchf);
        emit log_named_uint("hook svZCHF balance before recovery-mode swap", svZchf.balanceOf(address(hook)));
        emit log_named_uint("hook sUSDS balance before recovery-mode swap", susds.balanceOf(address(hook)));
        uint256 amountOutExempt = _performSwap(pool, IERC20(address(susds)), svZchf, 1e18);
        uint256 recoveryDelta = _bodenseeReserve(svZchf) - reserveBeforeExempt;
        emit log_named_uint("controlDelta Bodensee reserve rise (healthy)", controlDelta);
        emit log_named_uint("recoveryDelta Bodensee reserve rise (recovery mode)", recoveryDelta);
        assertGt(amountOutExempt, 0, "pool is still trading after the three-call sequence");
        // Exact flatness is the wrong shape here: the hook does not compute its own fee but
        // collects the Vault's already-charged aggregate through collectSwapAggregateFeesForHook
        // at AureumFeeRoutingHook.sol L381-L383, so recovery mode starves the path at its source.
        // Measured on this fixture the control rise is 24963783544357 and the recovery-mode rise
        // is 2483268481, a ratio of about 10053 to 1; the hook held ZERO svZCHF and ZERO sUSDS
        // immediately before the recovery-mode swap, as the emitted logs show, so the residual is
        // NOT swept hook dust; and the residual's source is NOT established by this test. The
        // claim under test is that the protocol half stopped, evidenced by the collapse in
        // magnitude; attaching an unverified cause to a correct measurement is the failure lesson
        // PB22 names.
        assertGt(controlDelta, 0, "protocol half reaches der Bodensee on a healthy pool");
        assertTrue(
            recoveryDelta * 1000 < controlDelta,
            "protocol half stopped flowing in recovery mode per Vault.sol L1059-L1061; recovery-mode rise is over three orders of magnitude below the control"
        );
    }

    /// @notice The recovery bit survives unpause and disqualifies nothing on the Aureum side.
    function test_P1_C5_theRecoveryBitSurvivesUnpauseAndDisqualifiesNothing() public {
        // Absence result verified by grep and not re-derived here: recovery mode appears in
        // Aureum source only in AureumGovernanceAuthorizer's action IDs and at
        // AureumGovernance.sol L443's disableRecoveryMode exit call; nothing in src/gauge/ or
        // src/emission/ reads isPoolInRecoveryMode, which is why eligibility and scoring are
        // blind to it.
        address pool = pilotPools[0];
        address lp = makeAddr("p1_c5_lp");

        // Score the pool while healthy so recordScore after the bit is set has a live EMA path.
        _matureStack(lp);

        vm.prank(address(orchestrator));
        vault.pausePool(pool);
        vault.enableRecoveryMode(pool);
        vm.prank(address(orchestrator));
        vault.unpausePool(pool);

        assertTrue(
            vault.isPoolInRecoveryMode(pool),
            "recovery bit survives unpausePool; it does not clear and has no expiry"
        );
        assertTrue(
            orchestrator.gaugeRegistry().isGaugeApproved(pool),
            "no Aureum contract reads the recovery bit; gauge approval is unchanged"
        );

        orchestrator.emissionDistributor().recordScore(pool);
        assertGt(
            orchestrator.emissionDistributor().poolScore(pool),
            0,
            "no Aureum contract reads the recovery bit; recordScore still writes a nonzero poolScore"
        );
    }
}
