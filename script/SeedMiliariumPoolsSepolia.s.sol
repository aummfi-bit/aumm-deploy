// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { Router } from "@balancer-labs/v3-vault/contracts/Router.sol";

import { MiliariumSeedAllocations } from "./config/MiliariumSeedAllocations.sol";

/// @notice Minimal view of the testnet stubs' permissionless seeding mint. Declared locally rather
///         than imported because `StubERC20` and `StubERC4626` are distinct contract types that
///         share this exact signature, so one interface serves both without a per-type cast.
interface IStubMintable {
    function mint(address to, uint256 amount) external;
}

/// @notice Minimal view of the ERC-4626 stub's real deposit path (PB-D46 (iii)).
interface IStubVault {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
}

/**
 * @title SeedMiliariumPoolsSepolia
 * @notice Rung g of PB3.8 — mints, approves and initializes the 26 seeded Miliarium pools against
 *         the PB-D41 (vi) $1,000,000 accounting-TVL table. One idempotent script per PB-D46 (vi).
 *
 * @dev SEPOLIA ONLY. `run()` reverts `WrongChain` unless `block.chainid` is 11155111, before any env
 *      read or external call, reusing the PB-D45 (ii) guard unchanged.
 *
 * @dev Initialization routes through the Aureum Router, NOT through `vault.unlock`. Every existing
 *      initialization in this repo passes a callback on the calling contract itself, which works in
 *      a fork test where the harness is deployed code and cannot work under `forge script
 *      --broadcast`, where `run()` is a simulation emitting EOA transactions and this contract is
 *      never deployed (PB-D46 (i)). `Router.initialize` unlocks internally with `sender` as
 *      `msg.sender`, so it broadcasts as an ordinary call.
 *
 * @dev The Router pulls through Permit2, so each token carries a two-step allowance: an ERC-20
 *      approval to canonical Permit2, then a Permit2 allowance to the Router. Both are guarded by
 *      their own reads and skipped when already sufficient.
 *
 * @dev ERC-4626 legs are discriminated by a LIVE `asset()` probe, never by the committed token map.
 *      svZCHF is a genuine share that self-maps by the PB-D42 (iii) exception, so a
 *      token-differs-from-underlying test would misclassify the numeraire (PB-D45 (iii)).
 *
 * @dev A share leg funds by minting its underlying and depositing 1:1, never by the bare share mint.
 *      A directly minted share is unbacked: the stub's `totalAssets` reads its own underlying
 *      balance and its `withdraw` performs a real transfer, so an unwrap reverts — invisible to
 *      valuation, since the stub's `previewRedeem` is `pure`, and visible to a user (PB-D46 (iii)).
 *
 * @dev Amounts are `allocation * 10**decimals * weight / 1e18`, multiplications before the division.
 *      Token order and weights come from the Vault's registered pool data and the pool's own
 *      `getNormalizedWeights`, never from a config library, per the PB-D26 lockstep lesson.
 *
 * @dev Idempotent throughout: a sufficient balance skips the mint, a sufficient allowance skips
 *      either approval, and `isPoolInitialized` skips a pool already seeded. A run interrupted by
 *      exhausted funds is resumed by topping up and re-running; it re-sends only what is missing and
 *      composes with forge's own `--resume`.
 *
 * @dev Broadcaster is the DEPLOYER, not the governance multisig — unlike rung f. Initialization is
 *      permissionless and its caller becomes the pool's first BPT holder (PB-D46 (vi)).
 *
 * @dev Env vars required (no defaults — a real broadcast must never silently fall back to zero):
 *
 *        AUREUM_VAULT        address — the Aureum Vault
 *        AUREUM_ROUTER       address — the PB3.3 Aureum Router; NEW KEY, add to .env.sepolia
 *        PERMIT2_ADDRESS     address — canonical cross-chain Permit2
 *        DEPLOYER_ADDRESS    address — broadcaster and initial LP; NEW KEY, add to .env.sepolia
 *        MILIARIUM_POOL_NN   address — one per seeded slot, NN zero-padded; 04 and 07 unused
 */
contract SeedMiliariumPoolsSepolia is Script {
    /// @notice Sepolia chain id; `run()` refuses to execute anywhere else.
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;

    /// @notice Thrown when executed against any chain other than Sepolia.
    error WrongChain(uint256 actual, uint256 expected);

    /// @notice Thrown when the committed allocation rows do not sum to the declared universe.
    error AllocationSumMismatch(uint256 summed, uint256 expected);

    /// @notice Thrown when a pool's registered token count disagrees with its weight count.
    error WeightLengthMismatch(uint256 slot, uint256 tokenCount, uint256 weightCount);

    /// @notice `forge script` entry — asserts the table, then seeds every unseeded pool.
    function run() external {
        if (block.chainid != SEPOLIA_CHAIN_ID) revert WrongChain(block.chainid, SEPOLIA_CHAIN_ID);

        IVault vault = IVault(vm.envAddress("AUREUM_VAULT"));
        Router router = Router(payable(vm.envAddress("AUREUM_ROUTER")));
        IPermit2 permit2 = IPermit2(vm.envAddress("PERMIT2_ADDRESS"));
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");

        (uint256[] memory slot, uint256[] memory usd) = MiliariumSeedAllocations.allocations();

        uint256 summed = 0;
        for (uint256 i = 0; i < slot.length; i++) {
            summed += usd[i];
        }
        if (summed != MiliariumSeedAllocations.TOTAL_USD) {
            revert AllocationSumMismatch(summed, MiliariumSeedAllocations.TOTAL_USD);
        }

        vm.startBroadcast(deployer);
        for (uint256 i = 0; i < slot.length; i++) {
            _seedPool(vault, router, permit2, deployer, slot[i], usd[i]);
        }
        vm.stopBroadcast();
    }

    /// @dev Seeds one slot, or returns early when that pool is already initialized.
    function _seedPool(
        IVault vault,
        Router router,
        IPermit2 permit2,
        address deployer,
        uint256 slotNumber,
        uint256 allocationUsd
    ) internal {
        address pool = vm.envAddress(string.concat("MILIARIUM_POOL_", _twoDigit(slotNumber)));

        if (vault.isPoolInitialized(pool)) {
            console2.log("skip, already initialized -- slot", slotNumber);
            return;
        }

        IERC20[] memory tokens = vault.getPoolTokens(pool);
        uint256[] memory weights = IWeightedPool(pool).getNormalizedWeights();
        if (tokens.length != weights.length) {
            revert WeightLengthMismatch(slotNumber, tokens.length, weights.length);
        }

        uint256[] memory amounts = new uint256[](tokens.length);
        for (uint256 j = 0; j < tokens.length; j++) {
            address token = address(tokens[j]);
            uint256 dec = IERC20Metadata(token).decimals();
            amounts[j] = (allocationUsd * (10 ** dec) * weights[j]) / 1e18;
            _fund(token, deployer, amounts[j]);
            _approve(permit2, address(router), token, amounts[j], deployer);
        }

        router.initialize(pool, tokens, amounts, 0, false, "");
        console2.log("seeded slot", slotNumber);
    }

    /// @dev Brings `to`'s balance of `token` up to `amount`. A share stub funds by minting its
    ///      underlying and depositing 1:1 so the share is backed; a plain stub mints directly.
    function _fund(address token, address to, uint256 amount) internal {
        uint256 held = IERC20(token).balanceOf(to);
        if (held >= amount) return;
        uint256 need = amount - held;

        try IERC4626(token).asset() returns (address underlying) {
            IStubMintable(underlying).mint(to, need);
            IERC20(underlying).approve(token, need);
            IStubVault(token).deposit(need, to);
        } catch {
            IStubMintable(token).mint(to, need);
        }
    }

    /// @dev Ensures the two-step Permit2 allowance chain covers `amount`; skips either leg already
    ///      sufficient. Both are set to their type maxima so a resumed run needs no re-approval.
    function _approve(IPermit2 permit2, address spender, address token, uint256 amount, address owner)
        internal
    {
        if (IERC20(token).allowance(owner, address(permit2)) < amount) {
            IERC20(token).approve(address(permit2), type(uint256).max);
        }
        (uint160 allowed, , ) = permit2.allowance(owner, token, spender);
        if (allowed < amount) {
            permit2.approve(token, spender, type(uint160).max, type(uint48).max);
        }
    }

    /// @dev Zero-padded two-digit slot rendering for the `MILIARIUM_POOL_NN` key names. Built from
    ///      digits rather than a cheatcode so the helper stays `pure`.
    function _twoDigit(uint256 n) internal pure returns (string memory) {
        bytes memory b = new bytes(2);
        b[0] = bytes1(uint8(48 + (n / 10)));
        b[1] = bytes1(uint8(48 + (n % 10)));
        return string(b);
    }
}
