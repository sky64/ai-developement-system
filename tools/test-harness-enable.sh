#!/usr/bin/env bash
# Unit test for tools/harness-enable.sh. Runs against throwaway repositories
# with Orca stubbed through ORCA_CLI_COMMAND. Exit 0 = all pass.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENABLE="$ROOT/tools/harness-enable.sh"
DEFAULTS="$ROOT/config/ai-dev-system.defaults.json"
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
sums() { (cd "$1" && sha256sum .claude/ai-dev-system.json .claude/settings.json CLAUDE.md 2>/dev/null); }

# 1. first run
R="$TMP/r1"; newrepo "$R"
out="$(bash "$ENABLE" "$R" 2>&1)"; rc=$?
[ "$rc" = 0 ] && case "$out" in *"config: written from defaults"*) true;; *) false;; esac && ok "first run exits 0 and writes config from defaults" || bad "first run: rc=$rc out=$out"
cmp -s "$R/.claude/ai-dev-system.json" "$DEFAULTS" && ok "config equals the defaults file" || bad "config differs from defaults"
grep -q '"ai-dev-system@ai-dev-system": true' "$R/.claude/settings.json" && ok "settings.json enables the plugin" || bad "settings.json"
grep -q 'ai-dev-system:orchestrator' "$R/CLAUDE.md" && ok "CLAUDE.md has the orchestrator line" || bad "CLAUDE.md"
[ "$(git -C "$R" log -1 --format=%s)" = "chore: enable ai-dev-system plugin" ] && ok "committed" || bad "commit message: $(git -C "$R" log -1 --format=%s)"
git -C "$R" ls-files --error-unmatch .claude/ai-dev-system.json >/dev/null 2>&1 && ok "config file is tracked" || bad "config not tracked"
[ "$(git config --global --get-all aidev.trustedRoot | grep -c -x "$R")" = 1 ] && ok "repo registered once as a trusted root in the global git config" || bad "trustedRoot registration: $(git config --global --get-all aidev.trustedRoot)"

# 2. second run: idempotent
before="$(sums "$R")"; n1="$(git -C "$R" rev-list --count HEAD)"
out="$(bash "$ENABLE" "$R" 2>&1)"; rc=$?
after="$(sums "$R")"; n2="$(git -C "$R" rev-list --count HEAD)"
[ "$rc" = 0 ] && case "$out" in *"config: already present"*) true;; *) false;; esac && ok "second run says already present" || bad "second run: rc=$rc out=$out"
[ "$before" = "$after" ] && [ "$n1" = "$n2" ] && ok "second run changes nothing and adds no commit" || bad "second run changed files or committed"
[ "$(git config --global --get-all aidev.trustedRoot | grep -c -x "$R")" = 1 ] && ok "second run does not duplicate the trusted root" || bad "trustedRoot duplicated"

# 3. --config copies a prepared file
R2="$TMP/r2"; newrepo "$R2"
out="$(bash "$ENABLE" "$R2" --config "$EXAMPLE" 2>&1)"; rc=$?
[ "$rc" = 0 ] && cmp -s "$R2/.claude/ai-dev-system.json" "$EXAMPLE" && case "$out" in *"config: written from $EXAMPLE"*) true;; *) false;; esac && ok "--config copies the example" || bad "--config: rc=$rc out=$out"

# 4. --config with an invalid file stops before writing
R3="$TMP/r3"; newrepo "$R3"; printf '{"version": 2}' > "$TMP/bad.json"
out="$(bash "$ENABLE" "$R3" --config "$TMP/bad.json" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ ! -e "$R3/.claude/ai-dev-system.json" ] && [ ! -e "$R3/.claude/settings.json" ] && case "$out" in *check*) true;; *) false;; esac && ok "invalid --config exits 1 before writing" || bad "invalid config: rc=$rc out=$out"

# 5b. a hand-formatted settings.json that already enables the plugin is left byte-identical
R5="$TMP/r5"; newrepo "$R5"; mkdir -p "$R5/.claude"
printf '{\n    "enabledPlugins": {\n        "ai-dev-system@ai-dev-system": true\n    },\n    "extraKnownMarketplaces": {\n        "ai-dev-system": {\n            "source": {\n                "source": "github",\n                "repo": "sky64/ai-developement-system"\n            }\n        }\n    }\n}\n' > "$R5/.claude/settings.json"
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

# 5. --no-commit stages only
R4="$TMP/r4"; newrepo "$R4"; n1="$(git -C "$R4" rev-list --count HEAD)"
out="$(bash "$ENABLE" "$R4" --no-commit 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(git -C "$R4" rev-list --count HEAD)" = "$n1" ] && git -C "$R4" diff --cached --name-only | grep -q 'ai-dev-system.json' && ok "--no-commit stages the config without committing" || bad "--no-commit: rc=$rc out=$out"

exit $fail
