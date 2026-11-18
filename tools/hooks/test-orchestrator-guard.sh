#!/usr/bin/env bash
# Unit test for tools/hooks/orchestrator-guard.py. Runs the hook against a
# throwaway repo (main checkout) and two worktrees of it, one with a space in
# its path. Exit 0 = all pass.
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/orchestrator-guard.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"; : > "$GIT_CONFIG_GLOBAL"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@x GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@x
git -C "$TMP" init -q main && git -C "$TMP/main" commit -q --allow-empty -m init
git -C "$TMP/main" worktree add -q "$TMP/wt" -b wt
git -C "$TMP/main" worktree add -q "$TMP/wt with space" -b wt-space
fail=0
run() { # expected_exit cwd tool json_input
  local exp="$1" cwd="$2" tool="$3" input="$4"
  printf '{"tool_name":"%s","cwd":"%s","tool_input":%s}' "$tool" "$cwd" "$input" \
    | ORCHESTRATOR_GUARD= python3 -I "$HOOK" 2>/dev/null; local got=$?
  if [ "$got" = "$exp" ]; then echo "ok   exit $got  $tool $(echo "$input" | cut -c1-60)"
  else echo "FAIL exit $got (want $exp)  cwd=$cwd $tool $input"; fail=1; fi
}
raw() { # expected_exit label raw_stdin ; stderr must be non-empty
  local exp="$1" label="$2" input="$3" err
  err="$(printf '%s' "$input" | ORCHESTRATOR_GUARD= python3 -I "$HOOK" 2>&1 >/dev/null)"; local got=$?
  if [ "$got" = "$exp" ] && [ -n "$err" ]; then echo "ok   exit $got  $label"
  else echo "FAIL exit $got (want $exp, stderr '$err')  $label"; fail=1; fi
}
runenv() { # VAR=value expected_exit cwd tool json_input
  local envpair="$1" exp="$2" cwd="$3" tool="$4" input="$5"
  printf '{"tool_name":"%s","cwd":"%s","tool_input":%s}' "$tool" "$cwd" "$input" \
    | env ORCHESTRATOR_GUARD= "$envpair" python3 -I "$HOOK" 2>/dev/null; local got=$?
  if [ "$got" = "$exp" ]; then echo "ok   exit $got  [$envpair] $tool $(echo "$input" | cut -c1-50)"
  else echo "FAIL exit $got (want $exp)  [$envpair] cwd=$cwd $tool $input"; fail=1; fi
}
M="$TMP/main"; W="$TMP/wt"; WS="$TMP/wt with space"

# Original cases: main checkout denies writes, allows reads.
run 2 "$M" Write  '{"file_path":"x.md","content":"hi"}'
run 2 "$M" Edit   '{"file_path":"x.md","old_string":"a","new_string":"b"}'
run 2 "$M" Bash   '{"command":"cat > docs/x.md <<EOF\nhi\nEOF"}'
run 2 "$M" Bash   '{"command":"sed -i s/a/b/ README.md"}'
run 2 "$M" Bash   '{"command":"git commit -m x"}'
run 2 "$M" Bash   '{"command":"echo hi | tee out.txt"}'
run 2 "$M" Bash   '{"command":"python3 -c \"open(\\\"f\\\",\\\"w\\\")\""}'
run 0 "$M" Bash   '{"command":"git diff --check"}'
run 0 "$M" Bash   '{"command":"cat README.md | head"}'
run 0 "$M" Bash   '{"command":"cargo test 2>&1 | tail"}'
run 0 "$M" Bash   '{"command":"orca worktree create --name t --agent claude --prompt x"}'
run 0 "$M" Bash   '{"command":"orca-ide worktree create --name t --agent claude --prompt x"}'
run 2 "$M" Bash   '{"command":"orca worktree create --prompt x > out.txt"}'
run 0 "$M" Bash   '{"command":"ls > /dev/null; grep -r x . 2>/dev/null"}'
run 0 "$M" Read   '{"file_path":"x.md"}'
run 0 "$W" Write  '{"file_path":"x.md","content":"hi"}'
run 0 "$W" Bash   '{"command":"git commit -m x"}'
run 0 "$W" Bash   '{"command":"cat > docs/x.md <<EOF\nhi\nEOF"}'

# P1: worktree writes must stay inside the worktree.
run 0 "$W" Write  "{\"file_path\":\"$W/docs/new.md\",\"content\":\"hi\"}"
run 2 "$W" Write  "{\"file_path\":\"$M/x.md\",\"content\":\"hi\"}"
run 2 "$W" Edit   '{"file_path":"../main/AGENTS.md","old_string":"a","new_string":"b"}'
run 0 "$W" MultiEdit '{"file_path":"/tmp/outside.md","edits":[]}'   # scratch: allowed since the field fixes
run 2 "$W" NotebookEdit '{"notebook_path":"../main/n.ipynb","new_source":"x"}'
run 2 "$W" Write  '{"content":"no path"}'

# Field fixes 2026-11-18: the session scratchpad under /tmp or $TMPDIR is writable from any checkout.
run 0 "$M" Write  '{"file_path":"/tmp/brief.md","content":"hi"}'
run 0 "$W" Edit   '{"file_path":"/tmp/brief.md","old_string":"a","new_string":"b"}'
run 2 "$M" Write  '{"file_path":"/tmp/../etc/passwd","content":"hi"}'
mkdir -p "$TMP/scratch"; ln -s "$M" "$TMP/scratch/repo"; ln -s "$TMP/scratch" "/tmp/guardtest-$$"
run 2 "$M" Write  "{\"file_path\":\"/tmp/guardtest-$$/repo/x.md\",\"content\":\"hi\"}"   # symlink out of /tmp into the repo
rm -f "/tmp/guardtest-$$"
SCR="$(mktemp -d -p "${XDG_RUNTIME_DIR:-$HOME}" guardtest.XXXXXX)"   # outside /tmp, so only the TMPDIR rule can allow it
runenv TMPDIR="$SCR" 0 "$M" Write "{\"file_path\":\"$SCR/b.md\",\"content\":\"hi\"}"                  # TMPDIR allowance
run 2 "$M" Write  "{\"file_path\":\"$SCR/b.md\",\"content\":\"hi\"}"                                   # same path without TMPDIR: denied
rmdir "$SCR"
runenv TMPDIR="$M/tmp" 2 "$M" Write "{\"file_path\":\"$M/tmp/b.md\",\"content\":\"hi\"}"              # TMPDIR inside the repo: ignored
run 2 "$M" Write  '{"file_path":"tmp/b.md","content":"hi"}'                                             # relative: not scratch

# P1: orca exemption only for a single plain invocation.
run 2 "$M" Bash   '{"command":"orca status; git add README.md"}'
run 2 "$M" Bash   '{"command":"orca status && git commit -m x"}'
run 2 "$M" Bash   '{"command":"orca status | tee out.txt"}'
run 2 "$M" Bash   '{"command":"orca status $(git add README.md)"}'
run 0 "$M" Bash   '{"command":"orca status --json"}'

# P2: git with leading global options, config writes, read-only forms.
run 2 "$M" Bash   '{"command":"git -c user.name=x commit -m y"}'
run 2 "$M" Bash   '{"command":"git --git-dir=.git commit -m y"}'
run 2 "$M" Bash   '{"command":"git --no-pager -C . add README.md"}'
run 2 "$M" Bash   '{"command":"git config set user.name x"}'
run 2 "$M" Bash   '{"command":"git config user.name x"}'
run 2 "$M" Bash   '{"command":"git config --global --unset user.name"}'
run 0 "$M" Bash   '{"command":"git config --get user.name"}'
run 0 "$M" Bash   '{"command":"git config --list"}'
run 0 "$M" Bash   '{"command":"git -c core.pager=cat log --oneline -3"}'
run 2 "$M" Bash   '{"command":"ls && git push origin main"}'
run 2 "$M" Bash   '{"command":"true || git fetch origin"}'
run 2 "$M" Bash   '{"command":"echo a\ngit stash push -m x"}'
run 2 "$M" Bash   '{"command":"git tag v1"}'
run 2 "$M" Bash   '{"command":"git branch -d wt"}'
run 2 "$M" Bash   '{"command":"git branch newbranch"}'
run 2 "$M" Bash   '{"command":"git worktree add ../x"}'
run 2 "$M" Bash   '{"command":"git remote add up https://example.invalid/r.git"}'
run 2 "$M" Bash   '{"command":"git submodule update --init"}'
run 2 "$M" Bash   '{"command":"git update-ref refs/heads/main HEAD~1"}'
run 0 "$M" Bash   '{"command":"git worktree list --porcelain"}'
run 0 "$M" Bash   '{"command":"git tag --list"}'
run 0 "$M" Bash   '{"command":"git tag -l v*"}'
run 0 "$M" Bash   '{"command":"git stash list"}'
run 0 "$M" Bash   '{"command":"git branch --show-current"}'
run 0 "$M" Bash   '{"command":"git branch -a"}'
run 0 "$M" Bash   '{"command":"git branch"}'
run 0 "$M" Bash   '{"command":"git remote -v"}'
run 0 "$M" Bash   '{"command":"git submodule status"}'

# P2: sed -i anywhere, Python write variants, /tmp redirect with "..".
run 2 "$M" Bash   '{"command":"sed -e s/a/b/ -i README.md"}'
run 2 "$M" Bash   '{"command":"sed -n -e p --in-place=.bak README.md"}'
run 0 "$M" Bash   '{"command":"sed -n 1,5p README.md"}'
run 2 "$M" Bash   '{"command":"python3 -c \"from pathlib import Path; Path(\\\"f\\\").write_text(\\\"x\\\")\""}'
run 2 "$M" Bash   '{"command":"python3 -c \"import pathlib; pathlib.Path(\\\"f\\\").write_bytes(b\\\"x\\\")\""}'
run 2 "$M" Bash   '{"command":"python3 -c \"import shutil; shutil.copy(\\\"a\\\",\\\"b\\\")\""}'
run 2 "$M" Bash   '{"command":"python3 -c \"import shutil; shutil.move(\\\"a\\\",\\\"b\\\")\""}'
run 2 "$M" Bash   '{"command":"python3 -c \"import os; os.remove(\\\"a\\\")\""}'
run 2 "$M" Bash   '{"command":"python3 -c \"import os; os.rename(\\\"a\\\",\\\"b\\\")\""}'
run 2 "$M" Bash   '{"command":"python3 -c \"import os; os.unlink(\\\"a\\\")\""}'
run 2 "$M" Bash   '{"command":"echo x > /tmp/../etc/hosts"}'
run 0 "$M" Bash   '{"command":"echo x > /tmp/scratch.txt"}'

# P2: worktree path with a space is still detected as a worktree.
run 0 "$WS" Write '{"file_path":"x.md","content":"hi"}'
run 0 "$WS" Bash  '{"command":"git commit -m x"}'

# P2: invalid hook input denies with a diagnostic instead of failing open.
raw 2 "malformed JSON"        '{"tool_name": "Write", '
raw 2 "non-object payload"    '["Write"]'
raw 2 "missing tool_name"     "{\"cwd\":\"$M\",\"tool_input\":{\"file_path\":\"x.md\"}}"
raw 2 "tool_input not object" "{\"tool_name\":\"Write\",\"cwd\":\"$M\",\"tool_input\":\"x\"}"

# Cycle 2, P2: quote-aware and operator-aware parsing.
run 2 "$M" Bash   '{"command":"orca status&git add README.md"}'
run 2 "$M" Bash   '{"command":"git -c \"user.name=A;B\" commit -m x"}'
run 2 "$M" Bash   '{"command":"\"git\" commit -m x"}'
run 2 "$M" Bash   '{"command":"'"'"'git'"'"' add README.md"}'
run 2 "$M" Bash   '{"command":"git -c '"'"'core.pager=cat'"'"' add README.md"}'
run 2 "$M" Bash   '{"command":"(git add README.md)"}'
run 2 "$M" Bash   '{"command":"echo `git add README.md`"}'
run 2 "$M" Bash   '{"command":"echo \"$(git add README.md)\""}'
run 2 "$M" Bash   '{"command":"echo x`git add README.md`"}'
run 2 "$M" Bash   '{"command":"echo x$(git add README.md)"}'
run 2 "$M" Bash   '{"command":"echo \"unterminated"}'
run 2 "$M" Bash   '{"command":"echo hi >"}'
run 2 "$M" Bash   '{"command":"echo hi > README.md"}'
run 2 "$M" Bash   '{"command":"echo hi >> README.md"}'
run 2 "$M" Bash   '{"command":"echo hi &> README.md"}'
run 2 "$M" Bash   '{"command":"echo hi 2> README.md"}'
run 2 "$M" Bash   '{"command":"cat <<EOF > README.md\nhi\nEOF"}'
run 0 "$M" Bash   '{"command":"grep -n \"x>y\" README.md"}'
run 0 "$M" Bash   '{"command":"grep -n '"'"'a;b|c&&d'"'"' README.md"}'
run 0 "$M" Bash   '{"command":"echo \"a > b\" | cat"}'
run 0 "$M" Bash   '{"command":"ls 2>&1 >/dev/null"}'
run 0 "$M" Bash   '{"command":"ls >/tmp/out.txt 2>&1"}'
run 0 "$M" Bash   '{"command":"ls > $TMPDIR/out.txt; cat ${TMPDIR}/out.txt"}'
run 2 "$M" Bash   '{"command":"echo \"$(git rev-parse HEAD)\" | cat"}'
run 0 "$M" Bash   '{"command":"orca worktree create --prompt '"'"'run tests; then git add x'"'"'"}'

# Cycle 2, P2: git remote/tag/branch/stash/worktree/config/submodule check every argument.
run 2 "$M" Bash   '{"command":"git remote -v add up https://example.invalid/r.git"}'
run 2 "$M" Bash   '{"command":"git remote set-url origin x"}'
run 2 "$M" Bash   '{"command":"git remote show --delete origin"}'
run 2 "$M" Bash   '{"command":"git tag --list -a v2 -m x"}'
run 2 "$M" Bash   '{"command":"git branch -a -D wt"}'
run 2 "$M" Bash   '{"command":"git branch --show-current -m renamed"}'
run 2 "$M" Bash   '{"command":"git stash"}'
run 2 "$M" Bash   '{"command":"git stash show --include-untracked"}'
run 2 "$M" Bash   '{"command":"git worktree --porcelain add ../x"}'
run 2 "$M" Bash   '{"command":"git submodule status --init"}'
run 2 "$M" Bash   '{"command":"git config --get --unset user.name"}'
run 2 "$M" Bash   '{"command":"git config --file .gitconfig user.name x"}'
run 0 "$M" Bash   '{"command":"git remote --verbose"}'
run 0 "$M" Bash   '{"command":"git remote show origin"}'
run 0 "$M" Bash   '{"command":"git remote get-url --push origin"}'
run 0 "$M" Bash   '{"command":"git stash show -p stash@{0}"}'
run 0 "$M" Bash   '{"command":"git branch -vv"}'

# Cycle 2, P2: read-only false positives.
run 0 "$M" Bash   '{"command":"git config get user.name"}'
run 0 "$M" Bash   '{"command":"git config --file .gitconfig --get user.name"}'
run 0 "$M" Bash   '{"command":"git config --global --get user.name"}'
run 0 "$M" Bash   '{"command":"git config --system --get core.pager"}'
run 0 "$M" Bash   '{"command":"git config --show-origin --get user.name"}'
run 0 "$M" Bash   '{"command":"git config --show-origin"}'
run 0 "$M" Bash   '{"command":"git config --get-regexp ^user"}'
for sub in "merge-base HEAD main" "rev-list --count HEAD" "rev-parse HEAD" "ls-files" "ls-tree HEAD" \
           "ls-remote origin" "blame README.md" "describe --tags" "name-rev HEAD" "cat-file -p HEAD" \
           "for-each-ref refs/heads" "shortlog -sn" "reflog" "check-ignore x" "status --short" \
           "log --oneline -3" "show HEAD" "diff --stat" "grep -n x" "count-objects -v" \
           "var GIT_EDITOR" "help log" "version"; do
  run 0 "$M" Bash "{\"command\":\"git $sub\"}"
done
run 2 "$M" Bash   '{"command":"git gc"}'
run 2 "$M" Bash   '{"command":"git format-patch -1"}'

# Cycle 2, P3: Bash call with a missing or null command denies with a diagnostic.
raw 2 "Bash without command"  "{\"tool_name\":\"Bash\",\"cwd\":\"$M\",\"tool_input\":{}}"
raw 2 "Bash with null command" "{\"tool_name\":\"Bash\",\"cwd\":\"$M\",\"tool_input\":{\"command\":null}}"
raw 2 "Bash with list command" "{\"tool_name\":\"Bash\",\"cwd\":\"$M\",\"tool_input\":{\"command\":[\"ls\"]}}"

# Plugin wiring: run the exact command from hooks/hooks.json, with the plugin
# Decision 0005: features.orchestrator_guard in .claude/crew64.json,
# read from the MAIN checkout, with env overrides. cfg <dir> <true|false>
# writes the shipped defaults with the guard switch set.
DEFAULTS="$(cd "$(dirname "$0")/../.." && pwd)/config/crew64.defaults.json"
git config --global --add crew64.trustedRoot "$TMP/main"   # decision 0005: only a registered main checkout may govern
cfg() { mkdir -p "$1/.claude"; python3 -I -c '
import json,sys
d=json.load(open(sys.argv[1])); d["features"]["orchestrator_guard"]=(sys.argv[3]=="true")
json.dump(d,open(sys.argv[2],"w"))' "$DEFAULTS" "$1/.claude/crew64.json" "$2"; }
cfg "$M" false
run 0 "$M" Write  '{"file_path":"x.md","content":"hi"}'                      # off by config allows
err="$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"x.md","content":"hi"}}' "$M" | ORCHESTRATOR_GUARD= python3 -I "$HOOK" 2>&1 >/dev/null)"
case "$err" in "orchestrator-guard: off by config"*) echo "ok   off-by-config prints its stderr line";; *) echo "FAIL off-by-config stderr: '$err'"; fail=1;; esac
cfg "$M" true; cfg "$W" false
run 2 "$W" Write  "{\"file_path\":\"$M/x.md\",\"content\":\"hi\"}"             # worktree copy ignored, main copy on
rm -rf "$W/.claude"
printf 'not json' > "$M/.claude/crew64.json"
run 2 "$M" Write  '{"file_path":"x.md","content":"hi"}'                      # malformed → guard on
cfg "$M" false; sed -i 's/"version": 1/"version": 2/' "$M/.claude/crew64.json"
run 2 "$M" Write  '{"file_path":"x.md","content":"hi"}'                      # wrong version → guard on
cfg "$M" false
runenv CREW64_FEATURE_ORCHESTRATOR_GUARD=on  2 "$M" Write '{"file_path":"x.md","content":"hi"}'  # env beats file
rm -f "$M/.claude/crew64.json"
runenv CREW64_FEATURE_ORCHESTRATOR_GUARD=off 0 "$M" Write '{"file_path":"x.md","content":"hi"}'  # env alone turns off
# The new variable beats the legacy alias, in the hook as in crew64_config.
printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"x.md","content":"hi"}}' "$M" \
  | env ORCHESTRATOR_GUARD=off CREW64_FEATURE_ORCHESTRATOR_GUARD=on python3 -I "$HOOK" 2>/dev/null; got=$?
[ "$got" = 2 ] && echo "ok   exit 2  [legacy off + new on] new variable wins" || { echo "FAIL exit $got (want 2) legacy off + new on"; fail=1; }
# A worktree whose commondir has been repointed at a repo INSIDE the worktree
# (planted by a worker) must not be able to switch the guard off: a config root
# that sits strictly inside the hook's cwd is ignored.
cfg "$M" true
git -C "$W" -c user.name=t -c user.email=t@x init -q planted 2>/dev/null; git -C "$W/planted" -c user.name=t -c user.email=t@x commit -q --allow-empty -m p
cfg "$W/planted" false
cp "$M/.git/worktrees/wt/commondir" "$TMP/commondir.bak"; printf '%s\n' "$W/planted/.git" > "$M/.git/worktrees/wt/commondir"
run 2 "$W" Write  "{\"file_path\":\"$M/x.md\",\"content\":\"hi\"}"             # planted config inside cwd ignored
# Codex review of PR 14: the same attack with the root EQUAL to the worktree
# (a bare repo inside the worktree as commondir, config in the worktree root)...
git init -q --bare "$W/fake-common" 2>/dev/null; printf '%s\n' "$W/fake-common" > "$M/.git/worktrees/wt/commondir"
cfg "$W" false
run 2 "$W" Write  "{\"file_path\":\"$M/x.md\",\"content\":\"hi\"}"             # root == worktree: ignored
rm -rf "$W/fake-common" "$W/.claude"
# ...and from a cwd NESTED inside the worktree, with the planted repo beside it.
printf '%s\n' "$W/planted/.git" > "$M/.git/worktrees/wt/commondir"; mkdir -p "$W/nested"
run 2 "$W/nested" Write "{\"file_path\":\"$M/x.md\",\"content\":\"hi\"}"      # planted root inside the worktree: ignored
cp "$TMP/commondir.bak" "$M/.git/worktrees/wt/commondir"; rm -rf "$W/planted" "$W/nested"
# Security review: a worker converts its worktree into a standalone repo (rm the
# .git file, git init in place) so git_dir == common_dir there. Its config must
# not govern, because that root is not registered in the global git config.
W3="$TMP/wt3"; git -C "$M" worktree add -q "$W3" -b wt3; rm -f "$W3/.git"; git -C "$W3" -c user.name=t -c user.email=t@x init -q; git -C "$W3" -c user.name=t -c user.email=t@x commit -q --allow-empty -m c
cfg "$W3" false
run 2 "$W3" Write  "{\"file_path\":\"$M/x.md\",\"content\":\"hi\"}"           # converted worktree: not a trusted root
# Codex cycle 2: the worker writes "." into its own admin commondir (plus
# objects/ and refs/) so git reports git_dir == common_dir for the worktree.
# The worktree toplevel is not a registered root, so its config is ignored.
W4="$TMP/wt4"; git -C "$M" worktree add -q "$W4" -b wt4
ADMIN="$(git -C "$W4" rev-parse --absolute-git-dir)"; mkdir -p "$ADMIN/objects" "$ADMIN/refs"
cp "$ADMIN/commondir" "$TMP/commondir4.bak"; printf '.\n' > "$ADMIN/commondir"
cfg "$W4" false
run 2 "$W4" Write  "{\"file_path\":\"$M/x.md\",\"content\":\"hi\"}"           # commondir=. masquerade: ignored
cp "$TMP/commondir4.bak" "$ADMIN/commondir"
# An unregistered real main checkout is not trusted either: guard stays on.
M2="$TMP/main2"; git init -q "$M2" && git -C "$M2" -c user.name=t -c user.email=t@x commit -q --allow-empty -m init
cfg "$M2" false
run 2 "$M2" Write  '{"file_path":"x.md","content":"hi"}'                      # unregistered main: guard on
git config --global --add crew64.trustedRoot "$M2"
run 0 "$M2" Write  '{"file_path":"x.md","content":"hi"}'                      # registered: switch honoured
# A hook that cannot import crew64_config must still deny (never crash open).
mkdir -p "$TMP/alone/hooks" && cp "$HOOK" "$TMP/alone/hooks/orchestrator-guard.py"
printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"x.md","content":"hi"}}' "$M" \
  | ORCHESTRATOR_GUARD= python3 -I "$TMP/alone/hooks/orchestrator-guard.py" 2>/dev/null; got=$?
[ "$got" = 2 ] && echo "ok   exit 2  hook without crew64_config denies" || { echo "FAIL exit $got (want 2) hook without crew64_config"; fail=1; }

# root variable set the way Claude Code sets it, in the main checkout.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_CMD="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["PreToolUse"][0]["hooks"][0]["command"])' "$ROOT/hooks/hooks.json")"
err="$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"x.md","content":"hi"}}' "$M" \
  | CLAUDE_PLUGIN_ROOT="$ROOT" ORCHESTRATOR_GUARD= bash -c "$PLUGIN_CMD" 2>&1 >/dev/null)"; got=$?
# A missing script also exits 2 with stderr, so require the guard's own message.
if [ "$got" = 2 ] && [ -n "$err" ] && case "$err" in "orchestrator-guard: denied"*) true;; *) false;; esac; then echo "ok   exit $got  plugin hooks.json command denies Write in main checkout"
else echo "FAIL exit $got (want 2, stderr '$err')  plugin hooks.json command"; fail=1; fi

printf '{"tool_name":"Write","cwd":"%s","tool_input":{}}' "$M" | ORCHESTRATOR_GUARD=off python3 -I "$HOOK" 2>/dev/null \
  && echo "ok   override ORCHESTRATOR_GUARD=off allows" || { echo "FAIL override"; fail=1; }
exit $fail
