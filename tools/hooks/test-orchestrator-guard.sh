#!/usr/bin/env bash
# Unit test for tools/hooks/orchestrator-guard.py. Runs the hook against a
# throwaway repo (main checkout) and a worktree of it. Exit 0 = all pass.
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/orchestrator-guard.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q main && git -C "$TMP/main" commit -q --allow-empty -m init
git -C "$TMP/main" worktree add -q "$TMP/wt" -b wt
fail=0
run() { # expected_exit cwd tool json_input
  local exp="$1" cwd="$2" tool="$3" input="$4"
  printf '{"tool_name":"%s","cwd":"%s","tool_input":%s}' "$tool" "$cwd" "$input" \
    | ORCHESTRATOR_GUARD= python3 -I "$HOOK" 2>/dev/null; local got=$?
  if [ "$got" = "$exp" ]; then echo "ok   exit $got  $tool $(echo "$input" | cut -c1-60)"
  else echo "FAIL exit $got (want $exp)  cwd=$cwd $tool $input"; fail=1; fi
}
M="$TMP/main"; W="$TMP/wt"
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
printf '{"tool_name":"Write","cwd":"%s","tool_input":{}}' "$M" | ORCHESTRATOR_GUARD=off python3 -I "$HOOK" 2>/dev/null \
  && echo "ok   override ORCHESTRATOR_GUARD=off allows" || { echo "FAIL override"; fail=1; }
exit $fail
