// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig } from "script/pools/PoolConfig.sol";

import { StubERC20 } from "test-stubs/StubERC20.sol";
import { StubERC4626 } from "test-stubs/StubERC4626.sol";
import { ERC4626RateProvider } from "src/rate_provider/ERC4626RateProvider.sol";

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

/**
 * @title DeployTestnetStubs
 * @notice PB3.2e (PB-D21): materializes the testnet token-stub roster by iterating all 26 Miliarium
 *         config libraries against a mainnet fork. WITH_RATE slots get an 18-dec StubERC20 underlying +
 *         a StubERC4626 + a real ERC4626RateProvider; STANDARD slots get a StubERC20 at the token's real
 *         mainnet decimals. Every STUB_ key derives from the same cfg.* literal the deploy-miliarium-pool
 *         resolver reads (drift-free per PB-D20 (ii)). Fork-run only, no broadcast, at e2 and PB3.4; the
 *         real Sepolia broadcast is PB3.5. This file (e2b1) is the iterate-and-deploy core; the named-key
 *         emission, console map, and coverage asserts land at e2b2.
 */
contract DeployTestnetStubs is Script {
    /// @dev mainnet token/RP address -> deployed stub; also the dedup sentinel (address(0) = unseen).
    mapping(address => address) internal stubOf;
    /// @dev mainnet WITH_RATE token -> its deployed ERC4626RateProvider (for the e2b2 named-key emission).
    mapping(address => address) internal rpOfToken;

    /// @dev Ordered emission pairs — STUB_-literal keys + (e2b2) named keys — console-logged by _emitMap.
    string[] internal envKeys;
    address[] internal envVals;

    function run() external {
        _processConfig(IxHelvetiaConfig.config());
        _processConfig(IxAetheronConfig.config(address(0), address(0)));
        _processConfig(IxCasperConfig.config(address(0)));
        _processConfig(IxEdelweissConfig.config());
        _processConfig(IxLibertasConfig.config(address(0), address(0)));
        _processConfig(IxBrevisConfig.config());
        _processConfig(IxAltrixConfig.config());
        _processConfig(IxMedioxConfig.config());
        _processConfig(IxLongusConfig.config());
        _processConfig(IxStrataConfig.config());
        _processConfig(IxForumConfig.config());
        _processConfig(IxAurebitConfig.config());
        _processConfig(IxRegistrumConfig.config());
        _processConfig(IxDebitumConfig.config());
        _processConfig(IxEquitixConfig.config());
        _processConfig(IxInnovixConfig.config());
        _processConfig(IxGigantusConfig.config());
        _processConfig(IxMagnixConfig.config(address(0)));
        _processConfig(IxNubixConfig.config());
        _processConfig(IxMonetaConfig.config());
        _processConfig(IxColossixConfig.config());
        _processConfig(IxVitalixConfig.config());
        _processConfig(IxMedicixConfig.config());
        _processConfig(IxMercaturaConfig.config());
        _processConfig(IxAurixConfig.config(address(0)));
        _processConfig(IxMetallumConfig.config());

        console2.log("STUB_ pairs recorded (unique tokens + hardcoded RPs):", envKeys.length);
    }

    /// @dev Deploy stubs for every token slot in `cfg`, deduped by mainnet address (first-seen wins).
    function _processConfig(PoolConfig memory cfg) internal {
        for (uint256 i = 0; i < cfg.tokens.length; ++i) {
            address token = cfg.tokens[i];
            if (cfg.tokenTypes[i] == TokenType.WITH_RATE) {
                _ensureWithRate(token);
                address rp = address(cfg.rateProviders[i]);
                if (rp != address(0) && stubOf[rp] == address(0)) {
                    stubOf[rp] = rpOfToken[token];
                    _record(string.concat("STUB_", vm.toString(rp)), rpOfToken[token]);
                }
            } else {
                _ensureStandard(token);
            }
        }
    }

    /// @dev WITH_RATE: 18-dec StubERC20 underlying + StubERC4626 + ERC4626RateProvider (PB-D21 (ii)); 18/18.
    function _ensureWithRate(address token) internal {
        if (stubOf[token] != address(0)) return;
        StubERC20 underlying = new StubERC20("Stub Underlying", "STUBU", 18);
        StubERC4626 vault = new StubERC4626(IERC20(address(underlying)), "Stub Vault", "STUBV");
        ERC4626RateProvider rp = new ERC4626RateProvider(IERC4626(address(vault)));
        stubOf[token] = address(vault);
        rpOfToken[token] = address(rp);
        _record(string.concat("STUB_", vm.toString(token)), address(vault));
    }

    /// @dev STANDARD: StubERC20 at the token's real mainnet decimals (read off the fork; PB-D21 (ii)).
    function _ensureStandard(address token) internal {
        if (stubOf[token] != address(0)) return;
        uint8 dec = IERC20Metadata(token).decimals();
        StubERC20 stub = new StubERC20("Stub Standard", "STUBS", dec);
        stubOf[token] = address(stub);
        _record(string.concat("STUB_", vm.toString(token)), address(stub));
    }

    /// @dev Append an emission pair.
    function _record(string memory key, address val) internal {
        envKeys.push(key);
        envVals.push(val);
    }
}
