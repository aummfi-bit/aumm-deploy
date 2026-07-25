// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, TokenType, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

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
        vm.setEnv("PILOT_POOL_01", vm.toString(pilotPools[0]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("PILOT_POOL_05", vm.toString(pilotPools[1]));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("PILOT_POOL_14", vm.toString(pilotPools[2]));
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
}
