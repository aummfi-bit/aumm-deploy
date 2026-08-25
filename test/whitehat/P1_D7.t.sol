// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {GaugeEligibility} from "src/gauge/GaugeEligibility.sol";
import {GaugeEligibilityFixture, MockERC4626Token, MockWeightedPool} from "test/unit/GaugeEligibility.t.sol";

/// @notice Reproduction PoC for seam-1 root cause D.7 (Low + Info). Entry conditions are not
///         membership conditions: `TVL_FLOOR_SVZCHF` is read at exactly one site, reachable only
///         from admission, and the eligibility certificate it earns is never re-tested and never
///         cleared. `evaluateEligibility` is the contract's only unguarded state-writing function
///         and it is write-true-or-revert, carrying no branch that writes false.
/// @dev NOT reproduced, and each is a source-structure fact rather than a state trajectory: that
///      the constitution's four-consecutive-disqualified-epoch automatic revocation
///      (`10_constitution.md:58`) exists nowhere in `src/`; that `revokeGauge` has exactly two call
///      sites, `AureumGovernance.sol:427` and `:431`, both governance-gated, so no permissionless
///      demotion path exists; and that the floor reads spot `tvl` rather than the gated EMA, which
///      is D.1/D.3/D.4 substrate rather than this row's. A missing feature cannot be driven, so
///      those are stated here and carried by the row's fix intent.
/// @dev The Info half is downgraded BY THE REPORT and this file does not overstate it.
///      `isEligible`, `isGaugeEligible` and `lastSnapshotEpoch` have ZERO readers anywhere in
///      `src/` or `script/` outside the getter's own body, and `GaugeRegistry.activateGauge`
///      consumes the return value inside a `try/catch`, so a pre-set certificate today buys a
///      public boolean carrying no authority. It is reportable because the moment any later stage
///      reads `isEligible` it becomes a live admission bypass, not because it is one now.
/// @dev PP10 — the inherited fixture's shims are substrate only and disable nothing under test:
///      `getHooksConfig` and `getPoolTokens` are Vault reads, `MockBasePoolFactory` is provenance,
///      `MockVaultClassRegistry` is the 4626 admission set, and `MockTVLOracle` is the knob the row
///      requires, TVL being the quantity that has to move. `GaugeEligibility` itself is real, and
///      the floor comparison and the certificate write are its own code.
contract P1_D7_TvlFloorIsAnEntryConditionNotAMembershipConditionTest is GaugeEligibilityFixture {
    /// @dev Mirrors the unit file's `_wirePool`, deliberately rather than inheriting it: that helper
    ///      lives on a CONCRETE test contract whose whole matrix would then re-run under this file's
    ///      path. Wires a pool that clears every gate in `_checkEligibilityCriteria` and sits at
    ///      exactly the floor.
    function _wirePoolAtFloor() internal returns (address pool) {
        MockWeightedPool weightedPool = new MockWeightedPool();
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;
        weightedPool.setNormalizedWeights(weights);
        pool = address(weightedPool);

        MockERC4626Token token = new MockERC4626Token(makeAddr("p1_d7_underlying_asset"));
        mockVaultClassRegistry.setAdmittedClass(address(token), true);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        vm.mockCall(vault, abi.encodeWithSignature("getPoolTokens(address)", pool), abi.encode(tokens));
        mockFactory.setPoolFromFactory(pool, true);
        mockTvlOracle.setTvl(pool, eligibility.TVL_FLOOR_SVZCHF());
        vm.mockCall(
            feeRoutingHook,
            abi.encodeWithSignature("poolBodenseeDepositToken(address)", pool),
            abi.encode(makeAddr("p1_d7_bodensee_rail"))
        );
    }

    /// @notice The Low face. The floor admits, and nothing afterwards asks the question again.
    function test_P1_D7_theTvlFloorIsAnEntryConditionAndTheCertificateOutlivesIt() public {
        uint256 floor = eligibility.TVL_FLOOR_SVZCHF();

        // Control. The floor really is load-bearing at admission, so the pass below is the
        // condition being met rather than the check being absent.
        address belowFloor = _wirePoolAtFloor();
        mockTvlOracle.setTvl(belowFloor, floor - 1);
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.TVLFloorNotMet.selector, floor - 1, floor));
        eligibility.evaluateEligibility(belowFloor);

        // Admission at exactly the floor. The comparison is a strict less-than, so the boundary is
        // admitted rather than rejected.
        address pool = _wirePoolAtFloor();
        assertTrue(eligibility.evaluateEligibility(pool), "admitted at the floor");
        assertTrue(eligibility.isEligible(pool), "certificate written at admission");

        // The pool's TVL now goes to zero, far below the bar it was admitted on.
        mockTvlOracle.setTvl(pool, 0);
        assertEq(mockTvlOracle.tvl(pool), 0, "premise: the pool is now worth nothing");
        assertTrue(eligibility.isEligible(pool), "the certificate outlives the condition that earned it");

        // The one permissionless entry cannot correct the record downward. It reverts on the very
        // criteria failure that ought to demote the pool, and there is no branch anywhere that
        // writes the certificate false.
        vm.expectRevert(abi.encodeWithSelector(GaugeEligibility.TVLFloorNotMet.selector, uint256(0), floor));
        eligibility.evaluateEligibility(pool);
        assertTrue(eligibility.isEligible(pool), "still certified after the re-evaluation reverted");
    }

    /// @notice The Info face. No access control, and the write is a permanent latch.
    function test_P1_D7_anyStrangerWritesThePermanentEligibilityCertificate() public {
        address pool = _wirePoolAtFloor();
        address stranger = makeAddr("p1_d7_stranger_not_the_gauge_registry");

        // The caller is not the principal the fix intent would gate this entry on.
        assertNotEq(stranger, eligibility.gaugeRegistry(), "premise: the caller is not the registry");
        assertFalse(eligibility.isEligible(pool), "premise: no certificate yet");

        vm.prank(stranger);
        assertTrue(eligibility.evaluateEligibility(pool), "an unrelated caller writes the certificate");
        assertTrue(eligibility.isEligible(pool), "certificate is live");
        assertEq(
            eligibility.lastSnapshotEpoch(pool),
            eligibility.currentSnapshotEpoch(),
            "and the caller stamps the snapshot epoch alongside it"
        );
    }
}
