// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {GaugeRegistry} from "src/gauge/GaugeRegistry.sol";
import {IGaugeEligibility} from "src/gauge/IGaugeEligibility.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockGaugeEligibility is IGaugeEligibility {
    mapping(address => bool) public eligibilityReturns;
    mapping(address => bytes) public revertReasons;

    function setEligibility(address pool, bool eligible) external {
        eligibilityReturns[pool] = eligible;
    }

    function setRevertReason(address pool, bytes calldata reason) external {
        revertReasons[pool] = reason;
    }

    function evaluateEligibility(address pool) external override returns (bool) {
        bytes memory reason = revertReasons[pool];
        if (reason.length > 0) {
            assembly {
                revert(add(reason, 0x20), mload(reason))
            }
        }
        return eligibilityReturns[pool];
    }

    function isEligible(address pool) external view override returns (bool) {
        return eligibilityReturns[pool];
    }

    function cohortOf(address) external view override returns (bool favored) {
        return false;
    }

    function snapshotEpoch() external view override returns (uint256) {
        return 0;
    }
}

contract MockSwapAndDeposit {
    IERC20 public lastPayToken;
    uint256 public lastAmount;
    address public lastCaller;
    uint256 public callCount;

    function swapAndDeposit(IERC20 payToken, uint256 amount) external {
        lastPayToken = payToken;
        lastAmount = amount;
        lastCaller = msg.sender;
        ++callCount;
    }
}

contract GaugeRegistryTest is Test {
    GaugeRegistry internal registry;
    MockGaugeEligibility internal eligibility;
    MockSwapAndDeposit internal swapper;
    MockERC20 internal svZchf;

    address internal constant GOVERNANCE = address(0x1111111111111111111111111111111111111111);
    address internal constant ALICE = address(0x2222222222222222222222222222222222222222);
    address internal constant BOB = address(0x3333333333333333333333333333333333333333);
    address internal constant POOL = address(0x4444444444444444444444444444444444444444);
    address internal constant POOL2 = address(0x5555555555555555555555555555555555555555);
    address internal constant POOL3 = address(0x6666666666666666666666666666666666666666);

    uint256 internal constant FEE = 100e18;

    function setUp() public {
        eligibility = new MockGaugeEligibility();
        swapper = new MockSwapAndDeposit();
        svZchf = new MockERC20("svZCHF", "svZCHF");
        registry = new GaugeRegistry(GOVERNANCE, address(eligibility), address(swapper), address(svZchf));

        vm.label(address(registry), "GaugeRegistry");
        vm.label(address(eligibility), "MockGaugeEligibility");
        vm.label(address(swapper), "MockSwapAndDeposit");
        vm.label(address(svZchf), "svZCHF");
        vm.label(GOVERNANCE, "GOVERNANCE");
        vm.label(ALICE, "ALICE");
        vm.label(BOB, "BOB");
    }

    function _fundAndApprove(address caller, uint256 amount) internal {
        svZchf.mint(caller, amount);
        vm.prank(caller);
        svZchf.approve(address(registry), amount);
    }

    function test_activateGauge_permissionless_happyPath() public {
        _fundAndApprove(ALICE, FEE);
        eligibility.setEligibility(POOL, true);

        uint256 aliceBalanceBefore = svZchf.balanceOf(ALICE);

        vm.expectEmit(true, false, false, true, address(registry));
        emit IGaugeRegistry.AntiSpamFeeRouted(ALICE, FEE);
        vm.expectEmit(true, true, false, false, address(registry));
        emit IGaugeRegistry.GaugeActivated(POOL, IGaugeRegistry.GaugeActivationPath.Permissionless);

        vm.prank(ALICE);
        registry.activateGauge(POOL);

        assertEq(svZchf.balanceOf(ALICE), aliceBalanceBefore - FEE);
        assertEq(svZchf.balanceOf(address(registry)), 0);
        assertEq(svZchf.balanceOf(address(swapper)), FEE);
        assertEq(swapper.callCount(), 1);
        assertTrue(swapper.lastPayToken() == IERC20(address(svZchf)));
        assertEq(swapper.lastAmount(), FEE);
        assertEq(swapper.lastCaller(), address(registry));
        assertTrue(registry.gaugeStatus(POOL) == IGaugeRegistry.GaugeStatus.Active);
        assertTrue(registry.isGaugeApproved(POOL));
    }

    function test_activateGauge_eligibilityReturnsFalse_retainsFee_nonRevert() public {
        _fundAndApprove(ALICE, FEE);
        eligibility.setEligibility(POOL, false);

        vm.expectEmit(true, false, false, true, address(registry));
        emit IGaugeRegistry.AntiSpamFeeRouted(ALICE, FEE);
        vm.expectEmit(true, false, false, true, address(registry));
        emit IGaugeRegistry.GaugeActivationFailed(POOL, bytes(""));

        vm.prank(ALICE);
        registry.activateGauge(POOL);

        assertEq(svZchf.balanceOf(address(swapper)), FEE);
        assertEq(swapper.callCount(), 1);
        assertTrue(registry.gaugeStatus(POOL) == IGaugeRegistry.GaugeStatus.None);
        assertFalse(registry.isGaugeApproved(POOL));
    }

    function test_activateGauge_eligibilityReverts_tryCatch_retainsFee_nonRevert() public {
        _fundAndApprove(ALICE, FEE);
        bytes memory reason = bytes("eligibility-revert-reason");
        eligibility.setRevertReason(POOL, reason);

        vm.expectEmit(true, false, false, true, address(registry));
        emit IGaugeRegistry.AntiSpamFeeRouted(ALICE, FEE);
        vm.expectEmit(true, false, false, true, address(registry));
        emit IGaugeRegistry.GaugeActivationFailed(POOL, reason);

        vm.prank(ALICE);
        registry.activateGauge(POOL);

        assertEq(svZchf.balanceOf(address(swapper)), FEE);
        assertEq(swapper.callCount(), 1);
        assertTrue(registry.gaugeStatus(POOL) == IGaugeRegistry.GaugeStatus.None);
        assertFalse(registry.isGaugeApproved(POOL));
    }

    function test_activateGauge_insufficientAllowance_revertsBeforeSwapper() public {
        vm.prank(ALICE);
        vm.expectRevert();
        registry.activateGauge(POOL);

        assertEq(swapper.callCount(), 0);
        assertTrue(registry.gaugeStatus(POOL) == IGaugeRegistry.GaugeStatus.None);
    }

    function test_activateGauge_alreadyGauged_secondActivationNoFee_noSecondSwapperCall() public {
        _fundAndApprove(ALICE, FEE * 2);
        eligibility.setEligibility(POOL, true);

        vm.prank(ALICE);
        registry.activateGauge(POOL);

        uint256 aliceBalanceAfterFirst = svZchf.balanceOf(ALICE);
        uint256 swapperCountBefore = swapper.callCount();

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IGaugeRegistry.AlreadyGauged.selector, POOL));
        registry.activateGauge(POOL);

        assertEq(svZchf.balanceOf(ALICE), aliceBalanceAfterFirst);
        assertEq(swapper.callCount(), swapperCountBefore);
        assertTrue(registry.gaugeStatus(POOL) == IGaugeRegistry.GaugeStatus.Active);
    }
}
