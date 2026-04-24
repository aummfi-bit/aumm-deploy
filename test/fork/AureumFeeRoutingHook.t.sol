// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, TokenType, PoolRoleAccounts, AfterSwapParams, SwapKind, VaultSwapParams } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
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
    // -------------------------------------------------------------------------
    // Constants — D-D21 / deploy script inline parity
    // -------------------------------------------------------------------------

    bytes32 internal constant VAULT_SALT = bytes32(uint256(1));
    bytes32 internal constant BODENSEE_SALT = bytes32(uint256(2));
    bytes32 internal constant TRADING_POOL_SALT = bytes32(uint256(3));
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
    IERC20 internal svZchf;
    IERC4626 internal susds;

    // -------------------------------------------------------------------------
    // setUp
    // -------------------------------------------------------------------------

    function setUp() public {
        svZchf = IERC20(vm.envAddress("SV_ZCHF"));
        susds = IERC4626(vm.envAddress("SUSDS"));

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
            PoolRoleAccounts({
                pauseManager: GOVERNANCE_MULTISIG,
                swapFeeManager: GOVERNANCE_MULTISIG,
                poolCreator: address(0)
            }),
            0.0075e18,
            address(0),
            false,
            false,
            BODENSEE_SALT
        );
        assert(bodenseePool == predictedBodensee);

        hook = new AureumFeeRoutingHook(
            address(vault), predictedBodensee, svZchf, IERC20(address(aumm)), address(controller), GOVERNANCE_MULTISIG
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
            tokens[i].transfer(address(vault), amountsIn[i]);
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
            tokens[i].transfer(address(vault), amountsIn[i]);
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
        svZchf.transfer(address(vault), amountIn);
        vault.settle(svZchf, amountIn);
        vault.sendTo(IERC20(address(aumm)), address(this), amountOut);
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
        vm.startPrank(address(controller));
        svZchf.approve(address(hook), amount);
        vm.expectEmit(true, true, false, false, address(hook));
        emit IAureumFeeRoutingHook.YieldFeeRouted(tradingPool, address(svZchf), amount, 0);
        uint256 bptMinted = hook.routeYieldFee(tradingPool, svZchf, amount);
        vm.stopPrank();
        assertGt(bptMinted, 0);
        assertEq(IERC20(bodenseePool).balanceOf(address(controller)), bptMinted);
        assertEq(svZchf.balanceOf(address(hook)), 0);

        // Unprivileged caller — UnauthorizedCaller revert.
        address attacker = address(uint160(uint256(keccak256("attacker"))));
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(IAureumFeeRoutingHook.UnauthorizedCaller.selector, attacker));
        hook.routeYieldFee(tradingPool, svZchf, 1e18);
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
        uint256 swapAmount = 10e18;
        deal(address(svZchf), address(this), swapAmount, true);
        vault.unlock(abi.encodeCall(this._performSwapCallback, (swapAmount)));

        // Swap generates the protocol fee on tradingPool → Vault invokes
        // hook.onAfterSwap, which routes the fee to Bodensee via nested
        // swap + one-sided addLiquidity, minting new BPT.
        assertGt(IERC20(bodenseePool).totalSupply(), bptSupplyBefore);
        assertEq(svZchf.balanceOf(address(hook)), 0);
    }
}
