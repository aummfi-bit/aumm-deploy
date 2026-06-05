// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { StageGIntegrationFixture } from "./StageGIntegration.t.sol";
import { MockMiliariumRegistry } from "./mocks/CCBMocks.sol";
import { IAuMM } from "../../src/token/IAuMM.sol";
import { EMASampler } from "../../src/ccb/EMASampler.sol";
import { IEMASampler } from "../../src/ccb/IEMASampler.sol";
import { CCBMultiplier } from "../../src/ccb/CCBMultiplier.sol";
import { ICCBMultiplier } from "../../src/ccb/ICCBMultiplier.sol";
import { AureumTime } from "../../src/lib/AureumTime.sol";
import { TVLOracle } from "../../src/emission/TVLOracle.sol";
import { EfficiencyOracle } from "../../src/emission/EfficiencyOracle.sol";
import { BodenseeBootstrapChannel } from "../../src/emission/BodenseeBootstrapChannel.sol";
import { IBodenseeBootstrapChannel } from "../../src/emission/IBodenseeBootstrapChannel.sol";
import { EmissionDistributor } from "../../src/emission/EmissionDistributor.sol";
import { IEmissionDistributor } from "../../src/emission/IEmissionDistributor.sol";
import { AddLiquidityParams, AddLiquidityKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

/**
 * @title StageIIntegrationFixture
 * @notice Stage I recorder-clock fork-test base — wires the I4 effectiveQualBlock clock + AureumFeeRoutingHook liquidity dispatch against real Bodensee + the 3 Stage E pilots.
 * @dev Inherits StageGIntegrationFixture (vault + factory + AuMM + Bodensee + pilots + hook + GaugeRegistry). Deploys its OWN emission stack mirroring StageHIntegrationFixture, but binds the per-pool recorder gate to the canonical AureumFeeRoutingHook (address(hook), NOT the test contract) and sets the hook one-shot emissionRecorder to this distributor, so real Balancer V3 add / remove-liquidity routes onAfterAddLiquidity / onAfterRemoveLiquidity into recordDeposit / recordWithdrawal. Does NOT inherit StageHIntegrationFixture: StageH one-shot-binds the pilots to address(this) (H6.3) and its EfficiencyOracle emissions-recorder handoff is one-shot, so the StageH distributor cannot be re-pointed at the hook — I6.1 deploys a fresh stack instead (user-chosen Option B). No AuMT token deploys (AuMT = BPT per I-D14). aumm.setMinter is NOT required — recordDeposit / recordWithdrawal do not mint (only claim mints, untested here). Anchors: I-D9 (recorder gate), I-D14 (clock), I-D16 (hook emissionRecorder one-shot), H13 (fixture-inheritance precedent).
 */
abstract contract StageIIntegrationFixture is StageGIntegrationFixture {
    TVLOracle internal tvlOracle;
    EMASampler internal emaSampler;
    CCBMultiplier internal ccbMultiplier;
    EfficiencyOracle internal efficiencyOracle;
    BodenseeBootstrapChannel internal bootstrapChannel;
    EmissionDistributor internal emissionDistributor;
    MockMiliariumRegistry internal miliariumRegistry;

    function setUp() public virtual override {
        super.setUp();

        address[3] memory miliariumPools;
        miliariumPools[0] = pilotPools[0];
        miliariumPools[1] = pilotPools[1];
        miliariumPools[2] = pilotPools[2];
        miliariumRegistry = new MockMiliariumRegistry(miliariumPools);

        tvlOracle = new TVLOracle(
            IVaultExplorer(address(vault)),
            bodenseePool,
            address(svZchf),
            address(this),
            new address[](0),
            new address[](0)
        );

        emaSampler = new EMASampler(tvlOracle);

        ccbMultiplier = new CCBMultiplier(miliariumRegistry, gaugeRegistry, IEMASampler(address(emaSampler)));

        efficiencyOracle = new EfficiencyOracle(
            tvlOracle,
            address(aumm),
            aumm.GENESIS_BLOCK(),
            address(this)
        );

        bootstrapChannel = new BodenseeBootstrapChannel(
            vault,
            bodenseePool,
            IAuMM(address(aumm)),
            aumm.GENESIS_BLOCK(),
            address(this)
        );

        emissionDistributor = new EmissionDistributor(
            IAuMM(address(aumm)),
            gaugeRegistry,
            IEMASampler(address(emaSampler)),
            ICCBMultiplier(address(ccbMultiplier)),
            efficiencyOracle,
            miliariumRegistry,
            aumm.GENESIS_BLOCK(),
            address(this)
        );

        efficiencyOracle.setEmissionsRecorder(address(emissionDistributor)); // H-D23 — distributor pushes recordEmissions; oracle must whitelist
        vm.prank(GOVERNANCE_MULTISIG); // hook moduleAdmin_ per StageG hook ctor — authorises the one-shot setEmissionRecorder
        hook.setEmissionRecorder(address(emissionDistributor)); // I-D16 one-shot — hook dispatches recordDeposit/recordWithdrawal here
        emissionDistributor.setAuMTContractForPool(pilotPools[0], address(hook)); // I-D9 amend — recorder gate admits the hook as msg.sender
        emissionDistributor.setAuMTContractForPool(pilotPools[1], address(hook));
        emissionDistributor.setAuMTContractForPool(pilotPools[2], address(hook));

        // setMinter not wired — I6 recorder-clock tests exercise recordDeposit/recordWithdrawal only (no mint path).
    }

    // -------------------------------------------------------------------------
    // I6 recorder-clock helpers — real add-liquidity through the hook
    // -------------------------------------------------------------------------

    /// @dev Recorded LP for the next liquidity op. The hook resolves the LP via
    ///      IRouterSender(router).getSender(); this fixture IS the router (it
    ///      calls Vault.addLiquidity directly inside unlock), so getSender()
    ///      returns _lpSender. Decoupled from the BPT recipient (address(this)).
    address internal _lpSender;

    /// @notice IRouterSender shim — the hook calls this on every add/remove.
    function getSender() external view returns (address) {
        return _lpSender;
    }

    /// @dev One-sided UNBALANCED add of `fractionBps`/10000 of token[0]'s current
    ///      pool balance, recording the deposit for `lp`. Mirrors StageG
    ///      _initializePool (deal -> unlock -> settle) with addLiquidity in place
    ///      of initialize.
    function _depositOneSided(address pool, address lp, uint256 fractionBps)
        internal
        returns (uint256 bptOut)
    {
        _lpSender = lp;
        IERC20[] memory tokens = vault.getPoolTokens(pool);
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(pool);
        uint256[] memory amountsIn = new uint256[](tokens.length);
        amountsIn[0] = (balancesRaw[0] * fractionBps) / 10_000;
        deal(address(tokens[0]), address(this), amountsIn[0]);
        bytes memory result = vault.unlock(abi.encodeCall(this._depositCallback, (pool, amountsIn)));
        bptOut = abi.decode(result, (uint256));
    }

    function _depositCallback(address pool, uint256[] memory amountsIn)
        external
        returns (uint256 bptOut)
    {
        require(msg.sender == address(vault), "onlyVault");
        IERC20[] memory tokens = vault.getPoolTokens(pool);
        (, bptOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: amountsIn,
                minBptAmountOut: 0,
                kind: AddLiquidityKind.UNBALANCED,
                userData: ""
            })
        );
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (amountsIn[i] > 0) {
                tokens[i].transfer(address(vault), amountsIn[i]);
                vault.settle(tokens[i], amountsIn[i]);
            }
        }
    }
}

contract StageIWiringTest is StageIIntegrationFixture {
    function test_recorderGateAndHookRecorderBound() public view {
        assertEq(emissionDistributor.auMTContractByPool(pilotPools[0]), address(hook));
        assertEq(emissionDistributor.auMTContractByPool(pilotPools[1]), address(hook));
        assertEq(emissionDistributor.auMTContractByPool(pilotPools[2]), address(hook));
        assertEq(hook.emissionRecorder(), address(emissionDistributor));
    }
}

contract StageIDepositTest is StageIIntegrationFixture {
    function test_deposit_dispatchSetsClockAndUserLPPerPool() public {
        address[3] memory lps;
        lps[0] = makeAddr("lpA");
        lps[1] = makeAddr("lpB");
        lps[2] = makeAddr("lpC");
        uint256 atBlock = block.number;
        for (uint256 i = 0; i < 3; ++i) {
            uint256 bptOut = _depositOneSided(pilotPools[i], lps[i], 100); // 1% one-sided add
            assertGt(bptOut, 0, "no BPT minted");
            assertEq(emissionDistributor.effectiveQualBlock(pilotPools[i], lps[i]), atBlock, "clock not fresh-started");
            assertEq(emissionDistributor.userLP(pilotPools[i], lps[i]), bptOut, "userLP not accrued");
        }
        // Per-pool isolation — each LP only deposited to its own pool.
        assertEq(emissionDistributor.effectiveQualBlock(pilotPools[1], lps[0]), 0, "lpA leaked to pool 1");
        assertEq(emissionDistributor.effectiveQualBlock(pilotPools[0], lps[1]), 0, "lpB leaked to pool 0");
    }
}
