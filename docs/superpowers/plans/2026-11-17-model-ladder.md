# Model Ladder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put the model ladder from decision 0004 into the ai-dev-system plugin so every dispatch names a rung, the rung decides the model, escalation only climbs, and Solvela meters the spend.

**Architecture:** This is a policy-and-prompt plugin with no application code. The ladder lands as text in `docs/05-delegation.md`, one bullet in `AGENTS.md`, dispatch rules in the orchestrator skill, a `Rung:` line in the role templates, a plan template, and the vendored `plan-tooling` skill. A shell check script pins the required wording so later edits cannot silently drop a rule.

**Tech Stack:** Markdown, bash, `claude plugin validate`, Orca CLI (`worker-start --model/--effort`), Solvela headers and team stats.

**Spec:** `docs/decisions/0004-model-ladder.md`

## Global Constraints

- Every change in this plan is **risky tier** under docs/05 (it edits AGENTS.md, delegation policy and the orchestrator skill): one implementer, one Codex review, attended.
- The orchestrator does not write or commit; every task here runs as a worker. The implementer is the plugin's `docs-engineer` agent role.
- Rung never descends once a task starts; the rung of an unplanned task equals its tier (trivial 0, normal 1, risky 2); risky tier is always rung 2.
- The Tooling table is identical at every rung. No text in this plan may tell a worker to skip a skill, reviewer or verification because of its rung.
- The ladder table changes only through a new decision record citing spend numbers.
- No secrets in the repo. Solvela keys, budgets and wallet are named as owner items, never valued.
- Repo verification list (AGENTS.md): `git diff --check`; `bash -n` on changed shell; `bash tools/hooks/test-orchestrator-guard.sh`; `claude plugin validate .` when plugin files change; changed Markdown links resolve.
- Conventional commits, no `Co-Authored-By`.

## Tooling

| Part of the job | Tool (exact id) | Kind | Used at | Why this one |
|---|---|---|---|---|
| Rung and tooling columns in this and every future plan | plan-tooling (vendored as `skills/plan-tooling` by Task 2) | skill | build | the Tooling contract the spec makes rung-invariant |
| Implement each task | `docs-engineer` (`agents/docs-engineer.md`) as an Orca worker | agent | build | the plugin's own docs/tooling implementer role |
| Independent review of each task | Codex worker, per docs/05 risky tier | agent | verify | required reviewer for policy files |
| Orca dispatch flags for Claude and Codex workers | `orca orchestration worker-start --model <id> --effort <level>` | CLI | runtime | verified 2026-11-17: accepts Claude and Codex ids; `dsh` takes its model from its own profile |
| Spend attribution and metering | Solvela `x-solvela-session` header, team stats `by_model` | API | runtime | spec section 6; `spend_logs.session_id` exists (migration 003) |
| Pin the required wording | `tools/check-ladder-docs.sh` (Task 1) | script | verify | the repo's existing test style (`test-orchestrator-guard.sh`) |
| Plugin manifest and skill validity | `claude plugin validate .` | CLI | verify | repo verification list |
| Whitespace and links | `git diff --check`; manual link check | CLI | verify | repo verification list |
| Writing the ladder text | hand-written | none | build | policy prose; nothing to reuse |

**Checked and rejected:** Caveman gateway (second proxy in front of the owner's own; spec option 2). Solvela `model: auto` / routing profiles as the chooser (cannot see risk tier; deferred by spec). A Solvela `by_session` stats breakdown (team `by_model` already yields spend per role and rung because the ladder maps rung to model within a role; `candidate on second use: solvela-session-breakdown`). `superpowers:test-driven-development` as a row (no application code; the check script in Task 1 is the test).

**Gaps to build first:** `skills/plan-tooling` inside the plugin (Task 2): application repos on other machines would otherwise reference a user-level skill they do not have.

## Review Focus

1. A brief that names a tier but no rung: the reader must find the rule that the rung equals the tier, not an invitation to judge. Pinned by `check-ladder-docs.sh` assertion on docs/05 and the orchestrator skill (Task 1, Tasks 3 and 5).
2. A risky-tier task someone marks rung 0 to save money: the risk floor must be stated where the rung is set (docs/05) and where it is dispatched (orchestrator skill). Pinned by Task 1 assertions.
3. A third escalation: the text must say the orchestrator stops and reports after two, matching the existing retry allowance. Pinned by Task 1 assertion on docs/05.
4. A DeepSeek rung on a host where `dsh` is not a registered Orca agent: the ladder must say the DeepSeek row applies only where docs/12 records it, and where the work goes otherwise. Pinned by Task 1 assertion on docs/05.
5. A Solvela budget hit mid-task: the worker must HALT and the orchestrator must escalate to the owner, not retry into the same ceiling. Pinned by Task 1 assertions on the specialist template and the orchestrator skill.

---

### Task 1: Check script that pins the ladder wording

**Files:**
- Create: `tools/check-ladder-docs.sh`
- Modify: `AGENTS.md:29-39` (Verification list: add the script)

**Interfaces:**
- Produces: `bash tools/check-ladder-docs.sh` exits 0 when every required phrase is present in its file, else prints each missing `file: phrase` and exits 1. Later tasks make its assertions pass one file at a time.

- [ ] **Step 1: Write the failing check**

`tools/check-ladder-docs.sh`, bash, `set -u`, one `need <file> <fixed-string>` helper using `grep -qF`. Assertions, grouped by file:

```text
docs/05-delegation.md:
  "## Model ladder"
  "rung defaults to its tier"
  "risky tier is always rung 2"
  "never moved down a rung"
  "at most two escalations"
  "identical at every rung"
  "only through a new decision record"
  "docs/12-orca-setup.md records a working dsh"
  "## Plans and owner items"
  "## Ladder review"
AGENTS.md:
  "complexity rung"
skills/orchestrator/SKILL.md:
  "Rung:"
  "--model"
  "x-solvela-session"
  "rung 1"
  "one rung higher"
  "budget"
agents/specialist-agent.md.tmpl:
  "Rung:"
  "budget"
  "tokens"
agents/docs-engineer.md:
  "Rung:"
docs/templates/plan.md:
  "| Rung |"
  "## Owner items"
  "## Tooling"
skills/plan-tooling/SKILL.md:
  "name: plan-tooling"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tools/check-ladder-docs.sh; echo "exit=$?"`
Expected: a list of missing phrases for every file above and `exit=1`.

- [ ] **Step 3: Add the script to the repo's verification list**

In `AGENTS.md` under "## Verification for this repository", add the line `- Run `bash tools/check-ladder-docs.sh` when the ladder, templates or the orchestrator skill change.`

- [ ] **Step 4: Verify the script and the edit**

Run: `bash -n tools/check-ladder-docs.sh && git diff --check && echo OK`
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add tools/check-ladder-docs.sh AGENTS.md
git commit -m "test: add check script that pins the model ladder wording"
```

### Task 2: Vendor the plan-tooling skill into the plugin

**Files:**
- Create: `skills/plan-tooling/SKILL.md` (copy of `/home/sky64/.claude/skills/plan-tooling/SKILL.md`, unchanged)
- Modify: `.claude/skills/THIRD-PARTY.md` (add one line: plan-tooling, MIT, author sky64, source path)

**Interfaces:**
- Produces: the skill id `plan-tooling` resolvable inside any repo that enables the plugin; its `## Tooling` block shape, which Task 6's plan template references.

- [ ] **Step 1: Run the check for this file to see it fail**

Run: `bash tools/check-ladder-docs.sh 2>&1 | grep plan-tooling`
Expected: `skills/plan-tooling/SKILL.md: name: plan-tooling`

- [ ] **Step 2: Copy the skill and record the licence line**

`cp /home/sky64/.claude/skills/plan-tooling/SKILL.md skills/plan-tooling/SKILL.md`; append the licence line to `.claude/skills/THIRD-PARTY.md`.

- [ ] **Step 3: Verify**

Run: `bash tools/check-ladder-docs.sh 2>&1 | grep -c plan-tooling; claude plugin validate . | tail -1`
Expected: `0` and `Validation passed` (warnings allowed).

- [ ] **Step 4: Commit**

```bash
git add skills/plan-tooling/SKILL.md .claude/skills/THIRD-PARTY.md
git commit -m "feat: vendor the plan-tooling skill into the plugin"
```

### Task 3: The ladder in docs/05-delegation.md

**Files:**
- Modify: `docs/05-delegation.md` (insert after "## Task tiers", before "## Enforcement" at line 31; append "## Ladder review" before "## Known conflicts" at line 99)

**Interfaces:**
- Produces: three new sections that the orchestrator skill (Task 5) and templates (Task 6) cite by heading: `## Model ladder`, `## Plans and owner items`, `## Ladder review`.

- [ ] **Step 1: Run the check to see the docs/05 assertions fail**

Run: `bash tools/check-ladder-docs.sh 2>&1 | grep '^docs/05'`
Expected: ten lines.

- [ ] **Step 2: Write `## Model ladder`**

Contents, in this order, with the spec's exact wording for each rule:

1. One paragraph: two axes; tier decides process weight (unchanged); rung decides the model.
2. Rung table (spec section 1): rung 0 mechanical, 1 bounded, 2 open, with the spec's examples.
3. Rules as bullets, each containing its pinned phrase: an unplanned task's "rung defaults to its tier (trivial 0, normal 1, risky 2)"; "risky tier is always rung 2"; the orchestrator's read-only subagents run at rung 1, rung 2 when the question is risky-tier; the orchestrator session stays on the top model.
4. Ladder table (spec section 2) with these cells, each marked "verify on the day" in a footnote:
   - Research subagents: `claude-haiku-5-5` / `claude-sonnet-5-5` / `claude-opus-5-5`.
   - Claude implementer (Orca `--model`): same three ids.
   - DeepSeek implementer: cheapest `dsh` profile / standard `dsh` profile (`deepseek-v4-pro` today) / not used, goes to the Claude row. Bullet after the table: "The DeepSeek row applies only on a host where docs/12-orca-setup.md records a working dsh agent and its profiles; elsewhere rung 0 and 1 implementation goes to the Claude row."
   - Codex reviewer (Orca `--model <codex id> --effort`): no reviewer at trivial tier, otherwise low / medium / high effort on the Codex default model.
   - Solvela-routed calls name the model with the Solvela alias (`haiku`, `sonnet`, `opus`, `deepseek`) or exact id; Solvela's `auto` profile is not used as the chooser.
5. Escalation bullets: triggers (worker HALT; failed verification; reviewer correctness finding); re-dispatch "one rung higher" with a summary of the failed attempt; "at most two escalations", then report to the owner; a task is "never moved down a rung" once started.
6. Tooling invariance: the Tooling table is "identical at every rung"; vendor capability limits (Codex cannot load Claude Code skills) are recorded against the vendor.
7. Change control: the table changes "only through a new decision record" citing spend numbers; never inside a task or a plan.

- [ ] **Step 3: Write `## Plans and owner items`**

Spec section 1 (owner decision) and section 5: a plan is written for a piece of work with more than one task, by a rung-2 Claude worker; the owner approves it once with its owner-items list; tasks inside dispatch without further approval; required columns per task row (risk tier, rung, model, tool ids, acceptance criteria, owner item); the `## Owner items` section; reference `docs/templates/plan.md` (Task 6) and the `plan-tooling` skill.

- [ ] **Step 4: Write `## Ladder review`**

Spec section 6. The review brief for one rung-1 worker: when (after the first ten normal-tier tasks, then monthly); inputs (Solvela team stats `by_model` for each role team; PR bodies and `Rung:` commit trailers for direct sessions; orchestrator completion reports for escalation counts); outputs (spend per role and rung, escalation rate per rung, cache hit rate); result is "no change" or a new decision record. State which sessions route through Solvela (pay-per-token workers) and that subscription Claude sessions stay direct until the owner decides otherwise.

- [ ] **Step 5: Verify**

Run: `bash tools/check-ladder-docs.sh 2>&1 | grep -c '^docs/05'; git diff --check && echo WS-OK`
Expected: `0` and `WS-OK`. Open every relative link added and confirm the target exists.

- [ ] **Step 6: Commit**

```bash
git add docs/05-delegation.md
git commit -m "docs: add the model ladder, plan contract and ladder review to the delegation policy"
```

### Task 4: AGENTS.md, README and the decision record cross-links

**Files:**
- Modify: `AGENTS.md:12` (one new bullet after the tiers bullet)
- Modify: `README.md:21` (Status paragraph: one sentence)
- Modify: `docs/decisions/0004-model-ladder.md:3` (link this plan)

- [ ] **Step 1: See the AGENTS.md assertion fail**

Run: `bash tools/check-ladder-docs.sh 2>&1 | grep '^AGENTS'`
Expected: `AGENTS.md: complexity rung`

- [ ] **Step 2: Add the bullet to AGENTS.md**

After the "Work is tiered by risk" bullet: `- Every task also carries a complexity rung (docs/05-delegation.md, "Model ladder") that decides its model. An unplanned task's rung equals its tier; risky is always rung 2; escalation only climbs; the tooling is the same at every rung.`

- [ ] **Step 3: README status and decision link**

README Status paragraph: append `The model ladder ([decision 0004](docs/decisions/0004-model-ladder.md)) is adopted on 2026-11-17; its Solvela routing rows are recorded in [docs/12](docs/12-orca-setup.md) as they are verified.` In 0004 line 3, replace "the plan that implements it will be linked here when written" with a link to `../superpowers/plans/2026-11-17-model-ladder.md`.

- [ ] **Step 4: Verify**

Run: `bash tools/check-ladder-docs.sh 2>&1 | grep -c '^AGENTS'; git diff --check && echo WS-OK`
Expected: `0`, `WS-OK`; both new links resolve.

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md README.md docs/decisions/0004-model-ladder.md
git commit -m "docs: reference the model ladder from AGENTS.md, README and decision 0004"
```

### Task 5: Dispatch rules in the orchestrator skill

**Files:**
- Modify: `skills/orchestrator/SKILL.md` (new "## Rungs and models" section after "## Delegation"; edits to the Delegation bullets)

**Interfaces:**
- Consumes: headings from Task 3.
- Produces: the brief fields every worker receives: `Tier:`, `Rung:`, `Model:`, `Session:` (the Orca dispatch id, also sent as `x-solvela-session`).

- [ ] **Step 1: See the skill assertions fail**

Run: `bash tools/check-ladder-docs.sh 2>&1 | grep '^skills/orchestrator'`
Expected: six lines.

- [ ] **Step 2: Write the section**

Bullets, each with its pinned phrase:

- Every brief names `Tier:`, `Rung:` and `Model:`; an unplanned task's rung is its tier; risky is rung 2.
- Claude and Codex workers: pass `--model <id>` and `--effort <level>` from the ladder table to `worker-start` or `worktree create`. DeepSeek workers: name the `dsh` profile for the rung in the brief; Orca cannot set it.
- Native read-only subagents run at the "rung 1" model unless the question is risky-tier; name the model in the subagent prompt.
- Workers routed through Solvela send `x-solvela-session` set to the Orca dispatch id; put the exact header and value in the brief's environment line.
- Escalation: on HALT, failed verification or a correctness finding, re-dispatch "one rung higher" with a summary of the failed attempt; stop after two and report.
- A Solvela "budget" error from a worker is an escalation to the owner, not a retry.
- Plans: for more than one task, dispatch a rung-2 Claude worker to write the plan from `docs/templates/plan.md` and the `plan-tooling` skill; wait for owner approval; then dispatch tasks.
- Completion report adds: rung used, escalations, tokens consumed as reported by the worker, and the model id.

- [ ] **Step 3: Verify**

Run: `bash tools/check-ladder-docs.sh 2>&1 | grep -c '^skills/orchestrator'; claude plugin validate . | tail -1`
Expected: `0`, `Validation passed`.

- [ ] **Step 4: Commit**

```bash
git add skills/orchestrator/SKILL.md
git commit -m "feat(orchestrator): dispatch by rung, pass models, attribute Solvela sessions, escalate upward only"
```

### Task 6: Role templates and the plan template

**Files:**
- Modify: `agents/specialist-agent.md.tmpl` (after the frontmatter paragraph; the Report section)
- Modify: `agents/docs-engineer.md` (same two places)
- Create: `docs/templates/plan.md`

**Interfaces:**
- Consumes: `## Tooling` block shape from `skills/plan-tooling/SKILL.md` (Task 2).
- Produces: the task-row columns every plan uses: `| Task | Tier | Rung | Model | Tools | Acceptance | Owner item |`.

- [ ] **Step 1: See the template assertions fail**

Run: `bash tools/check-ladder-docs.sh 2>&1 | grep -E '^(agents|docs/templates)'`
Expected: seven lines.

- [ ] **Step 2: Edit both role templates**

Under the opening paragraph add: `Tier: <trivial|normal|risky> · Rung: <0|1|2> · Model: <id as the brief names it>`. In `## HALT and report instead of guessing` add: `- A provider or Solvela budget error. Report it; do not retry.` In `## Report` add `tokens consumed (input and output) and the model actually used`.

- [ ] **Step 3: Create `docs/templates/plan.md`**

Sections in order: title; `**Spec:**`; `## Global Constraints`; `## Tooling` (the block from the plan-tooling skill, copied as a fenced example); `## Owner items` (table: item, who issues it, task it blocks); `## Tasks` with the row header `| Task | Tier | Rung | Model | Tools | Acceptance | Owner item |` and one example row; a closing note that rungs are set here and only climb.

- [ ] **Step 4: Verify**

Run: `bash tools/check-ladder-docs.sh && echo ALL-OK; claude plugin validate . | tail -1; bash tools/hooks/test-orchestrator-guard.sh | tail -1; git diff --check && echo WS-OK`
Expected: `ALL-OK`, `Validation passed`, the guard test's pass line, `WS-OK`.

- [ ] **Step 5: Commit**

```bash
git add agents/specialist-agent.md.tmpl agents/docs-engineer.md docs/templates/plan.md
git commit -m "feat: rung and token lines in role templates; add the plan template"
```

### Task 7: Routing verification record and version bump

**Files:**
- Modify: `docs/12-orca-setup.md` (new subsection "## Model ladder routing")
- Modify: `.claude-plugin/plugin.json` (`"version": "0.3.0"`)

**Interfaces:**
- Consumes: owner items (Solvela org, team keys, budgets) if present; the task runs with or without them and records which rows were verified.

- [ ] **Step 1: Write the routing table with every row initially "unverified"**

Rows: Codex `model_providers` base URL at Solvela with a bearer key; `dsh` profiles on the home-office host carrying the Solvela base URL and the cheapest-rung profile name; Claude Code `ANTHROPIC_CUSTOM_HEADERS` carrying `x-solvela-session` for any Claude session routed through Solvela; Solvela team per role with hourly and daily budgets; the team stats `by_model` call returning rows for a test session. Each row: what was run, exact observed output or "unverified: needs <owner item>".

- [ ] **Step 2: Run what can be run without owner items**

Run on the host that has the agent: `orca orchestration worker-start --help | grep -- --model` and record the line; `codex --help | grep -c config`; record `dsh --version`. Everything needing a key stays "unverified" with its owner item named.

- [ ] **Step 3: Bump the plugin version and validate**

`"version": "0.3.0"` in `.claude-plugin/plugin.json`. Run: `claude plugin validate . | tail -1; git diff --check && echo WS-OK; bash tools/check-ladder-docs.sh && echo ALL-OK`
Expected: `Validation passed`, `WS-OK`, `ALL-OK`.

- [ ] **Step 4: Commit**

```bash
git add docs/12-orca-setup.md .claude-plugin/plugin.json
git commit -m "docs: record model ladder routing verification; bump plugin to 0.3.0"
```

## Owner items

| Item | Who issues it | Blocks |
|---|---|---|
| Solvela org for the harness, one team per role (implementer, reviewer, research), API keys for the Codex and DeepSeek workers | owner, in Solvela app; keys into the secret manager, named only | Task 7 rows 1, 2, 4, 5 |
| Hourly and daily budget figures per team | owner | Task 7 row 4 |
| Confirmation of the wallet or balance funding those teams | owner | Task 7 row 4 |
| Decision whether any Claude Code session moves from subscription to Solvela-metered API this round (recommendation: none yet) | owner | Task 7 row 3; otherwise recorded "not routed" |
| Ladder table cells confirmed against the installed CLIs on the day | implementer, in Task 3 footnote | nothing; unverified cells stay marked |
