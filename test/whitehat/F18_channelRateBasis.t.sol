// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {BodenseeBootstrapChannel} from "src/emission/BodenseeBootstrapChannel.sol";
import {AuMM} from "src/token/AuMM.sol";
import {IAuMM} from "src/token/IAuMM.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

/// @notice Minimal Balancer V3 Vault stub — only getPoolTokens is exercised, by the
///         BodenseeBootstrapChannel constructor's _aummIndex lookup. accrue() (the F-18 surface)
///         never calls the Vault, so no other Vault method is needed.
contract MockVaultLite {
    IERC20[] private _tokens;

    function setTokens(IERC20[] calldata t) external {
        delete _tokens;
        for (uint256 i = 0; i < t.length; ++i) {
            _tokens.push(t[i]);
        }
    }

    function getPoolTokens(address) external view returns (IERC20[] memory) {
        return _tokens;
    }
}

/// @title F18_channelRateBasis — F-18 (Low) cross-seam (a) witness. BodenseeBootstrapChannel.accrue
///        must key the emission rate to an integrand block (Era 0), not the call block, so the channel's
///        minted bootstrap tranche always equals the EmissionDistributor's Era-0 subtraction from the LP
///        tranche (H-D26 / H-D27 conservation). Pre-fix accrue() reads blockEmissionRate(block.number); a
///        first bootstrap-spanning accrue() from an Era >= 1 call block prices the whole window at the
///        halved rate and under-funds der Bodensee. Post-fix reads blockEmissionRate(to) — robust for any
///        call era. Uses the real AuMM so blockEmissionRate is the genuine GENESIS_RATE >> era halving.
///        See docs/STAGE_P_NOTES.md P-D19.
contract F18ChannelRateBasisTest is Test {
    uint256 internal constant GENESIS = 1_000_000;
    address internal constant BODENSEE = address(0xB0DE);
    address internal constant GOV = address(0xC0FE);

    MockVaultLite internal vault;
    AuMM internal aumm;

    function setUp() public {
        vault = new MockVaultLite();
        aumm = new AuMM(GENESIS, address(this));

        IERC20[] memory roster = new IERC20[](3);
        roster[0] = IERC20(address(0xA11CE));
        roster[1] = IERC20(address(0xB0B));
        roster[2] = IERC20(address(aumm));
        vault.setTokens(roster);
    }

    function _deployChannel() internal returns (BodenseeBootstrapChannel) {
        return new BodenseeBootstrapChannel(IVault(address(vault)), BODENSEE, IAuMM(address(aumm)), GENESIS, GOV);
    }

    function _m6() internal pure returns (uint256) {
        return AureumTime.month6EndBlock(GENESIS);
    }

    function _m10() internal pure returns (uint256) {
        return AureumTime.month10EndBlock(GENESIS);
    }

    /// @notice Test-side mirror of BodenseeBootstrapChannel._apSum (byte-identical, H-D27).
    function _apSum(
        uint256 from,
        uint256 to,
        uint256 anchorStart,
        uint256 anchorEnd,
        uint256 startShare,
        uint256 dropShare,
        uint256 rate
    ) internal pure returns (uint256) {
        uint256 width = anchorEnd - anchorStart;
        uint256 first = startShare - (dropShare * (from - anchorStart)) / width;
        uint256 last = startShare - (dropShare * (to - anchorStart)) / width;
        uint256 n = to - from + 1;
        return ((first + last) * n * rate) / (2 * 1e18);
    }

    /// @notice The full-window Era-0 Bodensee tranche = the exact quantity the distributor subtracts from
    ///         the LP tranche over [genesis+1, m10] at GENESIS_RATE (boundary-spanning A-leg + B-leg).
    function _era0BootstrapTranche() internal pure returns (uint256) {
        uint256 aSum = _apSum(GENESIS + 1, _m6(), GENESIS, _m6(), 8e17, 3e17, 1e18);
        uint256 bSum = _apSum(_m6() + 1, _m10(), _m6(), _m10(), 5e17, 5e17, 1e18);
        return aSum + bSum;
    }

    /// @notice Witness: accrual over the bootstrap window must be invariant to the call-block era. An
    ///         in-window (Era 0) accrual and a late (Era 1) accrual of the same [genesis+1, m10] interval
    ///         must produce identical pendingAccrual. Pre-fix the Era-1 accrual is halved (rate keyed to
    ///         block.number) so this assertEq is RED; post-fix (rate keyed to `to`) GREEN.
    function test_F18_witness_accrualInvariantToCallEra() public {
        BodenseeBootstrapChannel chEra0 = _deployChannel();
        vm.roll(_m10());
        chEra0.accrue();
        uint256 correct = chEra0.pendingAccrual();

        BodenseeBootstrapChannel chEra1 = _deployChannel();
        vm.roll(GENESIS + AureumTime.BLOCKS_PER_ERA + 1);
        chEra1.accrue();
        uint256 late = chEra1.pendingAccrual();

        assertEq(late, correct, "F-18: accrual must be invariant to the call-block era");
    }

    /// @notice Cross-seam value: the channel's late (Era 1) bootstrap tranche must equal the distributor's
    ///         Era-0 subtraction (H-D26 conservation — the split must not under-mint Bodensee). Pre-fix the
    ///         late tranche is half the Era-0 tranche → RED; post-fix equal → GREEN.
    function test_F18_lateAccrual_matchesDistributorEra0Subtraction() public {
        BodenseeBootstrapChannel ch = _deployChannel();
        vm.roll(GENESIS + AureumTime.BLOCKS_PER_ERA + 1);
        ch.accrue();
        assertEq(ch.pendingAccrual(), _era0BootstrapTranche(), "F-18: channel tranche must equal the distributor Era-0 subtraction");
    }

    /// @notice Robustness across any late call era: an Era-5 accrual of the bootstrap window still prices
    ///         at GENESIS_RATE (the integrand blocks are Era 0). Pre-fix the tranche is 1/32 → RED; post-fix
    ///         equal to the Era-0 tranche → GREEN.
    function test_F18_deepEraAccrual_stillGenesisRate() public {
        BodenseeBootstrapChannel ch = _deployChannel();
        vm.roll(GENESIS + 5 * AureumTime.BLOCKS_PER_ERA + 1);
        ch.accrue();
        assertEq(ch.pendingAccrual(), _era0BootstrapTranche(), "F-18: bootstrap tranche keyed to Era-0 integrand rate for any call era");
    }
}
