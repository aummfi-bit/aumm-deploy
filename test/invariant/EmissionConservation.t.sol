// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AuMM} from "src/token/AuMM.sol";
import {IAuMM} from "src/token/IAuMM.sol";
import {AuMMMinterRouter} from "src/token/AuMMMinterRouter.sol";
import {EmissionDistributor} from "src/emission/EmissionDistributor.sol";
import {BodenseeBootstrapChannel} from "src/emission/BodenseeBootstrapChannel.sol";
import {IGaugeRegistry} from "src/ccb/IGaugeRegistry.sol";
import {IEMASampler} from "src/ccb/IEMASampler.sol";
import {ICCBMultiplier} from "src/ccb/ICCBMultiplier.sol";
import {IMiliariumRegistry} from "src/ccb/IMiliariumRegistry.sol";
import {IEfficiencyOracle} from "src/gauge/IEfficiencyOracle.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AureumTime} from "src/lib/AureumTime.sol";
import {ReferenceEmission} from "./ReferenceEmission.sol";
import {
    MockGaugeRegistry,
    MockEMASampler,
    MockCCBMultiplier,
    MockEfficiencyOracle,
    MockMiliariumRegistry
} from "../unit/EmissionDistributor.t.sol";
import {MockVault} from "../unit/BodenseeBootstrapChannel.t.sol";

/// @notice Fuzz-action driver for the INV-2 harness (P-D20). Bound as the distributor's per-pool AuMT recorder
///         (so `deposit` / `withdraw` pass `onlyAuMTContract`) and pranks GOV for `channelDistribute`. All amounts
///         and block advances are bounded so the fuzzer makes progress; `fail_on_revert = false` absorbs the
///         no-op reverts (empty-accrual distribute, over-withdraw clamp).
contract EmissionConservationHandler is Test {
    EmissionDistributor internal immutable distributor;
    BodenseeBootstrapChannel internal immutable channel;
    address internal immutable gov;
    address[] internal pools;
    address[] internal users;

    constructor(
        EmissionDistributor distributor_,
        BodenseeBootstrapChannel channel_,
        address gov_,
        address[] memory pools_,
        address[] memory users_
    ) {
        distributor = distributor_;
        channel = channel_;
        gov = gov_;
        for (uint256 i = 0; i < pools_.length; i++) {
            pools.push(pools_[i]);
        }
        for (uint256 i = 0; i < users_.length; i++) {
            users.push(users_[i]);
        }
    }

    function _pool(uint256 seed) internal view returns (address) {
        return pools[seed % pools.length];
    }

    function _user(uint256 seed) internal view returns (address) {
        return users[seed % users.length];
    }

    function advanceBlocks(uint256 seed) external {
        vm.roll(block.number + bound(seed, 1, AureumTime.BLOCKS_PER_MONTH));
    }

    function recordScore(uint256 poolSeed) external {
        distributor.recordScore(_pool(poolSeed));
    }

    function deposit(uint256 poolSeed, uint256 userSeed, uint256 amtSeed) external {
        distributor.recordDeposit(_pool(poolSeed), _user(userSeed), bound(amtSeed, 1, 1_000_000e18));
    }

    function withdraw(uint256 poolSeed, uint256 userSeed, uint256 amtSeed) external {
        distributor.recordWithdrawal(_pool(poolSeed), _user(userSeed), bound(amtSeed, 1, 1_000_000e18));
    }

    function claim(uint256 poolSeed, uint256 userSeed) external {
        address u = _user(userSeed);
        vm.prank(u);
        distributor.claim(_pool(poolSeed), u);
    }

    function channelAccrue() external {
        channel.accrue();
    }

    function channelDistribute() external {
        vm.prank(gov);
        channel.distribute();
    }
}

/// @notice INV-1 / INV-6 (≤ 21M cap) + INV-2 (≤ the non-circular ReferenceEmission schedule) across the full
///         integrated emission stack — both `mintFor` sites (distributor `claim` LP tranche + channel `distribute`
///         bootstrap tranche). Governance-weight monotonicity is deliberately NOT harnessed (P-D7, F-02
///         sub-additive); fee-split (INV-3) is covered by AureumProtocolFeeController.t.sol; solvency (INV-4) → P10.
contract EmissionConservationInvariant is Test {
    uint256 internal constant GENESIS = 1_000_000;
    uint256 internal constant CAP = 21_000_000e18;
    address internal constant GOV = address(0xC0FE);
    address internal constant BODENSEE = address(0xB0DE);
    address internal constant POOL_MIL = address(0xD1);
    address internal constant POOL_STD = address(0xD2);
    address internal constant USER_1 = address(0xE1);
    address internal constant USER_2 = address(0xE2);

    AuMM internal aumm;
    EmissionDistributor internal distributor;
    BodenseeBootstrapChannel internal channel;
    AuMMMinterRouter internal router;
    MockVault internal vault;
    EmissionConservationHandler internal handler;

    function setUp() public {
        aumm = new AuMM(GENESIS, address(this));
        MockGaugeRegistry gauges = new MockGaugeRegistry();
        MockEMASampler ema = new MockEMASampler();
        MockCCBMultiplier mult = new MockCCBMultiplier();
        MockEfficiencyOracle effOracle = new MockEfficiencyOracle();
        MockMiliariumRegistry miliReg = new MockMiliariumRegistry();
        distributor = new EmissionDistributor(
            IAuMM(address(aumm)),
            IGaugeRegistry(address(gauges)),
            IEMASampler(address(ema)),
            ICCBMultiplier(address(mult)),
            IEfficiencyOracle(address(effOracle)),
            IMiliariumRegistry(address(miliReg)),
            GENESIS,
            GOV
        );

        vault = new MockVault();
        IERC20[] memory roster = new IERC20[](3);
        roster[0] = IERC20(address(0xA11CE));
        roster[1] = IERC20(address(0xB0B));
        roster[2] = IERC20(address(aumm));
        vault.setTokens(roster);
        uint256[] memory bals = new uint256[](3);
        bals[0] = 1_000e18;
        bals[1] = 1_000e18;
        bals[2] = 1_000e18;
        vault.setBalancesRaw(bals);
        vault.enableBumpReserveOnDonation();
        channel = new BodenseeBootstrapChannel(IVault(address(vault)), BODENSEE, IAuMM(address(aumm)), GENESIS, GOV);
        vault.setHelper(address(channel));

        router = new AuMMMinterRouter(IAuMM(address(aumm)), address(channel), address(distributor));
        aumm.setMinter(address(router));
        vm.prank(GOV);
        distributor.setMintRouter(address(router));
        vm.prank(GOV);
        channel.setMintRouter(address(router));
        effOracle.setEmissionsRecorder(address(distributor));

        address[] memory pools = new address[](2);
        pools[0] = POOL_MIL;
        pools[1] = POOL_STD;
        for (uint256 i = 0; i < pools.length; i++) {
            vm.mockCall(pools[i], abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(1e30)));
            gauges.setApproved(pools[i], true);
            ema.setTVLEMA(pools[i], 100e18);
            mult.setMultiplier(pools[i], 1e18);
        }
        miliReg.setMiliarium(POOL_MIL, true);

        address[] memory users = new address[](2);
        users[0] = USER_1;
        users[1] = USER_2;

        handler = new EmissionConservationHandler(distributor, channel, GOV, pools, users);
        for (uint256 i = 0; i < pools.length; i++) {
            vm.prank(GOV);
            distributor.setAuMTContractForPool(pools[i], address(handler));
        }

        vm.roll(GENESIS);
        targetContract(address(handler));
    }

    /// @notice INV-1 / INV-6 — total AuMM minted never exceeds the 21M hard cap, across both mint paths.
    function invariant_totalSupplyNeverExceedsCap() public view {
        assertLe(aumm.totalSupply(), CAP);
    }

    /// @notice INV-2 — total AuMM minted never outpaces the independently re-derived emission schedule
    ///         (non-circular: ReferenceEmission, never AuMM.blockEmissionRate), within the documented bounded
    ///         two-cursor bootstrap-partition flooring dust (P-D21). The `+ 2 * (month10EndBlock - GENESIS)`
    ///         tolerance is a frozen upper envelope (~4.38M wei ≈ 4.4e-12 AuMM, established Months 0—10, cap-safe;
    ///         INV-1/6 stays strict). A materially larger over-mint still trips this invariant.
    function invariant_totalSupplyNeverExceedsSchedule() public view {
        assertLe(
            aumm.totalSupply(),
            ReferenceEmission.cumulativeAt(GENESIS, block.number)
                + 2 * (AureumTime.month10EndBlock(GENESIS) - GENESIS)
        );
    }

    /// @notice Liveness sanity — the harness CAN mint on BOTH paths, so the ≤-invariants are not vacuously true.
    function test_harness_actuallyMints_bothPaths() public {
        vm.roll(GENESIS + 1000);
        channel.accrue();
        vm.prank(GOV);
        channel.distribute();
        uint256 afterBootstrap = aumm.totalSupply();
        assertGt(afterBootstrap, 0, "bootstrap path minted nothing");

        vm.roll(AureumTime.year1EndBlock(GENESIS));
        distributor.recordScore(POOL_STD);
        vm.prank(address(handler));
        distributor.recordDeposit(POOL_STD, USER_1, 100e18);
        vm.roll(AureumTime.year1EndBlock(GENESIS) + 100);
        vm.prank(USER_1);
        distributor.claim(POOL_STD, USER_1);
        assertGt(aumm.totalSupply(), afterBootstrap, "LP claim path minted nothing");

        assertLe(aumm.totalSupply(), CAP);
        assertLe(aumm.totalSupply(), ReferenceEmission.cumulativeAt(GENESIS, block.number));
    }
}
