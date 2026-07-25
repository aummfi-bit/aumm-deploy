// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, TokenType, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

import { AuMM } from "../../src/token/AuMM.sol";
import { AureumFeeRoutingHook } from "../../src/fee_router/AureumFeeRoutingHook.sol";
import { AureumProtocolFeeController } from "../../src/vault/AureumProtocolFeeController.sol";
import { AureumWeightedPoolFactory } from "../../src/factory/AureumWeightedPoolFactory.sol";

import { DeployTestnetStubs } from "../../test-stubs/DeployTestnetStubs.s.sol";
import { DeployAureumVault } from "../../script/DeployAureumVault.s.sol";
import { DeployStageP } from "../../script/DeployStageP.s.sol";
import { DeployFeeRoutingHook } from "../../script/DeployFeeRoutingHook.s.sol";
import { DeployAuMM } from "../../script/DeployAuMM.s.sol";
import { DeployAureumWeightedPoolFactory } from "../../script/DeployAureumWeightedPoolFactory.s.sol";
import { DeployIxHelvetia } from "../../script/pools/DeployIxHelvetia.s.sol";
import { DeployIxEdelweiss } from "../../script/pools/DeployIxEdelweiss.s.sol";
import { DeployIxAurebit } from "../../script/pools/DeployIxAurebit.s.sol";
import { DeployIxCasper } from "../../script/pools/DeployIxCasper.s.sol";
import { DeployIxBrevis } from "../../script/pools/DeployIxBrevis.s.sol";
import { DeployIxAltrix } from "../../script/pools/DeployIxAltrix.s.sol";
import { DeployIxMediox } from "../../script/pools/DeployIxMediox.s.sol";
import { DeployIxLongus } from "../../script/pools/DeployIxLongus.s.sol";
import { DeployIxAetheron } from "../../script/pools/DeployIxAetheron.s.sol";
import { DeployIxLibertas } from "../../script/pools/DeployIxLibertas.s.sol";
import { DeployIxStrata } from "../../script/pools/DeployIxStrata.s.sol";
import { DeployIxForum } from "../../script/pools/DeployIxForum.s.sol";
import { DeployIxRegistrum } from "../../script/pools/DeployIxRegistrum.s.sol";
import { DeployIxDebitum } from "../../script/pools/DeployIxDebitum.s.sol";
import { DeployIxEquitix } from "../../script/pools/DeployIxEquitix.s.sol";
import { DeployIxInnovix } from "../../script/pools/DeployIxInnovix.s.sol";
import { DeployIxGigantus } from "../../script/pools/DeployIxGigantus.s.sol";
import { DeployIxMagnix } from "../../script/pools/DeployIxMagnix.s.sol";
import { DeployIxNubix } from "../../script/pools/DeployIxNubix.s.sol";
import { DeployIxMoneta } from "../../script/pools/DeployIxMoneta.s.sol";
import { DeployIxColossix } from "../../script/pools/DeployIxColossix.s.sol";
import { DeployIxVitalix } from "../../script/pools/DeployIxVitalix.s.sol";
import { DeployIxMedicix } from "../../script/pools/DeployIxMedicix.s.sol";
import { DeployIxMercatura } from "../../script/pools/DeployIxMercatura.s.sol";
import { DeployIxAurix } from "../../script/pools/DeployIxAurix.s.sol";
import { DeployIxMetallum } from "../../script/pools/DeployIxMetallum.s.sol";

/**
 * @title  StagePRunRehearsalTest
 * @notice PB3.4d2 (PB-D25) — the production-`run()` rehearsal on a mainnet fork at future genesis.
 *         A standalone harness (NOT a StagePIntegrationFixture subclass, per PB-D25 (b) — the P10
 *         close gate stays byte-identical): setUp deploys the base layer with a real-EOA governor and
 *         a full stub roster replayed in-process from DeployTestnetStubs, at GENESIS_BLOCK = fork
 *         block + one epoch, then drives the composed DeployStageP.run() (the production spine, not
 *         deploy()). The test body re-asserts the four post-conditions (d2c) and the Router seat (d2d).
 * @dev    Run file-scoped per D35/D36: forge test match-path on this file, fork-url mainnet, threads 1.
 */
contract StagePRunRehearsalTest is Test {
    bytes32 internal constant VAULT_SALT = bytes32(uint256(1));
    bytes32 internal constant BODENSEE_SALT = bytes32(uint256(2));
    uint32 internal constant PAUSE_WINDOW_DURATION = uint32(4 * 365 days);
    uint256 internal constant BUFFER_PERIOD_DURATION = 90 days;
    uint256 internal constant MIN_TRADE_AMOUNT = 1_000_000;
    uint256 internal constant MIN_WRAP_AMOUNT = 1_000;
    string internal constant FACTORY_VERSION = '{"name":"AureumWeightedPoolFactory","version":1,"deployment":"20260718-fork-rehearsal"}';
    string internal constant POOL_VERSION = '{"name":"AureumWeightedPool","version":1,"deployment":"20260718-fork-rehearsal"}';
    // The real mainnet susds / svZchf RP literals — used only as the STUB_ lookup keys for the bodensee stub RPs.
    address internal constant SUSDS_RATE_PROVIDER = 0x1195BE91e78ab25494C855826FF595Eef784d47B;
    address internal constant SV_ZCHF_RATE_PROVIDER = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;
    uint256 internal constant INIT_SEED = 1_000e18;
    address internal constant EMERGENCY_MULTISIG = address(uint160(uint256(keccak256("emergencyMultisig"))));
    // PB-D25 (a) — the real-EOA governor, distinct from the harness and the orchestrator.
    address internal constant GOVERNOR = address(uint160(uint256(keccak256("rehearsalGovernorEOA"))));
    // PB-D19 — one epoch (14 days) of block offset; the emission clock decouples from deploy time.
    uint256 internal constant GENESIS_OFFSET = 100_800;

    DeployStageP internal orchestrator;
    DeployFeeRoutingHook internal hookScript;
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
    // Resolved from the STUB_ roster in setUp (the stub RPs for the bodensee stub susds / svZchf).
    IRateProvider internal bodenseeSusdsRp;
    IRateProvider internal bodenseeSvZchfRp;
    address[3] internal pilotPools;
    address[5] internal majorPools;
    address[18] internal stageNPools;

    function setUp() public {}
}
