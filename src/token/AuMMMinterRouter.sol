// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IAuMM} from "./IAuMM.sol";
import {IAuMMMinterRouter} from "./IAuMMMinterRouter.sol";

/// @title  AuMMMinterRouter
/// @notice Dumb allowlist mint forwarder that holds AuMM's C-D11 one-shot minter
///         slot and forwards `mintFor` calls from exactly two allowlisted consumers
///         — the der Bodensee bootstrap channel and the emission distributor.
/// @dev    The 21M cap and the minter gate stay inside AuMM (Stage C). No setters,
///         no governance surface, no amount policy. `MintRouted` emits an indexed
///         `caller` before the forward because AuMM's `Transfer` shows
///         `minter == router` for both consumers — the event is the only on-chain
///         attribution distinguishing bootstrap-flush mints from claim mints.
contract AuMMMinterRouter is IAuMMMinterRouter {
    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice The AuMM token whose one-shot minter slot this router holds at K7.
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    IAuMM public immutable AUMM;

    /// @notice The der Bodensee bootstrap channel — one of two allowlisted
    ///         `mintFor` callers per K-D7.
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    address public immutable BOOTSTRAP_CHANNEL;

    /// @notice The emission distributor — one of two allowlisted `mintFor`
    ///         callers per K-D7.
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    address public immutable EMISSION_DISTRIBUTOR;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted immediately before each successful `AUMM.mint` forward.
    /// @dev    Indexed `caller` attributes the mint to the bootstrap channel or
    ///         the emission distributor — AuMM's `Transfer` alone cannot.
    /// @param  caller    The allowlisted consumer that invoked `mintFor`.
    /// @param  recipient Recipient of the newly minted tokens.
    /// @param  amount    Amount in AuMM wei forwarded to `AUMM.mint`.
    event MintRouted(address indexed caller, address indexed recipient, uint256 amount);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when a zero address is supplied where it is forbidden.
    /// @dev    Used by the constructor for all three immutable arguments.
    error ZeroAddress();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @notice Binds the three immutable allowlist slots. All arguments are
    ///         zero-checked; there are no setters and no post-construction wiring.
    /// @param  aumm_                 The AuMM token this router forwards to.
    /// @param  bootstrapChannel_     The der Bodensee bootstrap channel address.
    /// @param  emissionDistributor_  The emission distributor address.
    constructor(IAuMM aumm_, address bootstrapChannel_, address emissionDistributor_) {
        if (address(aumm_) == address(0)) revert ZeroAddress();
        if (bootstrapChannel_ == address(0)) revert ZeroAddress();
        if (emissionDistributor_ == address(0)) revert ZeroAddress();

        AUMM = aumm_;
        BOOTSTRAP_CHANNEL = bootstrapChannel_;
        EMISSION_DISTRIBUTOR = emissionDistributor_;
    }

    // -------------------------------------------------------------------------
    // State-changing
    // -------------------------------------------------------------------------

    /// @notice Mint `amount` AuMM to `recipient`. Callable only by the two
    ///         allowlisted consumers; any other caller reverts `NotAllowlisted`.
    /// @dev    Emits `MintRouted` then forwards `AUMM.mint(recipient, amount)`
    ///         with no amount policy of its own.
    /// @param  recipient Recipient of the newly minted tokens.
    /// @param  amount    Amount in AuMM wei.
    function mintFor(address recipient, uint256 amount) external override {
        if (msg.sender != BOOTSTRAP_CHANNEL && msg.sender != EMISSION_DISTRIBUTOR) revert NotAllowlisted(msg.sender);
        emit MintRouted(msg.sender, recipient, amount);
        AUMM.mint(recipient, amount);
    }
}
