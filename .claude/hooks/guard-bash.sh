#!/usr/bin/env bash
# guard-bash.sh - Claude Code PreToolUse hook on Bash.
#
# Every Bash tool call, from the main session and from every subagent, passes
# through here before it runs. A refusal exits 2, which blocks the call and
# feeds the reason back to the model. Three things are enforced:
#
#   1. For every caller: no git mutation, no network, no install, no
#      broadcast, no file mutation through the shell, no escape hatch that
#      could hide one (eval, xargs, find -exec, backticks, inline
#      interpreters, a shell running a script, a command name built from an
#      expansion), and no read of a .env file other than .env.example or of
#      a key store. Git mutations, dependency bumps, deletes and broadcasts
#      belong to the user's terminal (CLAUDE.md 8b, 8c); file content belongs
#      to the composer agent through Write and Edit, which guard-write.sh
#      polices.
#   2. Role gates: forge build, test, lint, clean, snapshot, coverage,
#      script, fmt --check, slither and hevm run only from the agent named
#      "checker"; every other caller is read-only. Output redirection is
#      refused except to /dev/*, and for the checker also into
#      .claude/audit/ or a claude scratchpad.
#   3. Fork runs: a forge test with --fork-url must name the mainnet alias,
#      carry a literal --match-path with no glob, and --threads 1 (D35, D36,
#      RB-023). Any --rpc-url is refused; runs against a node are the user's.
#
# Unknown commands pass. Refusals err toward refusing: a mutating verb inside
# a quoted string or a heredoc body still refuses, and the caller rephrases.
# Fails closed on a missing jq or unparseable input. Tools are pinned to
# /usr/bin so a caller's PATH cannot change how a pattern is read.
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

checker=0
[ "$agent" = "checker" ] && checker=1

has() { printf '%s' "$cmd" | $G -Eq -e "$1"; }
seghas() { printf '%s' "$2" | $G -Eq -e "$1"; }
unquote() { printf '%s' "$1" | $T -d "\"'"; }

# ---- whole-command rules, every caller ----

has '--broadcast' && refuse "--broadcast never leaves an agent; live broadcasts are the user's (CLAUDE.md 8c)."
has '`' && refuse "backtick substitution; use \$( ) where a substitution is needed."
has '>\(' && refuse "process substitution as an output target."
has '\|[[:space:]]*\\?"' && refuse "a pipe into a quoted command name."
has 'system\(|getline' && refuse "awk system() or getline runs a command."
has '(^|[^A-Za-z0-9_./-])(eval|xargs|parallel|source|alias|trap|fc|enable)([^A-Za-z0-9_-]|$)' && refuse "eval, xargs, parallel, source, alias, trap, fc and enable are escape hatches; none runs from an agent."
has '[[:space:]]-(exec|execdir|ok|okdir|delete|fprint|fprintf|fls)([^A-Za-z0-9_-]|$)' && refuse "find -exec, -ok, -delete and -fprint run or write; list instead."
has '\.ssh/|\.aws/|\.gnupg/|\.netrc|\.npmrc|\.pypirc|keystores?/|id_(rsa|ed25519|ecdsa)' && refuse "key material is never read from an agent."

stripped="$(printf '%s' "$cmd" | $S 's/\.env\.example//g')"
printf '%s' "$stripped" | $G -Eq -e '\.env(\.|[^A-Za-z0-9_.]|$)' && refuse "reading a .env file; only .env.example is readable (PB-D36, PP2)."

targets="$(printf '%s' "$cmd" | $G -Eo -e '(&>|>>|>)[[:space:]]*[^[:space:];&|()]+' || true)"
if [ -n "$targets" ]; then
  while IFS= read -r t; do
    t="$(printf '%s' "$t" | $S -E 's/^(&>|>>|>)[[:space:]]*//')"
    t="$(unquote "$t")"
    [ -n "$t" ] || continue
    case "$t" in
      /dev/null|/dev/stdout|/dev/stderr|/dev/fd/*) continue ;;
    esac
    if [ "$checker" -eq 1 ]; then
      case "$t" in
        .claude/audit/*|./.claude/audit/*|"$root"/.claude/audit/*|/private/tmp/claude-*|/tmp/claude-*) continue ;;
      esac
    fi
    refuse "output redirection to '$t'. Only /dev/* is a target, plus .claude/audit/ and a claude scratchpad for the checker; files are written by the composer through Write and Edit."
  done <<< "$targets"
fi

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
  while [ $# -gt 0 ]; do
    case "$1" in
      -c|--config-env|--config-env=*|--exec-path|--exec-path=*)
        refuse "git $1 can redefine what a verb does; not from an agent." ;;
      -C|--git-dir|--work-tree|--namespace)
        [ $# -ge 2 ] || refuse "git $1 without a value."
        shift 2 ;;
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
    case "$a" in --output*) refuse "git --output writes a file." ;; esac
  done
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
    *) refuse "git $verb mutates the repository or is not a known read; git mutations run in the user's terminal (CLAUDE.md 8b)." ;;
  esac
}

check_forge() {
  sub=""
  for a in "$@"; do case "$a" in -*|'>'*|'<'*|[0-9]'>'*|[0-9]'<'*) ;; *) sub="$(unquote "$a")"; break ;; esac; done
  [ -n "$sub" ] || return 0
  all="$*"
  case "$sub" in
    config|tree|remappings|inspect|selectors|eip712|help) return 0 ;;
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

check_cast() {
  sub=""
  for a in "$@"; do case "$a" in -*|'>'*|'<'*|[0-9]'>'*|[0-9]'<'*) ;; *) sub="$(unquote "$a")"; break ;; esac; done
  [ -n "$sub" ] || return 0
  case "$sub" in
    to-check-sum-address|to-checksum-address|keccak|sig|sig-event|abi-encode|abi-decode|calldata|calldata-decode|to-hex|to-dec|to-wei|from-wei|to-unit|to-bytes32|to-uint256|to-int256|to-ascii|to-utf8|from-utf8|concat-hex|compute-address|create2|namehash|selectors|disassemble|format-bytes32-string|parse-bytes32-string|parse-bytes32-address|max-uint|max-int|min-int|address-zero|hash-zero|shl|shr|to-rlp|from-rlp|pretty-calldata|decode-abi|encode-abi|help)
      return 0 ;;
    *) refuse "cast $sub reaches a node, a key or a signature service; only offline cast utilities run from an agent." ;;
  esac
}

check_shell() {
  sh="$1"; shift
  if [ "$sh" = "bash" ] && [ $# -eq 2 ] && [ "$1" = "-n" ]; then
    case "$2" in -*) ;; *) return 0 ;; esac
  fi
  refuse "$sh would run a script or an inline command; agents do not spawn shells. Only 'bash -n <file>' as a syntax check runs from an agent."
}

check_sed() {
  for a in "$@"; do
    case "$a" in --in-place*|-*[iI]*) refuse "sed $a rewrites a file in place." ;; esac
  done
  seghas '(^|[^A-Za-z\\])[wW][[:space:]]+[^[:space:]]' "$*" && refuse "a sed w command writes a file."
  return 0
}

check_sort() {
  for a in "$@"; do case "$a" in -o|--output|--output=*) refuse "sort -o writes a file." ;; esac; done
  return 0
}

check_export() {
  for a in "$@"; do
    case "$a" in PATH=*|BASH_ENV=*|ENV=*|LD_*|DYLD_*|PROMPT_COMMAND=*) refuse "exporting $a changes what later commands resolve to." ;; esac
  done
  return 0
}

judge() {
  while [ $# -gt 0 ]; do
    case "$1" in
      if|then|else|elif|fi|while|until|do|done|for|case|esac|in|select|function|'!'|exec|env|time|nice|nohup|builtin|caffeinate) shift ;;
      timeout|gtimeout) shift; [ $# -gt 0 ] && shift ;;
      command)
        shift
        case "${1:-}" in -v|-V) return 0 ;; esac ;;
      PATH=*|BASH_ENV=*|ENV=*|LD_*|DYLD_*|PROMPT_COMMAND=*) refuse "assigning $1 changes what later commands resolve to." ;;
      [A-Za-z_]*=*) shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || return 0
  first="$1"; shift
  case "$first" in
    '.') refuse "dot-sourcing a file." ;;
    *'$'*|*'\'*) refuse "command name '$first' comes from an expansion or an escape and cannot be judged." ;;
    -*) refuse "option '$first' where a command name was expected." ;;
    ./*|tools/*|*.py|*.sh|*.rb|*.js|*.pl|*.php) refuse "executing a script file ($first); scripts run in the user's terminal." ;;
  esac
  w="$(unquote "$first")"; w="${w##*/}"
  case "$w" in
    git) check_git "$@" ;;
    forge) check_forge "$@" ;;
    cast) check_cast "$@" ;;
    slither|hevm) [ "$checker" -eq 1 ] || refuse "$w runs only from the checker agent." ;;
    anvil|chisel|solc) refuse "$w does not run from an agent." ;;
    bash|sh|zsh|dash|ksh|fish) check_shell "$w" "$@" ;;
    sed|gsed) check_sed "$@" ;;
    sort|gsort) check_sort "$@" ;;
    export|declare|typeset|readonly) check_export "$@" ;;
    rm|rmdir|unlink|shred|srm|trash|mv|cp|install|ln|mkdir|mkfifo|mknod|touch|chmod|chown|chgrp|chflags|xattr|truncate|dd|tee|sponge|patch|split|csplit|ex|ed|vi|vim|nvim|nano|emacs|pico|tar|zip|unzip|gzip|gunzip|bzip2|xz|7z|openssl|base64|iconv|pbcopy|pbpaste)
      refuse "'$w' writes, moves or removes files or reads the clipboard; file content is the composer's through Write and Edit, and deletes are the user's (CLAUDE.md 8b)." ;;
    python|python2|python3|perl|ruby|node|php|lua|tclsh|osascript|swift|swiftc|expect|make|cmake|ninja|clang|gcc|cc|ld|xcrun|xcodebuild|rustc|cargo|go|javac|java)
      refuse "'$w' runs arbitrary code or a build outside forge; not from an agent." ;;
    open|say|defaults|launchctl|crontab|kill|killall|pkill|reboot|shutdown|halt|diskutil|hdiutil|mount|umount|security|networksetup|systemsetup|pmset|screencapture|sudo|su|doas|pkexec)
      refuse "'$w' changes the system or runs as another user; never from an agent." ;;
    ssh|scp|sftp|rsync|curl|wget|nc|ncat|netcat|telnet|ftp|ping|dig|nslookup|host|traceroute|whois|pip|pip3|npm|npx|pnpm|yarn|bun|brew|port|gem|docker|podman|foundryup|gh|hub|glab|aws|gcloud|az)
      refuse "'$w' reaches the network or installs software; that is the user's (CLAUDE.md 8b, 8c)." ;;
  esac
  return 0
}

segments="$(printf '%s\n' "$cmd" | $T ';|&(){}' '\n\n\n\n\n\n\n')"
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
