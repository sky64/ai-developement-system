#!/usr/bin/env bash
# Install the agent (bot) identity for Orca worktrees on this machine.
# usage: install-bot-identity.sh --name <login> --email <address> --token-command <shell command that prints the token> [--projects-dir <dir>]...
#
# Linked worktrees of repositories under each projects directory, plus
# repositories under ~/orca/workspaces, commit as the bot. Without
# --projects-dir the script uses whichever of ~/projects and ~/Projects exist.
# Re-running replaces the include block, so changed directories take effect.
#
# Writes (decision 0005):
# - aidev.bot.name, aidev.bot.email and aidev.bot.tokenCommand in the user's
#   global git config, read by gh-bot and git-credential-op-bot from any cwd;
# - orca-bot.gitconfig (user.name/user.email from the flags plus the
#   credential helper) and one includeIf block in the XDG git config directory,
#   so linked Git worktrees under ~/Projects and repositories under
#   ~/orca/workspaces commit as the bot while main checkouts keep the owner's
#   identity and helper;
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
# of ~/projects and ~/Projects exist (both spellings are common). Validate
# before anything is written: the path lands inside a quoted git config value
# and a glob pattern, so quote, backslash and glob characters are refused.
if [ "${#projects_dirs[@]}" -eq 0 ]; then
  for d in "$HOME/projects" "$HOME/Projects"; do [ -d "$d" ] && projects_dirs+=("$d"); done
fi
for d in "${projects_dirs[@]}"; do
  case "$d" in
    *'"'*|*'\'*|*'*'*|*'?'*|*'['*|*']'*|*$'\n'*|' '*|*' '|'')
      echo "install-bot-identity: --projects-dir '$d' contains a character that cannot be written safely into a git includeIf pattern (quote, backslash, * ? [ ], newline, or leading/trailing space)" >&2; exit 2 ;;
  esac
done
here="$(cd "$(dirname "$0")" && pwd)"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/git"
mkdir -p "$cfg" "$HOME/.local/bin"
ln -sfn "$here/git-credential-op-bot" "$HOME/.local/bin/git-credential-op-bot"
ln -sfn "$here/gh-bot" "$HOME/.local/bin/gh-bot"
git config --global aidev.bot.name "$name"
git config --global aidev.bot.email "$email"
git config --global aidev.bot.tokenCommand "$token_cmd"
cat > "$cfg/orca-bot.gitconfig" <<CFG
# Agent worktree identity. Installed by tools/bot/install-bot-identity.sh.
[user]
	name = $name
	email = $email
[credential "https://github.com"]
	helper =
	helper = !$HOME/.local/bin/git-credential-op-bot
CFG
# Git's gitdir: patterns take ~/ for the home directory; absolute paths pass through.
gitdir_pattern() {
  case "$1" in
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}
begin="# >>> orca-bot identity (tools/bot/install-bot-identity.sh) >>>"
end="# <<< orca-bot identity <<<"
legacy="# orca-bot identity (tools/bot/install-bot-identity.sh)"
block="$begin"$'\n'
for d in "${projects_dirs[@]}"; do
  block+="[includeIf \"gitdir:$(gitdir_pattern "${d%/}")/*/.git/worktrees/\"]"$'\n\t'"path = orca-bot.gitconfig"$'\n'
done
block+='[includeIf "gitdir:~/orca/workspaces/"]'$'\n\t'"path = orca-bot.gitconfig"$'\n'"$end"$'\n'
touch "$cfg/config"
before="$(cat "$cfg/config")"
# Replace the managed block. A begin/end-marked block is removed whole. A legacy
# block (bare marker) is removed only as far as its exact header + path pairs
# run; the first line that is not such a pair ends it, so nothing of the
# user's own config is touched. Then the new block is appended.
python3 -I - "$cfg/config" "$begin" "$end" "$legacy" "$block" <<'PY'
import sys, pathlib
path, begin, end, legacy, block = pathlib.Path(sys.argv[1]), *sys.argv[2:6]
lines = path.read_text().splitlines()
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
            j += 1
        i = j + 1 if j < len(lines) else len(lines)
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
path.write_text(text)
PY
if [ "$before" = "$(cat "$cfg/config")" ]; then
  echo "includeIf block already present in $cfg/config"
else
  echo "wrote includeIf block to $cfg/config for: ${projects_dirs[*]:-(no projects dir)} and ~/orca/workspaces"
fi
echo "wrote aidev.bot.* to the global git config and $cfg/orca-bot.gitconfig; symlinked git-credential-op-bot and gh-bot into ~/.local/bin"
