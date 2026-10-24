# 0001: Tier the delegation protocol by risk

Date: 2026-10-24. Status: accepted by the owner in thread thr_gjh7a4ifhu.

## Context

The first tasks through this harness were documentation edits. Each one cost two skill loads, a scope record, two GateGuard fact-forcing blocks, a Codex review, and a correction cycle. That overhead fits money-path code. It does not fit a fifteen-line doc change, and it will dominate throughput once an application exists.

The machine-wide copy of the ECC common rules told every agent to spawn subagents immediately and to run parallel Task calls. This project forbids that for anything that writes. The conflict was documented in [05-delegation.md](../05-delegation.md) but not removed.

## Decision

1. Three task tiers, defined in [05-delegation.md](../05-delegation.md). Trivial tasks get one implementer and no reviewer. Normal tasks get one implementer and one Codex review. Risky tasks get the full record and an attended run.
2. The ECC GateGuard fact-forcing hooks are disabled for this project through `ECC_DISABLED_HOOKS` in `.claude/settings.json`. The destructive-command checks stay on.
3. The machine-wide ECC rules copy at `~/.claude/rules/ecc/common` is removed. ECC skills and agents stay available on demand; only the always-loaded rules conflicted with project policy.
4. The next evidence the harness needs is a real application, not another setup document.

## Consequences

- Less ceremony for small work. The orchestrator still does not write unless the owner says so for a trivial task.
- The ECC `block-no-verify` Bash hook stays enabled.
- The hook disable is a setting change in this repository only. It takes effect in new sessions and has not been tested yet.
- Reverting is one commit plus re-copying the rules from the plugin cache.
