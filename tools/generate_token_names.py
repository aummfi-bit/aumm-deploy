#!/usr/bin/env python3
"""Generate the aumm-app token display-name map from the per-pool configs.

PB-D76. Every Sepolia stub reports symbol() STUBV, so the app cannot use the
chain symbol as a display name. The 26 per-pool config libraries are the same
source that drove the deployment: each declares an uppercase address constant,
assigns it into tokens[i], and annotates normalizedWeights[i] with a
display-cased name. This joins those by token index and emits mainnet address
to display name.

The join validates itself. Constant and comment must agree once underscores and
spaces are stripped and case is folded (AAVE_PRIME_GHO against Aave Prime GHO),
so a config whose comment drifts from its constant stops the generator rather
than emitting a wrong name.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

CONFIG_DIR = "script/pools/configs"
EXPECTED_CONFIGS = 26
EXPECTED_TOKENS = 59

GENERATOR = "tools/generate_token_names.py"

# Slots 04 and 07 are descoped per PB-D8, so 26 configs cover 28 slots.
CONST_RE = re.compile(r"address internal constant ([A-Z0-9_]+)\s*=\s*(0x[0-9a-fA-F]{40})")
TOKEN_RE = re.compile(r"tokens\[(\d+)\]\s*=\s*([A-Z0-9_]+);")
# Lazy up to the trailing percentage so multi-word names survive intact:
# "// Aave Prime GHO 26%" yields "Aave Prime GHO", not "Aave".
WEIGHT_RE = re.compile(r"normalizedWeights\[(\d+)\]\s*=\s*[^;]+;\s*//\s*(.+?)\s+[\d.]+%")

NOTE = (
    "Mainnet token addresses to display names, parsed from the per-pool config "
    "libraries in script/pools/configs. Keys are LOWERCASE: the deployed-addresses "
    "artifact mixes checksummed and lowercase forms, so callers must lowercase "
    "before lookup. On Sepolia a pool leg is a stub and resolves to its mainnet "
    "literal through the artifact's stubs reverse index first; on mainnet the leg "
    "address is the literal and matches here directly."
)


def fail(message):
    raise SystemExit(f"generate_token_names: {message}")


def fold(name):
    """Compare-form for a token name: no underscores, no spaces, lowercase."""
    return name.replace("_", "").replace(" ", "").lower()


def git_state(root):
    def run(args):
        result = subprocess.run(args, cwd=root, capture_output=True, text=True)
        if result.returncode != 0:
            fail(f"git {args[1]} failed: {result.stderr.strip()}")
        return result.stdout.strip()

    return run(["git", "rev-parse", "HEAD"]), bool(run(["git", "status", "--porcelain"]))


def parse_config(path):
    """Return {lowercase address: display name} for one pool config."""
    text = path.read_text(encoding="utf-8")
    constants = dict(CONST_RE.findall(text))
    tokens = dict(TOKEN_RE.findall(text))
    names = dict(WEIGHT_RE.findall(text))

    if not tokens:
        fail(f"{path.name}: no tokens[] assignments found")
    if set(tokens) != set(names):
        fail(
            f"{path.name}: token indices {sorted(tokens)} do not match "
            f"weight-comment indices {sorted(names)}"
        )

    found = {}
    for index, constant in tokens.items():
        if constant not in constants:
            fail(f"{path.name}: tokens[{index}] = {constant} has no address constant")
        display = names[index]
        if fold(constant) != fold(display):
            fail(
                f"{path.name}: tokens[{index}] constant {constant} disagrees with "
                f"weight comment {display!r}; one of them is wrong"
            )
        found[constants[constant].lower()] = display
    return found


def main():
    parser = argparse.ArgumentParser(description="Generate the aumm-app token name map.")
    parser.add_argument("--out", required=True, help="target file, e.g. ../aumm-app/src/config/token-names.json")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    configs = sorted((root / CONFIG_DIR).glob("*.s.sol"))
    if len(configs) != EXPECTED_CONFIGS:
        fail(f"found {len(configs)} configs in {CONFIG_DIR}, expected {EXPECTED_CONFIGS}")

    names = {}
    for path in configs:
        for address, display in parse_config(path).items():
            previous = names.get(address)
            if previous is not None and previous != display:
                fail(
                    f"{address} is named {previous!r} and {display!r} by different "
                    f"configs; resolve the disagreement at the source"
                )
            names[address] = display

    if len(names) != EXPECTED_TOKENS:
        fail(f"resolved {len(names)} distinct tokens, expected {EXPECTED_TOKENS}")

    commit, dirty = git_state(root)
    payload = {
        "generator": GENERATOR,
        "sourceRepo": "aumm-deploy",
        "commit": commit,
        "dirty": dirty,
        "note": NOTE,
        "names": dict(sorted(names.items())),
    }

    out_path = Path(args.out).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")

    print(f"wrote {out_path}: {len(names)} tokens from {len(configs)} configs")
    if dirty:
        print("WARNING: working tree dirty; the recorded commit does not fully describe this map")
    return 0


if __name__ == "__main__":
    sys.exit(main())
