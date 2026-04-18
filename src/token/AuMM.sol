// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAuMM} from "src/token/IAuMM.sol";
import {AureumTime} from "src/lib/AureumTime.sol";

/**
 * @title AuMM — Aureum Market Maker
 * @notice 21,000,000-cap ERC-20 with Bitcoin-style geometric halving.
 *         One-shot minter authorisation: constructor sets a minter admin,
 *         who calls setMinter() exactly once to hand off to the Stage H
 *         emission distributor. After that call, no entity has setter authority.
 * @dev Immutable schedule — blockEmissionRate is pure-view, computable without state.
 *      Does NOT extend ERC20Burnable — cap is a ceiling, not an inflation limit post-burn.
 */
contract AuMM is ERC20, IAuMM {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice The hard supply cap: 21,000,000 AuMM. Total supply can never exceed this.
    uint256 public constant override MAX_SUPPLY = 21_000_000e18;

    /// @notice The per-block emission rate during Era 0, before any halving.
    ///         One AuMM per block.
    uint256 public constant override GENESIS_RATE = 1e18;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice The block number at which the AuMM emission schedule begins.
    ///         Era 0 starts at this block. Set once at construction; never changes.
    uint256 public immutable override GENESIS_BLOCK;

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    /// @notice The address authorised to call mint(). Zero until setMinter() has
    ///         been called exactly once; then set permanently.
    address public override minter;

    /// @dev One-shot setter principal. Set in the constructor, zeroed in setMinter().
    ///      Part of the two-flag lock (minter != 0 AND _minterAdmin == 0), per C-D11.
    address private _minterAdmin;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Reverts setMinter() when msg.sender is not the constructor-set minter admin.
    error NotMinterAdmin();

    /// @notice Reverts mint() when msg.sender is not the configured minter.
    error NotMinter();

    /// @notice Reverts setMinter() when the minter has already been set.
    error MinterAlreadySet();

    /// @notice Reverts the constructor and setMinter() when a zero address is supplied.
    error ZeroAddress();

    /// @notice Reverts mint() when totalSupply() + amount would exceed MAX_SUPPLY.
    error SupplyCapExceeded();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @notice Deploy AuMM with a fixed genesis block and a one-shot minter admin.
    /// @dev Does not mint any tokens. No pre-mine, no treasury allocation. The
    ///      genesisBlock_ argument is not validated against block.number — the
    ///      deployment script is responsible for sanity (per C-D12).
    /// @param genesisBlock_ The block number at which Era 0 begins.
    /// @param minterAdmin_  The address authorised to call setMinter() exactly once.
    ///                      Must be non-zero; reverts with ZeroAddress otherwise,
    ///                      preventing a permanent brick at construction.
    constructor(uint256 genesisBlock_, address minterAdmin_)
        ERC20("Aureum Market Maker", "AuMM")
    {
        if (minterAdmin_ == address(0)) revert ZeroAddress();
        GENESIS_BLOCK = genesisBlock_;
        _minterAdmin = minterAdmin_;
    }

    // -------------------------------------------------------------------------
    // State-changing
    // -------------------------------------------------------------------------

    /// @inheritdoc IAuMM
    /// @dev Defence-in-depth via the two-flag lock (minter != 0 AND _minterAdmin == 0),
    ///      per C-D11: either flag alone prevents a second call. Both are set atomically
    ///      on success, making the "already set" condition trivially greppable.
    function setMinter(address newMinter) external override {
        if (msg.sender != _minterAdmin) revert NotMinterAdmin();
        if (minter != address(0))       revert MinterAlreadySet();
        if (newMinter == address(0))    revert ZeroAddress();

        minter = newMinter;
        _minterAdmin = address(0);
        emit MinterSet(newMinter);
    }

    /// @inheritdoc IAuMM
    /// @dev Cap check lives in mint(), not in an _update override (per C-D7). Keeps
    ///      the cap a mint-time ceiling and avoids accidentally blocking transfers
    ///      in any future extension.
    function mint(address to, uint256 amount) external override {
        if (msg.sender != minter)                revert NotMinter();
        if (totalSupply() + amount > MAX_SUPPLY) revert SupplyCapExceeded();
        _mint(to, amount);
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /// @inheritdoc IAuMM
    /// @dev Pure function of blockNumber and the immutable genesis block; no state
    ///      dependency. Returns 0 for blocks before GENESIS_BLOCK. The era >= 256
    ///      guard is defensive — integer right-shift produces zero naturally once
    ///      the era index exceeds log2(GENESIS_RATE), which is far earlier than 256.
    function blockEmissionRate(uint256 blockNumber) external view override returns (uint256) {
        if (blockNumber < GENESIS_BLOCK) return 0;
        uint256 era = (blockNumber - GENESIS_BLOCK) / AureumTime.BLOCKS_PER_ERA;
        if (era >= 256) return 0;
        return GENESIS_RATE >> era;
    }
}
