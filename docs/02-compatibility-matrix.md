# Capability and enforcement matrix

Updated 2026-10-19 for the revised [architecture proposal](01-architecture-proposal.md); rows revised 2026-10-22 from the [matrix tests](08-matrix-tests.md). Replaces the earlier vendor-wide matrix, which mixed historical documentation with tests from a different environment.

Labels: **Observed** = current CLI/API inspection; **Documented** = linked vendor feature; **Proposed** = intended configuration; **Untested** = behavioral proof required. Absence of evidence is not proof of unsupported behavior.

## A. Current baseline

| Item | Evidence | Status / limit |
|---|---|---|
| Cloudroom CLI | `room-cli --version` → 0.43.1 | Observed; does not establish app/Core or provider versions |
| Execution context | `room-cli status --json` → Project checkout | Observed for this session only; no sandbox assumed |
| Permission interface | `thread spawn --help` exposes permission mode; `thread interactions --help` exposes approve/deny/answer/grant | Observed interface; accept-edits behavior for a Claude child observed once in [08-matrix-tests.md](08-matrix-tests.md) |
| Delegation | Spawn help exposes parent and environment options | Observed interface; use Cloudroom child threads, verify target/mode and isolation before launching |
| Recovery interface | Stop and queue commands in installed help | Observed interface; stop and explicit resume verified once in [08-matrix-tests.md](08-matrix-tests.md); descendants and queue Untested |
| GitHub actor | `gh api user` → `sky64` | Observed; owner identity currently available to this agent |
| Existing PR actor | PR #1 author is `sky64` | Observed; cannot demonstrate separate human review |
| Repository visibility | GitHub API → private on 2026-10-19; made public on 2026-10-22 | Observed |
| Current main protection | Absent on 2026-10-19; since 2026-10-22 main requires one approving review, with admin enforcement and no force pushes | Observed; PR #1 cannot merge until a second identity approves or admin enforcement is lifted for the merge |
| Pilot repository/plan | This setup repository is the first workspace; plan not verified | Another application repo is optional; gate eligibility remains a prerequisite |

Do not commit raw authentication output or tokens. Capture only the identity, scopes/permissions, versions, configuration metadata, and redacted results necessary to assess a boundary.

The [setup record](03-cloudroom-setup.md) adds later observations: both CLIs are installed and signed in, and the worktree provider reports available. Those checks do not establish a model run, worktree creation, or handoff.

## B. Pilot runtime tests

Fill a separate result record for each provider × execution mode actually selected. Do not transfer results between a local checkout and a cloud sandbox.

| Capability | Claude Code | Codex | Passing evidence |
|---|---|---|---|
| Authentication and harmless task | Untested in pilot runtime | Untested in pilot runtime | Exact version, model, mode, task output; no token values |
| Shared instructions | CLAUDE.md imports AGENTS.md; .bb/AGENTS.md entry point added | Root AGENTS.md and .bb/AGENTS.md entry point added | Verified: discovery in new threads and the Claude to Codex handoff are recorded in [04-smoke-test.md](04-smoke-test.md) to [06-enforcement-test.md](06-enforcement-test.md) |
| Filesystem boundary | Untested | Untested | Dummy fixtures inside/outside allowed paths; mounts and credentials inspected |
| Approval and denial | Verified with accept-edits: in-worktree write allowed without prompt. Network denial from the phone verified end to end: the sandbox reported the denial and curl failed with exit 7 and a 403 from the CONNECT tunnel. Approval verified only as far as the permission gate: the approved route failed at the egress proxy with a repeatable 502, no approved request produced HTTP 200, and phone approval cannot be separated from the CLI grant. Observed: interaction records stayed pending after app decisions and the next command was rejected; reported to Cloudroom as a suspected defect, cause unconfirmed. Out-of-worktree write caught by the hook, permission layer untested for it. See [08-matrix-tests.md](08-matrix-tests.md) | Untested | Harmless interaction allowed/denied with actual permission mode |
| Independent review | Implementer | Verified reviewer: [04-smoke-test.md](04-smoke-test.md) and [06-enforcement-test.md](06-enforcement-test.md) | Separate context, specified base/head SHAs, reproducible findings |
| Child-thread handoff | Verified: [04-smoke-test.md](04-smoke-test.md), [06-enforcement-test.md](06-enforcement-test.md) | Verified: [04-smoke-test.md](04-smoke-test.md), [06-enforcement-test.md](06-enforcement-test.md) | Cloudroom-managed thread references and explicit ownership |
| Stop/restart/queue handling | Stop and explicit resume verified once without duplicate effects; queue inspection Untested. See [08-matrix-tests.md](08-matrix-tests.md) | Untested | Verified cessation, queue inspection, explicit resume without duplicate effects |
| Usage/time controls | No enforceable limit found in the installed CLI, so execution stays attended. See [08-matrix-tests.md](08-matrix-tests.md) | Not searched | Supported hard limits identified; otherwise attended operation only |

Cloudroom's current CLI advertises interactions. That is grounds to test them, not to claim universal approval support. Harness hooks, skill discovery, and sandboxing require separate checks.

## C. Phone interfaces

| Channel | Intended role | Evidence required |
|---|---|---|
| GitHub app/mobile web | Human review, checks, merge | Owner approves a new PR authored by the restricted agent identity |
| Cloudroom mobile web | Monitor and interact with supported threads | Denial verified end to end on 2026-10-22 from the Cloudroom phone app; approval verified only as far as the permission gate, see [08-matrix-tests.md](08-matrix-tests.md). Question response and stop from the phone remain Untested |
| Claude app/Remote Control | Optional Claude-specific monitoring/interactions | Verify the actual session is reachable and permission prompts work; do not assume a Cloudroom session automatically appears |
| Other harness apps/chat gateways | Deferred | Add only if a verified requirement remains unmet |

As of 2026-10-22 one phone-action path has been tested: the owner denied and approved network-access grant requests from the Cloudroom phone app, with the limits recorded in [08-matrix-tests.md](08-matrix-tests.md). GitHub app review and Claude app interactions remain untested. Required-reviewer deployment approval is conditional on repository plan eligibility and is outside the pilot. CLI support does not establish mobile delivery or push notifications.

## D. Enforcement and plan prerequisites

| Requirement | Mechanism | Current status / limitation |
|---|---|---|
| Human approval before merge | Restricted agent identity + required owner review + no agent rule editing/bypass | Partial since 2026-10-22: main requires one approving review with admin enforcement; current actor is still the owner, so a second identity is needed to merge |
| Private-repo branch protection | Eligible GitHub plan | Documented; actual eligibility Untested |
| No self-approval of PR | Distinct human and agent actors | Documented GitHub restriction; PR #1 is a bootstrap artifact |
| Deployment approval | Eligible Environment reviewers, separately verified platform gate, or owner-only manual deployment | Deferred; Environment reviewers are public-only on Free/Pro/Team |
| Production isolation | Credentials and execution inaccessible to dev agents | Proposed; check helpers, connectors, mounts, env, and network |
| Local file protection | Runtime/OS boundary with actual permission mode | Untested; the hook caught the out-of-worktree write before the permission layer did; branches/worktrees are Git separation only |
| Secrets management | Scoped dev credentials, optionally 1Password | Deferred as needed; receiving process can read injected secrets |
| Provider restriction | Runtime/external egress policy if required | No enforcement demonstrated; a registry flag is insufficient |
| Cost bound | Verified provider/runtime cap | No limit flag found in the installed CLI; missing billing login does not prevent API usage charges |
| Destructive-action prevention | OS/runtime restrictions plus supporting hooks | Untested; regex hooks are accident prevention |
| ECC duplicate prevention | Ownership inventory and resolved hook registrations | Untested; directories/counts alone are insufficient |

## E. Deferred capabilities

| Component | Later purpose | Before adoption |
|---|---|---|
| OpenCode | Alternative implementation/provider experiments | Confirm current adapter, auth, instructions, permissions, and cost |
| Hermes | Persistent assistance or chat operations | Establish a need beyond Cloudroom's scheduling tools; verify service isolation and gateway permissions |
| Pi | Task-specific extension | Demonstrate a task the initial harnesses cannot handle simply |
| Jev / other decision models | Structured decision support | Access observed once on a documentation diff, where high-confidence verdicts matched the Codex review and the one subtle claim came back low confidence for human review, see [07-jev-pilot.md](07-jev-pilot.md); value on real decisions not established; privacy policy, source-code value, and headless MCP connection still to verify |
| Parallel implementers | Independent task throughput | Verify workspaces, shared resources, resource limits, and merge coordination |

These rows record possible roles, not verified vendor compatibility. The pilot does not require their installation or credentials.

## F. Evidence record template

For each runtime or permission test, record:

- Date, target repository, disposable fixtures, and task/thread reference.
- App/CLI, harness and model versions; execution and permission modes.
- Authenticated actor and effective permissions without secrets.
- Expected result, observed result, and redacted supporting output.
- What the test does not establish, residual risk, and operator/next action.
- Commit SHA and review/check links where relevant.

Use the PR/issue for task evidence; this matrix is the capability baseline. Failed or incomplete tests stay visible.

## Sources checked for this revision

- Installed `room-cli` 0.43.1: status, spawn, interactions, stop, and queue help; interfaces inspected without launching threads.
- GitHub API: repository visibility, current actor, PR #1 author, main protection, and effective branch rules.
- [GitHub protected branches and plan eligibility](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches).
- [GitHub review rules, including author self-approval restriction](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/approving-a-pull-request-with-required-reviews).
- [GitHub Environments, plan restrictions, self-review and bypass settings](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments).
- [1Password runtime secret injection](https://developer.1password.com/docs/cli/reference/commands/run/).

Historical vendor research remains in [00](00-audit-and-architecture-proposal.md) for context, not as current compatibility proof.
