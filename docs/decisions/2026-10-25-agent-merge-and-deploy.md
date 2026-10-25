# Agent-performed merge and deploy

Date: 2026-10-25. Status: accepted by the owner in orchestrator thread thr_9zai9anhqx.

## Source

The owner (Kenneth Dixon) ruled: "I want to know when a merge happens but not to be the one to do it", and separately "I would rather you deploy". The owner merged sky64/floor#1 from the GitHub web UI at 2026-10-25T17:06:58Z, merge commit 976f5d0 (parents 56c5ccb and bda911d), a few minutes before the rule reached the agent. The agent made no merge call. No agent-performed merge has happened yet, so the capability is not exercised.

## Rule

- Merge and production deployment are performed by the agent identity (Solvela-bot) only after the independent Codex review is clean and the orchestrator has verified it.
- Every merge and every deployment is reported to the owner in the task thread and recorded on the PR with the merge SHA and time.
- The owner may revoke or narrow this at any time.
- New paid services, permission changes, external communications, and credential changes still require explicit per-case authorization.
- Main in this repository requires one approving review that the agent cannot give itself. The merge still waits for a human approval, and that is recorded, not hidden.

This replaces the text that made merge and production deployment owner-performed actions requiring explicit authorization. See [AGENTS.md](../../AGENTS.md) and the [merge gate](../09-agent-identity.md).

## Untested

- Whether a merge without the required approval is rejected by branch protection.
- Any agent-performed merge or deployment under this rule. None has been performed yet.
