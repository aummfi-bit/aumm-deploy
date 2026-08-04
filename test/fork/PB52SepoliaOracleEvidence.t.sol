// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IVaultExplorer} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import {TVLOracle} from "../../src/emission/TVLOracle.sol";
import {ITVLOracle} from "../../src/ccb/ITVLOracle.sol";
import {IMiliariumRegistry} from "../../src/ccb/IMiliariumRegistry.sol";
import {IMiliariumSlotRegistry} from "../../src/registry/IMiliariumSlotRegistry.sol";
import {SepoliaPhase4Addresses} from "../../script/config/SepoliaPhase4Addresses.sol";
import {SepoliaTokenUnderlyings} from "../../script/config/SepoliaTokenUnderlyings.sol";

/// @title PB52SepoliaOracleEvidence — the PB-D52 (viii) evidence test for the PB-D50 weight-term fix
/// @notice Forks live Sepolia after the rung-i2 seeding, stands up a CORRECTED `TVLOracle` in process against the
///         real seeded pool state, and reads it beside the live pre-fix oracle. Pool state is held fixed and only
///         the estimator varies, which is why PB-D52 (viii) prefers this over a live re-read: the two readings
///         differ in exactly one thing.
/// @dev THE ONLY SEPOLIA-FORK TEST IN THE TREE. Every other file under `test/fork/` forks mainnet, so this one
///      must be invoked file-scoped with `--fork-url sepolia` and never swept into a mainnet run. It also requires
///      `.env` to be the Sepolia canonical set (`cp .env.sepolia .env`, never the reverse) per PB-D36, since it
///      reads the base layer through `vm.envAddress`. It lives under `test/fork/` deliberately rather than in a
///      sibling directory, because D35's unit invocation excludes `test/fork/**` and a new top-level directory
///      would be swept INTO the unit pass, where it would fail for want of a fork URL.
///
///      Nothing here re-capitalises a pool, replays a seeding transaction, or writes to the live oracle. The only
///      writes are governance calls on the fresh in-process instance, per PB-D52 (viii)'s re-bind-means-its-own-
///      governance-state-and-nothing-else constraint. Rung i2 stands exactly as broadcast.
contract PB52SepoliaOracleEvidenceTest is Test {
    /// @notice Sepolia chain id, asserted in `setUp` on the PB-D45 (iii) precedent that an on-chain identity check
    ///         beats an environment marker answered off-chain.
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;

    /// @notice Pinned above 11405532, the last block of the rung-i2 seeding, and below the head at authoring time.
    ///         Pinned rather than floating because the whole point is a reproducible measurement.
    uint256 internal constant FORK_BLOCK = 11410000;

    /// @notice ixHelvetia's constellation slot; resolved to an address on chain rather than transcribed.
    uint256 internal constant IX_HELVETIA_SLOT = 1;

    /// @notice ixHelvetia's seeded accounting value: 11,200 svZCHF plus 2,800 sUSDS at the PB-D46 flat convention.
    uint256 internal constant IX_HELVETIA_SEEDED = 14_000e18;

    /// @notice What the live pre-fix oracle reads for ixHelvetia, recorded in PB-D50 (i) and re-read from chain
    ///         before this test was written: 2,800 times the biased 4/3 cross-venue mean, plus 11,200.
    uint256 internal constant IX_HELVETIA_LIVE_BIASED = 14933333333333333332400;

    /// @notice The biased constellation total PB-D50 (i) records across all 26 seeded pools.
    uint256 internal constant CONSTELLATION_LIVE_BIASED = 1_271_468e18;

    TVLOracle internal fixedOracle;
    ITVLOracle internal liveOracle;
    IMiliariumRegistry internal registry;
    address internal governor;
    address internal ixHelvetia;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"), FORK_BLOCK);

        assertEq(block.chainid, SEPOLIA_CHAIN_ID, "not forked onto Sepolia");

        registry = IMiliariumRegistry(SepoliaPhase4Addresses.MILIARIUM_REGISTRY);
        liveOracle = ITVLOracle(SepoliaPhase4Addresses.TVL_ORACLE);
        ixHelvetia = IMiliariumSlotRegistry(SepoliaPhase4Addresses.MILIARIUM_REGISTRY).poolAtSlot(IX_HELVETIA_SLOT);
        governor = makeAddr("pb52EvidenceGovernor");

        fixedOracle = new TVLOracle(
            IVaultExplorer(vm.envAddress("AUREUM_VAULT")),
            vm.envAddress("BODENSEE_POOL"),
            vm.envAddress("SV_ZCHF"),
            vm.envAddress("WEIGHTED_POOL_FACTORY"),
            vm.envAddress("AUREUM_WEIGHTED_POOL_FACTORY"),
            governor,
            new address[](0),
            new address[](0)
        );

        (address[] memory t, address[] memory u) = SepoliaTokenUnderlyings.pairs();

        vm.startPrank(governor);
        for (uint256 i = 0; i < t.length; i++) {
            fixedOracle.setTokenUnderlying(t[i], u[i]);
        }
        fixedOracle.setMiliariumRegistry(registry);
        fixedOracle.addConstellationPool(vm.envAddress("BODENSEE_POOL"));
        fixedOracle.addHopUnderlying(u[0]);
        vm.stopPrank();
    }

    /// @notice The premise: the live oracle still reads the biased value PB-D50 (i) recorded.
    /// @dev If this fails, the fork is not the state the finding was made against and every other assertion here
    ///      is measuring something else. It is asserted first for that reason.
    function test_liveOracle_stillReadsTheRecordedBiasedValue() public view {
        assertEq(liveOracle.tvl(ixHelvetia), IX_HELVETIA_LIVE_BIASED, "live oracle no longer reads the PB-D50 value");
    }

    /// @notice The evidence: the corrected oracle prices ixHelvetia at exactly its seeded accounting value.
    /// @dev Exact, not approximate. ixHelvetia's own venue contributes (11,200 times 0.20) over (2,800 times 0.80),
    ///      which is 1.0, and each of the eight equal-weight Standard venues holding both sUSDS and svZCHF also
    ///      contributes 1.0, so the cross-venue mean is exactly 1.0 with no truncation residue and the pool reads
    ///      11,200 plus 2,800. The pre-fix estimator returns 4 at ixHelvetia and 1 at the eight, a mean of 4/3.
    function test_correctedOracle_pricesIxHelvetiaAtExactlyItsSeededValue() public view {
        assertEq(fixedOracle.tvl(ixHelvetia), IX_HELVETIA_SEEDED, "corrected oracle does not read the seeded 14,000");
    }

    /// @notice The same contrast across the whole constellation, and the registry roster it walks.
    /// @dev Bounds rather than an exact figure, because PB-D52 (viii) specifies "near 987,000": the seeded universe
    ///      is 1,000,000 less slot 02's deliberately unpriced allocation. The load-bearing assertion is that the
    ///      corrected sum sits far below the biased one rather than at any particular value.
    function test_correctedOracle_constellationSumFallsNearAccounting() public view {
        uint256 n = registry.miliariumPoolsCount();
        assertEq(n, 26, "registry no longer enumerates the 26 seeded pools");
        uint256 fixedSum;
        uint256 liveSum;
        for (uint256 i = 0; i < n; i++) {
            address pool = registry.miliariumPoolAt(i);
            fixedSum += fixedOracle.tvl(pool);
            liveSum += liveOracle.tvl(pool);
        }
        assertGt(liveSum, fixedSum, "the biased sum should exceed the corrected sum");
        assertGt(liveSum, CONSTELLATION_LIVE_BIASED - 1_000e18, "live sum departs from the PB-D50 recorded total");
        assertLt(fixedSum, 1_050_000e18, "corrected constellation sum is not near the seeded accounting universe");
        assertGt(fixedSum, 900_000e18, "corrected constellation sum is implausibly low");
    }
}
