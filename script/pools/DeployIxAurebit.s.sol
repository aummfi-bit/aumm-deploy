// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxAurebitConfig } from "script/pools/configs/14_ixAurebit.s.sol";

/**
 * @title DeployIxAurebit
 * @notice Concrete MiliariumPoolDeployer wrapper for ixAurebit (Miliarium slot 14). Delegates all deploy logic to the abstract base; binds the pool config via IxAurebitConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxAurebit is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxAurebitConfig.config();
    }
}
