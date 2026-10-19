# ai-developement-system

A proposed Cloudroom development workflow: Claude implements, Codex independently reviews, CI verifies, and the owner approves and merges using a separate GitHub identity.

Start with the [revised architecture proposal](docs/01-architecture-proposal.md) and [capability matrix](docs/02-compatibility-matrix.md). The first milestone covers one real task in one application repository. Additional harnesses, decision models, and production deployment are deferred.

The [original audit](docs/00-audit-and-architecture-proposal.md) is historical. The [audit script](tools/audit/cloudroom-audit.sh) is a preliminary inventory tool; review its output before sharing and do not infer duplicate installations from directory counts.

Status: documentation proposal only. Runtime boundaries, restricted credentials, GitHub plan eligibility, repository gates, and mobile behavior still need verification.
