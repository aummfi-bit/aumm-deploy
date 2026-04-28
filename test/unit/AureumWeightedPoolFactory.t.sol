// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    TokenConfig,
    TokenType,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";

import { AureumWeightedPoolFactory } from "../../src/factory/AureumWeightedPoolFactory.sol";

/**
 * @title AureumWeightedPoolFactoryTest
 * @notice Unit tests for the factory's deterministic revert paths — the 52% ERC-4626 Quality Gate
 *         (`QualityGateUnsatisfied`), the array-length check (`WeightsLengthMismatch`), and the
 *         inherited `StandardPoolWithCreator` guard. Each test reverts before `_create` /
 *         `_registerPoolWithVault`, so a mock Vault address suffices — no fork required.
 *         Per `docs/STAGE_E_PLAN.md` E-D9 (E4 sub-step layout) and `docs/STAGE_E_NOTES.md` E-D13
 *         (QG predicate `WITH_RATE && rateProvider != address(0)`); boundary-case (52% exactly)
 *         coverage is provided implicitly by the ixAurebit fork test.
 */
contract AureumWeightedPoolFactoryTest is Test {
    AureumWeightedPoolFactory internal factory;

    address internal mockVault;
    address internal mockRateProvider;
    address internal hookContract;

    string internal constant FACTORY_VERSION =
        '{"name":"AureumWeightedPoolFactory","version":1,"deployment":"unit"}';
    string internal constant POOL_VERSION =
        '{"name":"WeightedPool","version":1,"deployment":"unit"}';
    uint32 internal constant PAUSE_WINDOW_DURATION = 365 days;
    uint256 internal constant DEFAULT_SWAP_FEE = 0.003e18;

    function setUp() public {
        mockVault = makeAddr("mockVault");
        mockRateProvider = makeAddr("mockRateProvider");
        hookContract = makeAddr("hookContract");

        factory = new AureumWeightedPoolFactory(
            IVault(mockVault),
            PAUSE_WINDOW_DURATION,
            FACTORY_VERSION,
            POOL_VERSION
        );
    }

    // ─── Test 1: all STANDARD tokens — QG sum = 0 ─────────────────────────────
    function test_RevertWhen_QGSubFiftyTwo_NoERC4626Tokens() public {
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0] = TokenConfig({
            token: IERC20(makeAddr("tokenA")),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });
        tokens[1] = TokenConfig({
            token: IERC20(makeAddr("tokenB")),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });

        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;

        vm.expectRevert(
            abi.encodeWithSelector(
                AureumWeightedPoolFactory.QualityGateUnsatisfied.selector,
                uint256(0),
                uint256(52e16)
            )
        );
        factory.create(
            "TestPool",
            "TEST",
            tokens,
            weights,
            _emptyRoles(),
            DEFAULT_SWAP_FEE,
            hookContract,
            false,
            false,
            bytes32(uint256(1))
        );
    }

    // ─── Test 2: partial ERC-4626 — QG sum = 40e16 ────────────────────────────
    function test_RevertWhen_QGSubFiftyTwo_PartialERC4626() public {
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0] = TokenConfig({
            token: IERC20(makeAddr("tokenA")),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });
        tokens[1] = TokenConfig({
            token: IERC20(makeAddr("tokenB")),
            tokenType: TokenType.WITH_RATE,
            rateProvider: IRateProvider(mockRateProvider),
            paysYieldFees: true
        });

        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.6e18;
        weights[1] = 0.4e18;

        vm.expectRevert(
            abi.encodeWithSelector(
                AureumWeightedPoolFactory.QualityGateUnsatisfied.selector,
                uint256(0.4e18),
                uint256(52e16)
            )
        );
        factory.create(
            "TestPool",
            "TEST",
            tokens,
            weights,
            _emptyRoles(),
            DEFAULT_SWAP_FEE,
            hookContract,
            false,
            false,
            bytes32(uint256(2))
        );
    }

    // ─── Test 3: STANDARD-with-RP excluded from QG sum (E-D13 predicate regression) ───
    function test_RevertWhen_QGSubFiftyTwo_StandardWithRPExcluded() public {
        // Three tokens summing to 1e18:
        //   index 0 — 51% STANDARD with non-zero RP (must NOT contribute to QG sum)
        //   index 1 — 11% STANDARD no RP (does not contribute)
        //   index 2 — 38% WITH_RATE+RP (contributes)
        // Correct QG sum = 38e16 < 52e16 → revert. A wrong predicate that counted "any
        // non-zero RP" would inflate the sum to 89e16 and the gate would falsely clear.
        TokenConfig[] memory tokens = new TokenConfig[](3);
        tokens[0] = TokenConfig({
            token: IERC20(makeAddr("tokenA_standardWithRP")),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(mockRateProvider),
            paysYieldFees: false
        });
        tokens[1] = TokenConfig({
            token: IERC20(makeAddr("tokenB_standardNoRP")),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });
        tokens[2] = TokenConfig({
            token: IERC20(makeAddr("tokenC_withRateRP")),
            tokenType: TokenType.WITH_RATE,
            rateProvider: IRateProvider(mockRateProvider),
            paysYieldFees: true
        });

        uint256[] memory weights = new uint256[](3);
        weights[0] = 0.51e18;
        weights[1] = 0.11e18;
        weights[2] = 0.38e18;

        vm.expectRevert(
            abi.encodeWithSelector(
                AureumWeightedPoolFactory.QualityGateUnsatisfied.selector,
                uint256(0.38e18),
                uint256(52e16)
            )
        );
        factory.create(
            "TestPool",
            "TEST",
            tokens,
            weights,
            _emptyRoles(),
            DEFAULT_SWAP_FEE,
            hookContract,
            false,
            false,
            bytes32(uint256(3))
        );
    }

    // ─── Test 4: tokens.length != normalizedWeights.length ────────────────────
    function test_RevertWhen_WeightsLengthMismatch() public {
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0] = TokenConfig({
            token: IERC20(makeAddr("tokenA")),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });
        tokens[1] = TokenConfig({
            token: IERC20(makeAddr("tokenB")),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });

        uint256[] memory weights = new uint256[](3);
        weights[0] = 0.5e18;
        weights[1] = 0.3e18;
        weights[2] = 0.2e18;

        vm.expectRevert(
            abi.encodeWithSelector(
                AureumWeightedPoolFactory.WeightsLengthMismatch.selector,
                uint256(2),
                uint256(3)
            )
        );
        factory.create(
            "TestPool",
            "TEST",
            tokens,
            weights,
            _emptyRoles(),
            DEFAULT_SWAP_FEE,
            hookContract,
            false,
            false,
            bytes32(uint256(4))
        );
    }

    // ─── Test 5: poolCreator non-zero — inherited StandardPoolWithCreator ─────
    function test_RevertWhen_PoolCreatorNotZero() public {
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0] = TokenConfig({
            token: IERC20(makeAddr("tokenA")),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });
        tokens[1] = TokenConfig({
            token: IERC20(makeAddr("tokenB")),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });

        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;

        PoolRoleAccounts memory roles = PoolRoleAccounts({
            pauseManager: address(0),
            swapFeeManager: address(0),
            poolCreator: makeAddr("creator")
        });

        vm.expectRevert(BasePoolFactory.StandardPoolWithCreator.selector);
        factory.create(
            "TestPool",
            "TEST",
            tokens,
            weights,
            roles,
            DEFAULT_SWAP_FEE,
            hookContract,
            false,
            false,
            bytes32(uint256(5))
        );
    }

    // ─── Helper: PoolRoleAccounts with all zero addresses ─────────────────────
    function _emptyRoles() internal pure returns (PoolRoleAccounts memory) {
        return PoolRoleAccounts({
            pauseManager: address(0),
            swapFeeManager: address(0),
            poolCreator: address(0)
        });
    }
}
