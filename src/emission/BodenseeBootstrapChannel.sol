// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {AddLiquidityKind, AddLiquidityParams} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {TransientStorageHelpers} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";
import {StorageSlotExtension} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol";
import {IBodenseeBootstrapChannel} from "./IBodenseeBootstrapChannel.sol";
import {IAuMM} from "../token/IAuMM.sol";
import {AureumTime} from "../lib/AureumTime.sol";

/// @title BodenseeBootstrapChannel — F-0 piecewise bootstrap rail routing accrued AuMM to der Bodensee from GENESIS_BLOCK through month10EndBlock per H-D2
/// @notice Permissionless accrue() advances pendingAccrual and lastAccrualBlock via AP piecewise integration (Bootstrap A: 80% to 50% over Months 0—6; Bootstrap B: 50% to 0% over Months 6—10) without minting. Governance-gated distribute() mints the accrued AuMM and performs a one-sided Balancer V3 AddLiquidityKind.DONATION into der Bodensee via IVault.unlock per H-D11 + H-D12.
/// @dev H-D14 — distribute() gated by onlyGovernance; BODENSEE_POOL is immutable (structurally stronger than H-D8 mutable constellation roster; no setBodenseePool setter). H-D12 — does NOT reuse SwapAndDepositToBodensee.donate (rejects non-svZCHF/sUSDS payToken per src/gauge/SwapAndDepositToBodensee.sol L362—L364); own IVault.unlock callback path with 3 transient slots. H-D13 — no selfdestruct / pause; permanent zero-activity fixture post-window with readable accumulator state. Stage K governance handoff via setGovernanceContract. Deploy prerequisite per H-D7: IAuMM.setMinter(address(this)) at H10.
abstract contract BodenseeBootstrapChannel is IBodenseeBootstrapChannel {
    using SafeERC20 for IERC20;
    using StorageSlotExtension for *;

    /* ---------- Immutables ---------- */

    /// @notice Balancer V3 Vault — entry point for IVault.unlock callback in distribute() per H-D12.
    IVault internal immutable _vault;

    /// @notice Immutable bootstrap destination — der Bodensee pool address per H-D14; no setBodenseePool setter (structurally stronger than H-D8 governance-extensible constellation roster).
    address public immutable BODENSEE_POOL;

    /// @notice AuMM token — minted to address(this) by IAuMM.mint(address(this), amount) inside distribute() per H-D12 step 4, then settled into der Bodensee via DONATION.
    IAuMM public immutable AuMM;

    /// @notice AuMM token index within the Bodensee pool roster — derived at construction via _vault.getPoolTokens(BODENSEE_POOL) loop per H-D12; used to build maxAmountsIn[_aummIndex] in the DONATION callback. Reverts IndexLookupFailed at construction if AuMM is absent from the Bodensee roster.
    uint8 internal immutable _aummIndex;

    /// @notice Stage H genesis block — anchors AureumTime.month6EndBlock(GENESIS_BLOCK) and AureumTime.month10EndBlock(GENESIS_BLOCK) calls in accrue() per H-D11. Same constructor-parameter precedent as AuMM.sol GENESIS_BLOCK.
    uint256 public immutable GENESIS_BLOCK;

    /* ---------- Governance (H-D14) ---------- */

    /// @notice Governance authority — Stage A—K Authorizer Safe at deploy; rebound via setGovernanceContract at Stage K per H-D14. Gates distribute() via onlyGovernance.
    address public governance;

    /* ---------- Accrue state (H-D11) ---------- */

    /// @notice Accumulated AuMM (scaled18) not yet minted and donated to der Bodensee — incremented by accrue() AP sum per H-D11; zeroed by distribute() before the IAuMM.mint call. Satisfies IBodenseeBootstrapChannel.pendingAccrual() view via public getter.
    uint256 public pendingAccrual;

    /// @notice Cumulative AuMM (scaled18) successfully minted and donated since deployment — incremented by distribute(), never decremented per H-D11. Satisfies IBodenseeBootstrapChannel.totalDistributed() view via public getter.
    uint256 public totalDistributed;

    /// @notice Last block through which pendingAccrual has been computed — advanced to min(block.number, month10EndBlock) on each accrue() call; initialized to GENESIS_BLOCK in the constructor per H-D11. Satisfies IBodenseeBootstrapChannel.lastAccrualBlock() view via public getter.
    uint256 public lastAccrualBlock;

    /* ---------- Transient slot constants (H-D12) ---------- */

    /// @dev EIP-1153 transient slots via Balancer V3 assembly-helper pattern per G-D14; 3-slot layout (_PENDING_PAY_TOKEN_SLOT dropped vs SwapAndDepositToBodensee — pay token is always AuMM, an immutable); solc 0.8.26 lacks the transient state-var keyword.
    bytes32 internal immutable _EXECUTING_SLOT = TransientStorageHelpers.calculateSlot("aureum.bodenseeBootstrapChannel", "executing");
    bytes32 internal immutable _PENDING_AMOUNT_SLOT = TransientStorageHelpers.calculateSlot("aureum.bodenseeBootstrapChannel", "pendingAmount");
    bytes32 internal immutable _ORIGINAL_CALLER_SLOT = TransientStorageHelpers.calculateSlot("aureum.bodenseeBootstrapChannel", "originalCaller");

    /* ---------- Errors ---------- */

    /// @notice Reverts when a zero address is supplied for an immutable or the initial governance slot.
    error ZeroAddress();

    /// @notice Reverts when distribute() is called with pendingAccrual == 0.
    error NoPendingAccrual();

    /// @notice Reverts when a non-governance address invokes distribute() or setGovernanceContract.
    error NotGovernance(address caller);

    /// @notice Reverts at construction if AuMM is not found in der Bodensee's token roster — misconfigured deploy is unrecoverable per H-D12.
    error IndexLookupFailed();

    /// @notice Reverts in _distributeCallback when the callback payload does not match _PENDING_AMOUNT_SLOT — mirrors SwapAndDepositToBodensee G-D11 sentinel.
    error CallbackPayloadMismatch(uint256 expected, uint256 actual);

    /// @notice Reverts in _distributeCallback when msg.sender != address(_vault) — identical to SwapAndDepositToBodensee G-D11 / G-D21 OnlyVault guard.
    error OnlyVault(address caller);

    /// @notice Reverts post-unlock if IERC20(address(AuMM)).balanceOf(address(this)) != 0 — ensures complete AuMM settlement per H-D12 residual assert.
    error HelperBalanceNonZero(uint256 residual);

    /* ---------- Events ---------- */

    /// @notice Emitted when setGovernanceContract rebinds the governance authority (Stage K handoff per H-D14).
    event GovernanceTransferred(address indexed oldGovernance, address indexed newGovernance);
}
