# Matrix tests: permission mode and stop/resume

Date: 2026-10-22. Run from orchestrator thread thr_nveh5eysxj. Scope: three behavioral tests from sections B and C of the [capability matrix](02-compatibility-matrix.md), each run as a Claude child thread in its own Cloudroom worktree. The facts below were reported by the orchestrator thread; nothing was re-run while writing this record.

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

## Test 3: phone approval

| Item | Observed |
|---|---|
| Thread | thr_gpt7yn9thb, Claude child in a worktree, permission mode accept-edits. The owner answered the requests from the Cloudroom phone app. |
| Request 1, `curl` to example.com, owner denied from the phone | curl exit 7, HTTP code 000, message `CONNECT tunnel failed, response 403`, sandbox message `deny network-outbound example.com:443 (user denied)`. The denial reached the sandbox. |
| Stale record after request 1 | Cloudroom's interaction record pint_vf7ed6s635 for that request stayed pending. The probe's next command was rejected with the message that the thread was already awaiting user interaction. The orchestrator cleared the stale record with `room-cli thread interactions deny`. |
| Request 2, `curl` to example.org, owner intended approve | Attempt 1 was rejected before execution by the stale record. Attempt 2 raised grant request pint_cer7p2s48b; the command timed out after 180 seconds with exit 28 and HTTP code 000 and no sandbox message while the record still showed pending. The owner reported approving from the phone, and the orchestrator also granted the record with `room-cli thread interactions grant`. Attempts 3 and 4 then returned promptly with exit 7, HTTP code 000, `CONNECT tunnel failed, response 502` and no sandbox violation, repeatable. |
| Further record | A further grant request, pint_3ga3atzqmy, appeared during the reruns and was resolved without orchestrator action. |
| Feedback | The orchestrator sent a Cloudroom feedback report about interaction records that stay pending after app decisions. |

Conclusion: phone denial is verified end to end. Phone approval is verified only as far as the permission gate, because the approved route failed at the egress proxy with a repeatable 502 and no approved request produced HTTP 200. Whether the phone approval itself or the CLI grant cleared the gate cannot be separated from this evidence. The stale-record behavior is a Cloudroom defect that blocks the next tool call after a decision.

## Hard limits

A search of `room-cli thread update`, `room-cli thread spawn` and settings help found no usage, cost, token or time limit flag. Only a reasoning level and a provider usage display exist. Recorded in the matrix as: no enforceable limit found in the installed CLI, so execution stays attended.

## Not tested

- Permission-layer handling of an out-of-worktree write. The hook denied it first.
- An approved network request that reaches its target. In Test 3 the approved route failed at the egress proxy with 502.
- Phone approval separated from the CLI grant. Both happened before the gate cleared in Test 3.

## Repository state recorded the same day

- PR 1 was made ready.
- The repository was made public.
- Branch protection on main requires one approving review, with admin enforcement and no force pushes.
- PR 1 cannot merge until a second identity approves or admin enforcement is lifted for the merge.
