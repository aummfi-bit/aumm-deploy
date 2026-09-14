#!/usr/bin/env bash
# guard-injection.sh - Claude Code PreToolUse hook on the tools that can put
# text into a conversation as if the user had typed it: scheduled and remote
# prompts, session messages, workflows, agent prompts and every MCP tool.
#
# Refuses a call whose input carries a go-ahead phrase ("clerk commit",
# "clerk push", "clerk config" or "terminal run", in any letter case), so no
# model can open the record that record-go-ahead.sh writes from the user's
# own message. For the Agent tool only a prompt whose first line begins with
# a phrase is refused, because agent prompts legitimately describe the clerk
# and the terminal agent.
#
# Fails open when its input cannot be read. The tools it guards include
# Agent, and record-go-ahead.sh needs the same jq and the same well-formed
# harness input to write anything, so a condition that disables this hook
# also leaves every go-ahead closed.
#
# Wired from .claude/settings.json as:
#   bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/guard-injection.sh
# Reads the hook JSON on stdin.

set -u

G=/usr/bin/grep
S=/usr/bin/sed

refuse() {
  echo "guard-injection: refused. $1" >&2
  exit 2
}

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
tool="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)" || exit 0
[ -n "$tool" ] || exit 0

if [ "$tool" = "Agent" ]; then
  first="$(printf '%s' "$input" | jq -r '.tool_input.prompt // ""' 2>/dev/null | $S -n '1p')"
  if printf '%s' "$first" | $G -Eiq '^[[:space:]]*(clerk[[:space:]]+(commit|push|config)|terminal[[:space:]]+run([^a-z]|$))'; then
    refuse "an agent prompt may not begin with a go-ahead phrase; only a message the user types opens a go-ahead."
  fi
  exit 0
fi

text="$(printf '%s' "$input" | jq -c '.tool_input // {}' 2>/dev/null)" || exit 0
if printf '%s' "$text" | $G -Eiq 'clerk[[:space:]]+(commit|push|config)|terminal[[:space:]]+run([^a-z]|$)'; then
  refuse "$tool input carries a go-ahead phrase; only a message the user types opens a go-ahead."
fi
exit 0
