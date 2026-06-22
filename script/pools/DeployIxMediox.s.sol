// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxMedioxConfig } from "script/pools/configs/10_ixMediox.s.sol";

/**
 * @title DeployIxMediox
 * @notice Concrete MiliariumPoolDeployer wrapper for ixMediox (Miliarium slot 10). Delegates all deploy logic to the abstract base; binds the pool config via IxMedioxConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxMediox is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxMedioxConfig.config();
    }
}
