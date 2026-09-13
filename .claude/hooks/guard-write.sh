#!/usr/bin/env bash
# guard-write.sh - Claude Code PreToolUse hook on Write | Edit | MultiEdit | NotebookEdit.
#
# Rule 1: only the agent named "composer" may write inside this repository.
# Every other caller, the main session included, is refused with exit 2,
# which blocks the tool call and feeds the reason back to the model.
# Writes outside the project directory pass for every caller, so artifact
# pages and scratchpad files keep working.
#
# Rule 2, for every caller: nothing writes under lib/, the vendored Balancer,
# OpenZeppelin and forge-std trees (CLAUDE.md section 8c).
#
# Fails closed: a missing jq or an unparseable hook input refuses the write.
#
# Wired from .claude/settings.json as:
#   bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/guard-write.sh
# Reads the hook JSON on stdin.

set -u

command -v jq >/dev/null 2>&1 || {
  echo "guard-write: refused. jq not found; failing closed." >&2
  exit 2
}

input="$(cat)"

if ! agent="$(printf '%s' "$input" | jq -r '.agent_type // ""')"; then
  echo "guard-write: refused. Hook input is not valid JSON; failing closed." >&2
  exit 2
fi
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')"
root="${CLAUDE_PROJECT_DIR:-$PWD}"

# Nothing to judge without a path.
[ -n "$path" ] || exit 0

case "$path" in
  /*) abs="$path" ;;
  *)  abs="$root/$path" ;;
esac

# Textual prefix match, deliberately: a path that names the repo root and
# then climbs out with ../ is treated as inside, which errs on refusal.
case "$abs" in
  "$root"/lib/*)
    echo "guard-write: refused. Nothing writes under lib/ (CLAUDE.md 8c). Path: $abs" >&2
    exit 2
    ;;
  "$root"/*|"$root")
    if [ "$agent" != "composer" ]; then
      echo "guard-write: refused. Only the composer agent writes inside the repo; caller is '${agent:-main session}'. Path: $abs" >&2
      exit 2
    fi
    ;;
esac

exit 0
