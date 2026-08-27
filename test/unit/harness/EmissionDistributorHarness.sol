// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {EmissionDistributor} from "../../../src/emission/EmissionDistributor.sol";
import {IAuMM} from "../../../src/token/IAuMM.sol";
import {IGaugeRegistry} from "../../../src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "../../../src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "../../../src/ccb/ICCBMultiplier.sol";
import {IEfficiencyOracle} from "../../../src/gauge/IEfficiencyOracle.sol";
import {IMiliariumRegistry} from "../../../src/ccb/IMiliariumRegistry.sol";

/// @title EmissionDistributorHarness
/// @notice Test-only inheriting wrapper exposing EmissionDistributor's internal observation helpers per H-D34.
/// @dev Inherits `EmissionDistributor` with 9-arg constructor pass-through. Adds two `external view` wrappers — `extLpTrancheIntegral` and `extLpTrancheEmission` — that delegate to the parent's `internal view` helpers for test-side conservation-invariant and AP-identity fixtures per H-D34. No additional state, no override of parent behavior, no modifiers, no events. Preserves prod ABI minimality — `EmissionDistributor` itself remains free of the test-only surface.
contract EmissionDistributorHarness is EmissionDistributor {
    constructor(
        IAuMM aumm_,
        IGaugeRegistry gaugeRegistry_,
        IEMASampler emaSampler_,
        ICCBMultiplier ccbMultiplier_,
        IEfficiencyOracle efficiencyOracle_,
        IMiliariumRegistry miliariumRegistry_,
        uint256 genesisBlock_,
        address initialGovernance_,
        address vault_
    ) EmissionDistributor(aumm_, gaugeRegistry_, emaSampler_, ccbMultiplier_, efficiencyOracle_, miliariumRegistry_, genesisBlock_, initialGovernance_, vault_) {}

    /// @notice Delegates to parent's `_lpTrancheIntegral(from, to)` internal view helper per H-D34.
    function extLpTrancheIntegral(uint256 from, uint256 to) external view returns (uint256) {
        return _lpTrancheIntegral(from, to);
    }

    /// @notice Delegates to parent's `_lpTrancheEmission(block_)` internal view helper per H-D34.
    function extLpTrancheEmission(uint256 block_) external view returns (uint256) {
        return _lpTrancheEmission(block_);
    }
}
