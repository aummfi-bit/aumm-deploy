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
 * @dev **G3.2** scaffold + **G3.3-pre-fix2c** typed-domain correction — constants, immutables, `_gaugeStatus` mapping, governance binding, `onlyGovernance` modifier — no constructor, no external function bodies (**G-D16**). Typed domain per **G-D16d** (Path (A), all-immutable) — `svZCHF`, `swapAndDeposit`, and `gaugeEligibility` are `address` immutables with `IERC20` / `SwapAndDepositToBodensee` / `IGaugeEligibility` casts at call sites only; deploy order per **G-D22** — `GaugeEligibility` first, `GaugeRegistry` second with `eligibility_` constructor arg, `GaugeEligibility.setGaugeRegistry(this)` post-deploy.
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
    // Modifier
    // ----------------------------------------------------------------------------

    modifier onlyGovernance() {
        if (msg.sender != governanceContract) revert NotGovernance(msg.sender);
        _;
    }
}
