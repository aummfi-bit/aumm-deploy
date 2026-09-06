// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

/**
 * @title IPositionCloseSink
 * @notice The single-method surface the emission recorder calls to tell the voting-weight reader that
 *         a holder's recorded position in one pool has closed.
 * @dev B.2 / PP-D55 (i) and (ix). Declared as its own interface rather than as a sixth member of
 *      `IVotingWeight` because the two surfaces face opposite directions: `IVotingWeight` is a
 *      five-member READER consumed by `VaultClassRegistry.vetoProposal` and `AureumGovernance`, while
 *      this is a recorder-gated WRITE with exactly one caller. Widening the reader would type a write
 *      edge with a reader interface and force a stub onto four test mocks that will never be the
 *      recorder; importing the concrete `VotingWeight` into the distributor instead would pull
 *      `Checkpoints`, `FixedPoint` and `SafeCast` into that compile unit and type the PP-D55 (vii)
 *      slot as a concrete contract. J-D2's `MiliariumRegistry is IMiliariumRegistry,
 *      IMiliariumSlotRegistry` is the shape followed here — one concrete, one interface per consumer
 *      role — as is the 1:1 callback edge of `IAureumProtocolFeeControllerHookExtension`.
 *
 *      The implementation is `src/governance/VotingWeight.sol`, which subtracts the holder's stored
 *      per-pool weight part from both aggregates, deletes the part and pushes both checkpoint
 *      histories. It performs NO oracle read, so it cannot revert against a hostile EMA and honours
 *      PP-D16's storage-only arm directly rather than through a wrapped call.
 */
interface IPositionCloseSink {
    /**
     * @notice Notifies the sink that `holder`'s recorded position in `pool` has closed.
     * @dev Gated to the recorder by the implementation. Idempotent — a call for a holder whose part
     *      is already zero returns without writing, so the recorder may fire it on every closing path
     *      without tracking whether it has already run for that pool.
     * @param pool The pool whose recorded position closed.
     * @param holder The holder whose recorded position closed.
     */
    function onPositionClosed(address pool, address holder) external;
}
