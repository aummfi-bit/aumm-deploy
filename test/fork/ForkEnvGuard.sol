// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Vm } from "forge-std/Vm.sol";

/**
 * @title ForkEnvGuard
 * @notice RB-023 clause 3 — the structural environment guard: enforcement rather than discipline,
 *         failing closed at `setUp` instead of at the first on-chain dereference.
 * @dev Covers the two surfaces the RB-023 register row names.
 *      (1) PREFIX POLLUTION / STUB OVERRIDE. A process environment variable beats foundry's dotenv
 *      load, so an exported `STUB_*`, `SUSDS` or `SV_ZCHF` silently redirects a mainnet fork while
 *      `.env` reads clean. Solidity cannot enumerate the process environment, so the check is the
 *      stronger incident-matching form: every address a fixture resolves from env must carry
 *      bytecode ON THIS FORK. That is what fails closed on `0x1AAaA43`, the Sepolia sUSDS stub
 *      whose `setUp` call cost four diagnostic rounds on 2026-08-21 before the environment was
 *      suspected, and one published wrong conclusion.
 *      (2) CHAIN MATCH. The resolved `AUMM_ENV_CHAIN` must equal the chain the fixture was handed.
 *      Cheap and uniform, but NOT sufficient alone: in the 2026-08-21 case `SUSDS` was exported
 *      while `AUMM_ENV_CHAIN` still resolved `mainnet` from `.env`, so a marker-only guard passes.
 *      A LIBRARY, deliberately. Twelve fork fixtures inherit `Test` directly with no common base;
 *      introducing one would change inheritance for every contract beneath them, which is the
 *      collision surface PP3.2u surfaced when `_performSwap` moved into a shared fixture. A library
 *      call site adds no base and no inherited name to any fixture.
 *      PLACEMENT. In a fixture whose `setUp` carries a `vm.computeCreateAddress` prologue, call
 *      this AFTER the last prediction assert, per the PP3.2p placement rule: an inserted call
 *      before them consumes a nonce and breaks every predicted address.
 */
library ForkEnvGuard {
    /// @dev The canonical forge cheatcode address. A library cannot inherit `Test`'s `vm`.
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice The resolved `AUMM_ENV_CHAIN` marker is not the chain this fixture expects.
    error ForkEnvChainMismatch(string expected, string resolved);

    /// @notice An address resolved from env carries no bytecode on this fork.
    error ForkEnvAddressHasNoCode(string key, address resolved);

    /// @dev Asserts the RESOLVED marker, never the file. `vm.envOr` reads the process environment
    ///      first, which is the surface forge itself reads and the one both prior guards missed:
    ///      the runbook check greps `.env` on disk and the CLAUDE.md sentinel named no shell.
    function assertChain(string memory expected) internal view {
        string memory resolved = VM.envOr("AUMM_ENV_CHAIN", string(""));
        if (keccak256(bytes(resolved)) != keccak256(bytes(expected))) {
            revert ForkEnvChainMismatch(expected, resolved);
        }
    }

    /// @dev Resolves `key` and asserts it carries bytecode here. Returns the checked address so a
    ///      caller can consume it rather than resolving the same key twice.
    function assertAddressHasCode(string memory key) internal view returns (address resolved) {
        resolved = VM.envAddress(key);
        if (resolved.code.length == 0) revert ForkEnvAddressHasNoCode(key, resolved);
    }

    /// @dev Both surfaces for a mainnet fork: the marker first, then every address key the calling
    ///      fixture resolves from env.
    function assertMainnetEnv(string[] memory addressKeys) internal view {
        assertChain("mainnet");
        for (uint256 i = 0; i < addressKeys.length; ++i) {
            assertAddressHasCode(addressKeys[i]);
        }
    }
}
