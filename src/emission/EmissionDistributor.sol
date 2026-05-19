// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {FixedPoint} from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import {IEmissionDistributor} from "./IEmissionDistributor.sol";
import {IAuMM} from "../token/IAuMM.sol";
import {IGaugeRegistry} from "../ccb/IGaugeRegistry.sol";
import {IEMASampler} from "../ccb/IEMASampler.sol";
import {ICCBMultiplier} from "../ccb/ICCBMultiplier.sol";
import {IEfficiencyOracle} from "../gauge/IEfficiencyOracle.sol";
import {CCBScore} from "../ccb/CCBScore.sol";

/// @title EmissionDistributor — Aureum Stage H pool-scoped emission distributor per H-D4—H-D5 + H-D15—H-D23
/// @notice Two-tier MasterChef / Synthetix accumulator topology: global `accRewardPerScoreUnit` plus per-pool `poolAccDebt` lazy-settle per H-D15. Permissionless `recordScore(pool)` writes the F-5 absolute score per H-D17 with F12 signed-delta `totalScore` middleware per H-D19. AuMT recorder (Stage I) drives `recordDeposit` / `recordWithdrawal`; user-facing `claim(pool, to)` is the sole `IAuMM.mint` entry per H-D20.
/// @dev H-D22 — two-tier storage (global + per-pool + per-user) + immutables, no transient storage (no Vault.unlock callback at H4). H-D15 — `_accrueGlobal` advances accRewardPerScoreUnit, `_settlePool` rebases poolAccDebt; F-10 `recordEmissions` push at the `_settlePool` boundary per H-D23 (allocation-side semantics, not literal-mint). H-D17 — score producer reverts `NotApproved(pool)` on revoked gauges. H-D21 — `_lpTrancheEmission(block_)` ships at H4 as a STUB returning `IAuMM.blockEmissionRate(block_)`; H5 wires F-0 / F-3 / F-7 phase-aware subtractions. H-D16 — per-user maps + `auMTContract` recorder slot (zero-address-acceptable safety valve mirroring EfficiencyOracle's H-D10 pattern). Deploy prerequisite per H-D7 (OPEN, locks at H10): `IAuMM.setMinter(address(this))` must fire before any `claim(...)` call hits `IAuMM.mint`. No `selfdestruct` / `pause` per H-D21 closing record.
abstract contract EmissionDistributor is IEmissionDistributor {
    using SafeCast for uint256;
    using SafeCast for int256;
    using FixedPoint for uint256;

    /* ---------- Immutables (H-D22) ---------- */

    /// @notice AuMM token — mint recipient at `claim` per H-D20; consumed for `blockEmissionRate(block_)` reads in `_lpTrancheEmission` per H-D21.
    IAuMM public immutable AuMM;

    /// @notice Stage G GaugeRegistry — gates `recordScore` via `isGaugeApproved(pool)` per H-D5 / H-D17 (a).
    IGaugeRegistry public immutable _gaugeRegistry;

    /// @notice Stage F EMASampler — read-only TVL_EMA source for F-5 score per H-D17 (c); never invokes `updateEMA` (F-D22 write/read separation).
    IEMASampler public immutable _emaSampler;

    /// @notice Stage F CCBMultiplier — read-only CCB_mult source for F-5 score per H-D17 (c); OQ-23 `1e18` default for non-Miliarium pools.
    ICCBMultiplier public immutable _ccbMultiplier;

    /// @notice Stage H EfficiencyOracle — `recordEmissions(pool, allocation)` push target at `_settlePool` per H-D23 (allocation-side F-10 semantics); push signature extended in-place at H4.1.x-bis.
    IEfficiencyOracle public immutable _efficiencyOracle;

    /// @notice Stage H genesis block — anchors halving math via `IAuMM.blockEmissionRate(block_)` per H-D21; same constructor-parameter precedent as `BodenseeBootstrapChannel` L36.
    uint256 public immutable GENESIS_BLOCK;

    /* ---------- Global accumulator (H-D15) ---------- */

    /// @notice Global FixedPoint 18-decimal accumulator per H-D15 — `accRewardPerScoreUnit += (rate * Δblocks).divDown(totalScore)` advances at `_accrueGlobal`.
    uint256 public override accRewardPerScoreUnit;

    /// @notice Sum of `poolScore` over approved gauges per H-D15 — mutated only through the H-D19 F12 signed-delta middleware (no other write surface).
    uint256 public override totalScore;

    /// @notice Most recent `_accrueGlobal` block per H-D21 — empty-interval short-circuit when `block.number == lastAccrualBlock`.
    uint256 public override lastAccrualBlock;

    /* ---------- Per-pool state (H-D22) ---------- */

    /// @notice Per-pool F-5 absolute score per H-D17 / H-D22 — written by `recordScore(pool)` as `CCBScore.score(tvlEMA, multiplier)`.
    mapping(address => uint256) public override poolScore;

    /// @notice Per-pool snapshot of `accRewardPerScoreUnit` at last `_settlePool` per H-D15 — write-only at `_settlePool` after the H-D23 `recordEmissions` push.
    mapping(address => uint256) public override poolAccDebt;

    /// @notice Σ `userLP[pool][*]` per H-D22 — needed for per-user share computation at settle time.
    mapping(address => uint256) public override poolTotalLP;

    /* ---------- Per-user state (H-D16 / H-D22) ---------- */

    /// @notice Per-user AuMT stake in pool per H-D16 — mutated by `recordDeposit` / `recordWithdrawal` (gated on `auMTContract`).
    mapping(address => mapping(address => uint256)) public override userLP;

    /// @notice Per-user single-snapshot variant analogous to `poolAccDebt` per H-D16 — computed against pool-effective acc-per-LP-unit at settle time.
    mapping(address => mapping(address => uint256)) public override userRewardDebt;

    /* ---------- Governance + recorder slots (H-D14 / H-D16) ---------- */

    /// @notice Mutable governance authority per H-D14 — Stage A—K Authorizer Safe at deploy; rebound via `setGovernanceContract` at Stage K (mirrors TVLOracle / EfficiencyOracle / BodenseeBootstrapChannel governance-slot pattern).
    address public override governance;

    /// @notice Mutable AuMT recorder authority per H-D16 — `address(0)` pre-Stage-I and as deprecation safety valve (mirrors EfficiencyOracle's H-D10 recorder slots). Gates `recordDeposit` / `recordWithdrawal` via `onlyAuMTContract` modifier (lands at H4.5).
    address public override auMTContract;

    /* ---------- Constructor ---------- */

    /**
     * @notice Wires the 6 core immutables + initial governance slot and anchors `lastAccrualBlock` for the H-D22 EmissionDistributor.
     * @dev ZeroAddress guards apply to the 6 address-bearing params; `genesisBlock_` accepts any `uint256` value (deploy-time correctness is governance's responsibility — same pattern as `BodenseeBootstrapChannel` / `EfficiencyOracle`). `lastAccrualBlock` initialized to `genesisBlock_` per H-D21 so the first `_accrueGlobal()` call computes from block `genesisBlock_ + 1` when `totalScore > 0` (otherwise the H-D15 empty-`totalScore` guard short-circuits and resets `lastAccrualBlock` to `block.number`). `auMTContract` defaults to `address(0)` per H-D16 pre-Stage-I posture — `recordDeposit` / `recordWithdrawal` revert `NotAuMTContract(msg.sender)` until governance calls `setAuMTContract` post-deploy with the Stage I AuMT producer (lands at H4.4). Deploy prerequisite per H-D7 (OPEN, locks at H10): `IAuMM.setMinter(address(this))` must fire before any `claim(...)` invocation. Deploy prerequisite per H-D23: `_efficiencyOracle.setEmissionsRecorder(address(this))` must be called by EfficiencyOracle governance before the first `recordScore(pool)` settle pushes; pre-handoff calls revert from `onlyEmissionsRecorder` — distributor does not catch (deploy correctness is governance's responsibility). No constructor emit for `GovernanceTransferred` — mirrors TVLOracle / EfficiencyOracle / BodenseeBootstrapChannel pattern where the initial governance slot is set silently.
     * @param aumm_ AuMM token — mint recipient at `claim` per H-D20; consumed for `blockEmissionRate(block_)` reads in `_lpTrancheEmission` per H-D21. Reverts `ZeroAddress` on zero input.
     * @param gaugeRegistry_ Stage G GaugeRegistry — gates `recordScore` via `isGaugeApproved(pool)` per H-D5 / H-D17 (a). Reverts `ZeroAddress` on zero input.
     * @param emaSampler_ Stage F EMASampler — read-only TVL_EMA source for F-5 score per H-D17 (c); never invokes `updateEMA` (F-D22 write/read separation). Reverts `ZeroAddress` on zero input.
     * @param ccbMultiplier_ Stage F CCBMultiplier — read-only CCB_mult source for F-5 score per H-D17 (c); OQ-23 `1e18` default for non-Miliarium pools. Reverts `ZeroAddress` on zero input.
     * @param efficiencyOracle_ Stage H EfficiencyOracle — `recordEmissions(pool, allocation)` push target at `_settlePool` per H-D23. Reverts `ZeroAddress` on zero input.
     * @param genesisBlock_ Stage H genesis block — anchors halving math via `IAuMM.blockEmissionRate(block_)` per H-D21; also seeds `lastAccrualBlock`. Same precedent as `BodenseeBootstrapChannel` / `EfficiencyOracle` / `AuMM.sol` `GENESIS_BLOCK`; no zero-check (uint256, accepts any value).
     * @param initialGovernance_ Initial governance authority — Stage A—K Authorizer Safe at deploy; rebound at Stage K via `setGovernanceContract` per H-D14. Reverts `ZeroAddress` on zero input.
     */
    constructor(
        IAuMM aumm_,
        IGaugeRegistry gaugeRegistry_,
        IEMASampler emaSampler_,
        ICCBMultiplier ccbMultiplier_,
        IEfficiencyOracle efficiencyOracle_,
        uint256 genesisBlock_,
        address initialGovernance_
    ) {
        if (address(aumm_) == address(0)) revert ZeroAddress();
        if (address(gaugeRegistry_) == address(0)) revert ZeroAddress();
        if (address(emaSampler_) == address(0)) revert ZeroAddress();
        if (address(ccbMultiplier_) == address(0)) revert ZeroAddress();
        if (address(efficiencyOracle_) == address(0)) revert ZeroAddress();
        if (initialGovernance_ == address(0)) revert ZeroAddress();

        AuMM = aumm_;
        _gaugeRegistry = gaugeRegistry_;
        _emaSampler = emaSampler_;
        _ccbMultiplier = ccbMultiplier_;
        _efficiencyOracle = efficiencyOracle_;
        GENESIS_BLOCK = genesisBlock_;
        governance = initialGovernance_;
        lastAccrualBlock = genesisBlock_;
    }

    /* ---------- Modifiers ---------- */

    /// @notice Restricts execution to the current `governance` authority; reverts `NotGovernance(msg.sender)` otherwise.
    /// @dev H-D14 / H-D16 — `setGovernanceContract`-pivoting governance slot; mirrors TVLOracle / EfficiencyOracle / BodenseeBootstrapChannel L145-L150 precedent.
    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance(msg.sender);
        _;
    }

    /* ---------- Governance setters (H-D14 / H-D16) ---------- */

    /**
     * @notice Stage K migration handoff per H-D14 — rebinds the `governance` authority.
     * @dev `onlyGovernance`-gated; reverts `ZeroAddress` on zero input per H-D14 (non-zero recipient is the load-bearing handoff invariant — mint authority via H-D7 `setMinter` cannot route to address(0)); captures `oldGovernance` before overwrite; emits `GovernanceTransferred(oldGovernance, newGovernance)`. Mirrors TVLOracle / EfficiencyOracle / BodenseeBootstrapChannel L159-L164 `setGovernanceContract` precedent.
     * @param newGovernance The new governance authority — typically the on-chain governance contract at the Stage K handoff. Reverts `ZeroAddress` on zero input.
     */
    function setGovernanceContract(address newGovernance) external override onlyGovernance {
        if (newGovernance == address(0)) revert ZeroAddress();
        address oldGovernance = governance;
        governance = newGovernance;
        emit GovernanceTransferred(oldGovernance, newGovernance);
    }

    /**
     * @notice Rebinds the `auMTContract` recorder slot per H-D16 — `onlyGovernance`-gated.
     * @dev Zero address is acceptable per H-D16 deprecation safety valve — mirrors EfficiencyOracle's H-D10 `setEmissionsRecorder` / `setFeeRecorder` recorder-slot pattern where `address(0)` permanently bricks the producer entry (pre-Stage-I posture; `recordDeposit` / `recordWithdrawal` revert `NotAuMTContract(msg.sender)` because `msg.sender` cannot equal zero in external-call contexts, so the gate stays closed). Captures `oldAuMTContract` before overwrite; emits `AuMTContractSet(oldAuMTContract, newAuMTContract)`. The setter does NOT revert `ZeroAddress` (deliberate asymmetry with `setGovernanceContract` per H-D14 / H-D16 + IEmissionDistributor L89-L90 documented contract).
     * @param newAuMTContract The new Stage I AuMT contract address. Zero address permitted as H-D16 deprecation safety valve.
     */
    function setAuMTContract(address newAuMTContract) external override onlyGovernance {
        address oldAuMTContract = auMTContract;
        auMTContract = newAuMTContract;
        emit AuMTContractSet(oldAuMTContract, newAuMTContract);
    }

    /* ---------- Emission rate stub (H-D21) ---------- */

    /**
     * @notice STUB returning the full per-block AuMM emission rate for `block_` per H-D21.
     * @dev H-D21 — H4 ships `_lpTrancheEmission` as a STUB returning `AuMM.blockEmissionRate(block_)` (the full block emission), no F-0 / F-3 / F-7 phase subtractions. Over-accrues vs the true LP tranche until H5 wires phase-aware schedule logic — H5 will (a) subtract the F-0 bodensee share for Months 0—10 (handing the bootstrap leg to `BodenseeBootstrapChannel` per H-D2), (b) apply the F-3 α-blend for Months 11—12 (per H-D6's 1/28 literal for the equal-split leg via `(1 − α(block)) × (1/28) + α(block) × CCB_share`), and (c) subtract the F-7 Step 1 Incendiary skim for Year 2+ (via `IIncendiaryRegistry.activeBoostClaims`, H7 forward-dep stub). The H4 stub posture is intentional test-harness limitation per H-D21 + H-D18 — unit tests exercise the H-D15 accumulator + H-D17 score producer + H-D20 claim math in isolation against the full block emission rate; H5 unit cohort migrates in place. Single read per `_accrueGlobal` call (`_accrueGlobal` invokes `_lpTrancheEmission(block.number)` once after the empty-interval check).
     * @param block_ The block number whose LP tranche emission rate to return.
     * @return The AuMM tokens-per-block emission rate at `block_` (18-decimal wei scale).
     */
    function _lpTrancheEmission(uint256 block_) internal view returns (uint256) {
        return AuMM.blockEmissionRate(block_);
    }

}
