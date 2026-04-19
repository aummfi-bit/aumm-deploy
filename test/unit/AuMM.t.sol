// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";
import {AuMM} from "src/token/AuMM.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

contract AuMMTest is Test {
    using stdStorage for StdStorage;

    AuMM aumm;
    address minterAdmin = address(0xA1);
    address minter      = address(0xB2);
    uint256 constant GENESIS = 20_000_000;

    // ERC20 Transfer event, redeclared for vm.expectEmit
    event Transfer(address indexed from, address indexed to, uint256 value);
    event MinterSet(address indexed minter);

    function setUp() public {
        aumm = new AuMM(GENESIS, minterAdmin);
    }

    // --- constructor ---

    function test_constructor_setsGenesis() public view {
        assertEq(aumm.GENESIS_BLOCK(), GENESIS);
    }

    function test_constructor_setsMinterAdmin() public {
        // _minterAdmin is private; observable proof is that minterAdmin
        // can call setMinter() successfully. Post-call, minter == newMinter.
        vm.prank(minterAdmin);
        aumm.setMinter(minter);
        assertEq(aumm.minter(), minter);
    }

    function test_constructor_doesNotMint() public view {
        assertEq(aumm.totalSupply(), 0);
    }

    function test_constructor_revertsOnZeroMinterAdmin() public {
        // C-D12 — permanent-brick prevention: a zero minterAdmin at
        // construction would leave no address authorised to call setMinter().
        vm.expectRevert(AuMM.ZeroAddress.selector);
        new AuMM(GENESIS, address(0));
    }

    // --- setMinter ---

    function test_setMinter_onlyMinterAdmin_canCall() public {
        // Called from this test contract (not minterAdmin) — reverts.
        vm.expectRevert(AuMM.NotMinterAdmin.selector);
        aumm.setMinter(minter);
    }

    function test_setMinter_revertsIfMinterAlreadySet() public {
        // Defensive check (C-D11): isolates the MinterAlreadySet branch,
        // which is otherwise unreachable in normal flow because a successful
        // setMinter zeroes _minterAdmin atomically. Use stdstore to locate
        // the slot backing the public `minter()` getter and vm.store to
        // write it directly, leaving _minterAdmin intact, then call setMinter
        // from the admin. stdstore.find() resolves the slot at test time,
        // so this stays robust against ERC20 storage-layout drift.
        uint256 slot = stdstore.target(address(aumm)).sig("minter()").find();
        vm.store(address(aumm), bytes32(slot), bytes32(uint256(uint160(address(0xCAFE)))));
        assertEq(aumm.minter(), address(0xCAFE));

        vm.prank(minterAdmin);
        vm.expectRevert(AuMM.MinterAlreadySet.selector);
        aumm.setMinter(minter);
    }

    function test_setMinter_revertsOnZeroAddress() public {
        vm.prank(minterAdmin);
        vm.expectRevert(AuMM.ZeroAddress.selector);
        aumm.setMinter(address(0));
    }

    function test_setMinter_selfLocksAdmin() public {
        // First call succeeds; _minterAdmin is zeroed atomically (C-D11).
        // Second call from the original admin reverts with NotMinterAdmin,
        // not MinterAlreadySet — the admin-identity check fires first once
        // _minterAdmin == address(0). This revert ordering is the observable
        // evidence of the self-lock.
        vm.prank(minterAdmin);
        aumm.setMinter(minter);

        vm.prank(minterAdmin);
        vm.expectRevert(AuMM.NotMinterAdmin.selector);
        aumm.setMinter(address(0xBEEF));
    }

    function test_setMinter_emitsMinterSetEvent() public {
        vm.expectEmit(true, false, false, true);
        emit MinterSet(minter);
        vm.prank(minterAdmin);
        aumm.setMinter(minter);
    }

    // --- mint ---

    function test_mint_revertsBeforeMinterSet() public {
        // Pre-setMinter, minter == address(0); mint() reverts NotMinter
        // for every caller.
        vm.expectRevert(AuMM.NotMinter.selector);
        aumm.mint(address(0xBEEF), 1);
    }

    function test_mint_onlyMinter_canCall() public {
        vm.prank(minterAdmin);
        aumm.setMinter(minter);

        // Called from this test contract (not minter) — reverts.
        vm.expectRevert(AuMM.NotMinter.selector);
        aumm.mint(address(0xBEEF), 1);
    }

    function test_mint_revertsIfExceedsCap() public {
        vm.prank(minterAdmin);
        aumm.setMinter(minter);

        // Cache MAX_SUPPLY — an inline `aumm.MAX_SUPPLY()` inside the
        // mint() arg list would evaluate as an external call and consume
        // the vm.expectRevert / vm.prank set below.
        uint256 cap = aumm.MAX_SUPPLY();

        vm.prank(minter);
        vm.expectRevert(AuMM.SupplyCapExceeded.selector);
        aumm.mint(address(0xBEEF), cap + 1);
    }

    function test_mint_succeedsUpToCap() public {
        // Single-call mint of exactly MAX_SUPPLY. Incremental-mints-summing-
        // to-cap is covered by the invariant fuzzer in C7.3.
        vm.prank(minterAdmin);
        aumm.setMinter(minter);

        // Cache MAX_SUPPLY — see test_mint_revertsIfExceedsCap for why.
        uint256 cap = aumm.MAX_SUPPLY();

        vm.prank(minter);
        aumm.mint(address(0xBEEF), cap);
        assertEq(aumm.totalSupply(), cap);
    }

    function test_mint_emitsTransferEvent() public {
        vm.prank(minterAdmin);
        aumm.setMinter(minter);

        uint256 amount = 1e18;
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(0xBEEF), amount);
        vm.prank(minter);
        aumm.mint(address(0xBEEF), amount);
    }

    // --- blockEmissionRate ---

    function test_blockEmissionRate_preGenesis_isZero() public view {
        assertEq(aumm.blockEmissionRate(GENESIS - 1), 0);
    }

    function test_blockEmissionRate_atGenesis_isGenesisRate() public view {
        assertEq(aumm.blockEmissionRate(GENESIS), aumm.GENESIS_RATE());
    }

    function test_blockEmissionRate_atFirstHalving_isHalfGenesisRate() public view {
        uint256 blk = GENESIS + AureumTime.BLOCKS_PER_ERA;
        assertEq(aumm.blockEmissionRate(blk), aumm.GENESIS_RATE() >> 1);
    }

    function test_blockEmissionRate_era2_isQuarter() public view {
        uint256 blk = GENESIS + 2 * AureumTime.BLOCKS_PER_ERA;
        assertEq(aumm.blockEmissionRate(blk), aumm.GENESIS_RATE() >> 2);
    }

    function test_blockEmissionRate_era5_is_1_over_32() public view {
        uint256 blk = GENESIS + 5 * AureumTime.BLOCKS_PER_ERA;
        assertEq(aumm.blockEmissionRate(blk), aumm.GENESIS_RATE() >> 5);
    }

    function test_blockEmissionRate_era10_is_very_small_but_positive() public view {
        // Derived via GENESIS_RATE >> 10 rather than a hardcoded literal —
        // keeps the assertion structurally tied to the contract's own
        // constants. Era 10 rate is ~9.77e14 wei, strictly positive.
        uint256 blk = GENESIS + 10 * AureumTime.BLOCKS_PER_ERA;
        assertEq(aumm.blockEmissionRate(blk), aumm.GENESIS_RATE() >> 10);
        assertGt(aumm.blockEmissionRate(blk), 0);
    }

    function test_blockEmissionRate_era60_plus_isZero() public view {
        // log2(1e18) ~ 59.79, so 1e18 >> 60 == 0 in uint256. Era 60 is
        // past the natural underflow-to-zero point; covers C-D7.
        uint256 blk = GENESIS + 60 * AureumTime.BLOCKS_PER_ERA;
        assertEq(aumm.blockEmissionRate(blk), 0);
    }

    function test_blockEmissionRate_nonIncreasing_acrossBoundary() public view {
        // Named property test (not an invariant — monotonicity of a pure
        // view function doesn't depend on handler state). Pair straddling
        // the Era 4 to Era 5 boundary.
        uint256 lastOfEra4  = GENESIS + 5 * AureumTime.BLOCKS_PER_ERA - 1;
        uint256 firstOfEra5 = GENESIS + 5 * AureumTime.BLOCKS_PER_ERA;
        assertGe(aumm.blockEmissionRate(lastOfEra4), aumm.blockEmissionRate(firstOfEra5));
    }

    // --- constants ---

    function test_maxSupply_is_21M() public view {
        assertEq(aumm.MAX_SUPPLY(), 21_000_000e18);
    }

    function test_genesisRate_is_1e18() public view {
        assertEq(aumm.GENESIS_RATE(), 1e18);
    }

    // --- fuzz ---

    function testFuzz_blockEmissionRate_eraIndexCorrect(uint64 blockOffset) public view {
        // Bound to <50 eras — far past the natural underflow point but
        // well inside the contract's `era >= 256` guard.
        vm.assume(blockOffset < 50 * AureumTime.BLOCKS_PER_ERA);
        uint256 blk = GENESIS + uint256(blockOffset);
        uint256 era = uint256(blockOffset) / AureumTime.BLOCKS_PER_ERA;
        uint256 expected = era >= 256 ? 0 : aumm.GENESIS_RATE() >> era;
        assertEq(aumm.blockEmissionRate(blk), expected);
    }

    function testFuzz_mint_respectsCap(uint256 amount) public {
        // Minter wired here, not in setUp — the named tests above rely on
        // AuMM being in the pre-setMinter state out of setUp().
        vm.prank(minterAdmin);
        aumm.setMinter(address(this));

        amount = bound(amount, 1, aumm.MAX_SUPPLY() * 2);
        if (amount > aumm.MAX_SUPPLY()) {
            vm.expectRevert(AuMM.SupplyCapExceeded.selector);
            aumm.mint(address(0xBEEF), amount);
        } else {
            aumm.mint(address(0xBEEF), amount);
            assertEq(aumm.totalSupply(), amount);
        }
    }
}

// === Invariant tests ===

contract AuMMInvariantTest is Test {
    AuMM aumm;
    AuMMHandler handler;
    uint256 constant GENESIS = 20_000_000;

    function setUp() public {
        aumm = new AuMM(GENESIS, address(this));
        handler = new AuMMHandler(aumm);
        aumm.setMinter(address(handler));

        // Pin the invariant fuzzer to the handler — without this, Foundry
        // targets every contract deployed in setUp (including aumm itself),
        // which dilutes real handler calls with wasted reverts.
        targetContract(address(handler));
    }

    function invariant_totalSupply_neverExceedsCap() public view {
        assertLe(aumm.totalSupply(), aumm.MAX_SUPPLY());
    }

    function invariant_mint_revertsFromNonMinter() public {
        // If anyone except the handler could mint, the cap invariant would
        // eventually break. This invariant checks the inverse — any direct
        // mint attempt from this test contract (not the handler) must revert.
        vm.expectRevert(AuMM.NotMinter.selector);
        aumm.mint(address(0xBEEF), 1);
    }
}

/// @dev AuMMHandler MUST inherit Test to access bound() — bound() lives in
///      StdUtils, which Test pulls in. A bare contract without `is Test`
///      fails to compile with a missing-symbol error.
contract AuMMHandler is Test {
    AuMM public aumm;

    constructor(AuMM a) {
        aumm = a;
    }

    function mint(address to, uint256 amount) external {
        // Never mint more than remaining cap headroom — lets invariant runs
        // continue past the point where totalSupply approaches MAX_SUPPLY.
        uint256 remaining = aumm.MAX_SUPPLY() - aumm.totalSupply();
        if (remaining == 0) return;
        amount = bound(amount, 1, remaining);
        if (to == address(0)) to = address(0x1234);
        aumm.mint(to, amount);
    }
}
