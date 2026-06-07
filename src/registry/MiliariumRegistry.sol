// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {IMiliariumRegistry} from "../ccb/IMiliariumRegistry.sol";
import {IMiliariumSlotRegistry} from "./IMiliariumSlotRegistry.sol";

/**
 * @title MiliariumRegistry
 * @notice Canonical Miliarium slot↔pool registry — the fixed 28-slot constellation binding (**J-D3**) together with the CCB membership and dense-enumeration read view (Stage F `IMiliariumRegistry`). Records which pool occupies each slot, exposes the dense pool list consumed by `CCBMultiplier`, and gates slot replacement plus the governance handoff behind `onlyGovernance` (**J-D5**).
 * @dev **J2** lineage J2.1 → J2.6 — J2.1 scaffold (storage + `onlyGovernance`), J2.2 constructor + `_assign` genesis seeding, J2.3 dense views, J2.4 slot views, J2.5 `replaceSlot`, J2.6 `setGovernanceContract` with the `abstract` keyword removed (concrete once all eight interface members are implemented, per the **G3.3-fix1 / G-D24** abstract-scaffold convention). Implements both `IMiliariumRegistry` (CCB read view, `src/ccb/`) and `IMiliariumSlotRegistry` (slot/governance surface, `src/registry/`) per **J-D2**.
 *      Dual internal structure per **J-D1** reconciles the sparse 28-slot model with the tagged Stage F dense enumeration: `_slots` is the 1-based-indexed (stored 0-based) slot layout with `address(0)` for empty slots, while `_enumerated` is the dense packed list of occupied pools — real pools only, never `address(0)` — that backs `miliariumPoolsCount` / `miliariumPoolAt`, so `CCBMultiplier.sol:249-251` never reads `tvlEMA(address(0))`. Three mirror mappings keep membership, reverse slot lookup, and swap-remove all O(1).
 *      Governance gate mirrors `GaugeRegistry` per **J-D5**: `governanceContract` is a mutable `address` (not `immutable`) set at construction to the Authorizer Safe and rebound at Stage K via `setGovernanceContract`. All events and errors are declared in `IMiliariumSlotRegistry` (single ABI source per **J1.1**); this contract declares none locally.
 */
abstract contract MiliariumRegistry is IMiliariumRegistry, IMiliariumSlotRegistry {
    // ----------------------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------------------

    /// @notice Number of Miliarium constellation slots — fixed at 28 per `04_tokenomics.md` §vii (**J-D3**).
    uint256 public constant SLOT_COUNT = 28;

    // ----------------------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------------------

    /// @notice 1-based slot → pool, stored 0-based as `_slots[slot - 1]`; `address(0)` marks an empty slot (**J-D1** / **J-D3**).
    address[SLOT_COUNT] private _slots;

    /// @notice Dense list of occupied pools — the `IMiliariumRegistry` CCB enumeration; real pools only, never `address(0)` (**J-D1**).
    address[] private _enumerated;

    /// @notice Pool → membership flag for O(1) `isMiliarium` (**J-D1**).
    mapping(address => bool) private _isMiliarium;

    /// @notice Pool → 1-based slot index; `0` marks "not registered", the `slotOf` sentinel (**J-D1** / **J-D3**).
    mapping(address => uint256) private _slotOf;

    /// @notice Pool → index into `_enumerated` for O(1) swap-remove on replacement (**J-D1**).
    mapping(address => uint256) private _enumIndex;

    /// @inheritdoc IMiliariumSlotRegistry
    address public override governanceContract;

    // ----------------------------------------------------------------------------
    // Modifier
    // ----------------------------------------------------------------------------

    /// @dev Restricts a call to the current `governanceContract` (**J-D5**).
    modifier onlyGovernance() {
        if (msg.sender != governanceContract) revert NotGovernance(msg.sender);
        _;
    }
}
