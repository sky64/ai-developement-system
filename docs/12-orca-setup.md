# Orca setup record

Verified on this machine on 2026-10-27 from a Claude session inside an Orca terminal, unless a row says otherwise. Facts, not proof of a security boundary.

## State

| Item | Result |
|---|---|
| Orca | 1.4.242 running, runtime ready, 15 repositories under `~/Projects` registered, one SSH target (`gach-staging`) registered and not connected |
| Claude Code hooks | Orca's agent hooks are in `~/.claude/settings.json` for every hook event; the hook port and token are in the Orca terminal environment |
| Native subagents | Available inside Orca-launched Claude. An Explore subagent ran a command and returned. Cloud Room disabled these |
| Worktree creation | `orca worktree create --repo name:<repo> --name <name> --no-parent --base-branch <ref> --setup skip --json` creates `~/orca/workspaces/<repo>/<name>` on branch `sky64/<name>` |
| Guard in an Orca worktree | The hook allows file-tool writes inside the worktree, denies writes from it into the main checkout, and denies writes and `git commit` in the main checkout. Run against the real worktree paths |
| Claude to Codex review through Orca | Exercised on the first port branch: Run `run_d8515884b14d`, Codex worker in a child worktree, `worker_done` received through the Run inbox in about 90 seconds with outcome succeeded and no findings, worker released, delivery acknowledged |
| `worker-start --worktree new-child` | Rejected by this build with `selector_not_found` although the bundled guide documents it. Create the worktree first and pass `--worktree id:<id>` |
| Repository setup script | Orca's repo settings for this repository carried `pnpm install` with no package.json. There is no CLI to change it; clear it in Orca's repo settings or create worktrees with `--setup skip` |
| Bot identity | `Solvela-bot` has write on this repository; its token is the 1Password item `Solvela-bot GitHub token` in vault `Agents`. `tools/bot/install-bot-identity.sh` scopes the identity and a 1Password-backed credential helper to linked worktrees; see the verification below |
| Plugin in an Orca-launched session | Untested |
| Orca environment recipes as a write boundary | Untested |
| Automatic Codex review as an Orca automation | Not built |

## Bot identity verification

Recorded when `tools/bot/install-bot-identity.sh` was run on this machine; see the pull request that added this file for the command output.

| Check | Expected |
|---|---|
| `git config user.name` in an Orca worktree | `Solvela-bot` |
| `git config user.name` in the main checkout | `sky64` |
| `git credential fill` for github.com in an Orca worktree | `username=Solvela-bot` (password not printed) |
| `gh-bot api user --jq .login` | `Solvela-bot` |
| `gh api user --jq .login` | `sky64` |

## Review and merge flow

1. The implementer works in an Orca worktree and commits as the bot.
2. The orchestrator starts a Codex reviewer as an Orca worker with base and head SHAs, changed files, acceptance criteria, and check results, and waits on the Run inbox.
3. With a clean review, the implementer pushes and opens the pull request as the bot with `gh-bot`.
4. The owner approves the pull request. Branch protection on `main` requires that approval and the bot cannot give it.
5. The orchestrator merges as the bot with `gh-bot pr merge`, reports to the owner, updates the Orca workspace comment, and records the merge SHA and time on the pull request, per the [standing authorization](decisions/2026-10-25-agent-merge-and-deploy.md).
