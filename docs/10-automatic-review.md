# Automatic Codex review: staged attended trial

Status on 2026-10-22: configuration and offline tests prepared. This change
does not activate a loop, install a secret, create a repository hook, or prove
a GitHub-to-Codex run. Owner approval and merge stay manual. Findings appear
only in Cloudroom; no GitHub review/comment/approval is posted.

## Smallest supported path

1. A trusted default-branch [Actions workflow](../.github/workflows/codex-review.yml)
   handles pull_request_target opened, reopened, ready_for_review, synchronize.
2. It accepts only open, non-draft, unmerged PRs authored by Solvela-bot, with
   head and base in sky64/ai-developement-system and base branch main.
   It checks current GitHub REST metadata again before sending, including exact
   event head/base SHAs. Missing/invalid metadata fails closed.
3. It POSTs six fields to the private Cloudroom webhook URL held in the
   CLOUDROOM_REVIEW_WEBHOOK Actions secret. No title, description, branch name,
   file, command, or URL from a PR is forwarded. No checkout or third-party
   action is used. The job has pull-requests:read only and a two-minute timeout.
4. Cloudroom starts a fresh Codex thread per webhook batch with the fixed
   [reviewer prompt](../tools/review/reviewer-prompt.txt). It revalidates public
   GitHub metadata anonymously, reviews immutable base/head content statically,
   rechecks freshness before its verdict, and reports only in its own thread.

The workflow runs trusted default-branch code under pull_request_target,
which has access to secrets; never add a checkout, PR script execution, or
PR text interpolated into a shell command. See GitHub's
[security guidance](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target)
and [event reference](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows).
The current [workflow execution protection guidance](https://github.blog/changelog/2026-09-17-workflow-execution-protections-in-github-actions-generally-available/)
also means event policy can prevent pull_request_target execution. Inspect the
actual run; absence of a run is not a successful skip. Do not change repository
permissions or policies automatically.

## Installed contract and limits

Read-only inspection used room-cli 0.43.1 automation help, the installed
automations skill and script-runtime reference, and the bundled automations
source map. Source paths below refer to that installed bundle, not this repo:

- src/cli.ts cloud create forwards enabled:!disabled, explicit new_thread, and
  provider/model/reasoning overrides. Thus --disabled stages a cloud loop
  without the create-then-pause race. Verify returned enabled:false.
- src/hooks.ts:17-26 formats each event as
  "--- webhook RECEIVED_AT · KIND" followed by the raw body. src/run.ts:87-90
  wraps the batch in webhook_events tags. The source comments call this the
  same format as cloud web/lib/hooks.ts; hosted implementation was not available
  for inspection. Delivery headers/IDs are not present in this surfaced format.
- The installed skill explicitly says cloud webhook loops take no script yet.
  Scheduled cloud script preflight exists, but that is not proof it works with
  webhooks. No unsupported --webhook --script combination is proposed.
- Therefore a direct repository webhook would start paid agent work before
  filtering. The Actions gate filters before POST instead. Anyone possessing
  the secret URL can still start paid work; payload checks inside the reviewer
  cannot prevent that initial cost.
- Installed script-runtime documents one active run per local automation,
  retry after 30/60 seconds and pause after three failures. The general skill
  says runs wait for previous completion. Cloud serialization, webhook retry,
  billing/runtime caps, and exactly-once delivery were not behaviorally verified;
  do not transfer the local guarantees to cloud.
- Actions concurrency cancels overlapping forwarding jobs for a PR. Cancellation
  can race an accepted POST and cannot stop a reviewer already launched. The
  stable request_key includes repository, PR, head, base. The prompt deduplicates
  within a batch only. There is no durable cross-run ledger or enforced
  cross-thread lock. Manual reruns/redelivery can duplicate reviews; compare
  keys in Loops Review before retrying.
- Each network operation has one attempt. The POST has a ten-second timeout and
  is never automatically retried. An ambiguous timeout is an unknown delivery,
  not permission to resend. GitHub metadata may change after the forwarding
  check; reviewer revalidation rejects stale requests.
- Prompt deadline is 15 minutes per review batch. There is no verified external
  runtime/spending cap, so this remains an attended trial, staged disabled
  until an operator is present. A prompt deadline is not enforcement.
- The parent observed workstation access true/full and copyLogins true. Cloud
  reviews can inherit owner credentials and workstation reachability. The prompt
  forbids their use, Mac tools, all writes, and candidate-code execution; these
  are conventions, not credential or OS boundaries. Anonymous API rate limits
  block the review instead of causing authenticated fallback. No shared setting
  is changed by this work.

## Operator setup after independent review

Use the reviewed commit's prompt and workflow. A cloud seed must already exist,
have this repository, and support Codex gpt-6.1-sol. Parent prepared
thr_886np4vmin as an infrastructure seed; readiness is not an end-to-end review.
Keep the seed prompt free of implementation/review history. Fresh-thread mode
is mandatory; do not use --same-thread.

The following is an operator procedure, not an activation performed by this
change. Installed source supports --disabled even though help omits it.
Run from the reviewed repository on the local coordinator. The example keeps
the create response in a private temporary file, passes the URL through stdin
to gh secret set, then runs the attended closed-PR receiver smoke test in the
same shell lifecycle. The recorded loop is paused in a finally block before
the EXIT trap deletes either private URL copy. Do not split these steps into
separate shell invocations. Run this whole block only when ready to attend the
temporary resume and smoke test. The URL is a bearer secret: never paste the
full response into chat or commit it.

```bash
set +x
set -eu
review_stage=$(mktemp -d)
chmod 700 "$review_stage"
trap 'rm -rf "$review_stage"' EXIT
room-cli automation create --cloud --thread thr_886np4vmin \
  --project proj_kndh2baf86 --name "Codex PR review (attended trial)" \
  --webhook --new-thread --disabled --provider codex \
  --model gpt-6.1-sol --reasoning high \
  --prompt "$(cat tools/review/reviewer-prompt.txt)" --json \
  > "$review_stage/loop.json"
python3 - "$review_stage/loop.json" "$review_stage/url" <<'PY'
import json
import sys
with open(sys.argv[1]) as stream:
    result = json.load(stream)
# Confirm the actual CLI result shape before using this procedure.
# The installed CLI returns the cloud automation record directly.
if result.get("enabled") is not False or result.get("new_thread") is not True:
    raise SystemExit("Unexpected loop mode; stop and inspect only redacted metadata")
url = result.get("url")
if not isinstance(url, str) or not url.startswith("https://"):
    raise SystemExit("No valid private webhook URL returned")
with open(sys.argv[2], "w") as stream:
    stream.write(url)
PY
gh secret set CLOUDROOM_REVIEW_WEBHOOK --repo sky64/ai-developement-system \
  < "$review_stage/url"
python3 - "$review_stage/loop.json" <<'PY'
import json
import sys
with open(sys.argv[1]) as stream:
    result = json.load(stream)
import subprocess
import urllib.request
import uuid

loop_id = str(uuid.UUID(result["id"]))
print("Staged cloud loop:", loop_id, "enabled:", result["enabled"],
      "new_thread:", result["new_thread"])

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

head = "bea714956be29d9f5af46471a3dc9c7c9a616f36"
base = "d343672f868ce13f5dd42cbea012532df0275626"
repo = "sky64/ai-developement-system"
payload = {"schema": 1, "repository": repo, "number": 3,
           "head": head, "base": base,
           "request_key": f"{repo}#3:{head}:{base}"}
failed = False
try:
    subprocess.run(["room-cli", "automation", "resume", loop_id],
                   check=True, capture_output=True)
    request = urllib.request.Request(
        result["url"], data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.build_opener(NoRedirect).open(request, timeout=10) as response:
        print("Receiver smoke POST HTTP:", response.status, "loop:", loop_id)
except Exception:
    failed = True
    print("Receiver smoke delivery uncertain/failed; inspect only redacted state. No retry.")
finally:
    # Always attempt pause, including an ambiguous resume or POST failure.
    paused = subprocess.run(["room-cli", "automation", "pause", loop_id],
                            capture_output=True)
    print("Loop pause confirmed:" if paused.returncode == 0 else
          "Loop pause FAILED; operator must pause recorded ID:", loop_id)
    failed = failed or paused.returncode != 0
if failed:
    raise SystemExit(1)
PY
```

Stop on failed or uncertain create; inspect redacted metadata before retrying,
so a timeout does not silently produce multiple loops. Record the nonsecret
loop ID in the task PR. Never use automation hook just to retrieve a URL:
it rotates the existing URL. If the API result shape differs, adjust only
after inspecting keys/nonsecret fields; do not print the full result.

The parent handles authorized staging and secret installation. Review of this
change must use a separate fresh Codex context with base/head and checks.
The owner must approve/merge before the trusted workflow is live on main.
A bot-created PR opened before that merge will not automatically retrigger;
use a later authorized supported event, such as reopening an eligible PR.

The same-shell procedure above temporarily resumes only the recorded loop,
POSTs one trusted minimal request for merged PR 3, then pauses it before private
file cleanup. Do not resend after an uncertain delivery or rotate the URL to
recover it. Expect an explicit closed/merged skip in a fresh thread, no review
or GitHub write. Inspect the resulting thread even though the loop is paused;
pause does not cancel a started run. Do not register a direct repository webhook.
This tests
the receiver/prompt, not the Actions trigger. Next exercise a new eligible bot
PR after workflow merge. Record Actions run, batch thread ID, request_key,
validated head/base, verdict, and proof of no comments/approval/merge. Those
live checks, cloud batching/serialization and actual deadline termination are
still untested here.

## Pause, retry, rollback

Pause with room-cli automation pause LOOP_ID first. Pausing does not prove an
already-started reviewer has stopped: inspect the task's run threads/queues
and stop only known reviewer IDs via room-cli thread stop THREAD_ID. Confirm
output and pending queues before resuming. Two repeated failures or duplicate
reviews are a stop condition; no unattended retry loop is authorized.

Disable the named GitHub workflow in Actions if forwarding must stop as well.
Pending GitHub runs need separate inspection/cancellation. Removing the named
Actions secret makes later forwarding fail without revealing its value.
Deleting the loop with room-cli automation delete LOOP_ID --yes removes that
loop; rotate a leaked URL with automation hook LOOP_ID only with authorized
secret replacement. Roll back repository changes through a reviewed revert.
No approval, merge, shared auth changes, or production changes are automated.

## Task evidence and verification

- Implementer: ECC loop-operator role, explicitly assigned to Codex after the
  original Claude session could not start; no other agents spawned.
- Base: c1da3f5d7f1b82265bab5dd8362ff66b50c78fb3.
- Ownership: .github/workflows/codex-review.yml, tools/review/*, this document,
  and minimal README/setup/matrix links. No dependencies added.
- Skills read: ecc:automation-audit-ops, ecc:github-ops, room-cli, automations;
  installed ECC loop-operator role read. All were available.
- Permission: explicitly authorized isolated local worktree, full access;
  no verified enforced filesystem or credential restriction.
- Runtime: attended implementation, deadline 2026-10-22T18:21:00Z. No verified
  external hard cap. At most two retries per failed operation and two
  correction/review cycles. No live loop/hook/secret activation in this task.
- On resumption: clean worktree at base, own message queue empty, no prior
  implementation commits or pending task processes/side effects found.
- Offline behavioral tests execute the exact inline workflow code with
  synthetic payloads and stubbed HTTP, without credentials or network:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/review -p 'test_*.py' -v
git diff --check
```

Tests cover allowed/ignored actions, ping, wrong repository/author/fork,
draft/closed/merged states, invalid IDs/SHAs, stale head/base, minimal POST,
redirect rejection, no POST for a merged PR 3 fixture, and no automatic POST
retry. They do not execute GitHub Actions or a cloud agent. Source security
scan passed with the expected generic GitHub workflow warning; the workflow
documents its trusted-code/no-checkout design. Independent review, live
GitHub-to-Cloudroom delivery, cost controls and security boundaries remain
separate checks, not inferred from these tests.
