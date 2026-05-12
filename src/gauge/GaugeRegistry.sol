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
 * @dev **G3.2** scaffold — constants, immutables, `_gaugeStatus` mapping, governance and eligibility bindings, `onlyGovernance` modifier — no constructor, no external function bodies (**G-D16**). Typed domain per **G-D16d** — `svZCHF` and `swapAndDeposit` are `address` immutables with `IERC20` / `SwapAndDepositToBodensee` casts at call sites only; `gaugeEligibility` is post-deploy `address` storage with `IGaugeEligibility` cast at call sites.
 */
contract GaugeRegistry is IGaugeRegistry {
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

    // ----------------------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------------------

    /// @notice Per-pool gauge state machine — **G-D17** terminal `Revoked`; `Active` gauges satisfy Stage F `isGaugeApproved` via **G-D16a** compat semantics.
    mapping(address => GaugeStatus) private _gaugeStatus;

    /// @notice Governance authority for restricted entrypoints (`registerGaugeFromComposition`, `seedFoundingPool`, `seedFoundingPools`, `revokeGauge`, `setGovernanceContract`). Not `immutable` — Stage K rebinding via `setGovernanceContract`.
    address public governanceContract;

    /// @notice Eligibility evaluator binding — post-deploy storage (not `immutable`) per G3.2 wiring discipline: `GaugeEligibility` constructor depends on this registry, so the registry deploys first and receives the eligibility address in a later one-shot wire step. Cast to `IGaugeEligibility(gaugeEligibility)` at every call site per **G-D16d**.
    address public gaugeEligibility;

    // ----------------------------------------------------------------------------
    // Modifier
    // ----------------------------------------------------------------------------

    modifier onlyGovernance() {
        if (msg.sender != governanceContract) revert NotGovernance(msg.sender);
        _;
    }
}
