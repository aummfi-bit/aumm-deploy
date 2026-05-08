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

    // -------------------------------------------------------------------------
    // Struct
    // -------------------------------------------------------------------------

    /**
     * @notice Lifecycle record for one vault-class admission proposal (G-D9).
     */
    struct VaultClassProposal {
        IVaultClassRegistry.AdmissionType admissionType; // fingerprint kind applying to admissionValue below
        /// @notice For `AdmissionType.ImplementationAddress` — ERC-4626 implementation; factory address for FactoryAddress; sentinel/zero for BytecodeHash (constraints-only path).
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

    // -------------------------------------------------------------------------
    // Custom errors
    // -------------------------------------------------------------------------

    error OnlyGovernance(address caller);

    error ZeroAddress();

    error InvalidAdmissionType();

    error ProposalAlreadyFinalized(uint256 proposalId);

    error VetoWindowExpired(uint256 proposalId);

    error VetoWindowOpen(uint256 proposalId);

    error InsufficientVetoWeight(uint256 weight, uint256 required);

    error ClassAlreadyAdmitted(address class);

    error ClassNotAdmitted(address class);

    error SetterAlreadyCalled();
}
