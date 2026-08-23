// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test, stdError} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {VaultClassRegistry} from "src/gauge/VaultClassRegistry.sol";
import {IVaultClassRegistry} from "src/gauge/IVaultClassRegistry.sol";
import {SwapAndDepositToBodensee} from "src/gauge/SwapAndDepositToBodensee.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VotingWeight} from "src/governance/VotingWeight.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {MockEMASampler, MockGaugeRegistry, MockMiliariumRegistry, MockRecorder} from "test/unit/VotingWeight.t.sol";
import {MockSwapAndDepositToBodensee} from "test/unit/VaultClassRegistry.t.sol";

/// @title P1 B.7 — vetoProposal banks absolute weight against a live totalSupply
/// @notice Reproduction PoC for seam-1 root cause B.7 (Medium). Reopens F-15's PB-D10
///         Accepted-risk disposition in the deflation direction — F15_vetoDenominatorInflation.t.sol
///         cannot see it because all six of its tests move the denominator upward.
contract P1_B7_VetoDenominatorDeflationTest is Test {
    VotingWeight internal vw;
    MockEMASampler internal emaSampler;
    MockGaugeRegistry internal gaugeReg;
    MockRecorder internal recorder;
    MockMiliariumRegistry internal miliariumReg;

    MockERC20 internal svZCHF;
    MockSwapAndDepositToBodensee internal helper;
    VaultClassRegistry internal registry;

    address internal vwSetter;
    address internal govSetter;
    address internal governance;
    address internal defender;

    address internal vetoer1;
    address internal vetoer2;
    address internal neutral;
    address internal dormant;
    address internal stranger;

    uint256 internal constant GENESIS_BLOCK = 1_000_000;
    uint256 internal constant START_BLOCK = 2_000_000;

    address internal constant POOL_VETOER1 = address(0xD1);
    address internal constant POOL_VETOER2 = address(0xD2);
    address internal constant POOL_NEUTRAL = address(0xD3);
    address internal constant POOL_DORMANT = address(0xD4);

    function setUp() public {
        emaSampler = new MockEMASampler();
        gaugeReg = new MockGaugeRegistry();
        recorder = new MockRecorder();
        miliariumReg = new MockMiliariumRegistry();
        vw = new VotingWeight(emaSampler, gaugeReg, recorder, miliariumReg, GENESIS_BLOCK);

        svZCHF = new MockERC20("svZCHF", "svZCHF", 18);
        helper = new MockSwapAndDepositToBodensee();

        vwSetter = makeAddr("vwSetter");
        govSetter = makeAddr("govSetter");
        governance = makeAddr("governance");
        defender = makeAddr("defender");

        vetoer1 = makeAddr("vetoer1");
        vetoer2 = makeAddr("vetoer2");
        neutral = makeAddr("neutral");
        dormant = makeAddr("dormant");
        stranger = makeAddr("stranger");

        registry = new VaultClassRegistry(
            IERC20(address(svZCHF)),
            SwapAndDepositToBodensee(address(helper)),
            vwSetter,
            govSetter,
            new address[](0),
            new IVaultClassRegistry.AdmissionType[](0)
        );

        vm.prank(vwSetter);
        registry.setVotingWeight(address(vw));
        vm.prank(govSetter);
        registry.setGovernanceContract(governance);

        svZCHF.mint(defender, 100_000e18);
        vm.prank(defender);
        svZCHF.approve(address(registry), type(uint256).max);

        address[] memory pools = new address[](4);
        pools[0] = POOL_VETOER1;
        pools[1] = POOL_VETOER2;
        pools[2] = POOL_NEUTRAL;
        pools[3] = POOL_DORMANT;
        miliariumReg.setPoolList(pools);

        vm.mockCall(POOL_VETOER1, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(1e30)));
        vm.mockCall(POOL_VETOER2, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(1e30)));
        vm.mockCall(POOL_NEUTRAL, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(1e30)));
        vm.mockCall(POOL_DORMANT, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(1e30)));

        vm.roll(START_BLOCK);

        uint256 eqb = START_BLOCK - AureumTime.ON_RAMP_PERIOD_BLOCKS;
        _configurePosition(POOL_VETOER1, vetoer1, true, 16e18, 100e18, 100e18, eqb);
        _configurePosition(POOL_VETOER2, vetoer2, true, 16e18, 100e18, 100e18, eqb);
        _configurePosition(POOL_NEUTRAL, neutral, true, 4096e18, 100e18, 100e18, eqb);
        _configurePosition(POOL_DORMANT, dormant, true, 65536e18, 100e18, 100e18, eqb);
    }

    function _configurePosition(
        address pool,
        address holder,
        bool gaugeApproved,
        uint256 tvlValue,
        uint256 lp,
        uint256 totalLP,
        uint256 eqb
    ) internal {
        gaugeReg.setApproved(pool, gaugeApproved);
        emaSampler.setTvlEMA(pool, tvlValue);
        emaSampler.setSeedBlock(pool, 1);
        emaSampler.setLastUpdateBlock(pool, block.number);
        recorder.setUserLP(pool, holder, lp);
        recorder.setPoolTotalLP(pool, totalLP);
        recorder.setEffectiveQualBlock(pool, holder, eqb);
    }

    function _propose(address admissionValue) private returns (uint256) {
        vm.prank(defender);
        return registry.proposeVaultClass(IVaultClassRegistry.AdmissionType.ImplementationAddress, admissionValue, bytes32(0));
    }

    /// @notice Falling totalSupply lets a zero-weight caller ratchet a banked veto over threshold.
    function test_P1_B7_supplyDeflationLetsAZeroWeightCallerRatchetABankedVetoOverThreshold() public {
        vw.poke(vetoer1);
        vw.poke(neutral);
        vw.poke(dormant);

        assertApproxEqRel(vw.totalSupply(), 26e18, 1e15);

        address admissionValue = makeAddr("admissionB7a");
        uint256 id = _propose(admissionValue);

        vm.prank(vetoer1);
        registry.vetoProposal(id);

        (,,,, uint256 vetoSupportAfterFirst, bool finalizedAfterFirst, bool revokedAfterFirst) = registry.proposals(id);
        assertApproxEqRel(vetoSupportAfterFirst, 2e18, 1e15);
        assertFalse(finalizedAfterFirst);
        assertFalse(revokedAfterFirst);
        assertLt((vetoSupportAfterFirst * 10_000) / vw.totalSupply(), registry.VETO_THRESHOLD_BPS());

        gaugeReg.setApproved(POOL_DORMANT, false);
        vw.poke(dormant);

        assertApproxEqRel(vw.totalSupply(), 10e18, 1e15);

        vm.prank(stranger);
        registry.vetoProposal(id);

        (,,,,, bool finalized, bool revoked) = registry.proposals(id);
        assertTrue(finalized);
        assertTrue(revoked);
    }

    /// @notice Zero totalSupply panics every veto attempt and the class finalizes unopposed after the window.
    function test_P1_B7_zeroSupplyPanicBarsEveryVetoAndTheClassFinalizesUnopposed() public {
        assertEq(vw.totalSupply(), 0);

        address admissionValue = makeAddr("admissionB7b");
        uint256 id = _propose(admissionValue);

        vm.expectRevert(stdError.divisionError);
        vm.prank(stranger);
        registry.vetoProposal(id);

        assertFalse(registry.hasVetoed(id, stranger));

        vm.roll(block.number + registry.VETO_WINDOW_BLOCKS() + 1);

        registry.finalizeProposal(id);

        assertTrue(registry.isAdmittedClass(admissionValue));
    }
}
