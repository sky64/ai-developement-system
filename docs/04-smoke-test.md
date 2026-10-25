# Smoke test: Claude implementation → Codex review

Note 2026-10-25: owner-merge statements in this record predate the [2026-10-25 standing authorization](decisions/2026-10-25-agent-merge-and-deploy.md).

Date: 2026-10-19. Requested by the owner in Cloudroom thread thr_nveh5eysxj. Scope: create this file, commit it locally, start one Codex child thread to review the commit, and report. No push, merge, permission change, or credential access.

## Run record

| Item | Observed |
|---|---|
| Lead thread | thr_nveh5eysxj, provider claude-code, model claude-fable-5-1, reasoning high |
| Environment | Project checkout at the repository root, branch claude/cloudroom-multi-agent-setup-ckmyut, base commit 29f0051 |
| Worktree | Not used for the lead. The suggested procedure was a Claude thread in a Worktree; the prompt was sent to the existing checkout thread instead. Recorded as a deviation, not hidden. |
| Permission mode | The harness reported bypass-permissions (Cloudroom `full`) for this turn. The machine ceiling is `full`. Nothing about this run proves a lower mode would have blocked anything. |
| Runtime limits | None enforced. The run was attended by the owner. Retry allowance: two per failed operation, per AGENTS.md. |
| Deadline | None was set before the run. AGENTS.md requires one. Recorded as a deviation; the reviewer caught it (see Result). |
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
2. Claude records scope, runtime, permission mode, deadline, limits, and retry allowance before starting the reviewer. In this run the table above was written without a deadline.
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

Reviewer: Cloudroom thread thr_pwtuszetdh, provider codex, model gpt-6.1-sol, reasoning high, Worktree at `~/.gui-cloudroom/plugins/environment-git-worktree/host-data/worktrees/thr_pwtuszetdh-1/ai-developement-system` on branch `room/codex-review-smoke-test-commit-e30f857-etdh`. Reviewed SHA: e30f857.

Codex reported that it received `.bb/AGENTS.md` through Cloudroom's injected workspace instructions and the root `AGENTS.md` as user-provided instructions, and that `CLAUDE.md` was not loaded automatically. That is the expected split: `CLAUDE.md` is Claude's native import; the shared text reaches Codex through the Cloudroom entry point.

Codex verified HEAD, the single-file diff, `git diff --check`, the two relative links, the code fence, that the documented spawn flags exist, and that the file does not claim permission enforcement, identity separation, or merge gates. Its worktree was left clean at e30f857.

Findings from Codex:

- Medium, docs/04-smoke-test.md step 2: the text said a deadline was recorded, but the run record had none. AGENTS.md requires a recorded deadline and a stop at it. Resolved in this follow-up by recording the omission in the run record and correcting step 2. The underlying gap stands: no deadline was set for this run.

Codex's stated limitations: it could not independently confirm Claude's startup load order, global-rule consumption, permission mode, or owner attendance. Those are lead-reported.

Pass criteria:

| Criterion | Outcome |
|---|---|
| Claude loads the shared instructions | Pass, lead-observed (see list above) |
| Change made in the lead's own worktree | Deviation. The lead ran in the project checkout; only the reviewer used a Worktree. |
| Codex independently reviews the correct commit | Pass. Fresh thread, fresh Worktree, correct SHA, Codex also received the shared instructions. |
| Claude receives and reports Codex's findings | Pass. Cloudroom delivered the child's final message to the lead thread, and `room-cli thread output thr_pwtuszetdh` returned the same text. |

Correction cycles used: one of two. Retries used: none. The reviewer thread was left open for the owner to inspect; archiving it releases its Worktree.
