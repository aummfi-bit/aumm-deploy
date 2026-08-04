// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {PoolData} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title StageHMocks — Stage H shared test mocks (MockVaultExplorer for TVLOracle; growable per sub-step)
/// @notice Aggregate file for Stage H test mocks per the Stage F + Stage G shared-mocks precedent (`test/fork/mocks/CCBMocks.sol` + `test/fork/mocks/StageGMocks.sol`). Subsequent H sub-steps grow this file; each mock is independently consumable by either unit or fork tests.
/// @dev G16 finding enumeration rule applies — any future interface evolution that changes a Stage H interface signature must enumerate all inheritors of that interface across `src/`, `test/`, and `script/` before changing the mocks.

/// @title MockVaultExplorer — minimal Balancer V3 IVaultExplorer stub for TVLOracle's getPoolTokens + getPoolData reads
/// @notice Implements only the surface `TVLOracle` calls (`getPoolTokens` + `getPoolData` + `isPoolInitialized`, the last added for F-19 / P-D37); deliberately does NOT inherit `IVaultExplorer` — consumers cast `IVaultExplorer(address(mockExplorer))` per the Stage F-D11 / G-D25c mock-cast precedent.
/// @dev `setPool(pool, tokens, balances)` programs both responses simultaneously (tokens.length must equal balances.length, otherwise reverts `LengthMismatch`). `getPoolData` returns a `PoolData` struct with only `.tokens` and `.balancesLiveScaled18` populated — other PoolData fields default to zero/empty since TVLOracle's H-D9 arithmetic reads only these two. F-19 / P-D37 — pools default to INITIALIZED (`isPoolInitialized` returns true); `setUninitialized(pool, true)` flips a pool to the registered-but-uninitialized state, whereupon `getPoolData(pool)` reverts `PoolNotInitialized(pool)` faithfully to the Vault's `withInitializedPool` modifier.
contract MockVaultExplorer {
    /// @notice Reverts when `setPool` is called with mismatched `tokens.length` / `balances.length`.
    error LengthMismatch();

    /// @notice F-19 / P-D37 — reverts from `getPoolData` when `pool` is flagged uninitialized, mirroring the Vault's `withInitializedPool` modifier.
    error PoolNotInitialized(address pool);

    /// @notice Per-pool tokens programmed via `setPool`.
    mapping(address => IERC20[]) internal _poolTokens;

    /// @notice Per-pool scaled-to-18-dec balances programmed via `setPool`; index-aligned with `_poolTokens[pool]`.
    mapping(address => uint256[]) internal _balancesLiveScaled18;

    /// @notice F-19 / P-D37 — per-pool uninitialized flag; default false (pools read as initialized) so pre-F-19 tests are unaffected. Set via `setUninitialized`.
    mapping(address => bool) internal _uninitialized;

    /// @notice Programs `pool`'s `getPoolTokens` + `getPoolData` responses; clears prior state for `pool`. Reverts `LengthMismatch` if `tokens.length != balances.length`.
    function setPool(address pool, IERC20[] memory tokens, uint256[] memory balances) external {
        if (tokens.length != balances.length) revert LengthMismatch();
        delete _poolTokens[pool];
        delete _balancesLiveScaled18[pool];
        for (uint256 i = 0; i < tokens.length; i++) {
            _poolTokens[pool].push(tokens[i]);
            _balancesLiveScaled18[pool].push(balances[i]);
        }
    }

    /// @notice Returns `pool`'s programmed tokens; empty array if `setPool` was never called for `pool`.
    function getPoolTokens(address pool) external view returns (IERC20[] memory) {
        return _poolTokens[pool];
    }

    /// @notice Returns `pool`'s `PoolData` with `.tokens` + `.balancesLiveScaled18` populated; other PoolData fields default to zero/empty since TVLOracle's H-D9 arithmetic reads only these two.
    function getPoolData(address pool) external view returns (PoolData memory data) {
        if (_uninitialized[pool]) revert PoolNotInitialized(pool);
        data.tokens = _poolTokens[pool];
        data.balancesLiveScaled18 = _balancesLiveScaled18[pool];
    }

    /// @notice F-19 / P-D37 — mirrors `IVaultExplorer.isPoolInitialized`; returns true unless `setUninitialized(pool, true)` was called. Default true so pre-F-19 tests read every pool as initialized.
    function isPoolInitialized(address pool) external view returns (bool) {
        return !_uninitialized[pool];
    }

    /// @notice F-19 / P-D37 — flips `pool` between initialized (default) and registered-but-uninitialized; when uninitialized, `getPoolData(pool)` reverts `PoolNotInitialized(pool)`.
    function setUninitialized(address pool, bool flag) external {
        _uninitialized[pool] = flag;
    }
}

/// @title MockWeightedPool — settable-weights weighted-pool double for `TVLOracle._venueRatio`'s PB-D50 weight term
/// @notice Implements only `getNormalizedWeights`, the sole weighted-pool surface `TVLOracle._venueRatio` calls — deliberately does NOT inherit `IWeightedPool`, per the `MockVaultExplorer` mock-cast precedent above (Stage F-D11 / G-D25c) and the hand-rolled `F12_SpoofWeightedPool` in `test/whitehat/F12_compositionGateProvenance.t.sol`. Consumers register the instance's address as a venue through `MockVaultExplorer.setPool` and vouch for it through `MockBasePoolFactory.setFromFactory`.
/// @dev `setWeights` VALIDATES NOTHING, and that is load-bearing rather than an omission — the double must be able to return a vector shorter than the venue's token array and a vector containing a zero entry, because those are precisely the malformed responses the PB-D53 (iv) length-mismatch skip and the PB-D53 (v) zero-weight skip exist to catch. Do not add length or non-zero validation here; it would make two of the five PB-D54 (vi) tests unwritable.
contract MockWeightedPool {
    uint256[] internal _weights;

    /// @notice Programs the weight vector returned by `getNormalizedWeights`; no validation, per the contract-level dev note.
    /// @param weights The normalized-weight vector to return, in the venue's registered token order.
    function setWeights(uint256[] memory weights) external {
        _weights = weights;
    }

    /// @notice Mirrors `IWeightedPool.getNormalizedWeights` — index-aligned with the venue's registered tokens.
    /// @return The programmed weight vector, empty until `setWeights` is called.
    function getNormalizedWeights() external view returns (uint256[] memory) {
        return _weights;
    }
}

/// @title MockBasePoolFactory — settable-membership factory double for `TVLOracle._venueRatio`'s PB-D52 (ii) provenance gate
/// @notice Implements only `isPoolFromFactory`, the sole factory surface `TVLOracle._venueRatio` calls — deliberately does NOT inherit `IBasePoolFactory`, per the same mock-cast precedent. Consumers pass the instance's address as the oracle's `approvedFactory` constructor argument.
/// @dev Membership defaults to FALSE for every address, matching production semantics where a pool no factory created is not from that factory — a venue is skipped until `setFromFactory(pool, true)` vouches for it. A permissive default was available and is rejected: it would invert the production default so a test could pass against a venue the live path would skip, which is the answers-on-behalf-of trap PB-D54 (ii) names, and it saves nothing because every venue site is rewritten at PB3.8i9c regardless.
contract MockBasePoolFactory {
    mapping(address => bool) internal _fromFactory;

    /// @notice Programs whether `pool` is reported as created by this factory.
    /// @param pool The venue address to vouch for or disown.
    /// @param flag True to report `pool` as factory-created, false to withhold provenance.
    function setFromFactory(address pool, bool flag) external {
        _fromFactory[pool] = flag;
    }

    /// @notice Mirrors `IBasePoolFactory.isPoolFromFactory` — false for any address never passed to `setFromFactory`.
    /// @param pool The venue address under evaluation.
    /// @return True when `pool` has been vouched for, false otherwise.
    function isPoolFromFactory(address pool) external view returns (bool) {
        return _fromFactory[pool];
    }
}
