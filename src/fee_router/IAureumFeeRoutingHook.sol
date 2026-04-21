// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title  IAureumFeeRoutingHook
/// @notice Interface for the Aureum fee-routing hook — the single contract
///         that converts protocol fees and primitive deposits into svZCHF
///         and one-sided-adds them into der-Bodensee.
/// @dev    Thin interface — does NOT inherit Balancer V3's IHooks. The
///         implementation contract inherits BaseHooks separately and
///         exposes the Aureum-specific primitive entry points defined
///         here. External callers (fee-controller, governance, Incendiary)
///         integrate against this interface; the Vault integrates against
///         IHooks on the implementation directly.
///
///         Three-layer fee architecture (per FINDINGS OQ-1):
///           1. Swap fees — hook fires on onAfterSwap, converts the fee
///              token to svZCHF in-kind, then one-sided-adds into
///              der-Bodensee. No external entry point; emits
///              SwapFeeRouted.
///           2. Yield fees — AureumProtocolFeeController sweeps aggregate
///              yield fees (excluding der-Bodensee itself) and calls
///              routeYieldFee. Emits YieldFeeRouted.
///           3. Governance / Incendiary deposits — the emission
///              distributor and Incendiary contract call
///              routeGovernanceDeposit / routeIncendiaryDeposit directly.
///              Emits GovernanceDepositRouted / IncendiaryDepositRouted.
///
///         Each external primitive is gated to a single sanctioned caller
///         (per D16 / D-D2 Option A). Re-entrancy from the hook's own
///         Vault ops is prevented by the trusted-router early-return in
///         onAfterSwap (per D10 / D-D4 Option a), not by a revert.
interface IAureumFeeRoutingHook {
    // -----------------------------------------------------------------
    //                              Events
    // -----------------------------------------------------------------

    /// @notice Emitted when a swap fee is routed to der-Bodensee from
    ///         onAfterSwap. Fired once per swap that produces fee
    ///         revenue.
    /// @param  pool       The pool whose swap produced the fee.
    /// @param  feeToken   The token the fee was denominated in.
    /// @param  feeAmount  Fee amount in `feeToken` decimals.
    /// @param  bptMinted  BPT minted to the fee-controller from the
    ///                    one-sided addLiquidity into der-Bodensee.
    event SwapFeeRouted(
        address indexed pool,
        address indexed feeToken,
        uint256 feeAmount,
        uint256 bptMinted
    );

    /// @notice Emitted when an aggregate yield fee is routed to
    ///         der-Bodensee via routeYieldFee.
    /// @param  pool       The source pool.
    /// @param  feeToken   The yield-fee token swept.
    /// @param  feeAmount  Fee amount in `feeToken` decimals.
    /// @param  bptMinted  BPT minted to the caller.
    event YieldFeeRouted(
        address indexed pool,
        address indexed feeToken,
        uint256 feeAmount,
        uint256 bptMinted
    );

    /// @notice Emitted when a governance deposit is routed to
    ///         der-Bodensee via routeGovernanceDeposit.
    /// @param  token      Input token of the deposit.
    /// @param  amount     Amount deposited in `token` decimals.
    /// @param  bptMinted  BPT minted to the caller.
    event GovernanceDepositRouted(
        address indexed token,
        uint256 amount,
        uint256 bptMinted
    );

    /// @notice Emitted when an Incendiary deposit is routed to
    ///         der-Bodensee via routeIncendiaryDeposit.
    /// @param  token      Input token of the deposit.
    /// @param  amount     Amount deposited in `token` decimals.
    /// @param  bptMinted  BPT minted to the caller.
    event IncendiaryDepositRouted(
        address indexed token,
        uint256 amount,
        uint256 bptMinted
    );

    // -----------------------------------------------------------------
    //                              Errors
    // -----------------------------------------------------------------

    /// @notice Thrown when a gated entry point is called by an address
    ///         other than its sanctioned caller.
    error UnauthorizedCaller(address caller);

    /// @notice Thrown when a routing primitive gated to a one-shot
    ///         module (governance, Incendiary) is called before that
    ///         module has been set via its one-shot setter. Checked
    ///         before the caller-gate so that integration probes against
    ///         an unset hook get a clear `ModuleNotSet` signal rather
    ///         than a misleading `UnauthorizedCaller`.
    error ModuleNotSet();

    /// @notice Thrown when a constructor argument or input address is
    ///         the zero address.
    error ZeroAddress();

    /// @notice Thrown when an amount argument is zero.
    error ZeroAmount();

    /// @notice Thrown when a pool argument is not a Vault-registered
    ///         pool or is der-Bodensee itself (which is hook-exempt).
    error InvalidPool(address pool);

    /// @notice Thrown when the fee-token to svZCHF swap inside the
    ///         routing pipeline fails or returns zero output.
    error SvZCHFSwapFailed();

    /// @notice Thrown when the one-sided addLiquidity into der-Bodensee
    ///         fails or mints zero BPT.
    error BodenseeDepositFailed();

    // -----------------------------------------------------------------
    //                       External primitives
    // -----------------------------------------------------------------

    /// @notice Route an aggregate yield fee into der-Bodensee. Pulls
    ///         `feeAmount` of `feeToken` from the caller, swaps to
    ///         svZCHF, then one-sided-adds into der-Bodensee.
    /// @dev    Gated to the AureumProtocolFeeController. The caller MUST
    ///         hold `feeAmount` of `feeToken` and MUST have approved
    ///         this contract for at least that amount. `pool` MUST be
    ///         Vault-registered and MUST NOT be der-Bodensee itself.
    ///         Emits YieldFeeRouted.
    /// @param  pool       The source pool (used for event indexing).
    /// @param  feeToken   The yield-fee token to route.
    /// @param  feeAmount  Amount of `feeToken` to route.
    /// @return bptMinted  BPT minted to the caller.
    function routeYieldFee(
        address pool,
        IERC20 feeToken,
        uint256 feeAmount
    ) external returns (uint256 bptMinted);

    /// @notice Route a governance deposit into der-Bodensee. Pulls
    ///         `amount` of `token` from the caller, swaps to svZCHF,
    ///         then one-sided-adds into der-Bodensee.
    /// @dev    Gated to the Aureum governance contract. Caller MUST
    ///         hold and have approved `amount` of `token`. Emits
    ///         GovernanceDepositRouted.
    /// @param  token      Input token.
    /// @param  amount     Amount of `token` to route.
    /// @return bptMinted  BPT minted to the caller.
    function routeGovernanceDeposit(
        IERC20 token,
        uint256 amount
    ) external returns (uint256 bptMinted);

    /// @notice Route an Incendiary deposit into der-Bodensee. Pulls
    ///         `amount` of `token` from the caller, swaps to svZCHF,
    ///         then one-sided-adds into der-Bodensee.
    /// @dev    Gated to the Aureum Incendiary contract. Caller MUST
    ///         hold and have approved `amount` of `token`. Emits
    ///         IncendiaryDepositRouted.
    /// @param  token      Input token.
    /// @param  amount     Amount of `token` to route.
    /// @return bptMinted  BPT minted to the caller.
    function routeIncendiaryDeposit(
        IERC20 token,
        uint256 amount
    ) external returns (uint256 bptMinted);

    // -----------------------------------------------------------------
    //                           View getters
    // -----------------------------------------------------------------

    /// @notice The svZCHF token — the intermediate routing asset every
    ///         fee and primitive deposit is converted into before being
    ///         one-sided-added into der-Bodensee. Immutable on the
    ///         implementation.
    function SV_ZCHF() external view returns (IERC20);

    /// @notice der-Bodensee pool address — terminal sink for all routed
    ///         fees and deposits. Immutable on the implementation.
    function DER_BODENSEE() external view returns (address);

    /// @notice The Balancer V3 Vault address. Immutable on the
    ///         implementation.
    function AUREUM_VAULT() external view returns (address);

    /// @notice The AureumProtocolFeeController — sanctioned caller for
    ///         routeYieldFee. Immutable on the implementation.
    function FEE_CONTROLLER() external view returns (address);

    /// @notice The AuMM ERC-20 — referenced by the hook for pool
    ///         eligibility checks. Immutable on the implementation.
    function AUMM() external view returns (IERC20);
}
