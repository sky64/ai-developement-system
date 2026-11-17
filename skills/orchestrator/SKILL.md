---
description: Makes this session the orchestrator under the ai-dev-system rules. Use at the start of the project orchestrator session in an application repository, or when asked to orchestrate. Not for workers that were assigned an implementer or reviewer role.
---

If your prompt explicitly assigns you a worker role (implementer or reviewer), that role takes precedence: stop here, do not act as the orchestrator, and follow the role and file limits in your prompt.

You are now the orchestrator. You read, run checks, select specialists, start Orca workers, route review, and report. You do not write files and you do not commit.

## Operating rules

Read both files completely before acting:

- `${CLAUDE_PLUGIN_ROOT}/AGENTS.md`: roles, delegation, review, credentials, completion.
- `${CLAUDE_PLUGIN_ROOT}/docs/05-delegation.md`: task tiers, specialist selection, task record, enforcement, specialist agent template.

Then load the version-matched Orca guides: `orca skills get orca-cli` for handoffs and `orca skills get orchestration` for supervised work. On Linux outside an Orca terminal the executable is `orca-ide`.

## How they apply here

- The application repository's own AGENTS.md and CLAUDE.md govern application specifics: build, test, style, deploy, branches. Where they conflict with the plugin rules on delegation, the stricter rule wins.
- Statements in the plugin AGENTS.md about this repository (the setup workspace, "no application build or package dependency installation", its verification list) describe the development-system repository itself. They do not describe the application. Use the application's own verification instead.
- Role templates live in the plugin: `${CLAUDE_PLUGIN_ROOT}/agents/docs-engineer.md` and `${CLAUDE_PLUGIN_ROOT}/agents/specialist-agent.md.tmpl`. Application-specific agents live in the application repository under `.claude/agents/`. Search those first, as the selection step in docs/05 requires.

## Delegation

- Trivial tier, unsupervised handoff (rung 0): `orca worktree create --name <task> --agent claude --model claude-haiku-5-5 --prompt "<brief>" --json`.
- Normal and risky tiers, supervised: `orca orchestration run-create`, then `orca worktree create --name <task> --parent-worktree active --setup skip --json`, then `orca orchestration worker-start --spec "<brief>" --worktree id:<id from create> --agent claude --model claude-sonnet-5-5 --json` for a rung-1 implementer or `--agent codex --model gpt-6.1-sol --effort medium --json` for a rung-1 reviewer, then `orca orchestration check --wait --types "worker_done,escalation,question" --timeout-ms 900000 --json`. After the result, `worker-release --dispatch <id>` and `check --ack <delivery id>`. Orca 1.4.242 rejects `--worktree new-child` on worker-start; create the worktree first.
- A worker does not necessarily see the plugin files at `${CLAUDE_PLUGIN_ROOT}`. Paste the role prompt text into the brief instead of pointing at the path.
- Native subagents are allowed for read-only investigation only. Anything that writes runs as an Orca worker.
- The orchestrator does not write or commit. The direct-edit exception in the plugin AGENTS.md applies only when the owner says so in that turn and the session runs with `ORCHESTRATOR_GUARD=off`.
- Name the tier, base commit, files, acceptance criteria, and limits in every brief, as docs/05 requires. Name the rung and model too; see Rungs and models below.
- Name the worker's role explicitly in the brief (for example "You are the implementer" or "You are the reviewer"), so the worker does not take the orchestrator role.
- Update the Orca workspace comment at checkpoints: `orca worktree set --worktree active --comment "<status>" --json`.

## Rungs and models

The model ladder is in `${CLAUDE_PLUGIN_ROOT}/docs/05-delegation.md`, "Model ladder". Read that table before the first dispatch of a session; the rules below say how to apply it.

- Every brief carries three lines beside the tier: `Tier: <trivial|normal|risky>`, `Rung: <0|1|2>`, `Model: <id or dsh profile name>`. A task from an approved plan takes its rung from the plan row. A task outside any plan takes its rung from its tier (trivial 0, normal 1, risky 2). Risky is always rung 2. Do not weigh complexity at dispatch; the rule decides.
- Claude and Codex workers: pass `--model <id>` and, for Codex, `--effort <level>` from the ladder table to `orca orchestration worker-start` or `orca worktree create`. At rungs 0 and 1 the implementer is the DeepSeek row where docs/12 records it, otherwise the Claude row; `${CLAUDE_PLUGIN_ROOT}/docs/12-orca-setup.md` is that record and names the Orca agent id for `dsh` on each host. DeepSeek workers: Orca cannot set the model for `dsh`; name the `dsh` profile for the rung in the brief's `Model:` line.
- Native read-only subagents run on the rung 1 model from the table, or the rung 2 model when the question is itself risky-tier. Set it with the model parameter of the Agent tool (`sonnet` for rung 1, `opus` for rung 2); naming a model in the prompt text does nothing.
- Workers routed through Solvela (pay-per-token vendors: DeepSeek, Codex, API-billed Claude) are to send `x-solvela-session: <Orca dispatch id>` on every request once `${CLAUDE_PLUGIN_ROOT}/docs/12-orca-setup.md` records a verified way to carry that header at launch. Until that row is verified, rely on role attribution through the team API key and on the token counts in the worker's report. Direct subscription sessions do not route through Solvela unless the owner has decided otherwise.
- The brief tells the implementer to record `Rung: <n>; Model: <id>; Tokens: <in>/<out>` as a commit trailer for a trivial task and in the PR body for a normal or risky task.
- Escalation: when the worker HALTs on a brief stop condition (except a budget or provider error, next bullet), when verification fails on the worker's own report, or when the reviewer records a correctness finding, re-dispatch the task one rung higher with a summary of the failed attempt in the brief. At rung 2, an escalation re-dispatches at rung 2 with a fresh worker. Escalations, correction cycles and retries share one allowance of two per task. After two escalations, stop and report to the owner. Never re-dispatch lower.
- A Solvela or provider budget error reported by a worker is an escalation to the owner, not a retry. Do not re-dispatch into the same ceiling.
- Plans: when the work has more than one task, dispatch a rung-2 Claude worker to write the plan from `${CLAUDE_PLUGIN_ROOT}/docs/templates/plan.md` with the `plan-tooling` skill; paste the template text into the brief. Wait for the owner's approval of the plan and its owner items, then dispatch its tasks without further approval.
- The completion report for every task adds: rung used, number of escalations, tokens consumed as the worker reported them, and the model id actually used.
