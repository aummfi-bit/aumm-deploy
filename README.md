# aumm-deploy

Foundry monorepo for **Aureum** — an automated market maker built as a parallel instance of Balancer V3 with a redesigned, Bitcoin-inspired tokenomic layer. Fair launch, fixed 21M cap, geometric halving, no pre-mine, no VCs, no creator fees.

Public site: <https://aumm.fi> · Canonical spec: [aummfi-bit/aumm-site](https://github.com/aummfi-bit/aumm-site)

> **Scope.** This repository contains the **full Aureum protocol** — the parallel Vault deployment *and* the complete tokenomic layer: the AuMM token, fee routing, the CCB engine, gauges, emission, the Miliarium registry, on-chain governance, and the Incendiary Boost.
>
> **Canonical specs.** All protocol specifications — mental model, tokenomics, constitution, formulas (F-0…F-12), the 28-slot Miliarium Aureum registry — live in [aummfi-bit/aumm-site](https://github.com/aummfi-bit/aumm-site). Constants and logic here reference that spec by path; they do not duplicate it.
>
> **Orientation.** New to the repo? Read [`CLAUDE.md`](CLAUDE.md) (operational context) and [`docs/STAGES_OVERVIEW.md`](docs/STAGES_OVERVIEW.md) (the stage sequence, A → R plus the Stage P-bis insert) first.

## Current status

**Stages A through P are complete** — tagged `stage-a-complete` through `stage-p-complete` — and **Stage P-bis is in flight**: workstream A (open-issue close-out) closed with every item Fixed, Built, or explicitly descoped with rationale; workstream B (Sepolia testnet go-live) executed; workstream C (the `aumm-app` frontend against live Sepolia) underway. Stage Q narrows to the external audit engagement; Stage R is mainnet.

**The full protocol is live on Sepolia** (chain 11155111): 53 protocol contracts — the base layer, the Stage F–K emission and governance stack, the canonical Router, and 26 of the 28 Miliarium slots deployed and capitalised — plus 59 stub tokens standing in for mainnet assets, all explorer-verified, the TVL oracle wired, and the emission genesis block sealed on-chain. Addresses live in [`deployments/11155111.json`](deployments/11155111.json); the authoritative per-transaction history, including two abandoned earlier generations, is [`docs/STAGE_P_BIS_SEPOLIA_DEPLOYMENT_RECORD.md`](docs/STAGE_P_BIS_SEPOLIA_DEPLOYMENT_RECORD.md).

White-hat ledger: findings F-01 through F-23, **zero open** — each Fixed, Split, or Accepted-risk with recorded rationale ([`docs/white_hat/AUREUM_WHITEHAT_OUTPUT.md`](docs/white_hat/AUREUM_WHITEHAT_OUTPUT.md)). Formal methods: 55/55 hevm symbolic proofs green across the four Aureum-owned surfaces, plus nine Act specs ([`formal/RESULTS.md`](formal/RESULTS.md)). Unit gate: 1005 tests green as of the 2026-08 Sepolia generation-3 refresh (run split-form per Quick start).

| Stage | Focus | Status |
|---|---|---|
| A | Foundry environment — toolchain compiling against the pinned Balancer V3 fork + a mainnet-fork sanity test | Complete |
| B | Vault substrate — `AureumVaultFactory`, `AureumProtocolFeeController`, `AureumAuthorizer` | Complete |
| C | Block-number time library + the AuMM token — 21M cap, geometric halving | Complete |
| D | Fee-routing hook (OQ-1) + der Bodensee pool | Complete |
| E | Pool-deployment framework + 3 pilot Miliarium pools | Complete |
| F | CCB engine — Compound Centrifugal Balance scoring (F-4/F-5/F-6/F-8) | Complete |
| G | Gauge registry + permissionless auto-gauge eligibility | Complete |
| H | Emission distributor — the AuMM emission schedule | Complete |
| I | AuMT LP tessera — reframed as the Vault's Balancer Pool Token | Complete |
| J | Miliarium registry — the 28-slot → pool mapping | Complete |
| K | On-chain governance + Vault authorizer migration | Complete |
| L | Incendiary Boost — the F-2 priority skim | Complete |
| M | Miliarium pools, Sector 2 — Majors / yield-core (5 pools) | Complete |
| N | Miliarium pools, Sector 3 — the 18-pool tranche + the rate-provider surface | Complete |
| O | Composition-fitness gate (OQ-7) for governance composition challenges | Complete |
| P | White-hat back-fill sweep + full-system deploy validation on a mainnet fork | Complete |
| P-bis | Open-issue close-out + Sepolia go-live + frontend | **In flight — current** |
| Q | External audit engagement | Pending |
| R | Mainnet deployment — terminal stage | Pending |

**Nothing in this repository is audited, deployed to mainnet, or production-ready.** The Sepolia deployment is a rehearsal of the mainnet sequence, not a production system.

## Architecture

Aureum deploys its own parallel instance of the Balancer V3 Vault. The vault contracts (`Vault.sol`, `VaultAdmin.sol`, `VaultExtension.sol`) come **source-byte-identical** from the pinned [aummfi-bit/balancer-v3-monorepo](https://github.com/aummfi-bit/balancer-v3-monorepo) submodule and are never edited — the audit-inheritance argument depends on that. They compile under a dedicated `[profile.vault]` (see Toolchain) for EIP-170 fit; compiled-bytecode parity with the mainnet-deployed Vault is a Stage R item, not claimed here. All Aureum customization is isolated to the reviewable contracts below.

| Module (`src/`) | Stage | Contracts | Role |
|---|---|---|---|
| `vault/` | B | `AureumVaultFactory`, `AureumAuthorizer`, `AureumProtocolFeeController` | F2 fork factory accepting an external fee controller; Safe-multisig authorizer; fee controller routing the Vault's 50%-capped protocol fees to der Bodensee, creator fees structurally disabled |
| `lib/` | C | `AureumTime` | Block-number math — eras, epochs, halving boundaries |
| `token/` | C, K | `AuMM`, `AuMMMinterRouter` | 21M-cap geometric-halving ERC-20; one-shot-minter allowlist forwarder |
| `fee_router/` | D | `AureumFeeRoutingHook` | Converts swap/yield fees and donates them into der Bodensee — irreversible depth, no BPT minted (OQ-1 hook saturating the 50% protocol-fee cap) |
| `factory/` | E | `AureumWeightedPoolFactory` | WeightedPool factory enforcing the 52% ERC-4626 Quality Gate |
| `ccb/` | F | `CCBMultiplier`, `CCBScore`, `CCBShare`, `EMASampler` | F-8 anti-cyclical (Compound Centrifugal Balance) multiplier; EMA TVL sampling |
| `gauge/` | G, O | `GaugeRegistry`, `GaugeEligibility`, `VaultClassRegistry`, `SwapAndDepositToBodensee` | Gauge state machine, eligibility + the OQ-7 composition-quality gate, vault-class admission, anti-spam Bodensee donation primitive |
| `emission/` | H | `EmissionDistributor`, `BodenseeBootstrapChannel`, `TVLOracle`, `EfficiencyOracle` | Pool-scoped AuMM emission; F-0 piecewise bootstrap rail; weighted-venue TVL oracle with a two-hop fallback; efficiency oracle |
| `registry/` | J | `MiliariumRegistry` | Canonical fixed 28-slot constellation binding + dense pool enumeration |
| `governance/` | K | `AureumGovernance`, `AureumGovernanceAuthorizer`, `VotingWeight` | Six proposal types — gauge, composition, fee, plus the F-22 Vault-admin set — with snapshot voting + timelock; 12-month time-bomb authorizer (OQ-10); value-weighted voting reader |
| `incendiary/` | L | `IncendiaryRegistry` | F-2 Incendiary Boost — five-gated `buyBoost`, 60-day-EMA pricing, der Bodensee deposit tail |
| `rate_provider/` | N | `ERC4626RateProvider`, `CompositeRateProvider` | Aureum-owned rate providers for ERC-4626 and two-hop legs (F-11 guard) |

**On AuMT.** Aureum's per-pool LP receipt (AuMT — Aureum Market Tessera) is the Vault's Balancer Pool Token (BPT) itself — there is no separate `AuMT.sol`. Governance weight derived from it is read by `VotingWeight`.

## Quick start

Prerequisites: Foundry — `curl -L https://foundry.paradigm.xyz | bash` then `foundryup`.

1. Clone with submodules: `git clone --recursive git@github.com:aummfi-bit/aumm-deploy.git && cd aumm-deploy` (already cloned without `--recursive`? run `git submodule update --init --recursive`).
2. Build: `forge build` (all Aureum source, default profile). The Balancer vault package builds separately: `FOUNDRY_PROFILE=vault forge build`.
3. Unit tests (no fork): `forge test --no-match-path "test/fork/**"`.
4. Fork tests: copy `.env.example` to `.env`, set `MAINNET_RPC_URL`, then run one fork file at a time: `source .env && forge test --match-path test/fork/StagePIntegration.t.sol --fork-url $MAINNET_RPC_URL --threads 1` (substitute the file under test).

> Run the unit and fork suites **separately**, and fork suites **file-scoped**: a single `forge test --fork-url …` over the whole tree applies fork context to every test and rate-limit-hangs, and `--threads 1` avoids a `vm.setEnv` race between parallel fork-test contracts. One fork suite (`PB52SepoliaOracleEvidence`) forks Sepolia rather than mainnet and needs `SEPOLIA_RPC_URL`.

## Repository layout

- `src/` — Aureum contracts, one directory per module (see the Architecture table).
- `script/` — Foundry deploy scripts: per-contract granular scripts, the `DeployStageP` full-system orchestrator, the Sepolia wiring and seeding scripts (`WireTVLOracleSepolia`, `SeedMiliariumPoolsSepolia`), `script/config/` (committed address and underlying tables), and `script/pools/` (per-Miliarium-pool configs and runners).
- `test/` — `unit/`, `fork/` (mainnet-fork integration), `whitehat/` (F-nn PoC suites), `invariant/`, `formal/` (hevm symbolic-proof harnesses), and shared `mocks/`.
- `test-stubs/` — Sepolia stand-ins: `StubERC20` / `StubERC4626`, their deploy script, and the committed stub address map.
- `formal/` — the Act specs (`act/`) plus `RESULTS.md`, the property → status index for the hevm/Act bundle.
- `deployments/` — deployed-address artifacts per chain (`11155111.json` = Sepolia).
- `tools/` — artifact generators: the deployment JSON and the frontend ABI package.
- `lib/` — submodules: `balancer-v3-monorepo` (aummfi-bit fork, pinned), `openzeppelin-contracts`, `forge-std`, `permit2`.
- `docs/` — `STAGES_OVERVIEW.md`, `FINDINGS.md`, `ROBUSTNESS_BACKPORT_REGISTER.md`, per-stage `_PLAN`/`_NOTES` files, the Stage P-bis Sepolia records (deployment record, runbooks, per-transaction ledgers), `balancer_v3_reference.md`, and `white_hat/` (audit process + findings ledger).
- Root — `CLAUDE.md` (session operational context), `foundry.toml`, `foundry.lock`, `remappings.txt`, `.env.example`, `.cursorrules`, `LICENSE` (GPL-3.0-or-later), `README.md`.

## Toolchain

- **Two compiler profiles** (`foundry.toml`): `[profile.default]` — solc `0.8.26`, EVM `cancun`, optimizer at 9999 runs, `via_ir = true` — all Aureum source, into `out/`; `[profile.vault]` — solc `0.8.30`, optimizer at 500 runs plus an explicit Yul `optimizerSteps` block — the Balancer vault package only, into `out-vault/`, because the Vault overruns the EIP-170 size limit under the default settings. Deployed sizes are gated by `test/unit/BytecodeSize.t.sol`.
- **Foundry** — forge, cast, anvil (install via `foundryup`).
- **Slither** `0.11.4` (in `.venv/`) for static analysis; **hevm** `0.58.0` + bitwuzla for the symbolic-proof bundle.
- **Editor** — Cursor with the Juan Blanco Solidity extension.

## License

GPL-3.0-or-later. Aureum forks Balancer V3 (GPL-3.0); this code inherits the license. Aureum is not affiliated with, endorsed by, or sponsored by Balancer Labs or Balancer DAO.

## Disclaimer

Nothing in this repository constitutes financial advice. The code is in active development, unaudited, and not production-ready. DeFi liquidity provision involves substantial risk — impermanent loss, smart-contract risk, oracle risk, governance risk, regulatory risk, and the total loss of deposited assets. See [aummfi-bit/aumm-site](https://github.com/aummfi-bit/aumm-site) for the full protocol disclaimer.
