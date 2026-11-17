#!/usr/bin/env bash
# Unit test for tools/bot: the identity comes from the user's git config
# (aidev.bot.*) and the repo's features.bot_identity switch (decision 0005).
# Runs in a throwaway HOME with a fake gh. Exit 0 = all pass.
set -u
BOT="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$BOT/../.." && pwd)"
DEFAULTS="$ROOT/config/ai-dev-system.defaults.json"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.local/bin" "$TMP/bin"
export XDG_CONFIG_HOME="$HOME/.config"
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"; : > "$GIT_CONFIG_GLOBAL"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${GH_TOKEN:-no-token}"\n' > "$TMP/bin/gh"; chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
R="$TMP/repo"; git init -q "$R" && git -C "$R" -c user.name=t -c user.email=t@x commit -q --allow-empty -m init
git config --global --add aidev.trustedRoot "$R"   # decision 0005: the switch is read only from a registered root
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
switch() { mkdir -p "$R/.claude"; python3 -I -c '
import json,sys
d=json.load(open(sys.argv[1])); d["features"]["bot_identity"]=(sys.argv[3]=="true")
json.dump(d,open(sys.argv[2],"w"))' "$DEFAULTS" "$R/.claude/ai-dev-system.json" "$1"; }

# 1. no keys yet, switch on → refuse naming the missing key
switch true
err="$(cd "$R" && "$BOT/gh-bot" x 2>&1 >/dev/null)"; rc=$?
[ "$rc" = 1 ] && case "$err" in *aidev.bot.name*) true;; *) false;; esac && ok "gh-bot without keys refuses, names aidev.bot.name" || bad "no keys: rc=$rc err=$err"

# 2. install writes the keys; second run is idempotent
out1="$("$BOT/install-bot-identity.sh" --name B --email e@x --token-command "echo tok-1" 2>&1)"; rc1=$?
out2="$("$BOT/install-bot-identity.sh" --name B --email e@x --token-command "echo tok-1" 2>&1)"; rc2=$?
[ "$rc1" = 0 ] && [ "$rc2" = 0 ] && case "$out2" in *"already present"*) true;; *) false;; esac && ok "install runs twice, second says already present" || bad "install: rc1=$rc1 rc2=$rc2 out2=$out2"
got="$(git config --global --get aidev.bot.tokenCommand)"
[ "$got" = "echo tok-1" ] && ok "aidev.bot.tokenCommand in global git config" || bad "tokenCommand: '$got'"
grep -q 'name = B' "$XDG_CONFIG_HOME/git/orca-bot.gitconfig" && ok "orca-bot.gitconfig takes user.name from --name" || bad "orca-bot.gitconfig user.name"

# 3. keys set, switch on → gh runs with the token
out="$(cd "$R" && "$BOT/gh-bot" x 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "tok-1" ] && ok "gh-bot passes the token to gh" || bad "gh-bot: rc=$rc out=$out"

# 4. credential helper answers get for github.com
out="$(cd "$R" && printf 'host=github.com\n\n' | "$BOT/git-credential-op-bot" get 2>/dev/null)"
case "$out" in *"username=B"*password=tok-1*) ok "credential helper prints username and token";; *) bad "helper: '$out'";; esac

# 5. switch off → refuse naming the switch
switch false
err="$(cd "$R" && "$BOT/gh-bot" x 2>&1 >/dev/null)"; rc=$?
[ "$rc" = 1 ] && case "$err" in *bot_identity*) true;; *) false;; esac && ok "gh-bot refuses when bot_identity is off" || bad "switch off: rc=$rc err=$err"

# 6. outside any repo → refuse naming the repository
err="$(cd "$TMP" && "$BOT/gh-bot" x 2>&1 >/dev/null)"; rc=$?
[ "$rc" = 1 ] && case "$err" in *repository*) true;; *) false;; esac && ok "gh-bot refuses outside a repository" || bad "outside repo: rc=$rc err=$err"

# 7. no config file at all → the switch defaults to off → refuse
rm -f "$R/.claude/ai-dev-system.json"
err="$(cd "$R" && "$BOT/gh-bot" x 2>&1 >/dev/null)"; rc=$?
[ "$rc" = 1 ] && case "$err" in *bot_identity*) true;; *) false;; esac && ok "gh-bot refuses when no config file exists" || bad "no config: rc=$rc err=$err"

# 8. a repo-local aidev.bot.* value is ignored: only the global config is trusted
switch true
git -C "$R" config aidev.bot.tokenCommand 'echo INJECTED'
git -C "$R" config aidev.bot.name 'Mallory'
out="$(cd "$R" && "$BOT/gh-bot" x 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "tok-1" ] && ok "repo-local tokenCommand is ignored (global wins)" || bad "repo-local override: rc=$rc out=$out"
out="$(cd "$R" && printf 'host=github.com\n\n' | "$BOT/git-credential-op-bot" get 2>/dev/null)"
case "$out" in *"username=B"*password=tok-1*) ok "repo-local name is ignored by the credential helper";; *) bad "helper with repo-local keys: '$out'";; esac

exit $fail
