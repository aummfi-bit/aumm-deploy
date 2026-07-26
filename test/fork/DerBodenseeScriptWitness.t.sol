// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";
import { StubERC20 } from "../../test-stubs/StubERC20.sol";
import { StubERC4626 } from "../../test-stubs/StubERC4626.sol";
import { ERC4626RateProvider } from "../../src/rate_provider/ERC4626RateProvider.sol";
import { DeployDerBodensee } from "../../script/DeployDerBodensee.s.sol";
import { DeployAureumWeightedPoolFactory } from "../../script/DeployAureumWeightedPoolFactory.s.sol";

/**
 * @title  DerBodenseeScriptWitnessTest
 * @notice PB3.5d1 (PB-D27 (vi)) — the first script-driven coverage of DeployDerBodensee.run().
 *         The P10 fixture and the PB3.4 rehearsal both inline the factory create() call for the
 *         creator-scoped CREATE3 reason P-D34 records, so run() has zero coverage on every path.
 *         This harness is standalone by the PB-D25 rationale (no StagePIntegrationFixture
 *         inheritance, so the P10 close gate stays byte-identical).
 * @dev    Run file-scoped per D35/D36: forge test match-path on this file, fork-url mainnet, threads 1.
 */
contract DerBodenseeScriptWitnessTest is Test {
    address internal constant BALANCER_V3_VAULT_MAINNET = 0xbA1333333333a1BA1108E8412f11850A5C319bA9;
    bytes32 internal constant BODENSEE_SALT = bytes32(uint256(2));
    // Mainnet literals hardcoded at DeployDerBodensee.s.sol L145 and L155 — used here only as the STUB_ lookup keys.
    address internal constant SUSDS_RATE_PROVIDER = 0x1195BE91e78ab25494C855826FF595Eef784d47B;
    address internal constant SV_ZCHF_RATE_PROVIDER = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;
    address internal constant GOVERNOR = address(uint160(uint256(keccak256("witnessGovernorEOA"))));

    DeployDerBodensee internal script;
    IVault internal vault;
    address internal factory;
    StubERC20 internal aumm;
    StubERC20 internal susdsUnderlying;
    StubERC20 internal svZchfUnderlying;
    StubERC4626 internal susds;
    StubERC4626 internal svZchf;
    ERC4626RateProvider internal susdsRp;
    ERC4626RateProvider internal svZchfRp;
    address internal predictedPool;
    address internal pool;

    function setUp() public {
        // (1)
        vault = IVault(BALANCER_V3_VAULT_MAINNET);

        // (2)
        aumm = new StubERC20("Aureum Market Maker", "AUMM", 18);

        // (3)
        susdsUnderlying = new StubERC20("Sky USDS", "USDS", 18);
        susds = new StubERC4626(IERC20(address(susdsUnderlying)), "Savings USDS", "sUSDS");

        // (4)
        svZchfUnderlying = new StubERC20("Frankencoin", "ZCHF", 18);
        svZchf = new StubERC4626(IERC20(address(svZchfUnderlying)), "Savings ZCHF", "svZCHF");

        // (5) Both underlyings are 18-decimal because the ERC4626RateProvider constructor enforces
        //     18-decimal shares AND an 18-decimal asset per F-11 (src/rate_provider/ERC4626RateProvider.sol L53-L59).
        susdsRp = new ERC4626RateProvider(IERC4626(address(susds)));
        svZchfRp = new ERC4626RateProvider(IERC4626(address(svZchf)));

        // (6) PB-D27 (ix): Sepolia deploys the UPSTREAM WeightedPoolFactory, so the witness exercises
        //     the same factory the broadcast will, here bound to the live forked mainnet Vault.
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("AUREUM_VAULT", vm.toString(BALANCER_V3_VAULT_MAINNET));

        // (7)
        factory = new DeployAureumWeightedPoolFactory().run();

        // (8)
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("WEIGHTED_POOL_FACTORY", vm.toString(factory));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("AUMM", vm.toString(address(aumm)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("SUSDS", vm.toString(address(susds)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("SV_ZCHF", vm.toString(address(svZchf)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("GOVERNANCE_MULTISIG", vm.toString(GOVERNOR));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("BODENSEE_SALT", vm.toString(BODENSEE_SALT));

        // (9) STUB_ keys built as string.concat("STUB_", vm.toString(<RP>)) so the key spelling cannot
        //     drift from the script's own lookup at DeployDerBodensee.s.sol L51.
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv(string.concat("STUB_", vm.toString(SUSDS_RATE_PROVIDER)), vm.toString(address(susdsRp)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv(string.concat("STUB_", vm.toString(SV_ZCHF_RATE_PROVIDER)), vm.toString(address(svZchfRp)));

        // (10) DEFAULT_SENDER is forge-std's default foundry sender (lib/forge-std/src/Base.sol L22),
        //      in scope through Test. DeployDerBodensee.run() opens a bare vm.startBroadcast()
        //      (DeployDerBodensee.s.sol L101), whose sender resolves to that default when neither a
        //      sender flag nor a single signer is configured. BasePoolFactory._computeFinalSalt hashes
        //      the create() caller (lib/balancer-v3-monorepo/pkg/pool-utils/contracts/BasePoolFactory.sol
        //      L126-L128) while the FACTORY is the CREATE3 creator. This is the deliberate delta from
        //      StagePRunRehearsal.t.sol L136-L139, which is scoped to the test contract there only
        //      because it calls the factory create() inline rather than through the script.
        predictedPool = CREATE3.getDeployed(
            keccak256(abi.encode(DEFAULT_SENDER, block.chainid, BODENSEE_SALT)),
            factory
        );
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("DER_BODENSEE_POOL", vm.toString(predictedPool));

        // (11)
        script = new DeployDerBodensee();
        pool = script.run();
    }

    function test_Witness_PoolDeployedAndRegistered() public {
        assertTrue(pool != address(0), "pool is zero address");
        assertEq(pool, predictedPool, "pool diverged from CREATE3 prediction");
        assertTrue(pool.code.length > 0, "pool has no code");
        assertTrue(vault.isPoolRegistered(pool), "pool not registered with vault");
    }
}
