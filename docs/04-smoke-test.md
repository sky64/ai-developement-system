# Smoke test: Claude implementation → Codex review

Date: 2026-10-19. Requested by the owner in Cloudroom thread thr_nveh5eysxj. Scope: create this file, commit it locally, start one Codex child thread to review the commit, and report. No push, merge, permission change, or credential access.

## Run record

| Item | Observed |
|---|---|
| Lead thread | thr_nveh5eysxj, provider claude-code, model claude-fable-5-1, reasoning high |
| Environment | Project checkout at the repository root, branch claude/cloudroom-multi-agent-setup-ckmyut, base commit 29f0051 |
| Worktree | Not used for the lead. The suggested procedure was a Claude thread in a Worktree; the prompt was sent to the existing checkout thread instead. Recorded as a deviation, not hidden. |
| Permission mode | The harness reported bypass-permissions (Cloudroom `full`) for this turn. The machine ceiling is `full`. Nothing about this run proves a lower mode would have blocked anything. |
| Runtime limits | None enforced. The run was attended by the owner. Retry allowance: two per failed operation, per AGENTS.md. |
| Reviewer | One Codex child thread, spawned through room-cli with `--parent-self`, in a fresh Worktree based on this branch so it sees the committed file without a push. Model: the Codex default on this machine. |

## Project instructions loaded

Observed in the lead session's context at startup, in this order:

1. `CLAUDE.md` at the repository root. It imports `AGENTS.md` with `@AGENTS.md` and adds the role summary.
2. `AGENTS.md` at the repository root, the canonical workflow and policy text.
3. `.bb/AGENTS.md`, injected by Cloudroom as "workspace instructions". It points back to the root `AGENTS.md`.
4. Nine global user rule files under `~/.claude/rules/ecc/common/` (agents, code-review, coding-style, development-workflow, git-workflow, hooks, patterns, performance, security). These are machine-wide ECC rules, not part of this repository.

So the wiring documented in [03-cloudroom-setup.md](03-cloudroom-setup.md) works: a new Claude turn in this project receives the shared instructions through both the Cloudroom entry point and Claude's native import. This verifies consumption for Claude only. Codex consumption is checked by the reviewer below.

### Conflict found

The global ECC rules tell the agent to start native subagents immediately (planner, code-reviewer, tdd-guide) and to "ALWAYS use parallel Task execution". The project `AGENTS.md` forbids native harness subagents and requires Cloudroom child threads for delegation. In this run the project rule won because the user's prompt was explicit. That is a convention holding, not an enforced boundary. If the global rules stay installed, every agent prompt should state the delegation method, or the global ECC rules should be scoped away from this project.

## How the handoff works

1. Claude reads `AGENTS.md` and the setup record, makes the change in its environment, and commits it locally. The commit SHA is the review target.
2. Claude records scope, runtime, permission mode, deadline, limits, and retry allowance (the table above) before starting the reviewer.
3. Claude starts exactly one Codex child thread:

   ```sh
   room-cli thread spawn --parent-self --project "$ROOM_PROJECT_ID" \
     --provider codex \
     --new-environment worktree --base-branch claude/cloudroom-multi-agent-setup-ckmyut \
     --title "Codex review: smoke test commit" \
     --prompt "<review brief with base SHA, head SHA, changed files, acceptance criteria, check results>"
   ```

   The Worktree is created from the local branch, so the reviewer sees the commit without a push. `--parent-self` links the child to the lead so Cloudroom delivers the child's final message back to the lead thread.
4. Codex reads the project instructions in its own session, reviews the diff between base and head, and replies with the reviewed SHA, findings with file and line references, what it verified, and what it could not verify. It does not edit, commit, or merge.
5. Claude receives the reply as a message in the lead thread, records it here, and reports to the owner. The owner decides what to merge.

Acceptance criteria given to the reviewer: the file exists at `docs/04-smoke-test.md`; it lists the instruction files loaded; it describes the handoff; the commit touches only that file; `git diff --check` is clean; the Markdown links resolve.

## What this test does and does not prove

Proves, if the reviewer reports back correctly:

- Claude loads the shared instructions in this project.
- A Cloudroom child thread can be started from a Claude thread with room-cli.
- Codex reviews the intended commit in a separate environment and context.
- The child's result reaches the lead.

Does not prove:

- That any permission mode blocks an action. The lead ran with full permissions.
- That the reviewer is independent in the security sense. Both agents run as the same OS user and the same GitHub identity.
- That stop, resume, deadline, or phone approval work.
- That GitHub rejects an unauthorized merge.

Those remain open in the [capability matrix](02-compatibility-matrix.md).

## Result

Pending at the time of this commit. The reviewer's findings and the final verdict are added in a follow-up commit so the reviewed SHA stays fixed.
