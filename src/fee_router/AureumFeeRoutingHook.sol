// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AddLiquidityKind, AddLiquidityParams, AfterSwapParams, HookFlags, LiquidityManagement, SwapKind, TokenConfig, VaultSwapParams} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import {BaseHooks} from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";
import {VaultGuard} from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";

import {IAureumFeeRoutingHook} from "src/fee_router/IAureumFeeRoutingHook.sol";
import {IAureumProtocolFeeControllerHookExtension} from "src/fee_router/IAureumProtocolFeeControllerHookExtension.sol";

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
 *      Governance and Incendiary module addresses are unknown at
 *      construction time (Stage K and Stage L don't exist yet); set
 *      post-deploy via one-shot setters mirroring Stage C's
 *      AuMM.setMinter per C-D11 — two independent admin slots, each
 *      zeroed atomically with its module-set. Post-state invariant:
 *      governanceModule != 0 AND _governanceAdmin == 0 AND
 *      incendiaryModule != 0 AND _incendiaryAdmin == 0 — no owner,
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

    /// @dev One-shot setter authority for governanceModule. Set in the
    ///      constructor; zeroed atomically in setGovernanceModule. Part
    ///      of the two-flag lock per C-D11.
    address private _governanceAdmin;

    /// @dev One-shot setter authority for incendiaryModule. Same
    ///      two-flag lock shape per C-D11.
    address private _incendiaryAdmin;

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

    /// @notice Reverts the internal primitive when a non—ZCHF—family fee
    ///         token is supplied with no swap pool.
    error UnsupportedFeeToken(IERC20 feeToken);

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
    /// @param aumm_           AuMM ERC-20.
    /// @param feeController_  AureumProtocolFeeController — sanctioned
    ///                        caller for routeYieldFee.
    /// @param moduleAdmin_    One-shot setter authority for
    ///                        governanceModule and incendiaryModule.
    constructor(
        address vault_,
        address derBodensee_,
        IERC20 svZchf_,
        IERC20 aumm_,
        address feeController_,
        address moduleAdmin_
    ) VaultGuard(IVault(vault_)) {
        if (vault_ == address(0))           revert ZeroAddress();
        if (derBodensee_ == address(0))     revert ZeroAddress();
        if (address(svZchf_) == address(0)) revert ZeroAddress();
        if (address(aumm_) == address(0))   revert ZeroAddress();
        if (feeController_ == address(0))   revert ZeroAddress();
        if (moduleAdmin_ == address(0))     revert ZeroAddress();

        AUREUM_VAULT = vault_;
        DER_BODENSEE = derBodensee_;
        SV_ZCHF = svZchf_;
        AUMM = aumm_;
        FEE_CONTROLLER = feeController_;
        ZCHF = IERC20(IERC4626(address(svZchf_)).asset());

        _governanceAdmin = moduleAdmin_;
        _incendiaryAdmin = moduleAdmin_;
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

    // -------------------------------------------------------------------------
    // IHooks (BaseHooks)
    // -------------------------------------------------------------------------

    /// @inheritdoc BaseHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallAfterSwap = true;
        return hookFlags;
    }

    /// @inheritdoc BaseHooks
    function onRegister(
        address,
        address pool,
        TokenConfig[] memory tokenConfig,
        LiquidityManagement calldata
    ) public view override onlyVault returns (bool) {
        if (pool == DER_BODENSEE) return false;
        uint256 len = tokenConfig.length;
        for (uint256 i = 0; i < len; ++i) {
            if (address(tokenConfig[i].token) == DER_BODENSEE) return false;
        }
        return true;
    }
    /// @inheritdoc BaseHooks
    function onAfterSwap(
        AfterSwapParams calldata params
    ) public override onlyVault returns (bool, uint256) {
        if (params.router == address(this)) {
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
                address(this)
            );
            emit SwapFeeRouted(
                params.pool,
                address(tokens[i]),
                forwardedAmounts[i],
                bptMinted
            );
        }

        return (true, params.amountCalculatedRaw);
    }

    // -------------------------------------------------------------------------
    // Internal routing primitive
    // -------------------------------------------------------------------------

    /// @dev Shared internal primitive consumed by onAfterSwap and the
    ///      three IAureumFeeRoutingHook external entry points. Two-phase
    ///      per the Stage D plan D3.3:
    ///      Phase 1 — convert `feeToken` to svZCHF on this hook's balance.
    ///      If `amount == 0`, return `0` as `bptMinted`. If `feeToken` is svZCHF, no-op
    ///      (hook already holds `amount` svZCHF from the caller). If
    ///      `feeToken` is ZCHF, `forceApprove` then ERC-4626 `deposit`
    ///      into this hook. Otherwise require `swapPool != 0` and
    ///      nested-swap to svZCHF via `_swapExactInFeeTokenToSvZchfViaVault`;
    ///      revert `UnsupportedFeeToken` if `swapPool == 0` for a
    ///      non—ZCHF—family token.
    ///      Phase 2 — one-sided add the hook's entire svZCHF balance
    ///      into der-Bodensee via `_addLiquidityOneSidedToBodenseeViaVault`,
    ///      minting BPT to `bptRecipient`; returns `bptMinted` from phase 2.
    ///      Balance-sweep is intentional: any svZCHF held by this hook
    ///      is protocol-owned and Bodensee-bound, including dust from
    ///      prior partial fills or donations (per D3.3.4 Q1 / Option X).
    function _swapFeeAndDeposit(
        IERC20 feeToken,
        uint256 amount,
        address swapPool,
        address bptRecipient
    ) private returns (uint256 bptMinted) {
        if (amount == 0) return 0;

        if (address(feeToken) == address(SV_ZCHF)) {
            // No-op: hook already holds `amount` svZCHF from the caller.
        } else if (address(feeToken) == address(ZCHF)) {
            IERC20(address(ZCHF)).forceApprove(address(SV_ZCHF), amount);
            IERC4626(address(SV_ZCHF)).deposit(amount, address(this));
        } else {
            if (swapPool == address(0)) revert UnsupportedFeeToken(feeToken);
            _swapExactInFeeTokenToSvZchfViaVault(feeToken, amount, swapPool);
        }

        bptMinted = _addLiquidityOneSidedToBodenseeViaVault(
            SV_ZCHF.balanceOf(address(this)),
            bptRecipient
        );
    }

    /// @dev Nested swap from this hook: inside `IVault.swap`, `msg.sender`
    ///      is this contract, so the hook owns the transient-accounting deltas
    ///      and must clear them before the outer `unlock` closes. Order:
    ///      `swap`, then transfer `tokenIn` to the Vault and `settle`, then
    ///      `sendTo` svZCHF to this hook—mirroring `RouterCommon._takeTokenIn`
    ///      and `_sendTokenOut` around `_vault.swap`. `limitRaw == 0` accepts
    ///      any `amountOut` for this protocol-internal leg (same trade-off
    ///      class as `minBptAmountOut == 0` on the phase-2 one-sided add
    ///      into der-Bodensee per the Stage D plan). Recursion: the
    ///      nested `swap` invokes `onAfterSwap` again with
    ///      `params.router == address(this)`; D10 early-return applies.
    function _swapExactInFeeTokenToSvZchfViaVault(
        IERC20 feeToken,
        uint256 amount,
        address swapPool
    ) private {
        (, uint256 amountIn, uint256 amountOut) = _vault.swap(
            VaultSwapParams({
                kind: SwapKind.EXACT_IN,
                pool: swapPool,
                tokenIn: feeToken,
                tokenOut: SV_ZCHF,
                amountGivenRaw: amount,
                limitRaw: 0,
                userData: bytes("")
            })
        );
        feeToken.safeTransfer(address(_vault), amountIn);
        _vault.settle(feeToken, amountIn);
        _vault.sendTo(SV_ZCHF, address(this), amountOut);
    }

    /// @dev Nested one-sided add from this hook: inside `IVault.addLiquidity`,
    ///      `msg.sender` is this contract, so the hook owns the transient
    ///      deltas and must clear them before the outer `unlock` closes.
    ///      Order: `addLiquidity`, then transfer SV_ZCHF to the Vault and
    ///      `settle`. BPT is minted to `to` via the `AddLiquidityParams.to`
    ///      field, so no `sendTo` is needed to realise the credit leg.
    ///      Returns `bptAmountOut` from the Vault.
    ///      `minBptAmountOut == 0` accepts any `bptAmountOut` for this
    ///      protocol-internal leg (same trade-off class as `limitRaw == 0`
    ///      in `_swapExactInFeeTokenToSvZchfViaVault`; MEV/sandwich risk
    ///      internalised, tracked as a Stage Q audit surface per
    ///      `STAGE_D_PLAN.md:L703`). `getPoolTokenCountAndIndexOfToken`
    ///      reverts natively if `DER_BODENSEE` does not contain SV_ZCHF
    ///      — no custom error path. Debits are settled using the returned
    ///      `amountsIn[svZchfIndex]` (actual consumed), not the caller-
    ///      supplied `svZchfAmount`, per defensive-coding convention.
    ///      Precedent for nested-Vault-add-from-hook:
    ///      `lib/balancer-v3-monorepo/pkg/pool-hooks/contracts/ExitFeeHookExample.sol:160`
    ///      (different kind — DONATION — and different callback —
    ///      `onAfterRemoveLiquidity` — but same structural property:
    ///      nested Vault call from a hook already inside an open unlock,
    ///      hook as delta-owner). Router-vs-Vault mechanism drift resolution
    ///      recorded at D20 in `docs/STAGE_D_NOTES.md`.
    function _addLiquidityOneSidedToBodenseeViaVault(
        uint256 svZchfAmount,
        address to
    ) private returns (uint256 bptAmountOut) {
        if (svZchfAmount == 0) return 0;
        (uint256 tokenCount, uint256 svZchfIndex) =
            _vault.getPoolTokenCountAndIndexOfToken(DER_BODENSEE, SV_ZCHF);

        uint256[] memory maxAmountsIn = new uint256[](tokenCount);
        maxAmountsIn[svZchfIndex] = svZchfAmount;

        (uint256[] memory amountsIn, uint256 bptOut, ) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: DER_BODENSEE,
                to: to,
                maxAmountsIn: maxAmountsIn,
                minBptAmountOut: 0,
                kind: AddLiquidityKind.UNBALANCED,
                userData: bytes("")
            })
        );
        bptAmountOut = bptOut;

        SV_ZCHF.safeTransfer(address(_vault), amountsIn[svZchfIndex]);
        _vault.settle(SV_ZCHF, amountsIn[svZchfIndex]);
    }

    // -------------------------------------------------------------------------
    // IAureumFeeRoutingHook — routing primitives
    // -------------------------------------------------------------------------

    /// @inheritdoc IAureumFeeRoutingHook
    function routeYieldFee(
        address pool,
        IERC20 feeToken,
        uint256 feeAmount
    ) external override returns (uint256 bptMinted) {
        if (msg.sender != FEE_CONTROLLER) revert UnauthorizedCaller(msg.sender);
        if (pool == address(0)) revert ZeroAddress();
        if (pool == DER_BODENSEE) revert InvalidPool(pool);
        if (feeAmount == 0) revert ZeroAmount();

        feeToken.safeTransferFrom(msg.sender, address(this), feeAmount);
        bytes memory result = _vault.unlock(
            abi.encodeCall(
                this._routeYieldFeeUnlocked,
                (msg.sender, pool, feeToken, feeAmount)
            )
        );
        bptMinted = abi.decode(result, (uint256));
        emit YieldFeeRouted(pool, address(feeToken), feeAmount, bptMinted);
    }

    /// @notice Unlock callback for routeYieldFee. onlyVault; reached
    ///         exclusively via IVault.unlock from routeYieldFee.
    function _routeYieldFeeUnlocked(
        address caller,
        address pool,
        IERC20 feeToken,
        uint256 feeAmount
    ) external onlyVault returns (uint256 bptMinted) {
        bptMinted = _swapFeeAndDeposit(
            feeToken,
            feeAmount,
            pool,
            caller
        );
    }

    /// @inheritdoc IAureumFeeRoutingHook
    function routeGovernanceDeposit(
        IERC20 token,
        uint256 amount
    ) external override returns (uint256 bptMinted) {
        if (governanceModule == address(0)) revert ModuleNotSet();
        if (msg.sender != governanceModule) revert UnauthorizedCaller(msg.sender);
        if (amount == 0) revert ZeroAmount();

        token.safeTransferFrom(msg.sender, address(this), amount);
        bytes memory result = _vault.unlock(
            abi.encodeCall(
                this._routeGovernanceDepositUnlocked,
                (msg.sender, token, amount)
            )
        );
        bptMinted = abi.decode(result, (uint256));
        emit GovernanceDepositRouted(address(token), amount, bptMinted);
    }

    /// @notice Unlock callback for routeGovernanceDeposit. onlyVault;
    ///         reached exclusively via IVault.unlock from
    ///         routeGovernanceDeposit. `swapPool == address(0)` is the
    ///         fast-path-only contract per D17: valid iff `token` is
    ///         SV_ZCHF or ZCHF; any other token reverts
    ///         `UnsupportedFeeToken` inside `_swapFeeAndDeposit`.
    function _routeGovernanceDepositUnlocked(
        address caller,
        IERC20 token,
        uint256 amount
    ) external onlyVault returns (uint256 bptMinted) {
        bptMinted = _swapFeeAndDeposit(
            token,
            amount,
            address(0),
            caller
        );
    }

    /// @inheritdoc IAureumFeeRoutingHook
    function routeIncendiaryDeposit(
        IERC20 token,
        uint256 amount
    ) external override returns (uint256 bptMinted) {
        if (incendiaryModule == address(0)) revert ModuleNotSet();
        if (msg.sender != incendiaryModule) revert UnauthorizedCaller(msg.sender);
        if (amount == 0) revert ZeroAmount();

        token.safeTransferFrom(msg.sender, address(this), amount);
        bytes memory result = _vault.unlock(
            abi.encodeCall(
                this._routeIncendiaryDepositUnlocked,
                (msg.sender, token, amount)
            )
        );
        bptMinted = abi.decode(result, (uint256));
        emit IncendiaryDepositRouted(address(token), amount, bptMinted);
    }

    /// @notice Unlock callback for routeIncendiaryDeposit. onlyVault;
    ///         reached exclusively via IVault.unlock from
    ///         routeIncendiaryDeposit. `swapPool == address(0)` is the
    ///         fast-path-only contract per D17: valid iff `token` is
    ///         SV_ZCHF or ZCHF; any other token reverts
    ///         `UnsupportedFeeToken` inside `_swapFeeAndDeposit`.
    function _routeIncendiaryDepositUnlocked(
        address caller,
        IERC20 token,
        uint256 amount
    ) external onlyVault returns (uint256 bptMinted) {
        bptMinted = _swapFeeAndDeposit(
            token,
            amount,
            address(0),
            caller
        );
    }
}
