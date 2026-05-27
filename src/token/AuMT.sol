// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAuMT} from "./IAuMT.sol";

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

    /// @notice Reverted by the constructor when `pool_`, `distributor_`, or `liquidityHook_` is `address(0)`.
    error ZeroAddress();

    /// @notice Reverted by `transfer` / `transferFrom` / `approve` per I-D1 — AuMT is soulbound.
    error NotTransferable();

    /* ---------- Immutables (I-D11) ---------- */

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

    /// @notice Protocol genesis block — anchors `governanceWeight` era-transition at
    ///         `AureumTime.firstHalvingBlock(GENESIS_BLOCK)` per I-D7 / F-9 (4th root → 3rd root crossing).
    ///         H13 avoidance: passed as constructor arg rather than read from `EmissionDistributor.GENESIS_BLOCK()`
    ///         at construction. Matches H-D7 Option C precedent at `EmissionDistributor.GENESIS_BLOCK` (L46)
    ///         and `BodenseeBootstrapChannel.GENESIS_BLOCK` (L36). Not declared in `IAuMT`.
    uint256 public immutable GENESIS_BLOCK;

    /* ---------- Constructor (I-D11) ---------- */

    /// @notice Deploy a per-pool AuMT instance with the given immutable bindings and ERC20 identity.
    /// @param pool_          Miliarium pool address; `ZeroAddress` revert on zero.
    /// @param distributor_   `EmissionDistributor` address (per-pool recorder per I-D9); `ZeroAddress` revert on zero.
    /// @param liquidityHook_ Bound `AureumFeeRoutingHook` address per I-D4 + I-D5; `ZeroAddress` revert on zero.
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
        uint256 genesisBlock_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        if (pool_          == address(0)) revert ZeroAddress();
        if (distributor_   == address(0)) revert ZeroAddress();
        if (liquidityHook_ == address(0)) revert ZeroAddress();
        pool          = pool_;
        distributor   = distributor_;
        liquidityHook = liquidityHook_;
        GENESIS_BLOCK = genesisBlock_;
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

    /* ---------- IAuMT placeholder bodies (I3.3 / I3.5) ---------- */

    /// @inheritdoc IAuMT
    /// @dev I3.1 placeholder — `onlyLiquidityHook` gate + ERC20 `_mint` + I-D6 qualification clock +
    ///      H-D35 `recordDeposit` dispatch land at I3.3 / I3.4 / I3.6.
    function mint(address to, uint256 amount) external override {
    }

    /// @inheritdoc IAuMT
    /// @dev I3.1 placeholder — `onlyLiquidityHook` gate + ERC20 `_burn` + I-D6 qualification reset +
    ///      H-D35 `recordWithdrawal` dispatch land at I3.3 / I3.4 / I3.6.
    function burn(address from, uint256 amount) external override {
    }

    /// @inheritdoc IAuMT
    /// @dev I3.1 placeholder — returns zero (matches H6.0c `IAuMT` stub semantic at `IAuMT.sol` L25).
    ///      Full I-D7 root-curve formula (4th/3rd root + qualification cliff + on-ramp cap +
    ///      gauge-revoked guard) lands at I3.5.
    function governanceWeight(address holder) external view override returns (uint256) {
        return 0;
    }
}
