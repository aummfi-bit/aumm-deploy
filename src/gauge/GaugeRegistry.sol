// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IGaugeRegistry} from "../ccb/IGaugeRegistry.sol";
import {IGaugeEligibility} from "./IGaugeEligibility.sol";
import {SwapAndDepositToBodensee} from "./SwapAndDepositToBodensee.sol";

/**
 * @title GaugeRegistry
 * @notice Gauge state machine for pool activation — three paths: permissionless `activateGauge` (**OQ-G3** anti-spam fee + eligibility), governance `registerGaugeFromComposition`, and governance `seedFoundingPool` / `seedFoundingPools`; revocation via `revokeGauge`. Cross-references: **G-D7** — three activation paths — **G-D17** — `Revoked` is terminal — no Stage G recovery to `Active`.
 * @dev **G3.3** constructor + `setGovernanceContract` + `activateGauge` over **G3.2** scaffold + **G3.3-pre-fix2c** typed-domain correction — four-argument constructor with zero-address checks (**ZeroAddress**) and raw `address` stores per **G-D16d**, Stage K `setGovernanceContract` handoff, **OQ-G3** permissionless `activateGauge` per the **G-D16c** five-step ordering (status precheck → fee pull → fee push → Bodensee routing → fee event → try/catch eligibility → state write + activated event) with non-reverting failure path. Typed domain per **G-D16d** (Path (A), all-immutable) — `svZCHF`, `swapAndDeposit`, and `gaugeEligibility` are `address` immutables with `IERC20` / `SwapAndDepositToBodensee` / `IGaugeEligibility` casts at call sites only; deploy order per **G-D22** — `GaugeEligibility` first, `GaugeRegistry` second with `eligibility_` constructor arg, `GaugeEligibility.setGaugeRegistry(this)` post-deploy. + **G3.3-fix1** abstract-keyword + override modifier on the two G3.3 interface functions per **G-D24** Schedule (a) (contract remains abstract through **G3.4**; concrete at **G3.5**).
 */
abstract contract GaugeRegistry is IGaugeRegistry {
    using SafeERC20 for IERC20;

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

    // ----------------------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------------------

    /// @notice Per-pool gauge state machine — **G-D17** terminal `Revoked`; `Active` gauges satisfy Stage F `isGaugeApproved` via **G-D16a** compat semantics.
    mapping(address => GaugeStatus) private _gaugeStatus;

    /// @notice Governance authority for restricted entrypoints (`registerGaugeFromComposition`, `seedFoundingPool`, `seedFoundingPools`, `revokeGauge`, `setGovernanceContract`). Not `immutable` — Stage K rebinding via `setGovernanceContract`.
    address public governanceContract;

    // ----------------------------------------------------------------------------
    // Custom errors
    // ----------------------------------------------------------------------------

    error ZeroAddress();

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
     * @notice Wires the four deploy-time dependencies for the gauge state machine, the OQ-G3 anti-spam fee path, and the Stage K governance handoff.
     * @dev Performs four zero-address checks (**ZeroAddress**) before any state assignment — any zero input reverts before storage binds. Stores all four arguments as raw `address` per **G-D16d** (Path (A), all-immutable). Cross-references: **G-D16d**, **G-D22** (deploy order — `GaugeEligibility` first with `gaugeRegistrySetter_`; `GaugeRegistry` second with `eligibility_` constructor arg; `GaugeEligibility.setGaugeRegistry(this)` post-deploy).
     * @param governance Initial governance authority for restricted entrypoints (Stage A–K Authorizer Safe per CLAUDE.md §1; rebound at Stage K via `setGovernanceContract`).
     * @param eligibility_ The deployed `GaugeEligibility` contract address — cast to `IGaugeEligibility(gaugeEligibility)` at every call site per **G-D16d**.
     * @param swapAndDeposit_ The deployed `SwapAndDepositToBodensee` helper address — cast to `SwapAndDepositToBodensee(swapAndDeposit)` at every call site per **G-D16d**.
     * @param svZCHF_ The svZCHF token address — cast to `IERC20(svZCHF)` at every call site per **G-D16d**.
     */
    constructor(
        address governance,
        address eligibility_,
        address swapAndDeposit_,
        address svZCHF_
    ) {
        if (governance == address(0)) revert ZeroAddress();
        if (eligibility_ == address(0)) revert ZeroAddress();
        if (swapAndDeposit_ == address(0)) revert ZeroAddress();
        if (svZCHF_ == address(0)) revert ZeroAddress();

        governanceContract = governance;
        gaugeEligibility = eligibility_;
        swapAndDeposit = swapAndDeposit_;
        svZCHF = svZCHF_;
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
        emit GaugeActivated(pool, GaugeActivationPath.Permissionless);
    }
}
