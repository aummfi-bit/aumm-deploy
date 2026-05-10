// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVaultClassRegistry} from "./IVaultClassRegistry.sol";
import {SwapAndDepositToBodensee} from "./SwapAndDepositToBodensee.sol";
import {IAuMT} from "../token/IAuMT.sol";

/**
 * @title VaultClassRegistry
 * @notice Frankencoin-inspired propose-veto-finalize-revoke registry for ERC-4626 vault classes counted toward the 52% Quality Gate numerator per G-D8 + G-D9.
 * @dev Constructor body, propose / veto / finalize / revoke functions, setters, and `IVaultClassRegistry` inheritance + view bridges land at G1.12+;
 *      this scaffold ships only types / state / immutables / constants / errors / events surface per G-D9 + G-D19 (G1.9 tunables lock).
 */
contract VaultClassRegistry {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice bond token, anchored at construction
    IERC20 public immutable svZCHF;

    /// @notice bond router per G-D9 + G-D12
    SwapAndDepositToBodensee public immutable helper;

    // -------------------------------------------------------------------------
    // Constants (G-D19 tunables lock)
    // -------------------------------------------------------------------------

    /// @notice svZCHF bond posted with each `proposeVaultClass` call (G-D9 / G-D19).
    uint256 public constant PROPOSAL_BOND_SVZCHF = 1_000e18;

    /// @notice Minimum cumulative AuMT veto weight (basis points of `auMT.totalSupply()`) to kill a proposal (G-D9 / G-D19).
    uint256 public constant VETO_THRESHOLD_BPS = 1000;

    /// @notice Length of the veto window in blocks, measured from `createdBlock` (G-D9 / G-D19).
    uint256 public constant VETO_WINDOW_BLOCKS = 201_600;

    /// @notice Maximum number of genesis classes accepted at construction per G-D20.
    uint256 public constant MAX_GENESIS_CLASSES = 32;

    // -------------------------------------------------------------------------
    // Struct
    // -------------------------------------------------------------------------

    /**
     * @notice Lifecycle record for one vault-class admission proposal (G-D9).
     */
    struct VaultClassProposal {
        IVaultClassRegistry.AdmissionType admissionType; // fingerprint kind applying to admissionValue below
        /// @notice For `AdmissionType.ImplementationAddress` — ERC-4626 implementation; factory address for FactoryAddress; reserved for future use under BytecodeHash (deferred at G1.13-pre-B).
        address admissionValue;
        /// @notice Hash of off-chain / registry constraints associated with the fingerprint (G-D9).
        bytes32 constraintsHash;
        /// @notice `block.number` snapshot when the proposal was created.
        uint256 createdBlock;
        /// @notice Cumulative AuMT veto weight accrued across successive `vetoProposal` calls in the veto window (G-D9).
        uint256 vetoSupport;
        /// @notice Set when the proposal clears (successful veto ⇒ admitted+revoked, or finalize without veto).
        bool finalized;
        /// @notice True only when a veto succeeded (proposal killed and class revoked if previously admitted); when true, `finalized` is also true.
        bool revoked;
    }

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    mapping(uint256 => VaultClassProposal) public proposals;

    uint256 public nextProposalId;

    mapping(address => bool) public admittedClasses;

    mapping(address => IVaultClassRegistry.AdmissionType) public admissionTypes;

    // -------------------------------------------------------------------------
    // Forward-dep placeholder + one-shot setter slots (F-D20–F-D23 pattern)
    // -------------------------------------------------------------------------

    /// @notice wired post-deploy via `setAuMT` (G1.12)
    IAuMT public auMT;

    /// @notice wired post-deploy via `setGovernanceContract` (G1.12)
    address public governanceContract;

    /// @notice one-shot, cleared on first set
    address public auMTSetter;

    /// @notice one-shot, cleared on first set
    address public governanceSetter;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event VaultClassProposed(
        uint256 indexed proposalId,
        address indexed proposer,
        IVaultClassRegistry.AdmissionType admissionType,
        address admissionValue,
        bytes32 constraintsHash
    );

    event VaultClassVetoed(
        uint256 indexed proposalId,
        address indexed vetoer,
        uint256 weight
    );

    event VaultClassFinalized(uint256 indexed proposalId, address indexed admissionValue);

    event VaultClassRevoked(address indexed admissionValue);

    /// @notice Emitted once per genesis token admitted in the constructor per G-D20; no proposalId (genesis classes bypass the proposal flow).
    event GenesisClassAdmitted(address indexed token, IVaultClassRegistry.AdmissionType admissionType);

    // -------------------------------------------------------------------------
    // Custom errors
    // -------------------------------------------------------------------------

    error OnlyGovernance(address caller);

    error ZeroAddress();

    error InvalidAdmissionType();

    error BytecodeHashAdmissionDeferred();

    error ProposalAlreadyFinalized(uint256 proposalId);

    error VetoWindowExpired(uint256 proposalId);

    error VetoWindowOpen(uint256 proposalId);

    error InsufficientVetoWeight(uint256 weight, uint256 required);

    error ClassAlreadyAdmitted(address class);

    error ClassNotAdmitted(address class);

    error SetterAlreadyCalled();

    error GenesisLengthMismatch(uint256 tokensLen, uint256 typesLen);

    error GenesisOverflow(uint256 provided, uint256 cap);

    error DuplicateGenesisToken(address token);

    error OnlyAuMTSetter();

    error OnlyGovernanceSetter();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @notice Initializes bond token, Bodensee helper, one-shot setter authorities, and optional genesis admits.
    constructor(
        IERC20 svZCHF_,
        SwapAndDepositToBodensee helper_,
        address auMTSetter_,
        address governanceSetter_,
        address[] memory genesisTokens,
        IVaultClassRegistry.AdmissionType[] memory genesisTypes
    ) {
        if (address(svZCHF_) == address(0)) revert ZeroAddress();
        if (address(helper_) == address(0)) revert ZeroAddress();
        if (auMTSetter_ == address(0)) revert ZeroAddress();
        if (governanceSetter_ == address(0)) revert ZeroAddress();

        svZCHF = svZCHF_;
        helper = helper_;
        auMTSetter = auMTSetter_;
        governanceSetter = governanceSetter_;

        if (genesisTokens.length != genesisTypes.length) revert GenesisLengthMismatch(genesisTokens.length, genesisTypes.length);
        if (genesisTokens.length > MAX_GENESIS_CLASSES) revert GenesisOverflow(genesisTokens.length, MAX_GENESIS_CLASSES);

        for (uint256 i = 0; i < genesisTokens.length; ++i) {
            if (genesisTokens[i] == address(0)) revert ZeroAddress();
            if (genesisTypes[i] == IVaultClassRegistry.AdmissionType.BytecodeHash) revert BytecodeHashAdmissionDeferred();
            if (admittedClasses[genesisTokens[i]]) revert DuplicateGenesisToken(genesisTokens[i]);
            admittedClasses[genesisTokens[i]] = true;
            admissionTypes[genesisTokens[i]] = genesisTypes[i];
            emit GenesisClassAdmitted(genesisTokens[i], genesisTypes[i]);
        }
    }

    // -------------------------------------------------------------------------
    // One-shot setters (F-D23 pattern)
    // -------------------------------------------------------------------------

    /// @notice Wires AuMT from the designated setter and seals the auMTSetter slot.
    function setAuMT(address auMT_) external {
        if (msg.sender != auMTSetter) revert OnlyAuMTSetter();
        if (auMT_ == address(0)) revert ZeroAddress();
        auMT = IAuMT(auMT_);
        auMTSetter = address(0);
    }

    /// @notice Wires governance from the designated setter and seals the governanceSetter slot.
    function setGovernanceContract(address governanceContract_) external {
        if (msg.sender != governanceSetter) revert OnlyGovernanceSetter();
        if (governanceContract_ == address(0)) revert ZeroAddress();
        governanceContract = governanceContract_;
        governanceSetter = address(0);
    }

    // -------------------------------------------------------------------------
    // Public proposal entry point
    // -------------------------------------------------------------------------

    /// @notice Opens a vault-class proposal: pulls svZCHF bond per G-D12, forwards to Bodensee via `helper.donate` per G-D21 (registry owns magnitude).
    /// @dev BytecodeHash proposals revert per G-D9 deferral-with-teeth; admission mutates only at finalize (G1.14).
    function proposeVaultClass(
        IVaultClassRegistry.AdmissionType admissionType,
        address admissionValue,
        bytes32 constraintsHash
    ) external returns (uint256 proposalId) {
        if (admissionType == IVaultClassRegistry.AdmissionType.BytecodeHash) revert BytecodeHashAdmissionDeferred();
        if (admissionValue == address(0)) revert ZeroAddress();
        if (admittedClasses[admissionValue]) revert ClassAlreadyAdmitted(admissionValue);
        svZCHF.safeTransferFrom(msg.sender, address(this), PROPOSAL_BOND_SVZCHF);
        svZCHF.safeTransfer(address(helper), PROPOSAL_BOND_SVZCHF);
        helper.donate(svZCHF, PROPOSAL_BOND_SVZCHF);
        proposalId = nextProposalId++;
        proposals[proposalId] = VaultClassProposal({
            admissionType: admissionType,
            admissionValue: admissionValue,
            constraintsHash: constraintsHash,
            createdBlock: block.number,
            vetoSupport: 0,
            finalized: false,
            revoked: false
        });
        emit VaultClassProposed(proposalId, msg.sender, admissionType, admissionValue, constraintsHash);
    }

    // -------------------------------------------------------------------------
    // Veto + finalize entry points
    // -------------------------------------------------------------------------

    /// @notice Records AuMT-weighted veto support during the window per G-D9 / G-D19; crossing threshold auto-revokes the proposal.
    /// @dev Emits `VaultClassVetoed` on every call; bond remains in Bodensee on successful veto per G-D9.
    function vetoProposal(uint256 proposalId) external {
        VaultClassProposal storage proposal = proposals[proposalId];
        if (proposal.finalized || proposal.revoked) revert ProposalAlreadyFinalized(proposalId);
        if (block.number > proposal.createdBlock + VETO_WINDOW_BLOCKS) revert VetoWindowExpired(proposalId);
        uint256 weight = auMT.governanceWeight(msg.sender);
        proposal.vetoSupport += weight;
        if ((proposal.vetoSupport * 10_000) / auMT.totalSupply() >= VETO_THRESHOLD_BPS) {
            proposal.finalized = true;
            proposal.revoked = true;
        }
        emit VaultClassVetoed(proposalId, msg.sender, weight);
    }

    /// @notice Admits the class after veto window expiry per G-D9 auto-finalize; permissionless caller.
    /// @dev Mutates `admittedClasses` / `admissionTypes`; emits `VaultClassFinalized` (G-D19 window constant).
    function finalizeProposal(uint256 proposalId) external {
        VaultClassProposal storage proposal = proposals[proposalId];
        if (proposal.finalized) revert ProposalAlreadyFinalized(proposalId);
        if (block.number <= proposal.createdBlock + VETO_WINDOW_BLOCKS) revert VetoWindowOpen(proposalId);
        proposal.finalized = true;
        admittedClasses[proposal.admissionValue] = true;
        admissionTypes[proposal.admissionValue] = proposal.admissionType;
        emit VaultClassFinalized(proposalId, proposal.admissionValue);
    }
}
