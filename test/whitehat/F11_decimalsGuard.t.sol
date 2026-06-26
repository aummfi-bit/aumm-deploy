// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IRateProvider} from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import {ERC4626RateProvider} from "src/rate_provider/ERC4626RateProvider.sol";
import {CompositeRateProvider} from "src/rate_provider/CompositeRateProvider.sol";

/// @notice F-11 fix regression (WN whitehat pass) — both rate providers' constructors enforce 18-decimal
///         vault shares AND an 18-decimal underlying asset, failing closed on any other pairing. Scope is
///         deploy-time preconditions only; `getRate()` math is unchanged.
contract F11_DecimalsGuardTest is Test {
    function test_erc4626_reverts_whenShareDecimalsNot18() public {
        MockDecimalsToken asset = new MockDecimalsToken(18);
        MockDecimalsVault vault = new MockDecimalsVault(6, address(asset));
        vm.expectRevert(abi.encodeWithSelector(ERC4626RateProvider.InvalidShareDecimals.selector, uint8(6)));
        new ERC4626RateProvider(IERC4626(address(vault)));
    }

    function test_erc4626_reverts_whenAssetDecimalsNot18() public {
        MockDecimalsToken asset = new MockDecimalsToken(6);
        MockDecimalsVault vault = new MockDecimalsVault(18, address(asset));
        vm.expectRevert(abi.encodeWithSelector(ERC4626RateProvider.InvalidAssetDecimals.selector, uint8(6)));
        new ERC4626RateProvider(IERC4626(address(vault)));
    }

    function test_erc4626_constructs_when18And18() public {
        MockDecimalsToken asset = new MockDecimalsToken(18);
        MockDecimalsVault vault = new MockDecimalsVault(18, address(asset));
        ERC4626RateProvider rp = new ERC4626RateProvider(IERC4626(address(vault)));
        assertEq(address(rp.wrappedToken()), address(vault));
    }

    function test_composite_reverts_whenWrapperShareDecimalsNot18() public {
        MockDecimalsToken asset = new MockDecimalsToken(18);
        MockDecimalsVault vault = new MockDecimalsVault(6, address(asset));
        MockRateProvider underlying = new MockRateProvider(1e18);
        vm.expectRevert(abi.encodeWithSelector(CompositeRateProvider.InvalidShareDecimals.selector, uint8(6)));
        new CompositeRateProvider(IERC4626(address(vault)), IRateProvider(address(underlying)));
    }

    function test_composite_reverts_whenWrapperAssetDecimalsNot18() public {
        MockDecimalsToken asset = new MockDecimalsToken(6);
        MockDecimalsVault vault = new MockDecimalsVault(18, address(asset));
        MockRateProvider underlying = new MockRateProvider(1e18);
        vm.expectRevert(abi.encodeWithSelector(CompositeRateProvider.InvalidAssetDecimals.selector, uint8(6)));
        new CompositeRateProvider(IERC4626(address(vault)), IRateProvider(address(underlying)));
    }

    function test_composite_constructs_when18And18() public {
        MockDecimalsToken asset = new MockDecimalsToken(18);
        MockDecimalsVault vault = new MockDecimalsVault(18, address(asset));
        MockRateProvider underlying = new MockRateProvider(1e18);
        CompositeRateProvider rp =
            new CompositeRateProvider(IERC4626(address(vault)), IRateProvider(address(underlying)));
        assertEq(address(rp.wrapper()), address(vault));
        assertEq(address(rp.underlyingRateProvider()), address(underlying));
    }
}

contract MockDecimalsToken {
    uint8 public immutable decimals;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }
}

contract MockDecimalsVault {
    uint8 public decimals;
    address public asset;

    constructor(uint8 shareDecimals_, address asset_) {
        decimals = shareDecimals_;
        asset = asset_;
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return shares;
    }
}

contract MockRateProvider is IRateProvider {
    uint256 internal immutable rate;

    constructor(uint256 rate_) {
        rate = rate_;
    }

    function getRate() external view override returns (uint256) {
        return rate;
    }
}
