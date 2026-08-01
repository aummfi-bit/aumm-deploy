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
    /// @dev mainnet TOKEN address -> deployed stub; also the dedup sentinel (address(0) = unseen).
    ///      Rate-provider literals are keyed separately in `stubRpOf` per PB-D47 (vii): holding both in
    ///      one namespace let a token that is its own rate provider shadow itself, which is how slot 02
    ///      registered a pool token as its own provider and became permanently un-initializable.
    mapping(address => address) internal stubOf;
    /// @dev mainnet WITH_RATE token -> its deployed ERC4626RateProvider (for the e2b2 named-key emission).
    mapping(address => address) internal rpOfToken;
    /// @dev mainnet RATE-PROVIDER literal -> deployed stub provider; the dedup sentinel for the STUB_RP_
    ///      namespace, disjoint from `stubOf` so a self-referential provider literal cannot collide with
    ///      the token entry that shares its address (PB-D47 (vii)).
    mapping(address => address) internal stubRpOf;

    /// @dev Ordered emission pairs — STUB_-literal keys + (e2b2) named keys — console-logged by _emitMap.
    string[] internal envKeys;
    address[] internal envVals;

    /// @dev PB-D27 (ii) — the STANDARD-slot decimals table: mainnet literal to its real decimals, read
    ///      off the fork here and captured into the committed artifact at PB3.5b2. The Sepolia entry
    ///      consumes these instead of calling decimals() on a literal that carries no code there.
    string[] internal decKeys;
    uint8[] internal decVals;

    /// @dev PB-D27 (ii) — chain 1 is the only environment where the STANDARD literals carry code, so
    ///      it is the only one that can derive decimals. Same signal as the Sanity.t.sol L59-L62 guard.
    uint256 internal constant MAINNET_CHAIN_ID = 1;

    function run() external {
        // PB-D31: every CREATE in this script happens inside the 26 `_processConfig` calls below.
        // Without this wrapper a live `--broadcast` sends nothing while still emitting a complete
        // STUB_ map of addresses that carry no code on the target chain.
        vm.startBroadcast();
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
        vm.stopBroadcast();

        console2.log("STUB_ pairs recorded (unique tokens + hardcoded RPs):", envKeys.length);
        _emitNamedKeys();
        _assertCoverage();
        _emitMap();
        _emitDecimalsMap();
    }

    /// @dev Deploy stubs for every token slot in `cfg`, deduped by mainnet address (first-seen wins).
    function _processConfig(PoolConfig memory cfg) internal {
        for (uint256 i = 0; i < cfg.tokens.length; ++i) {
            address token = cfg.tokens[i];
            if (cfg.tokenTypes[i] == TokenType.WITH_RATE) {
                _ensureWithRate(token);
                address rp = address(cfg.rateProviders[i]);
                if (rp != address(0) && stubRpOf[rp] == address(0)) {
                    stubRpOf[rp] = rpOfToken[token];
                    _record(string.concat("STUB_RP_", vm.toString(rp)), rpOfToken[token]);
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

    /// @dev STANDARD: StubERC20 at the token's real mainnet decimals — read off the literal on chain 1,
    ///      else out of the committed table via _standardDecimals (PB-D21 (ii), PB-D27 (ii)).
    function _ensureStandard(address token) internal {
        if (stubOf[token] != address(0)) return;
        uint8 dec = _standardDecimals(token);
        _recordDecimals(string.concat("DECIMALS_", vm.toString(token)), dec);
        StubERC20 stub = new StubERC20("Stub Standard", "STUBS", dec);
        stubOf[token] = address(stub);
        _record(string.concat("STUB_", vm.toString(token)), address(stub));
    }

    /// @dev PB-D27 (ii) — the decimals source, split by environment. On chain 1 the literal has code,
    ///      so read it. Everywhere else read the committed table (script/config/mainnet-token-decimals.env,
    ///      merged into .env per PB-D27 (iii)) with NO default — a missing key reverts the run before any
    ///      stub is constructed rather than seating a wrong-decimals stub. The uint8 bound is cast safety,
    ///      not policy: an out-of-range table value would truncate silently, the PB-D26 class of defect.
    function _standardDecimals(address token) internal view returns (uint8) {
        if (block.chainid == MAINNET_CHAIN_ID) {
            return IERC20Metadata(token).decimals();
        }
        uint256 fromTable = vm.envUint(string.concat("DECIMALS_", vm.toString(token)));
        require(fromTable <= type(uint8).max, "decimals table value exceeds uint8");
        return uint8(fromTable);
    }

    /// @dev Append an emission pair.
    function _record(string memory key, address val) internal {
        envKeys.push(key);
        envVals.push(val);
    }

    /// @dev Append a decimals-table pair. Held in its own arrays rather than the envKeys / envVals pair
    ///      list so the PB-D25 (ii) replay surface the rehearsal harness consumes — envPairAt returning
    ///      (string, address) — stays signature-identical.
    function _recordDecimals(string memory key, uint8 dec) internal {
        decKeys.push(key);
        decVals.push(dec);
    }

    /// @dev PB-D21 (iii)/(iv): the 5 N-D7 named-key RPs + the Tier-A SV_ZCHF / SUSDS keys. Each references
    ///      the config-library constant (zero-drift), mapping the named key to the stub RP / stub 4626 of
    ///      its token — these enter the pool configs via _config() params or protocol scripts, not STUB_.
    function _emitNamedKeys() internal {
        _record("WAETHWSTETH_COMPOSITE_RATE_PROVIDER", rpOfToken[IxCasperConfig.WAETHWSTETH]);
        _record("SFRXETH_RATE_PROVIDER", rpOfToken[IxAetheronConfig.SFRXETH]);
        _record("WOETH_RATE_PROVIDER", rpOfToken[IxAetheronConfig.WOETH]);
        _record("YSYBOLD_RATE_PROVIDER", rpOfToken[IxLibertasConfig.YSYBOLD]);
        _record("SCRVUSD_RATE_PROVIDER", rpOfToken[IxLibertasConfig.SCRVUSD]);
        _record("SV_ZCHF", stubOf[IxCasperConfig.SVZCHF]);
        _record("SUSDS", stubOf[IxHelvetiaConfig.SUSDS]);
    }

    /// @dev PB-D21 (vi): coverage gate. Each named-key token must have resolved to a stub, and every
    ///      emitted pair must carry a real value — no unresolved literal leaks through to a mainnet
    ///      address on testnet. Reverts the run on any gap.
    function _assertCoverage() internal view {
        require(rpOfToken[IxCasperConfig.WAETHWSTETH] != address(0), "STUB: waEthwstETH RP unresolved");
        require(rpOfToken[IxAetheronConfig.SFRXETH] != address(0), "STUB: sfrxETH RP unresolved");
        require(rpOfToken[IxAetheronConfig.WOETH] != address(0), "STUB: wOETH RP unresolved");
        require(rpOfToken[IxLibertasConfig.YSYBOLD] != address(0), "STUB: ysyBOLD RP unresolved");
        require(rpOfToken[IxLibertasConfig.SCRVUSD] != address(0), "STUB: scrvUSD RP unresolved");
        require(stubOf[IxCasperConfig.SVZCHF] != address(0), "STUB: svZCHF stub unresolved");
        require(stubOf[IxHelvetiaConfig.SUSDS] != address(0), "STUB: sUSDS stub unresolved");
        for (uint256 i = 0; i < envVals.length; ++i) {
            require(envVals[i] != address(0), "STUB: emitted pair has zero value");
        }
    }

    /// @dev Console-log the fork-sample env-map (PB-D21 (v)): STUB_-literal pairs then the named keys.
    ///      Captured into test-stubs/sepolia-stubs.env at e3; PB3.5 regenerates it with live Sepolia
    ///      addresses. Keys are canonical (mainnet literals); values are fork-throwaway.
    function _emitMap() internal view {
        console2.log("# PB3.2 testnet stub env-map (fork-sample; regenerated with live addresses at PB3.5)");
        for (uint256 i = 0; i < envKeys.length; ++i) {
            console2.log(string.concat(envKeys[i], "=", vm.toString(envVals[i])));
        }
    }

    /// @dev PB-D27 (ii): console-log the STANDARD-slot decimals table as a second, separately captured
    ///      block. Emitted apart from _emitMap so the address-map capture stays byte-clean — the two
    ///      artifacts have different lifecycles: the addresses are environment-specific and regenerate
    ///      at every broadcast, while these decimals are mainnet truth, committed once.
    function _emitDecimalsMap() internal view {
        console2.log("DECIMALS_ pairs recorded (unique STANDARD tokens):", decKeys.length);
        console2.log("# PB3.5 STANDARD-slot decimals table (mainnet-derived; stable across environments)");
        for (uint256 i = 0; i < decKeys.length; ++i) {
            console2.log(string.concat(decKeys[i], "=", vm.toString(uint256(decVals[i]))));
        }
    }

    /// @notice PB-D25 (ii) — the rehearsal-harness replay surface: the count of accumulated
    ///         (key, value) emission pairs (the STUB_ literals + the named keys), in emission order.
    function envPairCount() external view returns (uint256) {
        return envKeys.length;
    }

    /// @notice PB-D25 (ii) — the emission pair at index `i`; the rehearsal harness loops these into
    ///         vm.setEnv so it consumes the same drift-free map the e2 capture and the PB3.5 Sepolia
    ///         broadcast read.
    function envPairAt(uint256 i) external view returns (string memory key, address val) {
        return (envKeys[i], envVals[i]);
    }
}
