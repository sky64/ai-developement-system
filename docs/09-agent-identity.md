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

On 2026-10-22 the owner had the orchestrator (thread thr_nveh5eysxj) invite the account as a collaborator with write permission. The owner accepted the invitation from that account and created a fine-grained personal access token with contents and pull requests set to read and write. This repository could not be selected for that token, see below.

## Credential handling

The intended path was a fine-grained personal access token delivered through `room-cli secret request` into an untracked `.env.agent` file, never printed or committed. Two attempts on 2026-10-22 failed:

1. The first token identified as `sky64`, not the bot.
2. The second token identified as `Solvela-bot` but could not write to this repository. Fine-grained tokens can target repositories owned by the token's own account or by an organization the account belongs to. Here the bot is an outside collaborator on a repository owned by another personal account, `sky64`, so this repository could not be selected for the token.

The push and pull request were therefore made with gh's device-code OAuth login as `Solvela-bot`, into a throwaway configuration directory selected with `GH_CONFIG_DIR`. Afterwards the bot account was logged out and that directory was deleted. No token file was written to the worktree for that path. The owner's own `gh` login was not used for agent pushes. Deleting the directory is not complete cleanup; two side effects remain: `gh auth setup-git` set a global Git credential helper pointing at gh, which may have pre-existed, and a `.gh-agent-config` entry remains in the main repository's `info/exclude`.

- The OAuth grant does not expire unless it is revoked in the Solvela-bot account's authorized OAuth apps.
- A classic personal access token would be the alternative to the device-code login.

## Merge gate

Branch protection on `main` requires one approving review, with admin enforcement and no force pushes. Consequences:

- The bot can push branches and open pull requests.
- A write collaborator can merge once protection requirements pass. Merging without the required approval is expected to be blocked by branch protection; this is untested. Owner-only merging is procedure here, not an enforced restriction.
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
