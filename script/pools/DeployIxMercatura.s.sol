// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxMercaturaConfig } from "script/pools/configs/26_ixMercatura.s.sol";

/**
 * @title DeployIxMercatura
 * @notice Concrete MiliariumPoolDeployer wrapper for ixMercatura (Miliarium slot 26). Delegates all deploy logic to the abstract base; binds the pool config via IxMercaturaConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxMercatura is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxMercaturaConfig.config();
    }
}
