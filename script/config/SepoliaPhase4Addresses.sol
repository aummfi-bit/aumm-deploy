// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

/**
 * @title SepoliaPhase4Addresses
 * @notice Live-Sepolia addresses of the sixteen contracts created by the PB3.8h9g phase-4 broadcast.
 *
 * @dev SEPOLIA ONLY, per PB-D44 (iv) and RB-010. Every address here holds code on Sepolia (chain 11155111)
 *      and none on mainnet, so a consumer that could run against either chain asserts `block.chainid`
 *      before reading, on the PB-D45 (iii) precedent that an on-chain identity check beats an env marker
 *      answered off-chain.
 *
 *      Derived from `docs/STAGE_P_BIS_SEPOLIA_DEPLOYMENT_RECORD.md` section 11, nonces 125 to 238: the
 *      committed record of the single slow-mode invocation that broadcast 114 transactions across blocks
 *      11403323 to 11403470. The checksummed forms are `cast to-check-sum-address` output over that
 *      section's own lowercase literals rather than hand-cased, so this file derives from the record by
 *      tool rather than by transcription, and its audit is a diff against that same derivation.
 *
 *      Named constants, unlike the sibling `SepoliaTokenUnderlyings.sol`, which deliberately refuses them.
 *      PB-D44 (ii) withholds names where the subject is a freshly created stub whose only identity is its
 *      own address, since any name would be invented at transcription time. That reasoning inverts here:
 *      section 11 records a contract name beside every address, so a reviewer checks the two against each
 *      other independently. This takes the `GaugeGenesisManifest.sol` shape rather than the anonymous one.
 *
 *      First PB3.7 rung, and the RB-014 discharge for this set. These addresses previously existed only in
 *      the deployment record and in a gitignored `.env.sepolia` that carries none of them but `TVL_ORACLE`.
 */
library SepoliaPhase4Addresses {
    /// @notice Count of contracts the phase-4 broadcast created.
    uint256 internal constant DEPLOY_COUNT = 16;

    /// @notice Nonce 125 — Miliarium slot registry; the `_directRatio` Leg 2 enumeration source.
    address internal constant MILIARIUM_REGISTRY = 0xfBE5e161955Fb75FA99010dCfC71bbBE6405A511;

    /// @notice Nonce 126 — the live TVLOracle, which per PB-D52 (ix) remains pre-PB-D50-fix.
    address internal constant TVL_ORACLE = 0xBf78A49b1AB86247198f6660Bf5a0491007E6A64;

    /// @notice Nonce 127 — EfficiencyOracle.
    address internal constant EFFICIENCY_ORACLE = 0x1e70661C3F1844c01bE204E9dF032B12D04110b3;

    /// @notice Nonce 128 — EMASampler.
    address internal constant EMA_SAMPLER = 0x51f8D9E771E5EC3A33555C15032110d034891B3A;

    /// @notice Nonce 129 — CCBMultiplier.
    address internal constant CCB_MULTIPLIER = 0xDBB357259BE8dfb17FCbF0503D9BAb01e976f735;

    /// @notice Nonce 131 — SwapAndDepositToBodensee.
    address internal constant SWAP_AND_DEPOSIT_TO_BODENSEE = 0x5F716BD785D2990C6d42750091b0F2914c557F25;

    /// @notice Nonce 132 — VaultClassRegistry.
    address internal constant VAULT_CLASS_REGISTRY = 0xF6D7A7E633a1bC8B8896B7849BBFa53001854af7;

    /// @notice Nonce 133 — GaugeEligibility.
    address internal constant GAUGE_ELIGIBILITY = 0x9b9304deb0230CAB7780A66b184897d30F26cd78;

    /// @notice Nonce 134 — GaugeRegistry.
    address internal constant GAUGE_REGISTRY = 0xD6eEe04CA4E27A3e2e395538F907b1dFf523D987;

    /// @notice Nonce 141 — BodenseeBootstrapChannel.
    address internal constant BODENSEE_BOOTSTRAP_CHANNEL = 0x2325A6238Ff80e5a4e8D8071Ff1E949DcbcFB7cB;

    /// @notice Nonce 142 — EmissionDistributor.
    address internal constant EMISSION_DISTRIBUTOR = 0x2933bC72f2EA002ece4A2270c7985B72cfD0A695;

    /// @notice Nonce 222 — IncendiaryRegistry.
    address internal constant INCENDIARY_REGISTRY = 0xe1304F04C7f9138f8932B71A18Be7a7447cC93C1;

    /// @notice Nonce 225 — VotingWeight.
    address internal constant VOTING_WEIGHT = 0x2d2678488e3483f905930571c1b01d5E3a138674;

    /// @notice Nonce 226 — AureumGovernance.
    address internal constant AUREUM_GOVERNANCE = 0x2c5Fc5953c42B7e0bf1A5062632fCCCBC97F0a69;

    /// @notice Nonce 227 — AureumGovernanceAuthorizer; seated on the Vault by nonce 237.
    address internal constant AUREUM_GOVERNANCE_AUTHORIZER = 0xd25f8510Fbbc7Fe0DaEBca3bB995B907211068B7;

    /// @notice Nonce 228 — AuMMMinterRouter.
    address internal constant AUMM_MINTER_ROUTER = 0x71166F782Df23a8F0Af8769241c757c08D4998A8;
}
