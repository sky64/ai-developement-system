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

Bash parsing: the whole command is tokenized once with shlex in POSIX mode
with shell operator characters as punctuation, so quotes are respected and
";", "&", "|", "(", ")", redirects and newlines become their own tokens. The
token stream is split into simple commands on those operators. Command
substitution, unterminated quotes and unknown operator runs are parse
failures and deny.

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
# Read-only subcommands allowed with any arguments. Everything not listed
# here, in GIT_DENY, or in the per-subcommand tables below is denied.
GIT_ALLOW = {
    "merge-base", "rev-list", "rev-parse", "ls-files", "ls-tree", "ls-remote",
    "blame", "describe", "name-rev", "cat-file", "for-each-ref", "shortlog",
    "reflog", "check-ignore", "status", "log", "show", "diff", "grep",
    "count-objects", "var", "help", "version",
}
# Global git options that consume the next token as their value.
GIT_GLOBAL_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
# Subcommands whose positional arguments mutate unless a listing flag is
# present. Every option must be in the set.
GIT_LISTING_FLAGS = {
    "tag": {"-l", "--list", "-n", "--contains", "--points-at"},
    "branch": {"-l", "-a", "-r", "--list", "--show-current", "--contains",
               "-v", "-vv", "--verbose"},
}
# Subcommands driven by a verb (first positional argument). Only the listed
# verbs and options are read-only; later positionals are operands.
GIT_READ_VERBS = {
    "remote": ({"show", "get-url"}, {"-v", "--verbose", "-n", "--all",
                                     "--push"}, True),
    "stash": ({"list", "show"}, {"-p", "--patch", "--stat"}, False),
    "worktree": ({"list"}, {"--porcelain", "-v", "--verbose"}, False),
    "submodule": ({"status"}, {"--recursive", "--cached"}, False),
}
GIT_CONFIG_READ = {
    "--get", "--get-all", "--get-regexp", "--list", "-l", "--show-origin",
    "--show-scope", "--get-color", "--get-colorbool",
}
GIT_CONFIG_READ_VERBS = {"get", "list"}
GIT_CONFIG_OTHER_FLAGS = {
    "--global", "--local", "--system", "--worktree", "--file", "-f", "--blob",
    "--type", "--bool", "--int", "--bool-or-int", "--path", "--expiry-date",
    "--default", "--null", "-z", "--name-only", "--includes", "--no-includes",
    "--all", "--regexp", "--value", "--fixed-value", "--url",
}

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
# Shell operator characters. shlex returns runs of these as their own
# tokens, with quoted text left intact as ordinary word tokens.
OPERATOR_CHARS = ";&|()<>\n"
COMMAND_SEPARATORS = {";", ";;", "&", "&&", "|", "||", "|&", "(", ")", "((",
                      "))"}
OUTPUT_REDIRECTS = {">", ">>", "&>", "&>>", ">|"}
INPUT_REDIRECTS = {"<", "<<", "<<<", "<&", "<>"}
FD_DUP = {">&"}
# A /tmp or $TMPDIR target may not contain ".." (that could climb back out).
SAFE_REDIRECT_TARGET = re.compile(
    r"^(/dev/null|/tmp/(?!.*\.\.).*|\$\{?TMPDIR\}?(?!.*\.\.).*)$"
)


class ShellParseError(ValueError):
    """Command could not be parsed safely; the caller denies."""


def tokenize(cmd: str):
    """Return the shell token stream with quotes resolved.

    Raises ShellParseError on unterminated quotes and on command
    substitution: any token containing $( or a backtick, quoted or not.
    """
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=OPERATOR_CHARS)
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    lex.commenters = ""
    try:
        tokens = list(lex)
    except ValueError as exc:
        raise ShellParseError(f"shell parse error: {exc}") from exc
    for i, tok in enumerate(tokens):
        if "`" in tok or "$(" in tok:
            raise ShellParseError("command substitution")
        if tok == "$" and i + 1 < len(tokens) and tokens[i + 1] == "(":
            raise ShellParseError("command substitution")
    return tokens


def is_operator(tok: str) -> bool:
    return bool(tok) and all(c in OPERATOR_CHARS for c in tok)


def split_commands(tokens):
    """Split the token stream into (argv_lists, output_redirect_targets).

    A fd number before a redirect (the 2 in 2>&1) and the operands of input
    redirects and fd duplication are dropped from argv. Unknown operator runs
    and a trailing redirect without a target raise ShellParseError.
    """
    commands, targets, current = [], [], []
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        i += 1
        if not is_operator(tok):
            current.append(tok)
            continue
        op = tok.replace("\n", "")
        if op == "" or op in COMMAND_SEPARATORS:
            if current:
                commands.append(current)
            current = []
            continue
        if current and current[-1].isdigit():
            current.pop()
        if i >= len(tokens) or is_operator(tokens[i]):
            raise ShellParseError(f"redirect {tok!r} without an operand")
        if op in OUTPUT_REDIRECTS:
            targets.append(tokens[i])
        elif op not in INPUT_REDIRECTS and op not in FD_DUP:
            raise ShellParseError(f"unknown shell operator {tok!r}")
        i += 1
    if current:
        commands.append(current)
    return commands, targets


def is_single_room_cli(tokens) -> bool:
    """Exempt only one plain room-cli invocation with no shell operators."""
    return bool(tokens) and tokens[0] == "room-cli" and not any(
        is_operator(t) for t in tokens
    )


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


def option_name(arg: str) -> str:
    return arg.split("=", 1)[0]


def git_listing_reason(sub, args):
    flags = {option_name(a) for a in args if a.startswith("-")}
    positional = [a for a in args if not a.startswith("-")]
    if not flags <= GIT_LISTING_FLAGS[sub]:
        return f"git {sub} with a non-listing option"
    if positional and not flags:
        return f"git {sub} with a positional argument and no listing flag"
    return None


def git_verb_reason(sub, args):
    verbs, allowed_flags, bare_ok = GIT_READ_VERBS[sub]
    flags = {option_name(a) for a in args if a.startswith("-")}
    positional = [a for a in args if not a.startswith("-")]
    if not flags <= allowed_flags:
        return f"git {sub} with a mutating or unknown option"
    if not positional:
        return None if bare_ok else f"git {sub} without a read-only verb"
    if positional[0] not in verbs:
        return f"git {sub} {positional[0]} is not read-only"
    return None


def git_config_reason(args):
    flags = {option_name(a) for a in args if a.startswith("-")}
    positional = [a for a in args if not a.startswith("-")]
    if not flags <= (GIT_CONFIG_READ | GIT_CONFIG_OTHER_FLAGS):
        return "git config with a write or unknown option"
    read_verb = bool(positional) and positional[0] in GIT_CONFIG_READ_VERBS
    if flags & GIT_CONFIG_READ or read_verb:
        return None
    return "git config write"


def git_reason(argv):
    sub, args = git_subcommand(argv)
    if sub is None or sub in GIT_ALLOW:
        return None
    if sub in GIT_DENY:
        return f"git {sub} mutates the repository"
    if sub in GIT_LISTING_FLAGS:
        return git_listing_reason(sub, args)
    if sub in GIT_READ_VERBS:
        return git_verb_reason(sub, args)
    if sub == "config":
        return git_config_reason(args)
    return f"git {sub} is not in the read-only list"


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
    try:
        tokens = tokenize(cmd)
        if is_single_room_cli(tokens):
            return None
        commands, targets = split_commands(tokens)
    except ShellParseError as exc:
        return f"cannot parse command safely ({exc})"
    for pat in PYTHON_WRITE_PATTERNS:
        if re.search(pat, cmd):
            return f"matches write pattern: {pat}"
    for argv in commands:
        reason = segment_reason(argv)
        if reason:
            return reason
    for target in targets:
        if not SAFE_REDIRECT_TARGET.match(target):
            return f"redirects output to a file ({target})"
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
    command = tool_input.get("command")
    if not isinstance(command, str):
        return deny("Bash tool call without a command string")
    reason = bash_reason(command)
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
