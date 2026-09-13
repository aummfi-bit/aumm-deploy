#!/usr/bin/env bash
# record-write.sh - Claude Code PostToolUse hook on Write | Edit | MultiEdit | NotebookEdit.
#
# Appends one measured line per repo write to .claude/audit/write-ledger.log,
# whatever the writer reports about its own save: UTC time, calling agent,
# tool, path relative to the repo, line count, byte count, sha256, em-dash
# count, and the working-tree-versus-index diff stat. The auditor reads this
# ledger and re-measures independently; the writer never reads it. Writes
# outside the project directory are not ledgered.
#
# Fails loud, never silent: if the ledger cannot be written the hook exits 2
# so the reason reaches the model. The tool call itself has already run.
#
# Wired from .claude/settings.json as:
#   bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/record-write.sh
# Reads the hook JSON on stdin.

set -u

command -v jq >/dev/null 2>&1 || {
  echo "record-write: jq not found; no ledger line written." >&2
  exit 2
}

input="$(cat)"

if ! agent="$(printf '%s' "$input" | jq -r '.agent_type // "main"')"; then
  echo "record-write: hook input is not valid JSON; no ledger line written." >&2
  exit 2
fi
tool="$(printf '%s' "$input" | jq -r '.tool_name // "unknown"')"
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')"
root="${CLAUDE_PROJECT_DIR:-$PWD}"

[ -n "$path" ] || exit 0

case "$path" in
  /*) abs="$path" ;;
  *)  abs="$root/$path" ;;
esac

case "$abs" in
  "$root"/*) rel="${abs#"$root"/}" ;;
  *) exit 0 ;;
esac

ledger_dir="$root/.claude/audit"
ledger="$ledger_dir/write-ledger.log"
mkdir -p "$ledger_dir" 2>/dev/null || {
  echo "record-write: cannot create $ledger_dir; no ledger line written." >&2
  exit 2
}

if [ -f "$abs" ]; then
  lines="$(wc -l < "$abs" | tr -d ' ')"
  bytes="$(wc -c < "$abs" | tr -d ' ')"
  sha="$(shasum -a 256 "$abs" | cut -d ' ' -f 1)"
  emdash="$(grep -c $'\xe2\x80\x94' "$abs")"
  stat="$(git -C "$root" diff --stat -- "$rel" 2>/dev/null | tail -n 1 | sed 's/^ *//')"
  if [ -z "$stat" ]; then
    if git -C "$root" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
      stat="no diff against index"
    else
      stat="untracked"
    fi
  fi
else
  lines="absent"; bytes="absent"; sha="absent"; emdash="absent"; stat="file absent after the write"
fi

printf '%s\t%s\t%s\t%s\tlines=%s\tbytes=%s\tsha256=%s\temdash=%s\t%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$agent" "$tool" "$rel" \
  "$lines" "$bytes" "$sha" "$emdash" "$stat" >> "$ledger" || {
  echo "record-write: cannot append to $ledger; no ledger line written." >&2
  exit 2
}

exit 0
