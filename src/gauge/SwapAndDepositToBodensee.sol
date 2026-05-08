// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {AddLiquidityKind, AddLiquidityParams} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {TransientStorageHelpers} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";
import {StorageSlotExtension} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol";

/**
 * @title SwapAndDepositToBodensee
 * @notice Anti-spam fee helper — single-call svZCHF or sUSDS DONATION into der-Bodensee,
 * @notice gated by `vaultClassRegistry` and `gaugeRegistry` callers (set post-deploy via
 * @notice one-shot setters with atomic `moduleAdmin` burn at the second-set call).
 * @dev Entry point and `IVault.unlock` callback land at G1.6. Full behavioural spec: G-D12 (full spec)
 *      in `docs/STAGE_G_NOTES.md` ; transient-storage pattern: G-D14 in `docs/STAGE_G_NOTES.md` .
 */
contract SwapAndDepositToBodensee {
    using SafeERC20 for IERC20;
    using StorageSlotExtension for *;

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

    /// @notice Cached Bodensee token-index for `_svZchf` — derived at construction via `getPoolTokens`.
    uint8 internal immutable _svZchfIndex;

    /// @notice Cached Bodensee token-index for `_sUsds` — derived at construction via `getPoolTokens`.
    uint8 internal immutable _sUsdsIndex;

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    /// @notice Burnable admin slot; cleared atomically at the second one-shot setter call per G-D12.
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

    /// @notice Emitted by `setVaultClassRegistry` after the slot is written and any atomic admin-burn (per G-D12 event surface).
    event VaultClassRegistrySet(address indexed registry);

    /// @notice Emitted by `setGaugeRegistry` after the slot is written and any atomic admin-burn (per G-D12 event surface).
    event GaugeRegistrySet(address indexed registry);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    /// @notice Outer entry caller-gate — partial-activation correctness per G-D12.
    modifier onlyAuthorizedCaller() {
        if (msg.sender != vaultClassRegistry && msg.sender != gaugeRegistry) {
            revert OnlyAuthorizedCaller(msg.sender);
        }
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Derives Bodensee pay-token indices via `IVault.getPoolTokens` at construction per G-D12 token-index resolution lock.
     */
    constructor(
        IVault vault_,
        address bodensee_,
        IERC20 svZchf_,
        IERC20 sUsds_,
        address moduleAdmin_
    ) {
        if (address(vault_) == address(0)) revert ZeroAddress();
        if (bodensee_ == address(0)) revert ZeroAddress();
        if (address(svZchf_) == address(0)) revert ZeroAddress();
        if (address(sUsds_) == address(0)) revert ZeroAddress();
        if (moduleAdmin_ == address(0)) revert ZeroAddress();

        _vault = vault_;
        _bodensee = bodensee_;
        _svZchf = svZchf_;
        _sUsds = sUsds_;
        moduleAdmin = moduleAdmin_;

        IERC20[] memory tokens = vault_.getPoolTokens(bodensee_);
        uint256 len = tokens.length;
        uint8 svZchfIndex_ = type(uint8).max;
        uint8 sUsdsIndex_ = type(uint8).max;
        for (uint256 i = 0; i < len; ++i) {
            if (address(tokens[i]) == address(svZchf_)) {
                svZchfIndex_ = uint8(i);
            }
            if (address(tokens[i]) == address(sUsds_)) {
                sUsdsIndex_ = uint8(i);
            }
        }
        if (svZchfIndex_ == type(uint8).max) revert TokenNotInPool(svZchf_);
        if (sUsdsIndex_ == type(uint8).max) revert TokenNotInPool(sUsds_);

        _svZchfIndex = svZchfIndex_;
        _sUsdsIndex = sUsdsIndex_;
    }

    // -------------------------------------------------------------------------
    // One-shot caller-gate setters
    // -------------------------------------------------------------------------

    /**
     * @notice One-shot `vaultClassRegistry` wiring and optional atomic `moduleAdmin` burn — G-D12.
     */
    function setVaultClassRegistry(address registry_) external {
        if (msg.sender != moduleAdmin) revert OnlyModuleAdmin(msg.sender);
        if (registry_ == address(0)) revert ZeroAddress();
        if (vaultClassRegistry != address(0)) revert SetterAlreadyCalled();
        vaultClassRegistry = registry_;
        if (gaugeRegistry != address(0)) {
            moduleAdmin = address(0);
        }
        emit VaultClassRegistrySet(registry_);
    }

    /**
     * @notice One-shot `gaugeRegistry` wiring and optional atomic `moduleAdmin` burn — G-D12.
     */
    function setGaugeRegistry(address registry_) external {
        if (msg.sender != moduleAdmin) revert OnlyModuleAdmin(msg.sender);
        if (registry_ == address(0)) revert ZeroAddress();
        if (gaugeRegistry != address(0)) revert SetterAlreadyCalled();
        gaugeRegistry = registry_;
        if (vaultClassRegistry != address(0)) {
            moduleAdmin = address(0);
        }
        emit GaugeRegistrySet(registry_);
    }

    // -------------------------------------------------------------------------
    // External entry points
    // -------------------------------------------------------------------------

    /**
     * @notice Returns the canonical fixed anti-spam fee for `payToken` (svZCHF or sUSDS).
     */
    function requiredAmount(IERC20 payToken) external view returns (uint256) {
        return _requiredAmount(payToken);
    }

    /**
     * @notice Executes the G-D12 nine-step outer unlock flow: caller-gated fee donation into der Bodensee.
     * @param payToken svZCHF or sUSDS.
     * @param amount Exact fee amount; MUST equal `_requiredAmount(payToken)`.
     */
    function swapAndDeposit(IERC20 payToken, uint256 amount) external onlyAuthorizedCaller {
        if (payToken != _svZchf && payToken != _sUsds) {
            revert InvalidPayToken(payToken);
        }
        if (amount == 0) {
            revert ZeroAmount();
        }
        uint256 required = _requiredAmount(payToken);
        if (amount != required) {
            revert IncorrectAmount(amount, required);
        }
        if (_EXECUTING_SLOT.asBoolean().tload()) {
            revert ReentrancyGuard();
        }
        _EXECUTING_SLOT.asBoolean().tstore(true);
        _PENDING_PAY_TOKEN_SLOT.asAddress().tstore(address(payToken));
        _PENDING_AMOUNT_SLOT.asUint256().tstore(amount);
        _ORIGINAL_CALLER_SLOT.asAddress().tstore(msg.sender);
        _vault.unlock(abi.encodeCall(this._swapAndDepositCallback, (payToken, amount)));
        _EXECUTING_SLOT.asBoolean().tstore(false);
        _PENDING_PAY_TOKEN_SLOT.asAddress().tstore(address(0));
        _PENDING_AMOUNT_SLOT.asUint256().tstore(0);
        _ORIGINAL_CALLER_SLOT.asAddress().tstore(address(0));
        uint256 residual = payToken.balanceOf(address(this));
        if (residual != 0) {
            revert HelperBalanceNonZero(residual);
        }
    }

    // -------------------------------------------------------------------------
    // Vault callback
    // -------------------------------------------------------------------------

    /**
     * @notice G-D12 nine-step `_vault.unlock` callback: settle, DONATION add-liquidity, reserve delta, event.
     * @dev `external` for `abi.encodeCall` from the Vault; `OnlyVault` restricts `msg.sender` to `_vault`.
     */
    function _swapAndDepositCallback(IERC20 payToken, uint256 amount) external {
        if (msg.sender != address(_vault)) {
            revert OnlyVault(msg.sender);
        }
        if (
            address(payToken) != _PENDING_PAY_TOKEN_SLOT.asAddress().tload() ||
            amount != _PENDING_AMOUNT_SLOT.asUint256().tload()
        ) {
            revert CallbackPayloadMismatch();
        }
        uint8 idx = payToken == _svZchf ? _svZchfIndex : _sUsdsIndex;
        uint256 preReserve = _currentReserve(idx);
        payToken.safeTransfer(address(_vault), amount);
        _vault.settle(payToken, amount);
        uint256[] memory maxAmountsIn = new uint256[](3);
        maxAmountsIn[idx] = amount;
        (, uint256 bptOut, ) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: _bodensee,
                to: address(this),
                maxAmountsIn: maxAmountsIn,
                minBptAmountOut: 0,
                kind: AddLiquidityKind.DONATION,
                userData: ""
            })
        );
        if (bptOut != 0) {
            revert BptMintedOnDonation(bptOut);
        }
        uint256 postReserve = _currentReserve(idx);
        if (postReserve != preReserve + amount) {
            revert ReserveDeltaMismatch(preReserve + amount, postReserve);
        }
        emit FeeRoutedToBodensee(_ORIGINAL_CALLER_SLOT.asAddress().tload(), payToken, amount);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev Shared switch for `requiredAmount` and `swapAndDeposit` step 4 strict-equality fee.
    function _requiredAmount(IERC20 payToken) internal view returns (uint256) {
        if (payToken == _svZchf) {
            return FEE_SVZCHF;
        }
        if (payToken == _sUsds) {
            return FEE_SUSDS;
        }
        revert InvalidPayToken(payToken);
    }

    /// @dev G-D18: `IVault.getPoolTokenInfo` + `balancesRaw[idx]` only.
    function _currentReserve(uint8 idx) internal view returns (uint256) {
        (, , uint256[] memory balancesRaw, ) = _vault.getPoolTokenInfo(_bodensee);
        return balancesRaw[idx];
    }
}
