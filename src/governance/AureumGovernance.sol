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

    uint256 internal constant VOTING_DELAY_BLOCKS = AureumTime.BLOCKS_PER_DAY;
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
        Expired,
        Pending
    }

    struct Proposal {
        address proposer;
        ProposalType proposalType;
        uint256 startBlock;
        uint256 endBlock;
        uint256 snapshotBlock;
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
        uint256 snapshotBlock,
        uint256 endBlock
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
    error CompositionQualityGateFailed(address pool);
    error ExclusiveSwapFeeManager(address pool, address manager);

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

    /// @notice Resolve the fixed proposal deposit for a whitelisted pay token.
    /// @param payToken_ SVZCHF or sUSDS.
    /// @return deposit amount in `payToken_` wei.
    function _depositAmount(IERC20 payToken_) internal view returns (uint256) {
        if (payToken_ == SVZCHF) return PROPOSAL_DEPOSIT_SVZCHF;
        if (payToken_ == SUSDS) return PROPOSAL_DEPOSIT_SUSDS;
        revert InvalidPayToken();
    }

    /// @notice Shared propose tail — pull deposit, donate to Bodensee, stamp the voting-delay snapshot block, record proposal.
    /// @param proposalType_ gauge, composition, or fee variant.
    /// @param targetPool_ fee or gauge target; zero when unused.
    /// @param newPool_ composition replacement pool; zero when unused.
    /// @param slot_ constellation slot for composition; zero when unused.
    /// @param newFee_ proposed swap fee; zero when unused.
    /// @param payToken_ SVZCHF or sUSDS deposit token.
    /// @return proposalId 1-based identifier (`++proposalCount`).
    /// @dev Deposit is pulled via `safeTransferFrom(proposer → BODENSEE_CHANNEL)` then donated — proposer must
    ///      `approve` this contract before calling; deposit is non-refundable (permanent Bodensee donation per
    ///      K-D6d). This contract must be an `authorizedDonator` on `BODENSEE_CHANNEL` (G-D21, wired at K7).
    function _createProposal(ProposalType proposalType_, address targetPool_, address newPool_, uint256 slot_, uint256 newFee_, IERC20 payToken_) internal returns (uint256 proposalId) {
        uint256 amount = _depositAmount(payToken_);
        payToken_.safeTransferFrom(msg.sender, address(BODENSEE_CHANNEL), amount);
        BODENSEE_CHANNEL.donate(payToken_, amount);
        proposalId = ++proposalCount;
        uint256 start = block.number;
        uint256 snapshotBlock = start + VOTING_DELAY_BLOCKS;
        uint256 end = snapshotBlock + VOTING_PERIOD_BLOCKS;
        _proposals[proposalId] = Proposal({ proposer: msg.sender, proposalType: proposalType_, startBlock: start, endBlock: end, snapshotBlock: snapshotBlock, forVotes: 0, againstVotes: 0, eta: 0, executed: false, targetPool: targetPool_, newPool: newPool_, slot: slot_, newFee: newFee_ });
        emit ProposalCreated(proposalId, proposalType_, msg.sender, start, snapshotBlock, end);
    }

    /// @notice Propose a gauge challenge to revoke an active pilot gauge.
    /// @param targetPool_ pool whose gauge status must be Active and unslotted (`slotOf == 0`).
    /// @param payToken_ SVZCHF or sUSDS proposal deposit.
    /// @return proposalId 1-based identifier.
    /// @dev Proposer must `approve` this contract for the deposit amount before calling.
    function proposeGaugeChallenge(address targetPool_, IERC20 payToken_) external returns (uint256 proposalId) {
        if (GAUGE_REGISTRY.gaugeStatus(targetPool_) != IGaugeRegistry.GaugeStatus.Active || SLOT_REGISTRY.slotOf(targetPool_) != 0) revert InvalidGaugeTarget(targetPool_);
        proposalId = _createProposal(ProposalType.GaugeChallenge, targetPool_, address(0), 0, 0, payToken_);
    }

    /// @notice Propose a composition challenge to replace the pool at a filled constellation slot.
    /// @param slot_ Miliarium slot in [1, 28].
    /// @param newPool_ replacement pool address.
    /// @param payToken_ SVZCHF or sUSDS proposal deposit.
    /// @return proposalId 1-based identifier.
    /// @dev Proposer must `approve` this contract for the deposit amount before calling.
    function proposeCompositionChallenge(uint256 slot_, address newPool_, IERC20 payToken_) external returns (uint256 proposalId) {
        if (slot_ == 0 || slot_ > 28) revert InvalidCompositionTarget(slot_); // 28 = Miliarium constellation size
        if (newPool_ == address(0)) revert ZeroAddress();
        if (SLOT_REGISTRY.poolAtSlot(slot_) == address(0)) revert InvalidCompositionTarget(slot_);
        if (!GAUGE_REGISTRY.meetsCompositionQualityGate(newPool_)) revert CompositionQualityGateFailed(newPool_);
        proposalId = _createProposal(ProposalType.CompositionChallenge, address(0), newPool_, slot_, 0, payToken_);
    }

    /// @notice Propose a static swap-fee change on a gauged, non-Bodensee pool.
    /// @param targetPool_ pool whose fee will change on execution.
    /// @param newFee_ proposed fee in 18-decimal fixed-point (must lie in [SWAP_FEE_MIN, SWAP_FEE_MAX]).
    /// @param payToken_ SVZCHF or sUSDS proposal deposit.
    /// @return proposalId 1-based identifier.
    /// @dev Proposer must `approve` this contract for the deposit amount before calling; fee cooldown is enforced at
    ///      execute time (K4.5), not here. F-20 executability gate (P-D40): reverts `ExclusiveSwapFeeManager` when the
    ///      pool's Vault `swapFeeManager` role is set to any address other than this contract — the EXCLUSIVE role
    ///      would foreclose execution at `setStaticSwapFeePercentage` after the bond was already donated. Role
    ///      accounts are immutable post-registration, so the propose-time check is sufficient (no execute re-check).
    function proposeFeeChange(address targetPool_, uint256 newFee_, IERC20 payToken_) external returns (uint256 proposalId) {
        if (newFee_ < SWAP_FEE_MIN || newFee_ > SWAP_FEE_MAX) revert InvalidFeeValue(newFee_);
        if (targetPool_ == BODENSEE_POOL || !GAUGE_REGISTRY.isGaugeApproved(targetPool_)) revert InvalidFeeTarget(targetPool_);
        // F-20 / P-D40 executability gate: a non-zero swapFeeManager is an EXCLUSIVE Vault role
        // (VaultAdmin._ensureAuthenticatedByExclusiveRole) — execute's setStaticSwapFeePercentage
        // would revert SenderNotAllowed after the bond was already donated. Immutable role, so
        // propose-time suffices.
        address manager = VAULT.getPoolRoleAccounts(targetPool_).swapFeeManager;
        if (manager != address(0) && manager != address(this)) revert ExclusiveSwapFeeManager(targetPool_, manager);
        proposalId = _createProposal(ProposalType.FeeChange, targetPool_, address(0), 0, newFee_, payToken_);
    }

    /// @notice Cast a snapshot-weighted vote on an active proposal.
    /// @param proposalId 1-based proposal identifier.
    /// @param support `true` for, `false` against.
    /// @dev Weight is read via `getPastVotes(msg.sender, p.snapshotBlock)` — the caller's checkpoint frozen at
    ///      the proposal's snapshot block (F-06). A voter must `poke` themselves during the `Pending`
    ///      voting-delay window (on or before `snapshotBlock`) for their weight to count; an un-poked or
    ///      since-withdrawn voter reads 0 (Compound-parity no-op, not a revert). Voting is gated to the Active
    ///      window `snapshotBlock < block.number <= endBlock`; a `Pending` or closed proposal reverts
    ///      `ProposalNotActive`. The `hasVoted` guard is set before the external (view) `getPastVotes` read.
    function castVote(uint256 proposalId, bool support) external {
        Proposal storage p = _proposals[proposalId];
        if (block.number <= p.snapshotBlock || block.number > p.endBlock) revert ProposalNotActive(proposalId);
        if (hasVoted[proposalId][msg.sender]) revert AlreadyVoted(msg.sender, proposalId);
        hasVoted[proposalId][msg.sender] = true;
        uint256 weight = VOTING_WEIGHT.getPastVotes(msg.sender, p.snapshotBlock);
        if (support) {
            p.forVotes += weight;
        } else {
            p.againstVotes += weight;
        }
        emit VoteCast(proposalId, msg.sender, support, weight);
    }

    /// @notice Derive the lifecycle state of a proposal from stored fields.
    /// @param proposalId 1-based proposal identifier.
    /// @return Current `ProposalState` — non-existent or unvoted proposals derive to `Defeated`.
    /// @dev `Pending` during the voting-delay window (`block.number <= snapshotBlock`, F-06); `Active` while
    ///      `snapshotBlock < block.number <= endBlock`; the tally is evaluated only after `endBlock` per
    ///      K-D6c. A non-existent proposal (`snapshotBlock == endBlock == 0`) derives to `Defeated`, never
    ///      `Pending`, since `block.number > 0`.
    function state(uint256 proposalId) public view returns (ProposalState) {
        Proposal storage p = _proposals[proposalId];
        if (p.executed) return ProposalState.Executed;
        if (block.number <= p.snapshotBlock) return ProposalState.Pending;
        if (block.number <= p.endBlock) return ProposalState.Active;
        if (!_voteSucceeded(p)) return ProposalState.Defeated;
        if (p.eta == 0) return ProposalState.Succeeded;
        if (block.number < p.eta + EXECUTION_GRACE_BLOCKS) return ProposalState.Queued;
        return ProposalState.Expired;
    }

    /// @notice Evaluate quorum and per-type majority after the voting window closes.
    /// @param p Stored proposal record.
    /// @return `true` when turnout and majority thresholds are met.
    /// @dev Quorum is 20% turnout per `QUORUM_BPS`. `CompositionChallenge` requires integer-exact 2/3
    ///      supermajority; `GaugeChallenge` + `FeeChange` require simple majority, per K-D6c.
    /// @dev F-06 — both the numerator (`forVotes` + `againstVotes`, each a `getPastVotes(voter, snapshotBlock)`
    ///      read in `castVote`) and the denominator (`getPastTotalSupply(p.snapshotBlock)`) are frozen at the
    ///      same snapshot block, so turnout cannot exceed 100% of the denominator by construction. This
    ///      supersedes the F-01 live `totalSupply()` read: freezing both sides at `snapshotBlock` closes the
    ///      F-01 >100%-turnout face AND the F-06 post-`endBlock` denominator-inflation grief (a `poke` after
    ///      `endBlock` no longer moves the denominator this proposal reads).
    function _voteSucceeded(Proposal storage p) internal view returns (bool) {
        uint256 totalVotes = p.forVotes + p.againstVotes;
        if (totalVotes * 10_000 < VOTING_WEIGHT.getPastTotalSupply(p.snapshotBlock) * QUORUM_BPS) return false; // 10_000 = basis-points denominator
        if (p.proposalType == ProposalType.CompositionChallenge) {
            return p.forVotes * 3 >= totalVotes * 2;
        }
        return p.forVotes > p.againstVotes;
    }

    /// @notice Return a full proposal record for off-chain consumers and tests.
    /// @param proposalId 1-based proposal identifier.
    /// @return Proposal struct copy — `_proposals` is internal; this is the read surface.
    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return _proposals[proposalId];
    }

    /// @notice Queue a succeeded proposal for timelocked execution.
    /// @param proposalId 1-based proposal identifier.
    /// @dev Requires `Succeeded`; the timelock `eta` is set here. Single-queue is self-guarding via the
    ///      state transition to `Queued`. Permissionless — validity is established by the vote.
    function queue(uint256 proposalId) external {
        if (state(proposalId) != ProposalState.Succeeded) revert ProposalNotSucceeded(proposalId);
        Proposal storage p = _proposals[proposalId];
        uint256 eta = block.number + EXECUTION_TIMELOCK_BLOCKS;
        p.eta = eta;
        emit ProposalQueued(proposalId, eta);
    }

    /// @notice Execute a queued proposal after the timelock elapses.
    /// @param proposalId 1-based proposal identifier.
    /// @dev Requires `Queued` state — call `queue` first after `Succeeded`; a non-queued proposal reverts
    ///      `ProposalNotSucceeded`. The `executed` flag is set before the external routing call as a
    ///      checks-effects-interactions reentrancy guard. Permissionless — validity is established by the vote.
    function execute(uint256 proposalId) external {
        Proposal storage p = _proposals[proposalId];
        if (p.executed) revert ProposalAlreadyExecuted(proposalId);
        ProposalState s = state(proposalId);
        if (s == ProposalState.Expired) revert GracePeriodExpired(proposalId);
        if (s != ProposalState.Queued) revert ProposalNotSucceeded(proposalId);
        if (block.number < p.eta) revert TimelockNotMet(p.eta, block.number);
        p.executed = true;
        _executeProposal(p);
        emit ProposalExecuted(proposalId);
    }

    /// @notice Route an executed proposal to its per-type downstream effect.
    /// @param p Stored proposal record.
    /// @dev Per-type routing per K-D6e: gauge challenge revokes; composition is atomic
    ///      revoke-old → `replaceSlot` → register-new; fee change checks cooldown here, stamps
    ///      `lastFeeChangeBlock`, then calls `VAULT.setStaticSwapFeePercentage`.
    function _executeProposal(Proposal storage p) internal {
        if (p.proposalType == ProposalType.GaugeChallenge) {
            GAUGE_REGISTRY.revokeGauge(p.targetPool);
        } else if (p.proposalType == ProposalType.CompositionChallenge) {
            if (!GAUGE_REGISTRY.meetsCompositionQualityGate(p.newPool)) revert CompositionQualityGateFailed(p.newPool);
            address oldPool = SLOT_REGISTRY.poolAtSlot(p.slot);
            GAUGE_REGISTRY.revokeGauge(oldPool);
            SLOT_REGISTRY.replaceSlot(p.slot, p.newPool);
            GAUGE_REGISTRY.registerGaugeFromComposition(p.newPool);
        } else {
            if (block.number < lastFeeChangeBlock[p.targetPool] + FEE_CHANGE_COOLDOWN_BLOCKS) revert FeeCooldownActive(p.targetPool);
            lastFeeChangeBlock[p.targetPool] = block.number;
            VAULT.setStaticSwapFeePercentage(p.targetPool, p.newFee);
        }
    }
}
