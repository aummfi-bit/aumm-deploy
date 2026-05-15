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

    /* ---------- Errors ---------- */

    /// @notice Reverts when a zero address is supplied for an immutable or the initial governance slot.
    error ZeroAddress();

    /// @notice Reverts when seed array lengths mismatch (`_tokensSeed.length != _underlyingsSeed.length`).
    error ArrayLengthMismatch();

    /// @notice Reverts when a non-governance address invokes a governance-only entry point.
    error NotGovernance(address caller);

    /* ---------- Events ---------- */

    /// @notice Emitted when `setGovernanceContract` rebinds the `governance` authority (Stage K handoff per H-D8).
    event GovernanceTransferred(address indexed oldGovernance, address indexed newGovernance);

    /* ---------- Modifiers ---------- */

    /// @notice Restricts execution to the current `governance` authority; reverts `NotGovernance(msg.sender)` otherwise.
    /// @dev H-D8 — `setGovernanceContract`-pivoting governance slot mirroring Stage G `GaugeRegistry` precedent.
    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance(msg.sender);
        _;
    }

    /* ---------- Constructor ---------- */

    /**
     * @notice Wires `vaultExplorer`, `BODENSEE_POOL`, initial `governance`, and genesis `tokenToUnderlying` mappings per H-D9.
     * @dev `_governanceAddedPools` initial seed remains deferred to a later H2a sub-step. If `_tokensSeed.length != _underlyingsSeed.length`, reverts with `ArrayLengthMismatch`. Zero-address inputs for immutables or governance revert with `ZeroAddress`.
     * @param _vaultExplorer Balancer V3 `IVaultExplorer` — read entry for `getPoolData` / `balancesLiveScaled18` per H-D9 Step 1.
     * @param _bodenseePool Der Bodensee pool address — immutable constellation member per H-D8.
     * @param _initialGovernance Initial governance — Stage A–K Authorizer Safe at deploy; Stage K rebind via `setGovernanceContract` per H-D8.
     * @param _tokensSeed Tokens whose wrapper → underlying mapping is seeded at construction per H-D9 (STANDARD tokens use self-mapping where `_tokensSeed[i] == _underlyingsSeed[i]`).
     * @param _underlyingsSeed Per-index underlying address corresponding to `_tokensSeed[i]`; `_tokensSeed.length` must equal `_underlyingsSeed.length`.
     */
    constructor(
        IVaultExplorer _vaultExplorer,
        address _bodenseePool,
        address _initialGovernance,
        address[] memory _tokensSeed,
        address[] memory _underlyingsSeed
    ) {
        if (address(_vaultExplorer) == address(0)) revert ZeroAddress();
        if (_bodenseePool == address(0)) revert ZeroAddress();
        if (_initialGovernance == address(0)) revert ZeroAddress();

        if (_tokensSeed.length != _underlyingsSeed.length) revert ArrayLengthMismatch();

        vaultExplorer = _vaultExplorer;
        BODENSEE_POOL = _bodenseePool;
        governance = _initialGovernance;

        for (uint256 i = 0; i < _tokensSeed.length; i++) {
            tokenToUnderlying[_tokensSeed[i]] = _underlyingsSeed[i];
        }
    }

    /* ---------- Governance ---------- */

    /**
     * @notice Stage K migration handoff per H-D8 — rebinds governance authority.
     * @dev `onlyGovernance`-gated; reverts `ZeroAddress` on zero input; emits `GovernanceTransferred(oldGovernance, newGovernance)`.
     * @param newGovernance The new governance authority — typically the on-chain governance contract at Stage K.
     */
    function setGovernanceContract(address newGovernance) external onlyGovernance {
        if (newGovernance == address(0)) revert ZeroAddress();
        address oldGovernance = governance;
        governance = newGovernance;
        emit GovernanceTransferred(oldGovernance, newGovernance);
    }

    /// @inheritdoc ITVLOracle
    function tvl(address pool) external view virtual override returns (uint256);
}
