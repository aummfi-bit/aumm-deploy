// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxForumConfig } from "script/pools/configs/13_ixForum.s.sol";

/**
 * @title DeployIxForum
 * @notice Concrete MiliariumPoolDeployer wrapper for ixForum (Miliarium slot 13). Delegates all deploy logic to the abstract base; binds the pool config via IxForumConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxForum is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxForumConfig.config();
    }
}
