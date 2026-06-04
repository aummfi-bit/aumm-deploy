// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    TokenConfig,
    TokenType,
    PoolRoleAccounts,
    SwapKind,
    HooksConfig,
    VaultSwapParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";

import { AuMM } from "../../src/token/AuMM.sol";
import { AureumFeeRoutingHook } from "../../src/fee_router/AureumFeeRoutingHook.sol";
import { AureumProtocolFeeController } from "../../src/vault/AureumProtocolFeeController.sol";
import { AureumWeightedPoolFactory } from "../../src/factory/AureumWeightedPoolFactory.sol";
import { DeployAureumVault } from "../../script/DeployAureumVault.s.sol";
import { DeployIxHelvetia } from "../../script/pools/DeployIxHelvetia.s.sol";
import { DeployIxEdelweiss } from "../../script/pools/DeployIxEdelweiss.s.sol";
import { DeployIxAurebit } from "../../script/pools/DeployIxAurebit.s.sol";
import { SwapAndDepositToBodensee } from "../../src/gauge/SwapAndDepositToBodensee.sol";
import { VaultClassRegistry } from "../../src/gauge/VaultClassRegistry.sol";
import { IVaultClassRegistry } from "../../src/gauge/IVaultClassRegistry.sol";
import { GaugeEligibility } from "../../src/gauge/GaugeEligibility.sol";
import { GaugeRegistry } from "../../src/gauge/GaugeRegistry.sol";
import { IGaugeRegistry } from "../../src/ccb/IGaugeRegistry.sol";
import { IEfficiencyOracle } from "../../src/gauge/IEfficiencyOracle.sol";
import { MockTVLOracle, MockMiliariumRegistry, MockGaugeRegistry } from "./mocks/CCBMocks.sol";
import { MockEfficiencyOracle, MockVotingWeight } from "./mocks/StageGMocks.sol";
import { CCBMultiplier } from "../../src/ccb/CCBMultiplier.sol";
import { IMiliariumRegistry } from "../../src/ccb/IMiliariumRegistry.sol";
import { IEMASampler } from "../../src/ccb/IEMASampler.sol";

/**
 * @title StageGIntegrationFixture
 * @notice Stage G cross-contract fork-test base wiring `VaultClassRegistry` + `GaugeEligibility` + `GaugeRegistry`
 *         together against real Bodensee + Stage E pilot pools per the **G-D25** family.
 * @dev **F-D11** layout; **F-D26 (a)** mirror of `CCBEngineFixture` without extending `MiliariumPilotPoolBase`; three
 *      pilots (ixHelvetia / ixEdelweiss / ixAurebit); **G-D25a** single-token genesis `[sUSDS] + [ImplementationAddress]`;
 *      **G-D25b** `_makePoolEligible` admission-before-TVL invariant; **G-D25c** mock home at
 *      `test/fork/mocks/StageGMocks.sol`; **F-D20—F23** parallel one-shot setter pattern; **G-D22** `setGaugeRegistry`
 *      deploy order; **D35** split-form invocation; **D36** + **F-D11** `--threads 1` fork-run requirement.
 */
abstract contract StageGIntegrationFixture is Test {
    // Constants — D-D21 / E-D24 parity (CCBEngineFixture mirror per F-D26 (a))
    bytes32 internal constant VAULT_SALT = bytes32(uint256(1));
    bytes32 internal constant BODENSEE_SALT = bytes32(uint256(2));
    uint32 internal constant PAUSE_WINDOW_DURATION = uint32(4 * 365 days);
    uint256 internal constant BUFFER_PERIOD_DURATION = 90 days;
    uint256 internal constant MIN_TRADE_AMOUNT = 1_000_000;
    uint256 internal constant MIN_WRAP_AMOUNT = 1_000;
    string internal constant FACTORY_VERSION = '{"name":"AureumWeightedPoolFactory","version":1,"deployment":"20260512-fork-stage-g"}';
    string internal constant POOL_VERSION = '{"name":"AureumWeightedPool","version":1,"deployment":"20260512-fork-stage-g"}';
    address internal constant GOVERNANCE_MULTISIG = address(uint160(uint256(keccak256("govMultisig"))));
    address internal constant SUSDS_RATE_PROVIDER = 0x1195BE91e78ab25494C855826FF595Eef784d47B;
    address internal constant SV_ZCHF_RATE_PROVIDER = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;
    uint256 internal constant INIT_SEED = 1_000e18;

    // State — Vault scaffold
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

    // State — Pilot pools (order: ixHelvetia[0] / ixEdelweiss[1] / ixAurebit[2])
    /// @notice ixHelvetia (slot 01), ixEdelweiss (slot 05), ixAurebit (slot 14).
    address[3] internal pilotPools;

    // State — Stage G contracts
    SwapAndDepositToBodensee internal swapAndDeposit;
    VaultClassRegistry internal vaultClassRegistry;
    GaugeEligibility internal gaugeEligibility;
    GaugeRegistry internal gaugeRegistry;

    // State — Mocks (TVL from CCBMocks per OQ-22 carry-forward; Efficiency + AuMT from StageGMocks per G-D25c)
    MockTVLOracle internal mockTVLOracle;
    MockEfficiencyOracle internal mockEfficiencyOracle;
    MockVotingWeight internal mockAuMT;

    function setUp() public virtual {
        svZchf = IERC20(vm.envAddress("SV_ZCHF"));
        susds = IERC4626(vm.envAddress("SUSDS"));

        uint64 startNonce = vm.getNonce(address(this));
        address vaultScriptAddr = vm.computeCreateAddress(address(this), startNonce + 0);
        address wpfAddr = vm.computeCreateAddress(address(this), startNonce + 1);
        address auMmAddr = vm.computeCreateAddress(address(this), startNonce + 2);
        address hookAddr = vm.computeCreateAddress(address(this), startNonce + 3);
        address awpfAddr = vm.computeCreateAddress(address(this), startNonce + 4);
        address predictedController = vm.computeCreateAddress(vaultScriptAddr, 2);
        address predictedFactory = vm.computeCreateAddress(vaultScriptAddr, 3);
        address predictedVault = CREATE3.getDeployed(VAULT_SALT, predictedFactory);
        address predictedBodensee = CREATE3.getDeployed(
            keccak256(abi.encode(address(this), block.chainid, BODENSEE_SALT)),
            wpfAddr
        );

        // Rationale: vm.setEnv is flagged by forge-lint as an "unsafe
        // cheatcode" because it mutates process environment state. In this
        // test it is the intentional harness mechanism for parameterizing
        // DeployAureumVault.s.sol — the script reads deployment config via
        // vm.envString / vm.envUint, so the fork test must populate those
        // env vars before calling deploy(). Scoped to setUp() in a fork
        // test; no production code path touches vm.setEnv. Per Foundry
        // lint best-practice ("Minimize Scope"), each call is suppressed
        // individually with a targeted disable-next-line directive.
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("GOVERNANCE_MULTISIG", vm.toString(GOVERNANCE_MULTISIG));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("DER_BODENSEE_POOL", vm.toString(predictedBodensee));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("FEE_ROUTING_HOOK", vm.toString(hookAddr));
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

        vaultScript = new DeployAureumVault();
        assert(address(vaultScript) == vaultScriptAddr);

        vaultScript.deploy(address(vaultScript));
        vault = vaultScript.vault();
        controller = vaultScript.aureumFeeController();
        assert(address(vault) == predictedVault);
        assert(address(controller) == predictedController);

        wpf = new WeightedPoolFactory(IVault(address(vault)), PAUSE_WINDOW_DURATION, FACTORY_VERSION, POOL_VERSION);
        assert(address(wpf) == wpfAddr);

        aumm = new AuMM(block.number, address(this));
        assert(address(aumm) == auMmAddr);

        bodenseePool = wpf.create("der-Bodensee", "BODENSEE", _bodenseeTokenConfigs(), _bodenseeWeights(), PoolRoleAccounts({pauseManager: GOVERNANCE_MULTISIG, swapFeeManager: address(0), poolCreator: address(0)}), 0.0075e18, address(0), true, false, BODENSEE_SALT);
        assert(bodenseePool == predictedBodensee);

        hook = new AureumFeeRoutingHook(address(vault), predictedBodensee, svZchf, IERC20(address(aumm)), address(controller), GOVERNANCE_MULTISIG);
        assert(address(hook) == hookAddr);

        awpf = new AureumWeightedPoolFactory(IVault(address(vault)), PAUSE_WINDOW_DURATION, FACTORY_VERSION, POOL_VERSION);
        assert(address(awpf) == awpfAddr);

        _initializeBodensee();

        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("AUREUM_WEIGHTED_POOL_FACTORY", vm.toString(address(awpf)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("FEE_ROUTING_HOOK", vm.toString(address(hook)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("GOVERNANCE_MULTISIG", vm.toString(GOVERNANCE_MULTISIG));

        pilotPools[0] = new DeployIxHelvetia().run();
        IERC20[] memory tokens0 = vault.getPoolTokens(pilotPools[0]);
        uint256[] memory amts0 = new uint256[](2);
        amts0[0] = INIT_SEED;
        amts0[1] = INIT_SEED;
        _initializePool(pilotPools[0], tokens0, amts0);

        pilotPools[1] = new DeployIxEdelweiss().run();
        IERC20[] memory tokens1 = vault.getPoolTokens(pilotPools[1]);
        // Per E10 / E-D25 — 1_000 × 10**decimals(token), address-sorted slot order.
        uint256[] memory amts1 = new uint256[](4);
        amts1[0] = 1_000e6;
        amts1[1] = 1_000e6;
        amts1[2] = 1_000e18;
        amts1[3] = 1_000e18;
        _initializePool(pilotPools[1], tokens1, amts1);

        pilotPools[2] = new DeployIxAurebit().run();
        IERC20[] memory tokens2 = vault.getPoolTokens(pilotPools[2]);
        // Per E10 / E-D25 — 1_000 × 10**decimals(token), address-sorted slot order.
        uint256[] memory amts2 = new uint256[](5);
        amts2[0] = 1_000e8;
        amts2[1] = 1_000e18;
        amts2[2] = 1_000e8;
        amts2[3] = 1_000e18;
        amts2[4] = 1_000e18;
        _initializePool(pilotPools[2], tokens2, amts2);

        mockTVLOracle = new MockTVLOracle();
        mockEfficiencyOracle = new MockEfficiencyOracle();
        mockAuMT = new MockVotingWeight();

        swapAndDeposit = new SwapAndDepositToBodensee(vault, bodenseePool, svZchf, IERC20(address(susds)), address(this), address(this));
        address[] memory genesisTokens = new address[](1);
        genesisTokens[0] = address(susds);
        IVaultClassRegistry.AdmissionType[] memory genesisTypes = new IVaultClassRegistry.AdmissionType[](1);
        genesisTypes[0] = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        vaultClassRegistry = new VaultClassRegistry(svZchf, swapAndDeposit, address(this), address(this), genesisTokens, genesisTypes);
        gaugeEligibility = new GaugeEligibility(address(awpf), address(vaultClassRegistry), address(mockTVLOracle), address(vault), address(aumm), address(mockAuMT), address(this), address(mockEfficiencyOracle), address(hook));
        gaugeRegistry = new GaugeRegistry(address(this), address(gaugeEligibility), address(swapAndDeposit), address(svZchf));

        swapAndDeposit.setVaultClassRegistry(address(vaultClassRegistry));
        swapAndDeposit.setGaugeRegistry(address(gaugeRegistry));
        vaultClassRegistry.setVotingWeight(address(mockAuMT));
        vaultClassRegistry.setGovernanceContract(address(this));
        gaugeEligibility.setGaugeRegistry(address(gaugeRegistry));

        swapAndDeposit.addAuthorizedDonator(address(vaultClassRegistry));
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

    // Stage G fixture helpers — class admission + pool eligibility + activate-with-fee
    function _proposeAndFinalizeClass(address token, IVaultClassRegistry.AdmissionType admissionType_, bytes32 constraintsHash)
        internal
        returns (uint256 proposalId)
    {
        deal(address(svZchf), address(this), vaultClassRegistry.PROPOSAL_BOND_SVZCHF());
        svZchf.approve(address(vaultClassRegistry), vaultClassRegistry.PROPOSAL_BOND_SVZCHF());
        proposalId = vaultClassRegistry.proposeVaultClass(admissionType_, token, constraintsHash);
        vm.roll(block.number + vaultClassRegistry.VETO_WINDOW_BLOCKS() + 1);
        vaultClassRegistry.finalizeProposal(proposalId);
    }

    function _makePoolEligible(address pool, uint256 tvl) internal {
        IERC20[] memory tokens = vault.getPoolTokens(pool);
        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = address(tokens[i]);
            if (!vaultClassRegistry.isAdmittedClass(token)) {
                _proposeAndFinalizeClass(token, IVaultClassRegistry.AdmissionType.ImplementationAddress, bytes32(0));
            }
        }
        mockTVLOracle.set(pool, tvl);
    }

    function _approveAndActivate(address caller, address pool, uint256 fee) internal {
        deal(address(svZchf), caller, fee);
        vm.startPrank(caller);
        svZchf.approve(address(gaugeRegistry), fee);
        gaugeRegistry.activateGauge(pool);
        vm.stopPrank();
    }

    function _warmupTournament(address[] memory pools) internal {
        uint256 smoothing = gaugeEligibility.SMOOTHING_EPOCHS();
        vm.startPrank(address(gaugeRegistry));
        for (uint256 i = 0; i < smoothing; ++i) {
            gaugeEligibility.computeEpochSnapshot(pools);
        }
        vm.stopPrank();
    }
}

contract StageGVaultClassRegistryTest is StageGIntegrationFixture {
    event VaultClassFinalized(uint256 indexed proposalId, address indexed admissionValue);
    event VaultClassVetoed(uint256 indexed proposalId, address indexed vetoer, uint256 weight);
    event VaultClassRevoked(address indexed admissionValue);

    function _bodenseeSvZchfIndex() private view returns (uint256) {
        IERC20[] memory tokens = vault.getPoolTokens(bodenseePool);
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (address(tokens[i]) == address(svZchf)) return i;
        }
        revert("svZchf not in Bodensee");
    }

    function _bodenseeSvZchfBalance() private view returns (uint256) {
        uint256 idx = _bodenseeSvZchfIndex();
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(bodenseePool);
        return balances[idx];
    }

    function test_happyPath_proposeFinalizeAdmitsClass() external {
        address proposer = makeAddr("proposer");
        address target = makeAddr("targetClass");
        uint256 bondAmount = vaultClassRegistry.PROPOSAL_BOND_SVZCHF();

        assertEq(vaultClassRegistry.isAdmittedClass(target), false);

        uint256 svZchfReservePre = _bodenseeSvZchfBalance();
        uint256 bptSupplyPre = IERC20(bodenseePool).totalSupply();

        deal(address(svZchf), proposer, bondAmount);
        vm.startPrank(proposer);
        svZchf.approve(address(vaultClassRegistry), bondAmount);
        uint256 proposalId = vaultClassRegistry.proposeVaultClass(
            IVaultClassRegistry.AdmissionType.ImplementationAddress,
            target,
            bytes32(0)
        );
        vm.stopPrank();

        assertEq(svZchf.balanceOf(proposer), 0);

        assertEq(_bodenseeSvZchfBalance(), svZchfReservePre + bondAmount);
        assertEq(IERC20(bodenseePool).totalSupply(), bptSupplyPre);

        vm.roll(block.number + vaultClassRegistry.VETO_WINDOW_BLOCKS() + 1);

        vm.expectEmit(true, true, false, false, address(vaultClassRegistry));
        emit VaultClassFinalized(proposalId, target);
        vaultClassRegistry.finalizeProposal(proposalId);

        assertEq(vaultClassRegistry.isAdmittedClass(target), true);
        assertTrue(vaultClassRegistry.admissionType(target) == IVaultClassRegistry.AdmissionType.ImplementationAddress);
    }

    function test_vetoSuccess_blocksAdmissionAndKeepsBond() external {
        address voter = makeAddr("vetoVoter");
        address proposer = makeAddr("vetoProposer");
        address target = makeAddr("vetoTarget");
        uint256 bondAmount = vaultClassRegistry.PROPOSAL_BOND_SVZCHF();
        mockAuMT.setTotalSupply(100e18);
        mockAuMT.setGovernanceWeight(voter, 11e18);
        uint256 svZchfReservePre = _bodenseeSvZchfBalance();

        deal(address(svZchf), proposer, bondAmount);
        vm.startPrank(proposer);
        svZchf.approve(address(vaultClassRegistry), bondAmount);
        uint256 proposalId = vaultClassRegistry.proposeVaultClass(
            IVaultClassRegistry.AdmissionType.ImplementationAddress,
            target,
            bytes32(0)
        );
        vm.stopPrank();

        assertEq(_bodenseeSvZchfBalance(), svZchfReservePre + bondAmount);

        vm.expectEmit(true, true, false, false, address(vaultClassRegistry));
        emit VaultClassVetoed(proposalId, voter, 11e18);
        vm.prank(voter);
        vaultClassRegistry.vetoProposal(proposalId);

        assertEq(_bodenseeSvZchfBalance(), svZchfReservePre + bondAmount);
        assertEq(svZchf.balanceOf(proposer), 0);
        assertEq(vaultClassRegistry.isAdmittedClass(target), false);
        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.ProposalAlreadyFinalized.selector, proposalId));
        vaultClassRegistry.finalizeProposal(proposalId);
    }

    function test_vetoWindowGuards_expiredAndOpen() external {
        address proposer = makeAddr("guardProposer");
        address target = makeAddr("guardTarget");
        uint256 bondAmount = vaultClassRegistry.PROPOSAL_BOND_SVZCHF();

        deal(address(svZchf), proposer, bondAmount);
        vm.startPrank(proposer);
        svZchf.approve(address(vaultClassRegistry), bondAmount);
        uint256 proposalId = vaultClassRegistry.proposeVaultClass(
            IVaultClassRegistry.AdmissionType.ImplementationAddress,
            target,
            bytes32(0)
        );
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.VetoWindowOpen.selector, proposalId));
        vaultClassRegistry.finalizeProposal(proposalId);

        vm.roll(block.number + vaultClassRegistry.VETO_WINDOW_BLOCKS() + 1);

        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.VetoWindowExpired.selector, proposalId));
        vaultClassRegistry.vetoProposal(proposalId);
    }

    function test_revokeVaultClass_flipsAdmission() external {
        address target = makeAddr("revokeTarget");

        _proposeAndFinalizeClass(target, IVaultClassRegistry.AdmissionType.ImplementationAddress, bytes32(0));
        assertEq(vaultClassRegistry.isAdmittedClass(target), true);

        vm.expectEmit(true, false, false, false, address(vaultClassRegistry));
        emit VaultClassRevoked(target);
        vaultClassRegistry.revokeVaultClass(target);

        assertEq(vaultClassRegistry.isAdmittedClass(target), false);
    }
}

contract StageGEligibilityTest is StageGIntegrationFixture {
    event GaugeEfficiencyDropped(address indexed pool, uint256 indexed epoch, uint256 numeratorSma, uint256 denominatorSma, uint256 efficiencyRatio);
    event GaugeEfficiencyRising(address indexed pool, uint256 indexed epoch, uint256 numeratorSma, uint256 denominatorSma, uint256 efficiencyRatio);

    function _ord(uint256 ordinal) private pure returns (address) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(ordinal));
    }

    function test_happyPath_evaluateEligibilityPasses() external {
        address pool = pilotPools[0];
        // _makePoolEligible admits all pool tokens via _proposeAndFinalizeClass
        // and sets mockTVLOracle to the second argument
        _makePoolEligible(pool, 50_000e18);

        // Pre-evaluate state
        assertEq(gaugeEligibility.isGaugeEligible(pool), false);

        // Trigger evaluation
        bool ok = gaugeEligibility.evaluateEligibility(pool);

        // Post-evaluate state
        assertTrue(ok);
        assertEq(gaugeEligibility.isGaugeEligible(pool), true);
        assertTrue(gaugeEligibility.isEligible(pool));
    }

    function test_subFloorTVL_revertsTVLFloorNotMet() external {
        address pool = pilotPools[0];

        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.TVLFloorNotMet.selector, 0, gaugeEligibility.TVL_FLOOR_SVZCHF()));
        gaugeEligibility.evaluateEligibility(pool);
    }

    function test_svZchfUnadmitted_revertsInsufficientQualityGate() external {
        mockTVLOracle.set(pilotPools[0], 15_000e18);

        // sUSDS admitted (genesis) but svZCHF not admitted — numerator = 0.2e18 < 0.52e18
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.InsufficientQualityGate.selector, uint256(0.2e18)));
        gaugeEligibility.evaluateEligibility(pilotPools[0]);
    }

    function test_aummInPool_revertsForbiddenToken() external {
        // Bodensee pool contains AuMM by construction — T-I3 gate fires inside _compute52PctNumerator before factory/TVL checks
        // I-D13: Bodensee is hookless; mock its getHooksConfig past the fail-fast hook-gate to preserve T-I3 coverage
        HooksConfig memory _hc;
        _hc.hooksContract = address(hook);
        vm.mockCall(address(vault), abi.encodeWithSignature("getHooksConfig(address)", bodenseePool), abi.encode(_hc));
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.ForbiddenToken.selector, address(aumm)));
        gaugeEligibility.evaluateEligibility(bodenseePool);
    }

    function test_poolNotFromAwpf_revertsPoolTypeNotWhitelisted() external {
        // Mock awpf to deny pilotPools[0] — exercises G-D6 / G-D15a factory whitelist gate
        vm.mockCall(
            address(awpf),
            abi.encodeWithSelector(IBasePoolFactory.isPoolFromFactory.selector, pilotPools[0]),
            abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.PoolTypeNotWhitelisted.selector, address(awpf)));
        gaugeEligibility.evaluateEligibility(pilotPools[0]);
    }

    function test_g_d10TryCatchPaths_borderlinePass() external {
        address aavePrimeGho = 0xC71Ea051a5F82c67ADcF634c36FFE6334793D24C;
        _proposeAndFinalizeClass(aavePrimeGho, IVaultClassRegistry.AdmissionType.ImplementationAddress, bytes32(0));
        _proposeAndFinalizeClass(address(svZchf), IVaultClassRegistry.AdmissionType.ImplementationAddress, bytes32(0));
        mockTVLOracle.set(pilotPools[2], 50_000e18);
        // ixAurebit (pilotPools[2]) — all three G-D10 paths: WBTC + cbBTC + ixEDEL hit catch (0 each); Aave Prime GHO + svZCHF admitted ERC-4626 (0.26e18 each); numerator = 0.52e18 = bar, passes
        bool ok = gaugeEligibility.evaluateEligibility(pilotPools[2]);
        assertTrue(ok);
        assertTrue(gaugeEligibility.isEligible(pilotPools[2]));
    }

    function test_epochSnapshot_assignsTop15PctFavoredCohort() external {
        // 5 synthetic pools — favoredCount = (5*15 + 99) / 100 = 1; only top-1 favored after warmup + epoch 4 ranking.
        address[] memory pools = new address[](5);
        pools[0] = makeAddr("pool-A");
        pools[1] = makeAddr("pool-B");
        pools[2] = makeAddr("pool-C");
        pools[3] = makeAddr("pool-D");
        pools[4] = makeAddr("pool-E");
        mockEfficiencyOracle.setEfficiencyInputs(pools[0], 5e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(pools[1], 4e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(pools[2], 3e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(pools[3], 2e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(pools[4], 1e18, 1e18);
        _warmupTournament(pools);
        vm.prank(address(gaugeRegistry));
        gaugeEligibility.computeEpochSnapshot(pools);
        assertEq(gaugeEligibility.currentSnapshotEpoch(), 4);
        assertTrue(gaugeEligibility.isFavoredCohort(pools[0]));
        assertFalse(gaugeEligibility.isFavoredCohort(pools[1]));
        assertFalse(gaugeEligibility.isFavoredCohort(pools[4]));
    }

    function test_epochSnapshot_emitsRisingAndDroppedOnLeaderSwap() external {
        address[] memory pools = new address[](5);
        pools[0] = makeAddr("transition-pool-A");
        pools[1] = makeAddr("transition-pool-B");
        pools[2] = makeAddr("transition-pool-C");
        pools[3] = makeAddr("transition-pool-D");
        pools[4] = makeAddr("transition-pool-E");
        mockEfficiencyOracle.setEfficiencyInputs(pools[0], 5e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(pools[1], 4e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(pools[2], 3e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(pools[3], 2e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(pools[4], 1e18, 1e18);
        _warmupTournament(pools);
        vm.prank(address(gaugeRegistry));
        gaugeEligibility.computeEpochSnapshot(pools);
        // Cycle 1 — single-slot cohort; pools[0] is favored after epoch 4 snapshot.
        assertTrue(gaugeEligibility.isFavoredCohort(pools[0]));
        mockEfficiencyOracle.setEfficiencyInputs(pools[1], 6e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(pools[0], 0.5e18, 1e18);
        // Cycle 2 — expect Rising for new leader then Dropped for former leader at epoch 5.
        vm.expectEmit(true, true, false, true, address(gaugeEligibility));
        emit GaugeEfficiencyRising(pools[1], 5, 6e18, 1e18, 6e18);
        vm.expectEmit(true, true, false, true, address(gaugeEligibility));
        emit GaugeEfficiencyDropped(pools[0], 5, 0.5e18, 1e18, 0.5e18);
        vm.prank(address(gaugeRegistry));
        gaugeEligibility.computeEpochSnapshot(pools);
        assertEq(gaugeEligibility.currentSnapshotEpoch(), 5);
        assertTrue(gaugeEligibility.isFavoredCohort(pools[1]));
        assertFalse(gaugeEligibility.isFavoredCohort(pools[0]));
    }

    function test_epochSnapshot_addressAscendingTiebreakWithEqualRatios() external {
        address leader    = _ord(0x500);  // sole ratio leader at 10e18
        address tieWinner = _ord(0x100);  // lowest address among the 6 tied at 3e18 — wins boundary slot
        address tied200   = _ord(0x200);
        address tied300   = _ord(0x300);
        address tied400   = _ord(0x400);
        address tied600   = _ord(0x600);
        address tied700   = _ord(0x700);

        address[] memory pools = new address[](7);
        pools[0] = tied700;
        pools[1] = tieWinner;
        pools[2] = leader;
        pools[3] = tied300;
        pools[4] = tied600;
        pools[5] = tied200;
        pools[6] = tied400;

        mockEfficiencyOracle.setEfficiencyInputs(leader,    10e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(tieWinner,  3e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(tied200,    3e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(tied300,    3e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(tied400,    3e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(tied600,    3e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(tied700,    3e18, 1e18);

        _warmupTournament(pools);
        vm.prank(address(gaugeRegistry));
        gaugeEligibility.computeEpochSnapshot(pools);

        assertEq(gaugeEligibility.currentSnapshotEpoch(), 4);
        assertTrue(gaugeEligibility.isFavoredCohort(leader));
        assertTrue(gaugeEligibility.isFavoredCohort(tieWinner));
        assertFalse(gaugeEligibility.isFavoredCohort(tied200));
        assertFalse(gaugeEligibility.isFavoredCohort(tied300));
        assertFalse(gaugeEligibility.isFavoredCohort(tied400));
        assertFalse(gaugeEligibility.isFavoredCohort(tied600));
        assertFalse(gaugeEligibility.isFavoredCohort(tied700));
    }

    function test_epochSnapshot_isEligibleDeterministicAcrossSameBlockReads() external {
        _makePoolEligible(pilotPools[0], 50_000e18);
        gaugeEligibility.evaluateEligibility(pilotPools[0]);

        address[] memory pools = new address[](5);
        pools[0] = makeAddr("determinism-A");
        pools[1] = makeAddr("determinism-B");
        pools[2] = makeAddr("determinism-C");
        pools[3] = makeAddr("determinism-D");
        pools[4] = makeAddr("determinism-E");
        mockEfficiencyOracle.setEfficiencyInputs(pools[0], 5e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(pools[1], 4e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(pools[2], 3e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(pools[3], 2e18, 1e18);
        mockEfficiencyOracle.setEfficiencyInputs(pools[4], 1e18, 1e18);
        _warmupTournament(pools);
        vm.prank(address(gaugeRegistry));
        gaugeEligibility.computeEpochSnapshot(pools);

        uint256 anchorBlock = block.number;
        bool isEligibleA = gaugeEligibility.isEligible(pilotPools[0]);
        bool cohortA = gaugeEligibility.cohortOf(pools[0]);
        uint256 epochA = gaugeEligibility.snapshotEpoch();
        bool isEligibleB = gaugeEligibility.isEligible(pilotPools[0]);
        bool cohortB = gaugeEligibility.cohortOf(pools[0]);
        uint256 epochB = gaugeEligibility.snapshotEpoch();

        assertEq(block.number, anchorBlock);
        assertEq(isEligibleA, isEligibleB);
        assertEq(cohortA, cohortB);
        assertEq(epochA, epochB);

        assertTrue(isEligibleA);
        assertTrue(cohortA);
        assertEq(epochA, 4);
    }
}

contract StageGRegistryPermissionlessTest is StageGIntegrationFixture {
    event GaugeActivated(address indexed pool, IGaugeRegistry.GaugeActivationPath indexed path);
    event AntiSpamFeeRouted(address indexed payer, uint256 amount);
    event GaugeActivationFailed(address indexed pool, bytes reason);

    function _bodenseeSvZchfIndex() private view returns (uint256) {
        IERC20[] memory tokens = vault.getPoolTokens(bodenseePool);
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (address(tokens[i]) == address(svZchf)) return i;
        }
        revert("svZchf not in Bodensee");
    }

    function _bodenseeSvZchfBalance() private view returns (uint256) {
        uint256 idx = _bodenseeSvZchfIndex();
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(bodenseePool);
        return balances[idx];
    }

    function test_activateGauge_happyPath_routesAntiSpamFeeAndActivates() external {
        address pool = pilotPools[0];
        _makePoolEligible(pool, 50_000e18);

        address caller = makeAddr("permissionlessCaller");
        uint256 fee = gaugeRegistry.ANTI_SPAM_FEE();
        uint256 svZchfReservePre = _bodenseeSvZchfBalance();
        uint256 bptSupplyPre = IERC20(bodenseePool).totalSupply();

        deal(address(svZchf), caller, fee);

        vm.startPrank(caller);
        svZchf.approve(address(gaugeRegistry), fee);
        vm.recordLogs();
        gaugeRegistry.activateGauge(pool);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();

        bool foundFeeRouted;
        bool foundActivated;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != address(gaugeRegistry)) continue;
            if (logs[i].topics[0] == AntiSpamFeeRouted.selector) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), caller);
                assertEq(abi.decode(logs[i].data, (uint256)), fee);
                foundFeeRouted = true;
            } else if (logs[i].topics[0] == GaugeActivated.selector) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), pool);
                assertEq(uint256(logs[i].topics[2]), uint256(uint8(IGaugeRegistry.GaugeActivationPath.Permissionless)));
                foundActivated = true;
            }
        }
        assertTrue(foundFeeRouted);
        assertTrue(foundActivated);

        assertEq(svZchf.balanceOf(caller), 0);
        assertEq(_bodenseeSvZchfBalance(), svZchfReservePre + fee);
        assertEq(IERC20(bodenseePool).totalSupply(), bptSupplyPre);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Active);
        assertTrue(gaugeRegistry.isGaugeApproved(pool));
    }

    function test_activateGauge_failsEligibility_routesFeeButNoActivation() external {
        address pool = pilotPools[0]; // NO _makePoolEligible — TVL oracle stays at 0 → TVLFloorNotMet revert in evaluateEligibility
        address caller = makeAddr("permissionlessCallerFail");
        uint256 fee = gaugeRegistry.ANTI_SPAM_FEE();
        uint256 svZchfReservePre = _bodenseeSvZchfBalance();
        uint256 bptSupplyPre = IERC20(bodenseePool).totalSupply();
        bytes memory expectedReason = abi.encodeWithSelector(GaugeEligibility.TVLFloorNotMet.selector, uint256(0), gaugeEligibility.TVL_FLOOR_SVZCHF());

        deal(address(svZchf), caller, fee);

        vm.startPrank(caller);
        svZchf.approve(address(gaugeRegistry), fee);
        vm.recordLogs();
        gaugeRegistry.activateGauge(pool);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();

        bool foundFeeRouted;
        bool foundFailed;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != address(gaugeRegistry)) continue;
            if (logs[i].topics[0] == AntiSpamFeeRouted.selector) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), caller);
                assertEq(abi.decode(logs[i].data, (uint256)), fee);
                foundFeeRouted = true;
            } else if (logs[i].topics[0] == GaugeActivationFailed.selector) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), pool);
                bytes memory actualReason = abi.decode(logs[i].data, (bytes));
                assertEq(actualReason, expectedReason);
                foundFailed = true;
            } else if (logs[i].topics[0] == GaugeActivated.selector) {
                assertTrue(false, "GaugeActivated must not be emitted on eligibility-fail path");
            }
        }
        assertTrue(foundFeeRouted);
        assertTrue(foundFailed);

        assertEq(svZchf.balanceOf(caller), 0);
        assertEq(_bodenseeSvZchfBalance(), svZchfReservePre + fee);
        assertEq(IERC20(bodenseePool).totalSupply(), bptSupplyPre);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.None);
        assertFalse(gaugeRegistry.isGaugeApproved(pool));
    }

    function test_activateGauge_noApproval_revertsAndPreservesAllState() external {
        address pool = pilotPools[0];
        _makePoolEligible(pool, 50_000e18); // pool IS eligible — proves the revert is from fee precondition, not downstream eligibility
        address caller = makeAddr("permissionlessCallerNoApproval");
        uint256 fee = gaugeRegistry.ANTI_SPAM_FEE();
        deal(address(svZchf), caller, fee); // caller funded — revert is from missing approval, not missing balance
        // NO svZchf.approve call — allowance(caller, registry) stays 0
        uint256 callerBalancePre = svZchf.balanceOf(caller);
        uint256 registryBalancePre = svZchf.balanceOf(address(gaugeRegistry));
        uint256 svZchfReservePre = _bodenseeSvZchfBalance();
        uint256 bptSupplyPre = IERC20(bodenseePool).totalSupply();
        vm.startPrank(caller);
        vm.expectRevert();
        gaugeRegistry.activateGauge(pool);
        vm.stopPrank();

        assertEq(svZchf.balanceOf(caller), callerBalancePre);
        assertEq(svZchf.balanceOf(address(gaugeRegistry)), registryBalancePre);
        assertEq(_bodenseeSvZchfBalance(), svZchfReservePre);
        assertEq(IERC20(bodenseePool).totalSupply(), bptSupplyPre);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.None);
        assertFalse(gaugeRegistry.isGaugeApproved(pool));
    }

    function test_activateGauge_alreadyActive_revertsAlreadyGauged() external {
        address pool = pilotPools[0];
        _makePoolEligible(pool, 50_000e18);
        address firstCaller = makeAddr("firstCallerForAlreadyGauged");
        uint256 fee = gaugeRegistry.ANTI_SPAM_FEE();
        deal(address(svZchf), firstCaller, fee);
        vm.startPrank(firstCaller);
        svZchf.approve(address(gaugeRegistry), fee);
        gaugeRegistry.activateGauge(pool);
        vm.stopPrank();
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Active);
        address secondCaller = makeAddr("secondCallerForAlreadyGauged");
        deal(address(svZchf), secondCaller, fee);
        uint256 secondCallerBalancePre = svZchf.balanceOf(secondCaller);
        uint256 svZchfReservePre = _bodenseeSvZchfBalance();
        vm.startPrank(secondCaller);
        svZchf.approve(address(gaugeRegistry), fee); // approval granted — proves fee NOT pulled is from status check, not from missing approval
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.AlreadyGauged.selector, pool));
        gaugeRegistry.activateGauge(pool);
        vm.stopPrank();
        assertEq(svZchf.balanceOf(secondCaller), secondCallerBalancePre); // fee NOT pulled
        assertEq(_bodenseeSvZchfBalance(), svZchfReservePre); // Bodensee NOT mutated
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Active);
    }

    function test_activateGauge_revoked_revertsAlreadyRevoked() external {
        address pool = pilotPools[0];
        _makePoolEligible(pool, 50_000e18);
        address firstCaller = makeAddr("firstCallerForRevoke");
        uint256 fee = gaugeRegistry.ANTI_SPAM_FEE();
        deal(address(svZchf), firstCaller, fee);
        vm.startPrank(firstCaller);
        svZchf.approve(address(gaugeRegistry), fee);
        gaugeRegistry.activateGauge(pool);
        vm.stopPrank();
        gaugeRegistry.revokeGauge(pool); // governance == address(this) per fixture L208 — no prank needed
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Revoked);
        address secondCaller = makeAddr("secondCallerAfterRevoke");
        deal(address(svZchf), secondCaller, fee);
        uint256 secondCallerBalancePre = svZchf.balanceOf(secondCaller);
        uint256 svZchfReservePre = _bodenseeSvZchfBalance();
        vm.startPrank(secondCaller);
        svZchf.approve(address(gaugeRegistry), fee);
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.AlreadyRevoked.selector, pool));
        gaugeRegistry.activateGauge(pool);
        vm.stopPrank();
        assertEq(svZchf.balanceOf(secondCaller), secondCallerBalancePre);
        assertEq(_bodenseeSvZchfBalance(), svZchfReservePre);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Revoked);
    }
}

contract StageGRegistryCompositionTest is StageGIntegrationFixture {
    event GaugeActivated(address indexed pool, IGaugeRegistry.GaugeActivationPath indexed path);

    function _bodenseeSvZchfIndex() private view returns (uint256) {
        IERC20[] memory tokens = vault.getPoolTokens(bodenseePool);
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (address(tokens[i]) == address(svZchf)) return i;
        }
        revert("svZchf not in Bodensee");
    }

    function _bodenseeSvZchfBalance() private view returns (uint256) {
        uint256 idx = _bodenseeSvZchfIndex();
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(bodenseePool);
        return balances[idx];
    }

    function test_registerGaugeFromComposition_happyPath_bypassesEligibilityAndFee() external {
        address pool = makeAddr("composition-pool-happy");
        uint256 govSvZchfPre = svZchf.balanceOf(address(this));
        uint256 registrySvZchfPre = svZchf.balanceOf(address(gaugeRegistry));
        uint256 svZchfReservePre = _bodenseeSvZchfBalance();
        vm.expectEmit(true, true, false, true, address(gaugeRegistry));
        emit GaugeActivated(pool, IGaugeRegistry.GaugeActivationPath.Composition);
        gaugeRegistry.registerGaugeFromComposition(pool);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Active);
        assertTrue(gaugeRegistry.isGaugeApproved(pool));
        assertEq(svZchf.balanceOf(address(this)), govSvZchfPre); // no fee on composition path
        assertEq(svZchf.balanceOf(address(gaugeRegistry)), registrySvZchfPre);
        assertEq(_bodenseeSvZchfBalance(), svZchfReservePre); // Bodensee NOT touched
    }

    function test_registerGaugeFromComposition_nonGovernance_revertsNotGovernance() external {
        address pool = makeAddr("composition-pool-non-gov");
        address nonGov = makeAddr("composition-non-governance");
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.NotGovernance.selector, nonGov));
        gaugeRegistry.registerGaugeFromComposition(pool);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.None);
    }

    function test_registerGaugeFromComposition_alreadyActive_revertsAlreadyGauged() external {
        address pool = makeAddr("composition-pool-already-gauged");
        gaugeRegistry.registerGaugeFromComposition(pool);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Active);
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.AlreadyGauged.selector, pool));
        gaugeRegistry.registerGaugeFromComposition(pool);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Active);
    }

    function test_registerGaugeFromComposition_revokedPool_revertsAlreadyRevoked() external {
        address pool = makeAddr("composition-pool-revoked");
        gaugeRegistry.registerGaugeFromComposition(pool);
        gaugeRegistry.revokeGauge(pool);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Revoked);
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.AlreadyRevoked.selector, pool));
        gaugeRegistry.registerGaugeFromComposition(pool);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Revoked);
    }
}

contract StageGRegistryFoundingTest is StageGIntegrationFixture {
    event GaugeActivated(address indexed pool, IGaugeRegistry.GaugeActivationPath indexed path);

    function _bodenseeSvZchfIndex() private view returns (uint256) {
        IERC20[] memory tokens = vault.getPoolTokens(bodenseePool);
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (address(tokens[i]) == address(svZchf)) return i;
        }
        revert("svZchf not in Bodensee");
    }

    function _bodenseeSvZchfBalance() private view returns (uint256) {
        uint256 idx = _bodenseeSvZchfIndex();
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(bodenseePool);
        return balances[idx];
    }

    function test_seedFoundingPool_happyPath_emitsFoundingPathTag() external {
        address pool = makeAddr("founding-pool-scalar-happy");
        uint256 govSvZchfPre = svZchf.balanceOf(address(this));
        uint256 svZchfReservePre = _bodenseeSvZchfBalance();
        vm.expectEmit(true, true, false, true, address(gaugeRegistry));
        emit GaugeActivated(pool, IGaugeRegistry.GaugeActivationPath.Founding);
        gaugeRegistry.seedFoundingPool(pool);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Active);
        assertTrue(gaugeRegistry.isGaugeApproved(pool));
        assertEq(svZchf.balanceOf(address(this)), govSvZchfPre);
        assertEq(_bodenseeSvZchfBalance(), svZchfReservePre);
    }

    function test_seedFoundingPool_nonGovernance_revertsNotGovernance() external {
        address pool = makeAddr("founding-pool-scalar-non-gov");
        address nonGov = makeAddr("founding-non-governance");
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.NotGovernance.selector, nonGov));
        gaugeRegistry.seedFoundingPool(pool);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.None);
    }

    function test_seedFoundingPool_alreadyActive_revertsAlreadyGauged() external {
        address pool = makeAddr("founding-pool-scalar-already-gauged");
        gaugeRegistry.seedFoundingPool(pool);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Active);
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.AlreadyGauged.selector, pool));
        gaugeRegistry.seedFoundingPool(pool);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Active);
    }

    function test_seedFoundingPool_revokedPool_revertsAlreadyRevoked() external {
        address pool = makeAddr("founding-pool-scalar-revoked");
        gaugeRegistry.seedFoundingPool(pool);
        gaugeRegistry.revokeGauge(pool);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Revoked);
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.AlreadyRevoked.selector, pool));
        gaugeRegistry.seedFoundingPool(pool);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Revoked);
    }

    function test_seedFoundingPools_batchHappyPath_emitsFoundingForEachPool() external {
        address[] memory pools = new address[](3);
        pools[0] = makeAddr("founding-batch-pool-0");
        pools[1] = makeAddr("founding-batch-pool-1");
        pools[2] = makeAddr("founding-batch-pool-2");
        vm.expectEmit(true, true, false, true, address(gaugeRegistry));
        emit GaugeActivated(pools[0], IGaugeRegistry.GaugeActivationPath.Founding);
        vm.expectEmit(true, true, false, true, address(gaugeRegistry));
        emit GaugeActivated(pools[1], IGaugeRegistry.GaugeActivationPath.Founding);
        vm.expectEmit(true, true, false, true, address(gaugeRegistry));
        emit GaugeActivated(pools[2], IGaugeRegistry.GaugeActivationPath.Founding);
        gaugeRegistry.seedFoundingPools(pools);
        assertTrue(gaugeRegistry.gaugeStatus(pools[0]) == IGaugeRegistry.GaugeStatus.Active);
        assertTrue(gaugeRegistry.gaugeStatus(pools[1]) == IGaugeRegistry.GaugeStatus.Active);
        assertTrue(gaugeRegistry.gaugeStatus(pools[2]) == IGaugeRegistry.GaugeStatus.Active);
    }

    function test_seedFoundingPools_nonGovernance_revertsNotGovernance() external {
        address[] memory pools = new address[](2);
        pools[0] = makeAddr("founding-batch-non-gov-pool-0");
        pools[1] = makeAddr("founding-batch-non-gov-pool-1");
        address nonGov = makeAddr("founding-batch-non-governance");
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.NotGovernance.selector, nonGov));
        gaugeRegistry.seedFoundingPools(pools);
        assertTrue(gaugeRegistry.gaugeStatus(pools[0]) == IGaugeRegistry.GaugeStatus.None);
        assertTrue(gaugeRegistry.gaugeStatus(pools[1]) == IGaugeRegistry.GaugeStatus.None);
    }

    function test_seedFoundingPools_secondPoolAlreadyActive_atomicRevertsAndFirstPoolStaysNone() external {
        address[] memory pools = new address[](3);
        pools[0] = makeAddr("founding-batch-atomic-pool-0-fresh");
        pools[1] = makeAddr("founding-batch-atomic-pool-1-preActive");
        pools[2] = makeAddr("founding-batch-atomic-pool-2-fresh");
        gaugeRegistry.seedFoundingPool(pools[1]);
        assertTrue(gaugeRegistry.gaugeStatus(pools[1]) == IGaugeRegistry.GaugeStatus.Active);
        assertTrue(gaugeRegistry.gaugeStatus(pools[0]) == IGaugeRegistry.GaugeStatus.None);
        assertTrue(gaugeRegistry.gaugeStatus(pools[2]) == IGaugeRegistry.GaugeStatus.None);
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.AlreadyGauged.selector, pools[1]));
        gaugeRegistry.seedFoundingPools(pools);
        // Atomicity: pools[0] write from loop iteration 0 must be rolled back — pools[2] never reached.
        assertTrue(gaugeRegistry.gaugeStatus(pools[0]) == IGaugeRegistry.GaugeStatus.None);
        assertTrue(gaugeRegistry.gaugeStatus(pools[1]) == IGaugeRegistry.GaugeStatus.Active); // pre-seed state intact
        assertTrue(gaugeRegistry.gaugeStatus(pools[2]) == IGaugeRegistry.GaugeStatus.None);
    }
}

contract StageGRegistryRevocationTest is StageGIntegrationFixture {
    event GaugeRevoked(address indexed pool);

    function test_revokeGauge_happyPath_emitsGaugeRevokedAndFlipsStatus() external {
        address pool = makeAddr("revocation-pool-happy");
        gaugeRegistry.registerGaugeFromComposition(pool);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Active);
        vm.expectEmit(true, false, false, true, address(gaugeRegistry));
        emit GaugeRevoked(pool);
        gaugeRegistry.revokeGauge(pool);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Revoked);
        assertFalse(gaugeRegistry.isGaugeApproved(pool));
    }

    function test_revokeGauge_nonGovernance_revertsNotGovernance() external {
        address pool = makeAddr("revocation-pool-non-gov");
        // No pre-activation needed — onlyGovernance modifier (L59) runs before the status check (L148), so the access revert fires regardless of pool status.
        address nonGov = makeAddr("revocation-non-governance");
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.NotGovernance.selector, nonGov));
        gaugeRegistry.revokeGauge(pool);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.None);
    }

    function test_revokeGauge_noneStatusPool_revertsNotGauged() external {
        address pool = makeAddr("revocation-pool-none");
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.None);
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.NotGauged.selector, pool));
        gaugeRegistry.revokeGauge(pool); // governance == address(this) — access check passes; status check (None != Active) reverts NotGauged
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.None);
    }

    function test_revokeGauge_alreadyRevokedPool_revertsNotGauged() external {
        address pool = makeAddr("revocation-pool-double-revoke");
        gaugeRegistry.registerGaugeFromComposition(pool);
        gaugeRegistry.revokeGauge(pool);
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Revoked);
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.NotGauged.selector, pool));
        gaugeRegistry.revokeGauge(pool); // G-D17 terminal: Revoked != Active, single guard rejects double-revoke
        assertTrue(gaugeRegistry.gaugeStatus(pool) == IGaugeRegistry.GaugeStatus.Revoked);
    }
}

contract StageGRegistryGovernanceHandoffTest is StageGIntegrationFixture {
    event GovernanceTransferred(address indexed oldGovernance, address indexed newGovernance);

    function test_setGovernanceContract_happyPath_emitsGovernanceTransferredAndUpdatesStorage() external {
        address oldGov = gaugeRegistry.governanceContract();
        assertEq(oldGov, address(this));
        address newGov = makeAddr("new-governance-happy");
        vm.expectEmit(true, true, false, true, address(gaugeRegistry));
        emit GovernanceTransferred(oldGov, newGov);
        gaugeRegistry.setGovernanceContract(newGov);
        assertEq(gaugeRegistry.governanceContract(), newGov);
    }

    function test_setGovernanceContract_nonGovernance_revertsNotGovernance() external {
        address oldGov = gaugeRegistry.governanceContract();
        address nonGov = makeAddr("handoff-non-governance");
        address newGov = makeAddr("handoff-new-governance-rejected");
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.NotGovernance.selector, nonGov));
        gaugeRegistry.setGovernanceContract(newGov);
        assertEq(gaugeRegistry.governanceContract(), oldGov);
    }

    function test_setGovernanceContract_zeroAddress_revertsZeroAddress() external {
        address oldGov = gaugeRegistry.governanceContract();
        vm.expectRevert(abi.encodeWithSelector(GaugeRegistry.ZeroAddress.selector));
        gaugeRegistry.setGovernanceContract(address(0));
        assertEq(gaugeRegistry.governanceContract(), oldGov);
    }

    function test_setGovernanceContract_handoffShiftsAuthority_oldRejectedNewAccepted() external {
        address oldGov = gaugeRegistry.governanceContract();
        address newGov = makeAddr("handoff-new-governance-active");
        gaugeRegistry.setGovernanceContract(newGov);
        assertEq(gaugeRegistry.governanceContract(), newGov);
        address poolForOldGovAttempt = makeAddr("handoff-pool-old-gov-attempt");
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.NotGovernance.selector, oldGov));
        gaugeRegistry.registerGaugeFromComposition(poolForOldGovAttempt);
        assertTrue(gaugeRegistry.gaugeStatus(poolForOldGovAttempt) == IGaugeRegistry.GaugeStatus.None);
        address poolForNewGovAttempt = makeAddr("handoff-pool-new-gov-attempt");
        vm.prank(newGov);
        gaugeRegistry.registerGaugeFromComposition(poolForNewGovAttempt);
        assertTrue(gaugeRegistry.gaugeStatus(poolForNewGovAttempt) == IGaugeRegistry.GaugeStatus.Active);
    }
}

contract StageGRegistryStageFRegressionTest is StageGIntegrationFixture {
    CCBMultiplier private ccbMultiplier;
    MockMiliariumRegistry private mockMiliariumRegistry;
    MockGaugeRegistry private mockGaugeRegistry;
    address private regressionMiliariumPool;

    function setUp() public override {
        super.setUp();
        regressionMiliariumPool = makeAddr("regression-miliarium-pool");
        address[3] memory pools = [regressionMiliariumPool, makeAddr("regression-miliarium-slot-1"), makeAddr("regression-miliarium-slot-2")];
        mockMiliariumRegistry = new MockMiliariumRegistry(pools);
        mockGaugeRegistry = new MockGaugeRegistry();
        ccbMultiplier = new CCBMultiplier(
            IMiliariumRegistry(address(mockMiliariumRegistry)),
            IGaugeRegistry(address(mockGaugeRegistry)),
            IEMASampler(makeAddr("regression-ema-placeholder"))
        );
        ccbMultiplier.setGaugeRegistry(IGaugeRegistry(address(gaugeRegistry))); // F-D23 one-shot handoff to the production Stage G registry
        assertEq(address(ccbMultiplier.gaugeRegistry()), address(gaugeRegistry)); // handoff landed
        assertEq(ccbMultiplier.gaugeRegistrySetter(), address(0)); // seal closed per F-D23
    }

    function test_activateBoost_realGaugeRegistry_acceptsApprovedGauge() external {
        address gauge = makeAddr("regression-approved-gauge");
        gaugeRegistry.registerGaugeFromComposition(gauge); // governance == address(this); composition path activates gauge without fee/eligibility
        assertTrue(gaugeRegistry.isGaugeApproved(gauge));
        uint256 blockBefore = block.number;
        vm.prank(gauge);
        ccbMultiplier.activateBoost(regressionMiliariumPool);
        assertEq(ccbMultiplier.boostExpiryBlock(regressionMiliariumPool), blockBefore + ccbMultiplier.GAUGE_BOOST_DURATION_BLOCKS());
        assertEq(ccbMultiplier.M_i(regressionMiliariumPool), ccbMultiplier.INITIAL_MULTIPLIER());
    }

    function test_activateBoost_realGaugeRegistry_rejectsUnapprovedGauge() external {
        address unapprovedCaller = makeAddr("regression-unapproved-caller");
        assertFalse(gaugeRegistry.isGaugeApproved(unapprovedCaller)); // sanity: registry has not seen this address
        vm.prank(unapprovedCaller);
        vm.expectRevert(abi.encodeWithSelector(CCBMultiplier.OnlyApprovedGauge.selector, unapprovedCaller));
        ccbMultiplier.activateBoost(regressionMiliariumPool);
        assertEq(ccbMultiplier.boostExpiryBlock(regressionMiliariumPool), 0); // no state mutation
    }

    function test_activateBoost_realGaugeRegistry_rejectsRevokedGauge() external {
        address gauge = makeAddr("regression-revoked-gauge");
        gaugeRegistry.registerGaugeFromComposition(gauge);
        assertTrue(gaugeRegistry.isGaugeApproved(gauge));
        gaugeRegistry.revokeGauge(gauge);
        assertFalse(gaugeRegistry.isGaugeApproved(gauge)); // G-D17 terminal — isGaugeApproved now returns false through the live registry read
        vm.prank(gauge);
        vm.expectRevert(abi.encodeWithSelector(CCBMultiplier.OnlyApprovedGauge.selector, gauge));
        ccbMultiplier.activateBoost(regressionMiliariumPool);
        assertEq(ccbMultiplier.boostExpiryBlock(regressionMiliariumPool), 0);
    }
}
