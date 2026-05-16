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

    function _mapToken(address token, address underlying) internal {
        vm.prank(GOVERNANCE);
        oracle.setTokenUnderlying(token, underlying);
    }

    function _setComposition(address target, address[] memory tokenAddrs, uint256[] memory balances) internal {
        IERC20[] memory ierc20Tokens = new IERC20[](tokenAddrs.length);
        for (uint256 i = 0; i < tokenAddrs.length; i++) {
            ierc20Tokens[i] = IERC20(tokenAddrs[i]);
        }
        mockExplorer.setPool(target, ierc20Tokens, balances);
    }

    function _addVenue(address venue, address[] memory tokenAddrs, uint256[] memory balances) internal {
        _setComposition(venue, tokenAddrs, balances);
        vm.prank(GOVERNANCE);
        oracle.addConstellationPool(venue);
    }

    function test_tvl_emptyPool_returnsZero() public {
        address pool = _addr(0x5001);
        _setComposition(pool, new address[](0), new uint256[](0));
        assertEq(oracle.tvl(pool), 0);
    }

    function test_tvl_unmappedToken_returnsZero() public {
        address pool = _addr(0x5001);
        address token = _addr(0xA1);
        address[] memory toks = new address[](1);
        toks[0] = token;
        uint256[] memory bals = new uint256[](1);
        bals[0] = 1000e18;
        _setComposition(pool, toks, bals);
        assertEq(oracle.tvl(pool), 0);
    }

    function test_tvl_mappedButNoVenue_returnsZero() public {
        address pool = _addr(0x5001);
        address token = _addr(0xA1);
        address underlying = _addr(0xB1);
        _mapToken(token, underlying);
        address[] memory toks = new address[](1);
        toks[0] = token;
        uint256[] memory bals = new uint256[](1);
        bals[0] = 1000e18;
        _setComposition(pool, toks, bals);
        assertEq(oracle.tvl(pool), 0);
    }

    function test_tvl_svzchfIdentity_returnsBalanceUnchanged() public {
        address pool = _addr(0x5001);
        _mapToken(SVZCHF, SVZCHF);
        address[] memory toks = new address[](1);
        toks[0] = SVZCHF;
        uint256[] memory bals = new uint256[](1);
        bals[0] = 1000e18;
        _setComposition(pool, toks, bals);
        assertEq(oracle.tvl(pool), 1000e18);
    }

    function test_tvl_singleVenue_appliesRatio() public {
        address pool = _addr(0x5001);
        address venue = _addr(0x6001);
        address tokenU = _addr(0xA1);
        address underlying = _addr(0xB1);
        _mapToken(tokenU, underlying);
        _mapToken(SVZCHF, SVZCHF);
        address[] memory vTokens = new address[](2);
        vTokens[0] = tokenU;
        vTokens[1] = SVZCHF;
        uint256[] memory vBals = new uint256[](2);
        vBals[0] = 100e18;
        vBals[1] = 200e18;
        _addVenue(venue, vTokens, vBals);
        address[] memory pTokens = new address[](1);
        pTokens[0] = tokenU;
        uint256[] memory pBals = new uint256[](1);
        pBals[0] = 50e18;
        _setComposition(pool, pTokens, pBals);
        assertEq(oracle.tvl(pool), 100e18);
    }

    function test_tvl_twoVenues_averagesRatios() public {
        address pool = _addr(0x5001);
        address venue1 = _addr(0x6001);
        address venue2 = _addr(0x6002);
        address tokenU = _addr(0xA1);
        address underlying = _addr(0xB1);
        _mapToken(tokenU, underlying);
        _mapToken(SVZCHF, SVZCHF);
        address[] memory v1Tokens = new address[](2);
        v1Tokens[0] = tokenU;
        v1Tokens[1] = SVZCHF;
        uint256[] memory v1Bals = new uint256[](2);
        v1Bals[0] = 100e18;
        v1Bals[1] = 200e18;
        _addVenue(venue1, v1Tokens, v1Bals);
        address[] memory v2Tokens = new address[](2);
        v2Tokens[0] = tokenU;
        v2Tokens[1] = SVZCHF;
        uint256[] memory v2Bals = new uint256[](2);
        v2Bals[0] = 100e18;
        v2Bals[1] = 300e18;
        _addVenue(venue2, v2Tokens, v2Bals);
        address[] memory pTokens = new address[](1);
        pTokens[0] = tokenU;
        uint256[] memory pBals = new uint256[](1);
        pBals[0] = 100e18;
        _setComposition(pool, pTokens, pBals);
        assertEq(oracle.tvl(pool), 250e18);
    }

    function test_tvl_venueMultiTokenSummingPerUnderlying() public {
        address pool = _addr(0x5001);
        address venue = _addr(0x6001);
        address tokenU1 = _addr(0xA1);
        address tokenU2 = _addr(0xA2);
        address underlying = _addr(0xB1);
        _mapToken(tokenU1, underlying);
        _mapToken(tokenU2, underlying);
        _mapToken(SVZCHF, SVZCHF);
        address[] memory vTokens = new address[](3);
        vTokens[0] = tokenU1;
        vTokens[1] = tokenU2;
        vTokens[2] = SVZCHF;
        uint256[] memory vBals = new uint256[](3);
        vBals[0] = 60e18;
        vBals[1] = 40e18;
        vBals[2] = 200e18;
        _addVenue(venue, vTokens, vBals);
        address[] memory pTokens = new address[](1);
        pTokens[0] = tokenU1;
        uint256[] memory pBals = new uint256[](1);
        pBals[0] = 50e18;
        _setComposition(pool, pTokens, pBals);
        assertEq(oracle.tvl(pool), 100e18);
    }

    function test_tvl_poolMultiUnderlying_sumsAcrossTokens() public {
        address pool = _addr(0x5001);
        address venue1 = _addr(0x6001);
        address venue2 = _addr(0x6002);
        address tokenU1 = _addr(0xA1);
        address tokenU2 = _addr(0xA2);
        address underlying1 = _addr(0xB1);
        address underlying2 = _addr(0xB2);
        _mapToken(tokenU1, underlying1);
        _mapToken(tokenU2, underlying2);
        _mapToken(SVZCHF, SVZCHF);
        address[] memory v1Tokens = new address[](2);
        v1Tokens[0] = tokenU1;
        v1Tokens[1] = SVZCHF;
        uint256[] memory v1Bals = new uint256[](2);
        v1Bals[0] = 100e18;
        v1Bals[1] = 200e18;
        _addVenue(venue1, v1Tokens, v1Bals);
        address[] memory v2Tokens = new address[](2);
        v2Tokens[0] = tokenU2;
        v2Tokens[1] = SVZCHF;
        uint256[] memory v2Bals = new uint256[](2);
        v2Bals[0] = 100e18;
        v2Bals[1] = 300e18;
        _addVenue(venue2, v2Tokens, v2Bals);
        address[] memory pTokens = new address[](2);
        pTokens[0] = tokenU1;
        pTokens[1] = tokenU2;
        uint256[] memory pBals = new uint256[](2);
        pBals[0] = 30e18;
        pBals[1] = 20e18;
        _setComposition(pool, pTokens, pBals);
        assertEq(oracle.tvl(pool), 120e18);
    }

    function test_quoteSvZCHF_unmappedToken_returnsZero() public {
        address token = _addr(0xA1);
        assertEq(oracle.quoteSvZCHF(token, 1000e18), 0);
    }

    function test_quoteSvZCHF_mappedButNoVenue_returnsZero() public {
        address token = _addr(0xA1);
        address underlying = _addr(0xB1);
        _mapToken(token, underlying);
        assertEq(oracle.quoteSvZCHF(token, 1000e18), 0);
    }

    function test_quoteSvZCHF_zeroAmount_returnsZero() public {
        address tokenU = _addr(0xA1);
        address underlying = _addr(0xB1);
        address venue = _addr(0x6001);
        _mapToken(tokenU, underlying);
        _mapToken(SVZCHF, SVZCHF);
        address[] memory vTokens = new address[](2);
        vTokens[0] = tokenU;
        vTokens[1] = SVZCHF;
        uint256[] memory vBals = new uint256[](2);
        vBals[0] = 100e18;
        vBals[1] = 200e18;
        _addVenue(venue, vTokens, vBals);
        assertEq(oracle.quoteSvZCHF(tokenU, 0), 0);
    }

    function test_quoteSvZCHF_svzchfIdentity_returnsAmountUnchanged() public {
        _mapToken(SVZCHF, SVZCHF);
        assertEq(oracle.quoteSvZCHF(SVZCHF, 1000e18), 1000e18);
        assertEq(oracle.quoteSvZCHF(SVZCHF, 1), 1);
    }

    function test_quoteSvZCHF_singleVenue_appliesRatio() public {
        address tokenU = _addr(0xA1);
        address underlying = _addr(0xB1);
        address venue = _addr(0x6001);
        _mapToken(tokenU, underlying);
        _mapToken(SVZCHF, SVZCHF);
        address[] memory vTokens = new address[](2);
        vTokens[0] = tokenU;
        vTokens[1] = SVZCHF;
        uint256[] memory vBals = new uint256[](2);
        vBals[0] = 100e18;
        vBals[1] = 200e18;
        _addVenue(venue, vTokens, vBals);
        assertEq(oracle.quoteSvZCHF(tokenU, 50e18), 100e18);
    }

    function test_quoteSvZCHF_twoVenues_averagesRatios() public {
        address tokenU = _addr(0xA1);
        address underlying = _addr(0xB1);
        address venue1 = _addr(0x6001);
        address venue2 = _addr(0x6002);
        _mapToken(tokenU, underlying);
        _mapToken(SVZCHF, SVZCHF);
        address[] memory v1Tokens = new address[](2);
        v1Tokens[0] = tokenU;
        v1Tokens[1] = SVZCHF;
        uint256[] memory v1Bals = new uint256[](2);
        v1Bals[0] = 100e18;
        v1Bals[1] = 200e18;
        _addVenue(venue1, v1Tokens, v1Bals);
        address[] memory v2Tokens = new address[](2);
        v2Tokens[0] = tokenU;
        v2Tokens[1] = SVZCHF;
        uint256[] memory v2Bals = new uint256[](2);
        v2Bals[0] = 100e18;
        v2Bals[1] = 300e18;
        _addVenue(venue2, v2Tokens, v2Bals);
        assertEq(oracle.quoteSvZCHF(tokenU, 100e18), 250e18);
    }

    function test_quoteSvZCHF_linearInAmount() public {
        address tokenU = _addr(0xA1);
        address underlying = _addr(0xB1);
        address venue = _addr(0x6001);
        _mapToken(tokenU, underlying);
        _mapToken(SVZCHF, SVZCHF);
        address[] memory vTokens = new address[](2);
        vTokens[0] = tokenU;
        vTokens[1] = SVZCHF;
        uint256[] memory vBals = new uint256[](2);
        vBals[0] = 100e18;
        vBals[1] = 200e18;
        _addVenue(venue, vTokens, vBals);
        uint256 q1 = oracle.quoteSvZCHF(tokenU, 1e18);
        uint256 q100 = oracle.quoteSvZCHF(tokenU, 100e18);
        assertEq(q1 * 100, q100);
    }

    function test_quoteSvZCHF_matchesTvlInnerLoop() public {
        address tokenU = _addr(0xA1);
        address underlying = _addr(0xB1);
        address venue = _addr(0x6001);
        address pool = _addr(0x5001);
        _mapToken(tokenU, underlying);
        _mapToken(SVZCHF, SVZCHF);
        address[] memory vTokens = new address[](2);
        vTokens[0] = tokenU;
        vTokens[1] = SVZCHF;
        uint256[] memory vBals = new uint256[](2);
        vBals[0] = 100e18;
        vBals[1] = 200e18;
        _addVenue(venue, vTokens, vBals);
        address[] memory pTokens = new address[](1);
        pTokens[0] = tokenU;
        uint256[] memory pBals = new uint256[](1);
        pBals[0] = 75e18;
        _setComposition(pool, pTokens, pBals);
        assertEq(oracle.quoteSvZCHF(tokenU, 75e18), oracle.tvl(pool));
    }
}
