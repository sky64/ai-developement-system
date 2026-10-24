# 0001: Tier the delegation protocol by risk

Date: 2026-10-24. Status: accepted by the owner in thread thr_gjh7a4ifhu.

## Context

The first tasks through this harness were documentation edits. Each one cost two skill loads, a scope record, two GateGuard fact-forcing blocks, a Codex review, and a correction cycle. That overhead fits money-path code. It does not fit a fifteen-line doc change, and it will dominate throughput once an application exists.

The machine-wide copy of the ECC common rules told every agent to spawn subagents immediately and to run parallel Task calls. This project forbids that for anything that writes. The conflict was documented in [05-delegation.md](../05-delegation.md) but not removed.

## Decision

1. Three task tiers, defined in [05-delegation.md](../05-delegation.md). Trivial tasks get one implementer and no reviewer. Normal tasks get one implementer and one Codex review. Risky tasks get the full record and an attended run. Risk decides the tier, not size: policy, AGENTS.md, `.claude/settings.json`, hooks, and other protection settings are always risky.
2. In `.claude/settings.json`, `ECC_DISABLED_HOOKS` disables only `pre:edit-write:gateguard-fact-force`, the Edit and Write fact prompt. `GATEGUARD_BASH_ROUTINE_DISABLED=1` suppresses the routine Bash fact prompt. The Bash hook `pre:bash:gateguard-fact-force` stays enabled because the same script runs the destructive-command check, which therefore stays on.
3. The machine-wide ECC rules copy at `~/.claude/rules/ecc/common` is removed. ECC skills and agents stay available on demand; only the always-loaded rules conflicted with project policy.
4. The next evidence the harness needs is a real application, not another setup document.

## Consequences

- Less ceremony for small work. The orchestrator still does not write, with one exception: a trivial task, when the owner says so in that turn, in a session running with `ORCHESTRATOR_GUARD=off`. Both conditions are required.
- The ECC `block-no-verify` Bash hook stays enabled.
- The hook disable is a setting change in this repository only. It takes effect in new sessions and has not been tested yet.
- Reverting is one commit plus re-copying the rules from the plugin cache.
