# Architecture proposal — Cloudroom development workflow

Status: **REVISED PROPOSAL; project instructions added, pilot not yet run.** Updated 2026-10-19 after independent review. This document replaces the earlier architecture in full. [00](00-audit-and-architecture-proposal.md) is a historical audit; [02](02-compatibility-matrix.md) records current evidence and untested capabilities.

The first milestone is one real task through Claude implementation, independent Codex review, CI, owner approval, and merge in one repository (merge by the agent identity after the [2026-10-25 standing authorization](decisions/2026-10-25-agent-merge-and-deploy.md)). This setup repository is the initial workspace; another application repository is optional. OpenCode, Hermes, Pi, and decision models remain future options. See the [setup record](03-cloudroom-setup.md) for the instruction foundation and current provider checks.

## 1. Evidence and unresolved prerequisites

Labels: **Observed** = read from the installed CLI or GitHub API; **Documented** = described in the linked vendor documentation; **Proposed** = intended configuration; **Untested** = still needs a behavioral test. CLI help establishes an interface, not successful execution or enforcement.

Observed in the project checkout on 2026-10-19:

| Observation | Consequence |
|---|---|
| Cloudroom CLI reports version 0.43.1; current environment is a Project checkout | This session does not prove a hosted or self-hosted sandbox exists |
| CLI exposes `--permission-mode`, approval interactions, child-thread options, and stop/queue commands | Test provider × execution mode; do not claim all Cloudroom agents run without prompts |
| `gh api user` reports `sky64`; PR #1 is authored by `sky64` | Current agent access is not separated from the owner's identity |
| This repository is private; classic protection API reports unprotected and effective branch rules for `main` are empty | Approval gates are proposed, not already enforced |
| Pilot task, GitHub plan, runtime isolation, and mobile behavior are unverified | This repository can host the initial setup task; verify the remaining prerequisites |

The original audit ran in a different environment. Its versions, authentication findings, and platform descriptions must not be treated as the current workstation inventory. The existing audit script is a preliminary inventory only: its CLI output needs review before sharing, and directory counts cannot establish duplicate ECC installations.

## 2. Minimal architecture and roles

Cloudroom manages sessions and execution. GitHub holds code, checks, review evidence, and the merge gate. Shared project instructions describe the workflow. There is no custom approval service.

| Role | Initial assignment | Responsibility |
|---|---|---|
| Lead and implementer | Claude Code in a Cloudroom thread | Intake, implementation, verification, explicit handoff to review |
| Independent reviewer | Codex in a separate Cloudroom thread/context | Inspect the specified commit, reproduce relevant behavior, report findings |
| Owner | Human, using a separate GitHub identity from agents | Repository administration, code approval, merge, production access |
| CI | GitHub Actions | Run the application's existing relevant checks |

These are assignments, not permanent model dependencies. Another supported provider can fill a role after its runtime behavior is verified. Harness/model subscription login is separate from GitHub authorization.

Cloudroom delegation uses `room-cli thread spawn` child threads, following the installed CLI help and execution-mode instructions. Do not substitute native harness subagents or launch agent CLIs from scripts inside a Cloudroom thread. First use one implementer and one reviewer; parallel implementation is deferred.

The first milestone needs no always-on operator service, messaging gateway, provider adapter, custom Pi extension, or new hosting purchase.

## 3. GitHub identities and merge enforcement

### 3.1 Separate agent authorization

Before the pilot, provision a restricted GitHub App installation or dedicated bot account for agent work on the selected repository. Keep the owner's administrative credential outside the agent runtime, including credential helpers, inherited environment, shared home directories, and other available connectors.

Agent permissions must be documented and tested: repository content and PR access needed for branch work and review comments; no repository administration, rules management, environment administration, bypass entitlement, production access, or unrelated repository access. Use short-lived credentials where supported. Record identity and permission metadata, never token values.

A distinct commit author name is insufficient; GitHub evaluates the authenticated actor. Distinct model contexts can share an agent App identity for comments; they do not count as separate human approvals. If implementing CI requires extra workflow-writing permission, the owner bootstraps the reviewed workflow separately instead of granting standing administrative access.

GitHub [does not allow PR authors to approve their own PRs](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/approving-a-pull-request-with-required-reviews). PR #1 is therefore a documentation/bootstrap artifact, not proof of a human-review gate. Do not enable an agent bypass to work around that artifact. Demonstrate approval using a new agent-authored pilot PR.

### 3.2 Proposed repository rules

After confirming plan eligibility, the owner configures the target repository:

- Require a PR, approval from the owner through CODEOWNERS, and the named CI checks.
- Cover the whole repository and CODEOWNERS itself; require fresh review after changes.
- Apply protection to administrators where supported, and give agents no bypass or rule-editing permissions.
- Disable force pushes and deletion of the protected branch.
- Select the expected CI App as check source where supported; agents must not satisfy checks by submitting arbitrary statuses.
- Protect workflow and deployment changes through the same human review.

These settings do not reserve the merge button exclusively for the owner after approval; owner-only merging was the pilot procedure and is superseded by the [2026-10-25 standing authorization](decisions/2026-10-25-agent-merge-and-deploy.md). The enforced target is that an agent cannot merge **without** owner approval.

Private-repository [branch protection requires an eligible paid GitHub plan](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches). Record eligibility and inspect effective rules. If protection is unavailable, stop the enforcement milestone: a voluntary review convention must not be reported as an enforced gate.

## 4. Production deployment is a separate decision

Production deployment is outside the first milestone. Development runtimes and PR CI receive no production credentials. Production database changes, destructive migrations, billing administration, and external messaging are excluded from the pilot.

GitHub [Environment required reviewers are public-repository-only on Free, Pro, and Team plans](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments). This repository is private; do not promise Environment approval without verifying the target repository's eligibility.

Choose and document one of these before introducing deployment:

| Option | Required boundary |
|---|---|
| Eligible Environment with required reviewers | Owner reviewer, no agent bypass/admin access, production credentials only behind the gate, explicit approved branch restrictions |
| Owner performs deployment manually | Production credentials and execution stay in an owner-only environment; no agent-accessible automatic production job |
| Existing deployment platform's approval feature | Verify plan eligibility, identity separation, credentials, and rejection behavior before use |

A manual workflow trigger under an agent-accessible identity is not a human approval gate. If preventing self-review would block the sole owner's workflow, define and test the triggering identity before choosing that configuration. Approval evidence must identify the deployed commit. Production access stays unavailable until the selected boundary passes its own test.

## 5. Execution boundaries and limits of the controls

Threat model: an agent may make a mistake, follow hostile repository content, or ignore its instructions. Tests provide evidence for specific controls; they do not prove that every possible bypass is impossible.

| Area | Proposed boundary | Limit / required evidence |
|---|---|---|
| Files and processes | Prefer a disposable, isolated runtime with only the target repo and required dev data | A branch/worktree separates Git state, not OS access; inspect mounts, user permissions, helpers, sockets, and inherited credentials |
| Local execution | Explicit permission mode plus verified provider sandbox, where supported | A thread on the daily workstation is not assumed disposable or restricted; use supervised execution until its boundaries are established |
| Merge | Separate agent identity plus effective GitHub rules | Test rejected direct push and merge without owner review in a disposable test repository/branch with matching rules |
| Production | No development access to production credentials or endpoints where enforceable | Check all credential sources and network paths; absence from one vault alone is insufficient |
| Secrets | Provide only task-specific development credentials when needed | Read-only vault access limits mutation, not use of credentials; injected secrets are readable by their receiving process |
| Providers and network | Use only approved providers; enforce destination restrictions externally if that guarantee is required | A registry flag or missing API key is not an egress control; free/unauthenticated endpoints may exist |
| Spending | Avoid new paid APIs in the pilot; verify provider-side limits for any existing paid access | No billing login does not prevent usage charges through an existing key; alerts are not hard caps |
| Hooks and policies | Instructions, deny rules, and scanners help prevent mistakes | They do not replace OS, credential, network, or GitHub boundaries |

[1Password `op run`](https://developer.1password.com/docs/cli/reference/commands/run/) injects secrets into the launched process environment. If adopted later, use scoped development access and verify plan eligibility and runtime exposure; do not describe it as hiding secrets from agents.

Document each control as observed, tested, proposed, or unavailable. Where enforcement is missing, restrict scope or require supervision and state the residual risk. Do not use the earlier “structurally impossible” or “no agent can bypass” claims.

## 6. Pilot workflow, review trigger, and recovery

### 6.1 One task through merge

| Stage | Action | Evidence |
|---|---|---|
| Intake | Owner/lead selects a small real task and records acceptance criteria and bounds in an issue or PR | Task link and agreed scope |
| Implementation | Claude works in its assigned branch/runtime and runs relevant existing checks | Commit SHA and check results |
| Review handoff | Lead or owner explicitly starts a Codex Cloudroom child thread with repo, base/head SHAs, acceptance criteria, and review scope | Thread reference and immutable reviewed SHA |
| Independent review | Codex inspects the diff and relevant behavior in a separate context and reports findings as PR comments or linked review output | Findings, tests, risks, and reviewed SHA |
| Correction | Implementer fixes findings; changed commits receive another review within the remaining budget | Updated checks and review |
| Approval | Owner reviews the final commit and CI results under the human identity | GitHub approval |
| Integration | Merge after the gates pass (owner at the time of writing; superseded by the [2026-10-25 standing authorization](decisions/2026-10-25-agent-merge-and-deploy.md): the agent identity merges and reports); record outcome in the PR | Merge SHA and brief result |

A `needs-review` label is informational in the pilot; there is no watcher or automatic reviewer trigger. Reviewer results must identify the final commit. If the head changes, earlier findings remain historical and approval must be refreshed as configured. CI success alone does not prove acceptance criteria.

Keep task state in the PR/issue. Reserve ADRs for consequential architecture decisions; avoid a new ADR for every small task. A short `docs/progress.md` may link current work, but must not become a competing task database. Record completion in the PR rather than making an unreviewed post-merge commit.

### 6.2 Bounds and stop procedure

Before a launch, record the provider, runtime, permission mode, supported limits, owner/operator, deadline, and remaining retries in the task record.

| Bound | Initial rule | Enforcement / fallback |
|---|---|---|
| Active work | One implementer and one reviewer; no recursive delegation | Lead/operator checks active task threads before launch; policy until runtime support is tested |
| Corrections | At most two correction/review cycles per task; at most two retries of an operation | Track counts explicitly; exhaustion produces a blocker, not an automatic relaunch |
| Wall time | Explicit deadline for each active run | Use a verified runtime timeout if available; otherwise an attended operator must stop the run at the deadline |
| CI | Set finite job `timeout-minutes` appropriate to the application | Test an intentional failure in the pilot |
| Paid usage | Record available provider limits and remaining allowance | Use provider-enforced caps when available; otherwise supervised use only, with no claim of a hard cost limit |

Instructions and counters are conventions unless an external runtime enforces them. One-turn queues, idle sleep, and weekly usage summaries do not cap active execution or cost. If an unattended run cannot be stopped by a verified external limit, do not run it unattended.

At a deadline, repeated failure, provider outage, or uncertain completion:

1. Operator stops only the task's known Cloudroom thread IDs, including children, using the installed `thread stop` interface. Do not assume stopping a parent stops its children or background processes.
2. Inspect each task thread's queue and owned background jobs; cancel unintended queued work and stop only processes started for the task. Verify stop completion before launching a replacement.
3. Record last committed SHA, uncommitted work, completed/uncertain side effects, test results, remaining budget, and blocker in the PR/issue.
4. Before resuming, inspect repository and PR state and reconcile uncertain operations. Do not blindly repeat pushes, deployments, or external writes.
5. Resume explicitly within the remaining bounds. If exhausted, return the blocker to the owner with the evidence needed for a new decision.

Stop, queue cancellation, restart, and credential revocation behavior must be exercised on disposable task resources before unattended operation is considered.

## 7. Runtime and mobile verification

Record exact app/CLI and harness versions, execution mode (project checkout, worktree, hosted sandbox, or self-hosted host), permission mode, and whether each test passed. Use the installed commands and current documentation; option presence is not a passing test.

For Claude and Codex separately:

- Run a harmless in-workspace action, a harmless out-of-workspace access probe, and a harmless approval/deny interaction in disposable fixtures. Record what was blocked, prompted, allowed, or unsupported.
- Verify the intended credential identity without printing tokens. Check the runtime's ability to read an owner-only dummy file and platform credential locations without opening real secrets.
- Exercise stop, interruption, queue handling, and explicit resume, including a child thread and a task-owned background process.
- Test phone monitoring, answering a question, and approving/denying an action through the intended UI. Test a GitHub review on the separate-agent pilot PR.

Cloudroom CLI 0.43.1 advertises permission modes and `thread interactions` for approvals, denials, and questions. Provider and hosting support may differ. Do not infer phone behavior or native Claude-app connectivity from those interfaces. The Claude app, Cloudroom mobile web, and GitHub mobile are candidate channels; mark each tested or unavailable for the selected setup.

Failure of mobile action approval limits unattended remote operation; it does not justify silently switching permission modes. No custom relay or Hermes gateway is required to complete the initial development pilot.

## 8. ECC and repository conventions

### 8.1 Preserve existing installs until ownership is known

The audit kit can suggest where to look; it does not prove duplication. Manual skills and a plugin can coexist without invoking the same hook twice.

Before any ECC cleanup, inventory source/version, install manifests, enabled plugin entries, hook registrations, resolved script paths, and relevant file ownership. Identify actual duplicate registrations and preserve unrelated/custom files. Propose exact changes and a backup/rollback method before removal. Do not uninstall based on directory presence or counts, and do not assume an uninstall command exists for the installed route.

For the pilot, keep working configuration. Add only skills needed for the selected task; no blanket reinstall or global migration is required. If importing skills later, preserve license/attribution, pin their source, and test discovery per harness. Reading `AGENTS.md` does not prove full hook or skill portability.

### 8.2 Minimum project layout

```text
<project>/
├── .bb/AGENTS.md                Cloudroom entry point referring to AGENTS.md
├── AGENTS.md                    shared workflow and conventions
├── CLAUDE.md                    Claude-specific additions/import, if needed
├── docs/
│   ├── architecture.md
│   └── decisions/               only consequential decisions
├── .github/
│   ├── CODEOWNERS
│   ├── pull_request_template.md
│   └── workflows/               application's relevant CI
└── existing source and tests
```

Reuse existing repository conventions. This system repository now holds the shared instruction foundation, setup record, proposal, and audit tools. Cloudroom's installed guide documents .bb/AGENTS.md as the provider-neutral entry point; it refers to the canonical root AGENTS.md, and CLAUDE.md imports that root file. Application-specific templates can follow later. Do not create empty policy files, adapter directories, or a parallel task store merely to match a diagram.

## 9. Milestones, cost, and acceptance

| Milestone | Scope | Exit evidence |
|---|---|---|
| A. Establish prerequisites | Use this setup repository first; verify plan, separate GitHub identity, runtime boundaries, relevant checks, and supported limits | Redacted capability/permission record; owner configures gates |
| B. Prove one task | Claude implements; Codex independently reviews; CI runs; owner approves and merges (merging superseded by the [2026-10-25 standing authorization](decisions/2026-10-25-agent-merge-and-deploy.md)) | Task, PR, final reviewed SHA, approval, CI and merge evidence |
| C. Exercise failure/recovery | Reject unauthorized push/merge, fail CI, interrupt a task, simulate provider unavailability, resume safely | Disposable test evidence and documented residual risks |
| D. Verify mobile operation | Test the chosen phone interfaces with the actual providers/mode | Per-action pass/fail record; no inference from CLI help |
| Later, individually justified | OpenCode, parallel implementers, Hermes, Pi, decision models, deployment automation | Separate scope, cost, credentials, and acceptance criteria |

The first milestone is complete only after B and the relevant safety/recovery tests in C pass. Mobile success in D is required before claiming phone-operated unattended work. Additional harnesses and production deployment are not initial completion criteria.

Documentation changes add no runtime dependency. Execution may consume subscription allowance or paid CI/API usage; private-repository protections may require a plan upgrade. No new spend, hosting, or credential provisioning is assumed to be approved by acceptance of this document. Record actual eligibility and cost before selecting a paid option.

A negative permission test must use disposable resources with matching rules and an identified agent credential. If an unauthorized write unexpectedly succeeds, contain it, record the failure, and repair the boundary before retrying. A missing boundary is a failed test, not a documentation exception.

## 10. Deferred decision support

Do not implement a provider registry or adapters for the pilot. Independent Claude/Codex analysis on consequential choices can use the existing review handoff, recording evidence, uncertainty, disagreement, and rationale.

A later registry could describe approved providers, capabilities, privacy, cost, and discovery. Its settings would govern only clients that use it. It would not itself enforce network access or spending. Keep model capabilities attached to a tested model/runtime version rather than assuming a harness has one fixed context limit.

Jev, “Ting Cactus,” and Laya remain research candidates from the historical brief, with identity/access/pricing/privacy to be verified if selected. No new provider credential, API request, adapter stub, or service is needed now.

## 11. Implementation boundary

The repository now contains shared project instructions, the setup record, revised proposal, and audit inventory labels. This foundation does not provision agent identities, alter branch rules, install or remove ECC, change runtime permissions, start other agents, merge the PR, or enable deployment.

Approval of the direction allows planning the pilot. Credential setup, actual plan eligibility, pilot-task selection, and runtime test results must be resolved before claiming the proposed gates work.
