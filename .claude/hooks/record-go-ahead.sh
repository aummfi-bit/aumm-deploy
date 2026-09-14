#!/usr/bin/env bash
# record-go-ahead.sh - Claude Code UserPromptSubmit hook.
#
# Records a go-ahead the user types. When a message the user submits begins
# with one of these phrases, in any letter case, this writes
# .claude/approvals/go-ahead with the scope, the time and the session:
#   clerk commit           the clerk may run git add and git commit
#   clerk push             the clerk may run git push
#   clerk commit and push  the clerk may run all three
#   clerk config           the composer may write .claude/hooks/,
#                          .claude/agents/ and .claude/settings.json
#   terminal run           the terminal agent may run the operations
#                          guard-bash.sh grants it
# guard-bash.sh and guard-write.sh honour the record only while it is under
# 15 minutes old, was written in the same session, and covers the action.
# Any other message the user submits deletes the record, so one go-ahead
# lasts until the next message at most.
#
# Only this hook writes the record: guard-write.sh refuses every Write and
# Edit under .claude/approvals/, guard-bash.sh refuses shell writes, and
# guard-injection.sh refuses the tools that could put a phrase into the
# conversation. Input that carries an agent_id or an agent_type is ignored,
# so a subagent prompt can never open a go-ahead.
#
# Never blocks a prompt: every path exits 0. A missing jq or unparseable
# input records nothing, which leaves everything closed.
#
# Wired from .claude/settings.json as:
#   bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/record-go-ahead.sh
# Reads the hook JSON on stdin.

set -u

root="${CLAUDE_PROJECT_DIR:-$PWD}"
dir="$root/.claude/approvals"
record="$dir/go-ahead"

command -v jq >/dev/null 2>&1 || exit 0
input="$(cat)"
prompt="$(printf '%s' "$input" | jq -r '.prompt // ""' 2>/dev/null)" || exit 0
who="$(printf '%s' "$input" | jq -r '(.agent_id // "") + (.agent_type // "")' 2>/dev/null)" || exit 0
session="$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)" || exit 0
[ -z "$who" ] || exit 0

first="$(printf '%s\n' "$prompt" | /usr/bin/sed -n '1p' | /usr/bin/tr '[:upper:]' '[:lower:]' | /usr/bin/sed -E 's/^[[:space:]]+//')"

scope=""
case "$first" in
  "clerk commit and push"|"clerk commit and push"[!a-z]*) scope="commit+push" ;;
  "clerk commit"|"clerk commit"[!a-z]*) scope="commit" ;;
  "clerk push"|"clerk push"[!a-z]*) scope="push" ;;
  "clerk config"|"clerk config"[!a-z]*) scope="config" ;;
  "terminal run"|"terminal run"[!a-z]*) scope="terminal" ;;
esac

if [ -z "$scope" ] || [ -z "$session" ]; then
  rm -f "$record" 2>/dev/null
  exit 0
fi

mkdir -p "$dir" 2>/dev/null || exit 0
now="$(/bin/date +%s)"
printf 'scope=%s\nepoch=%s\nsession=%s\n' "$scope" "$now" "$session" > "$record" 2>/dev/null || exit 0
echo "Go-ahead recorded from the user's own message: scope $scope, open for this session until the user's next message or 15 minutes."
exit 0
