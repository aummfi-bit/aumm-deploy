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

    /// @notice Donation authorizer — set at construction to deploy multisig per OQ-10; multi-shot, mutable post-deploy via `setDonateAuthorizer` per G-D21 authorizer-rotation.
    address public donateAuthorizer;

    /// @notice Runtime-mutable allowlist of contracts authorized to call `donate` per G-D21; populated post-deploy by the donateAuthorizer.
    mapping(address => bool) public authorizedDonators;

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

    /// @notice Strict rise on DONATION per PP-D45 — replaces exact-delta check; DONATION round-trips raw through scaled18 so consumed amount is not exactly predictable.
    error ReserveDidNotRise(uint256 preReserve, uint256 postReserve);

    /// @notice helper balance != 0 after callback (resolves the `HelperBalanceNonZero(...)` ellipsis above).
    error HelperBalanceNonZero(uint256 residual);

    /// @notice Nested re-entry attempt.
    error ReentrancyGuard();

    /// @notice Constructor-time `getPoolTokens` miss.
    error TokenNotInPool(IERC20 token);

    /// @notice Callback args drift from cached payload.
    error CallbackPayloadMismatch();

    /// @notice `donate` caller-gate miss — `msg.sender` not in `authorizedDonators` (G-D21).
    error OnlyAuthorizedDonator(address caller);

    /// @notice Authorization-mutator caller-gate miss — `msg.sender` not the donateAuthorizer (G-D21).
    error OnlyDonateAuthorizer(address caller);

    /// @notice `addAuthorizedDonator` called for a donator already in the allowlist (G-D21).
    error DonatorAlreadyAuthorized(address donator);

    /// @notice `removeAuthorizedDonator` called for a donator not currently in the allowlist (G-D21).
    error DonatorNotAuthorized(address donator);

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

    /// @notice Emitted by `setDonateAuthorizer` after the slot is rotated (G-D21).
    event DonateAuthorizerSet(address indexed previous, address indexed current);

    /// @notice Emitted by `addAuthorizedDonator` after the mapping is set true (G-D21).
    event AuthorizedDonatorAdded(address indexed donator);

    /// @notice Emitted by `removeAuthorizedDonator` after the mapping is cleared (G-D21).
    event AuthorizedDonatorRemoved(address indexed donator);

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

    /// @notice `donate`-path caller-gate per G-D21 — variable-amount path is gated to the runtime allowlist, not the one-shot caller slots.
    modifier onlyAuthorizedDonator() {
        if (!authorizedDonators[msg.sender]) {
            revert OnlyAuthorizedDonator(msg.sender);
        }
        _;
    }

    /// @notice Authorization-mutator caller-gate per G-D21.
    modifier onlyDonateAuthorizer() {
        if (msg.sender != donateAuthorizer) {
            revert OnlyDonateAuthorizer(msg.sender);
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
        address moduleAdmin_,
        address donateAuthorizer_
    ) {
        if (address(vault_) == address(0)) revert ZeroAddress();
        if (bodensee_ == address(0)) revert ZeroAddress();
        if (address(svZchf_) == address(0)) revert ZeroAddress();
        if (address(sUsds_) == address(0)) revert ZeroAddress();
        if (moduleAdmin_ == address(0)) revert ZeroAddress();
        if (donateAuthorizer_ == address(0)) revert ZeroAddress();

        _vault = vault_;
        _bodensee = bodensee_;
        _svZchf = svZchf_;
        _sUsds = sUsds_;
        moduleAdmin = moduleAdmin_;
        donateAuthorizer = donateAuthorizer_;

        IERC20[] memory tokens = vault_.getPoolTokens(bodensee_);
        uint256 len = tokens.length;
        uint8 svZchfIndex_ = type(uint8).max;
        uint8 sUsdsIndex_ = type(uint8).max;
        for (uint256 i = 0; i < len; ++i) {
            if (address(tokens[i]) == address(svZchf_)) {
                // uint8(i) is safe: Bodensee is a 3-token pool by construction; len ≤ 3, i ∈ {0, 1, 2}; sentinel type(uint8).max reserved by the post-loop not-found check.
                // forge-lint: disable-next-line(unsafe-typecast)
                svZchfIndex_ = uint8(i);
            }
            if (address(tokens[i]) == address(sUsds_)) {
                // uint8(i) is safe: Bodensee is a 3-token pool by construction; len ≤ 3, i ∈ {0, 1, 2}; sentinel type(uint8).max reserved by the post-loop not-found check.
                // forge-lint: disable-next-line(unsafe-typecast)
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
    // Donate authorization mutators (G-D21)
    // -------------------------------------------------------------------------

    /**
     * @notice Rotates `donateAuthorizer` rights — multi-shot per G-D21 (Stage K hands authorizer from multisig to AureumGovernance).
     */
    function setDonateAuthorizer(address newAuthorizer) external onlyDonateAuthorizer {
        if (newAuthorizer == address(0)) revert ZeroAddress();
        address previous = donateAuthorizer;
        donateAuthorizer = newAuthorizer;
        emit DonateAuthorizerSet(previous, newAuthorizer);
    }

    /**
     * @notice Adds `donator` to the `donate` allowlist — G-D21 trust boundary: no `code.length > 0` check; authorizer review duty is operational, not on-chain.
     */
    function addAuthorizedDonator(address donator) external onlyDonateAuthorizer {
        if (donator == address(0)) revert ZeroAddress();
        if (authorizedDonators[donator]) revert DonatorAlreadyAuthorized(donator);
        authorizedDonators[donator] = true;
        emit AuthorizedDonatorAdded(donator);
    }

    /**
     * @notice Removes `donator` from the `donate` allowlist (G-D21).
     */
    function removeAuthorizedDonator(address donator) external onlyDonateAuthorizer {
        if (!authorizedDonators[donator]) revert DonatorNotAuthorized(donator);
        authorizedDonators[donator] = false;
        emit AuthorizedDonatorRemoved(donator);
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
        // PP-D45 — callers PUSH `amount` before invoking; entry balance already includes it, tolerated baseline is `entryBalance - consumed`, where `consumed` is what the Vault actually charged and is returned by the callback — the offered amount is not the charged amount once a rate rounds.
        uint256 entryBalance = payToken.balanceOf(address(this));
        if (_EXECUTING_SLOT.asBoolean().tload()) {
            revert ReentrancyGuard();
        }
        _EXECUTING_SLOT.asBoolean().tstore(true);
        _PENDING_PAY_TOKEN_SLOT.asAddress().tstore(address(payToken));
        _PENDING_AMOUNT_SLOT.asUint256().tstore(amount);
        _ORIGINAL_CALLER_SLOT.asAddress().tstore(msg.sender);
        bytes memory result = _vault.unlock(abi.encodeCall(this._swapAndDepositCallback, (payToken, amount)));
        _EXECUTING_SLOT.asBoolean().tstore(false);
        _PENDING_PAY_TOKEN_SLOT.asAddress().tstore(address(0));
        _PENDING_AMOUNT_SLOT.asUint256().tstore(0);
        _ORIGINAL_CALLER_SLOT.asAddress().tstore(address(0));
        uint256 consumed = abi.decode(result, (uint256));
        uint256 expectedResidual = entryBalance - consumed;
        uint256 residual = payToken.balanceOf(address(this));
        if (residual > expectedResidual) revert HelperBalanceNonZero(residual - expectedResidual);
    }

    /**
     * @notice Variable-amount DONATION entry point per G-D21 — gated to the `authorizedDonators` allowlist; serves vault-class admission bonds (G-D9 path #2), F-12 gauge-challenge deposits (Stage K path #3), composition-challenge deposits (Stage K/O path #4), and fee-proposal deposits (Stage K path #5). Reuses the same nine-step `_swapAndDepositCallback` and four transient slots as `swapAndDeposit`; the only validation surface delta vs `swapAndDeposit` is the absence of the magnitude check (variable `amount` flows through unchecked at the helper layer per G-D21 trust boundary — caller's bond math is upstream).
     * @param payToken svZCHF or sUSDS.
     * @param amount Variable amount; magnitude validation is the upstream caller's responsibility per G-D21.
     */
    function donate(IERC20 payToken, uint256 amount) external onlyAuthorizedDonator {
        if (payToken != _svZchf && payToken != _sUsds) {
            revert InvalidPayToken(payToken);
        }
        if (amount == 0) {
            revert ZeroAmount();
        }
        // PP-D45 — callers PUSH `amount` before invoking; entry balance already includes it, tolerated baseline is `entryBalance - consumed`, where `consumed` is what the Vault actually charged and is returned by the callback — the offered amount is not the charged amount once a rate rounds.
        uint256 entryBalance = payToken.balanceOf(address(this));
        if (_EXECUTING_SLOT.asBoolean().tload()) {
            revert ReentrancyGuard();
        }
        _EXECUTING_SLOT.asBoolean().tstore(true);
        _PENDING_PAY_TOKEN_SLOT.asAddress().tstore(address(payToken));
        _PENDING_AMOUNT_SLOT.asUint256().tstore(amount);
        _ORIGINAL_CALLER_SLOT.asAddress().tstore(msg.sender);
        bytes memory result = _vault.unlock(abi.encodeCall(this._swapAndDepositCallback, (payToken, amount)));
        _EXECUTING_SLOT.asBoolean().tstore(false);
        _PENDING_PAY_TOKEN_SLOT.asAddress().tstore(address(0));
        _PENDING_AMOUNT_SLOT.asUint256().tstore(0);
        _ORIGINAL_CALLER_SLOT.asAddress().tstore(address(0));
        uint256 consumed = abi.decode(result, (uint256));
        uint256 expectedResidual = entryBalance - consumed;
        uint256 residual = payToken.balanceOf(address(this));
        if (residual > expectedResidual) revert HelperBalanceNonZero(residual - expectedResidual);
    }

    // -------------------------------------------------------------------------
    // Vault callback
    // -------------------------------------------------------------------------

    /**
     * @notice G-D12 `_vault.unlock` callback: DONATION add-liquidity, then settle the Vault's actual debit, reserve rise, event.
     * @dev `external` for `abi.encodeCall` from the Vault; `OnlyVault` restricts `msg.sender` to `_vault`.
     *      Add runs before settle per PP-D45 and PB-D68 (xix); returns the amount actually consumed so the
     *      caller can thread it into its own residual check.
     */
    function _swapAndDepositCallback(IERC20 payToken, uint256 amount) external returns (uint256 consumed) {
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
        uint256[] memory maxAmountsIn = new uint256[](3);
        maxAmountsIn[idx] = amount;
        (uint256[] memory amountsIn, uint256 bptOut, ) = _vault.addLiquidity(
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
        // PP-D45 — DONATION branch round-trips raw through scaled18 so consumed amount is not exactly predictable; strict rise replaces exact equality.
        if (postReserve <= preReserve) {
            revert ReserveDidNotRise(preReserve, postReserve);
        }
        // PB-D68 (xix) — settle what the Vault actually charged, not what was offered; the remainder stays on the helper as dust, consumed by the caller's own residual accounting per PP-D45.
        consumed = amountsIn[idx];
        payToken.safeTransfer(address(_vault), consumed);
        // settle returns credit equal to consumed by construction; bounded fee-token loop. See D8 NOTES F12/F15.
        // slither-disable-next-line unused-return,calls-loop
        _vault.settle(payToken, consumed);
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
