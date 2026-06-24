// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxAetheronConfig } from "script/pools/configs/02_ixAetheron.s.sol";

/**
 * @title DeployIxAetheron
 * @notice Concrete MiliariumPoolDeployer wrapper for ixAetheron (Miliarium slot 02). Delegates all deploy logic to the abstract base; binds the pool config via IxAetheronConfig. The sfrxETH and wOETH yield cores' Rate Providers are the Aureum-deployed ERC4626RateProvider (N3.1), which have no mainnet address — per N-D7 they are resolved from the SFRXETH_RATE_PROVIDER and WOETH_RATE_PROVIDER env vars and injected into IxAetheronConfig.config(...); _config() is view (not pure) to permit the env read, per the N3.4 base widening. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxAetheron is MiliariumPoolDeployer {
    function _config() internal view override returns (PoolConfig memory) {
        return IxAetheronConfig.config(vm.envAddress("SFRXETH_RATE_PROVIDER"), vm.envAddress("WOETH_RATE_PROVIDER"));
    }
}
