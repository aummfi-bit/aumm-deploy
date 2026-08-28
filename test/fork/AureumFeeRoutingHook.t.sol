// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { ForkEnvGuard } from "./ForkEnvGuard.sol";
import { Vm } from "forge-std/Vm.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, TokenType, PoolRoleAccounts, AfterSwapParams, SwapKind, VaultSwapParams } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

import { AuMM } from "../../src/token/AuMM.sol";
import { AureumFeeRoutingHook } from "../../src/fee_router/AureumFeeRoutingHook.sol";
import { AureumProtocolFeeController } from "../../src/vault/AureumProtocolFeeController.sol";
import { IAureumFeeRoutingHook } from "../../src/fee_router/IAureumFeeRoutingHook.sol";
import { DeployAureumVault } from "../../script/DeployAureumVault.s.sol";

/**
 * @title AureumFeeRoutingHookForkTest
 * @notice Fork integration scaffold for `AureumFeeRoutingHook`—Vault, inline
 *         WPF, der-Bodensee, 50/50 trading pool, and hook. Test bodies are
 *         filled in D7.1b–D7.1g.
 * @dev Run: `source .env` then
 *        `forge test --fork-url $MAINNET_RPC_URL \
 *        --match-path test/fork/AureumFeeRoutingHook.t.sol -vv`
 *      — fork URL from the CLI, not `vm.createSelectFork`, matching
 *        `test/fork/DeployAureumVault.t.sol`.
 *      **§D7.1a**; **D-D19** (this file and naming); **D-D20** (real
 *      `AuMM`, no `setMinter` / `mint` in setUp or tests); **D-D21** (prologue
 *      pre-computes `vm.computeCreateAddress` / `CREATE3.getDeployed` before
 *      any `new`; `SV_ZCHF` / `SUSDS` read first to avoid shifting
 *      `address(this)` nonce); **D-D22** (six tests; trading pool 50/50, no
 *      rate providers). Env for `DeployAureumVault` is set with `vm.setEnv`
 *      (same pattern as the Stage B fork test).
 */
contract AureumFeeRoutingHookForkTest is Test {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants — D-D21 / deploy script inline parity
    // -------------------------------------------------------------------------

    bytes32 internal constant VAULT_SALT = bytes32(uint256(1));
    bytes32 internal constant BODENSEE_SALT = bytes32(uint256(2));
    bytes32 internal constant TRADING_POOL_SALT = bytes32(uint256(3));
    bytes32 internal constant NO_SVZCHF_POOL_SALT = bytes32(uint256(4));
    uint32 internal constant PAUSE_WINDOW_DURATION = uint32(4 * 365 days);
    uint256 internal constant BUFFER_PERIOD_DURATION = 90 days;
    uint256 internal constant MIN_TRADE_AMOUNT = 1_000_000;
    uint256 internal constant MIN_WRAP_AMOUNT = 1_000;
    string internal constant FACTORY_VERSION = '{"name":"AureumWeightedPoolFactory","version":1,"deployment":"20260423-fork"}';
    string internal constant POOL_VERSION = '{"name":"AureumWeightedPool","version":1,"deployment":"20260423-fork"}';
    address internal constant GOVERNANCE_MULTISIG = address(uint160(uint256(keccak256("govMultisig"))));
    address internal constant SUSDS_RATE_PROVIDER = 0x1195BE91e78ab25494C855826FF595Eef784d47B;
    address internal constant SV_ZCHF_RATE_PROVIDER = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;
    uint256 internal constant INIT_SEED = 1_000e18;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    DeployAureumVault internal vaultScript;
    WeightedPoolFactory internal wpf;
    AuMM internal aumm;
    AureumFeeRoutingHook internal hook;
    AureumProtocolFeeController internal controller;
    IVault internal vault;
    address internal bodenseePool;
    address internal tradingPool;
    address internal noSvZchfPool;
    IERC20 internal svZchf;
    IERC4626 internal susds;

    // -------------------------------------------------------------------------
    // setUp
    // -------------------------------------------------------------------------

    function setUp() public {
        svZchf = IERC20(vm.envAddress("SV_ZCHF"));
        susds = IERC4626(vm.envAddress("SUSDS"));
        string[] memory forkEnvKeys = new string[](2);
        forkEnvKeys[0] = "SUSDS";
        forkEnvKeys[1] = "SV_ZCHF";
        ForkEnvGuard.assertMainnetEnv(forkEnvKeys);


        uint64 startNonce = vm.getNonce(address(this));
        address vaultScriptAddr = vm.computeCreateAddress(address(this), startNonce + 0);
        address wpfAddr = vm.computeCreateAddress(address(this), startNonce + 1);
        address auMmAddr = vm.computeCreateAddress(address(this), startNonce + 2);
        address hookAddr = vm.computeCreateAddress(address(this), startNonce + 3);
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
            address(vault), predictedBodensee, svZchf, IERC20(address(susds)), IERC20(address(aumm)), address(controller), GOVERNANCE_MULTISIG
        );
        assert(address(hook) == hookAddr);

        tradingPool = wpf.create(
            "aumm-svZCHF-50-50",
            "AUMM-SVZCHF",
            _tradingPoolTokenConfigs(),
            _tradingPoolWeights(),
            PoolRoleAccounts({
                pauseManager: GOVERNANCE_MULTISIG,
                swapFeeManager: GOVERNANCE_MULTISIG,
                poolCreator: address(0)
            }),
            0.0075e18,
            address(hook),
            false,
            false,
            TRADING_POOL_SALT
        );

        noSvZchfPool = wpf.create(
            "aumm-sUSDS-50-50",
            "AUMM-SUSDS",
            _noSvZchfPoolTokenConfigs(),
            _tradingPoolWeights(),
            PoolRoleAccounts({
                pauseManager: GOVERNANCE_MULTISIG,
                swapFeeManager: GOVERNANCE_MULTISIG,
                poolCreator: address(0)
            }),
            0.0075e18,
            address(hook),
            false,
            false,
            NO_SVZCHF_POOL_SALT
        );
    }

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

    function _tradingPoolTokenConfigs() private view returns (TokenConfig[] memory) {
        address t0 = address(aumm);
        address t1 = address(svZchf);
        if (t0 > t1) (t0, t1) = (t1, t0);
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0] = TokenConfig({
            token: IERC20(t0),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });
        tokens[1] = TokenConfig({
            token: IERC20(t1),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });
        return tokens;
    }

    function _noSvZchfPoolTokenConfigs() private view returns (TokenConfig[] memory) {
        address t0 = address(aumm);
        address t1 = address(susds);
        if (t0 > t1) (t0, t1) = (t1, t0);
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0] = TokenConfig({
            token: IERC20(t0),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });
        tokens[1] = TokenConfig({
            token: IERC20(t1),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });
        return tokens;
    }

    function _tradingPoolWeights() private pure returns (uint256[] memory) {
        uint256[] memory weights = new uint256[](2);
        weights[0] = 5e17;
        weights[1] = 5e17;
        return weights;
    }

    // -------------------------------------------------------------------------
    // Bodensee fork init — (β) pattern per D32
    // -------------------------------------------------------------------------

    /// @notice Bodensee fork initialization — (β) pattern per D32. Seeding via
    ///         `deal` to `address(this)` is D-D20-compatible: the constraint
    ///         is no `setMinter` / `mint()` in setUp, not "no AuMM balance".
    function _initializeBodensee() internal returns (uint256 bptOut) {
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
            tokens[i].safeTransfer(address(vault), amountsIn[i]);
            vault.settle(tokens[i], amountsIn[i]);
        }
    }

    // -------------------------------------------------------------------------
    // Trading pool fork init + swap callback — (β) pattern per D32
    // -------------------------------------------------------------------------

    /// @notice Trading pool fork initialization — (β) pattern per D32. Seeds
    ///         underlying balances via `deal`, then `vault.unlock` with
    ///         `initialize` and per-token `settle` in the callback.
    function _initializeTradingPool() internal returns (uint256 bptOut) {
        deal(address(aumm), address(this), INIT_SEED, true);
        deal(address(svZchf), address(this), INIT_SEED, true);

        bytes memory result = vault.unlock(abi.encodeCall(this._initializeTradingPoolCallback, ()));
        bptOut = abi.decode(result, (uint256));
    }

    function _initializeTradingPoolCallback() external returns (uint256 bptOut) {
        require(msg.sender == address(vault), "onlyVault");
        address t0 = address(aumm);
        address t1 = address(svZchf);
        if (t0 > t1) (t0, t1) = (t1, t0);
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(t0);
        tokens[1] = IERC20(t1);
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = INIT_SEED;
        amountsIn[1] = INIT_SEED;

        bptOut = vault.initialize(tradingPool, address(this), tokens, amountsIn, 0, "");
        for (uint256 i = 0; i <= 1; ++i) {
            tokens[i].safeTransfer(address(vault), amountsIn[i]);
            vault.settle(tokens[i], amountsIn[i]);
        }
    }

    /// @notice `sendTo` resolves the `tokenOut` debit side so no explicit
    ///         `settle` is needed for `tokenOut`.
    function _performSwapCallback(uint256 swapAmount) external {
        require(msg.sender == address(vault), "onlyVault");
        (, uint256 amountIn, uint256 amountOut) = vault.swap(
            VaultSwapParams({
                kind: SwapKind.EXACT_IN,
                pool: tradingPool,
                tokenIn: svZchf,
                tokenOut: IERC20(address(aumm)),
                amountGivenRaw: swapAmount,
                limitRaw: 0,
                userData: ""
            })
        );
        svZchf.safeTransfer(address(vault), amountIn);
        vault.settle(svZchf, amountIn);
        vault.sendTo(IERC20(address(aumm)), address(this), amountOut);
    }

    // -------------------------------------------------------------------------
    // No-svZCHF pool fork init + swap callback — F-14 PoC (WH-G.2)
    // -------------------------------------------------------------------------

    function _initializeNoSvZchfPool() internal returns (uint256 bptOut) {
        deal(address(aumm), address(this), INIT_SEED, true);
        deal(address(susds), address(this), INIT_SEED, true);

        bytes memory result = vault.unlock(abi.encodeCall(this._initializeNoSvZchfPoolCallback, ()));
        bptOut = abi.decode(result, (uint256));
    }

    function _initializeNoSvZchfPoolCallback() external returns (uint256 bptOut) {
        require(msg.sender == address(vault), "onlyVault");
        address t0 = address(aumm);
        address t1 = address(susds);
        if (t0 > t1) (t0, t1) = (t1, t0);
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(t0);
        tokens[1] = IERC20(t1);
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = INIT_SEED;
        amountsIn[1] = INIT_SEED;

        bptOut = vault.initialize(noSvZchfPool, address(this), tokens, amountsIn, 0, "");
        for (uint256 i = 0; i <= 1; ++i) {
            tokens[i].safeTransfer(address(vault), amountsIn[i]);
            vault.settle(tokens[i], amountsIn[i]);
        }
    }

    function _performSwapOnNoSvZchfPoolCallback(uint256 swapAmount) external {
        require(msg.sender == address(vault), "onlyVault");
        (, uint256 amountIn, uint256 amountOut) = vault.swap(
            VaultSwapParams({
                kind: SwapKind.EXACT_IN,
                pool: noSvZchfPool,
                tokenIn: IERC20(address(susds)),
                tokenOut: IERC20(address(aumm)),
                amountGivenRaw: swapAmount,
                limitRaw: 0,
                userData: ""
            })
        );
        IERC20(address(susds)).safeTransfer(address(vault), amountIn);
        vault.settle(IERC20(address(susds)), amountIn);
        vault.sendTo(IERC20(address(aumm)), address(this), amountOut);
    }

    function _forkSwapExactIn(address tIn, address tOut, uint256 amt) internal returns (uint256 out) {
        bytes memory result = vault.unlock(abi.encodeCall(this._forkSwapCallback, (tIn, tOut, amt)));
        out = abi.decode(result, (uint256));
    }

    function _forkSwapCallback(address tIn, address tOut, uint256 amt) external returns (uint256 amountOut) {
        require(msg.sender == address(vault), "onlyVault");
        (, uint256 amountIn, uint256 amountOut_) = vault.swap(
            VaultSwapParams({
                kind: SwapKind.EXACT_IN,
                pool: tradingPool,
                tokenIn: IERC20(tIn),
                tokenOut: IERC20(tOut),
                amountGivenRaw: amt,
                limitRaw: 0,
                userData: ""
            })
        );
        IERC20(tIn).safeTransfer(address(vault), amountIn);
        vault.settle(IERC20(tIn), amountIn);
        vault.sendTo(IERC20(tOut), address(this), amountOut_);
        amountOut = amountOut_;
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

    // -------------------------------------------------------------------------
    // D7.1b–D7.1g — test bodies (empty in D7.1a)
    // -------------------------------------------------------------------------

    function test_Fork_WPFBoundToAureumVault() public view {
        assertEq(address(wpf.getVault()), address(vault));
    }

    function test_Fork_BodenseeYieldCollectionReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(AureumProtocolFeeController.BodenseeYieldCollectionDisabled.selector)
        );
        controller.collectAggregateFees(bodenseePool);
    }

    function test_Fork_WithdrawProtocolFeesRecipientCheck() public {
        address wrongRecipient = address(uint160(uint256(keccak256("wrongRecipient"))));
        vm.prank(GOVERNANCE_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(
                AureumProtocolFeeController.InvalidRecipient.selector,
                address(hook),
                wrongRecipient
            )
        );
        controller.withdrawProtocolFees(tradingPool, wrongRecipient);
    }

    function test_Fork_RouteYieldFeePrimitive() public {
        _initializeBodensee();
        uint256 amount = 100e18;
        deal(address(svZchf), address(controller), amount, true);
        uint256 supplyBefore = IERC20(bodenseePool).totalSupply();
        uint256 reserveBefore = _bodenseeReserve(svZchf);
        vm.startPrank(address(controller));
        svZchf.approve(address(hook), amount);
        vm.expectEmit(true, true, false, false, address(hook));
        emit IAureumFeeRoutingHook.YieldFeeRouted(tradingPool, address(svZchf), amount, 0);
        uint256 bptMinted = hook.routeYieldFee(tradingPool, svZchf, amount, 0, 0);
        vm.stopPrank();
        assertEq(bptMinted, 0, "PB-D68 (vi) - donation mints no BPT");
        assertEq(IERC20(bodenseePool).balanceOf(address(controller)), 0, "F-23 - no redeemable claim reaches the fee controller");
        assertEq(IERC20(bodenseePool).totalSupply(), supplyBefore, "F-23 - BPT supply unchanged by a donation");
        assertGt(_bodenseeReserve(svZchf), reserveBefore, "PB-D68 (xvii) - reserve rose; exact delta is not a Vault guarantee for rate-bearing rails");
        assertLt(svZchf.balanceOf(address(hook)), 1_000_000, "PB-D68 (xix) - dust only, swept by the next route");

        // Unprivileged caller — UnauthorizedCaller revert.
        address attacker = address(uint160(uint256(keccak256("attacker"))));
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(IAureumFeeRoutingHook.UnauthorizedCaller.selector, attacker));
        hook.routeYieldFee(tradingPool, svZchf, 1e18, 0, 0);
    }

    // E.4 (PP-D48 (i)): the routed amount is READ from `_protocolFeeAmounts[pool][token]`
    // rather than passed, and `collectAggregateFees` accrues nothing on a static fork
    // block, so a route driven here must credit the ledger directly. Slot formula and its
    // base-slot-7 provenance are the unit suite's (`test/unit/AureumProtocolFeeController
    // .t.sol` `_protocolFeeAmountsSlot`); every caller below asserts through the public
    // `getProtocolFeeAmounts` getter that the seed landed, so a wrong slot fails loudly
    // rather than routing a silent zero.
    function _seedLedger(address pool, IERC20 token, uint256 amount) private {
        bytes32 outerSlot = keccak256(abi.encode(pool, uint256(7)));
        vm.store(address(controller), keccak256(abi.encode(token, outerSlot)), bytes32(amount));
    }

    function test_Fork_RouteYieldFeeToHookEntryPoint() public {
        _initializeBodensee();
        uint256 amount = 100e18;

        // Step 1 — the permissionless Balancer-shaped collect (zero accrual on
        // a static fork block; exercises the real path without a rate-evolution
        // scenario — live yield accrual is the Sepolia run's job, PB3).
        controller.collectAggregateFees(tradingPool);

        // Step 2 — credit the pool's ledger and seed the controller's balance, then
        // route through the OQ-20 governance entry point: no prank-as-controller, the
        // real authenticate chain. Post-E.4 the routed amount is the CREDIT, not an
        // argument, so the seed is what makes this route non-zero.
        _seedLedger(tradingPool, svZchf, amount);
        deal(address(svZchf), address(controller), amount, true);
        (, uint256 idx) = vault.getPoolTokenCountAndIndexOfToken(tradingPool, svZchf);
        assertEq(
            controller.getProtocolFeeAmounts(tradingPool)[idx],
            amount,
            "rig: the ledger seed landed in the slot the route reads"
        );
        uint256 bodenseeSupplyBefore = IERC20(bodenseePool).totalSupply();
        uint256 bodenseeReserveBefore = _bodenseeReserve(svZchf);

        vm.expectEmit(true, true, false, false, address(hook));
        emit IAureumFeeRoutingHook.YieldFeeRouted(tradingPool, address(svZchf), amount, 0);
        vm.prank(GOVERNANCE_MULTISIG);
        uint256 bptMinted = controller.routeYieldFeeToHook(tradingPool, svZchf, 0);

        assertEq(bptMinted, 0, "PB-D68 (vi) - donation mints no BPT");
        assertEq(IERC20(bodenseePool).balanceOf(address(controller)), 0, "F-23 - no redeemable claim reaches the fee controller");
        assertEq(IERC20(bodenseePool).totalSupply(), bodenseeSupplyBefore, "F-23 - BPT supply unchanged by a donation");
        assertGt(_bodenseeReserve(svZchf), bodenseeReserveBefore, "PB-D68 (xvii) - reserve rose; exact delta is not a Vault guarantee for rate-bearing rails");
        assertLt(svZchf.balanceOf(address(hook)), 1_000_000, "PB-D68 (xix) - dust only, swept by the next route");
        assertEq(svZchf.allowance(address(controller), address(hook)), 0);

        // Step 3 — OQ-21: an immediate second route is epoch-throttled.
        deal(address(svZchf), address(controller), amount, true);
        vm.prank(GOVERNANCE_MULTISIG);
        vm.expectRevert(AureumProtocolFeeController.RouteThrottled.selector);
        controller.routeYieldFeeToHook(tradingPool, svZchf, 0);

        // Step 4 — the deployed-authorizer gate: non-governance reverts.
        address attacker = address(uint160(uint256(keccak256("attacker"))));
        vm.prank(attacker);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        controller.routeYieldFeeToHook(tradingPool, svZchf, 0);
    }

    function test_Fork_RecursionGuard() public {
        AfterSwapParams memory guarded = AfterSwapParams({
            kind: SwapKind.EXACT_IN,
            tokenIn: IERC20(address(aumm)),
            tokenOut: svZchf,
            amountInScaled18: 1e18,
            amountOutScaled18: 1e18,
            tokenInBalanceScaled18: 0,
            tokenOutBalanceScaled18: 0,
            amountCalculatedScaled18: 1e18,
            amountCalculatedRaw: 123e18,
            router: address(hook),
            pool: tradingPool,
            userData: ""
        });

        vm.recordLogs();
        vm.prank(address(vault));
        (bool hookSuccess, uint256 amountOut) = hook.onAfterSwap(guarded);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(hookSuccess);
        assertEq(amountOut, 123e18);
        // (i) Guarded path must not emit SwapFeeRouted.
        bytes32 swapFeeRoutedTopic = IAureumFeeRoutingHook.SwapFeeRouted.selector;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length > 0) {
                assertTrue(logs[i].topics[0] != swapFeeRoutedTopic, "guarded branch emitted SwapFeeRouted");
            }
        }

        // (ii) Unguarded path reaches collectSwapAggregateFeesForHook on a
        //      fresh pool with zero accrued fees — call returns cleanly,
        //      emits no SwapFeeRouted (nothing to route), and does not revert.
        AfterSwapParams memory unguarded = guarded;
        unguarded.router = address(this);
        vm.prank(address(vault));
        (hookSuccess, amountOut) = hook.onAfterSwap(unguarded);
        assertTrue(hookSuccess);
        assertEq(amountOut, 123e18);
    }

    function test_Fork_SwapRoutesFeeToBodensee() public {
        _initializeBodensee();
        _initializeTradingPool();
        uint256 bptSupplyBefore = IERC20(bodenseePool).totalSupply();
        uint256 bodenseeReserveBefore = _bodenseeReserve(svZchf);
        uint256 swapAmount = 10e18;
        deal(address(svZchf), address(this), swapAmount, true);
        vault.unlock(abi.encodeCall(this._performSwapCallback, (swapAmount)));

        // Swap generates the protocol fee on tradingPool → Vault invokes
        // hook.onAfterSwap, which routes the fee to Bodensee via a nested
        // swap plus a one-sided DONATION per PB-D68 (v): depth rises and no
        // claim on that depth is created. The fee amount is not known
        // test-side, so the reserve assertion is strict-greater rather than
        // exact; paired with supply-unchanged it still separates a real
        // donation from a silently skipped route.
        assertEq(IERC20(bodenseePool).totalSupply(), bptSupplyBefore, "F-23 - BPT supply unchanged by a donation");
        assertGt(_bodenseeReserve(svZchf), bodenseeReserveBefore, "PB-D68 (v) - depth donated, not silently skipped");
        assertLt(svZchf.balanceOf(address(hook)), 1_000_000, "PB-D68 (xix) - dust only, swept by the next route");
    }

    function test_Fork_F14_sUsdsRailRoutesToBodensee() public {
        _initializeBodensee();
        _initializeNoSvZchfPool();
        deal(address(susds), address(this), 10e18, true);
        uint256 bodenseeSupplyBefore = IERC20(bodenseePool).totalSupply();
        uint256 bodenseeReserveBefore = _bodenseeReserve(IERC20(address(susds)));
        // P-D12 (2) — noSvZchfPool = [AuMM, sUSDS] holds no svZCHF but holds sUSDS, so its Bodensee rail is sUSDS; onAfterSwap converts the fee to sUSDS on-pool and one-sides sUSDS into der Bodensee (routes, not skip).
        vault.unlock(abi.encodeCall(this._performSwapOnNoSvZchfPoolCallback, (10e18)));
        assertEq(hook.poolBodenseeDepositToken(noSvZchfPool), address(susds), "noSvZchfPool rail is sUSDS");
        assertEq(IERC20(bodenseePool).totalSupply(), bodenseeSupplyBefore, "F-23 - BPT supply unchanged by a donation");
        assertGt(_bodenseeReserve(IERC20(address(susds))), bodenseeReserveBefore, "sUSDS donated to Bodensee, not silently skipped");
    }

    // -------------------------------------------------------------------------
    // PB-D9 bounded-route witness (PB2.4d1) (4)
    // -------------------------------------------------------------------------

    function test_Fork_RouteYieldFee_minBptAmountOut_revertsWhenTooTight() public {
        _initializeBodensee();
        deal(address(svZchf), address(controller), 100e18, true);
        vm.startPrank(address(controller));
        svZchf.approve(address(hook), 100e18);
        // PB-D68 (xiv) - post-F-23 the floor is unsatisfiable at every nonzero
        // value, not merely at this one, so the revert now comes from the hook
        // before the Vault is reached. The full encoding pins the offending
        // value handed back to the caller.
        vm.expectRevert(
            abi.encodeWithSelector(
                IAureumFeeRoutingHook.BptFloorUnavailableOnDonation.selector,
                type(uint256).max
            )
        );
        hook.routeYieldFee(tradingPool, svZchf, 100e18, 0, type(uint256).max);
        vm.stopPrank();
    }

    function test_Fork_RouteYieldFee_minDepositTokenOut_revertsWhenTooTight() public {
        _initializeBodensee();
        _initializeTradingPool();
        deal(address(aumm), address(controller), 10e18, true);
        vm.startPrank(address(controller));
        IERC20(address(aumm)).approve(address(hook), 10e18);
        vm.expectPartialRevert(IVaultErrors.SwapLimit.selector);
        hook.routeYieldFee(tradingPool, IERC20(address(aumm)), 10e18, type(uint256).max, 0);
        vm.stopPrank();
    }

    function test_Fork_RouteYieldFee_addLegSucceedsAtRealisticBound() public {
        _initializeBodensee();
        uint256 supplyBefore = IERC20(bodenseePool).totalSupply();
        uint256 reserveBefore = _bodenseeReserve(svZchf);
        deal(address(svZchf), address(controller), 100e18, true);
        vm.startPrank(address(controller));
        svZchf.approve(address(hook), 100e18);
        uint256 bpt = hook.routeYieldFee(tradingPool, svZchf, 100e18, 0, 0);
        vm.stopPrank();

        // PB-D68 (xiv) - the probe-then-bound structure this test carried is
        // gone with the mint leg: no floor above zero is satisfiable, so the
        // only bound the add leg can take is zero. The name is retained as
        // historical because the F-13 ledger row cites it; what the test now
        // witnesses is that the leg still completes against real fork
        // economics and deepens the lake without minting a claim.
        assertEq(bpt, 0, "PB-D68 (vi) - donation mints no BPT");
        assertEq(IERC20(bodenseePool).totalSupply(), supplyBefore, "F-23 - BPT supply unchanged by a donation");
        assertGt(_bodenseeReserve(svZchf), reserveBefore, "PB-D68 (xvii) - reserve rose; exact delta is not a Vault guarantee for rate-bearing rails");
    }

    function test_Fork_RouteYieldFee_swapLegSucceedsAtRealisticBound() public {
        _initializeBodensee();
        _initializeTradingPool();
        uint256 reserveBefore = _bodenseeReserve(svZchf);
        deal(address(aumm), address(controller), 10e18, true);
        vm.startPrank(address(controller));
        IERC20(address(aumm)).approve(address(hook), 10e18);
        uint256 bpt = hook.routeYieldFee(tradingPool, IERC20(address(aumm)), 10e18, 5e18, 0);
        vm.stopPrank();
        // PB-D68 (xiv) - the realistic bound under test here is the SURVIVING
        // one, minDepositTokenOut at 5e18 on the phase-1 swap leg; only the BPT
        // floor moved to zero, so this test keeps its name.
        assertEq(bpt, 0, "PB-D68 (vi) - donation mints no BPT");
        assertGt(_bodenseeReserve(svZchf), reserveBefore, "PB-D68 (v) - swap leg output donated, not silently skipped");
    }

    // -------------------------------------------------------------------------
    // PB-D9 onAfterSwap ACCEPT evidence — fee-rider sandwich sim (PB2.4d2) (2)
    // -------------------------------------------------------------------------

    /// @notice PB-D9 (ii) — the onAfterSwap fee-rider is ≈ 50% × one trade's pool
    ///         swap fee (dust); measured against real fork economics; supports
    ///         onAfterSwap ACCEPT (0/0 bounds retained). The batched yield path is
    ///         the built half (PB2.4b); this residual is per-swap dust only.
    function test_Fork_F13_feeRiderPerSwapIsDust() public {
        _initializeBodensee();
        _initializeTradingPool();
        deal(address(aumm), address(this), 10_000e18, true);
        deal(address(svZchf), address(this), 10_000e18, true);

        uint256 V = 50e18;
        vm.recordLogs();
        _forkSwapExactIn(address(aumm), address(svZchf), V);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 swapFeeRoutedTopic = IAureumFeeRoutingHook.SwapFeeRouted.selector;
        uint256 feeRider;
        uint256 bptMinted;
        bool found;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == swapFeeRoutedTopic) {
                (feeRider, bptMinted) = abi.decode(logs[i].data, (uint256, uint256));
                found = true;
                break;
            }
        }
        assertTrue(found, "SwapFeeRouted not emitted");

        emit log_named_uint("V", V);
        emit log_named_uint("feeRider", feeRider);
        assertGt(feeRider, 0);
        assertLt(feeRider, V / 20);
    }

    /// @notice PB-D9 (ii) — skew-envelope cost on the conversion venue exceeds the
    ///         entire fee-rider prize; conservative fork sim supporting onAfterSwap
    ///         ACCEPT (0/0 bounds retained). Batched yield routing is PB2.4b; this
    ///         residual is per-swap dust only.
    function test_Fork_F13_skewCostExceedsFeeRiderPrize() public {
        _initializeBodensee();
        _initializeTradingPool();
        deal(address(aumm), address(this), 10_000e18, true);
        deal(address(svZchf), address(this), 10_000e18, true);

        uint256 SKEW = 200e18;
        uint256 got = _forkSwapExactIn(address(aumm), address(svZchf), SKEW);
        uint256 back = _forkSwapExactIn(address(svZchf), address(aumm), got);
        uint256 skewCost = SKEW - back;

        vm.recordLogs();
        _forkSwapExactIn(address(aumm), address(svZchf), 50e18);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 swapFeeRoutedTopic = IAureumFeeRoutingHook.SwapFeeRouted.selector;
        uint256 feeRider;
        bool found;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == swapFeeRoutedTopic) {
                (feeRider,) = abi.decode(logs[i].data, (uint256, uint256));
                found = true;
                break;
            }
        }
        assertTrue(found, "SwapFeeRouted not emitted");

        emit log_named_uint("skewCost", skewCost);
        emit log_named_uint("feeRider", feeRider);
        emit log_named_uint("skewCost / feeRider", skewCost / feeRider);
        assertGt(skewCost, feeRider);
    }

    /**
     * @notice E.4 — `routeYieldFeeToHook` spends the controller's tokens without
     *         debiting `_protocolFeeAmounts[pool][token]`, and without bounding
     *         `amount` by the pool's credit.
     * @dev Reproduction PoC for seam-1 root cause E.4 (Low). Both clauses are
     *      asserted on the already-railed `tradingPool` path that
     *      `test_Fork_RouteYieldFeeToHookEntryPoint` (L568-L607) proves reachable
     *      through the real `authenticate` chain — capability, not conduct
     *      (PP-D41). The `deal` is not a scaffold gap but the finding itself: a
     *      controller balance that no pool's credit backs is exactly what an
     *      unbounded spend draws on. Contrast `_withdrawProtocolFees`
     *      (`src/vault/AureumProtocolFeeController.sol:791-798`), which zeroes
     *      the ledger entry and transfers exactly that amount.
     */
    function test_P1_E4_routeYieldFeeToHookSpendsWithoutDebitingLedger() public {
        _initializeBodensee();
        uint256 amount = 100e18;

        // Permissionless collect first, so the ledger read below is post-collect
        // truth rather than a stale zero.
        controller.collectAggregateFees(tradingPool);

        (, uint256 idx) = vault.getPoolTokenCountAndIndexOfToken(tradingPool, svZchf);
        uint256[] memory creditBefore = controller.getProtocolFeeAmounts(tradingPool);

        // Clause two: the routed amount is not bounded by the pool's credit.
        assertLt(creditBefore[idx], amount, "E.4 - amount exceeds the pool's entire svZCHF credit");

        deal(address(svZchf), address(controller), amount, true);
        uint256 controllerBalanceBefore = svZchf.balanceOf(address(controller));

        vm.prank(GOVERNANCE_MULTISIG);
        controller.routeYieldFeeToHook(tradingPool, svZchf, amount, 0, 0);

        // The tokens left the controller's commingled balance ...
        assertEq(
            svZchf.balanceOf(address(controller)),
            controllerBalanceBefore - amount,
            "E.4 - amount left the controller's commingled balance"
        );

        // ... and clause one: no ledger entry moved.
        uint256[] memory creditAfter = controller.getProtocolFeeAmounts(tradingPool);
        assertEq(creditAfter.length, creditBefore.length, "E.4 - token count stable");
        for (uint256 i = 0; i < creditAfter.length; ++i) {
            assertEq(creditAfter[i], creditBefore[i], "E.4 - protocol fee ledger not debited");
        }
    }
}
