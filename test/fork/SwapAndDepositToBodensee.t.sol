// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { TokenConfig, TokenType, PoolRoleAccounts, AddLiquidityKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AuMM } from "../../src/token/AuMM.sol";
import { DeployAureumVault } from "../../script/DeployAureumVault.s.sol";
import { SwapAndDepositToBodensee } from "../../src/gauge/SwapAndDepositToBodensee.sol";
import { TokenInfo } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

contract SwapAndDepositToBodenseeForkTest is Test {
    using SafeERC20 for IERC20;

    bytes32 internal constant VAULT_SALT = bytes32(uint256(1));
    bytes32 internal constant BODENSEE_SALT = bytes32(uint256(2));
    uint32 internal constant PAUSE_WINDOW_DURATION = uint32(4 * 365 days);
    uint256 internal constant BUFFER_PERIOD_DURATION = 90 days;
    uint256 internal constant MIN_TRADE_AMOUNT = 1_000_000;
    uint256 internal constant MIN_WRAP_AMOUNT = 1_000;
    string internal constant FACTORY_VERSION =
        '{"name":"AureumWeightedPoolFactory","version":1,"deployment":"20260508-fork-stage-g"}';
    string internal constant POOL_VERSION =
        '{"name":"AureumWeightedPool","version":1,"deployment":"20260508-fork-stage-g"}';
    address internal constant GOVERNANCE_MULTISIG = address(uint160(uint256(keccak256("govMultisig"))));
    address internal constant SUSDS_RATE_PROVIDER = 0x1195BE91e78ab25494C855826FF595Eef784d47B;
    address internal constant SV_ZCHF_RATE_PROVIDER = 0xf32dc0eE2cC78Dca2160bb4A9B614108F28B176c;
    uint256 internal constant INIT_SEED = 1_000e18;
    uint256 internal constant FEE_SVZCHF = 100e18;
    uint256 internal constant FEE_SUSDS = 125e18;

    DeployAureumVault internal vaultScript;
    WeightedPoolFactory internal wpf;
    AuMM internal aumm;
    IVault internal vault;
    address internal bodenseePool;
    IERC20 internal svZchf;
    IERC4626 internal susds;
    SwapAndDepositToBodensee internal helper;

    event FeeRoutedToBodensee(address indexed originalCaller, IERC20 indexed payToken, uint256 amount);

    function setUp() public {
        svZchf = IERC20(vm.envAddress("SV_ZCHF"));
        susds = IERC4626(vm.envAddress("SUSDS"));

        uint64 startNonce = vm.getNonce(address(this));
        address vaultScriptAddr = vm.computeCreateAddress(address(this), startNonce + 0);
        address wpfAddr = vm.computeCreateAddress(address(this), startNonce + 1);
        address auMmAddr = vm.computeCreateAddress(address(this), startNonce + 2);
        address hookAddr = vm.computeCreateAddress(address(this), startNonce + 3);
        address predictedFactory = vm.computeCreateAddress(vaultScriptAddr, 3);
        address predictedVault = CREATE3.getDeployed(VAULT_SALT, predictedFactory);
        address predictedBodensee = CREATE3.getDeployed(
            keccak256(abi.encode(address(this), block.chainid, BODENSEE_SALT)),
            wpfAddr
        );

        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("GOVERNANCE_MULTISIG", vm.toString(GOVERNANCE_MULTISIG));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("DER_BODENSEE_POOL", vm.toString(predictedBodensee));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("FEE_ROUTING_HOOK", vm.toString(hookAddr));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("SALT", vm.toString(VAULT_SALT));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("PAUSE_WINDOW_DURATION", vm.toString(uint256(PAUSE_WINDOW_DURATION)));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("BUFFER_PERIOD_DURATION", vm.toString(BUFFER_PERIOD_DURATION));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MIN_TRADE_AMOUNT", vm.toString(MIN_TRADE_AMOUNT));
        /// forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MIN_WRAP_AMOUNT", vm.toString(MIN_WRAP_AMOUNT));

        vaultScript = new DeployAureumVault();
        assert(address(vaultScript) == vaultScriptAddr);

        vaultScript.deploy(address(vaultScript));
        vault = vaultScript.vault();
        assert(address(vault) == predictedVault);

        wpf = new WeightedPoolFactory(IVault(address(vault)), PAUSE_WINDOW_DURATION, FACTORY_VERSION, POOL_VERSION);
        assert(address(wpf) == wpfAddr);

        aumm = new AuMM(block.number, address(this));
        assert(address(aumm) == auMmAddr);

        bodenseePool = wpf.create(
            "der-Bodensee",
            "BODENSEE",
            _bodenseeTokenConfigs(),
            _bodenseeWeights(),
            PoolRoleAccounts({
                pauseManager: GOVERNANCE_MULTISIG,
                swapFeeManager: address(0),
                poolCreator: address(0)
            }),
            0.0075e18,
            address(0),
            true,
            false,
            BODENSEE_SALT
        );
        assert(bodenseePool == predictedBodensee);

        _initializeBodensee();

        helper = new SwapAndDepositToBodensee(
            vault,
            bodenseePool,
            svZchf,
            IERC20(address(susds)),
            address(this),
            address(this)
        );
        helper.setVaultClassRegistry(address(this));
        helper.setGaugeRegistry(address(this));
    }

    function _bodenseeTokenConfigs() private view returns (TokenConfig[] memory) {
        address t0 = address(aumm);
        address t1 = address(susds);
        address t2 = address(svZchf);
        if (t0 > t1) (t0, t1) = (t1, t0);
        if (t1 > t2) (t1, t2) = (t2, t1);
        if (t0 > t1) (t0, t1) = (t1, t0);

        TokenConfig[] memory tokens = new TokenConfig[](3);
        tokens[0] = t0 == address(aumm)
            ? TokenConfig({
                token: IERC20(t0),
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            })
            : t0 == address(susds)
                ? TokenConfig({
                    token: IERC20(t0),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SUSDS_RATE_PROVIDER),
                    paysYieldFees: true
                })
                : TokenConfig({
                    token: IERC20(t0),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SV_ZCHF_RATE_PROVIDER),
                    paysYieldFees: true
                });
        tokens[1] = t1 == address(aumm)
            ? TokenConfig({
                token: IERC20(t1),
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            })
            : t1 == address(susds)
                ? TokenConfig({
                    token: IERC20(t1),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SUSDS_RATE_PROVIDER),
                    paysYieldFees: true
                })
                : TokenConfig({
                    token: IERC20(t1),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SV_ZCHF_RATE_PROVIDER),
                    paysYieldFees: true
                });
        tokens[2] = t2 == address(aumm)
            ? TokenConfig({
                token: IERC20(t2),
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            })
            : t2 == address(susds)
                ? TokenConfig({
                    token: IERC20(t2),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SUSDS_RATE_PROVIDER),
                    paysYieldFees: true
                })
                : TokenConfig({
                    token: IERC20(t2),
                    tokenType: TokenType.WITH_RATE,
                    rateProvider: IRateProvider(SV_ZCHF_RATE_PROVIDER),
                    paysYieldFees: true
                });
        return tokens;
    }

    function _bodenseeWeights() private view returns (uint256[] memory) {
        address t0 = address(aumm);
        address t1 = address(susds);
        address t2 = address(svZchf);
        if (t0 > t1) (t0, t1) = (t1, t0);
        if (t1 > t2) (t1, t2) = (t2, t1);
        if (t0 > t1) (t0, t1) = (t1, t0);

        uint256[] memory weights = new uint256[](3);
        weights[0] = t0 == address(aumm) ? 4e17 : 3e17;
        weights[1] = t1 == address(aumm) ? 4e17 : 3e17;
        weights[2] = t2 == address(aumm) ? 4e17 : 3e17;
        return weights;
    }

    function _initializeBodensee() internal returns (uint256 bptOut) {
        deal(address(aumm), address(this), INIT_SEED, true);
        deal(address(susds), address(this), INIT_SEED, true);
        deal(address(svZchf), address(this), INIT_SEED, true);

        bytes memory result = vault.unlock(abi.encodeCall(this._initializeBodenseeCallback, ()));
        bptOut = abi.decode(result, (uint256));
    }

    function _initializeBodenseeCallback() external returns (uint256 bptOut) {
        require(msg.sender == address(vault), "onlyVault");
        address t0 = address(aumm);
        address t1 = address(susds);
        address t2 = address(svZchf);
        if (t0 > t1) (t0, t1) = (t1, t0);
        if (t1 > t2) (t1, t2) = (t2, t1);
        if (t0 > t1) (t0, t1) = (t1, t0);

        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = IERC20(t0);
        tokens[1] = IERC20(t1);
        tokens[2] = IERC20(t2);
        uint256[] memory amountsIn = new uint256[](3);
        amountsIn[0] = INIT_SEED;
        amountsIn[1] = INIT_SEED;
        amountsIn[2] = INIT_SEED;

        bptOut = vault.initialize(bodenseePool, address(this), tokens, amountsIn, 0, "");
        for (uint256 i = 0; i <= 2; ++i) {
            tokens[i].safeTransfer(address(vault), amountsIn[i]);
            vault.settle(tokens[i], amountsIn[i]);
        }
    }

    function testSvZchfHappyPathFork() public {
        deal(address(svZchf), address(helper), FEE_SVZCHF, true);

        (IERC20[] memory tokensPre, , uint256[] memory balancesRawPre, ) = vault.getPoolTokenInfo(bodenseePool);
        uint256 svZchfIdx;
        bool found;
        for (uint256 i = 0; i < tokensPre.length; ++i) {
            if (tokensPre[i] == svZchf) {
                svZchfIdx = i;
                found = true;
                break;
            }
        }
        assertTrue(found, "svZCHF not in Bodensee");
        uint256 preReserve = balancesRawPre[svZchfIdx];

        vm.expectEmit(true, true, false, true);
        emit FeeRoutedToBodensee(address(this), svZchf, FEE_SVZCHF);
        helper.swapAndDeposit(svZchf, FEE_SVZCHF);

        (, , uint256[] memory balancesRawPost, ) = vault.getPoolTokenInfo(bodenseePool);
        uint256 postReserve = balancesRawPost[svZchfIdx];
        assertEq(postReserve - preReserve, FEE_SVZCHF, "svZCHF reserve delta != fee");
        assertEq(svZchf.balanceOf(address(helper)), 0, "helper svZCHF residue not zero");
    }

    function testSUsdsHappyPathFork() public {
        deal(address(susds), address(helper), FEE_SUSDS, true);

        IERC20 susdsErc = IERC20(address(susds));
        (IERC20[] memory tokensPre, , uint256[] memory balancesRawPre, ) = vault.getPoolTokenInfo(bodenseePool);
        uint256 susdsIdx;
        bool found;
        for (uint256 i = 0; i < tokensPre.length; ++i) {
            if (tokensPre[i] == susdsErc) {
                susdsIdx = i;
                found = true;
                break;
            }
        }
        assertTrue(found, "sUSDS not in Bodensee");
        uint256 preReserve = balancesRawPre[susdsIdx];

        vm.expectEmit(true, true, false, true);
        emit FeeRoutedToBodensee(address(this), susdsErc, FEE_SUSDS);
        helper.swapAndDeposit(susdsErc, FEE_SUSDS);

        (, , uint256[] memory balancesRawPost, ) = vault.getPoolTokenInfo(bodenseePool);
        uint256 postReserve = balancesRawPost[susdsIdx];
        assertEq(postReserve - preReserve, FEE_SUSDS, "sUSDS reserve delta != fee");
        assertEq(susdsErc.balanceOf(address(helper)), 0, "helper sUSDS residue not zero");
    }

    function testReserveDeltaMismatchUnderMockedReserves() public {
        deal(address(svZchf), address(helper), FEE_SVZCHF, true);

        (
            IERC20[] memory tokens,
            TokenInfo[] memory tokenInfo,
            uint256[] memory balancesRaw,
            uint256[] memory balancesScaled18
        ) = vault.getPoolTokenInfo(bodenseePool);

        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IVaultExtension.getPoolTokenInfo.selector, bodenseePool),
            abi.encode(tokens, tokenInfo, balancesRaw, balancesScaled18)
        );

        // Foundry's vm.expectRevert(bytes4) requires exact revert-data match (selector + encoded params); use abi.encodeWithSelector with both expected and actual values per the helper's ReserveDeltaMismatch(expected, actual) signature.
        vm.expectRevert(abi.encodeWithSelector(SwapAndDepositToBodensee.ReserveDeltaMismatch.selector, INIT_SEED + FEE_SVZCHF, INIT_SEED));
        helper.swapAndDeposit(svZchf, FEE_SVZCHF);

        // PLAN L185 "mock transfer" is approximated by mocking `getPoolTokenInfo`: transfer/settle/addLiquidity hit the
        // real Vault, while `_currentReserve` keeps seeing frozen `balancesRaw`, so step-8 yields `ReserveDeltaMismatch`.
        vm.clearMockedCalls();
    }
}
