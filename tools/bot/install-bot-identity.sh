#!/usr/bin/env bash
# Install the agent (bot) identity for Orca worktrees on this machine.
# usage: install-bot-identity.sh --name <login> --email <address> --token-command <shell command that prints the token> [--projects-dir <dir>]...
#
# Linked worktrees of repositories under each projects directory, plus
# repositories under ~/orca/workspaces, commit as the bot. Without
# --projects-dir the script uses whichever of ~/projects and ~/Projects exist.
# Re-running replaces the managed include block, so changed directories take
# effect. Everything is validated and the new config is computed before any
# file is written; on any problem the script exits non-zero and changes nothing.
#
# Writes (decision 0005):
# - aidev.bot.name, aidev.bot.email and aidev.bot.tokenCommand in the user's
#   global git config, read by gh-bot and git-credential-op-bot from any cwd;
# - orca-bot.gitconfig (user.name/user.email from the flags plus the
#   credential helper) and one marked includeIf block in the XDG git config
#   directory, so linked Git worktrees under the projects directories and
#   repositories under ~/orca/workspaces commit as the bot while main
#   checkouts keep the owner's identity and helper;
# - two symlinks in ~/.local/bin.
# The include path is relative, which Git resolves against the including
# file, so the directory never needs quoting. Idempotent.
set -euo pipefail
name=""; email=""; token_cmd=""; projects_dirs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --name) name="${2:-}"; shift 2 ;;
    --email) email="${2:-}"; shift 2 ;;
    --token-command) token_cmd="${2:-}"; shift 2 ;;
    --projects-dir) [ -n "${2:-}" ] || { echo "install-bot-identity: --projects-dir needs a path" >&2; exit 2; }; projects_dirs+=("$2"); shift 2 ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "install-bot-identity: unknown argument $1" >&2; sed -n '3p' "$0" >&2; exit 2 ;;
  esac
done
[ -n "$name" ] && [ -n "$email" ] && [ -n "$token_cmd" ] || { echo "install-bot-identity: --name, --email and --token-command are all required" >&2; exit 2; }

# Which projects directories get the worktree rule: the flags, else whichever
# of ~/projects and ~/Projects exist (both spellings are common). Each is made
# absolute and normalised (relative paths resolve against the caller's cwd,
# repeated or trailing slashes collapse), then validated: the path lands inside
# a quoted git config value and a glob pattern, so quote, backslash and glob
# characters are refused.
if [ "${#projects_dirs[@]}" -eq 0 ]; then
  for d in "$HOME/projects" "$HOME/Projects"; do [ -d "$d" ] && projects_dirs+=("$d"); done
fi
reject_dir() {
  echo "install-bot-identity: --projects-dir '$1' contains a character that cannot be written safely into a git includeIf pattern (quote, backslash, * ? [ ], newline, carriage return, or leading/trailing space)" >&2; exit 2
}
normalized=()
for d in "${projects_dirs[@]}"; do
  # Validate the RAW argument first: Bash's $(...) strips trailing newlines, so a
  # check after normalisation would miss a directory that ends in one and
  # silently install a rule for its newline-less sibling.
  case "$d" in
    *'"'*|*'\'*|*'*'*|*'?'*|*'['*|*']'*|*$'\n'*|*$'\r'*|' '*|*' '|*'/ '*) reject_dir "$d" ;;
  esac
  case "$d" in /*) ;; *) d="$PWD/$d" ;; esac
  # Resolve symlinks before collapsing ".." (git matches gitdir against real
  # paths), then normalise. The ~/ form is only safe when HOME is itself real.
  d="$(python3 -I -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$d")"
  case "$d" in
    *'"'*|*'\'*|*'*'*|*'?'*|*'['*|*']'*|*$'\n'*|*$'\r'*|' '*|*' ') reject_dir "$d" ;;
  esac
  normalized+=("$d")
done
projects_dirs=("${normalized[@]}")

here="$(cd "$(dirname "$0")" && pwd)"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/git"

# Git's gitdir: patterns take ~/ for the home directory; absolute paths pass through.
real_home="$(python3 -I -c 'import os; print(os.path.realpath(os.path.expanduser("~")))')"
gitdir_pattern() {
  # Paths are real paths. Use the ~/ form only when HOME is not a symlink, so
  # git's expansion of ~ lands on the same real path; otherwise keep it absolute.
  if [ "$real_home" = "$HOME" ]; then
    case "$1" in
      "$HOME") printf '~'; return ;;
      "$HOME"/*) printf '~/%s' "${1#"$HOME"/}"; return ;;
    esac
  fi
  printf '%s' "$1"
}
begin="# >>> orca-bot identity (tools/bot/install-bot-identity.sh) >>>"
end="# <<< orca-bot identity <<<"
legacy="# orca-bot identity (tools/bot/install-bot-identity.sh)"
block="$begin"$'\n'
for d in "${projects_dirs[@]}"; do
  block+="[includeIf \"gitdir:$(gitdir_pattern "$d")/*/.git/worktrees/\"]"$'\n\t'"path = orca-bot.gitconfig"$'\n'
done
block+='[includeIf "gitdir:~/orca/workspaces/"]'$'\n\t'"path = orca-bot.gitconfig"$'\n'"$end"$'\n'

# Compute the new global config text BEFORE any write. A begin/end-marked block
# is removed whole; a legacy block (bare marker) is removed only as far as its
# exact header + path pairs run, so nothing of the user's own config is
# touched. An unmatched or nested begin marker is an error and nothing changes.
compute_config() { python3 -I - "$begin" "$end" "$legacy" "$block" "$cfg/config" <<'PY'
import sys, os
begin, end, legacy, block, cfg_path = sys.argv[1:6]
existing = open(cfg_path, encoding="utf-8").read() if os.path.exists(cfg_path) else ""
lines = existing.split("\n")
# A trailing newline in the file yields a final empty element; drop it for processing.
if lines and lines[-1] == "":
    lines.pop()
out, i = [], 0
def managed_pair(j):
    return (j + 1 < len(lines)
            and lines[j].startswith('[includeIf "gitdir:')
            and lines[j].rstrip().endswith('"]')
            and lines[j + 1].strip() == "path = orca-bot.gitconfig")
while i < len(lines):
    s = lines[i].strip()
    if s == begin:
        j = i + 1
        while j < len(lines) and lines[j].strip() != end:
            if lines[j].strip() == begin:
                sys.stderr.write("install-bot-identity: nested begin marker at line %d of the global git config; fix the file by hand, nothing was changed\n" % (j + 1)); sys.exit(3)
            j += 1
        if j >= len(lines):
            sys.stderr.write("install-bot-identity: begin marker at line %d has no matching end marker in the global git config; fix the file by hand, nothing was changed\n" % (i + 1)); sys.exit(3)
        i = j + 1
    elif s == end:
        sys.stderr.write("install-bot-identity: end marker without a begin marker at line %d of the global git config; fix the file by hand, nothing was changed\n" % (i + 1)); sys.exit(3)
    elif s == legacy:
        i += 1
        while managed_pair(i):
            i += 2
    else:
        out.append(lines[i]); i += 1
        continue
    while out and out[-1].strip() == "":
        out.pop()
text = "\n".join(out).rstrip("\n")
text = (text + "\n\n" if text else "") + block
sys.stdout.write(text)
PY
}

# Validate the marker structure before any write.
compute_config >/dev/null || exit 1

# All inputs validated and the new config computed: now write.
mkdir -p "$cfg" "$HOME/.local/bin"
ln -sfn "$here/git-credential-op-bot" "$HOME/.local/bin/git-credential-op-bot"
ln -sfn "$here/gh-bot" "$HOME/.local/bin/gh-bot"
cat > "$cfg/orca-bot.gitconfig" <<CFG
# Agent worktree identity. Installed by tools/bot/install-bot-identity.sh.
[user]
	name = $name
	email = $email
[credential "https://github.com"]
	helper =
	helper = !$HOME/.local/bin/git-credential-op-bot
CFG
git config --global aidev.bot.name "$name"
git config --global aidev.bot.email "$email"
git config --global aidev.bot.tokenCommand "$token_cmd"
existing=""; [ -f "$cfg/config" ] && existing="$(cat "$cfg/config")"
newcfg="$(compute_config)" || exit 1
if [ "$newcfg" = "$existing" ]; then
  echo "includeIf block already present in $cfg/config"
else
  printf '%s\n' "$newcfg" > "$cfg/config"
  echo "wrote includeIf block to $cfg/config for: ${projects_dirs[*]:-(no projects dir)} and ~/orca/workspaces"
fi
echo "wrote aidev.bot.* to the global git config and $cfg/orca-bot.gitconfig; symlinked git-credential-op-bot and gh-bot into ~/.local/bin"
