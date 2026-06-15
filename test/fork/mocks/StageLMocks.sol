// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {PoolData} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title StageLMocks — Stage L shared test mocks (der Bodensee explorer, venue weights, donate channel, AuMM rate)
/// @notice Aggregate file for Stage L unit-test mocks per the Stage F + Stage G + Stage H shared-mocks precedent (`test/fork/mocks/CCBMocks.sol`, `StageGMocks.sol`, `StageHMocks.sol`). Consumed by `IncendiaryRegistry` harness tests at L8.1—L8.4; each mock implements only the surface the registry calls.
/// @dev G16 finding enumeration rule applies — any future interface evolution that changes a Stage L consumer signature must enumerate all inheritors across `src/`, `test/`, and `script/` before changing the mocks. Cast-not-inherit per F-D11 / G-D25c — no mock inherits an upstream interface; consumers cast at the call site.

/// @title MockBodenseeExplorer — minimal IVaultExplorer stub for IncendiaryRegistry `_spotRate` / `_valueInAuMM` reads
/// @notice Implements only `getPoolData` with the four fields the registry indexes; deliberately does NOT inherit `IVaultExplorer` — consumers cast `IVaultExplorer(address(mockExplorer))` per the F-D11 / G-D25c mock-cast precedent.
/// @dev `setPoolData` programs tokens, balancesLiveScaled18, tokenRates, and decimalScalingFactors per pool. `getPoolData` populates only those four fields — `poolConfigBits`, `tokenInfo`, and `balancesRaw` default to zero/empty.
contract MockBodenseeExplorer {
    mapping(address => IERC20[]) internal _tokens;
    mapping(address => uint256[]) internal _balancesLiveScaled18;
    mapping(address => uint256[]) internal _tokenRates;
    mapping(address => uint256[]) internal _decimalScalingFactors;

    /// @notice Programs `pool`'s `getPoolData` response; clears prior state for `pool`.
    function setPoolData(
        address pool,
        IERC20[] memory tokens,
        uint256[] memory balancesLiveScaled18,
        uint256[] memory tokenRates,
        uint256[] memory decimalScalingFactors
    ) external {
        delete _tokens[pool];
        delete _balancesLiveScaled18[pool];
        delete _tokenRates[pool];
        delete _decimalScalingFactors[pool];
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokens[pool].push(tokens[i]);
            _balancesLiveScaled18[pool].push(balancesLiveScaled18[i]);
            _tokenRates[pool].push(tokenRates[i]);
            _decimalScalingFactors[pool].push(decimalScalingFactors[i]);
        }
    }

    /// @notice Returns `pool`'s `PoolData` with `.tokens`, `.balancesLiveScaled18`, `.tokenRates`, and `.decimalScalingFactors` populated; other PoolData fields default to zero/empty.
    function getPoolData(address pool) external view returns (PoolData memory data) {
        data.tokens = _tokens[pool];
        data.balancesLiveScaled18 = _balancesLiveScaled18[pool];
        data.tokenRates = _tokenRates[pool];
        data.decimalScalingFactors = _decimalScalingFactors[pool];
    }
}

/// @title MockWeightedVenue — minimal IWeightedPool stub for der Bodensee `getNormalizedWeights` reads
/// @notice Implements only `getNormalizedWeights`; deliberately does NOT inherit `IWeightedPool` — consumers cast `IWeightedPool(address(mockVenue))` at the call site per the F-D11 / G-D25c mock-cast precedent.
/// @dev The registry calls `getNormalizedWeights()` on `BODENSEE_POOL` (this mock's address), not on the vault explorer.
contract MockWeightedVenue {
    uint256[] internal _weights;

    /// @notice Stores the normalized weights returned by `getNormalizedWeights`.
    function setWeights(uint256[] memory weights) external {
        delete _weights;
        for (uint256 i = 0; i < weights.length; i++) {
            _weights.push(weights[i]);
        }
    }

    /// @notice Returns the stored normalized weights; empty array if `setWeights` was never called.
    function getNormalizedWeights() external view returns (uint256[] memory) {
        return _weights;
    }
}

/// @title MockBodenseeChannel — minimal SwapAndDepositToBodensee stub for IncendiaryRegistry `donate` calls
/// @notice Records the last `(payToken, amount)` pair; deliberately does NOT inherit `SwapAndDepositToBodensee` — consumers cast `SwapAndDepositToBodensee(address(mockChannel))` per the F-D11 / G-D25c mock-cast precedent.
/// @dev No-op `donate` with no access gate — the registry's `safeTransferFrom` already moved tokens; the mock only needs to not revert and record for assertions.
contract MockBodenseeChannel {
    /// @notice The pay token from the most recent `donate` call.
    IERC20 public lastPayToken;

    /// @notice The amount from the most recent `donate` call.
    uint256 public lastAmount;

    /// @notice Records `payToken` and `amount`; does not revert.
    function donate(IERC20 payToken, uint256 amount) external {
        lastPayToken = payToken;
        lastAmount = amount;
    }
}

/// @title MockAuMMRate — minimal IAuMM stub for IncendiaryRegistry `_epochEmissionIntegral` / cap reads
/// @notice Implements only `blockEmissionRate`; deliberately does NOT inherit `IAuMM` — consumers cast `IAuMM(address(mockAumm))` per the F-D11 / G-D25c mock-cast precedent.
/// @dev Flat rate via `setRate`; halving-straddle scenarios override via `vm.mockCall` at the test site (`EmissionDistributor.t.sol:1190-1191` precedent).
contract MockAuMMRate {
    uint256 internal _rate;

    /// @notice Sets the flat per-block emission rate returned by `blockEmissionRate`.
    function setRate(uint256 rate_) external {
        _rate = rate_;
    }

    /// @notice Returns the stored flat rate for any block argument.
    function blockEmissionRate(uint256) external view returns (uint256) {
        return _rate;
    }
}
