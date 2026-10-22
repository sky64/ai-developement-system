# Enforcement test: orchestrator write guard and first delegated run

Date: 2026-10-20. Run from orchestrator thread thr_nveh5eysxj. Scope: land the delegation policy from [05-delegation.md](05-delegation.md) through a delegated implementer, then probe the guard from two Claude threads, one in the checkout and one in a worktree. All facts below were confirmed by the orchestrator thread; nothing here was re-run while writing this record.

## Run record

| Item | Observed |
|---|---|
| Orchestrator | thr_nveh5eysxj, Claude in the project checkout |
| Policy landing | Orchestrator staged the change in the main checkout. Its own Git write was denied by the hook, which hot-loaded into the running session. It exported the staged diff to `/tmp/policy.patch`. |
| Implementer | thr_kbsuw9hifw, worktree branch `room/implementer-land-delegation-policy-and-g-hifw`, applied the patch as a7f23b1 |
| Implementer checks | All passing: 17 hook unit cases, whitespace, settings JSON, `bash -n`, 16 links |
| Leftover | The staged copy remains in the checkout working tree. The owner clears it. |
| Probe A | thr_gik97cgkd8, Claude in the checkout environment on the owner's workstation |
| Probe B | thr_bgvmxiiv2n, Claude in worktree branch `room/enforcement-test-b-worktree-expect-allow-iv2n`, based on a7f23b1 |
| Deadline | None was recorded for the policy-landing task. This record's task had one (30 minutes). Recorded as a deviation. |
| This record | Written by implementer thread thr_qfft7dyc5n on branch `room/implementer-docs-06-enforcement-test-rec-yc5n`, base a7f23b1, retry allowance 2, permission mode inherited from the orchestrator |

## Selection record

Required by [05-delegation.md](05-delegation.md) before any child starts.

1. Tech: Markdown, Bash and Python hook scripts.
2. Search order: project agents in `.claude/agents/` (docs-engineer, authored this run); the ECC roster (ecc:doc-updater exists but runs in-process, so the Cloudroom child adopts docs-engineer instead); skills named by the agent definition: ecc:git-workflow and ecc:coding-standards. The thread that wrote this record did not load them. The review cycle 1 implementer (thr_9qbyjvf9as) loaded both with the Skill tool.
3. Chosen agent: docs-engineer, run as a Cloudroom child thread in its own worktree.
4. Generalist: not used.

## Results

| Check | Probe A, checkout | Probe B, worktree |
|---|---|---|
| `git rev-parse --git-dir` vs `--git-common-dir` | Equal | Different |
| Write tool | DENIED, reason: file write tool | ALLOWED |
| Bash heredoc redirect | DENIED, reason: redirects output to a file | ALLOWED |
| Git record | Not attempted; no file existed | 8ca865d ALLOWED, then undone |
| End state | No file or change created | Tree left clean at a7f23b1 |

## Limitations found

- The project guard and the machine-wide ECC pre-bash hook both pattern-match words inside quoted prompt text. The orchestrator was denied two `room-cli thread spawn` commands because their prompts contained write-like words.
- The project guard exempts a single plain `room-cli` command with no shell operators. Since review cycle 2 the check is quote aware, so a quoted prompt argument containing `;`, `&`, `|` or a newline keeps the exemption; a prompt containing `$(` or a backtick, even quoted, is a parse failure and denies. The ECC hook has no exemption, so the denial can still come from the machine-wide hook.

## What the test proves

- The hook denies file writes and Git writes for a Claude thread in the checkout, even under full permissions.
- The hook allows the same operations for a Claude thread in a worktree.

## What it does not prove

- Anything about Codex threads. Codex runs no Claude hooks.
- Resistance to Bash bypass. The Bash check is pattern based.
- Any GitHub gate. Branch protection and merge rules were not part of this test.

## Next steps

1. Codex review of this change in a fresh child thread, with base a7f23b1 and the head SHA on this branch.
2. Owner merge.

## Review cycle 1

Codex review thread thr_v3s26gxxrp reviewed 47c6165..c2dc985 on 2026-10-20. Correction cycle 1 of 2 was implemented by docs-engineer in thread thr_9qbyjvf9as on branch `room/implementer-fix-guard-hook-per-codex-rev-f9as`, base c2dc985. Each finding below has at least one unit case in `tools/hooks/test-orchestrator-guard.sh`; the suite grew from 17 to 74 cases.

| Severity | Finding | Fix |
|---|---|---|
| P1 | Docs overstated worktree separation as a boundary; a worktree session may write any path, including the main checkout. | Hook denies Edit, Write, MultiEdit and NotebookEdit in a worktree when the real target path is outside the real cwd. Docs now say workspace separation, no enforced write boundary yet, OS-user separation or a Cloud sandbox needed for one. |
| P1 | The `room-cli` exemption skipped compound commands such as `room-cli --version; git add README.md`. | Exemption applies only to a single `room-cli` invocation with no `;`, `&`, `|`, newline, backtick, `$(` or `>`. |
| P2 | Missed write variants: git with leading global options, `git config set`, `sed -i` not directly after the command, Python `write_text`, `write_bytes`, `shutil.copy`, `shutil.move`, `os.remove`, `os.rename`, `os.unlink`, and `/tmp` redirect targets containing `..`. | Bash commands are split into simple commands and shlex-parsed; the git subcommand is found after global options; `sed`/`perl` in-place flags are matched on any argument; Python write calls are matched; `/tmp` targets with `..` are not exempt. |
| P2 | Read-only Git commands were blocked: `git worktree list --porcelain`, `git tag --list`, `git stash list`, `git branch --show-current`. | Listing forms of `tag`, `branch`, `stash`, `worktree`, `remote`, `config` and `submodule` are allowed; all other forms of those subcommands are denied. |
| P2 | Paths with spaces broke worktree detection because rev-parse output was split on whitespace. | Output is parsed with `splitlines`; a worktree with a space in its path is covered by the test. |
| P2 | Invalid hook input failed open. | Malformed JSON, a non-object payload, a missing `tool_name` or a non-object `tool_input` deny with exit 2 and a diagnostic on stderr; any internal error also denies. |
| P2 | The selection record said no skills beyond conventions although the agent definition names two. | Selection record lists ecc:git-workflow and ecc:coding-standards and states which thread loaded them. |

Still true after this cycle: the Bash check is pattern based and bypassable, Codex threads run no Claude hooks, and no GitHub gate was tested.

## Review cycle 2

Codex review thread thr_ue9kwf35yv reviewed c2dc985..f976bb3 on 2026-10-20. Correction cycle 2 of 2 was implemented by docs-engineer in thread thr_uz2kcxdctx on branch `room/implementer-guard-correction-cycle-2-doc-dctx`, base f976bb3. Each finding below has unit cases in `tools/hooks/test-orchestrator-guard.sh`; the suite grew from 74 to 150 cases.

| Severity | Finding | Fix |
|---|---|---|
| P2 | Shell parsing was not quote aware: `room-cli --version&git add README.md`, `git -c "user.name=A;B" commit -m x` and `"git" commit` all passed. | The whole command is tokenized once with `shlex` in POSIX mode with `;&|()<>` and newline as punctuation; the token stream is split into simple commands on operator tokens; quotes are stripped from the command name; any token containing `$(` or a backtick, an unterminated quote, an unknown operator run or a redirect without a target is a parse failure and denies. |
| P2 | `git remote -v add` passed because only the first argument was checked. | `remote`, `tag`, `branch`, `stash`, `worktree`, `config` and `submodule` check every argument: all options must be in the read-only set for the subcommand and the verb or positional form must be a read form. `remote` allows no arguments, `-v`, `--verbose`, `show` and `get-url`. |
| P2 | Read-only false positives: `git config get`, `git config --get` with `--file`, `--global` or `--system`, `git config --show-origin`, and read-only subcommands not named in the hook. | `config get`, `config list`, `--get` with scope or file flags and `--show-origin` are allowed. `merge-base`, `rev-list`, `rev-parse`, `ls-files`, `ls-tree`, `ls-remote`, `blame`, `describe`, `name-rev`, `cat-file`, `for-each-ref`, `shortlog`, `reflog`, `check-ignore`, `status`, `log`, `show`, `diff`, `grep`, `count-objects`, `var`, `help` and `version` are allowed explicitly; any Git subcommand outside the allow, deny and per-subcommand tables is now denied. |
| P2 | Partial fix from cycle 1: the attached ampersand and a quoted global option value hiding a subcommand were still missed. | Covered by the tokenizer above; both have unit cases. |
| P2 | The redirect check ran on raw text, so `grep -n "x>y"` was a write. | Output redirects are checked on the token stream; only `>`, `>>`, `&>`, `&>>` and `>|` operator tokens count, and their targets must be `/dev/null`, `/tmp` or `$TMPDIR` without `..`. |
| P3 | A Bash call with a missing or null command was allowed. | A non-string `command` denies with a diagnostic. |

Known cost of the stricter parse: `$(…)` and backticks are denied even inside quotes and even when the substituted command is read-only, so `echo "$(git rev-parse HEAD)"` is denied. The orchestrator runs such commands in two steps.

The review budget of two cycles is now spent. Remaining findings go to the owner.
