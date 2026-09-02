# aumm-deploy

Foundry monorepo for **Aureum** — an automated market maker built as a parallel instance of Balancer V3 with a redesigned, Bitcoin-inspired tokenomic layer. Fair launch, fixed 21M cap, geometric halving, no pre-mine, no VCs, no creator fees.

Public site: <https://aumm.fi> · Canonical spec: [aummfi-bit/aumm-site](https://github.com/aummfi-bit/aumm-site)

> **This branch is not current.** `main` is 1072 commits behind active development and describes the repository as it stood at Stage K. Current work — including a first external security audit whose remediation is in progress, with 36 findings still open — lives on the [`stage-p-prime`](https://github.com/aummfi-bit/aumm-deploy/blob/stage-p-prime/README.md) branch, whose README carries accurate status. Everything below describes an earlier state of the project.

> **Scope.** This repository contains the **full Aureum protocol** — the parallel Vault customization *and* the complete tokenomic layer: the AuMM token, fee routing, the CCB engine, gauges, emission, the Miliarium registry, and on-chain governance. (Earlier revisions of this README described a Vault-only repo with tokenomics living elsewhere — that is no longer the case; everything is here.)
>
> **Canonical specs.** All protocol specifications — mental model, tokenomics, constitution, formulas (F-0…F-12), the 28-pool Miliarium Aureum registry — live in [aummfi-bit/aumm-site](https://github.com/aummfi-bit/aumm-site). Constants and logic here reference that spec by path; they do not duplicate it.
>
> **Orientation.** New to the repo? Read [`CLAUDE.md`](CLAUDE.md) (operational context) and [`docs/STAGES_OVERVIEW.md`](docs/STAGES_OVERVIEW.md) (the C→R stage sequence) first.

## Current status

**Stage K complete** — tagged `stage-k-complete`. On-chain governance and the authorizer migration are in place; the contract surface spans Stages B through K. Full regression: **852/852 tests green** (759 unit + 93 fork, run split-form per the note in Quick start).

The protocol is built in lettered stages, A → R:

| Stage | Focus | Status |
|---|---|---|
| A | Foundry environment — toolchain compiling against the pinned Balancer V3 fork + a mainnet-fork sanity test (no Aureum code yet) | Complete |
| B | Vault substrate — forked `AureumVault`, `AureumVaultFactory`, `AureumProtocolFeeController`, `AureumAuthorizer` | Complete |
| C | Block-number time library + the AuMM token — 21M cap, geometric halving | Complete |
| D | Fee-routing hook (OQ-1) + der Bodensee pool | Complete |
| E | Pool-deployment framework + 3 pilot Miliarium pools | Complete |
| F | CCB engine — Compound Centrifugal Balance scoring (F-4/F-5/F-6/F-8) | Complete |
| G | Gauge registry + permissionless auto-gauge eligibility | Complete |
| H | Emission distributor — the AuMM emission schedule | Complete |
| I | AuMT LP tessera — reframed as the Vault's Balancer Pool Token | Complete |
| J | Miliarium registry — the 28-slot → pool mapping | Complete |
| K | On-chain governance + Vault authorizer migration | **Complete — current tip** |
| L | Incendiary Boost — the F-2 priority skim | Pending |
| M | Miliarium pools, Sector 2 — Majors / yield-core (~10) | Pending |
| N | Miliarium pools, Sector 3 — Equity + thematic (~14) | Pending |
| O | Composition challenge / replacement-launch path + Aureum Router | Pending |
| P | Holesky full-system deployment + integration validation | Pending |
| Q | External audit + patch cycle | Pending |
| R | Mainnet deployment — terminal stage | Pending |

**Nothing in this repository is audited, deployed to mainnet, or production-ready.**

## Architecture

Aureum deploys its own parallel instance of the Balancer V3 Vault using **byte-identical bytecode** for `Vault.sol`, `VaultAdmin.sol`, and `VaultExtension.sol` — these come directly from the pinned [aummfi-bit/balancer-v3-monorepo](https://github.com/aummfi-bit/balancer-v3-monorepo) submodule and are never edited. The audit-inheritance argument depends on that byte-identity. All Aureum customization is isolated to the reviewable contracts below.

| Module (`src/`) | Stage | Contracts | Role |
|---|---|---|---|
| `vault/` | B | `AureumVaultFactory`, `AureumAuthorizer`, `AureumProtocolFeeController` | F2 fork factory accepting an external fee controller; binary Safe-multisig authorizer; fee controller routing the Vault's 50%-capped protocol fees to der Bodensee, creator fees structurally disabled |
| `lib/` | C | `AureumTime` | Block-number math — eras, epochs, halving boundaries |
| `token/` | C, K | `AuMM`, `AuMMMinterRouter` | 21M-cap geometric-halving ERC-20; one-shot-minter allowlist forwarder (K5 handoff) |
| `fee_router/` | D | `AureumFeeRoutingHook` | Converts swap/yield fees and routes them to der Bodensee (OQ-1 hook saturating the 50% protocol-fee cap) |
| `factory/` | E | `AureumWeightedPoolFactory` | WeightedPool factory enforcing the 52% ERC-4626 Quality Gate |
| `ccb/` | F | `CCBMultiplier`, `CCBScore`, `CCBShare`, `EMASampler` | F-8 anti-cyclical (Compound Centrifugal Balance) multiplier over the 28-Miliarium constellation; EMA TVL sampling |
| `gauge/` | G | `GaugeRegistry`, `GaugeEligibility`, `VaultClassRegistry`, `SwapAndDepositToBodensee` | Gauge state machine (three activation paths), eligibility checks, vault-class admission, anti-spam Bodensee donation primitive |
| `emission/` | H | `EmissionDistributor`, `BodenseeBootstrapChannel`, `TVLOracle`, `EfficiencyOracle` | Pool-scoped AuMM emission; F-0 piecewise bootstrap rail; TVL and efficiency oracles |
| `registry/` | J | `MiliariumRegistry` | Canonical fixed 28-slot constellation binding + dense pool enumeration |
| `governance/` | K | `AureumGovernance`, `AureumGovernanceAuthorizer`, `VotingWeight` | Three proposal types (gauge / composition / fee) + snapshot voting + 2-day timelock; B-strict 12-month time-bomb authorizer (OQ-10); value-weighted voting reader |
| `incendiary/` | L | `IIncendiaryRegistry` (interface only) | Forward-dep stub for the Stage L boost registry — not yet implemented |

**On AuMT.** Aureum's per-pool LP receipt (AuMT — Aureum Market Tessera) is the Vault's Balancer Pool Token (BPT) itself, reframed at Stage I — there is no separate `AuMT.sol`. Governance weight derived from it is read by `VotingWeight`.

## Quick start

Prerequisites: Foundry — `curl -L https://foundry.paradigm.xyz | bash` then `foundryup`.

1. Clone with submodules: `git clone --recursive git@github.com:aummfi-bit/aumm-deploy.git && cd aumm-deploy` (already cloned without `--recursive`? run `git submodule update --init --recursive`).
2. Build: `forge build`.
3. Unit tests (no fork): `forge test --no-match-path "test/fork/**"`.
4. Fork tests: copy `.env.example` to `.env`, set `MAINNET_RPC_URL`, then `source .env && forge test --match-path "test/fork/**" --fork-url $MAINNET_RPC_URL --threads 1`.

> Run the unit and fork suites **separately**, as above. A single `forge test --fork-url …` applies fork context to all 200+ tests and rate-limit-hangs on Ankr; `--threads 1` avoids a `vm.setEnv` race between parallel fork-test contracts.

## Repository layout

- `src/` — Aureum contracts, one directory per module: `vault/` `lib/` `token/` `fee_router/` `factory/` `ccb/` `gauge/` `emission/` `registry/` `governance/` `incendiary/` (see the Architecture table).
- `script/` — Foundry deploy scripts: per-stage (`DeployAuMM`, `DeployAureumVault`, `DeployAureumWeightedPoolFactory`, `DeployDerBodensee`, `DeployStageH`…`DeployStageK`) plus `script/pools/` (per-Miliarium-pool configs and deploy runners).
- `test/` — `unit/` (per-contract suites + `harness/`), `fork/` (mainnet-fork integration + `mocks/`), and shared `mocks/`.
- `lib/` — submodules: `balancer-v3-monorepo` (aummfi-bit fork, pinned), `openzeppelin-contracts`, `forge-std`.
- `docs/` — `STAGES_OVERVIEW.md`, `FINDINGS.md`, `ROBUSTNESS_BACKPORT_REGISTER.md`, per-stage `STAGE_A`…`STAGE_K` `_PLAN`/`_NOTES` files, `balancer_v3_reference.md`, and `white_hat/` (audit process + findings ledger).
- Root — `CLAUDE.md` (session operational context), `foundry.toml`, `foundry.lock`, `remappings.txt`, `.env.example`, `.cursorrules`, `LICENSE` (GPL-3.0-or-later), `README.md`.

## Toolchain

- **Solc** `0.8.26` (exact match to Balancer V3 mainnet), **EVM** `cancun`, optimizer enabled at **9999** runs, **`via_ir = true`**.
- **Foundry** — forge, cast, anvil (install via `foundryup`).
- **Slither** `0.11.4` (in `.venv/`) for static analysis.
- **Editor** — Cursor with the Juan Blanco Solidity extension.

## License

GPL-3.0-or-later. Aureum forks Balancer V3 (GPL-3.0); this code inherits the license. Aureum is not affiliated with, endorsed by, or sponsored by Balancer Labs or Balancer DAO.

## Disclaimer

Nothing in this repository constitutes financial advice. The code is in active development, unaudited, and not production-ready. DeFi liquidity provision involves substantial risk — impermanent loss, smart-contract risk, oracle risk, governance risk, regulatory risk, and the total loss of deposited assets. See [aummfi-bit/aumm-site](https://github.com/aummfi-bit/aumm-site) for the full protocol disclaimer.
