# ai-developement-system

Project configuration for the existing Cloudroom installation: Claude leads implementation, Codex independently reviews, and the owner handles approval and merge.

Start with the [Cloudroom setup record](docs/03-cloudroom-setup.md). This repository is the setup workspace; another application repository is not required. Shared instructions are in [AGENTS.md](AGENTS.md), wired through [.bb/AGENTS.md](.bb/AGENTS.md) for Cloudroom and [CLAUDE.md](CLAUDE.md) for Claude.

The [architecture proposal](docs/01-architecture-proposal.md) and [capability matrix](docs/02-compatibility-matrix.md) define the intended boundaries and remaining checks. Additional harnesses, decision models, and production deployment are deferred.

The [original audit](docs/00-audit-and-architecture-proposal.md) is historical. The [audit script](tools/audit/cloudroom-audit.sh) is a preliminary inventory tool; review its output before sharing and do not infer duplicate installations from directory counts.

Status: Claude and Codex are installed and signed in; project instructions are added. Agent handoff, runtime boundaries, restricted GitHub credentials, repository gates, and mobile behavior remain unverified.
