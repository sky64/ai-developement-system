# Jev pilot: one real decision

Date: 2026-10-21. Requested by the owner in Cloudroom thread thr_pwtuszetdh after the Codex review of commit e30f857. Scope: make Jev (TypeSafe AI) answer the question the capability matrix asks, "is it useful on a real decision", with one bounded run. No adapter, provider registry, or project dependency was added.

## Run record

| Item | Observed |
|---|---|
| Thread | thr_pwtuszetdh, provider claude-code, model claude-fable-5-1, Worktree environment on branch room/codex-review-smoke-test-commit-e30f857-etdh |
| Permission mode | Bypass permissions (Cloudroom `full`). Same caveat as the smoke test: nothing here shows a lower mode would block anything. |
| Deadline and limits | Single turn, attended by the owner. Two API calls planned, two made. Retry allowance two per failed operation; none needed. |
| Credential | `TYPESAFE_API_KEY` requested through `room-cli secret request` and written to the thread's storage directory outside the repository. The value was never printed or read back. |
| Client path | The published `@jkudish/jev-mcp` server (0.14.5) driven over MCP stdio by a throwaway script in `/tmp`. This is the same server registered in the owner's global Claude config, which failed to connect in this thread because its `op run` wrapper needs an interactive 1Password unlock. |
| Model reported | `jev-1.13.0`, provider `typesafe` |

## Decision tested

The same diff Codex reviewed (base 29f0051, head e30f857, `docs/04-smoke-test.md` only), with the acceptance criteria as the request text.

### jev_review

| Measure | Value |
|---|---|
| Latency | 293 ms |
| Usage | 2,231 input tokens, 79 output tokens |
| Action | `escalate` |
| Composite | 0.852 (floor 0.7) |
| safe_to_apply | 0.64 |
| Limiting rubric | `test_gap`, confidence 0 |

Correctness and spec match scored high. Blast radius scored as a tiny local change with full confidence. The escalation came from the test-gap rubric, where the model had no opinion: a Markdown-only change has no tests, and the rubric cannot express "not applicable" with confidence. A human would call that a false escalation.

### jev_verify

Six claims checked against the full text of `docs/04-smoke-test.md`. Latency 120 ms, 3,214 input tokens, 376 output tokens.

| Claim | Verdict | Confidence |
|---|---|---|
| Run record states a specific deadline | unsupported, leaning contradicted | 0.31, flagged for review |
| Run record states the permission mode | verified | 1.00 |
| Run record states the retry allowance | verified | 1.00 |
| Document claims the test proves a permission mode blocks actions | contradicted | 0.98 |
| Document claims the reviewer is independent in the security sense | contradicted | 1.00 |
| Document lists the instruction files loaded | verified | 1.00 |

The first row is the finding Codex raised as Medium severity. Jev reached the same conclusion but with low confidence, so under its own thresholds it would hand that claim to a human rather than assert it. The other five rows match the Codex review and the document exactly.

## Cost

Reported pricing is $0.042 per million input tokens with free output, so the whole pilot cost about $0.0002. Billing was not checked against the TypeSafe console; this is a computed figure, not an observed charge.

## What this establishes

- Access works with the owner's key, and the published MCP server exposes twelve typed judgment tools.
- Latency is in the hundreds of milliseconds and cost is negligible for diff-sized inputs.
- On this decision Jev agreed with the Codex review on every claim it was confident about, and it was correctly unconfident on the one subtle finding.

## What it does not establish

- Privacy: the diff and document text left the machine to TypeSafe. Acceptable for this public repository; a policy is needed before sending private code.
- Value on code: this was a documentation diff. Correctness and test-gap rubrics on real source changes are untested.
- Headless operation in Cloudroom: the global `jev` MCP entry still cannot connect from a non-interactive thread. A pilot with a plain environment variable from `room-cli secret request` works; a durable fix for the `op run` wrapper is not chosen yet.
- Any enforcement. Jev returns probabilities. It cannot block a merge, and the architecture keeps policy decisions with the owner.

## Recommendation

Keep Jev as a cheap second opinion on review handoffs, not as a gate. Next step if wanted: run `jev_review` on one real source-code commit and compare against the Codex finding list before deciding on a permanent MCP registration for Cloudroom threads. Laya stays deferred; it needs labelled decisions that do not exist yet.
