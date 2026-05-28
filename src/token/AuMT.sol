// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGaugeRegistry} from "../ccb/IGaugeRegistry.sol";
import {IEmissionDistributor} from "../emission/IEmissionDistributor.sol";
import {IAuMT} from "./IAuMT.sol";
import {AureumTime} from "../lib/AureumTime.sol";
import {FixedPoint} from "../../lib/balancer-v3-monorepo/pkg/solidity-utils/contracts/math/FixedPoint.sol";

/**
 * @title AuMT
 * @notice Per-pool LP receipt token (Aureum Market Tessera) — one deployment per Miliarium pool at Stage I
 *         (3 pilot instances; 28 at full deployment per Stages M/N per OQ-I10). Soulbound per I-D1:
 *         `transfer` / `transferFrom` / `approve` revert `NotTransferable` (lands at I3.2). Mint and burn
 *         dispatched exclusively by the bound `AureumFeeRoutingHook` per I-D4; `onlyLiquidityHook` modifier
 *         and `NotLiquidityHook` revert land at I3.3. Governance weight per I-D7 root-curve:
 *         `(balance × qualified_time_capped)^(1/4)` in Era 0, `(balance × qualified_time_capped)^(1/3)`
 *         from Era 1 onward per F-9 era-boundary transition at `AureumTime.firstHalvingBlock(GENESIS_BLOCK)`;
 *         gauge-revoked holders → zero weight per OQ-7; full implementation lands at I3.5.
 * @dev I-D11 — 4 `public immutable` slots: `pool` (bound Miliarium pool address; satisfies `IAuMT.pool()`
 *      override), `distributor` (bound `EmissionDistributor` address; satisfies `IAuMT.distributor()` override;
 *      I-D9 per-pool mapping routes recorder calls from this AuMT instance via `auMTContractByPool`),
 *      `liquidityHook` (bound `AureumFeeRoutingHook` address per I-D4 + I-D5; concrete-only, not in `IAuMT`),
 *      `GENESIS_BLOCK` (protocol genesis block per H-D7 Option C precedent at `EmissionDistributor.GENESIS_BLOCK`
 *      L46 + `BodenseeBootstrapChannel.GENESIS_BLOCK` L36; concrete-only, not in `IAuMT`).
 *      6-arg constructor: `pool_` / `distributor_` / `liquidityHook_` / `genesisBlock_` / `name_` / `symbol_`.
 *      `name_` / `symbol_` per-creator per Balancer V3 BPT-naming convention; `ixXYZ` for 28 Miliarium pools
 *      per OQ-I10 / `miliarium_profiles/` in `aummfi-bit/aumm-site`. H13 avoidance: `GENESIS_BLOCK` is passed
 *      as a constructor immutable rather than read from `EmissionDistributor.GENESIS_BLOCK()` at construction —
 *      a constructor external call to a constructor arg is the H13 failure pattern (H10.2-revised lesson);
 *      fork tests with keccak-placeholder env stubs would break `setUp()`. Stage I5 invariant test asserts
 *      `AuMT.GENESIS_BLOCK() == IEmissionDistributor(distributor).GENESIS_BLOCK()` for deploy-side
 *      consistency. I-D1 soulbound state machine + I-D6 qualification clock + I-D7 root-curve + I-D4
 *      `onlyLiquidityHook` gate land across I3.2—I3.6; `IAuMT` NatSpec dual correction (L35 mint +
 *      L47-L48 burn stale "callable by the bound distributor only") at I3.7.
 */
contract AuMT is IAuMT, ERC20 {

    /* ---------- Errors ---------- */

    /// @notice Reverted by the constructor when `pool_`, `distributor_`, `liquidityHook_`, or `gaugeRegistry_` is `address(0)`.
    error ZeroAddress();

    /// @notice Reverted by `transfer` / `transferFrom` / `approve` per I-D1 — AuMT is soulbound.
    error NotTransferable();

    /// @notice Reverted by `mint` / `burn` when `msg.sender` is not the bound `liquidityHook` per I-D4.
    error NotLiquidityHook(address caller);

    /* ---------- Constants (I-D7) ---------- */

    /// @notice FixedPoint exponent for the Era 0 fourth-root branch of I-D7 `governanceWeight`:
    ///         `pow(x, 0.25)` matches §ix's "fourth root" dampening per F-9 pre-halving regime.
    uint256 internal constant FOURTH_ROOT_EXP = 0.25e18;

    /// @notice FixedPoint exponent for the Era 1+ cube-root branch of I-D7 `governanceWeight`:
    ///         `pow(x, 1/3)` matches §ix's "cube root" dampening per F-9 post-first-halving regime.
    ///         Value is `FixedPoint.ONE / 3` truncated to 18 decimals (irrational 1/3 → finite FP18).
    uint256 internal constant CUBE_ROOT_EXP = 333_333_333_333_333_333;

    /* ---------- Immutables (I-D11 / I-D12) ---------- */

    /// @notice Bound Miliarium pool address — I-D2 per-pool topology; satisfies `IAuMT.pool()` interface.
    address public immutable override pool;

    /// @notice Bound `EmissionDistributor` address — H-D35 recorder semantics (AuMT calls `recordDeposit` /
    ///         `recordWithdrawal` into the distributor; direction is AuMT → distributor, never the inverse);
    ///         satisfies `IAuMT.distributor()` interface. I-D9 per-pool `auMTContractByPool` mapping on the
    ///         distributor side routes incoming recorder calls to the correct pool accumulator slot.
    address public immutable override distributor;

    /// @notice Bound `AureumFeeRoutingHook` address — I-D4 `onlyLiquidityHook` mint/burn access gate; I-D5
    ///         hook extension wires `onAfterAddLiquidity` / `onAfterRemoveLiquidity` to dispatch `mint` /
    ///         `burn`. Not declared in `IAuMT` — concrete-contract-only immutable.
    address public immutable liquidityHook;

    /// @notice Gauge registry binding — I-D12 5th immutable extending I-D11. Consumed by
    ///         `governanceWeight` ZERO branch per I-D7 (`!gaugeRegistry.isGaugeApproved(pool())`).
    ///         Direct binding (Option A) mirrors `EmissionDistributor.sol:L31` precedent per I-D12;
    ///         alternatives B (distributor-chained) and C (interface widening) explicitly NOT chosen.
    ///         Not declared in `IAuMT` — concrete-contract-only immutable.
    IGaugeRegistry public immutable gaugeRegistry;

    /// @notice Protocol genesis block — anchors `governanceWeight` era-transition at
    ///         `AureumTime.firstHalvingBlock(GENESIS_BLOCK)` per I-D7 / F-9 (4th root → 3rd root crossing).
    ///         H13 avoidance: passed as constructor arg rather than read from `EmissionDistributor.GENESIS_BLOCK()`
    ///         at construction. Matches H-D7 Option C precedent at `EmissionDistributor.GENESIS_BLOCK` (L46)
    ///         and `BodenseeBootstrapChannel.GENESIS_BLOCK` (L36). Not declared in `IAuMT`.
    uint256 public immutable GENESIS_BLOCK;

    /* ---------- Storage (I-D6) ---------- */

    /// @notice Block at which `holder`'s current qualification clock started; `0` means never deposited or
    ///         reset by withdrawal per I-D6.
    mapping(address holder => uint256) public qualificationBlock;

    /// @notice Block of `holder`'s most recent mint, informational.
    mapping(address holder => uint256) public lastDepositBlock;

    /* ---------- Constructor (I-D11 / I-D12) ---------- */

    /// @notice Deploy a per-pool AuMT instance with the given immutable bindings and ERC20 identity.
    /// @param pool_          Miliarium pool address; `ZeroAddress` revert on zero.
    /// @param distributor_   `EmissionDistributor` address (per-pool recorder per I-D9); `ZeroAddress` revert on zero.
    /// @param liquidityHook_ Bound `AureumFeeRoutingHook` address per I-D4 + I-D5; `ZeroAddress` revert on zero.
    /// @param gaugeRegistry_ Stage G `GaugeRegistry` address (per I-D12 5th immutable); `ZeroAddress` revert on zero.
    /// @param genesisBlock_  Stage H genesis block (mirrors `EmissionDistributor.GENESIS_BLOCK` per H13 avoidance
    ///                       pattern); `uint256`, no zero-check (matches `EmissionDistributor` L114 +
    ///                       `BodenseeBootstrapChannel` constructor precedent).
    /// @param name_          ERC20 name forwarded to OpenZeppelin `ERC20` constructor; per-creator
    ///                       (`ixXYZ` for 28 Miliarium pools per OQ-I10).
    /// @param symbol_        ERC20 symbol forwarded to OpenZeppelin `ERC20` constructor; per-creator.
    constructor(
        address pool_,
        address distributor_,
        address liquidityHook_,
        address gaugeRegistry_,
        uint256 genesisBlock_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        if (pool_          == address(0)) revert ZeroAddress();
        if (distributor_   == address(0)) revert ZeroAddress();
        if (liquidityHook_ == address(0)) revert ZeroAddress();
        if (gaugeRegistry_ == address(0)) revert ZeroAddress();
        pool          = pool_;
        distributor   = distributor_;
        liquidityHook = liquidityHook_;
        gaugeRegistry = IGaugeRegistry(gaugeRegistry_);
        GENESIS_BLOCK = genesisBlock_;
    }

    /* ---------- Modifiers (I-D4) ---------- */

    /// @notice Restricts execution to the bound `liquidityHook` (the per-pool `AureumFeeRoutingHook` extension per I-D5).
    /// @dev Reverts `NotLiquidityHook(msg.sender)` if `msg.sender != liquidityHook`. Applied to `mint` and `burn` per I-D4 access semantics.
    modifier onlyLiquidityHook() {
        if (msg.sender != liquidityHook) revert NotLiquidityHook(msg.sender);
        _;
    }

    /* ---------- Soulbound overrides (I-D1) ---------- */

    /// @inheritdoc IERC20
    /// @dev I-D1 — AuMT is soulbound; reverts `NotTransferable` unconditionally.
    function transfer(address, uint256) public pure override(ERC20, IERC20) returns (bool) {
        revert NotTransferable();
    }

    /// @inheritdoc IERC20
    /// @dev I-D1 — AuMT is soulbound; reverts `NotTransferable` unconditionally.
    function transferFrom(address, address, uint256) public pure override(ERC20, IERC20) returns (bool) {
        revert NotTransferable();
    }

    /// @inheritdoc IERC20
    /// @dev I-D1 — AuMT is soulbound; reverts `NotTransferable` unconditionally.
    function approve(address, uint256) public pure override(ERC20, IERC20) returns (bool) {
        revert NotTransferable();
    }

    /* ---------- IAuMT implementations (I3.3 / I3.5 / I3.6) ---------- */

    /// @inheritdoc IAuMT
    /// @dev I-D4 `onlyLiquidityHook` gate. I-D6 qualification clock — first deposit sets
    ///      `qualificationBlock[to]`; subsequent top-ups leave it unchanged; `lastDepositBlock[to]` always
    ///      updated. H-D35 `recordDeposit` dispatched into the bound distributor post-`_mint`.
    function mint(address to, uint256 amount) external override onlyLiquidityHook {
        if (qualificationBlock[to] == 0) { qualificationBlock[to] = block.number; }
        lastDepositBlock[to] = block.number;
        _mint(to, amount);
        IEmissionDistributor(distributor).recordDeposit(pool, to, amount);
    }

    /// @inheritdoc IAuMT
    /// @dev I-D4 `onlyLiquidityHook` gate. I-D6 — any-amount withdrawal sets `qualificationBlock[from] = 0`
    ///      per §ix verbatim (withdrawal-reset rule). H-D35 `recordWithdrawal` dispatched into the bound distributor post-`_burn`.
    function burn(address from, uint256 amount) external override onlyLiquidityHook {
        qualificationBlock[from] = 0;
        _burn(from, amount);
        IEmissionDistributor(distributor).recordWithdrawal(pool, from, amount);
    }

    /// @inheritdoc IAuMT
    /// @dev I-D7 root-curve voting weight. Returns ZERO unless ALL three conditions hold:
    ///      (1) `qualificationBlock[holder] != 0` — holder has deposited and not been reset by withdrawal;
    ///      (2) `block.number - qualificationBlock[holder] >= QUALIFICATION_PERIOD_BLOCKS` — 14-day cliff crossed per §ix verbatim;
    ///      (3) `gaugeRegistry.isGaugeApproved(pool)` — bound pool's gauge is currently approved per FINDINGS OQ-7.
    ///      Active formula: `(balanceOf(holder) × time_in_pool_capped)^exp` via `FixedPoint.powDown`,
    ///      where `time_in_pool_capped = min(block.number - qualificationBlock[holder], ON_RAMP_PERIOD_BLOCKS)`
    ///      (6-month on-ramp cap per §ix "day 180"); exponent is `FOURTH_ROOT_EXP` in Era 0
    ///      (`block.number < AureumTime.firstHalvingBlock(GENESIS_BLOCK)`) else `CUBE_ROOT_EXP` per F-9 / §ix.
    function governanceWeight(address holder) external view override returns (uint256) {
        // I-D7 ZERO branch 1 — never deposited or reset by withdrawal per I-D6.
        uint256 qualBlock = qualificationBlock[holder];
        if (qualBlock == 0) return 0;

        // I-D7 ZERO branch 2 — qualification cliff not yet crossed (14 days = 1 epoch per OQ-3 / I-D10).
        uint256 timeInPool = block.number - qualBlock;
        if (timeInPool < AureumTime.QUALIFICATION_PERIOD_BLOCKS) return 0;

        // I-D7 ZERO branch 3 — bound pool's gauge revoked or never approved per FINDINGS OQ-7.
        if (!gaugeRegistry.isGaugeApproved(pool)) return 0;

        // I-D7 active branch — cap time at 180 days; multiply by balance; take root.
        uint256 timeInPoolCapped = timeInPool > AureumTime.ON_RAMP_PERIOD_BLOCKS
            ? AureumTime.ON_RAMP_PERIOD_BLOCKS
            : timeInPool;
        uint256 weightInput = balanceOf(holder) * timeInPoolCapped;
        uint256 exponent = block.number < AureumTime.firstHalvingBlock(GENESIS_BLOCK)
            ? FOURTH_ROOT_EXP
            : CUBE_ROOT_EXP;
        return FixedPoint.powDown(weightInput, exponent);
    }
}
