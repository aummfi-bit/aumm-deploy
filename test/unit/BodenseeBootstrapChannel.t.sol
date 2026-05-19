// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {AddLiquidityKind, AddLiquidityParams, TokenInfo} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {BodenseeBootstrapChannel} from "src/emission/BodenseeBootstrapChannel.sol";
import {IAuMM} from "src/token/IAuMM.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {IBodenseeBootstrapChannel} from "src/emission/IBodenseeBootstrapChannel.sol";

/// @notice Test-only ERC20 with public mint for setUp seeding.
contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Test-only IAuMM stub — settable per-block rate via `setRate`, mint gated on `msg.sender == minter`, schedule-getter stubs return canonical Stage C constants.
contract MockAuMM is ERC20, IAuMM {
    address private _minter;
    uint256 public rate;

    constructor() ERC20("AuMM", "AUMM") {
        rate = 1e18;
    }

    function setRate(uint256 rate_) external {
        rate = rate_;
    }

    function GENESIS_BLOCK() external pure override returns (uint256) {
        return 1_000_000;
    }

    function MAX_SUPPLY() external pure override returns (uint256) {
        return 21_000_000 * 1e18;
    }

    function GENESIS_RATE() external pure override returns (uint256) {
        return 1e18;
    }

    function blockEmissionRate(uint256) external view override returns (uint256) {
        return rate;
    }

    function minter() external view override returns (address) {
        return _minter;
    }

    function mint(address to, uint256 amount) external override {
        require(msg.sender == _minter, "MockAuMM: not minter");
        _mint(to, amount);
    }

    function setMinter(address newMinter) external override {
        _minter = newMinter;
        emit MinterSet(newMinter);
    }
}

/// @notice Test-only Balancer V3 Vault stub — full `_distributeCallback` callback path with switches for reentrancy, corrupt-callback amount, BPT-mint-on-DONATION, and reserve-bump-on-DONATION.
contract MockVault {
    IERC20[] public mockTokens;
    uint256[] public mockBalancesRaw;
    address public helperRef;
    bool public reentrancyAttack;
    bool public corruptCallbackAmount;
    bool public mintBptOnDonation;
    bool public bumpReserveOnDonation;

    function setTokens(IERC20[] calldata tokens_) external {
        delete mockTokens;
        uint256 len = tokens_.length;
        for (uint256 i = 0; i < len; ++i) {
            mockTokens.push(tokens_[i]);
        }
    }

    function setBalancesRaw(uint256[] calldata balancesRaw_) external {
        delete mockBalancesRaw;
        uint256 len = balancesRaw_.length;
        for (uint256 i = 0; i < len; ++i) {
            mockBalancesRaw.push(balancesRaw_[i]);
        }
    }

    function setHelper(address helper_) external {
        helperRef = helper_;
    }

    function enableReentrancyAttack() external {
        reentrancyAttack = true;
    }

    function enableCorruptCallback() external {
        corruptCallbackAmount = true;
    }

    function enableBptMintOnDonation() external {
        mintBptOnDonation = true;
    }

    function enableBumpReserveOnDonation() external {
        bumpReserveOnDonation = true;
    }

    function getPoolTokens(address) external view returns (IERC20[] memory) {
        IERC20[] memory tokens = new IERC20[](mockTokens.length);
        uint256 len = mockTokens.length;
        for (uint256 i = 0; i < len; ++i) {
            tokens[i] = mockTokens[i];
        }
        return tokens;
    }

    function unlock(bytes calldata data) external returns (bytes memory) {
        bytes memory callData = data;
        if (corruptCallbackAmount) {
            (uint256 amount) = abi.decode(data[4:], (uint256));
            callData = abi.encodeWithSelector(BodenseeBootstrapChannel._distributeCallback.selector, amount + 1);
        }
        (bool success, bytes memory ret) = helperRef.call(callData);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(ret, 32), mload(ret))
            }
        }
        return ret;
    }

    function settle(IERC20, uint256 amount_) external pure returns (uint256) {
        return amount_;
    }

    function getPoolTokenInfo(address)
        external
        returns (
            IERC20[] memory tokens,
            TokenInfo[] memory tokenInfo,
            uint256[] memory balancesRaw,
            uint256[] memory lastBalancesLiveScaled18
        )
    {
        if (reentrancyAttack) {
            BodenseeBootstrapChannel(helperRef).distribute();
        }
        uint256 len = mockTokens.length;
        tokens = new IERC20[](len);
        for (uint256 i = 0; i < len; ++i) {
            tokens[i] = mockTokens[i];
        }
        tokenInfo = new TokenInfo[](len);
        balancesRaw = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
            balancesRaw[i] = mockBalancesRaw[i];
        }
        lastBalancesLiveScaled18 = new uint256[](len);
    }

    function addLiquidity(AddLiquidityParams calldata params)
        external
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData)
    {
        require(params.kind == AddLiquidityKind.DONATION, "mock addLiquidity kind");
        uint256 len = mockTokens.length;
        amountsIn = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
            amountsIn[i] = params.maxAmountsIn[i];
        }
        bptAmountOut = mintBptOnDonation ? 1e18 : 0;
        if (bumpReserveOnDonation) {
            for (uint256 i = 0; i < params.maxAmountsIn.length; ++i) {
                mockBalancesRaw[i] += params.maxAmountsIn[i];
            }
        }
        returnData = "";
    }
}

/// @notice Unit tests for BodenseeBootstrapChannel (concrete H-D11—H-D14 implementation landed at H3.1—H3.6b) — scaffold only at H3.7a; test functions land at H3.7b onward.
contract BodenseeBootstrapChannelTest is Test {
    uint256 internal constant GENESIS_BLOCK_ = 1_000_000;
    address internal constant BODENSEE_POOL_ = address(0xB0DE);
    address internal constant GOV = address(0xC0FE);

    MockVault internal vault;
    MockERC20 internal svZchf;
    MockERC20 internal sUsds;
    MockAuMM internal aumm;
    BodenseeBootstrapChannel internal channel;

    function setUp() public virtual {
        vault = new MockVault();
        svZchf = new MockERC20("svZCHF", "svZCHF");
        sUsds = new MockERC20("sUSDS", "sUSDS");
        aumm = new MockAuMM();

        IERC20[] memory three = new IERC20[](3);
        three[0] = IERC20(address(svZchf));
        three[1] = IERC20(address(sUsds));
        three[2] = IERC20(address(aumm));
        vault.setTokens(three);

        uint256[] memory bals = new uint256[](3);
        bals[0] = 1_000e18;
        bals[1] = 1_000e18;
        bals[2] = 1_000e18;
        vault.setBalancesRaw(bals);

        channel = new BodenseeBootstrapChannel(
            IVault(address(vault)),
            BODENSEE_POOL_,
            IAuMM(address(aumm)),
            GENESIS_BLOCK_,
            GOV
        );
        vault.setHelper(address(channel));
        aumm.setMinter(address(channel));
        vm.roll(GENESIS_BLOCK_);
    }

    function _addr(uint256 seed) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(seed)))));
    }

    /// @notice F10 discipline — call sites that loop should thread an explicit counter via `_rollTo(currentBlock += BLOCKS_PER_DAY)` rather than `_rollTo(block.number + …)` to avoid solc optimizer hoisting `block.number` out of the loop.
    function _rollTo(uint256 blockNumber) internal {
        vm.roll(blockNumber);
    }

    function _month6End() internal pure returns (uint256) {
        return AureumTime.month6EndBlock(GENESIS_BLOCK_);
    }

    function _month10End() internal pure returns (uint256) {
        return AureumTime.month10EndBlock(GENESIS_BLOCK_);
    }

    /* ---------- Constructor (H-D14 + H-D11) ---------- */

    function test_Constructor_RevertWhen_VaultZero() public {
        vm.expectRevert(BodenseeBootstrapChannel.ZeroAddress.selector);
        new BodenseeBootstrapChannel(IVault(address(0)), BODENSEE_POOL_, IAuMM(address(aumm)), GENESIS_BLOCK_, GOV);
    }

    function test_Constructor_RevertWhen_BodenseeZero() public {
        vm.expectRevert(BodenseeBootstrapChannel.ZeroAddress.selector);
        new BodenseeBootstrapChannel(IVault(address(vault)), address(0), IAuMM(address(aumm)), GENESIS_BLOCK_, GOV);
    }

    function test_Constructor_RevertWhen_AummZero() public {
        vm.expectRevert(BodenseeBootstrapChannel.ZeroAddress.selector);
        new BodenseeBootstrapChannel(IVault(address(vault)), BODENSEE_POOL_, IAuMM(address(0)), GENESIS_BLOCK_, GOV);
    }

    function test_Constructor_RevertWhen_GovernanceZero() public {
        vm.expectRevert(BodenseeBootstrapChannel.ZeroAddress.selector);
        new BodenseeBootstrapChannel(IVault(address(vault)), BODENSEE_POOL_, IAuMM(address(aumm)), GENESIS_BLOCK_, address(0));
    }

    function test_Constructor_RevertWhen_AummNotInBodensee() public {
        MockVault badVault = new MockVault();
        MockERC20 other = new MockERC20("Other", "OTHER");
        IERC20[] memory roster = new IERC20[](3);
        roster[0] = IERC20(address(svZchf));
        roster[1] = IERC20(address(sUsds));
        roster[2] = IERC20(address(other));
        badVault.setTokens(roster);
        vm.expectRevert(BodenseeBootstrapChannel.IndexLookupFailed.selector);
        new BodenseeBootstrapChannel(IVault(address(badVault)), BODENSEE_POOL_, IAuMM(address(aumm)), GENESIS_BLOCK_, GOV);
    }

    function test_Constructor_WiresImmutables() public view {
        assertEq(channel.BODENSEE_POOL(), BODENSEE_POOL_, "BODENSEE_POOL");
        assertEq(address(channel.AuMM()), address(aumm), "AuMM");
        assertEq(channel.GENESIS_BLOCK(), GENESIS_BLOCK_, "GENESIS_BLOCK");
    }

    function test_Constructor_InitsGovernance() public view {
        assertEq(channel.governance(), GOV, "governance");
    }

    function test_Constructor_InitsLastAccrualBlock() public view {
        assertEq(channel.lastAccrualBlock(), GENESIS_BLOCK_, "lastAccrualBlock");
    }

    /* ---------- setGovernanceContract (H-D14) ---------- */

    function test_SetGovernanceContract_HappyPath_EmitsAndUpdates() public {
        address newGov = _addr(1);
        vm.expectEmit(true, true, false, false);
        emit BodenseeBootstrapChannel.GovernanceTransferred(GOV, newGov);
        vm.prank(GOV);
        channel.setGovernanceContract(newGov);
        assertEq(channel.governance(), newGov, "governance");
    }

    function test_SetGovernanceContract_RevertWhen_NewGovernanceZero() public {
        vm.expectRevert(BodenseeBootstrapChannel.ZeroAddress.selector);
        vm.prank(GOV);
        channel.setGovernanceContract(address(0));
    }

    function test_SetGovernanceContract_RevertWhen_CallerNotGovernance() public {
        address bad = _addr(99);
        vm.expectRevert(abi.encodeWithSelector(BodenseeBootstrapChannel.NotGovernance.selector, bad));
        vm.prank(bad);
        channel.setGovernanceContract(_addr(1));
    }

    function test_SetGovernanceContract_PostHandoffAccessShifts() public {
        address newGov = _addr(1);
        vm.prank(GOV);
        channel.setGovernanceContract(newGov);
        vm.prank(GOV);
        vm.expectRevert(abi.encodeWithSelector(BodenseeBootstrapChannel.NotGovernance.selector, GOV));
        channel.setGovernanceContract(_addr(2));
        address yetAnother = _addr(3);
        vm.prank(newGov);
        channel.setGovernanceContract(yetAnother);
        assertEq(channel.governance(), yetAnother, "post-shift");
    }

    /* ---------- accrue (H-D11) ---------- */

    /// @notice Test-side mirror of BodenseeBootstrapChannel._apSum for expected-value assertions.
    function _expectedApSum(
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

    function test_Accrue_EmptyInterval_NoOp() public {
        channel.accrue();
        assertEq(channel.pendingAccrual(), 0, "pendingAccrual");
        assertEq(channel.lastAccrualBlock(), GENESIS_BLOCK_, "lastAccrualBlock");
    }

    function test_Accrue_BootstrapAOnly() public {
        uint256 targetBlock = GENESIS_BLOCK_ + 1_000;
        _rollTo(targetBlock);
        uint256 expected = _expectedApSum(GENESIS_BLOCK_ + 1, targetBlock, GENESIS_BLOCK_, _month6End(), 8e17, 3e17, 1e18);
        channel.accrue();
        assertEq(channel.pendingAccrual(), expected, "pendingAccrual");
        assertEq(channel.lastAccrualBlock(), targetBlock, "lastAccrualBlock");
    }

    function test_Accrue_BootstrapBOnly() public {
        _rollTo(_month6End());
        channel.accrue();
        uint256 aSum = channel.pendingAccrual();
        uint256 targetBlock = _month6End() + 1_000;
        _rollTo(targetBlock);
        uint256 expectedB = _expectedApSum(_month6End() + 1, targetBlock, _month6End(), _month10End(), 5e17, 5e17, 1e18);
        channel.accrue();
        assertEq(channel.pendingAccrual(), aSum + expectedB, "pendingAccrual");
        assertEq(channel.lastAccrualBlock(), targetBlock, "lastAccrualBlock");
    }

    function test_Accrue_BoundarySpanning() public {
        uint256 targetBlock = _month6End() + 1_000;
        _rollTo(targetBlock);
        uint256 aSum = _expectedApSum(GENESIS_BLOCK_ + 1, _month6End(), GENESIS_BLOCK_, _month6End(), 8e17, 3e17, 1e18);
        uint256 bSum = _expectedApSum(_month6End() + 1, targetBlock, _month6End(), _month10End(), 5e17, 5e17, 1e18);
        channel.accrue();
        assertEq(channel.pendingAccrual(), aSum + bSum, "pendingAccrual");
        assertEq(channel.lastAccrualBlock(), targetBlock, "lastAccrualBlock");
    }

    function test_Accrue_PostMonth10Clamp() public {
        _rollTo(_month10End() + 1_000);
        channel.accrue();
        assertEq(channel.lastAccrualBlock(), _month10End(), "lastAccrualBlock clamped");
    }

    function test_Accrue_SecondCallAfterClampNoOp() public {
        _rollTo(_month10End() + 1_000);
        channel.accrue();
        uint256 firstAccrual = channel.pendingAccrual();
        _rollTo(_month10End() + 5_000);
        channel.accrue();
        assertEq(channel.pendingAccrual(), firstAccrual, "pendingAccrual unchanged");
        assertEq(channel.lastAccrualBlock(), _month10End(), "lastAccrualBlock still clamped");
    }

    function test_Accrue_SequentialAccumulation_BootstrapA() public {
        uint256 t1 = GENESIS_BLOCK_ + 1_000;
        _rollTo(t1);
        channel.accrue();
        uint256 firstAccrual = channel.pendingAccrual();
        uint256 t2 = GENESIS_BLOCK_ + 2_000;
        _rollTo(t2);
        channel.accrue();
        uint256 expected2 = _expectedApSum(t1 + 1, t2, GENESIS_BLOCK_, _month6End(), 8e17, 3e17, 1e18);
        assertEq(channel.pendingAccrual(), firstAccrual + expected2, "pendingAccrual");
        assertEq(channel.lastAccrualBlock(), t2, "lastAccrualBlock");
    }

    function test_Accrue_PermissionlessAndEmits() public {
        uint256 targetBlock = GENESIS_BLOCK_ + 1_000;
        _rollTo(targetBlock);
        uint256 expected = _expectedApSum(GENESIS_BLOCK_ + 1, targetBlock, GENESIS_BLOCK_, _month6End(), 8e17, 3e17, 1e18);
        vm.expectEmit(false, false, false, true);
        emit IBodenseeBootstrapChannel.Accrued(GENESIS_BLOCK_ + 1, targetBlock, expected);
        vm.prank(_addr(42));
        channel.accrue();
    }

    /* ---------- distribute (H-D12 + H-D14) ---------- */

    function test_Distribute_RevertWhen_NoPendingAccrual() public {
        vm.expectRevert(BodenseeBootstrapChannel.NoPendingAccrual.selector);
        vm.prank(GOV);
        channel.distribute();
    }

    function test_Distribute_RevertWhen_CallerNotGovernance() public {
        _rollTo(GENESIS_BLOCK_ + 1_000);
        channel.accrue();
        address bad = _addr(99);
        vm.expectRevert(abi.encodeWithSelector(BodenseeBootstrapChannel.NotGovernance.selector, bad));
        vm.prank(bad);
        channel.distribute();
    }

    function test_Distribute_HappyPath_MutatesStateAndEmitsDistributed() public {
        _rollTo(GENESIS_BLOCK_ + 1_000);
        channel.accrue();
        uint256 expectedAmount = channel.pendingAccrual();
        vault.enableBumpReserveOnDonation();
        vm.expectEmit(true, false, false, true);
        emit IBodenseeBootstrapChannel.Distributed(GOV, expectedAmount);
        vm.prank(GOV);
        channel.distribute();
        assertEq(channel.pendingAccrual(), 0, "pendingAccrual cleared");
        assertEq(channel.totalDistributed(), expectedAmount, "totalDistributed");
    }

    function test_Distribute_RevertWhen_HelperBalanceNonZero() public {
        _rollTo(GENESIS_BLOCK_ + 1_000);
        channel.accrue();
        vault.enableBumpReserveOnDonation();
        uint256 residual = 50e18;
        deal(address(aumm), address(channel), residual);
        vm.expectRevert(abi.encodeWithSelector(BodenseeBootstrapChannel.HelperBalanceNonZero.selector, residual));
        vm.prank(GOV);
        channel.distribute();
    }

    function test_Distribute_RevertWhen_Reentrant() public {
        BodenseeBootstrapChannel ch2 = new BodenseeBootstrapChannel(
            IVault(address(vault)),
            BODENSEE_POOL_,
            IAuMM(address(aumm)),
            GENESIS_BLOCK_,
            address(vault)
        );
        vault.setHelper(address(ch2));
        aumm.setMinter(address(ch2));
        _rollTo(GENESIS_BLOCK_ + 1_000);
        ch2.accrue();
        vault.enableReentrancyAttack();
        vm.expectRevert(BodenseeBootstrapChannel.NoPendingAccrual.selector);
        vm.prank(address(vault));
        ch2.distribute();
    }
}
