# Jev pilot: one real decision

Date: 2026-10-21. Requested by the owner in Cloudroom thread thr_pwtuszetdh after the Codex review of commit e30f857. Scope: make Jev (TypeSafe AI) answer the question the capability matrix asks, "is it useful on a real decision", with one bounded run. No adapter, provider registry, or project dependency was added.

## Run record

| Item | Observed |
|---|---|
| Thread | thr_pwtuszetdh, provider claude-code, model claude-fable-5-1, Worktree environment on branch room/codex-review-smoke-test-commit-e30f857-etdh |
| Permission mode | Bypass permissions (Cloudroom `full`). Same caveat as the smoke test: nothing here shows a lower mode would block anything. |
| Deadline | None was set for this pilot. Recorded as a deviation from the deadline procedure, as in [06-enforcement-test.md](06-enforcement-test.md). |
| Limits | Single turn, attended by the owner. Two API calls planned, two made. Retry allowance two per failed operation; none needed. These limits do not substitute for the missing deadline. |
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

Correctness and spec match scored high. Blast radius scored as a tiny local change with full confidence. The escalation came from the test-gap rubric, which returned confidence 0. Interpretation, not an observed response: a Markdown-only change has no tests, the rubric appears unable to express "not applicable" with confidence, and a human would likely call that a false escalation.

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

The first row relates to the finding Codex raised as Medium severity, but the two responses differ. Codex identified a contradiction between the deadline procedure and the run record. Jev was given the claim "run record states a specific deadline" and returned `unsupported, leaning contradicted` at confidence 0.31, flagged for human review. Jev did not reach the Codex conclusion on its own; it evaluated a supplied claim and declined to assert a verdict. Interpretation: the low confidence is consistent with the subtlety of the finding, but that is a reading of the number, not something Jev stated. The other five rows match the Codex review and the document text.

## Cost

Reported pricing is $0.042 per million input tokens with free output, so the whole pilot cost about $0.0002. Billing was not checked against the TypeSafe console; this is a computed figure, not an observed charge.

## What this establishes

- Access works with the owner's key, and the published MCP server exposes twelve typed judgment tools.
- Latency is in the hundreds of milliseconds and cost is negligible for diff-sized inputs.
- On this decision, every claim Jev verified or contradicted with high confidence matched the Codex review and the document text. On the deadline claim it returned low confidence and flagged it for human review. Interpretation: that uncertainty looks justified, but the pilot did not test whether Jev would find the contradiction unprompted.

## What it does not establish

- Privacy: the diff and document text left the machine to TypeSafe. Acceptable for this public repository; a policy is needed before sending private code.
- Value on code: this was a documentation diff. Correctness and test-gap rubrics on real source changes are untested.
- Headless operation in Cloudroom: the global `jev` MCP entry still cannot connect from a non-interactive thread. A pilot with a plain environment variable from `room-cli secret request` works; a durable fix for the `op run` wrapper is not chosen yet.
- Any enforcement. Jev returns probabilities. It cannot block a merge, and the architecture keeps policy decisions with the owner.

## Recommendation

Keep Jev as a cheap second opinion on review handoffs, not as a gate. Next step if wanted: run `jev_review` on one real source-code commit and compare against the Codex finding list before deciding on a permanent MCP registration for Cloudroom threads. Laya stays deferred; it needs labelled decisions that do not exist yet.
