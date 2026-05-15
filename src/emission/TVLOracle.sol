// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IVaultExplorer} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    /// @notice Reverts when `addConstellationPool` is called against a pool already in `isInGovernanceRoster`.
    error AlreadyAdded(address pool);

    /* ---------- Events ---------- */

    /// @notice Emitted when `setGovernanceContract` rebinds the `governance` authority (Stage K handoff per H-D8).
    event GovernanceTransferred(address indexed oldGovernance, address indexed newGovernance);

    /// @notice Emitted when governance appends a pool to the H-D8 append-only constellation roster leg (`indexed` for off-chain indexing).
    event ConstellationPoolAdded(address indexed pool);

    /// @notice Emitted on H-D9 governance-curated `tokenToUnderlying` writes; `token`, `oldUnderlying`, and `newUnderlying` are indexed for off-chain reconstruction of mapping history (Solidity 3-indexed-param limit).
    event TokenUnderlyingSet(address indexed token, address indexed oldUnderlying, address indexed newUnderlying);

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

    /* ---------- Constellation management ---------- */

    /**
     * @notice Appends `pool` to the governance leg of the H-D8 constellation roster (`_governanceAddedPools`) — append-only at Stage H.
     * @dev H-D9 — `_underlyingToPools` reverse-map is indexed at write time for Phase 1 direct-venue arithmetic. Reads `vaultExplorer.getPoolTokens(pool)` and appends `pool` under each Vault token's mapped `tokenToUnderlying` resolution; tokens with no `tokenToUnderlying` entry (zero-address resolution) are skipped without reverting — deferred indexing via `setTokenUnderlying` at H2a.6. Reverts `ZeroAddress` when `pool == address(0)`, `AlreadyAdded(pool)` on duplicate. Emits `ConstellationPoolAdded(pool)`.
     * @param pool The constellation venue address to append.
     */
    function addConstellationPool(address pool) external onlyGovernance {
        if (pool == address(0)) revert ZeroAddress();
        if (isInGovernanceRoster[pool]) revert AlreadyAdded(pool);
        isInGovernanceRoster[pool] = true;
        _governanceAddedPools.push(pool);
        IERC20[] memory tokens = vaultExplorer.getPoolTokens(pool);
        for (uint256 i = 0; i < tokens.length; i++) {
            address underlying = tokenToUnderlying[address(tokens[i])];
            if (underlying != address(0)) {
                _underlyingToPools[underlying].push(pool);
            }
        }
        emit ConstellationPoolAdded(pool);
    }

    /* ---------- Token underlying management ---------- */

    /**
     * @notice Post-construction governance write to `tokenToUnderlying` per H-D9 — complements the constructor genesis seed at H2a.3.
     * @dev Governance-curated per-token wrapper → underlying resolution; STANDARD tokens self-map per the H2a.3 seed convention. Reverse-map `_underlyingToPools` staleness is governance's responsibility: callers MUST invoke `setTokenUnderlying` BEFORE `addConstellationPool` for pools that hold `token`, or `_underlyingToPools` retains stale entries under the prior underlying — concrete rebuild deferred per H-D9 Phase 1 direct-venue-only scope and OQ-22 L1115 carry-forward. Reverts `ZeroAddress` when `token == address(0)` or `underlying == address(0)`. Emits `TokenUnderlyingSet(token, oldUnderlying, underlying)`. Clearing (`tokenToUnderlying[token] = address(0)`) is NOT supported at Phase 1 — the map is sticky once set non-zero; a dedicated clear primitive may land post-Phase 1 if needed.
     * @param token The pool token whose valuation underlying is set or updated.
     * @param underlying The non-zero valuation underlying address (`token` may equal `underlying` for STANDARD tokens).
     */
    function setTokenUnderlying(address token, address underlying) external onlyGovernance {
        if (token == address(0)) revert ZeroAddress();
        if (underlying == address(0)) revert ZeroAddress();
        address oldUnderlying = tokenToUnderlying[token];
        tokenToUnderlying[token] = underlying;
        emit TokenUnderlyingSet(token, oldUnderlying, underlying);
    }

    /// @inheritdoc ITVLOracle
    function tvl(address pool) external view virtual override returns (uint256);
}
