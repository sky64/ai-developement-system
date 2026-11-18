# Review Cycles Limit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the per-task allowance ("one allowance of two") out of policy text into `limits.review_cycles` in `.claude/crew64.json`, and make every reviewer brief name the runtime floor it reviews against.

**Architecture:** `tools/crew64_config.py` stays the single reader: it gains a `limit()` accessor with the same env-then-file-then-default fallback as `feature()`, validation of the new section in `check`, and a `review_cycles=<n>` field in the status line. Policy text (AGENTS.md, docs/05, the orchestrator skill, the specialist template) replaces the literal "two" with the configured value and adds the `Runtime:` brief line; `tools/check-ladder-docs.sh` pins the new wording.

**Tech Stack:** Python 3.13+ standard library, bash, `claude plugin validate`.

**Spec:** `docs/decisions/0007-review-cycles-limit.md`

## Global Constraints

- Risky tier throughout (AGENTS.md, policy, the module the guard hook imports): rung 2, one implementer, one Codex review, attended.
- Standard library only; every Python invocation is `python3 -I`.
- Fail safe: missing `limits`, missing `review_cycles`, or any value that is not an integer of at least 1 means the default 2. Booleans are not integers here.
- Schema version stays 1; a config without `limits` validates.
- Shipped default 2 in `config/crew64.defaults.json`; 3 in `config/examples/orca-solvela.json`.
- Environment override `CREW64_LIMIT_REVIEW_CYCLES=<n>` beats the file only when `<n>` is an integer of at least 1.
- The allowance stays one budget for correction cycles, retries and escalations; the text keeps "one budget, not three".
- Repo verification list applies: `git diff --check`, `bash -n`, `python3 -m py_compile`, `bash tools/test-crew64-config.sh`, `bash tools/hooks/test-orchestrator-guard.sh`, `bash tools/check-ladder-docs.sh`, `claude plugin validate .`.
- Conventional commits, no `Co-Authored-By`.

## Tooling

| Part of the job | Tool (exact id) | Kind | Used at | Why this one |
|---|---|---|---|---|
| `limit()`, `check`, status field | hand-written in `tools/crew64_config.py` | library | runtime | the single config reader; same fallback shape as `feature()` |
| Reader tests | `tools/test-crew64-config.sh` (extend) | script | verify | existing harness with `run`, `ok`, `bad`, `setfeat` helpers |
| Tests before code | `superpowers:test-driven-development` | skill | build | the repo rule for logic changes |
| Policy and brief wording | hand-written prose | none | build | AGENTS.md, docs/05, orchestrator skill, templates |
| Wording pins | `tools/check-ladder-docs.sh` (extend) | script | verify | the existing pin mechanism; moves the three "two" pins |
| Plugin validity | `claude plugin validate .` | CLI | verify | repo verification list; version bump touches plugin.json |
| Evidence before "done" | `superpowers:verification-before-completion` | skill | verify | run the full list, paste output |
| Independent review | Codex worker: `orca orchestration worker-start --agent codex --model gpt-6.1-sol --effort high` | agent | verify | risky tier requires Codex; rung 2 is `--effort high` |
| Pull request | `gh pr create` | CLI | verify | the repo's merge path |
| Rules obeyed | repo `AGENTS.md` (verification list, conventional commits); `~/.claude/rules/ecc/common/essentials.md` | rule | build | |

**Checked and rejected:** `ecc:python-reviewer` (the ECC plugin is disabled and Codex is this harness's reviewer); `caveman:cavecrew-reviewer` (not independent of the session that wrote the code); a JSON Schema library (not standard library; one integer check); `context7` MCP (unauthenticated and nothing here needs library docs).

**Gaps to build first:** none. All five rosters checked; no part of this job recurs in another repo under `~/Projects` and nothing reads a third-party credential.

## Review Focus

1. `"review_cycles": true` in the file. Python treats `bool` as `int`; the reader must reject it and report 2. Pinned by Task 1.
2. `CREW64_LIMIT_REVIEW_CYCLES=0`, `-1`, `abc` or `2.5` in the environment. Each must fall through to the file value, not to the default and not to a crash. Pinned by Task 1.
3. A config at an unregistered root with `review_cycles` 9. The status line must show `review_cycles=2` and `config=untrusted:`. Pinned by Task 1.
4. `limits` present but empty. `get` prints 2; `check` names `limits.review_cycles`. Pinned by Task 1.
5. A leftover literal "two" in any of the six policy sites after the edits. The pin script must fail on the old phrases, not only pass on the new ones. Pinned by Task 2 (forbid pins).

## Owner items

| Item | Who issues it | Blocks |
|---|---|---|
| none | | |

## Tasks

| Task | Tier | Rung | Vendor | Model | Tools | Acceptance | Owner item |
|---|---|---|---|---|---|---|---|
| 1. `limits.review_cycles` in the reader, defaults and example | risky | 2 | Claude; Codex for review | claude-opus-5-5 / gpt-6.1-sol high | crew64_config.py, test-crew64-config.sh | `bash tools/test-crew64-config.sh` all `ok`, exit 0 | none |
| 2. Policy text names the configured value; pins moved | risky | 2 | Claude; Codex for review | same | AGENTS.md, docs/05, orchestrator skill, check-ladder-docs.sh | `bash tools/check-ladder-docs.sh` prints `ladder docs OK` | none |
| 3. `Runtime:` brief line, repo runtime floor, version 0.6.0 | risky | 2 | Claude; Codex for review | same | templates, orchestrator skill, AGENTS.md, plugin.json, check-ladder-docs.sh | pin script OK, `claude plugin validate .` OK | none |

---

### Task 1: `limits.review_cycles` in the reader, defaults and example

**Files:**
- Modify: `tools/crew64_config.py` (constants near line 24; `feature()` at 160; `status_line()` at 199; `check()` at 228; `cli()` at 283)
- Modify: `config/crew64.defaults.json` (add `"limits": { "review_cycles": 2 }` after `features`)
- Modify: `config/examples/orca-solvela.json` (add `"limits": { "review_cycles": 3 }` after `features`)
- Test: `tools/test-crew64-config.sh` (append cases 15 to 20 before `exit $fail`)

**Interfaces:**
- Produces, in `tools/crew64_config.py`:
  - `LIMITS = ("review_cycles",)` and `LIMIT_ENV_PREFIX = "CREW64_LIMIT_"`.
  - `limit(cfg: dict | None, name: str, env: Mapping = os.environ) -> int`: env `CREW64_LIMIT_<NAME>` when it parses as an `int` of at least 1; else `cfg["limits"][name]` when it is an `int`, not a `bool`, and at least 1; else `defaults()["limits"][name]`.
  - `check()` adds: when `limits` is present it must be an object (`"limits must be an object"`), and `limits.review_cycles` must satisfy the same test (`"limits.review_cycles must be an integer of at least 1"`). A config without `limits` passes.
  - `status_line()` inserts ` review_cycles=<n>` immediately after the `build_map=` field, using `limit(cfg, "review_cycles")`.
  - CLI `get limits.<name>` prints `limit(cfg, name)` with the fallbacks, exit 0; an unknown limit name exits 1 with `crew64_config: unknown limit limits.<name>`.

- [ ] **Step 1: Write the failing tests**

Append to `tools/test-crew64-config.sh` before `exit $fail`. Add a helper beside `setfeat`:

```bash
setlimit() { # <value-json> : write defaults with limits.review_cycles = value ("absent" drops the limits block)
  mkdir -p "$M/.claude"; python3 -I -c '
import json,sys
d=json.load(open(sys.argv[1]))
if sys.argv[2]=="absent": d.pop("limits",None)
elif sys.argv[2]=="empty": d["limits"]={}
else: d["limits"]={"review_cycles": json.loads(sys.argv[2])}
json.dump(d,open(sys.argv[3],"w"))' "$DEFAULTS" "$1" "$M/.claude/crew64.json"; }
```

Cases, each an `ok`/`bad` line in the file's style:

```text
15. setlimit absent ; get limits.review_cycles          → "2" ; status contains "build_map=off review_cycles=2"
    check of that file                                   → exit 0, silent
16. setlimit 3 ; get limits.review_cycles                → "3" ; status contains "review_cycles=3"
    check config/examples/orca-solvela.json              → exit 0, silent (already case 10; re-run after the edit)
17. setlimit true ; get → "2"   setlimit 0 ; get → "2"   setlimit 2.0 ; get → "2"   setlimit '"3"' ; get → "2"
    check of the `true` file                             → exit 1, output contains "limits.review_cycles"
18. setlimit empty ; get → "2" ; check                   → exit 1, output contains "limits.review_cycles"
19. setlimit 3 ; CREW64_LIMIT_REVIEW_CYCLES=5 get        → "5"
    CREW64_LIMIT_REVIEW_CYCLES=0 get → "3"   =-1 → "3"   =abc → "3"   =2.5 → "3"
20. unregistered root $M3 with review_cycles 9 ; status  → contains "config=untrusted:" and "review_cycles=2"
    get limits.bogus                                     → exit 1, stderr contains "unknown limit"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tools/test-crew64-config.sh; echo exit=$?`
Expected: cases 1 to 14 `ok`, cases 15 to 20 `FAIL`, `exit=1`.

- [ ] **Step 3: Add `limits` to the two JSON files and implement `limit()`, the `check` rules, the status field and the CLI branch per Interfaces**

The integer test is one helper, `_positive_int(value) -> int | None`, used by the env parse, the file read and `check`: `isinstance(value, int) and not isinstance(value, bool) and value >= 1`; for the env string, `int(raw.strip())` inside `try`.

- [ ] **Step 4: Run to verify it passes**

Run: `bash tools/test-crew64-config.sh && python3 -m py_compile tools/crew64_config.py && bash -n tools/test-crew64-config.sh && bash tools/hooks/test-orchestrator-guard.sh && git diff --check && echo OK`
Expected: every case `ok`, guard tests pass, `OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/crew64_config.py tools/test-crew64-config.sh config/crew64.defaults.json config/examples/orca-solvela.json
git commit -m "feat(config): limits.review_cycles replaces the hardcoded allowance of two"
```

---

### Task 2: Policy text names the configured value; pins moved

**Files:**
- Modify: `AGENTS.md:27`
- Modify: `docs/05-delegation.md:27` (risky row, Reviewer cell) and `docs/05-delegation.md:65`
- Modify: `skills/orchestrator/SKILL.md:30` and `skills/orchestrator/SKILL.md:69`; add one bullet to `## Configuration`
- Modify: `tools/check-ladder-docs.sh:23,33,56` and the `need skills/orchestrator/SKILL.md "After two escalations"` line

**Interfaces:**
- Produces the exact phrases the pin script requires (Step 3 lists them). Task 3 adds its own pins and must not change these.

- [ ] **Step 1: Write the failing pins**

In `tools/check-ladder-docs.sh`, replace the four pins that quote "two" and add forbid lines:

```bash
need docs/05-delegation.md 'at most `limits.review_cycles` escalations'
need docs/05-delegation.md 'one allowance of `limits.review_cycles` per task'
need docs/05-delegation.md 'up to `limits.review_cycles` correction cycles (default 2)'
need AGENTS.md 'one allowance of `limits.review_cycles` per task'
need AGENTS.md "one budget, not three"
need skills/orchestrator/SKILL.md "When the allowance is spent"
need skills/orchestrator/SKILL.md "limits.review_cycles"
need skills/orchestrator/SKILL.md "CREW64_LIMIT_REVIEW_CYCLES"
need skills/orchestrator/SKILL.md "grants one more cycle"
need config/crew64.defaults.json '"review_cycles": 2'
need config/examples/orca-solvela.json '"review_cycles": 3'
forbid AGENTS.md "allowance of two"
forbid docs/05-delegation.md "allowance of two"
forbid docs/05-delegation.md "at most two escalations"
forbid docs/05-delegation.md "up to two correction cycles"
forbid skills/orchestrator/SKILL.md "allowance of two"
forbid skills/orchestrator/SKILL.md "After two escalations"
forbid skills/orchestrator/SKILL.md "two-cycle allowance"
```

The `forbid` function is defined below the `need` block today; move its definition above the first use.

- [ ] **Step 2: Run to verify it fails**

Run: `bash tools/check-ladder-docs.sh; echo exit=$?`
Expected: each new `need` listed as missing and each `forbid` as "must not contain", `exit=1`.

- [ ] **Step 3: Edit the five sites**

- `AGENTS.md:27`: "Correction/review cycles, retries of a failed operation and model-ladder escalations draw on one allowance of `limits.review_cycles` per task (`.claude/crew64.json`, default 2); it is one budget, not three. When it is spent the orchestrator stops and asks the owner once (orchestrator skill, Rungs and models). Stop at the recorded deadline; ..."
- `docs/05-delegation.md:27` Reviewer cell: "One Codex worker, up to `limits.review_cycles` correction cycles (default 2)".
- `docs/05-delegation.md:65`: "There are at most `limits.review_cycles` escalations per task (default 2). Escalations, reviewer correction cycles and retries of a failed operation draw on one allowance of `limits.review_cycles` per task, the allowance AGENTS.md sets from `.claude/crew64.json`. When it is spent the orchestrator reports to the owner and asks once; the orchestrator skill says what a yes grants."
- `skills/orchestrator/SKILL.md:30`: replace "the two-cycle allowance predates the ladder" with "the `limits.review_cycles` allowance predates the ladder".
- `skills/orchestrator/SKILL.md:69`: replace "share one allowance of two per task. After two escalations, stop and report to the owner." with "share one allowance of `limits.review_cycles` per task (read it with `crew64_config.py get limits.review_cycles`; default 2). When the allowance is spent, stop, report to the owner, and ask once whether to continue; a yes grants one more cycle, recorded in the task record with the owner's words. Never ask twice for the same task."
- `skills/orchestrator/SKILL.md`, `## Configuration`, new bullet after the Switches bullet: "Limits: `limits.review_cycles` (default 2) is the per-task allowance shared by correction cycles, retries and escalations. `CREW64_LIMIT_REVIEW_CYCLES=<n>` beats the file for one session. The status line shows the effective value as `review_cycles=<n>`."

- [ ] **Step 4: Run to verify it passes**

Run: `bash tools/check-ladder-docs.sh && git diff --check && echo OK`
Expected: `ladder docs OK`, then `OK`.

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md docs/05-delegation.md skills/orchestrator/SKILL.md tools/check-ladder-docs.sh
git commit -m "docs(policy): the per-task allowance is limits.review_cycles (decision 0007)"
```

---

### Task 3: `Runtime:` brief line, repo runtime floor, version 0.6.0

**Files:**
- Modify: `agents/specialist-agent.md.tmpl:13` (add a line after the Tier line)
- Modify: `agents/docs-engineer.md:17` (the plugin's portable role; `.claude/agents/docs-engineer.md` is this repo's own agent without a Tier line and is left alone)
- Modify: `skills/orchestrator/SKILL.md`, `## Delegation` (one bullet) and the Platform seam table's "hand a diff to a reviewer" row
- Modify: `AGENTS.md:30-38` (`## Verification for this repository`, one bullet)
- Modify: `docs/05-delegation.md:109-151` (Specialist agent template section mirrors the template file; add the same line)
- Modify: `.claude-plugin/plugin.json` version `0.5.0` to `0.6.0`
- Modify: `tools/check-ladder-docs.sh` (pins)

**Interfaces:**
- Consumes Task 2's pin layout; adds pins only.

- [ ] **Step 1: Write the failing pins**

```bash
need agents/specialist-agent.md.tmpl "Runtime:"
need agents/docs-engineer.md "Runtime:"
need skills/orchestrator/SKILL.md "Runtime:"
need skills/orchestrator/SKILL.md "outside that floor are out of scope"
need docs/05-delegation.md "Runtime:"
need AGENTS.md "Python 3.13+"
need .claude-plugin/plugin.json '"version": "0.6.0"'
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tools/check-ladder-docs.sh; echo exit=$?`
Expected: the seven new pins listed as missing, `exit=1`.

- [ ] **Step 3: Edit the sites**

- Template, `agents/docs-engineer.md` and the docs/05 template section, new line after the Tier line: ``Runtime: <interpreters, versions and platforms this code must run on; findings outside it are out of scope unless they are security findings>``.
- `skills/orchestrator/SKILL.md`, `## Delegation`, new bullet after "Name the tier, base commit, files...": "Every brief, and every reviewer brief in particular, carries `Runtime: <floor>`, taken from the application repository's AGENTS.md or CLAUDE.md, or stated by the orchestrator when they are silent. Tell the reviewer that findings about code paths outside that floor are out of scope unless they are security findings. This is what keeps correction cycles off code that never runs."
- Platform seam table, "hand a diff to a reviewer" row: append ", and the `Runtime:` floor" to the spec contents.
- `AGENTS.md` Verification section, new first bullet: "Runtime floor for this repository: Python 3.13+ and bash on Linux. Reviewer briefs for this repository state it; findings about older interpreters are out of scope unless they are security findings."
- `.claude-plugin/plugin.json`: `"version": "0.6.0"`.

- [ ] **Step 4: Run to verify it passes**

Run: `bash tools/check-ladder-docs.sh && claude plugin validate . && bash -n tools/check-ladder-docs.sh && git diff --check && echo OK`
Expected: `ladder docs OK`, plugin valid, `OK`.

- [ ] **Step 5: Commit**

```bash
git add agents skills/orchestrator/SKILL.md AGENTS.md docs/05-delegation.md .claude-plugin/plugin.json tools/check-ladder-docs.sh
git commit -m "feat(briefs): reviewer briefs name the runtime floor; plugin 0.6.0"
```

---

## After the tasks

- Run the whole verification list once more from a clean tree: `bash tools/test-crew64-config.sh && bash tools/hooks/test-orchestrator-guard.sh && bash tools/bot/test-bot-scripts.sh && bash tools/test-crew64-enable.sh && bash tools/check-ladder-docs.sh && claude plugin validate . && git diff --check`.
- Push `sky64/review-cycles-limit`, open the PR with the three-commit range and this test plan, and hand the diff to a Codex worker at `--effort high` with base and head SHAs, the acceptance lines above, and `Runtime: Python 3.13+ and bash on Linux`.
- Owner follow-up after merge (not a task): the 17 enabled repos pick up `review_cycles` 3 only when their config is re-copied from the example or edited; the default 2 applies until then.
