#!/usr/bin/env bash
# guard-bash.sh - Claude Code PreToolUse hook on Bash.
#
# Every Bash tool call, from the main session and from every subagent, passes
# through here before it runs. A refusal exits 2, which blocks the call and
# feeds the reason back to the model. Five things are enforced:
#
#   1. For every caller: a command runs only if its name is on the list in
#      judge, and a listed command that can write a file or run a program is
#      held to its read-only form. No git mutation, network, file mutation
#      through the shell or script run outside rules 4 and 5; no install and
#      no broadcast; no escape hatch that could hide one (eval, xargs, find
#      -exec, backticks, a shell running a script, a nested claude session,
#      a command name the shell would expand, an environment variable that
#      changes what a tool runs); and no read of a .env file other than
#      .env.example or of key material.
#      Git mutations, dependency bumps, deletes and broadcasts belong to the
#      user (CLAUDE.md 8b, 8c); file content belongs to the composer agent
#      through Write and Edit, which guard-write.sh polices.
#   2. Role gates: forge build, test, lint, clean, snapshot, coverage,
#      script, fmt --check, slither and hevm run only from the agent named
#      "checker", and never with FFI, another project root or config, or an
#      output path of their own; every other caller is read-only. Output
#      redirection is refused except to /dev/*, and for the checker also
#      into .claude/audit/ or a claude scratchpad, never through a . or ..
#      segment or a doubled slash and never onto an audit ledger.
#   3. Fork runs: a forge test with --fork-url must name the mainnet alias,
#      carry a literal --match-path with no glob, and --threads 1 (D35, D36,
#      RB-023). Any forge --rpc-url is refused; forge runs against a node
#      are the user's.
#   4. The clerk: git add, git commit and git push run only from the agent
#      named "clerk", only as git -C with this repository's literal path,
#      only while .claude/approvals/go-ahead holds a go-ahead the user typed
#      in this session, under 15 minutes old, that covers the verb, and only
#      in the forms clerk_add, clerk_commit and clerk_push accept.
#      record-go-ahead.sh writes that record; guard-write.sh refuses every
#      other writer.
#   5. The terminal: the agent named "terminal" runs only the commands
#      terminal_judge lists, reads only inside this repository, and runs
#      four operations no other caller may, each only while
#      .claude/approvals/go-ahead holds a terminal go-ahead the user typed in
#      this session, under 15 minutes old: the working .env swap and its
#      cmp -s check, a tracked tools/<name>.py generator that takes no
#      arguments, run as python3 -I -S from a clean tools/ tree, the
#      aumm-site pull --ff-only, and a cast chain read through the sepolia
#      or mainnet alias. It names every command bare and passes no double
#      quote, backslash, expansion, glob, tilde, comment, heredoc, background
#      job or environment assignment.
#
# The body of a quoted heredoc is data, not commands, but only where the
# shell is certain to open one; see heredoc_opener. That is what lets a
# payload be measured through a pipeline before handoff (PB18) and a commit
# message reach git untouched. Every other line is judged. Inside a quoted
# string the separators ; | & ( ) { } are masked before a line is split into
# commands, but only where the quoting is certain; see mask_quoted.
#
# Unknown commands are refused for every caller: the list in judge is the
# whole of what runs. Refusals err toward refusing: a mutating verb inside a
# quoted string still refuses, and the caller rephrases. Fails closed on a
# missing jq or unparseable input. Tools are pinned to /usr/bin so a
# caller's PATH cannot change how a pattern is read.
#
# Wired from .claude/settings.json as:
#   bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/guard-bash.sh
# Reads the hook JSON on stdin.

set -u
set -f

G=/usr/bin/grep
S=/usr/bin/sed
T=/usr/bin/tr

refuse() {
  echo "guard-bash: refused. $1" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || refuse "jq not found; failing closed."

input="$(cat)"
if ! agent="$(printf '%s' "$input" | jq -r '.agent_type // ""')"; then
  refuse "hook input is not valid JSON; failing closed."
fi
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
root="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -n "$cmd" ] || exit 0

# A control character other than tab and newline has no place in a command,
# and the masking below uses the first seven for its own marks.
printf '%s' "$cmd" | $T -d '\t\n' | $G -q '[[:cntrl:]]' && refuse "a control character in the command cannot be judged."

checker=0
[ "$agent" = "checker" ] && checker=1
terminal=0
[ "$agent" = "terminal" ] && terminal=1
icwd="$(printf '%s' "$input" | jq -r '.cwd // ""')"

lower() { printf '%s' "$1" | $T '[:upper:]' '[:lower:]'; }

# A textual <<'NAME' that the shell reads as a comment, a here-string or
# quoted text opens no heredoc, and stripping after it would hide the lines
# that follow from every rule. So a line opens a heredoc here only when it
# ends with <<'NAME' or <<"NAME"; carries no other <<, no <<<, no # and no
# backslash; has balanced quotes before the operator, counted from the last
# $( that sits outside single quotes; and no kept line before it carries #
# or a backslash or leaves a quote open. The body runs to the first line
# that equals NAME after leading whitespace. The opening line itself is
# always kept and judged, so the consumer of the heredoc is seen.
quotes_even() {
  dq="$(printf '%s' "$1" | $T -cd '"' | /usr/bin/wc -c | $T -d ' ')"
  sq="$(printf '%s' "$1" | $T -cd "'" | /usr/bin/wc -c | $T -d ' ')"
  [ $((dq % 2)) -eq 0 ] && [ $((sq % 2)) -eq 0 ]
}

singles_even() {
  sq="$(printf '%s' "$1" | $T -cd "'" | /usr/bin/wc -c | $T -d ' ')"
  [ $((sq % 2)) -eq 0 ]
}

heredoc_opener() {
  opened=""
  case "$1" in *'<<<'*|*'#'*|*'\'*) return 1 ;; esac
  case "$2" in *'#'*|*'\'*) return 1 ;; esac
  d="$(printf '%s' "$1" | $S -En "s/^(.*[^<])?<<['\"]([A-Za-z_][A-Za-z0-9_]*)['\"][[:space:]]*\$/\2/p")"
  [ -n "$d" ] || return 1
  head="${1%<<*}"
  case "$head" in *'<<'*) return 1 ;; esac
  quotes_even "$2" || return 1
  case "$head" in
    *'$('*)
      singles_even "${head%'$('*}" || return 1
      quotes_even "${head##*'$('}" || return 1 ;;
    *)
      quotes_even "$head" || return 1 ;;
  esac
  opened="$d"
  return 0
}

strip_quoted_heredocs() {
  delim=""
  prior=""
  printf '%s\n' "$cmd" | while IFS= read -r line; do
    if [ -n "$delim" ]; then
      bare="${line#"${line%%[![:space:]]*}"}"
      [ "$bare" = "$delim" ] && delim=""
      continue
    fi
    printf '%s\n' "$line"
    if heredoc_opener "$line" "$prior"; then
      delim="$opened"
    fi
    prior="$prior$line "
  done
}
judged="$(strip_quoted_heredocs)"

# The shell reads ; | & ( ) { } inside a quoted string as text, so masking
# them there keeps a quoted jq filter or grep pattern in one command. The
# mask applies only where the quoting is certain: a single-quoted string,
# unless it is a $'...' string carrying a backslash, and a double-quoted
# string with no $, backtick or backslash in it. Any other backslash, a #
# outside quotes, or a quote left open, and the line is split unmasked, so
# a doubt costs a refusal rather than a hidden command. Each separator is
# masked to its own control character, 1 through 7, and a blank inside the
# quotes to 8, so a quoted argument survives the whitespace split below as
# ONE word, the way the shell hands it to the program, and a rule that
# needs the text as written (check_sed) can unmask it exactly; the command
# was refused above if it carried any control character of its own.
mask_quoted() {
  printf '%s' "$1" | /usr/bin/awk '
    BEGIN { q = ""; ansi = 0; bad = 0; out = ""; prev = ""; seps = ";|&(){}" }
    {
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (q == "s") {
          if (c == "\047") { q = "" }
          else if (c == "\\" && ansi) { bad = 1 }
          else if ((k = index(seps, c)) > 0) { c = sprintf("%c", k) }
          else if (c == " " || c == "\t") { c = sprintf("%c", 8) }
        } else if (q == "d") {
          if (c == "\"") { q = "" }
          else if (c == "$" || c == "`" || c == "\\") { bad = 1 }
          else if ((k = index(seps, c)) > 0) { c = sprintf("%c", k) }
          else if (c == " " || c == "\t") { c = sprintf("%c", 8) }
        } else {
          if (c == "\047") { q = "s"; ansi = (prev == "$") }
          else if (c == "\"") { q = "d" }
          else if (c == "\\" || c == "#") { bad = 1 }
        }
        out = out c
        prev = c
      }
      out = out "\n"
      prev = "\n"
    }
    END { if (bad || q != "") exit 1; printf "%s", out }
  '
}
masked="$(mask_quoted "$judged")" || masked="$judged"

# A descriptor duplication such as 2>&1 and the &> redirection carry an &
# that is not a separator, so it must not split the command. A >& onto a
# file name keeps its &, and the name is then judged as a command and
# refused, besides the redirection rule refusing it. zsh's >| and >!
# clobber operators become a plain > so the target stays attached to the
# redirect through the split rather than becoming its own command.
masked="$(printf '%s\n' "$masked" | $S -E 's/[0-9]*>&([0-9]|-)([^0-9A-Za-z_./-]|$)/ \2/g; s/&>>/ >>/g; s/&>/ >/g; s/>[|!]/ > /g')"

# The content checks below run on both the command as written and a copy
# with every quote and backslash removed. zsh strips those before a tool
# sees its argument, so a substring like .env or -delete split by an
# interior quote (cat .e'nv', find . '-delete') would evade a check that
# read only the raw text. Removing them can only join text, never hide a
# separator, so a doubt costs a refusal, never a miss.
nq="$(printf '%s' "$judged" | $T -d "\"'\\\\")"
both="$(printf '%s\n%s' "$judged" "$nq")"

has() { printf '%s' "$both" | $G -Eq -e "$1"; }
seghas() { printf '%s' "$2" | $G -Eq -e "$1"; }
unquote() { printf '%s' "$1" | $T -d "\"'"; }
unmask() { printf '%s' "$1" | $T '\001\002\003\004\005\006\007\010' ';|&(){} '; }

# ---- the terminal's go-ahead and working directory ----

go_ahead() {
  rec="$root/.claude/approvals/go-ahead"
  [ -f "$rec" ] || refuse "no open go-ahead to $1. A message the user types must begin with 'terminal run'."
  gscope="$($S -n 's/^scope=//p' "$rec")"
  gepoch="$($S -n 's/^epoch=//p' "$rec")"
  gsess="$($S -n 's/^session=//p' "$rec")"
  gisess="$(printf '%s' "$input" | jq -r '.session_id // ""')"
  case "$gepoch" in ''|*[!0-9]*) refuse "the go-ahead record is unreadable; failing closed." ;; esac
  [ -n "$gsess" ] && [ "$gsess" = "$gisess" ] || refuse "the go-ahead was given in a different session; the user must give it in this one."
  gage=$(( $(/bin/date +%s) - gepoch ))
  [ "$gage" -ge 0 ] || refuse "the go-ahead record is dated in the future; failing closed."
  [ "$gage" -le 900 ] || refuse "the go-ahead is older than 15 minutes; the user must give it again."
  [ "$gscope" = "terminal" ] || refuse "the open go-ahead covers '$gscope', not the terminal's operations. A message the user types must begin with 'terminal run'."
}

root_cwd() {
  [ -n "$icwd" ] && [ "$(lower "$icwd")" = "$(lower "$root")" ] || refuse "the terminal runs $1 from the repository root; the working directory is '${icwd:-unknown}'."
}

# ---- whole-command rules, every caller ----

has '--broadcast' && refuse "--broadcast never leaves an agent; live broadcasts are the user's (CLAUDE.md 8c)."
has '`' && refuse "backtick substitution; use \$( ) where a substitution is needed."
has '>\(' && refuse "process substitution as an output target."
has '\|[[:space:]]*\\?"' && refuse "a pipe into a quoted command name."
has 'system\(|getline' && refuse "awk system() or getline runs a command."
has '(^|[^A-Za-z0-9_./-])(eval|xargs|parallel|source|alias|trap|fc|enable)([^A-Za-z0-9_-]|$)' && refuse "eval, xargs, parallel, source, alias, trap, fc and enable are escape hatches; none runs from an agent."
has '[[:space:]]-(exec|execdir|ok|okdir|delete|fprint|fprint0|fprintf|fls)([^A-Za-z0-9_-]|$)' && refuse "find -exec, -ok, -delete and -fprint run or write; list instead."
has '\.ssh/|\.aws/|\.gnupg/|\.netrc|\.npmrc|\.pypirc|keystores?/|id_(rsa|ed25519|ecdsa)|\.config/gh/|\.git-credentials|\.config/git/credentials|\.docker/config\.json|Keychains/|\.claude/\.credentials' && refuse "key material is never read from an agent."

envswap=0
if [ "$terminal" -eq 1 ]; then
  case "$cmd" in *'<<'*) refuse "the terminal passes no heredoc or here-string." ;; esac
  case "$cmd" in *'"'*|*'\'*) refuse "the terminal passes no double quote or backslash; quote with single quotes." ;; esac
  bare="$(printf '%s' "$judged" | $S -E "s/'[^']*'//g")"
  printf '%s' "$bare" | $G -Eq -e '[$~*?#]' -e '\[' -e '\]' && refuse "the terminal passes no expansion, tilde, glob or comment outside single quotes; name every file exactly."
  printf '%s' "$bare" | $G -Eq -e '(^|[^&])&([^&]|$)' && refuse "the terminal runs nothing in the background and duplicates no descriptor."
  case "$judged" in
    'cp .env.mainnet .env'|'cp .env.sepolia .env'|'cmp -s .env.mainnet .env'|'cmp -s .env.sepolia .env')
      go_ahead "swap or check the working .env"
      root_cwd "the env swap"
      envswap=1 ;;
  esac
fi

if [ "$envswap" -eq 0 ]; then
  stripped="$(printf '%s' "$both" | $S 's/\.env\.example//g')"
  printf '%s' "$stripped" | $G -Eq -e '\.env(\.|[^A-Za-z0-9_.]|$)' && refuse "reading a .env file; only .env.example is readable (PB-D36, PP2)."
fi

targets="$(printf '%s' "$judged" | $G -Eo -e '(&>>|&>|>>|>&|>\||>!|>)[[:space:]]*[^[:space:];&|()]+' || true)"
if [ -n "$targets" ]; then
  while IFS= read -r t; do
    op="$(printf '%s' "$t" | $S -En 's/^(&>>|&>|>>|>&|>\||>!|>).*/\1/p')"
    t="$(printf '%s' "$t" | $S -E 's/^(&>>|&>|>>|>&|>\||>!|>)[[:space:]]*//')"
    t="$(unquote "$t")"
    [ -n "$t" ] || continue
    if [ "$op" = ">&" ]; then
      case "$t" in [0-9]|-) continue ;; esac
    fi
    case "$t" in
      /dev/null|/dev/stdout|/dev/stderr|/dev/fd/*) continue ;;
    esac
    case "$t" in
      ..|../*|*/..|*/../*|*/.|*/./*|*//*) refuse "output redirection to '$t' goes through a . or .. segment or a doubled slash." ;;
    esac
    case "$(lower "$t")" in
      *ledger.log) refuse "output redirection to '$t' would overwrite an audit ledger, which only the record hooks write." ;;
    esac
    if [ "$checker" -eq 1 ]; then
      case "$t" in
        .claude/audit/*|./.claude/audit/*|"$root"/.claude/audit/*|/private/tmp/claude-*|/tmp/claude-*) continue ;;
      esac
    fi
    refuse "output redirection to '$t'. Only /dev/* is a target, plus .claude/audit/ and a claude scratchpad for the checker; files are written by the composer through Write and Edit."
  done <<< "$targets"
fi

# ---- the clerk: git add, commit and push on a go-ahead the user typed ----

clerk_approval() {
  rec="$root/.claude/approvals/go-ahead"
  [ -f "$rec" ] || refuse "no open go-ahead for the clerk. A message the user types must begin with 'clerk commit', 'clerk push' or 'clerk commit and push'."
  scope="$($S -n 's/^scope=//p' "$rec")"
  epoch="$($S -n 's/^epoch=//p' "$rec")"
  rsess="$($S -n 's/^session=//p' "$rec")"
  isess="$(printf '%s' "$input" | jq -r '.session_id // ""')"
  case "$epoch" in ''|*[!0-9]*) refuse "the go-ahead record is unreadable; failing closed." ;; esac
  [ -n "$rsess" ] && [ "$rsess" = "$isess" ] || refuse "the go-ahead was given in a different session; the user must give it in this one."
  now="$(/bin/date +%s)"
  age=$((now - epoch))
  [ "$age" -ge 0 ] || refuse "the go-ahead record is dated in the future; failing closed."
  [ "$age" -le 900 ] || refuse "the go-ahead is older than 15 minutes; the user must give it again."
  case "$1:$scope" in
    add:commit|add:commit+push|commit:commit|commit:commit+push|push:push|push:commit+push) return 0 ;;
  esac
  refuse "the open go-ahead covers '$scope', not git $1."
}

clerk_path() {
  case "$1" in
    ''|.|./|/*|*'*'*|*'?'*|*'['*|:*|..|../*|*/..|*/../*|*/./*|*//*)
      refuse "git path '$1': the clerk names repository-relative files, never a glob, an absolute path, the whole tree, a . or .. segment or a doubled slash." ;;
  esac
  case "$(lower "$1")" in
    lib|lib/*|./lib|./lib/*|.git|.git/*|./.git|./.git/*|.claude/approvals|.claude/approvals/*|./.claude/approvals|./.claude/approvals/*)
      refuse "git path '$1' is under lib/, .git/ or .claude/approvals/; the clerk never stages those." ;;
  esac
}

clerk_add() {
  n=0
  for a in "$@"; do
    case "$a" in
      --) ;;
      -*) refuse "git add $a is not allowed for the clerk; it stages named paths only." ;;
      *) clerk_path "$a"; n=$((n + 1)) ;;
    esac
  done
  [ "$n" -gt 0 ] || refuse "git add needs at least one named path."
}

clerk_commit() {
  only=0
  file=0
  n=0
  for a in "$@"; do
    case "$a" in
      --only|-o) only=1 ;;
      -F|--file=-) file=1 ;;
      -|--|'<<'*) ;;
      -*) refuse "git commit $a is not allowed for the clerk; it commits with --only <paths> -F - and a quoted heredoc message." ;;
      *) clerk_path "$a"; n=$((n + 1)) ;;
    esac
  done
  [ "$only" -eq 1 ] || refuse "the clerk commits with --only <paths>, never the whole index."
  [ "$file" -eq 1 ] || refuse "the clerk passes the message with -F - from a quoted heredoc, never -m."
  [ "$n" -gt 0 ] || refuse "git commit --only needs at least one named path."
}

clerk_push() {
  pos=""
  for a in "$@"; do
    case "$a" in
      -*) refuse "git push $a is not allowed for the clerk; it pushes the current branch to its upstream with no options." ;;
      *:*|+*) refuse "git push $a: the clerk uses no refspecs." ;;
      *) pos="$pos $a" ;;
    esac
  done
  br="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  up="$(git -C "$root" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"
  case "$br" in
    ''|HEAD|main|master) refuse "the clerk never pushes from '${br:-an unknown branch}' (CLAUDE.md 8c)." ;;
  esac
  [ "$up" = "origin/$br" ] || refuse "branch $br does not track origin/$br; creating or retargeting a remote branch is the user's (CLAUDE.md 8c)."
  case "$pos" in
    ''|' origin'|" origin $br") return 0 ;;
  esac
  refuse "git push$pos: the clerk pushes only $br to origin."
}

# ---- per-command rules on each simple command of a compound line ----

check_git_listflags() {
  what="$1"; shift
  prev=""
  for a in "$@"; do
    case "$a" in
      -a|-r|-l|-v|-vv|-av|-avv|-rv|-n|--list|--show-current|--merged|--no-merged|--contains|--no-contains|--points-at|--format=*|--sort=*|--color|--color=*|--no-color|--column|--no-column) ;;
      -*) refuse "git $what $a mutates a ref or is not a listing flag." ;;
      *) case "$prev" in
           --contains|--no-contains|--merged|--no-merged|--points-at|-l|--list) ;;
           *) refuse "git $what with a bare name creates or targets a ref; only listing runs from an agent." ;;
         esac ;;
    esac
    prev="$a"
  done
  return 0
}

check_git() {
  cdir=""
  cn=0
  gdir=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -c|--config-env|--config-env=*|--exec-path|--exec-path=*)
        refuse "git $1 can redefine what a verb does; not from an agent." ;;
      -C)
        [ $# -ge 2 ] || refuse "git -C without a value."
        cdir="$(unquote "$2")"
        cn=$((cn + 1))
        shift 2 ;;
      --git-dir|--work-tree|--namespace)
        [ $# -ge 2 ] || refuse "git $1 without a value."
        gdir=1
        shift 2 ;;
      --git-dir=*|--work-tree=*|--namespace=*)
        gdir=1
        shift ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || return 0
  verb="$(unquote "$1")"; shift
  case "$verb" in
    *'$'*|*'{'*|*'\'*) refuse "git verb '$verb' cannot be judged statically." ;;
  esac
  for a in "$@"; do
    case "$a" in
      --output*) refuse "git --output writes a file." ;;
      --open-files-in-pager*|-O*) [ "$verb" = "grep" ] && refuse "git grep -O runs a pager program." ;;
    esac
  done
  if [ "$verb" = "pull" ] && [ "$terminal" -eq 1 ] && [ "$gdir" -eq 0 ] && [ "$cn" -eq 1 ] \
    && [ "$(lower "$cdir")" = "/users/janus/code/aumm-site" ] && [ $# -eq 1 ] && [ "$1" = "--ff-only" ]; then
    go_ahead "pull the aumm-site spec clone"
    return 0
  fi
  if [ "$terminal" -eq 1 ]; then
    [ "$gdir" -eq 0 ] && [ "$cn" -le 1 ] || refuse "the terminal passes no --git-dir, --work-tree, --namespace or second -C."
    case " $* " in *' --no-index '*) refuse "the terminal reads through git only inside a repository." ;; esac
    if [ "$cn" -eq 0 ]; then
      root_cwd "a git read"
    else
      case "$(lower "$cdir")" in
        "$(lower "$root")"|/users/janus/code/aumm-site) ;;
        *) refuse "the terminal runs git only in this repository or the aumm-site clone; got -C '$cdir'." ;;
      esac
    fi
  fi
  case "$verb" in
    add|commit|push)
      [ "$agent" = "clerk" ] || refuse "git $verb runs only from the clerk agent, on a go-ahead the user types; otherwise git mutations are the user's (CLAUDE.md 8b)."
      [ "$gdir" -eq 0 ] || refuse "the clerk never passes --git-dir, --work-tree or --namespace."
      [ "$cn" -eq 1 ] && [ "$(lower "$cdir")" = "$(lower "$root")" ] || refuse "the clerk names this repository exactly once: git -C $root $verb."
      clerk_approval "$verb"
      case "$verb" in
        add) clerk_add "$@" ;;
        commit) clerk_commit "$@" ;;
        push) clerk_push "$@" ;;
      esac
      return 0 ;;
  esac
  case "$verb" in
    status|log|diff|show|ls-files|ls-tree|cat-file|rev-parse|rev-list|describe|blame|grep|shortlog|check-ignore|check-attr|check-ref-format|name-rev|merge-base|count-objects|var|version|help|for-each-ref|diff-tree|diff-index|diff-files|show-ref|verify-commit|verify-tag|whatchanged|cherry|range-diff|show-branch)
      return 0 ;;
    branch) check_git_listflags branch "$@" ;;
    tag) check_git_listflags tag "$@" ;;
    remote) case "${1:-}" in ""|-v|--verbose|show|get-url) return 0 ;; *) refuse "git remote ${1:-} mutates; only listing runs from an agent." ;; esac ;;
    worktree) [ "${1:-}" = "list" ] || refuse "git worktree ${1:-}; only list runs from an agent." ;;
    stash) case "${1:-}" in list|show) return 0 ;; *) refuse "git stash mutates; only list and show run from an agent." ;; esac ;;
    submodule) [ "${1:-}" = "status" ] || refuse "git submodule ${1:-} touches lib/; only status runs from an agent (CLAUDE.md 8c)." ;;
    config) case "${1:-}" in --get|--get-all|--get-regexp|-l|--list) return 0 ;; *) refuse "git config writes; only --get, --get-all, --get-regexp and --list run from an agent." ;; esac ;;
    reflog) case "${1:-}" in ""|show) return 0 ;; *) refuse "git reflog ${1:-} mutates." ;; esac ;;
    *) refuse "git $verb mutates the repository or is not a known read; git mutations run in the user's terminal or through the clerk (CLAUDE.md 8b)." ;;
  esac
}

check_forge() {
  for a in "$@"; do
    case "$a" in
      --ffi|--root|--root=*|-C|--config-path|--config-path=*|--report-file|--report-file=*|--build-info-path|--build-info-path=*|-o|--out|--out=*)
        refuse "forge $a enables FFI, points forge at another project or config, or writes output where told; the checker runs forge on this project with its own paths." ;;
    esac
  done
  sub=""
  for a in "$@"; do case "$a" in -*|'>'*|'<'*|[0-9]'>'*|[0-9]'<'*) ;; *) sub="$(unquote "$a")"; break ;; esac; done
  [ -n "$sub" ] || return 0
  all="$*"
  case "$sub" in
    config|tree|remappings|inspect|eip712|help) return 0 ;;
    selectors)
      case " $all " in *' upload '*) refuse "forge selectors upload publishes to a remote service; that is the user's." ;; esac
      return 0 ;;
    install|update|remove|clone|init|create|verify-contract|verify-check|verify-bytecode|soldeer|cache|bind|doc|debug|generate|generate-fig-spec|completions)
      refuse "forge $sub installs, deploys, verifies or writes outside build products; that is the user's (CLAUDE.md 8b, 8c)." ;;
    build|test|lint|clean|snapshot|coverage|script|fmt|flatten|compiler|geiger)
      [ "$checker" -eq 1 ] || refuse "forge $sub runs only from the checker agent; other callers read results, never produce them." ;;
    *) refuse "forge $sub is not a subcommand this hook knows." ;;
  esac
  for a in "$@"; do
    case "$a" in
      --rpc-url|--rpc-url=*|--rpc|-r|--verify|--resume|--etherscan-api-key|--etherscan-api-key=*|-e|--fix)
        refuse "forge $sub $a reaches a node or an explorer, or rewrites sources; that is the user's." ;;
    esac
  done
  case "$sub" in
    fmt) seghas '(^|[[:space:]])--check([[:space:]]|$)' "$all" || refuse "forge fmt rewrites sources; only forge fmt --check runs from an agent." ;;
    snapshot) seghas '(^|[[:space:]])--(check|diff)([[:space:]]|$)' "$all" || refuse "forge snapshot writes .gas-snapshot; only --check or --diff runs from an agent." ;;
    flatten) for a in "$@"; do case "$a" in -o|--output|--output=*) refuse "forge flatten -o writes a file." ;; esac; done ;;
    script) for a in "$@"; do case "$a" in --fork-url|--fork-url=*|-f) refuse "forge script against a node is the user's." ;; esac; done ;;
    test)
      if seghas '(^|[[:space:]])(--fork-url|-f)([[:space:]=]|$)' "$all"; then
        seghas '(^|[[:space:]])-f([[:space:]]|$)' "$all" && refuse "use --fork-url, not -f, so the alias is checkable."
        seghas '(^|[[:space:]])--fork-url[[:space:]=]+mainnet([[:space:]]|$)' "$all" || refuse "forge test --fork-url must name the mainnet alias; a Sepolia fork needs the .env swap and is the user's (PB-D59)."
        mp="$(printf '%s' "$all" | $S -En 's/.*--match-path[[:space:]=]+([^[:space:]]+).*/\1/p')"
        [ -n "$mp" ] || refuse "a fork run needs a literal --match-path (D35)."
        case "$mp" in *'*'*|*'?'*) refuse "a fork run is file-scoped; --match-path $mp is a glob (D36, CLAUDE.md 11)." ;; esac
        seghas '(^|[[:space:]])--threads[[:space:]=]+1([[:space:]]|$)' "$all" || refuse "a fork run needs --threads 1 (D36, PB-D13)."
      fi ;;
  esac
  return 0
}

check_slither() {
  for a in "$@"; do
    case "$a" in
      --json|--json=*|--sarif|--sarif=*|--zip|--zip=*|--solc|--solc=*|--solc-args|--solc-args=*|--config-file|--config-file=*|--crytic-args|--crytic-args=*|--foundry-out-directory|--foundry-out-directory=*)
        refuse "slither $a writes where told, runs a named compiler or takes compiler arguments; the checker keeps slither output in its own log." ;;
    esac
  done
  return 0
}

check_hevm() {
  for a in "$@"; do
    case "$a" in
      --ffi|--rpc|--rpc=*|--root|--root=*)
        refuse "hevm $a enables FFI, reaches a node or points hevm at another project; the checker runs hevm on this project." ;;
    esac
  done
  return 0
}

check_cast() {
  sub=""
  for a in "$@"; do case "$a" in -*|'>'*|'<'*|[0-9]'>'*|[0-9]'<'*) ;; *) sub="$(unquote "$a")"; break ;; esac; done
  [ -n "$sub" ] || return 0
  case "$sub" in
    to-check-sum-address|to-checksum-address|keccak|sig|sig-event|abi-encode|abi-decode|calldata|calldata-decode|to-hex|to-dec|to-wei|from-wei|to-unit|to-bytes32|to-uint256|to-int256|to-ascii|to-utf8|from-utf8|concat-hex|compute-address|create2|namehash|selectors|disassemble|format-bytes32-string|parse-bytes32-string|parse-bytes32-address|max-uint|max-int|min-int|address-zero|hash-zero|shl|shr|to-rlp|from-rlp|pretty-calldata|decode-abi|encode-abi|help)
      return 0 ;;
  esac
  if [ "$terminal" -eq 1 ]; then
    case "$sub" in
      call|code|codesize|codehash|nonce|balance|receipt|tx|block|block-number|storage|logs|chain-id|gas-price|basefee|age|find-block|implementation|admin)
        go_ahead "read chain state"
        root_cwd "a cast chain read"
        terminal_cast "$sub" "$@"
        return 0 ;;
    esac
  fi
  refuse "cast $sub reaches a node, a key or a signature service; only offline cast utilities run from an agent, and chain reads only from the terminal agent on a go-ahead."
}

check_shell() {
  sh="$1"; shift
  if [ "$sh" = "bash" ] && [ $# -ge 1 ] && [ "$1" = "-n" ]; then
    [ $# -eq 1 ] && return 0
    if [ $# -eq 2 ]; then
      case "$2" in -*) ;; *) return 0 ;; esac
    fi
  fi
  refuse "$sh would run a script or an inline command; agents do not spawn shells. Only 'bash -n' or 'bash -n <file>' as a syntax check runs from an agent."
}

# A sed script is read by a small parser rather than matched by a pattern,
# because the write, read and execute commands (w, W, r, R, e, and the w
# and e flags of s) can follow any address, any delimiter, a ; or a {, and
# a regex cannot tell a w in command position from a w inside an s///
# body. The parser walks addresses (numeric, $, /regex/, \cregexc, with ~
# steps and ! negation), s and y with any delimiter and escaped delimiters,
# blocks, comments, labels, and the text commands a, i and c, and exits 1
# on a file or execute command or on anything it does not recognise. It
# receives the script as written, unmasked and unquoted.
sed_script_ok() {
  printf '%s' "$1" | /usr/bin/awk '
function fail() { exit 1 }
function bracket(i,   c) {
  i++
  if (substr(s, i, 1) == "^") i++
  if (substr(s, i, 1) == "]") i++
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "]") return i + 1
    if (c == "[" && substr(s, i + 1, 1) == ":") {
      i += 2
      while (i <= n && !(substr(s, i, 1) == ":" && substr(s, i + 1, 1) == "]")) i++
      i += 2
      continue
    }
    i++
  }
  fail()
}
function skipto(i, d, rx,   c) {
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\\") { i += 2; continue }
    if (c == d) return i + 1
    if (rx && c == "[") { i = bracket(i); continue }
    i++
  }
  fail()
}
function addr(i,   c, d) {
  c = substr(s, i, 1)
  if (c ~ /[0-9]/) {
    while (substr(s, i, 1) ~ /[0-9]/) i++
    if (substr(s, i, 1) == "~") { i++; while (substr(s, i, 1) ~ /[0-9]/) i++ }
    return i
  }
  if (c == "$") return i + 1
  if (c == "/") { i = skipto(i + 1, "/", 1) }
  else if (c == "\\") { d = substr(s, i + 1, 1); i = skipto(i + 2, d, 1) }
  else return i
  while (substr(s, i, 1) ~ /[IM]/) i++
  return i
}
{ s = s $0 "\n" }
END {
  n = length(s); i = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == " " || c == "\t" || c == "\n" || c == ";" || c == "}") { i++; continue }
    if (c == "#") { while (i <= n && substr(s, i, 1) != "\n") i++; continue }
    i = addr(i)
    while (substr(s, i, 1) == " ") i++
    if (substr(s, i, 1) == ",") {
      i++
      while (substr(s, i, 1) == " ") i++
      if (substr(s, i, 1) == "+" || substr(s, i, 1) == "~") i++
      i = addr(i)
    }
    while (substr(s, i, 1) == " " || substr(s, i, 1) == "!") i++
    c = substr(s, i, 1)
    if (c == "") break
    if (c == "{") { i++; continue }
    if (c == "w" || c == "W" || c == "r" || c == "R" || c == "e" || c == "v") fail()
    if (c == "s") {
      d = substr(s, i + 1, 1)
      if (d == "" || d == "\n" || d == "\\") fail()
      i = skipto(i + 2, d, 1)
      i = skipto(i, d, 0)
      while (i <= n) {
        c = substr(s, i, 1)
        if (c ~ /[gpiImM0-9]/) { i++; continue }
        if (c == "w" || c == "W" || c == "e") fail()
        break
      }
      continue
    }
    if (c == "y") {
      d = substr(s, i + 1, 1)
      if (d == "" || d == "\n" || d == "\\") fail()
      i = skipto(i + 2, d, 0)
      i = skipto(i, d, 0)
      continue
    }
    if (c == "a" || c == "i" || c == "c") {
      i++
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\") { i += 2; continue }
        if (c == "\n") { i++; break }
        i++
      }
      continue
    }
    if (c == "b" || c == "t" || c == "T" || c == ":") {
      i++
      while (i <= n && substr(s, i, 1) != "\n" && substr(s, i, 1) != ";") i++
      continue
    }
    if (c == "q" || c == "Q" || c == "l" || c == "L") {
      i++
      while (substr(s, i, 1) ~ /[0-9 ]/) i++
      continue
    }
    if (c ~ /[=dDgGhHnNpPxzF]/) { i++; continue }
    fail()
  }
  exit 0
}
'
}

check_sed() {
  hasexpr=0
  for a in "$@"; do
    case "$a" in -e|--expression|--expression=*|-e?*) hasexpr=1 ;; esac
  done
  skipval=0
  first=1
  for a in "$@"; do
    if [ "$skipval" -eq 1 ]; then
      skipval=0
      sed_script_ok "$(unmask "$(unquote "$a")")" || refuse "the sed script '$a' writes a file, reads one, runs a program, or is not a form this hook reads; sed reads and prints only."
      continue
    fi
    case "$a" in
      --in-place*|-[!-]*[iI]*) refuse "sed $a rewrites a file in place." ;;
      --file|--file=*|-f|-[!-]*f*) refuse "sed $a reads its commands from a file this hook cannot see; pass them with -e or as an argument." ;;
      -e|--expression) skipval=1 ;;
      -e?*) sed_script_ok "$(unmask "$(unquote "${a#-e}")")" || refuse "the sed script '$a' writes a file, reads one, runs a program, or is not a form this hook reads; sed reads and prints only." ;;
      --expression=*) sed_script_ok "$(unmask "$(unquote "${a#--expression=}")")" || refuse "the sed script '$a' writes a file, reads one, runs a program, or is not a form this hook reads; sed reads and prints only." ;;
      --) ;;
      -*) ;;
      *)
        # Without -e the first bare operand is the script and the rest are input files.
        if [ "$hasexpr" -eq 0 ] && [ "$first" -eq 1 ]; then
          first=0
          sed_script_ok "$(unmask "$(unquote "$a")")" || refuse "the sed script '$a' writes a file, reads one, runs a program, or is not a form this hook reads; sed reads and prints only."
        else
          # A file operand that is itself a sed file or execute command letter can only be
          # a script fragment the split tore off; the masking above keeps quoted blanks in
          # one word, so this is a second lock on the same door.
          case "$(unmask "$(unquote "$a")")" in
            w|W|r|R|e) refuse "sed operand '$a' is a file or execute command letter standing alone; sed reads and prints only." ;;
          esac
        fi ;;
    esac
  done
  return 0
}

check_sort() {
  for a in "$@"; do
    case "$a" in
      --output|--output=*|--compress-program|--compress-program=*|--files0-from|--files0-from=*|--random-source|--random-source=*|--temporary-directory|--temporary-directory=*)
        refuse "sort $a writes a file, runs a program or reads a file list; sort reads and prints only." ;;
      --*) ;;
      -*[oT]*) refuse "sort $a writes a file or a temporary directory where told; sort reads and prints only." ;;
    esac
  done
  return 0
}

check_uniq() {
  n=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --) shift; n=$((n + $#)); break ;;
      -f|-s) [ $# -ge 2 ] && shift ;;
      -*) ;;
      *) n=$((n + 1)) ;;
    esac
    shift
  done
  [ "$n" -le 1 ] || refuse "uniq with a second file operand writes to it; uniq reads one input and prints."
  return 0
}

check_file() {
  for a in "$@"; do
    case "$a" in
      --compile*) refuse "file --compile writes a magic file." ;;
      --*) ;;
      -*C*) refuse "file -C writes a compiled magic file." ;;
    esac
  done
  return 0
}

check_export() {
  for a in "$@"; do
    case "$a" in
      FOUNDRY_PROFILE=*) ;;
      PATH=*|BASH_ENV=*|ENV=*|LD_*|DYLD_*|PROMPT_COMMAND=*|GIT_*|EDITOR=*|VISUAL=*|PAGER=*|SSH_*|HOME=*|XDG_CONFIG_HOME=*|FOUNDRY_*|DAPP_*|ETH_RPC_URL=*|PYTHON*|NODE_OPTIONS=*|PERL5OPT=*|RUBYOPT=*|LESSOPEN=*|LESSCLOSE=*|MANPAGER=*|BROWSER=*|ZDOTDIR=*)
        refuse "exporting $a changes what later commands resolve to or what a tool runs." ;;
    esac
  done
  return 0
}

# ---- the terminal's operations ----

terminal_cast() {
  csub="$1"; shift
  rpcs=0
  rpcok=0
  prev=""
  for a in "$@"; do
    a="$(unquote "$a")"
    if [ "$prev" = "--rpc-url" ]; then
      rpcs=$((rpcs + 1))
      case "$a" in sepolia|mainnet) rpcok=$((rpcok + 1)) ;; esac
    fi
    case "$a" in
      --rpc-url=*)
        rpcs=$((rpcs + 1))
        case "${a#--rpc-url=}" in sepolia|mainnet) rpcok=$((rpcok + 1)) ;; esac ;;
      --private-key*|--mnemonic*|--keystore*|--account*|--password*|--ledger|--trezor|--aws|--gcp|--turnkey|--browser|--interactive|--unlocked|--etherscan-api-key*|--flashbots|--debug|-i|-e*|-r*)
        refuse "cast $csub $a names a key, a signer, an explorer key, a debugger or an unchecked endpoint; the terminal reads chain state only through the sepolia or mainnet alias." ;;
    esac
    prev="$a"
  done
  [ "$rpcs" -eq 1 ] && [ "$rpcok" -eq 1 ] || refuse "cast $csub needs exactly one --rpc-url, naming the sepolia or mainnet alias."
}

terminal_python() {
  go_ahead "run a generator"
  root_cwd "a generator"
  [ "${1:-}" = "-I" ] && [ "${2:-}" = "-S" ] || refuse "the terminal runs a generator as python3 -I -S tools/<name>.py, isolated from site-packages and PYTHON variables."
  s="$(unquote "${3:-}")"
  case "$s" in
    tools/*/*) refuse "script '$s' is not a file directly under tools/." ;;
    tools/?*.py) ;;
    *) refuse "the terminal runs only tools/<name>.py, relative to the repository root; got '${s:-nothing}'." ;;
  esac
  shift 3
  [ $# -eq 0 ] || refuse "python3 $s takes no arguments from the terminal; the generators that need --out write into another repository, and those stay the user's."
  git -C "$root" ls-files --error-unmatch -- "$s" >/dev/null 2>&1 || refuse "script '$s' is not tracked; the terminal runs only a script git has."
  [ -z "$(git -C "$root" status --porcelain --untracked-files=all -- tools 2>/dev/null)" ] || refuse "tools/ has an uncommitted or untracked change; the terminal runs a generator only from a clean tools/ tree."
}

terminal_paths() {
  tcmd="$1"; shift
  root_cwd "$tcmd"
  for a in "$@"; do
    a="$(unquote "$a")"
    case "$a" in
      -*) continue ;;
      ..|../*|*/..|*/../*) refuse "$tcmd '$a': the terminal reads only inside the repository." ;;
      /*)
        case "$(lower "$a")/" in
          "$(lower "$root")"/*) ;;
          *) refuse "$tcmd '$a': the terminal reads only inside the repository." ;;
        esac ;;
    esac
  done
}

terminal_judge() {
  tf="$1"; tw="$2"; shift 2
  case "$tf" in
    */*) refuse "the terminal names a command bare, never by path; got '$tf'." ;;
  esac
  case "$tw" in
    git) check_git "$@" ;;
    cast) check_cast "$@" ;;
    python3) terminal_python "$@" ;;
    cp) [ "$envswap" -eq 1 ] || refuse "the terminal copies only in the env swap forms, cp .env.mainnet .env and cp .env.sepolia .env, each as a command on its own." ;;
    cmp|ls|cat|head|tail|wc|shasum|stat) terminal_paths "$tw" "$@" ;;
    echo|printf|pwd|date|true|false|basename|dirname|clear) ;;
    *) refuse "'$tw' is not a command the terminal runs. It runs the env swap, a tools/ generator, the aumm-site pull, cast chain reads, git reads, cmp, ls, cat, head, tail, wc, shasum and stat inside the repository, and echo, printf, pwd, date, basename and dirname." ;;
  esac
}

judge() {
  while [ $# -gt 0 ]; do
    case "$1" in
      if|then|else|elif|fi|while|until|do|done|case|esac|in|function|'!'|exec|env|time|nice|nohup|builtin|caffeinate) shift ;;
      for|select) return 0 ;;
      timeout|gtimeout) shift; [ $# -gt 0 ] && shift ;;
      command)
        shift
        case "${1:-}" in -v|-V) return 0 ;; esac ;;
      PATH=*|BASH_ENV=*|ENV=*|LD_*|DYLD_*|PROMPT_COMMAND=*) refuse "assigning $1 changes what later commands resolve to." ;;
      GIT_TERMINAL_PROMPT=0) shift ;;
      GIT_*=*|EDITOR=*|VISUAL=*|PAGER=*|SSH_*=*|HOME=*|XDG_CONFIG_HOME=*) refuse "assigning $1 changes what git runs or where it reads its config; not from an agent." ;;
      FOUNDRY_PROFILE=*)
        [ "$terminal" -eq 0 ] || refuse "the terminal sets no environment variable but GIT_TERMINAL_PROMPT=0; got $1."
        shift ;;
      FOUNDRY_*=*|DAPP_*=*|ETH_RPC_URL=*|PYTHON*=*|NODE_OPTIONS=*|PERL5OPT=*|RUBYOPT=*|LESSOPEN=*|LESSCLOSE=*|MANPAGER=*|BROWSER=*|ZDOTDIR=*)
        refuse "assigning $1 changes what a tool runs or where it reaches; not from an agent." ;;
      [A-Za-z_]*=*)
        [ "$terminal" -eq 0 ] || refuse "the terminal sets no environment variable but GIT_TERMINAL_PROMPT=0; got $1."
        shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || return 0
  first="$1"; shift
  case "$first" in
    '['|'[[') ;;
    '.') refuse "dot-sourcing a file." ;;
    *'$'*|*'\'*) refuse "command name '$first' comes from an expansion or an escape and cannot be judged." ;;
    -*) refuse "option '$first' where a command name was expected." ;;
    =*|*'*'*|*'?'*|*'['*|*','*|*'~'*) refuse "command name '$first' would be expanded by the shell, so the name judged here is not the program that would run." ;;
    ./*|tools/*|*.py|*.sh|*.rb|*.js|*.pl|*.php) refuse "executing a script file ($first); scripts run in the user's terminal." ;;
  esac
  w="$(unquote "$first")"; w="${w##*/}"
  if [ "$terminal" -eq 1 ]; then
    terminal_judge "$first" "$w" "$@"
    return 0
  fi
  case "$first" in
    */*)
      fq="$(unquote "$first")"
      case "$fq" in
        */..|*/../*) refuse "command '$first' is named through a .. segment." ;;
      esac
      case "$fq" in
        /usr/bin/*|/bin/*|/usr/sbin/*|/sbin/*|/opt/homebrew/bin/*|.venv/bin/*|"$root"/.venv/bin/*|"${HOME:-/nonexistent}"/.foundry/bin/*) ;;
        *) refuse "command '$first' is named by a path outside the system, Homebrew, foundry and .venv bin directories." ;;
      esac ;;
  esac
  case "$w" in
    git) check_git "$@" ;;
    forge) check_forge "$@" ;;
    cast) check_cast "$@" ;;
    slither) [ "$checker" -eq 1 ] || refuse "slither runs only from the checker agent."; check_slither "$@" ;;
    hevm) [ "$checker" -eq 1 ] || refuse "hevm runs only from the checker agent."; check_hevm "$@" ;;
    anvil|chisel|solc) refuse "$w does not run from an agent." ;;
    bash|sh|zsh|dash|ksh|fish) check_shell "$w" "$@" ;;
    sed) check_sed "$@" ;;
    sort) check_sort "$@" ;;
    uniq) check_uniq "$@" ;;
    file) check_file "$@" ;;
    export|declare|typeset|readonly) check_export "$@" ;;
    cat|head|tail|wc|shasum|md5|cksum|ls|find|stat|od|nl|cut|tr|diff|cmp|comm|paste|join|column|fold|expand|unexpand|rev|strings|hexdump|grep|egrep|fgrep|jq|test|'['|'[['|printf|echo|true|false|:|pwd|date|basename|dirname|realpath|readlink|which|type|read|exit|du|df|uname|sw_vers|whoami|id|seq|expr|clear) ;;
    rm|rmdir|unlink|shred|srm|trash|mv|cp|install|ln|link|ditto|mkfile|cpio|pax|bsdtar|mkdir|mkfifo|mknod|touch|chmod|chown|chgrp|chflags|xattr|truncate|dd|tee|sponge|patch|split|csplit|ex|ed|vi|vim|nvim|nano|emacs|pico|tar|zip|unzip|gzip|gunzip|bzip2|xz|7z|openssl|base64|iconv|pbcopy|pbpaste)
      refuse "'$w' writes, moves or removes files or reads the clipboard; file content is the composer's through Write and Edit, and deletes are the user's (CLAUDE.md 8b)." ;;
    python*|pypy*|perl*|ruby*|node*|php*|lua*|awk|nawk|gawk|mawk|sqlite3|tclsh|wish|osascript|swift|swiftc|expect|make|cmake|ninja|clang|gcc|cc|ld|xcrun|xcodebuild|rustc|cargo|go|javac|java|deno|claude|arch|script|sandbox-exec|taskpolicy|stdbuf|noglob|nocorrect)
      refuse "'$w' runs arbitrary code, a build outside forge, a nested Claude session or another command out of this hook's sight; not from an agent." ;;
    open|say|defaults|launchctl|crontab|kill|killall|pkill|reboot|shutdown|halt|diskutil|hdiutil|mount|umount|security|networksetup|systemsetup|pmset|screencapture|sudo|su|doas|pkexec)
      refuse "'$w' changes the system or runs as another user; never from an agent." ;;
    ssh|scp|sftp|rsync|curl|wget|nc|ncat|netcat|telnet|ftp|ping|dig|nslookup|host|traceroute|whois|pip|pip3|npm|npx|pnpm|yarn|bun|brew|port|gem|docker|podman|foundryup|gh|hub|glab|aws|gcloud|az|rg|ripgrep|ugrep)
      refuse "'$w' reaches the network, installs software or runs a preprocessor command; that is the user's (CLAUDE.md 8b, 8c)." ;;
    *) refuse "'$w' is not on the list of commands an agent may run. Read with cat, head, tail, grep, sed -n, jq, diff, cmp, ls, find, stat, od, wc and shasum, and use git reads; anything else runs in the user's terminal. A USER VERIFY block opens with clear, which is on the list." ;;
  esac
  return 0
}

segments="$(printf '%s\n' "$masked" | $T ';|&(){}' '\n\n\n\n\n\n\n')"
while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"
  [ -n "$seg" ] || continue
  set -- $seg
  judge "$@"
done <<< "$segments"

if [ "$checker" -eq 1 ]; then
  mkdir -p "$root/.claude/audit" 2>/dev/null || true
fi

exit 0
