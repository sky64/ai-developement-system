# Existing Cloudroom setup

This repository is the setup workspace for the installed Cloudroom app. Another application repository is not required to configure the workflow.

## Current state as of 2026-10-22

| Item | Result |
|---|---|
| Cloudroom | CLI 0.43.1 connected to the existing local project |
| Project | ai-developement-system, current checkout |
| Claude provider | Registered and available; installed CLI 2.1.303 |
| Claude authentication | Installed binary reports logged in through claude.ai |
| Codex provider | Registered and available; installed CLI 0.163.0 |
| Codex authentication | CLI reports logged in using ChatGPT |
| Worktree environment | Registered and reports available for this project/machine; creation not tested |
| Other providers | Pi, OpenCode, Hermes and others are registered; not needed for this first setup |
| Shared project instructions | Consumed by Claude (CLAUDE.md, AGENTS.md, .bb/AGENTS.md) and by Codex (.bb/AGENTS.md, AGENTS.md) in the [smoke test](04-smoke-test.md) |
| Claude → Codex handoff | Exercised once on 2026-10-19: local commit, Codex child in a Worktree, findings returned to the lead. See the [smoke test](04-smoke-test.md). No deadline was recorded; the lead ran in the checkout, not a Worktree. |
| Permission/stop/mobile tests | Permission mode accept-edits and stop/resume exercised on 2026-10-22, see the [matrix tests](08-matrix-tests.md). No hard-limit flag found in the installed CLI. Phone approval tested the same day: denial from the Cloudroom phone app verified end to end; approval verified only as far as the permission gate, because the approved route failed at the egress proxy with a repeatable 502, and the orchestrator also granted the record from the CLI, so the phone action's contribution cannot be isolated. Observed: interaction records stayed pending after app decisions and the next command was rejected; reported to Cloudroom through feedback as a suspected defect, cause unconfirmed. |
| Restricted agent GitHub identity and merge gate | Verified 2026-10-22: the agent identity `Solvela-bot` is a collaborator with write permission, main requires one approving review with admin enforcement and no force pushes, and PR 2 was authored by `Solvela-bot`, reviewed by Codex thread thr_h93fu5fccb, then approved and merged by the owner. See the [agent identity record](09-agent-identity.md). The PR adding the automated path there is the first from a Cloudroom cloud sandbox. Token rotation, self-approval refusal, bypass, and revocation of the device-code grant are unverified. |
| Orchestrator write guard | Hook and unit test added 2026-10-20; live test passed on 2026-10-20. See the [enforcement test](06-enforcement-test.md). |

Provider availability and login checks do not prove a model request, role handoff, sandbox, or approval gate works.

Claude's launcher at ~/.local/bin/claude runs a mise update/configuration step on every invocation. A status check through that wrapper timed out. A read-only check using the installed binary resolved by mise which claude succeeded. The wrapper has not been edited; if thread startup also stalls, investigate it before changing provider permissions or reinstalling Claude.

## Project instruction wiring

- [AGENTS.md](../AGENTS.md) contains the shared workflow and role assignments.
- [.bb/AGENTS.md](../.bb/AGENTS.md) tells Cloudroom provider sessions to read that canonical file.
- [CLAUDE.md](../CLAUDE.md) imports AGENTS.md for Claude's native instruction handling.

The installed room-cli guide agent-configuration documents Cloudroom's .bb/AGENTS.md entry point and says instructions are assembled when provider sessions start. A new thread/session is needed to verify discovery; writing these files does not prove they have been consumed. No global instructions or app permissions were changed.

There is no custom router or background service. Roles are carried by the project instructions and explicit task handoff.

## First run in this project

Start with this repository as the task workspace:

1. Use a new Cloudroom thread in this existing project with Claude Code as provider. For implementation, prefer the Worktree environment based on the branch containing these setup files. Keep the initial task attended and select a permission mode that the provider exposes; do not assume its enforcement before testing.
2. Give Claude a small setup task with acceptance criteria, such as inspecting these instructions and identifying a concrete missing setup check. Ask it to read AGENTS.md and report its role, branch, instruction paths, and proposed change before editing.
3. When explicitly requesting independent review, launch a Codex Cloudroom child thread against the intended commit. Include base/head SHAs, scope, expected behavior, and check output. Do not silently launch a different provider or reuse the implementation context as independent review.
4. Record results and any failures here or in the task PR. A file-only review can begin before GitHub identity separation, but it must not be reported as proof of enforced approval.
5. Before treating the workflow as unattended or protected, complete the runtime, separate-identity, rejection, stop/recovery, and phone tests in the architecture and capability matrix.

The task can stay focused on this Cloudroom setup. Move to another application only when the foundation works and an application task is useful.

A reusable initial lead prompt:

> Read AGENTS.md and docs/03-cloudroom-setup.md. Act as the lead for this Cloudroom setup project. Inspect the current foundation and propose the smallest missing setup improvement. Report your provider, branch, instruction paths, acceptance criteria, and verification before editing. Do not change credentials, global configuration, permission modes, or launch other agents.

A reusable independent-review handoff, when requested:

> Read AGENTS.md. Review the changes between the supplied base and head SHAs in a fresh context. Check the requested behavior and relevant failure cases. Do not edit files or merge. Return the reviewed SHA, findings with file/line references, verification, and remaining uncertainty.

## Checks performed for the foundation

The installation/provider and authentication checks above were read-only, apart from the existing Claude launcher invoking its own mise configuration/update step before timing out. The successful direct-binary authentication check did not invoke that wrapper.

Repository validation covers whitespace, Markdown local links/code fences, and Bash syntax for the existing audit script. No model task or child thread has been started as part of this foundation setup. No paid provider, extra service, global dependency, deployment, repository rule, or credential change is required merely to add the project instructions.

See the [architecture](01-architecture-proposal.md) for prerequisites before claiming enforcement and the [capability matrix](02-compatibility-matrix.md) for the outstanding behavioral tests.
