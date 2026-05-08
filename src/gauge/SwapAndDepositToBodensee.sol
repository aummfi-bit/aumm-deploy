// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {TransientStorageHelpers} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

/**
 * @title SwapAndDepositToBodensee
 * @notice Anti-spam fee helper — single-call svZCHF or sUSDS DONATION into der-Bodensee,
 *         gated by `vaultClassRegistry` and `gaugeRegistry` callers (set post-deploy via
 *         one-shot setters at G1.5). Constructor is the G1.4 minimal form (G1.5 refactors it).
 * @dev Entry point and `IVault.unlock` callback land at G1.6. Full behavioural spec: G-D12 (full spec)
 *      in `docs/STAGE_G_NOTES.md`; transient-storage pattern: G-D14 in `docs/STAGE_G_NOTES.md`.
 */
contract SwapAndDepositToBodensee {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice Balancer V3 Vault — wired at construction; never changes.
    IVault internal immutable _vault;

    /// @notice der-Bodensee pool address — donation sink; wired at construction.
    address internal immutable _bodensee;

    /// @notice svZCHF — Bodensee pay-token candidate (fee path).
    IERC20 internal immutable _svZchf;

    /// @notice sUSDS — Bodensee pay-token candidate (fee path).
    IERC20 internal immutable _sUsds;

    /// @notice Cached Bodensee token-index for `_svZchf` (G1.5 derives via `getPoolTokens`).
    uint8 internal immutable _svZchfIndex;

    /// @notice Cached Bodensee token-index for `_sUsds` (G1.5 derives via `getPoolTokens`).
    uint8 internal immutable _sUsdsIndex;

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    /// @notice Burnable; cleared atomically at the second one-shot setter call per G-D12 (the burn behavior lands at G1.5; the slot exists at G1.4).
    address public moduleAdmin;

    /// @notice Vault-class registry — set post-deploy via one-shot setter (G1.5); zero before set ⇒ corresponding caller path unreachable per partial-activation invariant.
    address public vaultClassRegistry;

    /// @notice Gauge registry — set post-deploy via one-shot setter (G1.5); zero before set ⇒ corresponding caller path unreachable per partial-activation invariant.
    address public gaugeRegistry;

    // -------------------------------------------------------------------------
    // Transient slot constants
    // -------------------------------------------------------------------------

    /// @dev EIP-1153 transient slots; Balancer V3 audit-precedent pattern (per G-D14 Toolchain provenance); `tload()` / `tstore()` calls land at G1.6; solc 0.8.26 lacks the `transient` state-var keyword.
    bytes32 internal immutable _EXECUTING_SLOT = TransientStorageHelpers.calculateSlot("aureum.swapAndDepositToBodensee", "executing");
    bytes32 internal immutable _PENDING_PAY_TOKEN_SLOT = TransientStorageHelpers.calculateSlot("aureum.swapAndDepositToBodensee", "pendingPayToken");
    bytes32 internal immutable _PENDING_AMOUNT_SLOT = TransientStorageHelpers.calculateSlot("aureum.swapAndDepositToBodensee", "pendingAmount");
    bytes32 internal immutable _ORIGINAL_CALLER_SLOT = TransientStorageHelpers.calculateSlot("aureum.swapAndDepositToBodensee", "originalCaller");

    // -------------------------------------------------------------------------
    // Fee constants
    // -------------------------------------------------------------------------

    /// @notice Anti-spam fee for svZCHF DONATION (per G-D9 / G-D12 asymmetric fee lock).
    uint256 internal constant FEE_SVZCHF = 100e18;

    /// @notice Anti-spam fee for sUSDS DONATION (per G-D9 / G-D12 asymmetric fee lock).
    uint256 internal constant FEE_SUSDS = 125e18;

    // -------------------------------------------------------------------------
    // Custom errors
    // -------------------------------------------------------------------------

    /// @notice Outer entry caller-gate miss.
    error OnlyAuthorizedCaller(address caller);

    /// @notice Callback entry sender-strict miss.
    error OnlyVault(address caller);

    /// @notice One-shot setter caller-gate miss.
    error OnlyModuleAdmin(address caller);

    /// @notice Second call to `setVaultClassRegistry` or `setGaugeRegistry`.
    error SetterAlreadyCalled();

    /// @notice Constructor input or setter arg is `address(0)`.
    error ZeroAddress();

    /// @notice Pay-token allowlist miss.
    error InvalidPayToken(IERC20 payToken);

    /// @notice `swapAndDeposit(_, 0)`.
    error ZeroAmount();

    /// @notice Strict-equality fee miss.
    error IncorrectAmount(uint256 provided, uint256 required);

    /// @notice Defensive — V3 spec guarantees zero.
    error BptMintedOnDonation(uint256 bptOut);

    /// @notice `postReserve != preReserve + amount`.
    error ReserveDeltaMismatch(uint256 expected, uint256 actual);

    /// @notice helper balance != 0 after callback (resolves the `HelperBalanceNonZero(...)` ellipsis above).
    error HelperBalanceNonZero(uint256 residual);

    /// @notice Nested re-entry attempt.
    error ReentrancyGuard();

    /// @notice Constructor-time `getPoolTokens` miss.
    error TokenNotInPool(IERC20 token);

    /// @notice Callback args drift from cached payload.
    error CallbackPayloadMismatch();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /**
     * @notice Emitted as the last step of `_swapAndDepositCallback` per G-D12 — after donation settlement succeeds.
     * @dev `originalCaller` is the cached outer caller — never the Vault.
     */
    event FeeRoutedToBodensee(address indexed originalCaller, IERC20 indexed payToken, uint256 amount);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Minimal G1.4 form — G1.5 refactors to drop the two `Index` params and derive indices via `_vault.getPoolTokens(_bodensee)`; G1.5 also adds `ZeroAddress` and `TokenNotInPool` guards. G1.4 lands the type surface and storage layout; runtime behaviour lands at G1.5 / G1.6.
     */
    constructor(
        IVault vault_,
        address bodensee_,
        IERC20 svZchf_,
        IERC20 sUsds_,
        address moduleAdmin_,
        uint8 svZchfIndex_,
        uint8 sUsdsIndex_
    ) {
        _vault = vault_;
        _bodensee = bodensee_;
        _svZchf = svZchf_;
        _sUsds = sUsds_;
        _svZchfIndex = svZchfIndex_;
        _sUsdsIndex = sUsdsIndex_;
        moduleAdmin = moduleAdmin_;
    }
}
