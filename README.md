# ai-developement-system

Project configuration for the existing Cloudroom installation: Claude orchestrates without writing code, specialist agents implement in Cloudroom worktrees, Codex independently reviews, and the owner handles approval and merge. Policy: [docs/05-delegation.md](docs/05-delegation.md).

Start with the [Cloudroom setup record](docs/03-cloudroom-setup.md). This repository is the setup workspace; another application repository is not required. Shared instructions are in [AGENTS.md](AGENTS.md), wired through [.bb/AGENTS.md](.bb/AGENTS.md) for Cloudroom and [CLAUDE.md](CLAUDE.md) for Claude.

The [architecture proposal](docs/01-architecture-proposal.md) and [capability matrix](docs/02-compatibility-matrix.md) define the intended boundaries and remaining checks. Additional harnesses and production deployment are deferred. Jev was tried once as a second opinion, recorded in the [Jev pilot](docs/07-jev-pilot.md); it is not integrated.

The [original audit](docs/00-audit-and-architecture-proposal.md) is historical. The [audit script](tools/audit/cloudroom-audit.sh) is a preliminary inventory tool; review its output before sharing and do not infer duplicate installations from directory counts.

This repository is public configuration and contains no secrets; credentials stay in the owner's secret manager and are referenced by name only. Audit output must never be committed.

Status: Claude and Codex are installed and signed in; project instructions are added. Agent handoff, runtime boundaries, restricted GitHub credentials, repository gates, and mobile behavior remain unverified.
