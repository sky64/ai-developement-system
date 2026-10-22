# Matrix tests: permission mode and stop/resume

Date: 2026-10-22. Run from orchestrator thread thr_nveh5eysxj. Scope: two behavioral tests from section B of the [capability matrix](02-compatibility-matrix.md), each run as a Claude child thread in its own Cloudroom worktree. The facts below were reported by the orchestrator thread; nothing was re-run while writing this record.

## Test 1: permission mode accept-edits

| Item | Observed |
|---|---|
| Thread | thr_95wpwyzv2t, Claude child in a worktree, spawned with permission mode accept-edits |
| Write inside the worktree | Allowed, no prompt |
| Write to a file in the home directory | Denied by the project orchestrator-guard hook before the permission system saw it |
| Network | `curl` to example.com with a 10 second limit. Cloudroom raised a SandboxNetworkAccess permission-grant interaction, pint_x4pjrwjhkh, which stayed pending with no grant. The command failed after 10 seconds with curl exit 28 and HTTP code 000. The orchestrator denied the interaction afterwards with `room-cli thread interactions deny`. |
| Side effect of the pending request | Four of the child's Bash calls failed with the message that the thread was already awaiting user interaction. Each succeeded on retry. |
| Sandbox artifact | Inside sandboxed commands, `git status` lists phantom untracked dotfiles because the sandbox bind-mounts /dev/null over them. The real worktree was clean. |

Conclusion: under accept-edits, Cloudroom raised a pending network-access grant request, nobody granted it, the curl command timed out after 10 seconds with exit 28 and HTTP code 000, and the orchestrator denied the request afterwards. Whether the permission layer enforced the denial, rather than the command simply timing out while the request was pending, remains unverified. Accept-edits did not prompt for the in-worktree write. The out-of-worktree write was caught by the hook, not by the permission mode, so the permission layer's handling of out-of-worktree writes remains untested.

## Test 2: stop and resume

| Item | Observed |
|---|---|
| Thread | thr_p4gw4nsmrk, Claude child in a worktree |
| Task | Six sequential steps, each with a 20 second sleep and a line in a progress log |
| Stop | The orchestrator ran `room-cli thread stop` after step 2 finished, during step 3's sleep. The child's shell was killed with exit 137. progress.txt showed step 3 starting with no finished line, and step-3.md was absent. |
| Resume | The orchestrator resumed the thread with `room-cli thread tell`. The child read the log, recorded that step 3 was started but unfinished and its file absent, redid step 3 once, and finished steps 4 to 6. |
| Result | One Git record, ea5a5d0, in the child's worktree. No step completed twice. |
| CLI note | `room-cli thread wait` does not accept a stopped status. A stopped thread reports idle. |

Conclusion: stop killed the running shell, the partial step stayed visible in the log, and an explicit resume continued without duplicate effects.

## Hard limits

A search of `room-cli thread update`, `room-cli thread spawn` and settings help found no usage, cost, token or time limit flag. Only a reasoning level and a provider usage display exist. Recorded in the matrix as: no enforceable limit found in the installed CLI, so execution stays attended.

## Not tested

- Phone approval. Needs the owner.
- Permission-layer handling of an out-of-worktree write. The hook denied it first.
- Behavior under a granted SandboxNetworkAccess interaction.

## Repository state recorded the same day

- PR 1 was made ready.
- The repository was made public.
- Branch protection on main requires one approving review, with admin enforcement and no force pushes.
- PR 1 cannot merge until a second identity approves or admin enforcement is lifted for the merge.
