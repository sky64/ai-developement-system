# 0004: A model ladder, set in the plan, that only climbs

Date: 2026-11-17. Status: accepted by the owner in the Orca chat of 2026-11-17 (approach and recommendations approved; remaining calls delegated to the agent and listed in this record). Design record for the v2 efficiency work; implemented by [the model ladder plan](../superpowers/plans/2026-11-17-model-ladder.md).

## Intent

The owner's goal for v2 of this harness, stated 2026-11-17: use lesser models for lesser jobs, and never let that saving take away the proper tools. Work should be done to the best of our abilities, and waste should be cut where it is plainly visible. The owner also named the hazard: that line is hard to define and swings with mood. So the mechanism has to make the choice once, in a reviewed place, and remove it from the moment of dispatch.

## Goals

- Every task runs on the cheapest model rung that its complexity allows, decided in the plan and reviewed there.
- The skills, agents, MCP servers and rules a task uses are chosen by the `plan-tooling` contract and are identical at every rung. A cheap model never means a shorter toolbox.
- Model changes during a task go in one direction only: up.
- Spend becomes a table of numbers per role and rung, so "plainly see waste" is read off a report rather than felt.

## Non-goals (separate rounds, not this one)

- Building a prompt cache or an automatic model picker. Solvela, the owner's gateway, already ships both (exact and semantic cache, 15-dimension router); this round uses it for measurement and caching and does not build a second one (see Approaches, option 2).
- Shared agent memory across projects and vendors.
- Parallel design, research and build teams as a standing structure.
- Any change to the risk tiers or the guard hook. They stay as adopted in [0001](0001-tiered-protocol.md) and [05-delegation.md](../05-delegation.md).

## Anti-goals (this would be failure even if it works)

- A rung-0 model assigned to a risky-tier task to save money.
- The orchestrator picking a model ad hoc in a worker brief, or changing the ladder table mid-task.
- A worker told to skip a skill, reviewer, or verification step because it runs on a cheaper model.
- Ladder edits made from a single bad or good day, without numbers behind them.

## Constraints

- The orchestrator does not write or commit. Every file change in this round is implemented by a worker and reviewed by Codex, per the existing policy. Changes to `AGENTS.md`, `docs/05-delegation.md`, the orchestrator skill and the plugin manifest are risky tier.
- Orca `worker-start --model` and `--effort` apply to Claude and Codex workers. The DeepSeek harness (`dsh`) launches with the model in its own profile, so a DeepSeek rung is a `dsh` profile, selected by name, not an Orca flag.
- Codex workers do not run Claude Code hooks or skills. That is a vendor capability limit recorded in the ladder, not a cost choice.
- DeepSeek availability is per execution host. On the home-office Orca host, `dsh-tui` is a registered Orca agent and DeepSeek workers already run there (observed 2026-11-17 on the woo-panel workspace). On a host where `docs/12-orca-setup.md` does not record a working `dsh` agent and its profiles, the DeepSeek row of the ladder is unavailable and rung 0 and 1 implementation goes to the Claude row. Registering `dsh` on a new host is machine setup, recorded in 12-orca-setup, not part of this round.
- The `plan-tooling` skill is vendored into the plugin under `skills/plan-tooling/` (MIT, same author) so application repos on other machines get the Tooling contract with the plugin rather than depending on a user-level skill.
- Nothing here is a security boundary. The ladder is policy plus a plan column; the guard hook remains the only tripwire.
- **Solvela** (`~/Projects/solvela`, hosted at `api.solvela.ai`) is the owner's own gateway and may be changed if this round needs it. Verified from its source and feature-state page on 2026-11-17: OpenAI-compatible `/v1/chat/completions`; a live native Anthropic `/v1/messages` relay that preserves tool use, thinking signatures and cache-token usage, built for Claude Code as the client; bearer API-key auth under an org/team hierarchy with hourly, daily and monthly team budgets; `spend_logs` rows per request carrying model, provider, token counts, USDC cost and an opaque `session_id` taken from the `x-solvela-session` header; org and team stats endpoints; request headers `x-solvela-model`, `x-solvela-profile` (eco, auto, premium, free) and `x-solvela-tier`; exact and semantic response cache. DeepSeek workers on the home-office host already pay through it (the 402 seen on the woo-panel workspace on 2026-11-17 was a Solvela balance error).
- Billing shape differs by vendor. DeepSeek and Codex API calls are pay-per-token wherever they go, so routing them through Solvela adds attribution at no extra cost. A Claude Code session on the owner's subscription is not pay-per-token; sending it through Solvela would convert it to metered API spend in USDC. Which Claude sessions go through Solvela is therefore a cost decision for the owner, recorded below.

## Approaches considered

1. **Plan-assigned model ladder** (chosen). The plan gives every task a complexity rung beside its risk tier. A fixed table maps rung to model per vendor. The orchestrator obeys the table. Escalation climbs one rung on failure. Mostly documentation and prompt text in the plugin; no new runtime, no new dependency.
2. **Gateway-side automatic routing.** Solvela's smart router, with `model: auto` or a routing profile, picks a model per request from the prompt alone. No plan overhead, but it cannot see the risk tier, and quality drift would be hard to attribute to a cause. Deferred as the *chooser* until option 1 has produced spend numbers that show where it would pay. Solvela itself is adopted now as the *meter and the cache*: the ladder names the model explicitly, Solvela records what it cost under the task's session id, enforces team budgets, and serves cache hits. Caveman, considered earlier for the same measurement role, is dropped: it would be a second gateway in front of the owner's own.
3. **Fixed role to vendor, written down.** Claude orchestrates, DeepSeek codes, Codex reviews, nothing varies per task. This is the status quo. It leaves the orchestrator spending top-model tokens on reading, research and summarising, which is the waste the owner can already see.

Option 1 was picked because it is the only one where the choice is made once, in a reviewed document, and is auditable afterwards.

## Decision

### 1. Two axes per task: risk tier and complexity rung

Risk tier (trivial, normal, risky) continues to decide process weight: reviewer or not, record depth, attended or not. It is unchanged.

Complexity rung (0, 1, 2) decides the model. It is set per task in the plan, by the planner, and reviewed with the plan.

**When a plan exists and when it does not** (owner decision, 2026-11-17). A plan is written for a piece of work: a feature, a project phase, anything with more than one task. The orchestrator does not write, so a rung-2 Claude worker writes the plan file; the owner approves it once, together with its owner-items list, and the tasks inside it then dispatch without further approval. A single task dispatched outside any plan carries tier and rung in its brief, and its rung **defaults to its tier** (trivial 0, normal 1, risky 2). That default is the whole rule; the orchestrator does not weigh complexity in the moment.

**Pre-plan reading and research** (owner decision, 2026-11-17). The orchestrator's read-only subagents run at rung 1 by default, rising to rung 2 only when the question being researched is itself risky-tier. The orchestrator session stays on the top model because it holds the plan and the risk calls.

| Rung | What the task looks like | Typical examples |
|---|---|---|
| 0 | Mechanical. The outcome is fully specified; the worker transcribes rather than decides. | Rename, move, format, fix a typo, change a config value, write a commit message from a diff, apply a reviewer's one-line fix |
| 1 | Bounded. Clear acceptance criteria; the worker makes local decisions inside one module or document. | A feature or bug fix with tests inside assigned files, read-only research with a stated question, summarising a document, triaging failures |
| 2 | Open. Several valid designs; mistakes propagate across files or across time. | Architecture, the plan itself, brainstorming, anything in the risky tier, cross-module refactors, writing a new agent or skill |

**Risk floor:** a risky-tier task is rung 2 whatever its complexity. Nothing else couples the axes.

### 2. The ladder table

One table, kept in `docs/05-delegation.md`, maps rung to model per role. Exact provider ids are the builder's to confirm against the installed CLIs and are listed in the plan, not here; the shape is fixed:

| Role | Rung 0 | Rung 1 | Rung 2 |
|---|---|---|---|
| Orchestrator session | not applicable: always the top Claude model, because it holds the plan and the risk calls | | top Claude model |
| Research and read-only subagents (native, inside the orchestrator) | smallest Claude model | mid Claude model | top Claude model |
| Implementer, Claude worker | smallest Claude model | mid Claude model | top Claude model |
| Implementer, DeepSeek worker | cheapest `dsh` profile | standard `dsh` profile (today `deepseek-v4-pro`) | not used; rung 2 implementation goes to a Claude worker |
| Reviewer, Codex worker | no reviewer at trivial tier; otherwise Codex at low effort | Codex at medium effort | Codex at high effort |

The table changes only through a new decision record that cites spend and outcome numbers from at least one review period. It never changes inside a task or a plan.

### 3. Escalation climbs, never descends

A task is re-dispatched one rung higher, with a summary of the failed attempt in the brief, when any of these happens:

- the worker HALTs on a stop condition in its brief;
- verification fails on the worker's own report;
- the reviewer records a correctness finding (not style or wording).

Two escalations at most, matching the existing two-retry allowance. After that, the orchestrator reports to the owner. A task is never moved down a rung once started, and a reviewer finding never lowers the rung of the fix.

### 4. Tooling is rung-invariant

The `plan-tooling` Tooling table is filled before rungs are assigned and is not revisited when they are. Every worker brief carries the same skill list for the task regardless of rung. Where a vendor cannot load a tool at all (Codex and Claude Code skills, for example) the ladder table records that limit against the vendor, and the planner picks a vendor that can.

### 5. The plan contract gains three columns and one section

Every task row in a plan carries: risk tier, complexity rung, the model that follows from them, the tool ids from the Tooling table, acceptance criteria, and the owner item it depends on, if any.

Every plan gains an **Owner items** section: everything the owner must supply (credentials by name, accounts, decisions, content, approvals), each tied to the task it blocks. The orchestrator asks for these at plan approval, not when a worker is already waiting.

### 6. Measurement through Solvela before any further routing

The harness records spend per role and rung from the first run of this policy. Solvela is the meter.

- **Which sessions go through Solvela.** All pay-per-token workers: DeepSeek (already there), Codex via its `model_providers` base URL, and any Claude worker that is API-billed rather than on the owner's subscription. Claude Code sessions on the subscription (the orchestrator and, today, Claude workers) stay direct unless the owner decides otherwise; see Owner items. The first ladder review compares the two populations and may move the line.
- **Attribution.** Every worker launched through Solvela sends `x-solvela-session` set to its Orca dispatch or task id, and the brief names the rung. Solvela's `spend_logs` then hold model, provider, tokens and USDC cost per task with no bookkeeping by any agent. The orchestrator's completion report still names rung, escalation count and tokens, read from the worker's report.
- **Ceilings.** One Solvela team per role (implementer, reviewer, research) with hourly and daily budgets. A budget hit is a clear error to the worker and an escalation to the owner, not a surprise bill.
- **The table.** At review time a rung-1 worker reads the org and team stats endpoints and the `spend_logs` rows for the period and produces spend per role and rung, escalation rate per rung, and cache hit rate. If the stats endpoints do not break down by session or by a rung tag, adding that to Solvela is a task in the plan; the owner has allowed changes to Solvela.
- **Fallback for direct sessions.** For sessions not routed through Solvela, the worker's reported token count goes into the PR body (normal and risky) or a `Rung:` commit trailer (trivial), and the same review worker folds those in. Orca workspace comments are not a ledger; they are overwritten.

A review of the ladder happens after a stated period (proposed: the first ten normal-tier tasks, then monthly) and produces either "no change" or a new decision record.

## Owner items for the implementing plan

- A Solvela org for the harness with one team per role, API keys for the Codex and DeepSeek workers, and the budget figures per team. Named here; values stay in the owner's secret manager.
- Confirmation of the Solvela wallet or balance that funds those teams.
- A decision on whether any Claude Code sessions move from subscription to Solvela-metered API in this round. Recommendation: none yet; take the first review's numbers first.

## Left to the builder

- Exact model id strings per vendor, verified against `claude`, `codex --help`, `orca orchestration worker-start --help` and the installed `dsh` profiles on the day of implementation.
- Whether the cheapest DeepSeek rung is a separate `dsh` profile or a `--patch` overlay; either is acceptable if it is selected by name in the brief.
- The exact wording of the ladder section in `docs/05-delegation.md`, the one-line addition to `AGENTS.md`, and the orchestrator skill's dispatch instructions (pass `--model` and `--effort` per the table; name the rung in every brief).
- The plan template location (proposed: `docs/templates/plan.md` in the plugin, referenced from the orchestrator skill) and the specialist template's new `Rung:` line.
- Verifying, on the day, that Codex honours a `model_providers` base URL pointing at Solvela with a bearer key, that the `dsh` profiles on the home-office host already carry the Solvela base URL, and that Claude Code's custom-headers setting can carry `x-solvela-session` for any Claude session that is routed through Solvela.
- Whether the Solvela org and team stats endpoints already report by `session_id`; if not, the shape of the small Solvela change that adds it.
- The Solvela model alias (for example `haiku`, `sonnet`, `opus`, `deepseek`) or exact provider id to put in each ladder cell.

## Consequences

- Dispatch gets one more line in every brief and one more column in every plan. In exchange, the orchestrator stops spending its own model on research and summarising, and trivial work stops running on the top model.
- Escalation adds up to two re-dispatches on hard tasks that were under-estimated. That is the accepted cost of starting cheap; the numbers in section 6 show whether the estimates are drifting.
- The owner's original "semantic cache and model picker" feature is served by Solvela as it stands: the cache is on today for every Solvela-routed call, and the router is available the moment the numbers say it should choose within a rung.
- Reverting is one commit: the ladder is text in the plugin, and a plan without rungs is still a valid plan under the previous policy.
