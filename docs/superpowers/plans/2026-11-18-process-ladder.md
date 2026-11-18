# Process Ladder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the process ladder: a per-task mode (native or delegated) decided by checkable facts, with a switch, thresholds, a native procedure, a runtime escalation and the numbers to tune it.

**Architecture:** The config reader gains a `process` section and switch with the same fallback shape as `limits`; the orchestrator skill, docs/05, AGENTS.md and the plan template carry the rule; the guard's deny message points at the native path; pins and tests cover all of it. No change to what the guard allows.

**Tech Stack:** Python 3.13+ standard library, bash, `claude plugin validate`.

**Spec:** `docs/decisions/0009-process-ladder.md`

**Branch:** create `sky64/process-ladder` from main after the scout64 PR (decision 0008) merges, since both plans edit the orchestrator skill and docs/05.

## Global Constraints

- Risky tier: rung 2, Codex review at `--effort high`, Runtime floor Python 3.13+ and bash on Linux.
- Defaults: `features.process_ladder` true; `process.default_mode` `auto`; `native_max_files` 3; `native_max_tool_calls` 40. Missing section or invalid values read as defaults; `check` names a bad value; `CREW64_PROCESS_MODE` beats the file only when it is one of `auto|native|delegated`.
- Native is never risky tier and never more than one task; a docs-only native normal-tier diff skips Codex, any code change gets it.
- The guard's allowances do not change; only its deny message text.
- Repo verification list after every task: `bash tools/test-crew64-config.sh`, `bash tools/hooks/test-orchestrator-guard.sh`, `bash tools/check-ladder-docs.sh`, `claude plugin validate .`, `git diff --check`.
- Conventional commits, no `Co-Authored-By`.

## Tooling

| Part of the job | Tool (exact id) | Kind | Used at | Why this one |
|---|---|---|---|---|
| `process` section, mode, thresholds, status field | hand-written in `tools/crew64_config.py` | library | runtime | the single reader; mirrors `limit()` |
| Reader tests | `tools/test-crew64-config.sh` (extend) | script | verify | existing helpers |
| Guard message and pair test | `tools/hooks/orchestrator-guard.py`, `tools/hooks/test-orchestrator-guard.sh` (extend) | script | runtime / verify | existing `run` helper |
| Rule wording | hand-written in `skills/orchestrator/SKILL.md`, `docs/05-delegation.md`, `AGENTS.md`, `docs/templates/plan.md`, `README.md` | none | build | prose |
| Pins | `tools/check-ladder-docs.sh` (extend) | script | verify | existing mechanism |
| Tests first | `superpowers:test-driven-development` | skill | build | repo rule |
| Evidence before done | `superpowers:verification-before-completion` | skill | verify | |
| Independent review | Codex worker at `--effort high` via `--spec-file` | agent | verify | risky tier |
| Pull request and merge | `gh pr create`; bot approval after a clean review; push from `~/Projects/ai-developement-system` | CLI | verify | as PRs 19 and 20 |
| Rules | repo `AGENTS.md`; `~/.claude/rules/ecc/common/essentials.md` | rule | build | |

**Checked and rejected:** a hook-enforced tool-call counter (no per-session counter is available to a PreToolUse hook without state the guard would have to trust); `update-config` skill (Claude settings, not plugin policy); counting tokens through Solvela (native subagents bypass the gateway).

**Gaps to build first:** none.

## Review Focus

1. `CREW64_PROCESS_MODE=NATIVE` or `native ` with whitespace: accept case-insensitively after strip, or fall through; never crash. Pinned by Task 1.
2. `process.native_max_files: 0` or `true`: default 3; `check` names the key. Pinned by Task 1.
3. A session that moved into its worktree must still be denied a write to the main checkout by absolute path. Pinned by Task 2.
4. The skill must forbid native for risky tier even when `default_mode` is `native`. Pinned by a Task 3 pin on that sentence.
5. The plan template's new column must not break the existing `| Rung |` and `| Vendor |` pins. Pinned by running the pin script in Task 3.

## Owner items

| Item | Who issues it | Blocks |
|---|---|---|
| none | | |

## Tasks

| Task | Tier | Rung | Vendor | Model | Tools | Acceptance | Owner item |
|---|---|---|---|---|---|---|---|
| 1. `process` section and switch in the reader | risky | 2 | Claude; Codex review | claude-opus-5-5 / gpt-6.1-sol high | crew64_config.py, its test, both JSON files | reader tests all ok | none |
| 2. Guard message and the worktree pair test | risky | 2 | same | same | guard hook and test | guard tests all ok | none |
| 3. The rule: skill, docs/05, AGENTS.md, plan template, README, pins; version 0.8.0 | risky | 2 | same | same | prose, check-ladder-docs.sh, plugin.json | `ladder docs OK` | none |

---

### Task 1: `process` section and switch in the reader

**Files:**
- Modify: `tools/crew64_config.py` (constants; new `process_mode()` and `process_limit()` beside `limit()`; `check()`; `status_line()`; CLI `get process.<key>`)
- Modify: `config/crew64.defaults.json`, `config/examples/orca-solvela.json` (add `"process_ladder": true` under `features` and the `process` block after `limits`)
- Test: `tools/test-crew64-config.sh` (cases 23-25)

**Interfaces:**
- `BOOL_FEATURES` gains `"process_ladder"`, also listed in `OPTIONAL_FEATURES` (from the scout64 plan) so old configs validate.
- `PROCESS_MODES = ("auto", "native", "delegated")`, `PROCESS_LIMITS = ("native_max_files", "native_max_tool_calls")`, `PROCESS_ENV = "CREW64_PROCESS_MODE"`.
- `process_mode(cfg, env=None) -> str`: env value, stripped and lower-cased, when in `PROCESS_MODES`; else `cfg["process"]["default_mode"]` when in `PROCESS_MODES`; else the default.
- `process_limit(cfg, name) -> int`: file value when `_positive_int`; else the default. No env override for the thresholds.
- `check()`: when `process` is present it must be an object (`"process must be an object"`); `default_mode` must be one of the modes; each limit must be an integer of at least 1; messages name `process.<key>`.
- `status_line()` appends ` process=<mode> max_files=<n> max_calls=<n>` after `scout64=`. When `features.process_ladder` is off the field reads ` process=off`.
- CLI: `get process.default_mode` prints `process_mode()`; `get process.<limit>` prints `process_limit()`; unknown key exits 1 with `crew64_config: unknown process key`.

- [ ] **Step 1: Write the failing tests**

```text
23. defaults without a process block: get process.default_mode → "auto"; get process.native_max_files → "3"; status contains "process=auto max_files=3 max_calls=40"; check → exit 0
24. process block {default_mode: "native", native_max_files: 5, native_max_tool_calls: 10}: get → "native", "5"; status contains "process=native max_files=5 max_calls=10"
    CREW64_PROCESS_MODE=delegated → "delegated"; "=NATIVE " → "native"; "=bogus" → file value "native"
25. {default_mode: "sometimes"} → get "auto"; check exit 1 names "process.default_mode"
    {native_max_files: 0} → "3"; {native_max_files: true} → "3"; check names "process.native_max_files"
    features.process_ladder false → status contains "process=off"; get process.default_mode still prints the configured mode
    get process.bogus → exit 1 "unknown process key"
```

Add a `setproc '<json-object>'` helper that writes the defaults with `process` replaced by the object (or removed for `absent`).

- [ ] **Step 2: Run to verify it fails**

Run: `bash tools/test-crew64-config.sh | grep -c FAIL`
Expected: at least `8`.

- [ ] **Step 3: Implement per Interfaces; add the keys to both JSON files**

- [ ] **Step 4: Run to verify it passes**

Run: `bash tools/test-crew64-config.sh | grep -c FAIL; python3 -m py_compile tools/crew64_config.py && bash tools/hooks/test-orchestrator-guard.sh | grep -c FAIL; git diff --check && echo OK`
Expected: `0`, `0`, `OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/crew64_config.py tools/test-crew64-config.sh config/crew64.defaults.json config/examples/orca-solvela.json
git commit -m "feat(config): process ladder section, switch and CREW64_PROCESS_MODE override"
```

---

### Task 2: Guard message and the worktree pair test

**Files:**
- Modify: `tools/hooks/orchestrator-guard.py` (module docstring line 2; `deny()` message text)
- Modify: `tools/hooks/test-orchestrator-guard.sh` (new cases)

**Interfaces:**
- Docstring: "the orchestrator does not write in the main checkout".
- `deny()` message: after "keep implementer writes inside that worktree (see docs/05-delegation.md)." append " For a native task, move into its task worktree first (orchestrator skill, Process ladder)."
- Tests: from `cwd="$W"`, `Write` to `x.md` → 0 and `Write` to `"$M/x.md"` → 2 (the pair, adjacent, labelled "native mode: inside allowed, main checkout denied"); `raw` check that a main-checkout denial's stderr contains "Process ladder".

- [ ] **Step 1: Write the failing test** (the stderr check fails; the pair passes already and documents the mechanism)

- [ ] **Step 2: Run to verify it fails**

Run: `bash tools/hooks/test-orchestrator-guard.sh | grep -c FAIL`
Expected: `1`.

- [ ] **Step 3: Edit the message and docstring**

- [ ] **Step 4: Run to verify it passes**

Run: `bash tools/hooks/test-orchestrator-guard.sh | grep -c FAIL; python3 -m py_compile tools/hooks/orchestrator-guard.py && git diff --check && echo OK`
Expected: `0`, `OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/hooks/orchestrator-guard.py tools/hooks/test-orchestrator-guard.sh
git commit -m "fix(guard): deny message names the native path; pin the worktree pair"
```

---

### Task 3: The rule in the skill, docs/05, AGENTS.md, plan template, README; version 0.8.0

**Files:**
- Modify: `skills/orchestrator/SKILL.md` (line 7 sentence; `## Configuration` switches bullet; new `## Process ladder` section between `## Delegation` and `## Rungs and models`; the Delegation bullet "The orchestrator does not write or commit")
- Modify: `docs/05-delegation.md` (new `## Process ladder` after `## Model ladder`; `## Task record` adds mode; `## Ladder review` adds the process numbers)
- Modify: `AGENTS.md` (line 11)
- Modify: `docs/templates/plan.md` (Tasks table: `| Mode |` column after `| Rung |`, cell text `native / delegated (risky is always delegated)`)
- Modify: `README.md` (step 2: one sentence on `features.process_ladder`)
- Modify: `.claude-plugin/plugin.json` (`0.7.0` to `0.8.0`), `tools/check-ladder-docs.sh`

**Interfaces, exact phrases the pins require:**
- Skill line 7: "You do not write files and you do not commit in the main checkout; in native mode you work in a task worktree (Process ladder below)."
- Skill `## Process ladder`: the table from the spec (columns Mode, Who works, Where, Review, When); the sentence "Risky tier is never native, whatever `process.default_mode` says."; the procedure as a numbered list ending with "return to the main checkout"; the escalation sentence "A native task that touches more than `process.native_max_files` files or passes `process.native_max_tool_calls` tool calls stops, commits its work in progress, and hands the worktree to a worker; the mode never goes back to native."; the workspace comment line `orca worktree set --worktree active --comment "<task>: mode=native tier=<tier> rung=<rung>" --json`; "Docs-only diffs skip Codex at normal tier; any code change gets it."; "With `features.process_ladder` off every task is delegated."
- docs/05 `## Process ladder`: the same table and rules in policy voice; Task record: "and the mode (native or delegated)"; Ladder review: a bullet "Process numbers: tasks by mode, tokens and wall time per task, reviewer findings per mode, escalations from native to delegated."
- AGENTS.md line 11: "Claude Code is the orchestrator and does not write code or commit in the main checkout; in native mode (docs/05, Process ladder) it works in a task worktree. Codex is the independent reviewer. Explicit user assignments take precedence."
- Pins: `need skills/orchestrator/SKILL.md "## Process ladder"`, `"Risky tier is never native"`, `"never goes back to native"`, `"mode=native tier=<tier> rung=<rung>"`, `"Docs-only diffs skip Codex"`, `"With \`features.process_ladder\` off"`; `need docs/05-delegation.md "## Process ladder"`, `"Process numbers"`; `need AGENTS.md "in the main checkout; in native mode"`; `need docs/templates/plan.md "| Mode |"`; `need README.md "features.process_ladder"`; `need config/crew64.defaults.json '"native_max_files": 3'`; version pin `0.8.0`; `forbid skills/orchestrator/SKILL.md "You do not write files and you do not commit."`.

- [ ] **Step 1: Write the failing pins**

- [ ] **Step 2: Run to verify it fails**

Run: `bash tools/check-ladder-docs.sh; echo exit=$?`
Expected: the new pins missing, the forbid line reported, `exit=1`.

- [ ] **Step 3: Edit the files per Interfaces and bump the version**

- [ ] **Step 4: Run to verify it passes**

Run: `bash tools/check-ladder-docs.sh && bash tools/test-crew64-config.sh | grep -c FAIL; claude plugin validate . && git diff --check && echo OK`
Expected: `ladder docs OK`, `0`, `OK`.

- [ ] **Step 5: Commit**

```bash
git add skills/orchestrator/SKILL.md docs/05-delegation.md AGENTS.md docs/templates/plan.md README.md .claude-plugin/plugin.json tools/check-ladder-docs.sh
git commit -m "feat(policy): the process ladder (decision 0009); plugin 0.8.0"
```

---

## After the tasks

- Full verification list from a clean tree; push from `~/Projects/ai-developement-system`; PR; Codex brief via `--spec-file` at `--effort high` with the Runtime floor and the Review Focus items.
- Clean review: bot approval, merge, reviewer worktree removed, plugin cache updated on each machine.
- First use: the next crew64 round runs under the ladder, and its completion reports are the first process numbers for the ladder review.
