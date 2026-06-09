// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {IVotingWeight} from "./IVotingWeight.sol";
import {IGaugeRegistry} from "../ccb/IGaugeRegistry.sol";
import {IMiliariumSlotRegistry} from "../registry/IMiliariumSlotRegistry.sol";
import {AureumTime} from "../lib/AureumTime.sol";
import {SwapAndDepositToBodensee} from "../gauge/SwapAndDepositToBodensee.sol";

/**
 * @title AureumGovernance
 * @notice On-chain governance for three proposal types — gauge challenge, composition challenge, and
 *         fee change — with snapshot voting, a post-success execution timelock, and voter weight
 *         sourced from K3 `VotingWeight` (F-9 dampening consumed there, not reimplemented here).
 * @dev Standalone contract — no `IAureumGovernance` interface; registries gate on a
 *      `governanceContract` address, not a typed interface. K-D6a—K-D6f locked at K4 pre-flight.
 *      K4.1 = scaffold only; function bodies land in K4.2—K4.5 (`propose`, `castVote`, `state`,
 *      `queue`, `execute`).
 */
contract AureumGovernance {
    using SafeERC20 for IERC20;

    uint256 internal constant VOTING_PERIOD_BLOCKS = AureumTime.BLOCKS_PER_EPOCH;
    uint256 internal constant EXECUTION_TIMELOCK_BLOCKS = 2 * AureumTime.BLOCKS_PER_DAY;
    uint256 internal constant EXECUTION_GRACE_BLOCKS = AureumTime.BLOCKS_PER_EPOCH;
    uint256 internal constant QUORUM_BPS = 2_000;
    uint256 internal constant PROPOSAL_DEPOSIT_SVZCHF = 1_000e18;
    uint256 internal constant PROPOSAL_DEPOSIT_SUSDS = 1_250e18;
    uint256 internal constant SWAP_FEE_MIN = 1e14;
    uint256 internal constant SWAP_FEE_MAX = 3e15;
    uint256 internal constant FEE_CHANGE_COOLDOWN_BLOCKS = AureumTime.BLOCKS_PER_EPOCH;

    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    IVotingWeight public immutable VOTING_WEIGHT;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    IGaugeRegistry public immutable GAUGE_REGISTRY;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    IMiliariumSlotRegistry public immutable SLOT_REGISTRY;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    IVault public immutable VAULT;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    SwapAndDepositToBodensee public immutable BODENSEE_CHANNEL;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    IERC20 public immutable SVZCHF;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    IERC20 public immutable SUSDS;
    // Rationale: Aureum immutables follow Balancer V3 SCREAMING_CASE convention
    // for protocol-critical addresses, matching upstream-forked files. See
    // foundry.toml [lint] ignore for the same decision on AureumVaultFactory
    // and AureumProtocolFeeController.
    // slither-disable-next-line naming-convention
    address public immutable BODENSEE_POOL;

    enum ProposalType {
        GaugeChallenge,
        CompositionChallenge,
        FeeChange
    }

    enum ProposalState {
        Active,
        Defeated,
        Succeeded,
        Queued,
        Executed,
        Expired
    }

    struct Proposal {
        address proposer;
        ProposalType proposalType;
        uint256 startBlock;
        uint256 endBlock;
        uint256 snapshotTotalSupply;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 eta;
        bool executed;
        address targetPool;
        address newPool;
        uint256 slot;
        uint256 newFee;
    }

    uint256 public proposalCount;
    mapping(uint256 => Proposal) internal _proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(address => uint256) public lastFeeChangeBlock;

    event ProposalCreated(
        uint256 indexed proposalId,
        ProposalType proposalType,
        address indexed proposer,
        uint256 startBlock,
        uint256 endBlock,
        uint256 snapshotTotalSupply
    );
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalQueued(uint256 indexed proposalId, uint256 eta);
    event ProposalExecuted(uint256 indexed proposalId);

    error ZeroAddress();
    error InvalidPayToken();
    error ProposalNotActive(uint256 proposalId);
    error AlreadyVoted(address voter, uint256 proposalId);
    error ProposalNotSucceeded(uint256 proposalId);
    error TimelockNotMet(uint256 eta, uint256 currentBlock);
    error GracePeriodExpired(uint256 proposalId);
    error ProposalAlreadyExecuted(uint256 proposalId);
    error InvalidFeeTarget(address pool);
    error FeeCooldownActive(address pool);
    error InvalidFeeValue(uint256 fee);
    error InvalidGaugeTarget(address pool);
    error InvalidCompositionTarget(uint256 slot);

    constructor(
        IVotingWeight votingWeight_,
        IGaugeRegistry gaugeRegistry_,
        IMiliariumSlotRegistry slotRegistry_,
        IVault vault_,
        SwapAndDepositToBodensee bodenseeChannel_,
        IERC20 svZchf_,
        IERC20 sUsds_,
        address bodenseePool_
    ) {
        if (address(votingWeight_) == address(0)) revert ZeroAddress();
        if (address(gaugeRegistry_) == address(0)) revert ZeroAddress();
        if (address(slotRegistry_) == address(0)) revert ZeroAddress();
        if (address(vault_) == address(0)) revert ZeroAddress();
        if (address(bodenseeChannel_) == address(0)) revert ZeroAddress();
        if (address(svZchf_) == address(0)) revert ZeroAddress();
        if (address(sUsds_) == address(0)) revert ZeroAddress();
        if (bodenseePool_ == address(0)) revert ZeroAddress();

        VOTING_WEIGHT = votingWeight_;
        GAUGE_REGISTRY = gaugeRegistry_;
        SLOT_REGISTRY = slotRegistry_;
        VAULT = vault_;
        BODENSEE_CHANNEL = bodenseeChannel_;
        SVZCHF = svZchf_;
        SUSDS = sUsds_;
        BODENSEE_POOL = bodenseePool_;
    }
}
