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

# 5. --no-commit stages only
R4="$TMP/r4"; newrepo "$R4"; n1="$(git -C "$R4" rev-list --count HEAD)"
out="$(bash "$ENABLE" "$R4" --no-commit 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(git -C "$R4" rev-list --count HEAD)" = "$n1" ] && git -C "$R4" diff --cached --name-only | grep -q 'crew64.json' && ok "--no-commit stages the config without committing" || bad "--no-commit: rc=$rc out=$out"

exit $fail
