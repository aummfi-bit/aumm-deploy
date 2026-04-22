// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title  MockERC20
/// @notice Minimal test-only ERC-20 with public `mint` and `burn` helpers
///         and a constructor-settable `decimals()`.
/// @dev    Used as ZCHF, AuMM, and arbitrary fee-token fixtures in
///         `test/unit/AureumFeeRoutingHook.t.sol` (and as the underlying
///         for `test/mocks/MockERC4626.sol`). Not for production use.
contract MockERC20 is ERC20 {
    uint8 private immutable _DECIMALS;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _DECIMALS = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _DECIMALS;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
