// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxMonetaConfig } from "script/pools/configs/22_ixMoneta.s.sol";

/**
 * @title DeployIxMoneta
 * @notice Concrete MiliariumPoolDeployer wrapper for ixMoneta (Miliarium slot 22). Delegates all deploy logic to the abstract base; binds the pool config via IxMonetaConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxMoneta is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxMonetaConfig.config();
    }
}
