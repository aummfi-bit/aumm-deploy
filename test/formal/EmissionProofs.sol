// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import {AuMM} from "src/token/AuMM.sol";
import {AuMMMinterRouter} from "src/token/AuMMMinterRouter.sol";
import {IAuMM} from "src/token/IAuMM.sol";
import {EmissionDistributor} from "src/emission/EmissionDistributor.sol";
import {BodenseeBootstrapChannel} from "src/emission/BodenseeBootstrapChannel.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "src/ccb/ICCBMultiplier.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {MockRegisteredVault} from "../mocks/MockRegisteredVault.sol";

/// @notice Minimal Vault stub with a settable getPoolTokens return, so the
///         BodenseeBootstrapChannel constructor can resolve the AuMM index.
///         Not declared `is IVault` -- the IVault cast at construction
///         dispatches getPoolTokens by selector, so the rest of IVault is
///         unused (the MockTVLOracleProof rationale).
contract MockVaultForChannel {
    IERC20 private immutable _aumm;

    constructor(IERC20 aumm_) {
        _aumm = aumm_;
    }

    function getPoolTokens(address) external view returns (IERC20[] memory tokens) {
        tokens = new IERC20[](3);
        tokens[0] = _aumm;
        tokens[1] = IERC20(address(0x1));
        tokens[2] = IERC20(address(0x2));
    }
}

/// @title  EmissionProofs
/// @notice hevm symbolic proofs for the emission-accrual surface (PB2.12e /
///         PB-D17). Invoke: hevm test --match prove_ --solver bitwuzla
///         --smt-timeout 300 --max-iterations 10 --root . Multi-call proofs
///         re-visit the target contract's entry pc across separate external
///         calls; the raised bound widens exploration only (cannot mask a
///         counterexample), per the e1 lesson.
/// @dev    Tier-1 of the emission-accrual surface (PB2.12e / PB-D17). The P-A*
///         namespace landed at e1 (AuMM only); P-R*/P-ED* landed at e2; P-BC*
///         lands HERE (e3), closing emission-accrual Tier-1; the .act spec (e4)
///         closes the surface. P-D* is deliberately unused (collides with
///         Stage-P planning codes). The three STAGES_OVERVIEW L411 candidates
///         map P-A1 = 21M cap, P-A4 = halving curve; the no-admin-redirect
///         candidate is covered by P-ED1 (setMintRouter one-shot) + P-R1
///         (allowlist gate). Solver note: address-logic proofs green under
///         z3; curve/cap arithmetic is canonical under bitwuzla 0.9.1
///         (constant-divisor class per the d1-d2 lesson). Modeling note:
///         setMinter's C-D11 two-flag lock makes post-bind rejection
///         caller-universal with NO EVM-sender axiom (either flag alone
///         blocks, unlike the F-D20 single-flag seal at P-M1), while the
///         PRE-bind mint gate does need caller != address(0) because the
///         unbound minter slot IS the zero address.
contract EmissionProofs is Test {
    AuMM internal aumm;
    AuMMMinterRouter internal router;
    EmissionDistributor internal dist;
    MockVaultForChannel internal mockVault;
    BodenseeBootstrapChannel internal channel;

    uint256 internal constant GENESIS = 1_000_000;
    address internal constant RECIPIENT = address(0xAAAA);
    uint256 internal constant MAX = 21_000_000e18;
    address internal constant BOOTSTRAP = address(0xB007);
    address internal constant DISTRIB = address(0xD157);
    address internal constant BODENSEE = address(0xB0DE);

    function setUp() public {
        // Minter UNBOUND; this contract is the C-D11 minter admin.
        aumm = new AuMM(GENESIS, address(this));
        // aumm's minter stays UNBOUND in setUp -- the e1 proofs depend on it.
        router = new AuMMMinterRouter(aumm, BOOTSTRAP, DISTRIB);
        // Constructor makes no external calls; dummies satisfy only the
        // ZeroAddress checks.
        dist = new EmissionDistributor(
            aumm,
            IGaugeRegistry(address(0xA222)),
            IEMASampler(address(0xA333)),
            ICCBMultiplier(address(0xA444)),
            IEfficiencyOracle(address(0xA555)),
            IMiliariumRegistry(address(0xA666)),
            GENESIS,
            address(this),
            address(new MockRegisteredVault())
        );
        // Mock supplies only getPoolTokens for the constructor aumm-index
        // lookup; aumm's minter stays UNBOUND (accrue reads blockEmissionRate,
        // never mints).
        mockVault = new MockVaultForChannel(aumm);
        channel = new BodenseeBootstrapChannel(
            IVault(address(mockVault)),
            BODENSEE,
            aumm,
            GENESIS,
            address(this)
        );
    }

    // -------------------------------------------------------------------------
    // P-A* -- AuMM setMinter C-D11 two-flag lock + mint gate + 21M cap + curve.
    // -------------------------------------------------------------------------

    /// P-A2 auth gate: before the seal, setMinter reverts for every caller
    /// other than the constructor-set minter admin (this contract).
    function prove_setMinter_onlyAdmin(address caller, address m) public {
        vm.assume(caller != address(this));

        vm.prank(caller);
        (bool ok, ) = address(aumm).call(abi.encodeCall(AuMM.setMinter, (m)));
        assert(!ok);
    }

    /// P-A2 one-shot: the admin's first set binds the minter and seals the
    /// admin; afterwards every caller reverts. Caller-universal with NO
    /// EVM-sender axiom -- C-D11's two-flag lock (minter != 0 AND
    /// _minterAdmin == 0) blocks on either flag alone, unlike the F-D20
    /// single-flag seal at P-M1.
    function prove_setMinter_oneShot(address first, address second, address caller) public {
        vm.assume(first != address(0));

        aumm.setMinter(first);
        assert(aumm.minter() == first);

        vm.prank(caller);
        (bool ok, ) = address(aumm).call(abi.encodeCall(AuMM.setMinter, (second)));
        assert(!ok);
    }

    /// P-A2 zero-rejection: even the authorized admin cannot bind the zero
    /// address (ZeroAddress fires after the authority check per C-D11).
    function prove_setMinter_rejectZero() public {
        (bool ok, ) = address(aumm).call(
            abi.encodeCall(AuMM.setMinter, (address(0)))
        );
        assert(!ok);
    }

    /// P-A3 mint auth: after setMinter(this), mint reverts for every caller
    /// other than the bound minter.
    function prove_mint_requiresMinter(address caller, uint256 amount) public {
        aumm.setMinter(address(this));
        vm.assume(caller != address(this));

        vm.prank(caller);
        (bool ok, ) = address(aumm).call(
            abi.encodeCall(AuMM.mint, (RECIPIENT, amount))
        );
        assert(!ok);
    }

    /// P-A3 unbound mint gate: with no setMinter call the minter slot is
    /// address(0), so mint reverts for every real caller. Needs the
    /// EVM-sender axiom caller != address(0) because the unbound minter
    /// slot IS the zero address (a zero-caller prank would pass the
    /// msg.sender == minter check).
    function prove_mint_unboundReverts(address caller, uint256 amount) public {
        vm.assume(caller != address(0));

        vm.prank(caller);
        (bool ok, ) = address(aumm).call(
            abi.encodeCall(AuMM.mint, (RECIPIENT, amount))
        );
        assert(!ok);
    }

    /// P-A1 within-cap: two successive mints whose sum stays at or under
    /// MAX_SUPPLY succeed and land exactly m1 + m2 on RECIPIENT.
    function prove_mint_withinCap(uint256 m1, uint256 m2) public {
        aumm.setMinter(address(this));
        vm.assume(m1 <= MAX);
        vm.assume(m2 <= MAX - m1);

        aumm.mint(RECIPIENT, m1);
        aumm.mint(RECIPIENT, m2);
        assert(aumm.totalSupply() == m1 + m2);
        assert(aumm.totalSupply() <= MAX);
        assert(aumm.balanceOf(RECIPIENT) == m1 + m2);
    }

    /// P-A1 cap-exceeded: after minting m1 <= MAX, any m2 > MAX - m1 reverts
    /// and leaves totalSupply at m1. Covers both the SupplyCapExceeded revert
    /// and the checked-add overflow for huge m2 -- no path past 21M either way.
    function prove_mint_capExceeded(uint256 m1, uint256 m2) public {
        aumm.setMinter(address(this));
        vm.assume(m1 <= MAX);
        vm.assume(m2 > MAX - m1);

        aumm.mint(RECIPIENT, m1);
        (bool ok, ) = address(aumm).call(
            abi.encodeCall(AuMM.mint, (RECIPIENT, m2))
        );
        assert(!ok);
        assert(aumm.totalSupply() == m1);
    }

    /// P-A4 pre-genesis: every block strictly before GENESIS emits zero.
    function prove_curve_preGenesisZero(uint256 b) public {
        vm.assume(b < GENESIS);
        assert(aumm.blockEmissionRate(b) == 0);
    }

    /// P-A4 era value: within era n (< 60) the rate is exactly
    /// GENESIS_RATE >> n at every in-era offset.
    function prove_curve_eraValue(uint256 n, uint256 offset) public {
        vm.assume(n < 60);
        vm.assume(offset < AureumTime.BLOCKS_PER_ERA);
        assert(
            aumm.blockEmissionRate(GENESIS + n * AureumTime.BLOCKS_PER_ERA + offset)
                == aumm.GENESIS_RATE() >> n
        );
    }

    /// P-A4 halving step: at every era boundary n in [1, 60] the rate is
    /// exactly half the prior-era terminal rate (floor division). Floor-
    /// halving is exact at every era step including the terminal 1 -> 0 at
    /// era 60.
    function prove_curve_halvingStep(uint256 n) public {
        vm.assume(n >= 1 && n <= 60);
        uint256 boundary = GENESIS + n * AureumTime.BLOCKS_PER_ERA;
        assert(
            aumm.blockEmissionRate(boundary)
                == aumm.blockEmissionRate(boundary - 1) / 2
        );
    }

    /// P-A4 exhausts: every era n >= 60 emits zero. 1e18 < 2**60 so every
    /// shift at era >= 60 zeroes; the n-range also witnesses the defensive
    /// era >= 256 guard branch.
    function prove_curve_exhausts(uint256 n, uint256 offset) public {
        vm.assume(n >= 60 && n < 1000);
        vm.assume(offset < AureumTime.BLOCKS_PER_ERA);
        assert(
            aumm.blockEmissionRate(GENESIS + n * AureumTime.BLOCKS_PER_ERA + offset)
                == 0
        );
    }

    // -------------------------------------------------------------------------
    // P-R* -- AuMMMinterRouter allowlist gate + forward + cap composition.
    // -------------------------------------------------------------------------

    /// P-R1 allowlist gate: mintFor reverts for every caller other than the
    /// two immutable consumers. The gate fires before any AuMM interaction,
    /// so no minter binding is needed.
    function prove_router_allowlistGate(address caller, uint256 amount) public {
        vm.assume(caller != BOOTSTRAP && caller != DISTRIB);

        vm.prank(caller);
        (bool ok, ) = address(router).call(
            abi.encodeCall(AuMMMinterRouter.mintFor, (RECIPIENT, amount))
        );
        assert(!ok);
    }

    /// P-R1 positive leg: both allowlist entries are live and forward exactly.
    /// Binds the router as AuMM minter, then mints from BOOTSTRAP and DISTRIB.
    function prove_router_bothConsumersMint(uint256 m1, uint256 m2) public {
        aumm.setMinter(address(router));
        vm.assume(m1 <= MAX);
        vm.assume(m2 <= MAX - m1);

        vm.prank(BOOTSTRAP);
        router.mintFor(RECIPIENT, m1);
        vm.prank(DISTRIB);
        router.mintFor(RECIPIENT, m2);
        assert(aumm.totalSupply() == m1 + m2);
        assert(aumm.balanceOf(RECIPIENT) == m1 + m2);
    }

    /// P-R2 cap through router: the 21M cap survives composition through the
    /// router; no bypass exists on the forwarded path.
    function prove_router_capHoldsThroughRouter(uint256 m1, uint256 m2) public {
        aumm.setMinter(address(router));
        vm.assume(m1 <= MAX);
        vm.assume(m2 > MAX - m1);

        vm.prank(BOOTSTRAP);
        router.mintFor(RECIPIENT, m1);
        vm.prank(BOOTSTRAP);
        (bool ok, ) = address(router).call(
            abi.encodeCall(AuMMMinterRouter.mintFor, (RECIPIENT, m2))
        );
        assert(!ok);
        assert(aumm.totalSupply() == m1);
    }

    // -------------------------------------------------------------------------
    // P-ED* -- EmissionDistributor governance locks (setMintRouter /
    // setAuMTContractForPool / setGovernanceContract / proposeIncendiaryRegistry / acceptIncendiaryRegistry).
    // ALL FOUR distributor locks are slot-flag or modifier gates on nonzero
    // principals, so every post-bind rejection is caller-universal with NO
    // EVM-sender axiom (governance is nonzero by construction; contrast the
    // F-D20 single-flag seal at P-M1).
    // -------------------------------------------------------------------------

    /// P-ED1 auth gate: setMintRouter reverts for every caller other than
    /// the constructor-set governance (this contract).
    function prove_distributor_setMintRouter_onlyGovernance(
        address caller,
        address r
    ) public {
        vm.assume(caller != address(this));

        vm.prank(caller);
        (bool ok, ) = address(dist).call(
            abi.encodeCall(EmissionDistributor.setMintRouter, (r))
        );
        assert(!ok);
    }

    /// P-ED1 one-shot: the L411 no-admin-redirect core -- once bound, no
    /// caller (governance included) re-points the mint sink.
    function prove_distributor_mintRouter_setOnce(
        address first,
        address second,
        address caller
    ) public {
        vm.assume(first != address(0));

        dist.setMintRouter(first);
        assert(address(dist.mintRouter()) == first);

        vm.prank(caller);
        (bool ok, ) = address(dist).call(
            abi.encodeCall(EmissionDistributor.setMintRouter, (second))
        );
        assert(!ok);
    }

    /// P-ED1 zero-rejection: even governance cannot bind the zero address.
    function prove_distributor_setMintRouter_rejectZero() public {
        (bool ok, ) = address(dist).call(
            abi.encodeCall(EmissionDistributor.setMintRouter, (address(0)))
        );
        assert(!ok);
    }

    /// P-ED2 one-shot per pool: once an AuMT recorder is bound for a pool,
    /// every later setAuMTContractForPool on that pool reverts for all callers.
    function prove_distributor_auMT_setOncePerPool(
        address pool,
        address first,
        address second,
        address caller
    ) public {
        vm.assume(first != address(0));

        dist.setAuMTContractForPool(pool, first);
        assert(dist.auMTContractByPool(pool) == first);

        vm.prank(caller);
        (bool ok, ) = address(dist).call(
            abi.encodeCall(
                EmissionDistributor.setAuMTContractForPool,
                (pool, second)
            )
        );
        assert(!ok);
    }

    /// P-ED2 pool independence: the P-H5 lock-independence class, mapping
    /// edition -- binding pool1 does not seal pool2.
    function prove_distributor_auMT_poolIndependence(
        address pool1,
        address pool2,
        address a1,
        address a2
    ) public {
        vm.assume(pool1 != pool2);
        vm.assume(a1 != address(0));
        vm.assume(a2 != address(0));

        dist.setAuMTContractForPool(pool1, a1);
        dist.setAuMTContractForPool(pool2, a2);
        assert(dist.auMTContractByPool(pool1) == a1);
        assert(dist.auMTContractByPool(pool2) == a2);
    }

    /// P-ED2 zero-rejection: governance cannot bind a zero AuMT recorder.
    function prove_distributor_auMT_rejectZero(address pool) public {
        (bool ok, ) = address(dist).call(
            abi.encodeCall(
                EmissionDistributor.setAuMTContractForPool,
                (pool, address(0))
            )
        );
        assert(!ok);
    }

    /// P-ED3 governance rotation: two-phase rotation, old authority locked
    /// out, new authority live (the P-H6 shape).
    function prove_distributor_governanceRotation(address newGov) public {
        vm.assume(newGov != address(0));
        vm.assume(newGov != address(this));

        dist.setGovernanceContract(newGov);
        assert(dist.governance() == newGov);

        (bool ok, ) = address(dist).call(
            abi.encodeCall(
                EmissionDistributor.proposeIncendiaryRegistry,
                (address(aumm))
            )
        );
        assert(!ok);

        vm.prank(newGov);
        dist.proposeIncendiaryRegistry(address(aumm));
        assert(dist.pendingIncendiaryRegistry() == address(aumm));
        assert(dist.pendingIncendiaryRegistryBlock() == block.number);
    }

    /// P-ED4 auth gate on both halves of the PP-D44 two-step registry rebind;
    /// H-D29 zero-permitted deprecation valve witnessed positively through
    /// propose-then-accept with no fast path (deliberate asymmetry with the
    /// ZeroAddress-guarded setters). `reg` stays symbolic on the propose auth
    /// leg because `onlyGovernance` runs before the body's code.length gate;
    /// positive legs use concrete `address(aumm)`.
    function prove_distributor_setIncendiaryRegistry_gateAndClear(
        address caller,
        address reg
    ) public {
        vm.assume(caller != address(this));

        vm.prank(caller);
        (bool ok, ) = address(dist).call(
            abi.encodeCall(EmissionDistributor.proposeIncendiaryRegistry, (reg))
        );
        assert(!ok);

        dist.proposeIncendiaryRegistry(address(aumm));
        vm.roll(block.number + 1);

        vm.prank(caller);
        (ok, ) = address(dist).call(
            abi.encodeWithSelector(EmissionDistributor.acceptIncendiaryRegistry.selector)
        );
        assert(!ok);

        dist.acceptIncendiaryRegistry();
        assert(dist.incendiaryRegistry() == address(aumm));

        dist.proposeIncendiaryRegistry(address(0));
        vm.roll(block.number + 1);
        dist.acceptIncendiaryRegistry();
        assert(dist.incendiaryRegistry() == address(0));
    }

    // -------------------------------------------------------------------------
    // P-BC* -- BodenseeBootstrapChannel governance locks + accrue structural
    // guards. The channel setters mirror the distributor locks (same class,
    // DISTINCT bytecode -- per-contract audit coverage). Accrue is proven here
    // for its structural guards only; distribute() (the H-D12 Vault-unlock
    // DONATION seam + 3 transient slots) and the H-D26 cross-contract
    // AP-conservation identity are the Tier-2 residual per PB-D17(ii), stated
    // in the e4 formal/act footer and pinned by the existing channel unit
    // tests + the P6.5 invariant harness (mirroring the S7
    // updateEMA/updateMultiplier residual handling).
    // -------------------------------------------------------------------------

    /// P-BC1 auth gate: setMintRouter reverts for every caller other than
    /// the constructor-set governance (this contract).
    function prove_channel_setMintRouter_onlyGovernance(
        address caller,
        address r
    ) public {
        vm.assume(caller != address(this));

        vm.prank(caller);
        (bool ok, ) = address(channel).call(
            abi.encodeCall(BodenseeBootstrapChannel.setMintRouter, (r))
        );
        assert(!ok);
    }

    /// P-BC1 one-shot: once bound, every later setMintRouter reverts.
    /// Caller-universal (non-gov reverts onlyGovernance; gov reverts
    /// MintRouterAlreadySet), no EVM-sender axiom.
    function prove_channel_setMintRouter_setOnce(
        address first,
        address second,
        address caller
    ) public {
        vm.assume(first != address(0));

        channel.setMintRouter(first);
        assert(address(channel.mintRouter()) == first);

        vm.prank(caller);
        (bool ok, ) = address(channel).call(
            abi.encodeCall(BodenseeBootstrapChannel.setMintRouter, (second))
        );
        assert(!ok);
    }

    /// P-BC1 zero-rejection: even governance cannot bind the zero address.
    function prove_channel_setMintRouter_rejectZero() public {
        (bool ok, ) = address(channel).call(
            abi.encodeCall(BodenseeBootstrapChannel.setMintRouter, (address(0)))
        );
        assert(!ok);
    }

    /// P-BC2 governance rotation: two-phase self-probe on
    /// setGovernanceContract itself (old locked out, new live), the P-H6
    /// shape.
    function prove_channel_governanceRotation(address newGov) public {
        vm.assume(newGov != address(0) && newGov != address(this));

        channel.setGovernanceContract(newGov);
        assert(channel.governance() == newGov);

        (bool ok, ) = address(channel).call(
            abi.encodeCall(
                BodenseeBootstrapChannel.setGovernanceContract,
                (address(0xBEEF))
            )
        );
        assert(!ok);

        vm.prank(newGov);
        channel.setGovernanceContract(address(0xBEEF));
        assert(channel.governance() == address(0xBEEF));
    }

    /// P-BC2 zero-rejection: even governance cannot hand off to address(0).
    function prove_channel_setGovernanceContract_rejectZero() public {
        (bool ok, ) = address(channel).call(
            abi.encodeCall(
                BodenseeBootstrapChannel.setGovernanceContract,
                (address(0))
            )
        );
        assert(!ok);
    }

    /// P-BC3 empty-interval idempotent: concrete Month-1 block (Bootstrap A);
    /// the second accrue hits from = b+1 > to = b and returns; also validates
    /// the mock-vault + real-AuMM channel rig runs under hevm.
    function prove_channel_accrue_emptyIntervalIdempotent() public {
        uint256 b = GENESIS + AureumTime.BLOCKS_PER_MONTH;
        vm.roll(b);
        channel.accrue();
        uint256 p1 = channel.pendingAccrual();
        assert(p1 > 0);
        assert(channel.lastAccrualBlock() == b);
        channel.accrue();
        assert(channel.pendingAccrual() == p1);
        assert(channel.lastAccrualBlock() == b);
    }

    /// P-BC3 pre-genesis no-op: at or before genesis from = GENESIS + 1 > to,
    /// the empty-interval guard returns before any AP arithmetic (symbolic b,
    /// early-return tractable).
    function prove_channel_accrue_preGenesisNoOp(uint256 b) public {
        vm.assume(b <= GENESIS);
        vm.roll(b);
        channel.accrue();
        assert(channel.pendingAccrual() == 0);
        assert(channel.lastAccrualBlock() == GENESIS);
    }

    /// P-BC3 post-window clamp: for every post-window block the clamp to =
    /// min(block.number, month10End) resolves to the constant month10End, so
    /// the AP sum runs over the concrete [genesis+1, m10] interval --
    /// symbolic extra, tractable.
    function prove_channel_accrue_postWindowClamp(uint256 extra) public {
        uint256 m10 = AureumTime.month10EndBlock(GENESIS);
        vm.assume(extra >= 1 && extra <= 1_000_000);
        vm.roll(m10 + extra);
        channel.accrue();
        assert(channel.lastAccrualBlock() == m10);
    }
}
