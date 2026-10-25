#!/usr/bin/env bash
# Unit test for tools/hooks/orchestrator-guard.py. Runs the hook against a
# throwaway repo (main checkout) and two worktrees of it, one with a space in
# its path. Exit 0 = all pass.
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/orchestrator-guard.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
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
run 0 "$M" Bash   '{"command":"room-cli thread spawn --parent-self --prompt x"}'
run 0 "$M" Bash   '{"command":"ls > /dev/null; grep -r x . 2>/dev/null"}'
run 0 "$M" Read   '{"file_path":"x.md"}'
run 0 "$W" Write  '{"file_path":"x.md","content":"hi"}'
run 0 "$W" Bash   '{"command":"git commit -m x"}'
run 0 "$W" Bash   '{"command":"cat > docs/x.md <<EOF\nhi\nEOF"}'

# P1: worktree writes must stay inside the worktree.
run 0 "$W" Write  "{\"file_path\":\"$W/docs/new.md\",\"content\":\"hi\"}"
run 2 "$W" Write  "{\"file_path\":\"$M/x.md\",\"content\":\"hi\"}"
run 2 "$W" Edit   '{"file_path":"../main/AGENTS.md","old_string":"a","new_string":"b"}'
run 2 "$W" MultiEdit '{"file_path":"/tmp/outside.md","edits":[]}'
run 2 "$W" NotebookEdit '{"notebook_path":"../main/n.ipynb","new_source":"x"}'
run 2 "$W" Write  '{"content":"no path"}'

# P1: room-cli exemption only for a single plain invocation.
run 2 "$M" Bash   '{"command":"room-cli --version; git add README.md"}'
run 2 "$M" Bash   '{"command":"room-cli --version && git commit -m x"}'
run 2 "$M" Bash   '{"command":"room-cli status | tee out.txt"}'
run 2 "$M" Bash   '{"command":"room-cli status $(git add README.md)"}'
run 0 "$M" Bash   '{"command":"room-cli status --json"}'

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
run 2 "$M" Bash   '{"command":"room-cli --version&git add README.md"}'
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
run 0 "$M" Bash   '{"command":"room-cli thread spawn --prompt '"'"'run tests; then git add x'"'"'"}'

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
