#!/usr/bin/env bash
# Enable the ai-dev-system plugin in a repository, write its config, and register it with Orca.
# usage: harness-enable.sh [/path/to/repo] [--config <prepared ai-dev-system.json>] [--no-commit]
#
# Run by path from a human or unharnessed session (the orchestrator guard
# would deny its writes). Steps: merge the plugin into .claude/settings.json;
# write .claude/ai-dev-system.json from config/ai-dev-system.defaults.json or
# from --config (validated first; an existing file is never overwritten); add
# the orchestrator line to CLAUDE.md; register the repo with Orca and set its
# base ref; commit the three files unless --no-commit. Idempotent.
set -euo pipefail

plugin_root="$(cd "$(dirname "$0")/.." && pwd)"
defaults="$plugin_root/config/ai-dev-system.defaults.json"
reader="$plugin_root/tools/aidev_config.py"

repo="."; commit=1; config_src=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-commit) commit=0; shift ;;
    --config) config_src="${2:-}"; [ -n "$config_src" ] || { echo "harness-enable: --config needs a path" >&2; exit 2; }; shift 2 ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    -*) echo "harness-enable: unknown option $1" >&2; exit 2 ;;
    *) repo="$1"; shift ;;
  esac
done
repo="$(cd "$repo" && pwd)"
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "harness-enable: not a git repository: $repo" >&2; exit 1; }
echo "target: $repo"

# 0. Validate a prepared config before touching anything.
if [ -n "$config_src" ]; then
  config_src="$(cd "$(dirname "$config_src")" && pwd)/$(basename "$config_src")"
  if ! problems="$(python3 -I "$reader" check "$config_src")"; then
    echo "harness-enable: --config failed check:" >&2
    printf '%s\n' "$problems" >&2
    exit 1
  fi
fi

if [ -n "${ORCA_CLI_COMMAND:-}" ]; then orca_bin="$ORCA_CLI_COMMAND"
elif [ -n "${ORCA_TERMINAL_HANDLE:-}" ]; then orca_bin="orca"
else orca_bin="orca-ide"; fi

# 1. settings.json merge
mkdir -p "$repo/.claude"
python3 -I - "$repo/.claude/settings.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text()) if p.exists() and p.read_text().strip() else {}
if not isinstance(d, dict):
    sys.exit("settings.json is not a JSON object")
before = json.dumps(d, sort_keys=True)
d.setdefault("extraKnownMarketplaces", {})["ai-dev-system"] = {
    "source": {"source": "github", "repo": "sky64/ai-developement-system"}}
d.setdefault("enabledPlugins", {})["ai-dev-system@ai-dev-system"] = True
if json.dumps(d, sort_keys=True) == before:
    print("settings: plugin already enabled in .claude/settings.json, left unchanged")
else:
    p.write_text(json.dumps(d, indent=2) + "\n")
    print("settings: plugin enabled in .claude/settings.json")
PY

# 1b. per-repo config (decision 0005)
config_dst="$repo/.claude/ai-dev-system.json"
if [ -e "$config_dst" ]; then
  echo "config: already present, left unchanged ($config_dst)"
elif [ -n "$config_src" ]; then
  cp "$config_src" "$config_dst"; echo "config: written from $config_src"
else
  cp "$defaults" "$config_dst"; echo "config: written from defaults"
fi

# 2. CLAUDE.md orchestrator line
line='If you were started as the project orchestrator and were not assigned a specific implementer or reviewer role in your prompt, invoke the ai-dev-system:orchestrator skill at session start. A session whose prompt assigns it a worker role (implementer, reviewer) keeps that role and does not invoke the skill. The orchestrator does not write or commit.'
if [ -f "$repo/CLAUDE.md" ] && grep -qF "ai-dev-system:orchestrator" "$repo/CLAUDE.md"; then
  echo "CLAUDE.md: orchestrator line already present"
else
  { [ -f "$repo/CLAUDE.md" ] && [ -s "$repo/CLAUDE.md" ] && printf '\n'; printf '%s\n' "$line"; } >> "$repo/CLAUDE.md"
  echo "CLAUDE.md: orchestrator line added"
fi

# 3. Orca registration and base ref
if timeout 20 "$orca_bin" repo show --repo "path:$repo" --json >/dev/null 2>&1; then
  echo "orca: repo already registered"
else
  timeout 30 "$orca_bin" repo add --path "$repo" --json >/dev/null && echo "orca: repo registered"
fi
default_ref="$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
if [ -n "$default_ref" ]; then
  timeout 20 "$orca_bin" repo set-base-ref --repo "path:$repo" --ref "$default_ref" --json >/dev/null && echo "orca: base ref set to $default_ref"
else
  echo "orca: no origin/HEAD; base ref left at Orca's default"
fi

# 4. Commit
files=(.claude/settings.json .claude/ai-dev-system.json CLAUDE.md)
git -C "$repo" add "${files[@]}"
if [ "$commit" = 1 ]; then
  if git -C "$repo" diff --cached --quiet -- "${files[@]}"; then echo "commit: nothing to commit"
  else ORCHESTRATOR_GUARD=off git -C "$repo" commit -q -m "chore: enable ai-dev-system plugin" -- "${files[@]}" && echo "commit: $(git -C "$repo" rev-parse --short HEAD) chore: enable ai-dev-system plugin"; fi
else
  echo "commit: skipped (--no-commit); files are staged"
fi
echo
echo "The plugin applies once this folder is trusted in Claude Code. Edit .claude/ai-dev-system.json to turn features on or off (docs/05-delegation.md). Orca's per-repo setup script is a UI setting; check it before creating worktrees with setup enabled."
