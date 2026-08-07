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

# Section-1 Contract cells are prose; map nonce -> canonical key stem.
BASE_LAYER_KEYS = {
    87: "AureumAuthorizer",
    88: "AureumProtocolFeeController",
    89: "AureumVaultFactory",
    90: "AureumAuthorizer",
    91: "AureumProtocolFeeController",
    92: "AureumVaultFactory",
    93: "Vault",
    94: "WeightedPoolFactory",
    95: "AuMM",
    96: "AureumFeeRoutingHook",
    97: "DerBodenseePool",
    98: "Router",
}

ABANDONED_NONCES = {87, 88, 89}

# Section 1 carries a second table for the three contracts the nonce-93 CALL created
# beside the Vault, keyed by contract name rather than by deployer nonce (PB-D67 (v)).
# The CREATE3 proxy is listed so an unexpected fourth row still raises, and maps to
# None because it carries no source and no protocol role.
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
    rows = table_rows(section_body(record_text, 1))
    nonce_rows = [cells for cells in rows if isinstance(parse_nonce(cells[0]), int)]
    sibling_rows = [cells for cells in rows if not isinstance(parse_nonce(cells[0]), int)]
    expect_count("section 1 nonce rows", len(nonce_rows), 12)
    expect_count("section 1 vault-sibling rows", len(sibling_rows), 3)
    base_layer = {}
    for cells in nonce_rows:
        nonce = parse_nonce(cells[0])
        if nonce not in BASE_LAYER_KEYS:
            raise ValueError(f"section 1 nonce {nonce!r} missing from BASE_LAYER_KEYS")
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
            raise ValueError(f"section 1 sibling {name!r} missing from VAULT_SIBLING_KEYS")
        key = VAULT_SIBLING_KEYS[name]
        if key is None:
            continue
        base_layer[key] = {
            "address": unwrap(cells[1]),
            "nonce": "via nonce 93 CALL",
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
    rows7 = table_rows(section_body(record_text, 7))
    rows8 = table_rows(section_body(record_text, 8))
    rows10 = table_rows(section_body(record_text, 10))
    expect_count("section 7 rows", len(rows7), 25)
    expect_count("section 8 rows", len(rows8), 1)
    expect_count("section 10 rows", len(rows10), 1)

    pools = {}
    for cells in rows7:
        slot, entry = parse_pool_row(cells, "live")
        pools[slot] = entry

    # Live slot 02 from section 10, then superseded section 8 under a distinct key.
    slot10, entry10 = parse_pool_row(rows10[0], "live")
    pools[slot10] = entry10

    slot8, entry8 = parse_pool_row(rows8[0], "superseded")
    pools[f"{slot8}-superseded"] = entry8

    return pools


def parse_phase4(record_text: str) -> dict:
    rows = table_rows(section_body(record_text, 11))
    expect_count("section 11 rows", len(rows), 16)
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

    # 53 = PB-D65's measured 51 plus the two contracts the nonce-93 CALL created beside
    # the Vault, which no committed artifact named until PB-D67 (v). The 51 was never
    # wrong; it counted what the record then held. VaultAdmin and VaultExtension are
    # live protocol contracts by every test that matters, so they enter the total
    # rather than sitting outside it as a special case.
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
