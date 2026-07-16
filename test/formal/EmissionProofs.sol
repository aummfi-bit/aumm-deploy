// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {AuMM} from "src/token/AuMM.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

/// @title  EmissionProofs
/// @notice hevm symbolic proofs for the emission-accrual surface AuMM cohort
///         (PB2.12e / PB-D17). Invoke: hevm test --match prove_ --solver bitwuzla
///         (curve/cap arithmetic) or z3 (address-logic).
/// @dev    Tier-1 of the emission-accrual surface (PB2.12e / PB-D17). The P-A*
///         namespace lands here (AuMM only); P-R*/P-ED* land at e2 and P-BC* at
///         e3. P-D* is deliberately unused (collides with Stage-P planning
///         codes). The three STAGES_OVERVIEW L411 candidates map P-A1 = 21M
///         cap, P-A4 = halving curve, with the no-admin-redirect candidate
///         landing at e2 (P-ED1/P-R1). Solver note: address-logic proofs green
///         under z3; curve/cap arithmetic is canonical under bitwuzla 0.9.1
///         (constant-divisor class per the d1-d2 lesson). Modeling note:
///         setMinter's C-D11 two-flag lock makes post-bind rejection
///         caller-universal with NO EVM-sender axiom (either flag alone
///         blocks, unlike the F-D20 single-flag seal at P-M1), while the
///         PRE-bind mint gate does need caller != address(0) because the
///         unbound minter slot IS the zero address.
contract EmissionProofs is Test {
    AuMM internal aumm;

    uint256 internal constant GENESIS = 1_000_000;
    address internal constant RECIPIENT = address(0xAAAA);
    uint256 internal constant MAX = 21_000_000e18;

    function setUp() public {
        // Minter UNBOUND; this contract is the C-D11 minter admin.
        aumm = new AuMM(GENESIS, address(this));
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
}
