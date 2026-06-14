// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

/**
 * @title IVotingWeight
 * @notice Forward-stub interface for the Aureum voting-weight reader — the value-weighted governance
 *         view consumed by `VaultClassRegistry.vetoProposal` (G-D9 veto-threshold semantic).
 * @dev Introduced at Stage I (I9.1) per I-D17 as the correctly-named replacement for the deleted
 *      `IAuMT` consumer surface: under I-D14, AuMT is the pool's own Balancer V3 BPT, not a separate
 *      token, so a token-named interface is wrong. This surface commits to five members — `governanceWeight(holder)` and `totalSupply()` (the `VaultClassRegistry.vetoProposal` live denominator pair), `getPastVotes(holder, block)` and `getPastTotalSupply(block)` (the `AureumGovernance` snapshot denominator pair — Governor-style block-keyed history per the F-06 fix), plus `poke(holder)` (the permissionless checkpoint-refresh that pushes that history) — and is deliberately NOT `is IERC20`: the reader holds no balances and effects no transfers.
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
     * @notice Governor-style historical vote weight for `holder` at a past block.
     * @dev The frozen weight `AureumGovernance` reads at a proposal's `snapshotBlock` (F-06). Returns the
     *      holder's checkpoint as of the most recent `poke` at or before `blockNumber`; a holder who never
     *      poked on or before `blockNumber` reads 0. Reverts for the current or a future block (the
     *      checkpoint is not yet final). The concrete `VotingWeight` implements this over OZ
     *      `Checkpoints.Trace208.upperLookup`.
     * @param holder The holder whose past weight is read.
     * @param blockNumber A strictly-past block (`< block.number`).
     * @return The holder's checkpointed weight as of `blockNumber`.
     */
    function getPastVotes(address holder, uint256 blockNumber) external view returns (uint256);

    /**
     * @notice Governor-style historical total qualified weight at a past block — the snapshot quorum denominator.
     * @dev The denominator `AureumGovernance` reads at `snapshotBlock` (F-06). Returns the running total as
     *      of the most recent `poke` at or before `blockNumber`; the concrete `VotingWeight` pushes it with
     *      the running sum on every `poke`, so it equals the sum of every holder's checkpoint at that block —
     *      hence `sum of getPastVotes(voter, b) <= getPastTotalSupply(b)`, the numerator-le-denominator
     *      invariant that closes the post-`endBlock` quorum-inflation grief. Reverts for the current or a
     *      future block.
     * @param blockNumber A strictly-past block (`< block.number`).
     * @return The total qualified weight as of `blockNumber`.
     */
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256);

    /**
     * @notice Permissionless refresh of `holder`'s value-weighted checkpoint — recomputes the live aggregate
     *         and pushes block-keyed history (F-06).
     * @dev Mutating and permissionless by design (anyone may refresh any holder, including resetting a
     *      withdrawn holder's stale weight to its live value). The concrete `VotingWeight` recomputes the
     *      holder's aggregate over the gauge-filtered registry, updates the live `totalSupply()` denominator
     *      via the signed-delta discipline, and pushes both the holder and total checkpoints read by
     *      `getPastVotes` / `getPastTotalSupply`. No longer called by `AureumGovernance.castVote` (which now
     *      reads `getPastVotes` at the proposal `snapshotBlock`); a voter must `poke` themselves before a
     *      proposal's `snapshotBlock` for their weight to count. Still drives the live `VaultClassRegistry`
     *      veto reads.
     * @param holder The address whose checkpoint is refreshed.
     */
    function poke(address holder) external;
}
