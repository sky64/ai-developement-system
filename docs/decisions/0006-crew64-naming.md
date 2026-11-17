# 0006: The harness is crew64; the agent identity is bot64

Date: 2026-11-17. Status: accepted by the owner in the Orca chat of 2026-11-17.

## Context

The owner wants brand development considered whenever they build something they use, and intends to open-source this harness. Until now it was named after its repository, `ai-developement-system`, with the plugin id `ai-dev-system`, the config file `.claude/ai-dev-system.json`, the environment prefix `AI_DEV_SYSTEM_FEATURE_`, and git keys under `aidev.*`. Nothing outside this repository depended on those names yet: no application repository had been re-enabled since decision 0005, so the rename costs one pull request now and would cost a migration later.

The owner has two brands. `sky64` is the builder, and the `64` suffix marks their tooling (Fill64, Oracle64, terminal64, woo64). Solvela is a company with a product, a licence, an org and a bot. A developer harness is tooling, so it carries the 64 mark; Solvela appears inside it as the first-class metering connector, not as its name.

## Decision

1. The harness is **crew64**: an orchestrator that never writes code, a crew of workers that never choose their own model, and a meter that counts every token. Repository `sky64/crew64` (renamed from `sky64/ai-developement-system`; GitHub redirects the old URL). Plugin id `crew64`, enabled as `crew64@crew64`; the orchestrator skill is `crew64:orchestrator`.
2. Names follow the plugin: per-repo config `.claude/crew64.json`; shipped defaults `config/crew64.defaults.json`; environment overrides `CREW64_FEATURE_<NAME>`; git keys `crew64.bot.name`, `crew64.bot.email`, `crew64.bot.tokenCommand`, `crew64.trustedRoot`; reader `tools/crew64_config.py`; enable script `tools/crew64-enable.sh`.
3. Connectors are named role then vendor: `crew64-platform-orca` (the only platform today), `crew64-gateway-solvela` and `crew64-gateway-openai-compatible` (the `gateway.kind` values), and the Orca side panel to come is `crew64-map`.
4. The agent identity becomes **bot64**: the owner renames the GitHub account `Solvela-bot` to `bot64`, and the Solvela org grants it the same write access. The installer takes the name as a flag, so nothing in the plugin changes for it.
5. Migration is automatic where a script already runs: `install-bot-identity.sh` writes the new git keys and removes `aidev.bot.*`; `crew64-enable.sh` renames an existing `.claude/ai-dev-system.json` to `.claude/crew64.json`, replaces the `ai-dev-system@ai-dev-system` plugin entry and marketplace with the crew64 ones, and carries any `aidev.trustedRoot` entries over to `crew64.trustedRoot`. The include-block markers and `orca-bot.gitconfig` keep their text, because changing them again would need another migration for no gain.
6. Historical records keep the old names: docs/00 to docs/04, docs/09, docs/10, decisions 0001 to 0003 and 2026-10-25, and the two plans of 2026-11-17 describe what they described. Decision 0005's file paths were updated because it is the live specification of the config.

## Consequences

- One rename pull request, reviewed like any risky-tier change. Plugin version 0.5.0.
- The owner's machines re-run the installer and re-enable their repositories once, with the final names.
- Anyone reading the repository meets one name throughout, and the connector names say where a vendor plugs in.
