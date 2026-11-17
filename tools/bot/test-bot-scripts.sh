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
mkdir -p "$XDG_CONFIG_HOME/git"; export GIT_CONFIG_GLOBAL="$XDG_CONFIG_HOME/git/config"; : > "$GIT_CONFIG_GLOBAL"   # the file the install script writes its includeIf rules to
git config --global user.name Owner; git config --global user.email owner@x
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

# 2b. the include rules follow the projects directories that exist, not a hard-coded ~/Projects
GC="$XDG_CONFIG_HOME/git/config"
rules() { grep -c '^\[includeIf "gitdir:' "$GC"; }
# no projects dir at all in this HOME → only the orca workspaces rule
[ "$(rules)" = 1 ] && grep -qF 'gitdir:~/orca/workspaces/' "$GC" && ! grep -qF 'Projects' "$GC" && ok "no projects dir → only the orca/workspaces rule, no ~/Projects" || bad "rules without projects dir: $(grep includeIf "$GC" | tr '\n' ' ')"
# lowercase ~/projects exists → rule for it; re-run replaces the block (no duplicates)
mkdir -p "$HOME/projects"
"$BOT/install-bot-identity.sh" --name B --email e@x --token-command "echo tok-1" >/dev/null 2>&1
[ "$(rules)" = 2 ] && grep -qF 'gitdir:~/projects/*/.git/worktrees/' "$GC" && [ "$(grep -c '^# >>> orca-bot identity' "$GC")" = 1 ] && ok "~/projects detected → its rule added, block replaced not duplicated" || bad "rules with ~/projects: $(grep -E 'includeIf|identity' "$GC" | tr '\n' ' ')"
# both spellings exist → both rules
mkdir -p "$HOME/Projects"
"$BOT/install-bot-identity.sh" --name B --email e@x --token-command "echo tok-1" >/dev/null 2>&1
[ "$(rules)" = 3 ] && grep -qF 'gitdir:~/Projects/*/.git/worktrees/' "$GC" && ok "both ~/projects and ~/Projects → both rules" || bad "rules with both: $(grep includeIf "$GC" | tr '\n' ' ')"
# explicit --projects-dir replaces detection
"$BOT/install-bot-identity.sh" --name B --email e@x --token-command "echo tok-1" --projects-dir "$HOME/code" >/dev/null 2>&1
[ "$(rules)" = 2 ] && grep -qF 'gitdir:~/code/*/.git/worktrees/' "$GC" && ! grep -qF 'gitdir:~/projects/' "$GC" && ok "--projects-dir replaces detection" || bad "rules with --projects-dir: $(grep includeIf "$GC" | tr '\n' ' ')"
# a linked worktree under the configured dir gets the bot identity
mkdir -p "$HOME/code"; git init -q "$HOME/code/r" && git -C "$HOME/code/r" -c user.name=t -c user.email=t@x commit -q --allow-empty -m i && git -C "$HOME/code/r" worktree add -q "$HOME/code/r-wt" -b wt
[ "$(git -C "$HOME/code/r-wt" config user.name)" = "B" ] && [ "$(git -C "$HOME/code/r" config user.name)" != "B" ] && ok "worktree under --projects-dir commits as the bot, main checkout does not" || bad "identity: wt=$(git -C "$HOME/code/r-wt" config user.name) main=$(git -C "$HOME/code/r" config user.name)"
# Codex review of PR 15: an unrelated include right after the managed block must survive a re-run intact,
# a comment inside the block must not orphan a path line, and a directory with config- or glob-special
# characters is refused before the config is touched.
printf '[includeIf "gitdir:~/elsewhere/"]\n\tpath = other.gitconfig\n' >> "$GC"
"$BOT/install-bot-identity.sh" --name B --email e@x --token-command "echo tok-1" --projects-dir "$HOME/code" >/dev/null 2>&1
grep -qF '[includeIf "gitdir:~/elsewhere/"]' "$GC" && grep -qF 'path = other.gitconfig' "$GC" && [ "$(grep -c 'path = other.gitconfig' "$GC")" = 1 ] && ok "unrelated include after the block keeps its header and path" || bad "unrelated include damaged: $(grep -n -E 'includeIf|path =' "$GC" | tr '\n' ' ')"
git config --file "$GC" --get-all includeIf.gitdir:~/elsewhere/.path >/dev/null && ok "config still parses after re-run" || bad "config no longer parses"
before="$(cat "$GC")"
for badd in "$HOME/ba\"d" "$HOME/code[1]" "$HOME/co*de"; do
  "$BOT/install-bot-identity.sh" --name B --email e@x --token-command "echo tok-1" --projects-dir "$badd" >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] || bad "special-char dir accepted (rc=$rc): $badd"
done
[ "$before" = "$(cat "$GC")" ] && ok "quote, bracket and star in --projects-dir are refused and the config is untouched" || bad "config changed by a refused --projects-dir"
# Codex cycle 4: symlinks resolve before the pattern is built, because git matches gitdir
# against real paths. A plain alias and an alias followed by .. both map to the real directory.
mkdir -p "$HOME/actual" "$HOME/outer/target" "$HOME/outer/projects2"; ln -sfn "$HOME/actual" "$HOME/alias"; ln -sfn "$HOME/outer/target" "$HOME/link"
"$BOT/install-bot-identity.sh" --name B --email e@x --token-command "echo tok-1" --projects-dir "$HOME/alias" >/dev/null 2>&1
grep -qF 'gitdir:~/actual/*/.git/worktrees/' "$GC" && ! grep -qF 'gitdir:~/alias/' "$GC" && ok "symlinked --projects-dir resolves to the real directory" || bad "alias: $(grep includeIf "$GC" | tr '\n' ' ')"
git init -q "$HOME/actual/r2" && git -C "$HOME/actual/r2" -c user.name=t -c user.email=t@x commit -q --allow-empty -m i && git -C "$HOME/actual/r2" worktree add -q "$HOME/actual/r2-wt" -b wt
[ "$(git -C "$HOME/alias/r2-wt" config user.name)" = "B" ] && ok "worktree reached through the alias commits as the bot" || bad "alias worktree identity: $(git -C "$HOME/alias/r2-wt" config user.name)"
"$BOT/install-bot-identity.sh" --name B --email e@x --token-command "echo tok-1" --projects-dir "$HOME/link/../projects2" >/dev/null 2>&1
grep -qF 'gitdir:~/outer/projects2/*/.git/worktrees/' "$GC" && ! grep -qF 'gitdir:~/projects2/' "$GC" && ok "symlink followed by .. resolves through the link target" || bad "link/..: $(grep includeIf "$GC" | tr '\n' ' ')"
# Codex cycle 5: a clean alias whose TARGET ends in a newline (or a symlink loop) must be refused
# after resolution, which means validating inside Python before the path crosses back into Bash.
mkdir -p "$HOME/outer/bad"$'\n'; ln -sfn "$HOME/outer/bad"$'\n' "$HOME/cleanalias"; ln -sfn "$HOME/loop1" "$HOME/loop2"; ln -sfn "$HOME/loop2" "$HOME/loop1"
before="$(cat "$GC")"; k0="$(git config --global --get aidev.bot.tokenCommand)"
mkdir -p "$HOME/future"   # Codex cycle 6: a loop in an ANCESTOR component must be refused too, with or without a .. after it
for badd in "$HOME/cleanalias" "$HOME/loop1" "$HOME/loop1/child" "$HOME/loop1/../future"; do
  "$BOT/install-bot-identity.sh" --name Q --email q@x --token-command "echo tok-Q" --projects-dir "$badd" >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] || bad "resolved-path problem accepted (rc=$rc): $badd"
done
[ "$before" = "$(cat "$GC")" ] && [ "$(git config --global --get aidev.bot.tokenCommand)" = "$k0" ] && ok "alias to a newline-named target and a symlink loop are refused after resolution, nothing written" || bad "config or keys changed by a refused resolved path"
# Codex cycle 3: a trailing newline survives Bash's \$(...) stripping only if validated on the raw argument.
k0="$(git config --global --get aidev.bot.tokenCommand)"; before="$(cat "$GC")"
"$BOT/install-bot-identity.sh" --name Q --email q@x --token-command "echo tok-Q" --projects-dir "$HOME/code"$'\n' >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ "$before" = "$(cat "$GC")" ] && [ "$(git config --global --get aidev.bot.tokenCommand)" = "$k0" ] && ok "trailing newline in --projects-dir is refused before any write" || bad "trailing LF: rc=$rc config_changed=$([ "$before" = "$(cat "$GC")" ] || echo yes) key=$(git config --global --get aidev.bot.tokenCommand)"
# Codex cycle 2: an unmatched begin marker must abort before any write; relative and
# slash-heavy directories normalise to one absolute pattern; a legacy block followed by
# a user include migrates with the user include intact.
cp "$GC" "$TMP/gc.good"
printf '# >>> orca-bot identity (tools/bot/install-bot-identity.sh) >>>\n[includeIf "gitdir:~/x/*/.git/worktrees/"]\n\tpath = orca-bot.gitconfig\n[includeIf "gitdir:~/elsewhere2/"]\n\tpath = other2.gitconfig\n[review]\n\tkeep = yes\n' > "$GC"
cp "$GC" "$TMP/gc.unmatched"; k1="$(git config --global --get aidev.bot.tokenCommand)"
"$BOT/install-bot-identity.sh" --name Z --email z@x --token-command "echo tok-Z" --projects-dir "$HOME/code" >/dev/null 2>&1; rc=$?
cmp -s "$GC" "$TMP/gc.unmatched" && [ "$rc" != 0 ] && [ "$(git config --global --get aidev.bot.tokenCommand)" = "$k1" ] && ok "unmatched begin marker → non-zero exit, config and keys untouched" || bad "unmatched marker: rc=$rc changed=$(cmp -s "$GC" "$TMP/gc.unmatched" || echo yes)"
cp "$TMP/gc.good" "$GC"
( cd "$HOME" && "$BOT/install-bot-identity.sh" --name B --email e@x --token-command "echo tok-1" --projects-dir code >/dev/null 2>&1 )
grep -qF 'gitdir:~/code/*/.git/worktrees/' "$GC" && ! grep -qF 'gitdir:code/' "$GC" && ok "relative --projects-dir resolves to an absolute pattern" || bad "relative dir: $(grep includeIf "$GC" | tr '\n' ' ')"
"$BOT/install-bot-identity.sh" --name B --email e@x --token-command "echo tok-1" --projects-dir "$HOME/code///" >/dev/null 2>&1
[ "$(grep -c 'gitdir:~/code/\*/.git/worktrees/' "$GC")" = 1 ] && ! grep -qF 'code///' "$GC" && [ "$(git -C "$HOME/code/r-wt" config user.name)" = "B" ] && ok "repeated trailing slashes normalise and the worktree still gets the bot" || bad "trailing slashes: $(grep includeIf "$GC" | tr '\n' ' ')"
printf '[user]\n\tname = Owner\n\temail = owner@x\n\n# orca-bot identity (tools/bot/install-bot-identity.sh)\n[includeIf "gitdir:~/Projects/*/.git/worktrees/"]\n\tpath = orca-bot.gitconfig\n[includeIf "gitdir:~/orca/workspaces/"]\n\tpath = orca-bot.gitconfig\n[includeIf "gitdir:~/elsewhere/"]\n\tpath = other.gitconfig\n' > "$GC"
"$BOT/install-bot-identity.sh" --name B --email e@x --token-command "echo tok-1" --projects-dir "$HOME/code" >/dev/null 2>&1
! grep -qF 'gitdir:~/Projects/' "$GC" && grep -qF 'gitdir:~/elsewhere/' "$GC" && grep -qF 'path = other.gitconfig' "$GC" && [ "$(grep -c '^# >>> orca-bot' "$GC")" = 1 ] && [ "$(grep -c '^# orca-bot identity (tools' "$GC")" = 0 ] && git config --file "$GC" --list >/dev/null && ok "legacy block migrates to markers; the user include after it survives" || bad "legacy migration: $(grep -n -E 'includeIf|identity|path' "$GC" | tr '\n' ' ')"
git config --global --add aidev.trustedRoot "$R"   # the legacy-migration fixture replaced the global config; re-register the repo
rmdir "$HOME/Projects"; "$BOT/install-bot-identity.sh" --name B --email e@x --token-command "echo tok-1" >/dev/null 2>&1   # restore detection for the tests below

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
