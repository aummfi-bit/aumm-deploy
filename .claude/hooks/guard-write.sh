#!/usr/bin/env bash
# guard-write.sh - Claude Code PreToolUse hook on Write | Edit | MultiEdit | NotebookEdit.
#
# Rule 1: only the agent named "composer" may write inside this repository.
# Every other caller, the main session included, is refused with exit 2,
# which blocks the tool call and feeds the reason back to the model.
# Writes outside the project directory pass for every caller unless rule 3
# names them, so artifact pages, memory files and scratchpad files keep
# working.
#
# Rule 2, for every caller: nothing writes under lib/, the vendored Balancer,
# OpenZeppelin and forge-std trees (CLAUDE.md section 8c).
#
# Rule 3, for every caller, the composer included:
#   - nothing writes inside any .git/ directory or to a git config file
#     (.gitconfig, .config/git/), because hooks and config there run as code
#     on the next git command, the clerk's included;
#   - nothing writes under .claude/approvals/ or .claude/audit/, where only
#     the record hooks write the go-ahead and the ledgers and the checker's
#     logs arrive by shell redirection;
#   - nothing writes a Claude Code settings file other than this project's
#     committed .claude/settings.json, because a settings.local.json or a
#     user-level settings.json could switch every hook off.
#
# Rule 4: the harness configuration, .claude/hooks/, .claude/agents/ and
# .claude/settings.json, is written only by the composer and only while
# .claude/approvals/go-ahead holds a config go-ahead under 15 minutes old
# that the user typed in this session. Without it the guards could be
# rewritten by the agents they bind.
#
# Paths are compared in lower case, because the macOS filesystem is not case
# sensitive and a differently cased path reaches the same file. A path with a
# . or .. segment or a doubled slash is refused outright.
#
# Fails closed: a missing jq or an unparseable hook input refuses the write.
#
# Wired from .claude/settings.json as:
#   bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/guard-write.sh
# Reads the hook JSON on stdin.

set -u

S=/usr/bin/sed

refuse() {
  echo "guard-write: refused. $1" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || refuse "jq not found; failing closed."

input="$(cat)"

if ! agent="$(printf '%s' "$input" | jq -r '.agent_type // ""')"; then
  refuse "Hook input is not valid JSON; failing closed."
fi
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')"
root="${CLAUDE_PROJECT_DIR:-$PWD}"

# Nothing to judge without a path.
[ -n "$path" ] || exit 0

case "$path" in
  /*) abs="$path" ;;
  *)  abs="$root/$path" ;;
esac

case "$abs" in
  */..|*/../*|*/.|*/./*|*//*)
    refuse "A path with a . or .. segment or a doubled slash cannot be judged. Path: $abs" ;;
esac

lower() { printf '%s' "$1" | /usr/bin/tr '[:upper:]' '[:lower:]'; }
la="$(lower "$abs")"
lr="$(lower "$root")"

config_open() {
  rec="$root/.claude/approvals/go-ahead"
  [ -f "$rec" ] || return 1
  scope="$($S -n 's/^scope=//p' "$rec")"
  epoch="$($S -n 's/^epoch=//p' "$rec")"
  rsess="$($S -n 's/^session=//p' "$rec")"
  isess="$(printf '%s' "$input" | jq -r '.session_id // ""')"
  case "$epoch" in ''|*[!0-9]*) return 1 ;; esac
  [ "$scope" = "config" ] || return 1
  [ -n "$rsess" ] && [ "$rsess" = "$isess" ] || return 1
  age=$(( $(/bin/date +%s) - epoch ))
  [ "$age" -ge 0 ] && [ "$age" -le 900 ] || return 1
  return 0
}

# Rules 3 and 4.
case "$la" in
  */.git|*/.git/*|*/.gitconfig|*/.config/git|*/.config/git/*)
    refuse "Nothing writes inside .git/ or to a git config file; hooks and config there run as code on the next git command. Path: $abs" ;;
  "$lr"/.claude/approvals|"$lr"/.claude/approvals/*|"$lr"/.claude/audit|"$lr"/.claude/audit/*)
    refuse "Only the record hooks write .claude/approvals/ and the ledgers in .claude/audit/; no Write or Edit reaches either. Path: $abs" ;;
  "$lr"/.claude/hooks|"$lr"/.claude/hooks/*|"$lr"/.claude/agents|"$lr"/.claude/agents/*|"$lr"/.claude/settings.json)
    [ "$agent" = "composer" ] || refuse "Only the composer writes harness configuration, and only on a config go-ahead the user types. Path: $abs"
    config_open || refuse "Harness configuration changes only while a config go-ahead is open: the user's own message must begin with 'clerk config'. Path: $abs"
    exit 0 ;;
  */.claude/settings.json|*/.claude/settings.local.json|*/managed-settings.json)
    refuse "Claude Code settings other than this project's .claude/settings.json are the user's; a write there could switch every hook off. Path: $abs" ;;
esac

# Rules 2 and 1.
case "$la" in
  "$lr"/lib/*)
    refuse "Nothing writes under lib/ (CLAUDE.md 8c). Path: $abs" ;;
  "$lr"/*|"$lr")
    if [ "$agent" != "composer" ]; then
      refuse "Only the composer agent writes inside the repo; caller is '${agent:-main session}'. Path: $abs"
    fi
    ;;
esac

exit 0
