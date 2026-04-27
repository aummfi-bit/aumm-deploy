// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxHelvetiaConfig } from "script/pools/configs/01_ixHelvetia.s.sol";

/**
 * @title DeployIxHelvetia
 * @notice Concrete MiliariumPoolDeployer wrapper for ixHelvetia (Miliarium slot 01). Delegates all deploy logic to the abstract base; binds the pool config via IxHelvetiaConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxHelvetia is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxHelvetiaConfig.config();
    }
}
