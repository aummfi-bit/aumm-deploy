# Run Metadata — aumm-q-governance-2026-08

Both hashes below go in the report header. Without them there is no reproduction
and no honest comparison between runs.

| Item | Value |
|---|---|
| Seam | 1 — Authority and governance (`src/governance/`) |
| Snapshot date | 2026-08-19 |
| auditician commit | `22aa9851caf68f13c9439bd145ef7594f217df5c` (no tags/releases exist) |
| aumm-deploy commit | `9ec513d99a68fb454a8a54271b34b884f40f2088` (branch `stage-p-bis`) |
| README canary | PASSED — no "Stage B" status line; new README confirmed in copy |
| lib/balancer-v3-monorepo | `68057fdad93cffe3499a5a1c04a40313ac07233c` (pinned, Etherscan-verified) |
| lib/openzeppelin-contracts | `5fd1781b1454fd1ef8e722282f86f9293cacf256` (v5.6.1) |
| lib/forge-std | `0844d7e1fc5e60d77b68e469bff60265f236c398` (v1.15.0) |
| lib/permit2 | `cc56ad0f3439c502c246fc5cfcc3db92bb8b7219` |

Submodule note: `audit-target/aumm-deploy/lib/*` was populated by copying the
verified submodule content from the working checkout (`.git` excluded), not by a
network fetch. Content corresponds to the pins above as recorded by
`git submodule status` in the source checkout on the snapshot date.
