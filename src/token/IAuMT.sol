// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IAuMT
 * @notice Stage G forward-dep stub extended at Stage H — AuMT (Aureum Market Tessera) interface surface
 *         for Stage G consumers (governance weight) and Stage I consumer-side documentary obligations
 *         (mint, burn, distributor, pool) per H-D35.
 * @dev IERC20 base + G-D9 governance-weight surface (consumed at `VaultClassRegistry.vetoProposal`) preserved
 *      verbatim from Stage G per G-DP4 forward-dependency wiring rule. Stage H extends the interface with the
 *      four Stage I receipt-token consumer-side signatures required by `EmissionDistributor` recorder semantics
 *      (H-D35 + H4—H5). Concrete implementation deferred to Stage I — events, errors, setter signatures, and
 *      qualification-period / withdrawal-reset semantics lock at Stage I; H6 ships minimum compile-stable
 *      surface plus G-D9 preservation, no Stage I behavior.
 */
interface IAuMT is IERC20 {
    /**
     * @notice AuMT-weighted governance vote share for `holder`.
     * @dev Used by `VaultClassRegistry.vetoProposal` per G-D9 veto-threshold semantic.
     *      Pre-Stage-I, the placeholder slot returns zero (vetoes structurally impossible per G-DP4).
     *      Encoding precision and qualification-period logic lock at Stage I;
     *      this stub commits only to function shape for Stage G call sites.
     * @param holder The address whose governance weight is queried.
     * @return weight AuMT-weighted vote-share, absolute (denominator is `totalSupply()` from IERC20).
     */
    function governanceWeight(address holder) external view returns (uint256);

    /**
     * @notice Mint `amount` AuMT receipt tokens to `to`.
     * @dev Called by the per-pool LP deposit hook at Stage I — the concrete AuMT implementation internally
     *      calls `EmissionDistributor.recordDeposit` after minting per H-D35 recorder semantics.
     *      Stage I access-control gate: callable by the bound liquidity hook only (`NotLiquidityHook` revert).
     *      Pre-Stage-I mock stubs expose this signature for compile-time compatibility; stub bodies are
     *      no-ops (return without minting).
     * @param to Recipient of the newly minted AuMT tokens.
     * @param amount Token amount (18-decimal scaled) to mint.
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burn `amount` AuMT receipt tokens from `from`.
     * @dev Called by the per-pool LP withdrawal hook at Stage I — the concrete AuMT implementation
     *      internally calls `EmissionDistributor.recordWithdrawal` after burning per H-D35 recorder
     *      semantics. Stage I access-control gate: callable by the bound liquidity hook only
     *      (`NotLiquidityHook` revert). Pre-Stage-I mock stubs expose this signature for compile-time
     *      compatibility; stub bodies are no-ops (return without burning).
     * @param from Address whose AuMT tokens are burned.
     * @param amount Token amount (18-decimal scaled) to burn.
     */
    function burn(address from, uint256 amount) external;

    /**
     * @notice Address of the `EmissionDistributor` bound to this AuMT contract.
     * @dev Set once at Stage I deployment — the distributor is the CONSUMER side of the recorder
     *      relationship (AuMT calls into the distributor, never the inverse); the `auMTContract`
     *      recorder slot in `EmissionDistributor` remains bare `address` per H-D16, not a typed
     *      `IAuMT` binding. Pre-Stage-I mock stubs return `address(0)`.
     * @return The bound `EmissionDistributor` address.
     */
    function distributor() external view returns (address);

    /**
     * @notice Address of the Miliarium pool this AuMT contract is bound to.
     * @dev AuMT is per-pool per CLAUDE.md §1 — one AuMT deployment per Miliarium pool at Stage I.
     *      Used by the distributor as a reverse-lookup from receipt token to pool to route recorder
     *      calls (`recordDeposit` / `recordWithdrawal`) to the correct pool slot. Pre-Stage-I mock
     *      stubs return `address(0)`.
     * @return The Miliarium pool address this AuMT token represents.
     */
    function pool() external view returns (address);
}
