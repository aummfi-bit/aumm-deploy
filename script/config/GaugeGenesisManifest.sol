// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { IVaultClassRegistry } from "../../src/gauge/IVaultClassRegistry.sol";

/**
 * @title GaugeGenesisManifest
 * @notice The VaultClassRegistry genesis admitted-ERC-4626 class set — P-D30 full union (11 tokens).
 *
 * @dev Seeds VaultClassRegistry's constructor genesisTokens[] / genesisTypes[] arrays per P-D30
 *      (docs/STAGE_P_NOTES.md). The 11 tokens are the deduplicated admitted-ERC-4626 (52%
 *      Quality-Gate numerator) set across the 26 deployed M/N/E pools — all slots except the
 *      deferred 04 ixViatica / 07 ixCambio — derived from each pool config's Quality-Gate NatSpec.
 *      Every entry is AdmissionType.ImplementationAddress: VaultClassRegistry.isAdmittedClass(token)
 *      is a direct admittedClasses[token] lookup, so a FactoryAddress / BytecodeHash entry would
 *      admit an address no pool token ever equals (and BytecodeHash is ctor-forbidden). 11 tokens
 *      sit under MAX_GENESIS_CLASSES (32). Genesis seed only — governance-mutable thereafter via
 *      proposeVaultClass / revokeVaultClass; 04/07 and future tokens admit by vote.
 *
 *      Token addresses are the E-D17 fork-verified mainnet literals, byte-identical to the
 *      script/pools/configs/ per-pool libraries.
 */
library GaugeGenesisManifest {
    // -------------------------------------------------------------------------
    // Admitted-ERC-4626 genesis classes (P-D30)
    // -------------------------------------------------------------------------

    address internal constant SVZCHF         = 0xE5F130253fF137f9917C0107659A4c5262abf6b0;
    address internal constant SUSDS          = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address internal constant WAETHUSDC      = 0xD4fa2D31b7968E448877f69A96DE69f5de8cD23E;
    address internal constant WAETHUSDT      = 0x7Bc3485026Ac48b6cf9BaF0A377477Fff5703Af8;
    address internal constant AAVE_GHO_VAULT = 0xC71Ea051a5F82c67ADcF634c36FFE6334793D24C;
    address internal constant YSYBOLD        = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
    address internal constant SFRXETH        = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address internal constant WOETH          = 0xDcEe70654261AF21C44c093C300eD3Bb97b78192;
    address internal constant FWSTETH        = 0x2411802D8BEA09be0aF8fD8D08314a63e706b29C;
    address internal constant FWETH          = 0x90551c1795392094FE6D29B758EcCD233cFAa260;
    address internal constant SCRVUSD        = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;

    /// @notice Count of genesis admitted-4626 classes (P-D30 full union).
    uint256 internal constant GENESIS_CLASS_COUNT = 11;

    /**
     * @notice Genesis admitted-ERC-4626 token addresses and their admission types, index-aligned,
     *         both length GENESIS_CLASS_COUNT, for VaultClassRegistry's constructor.
     * @dev Every admission type is ImplementationAddress per P-D30. Order follows the P-D30 table.
     */
    function genesis()
        internal
        pure
        returns (address[] memory tokens, IVaultClassRegistry.AdmissionType[] memory types)
    {
        tokens = new address[](GENESIS_CLASS_COUNT);
        tokens[0]  = SVZCHF;
        tokens[1]  = SUSDS;
        tokens[2]  = WAETHUSDC;
        tokens[3]  = WAETHUSDT;
        tokens[4]  = AAVE_GHO_VAULT;
        tokens[5]  = YSYBOLD;
        tokens[6]  = SFRXETH;
        tokens[7]  = WOETH;
        tokens[8]  = FWSTETH;
        tokens[9]  = FWETH;
        tokens[10] = SCRVUSD;

        types = new IVaultClassRegistry.AdmissionType[](GENESIS_CLASS_COUNT);
        types[0]  = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        types[1]  = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        types[2]  = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        types[3]  = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        types[4]  = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        types[5]  = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        types[6]  = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        types[7]  = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        types[8]  = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        types[9]  = IVaultClassRegistry.AdmissionType.ImplementationAddress;
        types[10] = IVaultClassRegistry.AdmissionType.ImplementationAddress;
    }
}
