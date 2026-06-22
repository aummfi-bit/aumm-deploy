// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxStrataConfig } from "script/pools/configs/12_ixStrata.s.sol";

/**
 * @title DeployIxStrata
 * @notice Concrete MiliariumPoolDeployer wrapper for ixStrata (Miliarium slot 12). Delegates all deploy logic to the abstract base; binds the pool config via IxStrataConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxStrata is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxStrataConfig.config();
    }
}
