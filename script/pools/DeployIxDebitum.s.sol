// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxDebitumConfig } from "script/pools/configs/16_ixDebitum.s.sol";

/**
 * @title DeployIxDebitum
 * @notice Concrete MiliariumPoolDeployer wrapper for ixDebitum (Miliarium slot 16). Delegates all deploy logic to the abstract base; binds the pool config via IxDebitumConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxDebitum is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxDebitumConfig.config();
    }
}
