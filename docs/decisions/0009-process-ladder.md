# 0009: A process ladder: small, bounded work runs native; risk still decides review

Date: 2026-11-18. Status: accepted by the owner in the Orca chat of 2026-11-18 (thoughts and full design laid out; owner approved and answered the three open questions: file threshold 3, Codex on every native code change, mode recorded in the Orca workspace comment). Implemented by [the process-ladder plan](../superpowers/plans/2026-11-18-process-ladder.md), after decision 0008 merges.

## Intent

The owner's belief, revised 2026-11-18 after reading on harnesses: the goal of this project is to pick the right process as well as the right model. Running a one-file fix through a worker, a brief, a wait and a reviewer handoff wastes tokens on overkill. Two rounds of three and four tasks each ran natively in one session that day, with one Codex review of the finished branch, and the waste that day was in review cycles, not in a shortage of sub-agents.

Three corrections to the first framing, agreed with the owner:

- **Do not gate on time to complete.** An estimate made before the work is a guess. Gate on facts checkable before starting (one task, how many files, one logical change, no new dependency), and add a runtime escalation that only climbs.
- **Risk decides review; size decides process.** docs/05 already says risk decides the tier, not size. A one-line change to a money path still gets Codex. Two axes: tier decides whether a reviewer is required, mode decides where the work runs.
- **Native still means a worktree and a pull request.** The saving is the brief, the duplicated context and the babysitting loop, not the branch. The guard already allows writes inside any worktree and its working directory follows a `cd`; only the skill's prose forbids the orchestrator from writing.

## Goals

- Every task carries a mode, native or delegated, decided by checkable facts and recorded in the plan, the completion report and the Orca workspace comment.
- Native mode: the session does the work itself in a task worktree, tests first, and still produces a branch, a PR and, when the tier or the change requires it, a Codex review.
- A runtime escalation from native to delegated that never goes back.
- A switch and config thresholds, and the numbers to tune them after one review period.

## Non-goals

- Changing what the guard allows inside a repository. The main checkout stays read-only for the orchestrator.
- Removing the planned path. Multi-task work still gets a plan and delegated tasks.
- Estimating effort or duration anywhere in policy.

## Anti-goals

- A native task that silently grows: the thresholds are counted, and crossing one is an escalation with a record, not a judgment call.
- A mode chosen by mood: the decision table has no "feels small" row.
- Losing the record: native work writes the same completion report as delegated work.

## Constraints

- The orchestrator session's shell working directory persists across Bash calls in Claude Code, and the guard's hook payload carries that directory; a session that moves into its worktree is, to the guard, inside a worktree. The existing guard test "worktree allows Write inside" covers it; a new test pins the pair (inside allowed, main checkout still denied from the same session shape).
- Tool-call counting is the orchestrator's own count in the task record; nothing executable enforces it this round.
- Risky tier throughout; rung 2; Codex at effort high; Runtime floor Python 3.13+ and bash on Linux.

## Approaches considered

1. **Two-axis rule: tier for review, mode for process, with native work done by the orchestrator in a task worktree** (chosen).
2. **Keep every write in a worker but make trivial handoffs cheaper.** Rejected: the brief and the context duplication are the cost, and a handoff keeps both.
3. **A lease that lets the orchestrator write in the main checkout for small tasks.** Rejected: breaks the clean-main-checkout invariant and needs a guard change with a new trust anchor; the worktree already gives write room for free.

## Decision

### 1. Modes

| Mode | Who works | Where | Review | When |
|---|---|---|---|---|
| native | the orchestrator session itself | a task worktree it creates and moves into | trivial tier: none; normal tier: one Codex review of the diff when any code changed (docs-only diffs skip it); risky: never native | all of: one task; at most `process.native_max_files` files (default 3); one logical change; no new dependency; tier trivial or normal |
| delegated | one Orca worker per task, plus the reviewer | the worker's worktree | by tier, as today | any of: risky tier; more than one task; tasks that could run in parallel; work that must run unattended or past a session; the owner says so |

Planned work (docs/05, Plans and owner items) stays as it is, with a Mode column per task row so a plan can mark small sequential tasks native.

### 2. Escalation

A native task that touches more than `process.native_max_files` files or passes `process.native_max_tool_calls` tool calls (default 40) stops, commits its work in progress on the task branch, and hands the worktree to a worker with a brief that names the files touched and what remains. The mode never goes back to native for that task. Escalations draw on the same allowance as correction cycles (`limits.review_cycles`, decision 0007).

### 3. Native procedure

Create the worktree (`orca worktree create --name <task> --parent-worktree active --setup skip --json`), move into it, run the task's tests first, implement, run the repository's verification list, commit, push, open the PR, then review per tier, then return to the main checkout. The completion report is the same as for delegated work plus `Mode: native`. The Orca workspace comment is set at task start to `<task>: mode=native tier=<tier> rung=<rung>` and updated at completion, so crew64-map can chart mode from the start.

### 4. Config and switch

```json
"process": { "default_mode": "auto", "native_max_files": 3, "native_max_tool_calls": 40 }
```

`features.process_ladder`, boolean, default true; off means every task is delegated, as before this record. `process.default_mode` is `auto` (the table decides), `native` (the table still forbids native for risky or multi-task work) or `delegated`. `CREW64_PROCESS_MODE=auto|native|delegated` overrides the file for one session. The two thresholds are integers of at least 1. Missing section or invalid values read as the defaults; `check` names a bad value. The status line gains ` process=<mode> max_files=<n> max_calls=<n>`.

### 5. Text

- AGENTS.md: "the orchestrator does not write code or commit in the main checkout; in native mode it works in a task worktree (docs/05, Process ladder)". The direct-edit exception stays as the only way to write in the main checkout.
- Orchestrator skill: a `## Process ladder` section with the table, the procedure and the escalation; the "You do not write files" sentence becomes "in the main checkout".
- docs/05: a `## Process ladder` section after Model ladder; the Task record adds mode; Ladder review adds the process numbers to collect (tasks by mode, tokens and wall time per task, review findings per mode, escalations native to delegated).
- Plan template: a Mode column.
- Guard hook: the deny message adds "or, for a native task, move into its worktree first (orchestrator skill, Process ladder)".
- Pins for all of the above; plugin 0.8.0.

## Left to the builder

- Exact wording of the status-line field and the workspace-comment line.
- Whether `native_max_files` counts files created as well as modified (it should: count everything in `git status --porcelain` of the task worktree).

## Consequences

- Small tasks cost one context instead of three. Normal-tier native code changes still pay for one Codex review, which the owner chose.
- The thresholds are a starting point. The ladder review collects the numbers; changing them is a new decision record citing them, like the model ladder.
