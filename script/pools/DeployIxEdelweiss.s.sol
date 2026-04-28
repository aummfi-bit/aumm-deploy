// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxEdelweissConfig } from "script/pools/configs/05_ixEdelweiss.s.sol";

/**
 * @title DeployIxEdelweiss
 * @notice Concrete MiliariumPoolDeployer wrapper for ixEdelweiss (Miliarium slot 05). Delegates all deploy logic to the abstract base; binds the pool config via IxEdelweissConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxEdelweiss is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxEdelweissConfig.config();
    }
}
