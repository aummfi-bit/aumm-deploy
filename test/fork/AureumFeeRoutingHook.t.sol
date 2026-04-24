// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, TokenType, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

import { AuMM } from "../../src/token/AuMM.sol";
import { AureumFeeRoutingHook } from "../../src/fee_router/AureumFeeRoutingHook.sol";
import { AureumProtocolFeeController } from "../../src/vault/AureumProtocolFeeController.sol";
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

    function test_Fork_RouteYieldFeePrimitive() public {}

    function test_Fork_RecursionGuard() public {}

    function test_Fork_SwapRoutesFeeToBodensee() public {}
}
