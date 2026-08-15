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
///      is invoked file-scoped and never swept into a mainnet run. Its base layer is PINNED to generation-1
///      literals per PB-D71 (xiv) rather than read from the environment: a fork pinned at block 11410000 is a
///      photograph, and an env read is a drift channel that broke this fixture when phase A moved the keys to
///      generation 2. Zero `vm.envAddress` reads remain, and `SEPOLIA_RPC_URL` sits in both canonical env sets,
///      so the test runs under either PB-D36 posture with no `cp` dance. It lives under `test/fork/` deliberately
///      rather than in a sibling directory, because D35's unit invocation excludes `test/fork/**` and a new
///      top-level directory would be swept INTO the unit pass, where it would fail for want of a fork URL.
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

    /// @notice Generation-1 base layer, PINNED per PB-D71 (xiv): this fixture is a photograph of block 11410000,
    ///         where these were the live addresses, so they are frozen here by design and must never be updated
    ///         to a later generation. Deployment-record section 1, nonces 93, 94, 95 and 97; svZCHF is the
    ///         generation-stable stub from the committed map, pinned anyway so no env read survives. The Vault
    ///         doubles as the explorer argument exactly as production wires it, DeployStageP deriving
    ///         VAULT_EXPLORER from VAULT.
    address internal constant GEN1_VAULT = 0x9c7e8F56D12823609C28788d4b80a315CcC5fC80;
    address internal constant GEN1_WEIGHTED_POOL_FACTORY = 0xC60E426294a06Fb95a6C1BB7A06219f794AAde8F;
    address internal constant GEN1_AUMM = 0xb8947f2fE2177d36f2f990300106f27c738DFC8D;
    address internal constant GEN1_BODENSEE = 0xD258d7670f2F7B86d4cAdcE20eC922FB2A908798;
    address internal constant SVZCHF_STUB = 0x290a0E1dDc7de7e8588Aa1c15974FBd771c82700;

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
            IVaultExplorer(GEN1_VAULT),
            GEN1_BODENSEE,
            SVZCHF_STUB,
            GEN1_WEIGHTED_POOL_FACTORY,
            GEN1_WEIGHTED_POOL_FACTORY,
            governor,
            new address[](0),
            new address[](0)
        );

        (address[] memory t, address[] memory u) = SepoliaTokenUnderlyings.pairs();

        vm.startPrank(governor);
        for (uint256 i = 0; i < t.length; i++) {
            fixedOracle.setTokenUnderlying(t[i], u[i]);
        }
        fixedOracle.setTokenUnderlying(GEN1_AUMM, GEN1_AUMM);
        fixedOracle.setMiliariumRegistry(registry);
        fixedOracle.addConstellationPool(GEN1_BODENSEE);
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
