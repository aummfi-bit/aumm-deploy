// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenConfig, TokenType, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

/**
 * @title DeployDerBodensee
 * @notice Fork-only deployment script for the der-Bodensee 40/30/30 WeightedPool
 *         (AuMM / sUSDS / svZCHF). Intended to be exercised with
 *         `forge script ... --fork-url`; this file deliberately omits any
 *         mainnet broadcast wiring.
 *
 * @dev **D-D6:** Fork-only scope: no production broadcast path here.
 *
 *      **D11:** Rate provider addresses are existing mainnet deployments
 *      (sUSDS and svZCHF); AuMM uses the identity provider (`address(0)`).
 *
 *      **D-D9 / OQ-2:** Bodensee yield collection is disabled at the
 *      `AureumProtocolFeeController` level. This script performs no fee-controller
 *      setters; structural OQ-2 behavior does not require registration-time calls.
 *
 *      **D28 (D6 plan reconciliation):** `WeightedPoolFactory.create` internally
 *      calls `_registerPoolWithVault`, so there is no separate `registerPool` from
 *      this script. Post-D0.5, `setPoolProtocolSwapFeePercentage` and
 *      `setPoolProtocolYieldFeePercentage` revert `SplitIsImmutable`; omit them.
 *      Bodensee parameters follow `docs/STAGE_D_NOTES.md` (Der Bodensee deployment
 *      parameters).
 *      **E-D22 / OQ-11 (2026-04-26 supersession, precision-corrected F-20/P-D40):** `swapFeeManager: address(0)` defers fee changes to the Vault authorizer — NOT "no one can change." Der Bodensee's fee is multisig-changeable pre-K via `AureumAuthorizer` and stays unreachable post-K only because `AureumGovernance.proposeFeeChange` excludes `BODENSEE_POOL`, not because the role is frozen; `governanceMultisig` retains only `pauseManager` as an explicit role. See `docs/FINDINGS.md` OQ-11 and `docs/STAGE_E_NOTES.md` E-D22.
 */
contract DeployDerBodensee is Script {
    /// @notice A WITH_RATE slot's non-zero rate provider resolved to address(0) via a STUB_ override; a zeroed
    ///         RP would flip both QG legs and Vault registration semantics (PB-D20 (i)).
    error StubRateProviderZeroed(address original);

    /// @notice The created pool diverged from the `DER_BODENSEE_POOL` prediction that `DeployAureumVault`
    ///         and `DeployFeeRoutingHook` have already consumed (PB-D27 (iv)(3)); abort immediately.
    error BodenseeAddressMismatch(address predicted, address actual);

    /// @dev PB-D27 (v) — testnet stub override resolver, mirrored from `deploy-miliarium-pool.s.sol` L50-L52.
    ///      With no matching `STUB_` key set the resolved address IS `original`, so the mainnet path stays
    ///      byte-identical. The `envOr` passthrough is deliberate and must NOT be tightened to `envAddress`:
    ///      that would oblige Stage R to publish an identity map for keys it has no reason to set. The
    ///      Sepolia mitigation is PB-D27 (iii)(c) — the stub map merged into `.env` before this script runs.
    function _resolveStub(address original) internal view returns (address) {
        return vm.envOr(string.concat("STUB_", vm.toString(original)), original);
    }

    /// @dev PB-D27 (v) — rate-provider override with fail-fast, mirrored from `deploy-miliarium-pool.s.sol`
    ///      L57-L63. Applies `_resolveStub`; a WITH_RATE slot whose non-zero RP resolves to address(0) reverts.
    function _resolveRateProvider(IRateProvider original, TokenType tokenType) internal view returns (IRateProvider) {
        address resolved = _resolveStub(address(original));
        if (tokenType == TokenType.WITH_RATE && address(original) != address(0) && resolved == address(0)) {
            revert StubRateProviderZeroed(address(original));
        }
        return IRateProvider(resolved);
    }

    function run() external returns (address pool) {
        address weightedPoolFactory = vm.envAddress("WEIGHTED_POOL_FACTORY");
        address aumm = vm.envAddress("AUMM");
        address svZchf = vm.envAddress("SV_ZCHF");
        address sUsds = vm.envAddress("SUSDS");
        address governanceMultisig = vm.envAddress("GOVERNANCE_MULTISIG");
        bytes32 bodenseeSalt = vm.envBytes32("BODENSEE_SALT");
        address predictedPool = vm.envAddress("DER_BODENSEE_POOL");

        // Runtime sort: ascending by token address (Balancer V3 registration convention).
        address t0 = aumm;
        address t1 = sUsds;
        address t2 = svZchf;
        if (t0 > t1) (t0, t1) = (t1, t0);
        if (t1 > t2) (t1, t2) = (t2, t1);
        if (t0 > t1) (t0, t1) = (t1, t0);

        TokenConfig[] memory tokens = new TokenConfig[](3);
        tokens[0] = _tokenConfig(t0, aumm, sUsds, svZchf);
        tokens[1] = _tokenConfig(t1, aumm, sUsds, svZchf);
        tokens[2] = _tokenConfig(t2, aumm, sUsds, svZchf);

        uint256[] memory normalizedWeights = new uint256[](3);
        normalizedWeights[0] = _normalizedWeight(t0, aumm);
        normalizedWeights[1] = _normalizedWeight(t1, aumm);
        normalizedWeights[2] = _normalizedWeight(t2, aumm);

        // E-D22 / OQ-11 (precision-corrected F-20/P-D40): swapFeeManager: address(0) defers to
        // the Vault authorizer, not "no one can change" — reachable pre-K via AureumAuthorizer,
        // unreachable post-K only because proposeFeeChange excludes BODENSEE_POOL.
        // See docs/FINDINGS.md OQ-11 (2026-04-26 status) and docs/STAGE_E_NOTES.md E-D22.
        PoolRoleAccounts memory roleAccounts = PoolRoleAccounts({
            pauseManager: governanceMultisig,
            swapFeeManager: address(0),
            poolCreator: address(0)
        });

        vm.startBroadcast();
        pool = WeightedPoolFactory(weightedPoolFactory).create(
            "der-Bodensee",
            "BODENSEE",
            tokens,
            normalizedWeights,
            roleAccounts,
            0.0075e18,
            address(0),
            true,
            false,
            bodenseeSalt
        );
        vm.stopBroadcast();

        // PB-D27 (iv)(3) — the base-layer address cycle is four-deep, and by the time this script runs
        // both `DeployAureumVault` and `DeployFeeRoutingHook` have already sealed immutables against this
        // key. A divergence is otherwise silent: the pool registers cleanly at an address nothing else
        // points to, and the failure only surfaces much later as an unrelated-looking bind error.
        if (pool != predictedPool) {
            revert BodenseeAddressMismatch(predictedPool, pool);
        }

        console2.log("der-Bodensee pool deployed at:", pool);
    }

    function _tokenConfig(
        address token,
        address aumm,
        address sUsds,
        address svZchf
    ) private view returns (TokenConfig memory) {
        if (token == aumm) {
            return TokenConfig({
                token: IERC20(token),
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            });
        } else if (token == sUsds) {
            return TokenConfig({
                token: IERC20(token),
                tokenType: TokenType.WITH_RATE,
                rateProvider: _resolveRateProvider(
                    IRateProvider(0x1195BE91e78ab25494C855826FF595Eef784d47B),
                    TokenType.WITH_RATE
                ),
                paysYieldFees: true
            });
        } else if (token == svZchf) {
            return TokenConfig({
                token: IERC20(token),
                tokenType: TokenType.WITH_RATE,
                rateProvider: _resolveRateProvider(
                    IRateProvider(0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c),
                    TokenType.WITH_RATE
                ),
                paysYieldFees: true
            });
        } else {
            revert();
        }
    }

    function _normalizedWeight(address token, address aumm) private pure returns (uint256) {
        if (token == aumm) {
            return 4e17;
        }
        return 3e17;
    }
}
