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
| Probe A | thr_gik97cgkd8, Claude in the checkout environment env_7wi6hunwb4 |
| Probe B | thr_bgvmxiiv2n, Claude in worktree branch `room/enforcement-test-b-worktree-expect-allow-iv2n`, based on a7f23b1 |
| Deadline | None was recorded for the policy-landing task. This record's task had one (30 minutes). Recorded as a deviation. |
| This record | Written by implementer thread thr_qfft7dyc5n on branch `room/implementer-docs-06-enforcement-test-rec-yc5n`, base a7f23b1, retry allowance 2, permission mode inherited from the orchestrator |

## Selection record

Required by [05-delegation.md](05-delegation.md) before any child starts.

1. Tech: Markdown, Bash and Python hook scripts.
2. Search order: project agents in `.claude/agents/` (docs-engineer, authored this run); the ECC roster (ecc:doc-updater exists but runs in-process, so the Cloudroom child adopts docs-engineer instead); skills (none beyond repository conventions).
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
- The project guard exempts one-line commands that start with `room-cli`. The ECC hook does not, so the denial can still come from the machine-wide hook.

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
