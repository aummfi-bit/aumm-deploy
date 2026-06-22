// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxBrevisConfig } from "script/pools/configs/08_ixBrevis.s.sol";

/**
 * @title DeployIxBrevis
 * @notice Concrete MiliariumPoolDeployer wrapper for ixBrevis (Miliarium slot 08). Delegates all deploy logic to the abstract base; binds the pool config via IxBrevisConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxBrevis is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxBrevisConfig.config();
    }
}
