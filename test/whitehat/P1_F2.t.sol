// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {AuMM} from "src/token/AuMM.sol";
import {IAuMM} from "src/token/IAuMM.sol";
import {AuMMMinterRouter} from "src/token/AuMMMinterRouter.sol";
import {IAuMMMinterRouter} from "src/token/IAuMMMinterRouter.sol";

/// @title P1 F.2 — mint capability vested with no amount policy
/// @notice Reproduction PoC for seam-1 root cause F.2 (Low, downgraded from Medium for want
///         of an independently demonstrated path, kept adjacent to the Critical with impact
///         counted once, and NOT the Critical's root cause). This file reproduces capability
///         and consequence rather than an exploit. PP-D36 orders F.3 before F.2 because a
///         schedule-derived ceiling in `mintFor` must be derived from the corrected schedule,
///         F.3 having measured that schedule at about 24000 AuMM above the cap.
contract P1_F2_MintCapabilityIsVestedWithNoAmountPolicyTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant HEADROOM = 100e18;
    uint256 internal constant ARBITRARY_BOOTSTRAP_MINT = 7e18;
    uint256 internal constant ARBITRARY_DISTRIBUTOR_MINT = 13e18;

    AuMM internal aumm;
    AuMMMinterRouter internal router;

    address internal bootstrapChannel;
    address internal emissionDistributor;
    address internal stranger;
    address internal recipient;

    function setUp() public {
        aumm = new AuMM(GENESIS_BLOCK, address(this));
        bootstrapChannel = makeAddr("bootstrapChannel");
        emissionDistributor = makeAddr("emissionDistributor");
        stranger = makeAddr("stranger");
        recipient = makeAddr("recipient");

        router = new AuMMMinterRouter(
            IAuMM(address(aumm)),
            bootstrapChannel,
            emissionDistributor
        );
        // Mirrors script/DeployStageK.s.sol L156 — one-shot seats the router as minter.
        aumm.setMinter(address(router));
    }

    /// @notice Allowlist is the only gate; no amount is ever inspected.
    function test_P1_F2_theRouterHasNoAmountPolicyAndNoControlSurfaceAtAll() public {
        // mintFor is the ONLY function declared on AuMMMinterRouter, and the contract declares
        // zero functions matching pause, unpause, setRateLimit, setBudget, rotate or setConsumer,
        // so there is no rotation, no pause, no rate limit and no per-consumer budget. AuMM.mint
        // at L112-L116 checks only that the caller is the minter and that the cap is not
        // exceeded, with no per-block or schedule-derived limit, so the cap is the sole backstop.

        assertEq(router.BOOTSTRAP_CHANNEL(), bootstrapChannel, "bootstrap channel fixed at construction");
        assertEq(
            router.EMISSION_DISTRIBUTOR(),
            emissionDistributor,
            "emission distributor fixed at construction"
        );

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAuMMMinterRouter.NotAllowlisted.selector, stranger)
        );
        router.mintFor(recipient, 1e18);

        vm.prank(bootstrapChannel);
        router.mintFor(recipient, ARBITRARY_BOOTSTRAP_MINT);
        assertEq(
            aumm.balanceOf(recipient),
            ARBITRARY_BOOTSTRAP_MINT,
            "bootstrap mint succeeds for any amount; no amount policy"
        );

        vm.prank(emissionDistributor);
        router.mintFor(recipient, ARBITRARY_DISTRIBUTOR_MINT);
        assertEq(
            aumm.balanceOf(recipient),
            ARBITRARY_BOOTSTRAP_MINT + ARBITRARY_DISTRIBUTOR_MINT,
            "distributor mint of a different arbitrary amount also succeeds"
        );
    }

    /// @notice Cap backstop is all-or-nothing: overshoot reverts; exact headroom fills the cap.
    function test_P1_F2_theCapBackstopFailsHardSoAnHonestClaimBecomesUnexecutable() public {
        // EmissionDistributor.claim takes a pool and a recipient and NO amount, and computes
        // the pending figure itself, so a claimant whose pending exceeds remaining headroom
        // cannot ask for less and their claim is permanently unexecutable. This file
        // demonstrates the hard-fail property of the backstop rather than driving a
        // distributor claim to that state, because the row is Low precisely for want of an
        // independently demonstrated path.

        uint256 cap = aumm.MAX_SUPPLY();
        uint256 fill = cap - HEADROOM;

        vm.prank(bootstrapChannel);
        router.mintFor(recipient, fill);

        uint256 remaining = cap - aumm.totalSupply();
        assertEq(remaining, HEADROOM, "remaining headroom is the deliberate small figure");

        vm.prank(emissionDistributor);
        vm.expectRevert(AuMM.SupplyCapExceeded.selector);
        router.mintFor(recipient, HEADROOM + 1);

        vm.prank(emissionDistributor);
        router.mintFor(recipient, HEADROOM);
        assertEq(
            aumm.totalSupply(),
            cap,
            "exact headroom fills the cap; backstop is all-or-nothing with no partial fill"
        );
    }
}
