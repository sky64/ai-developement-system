#!/usr/bin/env bash
# Unit test for tools/crew64-enable.sh. Runs against throwaway repositories
# with Orca stubbed through ORCA_CLI_COMMAND. Exit 0 = all pass.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENABLE="$ROOT/tools/crew64-enable.sh"
DEFAULTS="$ROOT/config/crew64.defaults.json"
EXAMPLE="$ROOT/config/examples/orca-solvela.json"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
printf '#!/usr/bin/env bash\necho "{}"\n' > "$TMP/orca-stub"; chmod +x "$TMP/orca-stub"
export ORCA_CLI_COMMAND="$TMP/orca-stub"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"; : > "$GIT_CONFIG_GLOBAL"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@x GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@x
mkdir -p "$TMP/home-default"; export HOME="$TMP/home-default"   # the wrapper install never touches the real home
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
newrepo() { git init -q "$1" && git -C "$1" commit -q --allow-empty -m init; }
sums() { (cd "$1" && sha256sum .claude/crew64.json .claude/settings.json CLAUDE.md 2>/dev/null); }

# 1. first run
R="$TMP/r1"; newrepo "$R"
out="$(bash "$ENABLE" "$R" 2>&1)"; rc=$?
[ "$rc" = 0 ] && case "$out" in *"config: written from defaults"*) true;; *) false;; esac && ok "first run exits 0 and writes config from defaults" || bad "first run: rc=$rc out=$out"
cmp -s "$R/.claude/crew64.json" "$DEFAULTS" && ok "config equals the defaults file" || bad "config differs from defaults"
grep -q '"crew64@crew64": true' "$R/.claude/settings.json" && ok "settings.json enables the plugin" || bad "settings.json"
grep -q 'crew64:orchestrator' "$R/CLAUDE.md" && ok "CLAUDE.md has the orchestrator line" || bad "CLAUDE.md"
[ "$(git -C "$R" log -1 --format=%s)" = "chore: enable crew64 plugin" ] && ok "committed" || bad "commit message: $(git -C "$R" log -1 --format=%s)"
git -C "$R" ls-files --error-unmatch .claude/crew64.json >/dev/null 2>&1 && ok "config file is tracked" || bad "config not tracked"
[ "$(git config --global --get-all crew64.trustedRoot | grep -c -x "$R")" = 1 ] && ok "repo registered once as a trusted root in the global git config" || bad "trustedRoot registration: $(git config --global --get-all crew64.trustedRoot)"

# 2. second run: idempotent
before="$(sums "$R")"; n1="$(git -C "$R" rev-list --count HEAD)"
out="$(bash "$ENABLE" "$R" 2>&1)"; rc=$?
after="$(sums "$R")"; n2="$(git -C "$R" rev-list --count HEAD)"
[ "$rc" = 0 ] && case "$out" in *"config: already present"*) true;; *) false;; esac && ok "second run says already present" || bad "second run: rc=$rc out=$out"
[ "$before" = "$after" ] && [ "$n1" = "$n2" ] && ok "second run changes nothing and adds no commit" || bad "second run changed files or committed"
[ "$(git config --global --get-all crew64.trustedRoot | grep -c -x "$R")" = 1 ] && ok "second run does not duplicate the trusted root" || bad "trustedRoot duplicated"

# 3. --config copies a prepared file
R2="$TMP/r2"; newrepo "$R2"
out="$(bash "$ENABLE" "$R2" --config "$EXAMPLE" 2>&1)"; rc=$?
[ "$rc" = 0 ] && cmp -s "$R2/.claude/crew64.json" "$EXAMPLE" && case "$out" in *"config: written from $EXAMPLE"*) true;; *) false;; esac && ok "--config copies the example" || bad "--config: rc=$rc out=$out"

# 4. --config with an invalid file stops before writing
R3="$TMP/r3"; newrepo "$R3"; printf '{"version": 2}' > "$TMP/bad.json"
out="$(bash "$ENABLE" "$R3" --config "$TMP/bad.json" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ ! -e "$R3/.claude/crew64.json" ] && [ ! -e "$R3/.claude/settings.json" ] && case "$out" in *check*) true;; *) false;; esac && ok "invalid --config exits 1 before writing" || bad "invalid config: rc=$rc out=$out"

# 5b. a hand-formatted settings.json that already enables the plugin is left byte-identical
R5="$TMP/r5"; newrepo "$R5"; mkdir -p "$R5/.claude"
printf '{\n    "enabledPlugins": {\n        "crew64@crew64": true\n    },\n    "extraKnownMarketplaces": {\n        "crew64": {\n            "source": {\n                "source": "github",\n                "repo": "sky64/crew64"\n            }\n        }\n    }\n}\n' > "$R5/.claude/settings.json"
s_before="$(sha256sum "$R5/.claude/settings.json")"
bash "$ENABLE" "$R5" >/dev/null 2>&1
[ "$(sha256sum "$R5/.claude/settings.json")" = "$s_before" ] && ok "settings.json untouched when nothing changes" || bad "settings.json reformatted on re-run"

# 5c. unrelated staged changes are not swept into the enable commit
R6="$TMP/r6"; newrepo "$R6"; echo x > "$R6/unrelated.txt"; git -C "$R6" add unrelated.txt
bash "$ENABLE" "$R6" >/dev/null 2>&1
git -C "$R6" diff --cached --name-only | grep -q '^unrelated.txt$' && ! git -C "$R6" show --name-only --format= HEAD | grep -q unrelated.txt && ok "enable commit leaves unrelated staged files staged" || bad "unrelated staged file was committed or lost"

# 5d. a rejected commit is a failure, not a silent exit 0
R7="$TMP/r7"; newrepo "$R7"; mkdir -p "$R7/.git/hooks"; printf '#!/bin/sh\nexit 1\n' > "$R7/.git/hooks/pre-commit"; chmod +x "$R7/.git/hooks/pre-commit"
out="$(bash "$ENABLE" "$R7" 2>&1)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *commit*fail*|*"commit failed"*) true;; *) false;; esac && ok "rejected commit → exit 1 with a commit failure message" || bad "rejected commit: rc=$rc out=$(echo "$out" | tail -2)"

# 5e. a failed Orca registration is a failure, not a silent exit 0
R8="$TMP/r8"; newrepo "$R8"
printf '#!/usr/bin/env bash\ncase "$*" in *"repo show"*) exit 7;; *"repo add"*) exit 7;; esac\necho "{}"\n' > "$TMP/orca-fail"; chmod +x "$TMP/orca-fail"
out="$(ORCA_CLI_COMMAND="$TMP/orca-fail" bash "$ENABLE" "$R8" 2>&1)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *orca*) true;; *) false;; esac && ok "failed Orca registration → exit 1 naming orca" || bad "orca failure: rc=$rc out=$(echo "$out" | tail -2)"

# 5f. only a main checkout may be registered as a trusted root: a linked
# worktree is refused, and a subdirectory registers the real toplevel.
R9="$TMP/r9"; newrepo "$R9"; git -C "$R9" worktree add -q "$TMP/r9-wt" -b wt
out="$(bash "$ENABLE" "$TMP/r9-wt" 2>&1)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"main checkout"*) true;; *) false;; esac && ! git config --global --get-all crew64.trustedRoot | grep -qxF "$TMP/r9-wt" && ok "a linked worktree is refused and not registered" || bad "worktree enable: rc=$rc out=$(echo "$out" | tail -1)"
mkdir -p "$R9/sub/dir"
bash "$ENABLE" "$R9/sub/dir" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && git config --global --get-all crew64.trustedRoot | grep -qxF "$(realpath "$R9")" && ! git config --global --get-all crew64.trustedRoot | grep -qxF "$R9/sub/dir" && [ -e "$R9/.claude/crew64.json" ] && ok "a subdirectory registers and configures the toplevel" || bad "subdir enable: rc=$rc roots=$(git config --global --get-all crew64.trustedRoot | tr '\n' ' ')"

# 5g. decision 0006: a repo enabled under the old names migrates to crew64 names
R10="$TMP/r10"; newrepo "$R10"; mkdir -p "$R10/.claude"
cp "$DEFAULTS" "$R10/.claude/ai-dev-system.json"
printf '{\n  "extraKnownMarketplaces": {\n    "ai-dev-system": {\n      "source": {\n        "source": "github",\n        "repo": "sky64/ai-developement-system"\n      }\n    }\n  },\n  "enabledPlugins": {\n    "ai-dev-system@ai-dev-system": true\n  }\n}\n' > "$R10/.claude/settings.json"
git config --global --add aidev.trustedRoot "$(realpath "$R10")"
out="$(bash "$ENABLE" "$R10" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -e "$R10/.claude/crew64.json" ] && [ ! -e "$R10/.claude/ai-dev-system.json" ] && cmp -s "$R10/.claude/crew64.json" "$DEFAULTS" && ok "old config file is renamed to crew64.json with its content kept" || bad "config migration: rc=$rc ls=$(ls "$R10/.claude")"
grep -q '"crew64@crew64": true' "$R10/.claude/settings.json" && ! grep -q 'ai-dev-system' "$R10/.claude/settings.json" && ok "old plugin entry and marketplace are replaced in settings.json" || bad "settings migration: $(cat "$R10/.claude/settings.json" | tr -d ' \n')"
git config --global --get-all crew64.trustedRoot | grep -qxF "$(realpath "$R10")" && ! git config --global --get-all aidev.trustedRoot 2>/dev/null | grep -qxF "$(realpath "$R10")" && ok "trusted-root registration moves from aidev to crew64" || bad "trustedRoot migration: crew64=$(git config --global --get-all crew64.trustedRoot | tr '\n' ' ') aidev=$(git config --global --get-all aidev.trustedRoot 2>/dev/null | tr '\n' ' ')"
git -C "$R10" ls-files --error-unmatch .claude/crew64.json >/dev/null 2>&1 && ! git -C "$R10" ls-files --error-unmatch .claude/ai-dev-system.json >/dev/null 2>&1 && ok "migration is committed (old file untracked, new file tracked)" || bad "migration commit: $(git -C "$R10" ls-files .claude)"

# Codex review of PR 16: four migration defects.
# (a) an unrelated aidev.* key survives the trusted-root move; (c) a path with a regex character and a
# duplicate entry migrate exactly; (d) the legacy CLAUDE.md orchestrator line is replaced, not kept; (b) a
# TRACKED old config is removed from HEAD by the migration commit.
R11="$TMP/r11+plus"; newrepo "$R11"; mkdir -p "$R11/.claude"; cp "$DEFAULTS" "$R11/.claude/ai-dev-system.json"
git -C "$R11" add .claude/ai-dev-system.json && git -C "$R11" commit -q -m "old config tracked"
printf 'If you were started as the project orchestrator and were not assigned a specific implementer or reviewer role in your prompt, invoke the ai-dev-system:orchestrator skill at session start. A session whose prompt assigns it a worker role (implementer, reviewer) keeps that role and does not invoke the skill. The orchestrator does not write or commit.\n' > "$R11/CLAUDE.md"
git -C "$R11" add CLAUDE.md && git -C "$R11" commit -q -m "old orchestrator line"
git config --global aidev.customSetting keep-me
git config --global --add aidev.trustedRoot "$(realpath "$R11")"; git config --global --add aidev.trustedRoot "$(realpath "$R11")"   # duplicate on purpose
git config --global --add aidev.trustedRoot "$(realpath "$TMP")/r11plus"                                                            # the regex-collision sibling
out="$(bash "$ENABLE" "$R11" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(git config --global --get aidev.customSetting)" = "keep-me" ] && ok "unrelated aidev.* key survives the trusted-root move" || bad "aidev.customSetting lost (rc=$rc): $(git config --global --get aidev.customSetting)"
! git config --global --get-all aidev.trustedRoot | grep -qxF "$(realpath "$R11")" && git config --global --get-all aidev.trustedRoot | grep -qxF "$(realpath "$TMP")/r11plus" && [ "$(git config --global --get-all crew64.trustedRoot | grep -cxF "$(realpath "$R11")")" = 1 ] && ok "trusted root with + migrates exactly: duplicates gone, regex sibling untouched, one crew64 entry" || bad "trustedRoot exactness: aidev=$(git config --global --get-all aidev.trustedRoot | tr '\n' ' ') crew64=$(git config --global --get-all crew64.trustedRoot | grep -c "$(basename "$R11")")"
[ "$(grep -c 'orchestrator skill at session start' "$R11/CLAUDE.md")" = 1 ] && grep -q 'crew64:orchestrator' "$R11/CLAUDE.md" && ! grep -q 'ai-dev-system:orchestrator' "$R11/CLAUDE.md" && ok "legacy CLAUDE.md orchestrator line is replaced, not duplicated" || bad "CLAUDE.md migration: $(grep -c orchestrator "$R11/CLAUDE.md") lines; legacy=$(grep -c 'ai-dev-system:orchestrator' "$R11/CLAUDE.md")"
git -C "$R11" ls-tree --name-only HEAD .claude/ | grep -qx '.claude/crew64.json' && ! git -C "$R11" ls-tree --name-only HEAD .claude/ | grep -qx '.claude/ai-dev-system.json' && [ -z "$(git -C "$R11" status --porcelain)" ] && ok "tracked old config is removed from HEAD and the tree is clean" || bad "tracked migration: HEAD=$(git -C "$R11" ls-tree --name-only HEAD .claude/ | tr '\n' ' ') status=$(git -C "$R11" status --porcelain | tr '\n' ' ')"
bash "$ENABLE" "$R11" >/dev/null 2>&1
[ "$(grep -c 'orchestrator skill at session start' "$R11/CLAUDE.md")" = 1 ] && ok "rerun keeps a single orchestrator line" || bad "rerun duplicated the orchestrator line"
R12="$TMP/r12"; newrepo "$R12"
git config --global --unset-all aidev.trustedRoot 2>/dev/null || true; git config --global --add aidev.trustedRoot "$(realpath "$R12")"   # the only legacy root
bash "$ENABLE" "$R12" >/dev/null 2>&1
[ "$(git config --global --get aidev.customSetting)" = "keep-me" ] && [ -z "$(git config --global --get-all aidev.trustedRoot)" ] && ok "moving the only legacy root keeps unrelated aidev.* keys" || bad "only-root move: customSetting=$(git config --global --get aidev.customSetting) aidev.trustedRoot=$(git config --global --get-all aidev.trustedRoot | tr '\n' ' ')"

# Codex PR 16 cycle 2: a migration resumed after --no-commit must still commit the legacy deletion;
# a legacy instruction already followed by the crew64 one is removed, not turned into a duplicate.
R13="$TMP/r13"; newrepo "$R13"; mkdir -p "$R13/.claude"; cp "$DEFAULTS" "$R13/.claude/ai-dev-system.json"
git -C "$R13" add .claude/ai-dev-system.json && git -C "$R13" commit -q -m "old config tracked"
printf 'intro line\nIf you were started as the project orchestrator and were not assigned a specific implementer or reviewer role in your prompt, invoke the ai-dev-system:orchestrator skill at session start. A session whose prompt assigns it a worker role (implementer, reviewer) keeps that role and does not invoke the skill. The orchestrator does not write or commit.\nIf you were started as the project orchestrator and were not assigned a specific implementer or reviewer role in your prompt, invoke the crew64:orchestrator skill at session start. A session whose prompt assigns it a worker role (implementer, reviewer) keeps that role and does not invoke the skill. The orchestrator does not write or commit.\n' > "$R13/CLAUDE.md"
git -C "$R13" add CLAUDE.md && git -C "$R13" commit -q -m "both lines"
bash "$ENABLE" "$R13" --no-commit >/dev/null 2>&1
bash "$ENABLE" "$R13" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ! git -C "$R13" ls-tree --name-only HEAD .claude/ | grep -qx '.claude/ai-dev-system.json' && git -C "$R13" ls-tree --name-only HEAD .claude/ | grep -qx '.claude/crew64.json' && [ -z "$(git -C "$R13" status --porcelain)" ] && ok "migration resumed after --no-commit commits the legacy deletion" || bad "resumed migration: rc=$rc HEAD=$(git -C "$R13" ls-tree --name-only HEAD .claude/ | tr '\n' ' ') status=$(git -C "$R13" status --porcelain | tr '\n' ' ')"
[ "$(grep -c 'orchestrator skill at session start' "$R13/CLAUDE.md")" = 1 ] && grep -q 'crew64:orchestrator' "$R13/CLAUDE.md" && grep -q '^intro line$' "$R13/CLAUDE.md" && ok "legacy line next to an existing crew64 line is removed, not duplicated" || bad "dedupe: $(grep -c 'orchestrator skill' "$R13/CLAUDE.md") orchestrator lines"

# A repo that gitignores .claude (common in public repos) must still enable: the ignored files are
# written and reported as left untracked, the trackable edits (CLAUDE.md) are committed, exit 0.
R14="$TMP/r14"; newrepo "$R14"; printf '.claude/\n' > "$R14/.gitignore"; git -C "$R14" add .gitignore && git -C "$R14" commit -q -m ignore
out="$(bash "$ENABLE" "$R14" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -e "$R14/.claude/crew64.json" ] && [ -e "$R14/.claude/settings.json" ] && case "$out" in *"left untracked"*) true;; *) false;; esac && ok "ignored .claude: files written, reported as left untracked, exit 0" || bad "ignored .claude: rc=$rc out=$(echo "$out" | tail -2 | tr '\n' ' ')"
git -C "$R14" ls-files --error-unmatch CLAUDE.md >/dev/null 2>&1 && [ "$(git -C "$R14" log -1 --format=%s)" = "chore: enable crew64 plugin" ] && [ -z "$(git -C "$R14" status --porcelain)" ] && ok "ignored .claude: CLAUDE.md committed and the tree is clean" || bad "ignored .claude commit: last=$(git -C "$R14" log -1 --format=%s) status=$(git -C "$R14" status --porcelain | tr '\n' ' ')"
git config --global --get-all crew64.trustedRoot | grep -qxF "$(realpath "$R14")" && ok "ignored .claude: repo still registered as a trusted root" || bad "ignored .claude: not registered"

# Codex PR 18: files already TRACKED inside an ignored .claude/ must still be staged and committed,
# including a tracked legacy config renamed inside that ignored directory, with and without --no-commit.
R15="$TMP/r15"; newrepo "$R15"; mkdir -p "$R15/.claude"
printf '{\n  "permissions": {}\n}\n' > "$R15/.claude/settings.json"; git -C "$R15" add -f .claude/settings.json && git -C "$R15" commit -q -m "tracked settings"
printf '.claude/\n' > "$R15/.gitignore"; git -C "$R15" add .gitignore && git -C "$R15" commit -q -m ignore
out="$(bash "$ENABLE" "$R15" 2>&1)"; rc=$?
[ "$rc" = 0 ] && grep -q '"crew64@crew64": true' "$R15/.claude/settings.json" && [ "$(git -C "$R15" log -1 --format=%s)" = "chore: enable crew64 plugin" ] && git -C "$R15" show --name-only --format= HEAD | grep -qx '.claude/settings.json' && ok "tracked settings.json inside ignored .claude/ is staged and committed" || bad "tracked-in-ignored: rc=$rc last=$(git -C "$R15" log -1 --format=%s) out=$(echo "$out" | tail -1)"
R16="$TMP/r16"; newrepo "$R16"; mkdir -p "$R16/.claude"; cp "$DEFAULTS" "$R16/.claude/ai-dev-system.json"
git -C "$R16" add -f .claude/ai-dev-system.json && git -C "$R16" commit -q -m "old config tracked"
printf '.claude/\n' > "$R16/.gitignore"; git -C "$R16" add .gitignore && git -C "$R16" commit -q -m ignore
bash "$ENABLE" "$R16" --no-commit >/dev/null 2>&1; rc1=$?
bash "$ENABLE" "$R16" >/dev/null 2>&1; rc2=$?
[ "$rc1" = 0 ] && [ "$rc2" = 0 ] && git -C "$R16" ls-tree --name-only HEAD .claude/ | grep -qx '.claude/crew64.json' && ! git -C "$R16" ls-tree --name-only HEAD .claude/ | grep -qx '.claude/ai-dev-system.json' && [ -z "$(git -C "$R16" status --porcelain)" ] && ok "tracked legacy config inside ignored .claude/ is renamed and committed across --no-commit and resume" || bad "legacy-in-ignored: rc1=$rc1 rc2=$rc2 HEAD=$(git -C "$R16" ls-tree --name-only HEAD .claude/ | tr '\n' ' ') status=$(git -C "$R16" status --porcelain | tr '\n' ' ')"

# 5h. CLAUDE.md is a symlink to AGENTS.md (new-repo convention): the orchestrator
# line lands in AGENTS.md and that file is in the enable commit; the tree is clean.
R20="$TMP/r20"; newrepo "$R20"; printf '# Rules\n' > "$R20/AGENTS.md"; ln -s AGENTS.md "$R20/CLAUDE.md"
git -C "$R20" add AGENTS.md CLAUDE.md && git -C "$R20" commit -q -m "rules + symlink"
out="$(bash "$ENABLE" "$R20" 2>&1)"; rc=$?
[ "$rc" = 0 ] && grep -q 'crew64:orchestrator' "$R20/AGENTS.md" && [ -L "$R20/CLAUDE.md" ] && [ -z "$(git -C "$R20" status --porcelain)" ] && git -C "$R20" show --stat HEAD | grep -q 'AGENTS.md' && ok "symlinked CLAUDE.md: AGENTS.md carries the line and is committed" || bad "symlink: rc=$rc status=$(git -C "$R20" status --porcelain | tr '\n' ' ') out=$out"
# a symlink whose target is outside the repo is reported, not fatal
R21="$TMP/r21"; newrepo "$R21"; printf 'x\n' > "$TMP/outside-rules.md"; ln -s "$TMP/outside-rules.md" "$R21/CLAUDE.md"; git -C "$R21" add CLAUDE.md && git -C "$R21" commit -q -m link
out="$(bash "$ENABLE" "$R21" 2>&1)"; rc=$?
[ "$rc" = 0 ] && case "$out" in *"outside the repository"*) true;; *) false;; esac && ok "symlink outside the repo is reported and the run succeeds" || bad "outside symlink: rc=$rc out=$out"

# 5i. the user-level harness-enable wrapper is installed, refreshed and left alone when current
H="$TMP/home"; mkdir -p "$H"; R22="$TMP/r22"; newrepo "$R22"
out="$(HOME="$H" bash "$ENABLE" "$R22" 2>&1)"; rc=$?
[ "$rc" = 0 ] && case "$out" in *"skill: installed"*) true;; *) false;; esac && [ -x "$H/.claude/skills/harness-enable/enable.sh" ] && grep -qF "$ENABLE" "$H/.claude/skills/harness-enable/enable.sh" && grep -q 'crew64@crew64' "$H/.claude/skills/harness-enable/SKILL.md" && ok "wrapper installed, points at this script" || bad "wrapper install: rc=$rc out=$(echo "$out" | grep skill)"
s1="$(sha256sum "$H/.claude/skills/harness-enable/enable.sh" "$H/.claude/skills/harness-enable/SKILL.md" 2>/dev/null)"
out="$(HOME="$H" bash "$ENABLE" "$R22" 2>&1)"
case "$out" in *"skill: current"*) ok "second run reports the wrapper current";; *) bad "wrapper second run: $(echo "$out" | grep skill)";; esac
[ -n "$s1" ] && [ "$s1" = "$(sha256sum "$H/.claude/skills/harness-enable/enable.sh" "$H/.claude/skills/harness-enable/SKILL.md" 2>/dev/null)" ] && ok "wrapper byte-identical after second run" || bad "wrapper rewritten"
printf 'stale\n' > "$H/.claude/skills/harness-enable/enable.sh" 2>/dev/null
out="$(HOME="$H" bash "$ENABLE" "$R22" 2>&1)"
case "$out" in *"skill: refreshed"*) ok "stale wrapper is refreshed";; *) bad "wrapper refresh: $(echo "$out" | grep skill)";; esac
out="$(HOME="$TMP/nohome" bash "$ENABLE" "$R22" --no-skill 2>&1)"; rc=$?
[ "$rc" = 0 ] && case "$out" in *"skill: skipped (--no-skill)"*) true;; *) false;; esac && [ ! -e "$TMP/nohome/.claude" ] && ok "--no-skill skips the wrapper" || bad "--no-skill: rc=$rc out=$(echo "$out" | grep skill)"
mkdir -p "$TMP/ro"; chmod 500 "$TMP/ro"
out="$(HOME="$TMP/ro" bash "$ENABLE" "$R22" 2>&1)"; rc=$?; chmod 700 "$TMP/ro"
[ "$rc" = 0 ] && case "$out" in *"skill: skipped ("*) true;; *) false;; esac && ok "unwritable HOME: wrapper skipped, run succeeds" || bad "ro HOME: rc=$rc out=$(echo "$out" | grep skill)"

# 5j. (Codex cycle 1) the wrapper renders the canonical script path literally: a plugin
# path with sed and shell metacharacters, and a plugin reached through a directory symlink.
P="$TMP/plug|&and"; mkdir -p "$P"; cp -r "$ROOT/tools" "$ROOT/config" "$P/"
H2="$TMP/home2"; mkdir -p "$H2"; R23="$TMP/r23"; newrepo "$R23"
out="$(HOME="$H2" bash "$P/tools/crew64-enable.sh" "$R23" 2>&1)"; rc=$?
[ "$rc" = 0 ] && grep -q 'crew64@crew64' "$R23/.claude/settings.json" && ok "metacharacter plugin path: run succeeds and settings are written" || bad "meta path run: rc=$rc out=$(echo "$out" | head -3 | tr '\n' ' ')"
real_meta="$(bash "$H2/.claude/skills/harness-enable/enable.sh" --print-real 2>/dev/null)"
[ "$real_meta" = "$P/tools/crew64-enable.sh" ] && ok "wrapper points at the metacharacter path literally" || bad "wrapper real path: '$real_meta'"
ln -s "$P" "$TMP/plug-alias"; H3="$TMP/home3"; mkdir -p "$H3"; R24="$TMP/r24"; newrepo "$R24"
HOME="$H3" bash "$TMP/plug-alias/tools/crew64-enable.sh" "$R24" >/dev/null 2>&1
real_alias="$(bash "$H3/.claude/skills/harness-enable/enable.sh" --print-real 2>/dev/null)"
[ "$real_alias" = "$P/tools/crew64-enable.sh" ] && ok "wrapper records the physical script path, not the symlink alias" || bad "wrapper alias: '$real_alias'"

# 5k. (Codex cycle 2, F3) a failing realpath must not install a wrapper with an empty path
mkdir -p "$TMP/bin"; cat > "$TMP/bin/realpath" <<'RP'
#!/usr/bin/env bash
case "${!#}" in *tools/crew64-enable.sh) exit 1 ;; esac
exec /usr/bin/realpath "$@"
RP
chmod +x "$TMP/bin/realpath"; H4="$TMP/home4"; mkdir -p "$H4"; R25="$TMP/r25"; newrepo "$R25"
out="$(HOME="$H4" PATH="$TMP/bin:$PATH" bash "$ENABLE" "$R25" 2>&1)"; rc=$?
[ "$rc" = 0 ] && case "$out" in *"skill: skipped ("*) true;; *) false;; esac && [ ! -e "$H4/.claude/skills/harness-enable/enable.sh" ] && ok "realpath failure: wrapper skipped, nothing installed, run succeeds" || bad "realpath failure: rc=$rc out=$(echo "$out" | grep skill) installed=$(ls "$H4/.claude/skills/harness-enable" 2>/dev/null | tr '\n' ' ')"

# 5l. Decision 0009: the orchestrator line says "in the main checkout" and names
# native mode. A repo enabled before 0.8.1 carries the old sentence; a re-run
# rewrites exactly that line, keeps everything else, and commits it.
NEW_TAIL='The orchestrator does not write or commit in the main checkout; in native mode it works in a task worktree.'
OLD_LINE='If you were started as the project orchestrator and were not assigned a specific implementer or reviewer role in your prompt, invoke the crew64:orchestrator skill at session start. A session whose prompt assigns it a worker role (implementer, reviewer) keeps that role and does not invoke the skill. The orchestrator does not write or commit.'
grep -qF -- "$NEW_TAIL" "$R/CLAUDE.md" && ! grep -qxF -- "$OLD_LINE" "$R/CLAUDE.md" && ok "first run writes the orchestrator line in its main-checkout wording" || bad "first-run line wording: $(cat "$R/CLAUDE.md")"
# (a) the old line between other content: replaced in place, neighbours kept, committed
R30="$TMP/r30"; newrepo "$R30"; printf 'intro line\n\n%s\n\noutro line\n' "$OLD_LINE" > "$R30/CLAUDE.md"
git -C "$R30" add CLAUDE.md && git -C "$R30" commit -q -m "old crew64 line"
out="$(bash "$ENABLE" "$R30" 2>&1)"; rc=$?
[ "$rc" = 0 ] && case "$out" in *"CLAUDE.md: orchestrator line updated"*) true;; *) false;; esac && ok "old orchestrator line: the run reports the update" || bad "old line report: rc=$rc out=$out"
[ "$(grep -c 'crew64:orchestrator' "$R30/CLAUDE.md")" = 1 ] && grep -qF -- "$NEW_TAIL" "$R30/CLAUDE.md" && ! grep -qxF -- "$OLD_LINE" "$R30/CLAUDE.md" && ok "old orchestrator line is rewritten once to the new wording" || bad "old line rewrite: $(cat "$R30/CLAUDE.md")"
[ "$(sed -n 1p "$R30/CLAUDE.md")" = "intro line" ] && [ "$(sed -n 5p "$R30/CLAUDE.md")" = "outro line" ] && [ "$(wc -l < "$R30/CLAUDE.md")" = 5 ] && ok "content around the line is kept, line for line" || bad "neighbours: $(cat -A "$R30/CLAUDE.md" | cut -c1-60)"
[ -z "$(git -C "$R30" status --porcelain)" ] && git -C "$R30" show --stat HEAD | grep -q 'CLAUDE.md' && ok "the updated line is in the enable commit and the tree is clean" || bad "old line commit: $(git -C "$R30" status --porcelain)"
# (b) a second run changes nothing
before="$(sha256sum < "$R30/CLAUDE.md")"; n1="$(git -C "$R30" rev-list --count HEAD)"
out="$(bash "$ENABLE" "$R30" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(sha256sum < "$R30/CLAUDE.md")" = "$before" ] && [ "$(git -C "$R30" rev-list --count HEAD)" = "$n1" ] && case "$out" in *"orchestrator line already present"*) true;; *) false;; esac && ok "rerun after the update is a no-op" || bad "rerun after update: rc=$rc out=$out"
# (c) a line the owner reworded is not the shipped line: left byte-identical
R31="$TMP/r31"; newrepo "$R31"; printf 'Our orchestrator invokes the crew64:orchestrator skill. The orchestrator does not write or commit.\n' > "$R31/CLAUDE.md"
git -C "$R31" add CLAUDE.md && git -C "$R31" commit -q -m "custom line"; before="$(sha256sum < "$R31/CLAUDE.md")"
out="$(bash "$ENABLE" "$R31" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(sha256sum < "$R31/CLAUDE.md")" = "$before" ] && case "$out" in *"orchestrator line already present"*) true;; *) false;; esac && ok "a reworded orchestrator line is left as the owner wrote it" || bad "custom line: rc=$rc out=$out"
# (d) CLAUDE.md is a symlink to AGENTS.md: the old line is rewritten in AGENTS.md and committed
R32="$TMP/r32"; newrepo "$R32"; printf '# Rules\n\n%s\n' "$OLD_LINE" > "$R32/AGENTS.md"; ln -s AGENTS.md "$R32/CLAUDE.md"
git -C "$R32" add AGENTS.md CLAUDE.md && git -C "$R32" commit -q -m "rules + symlink + old line"
out="$(bash "$ENABLE" "$R32" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -L "$R32/CLAUDE.md" ] && grep -qF -- "$NEW_TAIL" "$R32/AGENTS.md" && ! grep -qxF -- "$OLD_LINE" "$R32/AGENTS.md" && [ -z "$(git -C "$R32" status --porcelain)" ] && git -C "$R32" show --stat HEAD | grep -q 'AGENTS.md' && ok "symlinked CLAUDE.md: the old line is rewritten in AGENTS.md and committed" || bad "symlink old line: rc=$rc status=$(git -C "$R32" status --porcelain) out=$out"
# (e) the old line twice (a doubled paste): one new line remains
R33="$TMP/r33"; newrepo "$R33"; printf '%s\nmiddle\n%s\n' "$OLD_LINE" "$OLD_LINE" > "$R33/CLAUDE.md"
git -C "$R33" add CLAUDE.md && git -C "$R33" commit -q -m "old line twice"
bash "$ENABLE" "$R33" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(grep -c 'crew64:orchestrator' "$R33/CLAUDE.md")" = 1 ] && grep -qF -- "$NEW_TAIL" "$R33/CLAUDE.md" && grep -qx 'middle' "$R33/CLAUDE.md" && ok "a doubled old line collapses to one new line" || bad "doubled old line: $(cat "$R33/CLAUDE.md" | cut -c1-80)"
# (g) Codex cycle 1: only the matching line changes, byte for byte. Mixed line
# endings elsewhere in the file are kept, and the rewritten line keeps its own.
NEW_LINE="${OLD_LINE%The orchestrator does not write or commit.}$NEW_TAIL"
bytes_case() { # label repo expected-file : run enable, compare CLAUDE.md with the expected bytes
  git -C "$2" add CLAUDE.md && git -C "$2" commit -q -m fixture
  out="$(bash "$ENABLE" "$2" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && cmp -s "$2/CLAUDE.md" "$3" && ok "$1" || bad "$1: rc=$rc got=$(od -c "$2/CLAUDE.md" | head -3 | tr -s ' ' | cut -c1-150) out=$(printf '%s' "$out" | grep CLAUDE.md)"
}
R34="$TMP/r34"; newrepo "$R34"; printf 'intro\r\n%s\noutro\r\n' "$OLD_LINE" > "$R34/CLAUDE.md"; printf 'intro\r\n%s\noutro\r\n' "$NEW_LINE" > "$TMP/exp34"
bytes_case "mixed line endings: only the old line changes, CRLF neighbours keep their CRLF" "$R34" "$TMP/exp34"
# (h) a CRLF document: the old line is found and rewritten, CRLF kept on every line
R35="$TMP/r35"; newrepo "$R35"; printf 'intro\r\n%s\r\noutro\r\n' "$OLD_LINE" > "$R35/CLAUDE.md"; printf 'intro\r\n%s\r\noutro\r\n' "$NEW_LINE" > "$TMP/exp35"
bytes_case "CRLF document: the old line is rewritten and stays CRLF" "$R35" "$TMP/exp35"
case "$out" in *"CLAUDE.md: orchestrator line updated"*) ok "CRLF document: the update is reported";; *) bad "CRLF report: $out";; esac
# (i) new, old, old, new: exactly one new line remains, where the first new line was
R36="$TMP/r36"; newrepo "$R36"; printf '%s\na\n%s\nb\n%s\nc\n%s\n' "$NEW_LINE" "$OLD_LINE" "$OLD_LINE" "$NEW_LINE" > "$R36/CLAUDE.md"; printf '%s\na\nb\nc\n' "$NEW_LINE" > "$TMP/exp36"
bytes_case "old and new lines mixed and doubled: one new line remains, other lines kept" "$R36" "$TMP/exp36"
# (j) the file is only the old line, without a final newline: still no final newline
R37="$TMP/r37"; newrepo "$R37"; printf '%s' "$OLD_LINE" > "$R37/CLAUDE.md"; printf '%s' "$NEW_LINE" > "$TMP/exp37"
bytes_case "old line without a final newline: rewritten, still without one" "$R37" "$TMP/exp37"
# (k) no old line: a file with the new line is never rewritten, even when doubled
R38="$TMP/r38"; newrepo "$R38"; printf 'x\r\n%s\n%s\n' "$NEW_LINE" "$NEW_LINE" > "$R38/CLAUDE.md"; cp "$R38/CLAUDE.md" "$TMP/exp38"
bytes_case "no old line: the file is left byte-identical" "$R38" "$TMP/exp38"
# (f) the legacy ai-dev-system line migrates straight to the new wording
grep -qF -- "$NEW_TAIL" "$R11/CLAUDE.md" && grep -qF -- "$NEW_TAIL" "$R13/CLAUDE.md" && ! grep -qxF -- "$OLD_LINE" "$R13/CLAUDE.md" && ok "legacy ai-dev-system lines end in the new wording" || bad "legacy to new wording: r11=$(cat "$R11/CLAUDE.md" | cut -c300-) r13=$(cat "$R13/CLAUDE.md" | cut -c300-)"

# 5. --no-commit stages only
R4="$TMP/r4"; newrepo "$R4"; n1="$(git -C "$R4" rev-list --count HEAD)"
out="$(bash "$ENABLE" "$R4" --no-commit 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(git -C "$R4" rev-list --count HEAD)" = "$n1" ] && git -C "$R4" diff --cached --name-only | grep -q 'crew64.json' && ok "--no-commit stages the config without committing" || bad "--no-commit: rc=$rc out=$out"

# 6. native worktree access: settings.local.json lists <worktree_root>/<repo name>, never committed
R6="$TMP/accessrepo"; newrepo "$R6"
out="$(bash "$ENABLE" "$R6" 2>&1)"; rc=$?
want="$HOME/orca/workspaces/accessrepo"
got="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["permissions"]["additionalDirectories"])' "$R6/.claude/settings.local.json" 2>&1)"
[ "$rc" = 0 ] && [ "$got" = "['$want']" ] && ok "settings.local.json lists the Orca worktree dir for this repo" || bad "worktree access: rc=$rc got=$got out=$out"
case "$out" in *"worktree access: $want added to .claude/settings.local.json"*) ok "enable reports the added worktree dir";; *) bad "worktree access message: $out";; esac
git -C "$R6" ls-files --error-unmatch .claude/settings.local.json >/dev/null 2>&1 && bad "settings.local.json was committed" || ok "settings.local.json is not committed"
git -C "$R6" check-ignore -q .claude/settings.local.json && ok "settings.local.json is ignored by git" || bad "settings.local.json not ignored"
[ -z "$(git -C "$R6" status --porcelain)" ] && ok "worktree access leaves the tree clean" || bad "dirty after enable: $(git -C "$R6" status --porcelain)"
before="$(cat "$R6/.claude/settings.local.json")"; nx="$(grep -c 'settings.local.json' "$(git -C "$R6" rev-parse --absolute-git-dir)/info/exclude")"
out="$(bash "$ENABLE" "$R6" 2>&1)"
[ "$before" = "$(cat "$R6/.claude/settings.local.json")" ] && [ "$nx" = "$(grep -c 'settings.local.json' "$(git -C "$R6" rev-parse --absolute-git-dir)/info/exclude")" ] && case "$out" in *"worktree access: $want already listed"*) true;; *) false;; esac && ok "a re-run leaves settings.local.json and the exclude file unchanged" || bad "worktree access re-run: $out"
# an existing settings.local.json keeps its other keys and entries
R7="$TMP/accessrepo2"; newrepo "$R7"; mkdir -p "$R7/.claude"
printf '{"permissions": {"allow": ["Bash(ls:*)"], "additionalDirectories": ["/opt/x"]}, "model": "m"}\n' > "$R7/.claude/settings.local.json"
bash "$ENABLE" "$R7" >/dev/null 2>&1
got="$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["model"], d["permissions"]["allow"], d["permissions"]["additionalDirectories"])' "$R7/.claude/settings.local.json" 2>&1)"
[ "$got" = "m ['Bash(ls:*)'] ['/opt/x', '$HOME/orca/workspaces/accessrepo2']" ] && ok "existing settings.local.json keys and entries are kept" || bad "merge settings.local.json: $got"
# the switch off: nothing written
R8="$TMP/accessrepo3"; newrepo "$R8"
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); d["features"]["native_worktree_access"]=False; json.dump(d,open(sys.argv[2],"w"))' "$DEFAULTS" "$TMP/cfg-noaccess.json"
out="$(bash "$ENABLE" "$R8" --config "$TMP/cfg-noaccess.json" 2>&1)"
[ ! -e "$R8/.claude/settings.local.json" ] && case "$out" in *"worktree access: off"*) true;; *) false;; esac && ok "features.native_worktree_access false → no settings.local.json" || bad "access off: $out"
# platform.worktree_root overrides the default
R9="$TMP/accessrepo4"; newrepo "$R9"
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); d["platform"]["worktree_root"]=sys.argv[3]; json.dump(d,open(sys.argv[2],"w"))' "$DEFAULTS" "$TMP/cfg-root.json" "$TMP/wtroot"
bash "$ENABLE" "$R9" --config "$TMP/cfg-root.json" >/dev/null 2>&1
got="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["permissions"]["additionalDirectories"])' "$R9/.claude/settings.local.json" 2>&1)"
[ "$got" = "['$TMP/wtroot/accessrepo4']" ] && ok "platform.worktree_root sets the directory" || bad "worktree_root: $got"
# a settings.local.json that is not an object stops with an error and is left alone
R10="$TMP/accessrepo5"; newrepo "$R10"; mkdir -p "$R10/.claude"; echo '[1]' > "$R10/.claude/settings.local.json"
out="$(bash "$ENABLE" "$R10" 2>&1)"; rc=$?
[ "$rc" != 0 ] && [ "$(cat "$R10/.claude/settings.local.json")" = "[1]" ] && case "$out" in *"settings.local.json is not a JSON object"*) true;; *) false;; esac && ok "a non-object settings.local.json stops enable and is left alone" || bad "non-object local settings: rc=$rc out=$out"

exit $fail
