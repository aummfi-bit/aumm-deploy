// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {VaultClassRegistry} from "src/gauge/VaultClassRegistry.sol";
import {IVaultClassRegistry} from "src/gauge/IVaultClassRegistry.sol";
import {IAuMT} from "src/token/IAuMT.sol";
import {SwapAndDepositToBodensee} from "src/gauge/SwapAndDepositToBodensee.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Passive recorder for `donate` calls in VaultClassRegistry tests.
contract MockSwapAndDepositToBodensee {
    IERC20 public lastDonateToken;

    uint256 public lastDonateAmount;

    uint256 public donateCallCount;

    function donate(IERC20 payToken, uint256 amount) external {
        lastDonateToken = payToken;
        lastDonateAmount = amount;
        donateCallCount++;
    }
}

/// @notice Minimal IAuMT double with configurable weights for VaultClassRegistry coverage.
contract MockAuMT is IAuMT {
    mapping(address => uint256) public governanceWeights;

    uint256 private _totalSupply;

    function setTotalSupply(uint256 supply_) external {
        _totalSupply = supply_;
    }

    function setGovernanceWeight(address holder, uint256 weight) external {
        governanceWeights[holder] = weight;
    }

    function governanceWeight(address holder) external view returns (uint256) {
        return governanceWeights[holder];
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address) external view returns (uint256) {
        return 0;
    }

    function allowance(address, address) external view returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external returns (bool) {
        return false;
    }

    function approve(address, uint256) external returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external returns (bool) {
        return false;
    }
}

/// @notice Harness scaffold for VaultClassRegistry proposal-veto-finalize tests (G1.16 split).
contract VaultClassRegistryTest is Test {
    MockERC20 internal svZCHF;

    MockSwapAndDepositToBodensee internal mockHelper;

    MockAuMT internal mockAuMT;

    VaultClassRegistry internal registry;

    address internal auMTSetter;

    address internal governanceSetter;

    address internal governance;

    address internal proposer;

    address internal genesisTokenA;

    address internal genesisTokenB;

    uint256 internal constant INITIAL_AUMT_SUPPLY = 1_000_000e18;

    uint256 internal constant PROPOSER_SVZCHF_BALANCE = 100_000e18;

    function setUp() public {
        svZCHF = new MockERC20("svZCHF", "svZCHF", 18);
        mockHelper = new MockSwapAndDepositToBodensee();
        mockAuMT = new MockAuMT();
        mockAuMT.setTotalSupply(INITIAL_AUMT_SUPPLY);
        auMTSetter = makeAddr("auMTSetter");
        governanceSetter = makeAddr("governanceSetter");
        governance = makeAddr("governance");
        proposer = makeAddr("proposer");
        genesisTokenA = makeAddr("genesisTokenA");
        genesisTokenB = makeAddr("genesisTokenB");

        address[] memory tokens = new address[](2);
        tokens[0] = genesisTokenA;
        tokens[1] = genesisTokenB;

        IVaultClassRegistry.AdmissionType[] memory types = new IVaultClassRegistry.AdmissionType[](2);
        types[0] = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        types[1] = IVaultClassRegistry.AdmissionType.FactoryAddress;

        registry = new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(mockHelper)),
            auMTSetter,
            governanceSetter,
            tokens,
            types
        );

        vm.prank(auMTSetter);
        registry.setAuMT(address(mockAuMT));

        vm.prank(governanceSetter);
        registry.setGovernanceContract(governance);

        svZCHF.mint(proposer, PROPOSER_SVZCHF_BALANCE);

        vm.prank(proposer);
        svZCHF.approve(address(registry), type(uint256).max);
    }
}
