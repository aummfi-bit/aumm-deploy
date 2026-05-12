// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    TokenConfig,
    TokenType,
    PoolRoleAccounts,
    SwapKind,
    VaultSwapParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

import { AuMM } from "../../src/token/AuMM.sol";
import { AureumFeeRoutingHook } from "../../src/fee_router/AureumFeeRoutingHook.sol";
import { AureumProtocolFeeController } from "../../src/vault/AureumProtocolFeeController.sol";
import { AureumWeightedPoolFactory } from "../../src/factory/AureumWeightedPoolFactory.sol";
import { DeployAureumVault } from "../../script/DeployAureumVault.s.sol";
import { DeployIxHelvetia } from "../../script/pools/DeployIxHelvetia.s.sol";
import { DeployIxEdelweiss } from "../../script/pools/DeployIxEdelweiss.s.sol";
import { DeployIxAurebit } from "../../script/pools/DeployIxAurebit.s.sol";
import { SwapAndDepositToBodensee } from "../../src/gauge/SwapAndDepositToBodensee.sol";
import { VaultClassRegistry } from "../../src/gauge/VaultClassRegistry.sol";
import { IVaultClassRegistry } from "../../src/gauge/IVaultClassRegistry.sol";
import { GaugeEligibility } from "../../src/gauge/GaugeEligibility.sol";
import { GaugeRegistry } from "../../src/gauge/GaugeRegistry.sol";
import { IEfficiencyOracle } from "../../src/gauge/IEfficiencyOracle.sol";
import { MockTVLOracle } from "./mocks/CCBMocks.sol";
import { MockEfficiencyOracle, MockAuMT } from "./mocks/StageGMocks.sol";

/**
 * @title StageGIntegrationFixture
 * @notice Stage G cross-contract fork-test base wiring `VaultClassRegistry` + `GaugeEligibility` + `GaugeRegistry`
 *         together against real Bodensee + Stage E pilot pools per the **G-D25** family.
 * @dev **F-D11** layout; **F-D26 (a)** mirror of `CCBEngineFixture` without extending `MiliariumPilotPoolBase`; three
 *      pilots (ixHelvetia / ixEdelweiss / ixAurebit); **G-D25a** single-token genesis `[sUSDS] + [ImplementationAddress]`;
 *      **G-D25b** `_makePoolEligible` admission-before-TVL invariant; **G-D25c** mock home at
 *      `test/fork/mocks/StageGMocks.sol`; **F-D20—F23** parallel one-shot setter pattern; **G-D22** `setGaugeRegistry`
 *      deploy order; **D35** split-form invocation; **D36** + **F-D11** `--threads 1` fork-run requirement.
 */
abstract contract StageGIntegrationFixture is Test {
    // Constants — D-D21 / E-D24 parity (CCBEngineFixture mirror per F-D26 (a))
    bytes32 internal constant VAULT_SALT = bytes32(uint256(1));
    bytes32 internal constant BODENSEE_SALT = bytes32(uint256(2));
    uint32 internal constant PAUSE_WINDOW_DURATION = uint32(4 * 365 days);
    uint256 internal constant BUFFER_PERIOD_DURATION = 90 days;
    uint256 internal constant MIN_TRADE_AMOUNT = 1_000_000;
    uint256 internal constant MIN_WRAP_AMOUNT = 1_000;
    string internal constant FACTORY_VERSION = '{"name":"AureumWeightedPoolFactory","version":1,"deployment":"20260512-fork-stage-g"}';
    string internal constant POOL_VERSION = '{"name":"AureumWeightedPool","version":1,"deployment":"20260512-fork-stage-g"}';
    address internal constant GOVERNANCE_MULTISIG = address(uint160(uint256(keccak256("govMultisig"))));
    address internal constant SUSDS_RATE_PROVIDER = 0x1195BE91e78ab25494C855826FF595Eef784d47B;
    address internal constant SV_ZCHF_RATE_PROVIDER = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;
    uint256 internal constant INIT_SEED = 1_000e18;

    // State — Vault scaffold
    DeployAureumVault internal vaultScript;
    WeightedPoolFactory internal wpf;
    AureumWeightedPoolFactory internal awpf;
    AuMM internal aumm;
    AureumFeeRoutingHook internal hook;
    AureumProtocolFeeController internal controller;
    IVault internal vault;
    address internal bodenseePool;
    IERC20 internal svZchf;
    IERC4626 internal susds;

    // State — Pilot pools (order: ixHelvetia[0] / ixEdelweiss[1] / ixAurebit[2])
    /// @notice ixHelvetia (slot 01), ixEdelweiss (slot 05), ixAurebit (slot 14).
    address[3] internal pilotPools;

    // State — Stage G contracts
    SwapAndDepositToBodensee internal swapAndDeposit;
    VaultClassRegistry internal vaultClassRegistry;
    GaugeEligibility internal gaugeEligibility;
    GaugeRegistry internal gaugeRegistry;

    // State — Mocks (TVL from CCBMocks per OQ-22 carry-forward; Efficiency + AuMT from StageGMocks per G-D25c)
    MockTVLOracle internal mockTVLOracle;
    MockEfficiencyOracle internal mockEfficiencyOracle;
    MockAuMT internal mockAuMT;

    function setUp() public virtual {
        // Body lands at G4.0b — full deploy chain + one-shot setter wiring per F-D20—F23 + G-D22.
    }

    // Bodensee helpers — parity with test/fork/AureumFeeRoutingHook.t.sol
    function _bodenseeTokenConfigs() private view returns (TokenConfig[] memory) {
        address t0 = address(aumm);
        address t1 = address(susds);
        address t2 = address(svZchf);
        if (t0 > t1) (t0, t1) = (t1, t0);
        if (t1 > t2) (t1, t2) = (t2, t1);
        if (t0 > t1) (t0, t1) = (t1, t0);

        TokenConfig[] memory tokens = new TokenConfig[](3);
        tokens[0] = t0 == address(aumm)
            ? TokenConfig({
                token: IERC20(t0),
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            })
            : t0 == address(susds)
                ? TokenConfig({
                    token: IERC20(t0),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SUSDS_RATE_PROVIDER),
                    paysYieldFees: true
                })
                : TokenConfig({
                    token: IERC20(t0),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SV_ZCHF_RATE_PROVIDER),
                    paysYieldFees: true
                });
        tokens[1] = t1 == address(aumm)
            ? TokenConfig({
                token: IERC20(t1),
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            })
            : t1 == address(susds)
                ? TokenConfig({
                    token: IERC20(t1),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SUSDS_RATE_PROVIDER),
                    paysYieldFees: true
                })
                : TokenConfig({
                    token: IERC20(t1),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SV_ZCHF_RATE_PROVIDER),
                    paysYieldFees: true
                });
        tokens[2] = t2 == address(aumm)
            ? TokenConfig({
                token: IERC20(t2),
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            })
            : t2 == address(susds)
                ? TokenConfig({
                    token: IERC20(t2),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SUSDS_RATE_PROVIDER),
                    paysYieldFees: true
                })
                : TokenConfig({
                    token: IERC20(t2),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SV_ZCHF_RATE_PROVIDER),
                    paysYieldFees: true
                });
        return tokens;
    }

    function _bodenseeWeights() private view returns (uint256[] memory) {
        address t0 = address(aumm);
        address t1 = address(susds);
        address t2 = address(svZchf);
        if (t0 > t1) (t0, t1) = (t1, t0);
        if (t1 > t2) (t1, t2) = (t2, t1);
        if (t0 > t1) (t0, t1) = (t1, t0);

        uint256[] memory weights = new uint256[](3);
        weights[0] = t0 == address(aumm) ? 4e17 : 3e17;
        weights[1] = t1 == address(aumm) ? 4e17 : 3e17;
        weights[2] = t2 == address(aumm) ? 4e17 : 3e17;
        return weights;
    }

    function _initializeBodensee() private returns (uint256 bptOut) {
        deal(address(aumm), address(this), INIT_SEED, true);
        deal(address(susds), address(this), INIT_SEED, true);
        deal(address(svZchf), address(this), INIT_SEED, true);

        bytes memory result = vault.unlock(abi.encodeCall(this._initializeBodenseeCallback, ()));
        bptOut = abi.decode(result, (uint256));
    }

    function _initializeBodenseeCallback() external returns (uint256 bptOut) {
        require(msg.sender == address(vault), "onlyVault");
        address t0 = address(aumm);
        address t1 = address(susds);
        address t2 = address(svZchf);
        if (t0 > t1) (t0, t1) = (t1, t0);
        if (t1 > t2) (t1, t2) = (t2, t1);
        if (t0 > t1) (t0, t1) = (t1, t0);

        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = IERC20(t0);
        tokens[1] = IERC20(t1);
        tokens[2] = IERC20(t2);
        uint256[] memory amountsIn = new uint256[](3);
        amountsIn[0] = INIT_SEED;
        amountsIn[1] = INIT_SEED;
        amountsIn[2] = INIT_SEED;

        bptOut = vault.initialize(bodenseePool, address(this), tokens, amountsIn, 0, "");
        for (uint256 i = 0; i <= 2; ++i) {
            tokens[i].transfer(address(vault), amountsIn[i]);
            vault.settle(tokens[i], amountsIn[i]);
        }
    }

    // Pilot pool β-pattern helpers — generalized from D7 fork test
    function _initializePool(address pool, IERC20[] memory tokens, uint256[] memory amountsIn)
        internal
        returns (uint256 bptOut)
    {
        for (uint256 i = 0; i < tokens.length; ++i) {
            deal(address(tokens[i]), address(this), amountsIn[i]);
        }
        bytes memory result = vault.unlock(abi.encodeCall(this._initializePoolCallback, (pool, tokens, amountsIn)));
        bptOut = abi.decode(result, (uint256));
    }

    function _initializePoolCallback(address pool, IERC20[] memory tokens, uint256[] memory amountsIn)
        external
        returns (uint256 bptOut)
    {
        require(msg.sender == address(vault), "onlyVault");
        bptOut = vault.initialize(pool, address(this), tokens, amountsIn, 0, "");
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokens[i].transfer(address(vault), amountsIn[i]);
            vault.settle(tokens[i], amountsIn[i]);
        }
    }
}
