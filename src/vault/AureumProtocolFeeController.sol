// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FEE_SCALING_FACTOR, MAX_FEE_PERCENTAGE } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";

import { IAureumProtocolFeeControllerHookExtension } from "../fee_router/IAureumProtocolFeeControllerHookExtension.sol";
import { IAureumFeeRoutingHook } from "../fee_router/IAureumFeeRoutingHook.sol";
import { AureumTime } from "../lib/AureumTime.sol";

/**
 * @notice Helper contract to manage protocol and creator fees outside the Vault.
 * @dev This contract stores global default protocol swap and yield fees, and also tracks the values of those fees
 * for each pool (the `PoolFeeConfig` described below). Protocol fees can always be overwritten by governance, but
 * pool creator fees are controlled by the registered poolCreator (see `PoolRoleAccounts`).
 *
 * The Vault stores a single aggregate percentage for swap and yield fees; only this `ProtocolFeeController` knows
 * the component fee percentages, and how to compute the aggregate from the components. This is done for performance
 * reasons, to minimize gas on the critical path, as this way the Vault simply applies a single "cut", and stores the
 * fee amounts separately from the pool balances.
 *
 * The pool creator fees are "net" protocol fees, meaning the protocol fee is taken first, and the pool creator fee
 * percentage is applied to the remainder. Essentially, the protocol is paid first, then the remainder is divided
 * between the pool creator and the LPs.
 *
 * There is a permissionless function (`collectAggregateFees`) that transfers these tokens from the Vault to this
 * contract, and distributes them between the protocol and pool creator, after which they can be withdrawn at any
 * time by governance and the pool creator, respectively.
 *
 * Protocol fees can be zero in some cases (e.g., the token is registered as exempt), and pool creator fees are zero
 * if there is no creator role address defined. Protocol fees are capped at a maximum percentage (50%); pool creator
 * fees are computed "net" protocol fees, so they can be any value from 0 to 100%. Any combination is possible.
 * A protocol-fee-exempt pool with a 100% pool creator fee would send all fees to the creator. If there is no pool
 * creator, a pool with a 50% protocol fee would divide the fees evenly between the protocol and LPs.
 *
 * This contract is deployed with the Vault, but can be changed by governance.
 */
contract AureumProtocolFeeController is
    IProtocolFeeController,
    IAureumProtocolFeeControllerHookExtension,
    SingletonAuthentication,
    ReentrancyGuardTransient,
    VaultGuard
{
    using FixedPoint for uint256;
    using SafeERC20 for IERC20;
    using SafeCast for *;

    enum ProtocolFeeType {
        SWAP,
        YIELD
    }

    /**
     * @notice Fee configuration stored in the swap and yield fee mappings.
     * @dev Instead of storing only the fee in the mapping, also store a flag to indicate whether the fee has been
     * set by governance through a permissioned call. (The fee is stored in 64-bits, so that the struct fits
     * within a single slot.)
     *
     * We know the percentage is an 18-decimal FP value, which only takes 60 bits, so it's guaranteed to fit,
     * and we can do simple casts to truncate the high bits without needed SafeCast.
     *
     * We want to enable permissionless updates for pools, so that it is less onerous to update potentially
     * hundreds of pools if the global protocol fees change. However, we don't want to overwrite pools that
     * have had their fee percentages manually set by the DAO (i.e., after off-chain negotiation and agreement).
     *
     * @param feePercentage The raw swap or yield fee percentage
     * @param isOverride When set, this fee is controlled by governance, and cannot be changed permissionlessly
     */
    struct PoolFeeConfig {
        uint64 feePercentage;
        bool isOverride;
    }

    // Maximum protocol swap fee percentage. FixedPoint.ONE corresponds to a 100% fee.
    uint256 public constant MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50e16; // 50%

    // Maximum protocol yield fee percentage.
    uint256 public constant MAX_PROTOCOL_YIELD_FEE_PERCENTAGE = 50e16; // 50%

    // Maximum pool creator (swap, yield) fee percentage.
    uint256 public constant MAX_CREATOR_FEE_PERCENTAGE = 99.999e16; // 99.999%

    // Global protocol swap fee.
    // Locked at construction (Aureum D-D15: setter reverts SplitIsImmutable to enforce 50/50 split); slot kept as uint256 private for layout symmetry with _globalProtocolYieldFeePercentage. See D8 NOTES F19.
    // slither-disable-next-line immutable-states
    uint256 private _globalProtocolSwapFeePercentage;

    // Global protocol yield fee.
    uint256 private _globalProtocolYieldFeePercentage;

    // Store the pool-specific swap fee percentages (the Vault's poolConfigBits stores the aggregate percentage).
    mapping(address pool => PoolFeeConfig swapFeeConfig) internal _poolProtocolSwapFeePercentages;

    // Store the pool-specific yield fee percentages (the Vault's poolConfigBits stores the aggregate percentage).
    mapping(address pool => PoolFeeConfig yieldFeeConfig) internal _poolProtocolYieldFeePercentages;

    // Pool creators for each pool (empowered to set pool creator fee percentages, and withdraw creator fees).
    mapping(address pool => address poolCreator) internal _poolCreators;

    // Pool creator swap fee percentages for each pool.
    mapping(address pool => uint256 poolCreatorSwapFee) internal _poolCreatorSwapFeePercentages;

    // Pool creator yield fee percentages for each pool.
    mapping(address pool => uint256 poolCreatorYieldFee) internal _poolCreatorYieldFeePercentages;

    // Disaggregated protocol fees (from swap and yield), available for withdrawal by governance.
    mapping(address pool => mapping(IERC20 poolToken => uint256 feeAmount)) internal _protocolFeeAmounts;

    // Disaggregated pool creator fees (from swap and yield), available for withdrawal by the pool creator.
    mapping(address pool => mapping(IERC20 poolToken => uint256 feeAmount)) internal _poolCreatorFeeAmounts;

    // Ensure that the caller is the pool creator.
    modifier onlyPoolCreator(address pool) {
        _ensureCallerIsPoolCreator(pool);
        _;
    }

    // Validate the swap fee percentage against the maximum.
    modifier withValidSwapFee(uint256 newSwapFeePercentage) {
        if (newSwapFeePercentage > MAX_PROTOCOL_SWAP_FEE_PERCENTAGE) {
            revert ProtocolSwapFeePercentageTooHigh();
        }
        _ensureValidPrecision(newSwapFeePercentage);
        _;
    }

    modifier withValidPoolCreatorFee(uint256 newPoolCreatorFeePercentage) {
        if (newPoolCreatorFeePercentage > MAX_CREATOR_FEE_PERCENTAGE) {
            revert PoolCreatorFeePercentageTooHigh();
        }
        _;
    }

    // Force collection and disaggregation (e.g., before changing protocol fee percentages).
    modifier withLatestFees(address pool) {
        collectAggregateFees(pool);
        _;
    }

    /***************************************************************************
                            Aureum-Added State
    ***************************************************************************/

    error InvalidRecipient(address expected, address provided);
    error CreatorFeesDisabled();
    error ZeroBodenseeAddress();
    error ZeroHookAddress();
    error BodenseeYieldCollectionDisabled();
    /// @notice Reverts when a caller attempts to change the protocol swap-fee percentage.
    /// @dev Per Aureum D-D15: the 50/50 split between der Bodensee and LPs is expressed
    ///      by pinning `_globalProtocolSwapFeePercentage` to `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE`
    ///      (50e16, the Vault's maximum protocol-extractable share) at construction.
    ///      There is no governance path to change this value; both the global setter
    ///      and the per-pool override revert with this error.
    ///      See docs/STAGE_D_PLAN.md (D-D15) and docs/FINDINGS.md (OQ-1, OQ-1a).
    error SplitIsImmutable();

    /// @notice Reverts when a caller attempts to change the protocol yield-fee percentage.
    /// @dev Per `10_constitution.md` §xxix L150—151 the 10% ERC-4626 yield skim is immutable
    ///      from block 0, expressed here by pinning `_globalProtocolYieldFeePercentage` to
    ///      that skim (1e17) at construction. There is no governance path to change this
    ///      value; both the global setter and the per-pool override revert with this error.
    ///      Distinct from `SplitIsImmutable` above, whose provenance is the swap-side 50/50
    ///      split (D-D15, OQ-1, OQ-1a) and which governs a different pair of setters.
    ///      See docs/STAGE_P_PRIME_NOTES.md (PP-D48 (iv), (vi)).
    error YieldSkimIsImmutable();

    /// @notice Reverts when `routeYieldFeeToHook` is called before
    ///         `BLOCKS_PER_EPOCH` blocks have elapsed since `pool`'s last
    ///         successful route (OQ-21 per-pool cadence throttle).
    error RouteThrottled();

    /// @notice Block of `pool`'s last successful `routeYieldFeeToHook` route;
    ///         anchors the OQ-21 `BLOCKS_PER_EPOCH` throttle. Zero until first route.
    mapping(address pool => uint256 lastRouteBlock) private _lastRouteBlock;

    /// @notice Reverts when a yield route is attempted by neither the seated
    ///         `yieldRouteKeeper` nor the hook's `governanceModule` Safe.
    error NotYieldRouteKeeper(address caller);

    /// @notice Reverts when a keeper rotation is attempted by anyone other than
    ///         the hook's `governanceModule` Safe, or while that Safe is unseated.
    error NotKeeperAuthority(address caller);

    /// @notice Emitted when the yield-route keeper is seated or rotated.
    event YieldRouteKeeperChanged(address indexed previousKeeper, address indexed newKeeper);

    /// @notice The scheduled principal permitted to drive `routeYieldFeeToHook`
    ///         alongside the hook's governance Safe (PP-D48 clause (v)). STORAGE
    ///         rather than an immutable because keepers are rotated, compromised
    ///         and replaced, and ROTATABLE rather than one-shot because a burned
    ///         slot is a permanently dead route — the trap PP3.12 avoided when
    ///         `admissionAuthority` took the `GaugeRegistry.governance` shape
    ///         instead of `setGaugeRegistry`'s burn. `address(0)` is a PERMITTED
    ///         value that disables the keeper leg without stranding the skim,
    ///         since the Safe stays admissible; it can never bypass the gate,
    ///         because `msg.sender` is never the zero address.
    address public yieldRouteKeeper;

    /// @notice The der Bodensee pool address — the D-D9 `collectAggregateFees`
    ///         pool-identity guard target.
    /// @dev Post-D4 retarget (per D-D7 reconciled / STAGE_D_NOTES D23), this
    ///      immutable no longer serves B10 withdrawal-recipient enforcement —
    ///      that role moved to `FEE_ROUTING_HOOK`. Instead, per Aureum protocol
    ///      decision D-D9 / OQ-2, `collectAggregateFees(pool)` reverts
    ///      `BodenseeYieldCollectionDisabled()` when `pool == DER_BODENSEE_POOL`
    ///      (guard added at D4.4). Bodensee's ERC-4626 composition compounds
    ///      in-pool via Rate Providers; there is no yield to skim. See
    ///      docs/STAGE_B_NOTES.md for the original B10 rationale and
    ///      docs/STAGE_D_NOTES.md D23 for the two-immutables reconciliation.
    // Rationale: Aureum-introduced immutable; SCREAMING_CASE matches the
    // upstream Balancer V3 convention for protocol-critical addresses used
    // throughout this forked file.
    // slither-disable-next-line naming-convention
    address public immutable DER_BODENSEE_POOL;

    /// @notice The B10 withdrawal-recipient enforcement target — set at
    ///         construction to the Aureum fee-routing hook contract's address.
    /// @dev Per Aureum protocol decision D-D7 / B10, the two
    ///      `withdrawProtocolFees*` functions revert `InvalidRecipient` if any
    ///      other recipient is passed. The hook in turn forwards fees on to
    ///      der Bodensee (swap leg) per the β1 custody-transfer pattern; see
    ///      docs/STAGE_D_NOTES.md D17. There is no setter and no governance
    ///      path to change this address. See docs/STAGE_D_NOTES.md D23 for the
    ///      two-immutables shape rationale.
    // Rationale: Aureum-introduced immutable; SCREAMING_CASE matches the
    // upstream Balancer V3 convention for protocol-critical addresses used
    // throughout this forked file.
    // slither-disable-next-line naming-convention
    address public immutable FEE_ROUTING_HOOK;


    /// @notice Der Bodensee swap fee — immutable from block 0 (`swapFeeManager: address(0)` at
    ///         deployment of the Bodensee pool). No governance lever. The 2026-04-15 OQ-11
    ///         "0.10% – 1.00% governance-adjustable" Bodensee band is superseded; see
    ///         docs/FINDINGS.md OQ-11 (2026-04-26 status) and docs/STAGE_E_NOTES.md E-D22.
    uint256 public constant BODENSEE_SWAP_FEE = 0.0075e18;  // 0.75% — immutable from block 0

    /// @notice Miliarium pool swap-fee band (per E-D22 / OQ-11 supersession 2026-04-26).
    ///         Per-pool `swapFeeManager` is `governanceMultisig`; governance adjusts the per-pool
    ///         rate within the band via the standard proposal path with `BLOCKS_PER_EPOCH` cooldown.
    ///         Controller does NOT enforce the band at runtime; enforcement is the governance path's
    ///         responsibility at Stage K. See docs/FINDINGS.md OQ-11 and docs/STAGE_E_NOTES.md E-D22.
    uint256 public constant MILIARIUM_SWAP_FEE_MIN     = 0.0001e18;  // 0.01%
    uint256 public constant MILIARIUM_SWAP_FEE_MAX     = 0.003e18;   // 0.30%
    uint256 public constant MILIARIUM_SWAP_FEE_GENESIS = 0.0002e18;  // 0.02% — deployment default for all 28

    constructor(
        IVault vault_,
        address derBodenseePool_,
        address feeRoutingHook_
    ) SingletonAuthentication(vault_) VaultGuard(vault_) {
        if (derBodenseePool_ == address(0)) {
            revert ZeroBodenseeAddress();
        }
        if (feeRoutingHook_ == address(0)) {
            revert ZeroHookAddress();
        }
        DER_BODENSEE_POOL = derBodenseePool_;
        FEE_ROUTING_HOOK = feeRoutingHook_;
        // D-D15: pin the protocol swap-fee percentage at 50e16 (the Vault's maximum
        // protocol-extractable share) at construction. This saturates the Vault's cap
        // rather than bypassing it — the 50/50 split between der Bodensee and LPs is
        // expressed by taking 100% of the protocol-extractable share and routing it to
        // Bodensee. Both setters (`setGlobalProtocolSwapFeePercentage` and the per-pool
        // `setProtocolSwapFeePercentage`) revert with `SplitIsImmutable`.
        _globalProtocolSwapFeePercentage = MAX_PROTOCOL_SWAP_FEE_PERCENTAGE;
    }

    /// @inheritdoc IProtocolFeeController
    function vault() external view returns (IVault) {
        return _vault;
    }

    /// @inheritdoc IProtocolFeeController
    // Rationale: upstream pattern. The hook writes state directly; the
    // returned bytes from _vault.unlock() are unused by design.
    // slither-disable-next-line unused-return
    function collectAggregateFees(address pool) public {
        // D-D9: Bodensee is the fee-sink itself — its aggregate fees are routed via the
        // hook's Bodensee-aware path, not this single-pool overload.
        if (pool == DER_BODENSEE_POOL) {
            revert BodenseeYieldCollectionDisabled();
        }
        _vault.unlock(abi.encodeCall(AureumProtocolFeeController.collectAggregateFeesHook, pool));
    }

    /**
     * @dev Copy and zero out the `aggregateFeeAmounts` collected in the Vault accounting, supplying credit
     * for each token. The YIELD leg is credited to `_protocolFeeAmounts`; the SWAP leg is FORWARDED straight
     * to the fee-routing hook through `_receiveAggregateFeesSwapForward`, exactly as the hook's own
     * `collectAggregateFeesHookSwapForward` path does. E.2 (PP-D48 (iii)): before this, the permissionless
     * keeper entry credited BOTH legs into a single ledger slot per (pool, token), which no consumer can
     * split apart again — so `routeYieldFeeToHook`, which since E.4 routes the whole credit, would have
     * carried STANDARD swap dust through a function whose name and whose canonical clause
     * (`10_constitution.md` §xxix L150) are about yield alone. The ledger is now yield-only and the two
     * collect paths agree on what each leg means.
     */
    // Rationale: hook executes inside Vault unlock context; Vault reentrancy
    // lock held throughout the external calls and subsequent event emissions.
    // The swap-forward return is deliberately discarded: this keeper entry reports
    // nothing back to a caller, unlike the hook's own forward entry which decodes it.
    // slither-disable-next-line reentrancy-events,unused-return
    function collectAggregateFeesHook(address pool) external onlyVault {
        (uint256[] memory totalSwapFees, uint256[] memory totalYieldFees) = _vault.collectAggregateFees(pool);
        _receiveAggregateFees(pool, ProtocolFeeType.YIELD, totalYieldFees);
        (IERC20[] memory poolTokens, ) = _getPoolTokensAndCount(pool);
        _receiveAggregateFeesSwapForward(pool, poolTokens, totalSwapFees);
    }

    // AUREUM NOTE: Identical to upstream ProtocolFeeController.sol L203-259.
    // Aureum short-circuit: _poolCreatorSwapFeePercentages[pool] and
    // _poolCreatorYieldFeePercentages[pool] are always zero (their setters
    // revert unconditionally, per Pass 4). Therefore needToSplitFees is always
    // false and the else-branch always fires: 100% of collected fees accumulate
    // in _protocolFeeAmounts. Creator fee storage is never written. See
    // docs/STAGE_B_NOTES.md (Part 2, Interface divergences) for full analysis.
    // Rationale: upstream Balancer V3 fee-collection pattern. The Vault holds
    // its reentrancy lock during sendTo() because this code path executes
    // inside an unlock() context. No reentrant observer can act on emitted
    // events within the same transaction.
    // slither-disable-next-line reentrancy-no-eth,reentrancy-events
    function _receiveAggregateFees(address pool, ProtocolFeeType feeType, uint256[] memory feeAmounts) private {
        // There are two cases when we don't need to split fees (in which case we can save gas and avoid rounding
        // errors by skipping calculations) if either the protocol or pool creator fee percentage is zero.

        uint256 protocolFeePercentage = feeType == ProtocolFeeType.SWAP
            ? _poolProtocolSwapFeePercentages[pool].feePercentage
            : _poolProtocolYieldFeePercentages[pool].feePercentage;

        uint256 poolCreatorFeePercentage = feeType == ProtocolFeeType.SWAP
            ? _poolCreatorSwapFeePercentages[pool]
            : _poolCreatorYieldFeePercentages[pool];

        // Rationale: uint256 default-initializes to 0, then assigned before
        // first use below. Upstream Balancer pattern.
        // slither-disable-next-line uninitialized-local
        uint256 aggregateFeePercentage;

        bool needToSplitFees = poolCreatorFeePercentage > 0 && protocolFeePercentage > 0;
        if (needToSplitFees) {
            // Calculate once, outside the loop.
            aggregateFeePercentage = _computeAggregateFeePercentage(protocolFeePercentage, poolCreatorFeePercentage);
        }

        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);
        for (uint256 i = 0; i < numTokens; ++i) {
            if (feeAmounts[i] > 0) {
                IERC20 token = poolTokens[i];

                // Rationale: pool tokens are validated at pool registration;
                // the loop iterates over a controlled set. Upstream Balancer pattern.
                // slither-disable-next-line calls-loop
                _vault.sendTo(token, address(this), feeAmounts[i]);

                // It should be easier for off-chain processes to handle two events, rather than parsing the type
                // out of a single event.
                if (feeType == ProtocolFeeType.SWAP) {
                    emit ProtocolSwapFeeCollected(pool, token, feeAmounts[i]);
                } else {
                    emit ProtocolYieldFeeCollected(pool, token, feeAmounts[i]);
                }

                if (needToSplitFees) {
                    // The Vault took a single "cut" for the aggregate total percentage (protocol + pool creator) for
                    // this fee type (swap or yield). The first step is to reconstruct this total fee amount. Then we
                    // need to "disaggregate" this total, dividing it between the protocol and pool creator according
                    // to their individual percentages. We do this by computing the protocol portion first, then
                    // assigning the remainder to the pool creator.
                    uint256 totalFeeAmountRaw = feeAmounts[i].divUp(aggregateFeePercentage);
                    uint256 protocolPortion = totalFeeAmountRaw.mulUp(protocolFeePercentage);

                    _protocolFeeAmounts[pool][token] += protocolPortion;
                    _poolCreatorFeeAmounts[pool][token] += feeAmounts[i] - protocolPortion;
                } else {
                    // If we don't need to split, one of them must be zero.
                    if (poolCreatorFeePercentage == 0) {
                        _protocolFeeAmounts[pool][token] += feeAmounts[i];
                    } else {
                        _poolCreatorFeeAmounts[pool][token] += feeAmounts[i];
                    }
                }
            }
        }
    }

    // β1 swap-leg forward (D17 L170 / D4.7) — gated outer, Vault callback, internal helper.

    /// @inheritdoc IAureumProtocolFeeControllerHookExtension
    function collectSwapAggregateFeesForHook(
        address pool
    ) external override returns (IERC20[] memory tokens, uint256[] memory forwardedAmounts) {
        if (msg.sender != FEE_ROUTING_HOOK) {
            revert OnlyFeeRoutingHook(msg.sender);
        }
        bytes memory result = _vault.unlock(abi.encodeCall(AureumProtocolFeeController.collectAggregateFeesHookSwapForward, pool));
        (tokens, forwardedAmounts) = abi.decode(result, (IERC20[], uint256[]));
    }

    /**
     * @dev Hook-only variant of collectAggregateFeesHook (L267). Drains the Vault's aggregate
     * fee slots for `pool`, routes the yield leg via the unchanged _receiveAggregateFees path
     * (credits _protocolFeeAmounts), and forwards the swap leg to FEE_ROUTING_HOOK via
     * _receiveAggregateFeesSwapForward (does NOT credit _protocolFeeAmounts). Returns the pool
     * token list and per-token forwarded amounts so the outer collectSwapAggregateFeesForHook
     * can decode them for AureumFeeRoutingHook.
     */
    // Rationale: hook executes inside Vault unlock context; Vault reentrancy
    // lock held throughout the external calls and subsequent event emissions.
    // slither-disable-next-line reentrancy-events
    function collectAggregateFeesHookSwapForward(
        address pool
    ) external onlyVault returns (IERC20[] memory tokens, uint256[] memory forwardedAmounts) {
        (uint256[] memory totalSwapFees, uint256[] memory totalYieldFees) = _vault.collectAggregateFees(pool);
        _receiveAggregateFees(pool, ProtocolFeeType.YIELD, totalYieldFees);
        (IERC20[] memory poolTokens,) = _getPoolTokensAndCount(pool);
        forwardedAmounts = _receiveAggregateFeesSwapForward(pool, poolTokens, totalSwapFees);
        tokens = poolTokens;
    }

    /**
     * @dev β1 swap-leg forward — for each `tokens[i]` with `totalSwapFees[i] > 0`, drains the
     * Vault credit to FEE_ROUTING_HOOK via _vault.sendTo and emits SwapLegFeeForwarded. Never
     * credits _protocolFeeAmounts (D17 invariant 1). The yield leg is handled separately by
     * the upstream _receiveAggregateFees path inside collectAggregateFeesHookSwapForward.
     */
    // Rationale: forward executes inside Vault unlock context; Vault reentrancy lock held throughout the sendTo() calls and SwapLegFeeForwarded emissions.
    // slither-disable-next-line reentrancy-no-eth,reentrancy-events
    function _receiveAggregateFeesSwapForward(
        address pool,
        IERC20[] memory tokens,
        uint256[] memory totalSwapFees
    ) internal returns (uint256[] memory forwardedAmounts) {
        forwardedAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (totalSwapFees[i] > 0) {
                IERC20 token = tokens[i];

                // slither-disable-next-line calls-loop
                _vault.sendTo(token, FEE_ROUTING_HOOK, totalSwapFees[i]);
                emit SwapLegFeeForwarded(pool, address(token), totalSwapFees[i]);
                forwardedAmounts[i] = totalSwapFees[i];
            }
        }
    }

    /// @inheritdoc IProtocolFeeController
    function getGlobalProtocolSwapFeePercentage() external view returns (uint256) {
        return _globalProtocolSwapFeePercentage;
    }

    /// @inheritdoc IProtocolFeeController
    function getGlobalProtocolYieldFeePercentage() external view returns (uint256) {
        return _globalProtocolYieldFeePercentage;
    }

    /// @inheritdoc IProtocolFeeController
    function getPoolProtocolSwapFeeInfo(address pool) external view returns (uint256, bool) {
        PoolFeeConfig memory config = _poolProtocolSwapFeePercentages[pool];

        return (config.feePercentage, config.isOverride);
    }

    /// @inheritdoc IProtocolFeeController
    function getPoolProtocolYieldFeeInfo(address pool) external view returns (uint256, bool) {
        PoolFeeConfig memory config = _poolProtocolYieldFeePercentages[pool];

        return (config.feePercentage, config.isOverride);
    }

    /// @inheritdoc IProtocolFeeController
    function getProtocolFeeAmounts(address pool) external view returns (uint256[] memory feeAmounts) {
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        feeAmounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            feeAmounts[i] = _protocolFeeAmounts[pool][poolTokens[i]];
        }
    }

    /// @inheritdoc IProtocolFeeController
    function getPoolCreatorFeeAmounts(address pool) external view returns (uint256[] memory feeAmounts) {
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        feeAmounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            feeAmounts[i] = _poolCreatorFeeAmounts[pool][poolTokens[i]];
        }
    }

    /// @inheritdoc IProtocolFeeController
    function computeAggregateFeePercentage(
        uint256 protocolFeePercentage,
        uint256 poolCreatorFeePercentage
    ) external pure returns (uint256) {
        return _computeAggregateFeePercentage(protocolFeePercentage, poolCreatorFeePercentage);
    }

    /// @inheritdoc IProtocolFeeController
    // Rationale: events emitted after Vault calls inside the unlock context;
    // Vault reentrancy lock prevents observer action within the same tx.
    // slither-disable-next-line reentrancy-events
    function updateProtocolSwapFeePercentage(address pool) external withLatestFees(pool) {
        PoolFeeConfig memory feeConfig = _poolProtocolSwapFeePercentages[pool];
        uint256 globalProtocolSwapFee = _globalProtocolSwapFeePercentage;

        // Rationale: stylistic. Upstream-verbatim; preserved to minimize fork diff.
        // slither-disable-next-line boolean-equal
        if (feeConfig.isOverride == false && globalProtocolSwapFee != feeConfig.feePercentage) {
            _updatePoolSwapFeePercentage(pool, globalProtocolSwapFee, false);
        }
    }

    /// @inheritdoc IProtocolFeeController
    // Rationale: events emitted after Vault calls inside the unlock context;
    // Vault reentrancy lock prevents observer action within the same tx.
    // slither-disable-next-line reentrancy-events
    function updateProtocolYieldFeePercentage(address pool) external withLatestFees(pool) {
        PoolFeeConfig memory feeConfig = _poolProtocolYieldFeePercentages[pool];
        uint256 globalProtocolYieldFee = _globalProtocolYieldFeePercentage;

        // Rationale: stylistic. Upstream-verbatim; preserved to minimize fork diff.
        // slither-disable-next-line boolean-equal
        if (feeConfig.isOverride == false && globalProtocolYieldFee != feeConfig.feePercentage) {
            _updatePoolYieldFeePercentage(pool, globalProtocolYieldFee, false);
        }
    }

    function _getAggregateFeePercentage(address pool, ProtocolFeeType feeType) internal view returns (uint256) {
        uint256 protocolFeePercentage;
        uint256 poolCreatorFeePercentage;

        if (feeType == ProtocolFeeType.SWAP) {
            protocolFeePercentage = _poolProtocolSwapFeePercentages[pool].feePercentage;
            poolCreatorFeePercentage = _poolCreatorSwapFeePercentages[pool];
        } else {
            protocolFeePercentage = _poolProtocolYieldFeePercentages[pool].feePercentage;
            poolCreatorFeePercentage = _poolCreatorYieldFeePercentages[pool];
        }

        return _computeAggregateFeePercentage(protocolFeePercentage, poolCreatorFeePercentage);
    }

    function _computeAggregateFeePercentage(
        uint256 protocolFeePercentage,
        uint256 poolCreatorFeePercentage
    ) internal pure returns (uint256 aggregateFeePercentage) {
        aggregateFeePercentage =
            protocolFeePercentage +
            protocolFeePercentage.complement().mulDown(poolCreatorFeePercentage);

        // Protocol fee percentages are limited to 24-bit precision for performance reasons (i.e., to fit all the fees
        // in a single slot), and because high precision is not needed. Generally we expect protocol fees set by
        // governance to be simple integers.
        //
        // However, the pool creator fee is entirely controlled by the pool creator, and it is possible to craft a
        // valid pool creator fee percentage that would cause the aggregate fee percentage to fail the precision check.
        // This case should be rare, so we ensure this can't happen by truncating the final value.
        // Rationale: intentional precision-truncation idiom (round down to a
        // multiple of FEE_SCALING_FACTOR). Upstream Balancer fee math pattern.
        // slither-disable-next-line divide-before-multiply
        aggregateFeePercentage = (aggregateFeePercentage / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR;
    }

    // Rationale: orphaned by Aureum B19 design — public entry points were
    // replaced with revert stubs to disable pool-creator fees, but internal
    // helpers are preserved to minimize diff vs upstream Balancer V3.
    // slither-disable-next-line dead-code
    function _ensureCallerIsPoolCreator(address pool) internal view {
        address poolCreator = _poolCreators[pool];

        if (poolCreator == address(0)) {
            revert PoolCreatorNotRegistered(pool);
        }

        if (poolCreator != msg.sender) {
            revert CallerIsNotPoolCreator(msg.sender, pool);
        }
    }

    function _getPoolTokensAndCount(address pool) internal view returns (IERC20[] memory tokens, uint256 numTokens) {
        tokens = _vault.getPoolTokens(pool);
        numTokens = tokens.length;
    }

    /***************************************************************************
                                Permissioned Functions
    ***************************************************************************/

    /// @inheritdoc IProtocolFeeController
    /// @dev Aureum D-D15 override: the swap-fee side always registers at
    ///      `_globalProtocolSwapFeePercentage` (pinned to 50e16 in the constructor),
    ///      regardless of the `protocolFeeExempt` flag. This closes the hole where a
    ///      factory passing `protocolFeeExempt = true` would set the pool's swap-fee
    ///      to 0 and bypass the 50/50 split. The yield-fee side still honors the
    ///      exempt flag — Bodensee yield collection is gated separately by D-D9.
    function registerPool(
        address pool,
        address poolCreator,
        bool protocolFeeExempt
    ) external onlyVault returns (uint256 aggregateSwapFeePercentage, uint256 aggregateYieldFeePercentage) {
        _poolCreators[pool] = poolCreator;

        // Set local storage of the actual percentages for the pool (default to global).
        // D-D15: swap-fee is pinned to the global (50e16) unconditionally; the exempt
        // flag is ignored for the swap side. Yield side still honors the exempt flag.
        aggregateSwapFeePercentage = _globalProtocolSwapFeePercentage;
        aggregateYieldFeePercentage = protocolFeeExempt ? 0 : _globalProtocolYieldFeePercentage;

        // `isOverride` is true if the pool is protocol fee exempt; otherwise, default to false.
        // If exempt, this pool cannot be updated to the current global percentage permissionlessly.
        // The percentages are 18 decimal floating point numbers, bound between 0 and the max fee (<= FixedPoint.ONE).
        // Since this fits in 64 bits, the SafeCast shouldn't be necessary, and is done out of an abundance of caution.
        _poolProtocolSwapFeePercentages[pool] = PoolFeeConfig({
            feePercentage: aggregateSwapFeePercentage.toUint64(),
            // D-D15: swap-side isOverride is always false. The pinned value is canonical,
            // and `updateProtocolSwapFeePercentage(pool)` is a no-op post-retrofit.
            isOverride: false
        });
        _poolProtocolYieldFeePercentages[pool] = PoolFeeConfig({
            feePercentage: aggregateYieldFeePercentage.toUint64(),
            isOverride: protocolFeeExempt
        });
    }

    /// @inheritdoc IProtocolFeeController
    /// @dev Disabled per Aureum D-D15. The global protocol swap-fee percentage is pinned
    ///      at `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE` (50e16) in the constructor and is not
    ///      governance-adjustable. Any call reverts with `SplitIsImmutable`.
    function setGlobalProtocolSwapFeePercentage(
        uint256 /* newProtocolSwapFeePercentage */
    ) external pure {
        revert SplitIsImmutable();
    }

    /// @inheritdoc IProtocolFeeController
    /// @dev Disabled per PP-D48 (iv). The ERC-4626 yield skim is pinned to the
    ///      constitutional 10% at construction and applies uniformly to every pool;
    ///      per `10_constitution.md` §xxix L150—151 it is immutable from block 0, so
    ///      there is no governance path to change it. Any call reverts with
    ///      `YieldSkimIsImmutable`.
    function setGlobalProtocolYieldFeePercentage(
        uint256 /* newProtocolYieldFeePercentage */
    ) external pure {
        revert YieldSkimIsImmutable();
    }

    /// @inheritdoc IProtocolFeeController
    /// @dev Disabled per Aureum D-D15. Per-pool overrides would defeat the 50/50 split;
    ///      the pinned `MAX_PROTOCOL_SWAP_FEE_PERCENTAGE` applies uniformly to every pool
    ///      registered through the Vault. Any call reverts with `SplitIsImmutable`.
    function setProtocolSwapFeePercentage(
        address /* pool */,
        uint256 /* newProtocolSwapFeePercentage */
    ) external pure {
        revert SplitIsImmutable();
    }

    /// @inheritdoc IProtocolFeeController
    /// @dev Disabled per PP-D48 (iv). Per-pool overrides would defeat the uniform skim;
    ///      the pinned constitutional value applies to every pool registered through the
    ///      Vault. Any call reverts with `YieldSkimIsImmutable`.
    function setProtocolYieldFeePercentage(
        address /* pool */,
        uint256 /* newProtocolYieldFeePercentage */
    ) external pure {
        revert YieldSkimIsImmutable();
    }

    /// @inheritdoc IProtocolFeeController
    function setPoolCreatorSwapFeePercentage(
        address /* pool */,
        uint256 /* poolCreatorSwapFeePercentage */
    ) external pure {
        revert CreatorFeesDisabled();
    }

    /// @inheritdoc IProtocolFeeController
    function setPoolCreatorYieldFeePercentage(
        address /* pool */,
        uint256 /* poolCreatorYieldFeePercentage */
    ) external pure {
        revert CreatorFeesDisabled();
    }

    // Rationale (dead-code): orphaned by B19 revert-stub design; preserved
    // to minimize diff vs upstream Balancer V3.
    // Rationale (reentrancy-events): events emitted after Vault calls inside
    // unlock context; Vault reentrancy lock held throughout (moot since dead).
    // slither-disable-next-line dead-code,reentrancy-events
    function _setPoolCreatorFeePercentage(
        address pool,
        uint256 poolCreatorFeePercentage,
        ProtocolFeeType feeType
    ) internal {
        // Need to set locally, and update the aggregate percentage in the Vault.
        if (feeType == ProtocolFeeType.SWAP) {
            _poolCreatorSwapFeePercentages[pool] = poolCreatorFeePercentage;

            // The Vault will also emit an `AggregateSwapFeePercentageChanged` event.
            _vault.updateAggregateSwapFeePercentage(pool, _getAggregateFeePercentage(pool, ProtocolFeeType.SWAP));

            emit PoolCreatorSwapFeePercentageChanged(pool, poolCreatorFeePercentage);
        } else {
            _poolCreatorYieldFeePercentages[pool] = poolCreatorFeePercentage;

            // The Vault will also emit an `AggregateYieldFeePercentageChanged` event.
            _vault.updateAggregateYieldFeePercentage(pool, _getAggregateFeePercentage(pool, ProtocolFeeType.YIELD));

            emit PoolCreatorYieldFeePercentageChanged(pool, poolCreatorFeePercentage);
        }
    }

    /// @inheritdoc IProtocolFeeController
    /// @dev E.2 (PP-D48 (ii)): deliberately NOT `authenticate`-gated. The gate was
    ///      removed rather than retargeted because it protected nothing — `recipient` is
    ///      pinned to `FEE_ROUTING_HOOK` two lines below, so the only reachable effect is
    ///      moving a pool's own credit to the hook, which is where the fee pipeline sends
    ///      it regardless. Post-K the gate resolved to `AureumGovernance`, which cannot
    ///      express this call under fixed dispatch, leaving the fees withdrawable by
    ///      nobody; permissionless with a pinned recipient is strictly safer than gated
    ///      and unreachable. This does NOT touch `04_tokenomics.md` L155, which governs
    ///      ROUTING INTO der Bodensee — `routeYieldFeeToHook` keeps its gate per PP-D48
    ///      clause (v), still open.
    function withdrawProtocolFees(address pool, address recipient) external {
        if (recipient != FEE_ROUTING_HOOK) {
            revert InvalidRecipient(FEE_ROUTING_HOOK, recipient);
        }
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        for (uint256 i = 0; i < numTokens; ++i) {
            IERC20 token = poolTokens[i];

            _withdrawProtocolFees(pool, recipient, token);
        }
    }

    /// @inheritdoc IProtocolFeeController
    /// @dev E.2 (PP-D48 (ii)): ungated for the same reason as `withdrawProtocolFees`
    ///      above — the recipient pin below is the actual control, and the gate removed
    ///      here was unreachable post-K rather than protective.
    function withdrawProtocolFeesForToken(address pool, address recipient, IERC20 token) external {
        if (recipient != FEE_ROUTING_HOOK) {
            revert InvalidRecipient(FEE_ROUTING_HOOK, recipient);
        }
        // Revert if the pool is not registered or if the token does not belong to the pool.
        // Rationale: called for its revert side effect (validates token belongs
        // to pool); return values intentionally unused. Upstream pattern.
        // slither-disable-next-line unused-return
        _vault.getPoolTokenCountAndIndexOfToken(pool, token);
        _withdrawProtocolFees(pool, recipient, token);
    }

    /// @notice Seat or rotate the scheduled principal permitted to drive
    ///         `routeYieldFeeToHook` alongside the hook's governance Safe.
    /// @dev PP-D48 clause (v), decisions (b) and (c). Gated on the hook's
    ///      `governanceModule` Safe rather than on `authenticate`, and that is
    ///      not a stylistic choice: `authenticate` resolving to an
    ///      inexpressible `AureumGovernance` IS the defect E.2 reports, so an
    ///      `authenticate`-gated keeper setter would be unreachable for exactly
    ///      the same reason and the keeper could never be rotated once seated.
    ///      A zero `governanceModule` fails CLOSED — nobody may seat a keeper
    ///      before the hook's one-shot `setGovernanceModule` has fired.
    ///      `newKeeper == address(0)` is PERMITTED and disables the keeper leg
    ///      without stranding the skim, since the Safe remains admissible at
    ///      `routeYieldFeeToHook`; this mirrors the H-D29 zero valve rather
    ///      than inventing a new one.
    /// @param newKeeper The address to seat, or `address(0)` to disable the leg.
    function setYieldRouteKeeper(address newKeeper) external {
        address authority = IAureumFeeRoutingHook(FEE_ROUTING_HOOK).governanceModule();
        if (authority == address(0) || msg.sender != authority) {
            revert NotKeeperAuthority(msg.sender);
        }
        emit YieldRouteKeeperChanged(yieldRouteKeeper, newKeeper);
        yieldRouteKeeper = newKeeper;
    }

    /// @notice Route collected ERC-4626 yield fees for `pool` into the
    ///         AureumFeeRoutingHook pipeline (OQ-20 Option A / D4.6).
    /// @dev Gated, but NOT on `authenticate`. PP-D48 clause (v) keeps a gate
    ///      because `04_tokenomics.md` L155 specifies routing into der Bodensee
    ///      as governance-gated at most once per epoch, and resolves the caller's
    ///      post-K unreachability by RETARGETING the principal rather than by
    ///      deleting the gate. The admissible callers are the seated
    ///      `yieldRouteKeeper` — a scheduled keeper computing
    ///      `minDepositTokenOut` off-chain, which PRESERVES PB-D9 (iii) rather
    ///      than falsifying it — and the hook's `governanceModule` Safe as a
    ///      standing fallback, so a stalled keeper defers the skim instead of
    ///      stranding it. `authenticate` is deliberately absent: it resolves to
    ///      an `AureumGovernance` that cannot express this call under fixed
    ///      dispatch, which is E.2 itself. The caller check runs BEFORE the
    ///      throttle so an inadmissible caller sees `NotYieldRouteKeeper`.
    ///      E.4 (PP-D48 (i)): the routed amount is no longer a parameter. It is
    ///      READ from `_protocolFeeAmounts[pool][token]` and ZEROED before the
    ///      hook is approved, so the ledger is debited by exactly what leaves,
    ///      mirroring `_withdrawProtocolFees` below. The prior form approved and
    ///      let the hook pull a caller-supplied `amount` out of the controller's
    ///      COMMINGLED balance with no debit and no bound against the pool's own
    ///      credit, so one pool's route could spend another pool's fees.
    ///      `minBptAmountOut` is likewise gone, passed as 0: PB-D68 (xiv) makes
    ///      the der-Bodensee leg a DONATION returning zero BPT that reverts
    ///      `BptFloorUnavailableOnDonation` on any non-zero floor, so the only
    ///      satisfiable value was 0 and exposing it was a footgun.
    ///      The hook pulls via `safeTransferFrom`, preserving the leg asymmetry
    ///      (B10 `safeTransfer` vs yield `safeTransferFrom`, OQ-20). Remaining
    ///      validation stays hook-side (caller-pin, ZeroAddress,
    ///      InvalidPool(DER_BODENSEE), ZeroAmount — the last now firing when a
    ///      pool holds no credit rather than on a caller's zero argument).
    ///      The per-pool `BLOCKS_PER_EPOCH` throttle (OQ-21) stamps only after a
    ///      successful route, so a reverting hook call does not burn the pool's
    ///      epoch — including bound-tripped reverts per PB-D9. Observability is
    ///      the hook's `YieldFeeRouted` event.
    /// @param pool The source pool whose collected yield fees are routed.
    /// @param token The yield-fee token to route.
    /// @param minDepositTokenOut Minimum deposit-token output of the internal
    ///        conversion swap, EXACT_IN semantics, enforced only when the swap
    ///        leg runs and inert on the rate-exact ZCHF-to-svZCHF ERC-4626 fast
    ///        path and the same-token no-op.
    /// @return bptMinted BPT minted to this controller by the hook — ZERO on
    ///         every route since PB-D68 (xiv), retained as the hook interface's
    ///         return rather than dropped here.
    function routeYieldFeeToHook(
        address pool,
        IERC20 token,
        uint256 minDepositTokenOut
    ) external returns (uint256 bptMinted) {
        if (msg.sender != yieldRouteKeeper) {
            address authority = IAureumFeeRoutingHook(FEE_ROUTING_HOOK).governanceModule();
            if (authority == address(0) || msg.sender != authority) {
                revert NotYieldRouteKeeper(msg.sender);
            }
        }
        if (block.number < _lastRouteBlock[pool] + AureumTime.BLOCKS_PER_EPOCH) {
            revert RouteThrottled();
        }
        uint256 amount = _protocolFeeAmounts[pool][token];
        _protocolFeeAmounts[pool][token] = 0;
        token.forceApprove(FEE_ROUTING_HOOK, amount);
        bptMinted = IAureumFeeRoutingHook(FEE_ROUTING_HOOK).routeYieldFee(
            pool,
            token,
            amount,
            minDepositTokenOut,
            0
        );
        _lastRouteBlock[pool] = block.number;
    }

    // AUREUM NOTE: Identical to upstream ProtocolFeeController.sol L504-512.
    // B10 recipient enforcement happens in the two public callers above; this
    // helper does not validate recipient — it trusts the public boundary.
    function _withdrawProtocolFees(address pool, address recipient, IERC20 token) internal {
        uint256 amountToWithdraw = _protocolFeeAmounts[pool][token];
        if (amountToWithdraw > 0) {
            _protocolFeeAmounts[pool][token] = 0;
            token.safeTransfer(recipient, amountToWithdraw);

            emit ProtocolFeesWithdrawn(pool, token, recipient, amountToWithdraw);
        }
    }

    /// @inheritdoc IProtocolFeeController
    function withdrawPoolCreatorFees(address /* pool */, address /* recipient */) external pure {
        revert CreatorFeesDisabled();
    }

    /// @inheritdoc IProtocolFeeController
    function withdrawPoolCreatorFees(address /* pool */) external pure {
        revert CreatorFeesDisabled();
    }

    // Rationale: orphaned by Aureum B19 design — public entry points were
    // replaced with revert stubs to disable pool-creator fees, but internal
    // helpers are preserved to minimize diff vs upstream Balancer V3.
    // slither-disable-next-line dead-code
    function _withdrawPoolCreatorFees(address pool, address recipient) private {
        (IERC20[] memory poolTokens, uint256 numTokens) = _getPoolTokensAndCount(pool);

        for (uint256 i = 0; i < numTokens; ++i) {
            IERC20 token = poolTokens[i];

            uint256 amountToWithdraw = _poolCreatorFeeAmounts[pool][token];
            if (amountToWithdraw > 0) {
                _poolCreatorFeeAmounts[pool][token] = 0;
                token.safeTransfer(recipient, amountToWithdraw);

                emit PoolCreatorFeesWithdrawn(pool, token, recipient, amountToWithdraw);
            }
        }
    }

    /// @dev Common code shared between set/update. `isOverride` will be true if governance is setting the percentage.
    // Rationale: events emitted after Vault calls inside the unlock context;
    // Vault reentrancy lock prevents observer action within the same tx.
    // slither-disable-next-line reentrancy-events
    function _updatePoolSwapFeePercentage(address pool, uint256 newProtocolSwapFeePercentage, bool isOverride) private {
        // Update local storage of the raw percentage.
        //
        // The percentages are 18 decimal floating point numbers, bound between 0 and the max fee (<= FixedPoint.ONE).
        // Since this fits in 64 bits, the SafeCast shouldn't be necessary, and is done out of an abundance of caution.
        _poolProtocolSwapFeePercentages[pool] = PoolFeeConfig({
            feePercentage: newProtocolSwapFeePercentage.toUint64(),
            isOverride: isOverride
        });

        // Update the resulting aggregate swap fee value in the Vault (PoolConfig).
        _vault.updateAggregateSwapFeePercentage(pool, _getAggregateFeePercentage(pool, ProtocolFeeType.SWAP));

        emit ProtocolSwapFeePercentageChanged(pool, newProtocolSwapFeePercentage);
    }

    /// @dev Common code shared between set/update. `isOverride` will be true if governance is setting the percentage.
    // Rationale: events emitted after Vault calls inside the unlock context;
    // Vault reentrancy lock prevents observer action within the same tx.
    // slither-disable-next-line reentrancy-events
    function _updatePoolYieldFeePercentage(
        address pool,
        uint256 newProtocolYieldFeePercentage,
        bool isOverride
    ) private {
        // Update local storage of the raw percentage.
        // The percentages are 18 decimal floating point numbers, bound between 0 and the max fee (<= FixedPoint.ONE).
        // Since this fits in 64 bits, the SafeCast shouldn't be necessary, and is done out of an abundance of caution.
        _poolProtocolYieldFeePercentages[pool] = PoolFeeConfig({
            feePercentage: newProtocolYieldFeePercentage.toUint64(),
            isOverride: isOverride
        });

        // Update the resulting aggregate yield fee value in the Vault (PoolConfig).
        _vault.updateAggregateYieldFeePercentage(pool, _getAggregateFeePercentage(pool, ProtocolFeeType.YIELD));

        emit ProtocolYieldFeePercentageChanged(pool, newProtocolYieldFeePercentage);
    }

    function _ensureValidPrecision(uint256 feePercentage) private pure {
        // Primary fee percentages are 18-decimal values, stored here in 64 bits, and calculated with full 256-bit
        // precision. However, the resulting aggregate fees are stored in the Vault with 24-bit precision, which
        // corresponds to 0.00001% resolution (i.e., a fee can be 1%, 1.00001%, 1.00002%, but not 1.000005%).
        // Ensure there will be no precision loss in the Vault - which would lead to a discrepancy between the
        // aggregate fee calculated here and that stored in the Vault.
        // Rationale: intentional precision-truncation idiom (round down to a
        // multiple of FEE_SCALING_FACTOR, then check equality). Upstream
        // Balancer fee math pattern.
        // slither-disable-next-line divide-before-multiply
        if ((feePercentage / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR != feePercentage) {
            revert IVaultErrors.FeePrecisionTooHigh();
        }
    }
}
