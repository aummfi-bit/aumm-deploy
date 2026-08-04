// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TVLOracle} from "../../src/emission/TVLOracle.sol";
import {ITVLOracle} from "../../src/ccb/ITVLOracle.sol";
import {IMiliariumRegistry} from "../../src/ccb/IMiliariumRegistry.sol";
import {MockVaultExplorer, MockBasePoolFactory} from "../fork/mocks/StageHMocks.sol";
import {IVaultExplorer} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Settable dense-enumeration IMiliariumRegistry double for the K6 Leg 2 / dedup cohort - addPool appends to the enumeration and marks membership.
contract MockMiliariumRegistry is IMiliariumRegistry {
    address[] internal _pools;
    mapping(address => bool) internal _member;

    function addPool(address pool) external {
        _pools.push(pool);
        _member[pool] = true;
    }

    function isMiliarium(address pool) external view returns (bool) {
        return _member[pool];
    }

    function miliariumPoolsCount() external view returns (uint256) {
        return _pools.length;
    }

    function miliariumPoolAt(uint256 index) external view returns (address) {
        return _pools[index];
    }
}

contract TVLOracleTest is Test {
    address internal constant GOVERNANCE = address(0x1001);
    address internal constant SVZCHF = address(0x1002);
    address internal constant BODENSEE = address(0x1003);

    MockVaultExplorer internal mockExplorer;
    MockBasePoolFactory internal mockFactory;
    TVLOracle internal oracle;

    function setUp() public {
        mockExplorer = new MockVaultExplorer();
        mockFactory = new MockBasePoolFactory();
        oracle = new TVLOracle(
            IVaultExplorer(address(mockExplorer)),
            BODENSEE,
            SVZCHF,
            address(mockFactory),
            GOVERNANCE,
            new address[](0),
            new address[](0)
        );
    }

    function _addr(uint256 seed) internal returns (address) {
        return makeAddr(vm.toString(seed));
    }

    function test_constructor_revert_zeroVaultExplorer() public {
        vm.expectRevert(TVLOracle.ZeroAddress.selector);
        new TVLOracle(IVaultExplorer(address(0)), BODENSEE, SVZCHF, address(mockFactory), GOVERNANCE, new address[](0), new address[](0));
    }

    function test_constructor_revert_zeroBodensee() public {
        vm.expectRevert(TVLOracle.ZeroAddress.selector);
        new TVLOracle(IVaultExplorer(address(mockExplorer)), address(0), SVZCHF, address(mockFactory), GOVERNANCE, new address[](0), new address[](0));
    }

    function test_constructor_revert_zeroSvzchf() public {
        vm.expectRevert(TVLOracle.ZeroAddress.selector);
        new TVLOracle(IVaultExplorer(address(mockExplorer)), BODENSEE, address(0), address(mockFactory), GOVERNANCE, new address[](0), new address[](0));
    }

    function test_constructor_revert_zeroApprovedFactory() public {
        vm.expectRevert(TVLOracle.ZeroAddress.selector);
        new TVLOracle(IVaultExplorer(address(mockExplorer)), BODENSEE, SVZCHF, address(0), GOVERNANCE, new address[](0), new address[](0));
    }

    function test_constructor_revert_zeroGovernance() public {
        vm.expectRevert(TVLOracle.ZeroAddress.selector);
        new TVLOracle(IVaultExplorer(address(mockExplorer)), BODENSEE, SVZCHF, address(mockFactory), address(0), new address[](0), new address[](0));
    }

    function test_constructor_revert_arrayLengthMismatch() public {
        address[] memory tokens = new address[](2);
        address[] memory underlyings = new address[](3);
        vm.expectRevert(TVLOracle.ArrayLengthMismatch.selector);
        new TVLOracle(IVaultExplorer(address(mockExplorer)), BODENSEE, SVZCHF, address(mockFactory), GOVERNANCE, tokens, underlyings);
    }

    function test_constructor_wiresImmutablesAndGovernance() public {
        assertEq(address(oracle.vaultExplorer()), address(mockExplorer));
        assertEq(oracle.BODENSEE_POOL(), BODENSEE);
        assertEq(oracle.SVZCHF(), SVZCHF);
        assertEq(oracle.approvedFactory(), address(mockFactory));
        assertEq(oracle.governance(), GOVERNANCE);
    }

    function test_constructor_seedsTokenToUnderlying() public {
        address[] memory tokens = new address[](2);
        tokens[0] = _addr(0xA1);
        tokens[1] = _addr(0xA2);
        address[] memory underlyings = new address[](2);
        underlyings[0] = _addr(0xB1);
        underlyings[1] = _addr(0xB2);
        TVLOracle seeded = new TVLOracle(IVaultExplorer(address(mockExplorer)), BODENSEE, SVZCHF, address(mockFactory), GOVERNANCE, tokens, underlyings);
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

    function _addHop(address underlying) internal {
        vm.prank(GOVERNANCE);
        oracle.addHopUnderlying(underlying);
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

    /* ---------- setMiliariumRegistry + Leg 2 enumeration + dedup (K-D8) ---------- */

    function test_setMiliariumRegistry_happyPath_emitsAndSeals() public {
        MockMiliariumRegistry reg = new MockMiliariumRegistry();
        vm.expectEmit(true, false, false, false);
        emit TVLOracle.MiliariumRegistrySet(address(reg));
        vm.prank(GOVERNANCE);
        oracle.setMiliariumRegistry(IMiliariumRegistry(address(reg)));
        assertEq(address(oracle.miliariumRegistry()), address(reg));
        assertEq(oracle.registrySetter(), address(0));
    }

    function test_setMiliariumRegistry_revert_alreadySet() public {
        MockMiliariumRegistry reg = new MockMiliariumRegistry();
        vm.prank(GOVERNANCE);
        oracle.setMiliariumRegistry(IMiliariumRegistry(address(reg)));
        vm.expectRevert(TVLOracle.OnlyRegistrySetter.selector);
        oracle.setMiliariumRegistry(IMiliariumRegistry(address(reg)));
    }

    function test_setMiliariumRegistry_revert_notSetter() public {
        MockMiliariumRegistry reg = new MockMiliariumRegistry();
        vm.prank(_addr(0xBAD));
        vm.expectRevert(TVLOracle.OnlyRegistrySetter.selector);
        oracle.setMiliariumRegistry(IMiliariumRegistry(address(reg)));
    }

    function test_setMiliariumRegistry_revert_zeroAddress() public {
        vm.expectRevert(TVLOracle.ZeroAddress.selector);
        vm.prank(GOVERNANCE);
        oracle.setMiliariumRegistry(IMiliariumRegistry(address(0)));
    }

    function test_tvl_leg2_registryVenueContributes() public {
        address pool = _addr(0x5001);
        address venue = _addr(0x6001);
        address tokU = _addr(0xA1);
        address underlying = _addr(0xB1);
        _mapToken(tokU, underlying);
        _mapToken(SVZCHF, SVZCHF);
        address[] memory vTokens = new address[](2);
        vTokens[0] = tokU;
        vTokens[1] = SVZCHF;
        uint256[] memory vBals = new uint256[](2);
        vBals[0] = 100e18;
        vBals[1] = 200e18;
        _setComposition(venue, vTokens, vBals);
        address[] memory pTokens = new address[](1);
        pTokens[0] = tokU;
        uint256[] memory pBals = new uint256[](1);
        pBals[0] = 50e18;
        _setComposition(pool, pTokens, pBals);
        // pre-bind: venue is reachable only via the registry (not addConstellationPool'd) so tvl is 0
        assertEq(oracle.tvl(pool), 0);
        MockMiliariumRegistry reg = new MockMiliariumRegistry();
        reg.addPool(venue);
        vm.prank(GOVERNANCE);
        oracle.setMiliariumRegistry(IMiliariumRegistry(address(reg)));
        // Leg 2 now prices via the venue: 50e18 * (200/100) = 100e18
        assertEq(oracle.tvl(pool), 100e18);
    }

    function test_tvl_dedup_miliariumVenueCountedOnce() public {
        address pool = _addr(0x5001);
        address venueA = _addr(0x6001);
        address venueB = _addr(0x6002);
        address tokU = _addr(0xA1);
        address underlying = _addr(0xB1);
        _mapToken(tokU, underlying);
        _mapToken(SVZCHF, SVZCHF);
        // venue A (governance-only): ratio 100/100 = 1e18
        address[] memory aTokens = new address[](2);
        aTokens[0] = tokU;
        aTokens[1] = SVZCHF;
        uint256[] memory aBals = new uint256[](2);
        aBals[0] = 100e18;
        aBals[1] = 100e18;
        _addVenue(venueA, aTokens, aBals);
        // venue B (governance AND registry): ratio 300/100 = 3e18
        address[] memory bTokens = new address[](2);
        bTokens[0] = tokU;
        bTokens[1] = SVZCHF;
        uint256[] memory bBals = new uint256[](2);
        bBals[0] = 100e18;
        bBals[1] = 300e18;
        _addVenue(venueB, bTokens, bBals);
        MockMiliariumRegistry reg = new MockMiliariumRegistry();
        reg.addPool(venueB);
        vm.prank(GOVERNANCE);
        oracle.setMiliariumRegistry(IMiliariumRegistry(address(reg)));
        address[] memory pTokens = new address[](1);
        pTokens[0] = tokU;
        uint256[] memory pBals = new uint256[](1);
        pBals[0] = 50e18;
        _setComposition(pool, pTokens, pBals);
        // dedup: Leg 1 skips venueB (isMiliarium), Leg 2 owns it; avg = (1e18 + 3e18)/2 = 2e18 -> 50e18 * 2 = 100e18.
        // a double-count would be (1 + 3 + 3)/3 ~= 2.33e18 -> ~116.67e18.
        assertEq(oracle.tvl(pool), 100e18);
    }

    /* ---------- addHopUnderlying + 2-hop valuation fallback (PB-D7, OQ-22 Phase 2) ---------- */

    function test_addHopUnderlying_revert_notGovernance() public {
        address attacker = _addr(0x9999);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(TVLOracle.NotGovernance.selector, attacker));
        oracle.addHopUnderlying(_addr(0xB2));
    }

    function test_addHopUnderlying_revert_zeroAddress() public {
        vm.prank(GOVERNANCE);
        vm.expectRevert(TVLOracle.ZeroAddress.selector);
        oracle.addHopUnderlying(address(0));
    }

    function test_addHopUnderlying_revert_alreadyAdded() public {
        address I = _addr(0xB2);
        _addHop(I);
        vm.prank(GOVERNANCE);
        vm.expectRevert(abi.encodeWithSelector(TVLOracle.AlreadyAdded.selector, I));
        oracle.addHopUnderlying(I);
    }

    function test_addHopUnderlying_happyPath_setsFlagAndEmits() public {
        address I = _addr(0xB2);
        vm.expectEmit(true, false, false, false);
        emit TVLOracle.HopUnderlyingAdded(I);
        vm.prank(GOVERNANCE);
        oracle.addHopUnderlying(I);
        assertTrue(oracle.isHopUnderlying(I));
    }

    function test_tvl_twoHopFallback_pricesViaIntermediate() public {
        address tokenU = _addr(0xA1);
        address U = _addr(0xB1);
        address tokenI = _addr(0xA2);
        address I = _addr(0xB2);
        _mapToken(tokenU, U);
        _mapToken(tokenI, I);
        _mapToken(SVZCHF, SVZCHF);
        _addHop(I);
        address venueUI = _addr(0x6003);
        address[] memory uiTokens = new address[](2);
        uiTokens[0] = tokenU;
        uiTokens[1] = tokenI;
        uint256[] memory uiBals = new uint256[](2);
        uiBals[0] = 100e18;
        uiBals[1] = 200e18;
        _addVenue(venueUI, uiTokens, uiBals);
        address venueIZ = _addr(0x6004);
        address[] memory izTokens = new address[](2);
        izTokens[0] = tokenI;
        izTokens[1] = SVZCHF;
        uint256[] memory izBals = new uint256[](2);
        izBals[0] = 100e18;
        izBals[1] = 300e18;
        _addVenue(venueIZ, izTokens, izBals);
        address pool = _addr(0x5003);
        address[] memory pTokens = new address[](1);
        pTokens[0] = tokenU;
        uint256[] memory pBals = new uint256[](1);
        pBals[0] = 50e18;
        _setComposition(pool, pTokens, pBals);
        assertEq(oracle.tvl(pool), 300e18);
    }

    function test_tvl_directVenueWins_overHopPath() public {
        address tokenU = _addr(0xA1);
        address U = _addr(0xB1);
        address tokenI = _addr(0xA2);
        address I = _addr(0xB2);
        _mapToken(tokenU, U);
        _mapToken(tokenI, I);
        _mapToken(SVZCHF, SVZCHF);
        _addHop(I);
        address venueUI = _addr(0x6003);
        address[] memory uiTokens = new address[](2);
        uiTokens[0] = tokenU;
        uiTokens[1] = tokenI;
        uint256[] memory uiBals = new uint256[](2);
        uiBals[0] = 100e18;
        uiBals[1] = 200e18;
        _addVenue(venueUI, uiTokens, uiBals);
        address venueIZ = _addr(0x6004);
        address[] memory izTokens = new address[](2);
        izTokens[0] = tokenI;
        izTokens[1] = SVZCHF;
        uint256[] memory izBals = new uint256[](2);
        izBals[0] = 100e18;
        izBals[1] = 300e18;
        _addVenue(venueIZ, izTokens, izBals);
        address venueUZ = _addr(0x6005);
        address[] memory uzTokens = new address[](2);
        uzTokens[0] = tokenU;
        uzTokens[1] = SVZCHF;
        uint256[] memory uzBals = new uint256[](2);
        uzBals[0] = 100e18;
        uzBals[1] = 500e18;
        _addVenue(venueUZ, uzTokens, uzBals);
        address pool = _addr(0x5003);
        address[] memory pTokens = new address[](1);
        pTokens[0] = tokenU;
        uint256[] memory pBals = new uint256[](1);
        pBals[0] = 50e18;
        _setComposition(pool, pTokens, pBals);
        assertEq(oracle.tvl(pool), 250e18);
    }

    function test_tvl_twoHopFallback_meanAcrossTwoIntermediates() public {
        address tokenU = _addr(0xA1);
        address U = _addr(0xB1);
        address tokenI1 = _addr(0xA2);
        address I1 = _addr(0xB2);
        address tokenI2 = _addr(0xA3);
        address I2 = _addr(0xB3);
        _mapToken(tokenU, U);
        _mapToken(tokenI1, I1);
        _mapToken(tokenI2, I2);
        _mapToken(SVZCHF, SVZCHF);
        _addHop(I1);
        _addHop(I2);
        address venueU_I1 = _addr(0x6003);
        address[] memory uI1Tokens = new address[](2);
        uI1Tokens[0] = tokenU;
        uI1Tokens[1] = tokenI1;
        uint256[] memory uI1Bals = new uint256[](2);
        uI1Bals[0] = 100e18;
        uI1Bals[1] = 100e18;
        _addVenue(venueU_I1, uI1Tokens, uI1Bals);
        address venueI1_Z = _addr(0x6004);
        address[] memory i1ZTokens = new address[](2);
        i1ZTokens[0] = tokenI1;
        i1ZTokens[1] = SVZCHF;
        uint256[] memory i1ZBals = new uint256[](2);
        i1ZBals[0] = 100e18;
        i1ZBals[1] = 200e18;
        _addVenue(venueI1_Z, i1ZTokens, i1ZBals);
        address venueU_I2 = _addr(0x6005);
        address[] memory uI2Tokens = new address[](2);
        uI2Tokens[0] = tokenU;
        uI2Tokens[1] = tokenI2;
        uint256[] memory uI2Bals = new uint256[](2);
        uI2Bals[0] = 100e18;
        uI2Bals[1] = 100e18;
        _addVenue(venueU_I2, uI2Tokens, uI2Bals);
        address venueI2_Z = _addr(0x6006);
        address[] memory i2ZTokens = new address[](2);
        i2ZTokens[0] = tokenI2;
        i2ZTokens[1] = SVZCHF;
        uint256[] memory i2ZBals = new uint256[](2);
        i2ZBals[0] = 100e18;
        i2ZBals[1] = 400e18;
        _addVenue(venueI2_Z, i2ZTokens, i2ZBals);
        address pool = _addr(0x5003);
        address[] memory pTokens = new address[](1);
        pTokens[0] = tokenU;
        uint256[] memory pBals = new uint256[](1);
        pBals[0] = 50e18;
        _setComposition(pool, pTokens, pBals);
        assertEq(oracle.tvl(pool), 150e18);
    }

    function test_tvl_twoHop_skipsSelfHopUnderlying() public {
        address tokenU = _addr(0xA1);
        address U = _addr(0xB1);
        address tokenI = _addr(0xA2);
        address I = _addr(0xB2);
        _mapToken(tokenU, U);
        _mapToken(tokenI, I);
        _mapToken(SVZCHF, SVZCHF);
        _addHop(U);
        _addHop(I);
        address venueUI = _addr(0x6003);
        address[] memory uiTokens = new address[](2);
        uiTokens[0] = tokenU;
        uiTokens[1] = tokenI;
        uint256[] memory uiBals = new uint256[](2);
        uiBals[0] = 100e18;
        uiBals[1] = 200e18;
        _addVenue(venueUI, uiTokens, uiBals);
        address venueIZ = _addr(0x6004);
        address[] memory izTokens = new address[](2);
        izTokens[0] = tokenI;
        izTokens[1] = SVZCHF;
        uint256[] memory izBals = new uint256[](2);
        izBals[0] = 100e18;
        izBals[1] = 300e18;
        _addVenue(venueIZ, izTokens, izBals);
        address pool = _addr(0x5003);
        address[] memory pTokens = new address[](1);
        pTokens[0] = tokenU;
        uint256[] memory pBals = new uint256[](1);
        pBals[0] = 50e18;
        _setComposition(pool, pTokens, pBals);
        assertEq(oracle.tvl(pool), 300e18);
    }

    function test_tvl_twoHop_skipsSvzchfHop() public {
        address tokenU = _addr(0xA1);
        address U = _addr(0xB1);
        address tokenI = _addr(0xA2);
        address I = _addr(0xB2);
        _mapToken(tokenU, U);
        _mapToken(tokenI, I);
        _mapToken(SVZCHF, SVZCHF);
        _addHop(SVZCHF);
        _addHop(I);
        address venueUI = _addr(0x6003);
        address[] memory uiTokens = new address[](2);
        uiTokens[0] = tokenU;
        uiTokens[1] = tokenI;
        uint256[] memory uiBals = new uint256[](2);
        uiBals[0] = 100e18;
        uiBals[1] = 200e18;
        _addVenue(venueUI, uiTokens, uiBals);
        address venueIZ = _addr(0x6004);
        address[] memory izTokens = new address[](2);
        izTokens[0] = tokenI;
        izTokens[1] = SVZCHF;
        uint256[] memory izBals = new uint256[](2);
        izBals[0] = 100e18;
        izBals[1] = 300e18;
        _addVenue(venueIZ, izTokens, izBals);
        address pool = _addr(0x5003);
        address[] memory pTokens = new address[](1);
        pTokens[0] = tokenU;
        uint256[] memory pBals = new uint256[](1);
        pBals[0] = 50e18;
        _setComposition(pool, pTokens, pBals);
        assertEq(oracle.tvl(pool), 300e18);
    }

    function test_tvl_twoHop_h2MissIntermediateInert() public {
        address tokenU = _addr(0xA1);
        address U = _addr(0xB1);
        address tokenI = _addr(0xA2);
        address I = _addr(0xB2);
        _mapToken(tokenU, U);
        _mapToken(tokenI, I);
        _mapToken(SVZCHF, SVZCHF);
        _addHop(I);
        address venueUI = _addr(0x6003);
        address[] memory uiTokens = new address[](2);
        uiTokens[0] = tokenU;
        uiTokens[1] = tokenI;
        uint256[] memory uiBals = new uint256[](2);
        uiBals[0] = 100e18;
        uiBals[1] = 200e18;
        _addVenue(venueUI, uiTokens, uiBals);
        address pool = _addr(0x5003);
        address[] memory pTokens = new address[](1);
        pTokens[0] = tokenU;
        uint256[] memory pBals = new uint256[](1);
        pBals[0] = 50e18;
        _setComposition(pool, pTokens, pBals);
        assertEq(oracle.tvl(pool), 0);
    }

    function test_tvl_twoHop_noTransitiveHop_returnsZero() public {
        address tokenU = _addr(0xA1);
        address U = _addr(0xB1);
        address tokenI = _addr(0xA2);
        address I = _addr(0xB2);
        address tokenJ = _addr(0xA4);
        address J = _addr(0xB4);
        _mapToken(tokenU, U);
        _mapToken(tokenI, I);
        _mapToken(tokenJ, J);
        _mapToken(SVZCHF, SVZCHF);
        _addHop(I);
        _addHop(J);
        address venueUI = _addr(0x6003);
        address[] memory uiTokens = new address[](2);
        uiTokens[0] = tokenU;
        uiTokens[1] = tokenI;
        uint256[] memory uiBals = new uint256[](2);
        uiBals[0] = 100e18;
        uiBals[1] = 100e18;
        _addVenue(venueUI, uiTokens, uiBals);
        address venueIJ = _addr(0x6004);
        address[] memory ijTokens = new address[](2);
        ijTokens[0] = tokenI;
        ijTokens[1] = tokenJ;
        uint256[] memory ijBals = new uint256[](2);
        ijBals[0] = 100e18;
        ijBals[1] = 100e18;
        _addVenue(venueIJ, ijTokens, ijBals);
        address venueJZ = _addr(0x6005);
        address[] memory jzTokens = new address[](2);
        jzTokens[0] = tokenJ;
        jzTokens[1] = SVZCHF;
        uint256[] memory jzBals = new uint256[](2);
        jzBals[0] = 100e18;
        jzBals[1] = 200e18;
        _addVenue(venueJZ, jzTokens, jzBals);
        address pool = _addr(0x5003);
        address[] memory pTokens = new address[](1);
        pTokens[0] = tokenU;
        uint256[] memory pBals = new uint256[](1);
        pBals[0] = 50e18;
        _setComposition(pool, pTokens, pBals);
        assertEq(oracle.tvl(pool), 0);
    }

    function test_quoteSvZCHF_twoHopFallback_pricesViaIntermediate() public {
        address tokenU = _addr(0xA1);
        address U = _addr(0xB1);
        address tokenI = _addr(0xA2);
        address I = _addr(0xB2);
        _mapToken(tokenU, U);
        _mapToken(tokenI, I);
        _mapToken(SVZCHF, SVZCHF);
        _addHop(I);
        address venueUI = _addr(0x6003);
        address[] memory uiTokens = new address[](2);
        uiTokens[0] = tokenU;
        uiTokens[1] = tokenI;
        uint256[] memory uiBals = new uint256[](2);
        uiBals[0] = 100e18;
        uiBals[1] = 200e18;
        _addVenue(venueUI, uiTokens, uiBals);
        address venueIZ = _addr(0x6004);
        address[] memory izTokens = new address[](2);
        izTokens[0] = tokenI;
        izTokens[1] = SVZCHF;
        uint256[] memory izBals = new uint256[](2);
        izBals[0] = 100e18;
        izBals[1] = 300e18;
        _addVenue(venueIZ, izTokens, izBals);
        assertEq(oracle.quoteSvZCHF(tokenU, 50e18), 300e18);
    }

    function test_tvl_twoHop_emptyRosterDirectMiss_returnsZero() public {
        address tokenU = _addr(0xA1);
        address U = _addr(0xB1);
        _mapToken(tokenU, U);
        _mapToken(SVZCHF, SVZCHF);
        address pool = _addr(0x5003);
        address[] memory pTokens = new address[](1);
        pTokens[0] = tokenU;
        uint256[] memory pBals = new uint256[](1);
        pBals[0] = 50e18;
        _setComposition(pool, pTokens, pBals);
        assertEq(oracle.tvl(pool), 0);
        assertEq(oracle.quoteSvZCHF(tokenU, 50e18), 0);
    }
}
