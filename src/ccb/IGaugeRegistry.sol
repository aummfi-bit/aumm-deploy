// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

/// @title IGaugeRegistry — approved-gauge gate for CCB boost activation
/// @notice Whether an address is an approved gauge — consumed by `CCBMultiplier.activateBoost` for the caller gate per F-D17.
/// @dev F-D17 (`STAGE_F_NOTES.md` L84-L113): `activateBoost` requires `isGaugeApproved(msg.sender)`; boost lifecycle and replay policy are interface consumers' concern.
///      Stage F scope (`STAGE_F_PLAN.md` L91): gauge approval, revocation, and eligibility state machines are Stage G — not this file's burden.
///      Concrete registry: Stage G `GaugeRegistry.sol`. Pre-Stage-G placeholder: `isGaugeApproved` returns `false` for every address — so `activateBoost` denies all callers until Stage G ships and the registry is wired.
interface IGaugeRegistry {
    /// @notice Whether `gauge` is currently registered as an approved gauge authorized to trigger boost activation on Miliarium pools.
    /// @param gauge The address checked for gauge approval (callers typically pass `msg.sender`).
    /// @return True if `gauge` is approved; otherwise false.
    function isGaugeApproved(address gauge) external view returns (bool);
}
