// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title  IAuMM
/// @notice Interface for the AuMM ERC-20. Consumed by Stage H's emission
///         distributor and by any off-chain tool that needs a stable shape
///         to compile against.
/// @dev    Extends IERC20 — the ERC-20 surface is inherited. This interface
///         declares only the AuMM-specific additions: immutable/constant
///         getters, the emission schedule, the minter state machine, and
///         the MinterSet event.
interface IAuMM is IERC20 {
    // -------------------------------------------------------------------------
    // Immutable / constant getters
    // -------------------------------------------------------------------------

    /// @notice The block number at which the AuMM emission schedule begins.
    ///         Era 0 starts at this block.
    /// @return The genesis block, set immutably in the constructor.
    // Aureum-wide naming: interface getter mirrors UPPER_SNAKE_CASE impl constant/immutable.
    // slither-disable-next-line naming-convention
    function GENESIS_BLOCK() external view returns (uint256);

    /// @notice The hard supply cap: the total AuMM that can ever exist.
    /// @return 21_000_000 * 1e18.
    // Aureum-wide naming: interface getter mirrors UPPER_SNAKE_CASE impl constant/immutable.
    // slither-disable-next-line naming-convention
    function MAX_SUPPLY() external view returns (uint256);

    /// @notice The per-block emission rate during Era 0, before any halving.
    /// @return 1e18 (one AuMM per block in Era 0).
    // Aureum-wide naming: interface getter mirrors UPPER_SNAKE_CASE impl constant/immutable.
    // slither-disable-next-line naming-convention
    function GENESIS_RATE() external view returns (uint256);

    // -------------------------------------------------------------------------
    // Emission schedule
    // -------------------------------------------------------------------------

    /// @notice The per-block emission rate at a given block number, under the
    ///         immutable Bitcoin-style geometric halving schedule.
    /// @dev    Returns 0 for blocks before GENESIS_BLOCK. Otherwise returns
    ///         GENESIS_RATE >> eraIndex, where eraIndex is
    ///         (blockNumber - GENESIS_BLOCK) / BLOCKS_PER_ERA. Once the era
    ///         index exceeds log2(GENESIS_RATE), integer right-shift produces
    ///         zero naturally. Pure function of blockNumber and the immutable
    ///         genesis block; no state dependency.
    /// @param  blockNumber The block at which to evaluate the schedule.
    /// @return The per-block emission rate at blockNumber, in AuMM wei.
    function blockEmissionRate(uint256 blockNumber) external view returns (uint256);

    // -------------------------------------------------------------------------
    // Minter state
    // -------------------------------------------------------------------------

    /// @notice The address authorised to call mint(). Zero until setMinter()
    ///         has been called exactly once; then set permanently.
    /// @dev    Matches the auto-generated getter for `address public minter`
    ///         on the concrete AuMM contract.
    /// @return The current minter address, or address(0) if setMinter() has
    ///         not yet been called.
    function minter() external view returns (address);

    // -------------------------------------------------------------------------
    // State-changing
    // -------------------------------------------------------------------------

    /// @notice Mint `amount` AuMM to `to`. Gated by msg.sender == minter and
    ///         by a hard totalSupply() + amount <= MAX_SUPPLY backstop.
    /// @param  to     Recipient of the newly minted tokens.
    /// @param  amount Amount in AuMM wei.
    function mint(address to, uint256 amount) external;

    /// @notice Hand off mint authority to the emission distributor. Callable
    ///         exactly once, only by the minter admin set in the constructor.
    ///         Self-locks the admin slot on success: the admin address is
    ///         zeroed and this function can never be called again.
    /// @param  newMinter The address that will hold mint authority from now on.
    function setMinter(address newMinter) external;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted exactly once, when the minter admin hands off authority
    ///         to the emission distributor.
    /// @param  minter The address now authorised to call mint(). After this
    ///         event the minter-admin slot is zeroed and setMinter() reverts.
    event MinterSet(address indexed minter);
}
