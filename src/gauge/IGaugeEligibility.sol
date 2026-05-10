// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

/**
 * @title IGaugeEligibility
 * @notice Narrow read surface consumed by `GaugeRegistry` (G3) for pre-activation eligibility checks.
 * @dev Cross-references: **G-D5** (gauge eligibility + efficiency events), **G-D8** (52% quality gate — vault-class admission), **G-D10** (ERC-4626 detection + numerator discipline), **OQ-G1** (efficiency ratio inputs from `ITVLOracle`), **T-I5** (epoch-snapshot determinism for latched reads).
 */

interface IGaugeEligibility {
    /**
     * @notice Runs all eligibility criteria for `pool`; on success writes the per-pool eligibility latch and returns true.
     * @dev State-writing gate intended for `GaugeRegistry.activateGauge` — persists `isGaugeEligible[pool]` and `lastSnapshotEpoch[pool]` to the current snapshot epoch on success; reverts if any criterion fails. Not a `view` — mutates storage.
     * @param pool The pool address under evaluation.
     * @return eligible Always `true` when the call succeeds without revert.
     */
    function evaluateEligibility(address pool) external returns (bool);

    /**
     * @notice Returns the latched eligibility flag for `pool` without re-running criteria.
     * @dev Read-only view of storage written by `evaluateEligibility` and epoch-boundary snapshot logic per **G-D5** / **T-I5**.
     * @param pool The pool address.
     * @return eligible Whether the pool has passed evaluation and remains latched eligible.
     */
    function isEligible(address pool) external view returns (bool);

    /**
     * @notice Returns whether `pool` sits in the favored cohort from the last efficiency snapshot.
     * @dev Top-15% favored cohort semantics per **G-D3** / **OQ-G1** — `true` when the pool ranks inside the ceiling-favored set after the F-10 efficiency tournament at the last `computeEpochSnapshot` boundary.
     * @param pool The pool address.
     * @return favored Whether the pool is in the favored cohort at the last epoch snapshot.
     */
    function cohortOf(address pool) external view returns (bool favored);

    /**
     * @notice Returns the epoch index associated with the current eligibility latch semantics.
     * @dev **T-I5** epoch-snapshot determinism — two reads at the same block observe identical latched state; eligibility writes occur only via `evaluateEligibility` and epoch-boundary snapshot entrypoints, never inside this view.
     * @return epoch The current snapshot epoch counter exposed for observability.
     */
    function snapshotEpoch() external view returns (uint256);
}
