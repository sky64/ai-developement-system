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
# Which projects directories get the worktree rule: the flags, else whichever
# of ~/projects and ~/Projects exist (both spellings are common).
if [ "${#projects_dirs[@]}" -eq 0 ]; then
  for d in "$HOME/projects" "$HOME/Projects"; do [ -d "$d" ] && projects_dirs+=("$d"); done
fi
# Git's gitdir: patterns take ~/ for the home directory; absolute paths pass through.
gitdir_pattern() {
  case "$1" in
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}
marker="# orca-bot identity (tools/bot/install-bot-identity.sh)"
block="$marker"$'\n'
for d in "${projects_dirs[@]}"; do
  block+="[includeIf \"gitdir:$(gitdir_pattern "${d%/}")/*/.git/worktrees/\"]"$'\n\t'"path = orca-bot.gitconfig"$'\n'
done
block+='[includeIf "gitdir:~/orca/workspaces/"]'$'\n\t'"path = orca-bot.gitconfig"$'\n'
touch "$cfg/config"
before="$(cat "$cfg/config")"
# Drop the previous block (marker line plus its includeIf/path lines), then append the new one.
python3 -I - "$cfg/config" "$marker" "$block" <<'PY'
import sys, pathlib
path, marker, block = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
lines = path.read_text().splitlines()
out, i = [], 0
while i < len(lines):
    if lines[i].strip() == marker:
        i += 1
        while i < len(lines) and (lines[i].startswith('[includeIf "gitdir:') or lines[i].strip().startswith("path = orca-bot.gitconfig")):
            i += 1
        while out and out[-1].strip() == "":
            out.pop()
        continue
    out.append(lines[i]); i += 1
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
