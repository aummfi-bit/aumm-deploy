// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {FixedPoint} from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import {IEmissionDistributor} from "./IEmissionDistributor.sol";
import {IAuMM} from "../token/IAuMM.sol";
import {IGaugeRegistry} from "../ccb/IGaugeRegistry.sol";
import {IEMASampler} from "../ccb/IEMASampler.sol";
import {ICCBMultiplier} from "../ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "../ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "../gauge/IEfficiencyOracle.sol";
import {CCBScore} from "../ccb/CCBScore.sol";
import {AureumTime} from "../lib/AureumTime.sol";
import {IIncendiaryRegistry} from "../incendiary/IIncendiaryRegistry.sol";

/// @title EmissionDistributor — Aureum Stage H pool-scoped emission distributor per H-D4—H-D5 + H-D15—H-D23
/// @notice Two-tier MasterChef / Synthetix accumulator topology: global `accRewardPerScoreUnit` plus per-pool `poolAccDebt` lazy-settle per H-D15. Permissionless `recordScore(pool)` writes the F-5 absolute score per H-D17 with F12 signed-delta `totalScore` middleware per H-D19. AuMT recorder (Stage I) drives `recordDeposit` / `recordWithdrawal`; user-facing `claim(pool, to)` is the sole `IAuMM.mint` entry per H-D20.
/// @dev H-D22 — two-tier storage (global + per-pool + per-user) + immutables, no transient storage (no Vault.unlock callback at H4). H-D15 — `_accrueGlobal` advances accRewardPerScoreUnit, `_settlePool` rebases poolAccDebt; F-10 `recordEmissions` push at the `_settlePool` boundary per H-D23 (allocation-side semantics, not literal-mint). H-D17 — score producer reverts `NotApproved(pool)` on revoked gauges. H-D21 — `_lpTrancheEmission(block_)` ships at H4 as a STUB returning `IAuMM.blockEmissionRate(block_)`; H5 wires F-0 / F-3 / F-7 phase-aware subtractions. I-D9 — per-pool `auMTContractByPool` mapping (one-shot per pool, mandatory-non-zero per I-D9; replaces H-D16 single-slot zero-address safety valve). Deploy prerequisite per H-D7 (OPEN, locks at H10): `IAuMM.setMinter(address(this))` must fire before any `claim(...)` call hits `IAuMM.mint`. No `selfdestruct` / `pause` per H-D21 closing record.
contract EmissionDistributor is IEmissionDistributor {
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

    /// @notice Stage J / pre-Stage-J placeholder IMiliariumRegistry — gates the `recordScore` reshape branch via `isMiliarium(pool)` per H-D33; pre-Stage-J stub returns `isMiliarium = false` for all pools. H-D31 elects immutable (not the F-D20 mutable-with-seal pattern at `src/ccb/CCBMultiplier.sol` L72).
    IMiliariumRegistry public immutable _miliariumRegistry;

    /// @notice Stage H genesis block — anchors halving math via `IAuMM.blockEmissionRate(block_)` per H-D21; same constructor-parameter precedent as `BodenseeBootstrapChannel` L36.
    uint256 public immutable GENESIS_BLOCK;

    /* ---------- Global accumulator (H-D15) ---------- */

    /// @notice Global FixedPoint 18-decimal accumulator per H-D15 — `accRewardPerScoreUnit += (rate * Δblocks).divDown(totalScore)` advances at `_accrueGlobal`.
    uint256 public override accRewardPerScoreUnit;

    /// @notice Sum of `poolScore` over approved gauges per H-D15 — mutated only through the H-D19 F12 signed-delta middleware (no other write surface).
    uint256 public override totalScore;

    /// @notice Most recent `_accrueGlobal` block per H-D21 — empty-interval short-circuit when `block.number == lastAccrualBlock`.
    uint256 public override lastAccrualBlock;

    /// @notice Running sum of raw F-5 scores across all gauged pools per H-D31 — mutated through the H-D19 signed-delta middleware at H5.3e; consumed by the H-D33 Miliarium reshape leg (`effective_Mil = (1e18 - alpha).mulDown(f5Total / 28) + alpha.mulDown(score_F5_new)`).
    uint256 public f5Total;

    /* ---------- Per-pool state (H-D22) ---------- */

    /// @notice Per-pool F-5 absolute score per H-D17 / H-D22 — written by `recordScore(pool)` as `CCBScore.score(tvlEMA, multiplier)`.
    mapping(address => uint256) public override poolScore;

    /// @notice Per-pool raw F-5 absolute score (pre-reshape) per H-D31 — written by `recordScore` at H5.3e; pre-reshape role migrates from `poolScore` so `poolScore` can be repurposed for the reshaped effective score consumed by `_settlePool` + `totalScore` signed-delta.
    mapping(address => uint256) public f5Score;

    /// @notice Per-pool snapshot of `accRewardPerScoreUnit` at last `_settlePool` per H-D15 — write-only at `_settlePool` after the H-D23 `recordEmissions` push.
    mapping(address => uint256) public override poolAccDebt;

    /// @notice Per-pool acc-reward-per-LP-unit accumulator per H-D22 / H-D24 — FixedPoint 18-decimal AuMM-wei-per-LP-unit; advanced inside `_settlePool` after H-D23 push when `poolTotalLP[pool] > 0` (skip-on-zero-LP stranded-allocation semantic).
    mapping(address => uint256) public override poolAccRewardPerLP;

    /// @notice Σ `userLP[pool][*]` per H-D22 — needed for per-user share computation at settle time.
    mapping(address => uint256) public override poolTotalLP;

    /* ---------- Per-user state (H-D16 / H-D22) ---------- */

    /// @notice Per-user AuMT stake in pool per H-D16 — mutated by `recordDeposit` / `recordWithdrawal` (gated on `auMTContractByPool[pool]` per I-D9).
    mapping(address => mapping(address => uint256)) public override userLP;

    /// @notice Per-user single-snapshot variant analogous to `poolAccDebt` per H-D16 — computed against pool-effective acc-per-LP-unit at settle time.
    mapping(address => mapping(address => uint256)) public override userRewardDebt;

    /// @notice Per-user crystallized-pending AuMM reward balance per H-D22 / H-D25 — third per-user tier slot; FixedPoint 18-decimal AuMM-wei accumulated by `recordDeposit` and `recordWithdrawal` at user-settle time per H-D25, zeroed by `claim` per H-D20 / H-D25; leading term in `pendingClaim` additive form.
    mapping(address => mapping(address => uint256)) public override pendingBalance;

    /// @notice Per-user per-pool qualification clock per I-D14 / I-D6 — the
    ///         block from which `time_in_pool` accrues for the deferred
    ///         value-weighted voting view (Stage K `VotingWeight.sol` per
    ///         I-D15). Fresh-started at `block.number` on the first qualified
    ///         deposit (or the first deposit after a withdrawal reset);
    ///         weighted-average top-up on later deposits; reset to 0 on any
    ///         withdrawal (§viii "remove any amount — even 1% — drops to
    ///         zero"). 0 means no qualified position — the deferred view
    ///         treats 0 as zero weight. `public` with no interface getter;
    ///         the view's typed access is deferred per I-D15.
    mapping(address => mapping(address => uint256)) public effectiveQualBlock;

    /* ---------- Governance + recorder slots (H-D14 / H-D16) ---------- */

    /// @notice Mutable governance authority per H-D14 — Stage A—K Authorizer Safe at deploy; rebound via `setGovernanceContract` at Stage K (mirrors TVLOracle / EfficiencyOracle / BodenseeBootstrapChannel governance-slot pattern).
    address public override governance;

    /// @notice Per-pool AuMT recorder authority per I-D9 — one-shot per pool; no deprecation safety valve per I-D9 (mandatory-non-zero at bind time). `auMTContractByPool[pool] == address(0)` pre-binding posture causes all callers for that pool to revert via `onlyAuMTContract(pool)` modifier because `msg.sender` cannot equal zero in external-call contexts.
    mapping(address => address) public override auMTContractByPool;

    /* ---------- Incendiary registry slot (H-D29) ---------- */

    /// @notice Governance-settable Stage L Incendiary registry address per H-D29 — `address(0)` at deploy (pre-Stage-L posture and deprecation safety valve); read inside `_phaseAwareBody`'s continuous-leg sub-interval body of `_lpTrancheIntegral` per H-D29; `address(0)` short-circuits the F-7 Step 1 skim subtraction returning `rate × n` (zero skim); semantics mirror H-D10 `feeRecorder` / `emissionsRecorder` recorder-slot precedent (governance-settable, `address(0)` clears).
    address public incendiaryRegistry;

    /* ---------- Constructor ---------- */

    /**
     * @notice Wires the 7 core immutables + initial governance slot and anchors `lastAccrualBlock` for the H-D22 EmissionDistributor.
     * @dev ZeroAddress guards apply to the 7 address-bearing params; `genesisBlock_` accepts any `uint256` value (deploy-time correctness is governance's responsibility — same pattern as `BodenseeBootstrapChannel` / `EfficiencyOracle`). `lastAccrualBlock` initialized to `genesisBlock_` per H-D21 so the first `_accrueGlobal()` call computes from block `genesisBlock_ + 1` when `totalScore > 0` (otherwise the H-D15 empty-`totalScore` guard short-circuits and resets `lastAccrualBlock` to `block.number`). `auMTContractByPool` defaults to all-zero mapping per I-D9 pre-binding posture — `recordDeposit` / `recordWithdrawal` revert `NotAuMTContract(pool, msg.sender)` for any unbound pool until governance calls `setAuMTContractForPool(pool, auMT)` post-deploy (Stage I deploy step). Deploy prerequisite per H-D7 (OPEN, locks at H10): `IAuMM.setMinter(address(this))` must fire before any `claim(...)` invocation. Deploy prerequisite per H-D23: `_efficiencyOracle.setEmissionsRecorder(address(this))` must be called by EfficiencyOracle governance before the first `recordScore(pool)` settle pushes; pre-handoff calls revert from `onlyEmissionsRecorder` — distributor does not catch (deploy correctness is governance's responsibility). No constructor emit for `GovernanceTransferred` — mirrors TVLOracle / EfficiencyOracle / BodenseeBootstrapChannel pattern where the initial governance slot is set silently.
     * @param aumm_ AuMM token — mint recipient at `claim` per H-D20; consumed for `blockEmissionRate(block_)` reads in `_lpTrancheEmission` per H-D21. Reverts `ZeroAddress` on zero input.
     * @param gaugeRegistry_ Stage G GaugeRegistry — gates `recordScore` via `isGaugeApproved(pool)` per H-D5 / H-D17 (a). Reverts `ZeroAddress` on zero input.
     * @param emaSampler_ Stage F EMASampler — read-only TVL_EMA source for F-5 score per H-D17 (c); never invokes `updateEMA` (F-D22 write/read separation). Reverts `ZeroAddress` on zero input.
     * @param ccbMultiplier_ Stage F CCBMultiplier — read-only CCB_mult source for F-5 score per H-D17 (c); OQ-23 `1e18` default for non-Miliarium pools. Reverts `ZeroAddress` on zero input.
     * @param efficiencyOracle_ Stage H EfficiencyOracle — `recordEmissions(pool, allocation)` push target at `_settlePool` per H-D23. Reverts `ZeroAddress` on zero input.
     * @param miliariumRegistry_ Stage J / pre-Stage-J placeholder IMiliariumRegistry — gates the `recordScore` reshape branch via `isMiliarium(pool)` per H-D33; pre-Stage-J stub returns `isMiliarium = false` for all pools so all pools follow the non-Miliarium reshape branch per H-D31. Reverts `ZeroAddress` on zero input.
     * @param genesisBlock_ Stage H genesis block — anchors halving math via `IAuMM.blockEmissionRate(block_)` per H-D21; also seeds `lastAccrualBlock`. Same precedent as `BodenseeBootstrapChannel` / `EfficiencyOracle` / `AuMM.sol` `GENESIS_BLOCK`; no zero-check (uint256, accepts any value).
     * @param initialGovernance_ Initial governance authority — Stage A—K Authorizer Safe at deploy; rebound at Stage K via `setGovernanceContract` per H-D14. Reverts `ZeroAddress` on zero input.
     */
    constructor(
        IAuMM aumm_,
        IGaugeRegistry gaugeRegistry_,
        IEMASampler emaSampler_,
        ICCBMultiplier ccbMultiplier_,
        IEfficiencyOracle efficiencyOracle_,
        IMiliariumRegistry miliariumRegistry_,
        uint256 genesisBlock_,
        address initialGovernance_
    ) {
        if (address(aumm_) == address(0)) revert ZeroAddress();
        if (address(gaugeRegistry_) == address(0)) revert ZeroAddress();
        if (address(emaSampler_) == address(0)) revert ZeroAddress();
        if (address(ccbMultiplier_) == address(0)) revert ZeroAddress();
        if (address(efficiencyOracle_) == address(0)) revert ZeroAddress();
        if (address(miliariumRegistry_) == address(0)) revert ZeroAddress();
        if (initialGovernance_ == address(0)) revert ZeroAddress();

        AuMM = aumm_;
        _gaugeRegistry = gaugeRegistry_;
        _emaSampler = emaSampler_;
        _ccbMultiplier = ccbMultiplier_;
        _efficiencyOracle = efficiencyOracle_;
        _miliariumRegistry = miliariumRegistry_;
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

    /// @notice Restricts execution to the per-pool AuMT recorder; reverts `NotAuMTContract(pool, msg.sender)` otherwise.
    /// @dev I-D9 per-pool recorder gate — `setAuMTContractForPool`-pivoting `auMTContractByPool` mapping per I-D9; one-shot per pool, no deprecation safety valve (mandatory-non-zero at bind time per I-D9). Pre-binding posture has `auMTContractByPool[pool] == address(0)` which causes all callers for that pool to revert because `msg.sender` cannot equal zero in external-call contexts. Mirrors `onlyGovernance` structure.
    modifier onlyAuMTContract(address pool) {
        if (msg.sender != auMTContractByPool[pool]) revert NotAuMTContract(pool, msg.sender);
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
     * @notice Binds the AuMT recorder for `pool` per I-D9 — one-shot per pool, `onlyGovernance`-gated.
     * @dev I-D9 per-pool recorder mapping — `setAuMTContractForPool`-pivoting `auMTContractByPool` mapping; one-shot per pool, no rebinding support (deliberate departure from H-D16 mutable). `ZeroAddress` guard mandatory-non-zero rationale: mirrors `setGovernanceContract` H-D14 (non-zero recipient is the load-bearing handoff invariant); H-D16 zero-address deprecation safety valve removed because asymmetric rebind between hook `auMTByPool` and distributor `auMTContractByPool` would break per-pool topology. `AuMTAlreadyBound(pool)` one-shot rationale: mirrors H-D5 hook `setAuMTForPool` per I-D5 (one-shot binding prevents topology divergence). Emits `AuMTContractBound(pool, newAuMTContract)`.
     * @param pool The Balancer V3 pool address to bind the recorder for.
     * @param newAuMTContract The Stage I AuMT contract address for `pool`. Reverts `ZeroAddress` on zero input; reverts `AuMTAlreadyBound(pool)` if already bound.
     */
    function setAuMTContractForPool(address pool, address newAuMTContract) external override onlyGovernance {
        if (newAuMTContract == address(0)) revert ZeroAddress();
        if (auMTContractByPool[pool] != address(0)) revert AuMTAlreadyBound(pool);
        auMTContractByPool[pool] = newAuMTContract;
        emit AuMTContractBound(pool, newAuMTContract);
    }

    /**
     * @notice Rebinds the `incendiaryRegistry` slot per H-D29 — `onlyGovernance`-gated.
     * @dev Zero address is acceptable per H-D29 deprecation safety valve — mirrors H-D10 recorder-slot zero-permitted precedent (deliberate asymmetry with H-D14 `setGovernanceContract` mandatory-non-zero). Body sequence: cache `oldRegistry = incendiaryRegistry` → write `incendiaryRegistry = newRegistry` → emit `IncendiaryRegistrySet(oldRegistry, newRegistry)`. When `incendiaryRegistry == address(0)` the `_phaseAwareBody` continuous-leg sub-interval body of `_lpTrancheIntegral` short-circuits the F-7 Step 1 skim subtraction, returning `rate × n` per H-D29 (H5.1c). Stage L deployment hand-off: governance calls this setter once post-Stage-L deploy with the deployed `IIncendiaryRegistry` registry address; H10 deployment script defaults the slot to `address(0)`.
     * @param newRegistry The new Stage L Incendiary registry address. Zero address permitted as H-D29 deprecation safety valve.
     */
    function setIncendiaryRegistry(address newRegistry) external onlyGovernance {
        address oldRegistry = incendiaryRegistry;
        incendiaryRegistry = newRegistry;
        emit IncendiaryRegistrySet(oldRegistry, newRegistry);
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

    /* ---------- Bootstrap leg AP integration helper (H-D27) ---------- */

    /**
     * @notice Computes the AP closed-form sum of AuMM emissions over `[from, to]` inclusive for a single F-0 bootstrap leg per H-D27 + F-0.
     * @dev H-D27 lock — bit-for-bit mirror of `BodenseeBootstrapChannel._apSum` at L218-L226 (function declaration L212-L220, body L221-L225). H-D2 channel-distributor separation: the formula is duplicated here, not called from the channel contract — upstream-call coupling would defeat the H5.4 arithmetic-identity unit test discipline and violate H-D2's clean separation of channel accrual from LP distribution math. The share at block `b` follows a linear arithmetic progression: `bodensee_share(b) = startShare − dropShare × (b − anchorStart) / (anchorEnd − anchorStart)`, which justifies the closed form `n × (first + last) / 2 × rate / 1e18` (standard AP partial sum). Both `from` and `to` are inclusive; `n = to − from + 1` is the count of blocks. `startShare` and `dropShare` are FixedPoint 1e18-base fractions (e.g. `8e17` = 80%, `3e17` = 30%). Overflow analysis identical to BodenseeBootstrapChannel L202: `(first + last) ≤ 1.6e18`, `n ≤ 2.2e6` (max bootstrap window per OQ-3), `rate ≤ ~1e18` (Era 0 max per OQ-5) — product ≤ 3.5e42 fits in uint256. Caller (`_phaseAwareBody` at H5.1c) guarantees `to >= from` and that the entire `[from, to]` sub-interval lies within a single bootstrap leg (A-leg: `[genesis, month6End]`; B-leg: `[month6End + 1, month10End]`) — `_lpTrancheIntegral` (H5.1d) is the site of the cross-`month6End` split.
     * @param from Inclusive start block of the integration interval; caller guarantees `from <= to`.
     * @param to Inclusive end block of the integration interval; caller guarantees `to >= from`.
     * @param anchorStart First block of this bootstrap leg's share-decay range (A-leg: `GENESIS_BLOCK`; B-leg: `month6End + 1`).
     * @param anchorEnd Last block of this bootstrap leg's share-decay range (A-leg: `month6End`; B-leg: `month10End`); denominator of the AP slope per H-D27.
     * @param startShare FixedPoint 1e18-base share at `anchorStart` (A-leg: `8e17` = 80%; B-leg: `5e17` = 50%) per F-0 + H-D27.
     * @param dropShare FixedPoint 1e18-base total share drop across the leg (A-leg: `3e17` = 30%; B-leg: `5e17` = 50%) per F-0 + H-D27.
     * @param rate AuMM tokens-per-block emission rate at the representative block of this interval (from `IAuMM.blockEmissionRate`); 18-decimal wei scale.
     * @return AuMM-wei emission allocated to the Bodensee bootstrap channel over `[from, to]` per H-D27.
     */
    function _bootstrapApSum(
        uint256 from,
        uint256 to,
        uint256 anchorStart,
        uint256 anchorEnd,
        uint256 startShare,
        uint256 dropShare,
        uint256 rate
    ) private pure returns (uint256) {
        uint256 width = anchorEnd - anchorStart;
        uint256 first = startShare - (dropShare * (from - anchorStart)) / width;
        uint256 last = startShare - (dropShare * (to - anchorStart)) / width;
        uint256 n = to - from + 1;
        return ((first + last) * n * rate) / (2 * 1e18);
    }

    /* ---------- Phase-aware sub-interval body (H-D27 / H-D28 / H-D29) ---------- */

    /**
     * @notice Dispatches the AuMM emission integral over `[from, to]` to the F-0 bootstrap, F-3 transition, or F-7 continuous sub-interval body per H-D27 / H-D28 / H-D29, walking forward across phase boundaries within a single era.
     * @dev Caller is `_lpTrancheIntegral` (H5.1d) which guarantees `[from, to]` lies within a single era so `rate` is constant across the interval per H-D30. Three phase boundaries `m6 = AureumTime.month6EndBlock(GENESIS_BLOCK)`, `m10 = AureumTime.month10EndBlock(GENESIS_BLOCK)`, `y1 = AureumTime.year1EndBlock(GENESIS_BLOCK)` cached once at function entry. Bootstrap phase (`cursor <= m10`) further splits at `m6` into A-leg `[cursor, min(m6, phaseEnd)]` with anchor `[GENESIS_BLOCK, m6]` and shares `8e17 → 5e17` (drop `3e17`) per F-0, and B-leg `[m6+1, phaseEnd]` with anchor `[m6, m10]` and shares `5e17 → 0` (drop `5e17`) per F-0, each leg using the conservation identity `rate × n − _bootstrapApSum(...)` per H-D27 (one fewer rounding-mode divergence risk than direct LP-share AP per H-D27 prose). Transition phase (`m10 < cursor <= y1`) returns `rate × n` with no LP-tranche subtraction per H-D28 + canonical F-3 domain note (the F-3 α-blend `(1 − α) × 1/28 + α × CCB_share_i` lives in `recordScore` middleware at H5.3, NOT in this global integral). Continuous phase (`cursor > y1`) returns `rate × n − skim` where `skim = 0` when `incendiaryRegistry == address(0)` (Stage H ship default + deprecation safety valve per H-D29) and `skim = IIncendiaryRegistry(incendiaryRegistry).integratedSkim(cursor, to)` otherwise — NO `try/catch` wrap per H-D29 (a reverting registry reverts accrual; conservative against silent skim-suppression past the 21M cap). `private view` because the function reads the `incendiaryRegistry` storage slot and the `GENESIS_BLOCK` immutable and may make an external view call into `IIncendiaryRegistry`. Cursor never written back at the terminal continuous-phase branch (write is dead — no successor branch reads it). Local cache `phaseEnd` reused per phase block, distinct scope each time so no solc shadow.
     * @param from Inclusive start block of the integration interval; caller guarantees `from <= to` and `[from, to]` lies entirely within a single AuMM era per H-D30.
     * @param to Inclusive end block of the integration interval; caller guarantees `to >= from`.
     * @param rate AuMM tokens-per-block emission rate `IAuMM.blockEmissionRate(from)` snapshotted by the caller — constant across `[from, to]` per H-D30 era-splitting; 18-decimal wei scale.
     * @return AuMM-wei LP-tranche emission allocated over `[from, to]` after F-0 Bodensee subtraction (bootstrap) / F-7 Incendiary skim subtraction (continuous), or `rate × n` unchanged (transition) per H-D26 conservation invariant.
     */
    function _phaseAwareBody(uint256 from, uint256 to, uint256 rate) private view returns (uint256) {
        uint256 m6 = AureumTime.month6EndBlock(GENESIS_BLOCK);
        uint256 m10 = AureumTime.month10EndBlock(GENESIS_BLOCK);
        uint256 y1 = AureumTime.year1EndBlock(GENESIS_BLOCK);

        uint256 contribution = 0;
        uint256 cursor = from;

        if (cursor <= m10) {
            uint256 phaseEnd = m10 < to ? m10 : to;
            if (cursor <= m6) {
                uint256 aLegEnd = m6 < phaseEnd ? m6 : phaseEnd;
                uint256 nA = aLegEnd - cursor + 1;
                contribution += rate * nA - _bootstrapApSum(cursor, aLegEnd, GENESIS_BLOCK, m6, 8e17, 3e17, rate);
                cursor = aLegEnd + 1;
            }
            if (cursor <= phaseEnd) {
                uint256 nB = phaseEnd - cursor + 1;
                contribution += rate * nB - _bootstrapApSum(cursor, phaseEnd, m6, m10, 5e17, 5e17, rate);
                cursor = phaseEnd + 1;
            }
        }

        if (cursor <= to && cursor <= y1) {
            uint256 phaseEnd = y1 < to ? y1 : to;
            uint256 n = phaseEnd - cursor + 1;
            contribution += rate * n;
            cursor = phaseEnd + 1;
        }

        if (cursor <= to) {
            uint256 n = to - cursor + 1;
            uint256 skim = 0;
            address registry = incendiaryRegistry;
            if (registry != address(0)) {
                skim = IIncendiaryRegistry(registry).integratedSkim(cursor, to);
            }
            contribution += rate * n - skim;
        }

        return contribution;
    }

    /* ---------- Phase-aware interval integral (H-D26 / H-D30) ---------- */

    /**
     * @notice Integrates the AuMM LP-tranche emission over `[from, to]` inclusive per the H-D26 conservation invariant, splitting at every spanned era boundary per H-D30 and delegating each era sub-interval to `_phaseAwareBody`.
     * @dev Caller is `_accrueGlobal` (H5.1e) which guarantees `from = lastAccrualBlock + 1` and `to = block.number` after the empty-interval + empty-`totalScore` short-circuits. Supersedes H-D21's H4 single-block sample (which remains LOCKED for H4 historical posture per H-D26 prose). Algorithm is a cursor walk — each iteration reads `era = AureumTime.eraIndex(GENESIS_BLOCK, cursor)` then `eraEnd = AureumTime.nthHalvingBlock(GENESIS_BLOCK, era + 1) - 1` (last block of the current era; `Era 0 = [genesis, genesis + BLOCKS_PER_ERA)` per `AureumTime.eraIndex` L45 doc), clamps `subTo = min(eraEnd, to)`, snapshots a constant `rate = AuMM.blockEmissionRate(cursor)` valid across the entire era sub-interval per H-D30 (`blockEmissionRate(b) = GENESIS_RATE >> eraIndex(b, GENESIS_BLOCK)` is piecewise-constant within an era per OQ-5 / §xxix), dispatches to `_phaseAwareBody(cursor, subTo, rate)` for the inner phase split (H-D27 bootstrap A/B + H-D28 transition + H-D29 continuous), and advances `cursor = subTo + 1`. Loop termination is monotonic because `subTo >= cursor` always (era end is the last block of the current era so always `>= cursor`, and `to >= cursor` by loop precondition). Era 0 fully encloses both the bootstrap window (`month10End ≈ 2.19M < 10.5M = BLOCKS_PER_ERA`) and the transition window (`year1End ≈ 2.628M`) per OQ-3 / OQ-5, so for the first ~4 years post-genesis the era loop executes exactly 1 iteration per call and era-splitting is a no-op gas-wise — all phase splitting happens inside `_phaseAwareBody`. From Era 1 onward the loop is unbounded in principle but bounded in practice by user-activity cadence (active pools keep `lastAccrualBlock` close to `block.number`; fully dormant pools accumulate at most O(eras_since_genesis) = O(years/4) iterations over the protocol lifetime). Conservation invariant `LP_integral(from, to) + Σ Bodensee_apsum(sub) + Σ Incendiary_integral(sub) = Σ blockEmissionRate(sub_from) × n_sub` enforced piecewise by `_phaseAwareBody` per H-D26 (the era split preserves this because `blockEmissionRate` is constant within each era sub-interval). `internal view` per H-D26 verbatim — function reads `GENESIS_BLOCK` immutable, the `incendiaryRegistry` storage slot (transitively via `_phaseAwareBody`), and may make an external view call into `IIncendiaryRegistry.integratedSkim` (transitively via `_phaseAwareBody`). No caching layer, no memoisation — accrual cadence and the H-D21 lazy-tick discipline at every mutating entry bound the per-call work. `_lpTrancheEmission(block_)` view at L196-L198 is RETAINED unchanged per H-D26 as the single-block external view for tests / UI but is no longer read in the production accrual path (the wiring of `_accrueGlobal` to call `_lpTrancheIntegral` instead of `_lpTrancheEmission` lands at H5.1e).
     * @param from Inclusive start block of the integration interval; caller guarantees `from <= to` and `from >= GENESIS_BLOCK + 1` per H-D21's `_accrueGlobal` short-circuit invariants.
     * @param to Inclusive end block of the integration interval; caller passes `block.number` per H-D21.
     * @return AuMM-wei LP-tranche emission integrated over `[from, to]` per H-D26 conservation invariant; aggregates per-era sub-interval contributions from `_phaseAwareBody`.
     */
    function _lpTrancheIntegral(uint256 from, uint256 to) internal view returns (uint256) {
        uint256 cursor = from;
        uint256 contribution = 0;

        while (cursor <= to) {
            uint256 era = AureumTime.eraIndex(GENESIS_BLOCK, cursor);
            uint256 eraEnd = AureumTime.nthHalvingBlock(GENESIS_BLOCK, era + 1) - 1;
            uint256 subTo = eraEnd < to ? eraEnd : to;
            uint256 rate = AuMM.blockEmissionRate(cursor);
            contribution += _phaseAwareBody(cursor, subTo, rate);
            cursor = subTo + 1;
        }

        return contribution;
    }

    /* ---------- Accrual (H-D15 / H-D21) ---------- */

    /**
     * @notice Advances the global `accRewardPerScoreUnit` accumulator for the elapsed block interval per H-D15 / H-D26.
     * @dev H-D26 production accrual path — supersedes H-D21's H4 single-block-sample × Δblocks pattern (H-D21 LOCKED for H4 historical posture). Lazy accrual tick invoked at every mutating external entry (`recordScore` at H4.5e, `recordDeposit` / `recordWithdrawal` at H4.6, `claim` at H4.7) BEFORE any state mutation, ensuring `accRewardPerScoreUnit` is fresh against `block.number`. Two short-circuits in strict order — (1) empty-interval per H-D21: `block.number == lastAccrualBlock` returns immediately, no integral read, no write; (2) empty-`totalScore` per H-D15: `totalScore == 0` resets `lastAccrualBlock = block.number` and returns (prevents divide-by-zero on the divDown denominator + ensures no scaled emission accrues when no eligible pools exist — pre-Stage-J or post-revocation-storm conditions). Otherwise reads `contribution = _lpTrancheIntegral(last + 1, block.number)` once per call per H-D26 (the integral interval is inclusive on both ends — `[last + 1, block.number]` covers every block strictly after the previous accrual through the current block, so successive accruals tile the block timeline exactly once each, no double-counting and no gaps); the integral internally splits at era boundaries per H-D30 and phase boundaries per H-D27 / H-D28 / H-D29, snapshotting a constant `rate = AuMM.blockEmissionRate(sub_from)` per era sub-interval, so the conservation invariant `LP_integral + Σ Bodensee_apsum + Σ Incendiary_integral = Σ blockEmissionRate × n_sub` holds across the interval per H-D26. Applies FixedPoint divDown: `accRewardPerScoreUnit += contribution × 1e18 / totalScore` (the `.divDown(uint256)` binding from L22's `using FixedPoint for uint256;`); FixedPoint scale convention keeps `accRewardPerScoreUnit` in AuMM_wei-per-score-unit (FixedPoint 18-decimal), matching the `(accRewardPerScoreUnit - poolAccDebt[pool]).mulDown(poolScore[pool])` allocation formula at `_settlePool` per H-D15 / H-D23. `lastAccrualBlock` writes `block.number` AFTER the accumulator math so subsequent calls within the same block short-circuit at the empty-interval guard. Local caches `last` (lastAccrualBlock SLOAD) and `total` (totalScore SLOAD) eliminate redundant storage reads in the success path. `_lpTrancheEmission(block_)` at L196-L198 is no longer read in this production path per H-D26 — RETAINED as the single-block external view for tests / UI per H-D26 retention note.
     */
    function _accrueGlobal() internal {
        uint256 last = lastAccrualBlock;
        if (block.number == last) return;
        uint256 total = totalScore;
        if (total == 0) {
            lastAccrualBlock = block.number;
            return;
        }
        uint256 contribution = _lpTrancheIntegral(last + 1, block.number);
        accRewardPerScoreUnit += contribution.divDown(total);
        lastAccrualBlock = block.number;
    }

    /* ---------- Settlement (H-D15 / H-D23) ---------- */

    /**
     * @notice Settles `pool` against the current global accumulator snapshot per H-D15 / H-D23 — computes allocation, pushes to `_efficiencyOracle.recordEmissions`, rebases `poolAccDebt[pool]`.
     * @dev H-D15 / H-D23 per-pool lazy-settle. Invoked AFTER `_accrueGlobal()` by every upstream mutator (`recordScore` at H4.5e, `recordDeposit` / `recordWithdrawal` at H4.6, `claim` at H4.7) so `accRewardPerScoreUnit` is guaranteed fresh against `block.number`. Computes `deltaAcc = accRewardPerScoreUnit - poolAccDebt[pool]` (no-underflow invariant: `poolAccDebt[pool] <= accRewardPerScoreUnit` always holds because the only write site is `poolAccDebt[pool] = accRewardPerScoreUnit` at the end of this function and `accRewardPerScoreUnit` is monotonically non-decreasing per H-D15) and `poolAllocation = deltaAcc.mulDown(poolScore[pool])` — FixedPoint mulDown converts (FixedPoint AuMM-per-score-unit × FixedPoint score) into AuMM_wei. H-D23 zero-skip: when `poolAllocation == 0` the external `_efficiencyOracle.recordEmissions(pool, poolAllocation)` call is skipped (saves the EfficiencyOracle `_ensureCurrentEpoch` round-trip + matches H-D10's skip-on-zero spirit). When `poolAllocation > 0` the push lands BEFORE `poolAccDebt[pool]` is rebased per H-D23 strict order — the allocation amount is captured against the pre-settle snapshot, and `poolAccDebt[pool]` writes immediately after so a subsequent `_settlePool(pool)` in the same interval pushes only the incremental `(Δacc × poolScore)` (typically zero if no intervening accrual). Recorder-gate revert NOT caught: H-D23 / H-D10 — when `_efficiencyOracle.emissionsRecorder != address(this)` (pre-deploy or deprecated posture) the push reverts from `onlyEmissionsRecorder` and the entire `_settlePool` reverts; distributor does NOT try/catch (deploy correctness is governance's responsibility per H-D7 / H-D23 closing record). First-settle behavior: when `poolAccDebt[pool] == 0` (default) the pool captures `accRewardPerScoreUnit.mulDown(poolScore[pool])` — if `poolScore[pool] == 0` (pre-`recordScore`) the result is 0 and the push is skipped, fast-forwarding the debt baseline to current acc; if `poolScore[pool] > 0` the result is the full accumulated allocation since deployment (intentional MasterChef set-initial-debt semantic). Local cache `acc` (accRewardPerScoreUnit SLOAD) eliminates the redundant read between the subtraction and the final debt write; `poolAccDebt[pool]` and `poolScore[pool]` are each read once so no cache. H-D24 per-LP-unit accumulation step: inside the `poolAllocation > 0` zero-skip, AFTER the H-D23 EfficiencyOracle push and BEFORE the `poolAccDebt[pool]` rebase, the per-pool `poolAccRewardPerLP[pool]` accumulator is incremented by `poolAllocation.divDown(totalLP)` when `poolTotalLP[pool] > 0`; inner zero-LP guard prevents divide-by-zero — when `poolTotalLP[pool] == 0` (pool has score but no LP deposits, pre-Stage-I posture or post-withdrawal-storm) the allocation is effectively stranded from LP distribution but still feeds the F-10 EfficiencyOracle denominator via the prior H-D23 push, matching standard MasterChef stranded-allocation semantic locked at H-D24.
     * @param pool The Balancer V3 pool address to settle. No registry/gauge check here — `_settlePool` trusts the upstream caller to have already established gauge eligibility via the H-D17 / H-D5 `isGaugeApproved` check at `recordScore` (revoked-gauge pools entering `_settlePool` via stale state simply settle at the current accumulator with their last-known `poolScore`, then writing the debt baseline; no exploit surface because `poolScore` cannot grow without a fresh `recordScore` which itself requires gauge approval).
     */
    function _settlePool(address pool) internal {
        uint256 acc = accRewardPerScoreUnit;
        uint256 deltaAcc = acc - poolAccDebt[pool];
        uint256 poolAllocation = deltaAcc.mulDown(poolScore[pool]);
        if (poolAllocation > 0) {
            _efficiencyOracle.recordEmissions(pool, poolAllocation);
            uint256 totalLP = poolTotalLP[pool];
            if (totalLP > 0) {
                poolAccRewardPerLP[pool] += poolAllocation.divDown(totalLP);
            }
        }
        poolAccDebt[pool] = acc;
    }

    /* ---------- F12 signed-delta helper (H-D19) ---------- */

    /**
     * @notice Applies a signed `delta` to an unsigned `base` per F12 type-discipline / H-D19, returning the resulting unsigned value.
     * @dev H-D19 totalScore signed-delta middleware + F12 Stage F type-discipline pattern at `src/ccb/CCBMultiplier.sol` L272 + L276 — extracts the inlined CCBMultiplier pattern into reusable form for `recordScore` (H4.5e). `base.toInt256()` reverts on `base > type(int256).max` (impossible for FixedPoint scores at 18-decimal scale under any plausible totalScore). `.toUint256()` reverts on the final int256 being negative (the F12 clamp invariant — recordScore's signed-delta middleware preserves `totalScore >= 0` because the only call site computes `delta = newScore - oldScore` against `totalScore`, where oldScore is a prior write to `poolScore[pool]` summed into `totalScore`, so subtracting it cannot drive the aggregate below zero in well-formed sequences).
     * @param base The unsigned base value, typically `totalScore`.
     * @param delta The signed delta to apply, typically `newScore.toInt256() - oldScore.toInt256()`.
     * @return The resulting unsigned value after `(base.toInt256() + delta).toUint256()`.
     */
    function _applySignedDelta(uint256 base, int256 delta) internal pure returns (uint256) {
        return (base.toInt256() + delta).toUint256();
    }

    /* ---------- F-3 α-blend helper (H-D32) ---------- */

    /**
     * @notice Linear F-3 α blend across the transition window `(month10EndBlock, year1EndBlock]`, clamped to 0 below and 1e18 above.
     * @dev H-D32 anchor — F-3 defines a linear interpolation across the `(month10EndBlock, year1EndBlock]` transition window per F-3:
     *      lower clamp — returns 0 at `block_ <= m10` (canonical F-1 equal-split regime; Bodensee bootstrap channel active at full F-0 rate);
     *      upper clamp — returns 1e18 at `block_ >= y1` (canonical F-7 CCB-only regime; bootstrap channel closed);
     *      linear interior — `(block_ - m10 - 1) * 1e18 / (y1 - m10 - 1)` yields the FixedPoint 18-decimal α ∈ (0, 1e18) exclusive.
     *      Numerator `block_ - m10 - 1` is zero at `block_ == m10 + 1` (first interior block) and `y1 - m10 - 2` at `block_ == y1 - 1` (last interior block before upper clamp).
     *      Denominator `y1 - m10 - 1 = BLOCKS_PER_YEAR - 10 * BLOCKS_PER_MONTH - 1 = 2_628_000 - 2_190_000 - 1 = 437_999` (OQ-3 + OQ-5 block-count constants; `y1 > m10 + 1` by construction — no divide-by-zero).
     *      Plain integer arithmetic — multiplying by 1e18 before integer-dividing by the 437_999-block integer denominator yields the FixedPoint 18-decimal result directly; no `.divDown` / `.mulDown` / FixedPoint library call needed (H-D32 closing prose). Anchors: H-D32, H-D33, F-3, OQ-3, OQ-5. Consumed by `recordScore` at H5.3e per H-D33.
     * @param block_ The block-number input — typically `block.number` at the H-D31 step (7) `recordScore` call site; this helper does not read the `block` global.
     * @return α — FixedPoint 18-decimal value in `[0, 1e18]` representing the F-3 linear blend coefficient.
     */
    function _alphaF3(uint256 block_) private view returns (uint256) {
        uint256 m10 = AureumTime.month10EndBlock(GENESIS_BLOCK);
        uint256 y1 = AureumTime.year1EndBlock(GENESIS_BLOCK);
        if (block_ <= m10) return 0;
        if (block_ >= y1) return 1e18;
        return (block_ - m10 - 1) * 1e18 / (y1 - m10 - 1);
    }

    /* ---------- Score producer (H-D17 / H-D31) ---------- */

    /**
     * @notice Permissionlessly records the reshaped effective score for `pool` under H-D31 / H-D33 and updates `totalScore` and `f5Total`.
     * @dev H-D17 / H-D31 10-step flow — (1) gauge gate `_gaugeRegistry.isGaugeApproved(pool)` revert `NotApproved(pool)` per H-D5 / H-D17 (a); (2) H-D21 lazy accrual tick `_accrueGlobal()`; (3) per-pool settle `_settlePool(pool)` BEFORE any score mutation per H-D21 / H-D23; (4) F-5 recompute `score_F5_new = CCBScore.score(_emaSampler.tvlEMA(pool), _ccbMultiplier.getMultiplier(pool))` — `ICCBMultiplier.getMultiplier` returns `INITIAL_MULTIPLIER = 1e18` for non-Miliarium pools per OQ-23 / F-D16; (5) signed-delta on `f5Total` against old `f5Score[pool]` BEFORE overwrite at step (6) — `f5Total = _applySignedDelta(f5Total, score_F5_new.toInt256() - f5Score[pool].toInt256())` per H-D31 / H-D33 / F12; (6) write `f5Score[pool] = score_F5_new`; (7) snapshot `alpha = _alphaF3(block.number)` per H-D32 — 0 in bootstrap (Month 0—10, F-1 equal-split regime), 1e18 in continuous (Year 1+, F-7 CCB-only regime), linear interior in F-3 transition window; (8) H-D33 reshape — Miliarium branch `effective_new = (1e18 - alpha).mulDown(f5Total / 28) + alpha.mulDown(score_F5_new)` per H-D6 1/28 literal supply-deflationary share (α=0 collapses to protocol-aggregate F-5 mean, α=1e18 collapses to pool-own F-5 per §xxviii); non-Miliarium Option A `effective_new = alpha.mulDown(score_F5_new)` per `10_constitution.md §xxviii` (α=0 yields zero weight in bootstrap, α=1e18 yields full F-5 in continuous; F-D9 Miliarium-only multiplier scope); (9) capture `oldEffective = poolScore[pool]`, apply signed-delta `totalScore = _applySignedDelta(totalScore, effective_new.toInt256() - oldEffective.toInt256())` per H-D19 / F12 — `poolScore[pool]` stores reshaped effective score from H5.3 onward (H4 stored raw F-5; semantic repurpose at H5.3; downstream `_settlePool` + `totalScore` signed-delta reads unchanged per H-D31 Q2); (10) write `poolScore[pool] = effective_new` and emit `ScoreUpdated(pool, oldEffective, effective_new)` — no-op delta path (equal old/new effective) preserved per H-D17 permissionless idempotent producer; cross-pool α staleness accepted per H-D31 Q2 bot-poke cadence + H-D3 epoch-step descriptive. Anchors: H-D17, H-D31, H-D32, H-D33, H-D5, H-D6, H-D19, H-D21, H-D23, F-3, F-5, F-7, F-D9, F-D16, OQ-23, F12.
     * @param pool The Balancer V3 pool address whose score is being recorded.
     */
    function recordScore(address pool) external override {
        if (!_gaugeRegistry.isGaugeApproved(pool)) revert NotApproved(pool);
        _accrueGlobal();
        _settlePool(pool);
        uint256 score_F5_new = CCBScore.score(_emaSampler.tvlEMA(pool), _ccbMultiplier.getMultiplier(pool));
        f5Total = _applySignedDelta(f5Total, score_F5_new.toInt256() - f5Score[pool].toInt256());
        f5Score[pool] = score_F5_new;
        uint256 alpha = _alphaF3(block.number);
        uint256 effective_new;
        if (_miliariumRegistry.isMiliarium(pool)) {
            effective_new = (1e18 - alpha).mulDown(f5Total / 28) + alpha.mulDown(score_F5_new);
        } else {
            effective_new = alpha.mulDown(score_F5_new);
        }
        uint256 oldEffective = poolScore[pool];
        totalScore = _applySignedDelta(totalScore, effective_new.toInt256() - oldEffective.toInt256());
        poolScore[pool] = effective_new;
        emit ScoreUpdated(pool, oldEffective, effective_new);
    }

    /* ---------- Recorder mutators (H-D16 / H-D21 / H-D25) ---------- */

    /**
     * @notice Records a deposit of `amount` AuMT for `user` in `pool` — AuMT-recorder gated per H-D16.
     * @dev I-D9 / H-D21 / H-D25 single-snapshot MasterChef variant — (a) `onlyAuMTContract(pool)` gate reverts `NotAuMTContract(pool, msg.sender)` on non-recorder callers (pre-binding `auMTContractByPool[pool] == address(0)` posture causes all callers to revert because `msg.sender` cannot equal zero); (b) H-D21 lazy accrual tick `_accrueGlobal()` then per-pool settle `_settlePool(pool)` BEFORE any user-state mutation, ensuring `poolAccRewardPerLP[pool]` is fresh against `block.number`; (c) cache `acc = poolAccRewardPerLP[pool]` (the H-D24 per-LP-unit accumulator); (d) compute `pending = (acc - userRewardDebt[pool][user]).mulDown(userLP[pool][user])` against the pre-deposit user state per H-D25 — FixedPoint mulDown converts (FixedPoint per-LP-unit AuMM × LP-unit count) into AuMM-wei; (e) H-D25 zero-skip — when `pending > 0` crystallize via `pendingBalance[pool][user] += pending` (no separate event — single `DepositRecorded` per call per H-D16); (f) increment user stake `userLP[pool][user] += amount` and pool aggregate `poolTotalLP[pool] += amount` AFTER the pending math so the snapshot is computed against pre-deposit `userLP`; (g) rebase `userRewardDebt[pool][user] = acc` per H-D16 / H-D25 — subsequent `pendingClaim` derivations start the live-delta clock from the fresh accumulator; (h) emit `DepositRecorded(pool, user, amount)`. First-deposit behavior: when `userLP[pool][user] == 0` pre-deposit, `pending = (acc - 0).mulDown(0) = 0` regardless of `acc` magnitude — the zero-skip elides the no-op `pendingBalance` write; the debt rebase `userRewardDebt[pool][user] = acc` correctly initializes the per-user snapshot. No-underflow invariant on `acc - userRewardDebt[pool][user]`: `userRewardDebt[pool][user]` is only ever written as a snapshot of `poolAccRewardPerLP[pool]` (here and at `recordWithdrawal` / `claim`), which is monotonically non-decreasing per H-D24; so `userRewardDebt[pool][user] <= acc` always holds. Zero-amount deposits are permitted — the interface does not declare an `amount > 0` guard and the H-D16 prose does not impose one (AuMT recorder filters upstream); the function still runs the full accrue/settle/pending-crystallization sequence and emits the event. The `pendingBalance` crystallization step is the load-bearing departure from the Sushi MasterChef V2 auto-claim-at-deposit pattern: H-D20 fixes `IAuMM.mint` at the `claim` site only, so the pre-deposit allocation cannot transfer here — it accumulates in `pendingBalance` until the user calls `claim` (H4.7). Local cache `acc` (poolAccRewardPerLP SLOAD) eliminates the redundant read between the pending math and the debt rebase. No reentrancy guard — no external calls between the gate and the event (the EfficiencyOracle push in `_settlePool` per H-D23 happens before any user-state mutation).
     * @param pool The Balancer V3 pool address — caller-supplied; no `isGaugeApproved` gate here per H-D16 (deposit/withdrawal must always settle even on revoked-gauge pools so existing stake can exit cleanly; `recordScore` is the producer that filters on gauge approval per H-D17).
     * @param user The AuMT holder receiving the stake credit — caller-supplied; ZeroAddress not guarded (H-D16 trusts the AuMT recorder to filter).
     * @param amount The AuMT amount deposited (same scale as `userLP`); zero permitted.
     */
    function recordDeposit(address pool, address user, uint256 amount) external override onlyAuMTContract(pool) {
        _accrueGlobal();
        _settlePool(pool);
        uint256 acc = poolAccRewardPerLP[pool];
        uint256 pending = (acc - userRewardDebt[pool][user]).mulDown(userLP[pool][user]);
        if (pending > 0) {
            pendingBalance[pool][user] += pending;
        }
        // I-D14 effectiveQualBlock clock (see effectiveQualBlock NatSpec): fresh-start
        // at block.number when the clock is reset/unset, else weighted-average top-up.
        // amount > 0 guard keeps zero-amount deposits clock-neutral and ensures the
        // weighted-average denominator (oldAmount + amount) is non-zero.
        if (amount > 0) {
            uint256 oldEqb = effectiveQualBlock[pool][user];
            if (oldEqb == 0) {
                effectiveQualBlock[pool][user] = block.number;
            } else {
                uint256 oldAmount = userLP[pool][user];
                effectiveQualBlock[pool][user] = (oldAmount * oldEqb + amount * block.number) / (oldAmount + amount);
            }
        }
        userLP[pool][user] += amount;
        poolTotalLP[pool] += amount;
        userRewardDebt[pool][user] = acc;
        emit DepositRecorded(pool, user, amount);
    }

    /**
     * @notice Records a withdrawal of `amount` AuMT for `user` in `pool` — AuMT-recorder gated per H-D16.
     * @dev I-D9 / H-D21 / H-D25 symmetric settle pattern — mirrors `recordDeposit` with decrement instead of increment: (a) `onlyAuMTContract(pool)` gate; (b) H-D21 lazy accrual tick `_accrueGlobal()` then per-pool settle `_settlePool(pool)`; (c) cache `acc = poolAccRewardPerLP[pool]`; (d) compute `pending = (acc - userRewardDebt[pool][user]).mulDown(userLP[pool][user])` against the pre-withdrawal `userLP` per H-D25 — crystallize via `pendingBalance[pool][user] += pending` when `pending > 0` (zero-skip); (e) decrement `userLP[pool][user] -= amount` and `poolTotalLP[pool] -= amount` AFTER the pending math so the snapshot uses pre-withdrawal `userLP`; (f) rebase `userRewardDebt[pool][user] = acc`; (g) emit `WithdrawalRecorded(pool, user, amount)`. Underflow at step (e) reverts on over-withdrawal — AuMT recorder is responsible for balance checks; no explicit guard added per H-D16 trust-the-recorder posture. No-underflow invariant on `acc - userRewardDebt[pool][user]` identical to `recordDeposit` — `userRewardDebt` is only ever written as a snapshot of the monotonically non-decreasing `poolAccRewardPerLP[pool]`. Zero-amount withdrawals are permitted.
     * @param pool The Balancer V3 pool address.
     * @param user The AuMT holder losing the stake credit.
     * @param amount The AuMT amount withdrawn; zero permitted.
     */
    function recordWithdrawal(address pool, address user, uint256 amount) external override onlyAuMTContract(pool) {
        _accrueGlobal();
        _settlePool(pool);
        uint256 acc = poolAccRewardPerLP[pool];
        uint256 pending = (acc - userRewardDebt[pool][user]).mulDown(userLP[pool][user]);
        if (pending > 0) {
            pendingBalance[pool][user] += pending;
        }
        // I-D14 effectiveQualBlock clock: any withdrawal resets the qualification
        // clock to 0 (§viii). amount > 0 guard keeps zero-amount calls clock-neutral.
        if (amount > 0) {
            effectiveQualBlock[pool][user] = 0;
        }
        userLP[pool][user] -= amount;
        poolTotalLP[pool] -= amount;
        userRewardDebt[pool][user] = acc;
        emit WithdrawalRecorded(pool, user, amount);
    }

    /* ---------- User claim & pending view (H-D20 / H-D25) ---------- */

    /**
     * @notice Claims accrued AuMM rewards for `msg.sender` in `pool`, minting to `to` per H-D20 / H-D25.
     * @dev H-D20 / H-D21 / H-D25 sole mint site — the only `AuMM.mint` call in the distributor. (a) H-D21 lazy accrual tick `_accrueGlobal()` then per-pool settle `_settlePool(pool)` BEFORE any user-state read, ensuring `poolAccRewardPerLP[pool]` is fresh against `block.number`; (b) `user = msg.sender` — claim is permissionless (no gauge-approval gate; stranded allocations on revoked-gauge pools must remain claimable so existing stakers can exit cleanly, mirroring the H-D16 `recordDeposit` / `recordWithdrawal` posture at L256); `to` parameter supports delegated claims per IEmissionDistributor L130; (c) cache `acc = poolAccRewardPerLP[pool]` (the H-D24 per-LP-unit accumulator); (d) compute the H-D25 additive form `amount = pendingBalance[pool][user] + (acc - userRewardDebt[pool][user]).mulDown(userLP[pool][user])` — crystallized-pending plus live delta against current `userLP`; (e) zero-amount short-circuit per IEmissionDistributor L124 — `if (amount == 0) return;` skips the mint and the event (no `Claimed` emit on zero claims) and skips the `pendingBalance` zero / `userRewardDebt` rebase because they would be no-ops (`pendingBalance == 0` and `userRewardDebt == acc` are the only conditions producing `amount == 0` when `userLP > 0`); (f) effects per CEI — `pendingBalance[pool][user] = 0` zeros the crystallized balance per H-D25 + `userRewardDebt[pool][user] = acc` rebases the per-user snapshot so subsequent `pendingClaim` reads start the live-delta clock from this acc; (g) interaction — `AuMM.mint(to, amount)` per H-D20 / H-D7 (OPEN: requires `IAuMM.setMinter(address(this))` pre-deploy handoff per constructor @dev L90); (h) emit `Claimed(pool, user, to, amount)`. No H-D23 second push — `recordEmissions` happens at `_settlePool` boundary only (allocation-side F-10 semantics per IEmissionDistributor L127). No-underflow invariant on `acc - userRewardDebt[pool][user]` identical to `recordDeposit` / `recordWithdrawal` — `userRewardDebt` is only ever written as a snapshot of the monotonically non-decreasing `poolAccRewardPerLP[pool]`. No reentrancy guard — `AuMM` is the project's own ERC-20 (no callback hooks per Stage C AuMM contract), state mutations precede the mint per CEI, and `to == address(0)` reverts naturally at `AuMM.mint` via OpenZeppelin ERC-20 zero-recipient check.
     * @param pool The Balancer V3 pool address from which rewards are claimed.
     * @param to The AuMM mint recipient — supports delegated claims; `address(0)` reverts at `AuMM.mint` per OpenZeppelin ERC-20 (no explicit guard added).
     */
    function claim(address pool, address to) external override {
        _accrueGlobal();
        _settlePool(pool);
        address user = msg.sender;
        uint256 acc = poolAccRewardPerLP[pool];
        uint256 amount = pendingBalance[pool][user] + (acc - userRewardDebt[pool][user]).mulDown(userLP[pool][user]);
        if (amount == 0) {
            return;
        }
        pendingBalance[pool][user] = 0;
        userRewardDebt[pool][user] = acc;
        AuMM.mint(to, amount);
        emit Claimed(pool, user, to, amount);
    }

    /**
     * @notice Returns the unclaimed AuMM reward balance for `user` in `pool` per H-D25 additive form.
     * @dev H-D16 / H-D24 / H-D25 single-snapshot view — derives `pendingBalance[pool][user] + (poolAccRewardPerLP[pool] - userRewardDebt[pool][user]).mulDown(userLP[pool][user])` per the H-D25 binding and IEmissionDistributor L217. Uses the STORED `poolAccRewardPerLP[pool]` (not a live-simulated value against `block.number`); the view returns a snapshot as of the most recent `_accrueGlobal` + `_settlePool` invocation. Callers needing a fresh value should trigger any mutating entry first (`recordScore` / `recordDeposit` / `recordWithdrawal` / `claim` all invoke `_accrueGlobal` + `_settlePool` per H-D21). The FixedPoint mulDown form matches the AuMM-wei output unit per H-D24 — `pendingBalance` is already AuMM-wei (crystallized at `recordDeposit` / `recordWithdrawal`), and `(acc - userRewardDebt).mulDown(userLP)` converts (FixedPoint AuMM-per-LP-unit × LP-unit count) into AuMM-wei. No-underflow invariant on `poolAccRewardPerLP[pool] - userRewardDebt[pool][user]` identical to `claim` / `recordDeposit` / `recordWithdrawal` — `userRewardDebt` is only ever written as a snapshot of the monotonically non-decreasing `poolAccRewardPerLP[pool]`. Consumed by Stage I AuMT for pre-claim balance display per IEmissionDistributor L219.
     * @param pool The Balancer V3 pool address.
     * @param user The AuMT holder address.
     * @return The pending AuMM claim amount (18-decimal fixed-point).
     */
    function pendingClaim(address pool, address user) external view override returns (uint256) {
        return pendingBalance[pool][user] + (poolAccRewardPerLP[pool] - userRewardDebt[pool][user]).mulDown(userLP[pool][user]);
    }

}
