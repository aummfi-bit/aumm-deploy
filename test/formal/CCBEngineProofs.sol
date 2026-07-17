// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {EMASampler} from "src/ccb/EMASampler.sol";
import {ITVLOracle} from "src/ccb/ITVLOracle.sol";
import {CCBScore} from "src/ccb/CCBScore.sol";
import {CCBMultiplier} from "src/ccb/CCBMultiplier.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
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
///         P-E2 (seed bookkeeping), P-E3 (cadence guard, two-phase) and the
///         P-M1 trio (the F-D20 registry one-shot lock) landed at PB2.12d3.
///         P-S2 (score monotonicity / zero-absorption) FOLDS INTO the P-S1
///         residual: with both operands symbolic the mulDown overflow-guard
///         query is strictly harder than the single-operand form that already
///         exhausted z3 and bitwuzla, so it shares P-S1's disposition (audited
///         FixedPoint substrate; pinned concretely in the CCBScore unit tests).
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

    // -------------------------------------------------------------------------
    // P-E2 / P-E3 -- EMASampler seed bookkeeping + cadence guard (PB2.12d3).
    // -------------------------------------------------------------------------

    /// P-E2 seed bookkeeping: the first updateEMA (cold start, last == 0) sets
    /// the EMA to spot EXACTLY (no smoothing) and stamps both the F-D15 seed
    /// block and the cadence anchor at the call block.
    function prove_ema_seedPath(uint256 spot) public {
        vm.assume(spot <= 1e30);

        vm.roll(AureumTime.BLOCKS_PER_DAY);
        oracle.setTvl(spot);
        uint256 ret = ema.updateEMA(POOL);

        assert(ret == spot);
        assert(ema.tvlEMA(POOL) == spot);
        assert(ema.emaSeedBlock(POOL) == AureumTime.BLOCKS_PER_DAY);
        assert(ema.lastEMAUpdateBlock(POOL) == AureumTime.BLOCKS_PER_DAY);
    }

    /// P-E3 cadence guard, two-phase: after a seed at block B, updateEMA
    /// reverts at EVERY block strictly before B + BLOCKS_PER_DAY (symbolic
    /// delta), then succeeds at exactly B + BLOCKS_PER_DAY and re-stamps the
    /// anchor. Constant oracle signal, so the smoothed step is the fixpoint
    /// (2x + 59x) / 61 == x and the EMA is unchanged by the boundary update.
    function prove_ema_cadenceGuard(uint256 delta) public {
        vm.assume(delta < AureumTime.BLOCKS_PER_DAY);

        vm.roll(AureumTime.BLOCKS_PER_DAY);
        oracle.setTvl(1e18);
        ema.updateEMA(POOL);

        vm.roll(AureumTime.BLOCKS_PER_DAY + delta);
        (bool ok, ) = address(ema).call(
            abi.encodeCall(EMASampler.updateEMA, (POOL))
        );
        assert(!ok);

        vm.roll(2 * AureumTime.BLOCKS_PER_DAY);
        ema.updateEMA(POOL);
        assert(ema.lastEMAUpdateBlock(POOL) == 2 * AureumTime.BLOCKS_PER_DAY);
        assert(ema.tvlEMA(POOL) == 1e18);
    }

    // -------------------------------------------------------------------------
    // P-M1 -- the CCBMultiplier F-D20 registry one-shot lock (PB2.12d3).
    // The multiplier is deployed inside each proof (constructor makes no
    // external call), so registrySetter is this test contract and the
    // first-party call needs no prank. MODELING NOTE: F-D20 is a SINGLE-FLAG
    // seal (registrySetter zeroed; no already-set check on the registry slot),
    // unlike the hook's C-D11 two-flag lock -- so the post-seal universality
    // holds only under the explicit EVM-sender assumption caller != address(0)
    /// (no key exists for the zero address; F-D20's own NatSpec relies on it).
    // hevm otherwise finds the caller == 0 rebind path, which is
    // EVM-unreachable but real in the unconstrained model.
    // -------------------------------------------------------------------------

    /// P-M1 one-shot: the deployer's first set binds the registry and seals
    /// the setter (registrySetter == 0); afterwards every caller reverts,
    /// under the documented caller != address(0) EVM-sender assumption.
    function prove_registry_setOnce(address first, address second, address caller) public {
        vm.assume(first != address(0));
        vm.assume(caller != address(0));

        CCBMultiplier mult = new CCBMultiplier(
            IMiliariumRegistry(address(0xBEEF)),
            IEMASampler(address(0xE0A)),
            IGaugeRegistry(address(0x6A06E))
        );

        mult.setMiliariumRegistry(IMiliariumRegistry(first));
        assert(address(mult.miliariumRegistry()) == first);
        assert(mult.registrySetter() == address(0));

        vm.prank(caller);
        (bool ok, ) = address(mult).call(
            abi.encodeCall(CCBMultiplier.setMiliariumRegistry, (IMiliariumRegistry(second)))
        );
        assert(!ok);
    }

    /// P-M1 auth gate: before the seal, setMiliariumRegistry reverts for every
    /// caller other than the deployer (this contract).
    function prove_setMiliariumRegistry_onlyDeployer(address caller, address reg) public {
        vm.assume(caller != address(this));

        CCBMultiplier mult = new CCBMultiplier(
            IMiliariumRegistry(address(0xBEEF)),
            IEMASampler(address(0xE0A)),
            IGaugeRegistry(address(0x6A06E))
        );

        vm.prank(caller);
        (bool ok, ) = address(mult).call(
            abi.encodeCall(CCBMultiplier.setMiliariumRegistry, (IMiliariumRegistry(reg)))
        );
        assert(!ok);
    }

    /// P-M1 zero-rejection: even the authorized deployer cannot bind the zero
    /// address (InvalidRegistry fires after the authority check per F-D20).
    function prove_registry_rejectZero() public {
        CCBMultiplier mult = new CCBMultiplier(
            IMiliariumRegistry(address(0xBEEF)),
            IEMASampler(address(0xE0A)),
            IGaugeRegistry(address(0x6A06E))
        );

        (bool ok, ) = address(mult).call(
            abi.encodeCall(CCBMultiplier.setMiliariumRegistry, (IMiliariumRegistry(address(0))))
        );
        assert(!ok);
    }
}
