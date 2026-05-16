// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { ITVLOracle } from "../../../src/ccb/ITVLOracle.sol";
import { IMiliariumRegistry } from "../../../src/ccb/IMiliariumRegistry.sol";
import { IGaugeRegistry } from "../../../src/ccb/IGaugeRegistry.sol";

/// @notice Test-only mock for `ITVLOracle` — F4.1 / F-D26.
contract MockTVLOracle is ITVLOracle {
    mapping(address => uint256) private _tvl;

    function set(address pool, uint256 value) external {
        _tvl[pool] = value;
    }

    function tvl(address pool) external view returns (uint256) {
        return _tvl[pool];
    }

    function quoteSvZCHF(address, uint256) external pure override returns (uint256) {
        return 0;
    }
}

/// @notice Test-only mock for `IMiliariumRegistry` — F4.1 / F-D26.
contract MockMiliariumRegistry is IMiliariumRegistry {
    address[3] private _pools;

    constructor(address[3] memory pools) {
        _pools = pools;
    }

    function isMiliarium(address pool) external view returns (bool) {
        for (uint256 i = 0; i < 3; ++i) {
            if (_pools[i] == pool) {
                return true;
            }
        }
        return false;
    }

    function miliariumPoolsCount() external pure returns (uint256) {
        return 3;
    }

    function miliariumPoolAt(uint256 index) external view returns (address) {
        return _pools[index];
    }
}

/// @notice Test-only mock for `IGaugeRegistry` — F4.1 / F-D26 + **G3.3-fix2** seven-stub backfill per **G-D24** Schedule (b) for the Stage G interface expansion (1 → 8 functions); mock retains the `setApproved` test helper + the real `isGaugeApproved` getter (Stage F **F-D17** boost-gate consumer); all other interface functions are empty stubs that return defaults.
contract MockGaugeRegistry is IGaugeRegistry {
    mapping(address => bool) private _approved;

    function setApproved(address gauge, bool approved) external {
        _approved[gauge] = approved;
    }

    function isGaugeApproved(address gauge) external view override returns (bool) {
        return _approved[gauge];
    }

    function gaugeStatus(address) external view override returns (GaugeStatus status) {}

    function activateGauge(address) external override {}

    function registerGaugeFromComposition(address) external override {}

    function seedFoundingPool(address) external override {}

    function seedFoundingPools(address[] calldata) external override {}

    function revokeGauge(address) external override {}

    function setGovernanceContract(address) external override {}
}
