// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenType, TokenInfo } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";

/// @dev `test-stubs/StubERC4626.sol` L13 is deliberately not `is IERC4626` to avoid a
///      mint-signature collision, so a minimal interface is used rather than `IERC4626` —
///      the only method needed is `asset()`.
interface IAssetLike {
    function asset() external view returns (address);
}

/**
 * @title  DeriveTokenUnderlyings
 * @notice Read-only derivation of the Sepolia `tokenToUnderlying` map for PB3.8e.
 * @dev    PB-D42 (vi) derive-commit-then-assert: this script is the read-only discovery
 *         pass that emits a reviewable map for commit at e3; rung f re-asserts each entry
 *         against a live `asset()` read before writing. PB-D42 (iii): svZCHF self-maps so
 *         the resolved value equals the `SVZCHF` immutable. PB-D42 (iv): WITH_RATE
 *         underlyings are absent from the committed stub map and exist only on chain via
 *         `asset()`. No broadcast, no CREATE, no state-changing external call.
 */
contract DeriveTokenUnderlyings is Script {
    address[] internal tokens;
    address[] internal underlyings;
    mapping(address => bool) internal seen;
    address internal svZchf;

    /// @notice Walk every live pool's registered tokens, resolve each unique token to its
    ///         `tokenToUnderlying` value, gate the result, and console-emit paste-ready
    ///         Solidity assignments for `script/config/SepoliaTokenUnderlyings.sol` at e3.
    function run() external {
        IVaultExplorer explorer = IVaultExplorer(vm.envAddress("VAULT"));
        svZchf = vm.envAddress("SV_ZCHF");

        address[27] memory pools;
        pools[0] = vm.envAddress("MILIARIUM_POOL_01");
        pools[1] = vm.envAddress("MILIARIUM_POOL_02");
        pools[2] = vm.envAddress("MILIARIUM_POOL_03");
        pools[3] = vm.envAddress("MILIARIUM_POOL_05");
        pools[4] = vm.envAddress("MILIARIUM_POOL_06");
        pools[5] = vm.envAddress("MILIARIUM_POOL_08");
        pools[6] = vm.envAddress("MILIARIUM_POOL_09");
        pools[7] = vm.envAddress("MILIARIUM_POOL_10");
        pools[8] = vm.envAddress("MILIARIUM_POOL_11");
        pools[9] = vm.envAddress("MILIARIUM_POOL_12");
        pools[10] = vm.envAddress("MILIARIUM_POOL_13");
        pools[11] = vm.envAddress("MILIARIUM_POOL_14");
        pools[12] = vm.envAddress("MILIARIUM_POOL_15");
        pools[13] = vm.envAddress("MILIARIUM_POOL_16");
        pools[14] = vm.envAddress("MILIARIUM_POOL_17");
        pools[15] = vm.envAddress("MILIARIUM_POOL_18");
        pools[16] = vm.envAddress("MILIARIUM_POOL_19");
        pools[17] = vm.envAddress("MILIARIUM_POOL_20");
        pools[18] = vm.envAddress("MILIARIUM_POOL_21");
        pools[19] = vm.envAddress("MILIARIUM_POOL_22");
        pools[20] = vm.envAddress("MILIARIUM_POOL_23");
        pools[21] = vm.envAddress("MILIARIUM_POOL_24");
        pools[22] = vm.envAddress("MILIARIUM_POOL_25");
        pools[23] = vm.envAddress("MILIARIUM_POOL_26");
        pools[24] = vm.envAddress("MILIARIUM_POOL_27");
        pools[25] = vm.envAddress("MILIARIUM_POOL_28");
        pools[26] = vm.envAddress("DER_BODENSEE_POOL");

        for (uint256 i = 0; i < 27; ++i) {
            // getPoolTokenInfo is gated withRegisteredPool, not withInitializedPool
            // (VaultExtension.sol L525), which is why it works before seeding.
            (IERC20[] memory t, TokenInfo[] memory info, , ) = explorer.getPoolTokenInfo(pools[i]);
            for (uint256 j = 0; j < t.length; ++j) {
                address token = address(t[j]);
                if (seen[token]) {
                    continue;
                }
                seen[token] = true;

                address underlying;
                // svZCHF self-map before WITH_RATE so it never reaches asset() — PB-D42 (iii).
                if (token == svZchf) {
                    underlying = token;
                } else if (info[j].tokenType == TokenType.WITH_RATE) {
                    underlying = IAssetLike(token).asset();
                } else {
                    underlying = token;
                }

                tokens.push(token);
                underlyings.push(underlying);
            }
        }

        require(tokens.length == underlyings.length, "DERIVE: length mismatch");
        require(tokens.length > 0, "DERIVE: empty map");
        for (uint256 i = 0; i < underlyings.length; ++i) {
            require(underlyings[i] != address(0), "DERIVE: zero underlying");
        }
        require(seen[svZchf], "DERIVE: svZCHF not present in any pool");
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i] == svZchf) {
                require(underlyings[i] == svZchf, "DERIVE: svZCHF must self-map per PB-D42 (iii)");
                break;
            }
        }

        _emitMap();
    }

    /// @dev Console-log paste-ready Solidity assignments for e3 library body capture.
    ///      Mirrors DeployTestnetStubs._emitMap L214-L219 emission shape.
    function _emitMap() internal view {
        console2.log(
            "// PB3.8e derived token-to-underlying map (live Sepolia; capture into script/config/SepoliaTokenUnderlyings.sol at e3)"
        );
        console2.log(string.concat("// count: ", vm.toString(tokens.length)));
        for (uint256 i = 0; i < tokens.length; ++i) {
            console2.log(
                string.concat("        t[", vm.toString(i), "] = ", vm.toString(tokens[i]), ";")
            );
            console2.log(
                string.concat("        u[", vm.toString(i), "] = ", vm.toString(underlyings[i]), ";")
            );
        }
    }
}
