// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {VotingWeight} from "../../../src/governance/VotingWeight.sol";
import {IEMASampler} from "../../../src/ccb/IEMASampler.sol";
import {IGaugeRegistry} from "../../../src/ccb/IGaugeRegistry.sol";
import {IMiliariumRegistry} from "../../../src/ccb/IMiliariumRegistry.sol";
import {IEmissionDistributor} from "../../../src/emission/IEmissionDistributor.sol";

/// @title VotingWeightHarness
/// @notice Test-only inheriting wrapper exposing VotingWeight's internal per-pool weight parts per PP-D55 (xv).
/// @dev Inherits `VotingWeight` with 5-arg constructor pass-through. Adds one `external view` wrapper — `extHolderPoolWeight` — over the `internal` `_holderPoolWeight` map, so the B.2 parts-sum invariant of PP-D55 (viii) has a reader. A concrete-only public getter was REJECTED on D.7's ground: it would carry zero readers in `src/` and `script/`, since `onPositionClosed` reads the map directly and no production caller wants the parts. No additional state, no override of parent behavior, no modifiers, no events, so the parent ABI and semantics are untouched and a fixture retyping its `vw` handle to this harness keeps every existing assertion. Mirrors `EmissionDistributorHarness` (H-D34). NOTE the argument order: this getter takes `(holder, pool)`, the storage order of `_holderPoolWeight`, which is the REVERSE of `onPositionClosed(pool, holder)`.
contract VotingWeightHarness is VotingWeight {
    constructor(
        IEMASampler emaSampler_,
        IGaugeRegistry gaugeRegistry_,
        IEmissionDistributor recorder_,
        IMiliariumRegistry registry_,
        uint256 genesisBlock_
    ) VotingWeight(emaSampler_, gaugeRegistry_, recorder_, registry_, genesisBlock_) {}

    /// @notice Delegates to the parent's `internal` `_holderPoolWeight[holder][pool]` per PP-D55 (viii).
    function extHolderPoolWeight(address holder, address pool) external view returns (uint256) {
        return _holderPoolWeight[holder][pool];
    }
}
