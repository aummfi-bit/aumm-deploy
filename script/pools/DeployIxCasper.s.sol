// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxCasperConfig } from "script/pools/configs/03_ixCasper.s.sol";

/**
 * @title DeployIxCasper
 * @notice Concrete MiliariumPoolDeployer wrapper for ixCasper (Miliarium slot 03). Delegates all deploy logic to the abstract base; binds the pool config via IxCasperConfig. The slot-03 16% waEthwstETH theme leg's Rate Provider is the Aureum-deployed CompositeRateProvider (PB2.3) chaining waEthwstETH over the canonical Balancer wstETH RP (0x72D07D…) per PB-D8, which has no mainnet address — per N-D7 it is resolved from the WAETHWSTETH_COMPOSITE_RATE_PROVIDER env var and injected into IxCasperConfig.config(...); _config() is view (not pure) to permit the env read, per the N3.4 base widening. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxCasper is MiliariumPoolDeployer {
    function _config() internal view override returns (PoolConfig memory) {
        return IxCasperConfig.config(vm.envAddress("WAETHWSTETH_COMPOSITE_RATE_PROVIDER"));
    }
}
