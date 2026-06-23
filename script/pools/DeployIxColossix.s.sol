// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxColossixConfig } from "script/pools/configs/23_ixColossix.s.sol";

/**
 * @title DeployIxColossix
 * @notice Concrete MiliariumPoolDeployer wrapper for ixColossix (Miliarium slot 23). Delegates all deploy logic to the abstract base; binds the pool config via IxColossixConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxColossix is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxColossixConfig.config();
    }
}
