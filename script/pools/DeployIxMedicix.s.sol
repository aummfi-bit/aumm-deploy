// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxMedicixConfig } from "script/pools/configs/25_ixMedicix.s.sol";

/**
 * @title DeployIxMedicix
 * @notice Concrete MiliariumPoolDeployer wrapper for ixMedicix (Miliarium slot 25). Delegates all deploy logic to the abstract base; binds the pool config via IxMedicixConfig. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxMedicix is MiliariumPoolDeployer {
    function _config() internal pure override returns (PoolConfig memory) {
        return IxMedicixConfig.config();
    }
}
