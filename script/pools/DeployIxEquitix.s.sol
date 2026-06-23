// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxEquitixConfig } from "script/pools/configs/17_ixEquitix.s.sol";

/**
 * @title DeployIxEquitix
 * @notice Concrete MiliariumPoolDeployer wrapper for ixEquitix (Miliarium slot 17). Delegates all deploy logic to the abstract base; binds the pool config via IxEquitixConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxEquitix is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxEquitixConfig.config();
    }
}
