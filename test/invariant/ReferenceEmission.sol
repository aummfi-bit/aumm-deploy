// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AuMM} from "src/token/AuMM.sol";

/// @title ReferenceEmission — independent re-implementation of the AuMM emission schedule for INV-2 (P-D20).
/// @notice cumulativeAt(genesis, toBlock) = Σ_{b=genesis+1}^{toBlock} blockEmissionRate(b), computed from first
///         principles with its OWN constants — it NEVER reads AuMM.blockEmissionRate or any contract getter, so the
///         P6.5 emission-conservation invariant (totalSupply <= cumulativeAt) is a non-circular schedule ceiling
///         (process-doc §10). Deliberately duplicates GENESIS_RATE / BLOCKS_PER_ERA rather than importing them, so a
///         regression in the contract-under-test's schedule cannot silently propagate into the oracle.
library ReferenceEmission {
    uint256 internal constant GENESIS_RATE = 1e18;
    uint256 internal constant BLOCKS_PER_ERA = 10_512_000;

    /// @notice Closed-form per-era sum of scheduled AuMM emission over the half-open interval (genesisBlock, toBlock].
    /// @dev Era e covers [genesisBlock + e*BPE, genesisBlock + (e+1)*BPE - 1] at rate GENESIS_RATE >> e. Sums each
    ///      era's overlap with (genesisBlock, toBlock]. Terminates at the era containing toBlock (eraEnd >= toBlock)
    ///      or when the halving drives the rate to 0 (e >= 60 for a 1e18 genesis rate); the e < 256 bound mirrors
    ///      AuMM's defensive era guard. Pure — no state, no external call.
    function cumulativeAt(uint256 genesisBlock, uint256 toBlock) internal pure returns (uint256 total) {
        if (toBlock <= genesisBlock) return 0;
        uint256 from = genesisBlock + 1;
        for (uint256 e = 0; e < 256; e++) {
            uint256 rate = GENESIS_RATE >> e;
            if (rate == 0) break;
            uint256 eraStart = genesisBlock + e * BLOCKS_PER_ERA;
            uint256 eraEnd = eraStart + BLOCKS_PER_ERA - 1;
            uint256 lo = eraStart > from ? eraStart : from;
            uint256 hi = eraEnd < toBlock ? eraEnd : toBlock;
            if (lo <= hi) {
                total += rate * (hi - lo + 1);
            }
            if (eraEnd >= toBlock) break;
        }
    }
}

/// @notice Self-check for ReferenceEmission (P-D20) — three hand-computed assertions plus a block-by-block
///         cross-validation against the real AuMM.blockEmissionRate over a halving straddle. This is the ONE place
///         the reference is compared to the contract; the INV-2 invariant then trusts the reference alone.
contract ReferenceEmissionTest is Test {
    uint256 internal constant GENESIS = 1_000_000;
    uint256 internal constant BPE = 10_512_000;

    function test_cumulativeAt_atOrBeforeGenesis_isZero() public pure {
        assertEq(ReferenceEmission.cumulativeAt(GENESIS, GENESIS), 0);
        assertEq(ReferenceEmission.cumulativeAt(GENESIS, GENESIS - 1), 0);
    }

    function test_cumulativeAt_singleEra_handComputed() public pure {
        // 100 blocks into Era 0, each at 1e18.
        assertEq(ReferenceEmission.cumulativeAt(GENESIS, GENESIS + 100), 100e18);
    }

    function test_cumulativeAt_acrossFirstHalving_handComputed() public pure {
        uint256 firstHalving = GENESIS + BPE;
        // (firstHalving-10, firstHalving+10] = 9 Era-0 blocks (1e18) + 11 Era-1 blocks (5e17) = 14.5e18.
        uint256 window = ReferenceEmission.cumulativeAt(GENESIS, firstHalving + 10)
            - ReferenceEmission.cumulativeAt(GENESIS, firstHalving - 10);
        assertEq(window, 14.5e18);
    }

    function test_cumulativeAt_matchesRealAuMMSummed_acrossHalving() public {
        AuMM aumm = new AuMM(GENESIS, address(this));
        uint256 firstHalving = GENESIS + BPE;
        uint256 acc = 0;
        for (uint256 b = firstHalving - 9; b <= firstHalving + 10; b++) {
            acc += aumm.blockEmissionRate(b);
        }
        uint256 refWindow = ReferenceEmission.cumulativeAt(GENESIS, firstHalving + 10)
            - ReferenceEmission.cumulativeAt(GENESIS, firstHalving - 10);
        assertEq(refWindow, acc, "reference matches real AuMM blockEmissionRate summed");
        assertEq(acc, 14.5e18, "AuMM window = 9 Era-0 + 11 Era-1 blocks");
    }
}
