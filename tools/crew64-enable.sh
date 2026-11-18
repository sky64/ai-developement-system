#!/usr/bin/env bash
# Enable the crew64 plugin in a repository, write its config, and register it with Orca.
# usage: crew64-enable.sh [/path/to/repo] [--config <prepared crew64.json>] [--no-commit]
#
# Run by path from a human or unharnessed session (the orchestrator guard
# would deny its writes). Steps: merge the plugin into .claude/settings.json;
# write .claude/crew64.json from config/crew64.defaults.json or
# from --config (validated first; an existing file is never overwritten); add
# the orchestrator line to CLAUDE.md; register the repo with Orca and set its
# base ref; commit the three files unless --no-commit. Idempotent.
set -euo pipefail

plugin_root="$(cd "$(dirname "$0")/.." && pwd)"
defaults="$plugin_root/config/crew64.defaults.json"
reader="$plugin_root/tools/crew64_config.py"

repo="."; commit=1; config_src=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-commit) commit=0; shift ;;
    --config) config_src="${2:-}"; [ -n "$config_src" ] || { echo "crew64-enable: --config needs a path" >&2; exit 2; }; shift 2 ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    -*) echo "crew64-enable: unknown option $1" >&2; exit 2 ;;
    *) repo="$1"; shift ;;
  esac
done
repo="$(cd "$repo" && pwd -P)"
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "crew64-enable: not a git repository: $repo" >&2; exit 1; }
# Only a MAIN checkout may be harnessed and registered as a trusted root
# (decision 0005): the git dir must be the common dir, and the registered path
# is the real toplevel, never the raw argument (a subdirectory or a worktree).
gitdir="$(git -C "$repo" rev-parse --path-format=absolute --git-dir)"
common="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)"
toplevel="$(git -C "$repo" rev-parse --path-format=absolute --show-toplevel)"
if [ "$(realpath "$gitdir")" != "$(realpath "$common")" ]; then
  echo "crew64-enable: $repo is a linked worktree, not the main checkout ($(dirname "$common")). Run this against the main checkout." >&2
  exit 1
fi
repo="$(realpath "$toplevel")"
echo "target: $repo"

# 0. Validate a prepared config before touching anything.
if [ -n "$config_src" ]; then
  config_src="$(cd "$(dirname "$config_src")" && pwd)/$(basename "$config_src")"
  if ! problems="$(python3 -I "$reader" check "$config_src")"; then
    echo "crew64-enable: --config failed check:" >&2
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
# Decision 0006: the plugin used to be ai-dev-system; replace the old entries.
d.get("extraKnownMarketplaces", {}).pop("ai-dev-system", None)
d.get("enabledPlugins", {}).pop("ai-dev-system@ai-dev-system", None)
d.setdefault("extraKnownMarketplaces", {})["crew64"] = {
    "source": {"source": "github", "repo": "sky64/crew64"}}
d.setdefault("enabledPlugins", {})["crew64@crew64"] = True
if json.dumps(d, sort_keys=True) == before:
    print("settings: plugin already enabled in .claude/settings.json, left unchanged")
else:
    p.write_text(json.dumps(d, indent=2) + "\n")
    print("settings: plugin enabled in .claude/settings.json")
PY

# 1b. per-repo config (decision 0005)
config_dst="$repo/.claude/crew64.json"
legacy_cfg="$repo/.claude/ai-dev-system.json"
legacy_was_tracked=0
if [ -e "$legacy_cfg" ] && [ ! -e "$config_dst" ]; then
  # Decision 0006: carry an existing config over to the new name, keeping git history when tracked.
  if git -C "$repo" ls-files --error-unmatch .claude/ai-dev-system.json >/dev/null 2>&1; then
    legacy_was_tracked=1
    git -C "$repo" mv .claude/ai-dev-system.json .claude/crew64.json
  else
    mv "$legacy_cfg" "$config_dst"
  fi
  echo "config: renamed .claude/ai-dev-system.json to .claude/crew64.json"
fi
if [ -e "$config_dst" ]; then
  echo "config: already present, left unchanged ($config_dst)"
elif [ -n "$config_src" ]; then
  cp "$config_src" "$config_dst"; echo "config: written from $config_src"
else
  cp "$defaults" "$config_dst"; echo "config: written from defaults"
fi

# 1c. register the main checkout as a trusted root (decision 0005): the hook and
# the reader honour .claude/crew64.json only for roots listed here.
# Decision 0006: a registration made under the old key moves to the new one.
if git config --global --get-all aidev.trustedRoot 2>/dev/null | grep -qxF -- "$repo"; then
  # Exact, literal match of every duplicate; other aidev.* keys are left alone.
  git config --global --fixed-value --unset-all aidev.trustedRoot "$repo"
  echo "trust: moved $repo from aidev.trustedRoot to crew64.trustedRoot"
fi
if git config --global --get-all crew64.trustedRoot 2>/dev/null | grep -qxF -- "$repo"; then
  echo "trust: $repo already registered as crew64.trustedRoot"
else
  git config --global --add crew64.trustedRoot "$repo"
  echo "trust: registered $repo as crew64.trustedRoot in the global git config"
fi

# 2. CLAUDE.md orchestrator line
line='If you were started as the project orchestrator and were not assigned a specific implementer or reviewer role in your prompt, invoke the crew64:orchestrator skill at session start. A session whose prompt assigns it a worker role (implementer, reviewer) keeps that role and does not invoke the skill. The orchestrator does not write or commit.'
if [ -f "$repo/CLAUDE.md" ] && grep -qF "ai-dev-system:orchestrator" "$repo/CLAUDE.md"; then
  # Decision 0006: replace the legacy instruction in place rather than leaving a dead skill reference.
  python3 -I - "$repo/CLAUDE.md" "$line" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1]); new = sys.argv[2]
text = p.read_text()
if "crew64:orchestrator" in text:
    # The new instruction is already there: drop the legacy line instead of duplicating.
    text = re.sub(r"^[^\n]*ai-dev-system:orchestrator[^\n]*\n?", "", text, count=1, flags=re.M)
else:
    text = re.sub(r"^[^\n]*ai-dev-system:orchestrator[^\n]*$", lambda m: new, text, count=1, flags=re.M)
p.write_text(text)
PY
  echo "CLAUDE.md: legacy orchestrator line replaced"
elif [ -f "$repo/CLAUDE.md" ] && grep -qF "crew64:orchestrator" "$repo/CLAUDE.md"; then
  echo "CLAUDE.md: orchestrator line already present"
else
  { [ -f "$repo/CLAUDE.md" ] && [ -s "$repo/CLAUDE.md" ] && printf '\n'; printf '%s\n' "$line"; } >> "$repo/CLAUDE.md"
  echo "CLAUDE.md: orchestrator line added"
fi

# 3. Orca registration and base ref
if timeout 20 "$orca_bin" repo show --repo "path:$repo" --json >/dev/null 2>&1; then
  echo "orca: repo already registered"
elif timeout 30 "$orca_bin" repo add --path "$repo" --json >/dev/null 2>&1; then
  echo "orca: repo registered"
else
  echo "crew64-enable: orca registration failed (command: $orca_bin; is Orca running and is this the right executable?). The three files are written and staged; nothing was committed." >&2
  exit 1
fi
default_ref="$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
if [ -n "$default_ref" ]; then
  if timeout 20 "$orca_bin" repo set-base-ref --repo "path:$repo" --ref "$default_ref" --json >/dev/null 2>&1; then
    echo "orca: base ref set to $default_ref"
  else
    echo "crew64-enable: orca set-base-ref failed for $default_ref" >&2
    exit 1
  fi
else
  echo "orca: no origin/HEAD; base ref left at Orca's default"
fi

# 4. Commit
# Repositories often gitignore .claude (public and upstream-tracking repos). An
# ignored file is written and used, since the hook and the reader read the
# working copy, but it cannot be committed; report it and commit the rest.
files=(); ignored=()
for f in .claude/settings.json .claude/crew64.json CLAUDE.md; do
  if git -C "$repo" check-ignore -q -- "$f" 2>/dev/null && ! git -C "$repo" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    ignored+=("$f")
  else
    files+=("$f")
  fi
done
[ ${#ignored[@]} -eq 0 ] || echo "git: ${ignored[*]} left untracked (matched by git's exclude rules); the harness reads the working copy"
# CLAUDE.md is often a symlink to AGENTS.md (the new-repo convention). The
# orchestrator line was written through the link, so the target carries the
# change and must join the commit; the link itself is unchanged.
if [ -L "$repo/CLAUDE.md" ]; then
  link_target="$(realpath "$repo/CLAUDE.md")"
  case "$link_target" in
    "$repo"/*) files+=("${link_target#"$repo"/}") ;;
    *) echo "CLAUDE.md: symlink target $link_target is outside the repository; the orchestrator line was written there but not committed" ;;
  esac
fi
# -f: every file here is either not ignored or already tracked; without it git
# refuses the whole pathspec when a tracked file sits inside an ignored directory.
[ ${#files[@]} -eq 0 ] || git -C "$repo" add -f -- "${files[@]}"
# The rename's deletion side belongs in the same commit, also when a previous
# --no-commit run already staged it (the file is then gone from the tree but
# still present in HEAD).
if [ "$legacy_was_tracked" = 1 ] || git -C "$repo" cat-file -e HEAD:.claude/ai-dev-system.json 2>/dev/null; then
  files+=(.claude/ai-dev-system.json)
fi
if [ "$commit" = 1 ]; then
  if [ ${#files[@]} -eq 0 ] || git -C "$repo" diff --cached --quiet -- "${files[@]}"; then
    echo "commit: nothing to commit"
  elif ORCHESTRATOR_GUARD=off git -C "$repo" commit -q -m "chore: enable crew64 plugin" -- "${files[@]}"; then
    echo "commit: $(git -C "$repo" rev-parse --short HEAD) chore: enable crew64 plugin"
  else
    echo "crew64-enable: commit failed (a hook or git refused it); the files remain staged" >&2
    exit 1
  fi
else
  if [ ${#files[@]} -gt 0 ] && ! git -C "$repo" diff --cached --quiet -- "${files[@]}"; then
    echo "commit: skipped (--no-commit); files are staged"
  else
    echo "commit: skipped (--no-commit); nothing staged"
  fi
fi
echo
echo "The plugin applies once this folder is trusted in Claude Code. Edit .claude/crew64.json to turn features on or off (docs/05-delegation.md). Orca's per-repo setup script is a UI setting; check it before creating worktrees with setup enabled."
