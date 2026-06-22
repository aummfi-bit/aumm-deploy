// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxLongusConfig } from "script/pools/configs/11_ixLongus.s.sol";

/**
 * @title DeployIxLongus
 * @notice Concrete MiliariumPoolDeployer wrapper for ixLongus (Miliarium slot 11). Delegates all deploy logic to the abstract base; binds the pool config via IxLongusConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxLongus is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxLongusConfig.config();
    }
}
