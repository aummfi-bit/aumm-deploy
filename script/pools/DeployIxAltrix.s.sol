// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxAltrixConfig } from "script/pools/configs/09_ixAltrix.s.sol";

/**
 * @title DeployIxAltrix
 * @notice Concrete MiliariumPoolDeployer wrapper for ixAltrix (Miliarium slot 09). Delegates all deploy logic to the abstract base; binds the pool config via IxAltrixConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxAltrix is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxAltrixConfig.config();
    }
}
