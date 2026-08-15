// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IVaultExplorer} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import {IBasePoolFactory} from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import {IWeightedPool} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import {PoolData} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITVLOracle} from "../ccb/ITVLOracle.sol";
import {IMiliariumRegistry} from "../ccb/IMiliariumRegistry.sol";

/// @title TVLOracle — concrete `ITVLOracle` implementation per H-D8 + H-D9 (Phase 2 per PB-D7: direct constellation venues + 2-hop fallback)
/// @notice svZCHF-denominated pool TVL via Balancer V3 scaled balances, per-token underlying mapping, and constellation balance-ratio averaging per H-D8 + H-D9.
/// @dev H-D8 — constellation roster enumerated by `_directRatio` = `{IMiliariumRegistry roster} ∪ {governanceAddedPools}`; pre-Stage-J placeholder collapses to `{governanceAddedPools}` alone per F-D9 until concrete `IMiliariumRegistry` lands at Stage J. `BODENSEE_POOL` is stored for identity only and is NEVER in this union — pricing der Bodensee requires an explicit `addConstellationPool(BODENSEE_POOL)` call (PB-D41 (iii)). H-D9 — Step 1 reads `IVaultExplorer.getPoolData(pool).balancesLiveScaled18[i]`; Step 2 uses balance-ratio averaging at constellation venues via `_constellationRatio` (direct venues win; 2-hop fallback on direct-miss per PB-D7); per-token wrapper → underlying resolution is governance-curated via `tokenToUnderlying`; ERC-4626 `asset()` introspection is rejected as a runtime fallback. OQ-22 Phase 2 — hop-underlying roster + `_twoHopRatio` through governance-seeded intermediates (FINDINGS L1119). OQ-8 — `BTC_WRAPPERS` governance-extensible precedent. OQ-5a-bis — daily EMA cadence absorbs per-block α-approximation noise. H-D5 — anti-enumeration applies to the distributor only; oracle siblings may mirror deliberate roster state. Stage K — governance handoff via `setGovernanceContract`.
contract TVLOracle is ITVLOracle {
    /* ---------- Immutables ---------- */

    /// @notice Read-only Balancer V3 vault explorer — single entry for `getPoolData` per H-D9 Step 1.
    IVaultExplorer public immutable vaultExplorer;

    /// @notice Immutable der Bodensee pool address — stored for identity only; NOT auto-enumerated by `_directRatio` (PB-D41 (iii)). Pricing der Bodensee requires an explicit `addConstellationPool(BODENSEE_POOL)` call.
    address public immutable BODENSEE_POOL;

    /// @notice Immutable svZCHF numéraire address per H-D9 — quote currency for all `tvl()` outputs; may itself appear as a constellation pool token (svZCHF dual-role).
    address public immutable SVZCHF;

    /// @notice Immutable canonical weighted-pool factory — one half of the venue provenance gate per PB-D52 (ii) and PB-D57 (v), seeded from `WEIGHTED_POOL_FACTORY`, which per the E-D16 naming trap recorded at `DeployStageG` L62 holds the UPSTREAM Balancer factory and is the same value `GaugeEligibility` receives. Normalized weights are pool-self-reported rather than Vault-authoritative, so a venue claimed by neither approved factory is skipped rather than trusted.
    address public immutable approvedFactory;

    /// @notice Immutable Aureum weighted-pool factory — the other half of the provenance gate per PB-D57 (v), seeded from `AUREUM_WEIGHTED_POOL_FACTORY`. A constellation venue is a pricing source rather than an Aureum-owned asset, so a genuine weighted pool from either factory is trusted; the F-12 hand-rolled spoof is claimed by neither.
    address public immutable approvedFactoryAureum;

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

    /* ---------- Hop-underlying roster (PB-D7, OQ-22 Phase 2) ---------- */

    /// @notice Append-only governance roster of hop intermediates in underlying-key space (PB-D7).
    address[] internal _hopUnderlyings;

    /// @notice Membership flag for `_hopUnderlyings` entries.
    mapping(address => bool) public isHopUnderlying;

    /* ---------- Miliarium registry binding (K-D8) ---------- */

    /// @notice Live Miliarium registry — bound once via `setMiliariumRegistry` at the Stage K (K7) handoff per K-D8; `address(0)` pre-binding, in which case `_directRatio` runs its reverse-map leg only (exact pre-K6 behavior). Once bound, `_directRatio` enumerates this dense view (`miliariumPoolsCount` / `miliariumPoolAt`) as its second leg.
    IMiliariumRegistry public miliariumRegistry;

    /// @notice Governance-pinned authority for the one-shot `setMiliariumRegistry`, F-D20 self-seal mirroring `CCBMultiplier` — set to `_initialGovernance` at construction (the unified governor / `GOVERNANCE_MULTISIG` under `DeployStageF`), self-zeros on the first successful bind so the registry is sealed thereafter. Pinned to the governance identity, not the CREATE agent, per P-D35 (the orchestrator split-identity fix).
    address public registrySetter;

    /* ---------- Errors ---------- */

    /// @notice Reverts when a zero address is supplied for an immutable or the initial governance slot.
    error ZeroAddress();

    /// @notice Reverts when seed array lengths mismatch (`_tokensSeed.length != _underlyingsSeed.length`).
    error ArrayLengthMismatch();

    /// @notice Reverts when a non-governance address invokes a governance-only entry point.
    error NotGovernance(address caller);

    /// @notice Reverts when `addConstellationPool` or `addHopUnderlying` is called against an address already in the respective roster membership map.
    error AlreadyAdded(address pool);

    /// @notice Reverts when `addConstellationPool` is handed a pool holding a Vault token with no `tokenToUnderlying` entry — the H-D9 skip flipped fail-closed per PB-D71 (viii), because an unindexed leg is silent and unrepairable in place.
    error UnmappedPoolToken(address token);

    /// @notice Reverts when `setMiliariumRegistry` is called by a non-`registrySetter` caller — covers pre-seal unauthorized callers and all post-seal callers (F-D20 self-zero mechanic).
    error OnlyRegistrySetter();

    /* ---------- Events ---------- */

    /// @notice Emitted when `setGovernanceContract` rebinds the `governance` authority (Stage K handoff per H-D8).
    event GovernanceTransferred(address indexed oldGovernance, address indexed newGovernance);

    /// @notice Emitted when governance appends a pool to the H-D8 append-only constellation roster leg (`indexed` for off-chain indexing).
    event ConstellationPoolAdded(address indexed pool);

    /// @notice Emitted on H-D9 governance-curated `tokenToUnderlying` writes; `token`, `oldUnderlying`, and `newUnderlying` are indexed for off-chain reconstruction of mapping history (Solidity 3-indexed-param limit).
    event TokenUnderlyingSet(address indexed token, address indexed oldUnderlying, address indexed newUnderlying);

    /// @notice Emitted when `setMiliariumRegistry` binds the live Miliarium registry at the K7 handoff (one-shot per K-D8).
    event MiliariumRegistrySet(address indexed registry);

    /// @notice Emitted when governance appends a hop intermediate to the PB-D7 hop-underlying roster.
    event HopUnderlyingAdded(address indexed underlying);

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
     * @param _svzchf svZCHF numéraire address per H-D9 — quote currency for `tvl()` and a permitted constellation pool token (svZCHF dual-role). Reverts `ZeroAddress` on zero input.
     * @param _initialGovernance Initial governance — Stage A–K Authorizer Safe / `GOVERNANCE_MULTISIG` at deploy; governance rebinds via `setGovernanceContract` per H-D8. Also pins `registrySetter` (the one-shot `setMiliariumRegistry` authority) per P-D35; that slot self-zeros on the first bind.
     * @param _tokensSeed Tokens whose wrapper → underlying mapping is seeded at construction per H-D9 (STANDARD tokens use self-mapping where `_tokensSeed[i] == _underlyingsSeed[i]`).
     * @param _underlyingsSeed Per-index underlying address corresponding to `_tokensSeed[i]`; `_tokensSeed.length` must equal `_underlyingsSeed.length`.
     */
    constructor(
        IVaultExplorer _vaultExplorer,
        address _bodenseePool,
        address _svzchf,
        address _approvedFactory,
        address _approvedFactoryAureum,
        address _initialGovernance,
        address[] memory _tokensSeed,
        address[] memory _underlyingsSeed
    ) {
        if (address(_vaultExplorer) == address(0)) revert ZeroAddress();
        if (_bodenseePool == address(0)) revert ZeroAddress();
        if (_svzchf == address(0)) revert ZeroAddress();
        if (_approvedFactory == address(0)) revert ZeroAddress();
        if (_approvedFactoryAureum == address(0)) revert ZeroAddress();
        if (_initialGovernance == address(0)) revert ZeroAddress();

        if (_tokensSeed.length != _underlyingsSeed.length) revert ArrayLengthMismatch();

        vaultExplorer = _vaultExplorer;
        BODENSEE_POOL = _bodenseePool;
        SVZCHF = _svzchf;
        approvedFactory = _approvedFactory;
        approvedFactoryAureum = _approvedFactoryAureum;
        governance = _initialGovernance;

        for (uint256 i = 0; i < _tokensSeed.length; i++) {
            tokenToUnderlying[_tokensSeed[i]] = _underlyingsSeed[i];
        }
        registrySetter = _initialGovernance;
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
     * @dev H-D9 as amended by PB-D71 (viii) — `_underlyingToPools` reverse-map is indexed at write time. Reads `vaultExplorer.getPoolTokens(pool)` and appends `pool` under each Vault token's mapped `tokenToUnderlying` resolution; a token resolving to the zero address now reverts `UnmappedPoolToken(token)` rather than being skipped. The skip served H-D9's deferred-indexing model, in which `setTokenUnderlying` at H2a.6 could index a leg after the fact; PB-D45 made map-before-roster mandatory and generation 2 proved the deferral unrecoverable, the reverse map having no removal and no re-index primitive and `AlreadyAdded` barring a second attempt, so a silently unindexed leg is permanent on the deployed contract. Reverting is what a mainnet wiring inherits, including a bare `cast send` that no script mediates. Read-time skip-on-zero in `quoteSvZCHF` and `_venueRatio` is UNCHANGED — this is write-time indexing only. Reverts `ZeroAddress` when `pool == address(0)`, `AlreadyAdded(pool)` on duplicate. Emits `ConstellationPoolAdded(pool)`.
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
            if (underlying == address(0)) revert UnmappedPoolToken(address(tokens[i]));
            _underlyingToPools[underlying].push(pool);
        }
        emit ConstellationPoolAdded(pool);
    }

    /**
     * @notice Appends `underlying` to the PB-D7 hop-intermediate roster (`_hopUnderlyings`) — append-only, underlying-key space.
     * @dev PB-D7 — governance seeds hop intermediates (ZCHF + USDS per FINDINGS L1119) for `_twoHopRatio`; inert while empty. Reverts `ZeroAddress` when `underlying == address(0)`, `AlreadyAdded(underlying)` on duplicate. No removal primitive — mirrors `setTokenUnderlying` stickiness. Emits `HopUnderlyingAdded(underlying)`.
     * @param underlying The hop intermediate underlying address to append.
     */
    function addHopUnderlying(address underlying) external onlyGovernance {
        if (underlying == address(0)) revert ZeroAddress();
        if (isHopUnderlying[underlying]) revert AlreadyAdded(underlying);
        isHopUnderlying[underlying] = true;
        _hopUnderlyings.push(underlying);
        emit HopUnderlyingAdded(underlying);
    }

    /* ---------- Token underlying management ---------- */

    /**
     * @notice Post-construction governance write to `tokenToUnderlying` per H-D9 — complements the constructor genesis seed at H2a.3.
     * @dev Governance-curated per-token wrapper → underlying resolution; STANDARD tokens self-map per the H2a.3 seed convention. Reverse-map `_underlyingToPools` staleness is governance's responsibility: callers MUST invoke `setTokenUnderlying` BEFORE `addConstellationPool` for pools that hold `token`, or `_underlyingToPools` retains stale entries under the prior underlying — concrete rebuild deferred per H-D9. Reverts `ZeroAddress` when `token == address(0)` or `underlying == address(0)`. Emits `TokenUnderlyingSet(token, oldUnderlying, underlying)`. Clearing (`tokenToUnderlying[token] = address(0)`) is NOT supported — the map is sticky once set non-zero; a dedicated clear primitive may land later if needed.
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

    /* ---------- Miliarium registry binding (K-D8) ---------- */

    /**
     * @notice One-shot bind of the live Miliarium registry at the Stage K (K7) handoff per K-D8 — mirrors the `CCBMultiplier` F-D20 self-seal.
     * @dev Callable exactly once, by the `_initialGovernance`-pinned `registrySetter` (per P-D35). The authority check fires before the zero guard, so caller-side errors report `OnlyRegistrySetter` regardless of `newRegistry`. Binds `miliariumRegistry` then zeros `registrySetter` to seal — subsequent calls revert `OnlyRegistrySetter` because no caller holds `address(0)`. The `_directRatio` second leg (K6.2) enumerates the bound registry's dense view. Reverts `ZeroAddress` on a zero `newRegistry`; emits `MiliariumRegistrySet`.
     * @param newRegistry Concrete `IMiliariumRegistry` deployed at Stage J — must be non-zero.
     */
    function setMiliariumRegistry(IMiliariumRegistry newRegistry) external {
        if (msg.sender != registrySetter) revert OnlyRegistrySetter();
        if (address(newRegistry) == address(0)) revert ZeroAddress();
        miliariumRegistry = newRegistry;
        registrySetter = address(0);
        emit MiliariumRegistrySet(address(newRegistry));
    }

    /* ---------- Internal helpers (H-D9 Step 2) ---------- */

    /**
     * @notice H-D9 Step 2 — svZCHF quote for `underlying`: direct constellation venues win; PB-D7 2-hop fallback on direct-miss.
     * @dev (1) If `underlying == SVZCHF`, returns `1e18` identity. (2) `_directRatio(underlying, SVZCHF)` across the H-D8 constellation union; returns on non-zero. (3) On direct-miss, `_twoHopRatio(underlying)` iterates the governance hop roster. (4) Returns `0` when neither path prices the underlying.
     * @param underlying The valuation underlying being priced in svZCHF; if equal to `SVZCHF`, returns the 1e18 identity ratio without iteration.
     * @return ratio 18-dec fixed-point svZCHF quote for `underlying`; `0` when no direct or hop path exists.
     */
    function _constellationRatio(address underlying) internal view returns (uint256) {
        if (underlying == SVZCHF) return 1e18;
        uint256 direct = _directRatio(underlying, SVZCHF);
        if (direct != 0) return direct;
        return _twoHopRatio(underlying);
    }

    /**
     * @notice Cross-venue arithmetic mean of `(balQuote * 1e18) / balBase` at constellation venues holding both `base` and `quote`.
     * @dev Two enumeration legs are averaged together per K-D8: Leg 1 walks the governance reverse-map `_underlyingToPools[base]`; Leg 2 walks the live `MiliariumRegistry` dense view (`miliariumPoolsCount` / `miliariumPoolAt`) when `miliariumRegistry` is bound. Leg 1 skips any venue with `miliariumRegistry.isMiliarium(v) == true` so a pool present in both legs is counted once (Leg 2 owns Miliarium pools). When the registry is unbound (`address(0)`), Leg 2 is skipped and Leg 1's skip never fires — exact pre-K6 behavior. Per-venue eligibility and ratio are computed by `_venueRatio`. Returns `0` when no eligible venue exists.
     * @param base The valuation base underlying.
     * @param quote The valuation quote underlying.
     * @return ratio 18-dec fixed-point average of `(balQuote * 1e18) / balBase` across eligible venues; `0` when no eligible venue exists.
     */
    function _directRatio(address base, address quote) internal view returns (uint256) {
        bool registryBound = address(miliariumRegistry) != address(0);
        uint256 acc = 0;
        uint256 count = 0;
        // Leg 1 — governance reverse-map venues; skip Miliarium pools (Leg 2 owns them) per K-D8 dedup.
        address[] storage pools = _underlyingToPools[base];
        for (uint256 i = 0; i < pools.length; i++) {
            address v = pools[i];
            if (registryBound && miliariumRegistry.isMiliarium(v)) continue;
            (uint256 ratio, bool eligible) = _venueRatio(v, base, quote);
            if (eligible) {
                acc += ratio;
                count += 1;
            }
        }
        // Leg 2 — live MiliariumRegistry dense enumeration (K-D8); dormant until the registry is bound.
        if (registryBound) {
            uint256 n = miliariumRegistry.miliariumPoolsCount();
            for (uint256 k = 0; k < n; k++) {
                (uint256 ratio, bool eligible) = _venueRatio(miliariumRegistry.miliariumPoolAt(k), base, quote);
                if (eligible) {
                    acc += ratio;
                    count += 1;
                }
            }
        }
        return count == 0 ? 0 : acc / count;
    }

    /**
     * @notice PB-D7 — 2-hop valuation fallback: arithmetic mean of `h1 * h2 / 1e18` across contributing hop intermediates.
     * @dev Iterates `_hopUnderlyings`; skips `hop == underlying` and `hop == SVZCHF`; computes `h2 = _directRatio(hop, SVZCHF)` before `h1 = _directRatio(underlying, hop)` (cheap gate on venueless intermediates). No transitive hops — calls only `_directRatio`, depth exactly 2; an underlying reachable only through an intermediate that itself needs a hop returns `0`.
     * @param underlying The valuation underlying being priced via hop intermediates.
     * @return ratio 18-dec fixed-point mean hop product; `0` when no contributing intermediate exists.
     */
    function _twoHopRatio(address underlying) internal view returns (uint256) {
        uint256 acc = 0;
        uint256 count = 0;
        for (uint256 i = 0; i < _hopUnderlyings.length; i++) {
            address hop = _hopUnderlyings[i];
            if (hop == underlying || hop == SVZCHF) continue;
            uint256 h2 = _directRatio(hop, SVZCHF);
            if (h2 == 0) continue;
            uint256 h1 = _directRatio(underlying, hop);
            if (h1 == 0) continue;
            acc += (h1 * h2) / 1e18;
            count += 1;
        }
        return count == 0 ? 0 : acc / count;
    }

    /**
     * @notice Per-venue weighted balance-ratio contribution shared by `_directRatio` enumeration legs (K-D8), carrying the PB-D50 weight term.
     * @dev Sums `balancesLiveScaled18` into `balBase` / `balQuote` and `getNormalizedWeights` into `wBase` / `wQuote` across `v`'s tokens by `tokenToUnderlying` resolution, aggregating in LOCKSTEP so a summed balance is paired with the summed weight of exactly the legs that produced it (PB-D53 (ii)) — a weighted pool's parity relation is per-value-share, so the share carried by a summed balance is the sum of its legs' weights. H-D9 amended per PB-D50: a bare balance ratio is parity-exact only where quote and base weights are equal, which no constellation venue satisfies. Provenance is asserted BEFORE the weight read per PB-D52 (ii), so a venue that is not from the approved weighted-pool factory is skipped and the unsupported `getNormalizedWeights` call is never made, and a pool's self-reported weights never enter the mean unless its provenance is established (F-12); trust is DISJUNCTIVE per PB-D57 (v), so a venue claimed by either the canonical or the Aureum weighted-pool factory passes, which is what admits a genuine third-party pricing venue while still excluding the F-12 spoof, claimed by neither. Every rejection SKIPS rather than reverts per PB-D52 (iii): this is a pricing mean and not an admission check, so one mis-curated roster entry degrades a single venue's contribution instead of bricking `tvl()` for `EMASampler`, `GaugeEligibility` and `EmissionDistributor`. `_directRatio` counts only eligible venues, so a skip leaves the cross-venue mean over the venues that remain.
     * @param v The constellation venue (pool) to read.
     * @param base The valuation base underlying.
     * @param quote The valuation quote underlying.
     * @return ratio `(balQuote * wBase * 1e18) / (balBase * wQuote)` when eligible, else `0`.
     * @return eligible True when `v` is claimed by either approved factory and holds both `base` and `quote` with positive scaled balances and positive summed weights.
     */
    function _venueRatio(address v, address base, address quote) internal view returns (uint256 ratio, bool eligible) {
        // F-19 / P-D37 — an uninitialized venue cannot price and would return (0, false) anyway; skip BEFORE the getPoolData read, which carries the Vault's withInitializedPool modifier and reverts PoolNotInitialized.
        if (!vaultExplorer.isPoolInitialized(v)) return (0, false);
        // PB-D52 (ii) / PB-D57 (v) — provenance precedes every read it protects, and trust is disjunctive across the two weighted-pool factories this system actually runs. The Aureum factory is tested first because the Miliarium roster dominates the venue set, so the common case short-circuits on one call. A venue claimed by neither is skipped before getNormalizedWeights is reached, so a pool that cannot answer it is never asked. The PB-D55 BODENSEE_POOL exemption is retired here rather than kept beside this: der Bodensee is created from WEIGHTED_POOL_FACTORY and therefore passes on the general rule.
        if (!IBasePoolFactory(approvedFactoryAureum).isPoolFromFactory(v) && !IBasePoolFactory(approvedFactory).isPoolFromFactory(v)) return (0, false);
        IERC20[] memory tokens = vaultExplorer.getPoolTokens(v);
        PoolData memory data = vaultExplorer.getPoolData(v);
        uint256[] memory weights = IWeightedPool(v).getNormalizedWeights();
        // PB-D53 (iv) — a weight array disagreeing with the token array skips rather than reverting; close to unreachable behind the provenance gate, and one comparison cheaper than the out-of-bounds panic it prevents.
        if (weights.length != tokens.length) return (0, false);
        uint256 balBase = 0;
        uint256 balQuote = 0;
        uint256 wBase = 0;
        uint256 wQuote = 0;
        for (uint256 j = 0; j < tokens.length; j++) {
            address u = tokenToUnderlying[address(tokens[j])];
            if (u == base) {
                balBase += data.balancesLiveScaled18[j];
                wBase += weights[j];
            } else if (u == quote) {
                balQuote += data.balancesLiveScaled18[j];
                wQuote += weights[j];
            }
        }
        if (balBase > 0 && balQuote > 0 && wBase > 0 && wQuote > 0) {
            return ((balQuote * wBase * 1e18) / (balBase * wQuote), true);
        }
        return (0, false);
    }

    /* ---------- ITVLOracle ---------- */

    /**
     * @inheritdoc ITVLOracle
     * @dev H-D9 implementation — Step 1: reads `vaultExplorer.getPoolData(pool).balancesLiveScaled18[]` for the input pool's own scaled balances; Step 2: calls `_constellationRatio(underlying)` per token to convert each balance into svZCHF and sum contributions (direct venues win; PB-D7 2-hop fallback on direct-miss). Tokens with no `tokenToUnderlying` entry (zero-address resolution) contribute 0. Underlyings with no constellation pricing (`_constellationRatio` returns 0) also contribute 0. Return is 18-dec fixed-point svZCHF.
     */
    function tvl(address pool) external view override returns (uint256) {
        PoolData memory data = vaultExplorer.getPoolData(pool);
        uint256 sum = 0;
        for (uint256 i = 0; i < data.tokens.length; i++) {
            address u = tokenToUnderlying[address(data.tokens[i])];
            if (u == address(0)) continue;
            uint256 ratio = _constellationRatio(u);
            if (ratio == 0) continue;
            sum += (data.balancesLiveScaled18[i] * ratio) / 1e18;
        }
        return sum;
    }

    /// @notice external wrapper for the H-D9 constellation-ratio conversion — converts `amountScaled18` of `token` into its svZCHF-denominated equivalent
    /// @dev (a) mirrors the inner tvl() loop for a single (token, amount) input; (b) skip-on-zero semantics — returns 0 if `tokenToUnderlying[token] == address(0)` or if `_constellationRatio(underlying) == 0` (direct venues win; PB-D7 2-hop fallback on direct-miss); (c) input must be in Balancer V3 `balancesLiveScaled18` convention (18-decimal fixed-point of the token's economic amount); raw-decimal inputs must be pre-scaled by the caller; (d) required by Stage H H2b `EfficiencyOracle` per H-D10 for per-pool fee/emission svZCHF conversion
    /// @param token — the pool token whose underlying valuation is queried
    /// @param amountScaled18 — the amount of `token` to convert, in 18-decimal fixed-point per Balancer V3 scaled18 convention
    /// @return svZCHFAmountScaled18 — the svZCHF-denominated equivalent in 18-decimal fixed-point; 0 when token is unmapped or has no constellation venue
    function quoteSvZCHF(address token, uint256 amountScaled18) external view override returns (uint256 svZCHFAmountScaled18) {
        address u = tokenToUnderlying[token];
        if (u == address(0)) return 0;
        uint256 ratio = _constellationRatio(u);
        if (ratio == 0) return 0;
        return (amountScaled18 * ratio) / 1e18;
    }
}
