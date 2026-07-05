// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {AddLiquidityKind, AddLiquidityParams} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {TransientStorageHelpers} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";
import {StorageSlotExtension} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol";
import {IBodenseeBootstrapChannel} from "./IBodenseeBootstrapChannel.sol";
import {IAuMM} from "../token/IAuMM.sol";
import {IAuMMMinterRouter} from "../token/IAuMMMinterRouter.sol";
import {AureumTime} from "../lib/AureumTime.sol";

/// @title BodenseeBootstrapChannel — F-0 piecewise bootstrap rail routing accrued AuMM to der Bodensee from GENESIS_BLOCK through month10EndBlock per H-D2
/// @notice Permissionless accrue() advances pendingAccrual and lastAccrualBlock via AP piecewise integration (Bootstrap A: 80% to 50% over Months 0—6; Bootstrap B: 50% to 0% over Months 6—10) without minting. Governance-gated distribute() mints the accrued AuMM and performs a one-sided Balancer V3 AddLiquidityKind.DONATION into der Bodensee via IVault.unlock per H-D11 + H-D12.
/// @dev H-D14 — distribute() gated by onlyGovernance; BODENSEE_POOL is immutable (structurally stronger than H-D8 mutable constellation roster; no setBodenseePool setter). H-D12 — does NOT reuse SwapAndDepositToBodensee.donate (rejects non-svZCHF/sUSDS payToken per src/gauge/SwapAndDepositToBodensee.sol L362—L364); own IVault.unlock callback path with 3 transient slots. H-D13 — no selfdestruct / pause; permanent zero-activity fixture post-window with readable accumulator state. Stage K governance handoff via setGovernanceContract. K-D7 mint wiring — distribute() mints via mintRouter.mintFor (the AuMMMinterRouter holds AuMM's C-D11 one-shot minter slot, bound one-shot via setMintRouter and receiving the slot at K7 via aumm.setMinter(router)), superseding the H-D7 IAuMM.setMinter(address(this)) deploy prerequisite.
contract BodenseeBootstrapChannel is IBodenseeBootstrapChannel {
    using SafeERC20 for IERC20;
    using StorageSlotExtension for *;

    /* ---------- Immutables ---------- */

    /// @notice Balancer V3 Vault — entry point for IVault.unlock callback in distribute() per H-D12.
    IVault internal immutable _vault;

    /// @notice Immutable bootstrap destination — der Bodensee pool address per H-D14; no setBodenseePool setter (structurally stronger than H-D8 governance-extensible constellation roster).
    address public immutable BODENSEE_POOL;

    /// @notice AuMM token — read for blockEmissionRate() in accrue() and cast to IERC20 for the distribute() transfer/settle/balance path. Per K-D7 the mint itself routes through mintRouter.mintFor, not IAuMM.mint directly; the immutable is retained for these reads (the C-D11 minter slot now lives on the AuMMMinterRouter).
    IAuMM public immutable AuMM;

    /// @notice AuMM token index within the Bodensee pool roster — derived at construction via _vault.getPoolTokens(BODENSEE_POOL) loop per H-D12; used to build maxAmountsIn[_aummIndex] in the DONATION callback. Reverts IndexLookupFailed at construction if AuMM is absent from the Bodensee roster.
    uint8 internal immutable _aummIndex;

    /// @notice Stage H genesis block — anchors AureumTime.month6EndBlock(GENESIS_BLOCK) and AureumTime.month10EndBlock(GENESIS_BLOCK) calls in accrue() per H-D11. Same constructor-parameter precedent as AuMM.sol GENESIS_BLOCK.
    uint256 public immutable GENESIS_BLOCK;

    /* ---------- Governance (H-D14) ---------- */

    /// @notice Governance authority — Stage A—K Authorizer Safe at deploy; rebound via setGovernanceContract at Stage K per H-D14. Gates distribute() via onlyGovernance.
    address public governance;

    /* ---------- Mint router (K-D7) ---------- */

    /// @notice The AuMMMinterRouter holding AuMM's C-D11 one-shot minter slot per K-D7 — distribute() forwards mints through `mintRouter.mintFor`. Bound exactly once via `setMintRouter`; zero until then, after which distribute() goes live.
    IAuMMMinterRouter public mintRouter;

    /* ---------- Accrue state (H-D11) ---------- */

    /// @notice Accumulated AuMM (scaled18) not yet minted and donated to der Bodensee — incremented by accrue() AP sum per H-D11; zeroed by distribute() before the mintRouter.mintFor call. Satisfies IBodenseeBootstrapChannel.pendingAccrual() view via public getter.
    uint256 public pendingAccrual;

    /// @notice Cumulative AuMM (scaled18) successfully minted and donated since deployment — incremented by distribute(), never decremented per H-D11. Satisfies IBodenseeBootstrapChannel.totalDistributed() view via public getter.
    uint256 public totalDistributed;

    /// @notice Last block through which pendingAccrual has been computed — advanced to min(block.number, month10EndBlock) on each accrue() call; initialized to GENESIS_BLOCK in the constructor per H-D11. Satisfies IBodenseeBootstrapChannel.lastAccrualBlock() view via public getter.
    uint256 public lastAccrualBlock;

    /* ---------- Transient slot constants (H-D12) ---------- */

    /// @dev EIP-1153 transient slots via Balancer V3 assembly-helper pattern per G-D14; 3-slot layout (_PENDING_PAY_TOKEN_SLOT dropped vs SwapAndDepositToBodensee — pay token is always AuMM, an immutable); solc 0.8.26 lacks the transient state-var keyword.
    bytes32 internal immutable _EXECUTING_SLOT = TransientStorageHelpers.calculateSlot("aureum.bodenseeBootstrapChannel", "executing");
    bytes32 internal immutable _PENDING_AMOUNT_SLOT = TransientStorageHelpers.calculateSlot("aureum.bodenseeBootstrapChannel", "pendingAmount");
    bytes32 internal immutable _ORIGINAL_CALLER_SLOT = TransientStorageHelpers.calculateSlot("aureum.bodenseeBootstrapChannel", "originalCaller");

    /* ---------- Errors ---------- */

    /// @notice Reverts when a zero address is supplied for an immutable or the initial governance slot.
    error ZeroAddress();

    /// @notice Reverts when distribute() is called with pendingAccrual == 0.
    error NoPendingAccrual();

    /// @notice Reverts when a non-governance address invokes distribute() or setGovernanceContract.
    error NotGovernance(address caller);

    /// @notice Reverts at construction if AuMM is not found in der Bodensee's token roster — misconfigured deploy is unrecoverable per H-D12.
    error IndexLookupFailed();

    /// @notice Reverts in _distributeCallback when the callback payload does not match _PENDING_AMOUNT_SLOT — mirrors SwapAndDepositToBodensee G-D11 sentinel.
    error CallbackPayloadMismatch(uint256 expected, uint256 actual);

    /// @notice Reverts in _distributeCallback when msg.sender != address(_vault) — identical to SwapAndDepositToBodensee G-D11 / G-D21 OnlyVault guard.
    error OnlyVault(address caller);

    /// @notice Reverts post-unlock if IERC20(address(AuMM)).balanceOf(address(this)) != 0 — ensures complete AuMM settlement per H-D12 residual assert.
    error HelperBalanceNonZero(uint256 residual);

    /// @notice Reverts when distribute() is called while `_EXECUTING_SLOT` transient is already true — guards against re-entrant unlock per H-D12 (mirrors SwapAndDepositToBodensee G-D11).
    error ReentrancyGuard();

    /// @notice Reverts in `_distributeCallback` when DONATION returned `bptOut != 0` — `AddLiquidityKind.DONATION` must mint zero BPT per Balancer V3 invariant (mirrors SwapAndDepositToBodensee G-D11).
    error BptMintedOnDonation(uint256 bptOut);

    /// @notice Reverts in `_distributeCallback` when `postReserve != preReserve + amount` — AuMM reserve must increase by exactly `amount` after DONATION settlement (mirrors SwapAndDepositToBodensee G-D18).
    error ReserveDeltaMismatch(uint256 expected, uint256 actual);

    /// @notice Reverts when `setMintRouter` is called after the mint router has already been bound — the binding is one-shot per K-D7.
    error MintRouterAlreadySet();

    /// @notice Reverts in distribute() when the mint router has not been bound — `setMintRouter` must run before distribute() can mint. Replaces the H-D7 `NotMinter` revert posture per K-D7.
    error MintRouterNotSet();

    /* ---------- Events ---------- */

    /// @notice Emitted when setGovernanceContract rebinds the governance authority (Stage K handoff per H-D14).
    event GovernanceTransferred(address indexed oldGovernance, address indexed newGovernance);

    /// @notice Emitted once when `setMintRouter` binds the AuMMMinterRouter (K-D7 wiring at K7).
    event MintRouterBound(address indexed router);

    /* ---------- Constructor ---------- */

    /**
     * @notice Wires the 5 core immutables + initial governance + lastAccrualBlock for the H-D11 / H-D12 BodenseeBootstrapChannel.
     * @dev Resolves `_aummIndex` via `vault_.getPoolTokens(bodensee_)` loop with `type(uint8).max` sentinel per H-D12; reverts `IndexLookupFailed` if AuMM is not present in der Bodensee's token roster (misconfigured deploy is unrecoverable per H-D12). ZeroAddress guards apply to the 4 address-bearing params; `genesisBlock_` accepts any `uint256` value (deploy-time correctness is governance's responsibility — same pattern as EfficiencyOracle H2b.2). `lastAccrualBlock` initialized to `genesisBlock_` per H-D11 so the first `accrue()` call computes from block `genesisBlock_ + 1`. No constructor emit for `GovernanceTransferred` — mirrors TVLOracle / EfficiencyOracle pattern where the initial governance slot is set silently.
     * @param vault_ Balancer V3 Vault — `IVault.unlock` callback entry point per H-D12. Reverts `ZeroAddress` on zero input.
     * @param bodensee_ der Bodensee pool address — bootstrap destination per H-D14. Reverts `ZeroAddress` on zero input.
     * @param aumm_ AuMM token — must be a token in der Bodensee's roster, else `IndexLookupFailed`. Reverts `ZeroAddress` on zero input.
     * @param genesisBlock_ Stage H genesis block — anchors `AureumTime` helpers in `accrue()` per H-D11. No zero-check (uint256, accepts any value).
     * @param initialGovernance_ Initial governance authority — Stage A—K Authorizer Safe at deploy; rebound at Stage K via `setGovernanceContract`. Reverts `ZeroAddress` on zero input.
     */
    constructor(
        IVault vault_,
        address bodensee_,
        IAuMM aumm_,
        uint256 genesisBlock_,
        address initialGovernance_
    ) {
        if (address(vault_) == address(0)) revert ZeroAddress();
        if (bodensee_ == address(0)) revert ZeroAddress();
        if (address(aumm_) == address(0)) revert ZeroAddress();
        if (initialGovernance_ == address(0)) revert ZeroAddress();

        _vault = vault_;
        BODENSEE_POOL = bodensee_;
        AuMM = aumm_;
        GENESIS_BLOCK = genesisBlock_;
        governance = initialGovernance_;
        lastAccrualBlock = genesisBlock_;

        IERC20[] memory tokens = vault_.getPoolTokens(bodensee_);
        uint256 len = tokens.length;
        uint8 aummIndex_ = type(uint8).max;
        for (uint256 i = 0; i < len; ++i) {
            if (address(tokens[i]) == address(aumm_)) {
                // uint8(i) is safe: Bodensee is a 3-token pool by construction; len <= 3, i in {0, 1, 2}; sentinel type(uint8).max reserved by the post-loop not-found check.
                // forge-lint: disable-next-line(unsafe-typecast)
                aummIndex_ = uint8(i);
            }
        }
        if (aummIndex_ == type(uint8).max) revert IndexLookupFailed();

        _aummIndex = aummIndex_;
    }

    /* ---------- Modifiers ---------- */

    /// @notice Restricts execution to the current `governance` authority; reverts `NotGovernance(msg.sender)` otherwise.
    /// @dev H-D14 — `setGovernanceContract`-pivoting governance slot mirroring TVLOracle / EfficiencyOracle precedent.
    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance(msg.sender);
        _;
    }

    /* ---------- Governance ---------- */

    /**
     * @notice Stage K migration handoff per H-D14 — rebinds governance authority.
     * @dev `onlyGovernance`-gated; reverts `ZeroAddress` on zero input; emits `GovernanceTransferred(oldGovernance, newGovernance)`. Mirrors TVLOracle / EfficiencyOracle `setGovernanceContract`.
     * @param newGovernance The new governance authority — typically the on-chain governance contract at Stage K.
     */
    function setGovernanceContract(address newGovernance) external onlyGovernance {
        if (newGovernance == address(0)) revert ZeroAddress();
        address oldGovernance = governance;
        governance = newGovernance;
        emit GovernanceTransferred(oldGovernance, newGovernance);
    }

    /**
     * @notice One-shot binding of the AuMMMinterRouter per K-D7 — wires the mint path for distribute().
     * @dev `onlyGovernance`-gated; reverts `ZeroAddress` on zero input and `MintRouterAlreadySet` if already bound; emits `MintRouterBound(router_)`. Mirrors the I-D9 `setAuMTContractForPool` / H-D5 one-shot setter precedent. Executes at K7 step (2) while `governance` still points at the deploy-side authority, before the `setGovernanceContract` handoff per the K-D7 wiring order.
     * @param router_ The AuMMMinterRouter address — holds AuMM's C-D11 minter slot via `aumm.setMinter(router_)` at K7.
     */
    function setMintRouter(address router_) external onlyGovernance {
        if (router_ == address(0)) revert ZeroAddress();
        if (address(mintRouter) != address(0)) revert MintRouterAlreadySet();
        mintRouter = IAuMMMinterRouter(router_);
        emit MintRouterBound(router_);
    }

    /* ---------- Accrual (H-D11) ---------- */

    /**
     * @notice Permissionlessly advances `pendingAccrual` and `lastAccrualBlock` from `lastAccrualBlock + 1` through `min(block.number, month10EndBlock)` via AP piecewise integration over the F-0 piecewise share schedule per H-D11.
     * @dev O(1) regardless of interval length — each bootstrap leg is integrated via the arithmetic-progression closed-form `((first + last) / 2) × n × rate / 1e18`. Cross-boundary intervals (spanning `month6EndBlock`) split into two AP sums per H-D11 — A-leg covers `[from, month6End]` under Bootstrap A coefficients (80% to 50%), B-leg covers `[month6End + 1, to]` under Bootstrap B coefficients (50% to 0%). Lifecycle clamp `to = min(block.number, month10EndBlock)` per H-D13 — calls after the bootstrap window closes still capture residual emission up to `month10EndBlock` but no further; subsequent calls short-circuit via the empty-interval guard. Empty-interval guard `if (from > to) return;` short-circuits no-op calls (pre-genesis blocks, post-window dormancy) without emitting `Accrued`. `IAuMM.blockEmissionRate(to)` is snapshotted once per call per H-D11 / P-D19 (F-18) — keyed to the clamped integrand upper bound `to`, not `block.number`: since `to = min(block.number, month10EndBlock) < GENESIS_BLOCK + BLOCKS_PER_ERA` always (the bootstrap window lies wholly in Era 0), the rate resolves to `GENESIS_RATE` regardless of the call block, matching the `EmissionDistributor._lpTrancheIntegral` per-integrand-block basis so the channel's minted bootstrap tranche always equals the distributor's Era-0 subtraction from the LP tranche (H-D26 conservation); keying to `block.number` would under-price the tranche if the first bootstrap-spanning `accrue()` landed from an Era ≥ 1 block. No mint invoked — minting happens in `distribute()` via `mintRouter.mintFor` per H-D11 mint-at-distribute lock + K-D7. Permissionless (no access control) — bookkeeping advance is a public good per H-D11.
     */
    function accrue() external override {
        uint256 from = lastAccrualBlock + 1;
        uint256 month6End = AureumTime.month6EndBlock(GENESIS_BLOCK);
        uint256 month10End = AureumTime.month10EndBlock(GENESIS_BLOCK);
        uint256 to = block.number < month10End ? block.number : month10End;
        if (from > to) return;

        uint256 rate = AuMM.blockEmissionRate(to);
        uint256 contribution;

        if (to <= month6End) {
            // Entirely within Bootstrap A (80% to 50% over [genesisBlock, month6End])
            contribution = _apSum(from, to, GENESIS_BLOCK, month6End, 8e17, 3e17, rate);
        } else if (from > month6End) {
            // Entirely within Bootstrap B (50% to 0% over (month6End, month10End])
            contribution = _apSum(from, to, month6End, month10End, 5e17, 5e17, rate);
        } else {
            // Boundary-spanning: A-leg [from, month6End] + B-leg [month6End + 1, to] per H-D11
            uint256 aSum = _apSum(from, month6End, GENESIS_BLOCK, month6End, 8e17, 3e17, rate);
            uint256 bSum = _apSum(month6End + 1, to, month6End, month10End, 5e17, 5e17, rate);
            contribution = aSum + bSum;
        }

        pendingAccrual += contribution;
        lastAccrualBlock = to;
        emit Accrued(from, to, contribution);
    }

    /**
     * @notice Computes the AP-closed-form sum `Σ_{b=from}^{to} bodensee_share(b) × rate` for a single bootstrap leg per H-D11.
     * @dev `bodensee_share(b) = startShare − dropShare × (b − anchorStart) / (anchorEnd − anchorStart)` — linear in `b`, so the arithmetic-progression formula `n × (first + last) / 2 × rate / 1e18` applies exactly. Both `from` and `to` are inclusive; `n = to − from + 1`. `startShare` and `dropShare` are FixedPoint 1e18-base (e.g. `8e17` = 80%, `3e17` = 30%). Returns total contribution in AuMM scaled18. Overflow analysis: `(first + last) ≤ 1.6e18`, `n ≤ 2.2e6` (max bootstrap window), `rate ≤ ~1e18` (Era 0 max) — product ≤ 3.5e42 fits comfortably in uint256.
     * @param from First block in the integration window (inclusive).
     * @param to Last block in the integration window (inclusive); must satisfy `to >= from` (caller guarantees).
     * @param anchorStart The leg's anchor block — `share(anchorStart) = startShare`.
     * @param anchorEnd The leg's terminal block — `share(anchorEnd) = startShare − dropShare`.
     * @param startShare The share value at `anchorStart`, in FixedPoint 1e18-base.
     * @param dropShare The total share decrease from `anchorStart` to `anchorEnd`, in FixedPoint 1e18-base.
     * @param rate The per-block AuMM emission rate (scaled18 AuMM per block) snapshotted at `block.number`.
     * @return The total AuMM (scaled18) contribution across `[from, to]`.
     */
    function _apSum(
        uint256 from,
        uint256 to,
        uint256 anchorStart,
        uint256 anchorEnd,
        uint256 startShare,
        uint256 dropShare,
        uint256 rate
    ) internal pure returns (uint256) {
        uint256 width = anchorEnd - anchorStart;
        uint256 first = startShare - (dropShare * (from - anchorStart)) / width;
        uint256 last = startShare - (dropShare * (to - anchorStart)) / width;
        uint256 n = to - from + 1;
        return ((first + last) * n * rate) / (2 * 1e18);
    }

    /* ---------- Distribution (H-D12) ---------- */

    /**
     * @notice Governance-gated outer half of H-D12 — mints `pendingAccrual` via `mintRouter.mintFor` (K-D7), then invokes `_vault.unlock(abi.encodeCall(this._distributeCallback, (amount)))` so the callback performs the one-sided `AddLiquidityKind.DONATION` into der Bodensee per H-D14.
     * @dev H-D11 mint-at-distribute lock — mint timing belongs in `distribute()`, never in `accrue()`. H-D14 `onlyGovernance` gate — mint authority is the scarce resource; permissionless `distribute()` would let any caller force-flush at a self-chosen price window. K-D7 wiring — channel mints via `mintRouter.mintFor(address(this), amount)`, reverting `MintRouterNotSet` until the one-shot `setMintRouter` binds the `AuMMMinterRouter`; the router holds AuMM's minter slot via `aumm.setMinter(router)` at K7, superseding the H-D7 `IAuMM.setMinter(address(this))` posture. 3-transient-slot reentrancy + payload pattern mirrors G-D11 with `_PENDING_PAY_TOKEN_SLOT` omitted (AuMM is immutable pay token). Structural template is `src/gauge/SwapAndDepositToBodensee.sol` L328—L355 (`swapAndDeposit`) with substitutions — no `payToken` slot write, `mintRouter.mintFor(address(this), amount)` (guarded by `MintRouterNotSet`) precedes the reentrancy check, `IERC20(address(AuMM)).balanceOf(address(this))` for the residual read (IAuMM lacks the `using SafeERC20 for IERC20` binding so the cast is required), residual check uses the already-declared `HelperBalanceNonZero(residual)` error.
     */
    function distribute() external override onlyGovernance {
        uint256 amount = pendingAccrual;
        if (amount == 0) revert NoPendingAccrual();
        pendingAccrual = 0;
        totalDistributed += amount;
        if (address(mintRouter) == address(0)) revert MintRouterNotSet();
        mintRouter.mintFor(address(this), amount);
        if (_EXECUTING_SLOT.asBoolean().tload()) revert ReentrancyGuard();
        _EXECUTING_SLOT.asBoolean().tstore(true);
        _PENDING_AMOUNT_SLOT.asUint256().tstore(amount);
        _ORIGINAL_CALLER_SLOT.asAddress().tstore(msg.sender);
        _vault.unlock(abi.encodeCall(this._distributeCallback, (amount)));
        _EXECUTING_SLOT.asBoolean().tstore(false);
        _PENDING_AMOUNT_SLOT.asUint256().tstore(0);
        _ORIGINAL_CALLER_SLOT.asAddress().tstore(address(0));
        uint256 residual = IERC20(address(AuMM)).balanceOf(address(this));
        if (residual != 0) revert HelperBalanceNonZero(residual);
    }

    /* ---------- Vault callback (H-D12) ---------- */

    /**
     * @notice G-D12-style `_vault.unlock` callback: settle AuMM, DONATION add-liquidity, reserve delta check, `Distributed` emit per H-D12 steps 6—9.
     * @dev `external` — callable from `_vault.unlock` via `abi.encodeCall`; `OnlyVault` gate restricts `msg.sender` to `_vault`. `CallbackPayloadMismatch` sentinel verifies `amount` against `_PENDING_AMOUNT_SLOT.asUint256().tload()`. Pre/post reserve snapshot via `_currentReserve(_aummIndex)`. AuMM transferred to Vault via `IERC20(address(AuMM)).safeTransfer` (IAuMM lacks the using-for binding so explicit cast required). `_vault.settle` discards returned credit. `addLiquidity` with `AddLiquidityKind.DONATION` + `maxAmountsIn[_aummIndex] = amount` + `minBptAmountOut = 0` + `userData = ""`. `BptMintedOnDonation` rejects nonzero `bptOut`. `ReserveDeltaMismatch` rejects post-DONATION reserve drift. Emits `Distributed(_ORIGINAL_CALLER_SLOT.asAddress().tload(), amount)` as the final step per H-D12 step 9. Mirrors `src/gauge/SwapAndDepositToBodensee.sol` L390—L429 `_swapAndDepositCallback` with substitutions (`BODENSEE_POOL` replaces `_bodensee`; `_aummIndex` replaces dynamic idx; AuMM via IERC20 cast replaces dynamic payToken; `CallbackPayloadMismatch` carries `(expected, actual)` args; `IBodenseeBootstrapChannel.Distributed` event signature `(address indexed governance, uint256 amount)`).
     * @param amount The AuMM amount (scaled18) snapshotted in `_PENDING_AMOUNT_SLOT` before unlock — must match the transient slot or `CallbackPayloadMismatch` reverts.
     */
    function _distributeCallback(uint256 amount) external {
        if (msg.sender != address(_vault)) revert OnlyVault(msg.sender);
        uint256 expectedAmount = _PENDING_AMOUNT_SLOT.asUint256().tload();
        if (amount != expectedAmount) revert CallbackPayloadMismatch(expectedAmount, amount);
        uint256 preReserve = _currentReserve(_aummIndex);
        IERC20(address(AuMM)).safeTransfer(address(_vault), amount);
        _vault.settle(IERC20(address(AuMM)), amount);
        uint256[] memory maxAmountsIn = new uint256[](3);
        maxAmountsIn[_aummIndex] = amount;
        (, uint256 bptOut, ) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: BODENSEE_POOL,
                to: address(this),
                maxAmountsIn: maxAmountsIn,
                minBptAmountOut: 0,
                kind: AddLiquidityKind.DONATION,
                userData: ""
            })
        );
        if (bptOut != 0) revert BptMintedOnDonation(bptOut);
        uint256 postReserve = _currentReserve(_aummIndex);
        if (postReserve != preReserve + amount) revert ReserveDeltaMismatch(preReserve + amount, postReserve);
        emit Distributed(_ORIGINAL_CALLER_SLOT.asAddress().tload(), amount);
    }

    /* ---------- Internal helpers ---------- */

    /**
     * @notice Reads the raw on-chain reserve balance for token index `idx` in der Bodensee.
     * @dev G-D18 — reads `balancesRaw[idx]` from `_vault.getPoolTokenInfo(BODENSEE_POOL)`. Mirrors `src/gauge/SwapAndDepositToBodensee.sol` L447—L450 `_currentReserve`.
     * @param idx Token index within der Bodensee's roster — `_aummIndex` for AuMM in the DONATION callback.
     * @return Raw reserve balance (token-native decimals) for the indexed token.
     */
    function _currentReserve(uint8 idx) internal view returns (uint256) {
        (, , uint256[] memory balancesRaw, ) = _vault.getPoolTokenInfo(BODENSEE_POOL);
        return balancesRaw[idx];
    }
}
