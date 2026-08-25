// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {VotingWeight} from "src/governance/VotingWeight.sol";
import {IVotingWeight} from "src/governance/IVotingWeight.sol";
import {AureumGovernance} from "src/governance/AureumGovernance.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IMiliariumSlotRegistry} from "src/registry/IMiliariumSlotRegistry.sol";
import {SwapAndDepositToBodensee} from "src/gauge/SwapAndDepositToBodensee.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockEMASampler, MockGaugeRegistry, MockMiliariumRegistry, MockRecorder} from "test/unit/VotingWeight.t.sol";
import {MockSlotRegistry, MockVault, MockBodenseeChannel} from "test/unit/AureumGovernance.t.sol";

/// @title P1 G.1 — Succeeded never expires and redemption is permissionless
/// @notice Reproduction PoC for seam-1 root cause G.1 (Medium, returned from High at review
///         because the High leg is already counted in C.4 and per-pool pause containment survives
///         a sleeper unpause). A passed proposal that is never queued never expires; both
///         `queue` and `execute` are permissionless; a `VaultUnpause` ticket banked before an
///         emergency can be spent after it to undo the lever. PP-D29 is why this row lands after
///         A.1: the pre-queued exit is today the ONLY exit from a Vault pause.
/// @dev AureumGovernance declares ZERO functions matching "function cancel", and its ProposalState
///      enum has no Cancelled member, so there is no path by which a passed proposal is ever
///      withdrawn. EXECUTION_TIMELOCK_BLOCKS is two days while EXECUTION_GRACE_BLOCKS is one epoch,
///      both of which begin only at queue, which is why an un-queued Succeeded proposal is outside
///      every window.
contract P1_G1_SucceededNeverExpiresAndRedemptionIsPermissionlessTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant START_BLOCK = 2_000_000;
    uint256 internal constant TVL_EMA = 16e18;
    uint256 internal constant LP = 100e18;

    /// @dev Mirrored from AureumGovernance — VOTING_DELAY_BLOCKS / VOTING_PERIOD_BLOCKS /
    ///      EXECUTION_TIMELOCK_BLOCKS are private there; expressed here via AureumTime so every
    ///      `vm.roll` target is a compile-time constant (F15).
    uint256 internal constant PROPOSE_BLOCK = START_BLOCK;
    uint256 internal constant SNAPSHOT_BLOCK = PROPOSE_BLOCK + AureumTime.BLOCKS_PER_DAY;
    uint256 internal constant VOTE_BLOCK = SNAPSHOT_BLOCK + 1;
    uint256 internal constant END_BLOCK = SNAPSHOT_BLOCK + AureumTime.BLOCKS_PER_EPOCH;
    uint256 internal constant SUCCEEDED_BLOCK = END_BLOCK + 1;
    uint256 internal constant YEAR_LATER_BLOCK = SUCCEEDED_BLOCK + AureumTime.BLOCKS_PER_YEAR;
    uint256 internal constant QUEUE_BLOCK = YEAR_LATER_BLOCK;
    uint256 internal constant TIMELOCK_BLOCKS = 2 * AureumTime.BLOCKS_PER_DAY;
    uint256 internal constant ETA_BLOCK = QUEUE_BLOCK + TIMELOCK_BLOCKS;
    uint256 internal constant EXECUTE_BLOCK = ETA_BLOCK;

    VotingWeight internal vw;
    AureumGovernance internal gov;
    MockEMASampler internal emaSampler;
    MockGaugeRegistry internal gaugeReg;
    MockRecorder internal recorder;
    MockMiliariumRegistry internal miliariumReg;
    MockSlotRegistry internal slotReg;
    MockVault internal vault;
    MockBodenseeChannel internal channel;
    MockERC20 internal svZchf;
    MockERC20 internal sUsds;
    MockERC20 internal poolToken;

    address internal pool;
    address internal bodenseePool;
    address internal holder;
    address internal stranger;
    address internal proposer;

    function setUp() public {
        emaSampler = new MockEMASampler();
        gaugeReg = new MockGaugeRegistry();
        recorder = new MockRecorder();
        miliariumReg = new MockMiliariumRegistry();
        slotReg = new MockSlotRegistry();
        vault = new MockVault();
        channel = new MockBodenseeChannel();
        svZchf = new MockERC20("Staked Frankencoin", "svZCHF", 18);
        sUsds = new MockERC20("Savings USDS", "sUSDS", 18);
        // Real ERC-20 pool so IERC20(pool).balanceOf answers without vm.mockCall (PP10).
        poolToken = new MockERC20("Pilot BPT", "pBPT", 18);
        pool = address(poolToken);

        bodenseePool = makeAddr("bodenseePool");
        holder = makeAddr("holder");
        stranger = makeAddr("stranger");
        proposer = makeAddr("proposer");

        vw = new VotingWeight(emaSampler, gaugeReg, recorder, miliariumReg, GENESIS_BLOCK);
        gov = new AureumGovernance(
            IVotingWeight(address(vw)),
            IGaugeRegistry(address(gaugeReg)),
            IMiliariumSlotRegistry(address(slotReg)),
            IVault(address(vault)),
            SwapAndDepositToBodensee(address(channel)),
            IERC20(address(svZchf)),
            IERC20(address(sUsds)),
            bodenseePool
        );

        address[] memory pools = new address[](1);
        pools[0] = pool;
        miliariumReg.setPoolList(pools);
        miliariumReg.setMiliarium(pool, true);
        gaugeReg.setApproved(pool, true);

        emaSampler.setTvlEMA(pool, TVL_EMA);
        emaSampler.setSeedBlock(pool, 1);
        emaSampler.setLastUpdateBlock(pool, START_BLOCK);

        svZchf.mint(proposer, 1_000_000e18);
        vm.prank(proposer);
        svZchf.approve(address(gov), type(uint256).max);

        vm.roll(START_BLOCK);
    }

    function _configureAndPokeHolder() internal {
        uint256 eqb = START_BLOCK - AureumTime.ON_RAMP_PERIOD_BLOCKS;
        recorder.setUserLP(pool, holder, LP);
        recorder.setPoolTotalLP(pool, LP);
        recorder.setEffectiveQualBlock(pool, holder, eqb);
        poolToken.mint(holder, LP);
        vw.poke(holder);
    }

    /// @dev Passes a VaultUnpause at the fixed PROPOSE_BLOCK timeline and leaves it Succeeded.
    function _passUnpauseLeavingSucceeded() internal returns (uint256 id) {
        _configureAndPokeHolder();

        vm.prank(proposer);
        id = gov.proposeVaultUnpause(IERC20(address(svZchf)));

        AureumGovernance.Proposal memory p = gov.getProposal(id);
        assertEq(p.startBlock, PROPOSE_BLOCK, "proposal created at the fixed propose block");
        assertEq(p.snapshotBlock, SNAPSHOT_BLOCK, "snapshot is propose plus one day");
        assertEq(p.endBlock, END_BLOCK, "end is snapshot plus one epoch");

        vm.roll(VOTE_BLOCK);
        vm.prank(holder);
        gov.castVote(id, true);

        vm.roll(SUCCEEDED_BLOCK);
        assertEq(
            uint256(gov.state(id)),
            uint256(AureumGovernance.ProposalState.Succeeded),
            "sole poked holder carries VaultUnpause to Succeeded"
        );
    }

    /// @notice An un-queued Succeeded proposal never expires; any stranger can queue and execute it.
    function test_P1_G1_anUnqueuedSucceededProposalNeverExpiresAndAnyStrangerRedeemsIt() public {
        uint256 id = _passUnpauseLeavingSucceeded();

        // Roll at least a year past endBlock. state() returns Succeeded whenever eta is zero and
        // applies no time bound at all; expiry exists only after queueing (L340 vs L341-L342).
        vm.roll(YEAR_LATER_BLOCK);
        assertEq(
            uint256(gov.state(id)),
            uint256(AureumGovernance.ProposalState.Succeeded),
            "unqueued Succeeded never expires; queueing starts the only clock that exists"
        );

        // Permissionless queue: the stranger, who holds no position and was never poked, redeems.
        vm.prank(stranger);
        gov.queue(id);
        assertEq(
            uint256(gov.state(id)),
            uint256(AureumGovernance.ProposalState.Queued),
            "queue is permissionless; the holder need not be the redeemer"
        );

        AureumGovernance.Proposal memory queued = gov.getProposal(id);
        assertEq(queued.eta, ETA_BLOCK, "eta is queue block plus two-day timelock");

        // Failed early execute does not consume the ticket (executed is set only after the check).
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(AureumGovernance.TimelockNotMet.selector, ETA_BLOCK, QUEUE_BLOCK)
        );
        gov.execute(id);
        assertEq(
            uint256(gov.state(id)),
            uint256(AureumGovernance.ProposalState.Queued),
            "a failed execute attempt does not consume the ticket"
        );

        vm.roll(EXECUTE_BLOCK);
        vm.prank(stranger);
        gov.execute(id);
        assertEq(
            uint256(gov.state(id)),
            uint256(AureumGovernance.ProposalState.Executed),
            "execute is permissionless once the timelock elapses"
        );
    }

    /// @notice A VaultUnpause ticket banked before an emergency can be spent after it to undo the lever.
    function test_P1_G1_aTicketBankedBeforeAnEmergencyIsSpentAfterItToUndoTheLever() public {
        uint256 id = _passUnpauseLeavingSucceeded();
        assertEq(vault.unpauseVaultCalls(), 0, "banked ticket has not yet touched the Vault");

        // Emergency arises much later; the stranger then redeems the pre-banked ticket.
        vm.roll(QUEUE_BLOCK);
        vm.prank(stranger);
        gov.queue(id);

        vm.roll(EXECUTE_BLOCK);
        vm.prank(stranger);
        gov.execute(id);

        assertEq(
            vault.unpauseVaultCalls(),
            1,
            "banked VaultUnpause undoes the emergency lever after the fact"
        );

        AureumGovernance.Proposal memory p = gov.getProposal(id);
        assertEq(p.startBlock, PROPOSE_BLOCK, "creation block is the early bank time");
        assertLt(
            p.startBlock,
            EXECUTE_BLOCK,
            "ticket predates the emergency it defeats; two-day timelock is the whole defender warning"
        );
        assertGt(
            EXECUTE_BLOCK - p.startBlock,
            AureumTime.BLOCKS_PER_YEAR,
            "creation is more than a year before execution"
        );
    }
}
