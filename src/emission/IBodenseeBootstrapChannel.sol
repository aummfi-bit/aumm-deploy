// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

/// @title IBodenseeBootstrapChannel — Aureum F-0 bootstrap rail interface
/// @notice Exposes the externally-observable consumer surface for the Bodensee bootstrap channel:
///         permissionless `accrue()` bookkeeping and governance-gated `distribute()` mint-and-donate.
/// @dev Per H-D2 audit-isolation, the F-0 bootstrap rail is a separate contract from the pool-scoped
///      emission distributor. Per H-D11 mint-at-distribute, `accrue()` performs AP piecewise integration
///      over `[genesisBlock, month6EndBlock]` (Bootstrap A linear 80% → 50%) and
///      `(month6EndBlock, month10EndBlock]` (Bootstrap B linear 50% → 0%) with Era 0 covering all
///      bootstrap per OQ-3; `distribute()` is the sole `IAuMM.mint` entry point. Per H-D12 the channel
///      implements its own `IVault.unlock` callback path with AuMM as pay token and
///      `addLiquidity(AddLiquidityKind.DONATION)` to immutable `BODENSEE_POOL` — mirroring G-D11 /
///      G-D21 and NOT reusing `SwapAndDepositToBodensee.donate` (which rejects non-svZCHF/sUSDS pay
///      tokens per `src/gauge/SwapAndDepositToBodensee.sol` L329 + L362–L364). Per H-D13 lifecycle
///      clamp, accrual is bounded by `month10EndBlock`. Per H-D14, `distribute()` is governance-only.
///      Concrete implementation lands at H3.2 in `src/emission/BodenseeBootstrapChannel.sol`.
interface IBodenseeBootstrapChannel {
    /// @notice Emitted when `accrue()` records a new interval contribution.
    /// @param fromBlock The block immediately after the previous `lastAccrualBlock` (inclusive lower bound).
    /// @param toBlock The clamped upper bound `min(block.number, month10EndBlock)` (inclusive upper bound).
    /// @param contribution The amount of AuMM (scaled18) added to `pendingAccrual` for this interval.
    event Accrued(uint256 fromBlock, uint256 toBlock, uint256 contribution);

    /// @notice Emitted when `distribute()` mints and donates AuMM to der Bodensee.
    /// @param amount The amount of AuMM (scaled18) minted and donated in this distribution.
    event Distributed(uint256 amount);

    /// @notice Permissionlessly advances the bootstrap accumulator for the elapsed block interval.
    /// @dev Pure bookkeeping — does NOT call `IAuMM.mint` per H-D11. Cross-boundary AP split at
    ///      `month6EndBlock` when an interval spans Bootstrap A and Bootstrap B legs. Per H-D13
    ///      lifecycle clamp + empty-interval short-circuit: safe to call post-window as a no-op when
    ///      `from > to`.
    function accrue() external;

    /// @notice Governance-gated mint-and-donate of accumulated bootstrap AuMM to der Bodensee.
    /// @dev Reverts if `pendingAccrual == 0`. Mints AuMM, resets pending to zero, increments
    ///      `totalDistributed`, and executes `addLiquidity(AddLiquidityKind.DONATION)` inside the
    ///      Vault unlock callback per H-D12. Per H-D14 governance gating prevents arbitrary-block
    ///      caller-chosen price-window force-flush.
    function distribute() external;

    /// @notice Returns the accumulated but not yet distributed bootstrap AuMM.
    /// @dev Mutated only by `accrue()` (increment) and `distribute()` (reset to zero).
    /// @return AuMM 18-decimal fixed-point.
    function pendingAccrual() external view returns (uint256);

    /// @notice Returns the cumulative AuMM minted and donated since deployment.
    /// @dev Monotonically non-decreasing. Mutated only by `distribute()`.
    /// @return AuMM 18-decimal fixed-point.
    function totalDistributed() external view returns (uint256);

    /// @notice Returns the block number through which accrual has been recorded.
    /// @dev Advances monotonically up to `month10EndBlock` per the H-D13 lifecycle clamp.
    /// @return The upper bound of the bootstrap accumulator's last recorded interval.
    function lastAccrualBlock() external view returns (uint256);
}
