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
}
