// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxCasperConfig } from "script/pools/configs/03_ixCasper.s.sol";

/**
 * @title DeployIxCasper
 * @notice Concrete MiliariumPoolDeployer wrapper for ixCasper (Miliarium slot 03). Delegates all deploy logic to the abstract base; binds the pool config via IxCasperConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxCasper is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxCasperConfig.config();
    }
}
