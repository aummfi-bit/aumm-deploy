// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {AuMM} from "src/token/AuMM.sol";
import {AuMMMinterRouter} from "src/token/AuMMMinterRouter.sol";
import {IAuMM} from "src/token/IAuMM.sol";
import {EmissionDistributor} from "src/emission/EmissionDistributor.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "src/ccb/ICCBMultiplier.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

/// @title  EmissionProofs
/// @notice hevm symbolic proofs for the emission-accrual surface (PB2.12e /
///         PB-D17). Invoke: hevm test --match prove_ --solver bitwuzla
///         --smt-timeout 300 --max-iterations 10 --root . Multi-call proofs
///         re-visit the target contract's entry pc across separate external
///         calls; the raised bound widens exploration only (cannot mask a
///         counterexample), per the e1 lesson.
/// @dev    Tier-1 of the emission-accrual surface (PB2.12e / PB-D17). The P-A*
///         namespace landed at e1 (AuMM only); P-R*/P-ED* land HERE (e2); P-BC*
///         still at e3. P-D* is deliberately unused (collides with Stage-P
///         planning codes). The three STAGES_OVERVIEW L411 candidates map
///         P-A1 = 21M cap, P-A4 = halving curve; the no-admin-redirect
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

    uint256 internal constant GENESIS = 1_000_000;
    address internal constant RECIPIENT = address(0xAAAA);
    uint256 internal constant MAX = 21_000_000e18;
    address internal constant BOOTSTRAP = address(0xB007);
    address internal constant DISTRIB = address(0xD157);

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
    // setAuMTContractForPool / setGovernanceContract / setIncendiaryRegistry).
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
                EmissionDistributor.setIncendiaryRegistry,
                (address(0xC0DE))
            )
        );
        assert(!ok);

        vm.prank(newGov);
        dist.setIncendiaryRegistry(address(0xC0DE));
        assert(dist.incendiaryRegistry() == address(0xC0DE));
    }

    /// P-ED4 auth gate plus the H-D29 zero-permitted deprecation valve
    /// witnessed positively (deliberate asymmetry with the ZeroAddress-
    /// guarded setters).
    function prove_distributor_setIncendiaryRegistry_gateAndClear(
        address caller,
        address reg
    ) public {
        vm.assume(caller != address(this));

        vm.prank(caller);
        (bool ok, ) = address(dist).call(
            abi.encodeCall(EmissionDistributor.setIncendiaryRegistry, (reg))
        );
        assert(!ok);

        dist.setIncendiaryRegistry(reg);
        assert(dist.incendiaryRegistry() == reg);

        dist.setIncendiaryRegistry(address(0));
        assert(dist.incendiaryRegistry() == address(0));
    }
}
