// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title  StubERC20
/// @notice Testnet-only ERC-20 stub with constructor-set decimals and a
///         permissionless uncapped mint (PB-D20 (iv) templates + (v) mint policy).
/// @dev    Lives in `test-stubs/`, not `test/mocks/`. Production-shaped for
///         Sepolia deploy seeding and frontend testers — not a unit-test mock.
contract StubERC20 is ERC20 {
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
}
