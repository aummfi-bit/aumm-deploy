#!/usr/bin/env bash
# record-terminal.sh - Claude Code PostToolUse hook on Bash.
#
# Appends one tab-separated line to .claude/audit/terminal-ledger.log for
# every Bash call the terminal agent completes, whatever the agent reports:
# the time, the sha256 of the command, which canonical env set the working
# .env equals after the call, the line count and sha256 of git status taken
# after the call, and the command itself on one line. Calls from every other
# caller pass unrecorded, and a call the guard refused never reaches here.
#
# The env field is decided by cmp -s against .env.mainnet and .env.sepolia,
# so no .env content and no hash of it enters the ledger.
#
# Exits 2 when the line cannot be written, so the model hears that the
# ledger is broken; the call itself has already run.
#
# Wired from .claude/settings.json as:
#   bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/record-terminal.sh
# Reads the hook JSON on stdin.

set -u

fail() {
  echo "record-terminal: $1" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || fail "jq not found; the terminal ledger was not written."
input="$(cat)"
agent="$(printf '%s' "$input" | jq -r '.agent_type // ""' 2>/dev/null)" || fail "hook input is not valid JSON; the terminal ledger was not written."
[ "$agent" = "terminal" ] || exit 0

root="${CLAUDE_PROJECT_DIR:-$PWD}"
ledger="$root/.claude/audit/terminal-ledger.log"

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
csha="$(printf '%s' "$cmd" | /usr/bin/shasum -a 256 | /usr/bin/cut -d ' ' -f 1)"
one="$(printf '%s' "$cmd" | /usr/bin/tr '\t\r\n' '   ' | /usr/bin/cut -c 1-400)"

envset="absent"
if [ -f "$root/.env" ]; then
  envset="neither"
  /usr/bin/cmp -s "$root/.env" "$root/.env.mainnet" 2>/dev/null && envset="mainnet"
  /usr/bin/cmp -s "$root/.env" "$root/.env.sepolia" 2>/dev/null && envset="sepolia"
fi

status="$(git -C "$root" status --porcelain --untracked-files=all 2>&1)"
slines="$(printf '%s' "$status" | /usr/bin/grep -c '')"
ssha="$(printf '%s' "$status" | /usr/bin/shasum -a 256 | /usr/bin/cut -d ' ' -f 1)"
now="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"

/bin/mkdir -p "$root/.claude/audit" 2>/dev/null || fail "cannot create .claude/audit; the terminal ledger was not written."
printf '%s\tterminal\tBash\tcmd_sha256=%s\tenv=%s\tstatus_lines=%s\tstatus_sha256=%s\tcmd=%s\n' \
  "$now" "$csha" "$envset" "$slines" "$ssha" "$one" >> "$ledger" 2>/dev/null \
  || fail "cannot append to .claude/audit/terminal-ledger.log."
exit 0
