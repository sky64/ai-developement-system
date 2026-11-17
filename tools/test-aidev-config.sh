#!/usr/bin/env bash
# Unit test for tools/aidev_config.py: the single reader of
# .claude/ai-dev-system.json. Runs against a throwaway repo and a worktree.
# Exit 0 = all pass.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD="$ROOT/tools/aidev_config.py"
DEFAULTS="$ROOT/config/ai-dev-system.defaults.json"
EXAMPLE="$ROOT/config/examples/orca-solvela.json"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
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
d=json.load(open(sys.argv[1])); d["features"][sys.argv[3]]=json.loads(sys.argv[2]); json.dump(d,open(sys.argv[4],"w"))' "$DEFAULTS" "$1" "$2" "$M/.claude/ai-dev-system.json"; }

# 1. status without a config: defaults, config=none
out="$(run "$M" status)"
case "$out" in *"config=none guard=on ladder=on bot=off metering=none"*) ok "status without config shows defaults";; *) bad "status without config: $out";; esac

# 2. get with no config falls back to the default
out="$(run "$M" get features.model_ladder)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "true" ] && ok "get features.model_ladder without config → true" || bad "get without config: rc=$rc out=$out"

# 3. status from a worktree names the main checkout's file
mkdir -p "$M/.claude" && cp "$DEFAULTS" "$M/.claude/ai-dev-system.json" 2>/dev/null
out="$(run "$W" status)"
case "$out" in *"config=$M/.claude/ai-dev-system.json"*) ok "status from worktree reads main checkout";; *) bad "status from worktree: $out";; esac

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
out="$(cd "$M" && AI_DEV_SYSTEM_FEATURE_MODEL_LADDER=off python3 -I "$MOD" get features.model_ladder 2>&1)"
[ "$out" = "false" ] && ok "AI_DEV_SYSTEM_FEATURE_MODEL_LADDER=off → false" || bad "env override: $out"

# 8. ORCHESTRATOR_GUARD=off alias
out="$(cd "$M" && ORCHESTRATOR_GUARD=off python3 -I "$MOD" get features.orchestrator_guard 2>&1)"
[ "$out" = "false" ] && ok "ORCHESTRATOR_GUARD=off → orchestrator_guard false" || bad "guard alias: $out"

# 9. deviation from defaults is reported
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); d["models"]["research"][2]="claude-haiku-5-5"; json.dump(d,open(sys.argv[2],"w"))' "$DEFAULTS" "$M/.claude/ai-dev-system.json" 2>/dev/null
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

# 12. an unknown metering kind falls back to none; env overrides do not apply to metering
setfeat '"bogus"' metering
out="$(run "$M" get features.metering)"; [ "$out" = "none" ] && ok "features.metering bogus → none" || bad "bogus metering: $out"
out="$(cd "$M" && AI_DEV_SYSTEM_FEATURE_METERING=off python3 -I "$MOD" status 2>&1)"
case "$out" in *"metering=none"*) ok "env override ignored for metering";; *) bad "metering env: $out";; esac

exit $fail
