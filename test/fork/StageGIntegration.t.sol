// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    TokenConfig,
    TokenType,
    PoolRoleAccounts,
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
import { DeployIxHelvetia } from "../../script/pools/DeployIxHelvetia.s.sol";
import { DeployIxEdelweiss } from "../../script/pools/DeployIxEdelweiss.s.sol";
import { DeployIxAurebit } from "../../script/pools/DeployIxAurebit.s.sol";
import { SwapAndDepositToBodensee } from "../../src/gauge/SwapAndDepositToBodensee.sol";
import { VaultClassRegistry } from "../../src/gauge/VaultClassRegistry.sol";
import { IVaultClassRegistry } from "../../src/gauge/IVaultClassRegistry.sol";
import { GaugeEligibility } from "../../src/gauge/GaugeEligibility.sol";
import { GaugeRegistry } from "../../src/gauge/GaugeRegistry.sol";
import { IEfficiencyOracle } from "../../src/gauge/IEfficiencyOracle.sol";
import { MockTVLOracle } from "./mocks/CCBMocks.sol";
import { MockEfficiencyOracle, MockAuMT } from "./mocks/StageGMocks.sol";

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
    MockAuMT internal mockAuMT;

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
        mockAuMT = new MockAuMT();

        swapAndDeposit = new SwapAndDepositToBodensee(vault, bodenseePool, svZchf, IERC20(address(susds)), address(this), address(this));
        address[] memory genesisTokens = new address[](1);
        genesisTokens[0] = address(susds);
        IVaultClassRegistry.AdmissionType[] memory genesisTypes = new IVaultClassRegistry.AdmissionType[](1);
        genesisTypes[0] = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        vaultClassRegistry = new VaultClassRegistry(svZchf, swapAndDeposit, address(this), address(this), genesisTokens, genesisTypes);
        gaugeEligibility = new GaugeEligibility(address(awpf), address(vaultClassRegistry), address(mockTVLOracle), address(vault), address(aumm), address(mockAuMT), address(this), address(mockEfficiencyOracle));
        gaugeRegistry = new GaugeRegistry(address(this), address(gaugeEligibility), address(swapAndDeposit), address(svZchf));

        swapAndDeposit.setVaultClassRegistry(address(vaultClassRegistry));
        swapAndDeposit.setGaugeRegistry(address(gaugeRegistry));
        vaultClassRegistry.setAuMT(address(mockAuMT));
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
}
