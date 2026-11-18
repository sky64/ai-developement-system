# Orca setup record

Verified on this machine on 2026-10-27 from a Claude session inside an Orca terminal, unless a row says otherwise. Facts, not proof of a security boundary.

## State

| Item | Result |
|---|---|
| Orca | 1.4.255 verified 2026-11-17 on the local host (1.4.242 at the 2026-10-27 setup; `tools/orca-version-check.sh` compares the running version with this row), runtime ready, 15 repositories under `~/Projects` registered, one SSH target (`gach-staging`) registered and not connected |
| Claude Code hooks | Orca's agent hooks are in `~/.claude/settings.json` for every hook event; the hook port and token are in the Orca terminal environment |
| Native subagents | Available inside Orca-launched Claude. An Explore subagent ran a command and returned. Cloud Room disabled these |
| Worktree creation | `orca worktree create --repo name:<repo> --name <name> --no-parent --base-branch <ref> --setup skip --json` creates `~/orca/workspaces/<repo>/<name>` on branch `sky64/<name>` |
| Guard in an Orca worktree | The hook allows file-tool writes inside the worktree, denies writes from it into the main checkout, and denies writes and `git commit` in the main checkout. Run against the real worktree paths |
| Claude to Codex review through Orca | Exercised on the first port branch: Run `run_d8515884b14d`, Codex worker in a child worktree, `worker_done` received through the Run inbox in about 90 seconds with outcome succeeded and no findings, worker released, delivery acknowledged |
| `worker-start --worktree new-child` | Rejected by this build with `selector_not_found` although the bundled guide documents it. Create the worktree first and pass `--worktree id:<id>` |
| Repository setup script | Orca's repo settings for this repository carried `pnpm install` with no package.json. There is no CLI to change it; clear it in Orca's repo settings or create worktrees with `--setup skip` |
| Bot identity | `skybot64` (GitHub account id 277798848, renamed from `Solvela-bot` on 2026-11-18) has write on this repository; its token is the 1Password item `Solvela-bot GitHub token` in vault `Agents` (the item kept its old name). `tools/bot/install-bot-identity.sh` scopes the identity and a credential helper to linked worktrees; see the verification below |
| Bot identity values (decision 0005) | On the owner's machines `install-bot-identity.sh` is run as `--name skybot64 --email 277798848+skybot64@users.noreply.github.com --token-command "op read 'op://Agents/Solvela-bot GitHub token/credential'"`, which writes `crew64.bot.name`, `crew64.bot.email` and `crew64.bot.tokenCommand` into the global git config. Repositories that merge as the bot set `features.bot_identity` to true in `.claude/crew64.json`; the owner's full wiring is `config/examples/orca-solvela.json`. Re-run with the `skybot64` name on both of the owner's machines on 2026-11-18; `gh-bot api user --jq .login` printed `skybot64` on each |
| Plugin in an Orca-launched session | Untested |
| Orca environment recipes as a write boundary | Untested |
| Automatic Codex review as an Orca automation | Not built |

## Bot identity verification

Recorded when `tools/bot/install-bot-identity.sh` was run on this machine; see the pull request that added this file for the command output.

| Check | Expected |
|---|---|
| `git config user.name` in an Orca worktree | `skybot64` |
| `git config user.name` in the main checkout | `sky64` |
| `git credential fill` for github.com in an Orca worktree | `username=skybot64` (password not printed) |
| `gh-bot api user --jq .login` | `skybot64` |
| `gh api user --jq .login` | `sky64` |

## Review and merge flow

1. The implementer works in an Orca worktree and commits as the bot.
2. The orchestrator starts a Codex reviewer as an Orca worker with base and head SHAs, changed files, acceptance criteria, and check results, and waits on the Run inbox.
3. With a clean review, the implementer pushes and opens the pull request as the bot with `gh-bot`.
4. The owner approves the pull request. Branch protection on `main` requires that approval and the bot cannot give it.
5. The orchestrator merges as the bot with `gh-bot pr merge`, reports to the owner, updates the Orca workspace comment, and records the merge SHA and time on the pull request, per the [standing authorization](decisions/2026-10-25-agent-merge-and-deploy.md).

## Model ladder routing

Rows for the ladder in [docs/05](05-delegation.md), "Model ladder" and "Ladder review" ([decision 0004](decisions/0004-model-ladder.md)). A row is verified only when the command was run and its output recorded here; "unverified" rows name the owner item that blocks them. Checked 2026-11-17 on the local Orca 1.4.255 host unless stated.

| Row | What was run | Result |
|---|---|---|
| Orca passes a model and effort to Claude and Codex workers | `orca orchestration worker-start --help` | Verified: `--model <id>` "Provider model id for a new agent launch", `--effort <level>` "Reasoning effort for the selected model". Help text states `dsh` and other agents "launch with the model from their own config". |
| `dsh` is a registered Orca agent on the home-office host | `orca worktree ps --environment home-office-omarchy --json` | Verified: six panes with `"agentType": "dsh-tui"` listed; `dsh` 0.2.2-rc.1 installed locally. The Orca agent id there is `dsh-tui`. The DeepSeek row applies once both profile rows below are met. |
| `dsh` profiles for the two DeepSeek rungs exist by name | `dsh <profile> --dump-config` on the home-office host, 2026-11-18 (`dsh` 0.2.1-rc.5) | Verified: `1-DeepSeek64` (rung 0) resolves `agent-default-model` to `deepseek-flash`, `2-DeepSeek64` (rung 1) to `deepseek-v4-pro`. Both are copies of the `dsh-tui` profile with that one patch entry appended. Neither sets `DEEPSEEK_BASE_URL`, so they call DeepSeek directly, not through Solvela; that matches `gateway.kind` `none` in the owner's repositories today. |
| An Orca `dsh-tui` worker runs the profile the brief names | `ps` on the home-office host; the `dsh-tui` launcher source (`@deepseek-harness-tui/dsh-tui` 0.20.1); `DSH_TUI_PROFILE=<profile> dsh-tui <dir>` in tmux, 2026-11-18 | Not met. Orca starts the agent as `dsh-tui .`, which boots the profile named `dsh-tui`; `worker-start` passes no arguments or environment to it. The launcher does read `DSH_TUI_PROFILE`, but the TUI then lets the model last picked with `/model`, stored host-wide in `~/.dsh-tui/model.json`, win over any profile default. On this host that file pins `deepseek-v4-pro`, so every DeepSeek worker runs rung 1 whatever the brief says. Possible route, untested: remove `model.json`, open the worker terminal with `orca terminal create --command "DSH_TUI_PROFILE=<profile> dsh-tui ."` and hand it to `worker-start --terminal <handle>`. |
| Codex honours a `model_providers` base URL at Solvela with a bearer key | `codex --help` shows `-c, --config <key=value>` overrides for `~/.codex/config.toml` | Unverified end to end: needs the Solvela org API key for the reviewer team (owner item). |
| Claude Code carries `x-solvela-session` for a Claude session routed through Solvela | not run | Unverified and not scheduled: the owner has not moved any Claude session off the subscription (decision 0004, Owner items). |
| One Solvela team per role with hourly and daily budgets | not run | Unverified: needs the Solvela org, teams and budget figures (owner item). |
| Solvela team stats `by_model` return rows for a test session | not run | Unverified: needs the teams above and one test dispatch with `x-solvela-session` set. Solvela source confirms `spend_logs.session_id` (migration 003) and the `by_model` breakdown in the team stats route. |
