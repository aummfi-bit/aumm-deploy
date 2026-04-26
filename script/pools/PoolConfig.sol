// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

struct PoolConfig {
    string name;
    string symbol;
    uint8 slot;
    string sectorLabel;
    address[] tokens;
    TokenType[] tokenTypes;
    IRateProvider[] rateProviders;
    bool[] paysYieldFees;
    uint256[] normalizedWeights;
    uint256 swapFeePercentage;
    bytes32 salt;
}
