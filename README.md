# aumm-deploy

Foundry project for deploying Aureum's parallel instance of the Balancer V3 Vault.

> **Scope:** this repository contains only the code needed to deploy and operate Aureum's parallel Vault — `AureumVaultFactory` (forked `VaultFactory`), `AureumAuthorizer`, `AureumProtocolFeeController`, and the deploy script. It does **not** contain the AuMM token, gauges, CCB engine, or any tokenomics-layer contracts. Those live in a separate repository.
>
> **Canonical specs:** all protocol specifications (mental model, tokenomics, constitution, formulas, Miliarium Aureum pool registry) live in [`aummfi-bit/aumm-site`](https://github.com/aummfi-bit/aumm-site). When a canonical fact changes there, constants or logic in this repo may need updating, but the docs here reference by path and do not duplicate.

## Current status

**Stage A (Foundry environment setup).** See [`docs/STAGE_A_PLAN.md`](docs/STAGE_A_PLAN.md) for the step-by-step setup plan and the Completion Log. When Stage A is tagged `stage-a-complete`, work proceeds to [`docs/STAGE_B_PLAN.md`](docs/STAGE_B_PLAN.md).

**Nothing in this repository is audited, deployed to mainnet, or production-ready.**

## Architecture summary

Aureum deploys its own parallel instance of the Balancer V3 Vault using **byte-identical bytecode** for `Vault.sol`, `VaultAdmin.sol`, and `VaultExtension.sol`. Those three files are never edited — they come directly from the pinned [`aummfi-bit/balancer-v3-monorepo`](https://github.com/aummfi-bit/balancer-v3-monorepo) submodule. The audit-inheritance argument depends on this byte-identity.

Aureum owns four contracts in this repository:

| Contract | Role | Stage |
|---|---|---|
| `AureumVaultFactory.sol` | Forked `VaultFactory` — one-shot deployer. Diff against upstream: ~5 lines to accept an external `IProtocolFeeController` via constructor rather than deploying the stock one inline. | B |
| `AureumAuthorizer.sol` | Implements `IAuthorizer`. Grants all Vault admin permissions to a single governance Safe multisig address. Binary: multisig can do anything, no one else can do anything. | B |
| `AureumProtocolFeeController.sol` | Implements `IProtocolFeeController`. Routes 50% of swap fees + 100% of protocol-extractable yield fees to der Bodensee Pool. Rejects all pool creator fee calls. No treasury. | B |
| `script/DeployAureumVault.s.sol` | Foundry deploy script. Deploys authorizer + factory, computes future Vault address via CREATE3, deploys fee controller with that address, calls `factory.create()`. | B |

## Quick start

```bash
# Install Foundry (once, per machine)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone
git clone git@github.com:aummfi-bit/aumm-deploy.git
cd aumm-deploy

# Add submodule (the Aureum-owned Balancer V3 fork)
git submodule add https://github.com/aummfi-bit/balancer-v3-monorepo.git lib/balancer-v3-monorepo
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install foundry-rs/forge-std --no-commit

# Build
forge build

# Sanity test against mainnet fork
cp .env.example .env
# fill in MAINNET_RPC_URL
source .env
forge test --fork-url $MAINNET_RPC_URL -vv
```

Full walkthrough: [`docs/STAGE_A_PLAN.md`](docs/STAGE_A_PLAN.md).

## Repository layout

```
aumm-deploy/
├── src/                              # Aureum-owned Solidity (Stage B+)
├── script/                           # Foundry deployment scripts (Stage B+)
├── test/
│   ├── unit/                         # Unit tests (Stage B+)
│   └── fork/
│       └── Sanity.t.sol              # Stage A: toolchain-wired-correctly check
├── lib/
│   ├── balancer-v3-monorepo/         # Submodule (aummfi-bit fork)
│   ├── openzeppelin-contracts/
│   └── forge-std/
├── docs/
│   ├── STAGE_A_PLAN.md               # Stage A setup plan and completion log
│   ├── STAGE_B_NOTES.md              # Stage B design notes and working log
│   ├── STAGE_B_PLAN.md               # Stage B plan and completion log
│   └── balancer_v3_reference.md      # Manifest of V3 files and key constraints
├── foundry.toml
├── remappings.txt
├── .env.example
├── .cursorrules                      # Rules for Cursor's AI assistant
├── .gitignore
├── LICENSE                           # GPL-3.0-or-later
└── README.md                         # This file
```

## Toolchain

- **Solc:** `0.8.26` (matches Balancer V3 mainnet exactly)
- **EVM version:** `cancun`
- **Optimizer:** enabled, 9999 runs
- **IR pipeline:** `via_ir = true`
- **Foundry:** forge, cast, anvil (install via `foundryup`)
- **Editor:** Cursor with Solidity extension by Juan Blanco

## License

GPL-3.0-or-later. Aureum forks Balancer V3, which is GPL-3.0; this code inherits the license. Aureum is not affiliated with, endorsed by, or sponsored by Balancer Labs or Balancer DAO.

## Disclaimer

Nothing in this repository constitutes financial advice. The code is in active development, unaudited, and not production-ready. DeFi liquidity provision involves substantial risk, including impermanent loss, smart-contract risk, oracle risk, governance risk, regulatory risk, and the total loss of deposited assets. See [`aummfi-bit/aumm-site`](https://github.com/aummfi-bit/aumm-site) for the full protocol disclaimer.
