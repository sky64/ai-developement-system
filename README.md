# crew64

Development workflow on [Orca](https://orca.stably.ai): Claude orchestrates and never writes in the main checkout, specialist agents implement in Orca worktrees (the orchestrator does one small, bounded, non-risky task itself in a task worktree; see the process ladder in the policy), Codex independently reviews, and the owner approves where branch protection requires it. Merge and deploy are performed by the agent identity after a clean, verified review and reported to the owner ([decision](docs/decisions/2026-10-25-agent-merge-and-deploy.md)). Policy: [docs/05-delegation.md](docs/05-delegation.md). The move from Cloud Room to Orca is [decision 0003](docs/decisions/0003-orca.md).

Start with the [Orca setup record](docs/12-orca-setup.md). Shared instructions are in [AGENTS.md](AGENTS.md), imported by [CLAUDE.md](CLAUDE.md) for Claude; Codex reads AGENTS.md directly.

To use this system in an application repository without copying files, install it as a Claude Code plugin: [docs/11-plugin-install.md](docs/11-plugin-install.md).

## Using this on your own setup

The harness is built for Orca with Claude and Codex; DeepSeek workers and a metering gateway are optional. Every feature has a switch and every install-specific value lives in one file per repository ([decision 0005](docs/decisions/0005-feature-switches-and-portability.md)).

1. Clone this repository (or add it as a Claude Code marketplace) and, from a human session, run `bash <this repo>/tools/crew64-enable.sh /path/to/your/repo`. It enables the plugin, writes `.claude/crew64.json` from `config/crew64.defaults.json`, adds the orchestrator line to `CLAUDE.md`, registers the repo with Orca, records it as `crew64.trustedRoot` in your global git config (the hook honours a config only for registered main checkouts) and commits. The run also installs or refreshes the user-level `/harness-enable` skill at `~/.claude/skills/harness-enable`, a wrapper that forwards to this script (`--no-skill` skips it).
2. Edit `.claude/crew64.json`: turn features on or off, list the hosts that run extra agents, name your gateway and model ids. `config/examples/orca-solvela.json` is the owner's own wiring (names only) and the shape to copy; pass a prepared file with `--config`. `features.scout64` sends read-only lookups to the Haiku helper `crew64:scout64`; turn it off to use the rung 1 model for them. `features.process_ladder` lets the orchestrator do one small, bounded, non-risky task itself in a task worktree instead of briefing a worker (thresholds in `process`); turn it off to delegate every task.
3. Only if you want an agent identity for pushes and merges: run `tools/bot/install-bot-identity.sh --name <login> --email <address> --token-command "<command that prints the token>"` once per machine, then set `features.bot_identity` to true in the repos that use it.
4. Start a Claude session in the repo; the orchestrator prints its configuration on its first line. The rules are in [docs/05-delegation.md](docs/05-delegation.md).

### Upgrading an existing install

A repo's config governs only after its main checkout is registered as `crew64.trustedRoot` in your global git config. After updating the plugin, re-run tools/crew64-enable.sh against each existing main checkout, on every machine and user account that runs the harness, even where `.claude/crew64.json` already exists; the run is idempotent and only adds the registration. Until then that repo runs on the defaults (guard on, ladder on, no metering, no bot) and the orchestrator's status line shows `config=untrusted:<path>`. Reinstalling the bot identity alone does not re-enable the bot in a repo; the registration does.

```text
/plugin install crew64 --marketplace sky64/crew64
```

The [architecture proposal](docs/01-architecture-proposal.md) and [capability matrix](docs/02-compatibility-matrix.md) define the intended boundaries and remaining checks. Additional harnesses and production deployment are deferred. Jev was tried once as a second opinion, recorded in the [Jev pilot](docs/07-jev-pilot.md); it is not integrated.

The [automatic Codex review trial](docs/10-automatic-review.md) and its GitHub Action forwarded bot PRs to a Cloud Room webhook. The Action is removed with decision 0003; automatic review is to be rebuilt as an Orca automation. Until then the orchestrator starts the Codex reviewer as an Orca worker. Human approval remains manual; merging is governed by the [2026-10-25 standing authorization](docs/decisions/2026-10-25-agent-merge-and-deploy.md).

The [original audit](docs/00-audit-and-architecture-proposal.md) and the Cloud Room setup record ([docs/03](docs/03-cloudroom-setup.md)) are historical.

This repository is public configuration and contains no secrets; credentials stay in each user's secret manager and are referenced by name only, and the agent identity is whatever each install configures. Audit output must never be committed.

Status: Orca 1.4.242 is installed with Claude and Codex signed in. The Claude to Codex review handoff through Orca was exercised on 2026-10-27, see [docs/12](docs/12-orca-setup.md); the Cloud Room era verifications are in [docs/04](docs/04-smoke-test.md) to [docs/06](docs/06-enforcement-test.md). The restricted agent identity and the merge gate were exercised by PR 2, authored by `Solvela-bot` and approved and merged by the owner on 2026-10-22, see [docs/09](docs/09-agent-identity.md). That shows the approved path only; rejection of a merge without approval remains untested. Runtime boundaries, token rotation, gate bypass, and Orca environment recipes remain unverified. The model ladder ([decision 0004](docs/decisions/0004-model-ladder.md)) is adopted on 2026-11-17; its Solvela routing rows are recorded in [docs/12](docs/12-orca-setup.md) as they are verified.
