// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

/// @title IEfficiencyOracle — Aureum Gauge F-10 efficiency oracle interface
/// @notice Returns pre-smoothed F-10 efficiency inputs for a Balancer V3 pool — the numerator
///         (`swap_fee_revenue_i + yield_fee_revenue_i`) and denominator (`emissions_received_i`) of the
///         canonical OQ-G1 formula, both 3-epoch SMA-smoothed at oracle scope.
/// @dev Per G-D23 (i) the oracle owns the 3-epoch SMA; `GaugeEligibility.accumulateEpochSnapshot` reads
///      pre-smoothed inputs and computes the dimensionless ratio `(numeratorSma * 1e18) / denominatorSma`.
///      Per G-D23 (ii) this interface is a sibling to `ITVLOracle` — not an extension — so the F-10
///      efficiency path and the OQ-G2 TVL-floor path remain independently swappable.
///      F-10 is price-agnostic per `11_formulas.md` — `numeratorSma` and `denominatorSma` must be expressed in
///      the same unit (the ratio is dimensionless); this interface does NOT lock svZCHF or any other
///      numéraire on either return value.
///      `efficiencyInputs` concrete shipped at H2b in `src/emission/EfficiencyOracle.sol` per H-D10 v2 (intra-epoch accumulation with EpochEntry[3] ring buffer + 3-epoch SMA at oracle scope). The `recordEmissions` push entry point landed in-place at H4.1.x-bis per H-D23 (allocation-side F-10 semantics — emission-distributor wiring at H4 invokes this at the `_settlePool` boundary after `_accrueGlobal` and before `poolAccDebt` is rebased; mirrors the H2a.10c `quoteSvZCHF` retrofit on `ITVLOracle`) and took its `epoch` argument at E.7a per PP-D58 (xvi). `recordFees` and `feeRecorder` joined at E.7a so the fee routing hook produces the numerator, and `GaugeEligibility` reads the feed's seat, through this interface.
interface IEfficiencyOracle {
    /// @notice Pre-smoothed F-10 efficiency inputs for `pool` per OQ-G1.
    /// @param pool The Balancer V3 pool address.
    /// @return numeratorSma The 3-epoch SMA of `swap_fee_revenue_i + yield_fee_revenue_i` (1e18 fixed-point).
    /// @return denominatorSma The 3-epoch SMA of `emissions_received_i` (same unit as `numeratorSma`).
    function efficiencyInputs(address pool) external view returns (uint256 numeratorSma, uint256 denominatorSma);

    /// @notice Records a per-pool AuMM emissions allocation to the epoch it accrued in per H-D23 and PP-D58 (xvi) — push signature called by `EmissionDistributor._settlePool` after `_accrueGlobal` and before `poolAccDebt` is rebased; allocation-side F-10 semantics.
    /// @dev Per H-D23 `aummAmountScaled18` is what was allocated to the pool, not literal mint (F-10 denominator semantics are allocation-side per `11_formulas.md`). Per PP-D58 (xvi) the distributor splits a settle at the epoch marks `_accrueGlobal` records and calls this once per non-zero piece with that piece's accrual epoch, dropping pieces older than the three-epoch window. The concrete oracle at `src/emission/EfficiencyOracle.sol` converts `aummAmountScaled18` to svZCHF via `tvlOracle.quoteSvZCHF(AuMM, ...)` per H-D10 v2 and credits the current epoch's accumulator, or the ring slot of an epoch one to three back, ignoring any other epoch; mocks may stub as a no-op since unit tests pin `efficiencyInputs` directly.
    /// @param pool The Balancer V3 pool address whose F-10 denominator is being credited.
    /// @param epoch The epoch the allocation accrued in, indexed by `AureumTime.epochIndex(GENESIS_BLOCK, block)`.
    /// @param aummAmountScaled18 The 18-decimal fixed-point AuMM emissions amount allocated to `pool` for `epoch` per Balancer V3 `balancesLiveScaled18` convention.
    function recordEmissions(address pool, uint256 epoch, uint256 aummAmountScaled18) external;

    /// @notice Records a per-pool fee revenue contribution in the current epoch; gated to `feeRecorder`.
    /// @dev Called by the fee routing hook with the rail-token amount its own route landed at der Bodensee, in Vault live-scaled18 units per PP-D56 (iii) and PP-D58 (xvi).
    /// @param pool The pool whose F-10 numerator is being credited.
    /// @param token The token the amount is denominated in.
    /// @param amountScaled18 The amount in Vault live-scaled18 units.
    function recordFees(address pool, address token, uint256 amountScaled18) external;

    /// @notice The authorized fee feed; zero while no feed is seated.
    /// @dev `GaugeEligibility` reads it on a zero numerator: while it is zero a zero numerator means no feed and the pool is skipped, and once it is seated a zero numerator means no revenue and the pool ranks at ratio zero, per PP-D58 (ix) and (xvi).
    /// @return The current fee recorder, or zero.
    function feeRecorder() external view returns (address);
}
