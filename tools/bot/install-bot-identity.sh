#!/usr/bin/env bash
# Install the agent (bot) identity for Orca worktrees on this machine.
# usage: install-bot-identity.sh --name <login> --email <address> --token-command <shell command that prints the token> [--projects-dir <dir>]...
#
# Linked worktrees of repositories under each projects directory, plus
# repositories under ~/orca/workspaces, commit as the bot. Without
# --projects-dir the script uses whichever of ~/projects and ~/Projects exist.
# Re-running replaces the managed include block, so changed directories take
# effect. Everything is validated and the new config is computed before any
# file is written; on any problem the script exits non-zero and changes nothing.
#
# Writes (decision 0005):
# - crew64.bot.name, crew64.bot.email and crew64.bot.tokenCommand in the user's
#   global git config, read by gh-bot and git-credential-op-bot from any cwd;
# - orca-bot.gitconfig (user.name/user.email from the flags plus the
#   credential helper) and one marked includeIf block in the XDG git config
#   directory, so linked Git worktrees under the projects directories and
#   repositories under ~/orca/workspaces commit as the bot while main
#   checkouts keep the owner's identity and helper;
# - two symlinks in ~/.local/bin.
# The include path is relative, which Git resolves against the including
# file, so the directory never needs quoting. Idempotent.
set -euo pipefail
name=""; email=""; token_cmd=""; projects_dirs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --name) name="${2:-}"; shift 2 ;;
    --email) email="${2:-}"; shift 2 ;;
    --token-command) token_cmd="${2:-}"; shift 2 ;;
    --projects-dir) [ -n "${2:-}" ] || { echo "install-bot-identity: --projects-dir needs a path" >&2; exit 2; }; projects_dirs+=("$2"); shift 2 ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "install-bot-identity: unknown argument $1" >&2; sed -n '3p' "$0" >&2; exit 2 ;;
  esac
done
[ -n "$name" ] && [ -n "$email" ] && [ -n "$token_cmd" ] || { echo "install-bot-identity: --name, --email and --token-command are all required" >&2; exit 2; }

# Which projects directories get the worktree rule: the flags, else whichever
# of ~/projects and ~/Projects exist (both spellings are common). Each is made
# absolute and normalised (relative paths resolve against the caller's cwd,
# repeated or trailing slashes collapse), then validated: the path lands inside
# a quoted git config value and a glob pattern, so quote, backslash and glob
# characters are refused.
if [ "${#projects_dirs[@]}" -eq 0 ]; then
  for d in "$HOME/projects" "$HOME/Projects"; do [ -d "$d" ] && projects_dirs+=("$d"); done
fi
reject_dir() {
  echo "install-bot-identity: --projects-dir '$1' contains a character that cannot be written safely into a git includeIf pattern (quote, backslash, * ? [ ], newline, carriage return, or leading/trailing space)" >&2; exit 2
}
normalized=()
for d in "${projects_dirs[@]}"; do
  # Validate the RAW argument first: Bash's $(...) strips trailing newlines, so a
  # check after normalisation would miss a directory that ends in one and
  # silently install a rule for its newline-less sibling.
  case "$d" in
    *'"'*|*'\'*|*'*'*|*'?'*|*'['*|*']'*|*$'\n'*|*$'\r'*|' '*|*' '|*'/ '*) reject_dir "$d" ;;
  esac
  case "$d" in /*) ;; *) d="$PWD/$d" ;; esac
  # Resolve symlinks before collapsing ".." (git matches gitdir against real
  # paths), then validate the RESOLVED path inside Python before it crosses
  # back into Bash, which would strip a trailing newline that the symlink
  # target introduced. A symlink loop leaves an unresolved link and is refused.
  if ! d="$(python3 -I - "$d" <<'PY'
import os, re, sys
raw = sys.argv[1]
def resolve(path):
    """Real path with missing components allowed; raise OSError on a symlink loop anywhere."""
    allow_missing = getattr(os.path, "ALLOW_MISSING", None)
    if os.environ.get("CREW64_FORCE_REALPATH_FALLBACK") == "1":  # tests exercise the older-Python branch
        allow_missing = None
    if allow_missing is not None:
        return os.path.realpath(path, strict=allow_missing)
    # Older Python: walk the RAW absolute path component by component. A symlink
    # is followed by resolving its target with the same walk (so a loop anywhere
    # in a target's ancestors is seen), ".." applies to the resolved prefix, and
    # more than 40 link hops is a loop. Missing components are fine.
    def walk(p, depth):
        if depth > 40:
            raise OSError("symlink loop")
        prefix = os.sep
        for part in p.split(os.sep):
            if part in ("", "."):
                continue
            if part == "..":
                prefix = os.path.dirname(prefix) or os.sep
                continue
            candidate = os.path.join(prefix, part)
            if os.path.islink(candidate):
                target = os.readlink(candidate)
                if not os.path.isabs(target):
                    target = os.path.join(prefix, target)
                prefix = walk(target, depth + 1)
            else:
                prefix = candidate
        return prefix
    return walk(path, 0)
try:
    real = resolve(raw)
except OSError:
    sys.stderr.write("install-bot-identity: --projects-dir '%s' resolves through a symlink loop; nothing was changed\n" % raw); sys.exit(2)
if os.path.islink(real):
    sys.stderr.write("install-bot-identity: --projects-dir '%s' resolves through a symlink loop; nothing was changed\n" % raw); sys.exit(2)
if re.search(r'["\\*?\[\]\n\r]', real) or real != real.strip(" ") or real.endswith("/ "):
    sys.stderr.write("install-bot-identity: --projects-dir '%s' resolves to '%s', which contains a character that cannot be written safely into a git includeIf pattern; nothing was changed\n" % (raw, real.encode("unicode_escape").decode())); sys.exit(2)
sys.stdout.write(real)
PY
)"; then
    exit 2
  fi
  normalized+=("$d")
done
projects_dirs=("${normalized[@]}")

here="$(cd "$(dirname "$0")" && pwd)"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/git"

# Git's gitdir: patterns take ~/ for the home directory; absolute paths pass through.
real_home="$(python3 -I -c 'import os; print(os.path.realpath(os.path.expanduser("~")))')"
gitdir_pattern() {
  # Paths are real paths. Use the ~/ form only when HOME is not a symlink, so
  # git's expansion of ~ lands on the same real path; otherwise keep it absolute.
  if [ "$real_home" = "$HOME" ]; then
    case "$1" in
      "$HOME") printf '~'; return ;;
      "$HOME"/*) printf '~/%s' "${1#"$HOME"/}"; return ;;
    esac
  fi
  printf '%s' "$1"
}
begin="# >>> orca-bot identity (tools/bot/install-bot-identity.sh) >>>"
end="# <<< orca-bot identity <<<"
legacy="# orca-bot identity (tools/bot/install-bot-identity.sh)"
block="$begin"$'\n'
for d in "${projects_dirs[@]}"; do
  block+="[includeIf \"gitdir:$(gitdir_pattern "$d")/*/.git/worktrees/\"]"$'\n\t'"path = orca-bot.gitconfig"$'\n'
done
block+='[includeIf "gitdir:~/orca/workspaces/"]'$'\n\t'"path = orca-bot.gitconfig"$'\n'"$end"$'\n'

# Compute the new global config text BEFORE any write. A begin/end-marked block
# is removed whole; a legacy block (bare marker) is removed only as far as its
# exact header + path pairs run, so nothing of the user's own config is
# touched. An unmatched or nested begin marker is an error and nothing changes.
compute_config() { python3 -I - "$begin" "$end" "$legacy" "$block" "$cfg/config" <<'PY'
import sys, os
begin, end, legacy, block, cfg_path = sys.argv[1:6]
existing = open(cfg_path, encoding="utf-8").read() if os.path.exists(cfg_path) else ""
lines = existing.split("\n")
# A trailing newline in the file yields a final empty element; drop it for processing.
if lines and lines[-1] == "":
    lines.pop()
out, i = [], 0
def managed_pair(j):
    return (j + 1 < len(lines)
            and lines[j].startswith('[includeIf "gitdir:')
            and lines[j].rstrip().endswith('"]')
            and lines[j + 1].strip() == "path = orca-bot.gitconfig")
while i < len(lines):
    s = lines[i].strip()
    if s == begin:
        j = i + 1
        while j < len(lines) and lines[j].strip() != end:
            if lines[j].strip() == begin:
                sys.stderr.write("install-bot-identity: nested begin marker at line %d of the global git config; fix the file by hand, nothing was changed\n" % (j + 1)); sys.exit(3)
            j += 1
        if j >= len(lines):
            sys.stderr.write("install-bot-identity: begin marker at line %d has no matching end marker in the global git config; fix the file by hand, nothing was changed\n" % (i + 1)); sys.exit(3)
        i = j + 1
    elif s == end:
        sys.stderr.write("install-bot-identity: end marker without a begin marker at line %d of the global git config; fix the file by hand, nothing was changed\n" % (i + 1)); sys.exit(3)
    elif s == legacy:
        i += 1
        while managed_pair(i):
            i += 2
    else:
        out.append(lines[i]); i += 1
        continue
    while out and out[-1].strip() == "":
        out.pop()
text = "\n".join(out).rstrip("\n")
text = (text + "\n\n" if text else "") + block
sys.stdout.write(text)
PY
}

# Decision 0006: the keys used to live under aidev.*; drop them so one name
# remains. Unset key by key: `git config --remove-section` also deletes the
# comment lines that follow a section, which once took this script's own
# begin marker with it. Done before validation so the file is checked as it
# will be when the block is written.
for legacy_key in aidev.bot.name aidev.bot.email aidev.bot.tokenCommand; do
  git config --global --unset-all "$legacy_key" 2>/dev/null || true
done
# Validate the marker structure before any write.
compute_config >/dev/null || exit 1

# All inputs validated and the new config computed: now write.
mkdir -p "$cfg" "$HOME/.local/bin"
ln -sfn "$here/git-credential-op-bot" "$HOME/.local/bin/git-credential-op-bot"
ln -sfn "$here/gh-bot" "$HOME/.local/bin/gh-bot"
cat > "$cfg/orca-bot.gitconfig" <<CFG
# Agent worktree identity. Installed by tools/bot/install-bot-identity.sh.
[user]
	name = $name
	email = $email
[credential "https://github.com"]
	helper =
	helper = !$HOME/.local/bin/git-credential-op-bot
CFG
git config --global crew64.bot.name "$name"
git config --global crew64.bot.email "$email"
git config --global crew64.bot.tokenCommand "$token_cmd"
existing=""; [ -f "$cfg/config" ] && existing="$(cat "$cfg/config")"
newcfg="$(compute_config)" || exit 1
if [ "$newcfg" = "$existing" ]; then
  echo "includeIf block already present in $cfg/config"
else
  printf '%s\n' "$newcfg" > "$cfg/config"
  echo "wrote includeIf block to $cfg/config for: ${projects_dirs[*]:-(no projects dir)} and ~/orca/workspaces"
fi
echo "wrote crew64.bot.* to the global git config and $cfg/orca-bot.gitconfig; symlinked git-credential-op-bot and gh-bot into ~/.local/bin"
