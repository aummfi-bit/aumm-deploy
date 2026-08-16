#!/usr/bin/env python3
"""Generate the Sepolia chain-id-keyed deployment JSON from committed sources.

Stage R adds a sibling invocation writing deployments/1.json. This script is the
PB-D65 (viii) derivation whose audit is a diff of its output against those two
sources (the deployment record and the stub topology ledger).
"""

import json
import re
import sys
from pathlib import Path

CHAIN_ID = 11155111
RECORD = "docs/STAGE_P_BIS_SEPOLIA_DEPLOYMENT_RECORD.md"
LEDGER = "docs/STAGE_P_BIS_STUB_TOPOLOGY_LEDGER.md"
OUT = "deployments/11155111.json"

# Section-20 Contract cells are prose; map nonce -> canonical key stem.
BASE_LAYER_KEYS = {
    905: "AureumAuthorizer",
    906: "AureumProtocolFeeController",
    907: "AureumVaultFactory",
    908: "Vault",
    909: "WeightedPoolFactory",
    910: "AuMM",
    911: "AureumFeeRoutingHook",
    912: "DerBodenseePool",
    913: "Router",
}

# Generation 3 orphaned nothing. The PB-D32 EIP-170 trio belonged to generation 1's
# nonces 87 to 89 and is unreachable from this generation's sections, so the set is
# empty rather than deleted, which keeps the abandoned-key branch structurally live.
ABANDONED_NONCES: set = set()

# Section 20 carries a second table for the three contracts the nonce-908 CALL created
# beside the Vault, keyed by contract name rather than by deployer nonce (PB-D67 (v);
# the generation-3 sibling table landed at PB3.14h1). The CREATE3 proxy is listed so an
# unexpected fourth row still raises, and maps to None: no source, no protocol role.
VAULT_SIBLING_KEYS = {
    "VaultAdmin": "VaultAdmin",
    "VaultExtension": "VaultExtension",
    "CREATE3 proxy": None,
}

KIND_TO_ROLE = {
    "VAULT": "vault",
    "UNDERLYING": "underlying",
    "PROVIDER": "provider",
    "STANDARD": "standard",
}

HEADING_RE = re.compile(r"^## (\d+)\.")
POOL_CONTRACT_RE = re.compile(r"`([^`]+)`,\s*slot\s+(\d{2})")


def unwrap(value: str) -> str:
    """Strip a single surrounding backtick pair, if present."""
    value = value.strip()
    if len(value) >= 2 and value.startswith("`") and value.endswith("`"):
        return value[1:-1]
    return value


def parse_nonce(cell: str):
    """Return int when the cell is a bare integer; otherwise the raw cell text."""
    cell = cell.strip()
    try:
        return int(cell)
    except ValueError:
        return cell


def table_rows(lines):
    """Yield cell lists for markdown table data rows (not header or separator)."""
    rows = []
    for line in lines:
        if not line.startswith("| "):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if not cells:
            continue
        first = cells[0]
        if first in ("Nonce", "Contract") or first.startswith("---"):
            continue
        rows.append(cells)
    return rows


def section_body(text: str, section_num: int):
    """Return lines under heading ## N. until the next ## heading."""
    lines = text.splitlines()
    in_section = False
    body = []
    for line in lines:
        match = HEADING_RE.match(line)
        if match:
            if int(match.group(1)) == section_num:
                in_section = True
                continue
            if in_section:
                break
        elif in_section:
            body.append(line)
    return body


def expect_count(name: str, actual: int, expected: int) -> None:
    if actual != expected:
        raise ValueError(f"{name}: expected {expected}, got {actual}")


def parse_base_layer(record_text: str) -> dict:
    rows = table_rows(section_body(record_text, 20))
    nonce_rows = [cells for cells in rows if isinstance(parse_nonce(cells[0]), int)]
    sibling_rows = [cells for cells in rows if not isinstance(parse_nonce(cells[0]), int)]
    expect_count("section 20 nonce rows", len(nonce_rows), 9)
    expect_count("section 20 vault-sibling rows", len(sibling_rows), 3)
    base_layer = {}
    for cells in nonce_rows:
        nonce = parse_nonce(cells[0])
        if nonce not in BASE_LAYER_KEYS:
            raise ValueError(f"section 20 nonce {nonce!r} missing from BASE_LAYER_KEYS")
        stem = BASE_LAYER_KEYS[nonce]
        if nonce in ABANDONED_NONCES:
            key = stem + "Abandoned"
            status = "abandoned"
        else:
            key = stem
            status = "live"
        base_layer[key] = {
            "address": unwrap(cells[2]),
            "nonce": nonce,
            "status": status,
        }
    for cells in sibling_rows:
        name = unwrap(cells[0])
        if name not in VAULT_SIBLING_KEYS:
            raise ValueError(f"section 20 sibling {name!r} missing from VAULT_SIBLING_KEYS")
        key = VAULT_SIBLING_KEYS[name]
        if key is None:
            continue
        base_layer[key] = {
            "address": unwrap(cells[1]),
            "nonce": "via nonce 908 CALL",
            "status": "live",
        }
    return base_layer


def parse_pool_row(cells, status: str) -> tuple:
    """Return (slot_key, entry) from a pools-table row."""
    match = POOL_CONTRACT_RE.search(cells[1])
    if not match:
        raise ValueError(f"pool Contract cell not parseable: {cells[1]!r}")
    name = match.group(1)
    slot = match.group(2)
    return slot, {
        "name": name,
        "address": unwrap(cells[2]),
        "nonce": parse_nonce(cells[0]),
        "status": status,
    }


def parse_pools(record_text: str) -> dict:
    rows = table_rows(section_body(record_text, 21))
    expect_count("section 21 rows", len(rows), 26)

    # Generation 3 seated all 26 pools in one section from the canonical deployer, so
    # there is no salt-collision split and no superseded slot. Generation 1 needed
    # sections 7, 8 and 10 because PB-D39 forced slot 02 onto a second and then a third
    # sender; the relocated BODENSEE_SALT retired that, and section 21 is contiguous.
    pools = {}
    for cells in rows:
        slot, entry = parse_pool_row(cells, "live")
        pools[slot] = entry

    return pools


def parse_phase4(record_text: str) -> dict:
    rows = table_rows(section_body(record_text, 22))
    expect_count("section 22 rows", len(rows), 16)
    phase4 = {}
    for cells in rows:
        key = unwrap(cells[1])
        phase4[key] = {
            "address": unwrap(cells[2]),
            "nonce": parse_nonce(cells[0]),
            "status": "live",
        }
    return phase4


def parse_stubs(ledger_text: str) -> dict:
    rows = table_rows(ledger_text.splitlines())
    expect_count("ledger rows", len(rows), 87)
    stubs = {}
    for cells in rows:
        kind = cells[1].strip()
        if kind not in KIND_TO_ROLE:
            raise ValueError(f"unknown ledger Kind {kind!r}")
        role = KIND_TO_ROLE[kind]
        literal = unwrap(cells[2])
        entry = {
            "address": unwrap(cells[3]),
            "nonce": parse_nonce(cells[0]),
        }
        stubs.setdefault(literal, {})[role] = entry
    return stubs


def live_count(mapping: dict) -> int:
    return sum(1 for entry in mapping.values() if entry.get("status") == "live")


def main() -> int:
    record_text = Path(RECORD).read_text(encoding="utf-8")
    ledger_text = Path(LEDGER).read_text(encoding="utf-8")

    base_layer = parse_base_layer(record_text)
    pools = parse_pools(record_text)
    phase4 = parse_phase4(record_text)
    stubs = parse_stubs(ledger_text)

    # 53 holds across both generations but is reached differently. Generation 1 was 14
    # base-layer entries less the PB-D32 abandoned trio, 27 pools less the superseded
    # slot 02, and 16 from phase 4. Generation 3 is 11, 26 and 16 with nothing excluded,
    # which is why ABANDONED_NONCES is empty and pools carries no superseded key.
    live_total = live_count(base_layer) + live_count(pools) + live_count(phase4)
    expect_count("live protocol total", live_total, 53)

    payload = {
        "chainId": CHAIN_ID,
        "generatedFrom": [RECORD, LEDGER],
        "baseLayer": base_layer,
        "pools": pools,
        "phase4": phase4,
        "stubs": stubs,
    }

    out_path = Path(OUT)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")

    print(
        f"wrote {OUT}: baseLayer={len(base_layer)} pools={len(pools)} "
        f"phase4={len(phase4)} stubs={len(stubs)} live={live_total}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
