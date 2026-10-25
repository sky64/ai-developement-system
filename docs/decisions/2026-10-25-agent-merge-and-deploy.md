# Agent-performed merge and deploy

Date: 2026-10-25. Status: accepted by the owner in orchestrator thread thr_9zai9anhqx.

## Source

The owner (Kenneth Dixon) ruled: "I want to know when a merge happens but not to be the one to do it", and separately "I would rather you deploy". The owner merged sky64/floor#1 from the GitHub web UI at 2026-10-25T17:06:58Z, merge commit 976f5d0 (parents 56c5ccb and bda911d), a few minutes before the rule reached the agent. The agent made no merge call.

## Rule

- Merge and production deployment are performed by the agent identity (Solvela-bot) only after the independent Codex review is clean and the orchestrator has verified it.
- Every merge and every deployment is reported to the owner in the task thread and recorded on the PR with the merge SHA and time.
- The owner may revoke or narrow this at any time.
- New paid services, permission changes, external communications, and credential changes still require explicit per-case authorization.
- Main in this repository requires one approving review that the agent cannot give itself. The merge still waits for a human approval, and that is recorded, not hidden.

This replaces the text that made merge and production deployment owner-performed actions requiring explicit authorization. See [AGENTS.md](../../AGENTS.md) and the [merge gate](../09-agent-identity.md).

## First uses, 2026-10-25

- First agent-performed merge: sky64/floor PR 2 (web dev-dependency fix), merged by Solvela-bot through the REST API at 2026-10-25T17:20:37Z, merge commit 1d0db41500b7de14b8d49708595f148be47e150b, base `feat/fill64` (an unprotected branch), after Codex review thr_hj63ry7464 with no findings. GitHub shows the merge commit author as the account profile name `solvela-publisher`, which resolves to Solvela-bot.
- First agent merge on a protected branch: sky64/ai-developement-system PR 10, merged by Solvela-bot at 2026-10-25T18:22:40Z, merge commit 30ea1e3f1d623f385a39feeb89be32a0c6f7dccf, after the owner's approving review. Branch protection accepted it. Both merges are recorded as PR comments.
- First agent-performed deployment: `terminal-command/` of sky64/floor at 1d0db41 was synced to floor-nyc-1 by a local deploy-operator child (thread thr_9hu9qh5nxm) at 2026-10-25T18:21:48Z.
  - rsync was narrowed to `terminal-command/`, excluding `.venv`, `node_modules`, `dist`, `dist-guest`, `__pycache__`, `.ruff_cache`, `*.db*`, `state/` and `*.jsonl`, with no delete.
  - It was built on the server (node 24, `npm ci`, `npm run build`).
  - `server.check --guest` ran before and after: the same two pre-existing FAILs (G10 and E3) and six new C-pin PASS lines.
  - `terminal-command-web.service` was restarted at 18:22:50Z, timed away from the estate-ping and guest-probe timers.
  - Verified: `/healthz` shows 12 sources with `desks.contract` ok, the fill64 and oracle64 units untouched, no failed units, guest unaffected.
  - `/healthz` overall `ok` remains false because the three `tape.*` sources have been failing since early October (the orderflow dashboard on 8787 is down). That predates the deploy.
  - The whole-repo rsync in the floor handoff was not used: the server checkout holds an uncommitted edit to `fill64/fill64/bin/news.py` that a full sync would have reverted.

## Untested

- Whether a merge without the required approval is rejected by branch protection.
- The deployment rollback path.
