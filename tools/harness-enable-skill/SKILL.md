---
name: harness-enable
description: >-
  Enable the crew64 Claude Code plugin (formerly ai-dev-system) (orchestrator guard, orchestrator
  skill, role templates) in a repository, register the repo with Orca, set its
  base ref, add the orchestrator line to CLAUDE.md, and commit. Use when the
  user says "/harness-enable", "enable the harness", "harness this repo", or
  "set up the dev system in <repo>".
---

# Harness enable

Run the script with the repository path (defaults to the current directory):

```sh
bash ~/.claude/skills/harness-enable/enable.sh /path/to/repo [--config <crew64.json>] [--no-commit] [--no-skill]
```

Flags: `--no-commit` leaves the files staged but uncommitted; `--no-skill` skips refreshing this wrapper. `enable.sh --print-real` prints the plugin script this wrapper forwards to.

What it does, in order:

1. Installs or refreshes this user-level wrapper so it forwards to the plugin's `tools/crew64-enable.sh` wherever that checkout lives.
2. Merges `extraKnownMarketplaces` and `enabledPlugins` for `crew64@crew64` into the repository's `.claude/settings.json`, keeping any existing keys, and writes `.claude/crew64.json` from the plugin defaults (or `--config`).
3. Registers the main checkout as `crew64.trustedRoot` in your global git config and appends the orchestrator line to `CLAUDE.md` (through the symlink when it is one), creating the file if needed.
4. Registers the repository with Orca if it is not registered, and sets the Orca base ref to the remote default branch.
5. Commits the files on the current branch unless `--no-commit`.

Report the output to the user. Remind them that the plugin applies once the folder is trusted in Claude Code, and that Orca's per-repo setup script is a UI setting to check before creating worktrees with setup enabled. Application-specific specialists go in the repository's own `.claude/agents/`.
