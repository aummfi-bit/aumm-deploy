// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxVitalixConfig } from "script/pools/configs/24_ixVitalix.s.sol";

/**
 * @title DeployIxVitalix
 * @notice Concrete MiliariumPoolDeployer wrapper for ixVitalix (Miliarium slot 24). Delegates all deploy logic to the abstract base; binds the pool config via IxVitalixConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxVitalix is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxVitalixConfig.config();
    }
}
