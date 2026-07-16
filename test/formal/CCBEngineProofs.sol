// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {EMASampler} from "src/ccb/EMASampler.sol";
import {ITVLOracle} from "src/ccb/ITVLOracle.sol";
import {CCBScore} from "src/ccb/CCBScore.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

/// @notice Minimal TVL-oracle stub with a settable tvl() return, so a proof can
///         drive EMASampler.updateEMA with symbolic spot values. Not declared
///         `is ITVLOracle` -- EMASampler only calls tvl(), and the ITVLOracle
///         cast at construction dispatches by selector, so quoteSvZCHF is unused.
contract MockTVLOracleProof {
    uint256 private _ret;

    function setTvl(uint256 v) external {
        _ret = v;
    }

    function tvl(address) external view returns (uint256) {
        return _ret;
    }
}

/// @title  CCBEngineProofs
/// @notice hevm symbolic proofs for the S7 CCB / EMA engine (PB2.12d / PB-D17).
/// @dev    Tier-1 of the S7 roster. PB2.12d1 validated the multi-call rig:
///         P-E1 (the EMASampler convex-hull bound, a mock-oracle-driven
///         two-call symbolic update) is PROVEN under bitwuzla 0.9.1 -- the
///         canonical solver for the arithmetic surfaces (z3 4.15.4 returns
///         unknown on the division steps; the S5 hook's address-logic proofs
///         stay as-run under z3). P-S1 (the CCBScore identity) exits as a
///         NAMED RESIDUAL per PB-D17(iv) -- see residual_score_identity.
///         P-E2/P-E3/P-S2 + the CCBMultiplier registry lock (P-M1) land at
///         PB2.12d3.
contract CCBEngineProofs is Test {
    EMASampler internal ema;
    MockTVLOracleProof internal oracle;

    address internal constant POOL = address(0xF00D);

    function setUp() public {
        oracle = new MockTVLOracleProof();
        ema = new EMASampler(ITVLOracle(address(oracle)));
    }

    /// P-E1 convex-hull: one smoothed updateEMA step keeps the EMA within the
    /// [old, spot] hull -- newEMA = (2*spot + 59*old)/61 lies between them, the
    /// anti-manipulation bound (a single sample cannot push the EMA past spot).
    /// Inputs bounded to 1e30 so the checked 2*spot + 59*old cannot overflow.
    function prove_ema_convexHull(uint256 old, uint256 spot) public {
        vm.assume(old <= 1e30);
        vm.assume(spot <= 1e30);

        // Seed the EMA to `old` (the first update takes the seed path).
        vm.roll(AureumTime.BLOCKS_PER_DAY);
        oracle.setTvl(old);
        ema.updateEMA(POOL);
        assert(ema.tvlEMA(POOL) == old);

        // One smoothed step against `spot`.
        vm.roll(block.number + AureumTime.BLOCKS_PER_DAY);
        oracle.setTvl(spot);
        uint256 newEMA = ema.updateEMA(POOL);

        uint256 lo = old < spot ? old : spot;
        uint256 hi = old < spot ? spot : old;
        assert(newEMA >= lo);
        assert(newEMA <= hi);
    }

    /// P-S1 score identity (NAMED RESIDUAL per PB-D17(iv)): the F-5 score at
    /// the unit multiplier (1e18) is the TVL EMA itself --
    /// CCBScore.score(t, 1e18) == t.
    ///
    /// Solver-unknown, not a counterexample: z3 4.15.4 (120s) and bitwuzla
    /// 0.9.1 (300s, then 900s) all return unknown; cvc5 has no Homebrew
    /// formula on the build host. The hard query is not Aureum logic:
    /// Balancer FixedPoint.mulDown's internal overflow guard performs a
    /// variable-by-variable 256-bit division (product / a == b), the class
    /// bv solvers handle worst. That guard is audited Balancer substrate
    /// under the CLAUDE.md section-1 audit-inheritance posture; the
    /// Aureum-owned composition (score = tvlEMA x multiplier, fixed-point)
    /// is stated in the S7 .act spec, and the identity is concretely pinned
    /// in the CCBScore unit tests. Renamed off the prove_ prefix so the
    /// default hevm invocation stays green; retryable firm-side via
    /// hevm test --prefix residual.
    function residual_score_identity(uint256 t) public {
        vm.assume(t <= 1e30);
        assert(CCBScore.score(t, 1e18) == t);
    }
}
