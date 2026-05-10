// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {AddLiquidityKind, AddLiquidityParams, TokenInfo} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {SwapAndDepositToBodensee} from "src/gauge/SwapAndDepositToBodensee.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockVault {
    IERC20[] public mockTokens;
    uint256[] public mockBalancesRaw;

    bool public reentrancyAttack;
    bool public corruptCallbackAmount;
    address public helperRef;

    IERC20 public attackPayToken;
    uint256 public attackAmount;

    function setTokens(IERC20[] calldata tokens_) external {
        delete mockTokens;
        uint256 len = tokens_.length;
        for (uint256 i = 0; i < len; ++i) {
            mockTokens.push(tokens_[i]);
        }
    }

    function setBalancesRaw(uint256[] calldata balancesRaw_) external {
        delete mockBalancesRaw;
        uint256 len = balancesRaw_.length;
        for (uint256 i = 0; i < len; ++i) {
            mockBalancesRaw.push(balancesRaw_[i]);
        }
    }

    function setHelper(address helper_) external {
        helperRef = helper_;
    }

    function configureAttack(IERC20 payToken_, uint256 amount_) external {
        attackPayToken = payToken_;
        attackAmount = amount_;
    }

    function enableReentrancyAttack() external {
        reentrancyAttack = true;
    }

    function enableCorruptCallback() external {
        corruptCallbackAmount = true;
    }

    function getPoolTokens(address) external view returns (IERC20[] memory) {
        IERC20[] memory tokens = new IERC20[](mockTokens.length);
        uint256 len = mockTokens.length;
        for (uint256 i = 0; i < len; ++i) {
            tokens[i] = mockTokens[i];
        }
        return tokens;
    }

    function unlock(bytes calldata data) external returns (bytes memory) {
        bytes memory callData = data;
        if (corruptCallbackAmount) {
            (IERC20 payToken, uint256 amount) = abi.decode(data[4:], (IERC20, uint256));
            callData = abi.encodeWithSelector(
                SwapAndDepositToBodensee._swapAndDepositCallback.selector,
                payToken,
                amount + 1
            );
        }
        (bool success, bytes memory ret) = helperRef.call(callData);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(ret, 32), mload(ret))
            }
        }
        return ret;
    }

    function settle(IERC20, uint256 amount_) external pure returns (uint256) {
        return amount_;
    }

    function getPoolTokenInfo(address)
        external
        returns (
            IERC20[] memory tokens,
            TokenInfo[] memory tokenInfo,
            uint256[] memory balancesRaw,
            uint256[] memory lastBalancesLiveScaled18
        )
    {
        if (reentrancyAttack) {
            SwapAndDepositToBodensee(helperRef).swapAndDeposit(attackPayToken, attackAmount);
        }
        uint256 len = mockTokens.length;
        tokens = new IERC20[](len);
        for (uint256 i = 0; i < len; ++i) {
            tokens[i] = mockTokens[i];
        }
        tokenInfo = new TokenInfo[](len);
        balancesRaw = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
            balancesRaw[i] = mockBalancesRaw[i];
        }
        lastBalancesLiveScaled18 = new uint256[](len);
    }

    function addLiquidity(AddLiquidityParams calldata params)
        external
        view
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData)
    {
        require(params.kind == AddLiquidityKind.DONATION, "mock addLiquidity kind");
        uint256 len = mockTokens.length;
        amountsIn = new uint256[](len);
        bptAmountOut = 0;
        returnData = "";
    }
}

contract SwapAndDepositToBodenseeTest is Test {
    MockVault internal vault;
    MockERC20 internal svZchf;
    MockERC20 internal sUsds;
    MockERC20 internal aumm;

    address internal bodensee = address(0xB0DE);
    address internal moduleAdmin = address(0xAD);
    address internal registry = address(0xCAFE);
    address internal gauge = address(0xBEEF);

    SwapAndDepositToBodensee internal helper;

    uint256 internal constant FEE_SVZCHF = 100e18;
    uint256 internal constant FEE_SUSDS = 125e18;

    function setUp() public {
        vault = new MockVault();
        svZchf = new MockERC20("svZCHF", "svZCHF");
        sUsds = new MockERC20("sUSDS", "sUSDS");
        aumm = new MockERC20("AuMM", "AuMM");

        IERC20[] memory three = new IERC20[](3);
        three[0] = IERC20(address(svZchf));
        three[1] = IERC20(address(sUsds));
        three[2] = IERC20(address(aumm));
        vault.setTokens(three);

        uint256[] memory bals = new uint256[](3);
        bals[0] = 1_000e18;
        bals[1] = 1_000e18;
        bals[2] = 1_000e18;
        vault.setBalancesRaw(bals);

        helper = new SwapAndDepositToBodensee(
            IVault(address(vault)),
            bodensee,
            IERC20(address(svZchf)),
            IERC20(address(sUsds)),
            moduleAdmin,
            address(this)
        );
        vault.setHelper(address(helper));
    }

    function _setupBothSettersFired() internal {
        vm.prank(moduleAdmin);
        helper.setVaultClassRegistry(registry);
        vm.prank(moduleAdmin);
        helper.setGaugeRegistry(gauge);
    }

    function testConstructorTokenNotInPoolRevertsForSvZchf() public {
        MockVault badVault = new MockVault();
        IERC20[] memory pair = new IERC20[](2);
        pair[0] = IERC20(address(sUsds));
        pair[1] = IERC20(address(aumm));
        badVault.setTokens(pair);

        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.TokenNotInPool.selector, IERC20(address(svZchf)))
        );
        new SwapAndDepositToBodensee(
            IVault(address(badVault)),
            bodensee,
            IERC20(address(svZchf)),
            IERC20(address(sUsds)),
            moduleAdmin,
            moduleAdmin
        );
    }

    function testConstructorTokenNotInPoolRevertsForSUsds() public {
        MockVault badVault = new MockVault();
        IERC20[] memory pair = new IERC20[](2);
        pair[0] = IERC20(address(svZchf));
        pair[1] = IERC20(address(aumm));
        badVault.setTokens(pair);

        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.TokenNotInPool.selector, IERC20(address(sUsds)))
        );
        new SwapAndDepositToBodensee(
            IVault(address(badVault)),
            bodensee,
            IERC20(address(svZchf)),
            IERC20(address(sUsds)),
            moduleAdmin,
            moduleAdmin
        );
    }

    function testUnauthorizedCallerRevertsBeforeAnySetter() public {
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.OnlyAuthorizedCaller.selector, address(this))
        );
        helper.swapAndDeposit(IERC20(address(svZchf)), FEE_SVZCHF);
    }

    function testUnauthorizedCallerRevertsRandomCallerAfterSetters() public {
        _setupBothSettersFired();
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.OnlyAuthorizedCaller.selector, address(0xDEAD))
        );
        vm.prank(address(0xDEAD));
        helper.swapAndDeposit(IERC20(address(svZchf)), FEE_SVZCHF);
    }

    function testRegistrySetCallerPassesModifier() public {
        vm.prank(moduleAdmin);
        helper.setVaultClassRegistry(registry);

        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.InvalidPayToken.selector, IERC20(address(0xBAD)))
        );
        vm.prank(registry);
        helper.swapAndDeposit(IERC20(address(0xBAD)), FEE_SVZCHF);
    }

    function testGaugeSetCallerPassesModifier() public {
        vm.prank(moduleAdmin);
        helper.setGaugeRegistry(gauge);

        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.InvalidPayToken.selector, IERC20(address(0xBAD)))
        );
        vm.prank(gauge);
        helper.swapAndDeposit(IERC20(address(0xBAD)), FEE_SVZCHF);
    }

    function testBothSetBothCallersPassModifier() public {
        _setupBothSettersFired();

        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.InvalidPayToken.selector, IERC20(address(0xBAD)))
        );
        vm.prank(registry);
        helper.swapAndDeposit(IERC20(address(0xBAD)), FEE_SVZCHF);

        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.InvalidPayToken.selector, IERC20(address(0xBAD)))
        );
        vm.prank(gauge);
        helper.swapAndDeposit(IERC20(address(0xBAD)), FEE_SVZCHF);
    }

    function testSecondSetVaultClassRegistryReverts() public {
        address otherAddr = address(0x1111);
        vm.prank(moduleAdmin);
        helper.setVaultClassRegistry(registry);

        vm.expectRevert(SwapAndDepositToBodensee.SetterAlreadyCalled.selector);
        vm.prank(moduleAdmin);
        helper.setVaultClassRegistry(otherAddr);
    }

    function testSecondSetGaugeRegistryReverts() public {
        address otherAddr = address(0x2222);
        vm.prank(moduleAdmin);
        helper.setGaugeRegistry(gauge);

        vm.expectRevert(SwapAndDepositToBodensee.SetterAlreadyCalled.selector);
        vm.prank(moduleAdmin);
        helper.setGaugeRegistry(otherAddr);
    }

    function testAdminBurnedAfterSecondSet() public {
        _setupBothSettersFired();
        assertEq(helper.moduleAdmin(), address(0));
    }

    function testInvalidPayTokenReverts() public {
        _setupBothSettersFired();

        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.InvalidPayToken.selector, IERC20(address(0xBAD)))
        );
        vm.prank(registry);
        helper.swapAndDeposit(IERC20(address(0xBAD)), 1);
    }

    function testZeroAmountReverts() public {
        _setupBothSettersFired();

        vm.expectRevert(SwapAndDepositToBodensee.ZeroAmount.selector);
        vm.prank(registry);
        helper.swapAndDeposit(IERC20(address(svZchf)), 0);
    }

    function testSvZchfUnderpayReverts() public {
        _setupBothSettersFired();

        vm.expectRevert(
            abi.encodeWithSelector(
                SwapAndDepositToBodensee.IncorrectAmount.selector,
                FEE_SVZCHF - 1,
                FEE_SVZCHF
            )
        );
        vm.prank(registry);
        helper.swapAndDeposit(IERC20(address(svZchf)), FEE_SVZCHF - 1);
    }

    function testSvZchfOverpayReverts() public {
        _setupBothSettersFired();

        vm.expectRevert(
            abi.encodeWithSelector(
                SwapAndDepositToBodensee.IncorrectAmount.selector,
                FEE_SVZCHF + 1,
                FEE_SVZCHF
            )
        );
        vm.prank(registry);
        helper.swapAndDeposit(IERC20(address(svZchf)), FEE_SVZCHF + 1);
    }

    function testSUsdsUnderpayReverts() public {
        _setupBothSettersFired();

        vm.expectRevert(
            abi.encodeWithSelector(
                SwapAndDepositToBodensee.IncorrectAmount.selector,
                FEE_SUSDS - 1,
                FEE_SUSDS
            )
        );
        vm.prank(registry);
        helper.swapAndDeposit(IERC20(address(sUsds)), FEE_SUSDS - 1);
    }

    function testSUsdsOverpayReverts() public {
        _setupBothSettersFired();

        vm.expectRevert(
            abi.encodeWithSelector(
                SwapAndDepositToBodensee.IncorrectAmount.selector,
                FEE_SUSDS + 1,
                FEE_SUSDS
            )
        );
        vm.prank(registry);
        helper.swapAndDeposit(IERC20(address(sUsds)), FEE_SUSDS + 1);
    }

    function testReentrancyGuardFires() public {
        vm.prank(moduleAdmin);
        helper.setVaultClassRegistry(address(vault));
        vm.prank(moduleAdmin);
        helper.setGaugeRegistry(gauge);
        vault.configureAttack(IERC20(address(svZchf)), FEE_SVZCHF);
        vault.enableReentrancyAttack();
        svZchf.mint(address(helper), FEE_SVZCHF);
        vm.expectRevert(SwapAndDepositToBodensee.ReentrancyGuard.selector);
        vm.prank(gauge);
        helper.swapAndDeposit(IERC20(address(svZchf)), FEE_SVZCHF);
    }

    function testNonVaultCallbackReverts() public {
        _setupBothSettersFired();

        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.OnlyVault.selector, address(this))
        );
        helper._swapAndDepositCallback(IERC20(address(svZchf)), FEE_SVZCHF);
    }

    function testCallbackPayloadMismatchReverts() public {
        _setupBothSettersFired();
        vault.enableCorruptCallback();
        svZchf.mint(address(helper), FEE_SVZCHF);

        vm.expectRevert(SwapAndDepositToBodensee.CallbackPayloadMismatch.selector);
        vm.prank(registry);
        helper.swapAndDeposit(IERC20(address(svZchf)), FEE_SVZCHF);
    }

    function testConstructorZeroDonateAuthorizerReverts() public {
        MockVault freshVault = new MockVault();
        IERC20[] memory three = new IERC20[](3);
        three[0] = IERC20(address(svZchf));
        three[1] = IERC20(address(sUsds));
        three[2] = IERC20(address(aumm));
        freshVault.setTokens(three);

        vm.expectRevert(SwapAndDepositToBodensee.ZeroAddress.selector);
        new SwapAndDepositToBodensee(
            IVault(address(freshVault)),
            bodensee,
            IERC20(address(svZchf)),
            IERC20(address(sUsds)),
            moduleAdmin,
            address(0)
        );
    }

    function testSetDonateAuthorizerOnlyByAuthorizer() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.OnlyDonateAuthorizer.selector, address(0xDEAD))
        );
        helper.setDonateAuthorizer(address(0xAAAA));
    }

    function testSetDonateAuthorizerZeroAddressReverts() public {
        vm.expectRevert(SwapAndDepositToBodensee.ZeroAddress.selector);
        helper.setDonateAuthorizer(address(0));
    }

    function testSetDonateAuthorizerHappyPath() public {
        address newAuth = address(0xAAAA);
        vm.expectEmit(true, true, false, true, address(helper));
        emit SwapAndDepositToBodensee.DonateAuthorizerSet(address(this), newAuth);
        helper.setDonateAuthorizer(newAuth);
        assertEq(helper.donateAuthorizer(), newAuth);

        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.OnlyDonateAuthorizer.selector, address(this))
        );
        helper.setDonateAuthorizer(address(0xBBBB));

        vm.prank(newAuth);
        helper.setDonateAuthorizer(address(0xBBBB));
        assertEq(helper.donateAuthorizer(), address(0xBBBB));
    }

    function testAddAuthorizedDonatorOnlyByAuthorizer() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.OnlyDonateAuthorizer.selector, address(0xDEAD))
        );
        helper.addAuthorizedDonator(address(0xD1));
    }

    function testAddAuthorizedDonatorZeroAddressReverts() public {
        vm.expectRevert(SwapAndDepositToBodensee.ZeroAddress.selector);
        helper.addAuthorizedDonator(address(0));
    }

    function testAddAuthorizedDonatorAlreadyAuthorizedReverts() public {
        helper.addAuthorizedDonator(address(0xD1));
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.DonatorAlreadyAuthorized.selector, address(0xD1))
        );
        helper.addAuthorizedDonator(address(0xD1));
    }

    function testAddAuthorizedDonatorHappyPath() public {
        vm.expectEmit(true, false, false, true, address(helper));
        emit SwapAndDepositToBodensee.AuthorizedDonatorAdded(address(0xD1));
        helper.addAuthorizedDonator(address(0xD1));
        assertTrue(helper.authorizedDonators(address(0xD1)));
    }

    function testRemoveAuthorizedDonatorOnlyByAuthorizer() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.OnlyDonateAuthorizer.selector, address(0xDEAD))
        );
        helper.removeAuthorizedDonator(address(0xD1));
    }

    function testRemoveAuthorizedDonatorNotAuthorizedReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.DonatorNotAuthorized.selector, address(0xD1))
        );
        helper.removeAuthorizedDonator(address(0xD1));
    }

    function testRemoveAuthorizedDonatorHappyPath() public {
        helper.addAuthorizedDonator(address(0xD1));
        vm.expectEmit(true, false, false, true, address(helper));
        emit SwapAndDepositToBodensee.AuthorizedDonatorRemoved(address(0xD1));
        helper.removeAuthorizedDonator(address(0xD1));
        assertFalse(helper.authorizedDonators(address(0xD1)));

        vm.prank(address(0xD1));
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.OnlyAuthorizedDonator.selector, address(0xD1))
        );
        helper.donate(IERC20(address(svZchf)), 50e18);
    }

    function testDonateOnlyAuthorizedDonatorReverts() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.OnlyAuthorizedDonator.selector, address(0xDEAD))
        );
        helper.donate(IERC20(address(svZchf)), 50e18);
    }

    function testDonateInvalidPayTokenReverts() public {
        helper.addAuthorizedDonator(address(0xD1));
        vm.prank(address(0xD1));
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndDepositToBodensee.InvalidPayToken.selector, IERC20(address(0xBAD)))
        );
        helper.donate(IERC20(address(0xBAD)), 50e18);
    }

    function testDonateZeroAmountReverts() public {
        helper.addAuthorizedDonator(address(0xD1));
        vm.prank(address(0xD1));
        vm.expectRevert(SwapAndDepositToBodensee.ZeroAmount.selector);
        helper.donate(IERC20(address(svZchf)), 0);
    }

    function testDonateReentrancyGuardFires() public {
        vm.prank(moduleAdmin);
        helper.setVaultClassRegistry(address(vault));
        vm.prank(moduleAdmin);
        helper.setGaugeRegistry(gauge);
        helper.addAuthorizedDonator(address(vault));
        vault.configureAttack(IERC20(address(svZchf)), FEE_SVZCHF);
        vault.enableReentrancyAttack();
        svZchf.mint(address(helper), 50e18);
        vm.expectRevert(SwapAndDepositToBodensee.ReentrancyGuard.selector);
        vm.prank(address(vault));
        helper.donate(IERC20(address(svZchf)), 50e18);
    }

    function testDonateCallbackReachedAtNonFeeEqualAmount() public {
        helper.addAuthorizedDonator(address(0xD1));
        svZchf.mint(address(helper), 50e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapAndDepositToBodensee.ReserveDeltaMismatch.selector,
                1_050e18,
                1_000e18
            )
        );
        vm.prank(address(0xD1));
        helper.donate(IERC20(address(svZchf)), 50e18);
    }

    function testDonateCallbackReachedAtOneWei() public {
        helper.addAuthorizedDonator(address(0xD1));
        svZchf.mint(address(helper), 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapAndDepositToBodensee.ReserveDeltaMismatch.selector,
                1_000e18 + 1,
                1_000e18
            )
        );
        vm.prank(address(0xD1));
        helper.donate(IERC20(address(svZchf)), 1);
    }
}
