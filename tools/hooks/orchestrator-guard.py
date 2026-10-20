#!/usr/bin/env python3
"""Claude Code PreToolUse hook: the orchestrator does not write.

Policy (docs/05-delegation.md): a Claude session running in the project's
main checkout is the orchestrator. It reads, runs checks, selects
specialists, and routes review. It never edits tracked files or mutates Git.
Implementers run as Cloudroom child threads in their own worktrees, where
writes are allowed.

Decision rule: writes are allowed when the hook's cwd is a Git worktree
(git-dir differs from git-common-dir) and denied in the main checkout.
Set ORCHESTRATOR_GUARD=off to disable for a human session. That override is
a convention, not a boundary, and so is the Bash pattern check below.

Exit 2 blocks the tool call and sends stderr back to the agent.
"""
import json
import os
import re
import subprocess
import sys

WRITE_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}

# Bash commands that write tracked files or mutate Git. Pattern based and
# bypassable by design; the worktree separation is the real boundary.
BASH_DENY = [
    r"(^|[\s;&|(])sed\s+(-[a-zA-Z]*i|--in-place)",
    r"(^|[\s;&|(])perl\s+-[a-zA-Z]*i",
    r"(^|[\s;&|(])tee\s",
    r"(^|[\s;&|(])(cp|mv|rm|touch|ln|truncate|dd|patch|install|chmod|chown)\s",
    r"(^|[\s;&|(])git\s+(-C\s+\S+\s+)?(commit|add|apply|am|cherry-pick|merge|rebase|reset|checkout|switch|restore|stash|rm|mv|push|tag|branch\s+-[dDm]|worktree|clean|filter-branch)\b",
    r"open\([^)]*['\"][wax]\+?\\?['\"]",
    r"(^|[\s;&|(])(npm|pnpm|yarn|cargo|pip|uv)\s+(install|add|remove|uninstall|update)\b",
]
SAFE_REDIRECT_TARGETS = r"(/dev/null|/tmp/\S*|\$\{?TMPDIR\}?\S*)"


def strip_safe_redirects(cmd: str) -> str:
    cmd = re.sub(r"\d?>&\d", " ", cmd)           # 2>&1
    cmd = re.sub(r"&?>>?\s*" + SAFE_REDIRECT_TARGETS, " ", cmd)
    return cmd


def bash_reason(cmd: str):
    if cmd.strip().startswith("room-cli ") and "\n" not in cmd and ">" not in cmd:
        return None
    for pat in BASH_DENY:
        if re.search(pat, cmd):
            return f"matches write pattern: {pat}"
    rest = strip_safe_redirects(cmd)
    if re.search(r"(^|[^<])>", rest):
        return "redirects output to a file"
    if "<<" in rest and re.search(r">", rest):
        return "heredoc written to a file"
    return None


def in_worktree(cwd: str) -> bool:
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--git-dir", "--git-common-dir"],
            capture_output=True, text=True, timeout=5, check=True,
        ).stdout.split()
    except Exception:
        return False
    if len(out) != 2:
        return False
    git_dir, common = (os.path.realpath(os.path.join(cwd, p)) for p in out)
    return git_dir != common


def main() -> int:
    if os.environ.get("ORCHESTRATOR_GUARD", "").lower() == "off":
        return 0
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    tool = payload.get("tool_name", "")
    cwd = payload.get("cwd") or os.getcwd()
    if tool not in WRITE_TOOLS and tool != "Bash":
        return 0
    if in_worktree(cwd):
        return 0
    if tool in WRITE_TOOLS:
        reason = "file write tool"
    else:
        reason = bash_reason(payload.get("tool_input", {}).get("command", "") or "")
        if reason is None:
            return 0
    sys.stderr.write(
        "orchestrator-guard: denied. This session runs in the main checkout, "
        f"which is the orchestrator role ({reason}). The orchestrator does not "
        "write or commit. Delegate the change to a specialist implementer as a "
        "Cloudroom child thread in a worktree (see docs/05-delegation.md).\n"
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
