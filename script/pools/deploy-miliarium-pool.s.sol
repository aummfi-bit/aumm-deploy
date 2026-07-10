// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenConfig, TokenType, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AureumWeightedPoolFactory } from "src/factory/AureumWeightedPoolFactory.sol";
import { PoolConfig } from "script/pools/PoolConfig.sol";

/**
 * @title MiliariumPoolDeployer
 * @notice Abstract base for Miliarium pilot-pool `forge script` entrypoints: reads the env-var contract, builds
 *         `TokenConfig[]` and `PoolRoleAccounts`, re-asserts the 52% ERC-4626 Quality Gate, and calls
 *         `AureumWeightedPoolFactory.create(...)`.
 * @dev **E-D23** (`docs/STAGE_E_NOTES.md`): abstract base + per-pilot thin wrappers; env vars
 *      `AUREUM_WEIGHTED_POOL_FACTORY`, `FEE_ROUTING_HOOK`, and `GOVERNANCE_MULTISIG` are the only external addresses
 *      resolved at script runtime. **E-D3** (`docs/STAGE_E_PLAN.md`): QG belt-and-suspenders in `run()` before
 *      `vm.startBroadcast()`. `AureumWeightedPoolFactory.create` already registers the pool with the Vault (D28);
 *      initial liquidity and β-pattern init live in the fork-test harness, not here—**E-D23** final paragraph.
 */
abstract contract MiliariumPoolDeployer is Script {
    /// @notice Minimum ERC-4626 weight share for script-side QG re-assertion (52e16); matches the factory constant per E-D3.
    uint256 public constant MIN_ERC4626_WEIGHT = 52e16;

    /// @notice Sum of normalized weights for ERC-4626 (WITH_RATE + non-zero rate provider) is below 52% of one.
    error QualityGateUnsatisfied(uint256 erc4626WeightSum, uint256 minRequired);

    /// @dev Returns the per-pool config. `view` (not `pure`) per N-D7 so the RP-dependent wrappers
    ///      (ixMagnix 20, ixAurix 27, ixLibertas 06, ixAetheron 02) can resolve their Aureum-deployed
    ///      Rate-Provider address(es) from env vars; the clean pure-literal wrappers keep `pure override`
    ///      (`pure ⊆ view`), unchanged. Stage-N I13 fix-forward, no Stage-E re-tag.
    function _config() internal view virtual returns (PoolConfig memory);

    function run() external returns (address pool) {
        PoolConfig memory cfg = _config();

        address factoryAddr = vm.envAddress("AUREUM_WEIGHTED_POOL_FACTORY");
        address feeRoutingHook = vm.envAddress("FEE_ROUTING_HOOK");
        address governanceMultisig = vm.envAddress("GOVERNANCE_MULTISIG");

        TokenConfig[] memory tokens = new TokenConfig[](cfg.tokens.length);
        for (uint256 i = 0; i < cfg.tokens.length; ++i) {
            tokens[i] = TokenConfig({
                token: IERC20(cfg.tokens[i]),
                tokenType: cfg.tokenTypes[i],
                rateProvider: cfg.rateProviders[i],
                paysYieldFees: cfg.paysYieldFees[i]
            });
        }

        uint256 erc4626WeightSum;
        for (uint256 i = 0; i < cfg.tokens.length; ++i) {
            if (cfg.tokenTypes[i] == TokenType.WITH_RATE && cfg.rateProviders[i] != IRateProvider(address(0))) {
                erc4626WeightSum += cfg.normalizedWeights[i];
            }
        }
        if (erc4626WeightSum < MIN_ERC4626_WEIGHT) {
            revert QualityGateUnsatisfied(erc4626WeightSum, MIN_ERC4626_WEIGHT);
        }

        // F-20 / P-D40: swapFeeManager is address(0), NOT governanceMultisig. A non-zero
        // swapFeeManager is an EXCLUSIVE role (VaultAdmin._ensureAuthenticatedByExclusiveRole)
        // that locks fee changes to that one address and never consults the authorizer;
        // address(0) defers to the Vault authorizer, so the Safe (pre-K via AureumAuthorizer)
        // and then AureumGovernance's FeeChange proposal type (post-K via
        // AureumGovernanceAuthorizer) both keep the lever, and §xxix multisig dissolution
        // follows the migrating authorizer rather than a frozen immutable role slot.
        // pauseManager stays governanceMultisig — it is the NON-exclusive role
        // (_ensureAuthenticatedByRole) whose governance fall-through already exists.
        PoolRoleAccounts memory roleAccounts = PoolRoleAccounts({
            pauseManager: governanceMultisig,
            swapFeeManager: address(0),
            poolCreator: address(0)
        });

        vm.startBroadcast();
        pool = AureumWeightedPoolFactory(factoryAddr).create(
            cfg.name,
            cfg.symbol,
            tokens,
            cfg.normalizedWeights,
            roleAccounts,
            cfg.swapFeePercentage,
            feeRoutingHook,
            false,
            false,
            cfg.salt
        );
        vm.stopBroadcast();

        console2.log("Miliarium pool deployed at:", pool);
    }
}
