# Feature Switches and Portability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the ai-dev-system plugin a per-repo config file with feature switches, move every install-specific value out of policy text, and gate the model ladder behind its switch, as decision 0005 specifies.

**Architecture:** One Python module, `tools/aidev_config.py`, is the single reader of `.claude/ai-dev-system.json`: it finds the main checkout, loads and validates the file, applies environment overrides, compares against the shipped defaults and prints a status line. The guard hook imports it; the bot scripts and the orchestrator call its CLI. Policy text (docs/05, AGENTS.md, the orchestrator skill) is edited to refer to config keys instead of the owner's names, and the check script pins the new wording.

**Tech Stack:** Python 3 standard library, bash, git config, `claude plugin validate`.

**Spec:** `docs/decisions/0005-feature-switches-and-portability.md` (with `0004-model-ladder.md` for the ladder switch).

## Global Constraints

- Risky tier throughout (hooks, AGENTS.md, policy). One implementer, Codex review, attended.
- Standard library only in Python; `python3 -I` everywhere a script is invoked.
- Fail closed: a missing, unreadable or wrong-version config means the guard is on and the bot refuses.
- The hook and the bot scripts read the config from the **main checkout** (parent of `git rev-parse --path-format=absolute --git-common-dir`), never from a worktree's branch.
- Bot identity values live in the user's git config under `aidev.bot.name` and `aidev.bot.tokenCommand`; never in a repo file.
- Environment overrides: `AI_DEV_SYSTEM_FEATURE_<NAME>=on|off` beats the file; `ORCHESTRATOR_GUARD=off` is an alias for the guard switch.
- Defaults file `config/ai-dev-system.defaults.json` is the only place model ids are authored; docs refer to it.
- No secrets, no owner hosts or bot names in shared policy text; the owner's values go in `config/examples/orca-solvela.json` and docs/12.
- Repo verification list applies: `git diff --check`, `bash -n`, `python3 -m py_compile`, the guard test, the ladder check script, `claude plugin validate .`, links resolve.
- Conventional commits, no `Co-Authored-By`.

## Tooling

| Part of the job | Tool (exact id) | Kind | Used at | Why this one |
|---|---|---|---|---|
| Config reader, status line, validation | hand-written `tools/aidev_config.py` | library | runtime | one reader for hook, bot scripts and orchestrator |
| Guard hook config read | `tools/hooks/orchestrator-guard.py` importing `aidev_config` | library | runtime | existing hook, existing fail-closed style |
| Hook tests | `tools/hooks/test-orchestrator-guard.sh` (extend) | script | verify | repo's existing harness and `run` helper |
| Bot script tests | hand-written `tools/bot/test-bot-scripts.sh` | script | verify | same style; fake `gh` and `GIT_CONFIG_GLOBAL` in a temp HOME |
| harness-enable tests | hand-written `tools/test-harness-enable.sh` | script | verify | stubbed `ORCA_CLI_COMMAND`, temp repo |
| Wording pins | `tools/check-ladder-docs.sh` (extend) | script | verify | existing pin mechanism |
| Plugin validity | `claude plugin validate .` | CLI | verify | repo verification list |
| Implement each task | `docs-engineer` as an Orca worker (or Native per owner choice) | agent | build | plugin's docs/tooling implementer role |
| Independent review | Codex worker, risky tier | agent | verify | required for policy and hooks |
| Writing the policy edits | hand-written | none | build | prose |

**Checked and rejected:** `superpowers:test-driven-development` as a row (it governs every task; listed in Global Constraints instead). A JSON Schema library for validation (not standard library; a hand-rolled check of six keys is enough). Splitting into several plugins (spec option 2).

**Gaps to build first:** none. The reader module is Task 1 because every later task consumes it, not because a tool is missing.

## Review Focus

1. A repo with no config file: guard on, ladder on, bot refuses, metering none. Pinned by hook tests (Task 2) and bot tests (Task 3) run against an empty temp repo.
2. A worker flips `orchestrator_guard` to false in its branch copy: the hook must still deny a write outside the worktree, because it reads the main checkout's copy. Pinned by a Task 2 test with main on and worktree off.
3. `install-bot-identity.sh` re-run on a machine that already has the old include: idempotent, and the two new keys land in the global config, not only in the worktree include. Pinned by Task 3's double run and a `git config --global --get` from a non-worktree cwd.
4. harness-enable re-run on an already-harnessed repo: config not overwritten, settings and CLAUDE.md untouched, exit 0. Pinned by Task 4's second run and a checksum compare.
5. A config whose `models` differ from the defaults: the status line must list the deviation, not hide it. Pinned by a Task 1 test with rung 2 set to the smallest model.

---

### Task 1: The config reader module and the shipped config files

**Files:**
- Create: `config/ai-dev-system.defaults.json` (exact JSON from spec section 1, `build_map` false, `gateway.kind` `none`, `platform.hosts` `{}`)
- Create: `config/examples/orca-solvela.json` (defaults plus: `metering` `solvela`, `bot_identity` true, `gateway.kind` `solvela`, `base_url` `https://api.solvela.ai`, `team_key_env` `SOLVELA_KEY_IMPLEMENTER` / `SOLVELA_KEY_REVIEWER` / `SOLVELA_KEY_RESEARCH`, `platform.hosts["home-office-omarchy"]` with `deepseek_agent` `dsh-tui` and `dsh_profiles` `{"0": "", "1": ""}`)
- Create: `tools/aidev_config.py`
- Create: `tools/test-aidev-config.sh`

**Interfaces:**
- Produces, importable with `sys.path.insert(0, <tools dir>)`:
  - `main_checkout(cwd: str) -> str | None`: parent of the absolute git common dir; `None` outside a repo.
  - `load_config(root: str) -> dict | None`: parses `<root>/.claude/ai-dev-system.json`; `None` when missing, unparseable, not an object, or `version != 1`.
  - `feature(cfg: dict | None, name: str, env: Mapping = os.environ) -> bool | str`: env `AI_DEV_SYSTEM_FEATURE_<NAME>` (`on`/`off`, case-insensitive) wins; `ORCHESTRATOR_GUARD=off` counts as off for `orchestrator_guard`; then `cfg["features"][name]`; then the default from `defaults()`.
  - `defaults() -> dict`: the shipped defaults file, located relative to the module.
  - `deviations(cfg: dict, base: dict) -> list[str]`: dotted keys under `models` whose value differs.
  - `status_line(cfg: dict | None, cwd: str) -> str`: one line, exact shape `ai-dev-system: config=<path|none> guard=on|off ladder=on|off bot=on|off metering=<kind> build_map=on|off platform=<kind> hosts=<comma list|none> gateway=<kind> models=<defaults|deviates: k1,k2>`.
- CLI (`python3 -I tools/aidev_config.py ...`): `get <dotted.key>` prints the value (`true`/`false`, strings bare, objects as JSON) and exits 1 if absent; `status` prints `status_line` for the cwd; `check <path>` validates a file and exits 1 with one line per problem.

- [ ] **Step 1: Write the failing tests**

`tools/test-aidev-config.sh`, same style as the guard test (temp repo `$M`, worktree `$W`, `fail` counter, `ok`/`FAIL` lines). Cases:

```text
status in repo without config         → line contains "config=none guard=on ladder=on bot=off metering=none"
get features.model_ladder, no config  → prints "true" (default), exit 0
write defaults file to $M/.claude/… ; status from $W → "config=$M/.claude/ai-dev-system.json" (main checkout, not $W)
check config/ai-dev-system.defaults.json → exit 0, no output
check file with "version": 2          → exit 1, output contains "version"
check file missing "features"         → exit 1, output contains "features"
AI_DEV_SYSTEM_FEATURE_MODEL_LADDER=off get features.model_ladder → "false"
ORCHESTRATOR_GUARD=off get features.orchestrator_guard → "false"
config with models.research[2]="claude-haiku-5-5" ; status → contains "models=deviates: models.research"
check config/examples/orca-solvela.json → exit 0
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tools/test-aidev-config.sh; echo exit=$?`
Expected: every case `FAIL` (module missing), `exit=1`.

- [ ] **Step 3: Create the two JSON files and implement `tools/aidev_config.py` with the interfaces above**

Validation in `check`: `version == 1`; `features` object with the five keys, booleans except `metering` in `{none, solvela, openai-compatible}`; `platform.kind` string; `platform.hosts` object; `gateway.kind` in the same set; `models.research` and `models.claude_implementer` lists of three strings; `models.codex_reviewer.model` string and `.effort` list of three.

- [ ] **Step 4: Run to verify it passes**

Run: `bash tools/test-aidev-config.sh && python3 -m py_compile tools/aidev_config.py && bash -n tools/test-aidev-config.sh && git diff --check && echo OK`
Expected: all `ok`, then `OK`.

- [ ] **Step 5: Commit**

```bash
git add config tools/aidev_config.py tools/test-aidev-config.sh
git commit -m "feat: add the ai-dev-system config reader, defaults and example config"
```

### Task 2: The guard hook honours the switch and reads the main checkout's copy

**Files:**
- Modify: `tools/hooks/orchestrator-guard.py` (`main()` at the end; module docstring paragraph on `ORCHESTRATOR_GUARD`)
- Modify: `tools/hooks/test-orchestrator-guard.sh` (new cases before the plugin-command case)
- Modify: `AGENTS.md:29-39` (verification list: add `bash tools/test-aidev-config.sh`, `bash tools/bot/test-bot-scripts.sh`, `bash tools/test-harness-enable.sh`)

**Interfaces:**
- Consumes: `main_checkout`, `load_config`, `feature` from Task 1.
- Produces: stderr line `orchestrator-guard: off by config (<path>)` with exit 0 when the switch is off.

- [ ] **Step 1: Write the failing tests** (append to the guard test, using its `run` helper; `cfg()` helper writes `$1/.claude/ai-dev-system.json` from the defaults with `orchestrator_guard` set to `$2`)

```text
cfg "$M" false ; run 0 "$M" Write '{"file_path":"x.md","content":"hi"}'          # off by config allows
cfg "$M" true  ; cfg "$W" false ; run 2 "$W" Write "{\"file_path\":\"$M/x.md\",…}"  # worktree copy ignored
printf 'not json' > "$M/.claude/ai-dev-system.json" ; run 2 "$M" Write …           # malformed → guard on
cfg "$M" false then sed version 1→2 ; run 2 "$M" Write …                            # wrong version → guard on
cfg "$M" false ; AI_DEV_SYSTEM_FEATURE_ORCHESTRATOR_GUARD=on run 2 "$M" Write …     # env beats file
rm config ; AI_DEV_SYSTEM_FEATURE_ORCHESTRATOR_GUARD=off run 0 "$M" Write …         # env alone turns off
```

The `run` helper currently forces `ORCHESTRATOR_GUARD=`; add an optional env prefix argument or a second helper `runenv VAR=val …` so the two env cases can be expressed.

- [ ] **Step 2: Run to verify the new cases fail**

Run: `bash tools/hooks/test-orchestrator-guard.sh | grep -c FAIL`
Expected: `4` (the two "guard on" cases already pass by accident; the off-by-config, worktree-copy-ignored is a pass too; the FAIL count is the cases that need the feature: off-by-config allow, env-beats-file, env-alone-off, plus the worktree case if the implementation reads cwd instead of main). Record the exact number observed.

- [ ] **Step 3: Implement**

In `main()`: parse payload first; compute `cwd`; `root = main_checkout(cwd)`; `cfg = load_config(root) if root else None`; `if feature(cfg, "orchestrator_guard") is False: sys.stderr.write("orchestrator-guard: off by config (...)\n"); return 0`. Keep the `ORCHESTRATOR_GUARD=off` fast path by routing it through `feature` (alias handled there). Import with `sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))` then `import aidev_config`. Update the docstring paragraph to name the config switch and the env variable.

- [ ] **Step 4: Run to verify it passes**

Run: `bash tools/hooks/test-orchestrator-guard.sh | tail -3; bash tools/hooks/test-orchestrator-guard.sh | grep -c FAIL; python3 -m py_compile tools/hooks/orchestrator-guard.py && git diff --check && echo OK`
Expected: the plugin-command and override lines `ok`, `0`, `OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/hooks/orchestrator-guard.py tools/hooks/test-orchestrator-guard.sh AGENTS.md
git commit -m "feat(guard): honour features.orchestrator_guard from the main checkout's config"
```

### Task 3: Bot scripts read git config and the repo switch

**Files:**
- Modify: `tools/bot/gh-bot`, `tools/bot/git-credential-op-bot`, `tools/bot/install-bot-identity.sh`
- Create: `tools/bot/test-bot-scripts.sh`

**Interfaces:**
- Consumes: `python3 -I <tools>/aidev_config.py get features.bot_identity` (Task 1), located as `$(dirname "$(readlink -f "$0")")/../aidev_config.py` so the `~/.local/bin` symlinks resolve.
- Produces: git config keys `aidev.bot.name`, `aidev.bot.email`, `aidev.bot.tokenCommand` in the user's global config, written by `install-bot-identity.sh --name <n> --email <e> --token-command <cmd>`; `orca-bot.gitconfig` takes `user.name`/`user.email` from the same flags.

- [ ] **Step 1: Write the failing tests**

`tools/bot/test-bot-scripts.sh`: temp `HOME`, `XDG_CONFIG_HOME=$HOME/.config`, `GIT_CONFIG_GLOBAL=$HOME/.gitconfig`, fake `gh` on `PATH` that prints `$GH_TOKEN`, temp repo `$R` with the defaults config and `bot_identity` toggled per case. Cases:

```text
no keys, switch true   : gh-bot x        → exit 1, stderr contains "aidev.bot.name"
install --name B --email e@x --token-command "echo tok-1" ; second run → both exit 0, "already present" on second, `git config --global --get aidev.bot.tokenCommand` = "echo tok-1"
keys set, switch true  : gh-bot x        → stdout "tok-1"
keys set, switch true  : printf 'host=github.com\n\n' | git-credential-op-bot get → "username=B" and "password=tok-1"
keys set, switch false : gh-bot x        → exit 1, stderr contains "bot_identity"
keys set, outside repo : gh-bot x        → exit 1, stderr contains "repository"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tools/bot/test-bot-scripts.sh; echo exit=$?`
Expected: the install flags are unknown and the token read fails: at least four `FAIL`, `exit=1`.

- [ ] **Step 3: Implement**

Both token scripts: a shared prologue (duplicated, 12 lines; two files, no library) that resolves `tools/`, runs `aidev_config.py get features.bot_identity` from `$PWD` and refuses unless it prints `true`; reads `name=$(git config --get aidev.bot.name)` and `cmd=$(git config --get aidev.bot.tokenCommand)`, refusing when either is empty; `token="$(bash -c "$cmd")"`. `install-bot-identity.sh`: parse the three flags (all required), write the `aidev.bot.*` keys with `git config --global`, template `orca-bot.gitconfig` from the flags, keep the includeIf block idempotent. Remove every literal `Solvela-bot`, `1Password` and `op://` from the three scripts; the owner's values go to docs/12 in Task 6.

- [ ] **Step 4: Run to verify it passes**

Run: `bash tools/bot/test-bot-scripts.sh && bash -n tools/bot/gh-bot tools/bot/git-credential-op-bot tools/bot/install-bot-identity.sh && grep -c -i -E 'solvela-bot|1password|op://' tools/bot/gh-bot tools/bot/git-credential-op-bot tools/bot/install-bot-identity.sh; git diff --check && echo OK`
Expected: all `ok`; three `:0` counts; `OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/bot
git commit -m "feat(bot): take the bot identity from git config and the repo's bot_identity switch"
```

### Task 4: harness-enable moves into the plugin and writes the config

**Files:**
- Create: `tools/harness-enable.sh` (from `/home/sky64/.claude/skills/harness-enable/enable.sh`, plus the config step)
- Create: `tools/test-harness-enable.sh`

**Interfaces:**
- Consumes: `config/ai-dev-system.defaults.json`, `aidev_config.py check` (Task 1).
- Produces: `<repo>/.claude/ai-dev-system.json`; flag `--config <path>`; output lines `config: written from defaults`, `config: written from <path>`, `config: already present, left unchanged`.

- [ ] **Step 1: Write the failing tests**

`tools/test-harness-enable.sh`: temp repo with one commit; `ORCA_CLI_COMMAND` pointing at a stub script that prints `{}` and exits 0 (so the Orca steps succeed without Orca). Cases:

```text
first run                      → exit 0; .claude/ai-dev-system.json byte-equal to config/ai-dev-system.defaults.json; settings.json enables the plugin; CLAUDE.md has the orchestrator line; HEAD commit message "chore: enable ai-dev-system plugin"; output has "config: written from defaults"
second run                     → exit 0; output has "config: already present"; sha256 of the three files unchanged; no new commit
--config config/examples/orca-solvela.json on a fresh repo → config byte-equal to the example
--config pointing at an invalid file → exit 1 before writing anything; output names "check"
--no-commit                    → files staged, no commit
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tools/test-harness-enable.sh; echo exit=$?`
Expected: `tools/harness-enable.sh` missing, every case `FAIL`, `exit=1`.

- [ ] **Step 3: Implement**

Copy the script in; add step "1b. config" between the settings merge and the CLAUDE.md line: if `--config` given, run `aidev_config.py check <path>` and copy; else copy the defaults; skip with the "already present" line when the file exists; add it to the `git add` list. Resolve the plugin root as the script's own `../`.

- [ ] **Step 4: Run to verify it passes**

Run: `bash tools/test-harness-enable.sh && bash -n tools/harness-enable.sh && git diff --check && echo OK`
Expected: all `ok`, `OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/harness-enable.sh tools/test-harness-enable.sh
git commit -m "feat: ship harness-enable in the plugin and write the per-repo config"
```

### Task 5: The orchestrator reads the config and the ladder gets its switch

**Files:**
- Modify: `skills/orchestrator/SKILL.md` (new `## Configuration` section before `## Delegation`; edits in `## Rungs and models`)
- Modify: `tools/check-ladder-docs.sh` (pins listed below)

**Interfaces:**
- Consumes: `python3 -I "${CLAUDE_PLUGIN_ROOT}/tools/aidev_config.py" status` (Task 1).

- [ ] **Step 1: Add the pins and watch them fail**

Pins for `skills/orchestrator/SKILL.md`: `## Configuration`; `aidev_config.py" status`; `AI_DEV_SYSTEM_FEATURE_`; `model_ladder` ; `When model_ladder is off`; `When metering is none`; `When bot_identity is off`; `## Platform seam`; `create an isolated workspace`; `hand a diff to a reviewer`; `platform.hosts`; `gateway.kind`.
Run: `bash tools/check-ladder-docs.sh | grep -c '^skills/orchestrator'`
Expected: `12`.

- [ ] **Step 2: Write `## Configuration`**

Bullets: run the status command first and paste its line as the first line of the session's first message; the switches and what each changes (`When model_ladder is off`: no `Rung:`/`Model:` lines, no `--model`/`--effort`, subagents inherit the session model, completion report omits rung fields, escalation still by tier; `When metering is none`: skip the attribution bullets and the gateway header; `When bot_identity is off`: never push or merge, report that a human must); env overrides; the config is read from the main checkout and is risky-tier to change.

Write `## Platform seam`: a five-row table, operation → Orca command: create an isolated workspace (`orca worktree create`), start an agent with a brief and a model (`orca orchestration worker-start --agent --model --effort`), wait for completion (`orca orchestration check --wait`), read its result (`orca orchestration worker-read` / the worker_done message), hand a diff to a reviewer (`worker-start --agent codex` with base and head). One sentence: another platform is another table; `platform.kind` names which one is in use.

Edit `## Rungs and models`: replace "where docs/12 records it" with "where `platform.hosts` has an entry for the current host (`${CLAUDE_PLUGIN_ROOT}/docs/12-orca-setup.md` is the owner's verification log)"; replace Solvela wording with "when `gateway.kind` is `solvela`"; model ids come from `models` in the config, defaults in `config/ai-dev-system.defaults.json`.

- [ ] **Step 3: Verify**

Run: `bash tools/check-ladder-docs.sh && claude plugin validate . | tail -1 && git diff --check && echo OK`
Expected: `ladder docs OK`, `Validation passed`, `OK`.

- [ ] **Step 4: Commit**

```bash
git add skills/orchestrator/SKILL.md tools/check-ladder-docs.sh
git commit -m "feat(orchestrator): read the config at session start; ladder, metering and bot switches; platform seam"
```

### Task 6: Portability edits to policy, README and the setup log

**Files:**
- Modify: `docs/05-delegation.md` (lines 21, 47, 54-60, 142, 155-162)
- Modify: `AGENTS.md` (lines 45 and 47)
- Modify: `README.md` (after line 7: "Using this on your own setup"; line 19 bot sentence)
- Modify: `docs/12-orca-setup.md` (State table: a row "Bot identity values" with the owner's bot name and 1Password item; Model ladder routing intro: "this host's `platform.hosts` entry")
- Modify: `tools/check-ladder-docs.sh` (pins below)

- [ ] **Step 1: Add the pins and watch them fail**

docs/05: `.claude/ai-dev-system.json` (in the risky sentence); `config/ai-dev-system.defaults.json`; `platform.hosts`; `gateway.kind`; `the configured gateway`. AGENTS.md: `features.bot_identity`; `install-bot-identity.sh`. README: `## Using this on your own setup`; `tools/harness-enable.sh`; `config/examples/orca-solvela.json`. docs/12: `aidev.bot.name`.
Run: `bash tools/check-ladder-docs.sh | grep -c -E '^(docs/05|AGENTS|README|docs/12)'`
Expected: `11`.

- [ ] **Step 2: Edit**

docs/05:21 add `.claude/ai-dev-system.json` to the risky list. docs/05:47 "ids are the defaults in `config/ai-dev-system.defaults.json`; a repo's `models` block may override them and the orchestrator reports deviations". docs/05:57-58 "where `platform.hosts` has an entry for the host". docs/05:59 "When `gateway.kind` is `solvela`, calls name the model with a Solvela alias…". docs/05:142 "A provider or gateway budget error". docs/05:155-162 "the configured gateway (`gateway.kind`); Solvela is the owner's and the reference implementation" and each "Solvela" in the bullets becomes "the gateway" except the one naming it. AGENTS.md:45 and :47 per spec section 3. README: new section with four steps (clone or install the marketplace; `bash <plugin>/tools/harness-enable.sh /path/to/repo [--config …]`; edit `.claude/ai-dev-system.json`; `install-bot-identity.sh --name … --email … --token-command …` only if you want a bot); line 19 "an agent identity you configure". docs/12 rows.

- [ ] **Step 3: Verify**

Run: `bash tools/check-ladder-docs.sh && grep -n -i -E 'solvela-bot|1password' AGENTS.md docs/05-delegation.md skills/orchestrator/SKILL.md | grep -c . ; git diff --check && echo OK`
Expected: `ladder docs OK`, `0`, `OK`. Every new relative link resolves.

- [ ] **Step 4: Commit**

```bash
git add docs/05-delegation.md AGENTS.md README.md docs/12-orca-setup.md tools/check-ladder-docs.sh
git commit -m "docs: move install-specific values into config; add the setup guide for other installs"
```

### Task 7: Version, links and the full suite

**Files:**
- Modify: `.claude-plugin/plugin.json` (`"version": "0.4.0"`)
- Modify: `docs/decisions/0005-feature-switches-and-portability.md:3` (link this plan)
- Modify: `AGENTS.md` verification list if any test script was not added in Task 2

- [ ] **Step 1: Edits**, then **Step 2: Run everything**

Run: `bash tools/test-aidev-config.sh && bash tools/hooks/test-orchestrator-guard.sh | grep -c FAIL; bash tools/bot/test-bot-scripts.sh && bash tools/test-harness-enable.sh && bash tools/check-ladder-docs.sh && claude plugin validate . | tail -1 && git diff --check && echo ALL-OK`
Expected: `0` FAILs, every suite `ok`, `Validation passed`, `ALL-OK`.

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json docs/decisions/0005-feature-switches-and-portability.md AGENTS.md docs/superpowers/plans/2026-11-17-feature-switches.md
git commit -m "chore: bump plugin to 0.4.0; link the feature-switches plan"
```

## Owner items

| Item | Who issues it | Blocks |
|---|---|---|
| Per repo at re-enable: pass `--config config/examples/orca-solvela.json` or keep defaults; set `bot_identity` per repo | owner | nothing in this plan; rollout |
| Re-run `tools/bot/install-bot-identity.sh --name Solvela-bot --email <noreply address> --token-command "op read 'op://Agents/Solvela-bot GitHub token/credential'"` on each machine that pushes as the bot | owner | bot pushes after merge |
| Repoint `~/.claude/skills/harness-enable/enable.sh` to `exec bash ~/.local/share/ai-dev-system-main/tools/harness-enable.sh "$@"` after merge | owner or a follow-up task | the user-level skill |
