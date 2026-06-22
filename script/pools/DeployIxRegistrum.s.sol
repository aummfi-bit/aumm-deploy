// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxRegistrumConfig } from "script/pools/configs/15_ixRegistrum.s.sol";

/**
 * @title DeployIxRegistrum
 * @notice Concrete MiliariumPoolDeployer wrapper for ixRegistrum (Miliarium slot 15). Delegates all deploy logic to the abstract base; binds the pool config via IxRegistrumConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxRegistrum is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxRegistrumConfig.config();
    }
}
