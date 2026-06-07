// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title IMiliariumSlotRegistry — Miliarium slot↔pool binding and governance surface for Stage J
/// @notice The slot-assignment and governance API of the Miliarium registry: which pool occupies each of the 28 Miliarium constellation slots, the governance-gated `replaceSlot` mutation, and the governance-contract rebinding handoff. Consumed by Stage K composition challenges.
/// @dev Companion to the CCB read view `src/ccb/IMiliariumRegistry.sol` (membership + dense enumeration for `CCBMultiplier`); the concrete Stage J `MiliariumRegistry.sol` implements both — `MiliariumRegistry is IMiliariumRegistry, IMiliariumSlotRegistry` (J-D2).
///      Slot indices are 1-based in the external API — valid slots are `[1, 28]` per `04_tokenomics.md` §vii; `0` is reserved as the "not a member" sentinel returned by `slotOf` and is never a valid slot (J-D3).
///      Governance gate mirrors `GaugeRegistry` (J-D5): a mutable `governanceContract` set at construction to the Authorizer Safe, rebound at Stage K via `setGovernanceContract`; `replaceSlot` and `setGovernanceContract` are governance-only.
///      Population, replacement, and governance handoffs emit block-numbered events per J-D6 / CLAUDE.md §5 (block numbers are the canonical time unit).
interface IMiliariumSlotRegistry {
    /// @notice Emitted when a previously empty slot is assigned a pool — at genesis seeding and on any zero→nonzero `replaceSlot`.
    /// @param slot The 1-based Miliarium slot index `[1, 28]`.
    /// @param pool The pool address newly occupying `slot`.
    /// @param blockNumber `block.number` at population (canonical time unit per CLAUDE.md §5).
    event SlotPopulated(uint256 indexed slot, address indexed pool, uint256 blockNumber);

    /// @notice Emitted when an occupied slot's pool is swapped for a different pool — on any nonzero→nonzero `replaceSlot`.
    /// @param slot The 1-based Miliarium slot index `[1, 28]`.
    /// @param oldPool The pool previously occupying `slot` (now deregistered).
    /// @param newPool The pool now occupying `slot`.
    /// @param blockNumber `block.number` at replacement (canonical time unit per CLAUDE.md §5).
    event SlotReplaced(uint256 indexed slot, address indexed oldPool, address indexed newPool, uint256 blockNumber);

    /// @notice Emitted when the governance contract is rebound — construction handoff or Stage K migration.
    /// @param oldGovernance The previous governance contract address.
    /// @param newGovernance The new governance contract address.
    event GovernanceTransferred(address indexed oldGovernance, address indexed newGovernance);

    /// @notice Thrown when a slot index is outside the valid 1-based range `[1, 28]`.
    /// @param slot The offending slot index.
    error InvalidSlot(uint256 slot);

    /// @notice Thrown when a required address argument is the zero address — governance, a seeded pool, or the `replaceSlot` newPool.
    error ZeroAddress();

    /// @notice Thrown at construction when the `slotNumbers` and `pools` genesis arrays have unequal length.
    error LengthMismatch();

    /// @notice Thrown when a governance-gated call is made by an address other than `governanceContract`.
    /// @param caller The unauthorized caller.
    error NotGovernance(address caller);

    /// @notice Thrown when a pool is assigned to a slot while already registered in another slot — one slot per pool.
    /// @param pool The already-registered pool.
    error PoolAlreadyRegistered(address pool);

    /// @notice Thrown at construction when a genesis slot index is assigned more than once.
    /// @param slot The doubly-assigned slot index.
    error SlotAlreadyAssigned(uint256 slot);

    /// @notice Assign `newPool` to `slot`, populating an empty slot or replacing an occupied one; governance-only.
    /// @dev Keeps the dense `IMiliariumRegistry` enumeration in sync (J-D1): a zero→nonzero assignment appends to the enumeration; a nonzero→nonzero assignment swap-removes the old pool and appends the new. Emits `SlotPopulated` (empty slot) or `SlotReplaced` (occupied slot). Reverts `NotGovernance` for an unauthorized caller, `InvalidSlot` for an out-of-range slot, `ZeroAddress` for a zero `newPool`, and `PoolAlreadyRegistered` when `newPool` already occupies another slot.
    /// @param slot The 1-based Miliarium slot index `[1, 28]`.
    /// @param newPool The pool to assign to `slot` — must be nonzero and not already registered in another slot.
    function replaceSlot(uint256 slot, address newPool) external;

    /// @notice Rebind the governance contract; callable only by the current `governanceContract`.
    /// @dev Stage K handoff from the Authorizer Safe to on-chain governance (J-D5). Emits `GovernanceTransferred`. Reverts `NotGovernance` for an unauthorized caller and `ZeroAddress` for a zero `newGovernance`.
    /// @param newGovernance The new governance contract address — must be nonzero.
    function setGovernanceContract(address newGovernance) external;

    /// @notice The pool currently occupying `slot`, or the zero address if the slot is empty.
    /// @dev Reverts `InvalidSlot` when `slot` is outside `[1, 28]`.
    /// @param slot The 1-based Miliarium slot index `[1, 28]`.
    /// @return The pool address at `slot` — zero if unpopulated.
    function poolAtSlot(uint256 slot) external view returns (address);

    /// @notice The 1-based slot index occupied by `pool`, or `0` if `pool` is not a registered Miliarium member.
    /// @param pool The pool address to look up.
    /// @return The 1-based slot index `[1, 28]`, or `0` when `pool` is not registered.
    function slotOf(address pool) external view returns (uint256);

    /// @notice The current governance contract — the only address permitted to call `replaceSlot` and `setGovernanceContract`.
    /// @return The governance contract address.
    function governanceContract() external view returns (address);
}
