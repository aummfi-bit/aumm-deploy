// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxInnovixConfig } from "script/pools/configs/18_ixInnovix.s.sol";

/**
 * @title DeployIxInnovix
 * @notice Concrete MiliariumPoolDeployer wrapper for ixInnovix (Miliarium slot 18). Delegates all deploy logic to the abstract base; binds the pool config via IxInnovixConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxInnovix is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxInnovixConfig.config();
    }
}
