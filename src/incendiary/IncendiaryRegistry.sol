// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IIncendiaryRegistry} from "./IIncendiaryRegistry.sol";
import {SwapAndDepositToBodensee} from "../gauge/SwapAndDepositToBodensee.sol";
import {IGaugeRegistry} from "../ccb/IGaugeRegistry.sol";
import {IAuMM} from "../token/IAuMM.sol";
import {IVaultExplorer} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IncendiaryRegistry — Stage L concrete producer for the canonical F-2 Incendiary Boost
/// @notice Sells 14-day directed AuMM emission boosts funded by skimming the existing fixed block
///         emission (F-7 Step 1), never by minting new supply. A buyer deposits svZCHF or sUSDS
///         one-sided into der Bodensee and receives a supplementary per-block emission stream over
///         one or more epochs for a gauged pool of their choice.
/// @dev The concrete implementation behind the H-D29 `IIncendiaryRegistry` forward-dep. L2.1a is the
///      compiling skeleton (L-D16): immutables + constructor + the two `IIncendiaryRegistry` views
///      stubbed `return 0` (concrete + deployable, the H-D21 stub precedent). The price EMA (L3),
///      purchase entry + valuation (L4), placement + cap + crystallize (L5), and the real view bodies
///      (L6) land in subsequent sub-steps. Constants + settled storage land at L2.1b; the crystallize
///      cumulative-cache slots are deferred to L5.3 (L-D17). Until governance calls
///      `setIncendiaryRegistry`, the distributor defaults to `address(0)` (zero skim) per H-D29.
contract IncendiaryRegistry is IIncendiaryRegistry {
    /* ---------- Immutables ---------- */

    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching the sibling AureumGovernance /
    // EmissionDistributor declarations and the upstream-forked files.
    // slither-disable-next-line naming-convention

    /// @notice der Bodensee deposit channel — receives the svZCHF / sUSDS deposit and routes it via
    ///         `donate` (G-D21, zero-BPT DONATION) per L-D2.
    SwapAndDepositToBodensee public immutable BODENSEE_CHANNEL;

    /// @notice der Bodensee 40/30/30 WeightedPool address — the spot-rate read venue (L-D11).
    address public immutable BODENSEE_POOL;

    /// @notice Read-only Balancer V3 vault explorer — `getPoolData(BODENSEE_POOL).balancesLiveScaled18`
    ///         feeds the L-D11 direct spot rate.
    IVaultExplorer public immutable VAULT_EXPLORER;

    /// @notice AuMM token — `blockEmissionRate` feeds the L-D6 epoch-emission-integral cap basis (L5.1)
    ///         and denominates the entitlement in AuMM-wei.
    IAuMM public immutable AUMM;

    /// @notice svZCHF pay-token rail (L-D2).
    IERC20 public immutable SVZCHF;

    /// @notice sUSDS pay-token rail (L-D2).
    IERC20 public immutable SUSDS;

    /// @notice Gauge registry — the L-D10 purchase-time gauge gate (`isGaugeApproved(pool)`).
    IGaugeRegistry public immutable GAUGE_REGISTRY;

    /// @notice Protocol genesis block — the AureumTime epoch / era basis for placement and cap windows.
    uint256 public immutable GENESIS_BLOCK;

    /* ---------- Errors ---------- */

    /// @notice A constructor address argument was the zero address.
    error ZeroAddress();

    /* ---------- Constructor ---------- */

    /// @notice Wires the eight immutables; ZeroAddress-guards the seven address-bearing arguments.
    /// @dev `genesisBlock_` is unguarded — deploy correctness is governance's responsibility, the
    ///      AureumGovernance / EmissionDistributor convention (L-D16).
    constructor(
        SwapAndDepositToBodensee bodenseeChannel_,
        address bodenseePool_,
        IVaultExplorer vaultExplorer_,
        IAuMM aumm_,
        IERC20 svzchf_,
        IERC20 susds_,
        IGaugeRegistry gaugeRegistry_,
        uint256 genesisBlock_
    ) {
        if (address(bodenseeChannel_) == address(0)) revert ZeroAddress();
        if (bodenseePool_ == address(0)) revert ZeroAddress();
        if (address(vaultExplorer_) == address(0)) revert ZeroAddress();
        if (address(aumm_) == address(0)) revert ZeroAddress();
        if (address(svzchf_) == address(0)) revert ZeroAddress();
        if (address(susds_) == address(0)) revert ZeroAddress();
        if (address(gaugeRegistry_) == address(0)) revert ZeroAddress();

        BODENSEE_CHANNEL = bodenseeChannel_;
        BODENSEE_POOL = bodenseePool_;
        VAULT_EXPLORER = vaultExplorer_;
        AUMM = aumm_;
        SVZCHF = svzchf_;
        SUSDS = susds_;
        GAUGE_REGISTRY = gaugeRegistry_;
        GENESIS_BLOCK = genesisBlock_;
    }

    /* ---------- IIncendiaryRegistry views (L2.1a stubs; real bodies at L6) ---------- */

    /// @inheritdoc IIncendiaryRegistry
    /// @dev L2.1a stub returning 0; the O(1) epoch-bucketed body lands at L6.1. `pure` here is the
    ///      zero-warning stub form — widens to `view` at L6.1 when it reads the cumulative buckets.
    function integratedSkim(uint256, uint256) external pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc IIncendiaryRegistry
    /// @dev L2.1a stub returning 0; the O(1) per-pool body lands at L6.2. `pure` here is the
    ///      zero-warning stub form — widens to `view` at L6.2 when it reads the per-pool buckets.
    function boostIntegral(address, uint256, uint256) external pure override returns (uint256) {
        return 0;
    }
}
