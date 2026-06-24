// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxLibertasConfig } from "script/pools/configs/06_ixLibertas.s.sol";

/**
 * @title DeployIxLibertas
 * @notice Concrete MiliariumPoolDeployer wrapper for ixLibertas (Miliarium slot 06). Delegates all deploy logic to the abstract base; binds the pool config via IxLibertasConfig. The scrvUSD and sfrxUSD yield cores' Rate Providers are the Aureum-deployed ERC4626RateProvider (N3.1), which have no mainnet address — per N-D7 they are resolved from the SCRVUSD_RATE_PROVIDER and SFRXUSD_RATE_PROVIDER env vars and injected into IxLibertasConfig.config(...); _config() is view (not pure) to permit the env read, per the N3.4 base widening. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxLibertas is MiliariumPoolDeployer {
    function _config() internal view override returns (PoolConfig memory) {
        return IxLibertasConfig.config(vm.envAddress("SCRVUSD_RATE_PROVIDER"), vm.envAddress("SFRXUSD_RATE_PROVIDER"));
    }
}
