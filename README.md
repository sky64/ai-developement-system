# ai-developement-system

Development workflow on [Orca](https://orca.stably.ai): Claude orchestrates without writing code, specialist agents implement in Orca worktrees, Codex independently reviews, and the owner approves where branch protection requires it. Merge and deploy are performed by the agent identity after a clean, verified review and reported to the owner ([decision](docs/decisions/2026-10-25-agent-merge-and-deploy.md)). Policy: [docs/05-delegation.md](docs/05-delegation.md). The move from Cloud Room to Orca is [decision 0003](docs/decisions/0003-orca.md).

Start with the [Orca setup record](docs/12-orca-setup.md). Shared instructions are in [AGENTS.md](AGENTS.md), imported by [CLAUDE.md](CLAUDE.md) for Claude; Codex reads AGENTS.md directly.

To use this system in an application repository without copying files, install it as a Claude Code plugin: [docs/11-plugin-install.md](docs/11-plugin-install.md).

```text
/plugin install ai-dev-system --marketplace sky64/ai-developement-system
```

The [architecture proposal](docs/01-architecture-proposal.md) and [capability matrix](docs/02-compatibility-matrix.md) define the intended boundaries and remaining checks. Additional harnesses and production deployment are deferred. Jev was tried once as a second opinion, recorded in the [Jev pilot](docs/07-jev-pilot.md); it is not integrated.

The [automatic Codex review trial](docs/10-automatic-review.md) and its GitHub Action forwarded bot PRs to a Cloud Room webhook. The Action is removed with decision 0003; automatic review is to be rebuilt as an Orca automation. Until then the orchestrator starts the Codex reviewer as an Orca worker. Human approval remains manual; merging is governed by the [2026-10-25 standing authorization](docs/decisions/2026-10-25-agent-merge-and-deploy.md).

The [original audit](docs/00-audit-and-architecture-proposal.md) and the Cloud Room setup record ([docs/03](docs/03-cloudroom-setup.md)) are historical.

This repository is public configuration and contains no secrets; credentials stay in the owner's secret manager and are referenced by name only. Audit output must never be committed.

Status: Orca 1.4.242 is installed with Claude and Codex signed in. The Claude to Codex review handoff through Orca was exercised on 2026-10-27, see [docs/12](docs/12-orca-setup.md); the Cloud Room era verifications are in [docs/04](docs/04-smoke-test.md) to [docs/06](docs/06-enforcement-test.md). The restricted agent identity and the merge gate were exercised by PR 2, authored by `Solvela-bot` and approved and merged by the owner on 2026-10-22, see [docs/09](docs/09-agent-identity.md). That shows the approved path only; rejection of a merge without approval remains untested. Runtime boundaries, token rotation, gate bypass, and Orca environment recipes remain unverified.
