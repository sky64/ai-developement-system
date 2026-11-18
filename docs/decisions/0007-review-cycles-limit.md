# 0007: The per-task allowance is a config value, `limits.review_cycles`

Date: 2026-11-18. Status: accepted by the owner in the Orca chat of 2026-11-18 after the approaches were laid out and a short design approved. Implemented by [the review-cycles plan](../superpowers/plans/2026-11-18-review-cycles-limit.md).

## Intent

AGENTS.md and docs/05 cap each task at "one allowance of two": correction/review cycles, retries of a failed operation and model-ladder escalations all draw on it. The allowance was written when Codex calls looked scarce. The owner has a Codex subscription with plenty of capacity and, on 2026-11-17, authorized a third cycle on PR 14 by hand. Their constraints are determinism and waste, not review count. A cost guard whose right value differs per install belongs in the per-repo config, which is the rule decision 0005 set; keeping it in policy text forced the owner to override policy by hand.

The owner asked whether the cap of two had been failing them. The record says no: the one case where it bit (PR 14) was resolved by a third cycle, and the installer's nine cycles went six times to a Python fallback branch that never runs on the owner's machines. A higher cap would have let that loop run longer. The defect there was the reviewer's brief, which never said which runtime it reviewed against. This record therefore changes two things: where the number lives, and what the reviewer is told.

## Goals

- The allowance is one integer in `.claude/crew64.json`, `limits.review_cycles`, default 2, readable by the same reader as every switch and echoed in the status line.
- Policy text names the configured value instead of the number two.
- A session can raise it without a risky-tier config edit, through an environment variable, the same way the feature switches work.
- Reviewer briefs name the runtime floor the review applies to, so cycles are not spent on code paths that never run.

## Non-goals

- Separate limits per kind (cycles, retries, escalations). The allowance stays one budget, as AGENTS.md says ("one budget, not three").
- Changing the default. Two remains the shipped value; the owner's example config carries three.
- Any executable enforcement of the count. Only prose reads it today; the orchestrator keeps the count in the task record.

## Anti-goals

- A silent limit: the status line must show the effective value, and a wrong type must fall back to the default and be visible as such.
- A second schema version for one optional key: the 17 enabled repos keep working untouched.
- A name in the config that lies about scope: the key is `review_cycles` because the owner chose it, and this record and docs/05 say plainly that it governs cycles, retries and escalations together.

## Constraints

- Standard library Python, `python3 -I`, as in `tools/crew64_config.py`.
- Fail safe: missing `limits`, missing `review_cycles`, or a value that is not a positive integer means the default. Booleans are not integers here (`true` is not 1).
- All edits are risky tier under docs/05 (AGENTS.md, policy, the config reader the hook imports).
- The check script `tools/check-ladder-docs.sh` pins the wording; every pin that names "two" must move with the text.

## Approaches considered

1. **One shared number, `limits.review_cycles`, default 2** (chosen). Matches the policy as written; one counter per task; the smallest change. Cannot express "many review cycles but one retry".
2. **Three numbers** (`review_cycles`, `retries`, `escalations`). Reverses "one budget, not three" and makes every brief and completion report track three counters. Rejected.
3. **One shared number plus optional per-kind caps.** More config than the harness's five features justify. Rejected.

The owner picked approach 1 and the name `review_cycles` (over the proposed `task_allowance`).

## Decision

### 1. The config key

```json
"limits": { "review_cycles": 2 }
```

- Added to `config/crew64.defaults.json` (value 2) and `config/examples/orca-solvela.json` (value 3, the owner's choice for their installs).
- Schema version stays 1. `check` accepts a config without `limits`; when `limits` is present, `limits.review_cycles` must be an integer of at least 1, and `check` names the problem otherwise.
- `crew64_config.py` gains `limit(cfg, name, env)`: environment `CREW64_LIMIT_REVIEW_CYCLES=<n>` (a positive integer) beats the file, then the file, then the default. Anything else, including a boolean, a float, zero, a negative number or a malformed environment value, falls back to the next source.
- `get limits.review_cycles` prints the effective value with the same fallbacks. The status line gains ` review_cycles=<n>`, placed after `build_map`.

### 2. Who reads it

- **The orchestrator skill**: the Configuration section lists the limit beside the switches and says how to read it; Rungs and models says escalations, correction cycles and retries share one allowance of `limits.review_cycles` per task (default 2), and "After two escalations" becomes "when the allowance is spent".
- **AGENTS.md**: the allowance bullet names `limits.review_cycles` in `.claude/crew64.json` (default 2) and keeps "one budget, not three".
- **docs/05**: the risky-tier table's reviewer cell reads "up to `limits.review_cycles` correction cycles (default 2)"; the ladder bullet "at most two escalations" becomes "at most `limits.review_cycles` escalations".
- **Nothing executable** reads it. The orchestrator counts in the task record, as today.

### 3. When the allowance is spent

The orchestrator stops, reports to the owner, and asks once whether to continue. A yes grants one more cycle, recorded in the task record with the owner's word. This is the manual escape hatch that keeps the config the policy. It is written once, in the orchestrator skill, and docs/05 points at it.

### 4. The reviewer's runtime floor

Every reviewer brief carries a line `Runtime: <the interpreters, versions and platforms this code must run on>`, taken from the application repository's own AGENTS.md or CLAUDE.md, or stated by the orchestrator when they are silent. The reviewer is told that findings about code paths outside that floor are out of scope unless they are security findings. For this repository the floor is Python 3.13+ and bash on Linux, recorded in AGENTS.md "Verification for this repository". The specialist template and the orchestrator skill carry the line; the check script pins it.

### 5. Pins and tests

- `tools/check-ladder-docs.sh`: the three pins that quote "two" move to the new wording, and new pins cover `limits.review_cycles` in AGENTS.md, docs/05, the orchestrator skill and the defaults file, and `Runtime:` in the template and the skill.
- `tools/test-crew64-config.sh`: cases for the default without `limits`, a file value, the environment override, each rejected value falling back, the status line field, and `check` on a bad value.

## Left to the builder

- Exact phrasing of the "allowance spent" question and the task-record line.
- Where in the specialist template the `Runtime:` line sits.
- The order of the new `check` messages.

## Consequences

- One more optional key in every config; nothing changes for a repo that does not add it.
- The owner's installs raise the cap to three by re-copying the example, or by adding the key, a risky-tier edit per repo.
- Review loops stop arguing about dead code paths because the brief says what runs. That, not the number, is what the installer episode called for.
