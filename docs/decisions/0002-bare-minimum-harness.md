# 0002: Bare-minimum machine harness, add-ons per project

Date: 2026-10-24. Status: accepted by the owner in thread thr_tcveg9itrp.

## Context

The ECC plugin put about 47k tokens of always-on context into every session. Two documentation edits through the harness cost about eleven dollars. The owner builds applications and wants add-ons chosen per project, not loaded everywhere.

## Decision

1. The machine keeps only Claude Code, Codex, Cloudroom, and the project guard.
2. Each project vendors or enables what it needs. This repository vendors `git-workflow` and `coding-standards` under `.claude/skills/`, see [THIRD-PARTY.md](../../.claude/skills/THIRD-PARTY.md).
3. Implementers default to `claude-sonnet-5-5`. Fable or Opus is used for orchestration and architecture only.
4. The ECC env block is removed from `.claude/settings.json`; it superseded the hook settings from [decision 0001](0001-tiered-protocol.md).

## Consequences

- Sessions start with far less context and cost less.
- Skills are pinned to ECC 2.2.3 and do not update on their own.
- Agents here no longer use the `ecc:` skill prefix.

## Rollback

Reinstall the plugin at user scope from the `ecc` marketplace registration, restore the `env` block from decision 0001, and revert the agent skill names. Or enable the plugin at project scope for one project only.
