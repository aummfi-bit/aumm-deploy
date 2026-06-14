// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";
import {IVotingWeight} from "src/governance/IVotingWeight.sol";

/// @title StageGMocks
/// @notice Fork-side mock contract home for Stage G integration tests (`test/fork/StageGIntegration.t.sol`) per **G-D25c**.
/// @dev `MockEfficiencyOracle` mirrors verbatim from `test/unit/GaugeEligibility.t.sol:49`; `MockVotingWeight` mirrors verbatim from `test/unit/VaultClassRegistry.t.sol:29`. Unit-test embeds remain the ABI-stability source-of-truth per the §12 anchor at `test/unit/GaugeEligibility.t.sol:161`. Any future signature change to either mock MUST be propagated to the unit-test embed and this mirror in the same commit. `MockTVLOracle` triplet unification (canonical at `test/fork/mocks/CCBMocks.sol:10` + inline copies at `test/unit/GaugeEligibility.t.sol:34` + `test/unit/EMASampler.t.sol:325`) is out of scope per **G-D25c** Out-of-scope clause; deferred to a post-Stage-G housekeeping beat.

/// @notice Minimal IEfficiencyOracle double storing SMA pair per pool.
contract MockEfficiencyOracle is IEfficiencyOracle {
    mapping(address => uint256) public numeratorSmaOf;

    mapping(address => uint256) public denominatorSmaOf;

    /// @notice Pins numerator and denominator SMA for `pool` in isolation tests.
    function setEfficiencyInputs(address pool, uint256 numeratorSma_, uint256 denominatorSma_) external {
        numeratorSmaOf[pool] = numeratorSma_;
        denominatorSmaOf[pool] = denominatorSma_;
    }

    /// @notice Returns pinned SMA inputs for `pool`.
    function efficiencyInputs(address pool) external view override returns (uint256, uint256) {
        return (numeratorSmaOf[pool], denominatorSmaOf[pool]);
    }

    /// @notice No-op stub for H4.1.x-bis interface conformance; tests pin `efficiencyInputs` directly via `setEfficiencyInputs`.
    function recordEmissions(address, uint256) external override {}
}

/// @notice Minimal IVotingWeight double with configurable weights for VaultClassRegistry coverage.
contract MockVotingWeight is IVotingWeight {
    mapping(address => uint256) public governanceWeights;

    uint256 private _totalSupply;

    function setTotalSupply(uint256 supply_) external {
        _totalSupply = supply_;
    }

    function setGovernanceWeight(address holder, uint256 weight) external {
        governanceWeights[holder] = weight;
    }

    function governanceWeight(address holder) external view returns (uint256) {
        return governanceWeights[holder];
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function poke(address) external {}
    function getPastVotes(address, uint256) external view returns (uint256) { return 0; }
    function getPastTotalSupply(uint256) external view returns (uint256) { return 0; }
}
