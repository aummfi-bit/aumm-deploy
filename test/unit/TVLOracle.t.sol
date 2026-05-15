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

    function test_constructor_revert_zeroVaultExplorer() public {
        vm.expectRevert(TVLOracle.ZeroAddress.selector);
        new TVLOracle(IVaultExplorer(address(0)), BODENSEE, SVZCHF, GOVERNANCE, new address[](0), new address[](0));
    }

    function test_constructor_revert_zeroBodensee() public {
        vm.expectRevert(TVLOracle.ZeroAddress.selector);
        new TVLOracle(IVaultExplorer(address(mockExplorer)), address(0), SVZCHF, GOVERNANCE, new address[](0), new address[](0));
    }

    function test_constructor_revert_zeroSvzchf() public {
        vm.expectRevert(TVLOracle.ZeroAddress.selector);
        new TVLOracle(IVaultExplorer(address(mockExplorer)), BODENSEE, address(0), GOVERNANCE, new address[](0), new address[](0));
    }

    function test_constructor_revert_zeroGovernance() public {
        vm.expectRevert(TVLOracle.ZeroAddress.selector);
        new TVLOracle(IVaultExplorer(address(mockExplorer)), BODENSEE, SVZCHF, address(0), new address[](0), new address[](0));
    }

    function test_constructor_revert_arrayLengthMismatch() public {
        address[] memory tokens = new address[](2);
        address[] memory underlyings = new address[](3);
        vm.expectRevert(TVLOracle.ArrayLengthMismatch.selector);
        new TVLOracle(IVaultExplorer(address(mockExplorer)), BODENSEE, SVZCHF, GOVERNANCE, tokens, underlyings);
    }

    function test_constructor_wiresImmutablesAndGovernance() public {
        assertEq(address(oracle.vaultExplorer()), address(mockExplorer));
        assertEq(oracle.BODENSEE_POOL(), BODENSEE);
        assertEq(oracle.SVZCHF(), SVZCHF);
        assertEq(oracle.governance(), GOVERNANCE);
    }

    function test_constructor_seedsTokenToUnderlying() public {
        address[] memory tokens = new address[](2);
        tokens[0] = _addr(0xA1);
        tokens[1] = _addr(0xA2);
        address[] memory underlyings = new address[](2);
        underlyings[0] = _addr(0xB1);
        underlyings[1] = _addr(0xB2);
        TVLOracle seeded = new TVLOracle(IVaultExplorer(address(mockExplorer)), BODENSEE, SVZCHF, GOVERNANCE, tokens, underlyings);
        assertEq(seeded.tokenToUnderlying(_addr(0xA1)), _addr(0xB1));
        assertEq(seeded.tokenToUnderlying(_addr(0xA2)), _addr(0xB2));
    }

    function test_setGovernanceContract_happyPath_emitsEvent() public {
        address newGov = _addr(0x9001);
        vm.expectEmit(true, true, false, false);
        emit TVLOracle.GovernanceTransferred(GOVERNANCE, newGov);
        vm.prank(GOVERNANCE);
        oracle.setGovernanceContract(newGov);
        assertEq(oracle.governance(), newGov);
    }

    function test_setGovernanceContract_revert_notGovernance() public {
        address attacker = _addr(0x9999);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(TVLOracle.NotGovernance.selector, attacker));
        oracle.setGovernanceContract(_addr(0x9001));
    }

    function test_setGovernanceContract_revert_zeroAddress() public {
        vm.prank(GOVERNANCE);
        vm.expectRevert(TVLOracle.ZeroAddress.selector);
        oracle.setGovernanceContract(address(0));
    }

    function test_setGovernanceContract_postTransfer_oldGovernanceCannotCall() public {
        address newGov = _addr(0x9001);
        vm.prank(GOVERNANCE);
        oracle.setGovernanceContract(newGov);
        vm.prank(GOVERNANCE);
        vm.expectRevert(abi.encodeWithSelector(TVLOracle.NotGovernance.selector, GOVERNANCE));
        oracle.setGovernanceContract(_addr(0x9002));
    }
}
