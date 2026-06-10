// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title  IAuMMMinterRouter
/// @notice Interface for a dumb allowlist mint forwarder that holds AuMM's
///         one-shot minter slot (C-D11) and forwards mint calls from exactly
///         two allowlisted consumers — the der Bodensee bootstrap channel and
///         the emission distributor — which bind this interface as their
///         `mintRouter` storage type (K-D7).
/// @dev    The router holds no cap math — the 21M cap and the minter gate stay
///         inside AuMM (Stage C). It has no governance surface and no setters.
///         The concrete `AuMMMinterRouter` lands at K5.2.
interface IAuMMMinterRouter {
    // -------------------------------------------------------------------------
    // State-changing
    // -------------------------------------------------------------------------

    /// @notice Mint `amount` AuMM to `recipient`. Callable only by the two
    ///         allowlisted consumers; any other caller reverts `NotAllowlisted`.
    /// @dev    On success, forwards `AUMM.mint(recipient, amount)` and applies
    ///         no amount policy of its own.
    /// @param  recipient Recipient of the newly minted tokens.
    /// @param  amount    Amount in AuMM wei.
    function mintFor(address recipient, uint256 amount) external;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when `mintFor` is invoked by an address that is not one
    ///         of the two allowlisted consumers.
    /// @dev    The membership check is an equality test against the two
    ///         constructor immutables `BOOTSTRAP_CHANNEL` and
    ///         `EMISSION_DISTRIBUTOR`.
    /// @param  caller The address that failed the allowlist equality check.
    error NotAllowlisted(address caller);
}
