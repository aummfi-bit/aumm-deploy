// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { MiliariumPoolDeployer } from "script/pools/deploy-miliarium-pool.s.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";
import { IxAurixConfig } from "script/pools/configs/27_ixAurix.s.sol";

/**
 * @title DeployIxAurix
 * @notice Concrete MiliariumPoolDeployer wrapper for ixAurix (Miliarium slot 27). Delegates all deploy logic to the abstract base; binds the pool config via IxAurixConfig. The ysyBOLD yield core's Rate Provider is the Aureum-deployed CompositeRateProvider (N3.2) chaining ysyBOLD over ERC4626RateProvider(yBOLD) per N-D9, which has no mainnet address — per N-D7 it is resolved from the YSYBOLD_RATE_PROVIDER env var and injected into IxAurixConfig.config(...); _config() is view (not pure) to permit the env read, per the N3.4 base widening. Per docs/STAGE_E_NOTES.md E-D23.
 */
contract DeployIxAurix is MiliariumPoolDeployer {
    function _config() internal view override returns (PoolConfig memory) {
        return IxAurixConfig.config(vm.envAddress("YSYBOLD_RATE_PROVIDER"));
    }
}
