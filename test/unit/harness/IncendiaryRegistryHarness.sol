// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {IncendiaryRegistry} from "../../../src/incendiary/IncendiaryRegistry.sol";
import {SwapAndDepositToBodensee} from "../../../src/gauge/SwapAndDepositToBodensee.sol";
import {IGaugeRegistry} from "../../../src/ccb/IGaugeRegistry.sol";
import {IAuMM} from "../../../src/token/IAuMM.sol";
import {IVaultExplorer} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IncendiaryRegistryHarness
/// @notice Test-only inheriting wrapper exposing IncendiaryRegistry's internal observation and placement helpers per L-D26.
/// @dev Inherits `IncendiaryRegistry` with 8-arg constructor pass-through. Adds seven `external` wrappers — six `view` delegations to internal helpers plus one mutating `extPlaceBoost` — for L8.1—L8.4 unit fixtures. No additional state, no override of parent behavior, no modifiers, no events. `_payTokenIndex` is exercised transitively via `extValueInAuMM`; `updateRailEMA` / `buyBoost` / `integratedSkim` / `boostIntegral` remain tested on the harness instance directly.
contract IncendiaryRegistryHarness is IncendiaryRegistry {
    constructor(SwapAndDepositToBodensee bodenseeChannel_, address bodenseePool_, IVaultExplorer vaultExplorer_, IAuMM aumm_, IERC20 svzchf_, IERC20 susds_, IGaugeRegistry gaugeRegistry_, uint256 genesisBlock_) IncendiaryRegistry(bodenseeChannel_, bodenseePool_, vaultExplorer_, aumm_, svzchf_, susds_, gaugeRegistry_, genesisBlock_) {}

    /// @notice Delegates to parent's `_spotRate(payToken)` internal view helper per L-D26.
    function extSpotRate(address payToken) external view returns (uint256) {
        return _spotRate(payToken);
    }

    /// @notice Delegates to parent's `_maturePrice(payToken)` internal view helper per L-D26.
    function extMaturePrice(address payToken) external view returns (uint256) {
        return _maturePrice(payToken);
    }

    /// @notice Delegates to parent's `_valueInAuMM(payToken, amount)` internal view helper per L-D26.
    function extValueInAuMM(address payToken, uint256 amount) external view returns (uint256) {
        return _valueInAuMM(payToken, amount);
    }

    /// @notice Delegates to parent's `_epochEmissionIntegral(epoch)` internal view helper per L-D26.
    function extEpochEmissionIntegral(uint256 epoch) external view returns (uint256) {
        return _epochEmissionIntegral(epoch);
    }

    /// @notice Delegates to parent's `_epochCap(epoch)` internal view helper per L-D26.
    function extEpochCap(uint256 epoch) external view returns (uint256) {
        return _epochCap(epoch);
    }

    /// @notice Delegates to parent's `_epochOverlapBlocks(e, from, to)` internal view helper per L-D26.
    function extEpochOverlapBlocks(uint256 e, uint256 from, uint256 to) external view returns (uint256) {
        return _epochOverlapBlocks(e, from, to);
    }

    /// @notice Delegates to parent's `_placeBoost(pool, entitlement)` internal mutating helper per L-D26.
    function extPlaceBoost(address pool, uint256 entitlement) external {
        _placeBoost(pool, entitlement);
    }
}
