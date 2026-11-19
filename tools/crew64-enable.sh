#!/usr/bin/env bash
# Enable the crew64 plugin in a repository, write its config, and register it with Orca.
# usage: crew64-enable.sh [/path/to/repo] [--config <prepared crew64.json>] [--no-commit] [--no-skill]
#
# Run by path from a human or unharnessed session (the orchestrator guard
# would deny its writes). Steps: merge the plugin into .claude/settings.json;
# write .claude/crew64.json from config/crew64.defaults.json or
# from --config (validated first; an existing file is never overwritten); add
# the orchestrator line to CLAUDE.md; register the repo with Orca and set its
# base ref; list the Orca worktree directory in the untracked
# .claude/settings.local.json (features.native_worktree_access); commit the three files unless --no-commit. Also installs or
# refreshes the user-level /harness-enable wrapper skill under $HOME/.claude
# so every machine forwards to this script (--no-skill skips). Idempotent.
set -euo pipefail

plugin_root="$(cd "$(dirname "$0")/.." && pwd)"
defaults="$plugin_root/config/crew64.defaults.json"
reader="$plugin_root/tools/crew64_config.py"

repo="."; commit=1; config_src=""; skill=1
while [ $# -gt 0 ]; do
  case "$1" in
    --no-commit) commit=0; shift ;;
    --no-skill) skill=0; shift ;;
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

# 0b. User-level /harness-enable wrapper. The home-office copy went stale once
# (pre-0005 text writing the old plugin id) because it was copied by hand; the
# plugin now installs it and points it at this script's real location.
skill_dir="$HOME/.claude/skills/harness-enable"
if [ "$skill" = 0 ]; then
  echo "skill: skipped (--no-skill)"
else
  skill_src="$plugin_root/tools/harness-enable-skill"
  # The physical path (a directory symlink alias would go stale) rendered as a
  # shell-quoted literal, so | & and quotes in the path survive (Codex, PR 20).
  enable_real="$(realpath "$0" 2>/dev/null)" || enable_real=""
  rendered=""
  if [ -n "$enable_real" ] && [ -f "$enable_real" ]; then
    rendered="$(python3 -I - "$enable_real" "$skill_src/enable.sh.tmpl" <<'PY' 2>/dev/null || true
import shlex, sys
print(open(sys.argv[2], encoding="utf-8").read().replace("@CREW64_ENABLE@", shlex.quote(sys.argv[1])), end="")
PY
)"
  fi
  if [ -z "$enable_real" ]; then
    echo "skill: skipped (could not resolve the path of $0)"
  elif [ -z "$rendered" ]; then
    echo "skill: skipped (could not render the wrapper from $skill_src)"
  elif ! mkdir -p "$skill_dir" 2>/dev/null || [ ! -w "$skill_dir" ]; then
    echo "skill: skipped ($skill_dir is not writable)"
  elif [ -f "$skill_dir/enable.sh" ] && [ -f "$skill_dir/SKILL.md" ] \
       && [ "$(cat "$skill_dir/enable.sh")" = "$rendered" ] && cmp -s "$skill_src/SKILL.md" "$skill_dir/SKILL.md"; then
    echo "skill: current $skill_dir"
  else
    verb=installed; [ -e "$skill_dir/enable.sh" ] && verb=refreshed
    if printf '%s\n' "$rendered" > "$skill_dir/enable.sh" && chmod 755 "$skill_dir/enable.sh" && cp "$skill_src/SKILL.md" "$skill_dir/SKILL.md"; then
      echo "skill: $verb $skill_dir"
    else
      echo "skill: skipped (could not write $skill_dir)"
    fi
  fi
fi

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

# 1d. Native worktree access (features.native_worktree_access, platform.worktree_root).
# The orchestrator guard decides by the session's working directory, and Claude
# Code keeps a `cd` only inside the session's working directories, so a native
# task can move into its Orca worktree only when that directory is listed in
# permissions.additionalDirectories. The path is machine-specific, so it goes in
# the untracked .claude/settings.local.json, which is kept out of git through
# .git/info/exclude when nothing ignores it already. Read after 1c: the reader
# trusts this repo's config only once it is registered.
access="$(cd "$repo" && python3 -I "$reader" get features.native_worktree_access)"
if [ "$access" = "true" ]; then
  wt_root="$(cd "$repo" && python3 -I "$reader" get platform.worktree_root)"
  python3 -I - "$repo/.claude/settings.local.json" "$wt_root" "$(basename "$repo")" <<'PY'
import json, os, pathlib, sys
p, root, name = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
want = os.path.normpath(os.path.join(os.path.expanduser(root), name))
d = json.loads(p.read_text()) if p.exists() and p.read_text().strip() else {}
if not isinstance(d, dict):
    sys.exit("crew64-enable: .claude/settings.local.json is not a JSON object; fix it and re-run")
perms = d.setdefault("permissions", {})
dirs = perms.setdefault("additionalDirectories", []) if isinstance(perms, dict) else None
if not isinstance(dirs, list):
    sys.exit("crew64-enable: permissions.additionalDirectories in .claude/settings.local.json is not a list; fix it and re-run")
if want in dirs:
    print(f"worktree access: {want} already listed in .claude/settings.local.json")
else:
    dirs.append(want)
    p.write_text(json.dumps(d, indent=2) + "\n")
    print(f"worktree access: {want} added to .claude/settings.local.json")
PY
  if ! git -C "$repo" check-ignore -q .claude/settings.local.json; then
    exclude="$(git -C "$repo" rev-parse --absolute-git-dir)/info/exclude"
    mkdir -p "$(dirname "$exclude")"
    if ! grep -qxF '.claude/settings.local.json' "$exclude" 2>/dev/null; then
      printf '.claude/settings.local.json\n' >> "$exclude"
      echo "worktree access: .claude/settings.local.json added to .git/info/exclude"
    fi
  fi
else
  echo "worktree access: off (features.native_worktree_access is false); native tasks will run delegated"
fi

# 2. CLAUDE.md orchestrator line
line_head='If you were started as the project orchestrator and were not assigned a specific implementer or reviewer role in your prompt, invoke the crew64:orchestrator skill at session start. A session whose prompt assigns it a worker role (implementer, reviewer) keeps that role and does not invoke the skill.'
line="$line_head The orchestrator does not write or commit in the main checkout; in native mode it works in a task worktree."
# The line as shipped before 0.8.1 (decision 0009 added native mode). Only this
# exact line is rewritten on a re-run; a line the owner reworded is left alone.
old_line="$line_head The orchestrator does not write or commit."
legacy_replaced=0
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
  legacy_replaced=1
fi
# The rewrite works on bytes and touches nothing but the orchestrator lines: every
# other line keeps its content and its own line ending (LF or CRLF, mixed files
# included), and the rewritten line keeps the ending it had. With at least one
# old line present, exactly one current line remains: the first current line when
# there is one, otherwise the first old line rewritten in place. Without an old
# line the file is not written at all.
line_update=""
if [ -f "$repo/CLAUDE.md" ]; then
  line_update="$(python3 -I - "$repo/CLAUDE.md" "$old_line" "$line" <<'PY'
import sys

path, old, new = sys.argv[1], sys.argv[2].encode(), sys.argv[3].encode()
with open(path, "rb") as fh:
    entries = fh.read().splitlines(keepends=True)


def content(entry: bytes) -> bytes:
    return entry.rstrip(b"\r\n")


if not any(content(entry) == old for entry in entries):
    sys.exit(0)
out, have_new = [], False
keep_first_new = any(content(entry) == new for entry in entries)
for entry in entries:
    body = content(entry)
    if body == new:
        if not have_new:
            out.append(entry)
            have_new = True
    elif body == old:
        if not keep_first_new and not have_new:
            out.append(new + entry[len(body):])
            have_new = True
    else:
        out.append(entry)
with open(path, "wb") as fh:
    fh.write(b"".join(out))
print("updated")
PY
)"
fi
if [ "$line_update" = updated ]; then
  echo "CLAUDE.md: orchestrator line updated (main-checkout wording, decision 0009)"
elif [ -f "$repo/CLAUDE.md" ] && grep -qF "crew64:orchestrator" "$repo/CLAUDE.md"; then
  [ "$legacy_replaced" = 1 ] || echo "CLAUDE.md: orchestrator line already present"
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
