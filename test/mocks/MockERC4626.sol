// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title  MockERC4626
/// @notice Minimal 1:1 ERC-4626 share token used as the svZCHF fixture in
///         `test/unit/AureumFeeRoutingHook.t.sol`. Shares are minted 1:1
///         with underlying assets so tests can reason about fee flows
///         without wrestling with rounding.
/// @dev    Only the subset of IERC4626 actually touched by
///         `AureumFeeRoutingHook.sol` is implemented: `asset()` (called at
///         hook construction) and `deposit(assets, receiver)` (called in
///         the phase-1 ZCHF to svZCHF conversion branch of
///         `_swapFeeAndDeposit`). `redeem` is included so tests can
///         unwind share balances. Not for production use.
contract MockERC4626 is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 private immutable _ASSET;

    constructor(IERC20 asset_, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _ASSET = asset_;
    }

    function asset() external view returns (address) {
        return address(_ASSET);
    }

    /// @notice Pulls `assets` of underlying from `msg.sender` and mints
    ///         `assets` shares to `receiver` (1:1 ratio).
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        _ASSET.safeTransferFrom(msg.sender, address(this), assets);
        shares = assets;
        _mint(receiver, shares);
    }

    /// @notice Burns `shares` from `owner` and transfers `shares` of
    ///         underlying to `receiver` (1:1 ratio). When `msg.sender` is
    ///         not `owner`, the allowance is spent per ERC-4626 semantics;
    ///         tests typically call `redeem` directly from the owner.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        assets = shares;
        _ASSET.safeTransfer(receiver, assets);
    }
}
