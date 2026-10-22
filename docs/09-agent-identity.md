# Agent GitHub identity and the first gated pull request

Recorded 2026-10-22. This file states what was configured and what the first pull request through the gate exercised. It records facts, not proof of a security boundary; see the limits at the end.

## Identity

| Item | Value |
|---|---|
| GitHub user | `Solvela-bot` |
| Display name | solvela-publisher |
| Account origin | An existing account the owner controls |
| Repository role | Collaborator with write permission, not admin |
| Commit author | `Solvela-bot <277798848+Solvela-bot@users.noreply.github.com>` |

On 2026-10-22 the owner had the orchestrator (thread thr_nveh5eysxj) invite the account as a collaborator with write permission. The owner accepted the invitation from that account and created a fine-grained personal access token scoped to this repository with contents and pull requests set to read and write.

## Token handling

- The token reaches an implementer thread only through `room-cli secret request`.
- It is written to an untracked `.env.agent` file in the implementer's worktree. The `.gitignore` pattern `.env.*` covers it.
- It is never printed, echoed, logged, or committed.
- Pushes and pull requests use a separate `gh` configuration directory, selected with `GH_CONFIG_DIR`, authenticated with that token. The owner's own `gh` login is not used for agent pushes.

## Merge gate

Branch protection on `main` requires one approving review, with admin enforcement and no force pushes. Consequences:

- The bot can push branches and open pull requests.
- The bot cannot merge.
- The owner cannot merge without a reviewer approving the pull request.

## First gated pull request

The pull request that adds this file is the first to exercise that path: authored and pushed as `Solvela-bot`, opened against `main`. The Codex review and the owner's approval are recorded in the pull request itself, not here.

## Unverified

| Claim | Status |
|---|---|
| Token rotation practice | Not defined or tested |
| The bot cannot approve its own pull request | Relies on GitHub refusing self-approval; not tested here |
| The bot cannot bypass branch protection | Expected because it is not an admin; not tested here |

Related: [capability matrix](02-compatibility-matrix.md), [setup record](03-cloudroom-setup.md).
