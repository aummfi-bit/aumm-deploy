// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";

import { TVLOracle } from "../src/emission/TVLOracle.sol";
import { SepoliaTokenUnderlyings } from "./config/SepoliaTokenUnderlyings.sol";

/**
 * @title WireTVLOracleSepolia
 * @notice Seeds the live-Sepolia `TVLOracle` valuation wiring per PB-D45 — the 59 committed `tokenToUnderlying`
 *         entries of `SepoliaTokenUnderlyings`, then `addConstellationPool` for der Bodensee, then
 *         the single `addHopUnderlying` seed of PB-D43 (vi). Rung f of the PB3.8 ladder.
 *
 * @dev SEPOLIA ONLY. `run()` reverts `WrongChain` unless `block.chainid` is 11155111, before it reads
 *      an address or sends a transaction (PB-D45 (ii)). `block.chainid` is preferred over the PB-D36
 *      environment marker because it is reported by the node actually executing the call and so
 *      cannot disagree with the chain being written to.
 *
 * @dev Two phases per PB-D45 (iii). Phase one verifies all 59 committed pairs read-only, accumulating every
 *      mismatch rather than reverting on the first, and aborts with the total count — so an operator
 *      sees the whole picture in one run, with no state changed. Phase two writes only on a clean
 *      phase one. The per-entry rule follows PB-D42's convention: where token and underlying differ
 *      the entry is a WITH_RATE wrapper and its live `asset()` must equal the committed underlying;
 *      where they are equal it is a self-map with nothing to dereference. The split is NOT a proxy
 *      for ERC-4626-ness — svZCHF is a genuine share that self-maps by the PB-D42 (iii) exception.
 *
 * @dev Idempotent per PB-D45 (iv). Both roster setters revert `AlreadyAdded` on a duplicate, so each
 *      is guarded by its public membership read, and map entries already holding the intended value
 *      are skipped. The sequence is re-runnable after any interruption and re-sends only what is
 *      missing — which on a balance-constrained deployer is the difference between finishing and
 *      stalling again.
 *
 * @dev Ordering is enforced here rather than left to the operator per PB-D45 (v): all 60 writes, the 59 committed pairs plus the env-derived AuMM self-map,
 *      precede the roster call, because `addConstellationPool` indexes the pool only under tokens
 *      whose `tokenToUnderlying` already resolves non-zero and skips the rest with no revert and no
 *      event (`TVLOracle` L171-L177, warned at its own L198 and L163 NatSpec).
 *
 * @dev der Bodensee is read from the oracle's own immutable rather than from an environment key,
 *      which sidesteps the P-D25 env-key divergence for that pool and guarantees the roster call
 *      targets exactly the pool the oracle itself considers der Bodensee.
 *
 * @dev AuMM is derived from the environment rather than from `SepoliaTokenUnderlyings` per PB-D71: it
 *      is the one address that changes every deployment generation by construction, and a committed
 *      table carrying it is what left generation 2's der Bodensee indexed under two of its three legs.
 *      `run()` self-maps the live value inside the same broadcast, then refuses to roster der Bodensee
 *      unless every leg `getPoolTokens` reports resolves non-zero — positive and generation-agnostic,
 *      so ANY wrong `AUMM` value fails there, with no abandoned-address list to grow (PB-D71 (xiii)).
 *      The gate is deliberately post-write: a fresh oracle is all zeros, so the same assertion in
 *      phase one would revert every first run vacuously.
 *
 * @dev Env vars required (no defaults — a real broadcast must never silently fall back to zero):
 *
 *        TVL_ORACLE           address — the live Sepolia TVLOracle
 *        GOVERNANCE_MULTISIG  address — the oracle's governance; asserted before any write
 *        AUMM                 address — the live AuMM; self-mapped here, never committed to a table
 */
contract WireTVLOracleSepolia is Script {
    /// @notice Sepolia chain id; `run()` refuses to execute anywhere else (PB-D45 (ii)).
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;

    /// @notice Index of the sUSDS entry in the committed map, whose resolved underlying is the one
    ///         hop intermediate of PB-D43 (vi).
    uint256 internal constant HOP_INDEX = 0;

    /// @notice The single hop intermediate, copied from the derivation log and cross-checked against
    ///         the committed map at `HOP_INDEX`, so a reordering of either fails loudly rather than
    ///         seeding a hop nothing resolves to (PB-D43 (ii), RB-012).
    address internal constant HOP_UNDERLYING = 0xCc72810e4A91D2BDba70B380C9c41327D0E63169;

    /// @notice Thrown when a der Bodensee pool token maps to the zero address after the map writes.
    error UnmappedBodenseeLeg(address token);

    /// @notice Thrown when executed against any chain other than Sepolia.
    error WrongChain(uint256 actual, uint256 expected);

    /// @notice Thrown when the configured governor is not the oracle's live `governance`.
    error NotOracleGovernance(address configured, address onChain);

    /// @notice Thrown when the committed map's hop entry disagrees with `HOP_UNDERLYING`.
    error HopSeedMismatch(address expected, address inMap);

    /// @notice Thrown after phase one when any entry failed its live check; carries the total.
    error VerificationFailed(uint256 mismatchCount);

    /// @notice `forge script` entry — verifies all 59 committed pairs, self-maps the env-derived AuMM, then wires the oracle.
    function run() external {
        if (block.chainid != SEPOLIA_CHAIN_ID) revert WrongChain(block.chainid, SEPOLIA_CHAIN_ID);

        TVLOracle oracle = TVLOracle(vm.envAddress("TVL_ORACLE"));
        address governor = vm.envAddress("GOVERNANCE_MULTISIG");

        address onChainGovernance = oracle.governance();
        if (onChainGovernance != governor) revert NotOracleGovernance(governor, onChainGovernance);

        address aumm = vm.envAddress("AUMM");

        (address[] memory t, address[] memory u) = SepoliaTokenUnderlyings.pairs();
        if (u[HOP_INDEX] != HOP_UNDERLYING) revert HopSeedMismatch(HOP_UNDERLYING, u[HOP_INDEX]);

        uint256 mismatches = _verifyAll(t, u);
        if (mismatches != 0) revert VerificationFailed(mismatches);

        vm.startBroadcast(governor);
        uint256 written = _writeMap(oracle, t, u);
        written += _writeAuMM(oracle, aumm);
        _assertBodenseeLegsMapped(oracle);
        bool rosterSent = _addRoster(oracle);
        bool hopSent = _addHop(oracle);
        vm.stopBroadcast();

        console2.log("map entries written:", written);
        console2.log("constellation roster call sent:", rosterSent);
        console2.log("hop roster call sent:", hopSent);
    }

    /// @dev Phase one — read-only. Logs every mismatch and returns the total; never reverts early.
    function _verifyAll(address[] memory t, address[] memory u) internal view returns (uint256 mismatches) {
        for (uint256 i = 0; i < t.length; i++) {
            if (t[i] == u[i]) continue;
            try IERC4626(t[i]).asset() returns (address live) {
                if (live != u[i]) {
                    console2.log("MISMATCH at index", i);
                    console2.log("  token", t[i]);
                    console2.log("  committed", u[i]);
                    console2.log("  live asset", live);
                    mismatches++;
                }
            } catch {
                console2.log("NOT ERC4626 at index", i);
                console2.log("  token", t[i]);
                mismatches++;
            }
        }
    }

    /// @dev Phase two, first part — writes only entries not already holding the intended value.
    function _writeMap(TVLOracle oracle, address[] memory t, address[] memory u)
        internal
        returns (uint256 written)
    {
        for (uint256 i = 0; i < t.length; i++) {
            if (oracle.tokenToUnderlying(t[i]) == u[i]) continue;
            oracle.setTokenUnderlying(t[i], u[i]);
            written++;
        }
    }

    /// @dev Phase two, second part — der Bodensee as a constellation venue, strictly after the map.
    function _addRoster(TVLOracle oracle) internal returns (bool sent) {
        address bodensee = oracle.BODENSEE_POOL();
        if (oracle.isInGovernanceRoster(bodensee)) return false;
        oracle.addConstellationPool(bodensee);
        return true;
    }

    /// @dev Phase two, third part — the single PB-D43 (vi) hop intermediate.
    function _addHop(TVLOracle oracle) internal returns (bool sent) {
        if (oracle.isHopUnderlying(HOP_UNDERLYING)) return false;
        oracle.addHopUnderlying(HOP_UNDERLYING);
        return true;
    }

    /// @dev Live AuMM self-map; skipped when the slot already holds it (PB-D71).
    function _writeAuMM(TVLOracle oracle, address aumm) internal returns (uint256 written) {
        if (oracle.tokenToUnderlying(aumm) == aumm) return 0;
        oracle.setTokenUnderlying(aumm, aumm);
        return 1;
    }

    /// @dev Post-write: every der Bodensee leg must resolve non-zero before the roster call (PB-D71).
    function _assertBodenseeLegsMapped(TVLOracle oracle) internal view {
        address bodensee = oracle.BODENSEE_POOL();
        IERC20[] memory tokens = oracle.vaultExplorer().getPoolTokens(bodensee);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (oracle.tokenToUnderlying(address(tokens[i])) == address(0)) revert UnmappedBodenseeLeg(address(tokens[i]));
        }
    }
}
