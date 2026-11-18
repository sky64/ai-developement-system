# Field fixes from the first harnessed sessions (2026-11-18)

Status: approved by the owner in the Orca chat of 2026-11-18 ("follow your recommendations"). Short design; implemented by [the field-fixes plan](../plans/2026-11-18-field-fixes.md). No new decision record: these are defects in how decisions 0005 and 0006 were carried out, not new decisions.

## Intent

An orchestrator session in a harnessed application repository on the home-office machine produced a consolidated list of twelve findings. Four are defects in the plugin and are fixed here; the rest are config values or owner decisions and stay with the owner. The four:

1. **The guard denies scratch writes.** The hook denies every file-write tool in the main checkout and, in a worktree, every target outside it. An orchestrator therefore cannot write a brief to its session scratchpad under `/tmp` and had to pass a 9,000-character brief inline with quotes stripped. Bash redirects to `/tmp` are already allowed by the same hook, so the rule is inconsistent. `orca orchestration worker-start --spec-file` already exists; the skill does not mention it.
2. **harness-enable leaves the orchestrator line out of its own commit** when `CLAUDE.md` is a symlink to `AGENTS.md` (the `new-repo` convention). The line is appended through the symlink and lands in `AGENTS.md`, but only `CLAUDE.md`, the unchanged symlink, is staged. The report of a worktree being registered as a second Orca repo is already refused by the script since PR 15; it is re-verified by the existing test 5f and not changed here.
3. **The user-level `harness-enable` skill is stale on other machines.** On the home-office machine it is the pre-0005 version and would write `ai-dev-system@ai-dev-system` into a repo's settings. On this machine it is a wrapper that hardcodes `~/.local/share/ai-dev-system-main`, a path that exists nowhere else. The wrapper must be installed and refreshed by the plugin's own script, pointing at wherever that script lives.
4. **Orca version drift is invisible.** The orchestrator skill cites 1.4.242, docs/12 records 1.4.255, the home-office host runs 1.4.259. docs/12 is a verification log, so a session on a different version should say so in its first line.

## Goals

- Write and Edit tools may target the session scratchpad (`/tmp` and `$TMPDIR`) from any checkout, under the same no-climb rule the Bash redirect check already applies, and with symlinks resolved so a link out of `/tmp` into a repo is still denied.
- harness-enable's commit contains the orchestrator line wherever it landed.
- Every machine that runs `tools/crew64-enable.sh` gets a current user-level `harness-enable` skill that forwards to that script's real location.
- The orchestrator's first line names the running Orca version and flags a difference from the version docs/12 records.

## Non-goals

- Any change to what the guard allows inside a repository.
- Deleting the old `ai-dev-system` plugin cache on the owner's machines (a config step, listed for the owner).
- Verifying Solvela metering, the Codex-through-Solvela path or the DeepSeek profiles (owner items 1, 3, 4, 5 of the field list).

## Anti-goals

- A scratch allowance that can be aimed at a repo: realpath first, then the prefix test; a raw path containing `..` is denied before resolution, as the redirect rule does.
- A wrapper that overwrites a user's own skill silently: the install is reported on every run, writes only when content differs, and `--no-skill` skips it.
- A version check that fails the session: drift is a reported fact, never an exit.

## Constraints

- Standard library Python, `python3 -I`, bash; the existing test harnesses (`tools/hooks/test-orchestrator-guard.sh`, `tools/test-crew64-enable.sh`) and pin script.
- Risky tier throughout (hook, enable script, orchestrator skill): rung 2, Codex review at effort high, Runtime floor Python 3.13+ and bash on Linux.
- The guard test case `MultiEdit /tmp/outside.md` from a worktree currently expects a denial; it flips to an allowance by this design.

## Approaches considered

- **Scratch allowance in the guard (chosen)** versus telling orchestrators to always use `--spec` inline (rejected: the 9,000-character inline brief is the defect) versus a dedicated brief directory inside the repo (rejected: it would be a write in the main checkout, which the guard exists to deny).
- **Wrapper installed by the enable script (chosen)** versus shipping harness-enable as a plugin skill (rejected in decision 0005: the plugin is enabled per project and cannot run before the repo is harnessed) versus documenting a manual copy (rejected: that is how the home-office copy went stale).
- **A tiny version-check script the skill runs (chosen)** versus prose only in the skill (rejected: the orchestrator would have to parse docs/12 by eye every session).

## Design

1. `tools/hooks/orchestrator-guard.py`: `scratch_target(target: str) -> bool` is true when the raw target has no `..` segment and `os.path.realpath(target)` is under `/tmp/` or under `$TMPDIR/` (when set), using a realpath prefix test. `main()` returns 0 for a write tool whose target satisfies it, in both the main checkout and the worktree branch, before the existing denials. Denied targets keep their current messages.
2. `tools/crew64-enable.sh`, commit step: when `CLAUDE.md` is a symlink, the resolved target's path relative to the repo joins the `files` list before `git add`. The orchestrator line is still appended through `CLAUDE.md`.
3. `tools/crew64-enable.sh`, new step 0 "user skill": installs `~/.claude/skills/harness-enable/SKILL.md` and `enable.sh` from `tools/harness-enable-skill/SKILL.md` and `tools/harness-enable-skill/enable.sh.tmpl`, substituting the real path of `crew64-enable.sh` for `@CREW64_ENABLE@`. Writes only when the content differs, prints `skill: installed`, `skill: refreshed` or `skill: current`, and `--no-skill` skips the step. `$HOME` is honoured so tests can redirect it.
4. `tools/orca-version-check.sh`: prints one line `orca=<running|none> docs12=<recorded|none> drift=yes|no`. The running version comes from `${ORCA_CLI_COMMAND:-orca} --version` (first token that looks like a version); the recorded one from the `| Orca | <version>` row of docs/12 under `## State`. Exit 0 always. The orchestrator skill runs it as the second command of the session and pastes the line after the config status line. docs/12's State row is updated to 1.4.255, the version actually verified on 2026-11-17.
5. Skill text: the Delegation bullet for supervised dispatch shows `--spec-file <path under /tmp>` and says the guard allows Write to the scratchpad for this purpose. Pins in `tools/check-ladder-docs.sh` for the new phrases; README's "Using this on your own setup" step 1 mentions that the run installs the `/harness-enable` skill.

## Left to the builder

- Exact wording of the three `skill:` report lines and the `--no-skill` help text.
- Whether `scratch_target` also accepts `/dev/null` (harmless either way).
- Test fixture layout for the symlinked `CLAUDE.md` repo and the redirected `$HOME`.

## Owner items after merge

- Re-run `tools/crew64-enable.sh` once on each machine (any harnessed repo) so the wrapper is refreshed, then remove `~/.claude/plugins/cache/ai-dev-system` on the home-office machine.
- Field items 1, 2, 3, 4, 5, 8 and 12 remain the owner's or the application repo's.
