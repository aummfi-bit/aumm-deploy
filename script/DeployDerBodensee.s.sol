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
 */
contract DeployDerBodensee is Script {
    function run() external returns (address pool) {
        address weightedPoolFactory = vm.envAddress("WEIGHTED_POOL_FACTORY");
        address aumm = vm.envAddress("AUMM");
        address svZchf = vm.envAddress("SV_ZCHF");
        address sUsds = vm.envAddress("SUSDS");
        address governanceMultisig = vm.envAddress("GOVERNANCE_MULTISIG");
        bytes32 bodenseeSalt = vm.envBytes32("BODENSEE_SALT");

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

        PoolRoleAccounts memory roleAccounts = PoolRoleAccounts({
            pauseManager: governanceMultisig,
            swapFeeManager: governanceMultisig,
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
            false,
            false,
            bodenseeSalt
        );
        vm.stopBroadcast();

        console2.log("der-Bodensee pool deployed at:", pool);
    }

    function _tokenConfig(
        address token,
        address aumm,
        address sUsds,
        address svZchf
    ) private pure returns (TokenConfig memory) {
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
                rateProvider: IRateProvider(0x1195BE91e78ab25494C855826FF595Eef784d47B),
                paysYieldFees: true
            });
        } else if (token == svZchf) {
            return TokenConfig({
                token: IERC20(token),
                tokenType: TokenType.WITH_RATE,
                rateProvider: IRateProvider(0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c),
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
