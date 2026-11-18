#!/usr/bin/env bash
# Unit test for tools/crew64_config.py: the single reader of
# .claude/crew64.json. Runs against a throwaway repo and a worktree.
# Exit 0 = all pass.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD="$ROOT/tools/crew64_config.py"
DEFAULTS="$ROOT/config/crew64.defaults.json"
EXAMPLE="$ROOT/config/examples/orca-solvela.json"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"; : > "$GIT_CONFIG_GLOBAL"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@x GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@x
git config --global --add crew64.trustedRoot "$TMP/main"
git -C "$TMP" init -q main && git -C "$TMP/main" commit -q --allow-empty -m init
git -C "$TMP/main" worktree add -q "$TMP/wt" -b wt
M="$TMP/main"; W="$TMP/wt"
fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }
run()  { (cd "$1" && shift && python3 -I "$MOD" "$@" 2>&1); }
setfeat() { # <value-json> <feature> : write defaults with features.<feature> = value
  mkdir -p "$M/.claude"; python3 -I -c '
import json,sys
d=json.load(open(sys.argv[1])); d["features"][sys.argv[3]]=json.loads(sys.argv[2]); json.dump(d,open(sys.argv[4],"w"))' "$DEFAULTS" "$1" "$2" "$M/.claude/crew64.json"; }

# 1. status without a config: defaults, config=none
out="$(run "$M" status)"
case "$out" in *"config=none guard=on ladder=on bot=off metering=none"*) ok "status without config shows defaults";; *) bad "status without config: $out";; esac

# 2. get with no config falls back to the default
out="$(run "$M" get features.model_ladder)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "true" ] && ok "get features.model_ladder without config → true" || bad "get without config: rc=$rc out=$out"

# 3. status from a worktree names the main checkout's file
mkdir -p "$M/.claude" && cp "$DEFAULTS" "$M/.claude/crew64.json" 2>/dev/null
out="$(run "$W" status)"
case "$out" in *"config=$M/.claude/crew64.json"*) ok "status from worktree reads main checkout";; *) bad "status from worktree: $out";; esac

# 4. check accepts the shipped defaults
out="$(run "$M" check "$DEFAULTS")"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "check defaults → exit 0, silent" || bad "check defaults: rc=$rc out=$out"

# 5. wrong version
sed 's/"version": 1/"version": 2/' "$DEFAULTS" > "$TMP/v2.json" 2>/dev/null
out="$(run "$M" check "$TMP/v2.json")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *version*) true;; *) false;; esac && ok "check version 2 → exit 1 names version" || bad "check v2: rc=$rc out=$out"

# 6. missing features block
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); d.pop("features",None); json.dump(d,open(sys.argv[2],"w"))' "$DEFAULTS" "$TMP/nofeat.json" 2>/dev/null
out="$(run "$M" check "$TMP/nofeat.json")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *features*) true;; *) false;; esac && ok "check without features → exit 1 names features" || bad "check nofeat: rc=$rc out=$out"

# 7. env override beats the file
out="$(cd "$M" && CREW64_FEATURE_MODEL_LADDER=off python3 -I "$MOD" get features.model_ladder 2>&1)"
[ "$out" = "false" ] && ok "CREW64_FEATURE_MODEL_LADDER=off → false" || bad "env override: $out"

# 8. ORCHESTRATOR_GUARD=off alias
out="$(cd "$M" && ORCHESTRATOR_GUARD=off python3 -I "$MOD" get features.orchestrator_guard 2>&1)"
[ "$out" = "false" ] && ok "ORCHESTRATOR_GUARD=off → orchestrator_guard false" || bad "guard alias: $out"

# 9. deviation from defaults is reported
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); d["models"]["research"][2]="claude-haiku-5-5"; json.dump(d,open(sys.argv[2],"w"))' "$DEFAULTS" "$M/.claude/crew64.json" 2>/dev/null
out="$(run "$M" status)"
case "$out" in *"models=deviates: models.research"*) ok "status reports models deviation";; *) bad "deviation: $out";; esac

# 10. the example config validates
out="$(run "$M" check "$EXAMPLE")"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "check example → exit 0, silent" || bad "check example: rc=$rc out=$out"

# 11. a non-boolean switch value falls back to the default (never reported as off)
setfeat '"off"' orchestrator_guard
out="$(run "$M" get features.orchestrator_guard)"; [ "$out" = "true" ] && ok 'features.orchestrator_guard "off" (string) → default true' || bad "string switch: $out"
out="$(run "$M" status)"; case "$out" in *"guard=on"*) ok "status shows guard=on for a string switch value";; *) bad "status string switch: $out";; esac
setfeat '0' model_ladder
out="$(run "$M" get features.model_ladder)"; [ "$out" = "true" ] && ok "features.model_ladder 0 → default true" || bad "numeric switch: $out"

# 13. the CLI applies the same trusted-root rule as the hook: a planted repo
# inside the worktree, pointed at by commondir, is not a config source.
cp "$DEFAULTS" "$M/.claude/crew64.json"
git -C "$W" -c user.name=t -c user.email=t@x init -q planted 2>/dev/null; git -C "$W/planted" -c user.name=t -c user.email=t@x commit -q --allow-empty -m p
mkdir -p "$W/planted/.claude"; python3 -I -c '
import json,sys; d=json.load(open(sys.argv[1])); d["features"]["orchestrator_guard"]=False; json.dump(d,open(sys.argv[2],"w"))' "$DEFAULTS" "$W/planted/.claude/crew64.json"
cp "$M/.git/worktrees/wt/commondir" "$TMP/commondir.bak"; printf '%s\n' "$W/planted/.git" > "$M/.git/worktrees/wt/commondir"
out="$(run "$W" status)"
case "$out" in *"config=none guard=on"*) ok "status ignores a planted config root inside the worktree";; *) bad "planted status: $out";; esac
out="$(run "$W" get features.orchestrator_guard)"; [ "$out" = "true" ] && ok "get ignores the planted root too" || bad "planted get: $out"
cp "$TMP/commondir.bak" "$M/.git/worktrees/wt/commondir"; rm -rf "$W/planted"
out="$(run "$W" status)"
case "$out" in *"config=$M/.claude/crew64.json"*) ok "status reads the real main checkout again once commondir is restored";; *) bad "restored status: $out";; esac

# 14. a config at an unregistered root is reported as untrusted and not applied
M3="$TMP/main3"; git init -q "$M3" && git -C "$M3" -c user.name=t -c user.email=t@x commit -q --allow-empty -m init
mkdir -p "$M3/.claude"; python3 -I -c '
import json,sys; d=json.load(open(sys.argv[1])); d["features"]["orchestrator_guard"]=False; json.dump(d,open(sys.argv[2],"w"))' "$DEFAULTS" "$M3/.claude/crew64.json"
out="$(run "$M3" status)"
case "$out" in *"config=untrusted:$M3/.claude/crew64.json guard=on"*) ok "status marks a config at an unregistered root untrusted and keeps defaults";; *) bad "untrusted status: $out";; esac

# 12. an unknown metering kind falls back to none; env overrides do not apply to metering
setfeat '"bogus"' metering
out="$(run "$M" get features.metering)"; [ "$out" = "none" ] && ok "features.metering bogus → none" || bad "bogus metering: $out"
out="$(cd "$M" && CREW64_FEATURE_METERING=off python3 -I "$MOD" status 2>&1)"
case "$out" in *"metering=none"*) ok "env override ignored for metering";; *) bad "metering env: $out";; esac

# 15-20. limits.review_cycles (decision 0007)
setlimit() { # <value-json|absent|empty> : write defaults with limits.review_cycles = value
  mkdir -p "$M/.claude"; python3 -I -c '
import json,sys
d=json.load(open(sys.argv[1]))
if sys.argv[2]=="absent": d.pop("limits",None)
elif sys.argv[2]=="empty": d["limits"]={}
else: d["limits"]={"review_cycles": json.loads(sys.argv[2])}
json.dump(d,open(sys.argv[3],"w"))' "$DEFAULTS" "$1" "$M/.claude/crew64.json"; }
getlim() { (cd "$M" && python3 -I "$MOD" get limits.review_cycles 2>&1); }

# 15. no limits block: default 2, status shows it after build_map, check passes
setlimit absent
out="$(getlim)"; [ "$out" = "2" ] && ok "get limits.review_cycles without limits → 2" || bad "no limits get: $out"
out="$(run "$M" status)"; case "$out" in *"build_map=off review_cycles=2"*) ok "status shows review_cycles=2 after build_map";; *) bad "no limits status: $out";; esac
out="$(run "$M" check "$M/.claude/crew64.json")"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "check without limits → exit 0, silent" || bad "check no limits: rc=$rc out=$out"

# 16. a file value is read
setlimit 3
out="$(getlim)"; [ "$out" = "3" ] && ok "limits.review_cycles 3 → 3" || bad "file value: $out"
out="$(run "$M" status)"; case "$out" in *"review_cycles=3"*) ok "status shows review_cycles=3";; *) bad "file status: $out";; esac

# 17. wrong types and zero fall back to the default; check names the key
for v in true 0 2.0 '"3"'; do
  setlimit "$v"; out="$(getlim)"; [ "$out" = "2" ] && ok "limits.review_cycles $v → default 2" || bad "bad value $v: $out"
done
setlimit true
out="$(run "$M" check "$M/.claude/crew64.json")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"limits.review_cycles"*) true;; *) false;; esac && ok "check review_cycles true → exit 1 names limits.review_cycles" || bad "check true: rc=$rc out=$out"

# 18. an empty limits block: default, and check names the key
setlimit empty
out="$(getlim)"; [ "$out" = "2" ] && ok "empty limits → default 2" || bad "empty limits get: $out"
out="$(run "$M" check "$M/.claude/crew64.json")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"limits.review_cycles"*) true;; *) false;; esac && ok "check empty limits → exit 1 names limits.review_cycles" || bad "check empty: rc=$rc out=$out"

# 19. env override beats the file only when it is a positive integer
setlimit 3
out="$(cd "$M" && CREW64_LIMIT_REVIEW_CYCLES=5 python3 -I "$MOD" get limits.review_cycles 2>&1)"
[ "$out" = "5" ] && ok "CREW64_LIMIT_REVIEW_CYCLES=5 → 5" || bad "env 5: $out"
for v in 0 -1 abc 2.5; do
  out="$(cd "$M" && CREW64_LIMIT_REVIEW_CYCLES="$v" python3 -I "$MOD" get limits.review_cycles 2>&1)"
  [ "$out" = "3" ] && ok "CREW64_LIMIT_REVIEW_CYCLES=$v → file value 3" || bad "env $v: $out"
done

# 20. an untrusted root's limit is not applied; unknown limit names exit 1
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); d["limits"]={"review_cycles": 9}; json.dump(d,open(sys.argv[2],"w"))' "$DEFAULTS" "$M3/.claude/crew64.json"
out="$(run "$M3" status)"
case "$out" in *"config=untrusted:"*"review_cycles=2"*) ok "untrusted root keeps review_cycles=2";; *) bad "untrusted limit: $out";; esac
out="$(cd "$M" && python3 -I "$MOD" get limits.bogus 2>&1)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"unknown limit"*) true;; *) false;; esac && ok "get limits.bogus → exit 1 unknown limit" || bad "bogus limit: rc=$rc out=$out"

# 21-22. features.scout64 (decision 0008): default true, optional in validation
dropfeat() { # <feature> : write defaults with features.<feature> removed
  mkdir -p "$M/.claude"; python3 -I -c '
import json,sys
d=json.load(open(sys.argv[1])); d["features"].pop(sys.argv[2],None); json.dump(d,open(sys.argv[3],"w"))' "$DEFAULTS" "$1" "$M/.claude/crew64.json"; }

# 21. no scout64 key (every repo enabled before 0.7.0): reads as true, status
# shows it after review_cycles, check passes; a file value and the env override are read
dropfeat scout64
out="$(run "$M" get features.scout64)"; [ "$out" = "true" ] && ok "get features.scout64 without the key → true" || bad "scout64 absent get: $out"
out="$(run "$M" status)"; case "$out" in *"review_cycles=2 scout64=on"*) ok "status shows scout64=on after review_cycles";; *) bad "scout64 absent status: $out";; esac
out="$(run "$M" check "$M/.claude/crew64.json")"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "check without features.scout64 → exit 0, silent" || bad "check scout64 absent: rc=$rc out=$out"
setfeat 'false' scout64
out="$(run "$M" get features.scout64)"; [ "$out" = "false" ] && ok "features.scout64 false → false" || bad "scout64 false get: $out"
out="$(run "$M" status)"; case "$out" in *"scout64=off"*) ok "status shows scout64=off";; *) bad "scout64 false status: $out";; esac
setfeat 'true' scout64
out="$(cd "$M" && CREW64_FEATURE_SCOUT64=off python3 -I "$MOD" get features.scout64 2>&1)"
[ "$out" = "false" ] && ok "CREW64_FEATURE_SCOUT64=off beats a file true → false" || bad "scout64 env: $out"

# 22. a non-boolean value reads as the default true and check names the key;
# the shipped example validates
setfeat '"off"' scout64
out="$(run "$M" get features.scout64)"; [ "$out" = "true" ] && ok 'features.scout64 "off" (string) → default true' || bad "scout64 string get: $out"
out="$(run "$M" status)"; case "$out" in *"scout64=on"*) ok "status shows scout64=on for a string value";; *) bad "scout64 string status: $out";; esac
out="$(run "$M" check "$M/.claude/crew64.json")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"features.scout64"*) true;; *) false;; esac && ok "check scout64 string → exit 1 names features.scout64" || bad "check scout64 string: rc=$rc out=$out"
out="$(run "$M" check "$EXAMPLE")"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "check example with scout64 → exit 0, silent" || bad "check example scout64: rc=$rc out=$out"

# 23-25. the process ladder (decision 0009): process.* and features.process_ladder
setproc() { # <json-object|absent> [process_ladder json] : write defaults with process replaced or removed
  mkdir -p "$M/.claude"; python3 -I -c '
import json,sys
d=json.load(open(sys.argv[1]))
if sys.argv[2]=="absent": d.pop("process",None)
else: d["process"]=json.loads(sys.argv[2])
if len(sys.argv)>4: d["features"]["process_ladder"]=json.loads(sys.argv[4])
json.dump(d,open(sys.argv[3],"w"))' "$DEFAULTS" "$1" "$M/.claude/crew64.json" ${2+"$2"}; }
getproc() { (cd "$M" && python3 -I "$MOD" get "process.$1" 2>&1); }
envproc() { (cd "$M" && CREW64_PROCESS_MODE="$1" python3 -I "$MOD" get process.default_mode 2>&1); }

# 23. no process block: the defaults, status shows them after scout64, check passes
setproc absent
out="$(getproc default_mode)"; [ "$out" = "auto" ] && ok "get process.default_mode without process → auto" || bad "no process mode: $out"
out="$(getproc native_max_files)"; [ "$out" = "3" ] && ok "get process.native_max_files without process → 3" || bad "no process files: $out"
out="$(getproc native_max_tool_calls)"; [ "$out" = "40" ] && ok "get process.native_max_tool_calls without process → 40" || bad "no process calls: $out"
out="$(run "$M" status)"; case "$out" in *"scout64=on process=auto max_files=3 max_calls=40 platform="*) ok "status shows process=auto max_files=3 max_calls=40 after scout64";; *) bad "no process status: $out";; esac
out="$(run "$M" check "$M/.claude/crew64.json")"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "check without process → exit 0, silent" || bad "check no process: rc=$rc out=$out"
dropfeat process_ladder
out="$(run "$M" get features.process_ladder)"; [ "$out" = "true" ] && ok "get features.process_ladder without the key → true" || bad "process_ladder absent get: $out"
out="$(run "$M" check "$M/.claude/crew64.json")"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "check without features.process_ladder → exit 0, silent" || bad "check process_ladder absent: rc=$rc out=$out"
out="$(run "$M" check "$DEFAULTS")"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "check defaults with process → exit 0, silent" || bad "check defaults process: rc=$rc out=$out"
out="$(run "$M" check "$EXAMPLE")"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "check example with process → exit 0, silent" || bad "check example process: rc=$rc out=$out"

# 24. file values are read; CREW64_PROCESS_MODE beats the file only when it names a mode
setproc '{"default_mode":"native","native_max_files":5,"native_max_tool_calls":10}'
out="$(getproc default_mode)"; [ "$out" = "native" ] && ok "process.default_mode native → native" || bad "file mode: $out"
out="$(getproc native_max_files)"; [ "$out" = "5" ] && ok "process.native_max_files 5 → 5" || bad "file files: $out"
out="$(getproc native_max_tool_calls)"; [ "$out" = "10" ] && ok "process.native_max_tool_calls 10 → 10" || bad "file calls: $out"
out="$(run "$M" status)"; case "$out" in *"process=native max_files=5 max_calls=10"*) ok "status shows the file's process values";; *) bad "file process status: $out";; esac
out="$(envproc delegated)"; [ "$out" = "delegated" ] && ok "CREW64_PROCESS_MODE=delegated → delegated" || bad "env delegated: $out"
out="$(envproc 'NATIVE ')"; [ "$out" = "native" ] && ok "CREW64_PROCESS_MODE='NATIVE ' → native (stripped, lower-cased)" || bad "env NATIVE: $out"
out="$(cd "$M" && CREW64_PROCESS_MODE=' Auto' python3 -I "$MOD" status 2>&1)"; case "$out" in *"process=auto max_files=5"*) ok "status applies CREW64_PROCESS_MODE";; *) bad "env status: $out";; esac
for v in bogus '' ' ' 'native,delegated' 'off'; do
  out="$(envproc "$v")"; [ "$out" = "native" ] && ok "CREW64_PROCESS_MODE='$v' → file value native" || bad "env '$v': $out"
done
setproc absent
out="$(envproc native)"; [ "$out" = "native" ] && ok "CREW64_PROCESS_MODE=native without a process block → native" || bad "env no block: $out"

# 25. invalid values read as the defaults and check names the key
setproc '{"default_mode":"sometimes","native_max_files":3,"native_max_tool_calls":40}'
out="$(getproc default_mode)"; [ "$out" = "auto" ] && ok 'process.default_mode "sometimes" → default auto' || bad "bad mode: $out"
out="$(run "$M" check "$M/.claude/crew64.json")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"process.default_mode"*) true;; *) false;; esac && ok "check bad mode → exit 1 names process.default_mode" || bad "check bad mode: rc=$rc out=$out"
for v in 0 true -2 2.0 '"3"' null; do
  setproc "{\"default_mode\":\"auto\",\"native_max_files\":$v,\"native_max_tool_calls\":40}"
  out="$(getproc native_max_files)"; [ "$out" = "3" ] && ok "process.native_max_files $v → default 3" || bad "bad files $v: $out"
  out="$(run "$M" check "$M/.claude/crew64.json")"; rc=$?
  [ "$rc" = 1 ] && case "$out" in *"process.native_max_files"*) true;; *) false;; esac && ok "check native_max_files $v → exit 1 names the key" || bad "check files $v: rc=$rc out=$out"
done
setproc '{"default_mode":"auto","native_max_files":3,"native_max_tool_calls":0}'
out="$(getproc native_max_tool_calls)"; [ "$out" = "40" ] && ok "process.native_max_tool_calls 0 → default 40" || bad "bad calls: $out"
out="$(run "$M" check "$M/.claude/crew64.json")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"process.native_max_tool_calls"*) true;; *) false;; esac && ok "check native_max_tool_calls 0 → exit 1 names the key" || bad "check calls: rc=$rc out=$out"
for v in '[]' '"native"' 'null' '7'; do
  setproc "$v"
  out="$(getproc default_mode)$(getproc native_max_files)$(getproc native_max_tool_calls)"; [ "$out" = "auto340" ] && ok "process $v (not an object) → the defaults" || bad "non-object $v: $out"
  out="$(run "$M" status)"; case "$out" in *"process=auto max_files=3 max_calls=40"*) ok "status with process $v shows the defaults";; *) bad "non-object status $v: $out";; esac
  out="$(run "$M" check "$M/.claude/crew64.json")"; rc=$?
  [ "$rc" = 1 ] && case "$out" in *"process must be an object"*) true;; *) false;; esac && ok "check process $v → exit 1 process must be an object" || bad "check non-object $v: rc=$rc out=$out"
done
setproc '{}'
out="$(getproc default_mode)$(getproc native_max_files)"; [ "$out" = "auto3" ] && ok "empty process block → the defaults" || bad "empty process: $out"
out="$(run "$M" check "$M/.claude/crew64.json")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"process.default_mode"*"process.native_max_files"*"process.native_max_tool_calls"*) true;; *) false;; esac && ok "check empty process → exit 1 names all three keys" || bad "check empty process: rc=$rc out=$out"
# the switch off: status says so, the configured mode is still readable
setproc '{"default_mode":"native","native_max_files":5,"native_max_tool_calls":10}' false
out="$(run "$M" status)"; case "$out" in *"scout64=on process=off platform="*) ok "features.process_ladder false → status shows process=off";; *) bad "ladder off status: $out";; esac
out="$(getproc default_mode)"; [ "$out" = "native" ] && ok "get process.default_mode with the switch off → the configured mode" || bad "ladder off get: $out"
out="$(cd "$M" && CREW64_FEATURE_PROCESS_LADDER=on python3 -I "$MOD" status 2>&1)"; case "$out" in *"process=native max_files=5 max_calls=10"*) ok "CREW64_FEATURE_PROCESS_LADDER=on beats a file false";; *) bad "ladder env on: $out";; esac
out="$(getproc bogus)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"unknown process key"*) true;; *) false;; esac && ok "get process.bogus → exit 1 unknown process key" || bad "bogus process key: rc=$rc out=$out"
# an untrusted root's process block is not applied
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); d["process"]={"default_mode":"native","native_max_files":9,"native_max_tool_calls":9}; json.dump(d,open(sys.argv[2],"w"))' "$DEFAULTS" "$M3/.claude/crew64.json"
out="$(run "$M3" status)"
case "$out" in *"config=untrusted:"*"process=auto max_files=3 max_calls=40"*) ok "untrusted root keeps the default process values";; *) bad "untrusted process: $out";; esac

exit $fail
