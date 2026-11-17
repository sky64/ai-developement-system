#!/usr/bin/env bash
# Install the agent (bot) identity for Orca worktrees on this machine.
# usage: install-bot-identity.sh --name <login> --email <address> --token-command <shell command that prints the token>
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
name=""; email=""; token_cmd=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name) name="${2:-}"; shift 2 ;;
    --email) email="${2:-}"; shift 2 ;;
    --token-command) token_cmd="${2:-}"; shift 2 ;;
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
marker="# orca-bot identity (tools/bot/install-bot-identity.sh)"
if ! grep -qF "$marker" "$cfg/config" 2>/dev/null; then
  cat >> "$cfg/config" <<CFG

$marker
[includeIf "gitdir:~/Projects/*/.git/worktrees/"]
	path = orca-bot.gitconfig
[includeIf "gitdir:~/orca/workspaces/"]
	path = orca-bot.gitconfig
CFG
  echo "appended includeIf block to $cfg/config"
else
  echo "includeIf block already present in $cfg/config"
fi
echo "wrote aidev.bot.* to the global git config and $cfg/orca-bot.gitconfig; symlinked git-credential-op-bot and gh-bot into ~/.local/bin"
