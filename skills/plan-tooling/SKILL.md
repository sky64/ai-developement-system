---
name: plan-tooling
description: Use when planning any build, feature or fix, after the approach is chosen and before implementation tasks are written; when a draft plan names no skill, agent, MCP server or rule by its exact identifier; or when the job touches an external system (database, email, calendar, cloud account, vendor API, browser) that a connector or skill may already cover.
license: MIT
metadata:
  version: "0.2.0"
  author: sky64
  tags: "planning, tooling, skills, agents, mcp, rules, gaps"
  related_skills: "superpowers:brainstorming, superpowers:writing-plans, superpowers:writing-skills, anthropic-skills:mcp-builder, auto-skills, new-repo"
---

# Plan Tooling

## Overview

Which tool does each part of a job is a planning decision, not an
implementation detail. A plan is complete only when it carries a **Tooling**
section that names, by exact identifier, the skills, agents, MCP servers and
rules the job will use, says at which stage each is used, and lists the tools
that must be built or enabled before work starts.

Fits between superpowers:brainstorming (approach chosen) and
superpowers:writing-plans (tasks written). Costs about fifteen lines.

## Inventory: where the rosters are

Run every row before filling the section. Each is one look-up.

| Kind | Where to look |
|---|---|
| Skills, loaded | the "skills available" list in your system prompt |
| Skills, installed but not loaded | `ls ~/.claude/skills ~/.agents/skills .agents/skills`; skill libraries kept out of the session on purpose, such as ECC under `~/.claude/plugins/cache/ecc/`, which auto-skills links into a repo's `.agents/skills/` by stack |
| Agents | the "available agent types" list in your system prompt; `.claude/agents/` in the repo |
| MCP servers | tools named `mcp__<server>__*`; for each external system the job names, run ToolSearch with a keyword (`outlook send`, `zoho invoice`, `postgres`), because most MCP tools are deferred and invisible until searched |
| Rules | `~/.claude/rules/`, the repo's `AGENTS.md` or `CLAUDE.md`, `.claude/rules/` |

An installed-but-not-loaded tool is a candidate like any other. Its row says
how it gets loaded (`auto-skills apply`, enable the plugin, link the skill),
and that step is the plan's first task.

## The Tooling section (the contract)

Every plan contains this block before its task list. It has exactly these
parts, in this order.

```markdown
## Tooling

| Part of the job | Tool (exact id) | Kind | Used at | Why this one |
|---|---|---|---|---|
| Confirm Zoho status vocabulary | mcp__claude_ai_Zoho_Books__list_invoices | MCP | build | answers the open question now, not on the call |
| Schema + invoice_events table | ecc:postgres-patterns | skill | build | migration and index conventions; link via `auto-skills apply` (Task 1) |
| Send the Monday email from the cron job | httpx + Microsoft Graph sendMail | library | runtime | the shipped job runs without a Claude session |
| Check the email renders in Outlook | mcp__claude_ai_Microsoft_365__outlook_send_mail | MCP | verify | send the rendered HTML to yourself once |
| Tests for every change | superpowers:test-driven-development | skill | build | |
| Review of credentials handling | ecc:security-reviewer | agent | verify | touches secrets |
| Overdue report formatting | hand-written | none | runtime | one pure function, nothing to reuse |

**Checked and rejected:** `schedule` skill (a cloud routine would replace the Python job the approach chose); CronCreate (session-bound).

**Gaps to build first:**
- `graph-mail-send` (skill): the job reads `GRAPH_TENANT_ID`, `GRAPH_CLIENT_ID` and `GRAPH_CLIENT_SECRET`, which only an Entra app registration can issue; a second repo under `~/Projects` ships the same send path. Task 1.
- candidate on second use: `overdue-report-render` (one pure function today).
```

Rules for filling it:

- **One row per part of the job.** Every step the plan will contain maps to a
  row. A part with no fitting tool gets `hand-written` and a reason.
- **Exact identifiers**, copied from the roster: `ecc:postgres-patterns`, not
  "a Postgres skill"; `mcp__claude_ai_Microsoft_365__outlook_send_mail`, not
  "the Outlook MCP".
- **`Used at` is one of `build`, `verify`, `runtime`.** Skills, agents and
  MCP connectors exist only while an agent is working, so they are `build`
  or `verify`. A `runtime` row names what the shipped code depends on: a
  library, an API, a CLI. A connector in a `runtime` row is a wrong tool.
- **A row never changes the architecture the approach chose.** If the only
  way to use a tool is to change where the work runs (a Claude routine
  instead of the cron job), that is a different approach: list it under
  rejected and raise it with the user, do not smuggle it in.
- **At least one rejected candidate**, so the reader sees the inventory ran.
- **Gaps are tasks, not notes.** A part of the job with no tool is a gap
  when any one of these is true: the same part already exists in another repo
  of the user's (second use: `grep` for it under `~/Projects`); the user has
  said it will recur; or the shipped code reads a credential or identifier
  (client id, tenant id, secret, API key, webhook URL) that a third-party
  system must issue before the first run, since obtaining it is a procedure
  the code cannot show. Each gap is named, typed, and becomes
  the first task(s) of the plan. A part that fails all three stays a module in
  this repo, and the block records it as `candidate on second use: <name>`.
  Write `Gaps to build first: none` only after all five rosters were checked.
- **Verification has rows too:** which skill drives the tests and which
  reviewer agent reviews.

## Which kind to build

| The missing thing is | Build a | With |
|---|---|---|
| a repeatable technique with steps | skill | superpowers:writing-skills |
| a constraint every change must obey | rule | an entry in `AGENTS.md` or `~/.claude/rules/` |
| a reviewer or specialist with a fixed checklist | agent | `.claude/agents/<name>.md` |
| live access to an external system for the agent | MCP server | anthropic-skills:mcp-builder |

## Hand-off

Paste the Tooling section into the plan written with
superpowers:writing-plans. Each task in that plan names the tool from its
row. For a brand-new repo, run new-repo first, then this skill; the `build`
and `verify` rows also fill the `## Tooling` heading in the repo's
`AGENTS.md`.

## Common mistakes

| Mistake | What the contract requires instead |
|---|---|
| Writing API calls from memory for a system that has a connector in the roster | a `build` or `verify` row with the connector's exact tool id, used to confirm fields and output |
| Putting a connector in the shipped job's send or fetch path | a `runtime` row naming the library or API; the connector in a `verify` row |
| Rejecting a tool because it is installed but not loaded | a row whose Why names the enabling step, as Task 1 |
| "No tool needed" before looking at the rosters | the five look-ups, then the row |
| Naming a category instead of an identifier | the id as the roster prints it |
| Leaving a gap as "open question" or "out of scope" | a named gap that is Task 1 |
| Skipping the section because the user is in a hurry | the section is fifteen lines; one wrong tool costs more than fifteen lines |
