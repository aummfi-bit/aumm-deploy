// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";


/**
 * @title Sanity
 * @notice Stage A "is the toolchain wired correctly" fork test.
 * @dev This test does NOT deploy anything. It only forks mainnet, instantiates
 *      IVault at the live Balancer V3 mainnet Vault address, and calls one safe
 *      view function. If this passes, Stage A is verifiably done:
 *        - forge can compile against the Balancer V3 interface imports from
 *          the pinned submodule
 *        - the remappings are correct
 *        - the mainnet fork RPC is wired and responsive
 *        - the Balancer V3 Vault exists at the expected address
 *
 *      Run with:
 *          source .env
 *          forge test --fork-url $MAINNET_RPC_URL -vv
 *
 *      If this test fails, STOP. Copy the exact error and ask Claude - do not
 *      try to fix it by guessing.
 */




contract SanityTest is Test {
    /// @notice Canonical Balancer V3 Vault on Ethereum mainnet.
    /// @dev Deployed Dec 4, 2024 via the VaultFactory at
    ///      0xAc27df81663d139072E615855eF9aB0Af3FBD281 using CREATE3. The
    ///      vanity prefix (0xba1333...) comes from mining the CREATE3 salt.
    ///      Verified against multiple chains (mainnet, Arbitrum, Optimism) —
    ///      CREATE3 means the same address lands on every chain that was
    ///      deployed from the same factory+salt.
    address internal constant BALANCER_V3_VAULT_MAINNET =
        0xbA1333333333a1BA1108E8412f11850A5C319bA9;

    function test_VaultExistsAndPauseWindowIsSet() public view {
        // Instantiate the Vault interface at the known mainnet address.
        IVault vault = IVault(BALANCER_V3_VAULT_MAINNET);

        // Call a safe view function. getPauseWindowEndTime is defined in
        // IVaultAdmin and returns the immutable timestamp at which the Vault's
        // pause window ends. It was set at deployment to a timestamp ~4 years
        // in the future, so it must be a non-zero uint32.
        uint32 pauseWindowEndTime = vault.getPauseWindowEndTime();

        assertGt(
            pauseWindowEndTime,
            0,
            "Balancer V3 Vault pauseWindowEndTime is zero - wrong address or not a Vault"
        );

        // Additionally assert that the pause window end time is in the future
        // relative to the forked block. It was deployed Dec 2024 with a ~4 year
        // window, so it should still be valid through late 2028. If this fails,
        // either the fork block is from 2029+ or something is very wrong.
        assertGt(
            uint256(pauseWindowEndTime),
            block.timestamp,
            "Pause window has already ended - fork block may be too late"
        );
    }

    /// @notice Sanity check on the build toolchain itself — forces the compiler
    ///         to resolve the IVault import at compile time, even in the
    ///         degenerate case where no RPC is available and the fork test
    ///         above cannot run.
    function test_IVaultTypeResolves() public pure {
        // If this file compiles, the import resolved and the remapping is
        // correct. This test existing and being callable is the proof.
        assertTrue(true);
    }
}
