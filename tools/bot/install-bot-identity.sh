#!/usr/bin/env bash
# Install the Solvela-bot identity for agent worktrees on this machine.
#
# Linked Git worktrees (what Orca creates) resolve their .git directory to
# <main repo>/.git/worktrees/<name>, so the include is scoped to that path
# under ~/Projects, plus repositories cloned directly under ~/orca/workspaces.
# Main checkouts keep the owner's identity and gh credential helper.
#
# Writes: orca-bot.gitconfig and one includeIf block in the XDG git config
# directory (~/.config/git by default), and two symlinks in ~/.local/bin.
# The include path is relative, which Git resolves against the including
# file, so the directory never needs quoting. Idempotent.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/git"
mkdir -p "$cfg" "$HOME/.local/bin"
ln -sfn "$here/git-credential-op-bot" "$HOME/.local/bin/git-credential-op-bot"
ln -sfn "$here/gh-bot" "$HOME/.local/bin/gh-bot"
cat > "$cfg/orca-bot.gitconfig" <<CFG
# Agent worktree identity. Installed by tools/bot/install-bot-identity.sh.
[user]
	name = Solvela-bot
	email = 277798848+Solvela-bot@users.noreply.github.com
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
echo "wrote $cfg/orca-bot.gitconfig; symlinked git-credential-op-bot and gh-bot into ~/.local/bin"
