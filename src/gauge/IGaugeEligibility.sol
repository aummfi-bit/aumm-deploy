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

    /**
     * @notice Returns whether `pool` clears the composition-challenge Quality Gate — ≥52% admitted-ERC-4626 weight by `_compute52PctNumerator` plus the canonical fee-routing hook — without running the full activation-criteria suite.
     * @dev Stage O **O-D2** + **O-D2a** composition-fitness gate (canonical §xxvii registry-level check; supersedes K-D6e). Narrower than `evaluateEligibility`: runs only the **G-D8** 52% quality gate (`_compute52PctNumerator(tokens, weights) >= 0.52e18`) and the **I-D13** canonical-hook assertion — it does NOT run the TVL floor, factory-provenance, or anti-spam checks (a freshly-deployed composition replacement legitimately has no TVL yet). Reverts `ForbiddenToken` on AuMM/AuMT (via `_compute52PctNumerator`, **T-I3**) and `WrongFeeRoutingHook` when the pool's Vault-registered hook is not the canonical fee-routing hook. Consumed by `AureumGovernance.proposeCompositionChallenge` / `_executeProposal` through the `IGaugeRegistry` delegation.
     * @param pool The candidate replacement pool under evaluation.
     * @return passes `true` when the pool clears the 52% quality gate and carries the canonical hook.
     */
    function meetsCompositionQualityGate(address pool) external view returns (bool);

    /**
     * @notice Returns whether `pool` satisfies the **PB-D69** fee-rail conjunct — the pool carries a der-Bodensee deposit rail, or it is `recoveryPathAdmitted`.
     * @dev Split out of `meetsCompositionQualityGate` by **PP-D50** amendment (x). The composition path needs this value SNAPSHOTTED at propose, so that a revocation landing between a passed two-thirds vote and its execution can no longer annul the mandate (**C.6**), while the gate's pool-intrinsic checks stay live at execute. Named for the conjunct rather than for admission because it is true for any railed pool that was never admitted at all. The ACTIVATION path is unaffected and keeps its own inline conjunct in `_checkEligibilityCriteria`; it does not consume this view. Consumed by `AureumGovernance.proposeCompositionChallenge` through the `IGaugeRegistry` delegation.
     * @param pool The pool whose fee-rail conjunct is queried.
     * @return satisfied `true` when `pool` carries a der-Bodensee rail or is admitted to the recovery path.
     */
    function feeRailConjunctSatisfied(address pool) external view returns (bool satisfied);
}
