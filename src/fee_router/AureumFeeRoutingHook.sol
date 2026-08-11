// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AddLiquidityKind, AddLiquidityParams, AfterSwapParams, HookFlags, LiquidityManagement, RemoveLiquidityKind, SwapKind, TokenConfig, VaultSwapParams} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import {BaseHooks} from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";
import {VaultGuard} from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";

import {IAureumFeeRoutingHook} from "src/fee_router/IAureumFeeRoutingHook.sol";
import {IAureumProtocolFeeControllerHookExtension} from "src/fee_router/IAureumProtocolFeeControllerHookExtension.sol";
import {IRouterSender} from "src/fee_router/IRouterSender.sol";
import {IEmissionDistributor} from "src/emission/IEmissionDistributor.sol";

/**
 * @title AureumFeeRoutingHook
 * @notice The Aureum fee-routing hook — converts swap fees, yield fees,
 *         and external primitive deposits into svZCHF and one-sided-adds
 *         them into der-Bodensee.
 * @dev Inherits Balancer V3 BaseHooks for the IHooks surface, and
 *      IAureumFeeRoutingHook for the Aureum-specific primitive entry
 *      points. The five typed immutable getters are inherited from
 *      IAureumFeeRoutingHook; ZCHF is cached at construction from
 *      SV_ZCHF.asset() as an implementation-surface convenience so the
 *      fee router can branch on feeToken == ZCHF vs SV_ZCHF without a
 *      runtime asset() call (per D3.1 design).
 *
 *      Recursion-guard at onAfterSwap via trusted-router early return
 *      per D10 / D-D4 option a; detail in D3.2.
 *
 *      Caller-gate for the three external primitive entry points
 *      (routeYieldFee, routeGovernanceDeposit, routeIncendiaryDeposit)
 *      per D16 / D-D2 option A; detail in D3.4.
 *
 *      Governance, Incendiary, and emission-recorder addresses are
 *      unknown at construction time (Stage K / Stage L modules and the
 *      Stage H EmissionDistributor are all deployed after this Stage D
 *      hook); set post-deploy via one-shot setters mirroring Stage C's
 *      AuMM.setMinter per C-D11 — three independent admin slots, each
 *      zeroed atomically with its module-set. Post-state invariant:
 *      governanceModule != 0 AND _governanceAdmin == 0 AND
 *      incendiaryModule != 0 AND _incendiaryAdmin == 0 AND
 *      emissionRecorder != 0 AND _emissionRecorderAdmin == 0 — no owner,
 *      no upgrade path.
 */
contract AureumFeeRoutingHook is BaseHooks, IAureumFeeRoutingHook, VaultGuard {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice The Balancer V3 Vault address. Set at construction; never changes.
    // Aureum-wide naming: immutable set at construction, UPPER_SNAKE_CASE.
    // slither-disable-next-line naming-convention
    address public immutable override AUREUM_VAULT;

    /// @notice der-Bodensee pool address — terminal sink for all routed fees
    ///         and deposits. Set at construction; never changes.
    // slither-disable-next-line naming-convention
    address public immutable override DER_BODENSEE;

    /// @notice svZCHF — the ERC-4626 vault-share token that is the
    ///         intermediate routing asset. Fee tokens are converted into
    ///         svZCHF before being one-sided-added into der-Bodensee.
    // slither-disable-next-line naming-convention
    IERC20 public immutable override SV_ZCHF;

    /// @notice AuMM ERC-20 — referenced for pool eligibility checks.
    // slither-disable-next-line naming-convention
    IERC20 public immutable override AUMM;

    /// @notice AureumProtocolFeeController — sanctioned caller for
    ///         routeYieldFee.
    // slither-disable-next-line naming-convention
    address public immutable override FEE_CONTROLLER;

    /// @notice ZCHF — the ERC-20 asset underlying svZCHF. Cached at
    ///         construction via IERC4626(SV_ZCHF).asset() so the fee
    ///         router can branch on feeToken == ZCHF vs SV_ZCHF without
    ///         a runtime asset() call. Not part of IAureumFeeRoutingHook
    ///         — implementation-surface only.
    /// @dev If svZCHF's ERC-4626 asset() were ever to change (not
    ///      expected for a production stable-vault), the cached ZCHF
    ///      reference would drift; this is caught at deploy time by
    ///      failing construction if asset() reverts, and would require
    ///      hook re-deployment if the upstream vault were swapped out.
    ///      One SLOAD per branch decision, zero runtime drift risk.
    // slither-disable-next-line naming-convention
    IERC20 public immutable ZCHF;

    /// @notice sUSDS — the secondary Bodensee deposit rail per P-D12 (2).
    ///         Impl-side only (not in IAureumFeeRoutingHook); set at construction.
    // slither-disable-next-line naming-convention
    IERC20 public immutable SUSDS;

    // -------------------------------------------------------------------------
    // Post-construction state
    // -------------------------------------------------------------------------

    /// @notice The Aureum governance module — sanctioned caller for
    ///         routeGovernanceDeposit. address(0) until set via
    ///         setGovernanceModule; set exactly once.
    /// @dev Stage K's governance module does not exist at hook deploy
    ///      time, so this cannot be a constructor immutable. One-shot
    ///      setter mirrors AuMM.setMinter per C-D11.
    address public governanceModule;

    /// @notice The Aureum Incendiary module — sanctioned caller for
    ///         routeIncendiaryDeposit. address(0) until set via
    ///         setIncendiaryModule; set exactly once.
    /// @dev Stage L's Incendiary module does not exist at hook deploy
    ///      time; same rationale as governanceModule.
    address public incendiaryModule;

    /// @notice The Aureum emission recorder — the EmissionDistributor the
    ///         hook calls recordDeposit / recordWithdrawal on from its
    ///         liquidity callbacks. address(0) until set via
    ///         setEmissionRecorder; set exactly once.
    /// @dev Stage H's EmissionDistributor is deployed after this hook
    ///      (Stage D < Stage H), so this cannot be a constructor immutable
    ///      (H13-class). One-shot setter mirrors setGovernanceModule per
    ///      I-D16.
    address public emissionRecorder;

    /// @dev One-shot setter authority for governanceModule. Set in the
    ///      constructor; zeroed atomically in setGovernanceModule. Part
    ///      of the two-flag lock per C-D11.
    address private _governanceAdmin;

    /// @dev One-shot setter authority for incendiaryModule. Same
    ///      two-flag lock shape per C-D11.
    address private _incendiaryAdmin;

    /// @dev One-shot setter authority for emissionRecorder. Set in the
    ///      constructor; zeroed atomically in setEmissionRecorder. Same
    ///      two-flag lock shape per I-D16.
    address private _emissionRecorderAdmin;

    /// @notice Governance-managed allowlist of routers whose `getSender()` the liquidity callbacks trust for recorder attribution (F-09). Empty by default — the recorder dispatch in onAfterAddLiquidity / onAfterRemoveLiquidity is skipped (no credit, no revert) for any non-allowlisted router, so an attacker acting as its own router cannot spoof LP identity into the emission / qualification clock. Populated by governance via `setTrustedRouter` (e.g. the Stage O Aureum Router). Declared last in storage so its slot follows the C-D11 / I-D16 admin slots (3—5), preserving their pinned layout (F-09 fix).
    mapping(address => bool) public trustedRouter;

    /// @notice per-pool Bodensee deposit rail per P-D12 (2), set once at onRegister — svZCHF if the pool holds it (preferred), else sUSDS if the pool holds it, else address(0) (skip in onAfterSwap, no revert); immutable pool token sets so the cache never staleness-drifts.
    mapping(address => address) public poolBodenseeDepositToken;

    // -------------------------------------------------------------------------
    // Impl-side errors
    // -------------------------------------------------------------------------

    /// @notice Reverts setGovernanceModule when msg.sender is not the
    ///         constructor-set module admin.
    error NotGovernanceAdmin();

    /// @notice Reverts setIncendiaryModule when msg.sender is not the
    ///         constructor-set module admin.
    error NotIncendiaryAdmin();

    /// @notice Reverts setGovernanceModule when the module has already
    ///         been set.
    error GovernanceModuleAlreadySet();

    /// @notice Reverts setIncendiaryModule when the module has already
    ///         been set.
    error IncendiaryModuleAlreadySet();

    /// @notice Reverts setEmissionRecorder when msg.sender is not the
    ///         constructor-set module admin.
    error NotEmissionRecorderAdmin();

    /// @notice Reverts setEmissionRecorder when the recorder has already
    ///         been set.
    error EmissionRecorderAlreadySet();

    /// @notice Reverts the internal primitive when a non—ZCHF—family fee
    ///         token is supplied with no swap pool.
    error UnsupportedFeeToken(IERC20 feeToken);

    /// @notice Reverts the one-sided der-Bodensee deposit when
    ///         `AddLiquidityKind.DONATION` returned a nonzero `bptOut`.
    ///         A donation must mint zero BPT per the Balancer V3 invariant.
    ///         Mirrors `BodenseeBootstrapChannel` L94 per PB-D68 (v).
    error BptMintedOnDonation(uint256 bptOut);

    /// @notice Reverts the one-sided der-Bodensee deposit when der
    ///         Bodensee's reserve for the deposit token did not rise at all.
    ///         Deliberately a strict rise rather than an exact delta per
    ///         PB-D68 (xvii): the Vault's DONATION branch round-trips raw
    ///         through scaled18, and rate-bearing rails accrue yield fees in
    ///         the same call, so no exact figure is predictable. Distinct
    ///         from `BodenseeBootstrapChannel` L97, which asserts exactness
    ///         and can, because AuMM is STANDARD at unit rate.
    error ReserveDidNotRise(uint256 preReserve, uint256 postReserve);

    // -------------------------------------------------------------------------
    // Impl-side events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the governance module is set (exactly once,
    ///         via the one-shot setter).
    /// @param module The governance module address.
    event GovernanceModuleSet(address indexed module);

    /// @notice Emitted when the Incendiary module is set (exactly once,
    ///         via the one-shot setter).
    /// @param module The Incendiary module address.
    event IncendiaryModuleSet(address indexed module);

    /// @notice Emitted when the emission recorder is set (exactly once,
    ///         via the one-shot setter).
    /// @param recorder The emission recorder (EmissionDistributor) address.
    event EmissionRecorderSet(address indexed recorder);

    /// @notice Emitted when governance allowlists or de-allowlists a router for recorder attribution (F-09).
    event TrustedRouterSet(address indexed router, bool trusted);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @notice Deploy the fee-routing hook with its immutable
    ///         dependencies and a one-shot module admin.
    /// @dev ZCHF is derived from svZchf_ via IERC4626.asset() — if
    ///      svZchf_ is not an ERC-4626 vault, construction reverts.
    ///      Governance and Incendiary module addresses are NOT ctor
    ///      args; they are set post-deploy via setGovernanceModule and
    ///      setIncendiaryModule. moduleAdmin_ is the EOA or multisig
    ///      authorised to call each setter exactly once.
    /// @param vault_          The Balancer V3 Vault.
    /// @param derBodensee_    der-Bodensee pool address.
    /// @param svZchf_         svZCHF (ERC-4626 vault share over ZCHF).
    /// @param susds_          sUSDS — secondary Bodensee deposit rail per P-D12 (2).
    /// @param aumm_           AuMM ERC-20.
    /// @param feeController_  AureumProtocolFeeController — sanctioned
    ///                        caller for routeYieldFee.
    /// @param moduleAdmin_    One-shot setter authority for
    ///                        governanceModule and incendiaryModule.
    constructor(
        address vault_,
        address derBodensee_,
        IERC20 svZchf_,
        IERC20 susds_,
        IERC20 aumm_,
        address feeController_,
        address moduleAdmin_
    ) VaultGuard(IVault(vault_)) {
        if (vault_ == address(0))           revert ZeroAddress();
        if (derBodensee_ == address(0))     revert ZeroAddress();
        if (address(svZchf_) == address(0)) revert ZeroAddress();
        if (address(susds_) == address(0)) revert ZeroAddress();
        if (address(aumm_) == address(0))   revert ZeroAddress();
        if (feeController_ == address(0))   revert ZeroAddress();
        if (moduleAdmin_ == address(0))     revert ZeroAddress();

        AUREUM_VAULT = vault_;
        DER_BODENSEE = derBodensee_;
        SV_ZCHF = svZchf_;
        SUSDS = susds_;
        AUMM = aumm_;
        FEE_CONTROLLER = feeController_;
        ZCHF = IERC20(IERC4626(address(svZchf_)).asset());

        _governanceAdmin = moduleAdmin_;
        _incendiaryAdmin = moduleAdmin_;
        _emissionRecorderAdmin = moduleAdmin_;
    }

    // -------------------------------------------------------------------------
    // One-shot module setters
    // -------------------------------------------------------------------------

    /// @notice Set the Aureum governance module exactly once. Callable
    ///         only by the constructor-set moduleAdmin.
    /// @dev Two-flag lock per C-D11: on success, governanceModule != 0
    ///      AND _governanceAdmin == 0. Either flag alone rejects
    ///      subsequent calls.
    /// @param module The governance module address. Must be non-zero.
    function setGovernanceModule(address module) external {
        if (msg.sender != _governanceAdmin) revert NotGovernanceAdmin();
        if (governanceModule != address(0)) revert GovernanceModuleAlreadySet();
        if (module == address(0))           revert ZeroAddress();

        governanceModule = module;
        _governanceAdmin = address(0);
        emit GovernanceModuleSet(module);
    }

    /// @notice Set the Aureum Incendiary module exactly once. Callable
    ///         only by the constructor-set moduleAdmin.
    /// @dev Two-flag lock per C-D11: on success, incendiaryModule != 0
    ///      AND _incendiaryAdmin == 0. Either flag alone rejects
    ///      subsequent calls.
    /// @param module The Incendiary module address. Must be non-zero.
    function setIncendiaryModule(address module) external {
        if (msg.sender != _incendiaryAdmin) revert NotIncendiaryAdmin();
        if (incendiaryModule != address(0)) revert IncendiaryModuleAlreadySet();
        if (module == address(0))           revert ZeroAddress();

        incendiaryModule = module;
        _incendiaryAdmin = address(0);
        emit IncendiaryModuleSet(module);
    }

    /// @notice Set the Aureum emission recorder exactly once. Callable
    ///         only by the constructor-set moduleAdmin.
    /// @dev Two-flag lock per I-D16: on success, emissionRecorder != 0
    ///      AND _emissionRecorderAdmin == 0. Either flag alone rejects
    ///      subsequent calls.
    /// @param recorder The emission recorder address. Must be non-zero.
    function setEmissionRecorder(address recorder) external {
        if (msg.sender != _emissionRecorderAdmin) revert NotEmissionRecorderAdmin();
        if (emissionRecorder != address(0))       revert EmissionRecorderAlreadySet();
        if (recorder == address(0))               revert ZeroAddress();

        emissionRecorder = recorder;
        _emissionRecorderAdmin = address(0);
        emit EmissionRecorderSet(recorder);
    }

    /// @notice Governance allowlist toggle for a router whose `getSender()` is trusted for recorder attribution (F-09).
    /// @dev Gated by `governanceModule` (the Stage K AureumGovernance authority) — reverts `UnauthorizedCaller` before governance is bound or from any other caller. Unlike the one-shot module setters this is a persistent, repeatable governance lever (routers added/removed over time); it sets no admin flag. The Stage O Aureum Router is allowlisted here when it ships; until then the allowlist is empty and the callback recorder dispatch is dormant (fail-closed).
    /// @param router  The router address to allow or disallow.
    /// @param trusted True to trust the router's getSender() for recorder credit; false to revoke.
    function setTrustedRouter(address router, bool trusted) external {
        if (msg.sender != governanceModule) revert UnauthorizedCaller(msg.sender);
        trustedRouter[router] = trusted;
        emit TrustedRouterSet(router, trusted);
    }

    // -------------------------------------------------------------------------
    // IHooks (BaseHooks)
    // -------------------------------------------------------------------------

    /// @inheritdoc BaseHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallAfterSwap = true;
        hookFlags.shouldCallAfterAddLiquidity = true;
        hookFlags.shouldCallAfterRemoveLiquidity = true;
        return hookFlags;
    }

    /// @inheritdoc BaseHooks
    function onRegister(
        address,
        address pool,
        TokenConfig[] memory tokenConfig,
        LiquidityManagement calldata
    ) public override onlyVault returns (bool) {
        if (pool == DER_BODENSEE) return false;
        uint256 len = tokenConfig.length;
        address depositToken = address(0);
        for (uint256 i = 0; i < len; ++i) {
            address token = address(tokenConfig[i].token);
            if (token == DER_BODENSEE) return false;
            if (token == address(SV_ZCHF)) {
                depositToken = address(SV_ZCHF);
            } else if (token == address(SUSDS) && depositToken == address(0)) {
                depositToken = address(SUSDS);
            }
        }
        poolBodenseeDepositToken[pool] = depositToken;
        return true;
    }
    /// @inheritdoc BaseHooks
    function onAfterSwap(
        AfterSwapParams calldata params
    ) public override onlyVault returns (bool, uint256) {
        if (params.router == address(this)) {
            return (true, params.amountCalculatedRaw);
        }

        // F-14 / P-D12 (2) — poolBodenseeDepositToken[params.pool] == address(0) skips collect/convert/route (its 50% protocol fee still accrues in the Vault, governance-withdrawable via AureumProtocolFeeController.withdrawProtocolFees) rather than reverting the user swap.
        address depositToken = poolBodenseeDepositToken[params.pool];
        if (depositToken == address(0)) {
            return (true, params.amountCalculatedRaw);
        }

        (IERC20[] memory tokens, uint256[] memory forwardedAmounts) =
            IAureumProtocolFeeControllerHookExtension(FEE_CONTROLLER)
                .collectSwapAggregateFeesForHook(params.pool);

        uint256 len = tokens.length;
        for (uint256 i = 0; i < len; ++i) {
            if (forwardedAmounts[i] == 0) continue;
            uint256 bptMinted = _swapFeeAndDeposit(
                tokens[i],
                forwardedAmounts[i],
                params.pool,
                IERC20(depositToken),
                0,
                0
            );
            // onAfterSwap is onlyVault under the Vault's open unlock; external calls are into the Vault itself (the protocol's reentrancy guard); CEI ordering preserved. See D8 NOTES F1.
            // slither-disable-next-line reentrancy-events
            emit SwapFeeRouted(
                params.pool,
                address(tokens[i]),
                forwardedAmounts[i],
                bptMinted
            );
        }

        return (true, params.amountCalculatedRaw);
    }

    /// @inheritdoc BaseHooks
    /// @dev I-D14 recorder dispatch — resolves the liquidity provider via
    ///      `IRouterSender(router).getSender()` (the address that initiated
    ///      the Router call) and forwards `bptAmountOut` to the
    ///      EmissionDistributor recorder clock. Recorder-unset guard per
    ///      I-D16: `emissionRecorder` is unbound through Stages D—H (bound at
    ///      I6/I7) yet `getHookFlags` (I4.1) calls this on every add, so an
    ///      unguarded dispatch into `address(0)` would revert all
    ///      add-liquidity pre-binding. No amount adjustment — `amountsInRaw`
    ///      passes through.
    function onAfterAddLiquidity(
        address router,
        address pool,
        AddLiquidityKind,
        uint256[] memory,
        uint256[] memory amountsInRaw,
        uint256 bptAmountOut,
        uint256[] memory,
        bytes memory
    ) public override onlyVault returns (bool, uint256[] memory) {
        address recorder = emissionRecorder;
        // F-09: credit the recorder only from a governance-allowlisted router; a non-allowlisted (e.g. self-)router is skipped (no credit, no revert) so getSender() cannot spoof LP identity.
        if (recorder != address(0) && trustedRouter[router]) {
            address lp = IRouterSender(router).getSender();
            IEmissionDistributor(recorder).recordDeposit(pool, lp, bptAmountOut);
        }
        return (true, amountsInRaw);
    }

    /// @inheritdoc BaseHooks
    /// @dev I-D14 recorder dispatch — symmetric to `onAfterAddLiquidity`:
    ///      resolves the liquidity provider via `IRouterSender(router).getSender()`
    ///      and forwards `bptAmountIn` to the EmissionDistributor recorder
    ///      clock as a withdrawal. Recorder-unset guard per I-D16 (see
    ///      `onAfterAddLiquidity`). No amount adjustment — `amountsOutRaw`
    ///      passes through.
    function onAfterRemoveLiquidity(
        address router,
        address pool,
        RemoveLiquidityKind,
        uint256 bptAmountIn,
        uint256[] memory,
        uint256[] memory amountsOutRaw,
        uint256[] memory,
        bytes memory
    ) public override onlyVault returns (bool, uint256[] memory) {
        address recorder = emissionRecorder;
        // F-09: credit the recorder only from a governance-allowlisted router; a non-allowlisted (e.g. self-)router is skipped (no credit, no revert) so getSender() cannot spoof LP identity.
        if (recorder != address(0) && trustedRouter[router]) {
            address lp = IRouterSender(router).getSender();
            IEmissionDistributor(recorder).recordWithdrawal(pool, lp, bptAmountIn);
        }
        return (true, amountsOutRaw);
    }

    // -------------------------------------------------------------------------
    // Internal routing primitive
    // -------------------------------------------------------------------------

    /// @dev Shared internal primitive consumed by onAfterSwap and the
    ///      three IAureumFeeRoutingHook external entry points. Two-phase
    ///      per the Stage D plan D3.3:
    ///      Phase 1 — convert `feeToken` to the deposit token on this hook's balance.
    ///      If `amount == 0`, return `0` as `bptMinted`. If `feeToken` is the deposit token, no-op
    ///      (hook already holds `amount` from the caller). If
    ///      `feeToken` is ZCHF and the deposit token is svZCHF, `forceApprove` then ERC-4626 `deposit`
    ///      into this hook. Otherwise require `swapPool != 0` and
    ///      nested-swap to the deposit token via `_swapExactInFeeTokenToDepositTokenViaVault`;
    ///      revert `UnsupportedFeeToken` if `swapPool == 0` for a
    ///      non—ZCHF—family token.
    ///      Phase 2 — one-sided DONATION of the hook's entire deposit-token
    ///      balance into der-Bodensee via
    ///      `_addLiquidityOneSidedToBodenseeViaVault`. No BPT is minted per
    ///      PB-D68 (v), so `bptMinted` returns zero on every route and is
    ///      retained for ABI stability per PB-D68 (vi).
    ///      Balance-sweep is intentional: any deposit token held by this hook
    ///      is protocol-owned and Bodensee-bound, including dust from
    ///      prior partial fills or donations (per D3.3.4 Q1 / Option X).
    ///      `minDepositTokenOut` bounds the phase-1 swap leg (EXACT_IN
    ///      minimum-out, enforced only when the swap leg runs; inert on the
    ///      ZCHF-to-svZCHF ERC-4626 fast path and the same-token no-op per
    ///      PB-D9 (iii)). `minBptAmountOut` is rejected nonzero by phase 2
    ///      via `BptFloorUnavailableOnDonation` per PB-D68 (xiv); under
    ///      DONATION no floor above zero is satisfiable at any value.
    function _swapFeeAndDeposit(
        IERC20 feeToken,
        uint256 amount,
        address swapPool,
        IERC20 depositToken,
        uint256 minDepositTokenOut,
        uint256 minBptAmountOut
    ) private returns (uint256 bptMinted) {
        if (amount == 0) return 0;

        if (address(feeToken) == address(depositToken)) {
            // No-op: hook already holds `amount` of the deposit token from the caller.
        } else if (address(depositToken) == address(SV_ZCHF) && address(feeToken) == address(ZCHF)) {
            IERC20(address(ZCHF)).forceApprove(address(SV_ZCHF), amount);
            // Balance-sweep: phase-2 reads depositToken.balanceOf(this) at L336; bounded fee-token loop in onAfterSwap (max 8 per BAL v3 pool). See D8 NOTES F2/F3.
            // slither-disable-next-line unused-return,calls-loop
            IERC4626(address(SV_ZCHF)).deposit(amount, address(this));
        } else {
            if (swapPool == address(0)) revert UnsupportedFeeToken(feeToken);
            _swapExactInFeeTokenToDepositTokenViaVault(feeToken, amount, swapPool, depositToken, minDepositTokenOut);
        }

        // Traced external call inside bounded fee-token loop in onAfterSwap (max 8 per BAL v3 pool). See D8 NOTES F4.
        // slither-disable-next-line calls-loop
        bptMinted = _addLiquidityOneSidedToBodenseeViaVault(
            depositToken,
            depositToken.balanceOf(address(this)),
            minBptAmountOut
        );
    }

    /// @dev Nested swap from this hook: inside `IVault.swap`, `msg.sender`
    ///      is this contract, so the hook owns the transient-accounting deltas
    ///      and must clear them before the outer `unlock` closes. Order:
    ///      `swap`, then transfer `tokenIn` to the Vault and `settle`, then
    ///      `sendTo` the deposit token to this hook—mirroring `RouterCommon._takeTokenIn`
    ///      and `_sendTokenOut` around `_vault.swap`. `limitRaw` is caller-
    ///      parameterized (`minDepositTokenOut`); `onAfterSwap` passes 0 per
    ///      the PB-D9 accepted per-swap dust path; the batched entries carry
    ///      caller-supplied bounds; the Vault reverts `SwapLimit` on violation.
    ///      Recursion: the nested `swap` invokes `onAfterSwap` again with
    ///      `params.router == address(this)`; D10 early-return applies.
    function _swapExactInFeeTokenToDepositTokenViaVault(
        IERC20 feeToken,
        uint256 amount,
        address swapPool,
        IERC20 depositToken,
        uint256 minDepositTokenOut
    ) private returns (uint256) {
        // Tuple discard: amountCalculated == amountOut for EXACT_IN, redundant; bounded fee-token loop. See D8 NOTES F5/F7.
        // slither-disable-next-line unused-return,calls-loop
        (, uint256 amountIn, uint256 amountOut) = _vault.swap(
            VaultSwapParams({
                kind: SwapKind.EXACT_IN,
                pool: swapPool,
                tokenIn: feeToken,
                tokenOut: depositToken,
                amountGivenRaw: amount,
                limitRaw: minDepositTokenOut,
                userData: bytes("")
            })
        );
        feeToken.safeTransfer(address(_vault), amountIn);
        // settle returns credit equal to amountIn by construction (Vault reservesOf accounting); bounded fee-token loop. See D8 NOTES F6/F8.
        // slither-disable-next-line unused-return,calls-loop
        _vault.settle(feeToken, amountIn);
        // Vault sendTo inside bounded fee-token loop in onAfterSwap (max 8 per BAL v3 pool). See D8 NOTES F9.
        // slither-disable-next-line calls-loop
        _vault.sendTo(depositToken, address(this), amountOut);
        return amountOut;
    }

    /// @dev Nested one-sided DONATION from this hook: inside
    ///      `IVault.addLiquidity`, `msg.sender` is this contract, so the hook
    ///      owns the transient deltas and must clear them before the outer
    ///      `unlock` closes. Order: `addLiquidity`, then transfer and
    ///      `settle`. PB-D68 (v) claimed the reverse was load-bearing on the
    ///      grounds that a donation mints no BPT to offset the debit; that is
    ///      withdrawn per PB-D68 (xix), since BPT is not a token credit in the
    ///      unlock ledger and both kinds take their debt through one path.
    ///      No BPT is minted at
    ///      all, so there is no recipient and no `sendTo` credit leg;
    ///      `AddLiquidityParams.to` is this contract only because the field
    ///      is non-optional. `bptAmountOut` is therefore always zero, kept
    ///      for ABI stability per PB-D68 (vi) and asserted via
    ///      `BptMintedOnDonation` rather than assumed. `minBptAmountOut` is
    ///      rejected nonzero via `BptFloorUnavailableOnDonation` per
    ///      PB-D68 (xiv): no floor above zero is satisfiable under DONATION,
    ///      and F-13's bounded-route protection rests on `minDepositTokenOut`
    ///      in phase 1. `getPoolTokenCountAndIndexOfToken` reverts natively
    ///      if `DER_BODENSEE` does not contain the deposit token — no custom
    ///      error path. Debits settle `amountsIn[depositIndex]`, the amount
    ///      the Vault actually charged, NOT the caller-supplied
    ///      `depositAmount`: the DONATION branch round-trips raw through
    ///      scaled18 and charges less, so settling the offered amount
    ///      over-credits the unlock and trips `BalanceNotSettled` at close
    ///      (PB-D68 (xix)). The remainder stays on the hook as dust and the
    ///      next route sweeps it. `ReserveDidNotRise` then proves the donation
    ///      landed rather than the route silently skipping, which is the one
    ///      thing supply-unchanged cannot distinguish. It asserts a strict
    ///      rise and NOT an exact delta, per PB-D68 (xvii). Mirrors
    ///      `BodenseeBootstrapChannel._distributeCallback` and
    ///      `SwapAndDepositToBodensee._swapAndDepositCallback`, the two
    ///      sibling subsystems that already donate and already reject a
    ///      nonzero `bptOut`. Balancer-side precedent for a nested add from a
    ///      hook already inside an open unlock:
    ///      `lib/balancer-v3-monorepo/pkg/pool-hooks/contracts/ExitFeeHookExample.sol:160`
    ///      (same DONATION kind, different callback). Router-vs-Vault
    ///      mechanism drift resolution recorded at D20 in
    ///      `docs/STAGE_D_NOTES.md`; the superseded one-sided-mint shape and
    ///      its G-D11 sanction are retired per PB-D68 (vii).
    function _addLiquidityOneSidedToBodenseeViaVault(
        IERC20 depositToken,
        uint256 depositAmount,
        uint256 minBptAmountOut
    ) private returns (uint256 bptAmountOut) {
        // depositAmount is a uint256 function argument (not a balance read); == 0 vs < 1 equivalent for uint; early-return guard, not auth or fund-routing. See D8 NOTES F10.
        // slither-disable-next-line incorrect-equality
        if (depositAmount == 0) return 0;
        // PB-D68 (xiv) — DONATION returns bptOut == 0 by construction, so any nonzero floor is unsatisfiable at any value. Guarded here, beside the invariant it protects, rather than at the three external entries. Ordered after the zero-amount short-circuit deliberately: a donation that is not happening stays a no-op.
        if (minBptAmountOut != 0) revert BptFloorUnavailableOnDonation(minBptAmountOut);
        // getPoolTokenCountAndIndexOfToken call inside bounded fee-token loop in onAfterSwap. See D8 NOTES F13.
        // slither-disable-next-line calls-loop
        (uint256 tokenCount, uint256 depositIndex) =
            _vault.getPoolTokenCountAndIndexOfToken(DER_BODENSEE, depositToken);

        uint256 preReserve = _currentBodenseeReserve(depositIndex);

        uint256[] memory maxAmountsIn = new uint256[](tokenCount);
        maxAmountsIn[depositIndex] = depositAmount;

        // Tuple discard: returnData unused (der-Bodensee does not chain hooks); bounded fee-token loop. See D8 NOTES F11/F14.
        // slither-disable-next-line unused-return,calls-loop
        (uint256[] memory amountsIn, uint256 bptOut, ) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: DER_BODENSEE,
                to: address(this),
                maxAmountsIn: maxAmountsIn,
                minBptAmountOut: 0,
                kind: AddLiquidityKind.DONATION,
                userData: bytes("")
            })
        );
        if (bptOut != 0) revert BptMintedOnDonation(bptOut);
        bptAmountOut = bptOut;

        uint256 postReserve = _currentBodenseeReserve(depositIndex);
        // PB-D68 (xvii) — strict rise, not an exact delta: the DONATION branch computes amountsInRaw by round-tripping raw through scaled18 rather than deep-copying maxAmountsIn the way UNBALANCED does, so the consumed amount is not predictable by the caller.
        if (postReserve <= preReserve) {
            revert ReserveDidNotRise(preReserve, postReserve);
        }

        // PB-D68 (xix) — settle what the Vault actually charged, not what was offered. amountsIn[depositIndex] is the round-tripped debit; settling depositAmount instead over-credits the unlock and fails BalanceNotSettled at close. The remainder stays on the hook as dust, and the next route sweeps it through depositToken.balanceOf(address(this)).
        depositToken.safeTransfer(address(_vault), amountsIn[depositIndex]);
        // settle returns credit equal to amountsIn[depositIndex] by construction; bounded fee-token loop. See D8 NOTES F12/F15.
        // slither-disable-next-line unused-return,calls-loop
        _vault.settle(depositToken, amountsIn[depositIndex]);
    }

    /// @dev Reads der Bodensee's raw reserve for token index `idx`, the
    ///      pre/post snapshot pair the `ReserveDidNotRise` assertion
    ///      compares per PB-D68 (v). Mirrors
    ///      `BodenseeBootstrapChannel._currentReserve`
    ///      (`src/emission/BodenseeBootstrapChannel.sol` L321) with a
    ///      `uint256` index, since `getPoolTokenCountAndIndexOfToken`
    ///      returns `uint256` where that channel carries a `uint8` field.
    function _currentBodenseeReserve(uint256 idx) private view returns (uint256) {
        // getPoolTokenInfo call inside bounded fee-token loop in onAfterSwap; twice per donation (pre and post). See D8 NOTES F13.
        // slither-disable-next-line calls-loop
        (, , uint256[] memory balancesRaw, ) = _vault.getPoolTokenInfo(DER_BODENSEE);
        return balancesRaw[idx];
    }

    // -------------------------------------------------------------------------
    // IAureumFeeRoutingHook — routing primitives
    // -------------------------------------------------------------------------

    /// @inheritdoc IAureumFeeRoutingHook
    function routeYieldFee(
        address pool,
        IERC20 feeToken,
        uint256 feeAmount,
        uint256 minDepositTokenOut,
        uint256 minBptAmountOut
    ) external override returns (uint256 bptMinted) {
        if (msg.sender != FEE_CONTROLLER) revert UnauthorizedCaller(msg.sender);
        if (pool == address(0)) revert ZeroAddress();
        if (pool == DER_BODENSEE) revert InvalidPool(pool);
        if (feeAmount == 0) revert ZeroAmount();

        feeToken.safeTransferFrom(msg.sender, address(this), feeAmount);
        bytes memory result = _vault.unlock(
            abi.encodeCall(
                this._routeYieldFeeUnlocked,
                (pool, feeToken, feeAmount, minDepositTokenOut, minBptAmountOut)
            )
        );
        bptMinted = abi.decode(result, (uint256));
        // Event reports bptMinted decoded from _vault.unlock callback; emission must follow unlock by causality; _vault.unlock is the Vault's reentrancy guard. See D8 NOTES F16.
        // slither-disable-next-line reentrancy-events
        emit YieldFeeRouted(pool, address(feeToken), feeAmount, bptMinted);
    }

    /// @notice Unlock callback for routeYieldFee. onlyVault; reached
    ///         exclusively via IVault.unlock from routeYieldFee.
    function _routeYieldFeeUnlocked(
        address pool,
        IERC20 feeToken,
        uint256 feeAmount,
        uint256 minDepositTokenOut,
        uint256 minBptAmountOut
    ) external onlyVault returns (uint256 bptMinted) {
        bptMinted = _swapFeeAndDeposit(
            feeToken,
            feeAmount,
            pool,
            IERC20(poolBodenseeDepositToken[pool]),
            minDepositTokenOut,
            minBptAmountOut
        );
    }

    /// @inheritdoc IAureumFeeRoutingHook
    function routeGovernanceDeposit(
        IERC20 token,
        uint256 amount,
        uint256 minDepositTokenOut,
        uint256 minBptAmountOut
    ) external override returns (uint256 bptMinted) {
        if (governanceModule == address(0)) revert ModuleNotSet();
        if (msg.sender != governanceModule) revert UnauthorizedCaller(msg.sender);
        if (amount == 0) revert ZeroAmount();

        token.safeTransferFrom(msg.sender, address(this), amount);
        bytes memory result = _vault.unlock(
            abi.encodeCall(
                this._routeGovernanceDepositUnlocked,
                (token, amount, minDepositTokenOut, minBptAmountOut)
            )
        );
        bptMinted = abi.decode(result, (uint256));
        // Event reports bptMinted decoded from _vault.unlock callback; emission must follow unlock by causality; _vault.unlock is the Vault's reentrancy guard. See D8 NOTES F17.
        // slither-disable-next-line reentrancy-events
        emit GovernanceDepositRouted(address(token), amount, bptMinted);
    }

    /// @notice Unlock callback for routeGovernanceDeposit. onlyVault;
    ///         reached exclusively via IVault.unlock from
    ///         routeGovernanceDeposit. `swapPool == address(0)` is the
    ///         fast-path-only contract per D17: valid iff `token` is
    ///         SV_ZCHF or ZCHF; any other token reverts
    ///         `UnsupportedFeeToken` inside `_swapFeeAndDeposit`.
    function _routeGovernanceDepositUnlocked(
        IERC20 token,
        uint256 amount,
        uint256 minDepositTokenOut,
        uint256 minBptAmountOut
    ) external onlyVault returns (uint256 bptMinted) {
        bptMinted = _swapFeeAndDeposit(
            token,
            amount,
            address(0),
            SV_ZCHF,
            minDepositTokenOut,
            minBptAmountOut
        );
    }

    /// @inheritdoc IAureumFeeRoutingHook
    function routeIncendiaryDeposit(
        IERC20 token,
        uint256 amount,
        uint256 minDepositTokenOut,
        uint256 minBptAmountOut
    ) external override returns (uint256 bptMinted) {
        if (incendiaryModule == address(0)) revert ModuleNotSet();
        if (msg.sender != incendiaryModule) revert UnauthorizedCaller(msg.sender);
        if (amount == 0) revert ZeroAmount();

        token.safeTransferFrom(msg.sender, address(this), amount);
        bytes memory result = _vault.unlock(
            abi.encodeCall(
                this._routeIncendiaryDepositUnlocked,
                (token, amount, minDepositTokenOut, minBptAmountOut)
            )
        );
        bptMinted = abi.decode(result, (uint256));
        // Event reports bptMinted decoded from _vault.unlock callback; emission must follow unlock by causality; _vault.unlock is the Vault's reentrancy guard. See D8 NOTES F18.
        // slither-disable-next-line reentrancy-events
        emit IncendiaryDepositRouted(address(token), amount, bptMinted);
    }

    /// @notice Unlock callback for routeIncendiaryDeposit. onlyVault;
    ///         reached exclusively via IVault.unlock from
    ///         routeIncendiaryDeposit. `swapPool == address(0)` is the
    ///         fast-path-only contract per D17: valid iff `token` is
    ///         SV_ZCHF or ZCHF; any other token reverts
    ///         `UnsupportedFeeToken` inside `_swapFeeAndDeposit`.
    function _routeIncendiaryDepositUnlocked(
        IERC20 token,
        uint256 amount,
        uint256 minDepositTokenOut,
        uint256 minBptAmountOut
    ) external onlyVault returns (uint256 bptMinted) {
        bptMinted = _swapFeeAndDeposit(
            token,
            amount,
            address(0),
            SV_ZCHF,
            minDepositTokenOut,
            minBptAmountOut
        );
    }

    /// @inheritdoc IAureumFeeRoutingHook
    function recoverStrandedFees(
        IERC20 feeToken,
        IERC20 depositToken,
        address[] calldata swapPools,
        IERC20[] calldata hopTokenOuts,
        uint256[] calldata minHopOuts
    ) external override {
        if (governanceModule == address(0)) revert ModuleNotSet();
        if (msg.sender != governanceModule) revert UnauthorizedCaller(msg.sender);
        if (address(depositToken) != address(SV_ZCHF) && address(depositToken) != address(SUSDS)) {
            revert InvalidDepositToken(address(depositToken));
        }

        uint256 hops = swapPools.length;
        if (hops == 0) revert EmptySwapPath();
        if (hopTokenOuts.length != hops || minHopOuts.length != hops) {
            revert SwapPathLengthMismatch(hops, hopTokenOuts.length, minHopOuts.length);
        }
        if (address(hopTokenOuts[hops - 1]) != address(depositToken)) {
            revert TerminalTokenMismatch(address(depositToken), address(hopTokenOuts[hops - 1]));
        }

        uint256 amountIn = feeToken.balanceOf(address(this));
        if (amountIn == 0) revert ZeroAmount();

        // Return discarded: the callback returns nothing, the recovery's effect being the donation itself. See PB-D66 (xiii).
        // slither-disable-next-line unused-return
        _vault.unlock(
            abi.encodeCall(
                this._recoverStrandedFeesUnlocked,
                (feeToken, depositToken, swapPools, hopTokenOuts, minHopOuts, amountIn)
            )
        );
        // Emission follows unlock by causality; _vault.unlock is the Vault's reentrancy guard. Mirrors the route* entries. See D8 NOTES F17.
        // slither-disable-next-line reentrancy-events
        emit StrandedFeesRecovered(address(feeToken), address(depositToken), amountIn, hops);
    }

    /// @notice Unlock callback for recoverStrandedFees. onlyVault; reached
    ///         exclusively via IVault.unlock from recoverStrandedFees, whose
    ///         four route invariants are validated before the unlock opens.
    /// @dev Walks the hops in order. Each swap settles its own tokenIn and
    ///      sendTo-s its output to this hook, so hop i+1 spends exactly what
    ///      hop i produced without re-reading balances — the return value
    ///      PB3.10b2a added for this purpose. The terminal add sweeps
    ///      `depositToken.balanceOf(address(this))` rather than the last
    ///      hop's output, matching `_swapFeeAndDeposit` and collecting any
    ///      dust earlier routes left; its floor is 0 because DONATION admits
    ///      no other value per PB-D68 (xiv).
    function _recoverStrandedFeesUnlocked(
        IERC20 feeToken,
        IERC20 depositToken,
        address[] calldata swapPools,
        IERC20[] calldata hopTokenOuts,
        uint256[] calldata minHopOuts,
        uint256 amountIn
    ) external onlyVault {
        IERC20 tokenIn = feeToken;
        uint256 hopAmount = amountIn;
        uint256 hops = swapPools.length;
        for (uint256 i = 0; i < hops; ++i) {
            hopAmount = _swapExactInFeeTokenToDepositTokenViaVault(
                tokenIn,
                hopAmount,
                swapPools[i],
                hopTokenOuts[i],
                minHopOuts[i]
            );
            tokenIn = hopTokenOuts[i];
        }
        _addLiquidityOneSidedToBodenseeViaVault(depositToken, depositToken.balanceOf(address(this)), 0);
    }
}
