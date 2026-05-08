// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

/**
 * @title IVaultClassRegistry
 * @notice Narrow read surface for class-admission lookups consumed by `GaugeEligibility` per G-D8 (canonical 52% numerator) + G-D9 (Frankencoin-inspired veto mechanism). Mutations live on the concrete `VaultClassRegistry.sol`.
 * @dev Per G-D10 (ERC-4626 detection method), `GaugeEligibility` invokes `isAdmittedClass(token)` AFTER a successful `try/catch IERC4626(token).asset()` — non-ERC-4626 tokens skip this interface entirely. Per G-D9, admission proceeds via `propose → veto-window → finalize` with three fingerprint kinds enumerated in `AdmissionType`.
 */

interface IVaultClassRegistry {
    enum AdmissionType { ImplementationAddress, FactoryAddress, BytecodeHash }

    /**
     * @notice Returns true iff `token` is an admitted ERC-4626 class.
     * @dev Hot-path runtime check invoked by `GaugeEligibility` per pool token after ERC-4626 detection (G-D10).
     * @param token The candidate ERC-4626 token address.
     * @return admitted Whether the token is currently admitted.
     */
    function isAdmittedClass(address token) external view returns (bool);

    /**
     * @notice Returns the fingerprint kind under which `token` was admitted.
     * @dev Diagnostic / event surface; NOT on the `GaugeEligibility` hot path. Reverts (or returns the default `ImplementationAddress` slot under Solidity zero-init semantics — concrete contract behavior locks at G1.11 + G1.12) if `token` is not currently admitted; consumers should call `isAdmittedClass` first.
     * @param token The candidate ERC-4626 token address.
     * @return kind The `AdmissionType` enum value under which the token was admitted.
     */
    function admissionType(address token) external view returns (AdmissionType);
}
