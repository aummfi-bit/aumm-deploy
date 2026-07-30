// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, TokenType, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { Router } from "@balancer-labs/v3-vault/contracts/Router.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { AuMM } from "../../src/token/AuMM.sol";
import { AureumAuthorizer } from "../../src/vault/AureumAuthorizer.sol";
import { AureumFeeRoutingHook } from "../../src/fee_router/AureumFeeRoutingHook.sol";
import { AureumProtocolFeeController } from "../../src/vault/AureumProtocolFeeController.sol";
import { AureumWeightedPoolFactory } from "../../src/factory/AureumWeightedPoolFactory.sol";

import { DeployTestnetStubs } from "../../test-stubs/DeployTestnetStubs.s.sol";
import { DeployAureumVault } from "../../script/DeployAureumVault.s.sol";
import { DeployStageP } from "../../script/DeployStageP.s.sol";
import { DeployFeeRoutingHook } from "../../script/DeployFeeRoutingHook.s.sol";
import { DeployAuMM } from "../../script/DeployAuMM.s.sol";
import { DeployAureumWeightedPoolFactory } from "../../script/DeployAureumWeightedPoolFactory.s.sol";
import { DeployRouter } from "../../script/DeployRouter.s.sol";
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
 * @title  StagePRunRehearsalTest
 * @notice PB3.4d2 (PB-D25) — the production-`run()` rehearsal on a mainnet fork at future genesis.
 *         A standalone harness (NOT a StagePIntegrationFixture subclass, per PB-D25 (b) — the P10
 *         close gate stays byte-identical): setUp deploys the base layer with a real-EOA governor and
 *         a full stub roster replayed in-process from DeployTestnetStubs, at GENESIS_BLOCK = fork
 *         block + one epoch, then drives the composed DeployStageP.run() (the production spine, not
 *         deploy()). The test body re-asserts the four post-conditions (d2c) and the Router seat (d2d).
 * @dev    Run file-scoped per D35/D36: forge test match-path on this file, fork-url mainnet, threads 1.
 */
contract StagePRunRehearsalTest is Test {
    bytes32 internal constant VAULT_SALT = bytes32(uint256(1));
    bytes32 internal constant BODENSEE_SALT = bytes32(uint256(2));
    uint32 internal constant PAUSE_WINDOW_DURATION = uint32(4 * 365 days);
    uint256 internal constant BUFFER_PERIOD_DURATION = 90 days;
    uint256 internal constant MIN_TRADE_AMOUNT = 1_000_000;
    uint256 internal constant MIN_WRAP_AMOUNT = 1_000;
    string internal constant FACTORY_VERSION = '{"name":"AureumWeightedPoolFactory","version":1,"deployment":"20260718-fork-rehearsal"}';
    string internal constant POOL_VERSION = '{"name":"AureumWeightedPool","version":1,"deployment":"20260718-fork-rehearsal"}';
    // The real mainnet susds / svZchf RP literals — used only as the STUB_ lookup keys for the bodensee stub RPs.
    address internal constant SUSDS_RATE_PROVIDER = 0x1195BE91e78ab25494C855826FF595Eef784d47B;
    address internal constant SV_ZCHF_RATE_PROVIDER = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;
    uint256 internal constant INIT_SEED = 1_000e18;
    address internal constant EMERGENCY_MULTISIG = address(uint160(uint256(keccak256("emergencyMultisig"))));
    // PB-D25 (a) — the real-EOA governor, distinct from the harness and the orchestrator.
    address internal constant GOVERNOR = address(uint160(uint256(keccak256("rehearsalGovernorEOA"))));
    // PB-D19 — one epoch (14 days) of block offset; the emission clock decouples from deploy time.
    uint256 internal constant GENESIS_OFFSET = 100_800;
    // PB3.3/PB-D22 Router-leg literals — mainnet WETH and the canonical cross-chain permit2.
    address internal constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant CANONICAL_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    DeployStageP internal orchestrator;
    DeployFeeRoutingHook internal hookScript;
    DeployAureumVault internal vaultScript;
    WeightedPoolFactory internal wpf;
    AureumWeightedPoolFactory internal awpf;
    AuMM internal aumm;
    AureumFeeRoutingHook internal hook;
    AureumProtocolFeeController internal controller;
    IVault internal vault;
    // Captured pre-run(): Stage K migrates the Vault's authorizer, so the base-layer seat needs holding.
    AureumAuthorizer internal baseAuthorizer;
    // The PB-D25 (iii) Router leg, deployed at the tail of setUp AFTER orchestrator.run().
    address internal router;
    address internal bodenseePool;
    IERC20 internal svZchf;
    IERC4626 internal susds;
    // Resolved from the STUB_ roster in setUp (the stub RPs for the bodensee stub susds / svZchf).
    IRateProvider internal bodenseeSusdsRp;
    IRateProvider internal bodenseeSvZchfRp;
    address[3] internal pilotPools;
    address[5] internal majorPools;
    address[18] internal stageNPools;

    function setUp() public {
        // PB3.5f1 (PB-D27 (vii)(1)) -- brackets the whole deployment spine so the SepETH target
        //                              is a measured number rather than an estimate.
        uint256 gasAtStart = gasleft();
        // PB-D25 (ii) — the stub roster runs FIRST: it publishes SV_ZCHF, SUSDS and the five N-D7 RP
        // keys that every downstream pool config reads during its own .run(), so nothing below may
        // precede it. No rate providers are constructed here (the P10 fixture builds five by hand) —
        // the replayed roster already carries them, stubbed 1:1 over StubERC4626.
        _replayStubs();

        svZchf = IERC20(vm.envAddress("SV_ZCHF"));
        susds = IERC4626(vm.envAddress("SUSDS"));

        orchestrator = new DeployStageP();

        // PB-D25 (a) — the real-EOA governor, NOT address(orchestrator): run() reads this key back in
        // _assertBaseLayerGovernorProduction and never overwrites it (only the deploy() path does).
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("GOVERNANCE_MULTISIG", vm.toString(GOVERNOR));

        hookScript = new DeployFeeRoutingHook();
        address predictedHook = vm.computeCreateAddress(address(hookScript), 1);

        vaultScript = new DeployAureumVault();
        // The harness's NEXT own CREATE is the wpf; the Bodensee CREATE3 salt is creator-scoped (P-D34).
        // Both predictions read the live nonce, so the _replayStubs CREATE above cannot skew them.
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
        baseAuthorizer = AureumAuthorizer(address(vault.getAuthorizer()));

        wpf = new WeightedPoolFactory(IVault(address(vault)), PAUSE_WINDOW_DURATION, FACTORY_VERSION, POOL_VERSION);
        assert(address(wpf) == wpfAddr);

        // PB-D19 — genesis one epoch (100_800 blocks) into the future; DeployAuMM reads the key with no
        // block.number clamp, so the emission clock decouples from deploy time.
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("GENESIS_BLOCK", vm.toString(block.number + GENESIS_OFFSET));
        // minterAdmin_ = GOVERNANCE_MULTISIG env = GOVERNOR (the PB-D25 (a) delta vs the P10 fixture).
        aumm = AuMM(new DeployAuMM().run());

        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("AUMM", vm.toString(address(aumm)));

        bodenseePool = wpf.create(
            "der-Bodensee",
            "BODENSEE",
            _bodenseeTokenConfigs(),
            _bodenseeWeights(),
            PoolRoleAccounts({
                pauseManager: GOVERNOR,
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

        // moduleAdmin_ = GOVERNOR — the hook's module seal fires under run()'s governor broadcast.
        hook = hookScript.deploy(
            address(vault),
            bodenseePool,
            svZchf,
            IERC20(address(susds)),
            IERC20(address(aumm)),
            address(controller),
            GOVERNOR
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

        // --- Pilots (initialized — G parity; seeds derived per slot, never the fixture's literals) ---
        pilotPools[0] = new DeployIxHelvetia().run();
        IERC20[] memory tokens0 = vault.getPoolTokens(pilotPools[0]);
        _initializePool(pilotPools[0], tokens0, _seedAmounts(tokens0));

        pilotPools[1] = new DeployIxEdelweiss().run();
        IERC20[] memory tokens1 = vault.getPoolTokens(pilotPools[1]);
        _initializePool(pilotPools[1], tokens1, _seedAmounts(tokens1));

        pilotPools[2] = new DeployIxAurebit().run();
        IERC20[] memory tokens2 = vault.getPoolTokens(pilotPools[2]);
        _initializePool(pilotPools[2], tokens2, _seedAmounts(tokens2));

        // --- Majors (bind-only, uninitialized — M parity). The PB-D8 waEthwstETH composite RP the P10
        // fixture builds by hand here is already published by _replayStubs, so ixCasper's config
        // resolves it straight out of the replayed roster. ---
        majorPools[0] = new DeployIxCasper().run();
        majorPools[1] = new DeployIxBrevis().run();
        majorPools[2] = new DeployIxAltrix().run();
        majorPools[3] = new DeployIxMediox().run();
        majorPools[4] = new DeployIxLongus().run();

        // --- Sector-3 (bind-only, uninitialized — N parity, N-D0 canonical slot order). The four N-D9
        // rate providers likewise arrive from the replayed roster, not from fixture-local builds. ---
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

        // --- Orchestrate: the PRODUCTION spine per PB-D25 — run(), never the deploy() entry the P10
        // fixture drives. run() reads GOVERNANCE_MULTISIG back as the real EOA governor rather than
        // overriding it, asserts the base-layer seat matches, composes the sub-scripts' own run()
        // entries under nested governor broadcasts (proven at PB3.4d1), and fires the four
        // post-conditions in-run at the future genesis. ---
        orchestrator.run();

        // --- PB-D25 (iii) Router leg: DEPLOY ONLY. The hook's governanceModule stays unset here, so
        // the post-condition (3) at-rest baseline survives; seating is per-test via _seatRouter. ---
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("WETH_ADDRESS", vm.toString(MAINNET_WETH));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("PERMIT2_ADDRESS", vm.toString(CANONICAL_PERMIT2));
        router = new DeployRouter().run();

        uint256 spineGasUsed = gasAtStart - gasleft();
        console2.log("PB3.5f spine gas used (fork, setUp total):", spineGasUsed);
    }

    /// @dev 1_000 whole tokens per slot, scaled by each token's OWN decimals. The P10 fixture's
    ///      per-index literals cannot be transcribed onto the stub roster: WITH_RATE stubs are
    ///      uniformly 18-dec StubERC4626 while STANDARD stubs keep their mainnet decimals, and the
    ///      Vault's ascending-address slot order over freshly-CREATEd stubs bears no relation to the
    ///      mainnet order those literals were tuned against.
    function _seedAmounts(IERC20[] memory tokens) private view returns (uint256[] memory amounts) {
        amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            amounts[i] = 1_000 * 10 ** IERC20Metadata(address(tokens[i])).decimals();
        }
    }

    /// @dev PB-D25 (ii) — deploy the stub roster in-process and replay its full emission into env.
    ///      DeployTestnetStubs accumulates the STUB_ literal pairs plus the named keys (SV_ZCHF,
    ///      SUSDS, the five N-D7 RP keys); looping them through vm.setEnv gives the pool configs
    ///      and the base layer the same drift-free map the e2 capture and the PB3.5 broadcast
    ///      consume. The script's own _assertCoverage gate reverts the run on any unresolved slot.
    function _replayStubs() private {
        DeployTestnetStubs stubs = new DeployTestnetStubs();
        stubs.run();

        uint256 n = stubs.envPairCount();
        for (uint256 i = 0; i < n; ++i) {
            (string memory key, address val) = stubs.envPairAt(i);
            vm.setEnv(key, vm.toString(val));
        }

        // The bodensee legs are WITH_RATE: their stub RPs live under the STUB_ key of the REAL
        // mainnet RP literal (the same derivation _resolveStub uses), never a named key.
        bodenseeSusdsRp = IRateProvider(vm.envAddress(string.concat("STUB_", vm.toString(SUSDS_RATE_PROVIDER))));
        bodenseeSvZchfRp = IRateProvider(vm.envAddress(string.concat("STUB_", vm.toString(SV_ZCHF_RATE_PROVIDER))));
    }

    /// @dev The der-Bodensee token configs — AuMM STANDARD (no RP, no yield fees), the two stub
    ///      legs WITH_RATE against their replayed stub RPs. Slot order is the Vault's ascending
    ///      address sort, so each leg's identity is resolved per slot rather than assumed.
    function _bodenseeTokenConfigs() private view returns (TokenConfig[] memory) {
        address[3] memory addrs = _bodenseeSorted();
        TokenConfig[] memory tokens = new TokenConfig[](3);
        for (uint256 i = 0; i < 3; ++i) {
            tokens[i] = _bodenseeSlot(addrs[i]);
        }
        return tokens;
    }

    /// @dev One bodensee slot: AuMM is the STANDARD leg, susds / svZchf are WITH_RATE over stub RPs.
    function _bodenseeSlot(address t) private view returns (TokenConfig memory) {
        if (t == address(aumm)) {
            return TokenConfig({
                token: IERC20(t),
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            });
        }
        return TokenConfig({
            token: IERC20(t),
            tokenType: TokenType.WITH_RATE,
            rateProvider: t == address(susds) ? bodenseeSusdsRp : bodenseeSvZchfRp,
            paysYieldFees: true
        });
    }

    /// @dev The three bodensee tokens in ascending address order (the Vault's registration order).
    function _bodenseeSorted() private view returns (address[3] memory addrs) {
        addrs[0] = address(aumm);
        addrs[1] = address(susds);
        addrs[2] = address(svZchf);
        if (addrs[0] > addrs[1]) (addrs[0], addrs[1]) = (addrs[1], addrs[0]);
        if (addrs[1] > addrs[2]) (addrs[1], addrs[2]) = (addrs[2], addrs[1]);
        if (addrs[0] > addrs[1]) (addrs[0], addrs[1]) = (addrs[1], addrs[0]);
    }

    /// @dev 40/30/30 — AuMM takes the 40 percent leg, the two stable legs 30 percent each.
    function _bodenseeWeights() private view returns (uint256[] memory) {
        address[3] memory addrs = _bodenseeSorted();
        uint256[] memory weights = new uint256[](3);
        for (uint256 i = 0; i < 3; ++i) {
            weights[i] = addrs[i] == address(aumm) ? 4e17 : 3e17;
        }
        return weights;
    }

    /// @dev Bodensee init via the D32 beta-pattern: unlock, initialize, then per-token transfer plus
    ///      settle. Stub rates are pure 1:1, so the deal supply adjustment cannot skew them.
    function _initializeBodensee() private returns (uint256 bptOut) {
        deal(address(aumm), address(this), INIT_SEED, true);
        deal(address(susds), address(this), INIT_SEED, true);
        deal(address(svZchf), address(this), INIT_SEED, true);

        bytes memory result = vault.unlock(abi.encodeCall(this._initializeBodenseeCallback, ()));
        bptOut = abi.decode(result, (uint256));
    }

    function _initializeBodenseeCallback() external returns (uint256 bptOut) {
        require(msg.sender == address(vault), "onlyVault");

        address[3] memory addrs = _bodenseeSorted();
        IERC20[] memory tokens = new IERC20[](3);
        uint256[] memory amountsIn = new uint256[](3);
        for (uint256 i = 0; i < 3; ++i) {
            tokens[i] = IERC20(addrs[i]);
            amountsIn[i] = INIT_SEED;
        }

        bptOut = vault.initialize(bodenseePool, address(this), tokens, amountsIn, 0, "");
        for (uint256 i = 0; i < 3; ++i) {
            tokens[i].transfer(address(vault), amountsIn[i]);
            vault.settle(tokens[i], amountsIn[i]);
        }
    }

    /// @dev Pool init, same beta-pattern, generalized over the token set. Pilots only; the Majors and
    ///      the Sector-3 tranche stay bind-only per M / N parity.
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

    /// @notice PB3.4d2b2a gate — the base layer is seated with the PB-D25 / PB-D19 deltas live, before
    ///         any orchestration runs: the EOA governor (not the orchestrator) holds the authorizer seat
    ///         run() will check in _assertBaseLayerGovernorProduction, genesis sits one epoch out, both
    ///         bodensee stub RPs resolved out of the replayed roster, and der-Bodensee plus the three
    ///         pilots are initialized over stub liquidity.
    function test_baseLayer_seatedAtFutureGenesis() public view {
        assertEq(
            baseAuthorizer.GOVERNANCE_MULTISIG(),
            GOVERNOR,
            "authorizer seat is not the EOA governor"
        );
        assertTrue(GOVERNOR != address(orchestrator), "governor must not be the orchestrator");
        assertTrue(GOVERNOR != address(this), "governor must not be the harness");
        assertEq(aumm.GENESIS_BLOCK(), block.number + GENESIS_OFFSET, "genesis is not one epoch ahead");
        assertTrue(aumm.GENESIS_BLOCK() > block.number, "genesis must be in the future");
        assertTrue(address(bodenseeSusdsRp) != address(0), "susds stub RP unresolved");
        assertTrue(address(bodenseeSvZchfRp) != address(0), "svZchf stub RP unresolved");
        assertTrue(vault.isPoolInitialized(bodenseePool), "bodensee not initialized");
        for (uint256 i = 0; i < 3; ++i) {
            assertTrue(pilotPools[i] != address(0), "pilot pool unset");
            assertTrue(vault.isPoolInitialized(pilotPools[i]), "pilot pool not initialized");
        }
    }

    /// @notice Post-condition (1) — genesis uniformity, re-asserted test-side, plus the PB-D19 delta
    ///         run() cannot check: _assertPostConditions proves the four genesis slots AGREE, never
    ///         that they carry the FUTURE value. Pinning the common value at block.number plus
    ///         GENESIS_OFFSET is what catches a regression reverting genesis to deploy time.
    function test_postCondition1_genesisUniformAtFutureOffset() public view {
        uint256 gb = orchestrator.gaugeRegistry().GENESIS_BLOCK();
        assertEq(gb, block.number + GENESIS_OFFSET, "genesis is not the PB-D19 future offset");
        assertGt(gb, block.number, "genesis must still be in the future");
        assertEq(orchestrator.efficiencyOracle().GENESIS_BLOCK(), gb, "efficiencyOracle genesis diverged");
        assertEq(orchestrator.emissionDistributor().GENESIS_BLOCK(), gb, "emissionDistributor genesis diverged");
        assertEq(aumm.GENESIS_BLOCK(), gb, "AuMM genesis diverged");
    }

    /// @notice Post-condition (2) — every one of the 26 roster pools gauge-approved and recorder-bound.
    function test_postCondition2_roster26GaugedAndRecorderBound() public view {
        for (uint256 i = 0; i < 3; ++i) {
            _assertRosterPool(pilotPools[i]);
        }
        for (uint256 i = 0; i < 5; ++i) {
            _assertRosterPool(majorPools[i]);
        }
        for (uint256 i = 0; i < 18; ++i) {
            _assertRosterPool(stageNPools[i]);
        }
    }

    /// @dev One roster slot: gauge-approved, and its emission recorder bound to the fee-routing hook.
    function _assertRosterPool(address p) private view {
        assertTrue(p != address(0), "roster pool unset");
        assertTrue(orchestrator.gaugeRegistry().isGaugeApproved(p), "roster pool not gauged");
        assertEq(orchestrator.emissionDistributor().auMTContractByPool(p), address(hook), "roster pool recorder unbound");
    }

    /// @notice Post-condition (3) — the structural negative: run() fires no setTrustedRouter, and the
    ///         seat is governanceModule-gated, so an unset module proves the allowlist is necessarily
    ///         empty. PB3.4d2d seats it deliberately from exactly this at-rest baseline.
    function test_postCondition3_atRestNoTrustedRouter() public view {
        assertEq(hook.governanceModule(), address(0), "governance module unexpectedly seated");
        assertFalse(hook.trustedRouter(GOVERNOR), "governor unexpectedly trusted");
        assertFalse(hook.trustedRouter(address(orchestrator)), "orchestrator unexpectedly trusted");
        assertFalse(hook.trustedRouter(address(this)), "harness unexpectedly trusted");
    }

    /// @notice Post-condition (4) — the PB-D18 (v) CCB seal landed on the concrete GaugeRegistry. Under
    ///         run() it lands through the direct-governor path (PB-D23 (i)), not the f.sealGaugeRegistry
    ///         forward the prank spine uses, so this witnesses the production seal specifically.
    function test_postCondition4_ccbGaugeRegistrySealed() public view {
        assertEq(
            address(orchestrator.ccbMultiplier().gaugeRegistry()),
            address(orchestrator.gaugeRegistry()),
            "CCB gauge-registry seal missing"
        );
        assertTrue(
            address(orchestrator.ccbMultiplier().gaugeRegistry()) != address(orchestrator),
            "CCB seal still points at the deploy-time placeholder"
        );
    }

    /// @notice The authorizer migration — re-asserted against the pre-run baseline: run() checks only
    ///         that the Vault points at the Stage-K authorizer, while this additionally proves it MOVED
    ///         off the base-layer instance that carried the EOA-governor seat before orchestration.
    function test_postCondition_authorizerMigratedOffBaseLayer() public view {
        address live = address(vault.getAuthorizer());
        assertEq(live, address(orchestrator.authorizer()), "authorizer not migrated to the Stage-K instance");
        assertTrue(live != address(baseAuthorizer), "authorizer still the base-layer instance");
        assertEq(baseAuthorizer.GOVERNANCE_MULTISIG(), GOVERNOR, "base-layer seat was not the EOA governor");
    }

    /// @dev The PB-D22 (iii) seat sequence under the REAL EOA governor: the one-shot module-aim at
    ///      self, then the persistent allowlist entry. Each prank is single-shot and immediately
    ///      precedes its own call — never chained through an orchestrator getter, per PB10.
    function _seatRouter() internal {
        vm.prank(GOVERNOR);
        hook.setGovernanceModule(GOVERNOR);
        vm.prank(GOVERNOR);
        hook.setTrustedRouter(router, true);
    }

    /// @notice The Router deployed from script/DeployRouter.s.sol against the run()-built stack, with
    ///         version() reading the PB-D22 (iv) Aureum-branded string.
    function test_routerLeg_deployedWithAureumVersion() public view {
        assertTrue(router != address(0), "router not deployed");
        assertGt(router.code.length, 0, "router has no code");
        assertEq(
            Router(payable(router)).version(),
            "Aureum V3 Router v1 (Balancer V3 Router, pinned 68057fda)",
            "router version is not the Aureum-branded string"
        );
    }

    /// @notice The PB-D22 (iii) sequence driven by the REAL EOA governor rather than the orchestrator
    ///         contract — the distinction PB-D25 (a) exists to exercise: the at-rest premise, then the
    ///         one-shot aim at self, then the F-09 seat.
    function test_routerLeg_governorAimsModuleAndSeatsRouter() public {
        assertEq(hook.governanceModule(), address(0), "module seated before the aim");
        assertFalse(hook.trustedRouter(router), "router trusted before the seat");

        _seatRouter();

        assertEq(hook.governanceModule(), GOVERNOR, "module not aimed at the EOA governor");
        assertTrue(hook.trustedRouter(router), "router not seated on the F-09 allowlist");
    }

    /// @dev Fund `lp` and run the permit2 two-step toward the Router: ERC20 approve to canonical
    ///      permit2, then permit2.approve(token, router, amount, expiry).
    function _fundAndPermit(address lp, IERC20[] memory tokens, uint256[] memory amts) internal {
        vm.startPrank(lp);
        for (uint256 i = 0; i < tokens.length; ++i) {
            deal(address(tokens[i]), lp, amts[i]);
            tokens[i].approve(CANONICAL_PERMIT2, type(uint256).max);
            IPermit2(CANONICAL_PERMIT2).approve(
                address(tokens[i]), router, uint160(amts[i]), uint48(block.timestamp + 1 days)
            );
        }
        vm.stopPrank();
    }

    /// @dev `lp` adds 100 whole tokens of each pilot-0 leg through the Router via the permit2 two-step,
    ///      returning the BPT minted. Amounts scale by each token's OWN decimals for the same reason
    ///      _seedAmounts does — the stub roster does not preserve the mainnet decimal layout, so a flat
    ///      literal would be wrong the moment pilot 0 carries a non-18-decimal leg.
    function _routerAdd(address lp) internal returns (uint256 bptOut) {
        IERC20[] memory tokens = vault.getPoolTokens(pilotPools[0]);
        uint256[] memory amts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            amts[i] = 100 * 10 ** IERC20Metadata(address(tokens[i])).decimals();
        }
        _fundAndPermit(lp, tokens, amts);
        vm.prank(lp);
        bptOut = Router(payable(router)).addLiquidityUnbalanced(pilotPools[0], amts, 1, false, "");
    }

    /// @notice The PB-D25 (v) seated-add smoke assertion, closing the Router leg: once the EOA governor
    ///         has seated the Router, a REAL Router add drives the recorder — the hook resolves the LP
    ///         through getSender() and credits userLP to the true LP for exactly the BPT minted. The
    ///         positive counterpart to the post-condition (3) at-rest negative.
    function test_routerLeg_postSeatAddCreditsTrueLp() public {
        _seatRouter();

        address lp = makeAddr("rehearsalPostSeatLp");
        uint256 bptOut = _routerAdd(lp);

        assertGt(bptOut, 0, "router add minted no BPT");
        assertEq(IERC20(pilotPools[0]).balanceOf(lp), bptOut, "LP did not receive the minted BPT");
        assertEq(
            orchestrator.emissionDistributor().userLP(pilotPools[0], lp),
            bptOut,
            "recorder did not credit userLP to the true LP"
        );
    }
}
