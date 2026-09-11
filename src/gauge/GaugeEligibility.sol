// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {IWeightedPool} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import {IBasePoolFactory} from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import {IGaugeEligibility} from "./IGaugeEligibility.sol";
import {IVaultClassRegistry} from "./IVaultClassRegistry.sol";
import {IEfficiencyOracle} from "./IEfficiencyOracle.sol";
import {ITVLOracle} from "../ccb/ITVLOracle.sol";
import {IAureumFeeRoutingHook} from "../fee_router/IAureumFeeRoutingHook.sol";
import {AureumTime} from "../lib/AureumTime.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title GaugeEligibility
 * @notice Auto-gauge eligibility evaluator — 52% Quality Gate per **G-D8**, TVL floor per **OQ-G2**, pool-type whitelist per **G-D6**, F-10 efficiency tournament per **G-D3**, threshold transition events per **G-D5**.
 * @dev G2.3 — constructor body + `_compute52PctNumerator` (G-D8 + G-D10); G2.4 — `_checkEligibilityCriteria` (OQ-G2 + G-D6 + G-D15a); **G2.4-post** — F-D23 one-shot setter for `gaugeRegistry` + `onlyGaugeRegistry` modifier per **G-D22** (caller-restriction lock for `computeEpochSnapshot`; mirrors `VaultClassRegistry.setAuMT` at G1.12 literally). **G2.5-pre-2** — IEfficiencyOracle sibling import + 8-arg constructor + `efficiencyOracle` immutable + event ABI reshape (`tvlSma` → `numeratorSma` + `denominatorSma`) per **G-D23 (iii)** + `firstTournamentEpoch` storage per **G-D23 (v)**. **G2.5** — `computeEpochSnapshot` (carries `onlyGaugeRegistry`; reads `IEfficiencyOracle.efficiencyInputs` pair per **G-D23 (i)** with cold-start grace via `firstTournamentEpoch` per **G-D23 (v)**). **G2.6** — `evaluateEligibility` (per-pool gate via `_checkEligibilityCriteria` + latch write) + view bridges `isEligible` / `cohortOf` / `snapshotEpoch` + `is IGaugeEligibility` inheritance per **G-D5** / **T-I5**.
 */
contract GaugeEligibility is IGaugeEligibility {
    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice G-D15a singleton Balancer pool factory — no setter; set once at deploy.
    address public immutable approvedFactory;

    /// @notice `VaultClassRegistry` binding for 52% numerator admission lookups per G-D8.
    address public immutable vaultClassRegistry;

    /// @notice TVL and fee-revenue oracle per OQ-G1 / OQ-22.
    address public immutable tvlOracle;

    /// @notice F-10 efficiency oracle per **G-D23 (i)** — pre-smoothed numerator/denominator inputs for the canonical OQ-G1 formula `(swap_fee_revenue_i + yield_fee_revenue_i) / emissions_received_i`; oracle owns the 3-epoch SMA, contract reads pre-smoothed pair.
    address public immutable efficiencyOracle;

    /// @notice Balancer V3 vault for pool token and factory reads at G2.3+.
    address public immutable vault;

    /// @notice Canonical AureumFeeRoutingHook — the only hook a gauge-eligible pool may carry per **I-D13** / **OQ-24**; `_checkEligibilityCriteria` rejects any pool whose `IVault(vault).getHooksConfig(pool).hooksContract` differs. Set once at deploy; no setter.
    address public immutable feeRoutingHook;

    /// @notice T-I3 forbidden-token block — AuMM; compared against every pool token in the 52% path.
    address internal immutable _auMM;

    // -------------------------------------------------------------------------
    // Constants (G-D15 G2.0 lock)
    // -------------------------------------------------------------------------

    /// @notice Minimum TVL in svZCHF (18 decimals) for pool-type gate per G-D15c — **Coarse anti-spam gate, not oracle-precise USD**.
    uint256 public constant TVL_FLOOR_SVZCHF = 10_000e18;

    /// @notice Favored cohort size as basis points of the ranked set (1500 = 15%) per G-D3 / OQ-G1.
    uint256 public constant FAVORED_COHORT_BPS = 1500;

    /// @notice Oracle smoothing horizon in epochs for OQ-G1 EMA discipline.
    uint256 public constant SMOOTHING_EPOCHS = 3;

    /// @notice **PP-D50** (vii) delay a `recoveryPathAdmitted` revocation waits before `finalizeRecoveryPathRevocation` may clear it — one full `AureumGovernance` proposal lifecycle plus one block, so a revocation cannot outrun a composition mandate already snapshotted at propose.
    /// @dev **PP-D50** amendment (xiii). MIRRORS the `AureumTime` expansion `AureumGovernance.sol:28-31` uses for its own four lifecycle constants, plus one block; it does NOT read them through the `AureumGovernance` type, which is invalid Solidity — `public constant` on a contract yields instance getters, not type-level members. **RB-026** is discharged by a unit pin asserting this equals the sum of those four PUBLIC GETTERS plus one, the only form that catches governance changing a term while this formula sits still. 223,201 blocks at canonical figures.
    uint256 public constant REVOCATION_DELAY_BLOCKS =
        AureumTime.BLOCKS_PER_DAY + AureumTime.BLOCKS_PER_EPOCH + 2 * AureumTime.BLOCKS_PER_DAY
            + AureumTime.BLOCKS_PER_EPOCH + 1;

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    mapping(address => bool) public isGaugeEligible;

    mapping(address => bool) public isFavoredCohort;

    mapping(address => uint256) public lastSnapshotEpoch;

    /// @notice First epoch index at which `pool` was ranked in `computeEpochSnapshot` per **G-D23 (v)** — single-purpose cold-start grace predicate; set once on first appearance and gates the 3-epoch warmup window. Never overloaded with `lastSnapshotEpoch` semantics.
    mapping(address => uint256) public firstTournamentEpoch;

    uint256 public currentSnapshotEpoch;

    /// @notice F-10 per-pool emission cap in basis points assigned by the last `computeEpochSnapshot` — 0 (uncapped, top 85%), 100 (bottom 15–10%, 1%), 50 (bottom 10–5%, 0.5%), 10 (bottom 5%, 0.1%) — **P-D13 (3)** / **P-D15 (2)**. Written each epoch for every ranked pool (including 0 that un-caps a pool which climbed back into the top 85% — self-correction per spec L129). Skipped pools retain their prior value per **P-D15 (4)**, and **PP-D56 (viii)** changes which pools those are: the order is now zero numerator, zero denominator, cold-start, warmup, with both zero-input skips preceding the stamp — so a pool that loses its feed keeps whatever cap it last earned, and one that never had a feed keeps the 0 it started with. Consumed by the EmissionDistributor via `IGaugeRegistry` delegation (F16e / F16f).
    mapping(address => uint256) public poolEmissionCapBps;

    /// @notice **PB-D69 (viii)** governance authority over the recovery-path admission map — gates `setRecoveryPathAdmitted` and its own rotation via `proposeAdmissionAuthority`. Storage rather than immutable and rotatable rather than one-shot, inverting the `setGaugeRegistry` pattern below: a burned authority here would leave a dead map in which no rail-less pool could ever be admitted again. Seated at genesis on the same Safe that holds `AureumFeeRoutingHook.governanceModule`, never `AureumGovernance` (**PB-D61 (iii)**), because admission is an ops commitment tied to a manual call rather than a proposal.
    address public admissionAuthority;

    /// @notice **PB-D69** no-fees-no-emissions attestation — `true` when `admissionAuthority` has committed to recovering this pool's stranded protocol fees through the PB-D66 `recoverStrandedFees` path on `AureumFeeRoutingHook`. Read at **PB3.12c** as the second disjunct of the eligibility conjunct, so a pool carrying no der-Bodensee rail (`poolBodenseeDepositToken(pool) == address(0)`; live instance `02 ixAetheron`) stays eligible only while admitted. Deliberately an attestation and NOT a route registry per **PB-D69 (vi)** — recovery takes its route as calldata and carries no pool identifier, so nothing on that path could consume a per-pool route. It certifies capability-of-ops, never contribution (**PB-D69 (vii)**).
    mapping(address => bool) public recoveryPathAdmitted;

    /// @notice **PP-D50** (xii) scheduled-revocation stamp — the block at or after which `finalizeRecoveryPathRevocation` may clear `recoveryPathAdmitted[pool]`. Zero means no revocation is pending.
    mapping(address => uint256) public revocationEffectiveBlock;

    /// @notice **PP-D50** (viii) incoming admission authority awaiting its own `acceptAdmissionAuthority` call — zero when no rotation is pending.
    address public pendingAdmissionAuthority;

    /// @notice One entry of the paginated tournament's ranked scratch per **PP-D56 (iv)**.
    /// @dev Carries the two SMAs the transition events already emit, so a finalize page can emit
    ///      without re-reading the oracle. Storage, because accumulation spans transactions.
    struct RankedEntry {
        address pool;
        uint128 numeratorSma;
        uint128 denominatorSma;
        uint256 efficiencyRatio;
    }

    /// @notice Ranked scratch for the paginated tournament, kept SORTED by insertion during
    ///         accumulation per **PP-D56 (x)**, so finalize needs no global pass.
    /// @dev Ordering is **G-D23 (iv)** / **T-T3** unchanged: descending by ratio, address-ascending
    ///      on a tie. Entries beyond `nRanked` are STALE BY DESIGN, because the last finalize page
    ///      clears the scratch LOGICALLY by zeroing `nRanked` rather than deleting entries: a
    ///      physical clear is one unbounded write set per epoch, which would reinstate on that page
    ///      the very bound (x) exists to impose, and overwriting a nonzero slot is cheaper anyway.
    RankedEntry[] internal _rankedScratch;

    /// @notice Live entry count at the head of `_rankedScratch` per **PP-D56 (iv)**. Final once
    ///         accumulation completes, so every finalize page derives the same percentile bands.
    uint256 public nRanked;

    /// @notice Epoch whose accumulation is in progress, zero when idle, per **PP-D56 (iv)**.
    /// @dev Mirrors the slot of the same name on `GaugeRegistry`; the two must agree for a page.
    uint256 public accumulationEpoch;

    /// @notice Next `_rankedScratch` index awaiting cap assignment per **PP-D56 (x)**. Reaching
    ///         `nRanked` marks finalization complete; there is no completion boolean, by design.
    uint256 public finalizeCursor;

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
     * @param numeratorSma 3-epoch SMA of `swap_fee_revenue_i + yield_fee_revenue_i` per OQ-G1 / **G-D23 (i)**.
     * @param denominatorSma 3-epoch SMA of `emissions_received_i` per OQ-G1 / **G-D23 (i)**; same unit as `numeratorSma` (F-10 is price-agnostic).
     * @param efficiencyRatio F-10 dimensionless ratio `(numeratorSma * 1e18) / denominatorSma` per OQ-G1 / **G-D23 (i)**, 1e18 fixed-point.
     */
    event GaugeEfficiencyDropped(address indexed pool, uint256 indexed epoch, uint256 numeratorSma, uint256 denominatorSma, uint256 efficiencyRatio);

    /**
     * @notice Emitted on bottom-to-top cohort crossing when a pool enters the favored set (T-T1).
     * @param pool The Balancer pool address.
     * @param epoch Snapshot epoch index for this transition.
     * @param numeratorSma 3-epoch SMA of `swap_fee_revenue_i + yield_fee_revenue_i` per OQ-G1 / **G-D23 (i)**.
     * @param denominatorSma 3-epoch SMA of `emissions_received_i` per OQ-G1 / **G-D23 (i)**; same unit as `numeratorSma` (F-10 is price-agnostic).
     * @param efficiencyRatio F-10 dimensionless ratio `(numeratorSma * 1e18) / denominatorSma` per OQ-G1 / **G-D23 (i)**, 1e18 fixed-point.
     */
    event GaugeEfficiencyRising(address indexed pool, uint256 indexed epoch, uint256 numeratorSma, uint256 denominatorSma, uint256 efficiencyRatio);

    /**
     * @notice Emitted when `acceptAdmissionAuthority` completes a rotation of the **PB-D69** admission authority.
     * @param oldAuthority The authority in force before the rotation.
     * @param newAuthority The authority in force after the rotation.
     */
    event AdmissionAuthorityTransferred(address indexed oldAuthority, address indexed newAuthority);

    /**
     * @notice Emitted when the recovery-path flag is actually WRITTEN — the admission branch of `setRecoveryPathAdmitted`, and a revocation once `finalizeRecoveryPathRevocation` clears it. Per **PP-D50** amendment (xii) it no longer fires on every `setRecoveryPathAdmitted` call: the revocation branch only schedules, and emits `RecoveryPathRevocationScheduled` instead.
     * @param pool The pool whose recovery-path attestation was written.
     * @param admitted The value written — `true` from the admission branch, `false` from a finalized revocation.
     */
    event RecoveryPathAdmissionSet(address indexed pool, bool admitted);

    /**
     * @notice Emitted when `setRecoveryPathAdmitted(pool, false)` SCHEDULES a revocation per **PP-D50** (xii) — the flag itself is unchanged until `finalizeRecoveryPathRevocation` runs.
     * @param pool The pool whose revocation was scheduled.
     * @param effectiveBlock The block at or after which the revocation may be finalized.
     */
    event RecoveryPathRevocationScheduled(address indexed pool, uint256 effectiveBlock);

    /**
     * @notice Emitted when the current authority nominates its successor per **PP-D50** (viii); the rotation completes only when that address calls `acceptAdmissionAuthority`.
     * @param currentAuthority The authority making the nomination.
     * @param pendingAuthority The nominated address, which must accept before it takes effect.
     */
    event AdmissionAuthorityProposed(address indexed currentAuthority, address indexed pendingAuthority);

    // -------------------------------------------------------------------------
    // Custom errors
    // -------------------------------------------------------------------------

    error ZeroAddress();

    error ForbiddenToken(address token);

    error PoolTypeNotWhitelisted(address factory);

    error TVLFloorNotMet(uint256 tvl, uint256 floor);

    error InsufficientQualityGate(uint256 numerator);

    error OnlyGaugeRegistry(address caller);

    error OnlyGaugeRegistrySetter();

    error WrongFeeRoutingHook(address pool, address actualHook);

    error OnlyAdmissionAuthority(address caller);

    error NoFeeRailAndNotAdmitted(address pool);

    error RecoveryPathNotAdmitted(address pool);

    error NoPendingRevocation(address pool);

    error RevocationNotMatured(address pool, uint256 effectiveBlock);

    error OnlyPendingAdmissionAuthority(address caller);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    /// @notice Gates `computeEpochSnapshot` to the wired `gaugeRegistry` per G-D22 (T-I5 epoch-snapshot determinism).
    modifier onlyGaugeRegistry() {
        if (msg.sender != gaugeRegistry) revert OnlyGaugeRegistry(msg.sender);
        _;
    }

    /// @notice Gates the **PB-D69** admission surface — `setRecoveryPathAdmitted` and `proposeAdmissionAuthority` — to the current `admissionAuthority`. `acceptAdmissionAuthority` sits deliberately OUTSIDE this gate, guarded by the pending slot instead, so the incoming holder rather than the outgoing one completes a rotation.
    modifier onlyAdmissionAuthority() {
        if (msg.sender != admissionAuthority) revert OnlyAdmissionAuthority(msg.sender);
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Wires the nine deploy-time dependencies for eligibility evaluation, the 52% numerator path, and the **PB-D69** admission surface.
     * @dev Assigns all immutables after **G-D15a** / G-D8 / OQ-1 address validation — any zero input reverts **ZeroAddress** before storage binds.
     * @param approvedFactory_ Balancer pool factory admitted for G-D15a singleton equality checks.
     * @param vaultClassRegistry_ **G-D8** `VaultClassRegistry` for ERC-4626 class admission look-ups.
     * @param tvlOracle_ Oracle binding for TVL / fee inputs at **G2.4+** / **G2.5**.
     * @param vault_ Balancer V3 vault for pool token reads at **G2.4+**.
     * @param auMM_ T-I3 forbidden token — AuMM.
     * @param gaugeRegistrySetter_ One-shot setter authority for wiring `gaugeRegistry` post-deploy per **G-D22**.
     * @param efficiencyOracle_ **G-D23 (i)** + **G-D23 (ii)** F-10 efficiency oracle binding (sibling to `tvlOracle`) for the OQ-G1 canonical formula at **G2.5**.
     * @param feeRoutingHook_ Canonical `AureumFeeRoutingHook` — the only hook a gauge-eligible pool may carry per **I-D13** / **OQ-24**.
     * @param admissionAuthority_ **PB-D69 (viii)** initial admission authority for `recoveryPathAdmitted` — seated on the same Safe as the hook's `governanceModule`, rotatable thereafter via the `proposeAdmissionAuthority` and `acceptAdmissionAuthority` handshake.
     */
    constructor(
        address approvedFactory_,
        address vaultClassRegistry_,
        address tvlOracle_,
        address vault_,
        address auMM_,
        address gaugeRegistrySetter_,
        address efficiencyOracle_,
        address feeRoutingHook_,
        address admissionAuthority_
    ) {
        if (approvedFactory_ == address(0)) revert ZeroAddress();
        if (vaultClassRegistry_ == address(0)) revert ZeroAddress();
        if (tvlOracle_ == address(0)) revert ZeroAddress();
        if (vault_ == address(0)) revert ZeroAddress();
        if (auMM_ == address(0)) revert ZeroAddress();
        if (gaugeRegistrySetter_ == address(0)) revert ZeroAddress();
        if (efficiencyOracle_ == address(0)) revert ZeroAddress();
        if (feeRoutingHook_ == address(0)) revert ZeroAddress();
        if (admissionAuthority_ == address(0)) revert ZeroAddress();

        approvedFactory = approvedFactory_;
        vaultClassRegistry = vaultClassRegistry_;
        tvlOracle = tvlOracle_;
        vault = vault_;
        _auMM = auMM_;
        gaugeRegistrySetter = gaugeRegistrySetter_;
        efficiencyOracle = efficiencyOracle_;
        feeRoutingHook = feeRoutingHook_;
        admissionAuthority = admissionAuthority_;
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
    // External — PB-D69 recovery-path admission (no fees, no emissions)
    // -------------------------------------------------------------------------

    /**
     * @notice Writes the **PB-D69** recovery-path attestation for `pool` — `true` admits immediately, `false` SCHEDULES a revocation rather than performing one.
     * @dev `onlyAdmissionAuthority`-gated. **PP-D50** amendment (xii) splits the two directions. Admission is immediate and additionally CLEARS any pending stamp, so re-admitting cancels a scheduled revocation. Revocation writes nothing to the flag: it stamps `revocationEffectiveBlock[pool]` one `REVOCATION_DELAY_BLOCKS` out, and the flag falls only when anyone calls `finalizeRecoveryPathRevocation` at or after that block — so a revocation cannot annul a composition mandate already snapshotted at propose. Reverts `RecoveryPathNotAdmitted` when revoking a pool that is not admitted, since a stamp there would leave finalize writing false over false. Re-stamping while a schedule is pending is legal and only moves the effective block later; cancellation is the `true` call. The former idempotence claim is WITHDRAWN — the two directions no longer share a body.
     * @param pool The pool whose attestation is written.
     * @param admitted `true` to admit the pool's recovery path immediately, `false` to schedule its revocation.
     */
    function setRecoveryPathAdmitted(address pool, bool admitted) external onlyAdmissionAuthority {
        if (pool == address(0)) revert ZeroAddress();
        if (admitted) {
            recoveryPathAdmitted[pool] = true;
            delete revocationEffectiveBlock[pool];
            emit RecoveryPathAdmissionSet(pool, true);
        } else {
            if (!recoveryPathAdmitted[pool]) revert RecoveryPathNotAdmitted(pool);
            uint256 effectiveBlock = block.number + REVOCATION_DELAY_BLOCKS;
            revocationEffectiveBlock[pool] = effectiveBlock;
            emit RecoveryPathRevocationScheduled(pool, effectiveBlock);
        }
    }

    /**
     * @notice Permissionlessly clears `recoveryPathAdmitted[pool]` once a scheduled revocation has matured, completing the two-step that `setRecoveryPathAdmitted(pool, false)` begins.
     * @dev Deliberately NOT `onlyAdmissionAuthority` per **PP-D50** amendment (xii): the authority has already made the decision, and gating execution behind the same key would let a revocation be scheduled and then never executed, leaving the pool's status indefinitely ambiguous. The two guards are distinct so an operator can tell nothing-scheduled from scheduled-but-early — `NoPendingRevocation` on a zero stamp, `RevocationNotMatured` carrying the effective block otherwise. The stamp is cleared in the same call that consumes it, so a finalized revocation leaves no live schedule behind, and the write emits `RecoveryPathAdmissionSet` rather than a third event, being an admission-state change like any other.
     * @param pool The pool whose matured revocation is finalized.
     */
    function finalizeRecoveryPathRevocation(address pool) external {
        uint256 effectiveBlock = revocationEffectiveBlock[pool];
        if (effectiveBlock == 0) revert NoPendingRevocation(pool);
        if (block.number < effectiveBlock) revert RevocationNotMatured(pool, effectiveBlock);
        delete revocationEffectiveBlock[pool];
        recoveryPathAdmitted[pool] = false;
        emit RecoveryPathAdmissionSet(pool, false);
    }

    /**
     * @notice Nominates `newAuthority` as the incoming **PB-D69** admission authority; the rotation completes only when that address calls `acceptAdmissionAuthority`.
     * @dev `onlyAdmissionAuthority`-gated and REPEATABLE per **PB-D69 (viii)** — deliberately not the one-shot `setGaugeRegistry` pattern, because a burned authority leaves a dead map no rail-less pool could ever clear. **PP-D50** amendment (xii) splits the former single-step write into a nomination and an acceptance, so a rotation aimed at an address that cannot transact is no longer a one-transaction brick. A later nomination REPLACES an earlier pending one, so a mistaken nomination is corrected by making another rather than by waiting. Passing `address(0)` reverts rather than clearing, since a zero pending slot is exactly what `acceptAdmissionAuthority` reads as no rotation in flight.
     * @param newAuthority The nominated incoming authority; must be non-zero.
     */
    function proposeAdmissionAuthority(address newAuthority) external onlyAdmissionAuthority {
        if (newAuthority == address(0)) revert ZeroAddress();
        pendingAdmissionAuthority = newAuthority;
        emit AdmissionAuthorityProposed(admissionAuthority, newAuthority);
    }

    /**
     * @notice Completes a rotation nominated by `proposeAdmissionAuthority`; callable only by the nominated address.
     * @dev **PP-D50** amendment (xii). Reverts `OnlyPendingAdmissionAuthority` for every other caller, the outgoing authority included — that is what makes this a handshake rather than a push, since the incoming address proves it can transact before it holds the map. With no rotation in flight the pending slot is zero and no real caller matches it, so the same guard covers that case without a second one. Clears the pending slot in the same call, so a nomination cannot be replayed, and emits `AdmissionAuthorityTransferred` exactly as the single-step form did.
     */
    function acceptAdmissionAuthority() external {
        address pending = pendingAdmissionAuthority;
        if (msg.sender != pending) revert OnlyPendingAdmissionAuthority(msg.sender);
        address oldAuthority = admissionAuthority;
        admissionAuthority = pending;
        delete pendingAdmissionAuthority;
        emit AdmissionAuthorityTransferred(oldAuthority, pending);
    }

    // -------------------------------------------------------------------------
    // External — F-10 efficiency tournament (G-D3 + OQ-G1 + G-D22 + G-D23)
    // -------------------------------------------------------------------------

    /// @dev Inserts one survivor at its sorted position per **PP-D56 (x)**, descending by ratio
    ///      with an address-ascending tie, which is **G-D23 (iv)** / **T-T3** unchanged.
    function _insertRanked(address pool, uint256 num, uint256 den, uint256 ratio) internal {
        uint256 n = nRanked;
        if (_rankedScratch.length == n) _rankedScratch.push();
        uint256 j = n;
        while (
            j > 0 &&
            (_rankedScratch[j - 1].efficiencyRatio < ratio ||
                (_rankedScratch[j - 1].efficiencyRatio == ratio && _rankedScratch[j - 1].pool > pool))
        ) {
            _rankedScratch[j] = _rankedScratch[j - 1];
            --j;
        }
        _rankedScratch[j] = RankedEntry(pool, SafeCast.toUint128(num), SafeCast.toUint128(den), ratio);
        nRanked = n + 1;
    }

    /// @dev One pool's accumulation work in the **PP-D56 (viii)** gate order: oracle read,
    ///      zero-numerator skip, zero-denominator skip, cold-start stamp, warmup gate, then the
    ///      ranked insert. The numerator skip is E.7a's fix per **PP-D56 (iii)**: a zero numerator
    ///      gives every pool alike a zero ratio, which would collapse the sort onto its address
    ///      tiebreak and assign cap tiers by ADDRESS. The denominator skip is **P-D15 (3)**: one dead
    ///      gauge must not brick the permissionless tournament. Both precede the cold `SSTORE`, so
    ///      `firstTournamentEpoch` marks the first epoch with usable data rather than the first
    ///      sighting, a skipped pool never pays that store, and a pool that later loses its feed keeps
    ///      its grace epoch and re-ranks without re-warming once the feed returns.
    function _accumulateOne(address pool, uint256 newEpoch) internal {
        (uint256 num, uint256 den) = IEfficiencyOracle(efficiencyOracle).efficiencyInputs(pool);
        if (num == 0) return;
        if (den == 0) return;
        if (firstTournamentEpoch[pool] == 0) {
            firstTournamentEpoch[pool] = newEpoch;
            return;
        }
        if (newEpoch - firstTournamentEpoch[pool] < SMOOTHING_EPOCHS) return;
        _insertRanked(pool, num, den, (num * 1e18) / den);
    }

    /// @notice Accumulates one page of this epoch's tournament per **PP-D56 (iv)**.
    /// @dev A page carrying any epoch other than the seated one seats it and resets the counters.
    ///      That is also how an abandoned accumulation is discarded per **PP-D56 (xiv)**: the
    ///      registry, the only caller, passes a new epoch only on a first page or a reseat.
    function accumulateEpochSnapshot(address[] calldata page, uint256 epoch) external onlyGaugeRegistry {
        if (accumulationEpoch != epoch) {
            accumulationEpoch = epoch;
            nRanked = 0;
            finalizeCursor = 0;
        }
        uint256 newEpoch = currentSnapshotEpoch + 1;
        for (uint256 i = 0; i < page.length; ++i) {
            _accumulateOne(page[i], newEpoch);
        }
    }

    /// @dev Floor-percentile cap tier for rank `i` of `n`, most severe first, per **P-D13 (3)** /
    ///      **P-D15 (1)**. Identical arithmetic to the single-call form, from a settled `nRanked`.
    function _capBpsFor(uint256 i, uint256 n) internal pure returns (uint256) {
        if (i >= n - (n * 5) / 100) return 10;
        if (i >= n - (n * 10) / 100) return 50;
        if (i >= n - (n * 15) / 100) return 100;
        return 0;
    }

    /// @dev Emits the **G-D5** crossing event for one entry, at most once per pool per epoch.
    function _emitCrossing(RankedEntry storage e, uint256 newEpoch, bool wasFavored, bool isFavored) internal {
        if (wasFavored && !isFavored) {
            emit GaugeEfficiencyDropped(e.pool, newEpoch, e.numeratorSma, e.denominatorSma, e.efficiencyRatio);
        } else if (!wasFavored && isFavored) {
            emit GaugeEfficiencyRising(e.pool, newEpoch, e.numeratorSma, e.denominatorSma, e.efficiencyRatio);
        }
    }

    /// @dev Pass-3 work for one ranked entry: the crossing event, then the cap, cohort and epoch writes.
    function _finalizeOne(uint256 i, uint256 newEpoch) internal {
        uint256 n = nRanked;
        RankedEntry storage e = _rankedScratch[i];
        address pool = e.pool;
        bool isFavored = i < (n * 15 + 99) / 100;
        _emitCrossing(e, newEpoch, isFavoredCohort[pool], isFavored);
        poolEmissionCapBps[pool] = _capBpsFor(i, n);
        isFavoredCohort[pool] = isFavored;
        lastSnapshotEpoch[pool] = newEpoch;
    }

    /// @notice Finalizes one page of the ranked scratch per **PP-D56 (x)**; true when the epoch closes.
    function finalizeEpochSnapshot(uint256 maxPools) external onlyGaugeRegistry returns (bool done) {
        uint256 newEpoch = currentSnapshotEpoch + 1;
        uint256 i = finalizeCursor;
        // Saturates rather than overflowing, so type(uint256).max means every remaining entry per PP-D56 (xv).
        uint256 end = maxPools < nRanked - i ? i + maxPools : nRanked;
        for (; i < end; ++i) {
            _finalizeOne(i, newEpoch);
        }
        finalizeCursor = i;
        done = i == nRanked;
        if (done) {
            currentSnapshotEpoch = newEpoch;
            accumulationEpoch = 0;
            nRanked = 0;
            finalizeCursor = 0;
        }
    }

    // -------------------------------------------------------------------------
    // External — `IGaugeEligibility` surface (G-D5 + T-I5)
    // -------------------------------------------------------------------------

    /// @inheritdoc IGaugeEligibility
    function evaluateEligibility(address pool) external override returns (bool) {
        _checkEligibilityCriteria(pool);
        isGaugeEligible[pool] = true;
        lastSnapshotEpoch[pool] = currentSnapshotEpoch;
        return true;
    }

    /// @inheritdoc IGaugeEligibility
    function isEligible(address pool) external view override returns (bool) {
        return isGaugeEligible[pool];
    }

    /// @inheritdoc IGaugeEligibility
    function cohortOf(address pool) external view override returns (bool favored) {
        favored = isFavoredCohort[pool];
    }

    /// @inheritdoc IGaugeEligibility
    function snapshotEpoch() external view override returns (uint256) {
        return currentSnapshotEpoch;
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Accumulates normalized weights for ERC-4626 pool tokens whose underlying implementation class is admitted — the **G-D8** 52% Quality Gate numerator.
     * @dev **G-D10** — `try IERC4626(token).asset()`/`catch` discriminates ERC-4626Claiming candidates from plain ERC-20s; **T-I3** blocks AuMM before the probe. Non-4626 tokens hit an empty `catch` and add **0**; admitted 4626 tokens add `weights[i]`.
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
            if (token == _auMM) revert ForbiddenToken(token);

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
     * @dev Body order locked at **G2.4**: numerator path (forbidden tokens + **G-D10** + admitted class weights) then factory provenance, TVL floor, then **0.52e18** quality bar. **PB3.12c** inserts the **PB-D69 (v)** fee-rail conjunct directly after the hook check and before the numerator path — the rail is read off the canonical hook, so confirming the pool carries that hook must precede it, and a pool failing here skips the token loop entirely. Caller must pass a weighted pool implementing `IWeightedPool`.
     * @param pool Balancer pool address under evaluation.
     */
    function _checkEligibilityCriteria(address pool) internal view {
        address poolHook = IVault(vault).getHooksConfig(pool).hooksContract;
        if (poolHook != feeRoutingHook) revert WrongFeeRoutingHook(pool, poolHook);
        address rail = IAureumFeeRoutingHook(feeRoutingHook).poolBodenseeDepositToken(pool);
        if (rail == address(0) && !recoveryPathAdmitted[pool]) revert NoFeeRailAndNotAdmitted(pool);
        IERC20[] memory tokens = IVault(vault).getPoolTokens(pool);
        uint256[] memory weights = IWeightedPool(pool).getNormalizedWeights();
        uint256 numerator = _compute52PctNumerator(tokens, weights);
        if (!IBasePoolFactory(approvedFactory).isPoolFromFactory(pool)) revert PoolTypeNotWhitelisted(approvedFactory);
        uint256 tvl = ITVLOracle(tvlOracle).tvl(pool);
        if (tvl < TVL_FLOOR_SVZCHF) revert TVLFloorNotMet(tvl, TVL_FLOOR_SVZCHF);
        if (numerator < 0.52e18) revert InsufficientQualityGate(numerator);
    }

    /**
     * @notice Composition-challenge Quality Gate per **O-D2** / **O-D2a** — ≥52% admitted-ERC-4626 weight, the canonical fee-routing hook, Aureum-factory provenance, without the TVL floor or anti-spam checks `_checkEligibilityCriteria` runs.
     * @dev Stage O addition (canonical §xxvii registry-level composition check; supersedes K-D6e). Reverts `WrongFeeRoutingHook` if the pool's Vault-registered hook is not the canonical `feeRoutingHook` (**I-D13**); reverts `ForbiddenToken` on AuMM via `_compute52PctNumerator` (**T-I3**, **G-D10**); reverts `PoolTypeNotWhitelisted` if the pool is not from the approved Aureum weighted-pool factory (**F-12** — provenance is what makes the pool's self-reported `getNormalizedWeights` trustworthy, since the canonical hook's `onRegister` does not gate by factory); the **PB-D69** fee-rail conjunct is NO LONGER evaluated here: **PP-D50** amendment (x) split it into `feeRailConjunctSatisfied`, which `AureumGovernance` reads LIVE at `proposeCompositionChallenge` and then honours from `Proposal.railAdmittedAtPropose` at `_executeProposal`, so a revocation landing after a passed two-thirds vote can no longer annul the mandate (**C.6**). The enforcement is unchanged in substance and its reason still stands — a challenge winner takes a Miliarium slot and therefore an emission share under **F-5** / **F-6**, so a rail-less unadmitted pool must not pass; only the point at which the value is read has moved. Returns `false` (does not revert) on a sub-0.52e18 numerator — the **G-D8** quality bar — so the caller (`AureumGovernance` via `IGaugeRegistry`) can branch on a boolean rather than catching a revert.
     * @param pool The candidate replacement pool under evaluation.
     * @return passes `true` when the pool clears the 52% quality gate, carries the canonical hook, and is factory-provenanced.
     */
    function meetsCompositionQualityGate(address pool) external view override returns (bool) {
        address poolHook = IVault(vault).getHooksConfig(pool).hooksContract;
        if (poolHook != feeRoutingHook) revert WrongFeeRoutingHook(pool, poolHook);
        IERC20[] memory tokens = IVault(vault).getPoolTokens(pool);
        uint256[] memory weights = IWeightedPool(pool).getNormalizedWeights();
        uint256 numerator = _compute52PctNumerator(tokens, weights);
        if (!IBasePoolFactory(approvedFactory).isPoolFromFactory(pool)) revert PoolTypeNotWhitelisted(approvedFactory);
        return numerator >= 0.52e18;
    }

    /**
     * @notice Returns whether `pool` satisfies the **PB-D69** fee-rail conjunct — it carries a der-Bodensee deposit rail, or it is `recoveryPathAdmitted`.
     * @dev **PP-D50** amendment (x) splits this out of `meetsCompositionQualityGate`, which no longer evaluates it. `AureumGovernance` reads this LIVE at `proposeCompositionChallenge`, stores the result in `Proposal.railAdmittedAtPropose`, and honours the STORED value at `_executeProposal`, so a revocation landing after a passed two-thirds vote cannot annul the mandate (**C.6**). It returns a boolean rather than reverting because the caller branches on it at two different lifecycle points and needs the value, not a revert. The ACTIVATION path keeps its own inline conjunct in `_checkEligibilityCriteria` and does not consume this view — the two paths are deliberately independent per **PP-D50** (iii).
     * @param pool The pool whose fee-rail conjunct is queried.
     * @return satisfied `true` when `pool` carries a der-Bodensee rail or is admitted to the recovery path.
     */
    function feeRailConjunctSatisfied(address pool) external view override returns (bool satisfied) {
        address rail = IAureumFeeRoutingHook(feeRoutingHook).poolBodenseeDepositToken(pool);
        return rail != address(0) || recoveryPathAdmitted[pool];
    }
}
