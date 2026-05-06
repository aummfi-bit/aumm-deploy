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
import { MiliariumPoolDeployer } from "../../script/pools/deploy-miliarium-pool.s.sol";
import { DeployIxHelvetia } from "../../script/pools/DeployIxHelvetia.s.sol";
import { DeployIxEdelweiss } from "../../script/pools/DeployIxEdelweiss.s.sol";
import { DeployIxAurebit } from "../../script/pools/DeployIxAurebit.s.sol";
import { IxEdelweissConfig } from "../../script/pools/configs/05_ixEdelweiss.s.sol";
import { IxAurebitConfig } from "../../script/pools/configs/14_ixAurebit.s.sol";

/**
 * @title MiliariumPilotPoolBase
 * @notice Shared fork-test base for Stage E Miliarium pilot pools—canonical harness shape per **E-D24**
 *         (`docs/STAGE_E_NOTES.md`); **E-D6** env-key suffix wording is superseded by that record and
 *         `docs/STAGE_E_PLAN.md` Mid-stage supersessions. **D-D21** CREATE2 / CREATE3 address prologue matches
 *         `test/fork/AureumFeeRoutingHook.t.sol` (env reads before any `new`). **D32** β-pattern init and swap
 *         callbacks—no Router, no Permit2. No test methods or derived contracts in this file — both at E1.6b.
 */
abstract contract MiliariumPilotPoolBase is Test {
    // Constants — D-D21 / E-D24 parity
    bytes32 internal constant VAULT_SALT = bytes32(uint256(1));
    bytes32 internal constant BODENSEE_SALT = bytes32(uint256(2));
    uint32 internal constant PAUSE_WINDOW_DURATION = uint32(4 * 365 days);
    uint256 internal constant BUFFER_PERIOD_DURATION = 90 days;
    uint256 internal constant MIN_TRADE_AMOUNT = 1_000_000;
    uint256 internal constant MIN_WRAP_AMOUNT = 1_000;
    string internal constant FACTORY_VERSION = '{"name":"AureumWeightedPoolFactory","version":1,"deployment":"20260427-fork-stage-e"}';
    string internal constant POOL_VERSION = '{"name":"AureumWeightedPool","version":1,"deployment":"20260427-fork-stage-e"}';
    address internal constant GOVERNANCE_MULTISIG = address(uint160(uint256(keccak256("govMultisig"))));
    address internal constant SUSDS_RATE_PROVIDER = 0x1195BE91e78ab25494C855826FF595Eef784d47B;
    address internal constant SV_ZCHF_RATE_PROVIDER = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;
    uint256 internal constant INIT_SEED = 1_000e18;

    // State
    DeployAureumVault internal vaultScript;
    WeightedPoolFactory internal wpf;
    AureumWeightedPoolFactory internal awpf;
    AuMM internal aumm;
    AureumFeeRoutingHook internal hook;
    AureumProtocolFeeController internal controller;
    IVault internal vault;
    address internal bodenseePool;
    address internal pilotPool;
    IERC20 internal svZchf;
    IERC4626 internal susds;

    // Virtual hooks for derived contracts
    function _deployer() internal virtual returns (MiliariumPoolDeployer);

    function _seedAmounts() internal view virtual returns (uint256[] memory);

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

        bodenseePool = wpf.create(
            "der-Bodensee",
            "BODENSEE",
            _bodenseeTokenConfigs(),
            _bodenseeWeights(),
            // E-D22 / OQ-11: Bodensee swap fee is immutable from block 0.
            // `swapFeeManager: address(0)` is BAL v3's "no one can change" sentinel.
            PoolRoleAccounts({
                pauseManager: GOVERNANCE_MULTISIG,
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

        hook = new AureumFeeRoutingHook(
            address(vault), predictedBodensee, svZchf, IERC20(address(aumm)), address(controller), GOVERNANCE_MULTISIG
        );
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

        pilotPool = _deployer().run();

        IERC20[] memory pilotTokens = vault.getPoolTokens(pilotPool);
        _initializePool(pilotPool, pilotTokens, _seedAmounts());
    }

    // Bodensee helpers — parity with test/fork/AureumFeeRoutingHook.t.sol
    function _bodenseeTokenConfigs() private view returns (TokenConfig[] memory) {
        address t0 = address(aumm);
        address t1 = address(susds);
        address t2 = address(svZchf);
        if (t0 > t1) (t0, t1) = (t1, t0);
        if (t1 > t2) (t1, t2) = (t2, t1);
        if (t0 > t1) (t0, t1) = (t1, t0);

        TokenConfig[] memory tokens = new TokenConfig[](3);
        tokens[0] = t0 == address(aumm)
            ? TokenConfig({
                token: IERC20(t0),
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            })
            : t0 == address(susds)
                ? TokenConfig({
                    token: IERC20(t0),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SUSDS_RATE_PROVIDER),
                    paysYieldFees: true
                })
                : TokenConfig({
                    token: IERC20(t0),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SV_ZCHF_RATE_PROVIDER),
                    paysYieldFees: true
                });
        tokens[1] = t1 == address(aumm)
            ? TokenConfig({
                token: IERC20(t1),
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            })
            : t1 == address(susds)
                ? TokenConfig({
                    token: IERC20(t1),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SUSDS_RATE_PROVIDER),
                    paysYieldFees: true
                })
                : TokenConfig({
                    token: IERC20(t1),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SV_ZCHF_RATE_PROVIDER),
                    paysYieldFees: true
                });
        tokens[2] = t2 == address(aumm)
            ? TokenConfig({
                token: IERC20(t2),
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            })
            : t2 == address(susds)
                ? TokenConfig({
                    token: IERC20(t2),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SUSDS_RATE_PROVIDER),
                    paysYieldFees: true
                })
                : TokenConfig({
                    token: IERC20(t2),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SV_ZCHF_RATE_PROVIDER),
                    paysYieldFees: true
                });
        return tokens;
    }

    function _bodenseeWeights() private view returns (uint256[] memory) {
        address t0 = address(aumm);
        address t1 = address(susds);
        address t2 = address(svZchf);
        if (t0 > t1) (t0, t1) = (t1, t0);
        if (t1 > t2) (t1, t2) = (t2, t1);
        if (t0 > t1) (t0, t1) = (t1, t0);

        uint256[] memory weights = new uint256[](3);
        weights[0] = t0 == address(aumm) ? 4e17 : 3e17;
        weights[1] = t1 == address(aumm) ? 4e17 : 3e17;
        weights[2] = t2 == address(aumm) ? 4e17 : 3e17;
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
        address t0 = address(aumm);
        address t1 = address(susds);
        address t2 = address(svZchf);
        if (t0 > t1) (t0, t1) = (t1, t0);
        if (t1 > t2) (t1, t2) = (t2, t1);
        if (t0 > t1) (t0, t1) = (t1, t0);

        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = IERC20(t0);
        tokens[1] = IERC20(t1);
        tokens[2] = IERC20(t2);
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

    function _performSwap(address pool, IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        deal(address(tokenIn), address(this), amountIn, true);
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
}

contract IxHelvetiaPilotTest is MiliariumPilotPoolBase {
    function _deployer() internal override returns (MiliariumPoolDeployer) {
        return new DeployIxHelvetia();
    }

    function _seedAmounts() internal pure override returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = INIT_SEED;
        amounts[1] = INIT_SEED;
        return amounts;
    }

    function test_Fork_IxHelvetia_DeploysAndRoutesFee() external {
        assertTrue(pilotPool != address(0));
        uint256 bptSupplyBefore = IERC20(bodenseePool).totalSupply();
        _performSwap(pilotPool, IERC20(address(susds)), svZchf, 1e18);
        assertGt(IERC20(bodenseePool).totalSupply(), bptSupplyBefore);
        assertEq(svZchf.balanceOf(address(hook)), 0);
    }
}

contract IxEdelweissPilotTest is MiliariumPilotPoolBase {
    function _deployer() internal override returns (MiliariumPoolDeployer) {
        return new DeployIxEdelweiss();
    }

    function _seedAmounts() internal pure override returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](4);
        // Per E10 / E-D25 — 1_000 × 10**decimals(token), matched to address-sorted slot order from
        // IxEdelweissConfig: waEthUSDT (6) / waEthUSDC (6) / ixEDEL (18) / svZCHF (18).
        amounts[0] = 1_000e6;
        amounts[1] = 1_000e6;
        amounts[2] = 1_000e18;
        amounts[3] = 1_000e18;
        return amounts;
    }

    function test_Fork_IxEdelweiss_DeploysAndRoutesFee() external {
        assertTrue(pilotPool != address(0));
        uint256 bptSupplyBefore = IERC20(bodenseePool).totalSupply();
        _performSwap(pilotPool, IERC20(IxEdelweissConfig.WAETHUSDC), svZchf, 1e6);
        assertGt(IERC20(bodenseePool).totalSupply(), bptSupplyBefore);
        assertEq(svZchf.balanceOf(address(hook)), 0);
    }
}

contract IxAurebitPilotTest is MiliariumPilotPoolBase {
    function _deployer() internal override returns (MiliariumPoolDeployer) {
        return new DeployIxAurebit();
    }

    function _seedAmounts() internal pure override returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](5);
        // Per E10 / E-D25 — 1_000 × 10**decimals(token), matched to address-sorted slot order from
        // IxAurebitConfig: WBTC (8) / Aave Prime GHO (18) / cbBTC (8) / ixEDEL (18) / svZCHF (18).
        amounts[0] = 1_000e8;
        amounts[1] = 1_000e18;
        amounts[2] = 1_000e8;
        amounts[3] = 1_000e18;
        amounts[4] = 1_000e18;
        return amounts;
    }

    function test_Fork_IxAurebit_DeploysAndRoutesFee() external {
        assertTrue(pilotPool != address(0));
        uint256 bptSupplyBefore = IERC20(bodenseePool).totalSupply();
        _performSwap(pilotPool, IERC20(IxAurebitConfig.WBTC), svZchf, 1e8);
        assertGt(IERC20(bodenseePool).totalSupply(), bptSupplyBefore);
        assertEq(svZchf.balanceOf(address(hook)), 0);
    }
}
