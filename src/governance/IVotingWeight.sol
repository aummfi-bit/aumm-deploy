// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

/**
 * @title IVotingWeight
 * @notice Forward-stub interface for the Aureum voting-weight reader — the value-weighted governance
 *         view consumed by `VaultClassRegistry.vetoProposal` (G-D9 veto-threshold semantic).
 * @dev Introduced at Stage I (I9.1) per I-D17 as the correctly-named replacement for the deleted
 *      `IAuMT` consumer surface: under I-D14, AuMT is the pool's own Balancer V3 BPT, not a separate
 *      token, so a token-named interface is wrong. This surface commits to three members — `governanceWeight(holder)` and `totalSupply()` (the `VaultClassRegistry.vetoProposal` denominator pair) plus `poke(holder)` (the `AureumGovernance.castVote` checkpoint-refresh, added at Stage K per K10) — and is deliberately NOT `is IERC20`: the reader holds no balances and effects no transfers.
 *
 *      The concrete implementation — `src/governance/VotingWeight.sol`, computing
 *      `(qualified_AuMT_value × time_in_pool_capped)^(1/4 → 1/3)` over the EmissionDistributor
 *      recorder clock — is deferred to Stage K per I-D15: it needs a concrete `ITVLOracle`
 *      (OQ-22 / F-D3) plus the snapshot-voting layer. Until it lands, the bound reader returns zero,
 *      so vetoes are structurally impossible — the pre-Stage-I `IAuMT` stub behaviour, preserved.
 */
interface IVotingWeight {
    /**
     * @notice Value-weighted governance vote share for `holder`.
     * @dev Consumed by `VaultClassRegistry.vetoProposal` per G-D9; the denominator is `totalSupply()`.
     *      Encoding precision and the qualification / on-ramp curve lock with the Stage K
     *      `VotingWeight.sol` implementation (I-D15); this stub commits only to the function shape.
     * @param holder The address whose governance weight is queried.
     * @return The holder's absolute voting weight (denominator is `totalSupply()`).
     */
    function governanceWeight(address holder) external view returns (uint256);

    /**
     * @notice Total voting-weight supply — the veto-threshold denominator.
     * @dev Read by `VaultClassRegistry.vetoProposal` (G-D9 / G-D19) as the denominator of the
     *      basis-points veto check. Its concrete semantics under the BPT model (BPT total supply vs
     *      total qualified voting weight) lock with the Stage K `VotingWeight.sol` implementation per
     *      I-D17; this stub commits only to the function shape.
     * @return The total voting-weight supply.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Permissionless refresh of `holder`'s value-weighted checkpoint.
     * @dev Consumed by `AureumGovernance.castVote` per K-D6b — called on `msg.sender` immediately
     *      before reading `governanceWeight`, so the vote uses a fresh checkpoint. Mutating and
     *      permissionless by design (anyone may refresh any holder, including resetting a withdrawn
     *      holder's stale weight to its live value). The concrete `VotingWeight` recomputes the
     *      holder's aggregate over the gauge-filtered registry and updates the `totalSupply()`
     *      denominator via the signed-delta discipline.
     * @param holder The address whose checkpoint is refreshed.
     */
    function poke(address holder) external;
}
