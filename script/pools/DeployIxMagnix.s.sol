// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxMagnixConfig } from "script/pools/configs/20_ixMagnix.s.sol";

/**
 * @title DeployIxMagnix
 * @notice Concrete MiliariumPoolDeployer wrapper for ixMagnix (Miliarium slot 20). Delegates all deploy logic to the abstract base; binds the pool config via IxMagnixConfig. The sfrxUSD yield core's Rate Provider is the Aureum-deployed ERC4626RateProvider (N-D2), which has no mainnet address — per N-D7 it is resolved from the SFRXUSD_RATE_PROVIDER env var and injected into IxMagnixConfig.config(...); _config() is view (not pure) to permit the env read, per the N3.4 base widening. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxMagnix is MiliariumPoolDeployer {
    function _config() internal view override returns (PoolConfig memory) {
        return IxMagnixConfig.config(vm.envAddress("SFRXUSD_RATE_PROVIDER"));
    }
}
