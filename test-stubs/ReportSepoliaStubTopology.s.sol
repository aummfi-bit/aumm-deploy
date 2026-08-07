// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

import { IxHelvetiaConfig } from "script/pools/configs/01_ixHelvetia.s.sol";
import { IxAetheronConfig } from "script/pools/configs/02_ixAetheron.s.sol";
import { IxCasperConfig } from "script/pools/configs/03_ixCasper.s.sol";
import { IxEdelweissConfig } from "script/pools/configs/05_ixEdelweiss.s.sol";
import { IxLibertasConfig } from "script/pools/configs/06_ixLibertas.s.sol";
import { IxBrevisConfig } from "script/pools/configs/08_ixBrevis.s.sol";
import { IxAltrixConfig } from "script/pools/configs/09_ixAltrix.s.sol";
import { IxMedioxConfig } from "script/pools/configs/10_ixMediox.s.sol";
import { IxLongusConfig } from "script/pools/configs/11_ixLongus.s.sol";
import { IxStrataConfig } from "script/pools/configs/12_ixStrata.s.sol";
import { IxForumConfig } from "script/pools/configs/13_ixForum.s.sol";
import { IxAurebitConfig } from "script/pools/configs/14_ixAurebit.s.sol";
import { IxRegistrumConfig } from "script/pools/configs/15_ixRegistrum.s.sol";
import { IxDebitumConfig } from "script/pools/configs/16_ixDebitum.s.sol";
import { IxEquitixConfig } from "script/pools/configs/17_ixEquitix.s.sol";
import { IxInnovixConfig } from "script/pools/configs/18_ixInnovix.s.sol";
import { IxGigantusConfig } from "script/pools/configs/19_ixGigantus.s.sol";
import { IxMagnixConfig } from "script/pools/configs/20_ixMagnix.s.sol";
import { IxNubixConfig } from "script/pools/configs/21_ixNubix.s.sol";
import { IxMonetaConfig } from "script/pools/configs/22_ixMoneta.s.sol";
import { IxColossixConfig } from "script/pools/configs/23_ixColossix.s.sol";
import { IxVitalixConfig } from "script/pools/configs/24_ixVitalix.s.sol";
import { IxMedicixConfig } from "script/pools/configs/25_ixMedicix.s.sol";
import { IxMercaturaConfig } from "script/pools/configs/26_ixMercatura.s.sol";
import { IxAurixConfig } from "script/pools/configs/27_ixAurix.s.sol";
import { IxMetallumConfig } from "script/pools/configs/28_ixMetallum.s.sol";

/// @dev Minimal view of `ERC4626RateProvider.wrappedToken()` — returns `address` rather than
///      `IERC4626` so a try/catch probe does not depend on the concrete return-type encoding.
interface IWrappedTokenView {
    function wrappedToken() external view returns (address);
}

/**
 * @title ReportSepoliaStubTopology
 * @notice Read-only derivation of the live Sepolia stub topology for the RB-014 recorded-topology
 *         half per PB-D65 (v). Emits one pipe-delimited line per contract; those lines are the
 *         diff target the deployment record is audited against per PB-D65 (viii).
 * @dev    Never broadcasts. No CREATE, no state-changing external call. Run against Sepolia with
 *         the Sepolia canonical env (`.env` copied from `.env.sepolia`, `AUMM_ENV_CHAIN=sepolia`)
 *         so `STUB_*` resolves to the live roster and `DEPLOYER_ADDRESS` is the creating EOA.
 *         Provider discovery walks nonces 0..86 via `computeCreateAddress` and probes
 *         `wrappedToken()` — no assumption about creation order. First-occurrence token
 *         classification mirrors `DeployTestnetStubs` so the two scripts agree on WITH_RATE vs
 *         STANDARD for every literal.
 */
contract ReportSepoliaStubTopology is Script {
    address[] internal tokens;
    bool[] internal withRate;
    mapping(address => bool) internal seen;
    mapping(address => address) internal rpOfVault;

    /// @dev First occurrence wins — later slots that reuse a mainnet literal are skipped entirely,
    ///      matching `DeployTestnetStubs`' `stubOf[token] != address(0)` guard.
    function _collect(PoolConfig memory cfg) internal {
        for (uint256 i = 0; i < cfg.tokens.length; ++i) {
            address token = cfg.tokens[i];
            if (seen[token]) {
                continue;
            }
            seen[token] = true;
            tokens.push(token);
            withRate.push(cfg.tokenTypes[i] == TokenType.WITH_RATE);
        }
    }

    /// @notice Derive and console-emit the full 87-contract stub topology; reverts only after the
    ///         report is fully printed if any vault or provider is missing.
    function run() external {
        // Roster: same 26 config calls, same order, same address(0) placeholders as
        // DeployTestnetStubs.run() — duplication is deliberate; the self-check below guards drift.
        _collect(IxHelvetiaConfig.config());
        _collect(IxAetheronConfig.config(address(0), address(0)));
        _collect(IxCasperConfig.config(address(0)));
        _collect(IxEdelweissConfig.config());
        _collect(IxLibertasConfig.config(address(0), address(0)));
        _collect(IxBrevisConfig.config());
        _collect(IxAltrixConfig.config());
        _collect(IxMedioxConfig.config());
        _collect(IxLongusConfig.config());
        _collect(IxStrataConfig.config());
        _collect(IxForumConfig.config());
        _collect(IxAurebitConfig.config());
        _collect(IxRegistrumConfig.config());
        _collect(IxDebitumConfig.config());
        _collect(IxEquitixConfig.config());
        _collect(IxInnovixConfig.config());
        _collect(IxGigantusConfig.config());
        _collect(IxMagnixConfig.config(address(0)));
        _collect(IxNubixConfig.config());
        _collect(IxMonetaConfig.config());
        _collect(IxColossixConfig.config());
        _collect(IxVitalixConfig.config());
        _collect(IxMedicixConfig.config());
        _collect(IxMercaturaConfig.config());
        _collect(IxAurixConfig.config(address(0)));
        _collect(IxMetallumConfig.config());

        uint256 withRateCount;
        for (uint256 i = 0; i < withRate.length; ++i) {
            if (withRate[i]) {
                ++withRateCount;
            }
        }
        require(
            tokens.length + 2 * withRateCount == 87,
            "roster does not match the 87 deployed stub nonces"
        );

        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        for (uint256 n = 0; n < 87; ++n) {
            address candidate = vm.computeCreateAddress(deployer, n);
            try IWrappedTokenView(candidate).wrappedToken() returns (address v) {
                rpOfVault[v] = candidate;
            } catch {}
        }

        uint256 problems;
        uint256 emitted;
        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            address vault = vm.envOr(string.concat("STUB_", vm.toString(token)), address(0));
            bool vaultMissing = vault == address(0);

            if (withRate[i]) {
                if (vaultMissing) {
                    ++problems;
                    console2.log(
                        string.concat("MISSING|", vm.toString(token), "|", vm.toString(address(0)))
                    );
                } else {
                    console2.log(
                        string.concat("VAULT|", vm.toString(token), "|", vm.toString(vault))
                    );
                }
                ++emitted;

                if (vaultMissing) {
                    console2.log(
                        string.concat("MISSING|", vm.toString(token), "|", vm.toString(address(0)))
                    );
                } else {
                    address underlying = IERC4626(vault).asset();
                    console2.log(
                        string.concat(
                            "UNDERLYING|", vm.toString(token), "|", vm.toString(underlying)
                        )
                    );
                }
                ++emitted;

                address provider = vaultMissing ? address(0) : rpOfVault[vault];
                if (provider == address(0)) {
                    ++problems;
                    console2.log(
                        string.concat("MISSING|", vm.toString(token), "|", vm.toString(address(0)))
                    );
                } else {
                    console2.log(
                        string.concat("PROVIDER|", vm.toString(token), "|", vm.toString(provider))
                    );
                }
                ++emitted;
            } else {
                if (vaultMissing) {
                    ++problems;
                    console2.log(
                        string.concat("MISSING|", vm.toString(token), "|", vm.toString(address(0)))
                    );
                } else {
                    console2.log(
                        string.concat("STANDARD|", vm.toString(token), "|", vm.toString(vault))
                    );
                }
                ++emitted;
            }
        }

        console2.log("token count:", tokens.length);
        console2.log("WITH_RATE count:", withRateCount);
        console2.log("emitted line count:", emitted);
        console2.log("problems:", problems);
        require(problems == 0, "topology incomplete");
    }
}
