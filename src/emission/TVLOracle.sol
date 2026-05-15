// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IVaultExplorer} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import {ITVLOracle} from "../ccb/ITVLOracle.sol";

/// @title TVLOracle — `ITVLOracle` scaffold (abstract; concrete `tvl()` at H2a.6)
/// @notice svZCHF-denominated pool TVL via Balancer V3 scaled balances, per-token underlying mapping, and constellation balance-ratio averaging per H-D8 + H-D9.
/// @dev H-D8 — constellation roster = `{IMiliariumRegistry roster} ∪ {BODENSEE_POOL} ∪ {governanceAddedPools}`; pre-Stage-J placeholder collapses to `{BODENSEE_POOL} ∪ {governanceAddedPools}` per F-D9 until concrete `IMiliariumRegistry` lands at Stage J. H-D9 — Step 1 reads `IVaultExplorer.getPoolData(pool).balancesLiveScaled18[i]`; Step 2 uses balance-ratio averaging at constellation venues; per-token wrapper → underlying resolution is governance-curated via `tokenToUnderlying`; ERC-4626 `asset()` introspection is rejected as a runtime fallback. OQ-22 (FINDINGS L1106—L1153; L1115 anchors the 2-hop carry-forward deferred out of Phase 1). OQ-8 — `BTC_WRAPPERS` governance-extensible precedent. OQ-5a-bis — daily EMA cadence absorbs per-block α-approximation noise. H-D5 — anti-enumeration applies to the distributor only; oracle siblings may mirror deliberate roster state. Phase 1 = direct venues only. Stage K — governance handoff via `setGovernanceContract`. Contract remains `abstract` with no concrete `tvl()` until H2a.6.
abstract contract TVLOracle is ITVLOracle {
    /* ---------- Immutables ---------- */

    /// @notice Read-only Balancer V3 vault explorer — single entry for `getPoolData` per H-D9 Step 1.
    IVaultExplorer public immutable vaultExplorer;

    /// @notice Immutable der Bodensee pool address — always in the H-D8 constellation union.
    address public immutable BODENSEE_POOL;

    /* ---------- Governance (Stage K) ---------- */

    /// @notice Governance authority — Stage A–K Safe at deploy; rebound via `setGovernanceContract` at Stage K per H-D8.
    address public governance;

    /* ---------- Constellation roster (H-D8) ---------- */

    /// @notice Append-only governance-added constellation venue addresses (roster leg beyond Miliarium + Bodensee).
    address[] internal _governanceAddedPools;

    /// @notice Membership flag for `_governanceAddedPools` entries.
    mapping(address => bool) public isInGovernanceRoster;

    /* ---------- Token → underlying map (H-D9) ---------- */

    /// @notice Governance-curated mapping from pool token to valuation underlying (self-map for STANDARD tokens at seed).
    mapping(address => address) public tokenToUnderlying;

    /* ---------- Reverse map: underlying → pools (H-D9) ---------- */

    /// @notice Precomputed reverse index from underlying to constellation pools — rebuilt when roster or `tokenToUnderlying` changes.
    mapping(address => address[]) internal _underlyingToPools;

    /// @inheritdoc ITVLOracle
    function tvl(address pool) external view virtual override returns (uint256);
}
