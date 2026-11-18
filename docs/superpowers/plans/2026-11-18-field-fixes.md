# Field Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the four plugin defects found by the first harnessed sessions: scratch writes denied by the guard, the orchestrator line missing from harness-enable's commit behind a symlink, a stale user-level harness-enable skill, and invisible Orca version drift.

**Architecture:** Each fix lands in the file that owns the behaviour, with its test in the existing harness for that file: the guard hook and its test, the enable script and its test, a new one-line version-check script with its own test, and the orchestrator skill plus pin script for the wording.

**Tech Stack:** Python 3.13+ standard library, bash, `claude plugin validate`.

**Spec:** `docs/superpowers/specs/2026-11-18-field-fixes-design.md`

## Global Constraints

- Risky tier throughout: rung 2, one implementer, Codex review at `--effort high`, Runtime floor Python 3.13+ and bash on Linux.
- Standard library only; `python3 -I` everywhere.
- Scratch allowance: raw target with a `..` segment is denied; otherwise `os.path.realpath(target)` must be under `/tmp/` or `$TMPDIR/`. Nothing else the guard denies today changes.
- The wrapper install writes only when content differs, reports every run, honours `$HOME`, and is skipped by `--no-skill`.
- The version check always exits 0 and prints exactly `orca=<v|none> docs12=<v|none> drift=yes|no`.
- Repo verification list applies after every task: `bash tools/hooks/test-orchestrator-guard.sh`, `bash tools/test-crew64-enable.sh`, `bash tools/test-crew64-config.sh`, `bash tools/bot/test-bot-scripts.sh`, `bash tools/check-ladder-docs.sh`, `bash -n` on changed scripts, `python3 -m py_compile tools/hooks/orchestrator-guard.py`, `claude plugin validate .`, `git diff --check`.
- Conventional commits, no `Co-Authored-By`.

## Tooling

| Part of the job | Tool (exact id) | Kind | Used at | Why this one |
|---|---|---|---|---|
| Scratch allowance | hand-written in `tools/hooks/orchestrator-guard.py` | library | runtime | the hook; reuse of its realpath style |
| Guard tests | `tools/hooks/test-orchestrator-guard.sh` (extend) | script | verify | `run`, `runenv`, `raw` helpers exist |
| Symlink staging, wrapper install | hand-written in `tools/crew64-enable.sh` | script | runtime | the enable script owns the commit and the machine setup |
| Enable tests | `tools/test-crew64-enable.sh` (extend) | script | verify | temp repos, Orca stub, `sums` helper |
| Version check | hand-written `tools/orca-version-check.sh` + `tools/test-orca-version-check.sh` | script | runtime / verify | one line, stubbed `ORCA_CLI_COMMAND` |
| Wording pins | `tools/check-ladder-docs.sh` (extend) | script | verify | existing mechanism |
| Tests first | `superpowers:test-driven-development` | skill | build | repo rule |
| Evidence before done | `superpowers:verification-before-completion` | skill | verify | |
| Independent review | Codex worker: `orca orchestration worker-start --agent codex --model gpt-6.1-sol --effort high --spec-file <brief>` | agent | verify | risky tier; the brief goes through `--spec-file`, which this round also documents |
| Pull request | `gh pr create`, approval by the agent identity via `tools/bot/gh-bot` with `CREW64_FEATURE_BOT_IDENTITY=on` after a clean review, as PR 19 | CLI | verify | main requires one approving review from a writer |
| Rules | repo `AGENTS.md`; `~/.claude/rules/ecc/common/essentials.md` | rule | build | |

**Checked and rejected:** `ecc:python-reviewer` (plugin disabled; Codex is the reviewer); `caveman:cavecrew-reviewer` (same session, not independent); `update-config` skill (it edits Claude settings, not a plugin hook); shipping harness-enable as a plugin skill (decision 0005 rejected it).

**Gaps to build first:** none. The version-check script is Task 4, a module of this repo, not a reusable gap (`candidate on second use: orca-version-check`).

## Review Focus

1. A symlink inside `/tmp` pointing into the repo, written through the symlink: must be denied (realpath leaves `/tmp`). Pinned by Task 1.
2. `TMPDIR` set to a directory inside the repo: the allowance would then permit repo writes. Ruling in Task 1: `$TMPDIR` under the repo's real path is ignored for the allowance (treated as unset), pinned by a test.
3. `CLAUDE.md` symlink whose target is outside the repo: `git add` of the target would fail. Pinned by Task 2: the target joins `files` only when it resolves inside the repo; otherwise the run reports it and commits the rest.
4. `$HOME` unwritable or missing `~/.claude`: the enable run must not fail the repo part. Pinned by Task 3: the skill step reports `skill: skipped (<reason>)` and continues.
5. `orca --version` output with a prefix such as `orca 1.4.259` or a missing binary: the check prints `none` and `drift=no`, never a traceback. Pinned by Task 4.

## Owner items

| Item | Who issues it | Blocks |
|---|---|---|
| none | | |

## Tasks

| Task | Tier | Rung | Vendor | Model | Tools | Acceptance | Owner item |
|---|---|---|---|---|---|---|---|
| 1. Guard allows scratch writes | risky | 2 | Claude; Codex review | claude-opus-5-5 / gpt-6.1-sol high | guard hook, guard test, orchestrator skill | guard test all ok | none |
| 2. Enable stages the symlink target | risky | 2 | same | same | enable script, enable test | enable test all ok | none |
| 3. Enable installs the user skill | risky | 2 | same | same | enable script, shipped wrapper files, enable test, README | enable test all ok | none |
| 4. Orca version check | risky | 2 | same | same | new script and test, docs/12, skill, pins | its test ok, `ladder docs OK` | none |

---

### Task 1: Guard allows scratch writes

**Files:**
- Modify: `tools/hooks/orchestrator-guard.py` (`WRITE_TOOLS` block near line 54; `main()` at line 410)
- Modify: `tools/hooks/test-orchestrator-guard.sh` (line 53 flips; new cases after line 55)
- Modify: `skills/orchestrator/SKILL.md` (`## Delegation`, supervised bullet)
- Modify: `tools/check-ladder-docs.sh` (pins)

**Interfaces:**
- Produces `scratch_target(target: str, env: Mapping = os.environ) -> bool` in the hook. True when no path segment of the raw `target` equals `..` and `os.path.realpath(target)` is `/tmp` or under `/tmp/`, or is under the realpath of `env["TMPDIR"]` when that is set and is not itself inside the current repo (`os.path.realpath(cwd)` passed by the caller via `os.getcwd()` is enough: the hook's cwd is the checkout). Relative targets resolve against the hook's cwd and so never match.
- `main()`: for `tool in WRITE_TOOLS`, read `target = tool_input.get("file_path") or tool_input.get("notebook_path")`; if `isinstance(target, str) and scratch_target(target)` return 0. This check runs before `in_worktree`.

- [ ] **Step 1: Write the failing tests**

In `tools/hooks/test-orchestrator-guard.sh`, change line 53 to expect 0, and add after line 55:

```bash
# Decision 0007 field fixes: the session scratchpad under /tmp or $TMPDIR is writable from any checkout.
run 0 "$M" Write  '{"file_path":"/tmp/brief.md","content":"hi"}'
run 0 "$W" Edit   '{"file_path":"/tmp/brief.md","old_string":"a","new_string":"b"}'
run 2 "$M" Write  '{"file_path":"/tmp/../etc/passwd","content":"hi"}'
mkdir -p "$TMP/scratch"; ln -s "$M" "$TMP/scratch/repo"; ln -s "$TMP/scratch" /tmp/guardtest-$$ 2>/dev/null || true
run 2 "$M" Write  "{\"file_path\":\"/tmp/guardtest-$$/repo/x.md\",\"content\":\"hi\"}"   # symlink out of /tmp into the repo
rm -f /tmp/guardtest-$$
runenv TMPDIR="$TMP/scratch" 0 "$M" Write "{\"file_path\":\"$TMP/scratch/b.md\",\"content\":\"hi\"}"   # TMPDIR allowance
runenv TMPDIR="$M/tmp" 2 "$M" Write "{\"file_path\":\"$M/tmp/b.md\",\"content\":\"hi\"}"              # TMPDIR inside the repo: ignored
run 2 "$M" Write  '{"file_path":"tmp/b.md","content":"hi"}'                                             # relative: not scratch
```

`runenv` is defined at line 197 today; move its definition up beside `run` so these cases can use it.

- [ ] **Step 2: Run to verify it fails**

Run: `bash tools/hooks/test-orchestrator-guard.sh | grep -c FAIL`
Expected: `4` (the two `/tmp` allowances, the `TMPDIR` allowance, and line 53).

- [ ] **Step 3: Implement `scratch_target()` and the early return in `main()`**

- [ ] **Step 4: Edit the skill and pins**

`skills/orchestrator/SKILL.md`, supervised bullet: replace `worker-start --spec "<brief>"` with `worker-start --spec-file <path> ` and append the sentence: "Write the brief to the session scratchpad under `/tmp` first; the guard allows Write and Edit there from any checkout (field fixes 2026-11-18). `--spec "<text>"` remains for one-line briefs." Pins: `need skills/orchestrator/SKILL.md "--spec-file"` and `need skills/orchestrator/SKILL.md "the guard allows Write and Edit there"`.

- [ ] **Step 5: Run to verify it passes**

Run: `bash tools/hooks/test-orchestrator-guard.sh | grep -c FAIL; python3 -m py_compile tools/hooks/orchestrator-guard.py && bash tools/check-ladder-docs.sh && git diff --check && echo OK`
Expected: `0`, `ladder docs OK`, `OK`.

- [ ] **Step 6: Commit**

```bash
git add tools/hooks/orchestrator-guard.py tools/hooks/test-orchestrator-guard.sh skills/orchestrator/SKILL.md tools/check-ladder-docs.sh
git commit -m "fix(guard): allow Write and Edit to the session scratchpad under /tmp and TMPDIR"
```

---

### Task 2: Enable stages the symlink target

**Files:**
- Modify: `tools/crew64-enable.sh` (commit step, the `for f in ...` loop near line 164)
- Modify: `tools/test-crew64-enable.sh` (new case 5h before `# 5. --no-commit stages only`)

**Interfaces:**
- After the loop builds `files`, when `[ -L "$repo/CLAUDE.md" ]`: `target="$(realpath "$repo/CLAUDE.md")"`; if `case "$target" in "$repo"/*)` then `files+=("${target#"$repo"/}")` else `echo "CLAUDE.md: symlink target $target is outside the repository; the orchestrator line was written there but not committed"`.

- [ ] **Step 1: Write the failing test**

```bash
# 5h. CLAUDE.md is a symlink to AGENTS.md (new-repo convention): the orchestrator
# line lands in AGENTS.md and that file is in the enable commit; the tree is clean.
R15="$TMP/r15"; newrepo "$R15"; printf '# Rules\n' > "$R15/AGENTS.md"; ln -s AGENTS.md "$R15/CLAUDE.md"
git -C "$R15" add AGENTS.md CLAUDE.md && git -C "$R15" commit -q -m "rules + symlink"
out="$(bash "$ENABLE" "$R15" 2>&1)"; rc=$?
[ "$rc" = 0 ] && grep -q 'crew64:orchestrator' "$R15/AGENTS.md" && [ -L "$R15/CLAUDE.md" ] && [ -z "$(git -C "$R15" status --porcelain)" ] && git -C "$R15" show --stat HEAD | grep -q 'AGENTS.md' && ok "symlinked CLAUDE.md: AGENTS.md carries the line and is committed" || bad "symlink: rc=$rc status=$(git -C "$R15" status --porcelain | tr '\n' ' ') out=$out"
# a symlink whose target is outside the repo is reported, not fatal
R16="$TMP/r16"; newrepo "$R16"; printf 'x\n' > "$TMP/outside-rules.md"; ln -s "$TMP/outside-rules.md" "$R16/CLAUDE.md"; git -C "$R16" add CLAUDE.md && git -C "$R16" commit -q -m link
out="$(bash "$ENABLE" "$R16" 2>&1)"; rc=$?
[ "$rc" = 0 ] && case "$out" in *"outside the repository"*) true;; *) false;; esac && ok "symlink outside the repo is reported and the run succeeds" || bad "outside symlink: rc=$rc out=$out"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tools/test-crew64-enable.sh | grep FAIL`
Expected: the 5h "symlinked CLAUDE.md" case FAILs (status shows ` M AGENTS.md`); the outside case FAILs on the missing message.

- [ ] **Step 3: Implement per Interfaces**

- [ ] **Step 4: Run to verify it passes**

Run: `bash tools/test-crew64-enable.sh | grep -c FAIL; bash -n tools/crew64-enable.sh && git diff --check && echo OK`
Expected: `0`, `OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/crew64-enable.sh tools/test-crew64-enable.sh
git commit -m "fix(enable): commit the orchestrator line when CLAUDE.md is a symlink"
```

---

### Task 3: Enable installs the user skill

**Files:**
- Create: `tools/harness-enable-skill/SKILL.md` (the current `~/.claude/skills/harness-enable/SKILL.md` text with `<ai-dev-system.json>` replaced by `<crew64.json>` and the command shown as `bash ~/.claude/skills/harness-enable/enable.sh /path/to/repo [--config <crew64.json>] [--no-commit] [--no-skill]`)
- Create: `tools/harness-enable-skill/enable.sh.tmpl` (three lines: shebang, comment "Thin wrapper installed by tools/crew64-enable.sh; the real script ships in the crew64 plugin.", `exec bash "@CREW64_ENABLE@" "$@"`, with a file-exists check that names the path when missing)
- Modify: `tools/crew64-enable.sh` (option parsing: `--no-skill`; new step 0 after argument parsing, before step 1; usage comment)
- Modify: `tools/test-crew64-enable.sh` (new case 5i)
- Modify: `README.md` step 1 and `tools/check-ladder-docs.sh` (pin `need README.md "/harness-enable"`)

**Interfaces:**
- Step 0 writes `$HOME/.claude/skills/harness-enable/SKILL.md` and `enable.sh` (mode 755). Rendering: `sed "s|@CREW64_ENABLE@|$plugin_root/tools/crew64-enable.sh|"`. Compare rendered content with the installed file; print `skill: installed ~/.claude/skills/harness-enable`, `skill: refreshed ...`, or `skill: current ...`. If `mkdir -p` or the write fails, print `skill: skipped (<reason>)` to stdout and continue. `--no-skill` prints `skill: skipped (--no-skill)`.

- [ ] **Step 1: Write the failing test**

```bash
# 5i. the user-level harness-enable wrapper is installed, refreshed and left alone when current
H="$TMP/home"; mkdir -p "$H"; R17="$TMP/r17"; newrepo "$R17"
out="$(HOME="$H" bash "$ENABLE" "$R17" 2>&1)"; rc=$?
[ "$rc" = 0 ] && case "$out" in *"skill: installed"*) true;; *) false;; esac && [ -x "$H/.claude/skills/harness-enable/enable.sh" ] && grep -qF "$ENABLE" "$H/.claude/skills/harness-enable/enable.sh" && grep -q 'crew64@crew64' "$H/.claude/skills/harness-enable/SKILL.md" && ok "wrapper installed, points at this script" || bad "wrapper install: rc=$rc out=$out"
s1="$(sha256sum "$H/.claude/skills/harness-enable/enable.sh" "$H/.claude/skills/harness-enable/SKILL.md")"
out="$(HOME="$H" bash "$ENABLE" "$R17" 2>&1)"
case "$out" in *"skill: current"*) ok "second run reports the wrapper current";; *) bad "wrapper second run: $out";; esac
[ "$s1" = "$(sha256sum "$H/.claude/skills/harness-enable/enable.sh" "$H/.claude/skills/harness-enable/SKILL.md")" ] && ok "wrapper byte-identical after second run" || bad "wrapper rewritten"
printf 'stale\n' > "$H/.claude/skills/harness-enable/enable.sh"
out="$(HOME="$H" bash "$ENABLE" "$R17" 2>&1)"
case "$out" in *"skill: refreshed"*) ok "stale wrapper is refreshed";; *) bad "wrapper refresh: $out";; esac
out="$(HOME="$TMP/nohome-ro" bash "$ENABLE" "$R17" --no-skill 2>&1)"; rc=$?
[ "$rc" = 0 ] && case "$out" in *"skill: skipped (--no-skill)"*) true;; *) false;; esac && ok "--no-skill skips the wrapper" || bad "--no-skill: rc=$rc out=$out"
mkdir -p "$TMP/ro"; chmod 500 "$TMP/ro"
out="$(HOME="$TMP/ro" bash "$ENABLE" "$R17" 2>&1)"; rc=$?; chmod 700 "$TMP/ro"
[ "$rc" = 0 ] && case "$out" in *"skill: skipped ("*) true;; *) false;; esac && ok "unwritable HOME: wrapper skipped, run succeeds" || bad "ro HOME: rc=$rc out=$out"
```

Also add `HOME="$TMP/home-default"` to the test's exports at the top so earlier cases never touch the real home, and `mkdir -p "$TMP/home-default"`.

- [ ] **Step 2: Run to verify it fails**

Run: `bash tools/test-crew64-enable.sh | grep -c FAIL`
Expected: `5` (every 5i assertion).

- [ ] **Step 3: Create the two shipped files and implement step 0 and `--no-skill`**

- [ ] **Step 4: README and pin**

README step 1, append: "The run also installs or refreshes the user-level `/harness-enable` skill at `~/.claude/skills/harness-enable`, a wrapper that forwards to this script (`--no-skill` skips it)." Pin: `need README.md "/harness-enable"`.

- [ ] **Step 5: Run to verify it passes**

Run: `bash tools/test-crew64-enable.sh | grep -c FAIL; bash -n tools/crew64-enable.sh tools/harness-enable-skill/enable.sh.tmpl; bash tools/check-ladder-docs.sh && git diff --check && echo OK`
Expected: `0`, `ladder docs OK`, `OK`. (`bash -n` on the template passes: the placeholder sits inside quotes.)

- [ ] **Step 6: Commit**

```bash
git add tools/harness-enable-skill tools/crew64-enable.sh tools/test-crew64-enable.sh README.md tools/check-ladder-docs.sh
git commit -m "feat(enable): install and refresh the user-level harness-enable wrapper"
```

---

### Task 4: Orca version check

**Files:**
- Create: `tools/orca-version-check.sh`
- Create: `tools/test-orca-version-check.sh`
- Modify: `docs/12-orca-setup.md:9` (State row: `1.4.255 verified 2026-11-17 (local host)...`)
- Modify: `skills/orchestrator/SKILL.md` (`## Configuration`, first bullet: add the second command)
- Modify: `AGENTS.md` verification list (run the new test when the script changes)
- Modify: `tools/check-ladder-docs.sh` (pins)

**Interfaces:**
- `tools/orca-version-check.sh [docs12-path]`: default docs path `$(dirname "$0")/../docs/12-orca-setup.md`. Running version: `"${ORCA_CLI_COMMAND:-orca}" --version 2>/dev/null`, first match of `[0-9]+\.[0-9]+\.[0-9]+`, else `none`. Recorded: first match of the same pattern on the first line matching `^\| Orca \|` in the docs file, else `none`. Output exactly `orca=<a> docs12=<b> drift=<yes|no>` where drift is `yes` only when both are versions and differ. Exit 0 always.

- [ ] **Step 1: Write the failing test**

`tools/test-orca-version-check.sh`, same style (`ok`/`bad`, temp dir):

```text
stub prints "1.4.259"; docs row "| Orca | 1.4.255 verified ..."  → orca=1.4.259 docs12=1.4.255 drift=yes
stub prints "orca 1.4.255 (build x)"; same docs                   → orca=1.4.255 docs12=1.4.255 drift=no
ORCA_CLI_COMMAND=/nonexistent                                      → orca=none docs12=1.4.255 drift=no ; exit 0
docs file without an Orca row                                      → docs12=none drift=no
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tools/test-orca-version-check.sh; echo exit=$?`
Expected: every case FAIL (script missing), `exit=1`.

- [ ] **Step 3: Implement the script**

- [ ] **Step 4: Docs, skill, AGENTS.md, pins**

- docs/12 State row: `| Orca | 1.4.255 verified 2026-11-17 on the local host (1.4.242 at the 2026-10-27 setup); runtime ready, ... |` keeping the rest of the cell.
- Skill, Configuration first bullet, append: "Second command: `bash "${CLAUDE_PLUGIN_ROOT}/tools/orca-version-check.sh"`; paste its line after the status line. `drift=yes` means this host runs an Orca version docs/12 has not verified: say so and carry on."
- AGENTS.md verification: add `bash tools/test-orca-version-check.sh` to the bullet that lists the config, bot and enable tests.
- Pins: `need skills/orchestrator/SKILL.md "orca-version-check.sh"`, `need docs/12-orca-setup.md "| Orca | 1.4.255"`, `need AGENTS.md "test-orca-version-check.sh"`.

- [ ] **Step 5: Run to verify it passes**

Run: `bash tools/test-orca-version-check.sh && bash tools/orca-version-check.sh && bash tools/check-ladder-docs.sh && bash -n tools/orca-version-check.sh tools/test-orca-version-check.sh && git diff --check && echo OK`
Expected: all ok, one `orca=... docs12=1.4.255 drift=...` line, `ladder docs OK`, `OK`.

- [ ] **Step 6: Commit**

```bash
git add tools/orca-version-check.sh tools/test-orca-version-check.sh docs/12-orca-setup.md skills/orchestrator/SKILL.md AGENTS.md tools/check-ladder-docs.sh
git commit -m "feat(skill): report Orca version drift against docs/12 at session start"
```

---

## After the tasks

- Full verification list from a clean tree, then `claude plugin validate .`.
- Push from `~/Projects/ai-developement-system` (the real main checkout; the bot helper intercepts linked worktrees), open the PR, write the Codex brief to the scratchpad and dispatch with `--spec-file` at `--effort high` with the Runtime floor.
- After a clean review: approve as the agent identity (`CREW64_FEATURE_BOT_IDENTITY=on tools/bot/gh-bot pr review <n> --approve`) and merge, as PR 19.
- Owner items after merge: re-run `tools/crew64-enable.sh` on a harnessed repo on each machine to refresh the wrapper; delete `~/.claude/plugins/cache/ai-dev-system` on the home-office machine.
