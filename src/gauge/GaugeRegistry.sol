// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IGaugeRegistry} from "../ccb/IGaugeRegistry.sol";
import {IGaugeEligibility} from "./IGaugeEligibility.sol";
import {SwapAndDepositToBodensee} from "./SwapAndDepositToBodensee.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {GaugeEligibility} from "./GaugeEligibility.sol";
import {AureumTime} from "../lib/AureumTime.sol";

/**
 * @title GaugeRegistry
 * @notice Gauge state machine for pool activation — three paths: permissionless `activateGauge` (**OQ-G3** anti-spam fee + eligibility), governance `registerGaugeFromComposition`, and governance `seedFoundingPool` / `seedFoundingPools`; revocation via `revokeGauge`. Cross-references: **G-D7** — three activation paths — **G-D17** — `Revoked` is terminal — no Stage G recovery to `Active`.
 * @dev **G3.5** concrete state machine over the **G3.2 → G3.5** lineage — **G3.2** scaffold + **G3.3** constructor + `setGovernanceContract` + `activateGauge` (with **G3.3-pre-fix2c** typed-domain correction and **G3.3-fix1** `abstract` keyword + `external override` modifier per **G-D24** Schedule (a)) + **G3.4** `registerGaugeFromComposition` + `revokeGauge` + `isGaugeApproved` + `gaugeStatus` + **G3.5** `seedFoundingPool` + `seedFoundingPools` with the `abstract` keyword removed (8 of 8 `IGaugeRegistry` functions implemented; contract concrete). Five-argument constructor — four address arguments with zero-address checks (**ZeroAddress**) and raw `address` stores per **G-D16d**, plus a fifth `genesisBlock_` (`uint256`) bound raw to `GENESIS_BLOCK` with no zero-check per **P-D14 (1)**; Stage K `setGovernanceContract` handoff with `GovernanceTransferred` emit; **OQ-G3** permissionless `activateGauge` per the **G-D16c** five-step ordering (status precheck → fee pull → fee push → Bodensee routing → fee event → try/catch eligibility → state write + activated event) with non-reverting failure path; governance composition (`registerGaugeFromComposition` per **G-D7** path 2) and governance founding (`seedFoundingPool` scalar + `seedFoundingPools` inlined batch per **G-D16b** + **STAGE_G_PRECHECK_AUTO_GAUGE** C-4) — both bypass eligibility and the anti-spam fee; `revokeGauge` flips `Active → Revoked` per **G-D17** (terminal at Stage G; no entrypoint writes `Revoked → Active`); `isGaugeApproved` returns `_gaugeStatus[pool] == GaugeStatus.Active` per Stage F compat (**G-D16a**). Typed domain per **G-D16d** (Path (A), all-immutable) — `svZCHF`, `swapAndDeposit`, and `gaugeEligibility` are `address` immutables with `IERC20` / `SwapAndDepositToBodensee` / `IGaugeEligibility` casts at call sites only; deploy order per **G-D22** — `GaugeEligibility` first, `GaugeRegistry` second with `eligibility_` constructor arg, `GaugeEligibility.setGaugeRegistry(this)` post-deploy. **F16c additions per P-D14** — `GENESIS_BLOCK` immutable (5th constructor arg, anchors F-10 tournament epoch cadence + month-13 gate); `lastTournamentEpoch` cadence storage (one snapshot per `BLOCKS_PER_EPOCH`); permissionless `advanceTournament()` (F-10 efficiency tournament caller — concrete-only, not on `IGaugeRegistry`).
 */
contract GaugeRegistry is IGaugeRegistry {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ----------------------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------------------

    /// @notice OQ-G3 permissionless activation fee — 100 svZCHF at 18 decimals per **STAGE_G_PRECHECK_AUTO_GAUGE** §1; magnitude locked with **G-D12** strict-equality routing on the Bodensee helper path.
    uint256 public constant ANTI_SPAM_FEE = 100e18;

    // ----------------------------------------------------------------------------
    // Immutables
    // ----------------------------------------------------------------------------

    /// @notice Anti-spam fee token (**OQ-G3** ERC-20 pull path). Stored as `address`; cast to `IERC20(svZCHF)` at every call site per **G-D16d**.
    address public immutable svZCHF;

    /// @notice **G-D12** Bodensee fee-router helper binding. Stored as `address`; cast to `SwapAndDepositToBodensee(swapAndDeposit)` at every call site per **G-D16d**.
    address public immutable swapAndDeposit;

    /// @notice Eligibility evaluator binding — `GaugeEligibility` deploys first with this registry as its `gaugeRegistrySetter_` authority per **G-D22**; the registry then receives the eligibility address as a constructor arg, and the deployer calls `GaugeEligibility.setGaugeRegistry(this)` post-deploy. Cast to `IGaugeEligibility(gaugeEligibility)` at every call site per **G-D16d**.
    address public immutable gaugeEligibility;

    /// @notice Stage H genesis block anchoring the F-10 efficiency tournament epoch cadence (`AureumTime.epochIndex`) and the month-13 activation gate (`AureumTime.year1EndBlock(GENESIS_BLOCK) + 1`) — **P-D14 (1)**. Bound raw with no zero-check (uint256, accepts any value); same precedent as `AuMM.sol` L37, `EfficiencyOracle.sol` L30, and `EmissionDistributor.sol` L47. P9 deploy invariant: MUST equal `EfficiencyOracle.GENESIS_BLOCK` == `EmissionDistributor.GENESIS_BLOCK` — the tournament's epoch accounting and the distributor's month-13 cap gate must switch on the same block.
    uint256 public immutable GENESIS_BLOCK;

    // ----------------------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------------------

    /// @notice Per-pool gauge state machine — **G-D17** terminal `Revoked`; `Active` gauges satisfy Stage F `isGaugeApproved` via **G-D16a** compat semantics.
    mapping(address => GaugeStatus) private _gaugeStatus;

    /// @notice Complete Active-gauge enumeration consumed by the F-10 efficiency tournament — **P-D13** part (1); maintained by all four activation paths (activateGauge, registerGaugeFromComposition, seedFoundingPool, seedFoundingPools) and removed by revokeGauge.
    EnumerableSet.AddressSet private _activeGauges;

    /// @notice Governance authority for restricted entrypoints (`registerGaugeFromComposition`, `seedFoundingPool`, `seedFoundingPools`, `revokeGauge`, `setGovernanceContract`). Not `immutable` — Stage K rebinding via `setGovernanceContract`.
    address public governanceContract;

    /// @notice F-10 tournament cadence tracker — **P-D14 (2)**. Stores the epoch index of the last completed `advanceTournament` run; 0 until the first post-month-13 call. `advanceTournament` enforces `currentEpoch > lastTournamentEpoch` — exactly one snapshot per `BLOCKS_PER_EPOCH`.
    uint256 public lastTournamentEpoch;

    // ----------------------------------------------------------------------------
    // Custom errors
    // ----------------------------------------------------------------------------

    error ZeroAddress();

    /// @notice Reverts `advanceTournament` calls before the month-13 boundary (`AureumTime.year1EndBlock(GENESIS_BLOCK) + 1`) — **P-D14 (3)**.
    error TournamentNotActive();

    /// @notice Reverts `advanceTournament` calls when the current epoch index has not advanced beyond `lastTournamentEpoch` — **P-D14 (2)**; enforces one snapshot per `BLOCKS_PER_EPOCH`.
    error TournamentEpochNotElapsed();

    /// @notice Reverts `revokeGaugeIfIneligible` when `pool` still satisfies the **PB-D69** fee-rail conjunct — there is nothing to revoke, and that entry is hygiene rather than a governance lever.
    error GaugeStillEligible(address pool);

    // ----------------------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------------------

    /// @notice Emitted at the end of each successful `advanceTournament` call — **P-D14 (4)**; concrete-only (not on `IGaugeRegistry`). `epoch` is the `AureumTime.epochIndex` value snapshotted; `gaugeCount` is the Active-gauge set size passed to `computeEpochSnapshot`.
    event TournamentAdvanced(uint256 indexed epoch, uint256 gaugeCount);

    // ----------------------------------------------------------------------------
    // Modifier
    // ----------------------------------------------------------------------------

    modifier onlyGovernance() {
        if (msg.sender != governanceContract) revert NotGovernance(msg.sender);
        _;
    }

    // ----------------------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------------------

    /**
     * @notice Wires four address deploy-time dependencies for the gauge state machine, the OQ-G3 anti-spam fee path, and the Stage K governance handoff, plus the genesis block anchor for the F-10 efficiency tournament cadence and month-13 gate.
     * @dev Performs four zero-address checks (**ZeroAddress**) on the four address arguments before any state assignment — any zero address reverts before storage binds. Stores the four address arguments as raw `address` per **G-D16d** (Path (A), all-immutable). The fifth argument `genesisBlock_` binds `GENESIS_BLOCK` raw with no zero-check (uint256, accepts any value) per **P-D14 (1)** — same precedent as `AuMM.sol`, `EfficiencyOracle.sol`, and `EmissionDistributor.sol`. Cross-references: **G-D16d**, **G-D22** (deploy order — `GaugeEligibility` first with `gaugeRegistrySetter_`; `GaugeRegistry` second with `eligibility_` constructor arg; `GaugeEligibility.setGaugeRegistry(this)` post-deploy), **P-D14 (1)** (P9 deploy invariant: `GENESIS_BLOCK` MUST equal `EfficiencyOracle.GENESIS_BLOCK` == `EmissionDistributor.GENESIS_BLOCK`).
     * @param governance Initial governance authority for restricted entrypoints (Stage A–K Authorizer Safe per CLAUDE.md §1; rebound at Stage K via `setGovernanceContract`).
     * @param eligibility_ The deployed `GaugeEligibility` contract address — cast to `IGaugeEligibility(gaugeEligibility)` at every call site per **G-D16d**.
     * @param swapAndDeposit_ The deployed `SwapAndDepositToBodensee` helper address — cast to `SwapAndDepositToBodensee(swapAndDeposit)` at every call site per **G-D16d**.
     * @param svZCHF_ The svZCHF token address — cast to `IERC20(svZCHF)` at every call site per **G-D16d**.
     * @param genesisBlock_ Stage H genesis block anchoring the F-10 tournament epoch cadence (`AureumTime.epochIndex`) and the month-13 activation gate (`AureumTime.year1EndBlock(GENESIS_BLOCK) + 1`). Bound raw with no zero-check per **P-D14 (1)**; P9 deploy invariant: MUST equal `EfficiencyOracle.GENESIS_BLOCK` == `EmissionDistributor.GENESIS_BLOCK`.
     */
    constructor(
        address governance,
        address eligibility_,
        address swapAndDeposit_,
        address svZCHF_,
        uint256 genesisBlock_
    ) {
        if (governance == address(0)) revert ZeroAddress();
        if (eligibility_ == address(0)) revert ZeroAddress();
        if (swapAndDeposit_ == address(0)) revert ZeroAddress();
        if (svZCHF_ == address(0)) revert ZeroAddress();

        governanceContract = governance;
        gaugeEligibility = eligibility_;
        swapAndDeposit = swapAndDeposit_;
        svZCHF = svZCHF_;
        GENESIS_BLOCK = genesisBlock_;
    }

    // ----------------------------------------------------------------------------
    // External — governance (Stage K handoff)
    // ----------------------------------------------------------------------------

    /// @inheritdoc IGaugeRegistry
    function setGovernanceContract(address newGovernance) external override onlyGovernance {
        if (newGovernance == address(0)) revert ZeroAddress();
        address old = governanceContract;
        governanceContract = newGovernance;
        emit GovernanceTransferred(old, newGovernance);
    }

    // ----------------------------------------------------------------------------
    // External — permissionless (OQ-G3 anti-spam fee path)
    // ----------------------------------------------------------------------------

    /// @inheritdoc IGaugeRegistry
    function activateGauge(address pool) external override {
        GaugeStatus status = _gaugeStatus[pool];
        if (status == GaugeStatus.Active) revert AlreadyGauged(pool);
        if (status == GaugeStatus.Revoked) revert AlreadyRevoked(pool);

        IERC20(svZCHF).safeTransferFrom(msg.sender, address(this), ANTI_SPAM_FEE);
        IERC20(svZCHF).safeTransfer(swapAndDeposit, ANTI_SPAM_FEE);
        SwapAndDepositToBodensee(swapAndDeposit).swapAndDeposit(IERC20(svZCHF), ANTI_SPAM_FEE);
        emit AntiSpamFeeRouted(msg.sender, ANTI_SPAM_FEE);
        try IGaugeEligibility(gaugeEligibility).evaluateEligibility(pool) returns (bool ok) {
            if (!ok) {
                emit GaugeActivationFailed(pool, "");
                return;
            }
        } catch (bytes memory reason) {
            emit GaugeActivationFailed(pool, reason);
            return;
        }

        _gaugeStatus[pool] = GaugeStatus.Active;
        _activeGauges.add(pool);
        emit GaugeActivated(pool, GaugeActivationPath.Permissionless);
    }

    // ----------------------------------------------------------------------------
    // External — governance (composition + revocation)
    // ----------------------------------------------------------------------------

    /// @inheritdoc IGaugeRegistry
    function registerGaugeFromComposition(address pool) external override onlyGovernance {
        GaugeStatus status = _gaugeStatus[pool];
        if (status == GaugeStatus.Active) revert AlreadyGauged(pool);
        if (status == GaugeStatus.Revoked) revert AlreadyRevoked(pool);
        _gaugeStatus[pool] = GaugeStatus.Active;
        _activeGauges.add(pool);
        emit GaugeActivated(pool, GaugeActivationPath.Composition);
    }

    /// @inheritdoc IGaugeRegistry
    function revokeGauge(address pool) external override onlyGovernance {
        if (_gaugeStatus[pool] != GaugeStatus.Active) revert NotGauged(pool);
        _gaugeStatus[pool] = GaugeStatus.Revoked;
        _activeGauges.remove(pool);
        emit GaugeRevoked(pool);
    }

    /**
     * @notice Permissionlessly revokes `pool`'s gauge once its **PB-D69** fee-rail conjunct no longer holds, closing **C.6**'s first face — a withdrawn admission previously left a live gauge drawing emissions until an 18-day `GaugeChallenge` removed it.
     * @dev **PP-D50** (v). Deliberately UNGATED: the admission authority has already withdrawn its attestation and `finalizeRecoveryPathRevocation` has already let the delay run, so executing the consequence is hygiene anyone may perform. The predicate is the CONJUNCT ALONE and not the full criteria suite, which is a decision rather than a shortcut — **PP-D50** (vi) excludes the TVL floor, since a pool dipping momentarily below it would otherwise become revocable by anyone, and every other criterion is immutable after activation: the rail is written once in `onRegister`, the hook is sealed by the Vault at registration, and factory provenance, the token set and the weights cannot move. Mirrors `revokeGauge`'s transition exactly and emits the same `GaugeRevoked`, because consumers must react identically however the revocation arose; the `RecoveryPathAdmissionSet(pool, false)` that necessarily precedes it is what distinguishes the path. Once revoked, `EmissionDistributor.deregisterScore` becomes callable and clears the stale score.
     * @param pool The Active gauge whose admission has lapsed.
     */
    function revokeGaugeIfIneligible(address pool) external {
        if (_gaugeStatus[pool] != GaugeStatus.Active) revert NotGauged(pool);
        if (IGaugeEligibility(gaugeEligibility).feeRailConjunctSatisfied(pool)) revert GaugeStillEligible(pool);
        _gaugeStatus[pool] = GaugeStatus.Revoked;
        _activeGauges.remove(pool);
        emit GaugeRevoked(pool);
    }

    // ----------------------------------------------------------------------------
    // External — governance (founding seeds)
    // ----------------------------------------------------------------------------

    /// @inheritdoc IGaugeRegistry
    function seedFoundingPool(address pool) external override onlyGovernance {
        GaugeStatus status = _gaugeStatus[pool];
        if (status == GaugeStatus.Active) revert AlreadyGauged(pool);
        if (status == GaugeStatus.Revoked) revert AlreadyRevoked(pool);
        _gaugeStatus[pool] = GaugeStatus.Active;
        _activeGauges.add(pool);
        emit GaugeActivated(pool, GaugeActivationPath.Founding);
    }

    /// @inheritdoc IGaugeRegistry
    function seedFoundingPools(address[] calldata pools) external override onlyGovernance {
        for (uint256 i = 0; i < pools.length; ++i) {
            address pool = pools[i];
            GaugeStatus status = _gaugeStatus[pool];
            if (status == GaugeStatus.Active) revert AlreadyGauged(pool);
            if (status == GaugeStatus.Revoked) revert AlreadyRevoked(pool);
            _gaugeStatus[pool] = GaugeStatus.Active;
            _activeGauges.add(pool);
            emit GaugeActivated(pool, GaugeActivationPath.Founding);
        }
    }

    // ----------------------------------------------------------------------------
    // External — F-10 efficiency tournament (P-D14)
    // ----------------------------------------------------------------------------

    /**
     * @notice Permissionless F-10 efficiency tournament caller — advances the epoch snapshot by one `BLOCKS_PER_EPOCH` step, driving tier assignment and emission-cap updates for all Active gauges — **P-D14 (2)-(4)**.
     * @dev Gate order per **P-D14 (3)-(4)**: (1) `TournamentNotActive` — reverts before `AureumTime.year1EndBlock(GENESIS_BLOCK) + 1` (month-13 boundary, honoring P-D13 amendment (b)); (2) `TournamentEpochNotElapsed` — reverts when `currentEpoch <= lastTournamentEpoch` (one snapshot per `BLOCKS_PER_EPOCH`); (3) `lastTournamentEpoch = currentEpoch` written before the external call (CEI — a reverting snapshot rolls back the write); (4) `GaugeEligibility(gaugeEligibility).computeEpochSnapshot(...)` — concrete cast per **G2.5** (`computeEpochSnapshot` is concrete-only on `GaugeEligibility`, absent from `IGaugeEligibility`; confirmed by reading `src/gauge/IGaugeEligibility.sol`); (5) `_activeGauges.values()` supplies the complete deduped Active-gauge set (EnumerableSet invariant — satisfies the "caller passes a deduped set" contract at `GaugeEligibility` L210). At F16c the snapshot sorts + emits transition events; F-16 emission caps land at F16d. Concrete-only — not on `IGaugeRegistry`; interface plumbing deferred to F16e with the G16 sweep.
     */
    function advanceTournament() external {
        if (block.number < AureumTime.year1EndBlock(GENESIS_BLOCK) + 1) revert TournamentNotActive();
        uint256 currentEpoch = AureumTime.epochIndex(GENESIS_BLOCK, block.number);
        if (currentEpoch <= lastTournamentEpoch) revert TournamentEpochNotElapsed();
        lastTournamentEpoch = currentEpoch;
        GaugeEligibility(gaugeEligibility).computeEpochSnapshot(_activeGauges.values());
        emit TournamentAdvanced(currentEpoch, _activeGauges.length());
    }

    // ----------------------------------------------------------------------------
    // External — views
    // ----------------------------------------------------------------------------

    /// @inheritdoc IGaugeRegistry
    function isGaugeApproved(address pool) external view override returns (bool) {
        return _gaugeStatus[pool] == GaugeStatus.Active;
    }

    /// @inheritdoc IGaugeRegistry
    function gaugeStatus(address pool) external view override returns (GaugeStatus) {
        return _gaugeStatus[pool];
    }

    /// @inheritdoc IGaugeRegistry
    function meetsCompositionQualityGate(address pool) external view override returns (bool) {
        return IGaugeEligibility(gaugeEligibility).meetsCompositionQualityGate(pool);
    }

    /// @inheritdoc IGaugeRegistry
    function feeRailConjunctSatisfied(address pool) external view override returns (bool) {
        return IGaugeEligibility(gaugeEligibility).feeRailConjunctSatisfied(pool);
    }

    /// @inheritdoc IGaugeRegistry
    function poolEmissionCapBps(address pool) external view override returns (uint256) {
        return GaugeEligibility(gaugeEligibility).poolEmissionCapBps(pool);
    }

    /// @notice Returns the number of currently Active gauges — **P-D13** part (1); consumed by the F-10 efficiency tournament to bound its enumeration loop.
    function gaugeCount() external view returns (uint256) {
        return _activeGauges.length();
    }

    /// @notice Returns the Active-gauge address at `index` in the enumeration set — **P-D13** part (1); reverts if `index >= gaugeCount()`.
    function gaugeAt(uint256 index) external view returns (address) {
        return _activeGauges.at(index);
    }
}
