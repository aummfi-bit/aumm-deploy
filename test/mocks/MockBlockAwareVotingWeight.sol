// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IVotingWeight} from "../../src/governance/IVotingWeight.sol";

/// @notice Block-aware voting-weight mock. Unlike the block-agnostic MockVotingWeight in
///         AureumGovernance.t.sol, this honors the block argument of getPastVotes /
///         getPastTotalSupply via ascending per-block checkpoints, mirroring the OZ
///         Checkpoints.Trace208 upperLookup semantics of the real VotingWeight. poke(holder) pulls
///         the holder's true (position-derived) weight into the live accumulator and stamps a
///         checkpoint at the current block. The future-lookup guard is omitted; callers read only
///         strictly-past blocks.
/// @dev    Lifted here at PP4.10f5 from F06_postEndBlockDenominatorFreeze.t.sol, which was its sole
///         resident. It is shared because two findings need the same divergence between live and
///         checkpointed supply, for different reasons: F-06 pulls the permissionless poke lever
///         AFTER endBlock, while F-21 needs a live supply that is non-zero at propose and a
///         snapshot denominator that is zero at the vote. A block-agnostic mock cannot express
///         either, because it collapses the two quantities into one.
contract MockBlockAwareVotingWeight is IVotingWeight {
    struct Ckpt {
        uint256 blk;
        uint256 val;
    }

    mapping(address => Ckpt[]) private _holderCkpts;
    Ckpt[] private _totalCkpts;
    mapping(address => uint256) private _liveHolder;
    uint256 private _liveTotal;
    mapping(address => uint256) public trueWeight;

    /// @notice Set a holder's true position-derived weight, materialized into the accumulator on the next poke.
    function setTrueWeight(address holder, uint256 weight) external {
        trueWeight[holder] = weight;
    }

    function poke(address holder) external {
        uint256 prev = _liveHolder[holder];
        uint256 target = trueWeight[holder];
        _liveTotal = _liveTotal - prev + target;
        _liveHolder[holder] = target;
        _holderCkpts[holder].push(Ckpt(block.number, target));
        _totalCkpts.push(Ckpt(block.number, _liveTotal));
    }

    function governanceWeight(address holder) external view returns (uint256) {
        return _liveHolder[holder];
    }

    function totalSupply() external view returns (uint256) {
        return _liveTotal;
    }

    function getPastVotes(address holder, uint256 blockNumber) external view returns (uint256) {
        return _upperLookup(_holderCkpts[holder], blockNumber);
    }

    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256) {
        return _upperLookup(_totalCkpts, blockNumber);
    }

    function _upperLookup(Ckpt[] storage ckpts, uint256 blockNumber) private view returns (uint256) {
        uint256 value;
        for (uint256 i; i < ckpts.length; ++i) {
            if (ckpts[i].blk <= blockNumber) value = ckpts[i].val;
            else break;
        }
        return value;
    }
}
