// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    RemoveLiquidityParams,
    RemoveLiquidityKind,
    TokenConfig,
    TokenType,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { Router } from "@balancer-labs/v3-vault/contracts/Router.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { StagePIntegrationFixture } from "./StagePIntegration.t.sol";
import { DeployRouter } from "../../script/DeployRouter.s.sol";
import { EmissionDistributor } from "../../src/emission/EmissionDistributor.sol";
import { VotingWeight } from "../../src/governance/VotingWeight.sol";
import { AureumTime } from "../../src/lib/AureumTime.sol";

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

    /// @notice PP-D16's fork witness for B.2: a trusted-router exit succeeds against hostile EMA state
    ///         and clears the checkpoint a poke refuses to touch. The contrast IS the design. With the
    ///         oracle stale, `poke` reaches `_positionPower`'s staleness branch, reads `(0, true)`, and
    ///         the PP-D52 (ix) hold refuses the downward write, so no third party can reset this holder
    ///         however often they try. `onPositionClosed` reads no oracle at all per PP-D55 (ix), so the
    ///         same state that blocks the poke cannot block the exit. That is why clause (ii) rejected
    ///         sharing poke's loop: an entry inheriting the hold would inherit the brick.
    function test_P1_B2_trustedExitClearsTheCheckpointUnderAStaleEma() public {
        _seatRouter();
        // PP10: `_matureStack` adds through the Vault DIRECTLY and is attributed by this contract's
        // own `getSender()`, so the hook credits nobody unless this contract is ALSO on the F-09
        // allowlist. StagePEndToEndTest seats itself in its own setUp for exactly this reason; this
        // file does not, because its other cases exercise the real Router's seat in isolation.
        vm.prank(gov);
        hook.setTrustedRouter(address(this), true);
        address lp = makeAddr("p1_b2_forkLp");
        _seatVoter(lp);

        VotingWeight vw = orchestrator.votingWeight();
        uint256 weightBefore = vw.governanceWeight(lp);
        uint256 supplyBefore = vw.totalSupply();
        assertGt(weightBefore, 0, "premise: the matured position carries governance weight");

        // Hostile state: one epoch past the last refresh, so every live position reads stale.
        vm.roll(block.number + AureumTime.BLOCKS_PER_EPOCH + 1);

        // The hold is armed and real: a stranger cannot ratchet this holder down.
        address stranger = makeAddr("p1_b2_forkStranger");
        vm.prank(stranger);
        vw.poke(lp);
        assertEq(vw.governanceWeight(lp), weightBefore, "premise: the stale-EMA hold refuses the poke");
        assertEq(vw.totalSupply(), supplyBefore, "premise: the denominator is held too");

        // The exit runs anyway, through the REAL seated Router, and clears what the poke could not.
        uint256 bptHeld = IERC20(pilotPools[0]).balanceOf(lp);
        assertGt(bptHeld, 0, "premise: the LP holds its receipt");
        IERC20[] memory tokens = vault.getPoolTokens(pilotPools[0]);
        uint256[] memory minOut = new uint256[](tokens.length);
        vm.prank(lp);
        IERC20(pilotPools[0]).approve(router, bptHeld);
        vm.prank(lp);
        Router(payable(router)).removeLiquidityProportional(pilotPools[0], bptHeld, minOut, false, "");

        assertEq(distributor.userLP(pilotPools[0], lp), 0, "the exit did not reach the recorder");
        assertEq(vw.governanceWeight(lp), 0, "a stale EMA blocked the storage-only close");
        assertEq(vw.totalSupply(), supplyBefore - weightBefore, "the denominator kept the closed position");
    }

    /* ---------- B.3 / PP-D58 (iii) — the seed recorded through the path that already records ---------- */

    /// @dev A fresh awpf pool on the canonical hook, created after `orchestrator.deploy()` so the recorder
    ///      and the Router seat can both precede its seeding, which RB-033 found the pilots cannot express:
    ///      they are initialized before any recorder is wired. Mirrors StagePEndToEndTest's candidate builder.
    function _buildSeedWitnessPool() internal returns (address pool) {
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
        pool = awpf.create(
            "B3 Seed Witness",
            "B3SEED",
            tokens,
            weights,
            PoolRoleAccounts({ pauseManager: address(0), swapFeeManager: address(0), poolCreator: address(0) }),
            0.0075e18,
            address(hook),
            false,
            false,
            keccak256("pp4_15_b3_seed_witness")
        );
    }

    /// @notice B.3 / PP-D58 (iii) witness — a pool seeded AFTER the recorder is bound and the Router
    ///         seated, by a dust initialize through the Vault and then the seed through the trusted
    ///         Router, records the seeder's whole seed, and at rest its live supply exceeds the recorded
    ///         tally by exactly the dust initialize's BPT plus the Vault's 1e6 minimum.
    function test_seedRecordedThroughTheTrustedRouterAgreesWithSupplyAtRest() public {
        _seatRouter();
        address pool = _buildSeedWitnessPool();
        vm.prank(gov);
        distributor.setAuMTContractForPool(pool, address(hook));

        IERC20[] memory tokens = vault.getPoolTokens(pool);
        uint256[] memory dust = new uint256[](tokens.length);
        uint256[] memory seed = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            dust[i] = 1e12;
            seed[i] = 1_000e18;
        }
        uint256 dustBpt = _initializePool(pool, tokens, dust);
        assertEq(IERC20(pool).totalSupply(), dustBpt + 1e6, "initialize mints the dust BPT plus the 1e6 minimum");
        assertEq(distributor.poolTotalLP(pool), 0, "initialize reaches no recorder, the hook having no initialize callback");

        // PP-D58 (xv): a PROPORTIONAL add, as the script makes it — an unbalanced add from dust would
        // multiply the invariant past the weighted pool's 3x cap. One dust unit of slack stays under
        // the funded seed, which bounds maxAmountsIn.
        address seeder = makeAddr("b3Seeder");
        uint256 seedBpt = IERC20(pool).totalSupply() * (seed[0] / dust[0] - 2);
        _fundAndPermit(seeder, tokens, seed);
        vm.prank(seeder);
        Router(payable(router)).addLiquidityProportional(pool, seed, seedBpt, false, "");

        assertEq(IERC20(pool).balanceOf(seeder), seedBpt, "the Router mints the exact proportional BPT to the seeder");
        assertEq(distributor.userLP(pool, seeder), seedBpt, "the trusted add records the seeder's whole seed");
        assertEq(distributor.poolTotalLP(pool), seedBpt, "the seeder is the pool's whole recorded tally");
        assertEq(
            IERC20(pool).totalSupply() - distributor.poolTotalLP(pool),
            dustBpt + 1e6,
            "at rest supply exceeds the tally by exactly the dust BPT plus the minimum"
        );
        assertEq(IERC20(pool).balanceOf(address(0)), 1e6, "the Vault's minimum sits at address zero");
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
