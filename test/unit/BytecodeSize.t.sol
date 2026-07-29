// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

/**
 * @title BytecodeSizeTest
 * @notice The PB-D37 standing deployed-bytecode-size gate: every artifact this project
 *         deploys must fit within EIP-170's 24,576-byte runtime-code limit.
 *
 * @dev Why a test rather than `forge build --sizes` (PB-D37 (ii)): neither compiler
 *      profile can ever exit clean under an unscoped `--sizes`. `[profile.vault]`
 *      compiles Balancer's own `test/` tree, where `VaultMock` stands at 42,408 bytes,
 *      and `[profile.default]` carries twenty over-limit artifacts, every one a test
 *      contract or a deploy script that is never deployed to a chain. Forge exposes no
 *      per-contract exclusion for the flag, so named-artifact assertion is the only
 *      form available.
 *
 * @dev Why the gap existed (PB-D37 (i)): forge does not enforce EIP-170 in simulation,
 *      so a contract too large to deploy to any chain executes normally in every unit
 *      test and every fork test. Deployed size is invisible to the whole pipeline by
 *      construction — which is how a 28,304-byte Vault survived every gate from Stage B
 *      to a funded broadcast.
 */
contract BytecodeSizeTest is Test {
    /// @dev EIP-170 admits code of exactly this length; only a greater length fails.
    uint256 internal constant MAX_CODE_SIZE = 24_576;

    /// @dev Concrete Aureum contracts carrying deployed bytecode. Interfaces are
    ///      excluded (they have none); the three pure libraries are included — they
    ///      sit at 3 bytes.
    uint256 internal constant ROSTER_LENGTH = 27;

    /// @dev Total `.sol` files under `src/`, concrete and interface alike. Pinning this
    ///      makes a newly added contract fail the gate instead of silently escaping the
    ///      roster.
    uint256 internal constant SRC_SOL_FILE_COUNT = 45;

    // The three vault artifacts are named by explicit `out-vault/` path, never by bare
    // identifier: `[profile.default]` holds its own differently-compiled copies of
    // VaultAdmin and VaultExtension, kept permanently in the default compile graph by
    // the concrete-type imports at src/vault/AureumVaultFactory.sol L18-L19 — see
    // PB-D37 (v) and (viii).
    string internal constant VAULT_ARTIFACT = "out-vault/Vault.sol/Vault.json";
    string internal constant VAULT_EXTENSION_ARTIFACT = "out-vault/VaultExtension.sol/VaultExtension.json";
    string internal constant VAULT_ADMIN_ARTIFACT = "out-vault/VaultAdmin.sol/VaultAdmin.json";

    // -----------------------------------------------------------------
    // Vault artifacts (PB-D37 (v), (vii))
    // -----------------------------------------------------------------

    function test_vaultArtifacts_presentOrFailClosed() public view {
        _assertArtifactPresent(VAULT_ARTIFACT);
        _assertArtifactPresent(VAULT_EXTENSION_ARTIFACT);
        _assertArtifactPresent(VAULT_ADMIN_ARTIFACT);
    }

    function test_vaultArtifacts_underMaxCodeSize() public view {
        _assertArtifactPresent(VAULT_ARTIFACT);
        _assertArtifactPresent(VAULT_EXTENSION_ARTIFACT);
        _assertArtifactPresent(VAULT_ADMIN_ARTIFACT);

        _assertUnderMaxCodeSize(VAULT_ARTIFACT);
        _assertUnderMaxCodeSize(VAULT_EXTENSION_ARTIFACT);
        _assertUnderMaxCodeSize(VAULT_ADMIN_ARTIFACT);
    }

    // -----------------------------------------------------------------
    // Aureum artifacts (PB-D37 (vi), (xi))
    // -----------------------------------------------------------------

    function test_aureumArtifacts_underMaxCodeSize() public view {
        string[] memory roster = _aureumRoster();
        for (uint256 i = 0; i < roster.length; ++i) {
            _assertUnderMaxCodeSize(roster[i]);
        }
    }

    function test_aureumRoster_coversEverySourceFile() public view {
        assertEq(_aureumRoster().length, ROSTER_LENGTH, "roster length drifted from ROSTER_LENGTH");
        assertEq(
            _countSolFilesUnderSrc(),
            SRC_SOL_FILE_COUNT,
            "src/ gained or lost a .sol file: update _aureumRoster(), ROSTER_LENGTH and SRC_SOL_FILE_COUNT"
        );
    }

    // -----------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------

    function _assertArtifactPresent(string memory artifactPath) internal view {
        assertTrue(vm.isFile(artifactPath), "vault artifact missing: run FOUNDRY_PROFILE=vault forge build");
    }

    function _assertUnderMaxCodeSize(string memory artifactId) internal view {
        uint256 size = vm.getDeployedCode(artifactId).length;
        assertLe(size, MAX_CODE_SIZE, string.concat("exceeds EIP-170 max code size: ", artifactId));
    }

    function _countSolFilesUnderSrc() internal view returns (uint256 count) {
        Vm.DirEntry[] memory entries = vm.readDir("src", 5);
        for (uint256 i = 0; i < entries.length; ++i) {
            if (!entries[i].isDir && _hasSolExtension(entries[i].path)) {
                ++count;
            }
        }
    }

    function _hasSolExtension(string memory path) internal pure returns (bool) {
        bytes memory b = bytes(path);
        if (b.length < 4) {
            return false;
        }
        return b[b.length - 4] == "." && b[b.length - 3] == "s" && b[b.length - 2] == "o"
            && b[b.length - 1] == "l";
    }

    // The roster is hand-listed by design (PB-D37 (vi)) and each entry names its full
    // source path rather than a bare identifier (PB-D37 (xi)), because
    // ERC4626RateProvider collides by basename with Balancer's test-tree contract of
    // the same name.
    function _aureumRoster() internal pure returns (string[] memory roster) {
        roster = new string[](ROSTER_LENGTH);
        roster[0] = "src/ccb/CCBMultiplier.sol:CCBMultiplier";
        roster[1] = "src/ccb/CCBScore.sol:CCBScore";
        roster[2] = "src/ccb/CCBShare.sol:CCBShare";
        roster[3] = "src/ccb/EMASampler.sol:EMASampler";
        roster[4] = "src/emission/BodenseeBootstrapChannel.sol:BodenseeBootstrapChannel";
        roster[5] = "src/emission/EfficiencyOracle.sol:EfficiencyOracle";
        roster[6] = "src/emission/EmissionDistributor.sol:EmissionDistributor";
        roster[7] = "src/emission/TVLOracle.sol:TVLOracle";
        roster[8] = "src/factory/AureumWeightedPoolFactory.sol:AureumWeightedPoolFactory";
        roster[9] = "src/fee_router/AureumFeeRoutingHook.sol:AureumFeeRoutingHook";
        roster[10] = "src/gauge/GaugeEligibility.sol:GaugeEligibility";
        roster[11] = "src/gauge/GaugeRegistry.sol:GaugeRegistry";
        roster[12] = "src/gauge/SwapAndDepositToBodensee.sol:SwapAndDepositToBodensee";
        roster[13] = "src/gauge/VaultClassRegistry.sol:VaultClassRegistry";
        roster[14] = "src/governance/AureumGovernance.sol:AureumGovernance";
        roster[15] = "src/governance/AureumGovernanceAuthorizer.sol:AureumGovernanceAuthorizer";
        roster[16] = "src/governance/VotingWeight.sol:VotingWeight";
        roster[17] = "src/incendiary/IncendiaryRegistry.sol:IncendiaryRegistry";
        roster[18] = "src/lib/AureumTime.sol:AureumTime";
        roster[19] = "src/rate_provider/CompositeRateProvider.sol:CompositeRateProvider";
        roster[20] = "src/rate_provider/ERC4626RateProvider.sol:ERC4626RateProvider";
        roster[21] = "src/registry/MiliariumRegistry.sol:MiliariumRegistry";
        roster[22] = "src/token/AuMM.sol:AuMM";
        roster[23] = "src/token/AuMMMinterRouter.sol:AuMMMinterRouter";
        roster[24] = "src/vault/AureumAuthorizer.sol:AureumAuthorizer";
        roster[25] = "src/vault/AureumProtocolFeeController.sol:AureumProtocolFeeController";
        roster[26] = "src/vault/AureumVaultFactory.sol:AureumVaultFactory";
    }
}
