// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TVLOracle} from "../../src/emission/TVLOracle.sol";
import {IMiliariumRegistry} from "../../src/ccb/IMiliariumRegistry.sol";
import {MockVaultExplorer, MockBasePoolFactory} from "../fork/mocks/StageHMocks.sol";
import {IVaultExplorer} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal dense-enumeration IMiliariumRegistry double — `addPool` appends to the enumeration and marks membership (mirrors the unit-suite double; kept inline for PoC isolation per the F18 house style).
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

/// @title F19_uninitializedVenueLiveness — F-19 (S7 Low) witness for the K-D8 Leg 2 venue enumeration.
/// @notice `TVLOracle._constellationRatio` Leg 2 enumerates every Miliarium-registry pool as a pricing venue
///         via `_venueRatio`, which reads `vaultExplorer.getPoolData(v)` — a call carrying the Vault's
///         `withInitializedPool` modifier. One registered-but-uninitialized roster pool therefore reverted
///         `PoolNotInitialized` and bricked EVERY `tvl()` / `quoteSvZCHF` protocol-wide (surfaced by the
///         P10.3a Leg A e2e on the orchestrator's 26-pool / deploy-uninitialized posture). The P-D37 fix adds
///         an `isPoolInitialized` guard as the first statement of `_venueRatio` — an uninitialized venue is
///         skipped (returns (0, false), the same as any venue that cannot price). This PoC witnesses: (1) tvl
///         survives an uninitialized roster venue and prices via the remaining venue; (2) the guard is
///         load-bearing (the venue read reverts directly); (3) flipping the venue to initialized folds it back
///         into the average — the skip is conditional on init-state, not a permanent drop; (4) quoteSvZCHF,
///         which shares the venue path, is equally unbricked. See docs/STAGE_P_NOTES.md P-D37.
contract F19UninitializedVenueLivenessTest is Test {
    address internal constant GOVERNANCE = address(0x1001);
    address internal constant SVZCHF = address(0x1002);
    address internal constant BODENSEE = address(0x1003);

    address internal constant POOL = address(0x5001);
    address internal constant VENUE_A = address(0x6001);
    address internal constant VENUE_B = address(0x6002);
    address internal constant TOK_U = address(0x00A1);
    address internal constant UNDERLYING = address(0x00B1);

    MockVaultExplorer internal mockExplorer;
    MockBasePoolFactory internal mockFactory;
    MockMiliariumRegistry internal registry;
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
        registry = new MockMiliariumRegistry();

        vm.startPrank(GOVERNANCE);
        oracle.setTokenUnderlying(TOK_U, UNDERLYING);
        oracle.setTokenUnderlying(SVZCHF, SVZCHF);
        vm.stopPrank();

        // VENUE_A initialized (default): TOK_U 100e18 + SVZCHF 200e18 -> ratio 2e18.
        _setVenue(VENUE_A, 100e18, 200e18);

        // VENUE_B registered in the roster but flagged uninitialized and never given a composition.
        mockExplorer.setUninitialized(VENUE_B, true);

        // The priced pool holds only TOK_U (50e18).
        _setPoolSingle(POOL, TOK_U, 50e18);

        registry.addPool(VENUE_A);
        registry.addPool(VENUE_B);
        vm.prank(GOVERNANCE);
        oracle.setMiliariumRegistry(IMiliariumRegistry(address(registry)));
    }

    /// @dev Two-token venue: `underlyingBal` of TOK_U and `svzchfBal` of SVZCHF.
    function _setVenue(address venue, uint256 underlyingBal, uint256 svzchfBal) internal {
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(TOK_U);
        tokens[1] = IERC20(SVZCHF);
        uint256[] memory bals = new uint256[](2);
        bals[0] = underlyingBal;
        bals[1] = svzchfBal;
        mockExplorer.setPool(venue, tokens, bals);
    }

    function _setPoolSingle(address pool, address token, uint256 bal) internal {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(token);
        uint256[] memory bals = new uint256[](1);
        bals[0] = bal;
        mockExplorer.setPool(pool, tokens, bals);
    }

    /// @notice Core F-19 witness — an uninitialized roster venue does NOT brick tvl(); VENUE_A alone prices.
    function test_F19_uninitializedVenue_doesNotBrickTvl() public view {
        // Guard skips VENUE_B; avg ratio = VENUE_A's 2e18; tvl = 50e18 * 2 = 100e18.
        assertEq(oracle.tvl(POOL), 100e18);
    }

    /// @notice The guard is load-bearing — the venue read reverts directly, so absent the guard the Leg 2
    ///         enumeration would propagate this revert into every tvl()/quoteSvZCHF call.
    function test_F19_guardIsLoadBearing_venueReadRevertsDirectly() public {
        vm.expectRevert(abi.encodeWithSelector(MockVaultExplorer.PoolNotInitialized.selector, VENUE_B));
        mockExplorer.getPoolData(VENUE_B);
    }

    /// @notice Flipping VENUE_B to initialized folds it back into the average — the skip is conditional.
    function test_F19_flipToInitialized_foldsVenueBackIn() public {
        _setVenue(VENUE_B, 100e18, 400e18); // ratio 4e18
        mockExplorer.setUninitialized(VENUE_B, false);
        // avg(2e18, 4e18) = 3e18; tvl = 50e18 * 3 = 150e18.
        assertEq(oracle.tvl(POOL), 150e18);
    }

    /// @notice quoteSvZCHF shares the venue path and is equally unbricked by the guard.
    function test_F19_quoteSvZCHF_alsoSurvives() public view {
        // 50e18 * (VENUE_A ratio 2e18) / 1e18 = 100e18.
        assertEq(oracle.quoteSvZCHF(TOK_U, 50e18), 100e18);
    }
}
