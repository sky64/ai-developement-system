#!/usr/bin/env python3
"""Claude Code PreToolUse hook: the orchestrator does not write.

Policy (docs/05-delegation.md): a Claude session running in the project's
main checkout is the orchestrator. It reads, runs checks, selects
specialists, and routes review. It never edits tracked files or mutates Git.
Implementers run as Cloudroom child threads in their own worktrees, where
writes inside the worktree are allowed.

Decision rules:
- Main checkout (git-dir equals git-common-dir): deny file write tools and
  Bash commands that write files or mutate Git.
- Worktree: allow file write tools only when the real path of the target is
  inside the real path of cwd. Bash is not checked.
- Malformed hook input (not JSON, not an object, no tool_name) is denied.

Set ORCHESTRATOR_GUARD=off to disable for a human session. That override is
a convention, not a boundary, and so is the Bash check below. The Bash check
is pattern based and bypassable; it is a tripwire, not a security boundary.

Exit 2 blocks the tool call and sends stderr back to the agent.
"""
import json
import os
import re
import shlex
import subprocess
import sys

WRITE_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}

GIT_DENY = {
    "commit", "add", "apply", "am", "cherry-pick", "merge", "rebase", "reset",
    "checkout", "switch", "restore", "rm", "mv", "push", "clean",
    "filter-branch", "fetch", "pull", "notes", "replace", "update-ref",
    "symbolic-ref",
}
# Global git options that consume the next token as their value.
GIT_GLOBAL_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
# Subcommands allowed only with these flags (or no arguments at all).
GIT_READ_ONLY_FLAGS = {
    "tag": {"-l", "--list"},
    "branch": {"-l", "-a", "-r", "--list", "--show-current", "--contains"},
}
# Subcommands allowed only when the first argument is one of these.
GIT_READ_ONLY_FIRST_ARG = {
    "stash": {"list", "show"},
    "worktree": {"list"},
    "submodule": {"status"},
}
GIT_REMOTE_READ_ARGS = {"-v", "show"}
GIT_CONFIG_SCOPE_FLAGS = {"--global", "--local", "--system", "--worktree"}
GIT_CONFIG_READ_FLAGS = {"--get", "--get-all", "--list", "-l"}

WRITE_COMMANDS = {
    "tee", "cp", "mv", "rm", "touch", "ln", "truncate", "dd", "patch",
    "install", "chmod", "chown",
}
PACKAGE_MANAGERS = {"npm", "pnpm", "yarn", "cargo", "pip", "uv"}
PACKAGE_WRITE_VERBS = {"install", "add", "remove", "uninstall", "update"}
COMMAND_WRAPPERS = {"sudo", "env", "command", "nice", "time"}
IN_PLACE_FLAG = re.compile(r"^(-[a-zA-Z]*i|--in-place)")

PYTHON_WRITE_PATTERNS = [
    r"open\([^)]*['\"][wax]\+?\\?['\"]",
    r"\.write_(text|bytes)\(",
    r"shutil\.(copy\w*|move)\(",
    r"os\.(remove|rename|unlink|replace)\(",
]
# A /tmp target may not contain ".." (that could climb back out of /tmp).
TMP_PATH = r"(?:(?!\.\.)\S)*"
SAFE_REDIRECT_TARGETS = (
    rf"(/dev/null|/tmp/{TMP_PATH}|\$\{{?TMPDIR\}}?{TMP_PATH})(?=[\s;&|)]|$)"
)
# Simple-command boundaries, including subshells and command substitution.
SEGMENT_SPLIT = re.compile(r"\|\||&&|\$\(|[;|\n`()]")
ROOM_CLI_COMPOUND = re.compile(r"[;&|\n`>]|\$\(")


def strip_safe_redirects(cmd: str) -> str:
    cmd = re.sub(r"\d?>&\d", " ", cmd)           # 2>&1
    cmd = re.sub(r"&?>>?\s*" + SAFE_REDIRECT_TARGETS, " ", cmd)
    return cmd


def is_single_room_cli(cmd: str) -> bool:
    """Exempt only one plain room-cli invocation with no shell operators."""
    stripped = cmd.strip()
    if not (stripped == "room-cli" or stripped.startswith("room-cli ")):
        return False
    return ROOM_CLI_COMPOUND.search(stripped) is None


def segments(cmd: str):
    """Yield argv lists, one per simple command."""
    for raw in SEGMENT_SPLIT.split(cmd):
        try:
            tokens = shlex.split(raw, comments=False)
        except ValueError:
            tokens = raw.split()
        current = []
        for tok in tokens:
            if tok == "&":
                if current:
                    yield current
                current = []
            else:
                current.append(tok)
        if current:
            yield current


def strip_wrappers(argv):
    i = 0
    while i < len(argv) and (argv[i] in COMMAND_WRAPPERS or re.match(r"^\w+=", argv[i])):
        i += 1
    return argv[i:]


def git_subcommand(argv):
    """Return (subcommand, args) after git's global options."""
    i = 1
    while i < len(argv):
        tok = argv[i]
        if tok in GIT_GLOBAL_WITH_VALUE:
            i += 2
        elif tok.startswith("-"):
            i += 1
        else:
            return tok, argv[i + 1:]
    return None, []


def git_reason(argv):
    sub, args = git_subcommand(argv)
    if sub is None:
        return None
    if sub in GIT_DENY:
        return f"git {sub} mutates the repository"
    if sub in GIT_READ_ONLY_FLAGS:
        flags = {a for a in args if a.startswith("-")}
        if not args or (flags and flags <= GIT_READ_ONLY_FLAGS[sub]):
            return None
        return f"git {sub} with non-listing arguments"
    if sub in GIT_READ_ONLY_FIRST_ARG:
        if args and args[0] in GIT_READ_ONLY_FIRST_ARG[sub]:
            return None
        return f"git {sub} outside its read-only forms"
    if sub == "remote":
        if not args or args[0] in GIT_REMOTE_READ_ARGS:
            return None
        return "git remote mutation"
    if sub == "config":
        rest = [a for a in args if a not in GIT_CONFIG_SCOPE_FLAGS]
        if rest and rest[0] in GIT_CONFIG_READ_FLAGS:
            return None
        return "git config write"
    return None


def segment_reason(argv):
    argv = strip_wrappers(argv)
    if not argv:
        return None
    name = os.path.basename(argv[0])
    rest = argv[1:]
    if name == "git":
        return git_reason(argv)
    if name in WRITE_COMMANDS:
        return f"{name} writes files"
    if name in ("sed", "perl") and any(IN_PLACE_FLAG.match(a) for a in rest):
        return f"{name} edits in place"
    if name in PACKAGE_MANAGERS and rest and rest[0] in PACKAGE_WRITE_VERBS:
        return f"{name} {rest[0]} changes dependencies"
    return None


def bash_reason(cmd: str):
    if is_single_room_cli(cmd):
        return None
    for pat in PYTHON_WRITE_PATTERNS:
        if re.search(pat, cmd):
            return f"matches write pattern: {pat}"
    for argv in segments(cmd):
        reason = segment_reason(argv)
        if reason:
            return reason
    rest = strip_safe_redirects(cmd)
    if re.search(r"(^|[^<])>", rest):
        return "redirects output to a file"
    if "<<" in rest and ">" in rest:
        return "heredoc written to a file"
    return None


def in_worktree(cwd: str) -> bool:
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--git-dir", "--git-common-dir"],
            capture_output=True, text=True, timeout=5, check=True,
        ).stdout.splitlines()
    except Exception:
        return False
    if len(out) != 2:
        return False
    git_dir, common = (os.path.realpath(os.path.join(cwd, p)) for p in out)
    return git_dir != common


def path_outside_cwd(cwd: str, tool_input: dict):
    """Reason string when the write target is not inside cwd, else None."""
    target = tool_input.get("file_path") or tool_input.get("notebook_path")
    if not isinstance(target, str) or not target:
        return "write tool without a file path"
    real_cwd = os.path.realpath(cwd)
    real_target = os.path.realpath(os.path.join(real_cwd, target))
    if os.path.commonpath([real_cwd, real_target]) != real_cwd:
        return f"target {real_target} is outside the worktree {real_cwd}"
    return None


def deny(reason: str) -> int:
    sys.stderr.write(
        f"orchestrator-guard: denied ({reason}). The orchestrator does not "
        "write or commit. Delegate the change to a specialist implementer as a "
        "Cloudroom child thread in a worktree, and keep implementer writes "
        "inside that worktree (see docs/05-delegation.md).\n"
    )
    return 2


def decide(payload) -> int:
    if not isinstance(payload, dict):
        return deny("invalid hook input: payload is not a JSON object")
    tool = payload.get("tool_name")
    if not isinstance(tool, str) or not tool:
        return deny("invalid hook input: missing tool_name")
    tool_input = payload.get("tool_input")
    if tool_input is None:
        tool_input = {}
    if not isinstance(tool_input, dict):
        return deny("invalid hook input: tool_input is not an object")
    cwd = payload.get("cwd") or os.getcwd()
    if tool not in WRITE_TOOLS and tool != "Bash":
        return 0
    if in_worktree(cwd):
        if tool in WRITE_TOOLS:
            reason = path_outside_cwd(cwd, tool_input)
            if reason:
                return deny(reason)
        return 0
    if tool in WRITE_TOOLS:
        return deny("file write tool in the main checkout")
    reason = bash_reason(tool_input.get("command", "") or "")
    if reason is None:
        return 0
    return deny(f"main checkout, {reason}")


def main() -> int:
    if os.environ.get("ORCHESTRATOR_GUARD", "").lower() == "off":
        return 0
    try:
        payload = json.load(sys.stdin)
    except (ValueError, UnicodeDecodeError) as exc:
        return deny(f"invalid hook input: not JSON ({exc})")
    try:
        return decide(payload)
    except Exception as exc:  # never crash open
        return deny(f"internal error, denying by default: {exc!r}")


if __name__ == "__main__":
    sys.exit(main())
