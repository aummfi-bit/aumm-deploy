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

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function approve(address, uint256) external pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }

    function mint(address, uint256) external {}

    function burn(address, uint256) external {}

    function distributor() external view returns (address) {
        return address(0);
    }

    function pool() external view returns (address) {
        return address(0);
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

    event VaultClassProposed(
        uint256 indexed proposalId,
        address indexed proposer,
        IVaultClassRegistry.AdmissionType admissionType,
        address admissionValue,
        bytes32 constraintsHash
    );

    event VaultClassVetoed(uint256 indexed proposalId, address indexed vetoer, uint256 weight);

    event VaultClassFinalized(uint256 indexed proposalId, address indexed admissionValue);

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

    function testGenesisTokenA_Admitted() public view {
        assertTrue(registry.isAdmittedClass(genesisTokenA));
    }

    function testGenesisTokenB_Admitted() public view {
        assertTrue(registry.isAdmittedClass(genesisTokenB));
    }

    function testGenesisAdmissionType_TokenA() public view {
        assertEq(uint256(registry.admissionType(genesisTokenA)), uint256(IVaultClassRegistry.AdmissionType.ImplementationAddress));
    }

    function testGenesisAdmissionType_TokenB() public view {
        assertEq(uint256(registry.admissionType(genesisTokenB)), uint256(IVaultClassRegistry.AdmissionType.FactoryAddress));
    }

    function testNonGenesisToken_NotAdmitted() public {
        assertFalse(registry.isAdmittedClass(makeAddr("stranger")));
    }

    function testConstructorZeroSvZCHF_Reverts() public {
        vm.expectRevert(VaultClassRegistry.ZeroAddress.selector);
        new VaultClassRegistry(
            IERC20(address(0)),
            SwapAndDepositToBodensee(address(mockHelper)),
            makeAddr("s1"),
            makeAddr("s2"),
            new address[](0),
            new IVaultClassRegistry.AdmissionType[](0)
        );
    }

    function testConstructorZeroHelper_Reverts() public {
        vm.expectRevert(VaultClassRegistry.ZeroAddress.selector);
        new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(0)),
            makeAddr("s1"),
            makeAddr("s2"),
            new address[](0),
            new IVaultClassRegistry.AdmissionType[](0)
        );
    }

    function testConstructorZeroAuMTSetter_Reverts() public {
        vm.expectRevert(VaultClassRegistry.ZeroAddress.selector);
        new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(mockHelper)),
            address(0),
            makeAddr("s2"),
            new address[](0),
            new IVaultClassRegistry.AdmissionType[](0)
        );
    }

    function testConstructorZeroGovernanceSetter_Reverts() public {
        vm.expectRevert(VaultClassRegistry.ZeroAddress.selector);
        new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(mockHelper)),
            makeAddr("s1"),
            address(0),
            new address[](0),
            new IVaultClassRegistry.AdmissionType[](0)
        );
    }

    function testGenesisLengthMismatch_Reverts() public {
        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("lenMismatchA");
        IVaultClassRegistry.AdmissionType[] memory types = new IVaultClassRegistry.AdmissionType[](2);
        types[0] = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        types[1] = IVaultClassRegistry.AdmissionType.ImplementationAddress;

        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.GenesisLengthMismatch.selector, uint256(1), uint256(2)));
        new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(mockHelper)),
            makeAddr("s1"),
            makeAddr("s2"),
            tokens,
            types
        );
    }

    function testGenesisOverflow_Reverts() public {
        uint256 cap = registry.MAX_GENESIS_CLASSES();
        address[] memory tokens = new address[](cap + 1);
        IVaultClassRegistry.AdmissionType[] memory types = new IVaultClassRegistry.AdmissionType[](cap + 1);
        for (uint256 i = 0; i < cap + 1; ++i) {
            tokens[i] = makeAddr(vm.toString(i));
            types[i] = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        }

        vm.expectRevert(
            abi.encodeWithSelector(VaultClassRegistry.GenesisOverflow.selector, uint256(cap + 1), cap)
        );
        new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(mockHelper)),
            makeAddr("s1"),
            makeAddr("s2"),
            tokens,
            types
        );
    }

    function testGenesisDuplicate_Reverts() public {
        address dup = makeAddr("dupGenesis");
        address[] memory tokens = new address[](2);
        tokens[0] = dup;
        tokens[1] = dup;
        IVaultClassRegistry.AdmissionType[] memory types = new IVaultClassRegistry.AdmissionType[](2);
        types[0] = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        types[1] = IVaultClassRegistry.AdmissionType.ImplementationAddress;

        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.DuplicateGenesisToken.selector, dup));
        new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(mockHelper)),
            makeAddr("s1"),
            makeAddr("s2"),
            tokens,
            types
        );
    }

    function testGenesisBytecodeHash_Reverts() public {
        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("bhGenesis");
        IVaultClassRegistry.AdmissionType[] memory types = new IVaultClassRegistry.AdmissionType[](1);
        types[0] = IVaultClassRegistry.AdmissionType.BytecodeHash;

        vm.expectRevert(VaultClassRegistry.BytecodeHashAdmissionDeferred.selector);
        new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(mockHelper)),
            makeAddr("s1"),
            makeAddr("s2"),
            tokens,
            types
        );
    }

    function testGenesisZeroAddress_Reverts() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0);
        IVaultClassRegistry.AdmissionType[] memory types = new IVaultClassRegistry.AdmissionType[](1);
        types[0] = IVaultClassRegistry.AdmissionType.ImplementationAddress;

        vm.expectRevert(VaultClassRegistry.ZeroAddress.selector);
        new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(mockHelper)),
            makeAddr("s1"),
            makeAddr("s2"),
            tokens,
            types
        );
    }

    function _propose(address admissionValue) internal returns (uint256 proposalId) {
        vm.prank(proposer);
        proposalId = registry.proposeVaultClass(
            IVaultClassRegistry.AdmissionType.ImplementationAddress,
            admissionValue,
            bytes32(0)
        );
    }

    function _warpPastWindow() internal {
        vm.roll(block.number + registry.VETO_WINDOW_BLOCKS() + 1);
    }

    function testPropose_Success() public {
        address admissionValue = makeAddr("newToken");
        uint256 balBefore = svZCHF.balanceOf(proposer);
        _propose(admissionValue);
        assertEq(svZCHF.balanceOf(proposer), balBefore - registry.PROPOSAL_BOND_SVZCHF());
        assertEq(svZCHF.balanceOf(proposer), PROPOSER_SVZCHF_BALANCE - registry.PROPOSAL_BOND_SVZCHF());
        assertEq(registry.nextProposalId(), 1);
        assertEq(mockHelper.donateCallCount(), 1);
        assertEq(mockHelper.lastDonateAmount(), registry.PROPOSAL_BOND_SVZCHF());
        assertEq(svZCHF.balanceOf(address(mockHelper)), registry.PROPOSAL_BOND_SVZCHF());
        (,,,,, bool finalized, bool revoked) = registry.proposals(0);
        assertFalse(finalized);
        assertFalse(revoked);
    }

    function testVeto_SufficientWeight_KillsProposal() public {
        address admissionValue = makeAddr("vetoKillAdmission");
        _propose(admissionValue);
        address vetoer = makeAddr("vetoer");
        mockAuMT.setGovernanceWeight(vetoer, 100_000e18);
        vm.prank(vetoer);
        registry.vetoProposal(0);
        (,,,,, bool finalized, bool revoked) = registry.proposals(0);
        assertTrue(finalized);
        assertTrue(revoked);
        assertFalse(registry.admittedClasses(admissionValue));
    }

    function testVeto_InsufficientWeight_Accumulates() public {
        address admissionValue = makeAddr("insufficientVetoAdmission");
        _propose(admissionValue);
        address vetoer = makeAddr("weakVetoer");
        mockAuMT.setGovernanceWeight(vetoer, 99_999e18);
        vm.prank(vetoer);
        registry.vetoProposal(0);
        (,,,, uint256 vetoSupp, bool finalized, bool revoked) = registry.proposals(0);
        assertFalse(finalized);
        assertFalse(revoked);
        assertEq(vetoSupp, 99_999e18);
    }

    function testVeto_Cumulative_CrossesThreshold() public {
        address admissionValue = makeAddr("cumulativeVetoAdmission");
        _propose(admissionValue);
        address vetoer1 = makeAddr("vetoer1");
        address vetoer2 = makeAddr("vetoer2");
        mockAuMT.setGovernanceWeight(vetoer1, 50_000e18);
        mockAuMT.setGovernanceWeight(vetoer2, 50_000e18);
        vm.prank(vetoer1);
        registry.vetoProposal(0);
        (,,,,, bool finalizedAfterFirst, bool revokedAfterFirst) = registry.proposals(0);
        assertFalse(finalizedAfterFirst);
        assertFalse(revokedAfterFirst);
        vm.prank(vetoer2);
        registry.vetoProposal(0);
        (,,,,, bool finalized, bool revoked) = registry.proposals(0);
        assertTrue(finalized);
        assertTrue(revoked);
    }

    function testFinalize_AfterWindow_AdmitsClass() public {
        address admissionValue = makeAddr("finalizeAdmission");
        _propose(admissionValue);
        _warpPastWindow();
        registry.finalizeProposal(0);
        (,,,,, bool finalized, bool revoked) = registry.proposals(0);
        assertTrue(finalized);
        assertFalse(revoked);
        assertTrue(registry.admittedClasses(admissionValue));
        assertEq(uint256(registry.admissionTypes(admissionValue)), uint256(IVaultClassRegistry.AdmissionType.ImplementationAddress));
    }

    function testVeto_AfterWindow_Reverts() public {
        address admissionValue = makeAddr("afterWindow");
        uint256 proposalId = _propose(admissionValue);
        address vetoer = makeAddr("lateVetoer");
        _warpPastWindow();
        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.VetoWindowExpired.selector, proposalId));
        vm.prank(vetoer);
        registry.vetoProposal(proposalId);
    }

    function testFinalize_BeforeWindow_Reverts() public {
        address admissionValue = makeAddr("beforeWindow");
        uint256 proposalId = _propose(admissionValue);
        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.VetoWindowOpen.selector, proposalId));
        registry.finalizeProposal(proposalId);
    }

    function testVeto_AlreadyFinalized_Reverts() public {
        address admissionValue = makeAddr("doubleVeto");
        uint256 proposalId = _propose(admissionValue);
        address vetoer = makeAddr("vetoerFinalize");
        mockAuMT.setGovernanceWeight(vetoer, 100_000e18);
        vm.prank(vetoer);
        registry.vetoProposal(proposalId);
        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.ProposalAlreadyFinalized.selector, proposalId));
        vm.prank(vetoer);
        registry.vetoProposal(proposalId);
    }

    function testFinalize_AlreadyFinalized_Reverts() public {
        address admissionValue = makeAddr("doubleFinalize");
        uint256 proposalId = _propose(admissionValue);
        _warpPastWindow();
        registry.finalizeProposal(proposalId);
        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.ProposalAlreadyFinalized.selector, proposalId));
        registry.finalizeProposal(proposalId);
    }

    function testRevoke_NonGovernance_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.OnlyGovernance.selector, address(this)));
        registry.revokeVaultClass(genesisTokenA);
    }

    function testRevoke_ClassNotAdmitted_Reverts() public {
        address stranger = makeAddr("stranger");
        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.ClassNotAdmitted.selector, stranger));
        vm.prank(governance);
        registry.revokeVaultClass(stranger);
    }

    function testRevoke_GenesisToken_Success() public {
        vm.prank(governance);
        registry.revokeVaultClass(genesisTokenA);
        assertFalse(registry.isAdmittedClass(genesisTokenA));
    }

    function testPropose_BytecodeHash_Reverts() public {
        vm.expectRevert(VaultClassRegistry.BytecodeHashAdmissionDeferred.selector);
        vm.prank(proposer);
        registry.proposeVaultClass(IVaultClassRegistry.AdmissionType.BytecodeHash, makeAddr("bhAdmission"), bytes32(0));
    }

    function testPropose_ClassAlreadyAdmitted_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.ClassAlreadyAdmitted.selector, genesisTokenA));
        vm.prank(proposer);
        registry.proposeVaultClass(
            IVaultClassRegistry.AdmissionType.ImplementationAddress,
            genesisTokenA,
            bytes32(0)
        );
    }

    function testSetAuMT_ReCall_Reverts() public {
        vm.expectRevert(VaultClassRegistry.OnlyAuMTSetter.selector);
        vm.prank(auMTSetter);
        registry.setAuMT(address(mockAuMT));
    }

    function testSetGovernanceContract_ReCall_Reverts() public {
        vm.expectRevert(VaultClassRegistry.OnlyGovernanceSetter.selector);
        vm.prank(governanceSetter);
        registry.setGovernanceContract(governance);
    }

    function testSetAuMT_ZeroAddress_Reverts() public {
        address setter = makeAddr("bareAuMTSetter");
        VaultClassRegistry bare = new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(mockHelper)),
            setter,
            makeAddr("bareGovSetterAuMT"),
            new address[](0),
            new IVaultClassRegistry.AdmissionType[](0)
        );
        vm.expectRevert(VaultClassRegistry.ZeroAddress.selector);
        vm.prank(setter);
        bare.setAuMT(address(0));
    }

    function testSetGovernanceContract_ZeroAddress_Reverts() public {
        address setter = makeAddr("bareGovSetter");
        VaultClassRegistry bare = new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(mockHelper)),
            makeAddr("bareAuMTZeroGov"),
            setter,
            new address[](0),
            new IVaultClassRegistry.AdmissionType[](0)
        );
        vm.expectRevert(VaultClassRegistry.ZeroAddress.selector);
        vm.prank(setter);
        bare.setGovernanceContract(address(0));
    }

    function testVeto_PreSetAuMT_Reverts() public {
        VaultClassRegistry bare = new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(mockHelper)),
            makeAddr("unusedAuMTSetter"),
            makeAddr("unusedGovSetter"),
            new address[](0),
            new IVaultClassRegistry.AdmissionType[](0)
        );
        vm.prank(proposer);
        svZCHF.approve(address(bare), type(uint256).max);
        vm.prank(proposer);
        bare.proposeVaultClass(
            IVaultClassRegistry.AdmissionType.ImplementationAddress,
            makeAddr("preAuMTAdmission"),
            bytes32(0)
        );
        vm.expectRevert();
        bare.vetoProposal(0);
    }

    function testRevoke_PreSetGovernanceContract_Reverts() public {
        address genesisToken = makeAddr("bareGenesis");
        address[] memory tokens = new address[](1);
        tokens[0] = genesisToken;
        IVaultClassRegistry.AdmissionType[] memory types = new IVaultClassRegistry.AdmissionType[](1);
        types[0] = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        VaultClassRegistry bare = new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(mockHelper)),
            makeAddr("bareAuMTRevoke"),
            makeAddr("bareGovSetterRevoke"),
            tokens,
            types
        );
        vm.expectRevert(abi.encodeWithSelector(VaultClassRegistry.OnlyGovernance.selector, address(this)));
        bare.revokeVaultClass(genesisToken);
    }

    function testPropose_EmitsVaultClassProposed() public {
        address admissionValue = makeAddr("emitPropose");
        vm.expectEmit(true, true, false, true);
        emit VaultClassProposed(0, proposer, IVaultClassRegistry.AdmissionType.ImplementationAddress, admissionValue, bytes32(0));
        _propose(admissionValue);
    }

    function testVeto_EmitsVaultClassVetoed() public {
        address admissionValue = makeAddr("emitVeto");
        uint256 proposalId = 0;
        _propose(admissionValue);
        address vetoer = makeAddr("emitVetoer");
        mockAuMT.setGovernanceWeight(vetoer, 50_000e18);
        vm.expectEmit(true, true, false, true);
        emit VaultClassVetoed(proposalId, vetoer, 50_000e18);
        vm.prank(vetoer);
        registry.vetoProposal(proposalId);
    }

    function testFinalize_EmitsVaultClassFinalized() public {
        address admissionValue = makeAddr("emitFinalize");
        uint256 proposalId = 0;
        _propose(admissionValue);
        _warpPastWindow();
        vm.expectEmit(true, true, false, false);
        emit VaultClassFinalized(proposalId, admissionValue);
        registry.finalizeProposal(proposalId);
    }
}
