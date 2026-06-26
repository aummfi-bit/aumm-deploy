// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IRateProvider} from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import {ERC4626RateProvider} from "src/rate_provider/ERC4626RateProvider.sol";
import {CompositeRateProvider} from "src/rate_provider/CompositeRateProvider.sol";

/// @title RateProviderTest
/// @notice N3.3 unit coverage for the Aureum-owned src/rate_provider/ surface (N-D1 / N-D2), gating the
///         N7 WN whitehat pass (N-D6). Exercises both providers against purpose-built file-local mocks:
///         getRate() correctness, EIP-4626 round-down pass-through, FixedPoint mulDown round-down on the
///         composite, zero-rate handling, and revert propagation from the underlying rate provider.
///         Real-vault mixed-decimal behavior is covered at the N6 fork tier.
contract RateProviderTest is Test {
    MockPreviewVault internal vault;
    MockRevertableRateProvider internal underlying;

    function setUp() public {
        // Default wrapper rate 1 share -> 1.05 assets (105/100); default underlying 1.10e18.
        vault = new MockPreviewVault(105, 100);
        underlying = new MockRevertableRateProvider(1.1e18);
    }

    // --- ERC4626RateProvider ---

    function test_erc4626_immutableWired() public {
        ERC4626RateProvider rp = new ERC4626RateProvider(IERC4626(address(vault)));
        assertEq(address(rp.wrappedToken()), address(vault), "wrappedToken not wired");
    }

    function test_erc4626_getRate_returnsPreviewRedeemOfOneShare() public {
        ERC4626RateProvider rp = new ERC4626RateProvider(IERC4626(address(vault)));
        // previewRedeem(1e18) = 1e18 * 105 / 100 = 1.05e18.
        assertEq(rp.getRate(), 1.05e18, "getRate != previewRedeem(1e18)");
    }

    function test_erc4626_getRate_passesThroughVaultRoundDown() public {
        // 1 share -> 1/3 asset; previewRedeem(1e18) = 1e18 / 3, floored by EIP-4626 convertToAssets.
        vault.set(1, 3);
        ERC4626RateProvider rp = new ERC4626RateProvider(IERC4626(address(vault)));
        assertEq(rp.getRate(), uint256(1e18) / 3, "round-down not passed through");
    }

    function test_erc4626_getRate_zeroWhenVaultRateZero() public {
        vault.set(0, 100);
        ERC4626RateProvider rp = new ERC4626RateProvider(IERC4626(address(vault)));
        assertEq(rp.getRate(), 0, "zero rate not reported");
    }

    // --- CompositeRateProvider ---

    function test_composite_immutablesWired() public {
        CompositeRateProvider rp =
            new CompositeRateProvider(IERC4626(address(vault)), IRateProvider(address(underlying)));
        assertEq(address(rp.wrapper()), address(vault), "wrapper not wired");
        assertEq(address(rp.underlyingRateProvider()), address(underlying), "underlyingRateProvider not wired");
    }

    function test_composite_getRate_composesBothHops() public {
        CompositeRateProvider rp =
            new CompositeRateProvider(IERC4626(address(vault)), IRateProvider(address(underlying)));
        // hop1 = previewRedeem(1e18) = 1.05e18; hop2 = underlying.getRate() = 1.1e18.
        // composite = mulDown(1.05e18, 1.1e18) = 1.05e18 * 1.1e18 / 1e18 = 1.155e18.
        uint256 expected = uint256(1.05e18) * 1.1e18 / 1e18;
        assertEq(rp.getRate(), expected, "composite != hop1.mulDown(hop2)");
        assertEq(expected, 1.155e18, "expected literal sanity");
    }

    function test_composite_getRate_mulDownRoundsDown() public {
        // hop1 = 1e18/3 (vault 1/3), hop2 = 1e18/3 (underlying); mulDown floors the product.
        vault.set(1, 3);
        underlying.setRate(uint256(1e18) / 3);
        CompositeRateProvider rp =
            new CompositeRateProvider(IERC4626(address(vault)), IRateProvider(address(underlying)));
        uint256 hop1 = uint256(1e18) / 3;
        uint256 expected = hop1 * (uint256(1e18) / 3) / 1e18;
        assertEq(rp.getRate(), expected, "mulDown round-down mismatch");
    }

    function test_composite_getRate_zeroWhenUnderlyingZero() public {
        underlying.setRate(0);
        CompositeRateProvider rp =
            new CompositeRateProvider(IERC4626(address(vault)), IRateProvider(address(underlying)));
        assertEq(rp.getRate(), 0, "zero underlying rate not propagated");
    }

    function test_composite_getRate_zeroWhenWrapperZero() public {
        vault.set(0, 100);
        CompositeRateProvider rp =
            new CompositeRateProvider(IERC4626(address(vault)), IRateProvider(address(underlying)));
        assertEq(rp.getRate(), 0, "zero wrapper rate not propagated");
    }

    function test_composite_getRate_revertsWhenUnderlyingReverts() public {
        underlying.setShouldRevert(true);
        CompositeRateProvider rp =
            new CompositeRateProvider(IERC4626(address(vault)), IRateProvider(address(underlying)));
        vm.expectRevert(MockRevertableRateProvider.ForcedRevert.selector);
        rp.getRate();
    }

    function test_composite_getRate_largeAndSmallMagnitudesNoImplicitScaling() public {
        // hop1 = 2e18 (vault 2:1), hop2 = 0.5e18 -> mulDown = 1e18; confirms no decimal fudge.
        vault.set(200, 100);
        underlying.setRate(0.5e18);
        CompositeRateProvider rp =
            new CompositeRateProvider(IERC4626(address(vault)), IRateProvider(address(underlying)));
        assertEq(rp.getRate(), 1e18, "magnitude composition wrong");
    }
}

// --- file-local mocks ---

/// @notice Minimal ERC-4626 stub exposing previewRedeem plus the decimals()/asset() pair the F-11
///         constructor guard reads. previewRedeem(shares) = shares * numerator / denominator floors,
///         mirroring EIP-4626 convertToAssets round-down. 18-decimal shares + 18-decimal asset so the
///         providers' F-11 guard passes; non-18-decimal cases live in test/whitehat/F11. Cast to
///         IERC4626 at the call site.
contract MockPreviewVault {
    uint256 public numerator;
    uint256 public denominator;
    address internal immutable _asset;

    constructor(uint256 numerator_, uint256 denominator_) {
        numerator = numerator_;
        denominator = denominator_;
        _asset = address(new MockDecimalsToken(18));
    }

    function set(uint256 numerator_, uint256 denominator_) external {
        numerator = numerator_;
        denominator = denominator_;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function asset() external view returns (address) {
        return _asset;
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return shares * numerator / denominator;
    }
}

/// @notice Minimal token exposing only decimals(), so MockPreviewVault.asset() satisfies the F-11
///         guard's IERC20Metadata(asset).decimals() == 18 check.
contract MockDecimalsToken {
    uint8 public immutable decimals;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }
}

/// @notice Mock IRateProvider with a settable rate and a forced-revert mode, for exercising the
///         composite's zero-rate and revert-propagation paths.
contract MockRevertableRateProvider is IRateProvider {
    error ForcedRevert();

    uint256 public rate;
    bool public shouldRevert;

    constructor(uint256 rate_) {
        rate = rate_;
    }

    function setRate(uint256 rate_) external {
        rate = rate_;
    }

    function setShouldRevert(bool shouldRevert_) external {
        shouldRevert = shouldRevert_;
    }

    function getRate() external view override returns (uint256) {
        if (shouldRevert) revert ForcedRevert();
        return rate;
    }
}
