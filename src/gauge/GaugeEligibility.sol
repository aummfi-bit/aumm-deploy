// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {IWeightedPool} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import {IBasePoolFactory} from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import {IGaugeEligibility} from "./IGaugeEligibility.sol";
import {IVaultClassRegistry} from "./IVaultClassRegistry.sol";
import {ITVLOracle} from "../ccb/ITVLOracle.sol";

/**
 * @title GaugeEligibility
 * @notice Auto-gauge eligibility evaluator — 52% Quality Gate per **G-D8**, TVL floor per **OQ-G2**, pool-type whitelist per **G-D6**, F-10 efficiency tournament per **G-D3**, threshold transition events per **G-D5**.
 * @dev G2.3 — constructor body + `_compute52PctNumerator` (G-D8 + G-D10); G2.4 — `_checkEligibilityCriteria` (OQ-G2 + G-D6 + G-D15a); **G2.4-post** — F-D23 one-shot setter for `gaugeRegistry` + `onlyGaugeRegistry` modifier per **G-D22** (caller-restriction lock for `computeEpochSnapshot`; mirrors `VaultClassRegistry.setAuMT` at G1.12 literally). **G2.5** — `computeEpochSnapshot` (carries `onlyGaugeRegistry`). **G2.6** — `evaluateEligibility` / `isEligible` / `cohortOf` / `snapshotEpoch` implementations and `is IGaugeEligibility` inheritance (deferred to G2.6 per G1.11 precedent).
 */
contract GaugeEligibility {
    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice G-D15a singleton Balancer pool factory — no setter; set once at deploy.
    address public immutable approvedFactory;

    /// @notice `VaultClassRegistry` binding for 52% numerator admission lookups per G-D8.
    address public immutable vaultClassRegistry;

    /// @notice TVL and fee-revenue oracle per OQ-G1 / OQ-22.
    address public immutable tvlOracle;

    /// @notice Balancer V3 vault for pool token and factory reads at G2.3+.
    address public immutable vault;

    /// @notice T-I3 forbidden-token block — AuMM; compared against every pool token in the 52% path.
    address internal immutable _auMM;

    /// @notice T-I3 forbidden-token block — AuMT; compared against every pool token in the 52% path.
    address internal immutable _auMT;

    // -------------------------------------------------------------------------
    // Constants (G-D15 G2.0 lock)
    // -------------------------------------------------------------------------

    /// @notice Minimum TVL in svZCHF (18 decimals) for pool-type gate per G-D15c — **Coarse anti-spam gate, not oracle-precise USD**.
    uint256 public constant TVL_FLOOR_SVZCHF = 10_000e18;

    /// @notice Favored cohort size as basis points of the ranked set (1500 = 15%) per G-D3 / OQ-G1.
    uint256 public constant FAVORED_COHORT_BPS = 1500;

    /// @notice Oracle smoothing horizon in epochs for OQ-G1 EMA discipline.
    uint256 public constant SMOOTHING_EPOCHS = 3;

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    mapping(address => bool) public isGaugeEligible;

    mapping(address => bool) public isFavoredCohort;

    mapping(address => uint256) public lastSnapshotEpoch;

    uint256 public currentSnapshotEpoch;

    // -------------------------------------------------------------------------
    // Post-deploy wiring (F-D23 pattern per G-D22)
    // -------------------------------------------------------------------------

    /// @notice GaugeRegistry binding wired post-deploy via `setGaugeRegistry` (G-D22 / G1.12 mirror) — storage, not immutable, because GaugeRegistry's constructor depends on `IGaugeEligibility`.
    address public gaugeRegistry;

    /// @notice one-shot, cleared on first `setGaugeRegistry` call (F-D23 pattern).
    address public gaugeRegistrySetter;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /**
     * @notice Emitted on top-to-bottom cohort crossing when a pool drops out of the favored set (T-T2).
     * @param pool The Balancer pool address.
     * @param epoch Snapshot epoch index for this transition.
     * @param tvlSma Smoothed TVL anchor in **svZCHF-denominated 18-decimal fixed point** per `ITVLOracle` / OQ-22.
     * @param efficiencyRatio F-10 fee-revenue-over-TVL efficiency ratio from `11_formulas.md`, scaled 1e18 after OQ-G1 smoothing.
     */
    event GaugeEfficiencyDropped(address indexed pool, uint256 indexed epoch, uint256 tvlSma, uint256 efficiencyRatio);

    /**
     * @notice Emitted on bottom-to-top cohort crossing when a pool enters the favored set (T-T1).
     * @param pool The Balancer pool address.
     * @param epoch Snapshot epoch index for this transition.
     * @param tvlSma Smoothed TVL anchor in **svZCHF-denominated 18-decimal fixed point** per `ITVLOracle` / OQ-22.
     * @param efficiencyRatio F-10 fee-revenue-over-TVL efficiency ratio from `11_formulas.md`, scaled 1e18 after OQ-G1 smoothing.
     */
    event GaugeEfficiencyRising(address indexed pool, uint256 indexed epoch, uint256 tvlSma, uint256 efficiencyRatio);

    // -------------------------------------------------------------------------
    // Custom errors
    // -------------------------------------------------------------------------

    error ZeroAddress();

    error ForbiddenToken(address token);

    error PoolTypeNotWhitelisted(address factory);

    error TVLFloorNotMet(uint256 tvl, uint256 floor);

    error InsufficientQualityGate(uint256 numerator);

    error EfficiencyDataUnavailable(address pool);

    error OnlyGaugeRegistry(address caller);

    error OnlyGaugeRegistrySetter();

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    /// @notice Gates `computeEpochSnapshot` to the wired `gaugeRegistry` per G-D22 (T-I5 epoch-snapshot determinism).
    modifier onlyGaugeRegistry() {
        if (msg.sender != gaugeRegistry) revert OnlyGaugeRegistry(msg.sender);
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Wires the six deploy-time dependencies for eligibility evaluation and the 52% numerator path.
     * @dev Assigns all immutables after **G-D15a** / G-D8 / OQ-1 address validation — any zero input reverts **ZeroAddress** before storage binds.
     * @param approvedFactory_ Balancer pool factory admitted for G-D15a singleton equality checks.
     * @param vaultClassRegistry_ **G-D8** `VaultClassRegistry` for ERC-4626 class admission look-ups.
     * @param tvlOracle_ Oracle binding for TVL / fee inputs at **G2.4+** / **G2.5**.
     * @param vault_ Balancer V3 vault for pool token reads at **G2.4+**.
     * @param auMM_ T-I3 forbidden token — AuMM.
     * @param auMT_ T-I3 forbidden token — AuMT.
     * @param gaugeRegistrySetter_ One-shot setter authority for wiring `gaugeRegistry` post-deploy per **G-D22**.
     */
    constructor(
        address approvedFactory_,
        address vaultClassRegistry_,
        address tvlOracle_,
        address vault_,
        address auMM_,
        address auMT_,
        address gaugeRegistrySetter_
    ) {
        if (approvedFactory_ == address(0)) revert ZeroAddress();
        if (vaultClassRegistry_ == address(0)) revert ZeroAddress();
        if (tvlOracle_ == address(0)) revert ZeroAddress();
        if (vault_ == address(0)) revert ZeroAddress();
        if (auMM_ == address(0)) revert ZeroAddress();
        if (auMT_ == address(0)) revert ZeroAddress();
        if (gaugeRegistrySetter_ == address(0)) revert ZeroAddress();

        approvedFactory = approvedFactory_;
        vaultClassRegistry = vaultClassRegistry_;
        tvlOracle = tvlOracle_;
        vault = vault_;
        _auMM = auMM_;
        _auMT = auMT_;
        gaugeRegistrySetter = gaugeRegistrySetter_;
    }

    // -------------------------------------------------------------------------
    // One-shot setters (F-D23 pattern)
    // -------------------------------------------------------------------------

    /// @notice Wires `gaugeRegistry` from the designated setter and seals the `gaugeRegistrySetter` slot per **G-D22** F-D23 pattern.

    function setGaugeRegistry(address gaugeRegistry_) external {
        if (msg.sender != gaugeRegistrySetter) revert OnlyGaugeRegistrySetter();
        if (gaugeRegistry_ == address(0)) revert ZeroAddress();
        gaugeRegistry = gaugeRegistry_;
        gaugeRegistrySetter = address(0);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Accumulates normalized weights for ERC-4626 pool tokens whose underlying implementation class is admitted — the **G-D8** 52% Quality Gate numerator.
     * @dev **G-D10** — `try IERC4626(token).asset()`/`catch` discriminates ERC-4626Claiming candidates from plain ERC-20s; **T-I3** blocks AuMM / AuMT before the probe. Non-4626 tokens hit an empty `catch` and add **0**; admitted 4626 tokens add `weights[i]`.
     * @param tokens Pool token set aligned index-wise with `weights`.
     * @param weights Normalized weights from `IBasePool.getNormalizedWeights` — same length as `tokens`.
     * @return numerator Sum of weights for admitted ERC-4626 classes, **1e18**-scale fixed-point compatible with the half-pool bar.
     */
    function _compute52PctNumerator(IERC20[] memory tokens, uint256[] memory weights)
        internal
        view
        returns (uint256 numerator)
    {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ++i) {
            address token = address(tokens[i]);
            if (token == _auMM || token == _auMT) revert ForbiddenToken(token);

            try IERC4626(token).asset() returns (address) {
                if (IVaultClassRegistry(vaultClassRegistry).isAdmittedClass(token)) {
                    numerator += weights[i];
                }
            } catch {
                // Plain ERC-20 — no numerator contribution (G-D10 empty catch).
            }
        }
    }

    /**
     * @notice Aggregate binary eligibility gate for `pool` per **OQ-G2** + **G-D6** + **G-D15a** + **G-D8** — reverts on first failed criterion.
     * @dev Body order locked at **G2.4**: numerator path (forbidden tokens + **G-D10** + admitted class weights) then factory provenance, TVL floor, then **0.52e18** quality bar. Caller must pass a weighted pool implementing `IWeightedPool`.
     * @param pool Balancer pool address under evaluation.
     */
    function _checkEligibilityCriteria(address pool) internal view {
        IERC20[] memory tokens = IVault(vault).getPoolTokens(pool);
        uint256[] memory weights = IWeightedPool(pool).getNormalizedWeights();
        uint256 numerator = _compute52PctNumerator(tokens, weights);
        if (!IBasePoolFactory(approvedFactory).isPoolFromFactory(pool)) revert PoolTypeNotWhitelisted(approvedFactory);
        uint256 tvl = ITVLOracle(tvlOracle).tvl(pool);
        if (tvl < TVL_FLOOR_SVZCHF) revert TVLFloorNotMet(tvl, TVL_FLOOR_SVZCHF);
        if (numerator < 0.52e18) revert InsufficientQualityGate(numerator);
    }
}
