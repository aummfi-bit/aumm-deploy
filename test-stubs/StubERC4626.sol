// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title  StubERC4626
/// @notice Fixed 1:1 NAV testnet ERC-4626 share stub over an ERC-20 underlying
///         (PB-D20 (iv) templates). Exposes the read + deposit/withdraw surface
///         consumed by the fee-routing hook and `ERC4626RateProvider`, plus a
///         permissionless seeding mint (PB-D20 (v)).
/// @dev    Deliberately not `is IERC4626` so the seeding `mint(address,uint256)`
///         does not collide with 4626 `mint(uint256,address)`. Shares inherit
///         OZ ERC20's 18 decimals per F-11 (PB-D20 (iii)). Lives in
///         `test-stubs/`, not `test/mocks/`.
contract StubERC4626 is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 private immutable _ASSET;

    constructor(IERC20 asset_, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _ASSET = asset_;
    }

    /// @notice Underlying asset address.
    function asset() external view returns (address) {
        return address(_ASSET);
    }

    /// @notice Total underlying held by this vault.
    function totalAssets() external view returns (uint256) {
        return _ASSET.balanceOf(address(this));
    }

    /// @notice Fixed 1:1 NAV — assets equal shares.
    function convertToAssets(uint256 shares) public pure returns (uint256) {
        return shares;
    }

    /// @notice Fixed 1:1 NAV — shares equal assets.
    function convertToShares(uint256 assets) public pure returns (uint256) {
        return assets;
    }

    /// @notice Preview deposit at 1:1.
    function previewDeposit(uint256 assets) public pure returns (uint256) {
        return assets;
    }

    /// @notice Preview withdraw at 1:1.
    function previewWithdraw(uint256 assets) public pure returns (uint256) {
        return assets;
    }

    /// @notice Preview redeem at 1:1 — `ERC4626RateProvider.getRate()` reads
    ///         `previewRedeem(1e18)` and therefore sees `1e18`.
    function previewRedeem(uint256 shares) public pure returns (uint256) {
        return shares;
    }

    /// @notice Pulls `assets` of underlying from `msg.sender` and mints
    ///         `assets` shares to `receiver` (1:1).
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        _ASSET.safeTransferFrom(msg.sender, address(this), assets);
        shares = assets;
        _mint(receiver, shares);
    }

    /// @notice Burns `assets` shares from `owner` and transfers `assets` of
    ///         underlying to `receiver` (1:1). Spends allowance when
    ///         `msg.sender` is not `owner`.
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, assets);
        }
        _burn(owner, assets);
        shares = assets;
        _ASSET.safeTransfer(receiver, assets);
    }

    /// @notice Permissionless uncapped seeding mint — `(address,uint256)` shape
    ///         only; not the ERC-4626 `mint(uint256,address)`.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
