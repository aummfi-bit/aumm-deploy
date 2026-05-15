// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TVLOracle} from "../../src/emission/TVLOracle.sol";
import {ITVLOracle} from "../../src/ccb/ITVLOracle.sol";
import {MockVaultExplorer} from "../fork/mocks/StageHMocks.sol";
import {IVaultExplorer} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TVLOracleTest is Test {
    address internal constant GOVERNANCE = address(0x1001);
    address internal constant SVZCHF = address(0x1002);
    address internal constant BODENSEE = address(0x1003);

    MockVaultExplorer internal mockExplorer;
    TVLOracle internal oracle;

    function setUp() public {
        mockExplorer = new MockVaultExplorer();
        oracle = new TVLOracle(
            IVaultExplorer(address(mockExplorer)),
            BODENSEE,
            SVZCHF,
            GOVERNANCE,
            new address[](0),
            new address[](0)
        );
    }

    function _addr(uint256 seed) internal pure returns (address) {
        return address(uint160(seed));
    }
}
