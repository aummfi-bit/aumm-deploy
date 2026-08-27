// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title  MockRegisteredVault
/// @notice Test-only stub answering the single Vault selector `EmissionDistributor`
///         reads — `isPoolRegistered(address)` — for the PP-D44 (F.1) pool-validation
///         gate on `setAuMTContractForPool`.
/// @dev    Deliberately NOT `is IVault`: the distributor holds `address public immutable
///         vault` and casts it, so only the called selector must exist. This follows the
///         five existing file-local vault stubs, each of which implements only what its
///         subject calls. The name avoids `MockVault`, which four test files already
///         define locally and which would collide on import.
///
///         `isPoolRegistered` defaults TRUE for every pool so that the thirty-five
///         construction sites in the PP4.1c ripple need no fixture setup. Tests wanting
///         the negative case call `setPoolRegistered(pool, false)` first.
contract MockRegisteredVault {
    mapping(address => bool) private _unregistered;

    function setPoolRegistered(address pool, bool registered) external {
        _unregistered[pool] = !registered;
    }

    function isPoolRegistered(address pool) external view returns (bool) {
        return !_unregistered[pool];
    }
}
