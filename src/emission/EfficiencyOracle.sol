// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {ITVLOracle} from "../ccb/ITVLOracle.sol";
import {IEfficiencyOracle} from "../gauge/IEfficiencyOracle.sol";
import {AureumTime} from "../lib/AureumTime.sol";

/// @title EfficiencyOracle — concrete `IEfficiencyOracle` implementation per H-D10 (Phase 1: svZCHF numéraire + intra-epoch accumulation + EpochEntry ring buffer)
/// @notice Per-pool 3-epoch SMA of OQ-G1's F-10 efficiency inputs `(swap_fee_revenue_i + yield_fee_revenue_i, emissions_received_i)` — both legs denominated in svZCHF scaled18 via `tvlOracle.quoteSvZCHF` to satisfy G-D23(i)'s same-unit requirement.
/// @dev H-D10 — intra-epoch accumulators (`_accNumerator`, `_accDenominator`, `_accEpoch`) advance via `_ensureCurrentEpoch` (lazy, O(1)); the per-pool `EpochEntry[3]` ring buffer at `_history[pool]` stores finalized epochs at slot `epoch % 3` with the epoch stamp enabling stale-slot detection in the pure view. H-D8 — `governance` slot mirrors TVLOracle's `setGovernanceContract`-pivoting pattern; `feeRecorder` / `emissionsRecorder` are governance-settable feed addresses (Phase 1: Stage H governance Safe; later upgrades wire the fee routing hook and `EmissionDistributor` respectively). Deploy prerequisite per H-D10 v2 (H1.9-bis): `tvlOracle.tokenToUnderlying[AuMM]` must be seeded with a constellation venue pricing AuMM in svZCHF, or `recordEmissions` accumulates 0 and `efficiencyInputs` returns `denominatorSma = 0` post-warmup, triggering `EfficiencyDataUnavailable` reverts in `GaugeEligibility`. Stage K — governance handoff via `setGovernanceContract`.
contract EfficiencyOracle is IEfficiencyOracle {
    /* ---------- Structs ---------- */

    /// @notice Epoch-stamped ring buffer entry per H-D10 — the stored `epoch` field validates the slot against the target epoch during view-side SMA reconstruction; stale slots (epoch older than `currentEpoch - 3`) are implicitly ignored without a zero-fill loop.
    struct EpochEntry {
        uint256 epoch;
        uint256 numerator;
        uint256 denominator;
    }

    /* ---------- Immutables ---------- */

    /// @notice Concrete `ITVLOracle` deployed at H2a — single dependency for `quoteSvZCHF(token, amountScaled18)` calls in `recordFees` + `recordEmissions` per H-D10 v2 (H1.9-bis).
    ITVLOracle public immutable tvlOracle;

    /// @notice Immutable AuMM token address — passed as the `token` argument to `tvlOracle.quoteSvZCHF` in `recordEmissions` to convert AuMM emissions to svZCHF per H-D10 v2.
    address public immutable AuMM;

    /// @notice Stage H genesis block — anchor for `AureumTime.epochIndex(GENESIS_BLOCK, block.number)` calls in `_ensureCurrentEpoch` and `efficiencyInputs` per H-D10. Same precedent as `AuMM.sol` GENESIS_BLOCK.
    uint256 public immutable GENESIS_BLOCK;

    /* ---------- Governance (H-D8 pattern) ---------- */

    /// @notice Governance authority — Stage A–K Safe at deploy; rebound via `setGovernanceContract` at Stage K per H-D8 (mirrors TVLOracle).
    address public governance;

    /// @notice Authorized fee feed — gates `recordFees`; governance-settable via `setFeeRecorder`. Initially the Stage H governance Safe; later upgrades wire the fee routing hook or a fee aggregator. Zero-address-acceptable per H-D10: clearing disables stale-fee accumulation after a feed is deprecated.
    address public feeRecorder;

    /// @notice Authorized emissions feed — gates `recordEmissions`; governance-settable via `setEmissionsRecorder`. Wired to `EmissionDistributor` at H4 deploy. Zero-address-acceptable per H-D10: same safety valve as `feeRecorder`.
    address public emissionsRecorder;

    /* ---------- Intra-epoch accumulators (H-D10) ---------- */

    /// @notice In-progress svZCHF-denominated fee revenue accumulator per pool — flushed to the history ring at the next `_ensureCurrentEpoch` call when `block.number` crosses an epoch boundary.
    mapping(address => uint256) internal _accNumerator;

    /// @notice In-progress svZCHF-denominated emissions accumulator per pool — flushed alongside `_accNumerator` at epoch rollover.
    mapping(address => uint256) internal _accDenominator;

    /// @notice Epoch index currently being accumulated per pool — `0` until the pool's first `recordFees` or `recordEmissions` call; advanced by `_ensureCurrentEpoch` to `AureumTime.epochIndex(GENESIS_BLOCK, block.number)` on rollover.
    mapping(address => uint256) internal _accEpoch;

    /* ---------- History ring (H-D10) ---------- */

    /// @notice Per-pool ring buffer of finalized epochs — fixed size 3 to match `SMOOTHING_EPOCHS = 3` per OQ-4 / FINDINGS L501; epoch `e` writes to slot `e % 3`, overwriting data three epochs prior. Read-side validation in `efficiencyInputs` keys on the stored `EpochEntry.epoch` field — no zero-fill loop required for dormant pools.
    mapping(address => EpochEntry[3]) internal _history;

    /* ---------- Errors ---------- */

    /// @notice Reverts when a zero address is supplied for an immutable or the initial governance slot.
    error ZeroAddress();

    /// @notice Reverts when a non-governance address invokes a governance-only entry point.
    error NotGovernance(address caller);

    /// @notice Reverts when a non-`feeRecorder` address invokes `recordFees`.
    error NotFeeRecorder(address caller);

    /// @notice Reverts when a non-`emissionsRecorder` address invokes `recordEmissions`.
    error NotEmissionsRecorder(address caller);

    /* ---------- Events ---------- */

    /// @notice Emitted when `setGovernanceContract` rebinds the `governance` authority (Stage K handoff per H-D8).
    event GovernanceTransferred(address indexed oldGovernance, address indexed newGovernance);

    /// @notice Emitted when governance rebinds the `feeRecorder` slot per H-D10 — `address(0)` is permitted as a deprecation signal.
    event FeeRecorderSet(address indexed oldRecorder, address indexed newRecorder);

    /// @notice Emitted when governance rebinds the `emissionsRecorder` slot per H-D10 — `address(0)` is permitted as a deprecation signal.
    event EmissionsRecorderSet(address indexed oldRecorder, address indexed newRecorder);

    /// @notice Emitted on each `recordFees` invocation — `pool` and `token` are indexed for off-chain reconstruction; `amountScaled18` is the caller-supplied input, `svZCHFAmountScaled18` is the post-`quoteSvZCHF` conversion (0 when `token` is unmapped in TVLOracle, per H-D10 skip-on-zero semantics).
    event FeesRecorded(address indexed pool, address indexed token, uint256 amountScaled18, uint256 svZCHFAmountScaled18);

    /// @notice Emitted on each `recordEmissions` invocation — `pool` is indexed for off-chain reconstruction; `aummAmountScaled18` is the caller-supplied AuMM emissions amount, `svZCHFAmountScaled18` is the post-`quoteSvZCHF(AuMM, ...)` conversion (0 when the AuMM mapping prerequisite is unsatisfied per H-D10 v2).
    event EmissionsRecorded(address indexed pool, uint256 aummAmountScaled18, uint256 svZCHFAmountScaled18);

    /// @notice Emitted when `_ensureCurrentEpoch` flushes an in-progress accumulator pair to the history ring — `pool` and `epoch` are indexed for off-chain reconstruction of the per-pool SMA window.
    event EpochFinalized(address indexed pool, uint256 indexed epoch, uint256 numerator, uint256 denominator);

    /* ---------- Constructor ---------- */

    /**
     * @notice Wires the four core immutables/governance slot for the H-D10 EfficiencyOracle Phase 1.
     * @dev `feeRecorder` and `emissionsRecorder` default to `address(0)` and must be set post-construction via `setFeeRecorder` / `setEmissionsRecorder` (governance-gated, H2b.3) before `recordFees` / `recordEmissions` calls land per H-D10. ZeroAddress guards apply to the three address parameters; `_genesisBlock` accepts any `uint256` value (deploy-time correctness is governance's responsibility — invalid genesis values yield an arithmetically valid but semantically wrong epoch series via `AureumTime.epochIndex`). No constructor emit for `GovernanceTransferred` — mirrors TVLOracle pattern where the initial governance slot is set silently.
     * @param _tvlOracle Concrete `ITVLOracle` deployed at H2a — required dependency for `quoteSvZCHF` conversions in `recordFees` + `recordEmissions` per H-D10 v2 (H1.9-bis). Reverts `ZeroAddress` on zero input.
     * @param _aumm AuMM token address — passed as the `token` argument to `tvlOracle.quoteSvZCHF` in `recordEmissions` per H-D10 v2. Reverts `ZeroAddress` on zero input. Deploy prerequisite: `tvlOracle.tokenToUnderlying[_aumm]` must be seeded with a constellation venue pricing AuMM in svZCHF, or `recordEmissions` accumulates 0 and post-warmup `efficiencyInputs` returns `denominatorSma = 0`.
     * @param _genesisBlock Stage H genesis block — anchors `AureumTime.epochIndex(GENESIS_BLOCK, block.number)` in `_ensureCurrentEpoch` and `efficiencyInputs` per H-D10. Same precedent as `AuMM.sol` GENESIS_BLOCK; no zero-check (uint256, accepts any value).
     * @param _initialGovernance Initial governance authority — Stage A–K Authorizer Safe at deploy; Stage K rebind via `setGovernanceContract` per H-D8. Reverts `ZeroAddress` on zero input.
     */
    constructor(
        ITVLOracle _tvlOracle,
        address _aumm,
        uint256 _genesisBlock,
        address _initialGovernance
    ) {
        if (address(_tvlOracle) == address(0)) revert ZeroAddress();
        if (_aumm == address(0)) revert ZeroAddress();
        if (_initialGovernance == address(0)) revert ZeroAddress();

        tvlOracle = _tvlOracle;
        AuMM = _aumm;
        GENESIS_BLOCK = _genesisBlock;
        governance = _initialGovernance;
    }

    /* ---------- Modifiers ---------- */

    /// @notice Restricts execution to the current `governance` authority; reverts `NotGovernance(msg.sender)` otherwise.
    /// @dev H-D8 — `setGovernanceContract`-pivoting governance slot mirroring TVLOracle precedent.
    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance(msg.sender);
        _;
    }

    /* ---------- Governance ---------- */

    /**
     * @notice Stage K migration handoff per H-D8 — rebinds governance authority.
     * @dev `onlyGovernance`-gated; reverts `ZeroAddress` on zero input; emits `GovernanceTransferred(oldGovernance, newGovernance)`. Mirrors TVLOracle `setGovernanceContract`.
     * @param newGovernance The new governance authority — typically the on-chain governance contract at Stage K.
     */
    function setGovernanceContract(address newGovernance) external onlyGovernance {
        if (newGovernance == address(0)) revert ZeroAddress();
        address oldGovernance = governance;
        governance = newGovernance;
        emit GovernanceTransferred(oldGovernance, newGovernance);
    }

    /**
     * @notice Rebinds the `feeRecorder` slot per H-D10 — the authorized fee feed that gates `recordFees` (H2b.4).
     * @dev `onlyGovernance`-gated; `address(0)` is permitted as a deprecation signal (clearing disables `recordFees` accumulation after a feed is deprecated, by definition since `msg.sender != address(0)`); emits `FeeRecorderSet(oldRecorder, newRecorder)`. Phase 1 deploy: initially the Stage H governance Safe; later upgrades wire the fee routing hook or a fee aggregator.
     * @param newRecorder The new fee feed address; pass `address(0)` to disable recording.
     */
    function setFeeRecorder(address newRecorder) external onlyGovernance {
        address oldRecorder = feeRecorder;
        feeRecorder = newRecorder;
        emit FeeRecorderSet(oldRecorder, newRecorder);
    }

    /**
     * @notice Rebinds the `emissionsRecorder` slot per H-D10 — the authorized emissions feed that gates `recordEmissions` (H2b.4).
     * @dev `onlyGovernance`-gated; `address(0)` is permitted as a deprecation signal (same safety valve as `setFeeRecorder`); emits `EmissionsRecorderSet(oldRecorder, newRecorder)`. Phase 1 deploy: wired to `EmissionDistributor` at H4 deploy.
     * @param newRecorder The new emissions feed address; pass `address(0)` to disable recording.
     */
    function setEmissionsRecorder(address newRecorder) external onlyGovernance {
        address oldRecorder = emissionsRecorder;
        emissionsRecorder = newRecorder;
        emit EmissionsRecorderSet(oldRecorder, newRecorder);
    }

    /* ---------- Recorder modifiers ---------- */

    /// @notice Restricts execution to the current `feeRecorder` authority; reverts `NotFeeRecorder(msg.sender)` otherwise.
    /// @dev When `feeRecorder == address(0)` (deprecated/uninitialized), every call reverts because `msg.sender` cannot be `address(0)` in standard external-call contexts — the H-D10 deprecation safety valve operates implicitly via the equality check, no special branch.
    modifier onlyFeeRecorder() {
        if (msg.sender != feeRecorder) revert NotFeeRecorder(msg.sender);
        _;
    }

    /// @notice Restricts execution to the current `emissionsRecorder` authority; reverts `NotEmissionsRecorder(msg.sender)` otherwise.
    /// @dev Same `address(0)` safety semantics as `onlyFeeRecorder`.
    modifier onlyEmissionsRecorder() {
        if (msg.sender != emissionsRecorder) revert NotEmissionsRecorder(msg.sender);
        _;
    }

    /* ---------- Internal helpers (H-D10) ---------- */

    /**
     * @notice Advances per-pool epoch accumulation state on epoch rollover — flushes the in-progress accumulator pair into the history ring and resets the accumulators per H-D10.
     * @dev Reads `currentEpoch = AureumTime.epochIndex(GENESIS_BLOCK, block.number)`. If `currentEpoch > _accEpoch[pool]`, writes `EpochEntry { epoch: _accEpoch[pool], numerator: _accNumerator[pool], denominator: _accDenominator[pool] }` to `_history[pool][_accEpoch[pool] % 3]`, emits `EpochFinalized`, resets the accumulators to zero, and advances `_accEpoch[pool]` to `currentEpoch`. Same-epoch calls are no-ops. First-activation for a pool (`_accEpoch[pool] == 0`) at any `currentEpoch > 0` writes a phantom `(epoch:0, num:0, denom:0)` entry into slot 0 on the first rollover — harmless because the read-side epoch-stamp check only matches stored epoch == target epoch (slot 0 stamped with epoch 0 matches only target epoch 0; otherwise the slot contributes 0 to the SMA). O(1) regardless of dormancy duration per H-D10's stale-slot detection design.
     * @param pool The pool whose epoch state is being advanced.
     */
    function _ensureCurrentEpoch(address pool) internal {
        uint256 currentEpoch = AureumTime.epochIndex(GENESIS_BLOCK, block.number);
        uint256 accEpoch = _accEpoch[pool];
        if (currentEpoch > accEpoch) {
            uint256 num = _accNumerator[pool];
            uint256 denom = _accDenominator[pool];
            _history[pool][accEpoch % 3] = EpochEntry({ epoch: accEpoch, numerator: num, denominator: denom });
            emit EpochFinalized(pool, accEpoch, num, denom);
            _accNumerator[pool] = 0;
            _accDenominator[pool] = 0;
            _accEpoch[pool] = currentEpoch;
        }
    }

    /* ---------- Recording (H-D10) ---------- */

    /**
     * @notice Records a per-pool fee revenue contribution per H-D10 v2 — converts `amountScaled18` of `token` to svZCHF via `tvlOracle.quoteSvZCHF` and accumulates the result into `_accNumerator[pool]`.
     * @dev `onlyFeeRecorder`-gated; triggers `_ensureCurrentEpoch(pool)` before accumulating. Skip-on-zero semantics inherited from `quoteSvZCHF`: tokens unmapped in TVLOracle contribute `0` to the accumulator without revert (consistent with the wider H-D10 skip-on-zero design). Emits `FeesRecorded(pool, token, amountScaled18, svZCHFAmountScaled18)` for off-chain reconstruction even when `svZCHFAmountScaled18 == 0` (audit trail clarity).
     * @param pool The pool whose numerator is being accumulated.
     * @param token The token in which the fee revenue is denominated (must be mapped in `tvlOracle.tokenToUnderlying`, else the contribution is silently zeroed).
     * @param amountScaled18 The 18-decimal fixed-point fee revenue amount per Balancer V3 `balancesLiveScaled18` convention.
     */
    function recordFees(address pool, address token, uint256 amountScaled18) external onlyFeeRecorder {
        _ensureCurrentEpoch(pool);
        uint256 svZCHFAmountScaled18 = tvlOracle.quoteSvZCHF(token, amountScaled18);
        _accNumerator[pool] += svZCHFAmountScaled18;
        emit FeesRecorded(pool, token, amountScaled18, svZCHFAmountScaled18);
    }

    /**
     * @notice Records a per-pool AuMM emissions contribution per H-D10 v2 — converts `aummAmountScaled18` of the AuMM token to svZCHF via `tvlOracle.quoteSvZCHF(AuMM, ...)` and accumulates the result into `_accDenominator[pool]`.
     * @dev `onlyEmissionsRecorder`-gated; triggers `_ensureCurrentEpoch(pool)` before accumulating. Skip-on-zero semantics: if the deploy prerequisite (`tvlOracle.tokenToUnderlying[AuMM]` seeded with a constellation venue pricing AuMM in svZCHF) is unsatisfied, contributions are silently zero — post-warmup `efficiencyInputs` will return `denominatorSma = 0`, triggering `EfficiencyDataUnavailable(pool)` reverts in `GaugeEligibility`. Emits `EmissionsRecorded(pool, aummAmountScaled18, svZCHFAmountScaled18)` for off-chain reconstruction.
     * @param pool The pool whose denominator is being accumulated.
     * @param aummAmountScaled18 The 18-decimal fixed-point AuMM emissions amount per Balancer V3 `balancesLiveScaled18` convention.
     */
    function recordEmissions(address pool, uint256 aummAmountScaled18) external onlyEmissionsRecorder {
        _ensureCurrentEpoch(pool);
        uint256 svZCHFAmountScaled18 = tvlOracle.quoteSvZCHF(AuMM, aummAmountScaled18);
        _accDenominator[pool] += svZCHFAmountScaled18;
        emit EmissionsRecorded(pool, aummAmountScaled18, svZCHFAmountScaled18);
    }

    /* ---------- View (H-D10) ---------- */

    /**
     * @notice Returns pre-smoothed F-10 efficiency inputs for `pool` per OQ-G1 — 3-epoch SMA over finalized epochs `(currentEpoch − 1, currentEpoch − 2, currentEpoch − 3)` with early-epoch underflow guard per H-D10.
     * @dev Two-tier retrieval per epoch target: tier 1 — if `_accEpoch[pool] == targetEpoch`, sum the live `_accNumerator[pool]` and `_accDenominator[pool]` (not yet flushed by `_ensureCurrentEpoch`); else tier 2 — read `_history[pool][targetEpoch % 3]` and contribute only when `epoch` matches `targetEpoch` (stale slots contribute 0; no zero-fill loop). Totals divide by `3` always (`sumNumerator / 3`, `sumDenominator / 3`), so dormant-epoch zeros attenuate the SMA. When `denominatorSma == 0` cold path, callers such as `GaugeEligibility` own `EfficiencyDataUnavailable`; this view never reverts.
     * @param pool The Balancer V3 pool address.
     * @return numeratorSma The 3-epoch SMA of `swap_fee_revenue_i + yield_fee_revenue_i` (1e18 fixed-point).
     * @return denominatorSma The 3-epoch SMA of `emissions_received_i` (same unit as `numeratorSma`).
     */
    function efficiencyInputs(address pool) external view override returns (uint256 numeratorSma, uint256 denominatorSma) {
        uint256 currentEpoch = AureumTime.epochIndex(GENESIS_BLOCK, block.number);
        if (currentEpoch < 3) return (0, 0);

        uint256 sumNumerator;
        uint256 sumDenominator;

        for (uint256 i = 1; i <= 3; ++i) {
            uint256 targetEpoch = currentEpoch - i;
            if (_accEpoch[pool] == targetEpoch) {
                sumNumerator += _accNumerator[pool];
                sumDenominator += _accDenominator[pool];
            } else {
                EpochEntry storage entry = _history[pool][targetEpoch % 3];
                if (entry.epoch == targetEpoch) {
                    sumNumerator += entry.numerator;
                    sumDenominator += entry.denominator;
                }
            }
        }

        numeratorSma = sumNumerator / 3;
        denominatorSma = sumDenominator / 3;
    }
}
