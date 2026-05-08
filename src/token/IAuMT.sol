// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IAuMT
 * @notice Stage I forward-dep stub — minimal AuMT (Aureum Market Tessera) interface for Stage G consumers.
 * @dev IERC20 base + governance-weight surface used by `VaultClassRegistry.vetoProposal` per G-D9;
 *      per G-DP4 forward-dependency wiring rule, pre-Stage-I deployments expose this stub but the concrete
 *      `setAuMT`-wired contract returns zero from `governanceWeight` until Stage I lands `AuMT.sol`.
 */
interface IAuMT is IERC20 {
    /**
     * @notice AuMT-weighted governance vote share for `holder`.
     * @dev Used by `VaultClassRegistry.vetoProposal` per G-D9 veto-threshold semantic.
     *      Pre-Stage-I, the placeholder slot returns zero (vetoes structurally impossible per G-DP4).
     *      Encoding precision and qualification-period logic lock at Stage I;
     *      this stub commits only to function shape for Stage G call sites.
     * @param holder The address whose governance weight is queried.
     * @return weight AuMT-weighted vote-share, absolute (denominator is `totalSupply()` from IERC20).
     */
    function governanceWeight(address holder) external view returns (uint256);
}
