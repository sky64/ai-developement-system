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

## Credential handling

The intended path was a fine-grained personal access token delivered through `room-cli secret request` into an untracked `.env.agent` file, never printed or committed. Two attempts on 2026-10-22 failed:

1. The first token identified as `sky64`, not the bot.
2. The second token identified as `Solvela-bot` but could not write to this repository. A fine-grained token can only reach repositories owned by its own account, and this repository is owned by `sky64`.

The push and pull request were therefore made with gh's device-code OAuth login as `Solvela-bot`, into a throwaway configuration directory selected with `GH_CONFIG_DIR` and deleted afterwards. No token file was written to the worktree for that path. The owner's own `gh` login was not used for agent pushes.

- The OAuth grant does not expire unless it is revoked in the Solvela-bot account's authorized OAuth apps.
- A classic personal access token would be the alternative to the device-code login.

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
| Credential rotation practice | Not defined or tested; the OAuth grant stays valid until revoked |
| The bot cannot approve its own pull request | Relies on GitHub refusing self-approval; not tested here |
| The bot cannot bypass branch protection | Expected because it is not an admin; not tested here |

Related: [capability matrix](02-compatibility-matrix.md), [setup record](03-cloudroom-setup.md).
