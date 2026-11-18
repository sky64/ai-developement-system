# Development system

This repository configures the development workflow on Orca and ships it as a Claude Code plugin for application repositories. It is the setup workspace; another application repository is not required to begin.

## Read first

Read README.md and docs/12-orca-setup.md for the current setup state. docs/05-delegation.md holds the delegation policy and task tiers. docs/00 to docs/11 are Cloud Room era records; the decisions under docs/decisions still apply unless superseded by [0003](docs/decisions/0003-orca.md).

## Roles and delegation

- Claude Code is the orchestrator and does not write code or commit in the main checkout; in native mode (docs/05, Process ladder) it works in a task worktree. Codex is the independent reviewer. Explicit user assignments take precedence.
- Work is tiered by risk (docs/05-delegation.md, "Task tiers"). Trivial: one implementer, no reviewer, the commit message is the record. Normal: one implementer and one Codex review. Risky: the full record, attended. Risk decides the tier, not size: any change to delegation policy, AGENTS.md, .claude/settings.json, hooks, or other protection settings is risky. Specialist selection applies to normal and risky tasks; trivial tasks may use a generalist.
- Every task also carries a complexity rung (docs/05-delegation.md, "Model ladder") that decides its model. An unplanned task's rung equals its tier; risky is always rung 2; escalation only climbs; the tooling is the same at every rung. Work with more than one task gets a plan, written by a rung-2 worker and approved once by the owner with its owner-items list (docs/05-delegation.md, "Plans and owner items").
- The orchestrator may edit directly in the main checkout only for a trivial task when the owner says so in that turn and the session runs with ORCHESTRATOR_GUARD=off. That exception is the only way to write there.
- Every task also carries a mode (docs/05-delegation.md, "Process ladder"): native, where the orchestrator does one small, bounded, non-risky task itself in a task worktree, or delegated. Risky work is always delegated; a native code change at normal tier still gets its Codex review.
- Delegated implementers and all reviewers run as Orca workers, each in its own Orca worktree. Load `orca skills get orca-cli` for handoffs and `orca skills get orchestration` for supervised work, then start them with `orca worktree create --agent` or `orca orchestration worker-start`. Keep a task to one implementer and one reviewer. Assign each worker its files, acceptance criteria, base commit, and limits.
- Native subagents work inside Orca-launched Claude (verified 2026-10-27, docs/12-orca-setup.md). Use them for read-only investigation only. Anything that writes runs as an Orca worker so Orca can see, stop, and inspect it, or as the orchestrator in a task worktree in native mode. Never launch agent CLIs from shell scripts to delegate.
- A Claude Code hook in .claude/settings.json blocks writes in the main checkout and, in a worktree, writes outside that worktree. It is a tripwire, not a security boundary. Worktrees are workspace separation, not an enforced write boundary; one would need OS-user separation or an Orca per-workspace environment recipe, which is untested.
- Inspect or message only the current task's workers when authorized, not unrelated ones.

## Work and review

- Keep changes small, preserve existing work, and add no project dependencies without approval.
- Use the installed `orca --help` and `orca skills get` guides for commands; do not assume the bundled guide matches the running build without checking.
- Before a risky agent run, record the scope, runtime, permission mode, deadline, available hard limits, and retry allowance. Normal tasks record scope, base commit, files, and acceptance criteria in the worker brief.
- Hand review to a fresh Codex context with repository, base/head SHAs, acceptance criteria, changed files, and check results. Review the actual diff and relevant behavior.
- Reviewer output identifies the commit, actionable findings with file/line references, verification, and limitations. It is advisory and does not replace human approval.
- Correction/review cycles, retries of a failed operation and model-ladder escalations draw on one allowance of `limits.review_cycles` per task (`.claude/crew64.json`, default 2); it is one budget, not three. When it is spent the orchestrator stops and asks the owner once (orchestrator skill, Rungs and models). Stop at the recorded deadline; if no external limit is verified, keep execution attended.
- On interruption, inspect commits, uncommitted work, pending side effects, and Orca Runs before resuming. Stop only known workers and processes.

## Verification for this repository

There is no application build or package dependency installation at present.

- Runtime floor for this repository: Python 3.13+ and bash on Linux. Reviewer briefs for this repository state it; findings about older interpreters are out of scope unless they are security findings.
- Run `git diff --check` for changes.
- Run `bash -n` for shell scripts under tools/ and `python3 -m py_compile tools/hooks/orchestrator-guard.py` when they change.
- Run `bash tools/hooks/test-orchestrator-guard.sh`.
- Run `bash tools/test-crew64-config.sh`, `bash tools/bot/test-bot-scripts.sh`, `bash tools/test-crew64-enable.sh` and `bash tools/test-orca-version-check.sh` when the config reader, the bot scripts, harness-enable or the Orca version check change.
- Run `claude plugin validate .` when plugin files change.
- Run `bash tools/check-ladder-docs.sh` when the ladder, templates or the orchestrator skill change, and `bash tools/test-check-ladder-docs.sh` when that script or an agent file's frontmatter pins change.
- Check changed Markdown links and code fences.
- Test behavior when adding executable functionality. CLI help, file presence, and login status are not an end-to-end agent test.

## Credentials and external actions

- Do not print secrets, read credential values, copy personal authentication into worktrees, or commit audit output without review.
- Agent worktrees commit and push as the agent identity installed in the user's git config by `tools/bot/install-bot-identity.sh` (`crew64.bot.name`, `crew64.bot.tokenCommand`) and enabled per repository by `features.bot_identity` in `.claude/crew64.json`: a Git identity include scoped to linked worktrees and a credential helper that runs the token command at push time. The owner's own gh login is never used for agent pushes. The owner's values are recorded in docs/12-orca-setup.md.
- Prepare reversible project changes within the user's request. Do not install global tooling, remove custom files, or change shared machine settings without authorization.
- Merge and production deployment are performed by the agent identity, not the owner, where `features.bot_identity` is on, only after the independent Codex review is clean and the orchestrator has verified it. This is a standing authorization from the owner, who may revoke or narrow it at any time ([decision](docs/decisions/2026-10-25-agent-merge-and-deploy.md)). Where branch protection requires an approving review the agent cannot give itself, the merge waits for a human approval.
- New paid services, permission changes, external communications, and credential changes require explicit per-case authorization.
- Do not represent instructions, hooks, branches, provider flags, or read-only vault access as security boundaries. Test the actual external boundary.

## Completion

Report what changed, what was checked, and what remains untested. Keep task evidence in the PR and consequential architecture decisions in docs/decisions. Update the setup record when a capability is actually verified. Report every merge and every deployment to the owner, update the Orca workspace comment, and record it on the PR with the merge SHA and time.
