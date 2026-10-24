# Cloudroom development system

This repository configures the development workflow in the existing Cloudroom installation. It is the setup workspace; another application repository is not required to begin.

## Read first

Read README.md and docs/03-cloudroom-setup.md for the current setup state. The architecture in docs/01-architecture-proposal.md describes the intended boundaries. docs/02-compatibility-matrix.md separates observations from untested behavior. docs/00-audit-and-architecture-proposal.md is historical.

## Roles and delegation

- Claude Code is the orchestrator and does not write code or commit, apart from the trivial direct-edit exception below. Codex is the independent reviewer. Explicit user assignments take precedence.
- Work is tiered by risk (docs/05-delegation.md, "Task tiers"). Trivial: one implementer thread, no reviewer, the commit message is the record. Normal: one implementer and one Codex review. Risky: the full task record below, attended. Risk decides the tier, not size: any change to delegation policy, AGENTS.md, .claude/settings.json, hooks, or other protection settings is risky. Specialist selection applies to normal and risky tasks; trivial tasks may use a generalist.
- The orchestrator may edit directly only for a trivial task when the owner says so in that turn and the session runs with ORCHESTRATOR_GUARD=off.
- Implementers and reviewers run as Cloudroom child threads through room-cli, each in its own worktree. Keep a task to one implementer and one reviewer. Assign each worker its files, acceptance criteria, base commit, and limits.
- Native subagents are unavailable inside Cloudroom threads; the Agent tool returns `bb has disabled Claude Code native subagents, use bb delegation instead` (verified 2026-10-21, thread thr_nveh5eysxj). ECC agent definitions are used as role prompts for Cloudroom child threads, and the orchestrator does read-only investigation itself. Never launch agent CLIs from shell scripts to delegate.
- A Claude Code hook in .claude/settings.json blocks writes in the main checkout and, in a worktree, writes outside that worktree. It is a tripwire, not a security boundary. Worktrees are workspace separation, not an enforced write boundary; one would need OS-user separation or a Cloud sandbox.
- Inspect or message only the current task's threads when authorized, not unrelated threads.

## Work and review

- Keep changes small, preserve existing work, and add no project dependencies without approval.
- Use installed room-cli help and guides for commands; do not assume hosted behavior applies to this local checkout.
- Before a risky agent run, record the scope, runtime, permission mode, deadline, available hard limits, and retry allowance. Normal tasks record scope, base commit, files, and acceptance criteria in the spawn prompt.
- Hand review to a fresh Codex context with repository, base/head SHAs, acceptance criteria, changed files, and check results. Review the actual diff and relevant behavior.
- Reviewer output identifies the commit, actionable findings with file/line references, verification, and limitations. It is advisory and does not replace human approval.
- At most two correction/review cycles and two retries of a failed operation. Stop at the recorded deadline; if no external limit is verified, keep execution attended.
- On interruption, inspect commits, uncommitted work, pending side effects, and task queues before resuming. Stop only known task threads and processes.

## Verification for this repository

There is no application build or package dependency installation at present.

- Run git diff --check for changes.
- Run bash -n tools/audit/cloudroom-audit.sh when changing the audit script.
- Check changed Markdown links and code fences.
- Test behavior when adding executable functionality. CLI help, file presence, and login status are not an end-to-end agent test.

## Credentials and external actions

- Do not print secrets, read credential values, copy personal authentication into worktrees, or commit audit output without review.
- Prepare reversible project changes within the user's request. Do not install global tooling, remove ECC/custom files, or change shared machine settings without authorization.
- Merge, production deployment, new paid services, permission changes, and external communications require explicit authorization.
- The current GitHub actor is the owner. This bootstrap setup is not proof of a restricted agent identity or enforced human-review gate.
- Do not represent instructions, hooks, branches, provider flags, or read-only vault access as security boundaries. Test the actual external boundary.

## Completion

Report what changed, what was checked, and what remains untested. Keep task evidence in the PR/issue and consequential architecture decisions in docs/decisions when needed. Update the setup record when a capability is actually verified.
