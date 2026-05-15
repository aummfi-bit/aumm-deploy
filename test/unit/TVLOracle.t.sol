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

    function test_addConstellationPool_revert_notGovernance() public {
        address attacker = _addr(0x9999);
        address pool = _addr(0x5001);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(TVLOracle.NotGovernance.selector, attacker));
        oracle.addConstellationPool(pool);
    }

    function test_addConstellationPool_revert_zeroAddress() public {
        vm.prank(GOVERNANCE);
        vm.expectRevert(TVLOracle.ZeroAddress.selector);
        oracle.addConstellationPool(address(0));
    }

    function test_addConstellationPool_revert_alreadyAdded() public {
        address pool = _addr(0x5001);
        mockExplorer.setPool(pool, new IERC20[](0), new uint256[](0));
        vm.prank(GOVERNANCE);
        oracle.addConstellationPool(pool);
        vm.prank(GOVERNANCE);
        vm.expectRevert(abi.encodeWithSelector(TVLOracle.AlreadyAdded.selector, pool));
        oracle.addConstellationPool(pool);
    }

    function test_addConstellationPool_happyPath_setsFlagAndEmits() public {
        address pool = _addr(0x5001);
        address token = _addr(0xA1);
        address underlying = _addr(0xB1);
        vm.prank(GOVERNANCE);
        oracle.setTokenUnderlying(token, underlying);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(token);
        uint256[] memory balances = new uint256[](1);
        balances[0] = 1000e18;
        mockExplorer.setPool(pool, tokens, balances);
        vm.expectEmit(true, false, false, false);
        emit TVLOracle.ConstellationPoolAdded(pool);
        vm.prank(GOVERNANCE);
        oracle.addConstellationPool(pool);
        assertTrue(oracle.isInGovernanceRoster(pool));
    }

    function test_setTokenUnderlying_revert_notGovernance() public {
        address attacker = _addr(0x9999);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(TVLOracle.NotGovernance.selector, attacker));
        oracle.setTokenUnderlying(_addr(0xA1), _addr(0xB1));
    }

    function test_setTokenUnderlying_revert_zeroToken() public {
        vm.prank(GOVERNANCE);
        vm.expectRevert(TVLOracle.ZeroAddress.selector);
        oracle.setTokenUnderlying(address(0), _addr(0xB1));
    }

    function test_setTokenUnderlying_revert_zeroUnderlying() public {
        vm.prank(GOVERNANCE);
        vm.expectRevert(TVLOracle.ZeroAddress.selector);
        oracle.setTokenUnderlying(_addr(0xA1), address(0));
    }

    function test_setTokenUnderlying_happyPath_firstSet_emitsOldZero() public {
        address token = _addr(0xA1);
        address underlying = _addr(0xB1);
        vm.expectEmit(true, true, true, false);
        emit TVLOracle.TokenUnderlyingSet(token, address(0), underlying);
        vm.prank(GOVERNANCE);
        oracle.setTokenUnderlying(token, underlying);
        assertEq(oracle.tokenToUnderlying(token), underlying);
    }

    function test_setTokenUnderlying_overwrite_emitsOldNonZero() public {
        address token = _addr(0xA1);
        address oldU = _addr(0xB1);
        address newU = _addr(0xB2);
        vm.prank(GOVERNANCE);
        oracle.setTokenUnderlying(token, oldU);
        vm.expectEmit(true, true, true, false);
        emit TVLOracle.TokenUnderlyingSet(token, oldU, newU);
        vm.prank(GOVERNANCE);
        oracle.setTokenUnderlying(token, newU);
        assertEq(oracle.tokenToUnderlying(token), newU);
    }
}
